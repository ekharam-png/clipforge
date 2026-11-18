// Putting a downloaded, checked update in place on a computer.
//
// Windows and macOS work the same way (decision, 1.12):
//   1. the new app is unpacked into a folder NEXT TO the installed one
//      (`<install>.update-new`), so the final step is a rename on the same
//      disk;
//   2. a small script (assets/update/clipforge-update.ps1 / .sh) is
//      started detached; the app closes;
//   3. the script waits for the app to be gone, renames
//      `<install>` -> `<install>.update-old` and `<install>.update-new`
//      -> `<install>`, starts the app and deletes the old folder. A rename
//      happens completely or not at all; when either rename fails the old
//      app is back in place and is started again. The outcome is written
//      to a result file that the app reads on its next start.
// Projects and media live in Documents/ClipForge and are never touched.
//
// When the place the app is installed in cannot be written (Program Files,
// a read-only disk image, macOS "app translocation" for an app that was
// started straight from Downloads) nothing is attempted: Windows opens the
// download page, macOS shows the unpacked new app in Finder.
//
// Pure Dart (dart:io, dart:isolate).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'update_info.dart';

const String kUpdateNewSuffix = '.update-new';
const String kUpdateOldSuffix = '.update-old';
const String kUpdateResultFile = 'update-result.json';

/// Where the running app is installed: the folder with clipforge.exe
/// (Windows), the ClipForge.app bundle (macOS), else null.
String? installDirOf(String resolvedExecutable, String os) {
  switch (os) {
    case 'windows':
      return p.windows.dirname(resolvedExecutable);
    case 'macos':
      // <X>.app/Contents/MacOS/<program>
      final macOs = p.posix.dirname(resolvedExecutable);
      final contents = p.posix.dirname(macOs);
      final bundle = p.posix.dirname(contents);
      if (p.posix.basename(macOs) == 'MacOS' &&
          p.posix.basename(contents) == 'Contents' &&
          bundle.toLowerCase().endsWith('.app')) {
        return bundle;
      }
      return null;
  }
  return null;
}

/// macOS runs an app that was downloaded and never moved from a random
/// read-only copy ("app translocation"); its real place is unknown then.
bool isTranslocated(String path) => path.contains('/AppTranslocation/');

/// Whether a folder can be created and removed in [dir].
bool canWriteIn(String dir) {
  try {
    final probe = Directory(p.join(dir, '.clipforge-write-test-$pid'));
    probe.createSync();
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Null when the app at [installDir] can be replaced in place, else why
/// not (for the log; the user gets plan B).
String? replaceInPlaceProblem(String? installDir, String os) {
  if (installDir == null) return 'the place the app runs from is not known';
  if (os == 'macos' && isTranslocated(installDir)) {
    return 'macOS runs this copy from a temporary place (it was opened '
        'straight from the download)';
  }
  if (!Directory(installDir).existsSync()) return 'the app folder was not found';
  if (!canWriteIn(p.dirname(installDir))) {
    return 'the folder that holds ClipForge cannot be changed '
        '(${p.dirname(installDir)})';
  }
  if (os == 'windows' && !canWriteIn(installDir)) {
    return 'the ClipForge folder cannot be changed ($installDir)';
  }
  return null;
}

/// Removes `<install>.update-new` / `.update-old` left by an earlier
/// update (the app calls this at start). Best effort.
void cleanUpdateLeftovers(String installDir) {
  for (final suffix in const [kUpdateNewSuffix, kUpdateOldSuffix]) {
    final d = Directory('$installDir$suffix');
    try {
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// What the swap script reported.
class UpdateResult {
  const UpdateResult(this.status, this.message, this.version);

  /// "updated", "failed" (nothing changed) or "broken".
  final String status;
  final String message;
  final String version;
  bool get updated => status == 'updated';
}

/// Reads and deletes the result file an update left in [dir]; null when
/// there is none.
UpdateResult? takeUpdateResult(String dir) {
  final file = File(p.join(dir, kUpdateResultFile));
  try {
    if (!file.existsSync()) return null;
    var text = file.readAsStringSync();
    file.deleteSync();
    if (text.startsWith('﻿')) text = text.substring(1);
    final json = jsonDecode(text);
    if (json is! Map) return null;
    return UpdateResult('${json['status'] ?? ''}', '${json['message'] ?? ''}',
        '${json['version'] ?? ''}');
  } catch (_) {
    return null;
  }
}

/// Unpacks the Windows zip at [zipPath] next to [installDir] and returns
/// the folder with the new app (`<installDir>.update-new`). The zip holds
/// one top folder with clipforge.exe in it. Throws an [UpdateException]
/// when it is not that.
Future<String> stageWindowsUpdate(String zipPath, String installDir,
    {String exeName = 'clipforge.exe'}) async {
  final newDir = '$installDir$kUpdateNewSuffix';
  final tmp = '$installDir.update-unpack';
  for (final d in [newDir, tmp]) {
    if (Directory(d).existsSync()) Directory(d).deleteSync(recursive: true);
  }
  try {
    // Unpacking 100+ MB: off the main thread so the window keeps drawing.
    await Isolate.run(() => extractFileToDisk(zipPath, tmp));
    String? found;
    if (File(p.join(tmp, exeName)).existsSync()) {
      found = tmp;
    } else {
      for (final d in Directory(tmp).listSync().whereType<Directory>()) {
        if (File(p.join(d.path, exeName)).existsSync()) {
          found = d.path;
          break;
        }
      }
    }
    if (found == null) {
      throw UpdateException(
          'The update was downloaded, but ClipForge was not found in it. '
          'Nothing was changed; use the download page instead.',
          kind: 'check',
          detail: 'no $exeName in the zip');
    }
    Directory(found).renameSync(newDir);
    return newDir;
  } on UpdateException {
    rethrow;
  } catch (e) {
    throw UpdateException(
        'The update could not be unpacked next to ClipForge. Nothing was '
        'changed; use the download page instead.',
        detail: '$e');
  } finally {
    try {
      if (Directory(tmp).existsSync()) Directory(tmp).deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Unpacks the macOS zip at [zipPath] into [intoDir] with `ditto` (it keeps
/// the links inside the app intact, which a plain unzip would not) and
/// returns the path of the .app in it. [unzip] replaces ditto in tests.
Future<String> unpackMacUpdate(String zipPath, String intoDir,
    {Future<ProcessResult> Function(String zip, String dir)? unzip}) async {
  final dir = Directory(intoDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final r = await (unzip ??
      (z, d) => Process.run('/usr/bin/ditto', ['-x', '-k', z, d]))(zipPath, intoDir);
  if (r.exitCode != 0) {
    throw UpdateException(
        'The update could not be unpacked. Nothing was changed; use the '
        'download page instead.',
        detail: 'ditto: ${r.stderr}');
  }
  final apps = [
    for (final d in dir.listSync().whereType<Directory>())
      if (d.path.toLowerCase().endsWith('.app')) d.path,
  ];
  if (apps.isEmpty) {
    throw UpdateException(
        'The update was downloaded, but ClipForge was not found in it. '
        'Nothing was changed; use the download page instead.',
        kind: 'check',
        detail: 'no .app in the zip');
  }
  // Files this app wrote are not quarantined, so macOS does not ask
  // again; removing the mark is a precaution and may fail harmlessly.
  try {
    await Process.run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', apps.first]);
  } catch (_) {}
  return apps.first;
}

/// Unpacks the macOS zip next to the installed app and returns the new
/// bundle (`<installDir>.update-new`).
Future<String> stageMacUpdate(String zipPath, String installDir,
    {Future<ProcessResult> Function(String zip, String dir)? unzip}) async {
  final newDir = '$installDir$kUpdateNewSuffix';
  final tmp = '$installDir.update-unpack';
  if (Directory(newDir).existsSync()) Directory(newDir).deleteSync(recursive: true);
  try {
    final app = await unpackMacUpdate(zipPath, tmp, unzip: unzip);
    Directory(app).renameSync(newDir);
    return newDir;
  } finally {
    try {
      if (Directory(tmp).existsSync()) Directory(tmp).deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// The command that runs the swap script for [os] ("windows" / "macos").
/// [scriptPath] must be OUTSIDE the install folder.
({String executable, List<String> arguments}) swapCommand({
  required String os,
  required String scriptPath,
  required String installDir,
  required String newDir,
  required int waitPid,
  required String resultFile,
  required String version,
  String exeName = 'clipforge.exe',
}) {
  if (os == 'windows') {
    return (
      executable: 'powershell.exe',
      arguments: [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', //
        '-WindowStyle', 'Hidden', '-File', scriptPath,
        '-InstallDir', installDir, '-NewDir', newDir, '-WaitPid', '$waitPid',
        '-ExeName', exeName, '-ResultFile', resultFile, '-Version', version,
      ],
    );
  }
  return (
    executable: '/bin/sh',
    arguments: [scriptPath, installDir, newDir, '$waitPid', resultFile, version],
  );
}

/// Writes [scriptText] to [workDir] and starts it detached (it outlives
/// this app). The app must close right after this returns.
Future<void> startSwap({
  required String os,
  required String scriptText,
  required String workDir,
  required String installDir,
  required String newDir,
  required String resultFile,
  required String version,
  String exeName = 'clipforge.exe',
}) async {
  await Directory(workDir).create(recursive: true);
  final script = File(p.join(
      workDir, os == 'windows' ? 'clipforge-update.ps1' : 'clipforge-update.sh'));
  await script.writeAsString(scriptText, flush: true);
  final cmd = swapCommand(
    os: os,
    scriptPath: script.path,
    installDir: installDir,
    newDir: newDir,
    waitPid: pid,
    resultFile: resultFile,
    version: version,
    exeName: exeName,
  );
  // The working folder must not be inside the app (it would lock it).
  await Process.start(cmd.executable, cmd.arguments,
      workingDirectory: workDir, mode: ProcessStartMode.detached);
}
