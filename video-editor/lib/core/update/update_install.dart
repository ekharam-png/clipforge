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

/// The MARKER that says "this folder was made by ClipForge's updater".
/// Only a folder with its marker is ever deleted (1.14): a folder a user
/// happened to call "ClipForge.update-old" is left alone.
///
/// Windows: a small file INSIDE the folder (it travels with the folder
/// through the swap). macOS: a file NEXT TO the app bundle
/// (`<bundle>.update-new.marker`), because a file added inside a signed
/// .app would break its seal.
const String kUpdateMarkerName = '.clipforge-update-marker';

String updateMarkerPath(String folder, String os) =>
    os == 'windows' ? p.join(folder, kUpdateMarkerName) : '$folder.marker';

/// Marks [folder] as made by the updater. Best effort.
void writeUpdateMarker(String folder, String os, {String version = ''}) {
  try {
    File(updateMarkerPath(folder, os)).writeAsStringSync(
        jsonEncode({'by': 'ClipForge updater', 'version': version}),
        flush: true);
  } catch (_) {}
}

bool hasUpdateMarker(String folder, String os) {
  try {
    return File(updateMarkerPath(folder, os)).existsSync();
  } catch (_) {
    return false;
  }
}

/// What [cleanUpdateLeftovers] found next to the app.
class LeftoverReport {
  const LeftoverReport(this.removed, this.kept, this.foreign);

  /// Folders of the updater that were deleted.
  final List<String> removed;

  /// Folders of the updater that are still there (asked to keep, or a file
  /// in them is in use).
  final List<String> kept;

  /// Folders with such a name that the updater did NOT make (no marker):
  /// never touched.
  final List<String> foreign;
}

/// Removes `<install>.update-new` / `.update-old` left by an earlier
/// update (the app calls this at start) - ONLY folders that carry the
/// updater's marker, and not those in [keep] (an update that is still
/// waiting to be finished). Best effort.
LeftoverReport cleanUpdateLeftovers(String installDir, String os,
    {Set<String> keep = const {}}) {
  final removed = <String>[], kept = <String>[], foreign = <String>[];
  for (final suffix in const [kUpdateNewSuffix, kUpdateOldSuffix, '.update-unpack']) {
    final path = '$installDir$suffix';
    final d = Directory(path);
    final marker = File(updateMarkerPath(path, os));
    try {
      if (!d.existsSync()) {
        // A marker whose folder is gone (macOS keeps it outside).
        if (os != 'windows' && marker.existsSync()) marker.deleteSync();
        continue;
      }
      if (!hasUpdateMarker(path, os)) {
        foreign.add(path);
        continue;
      }
      if (keep.contains(path)) {
        kept.add(path);
        continue;
      }
      d.deleteSync(recursive: true);
      if (os != 'windows' && marker.existsSync()) marker.deleteSync();
      removed.add(path);
    } catch (_) {
      kept.add(path);
    }
  }
  return LeftoverReport(removed, kept, foreign);
}

/// An update that was downloaded, checked and unpacked next to the app
/// and is waiting for the swap (`update-pending.json` in the state
/// folder). It lets the app finish the update at its next start when the
/// user chose "Later", and notice a swap that was started but never
/// reported back.
class PendingUpdate {
  const PendingUpdate({
    required this.version,
    required this.build,
    required this.installDir,
    required this.newDir,
    this.swapStartedAt,
    this.attempts = 0,
  });
  final String version;
  final int build;
  final String installDir;
  final String newDir;

  /// When the swap script was last started; null: never.
  final DateTime? swapStartedAt;

  /// How often the swap was started.
  final int attempts;

  PendingUpdate started(DateTime at) => PendingUpdate(
      version: version,
      build: build,
      installDir: installDir,
      newDir: newDir,
      swapStartedAt: at,
      attempts: attempts + 1);

  static const String fileName = 'update-pending.json';

  void write(String stateDir) {
    Directory(stateDir).createSync(recursive: true);
    File(p.join(stateDir, fileName)).writeAsStringSync(
        jsonEncode({
          'version': version,
          'build': build,
          'installDir': installDir,
          'newDir': newDir,
          'swapStartedAt': swapStartedAt?.toUtc().toIso8601String(),
          'attempts': attempts,
        }),
        flush: true);
  }

  static PendingUpdate? read(String stateDir) {
    try {
      final f = File(p.join(stateDir, fileName));
      if (!f.existsSync()) return null;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map) return null;
      final dir = j['installDir'], next = j['newDir'];
      if (dir is! String || next is! String) return null;
      return PendingUpdate(
        version: '${j['version'] ?? ''}',
        build: (j['build'] as num?)?.toInt() ?? 0,
        installDir: dir,
        newDir: next,
        swapStartedAt: j['swapStartedAt'] == null
            ? null
            : DateTime.tryParse('${j['swapStartedAt']}'),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static void clear(String stateDir) {
    try {
      final f = File(p.join(stateDir, fileName));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// What the app does about updates when it starts.
enum UpdateStartAction {
  /// Nothing is waiting: remove stale leftovers.
  tidy,

  /// The swap ran and worked: say "Updated to …", remove leftovers.
  reportUpdated,

  /// The swap ran and reported a failure: say why, offer Try again.
  reportFailed,

  /// The swap was started and never reported back (the script was blocked
  /// or stopped): say so, offer Try again.
  reportUnfinished,

  /// An update is unpacked and waiting ("Later" was chosen, or the app
  /// was closed another way): finish it now.
  applyNow,
}

/// Decides [UpdateStartAction] from what is on disk: the swap script's
/// [result] (already taken), the [pending] record, this app's
/// [currentBuild], whether this start is from the folder the update was
/// prepared for ([sameInstall]) and whether the unpacked update is still
/// there and carries the marker ([stagedReady]).
UpdateStartAction decideUpdateAtStart({
  required UpdateResult? result,
  required PendingUpdate? pending,
  required int? currentBuild,
  required bool sameInstall,
  required bool stagedReady,
}) {
  if (result != null) {
    return result.updated
        ? UpdateStartAction.reportUpdated
        : UpdateStartAction.reportFailed;
  }
  if (pending == null || !sameInstall) return UpdateStartAction.tidy;
  // The new version runs although nothing was reported (the result file
  // could not be written).
  if (currentBuild != null && currentBuild >= pending.build) {
    return UpdateStartAction.reportUpdated;
  }
  if (!stagedReady) return UpdateStartAction.tidy;
  if (pending.swapStartedAt != null) return UpdateStartAction.reportUnfinished;
  return UpdateStartAction.applyNow;
}

/// One sentence for someone whose ClipForge folder is named after an
/// OLDER version (they unzipped "ClipForge-1.12.0" and it now holds
/// [version]); null when the name says nothing wrong. The folder is never
/// renamed by the app: shortcuts point at it.
String? folderNameNote(String installDir, String version, String os) {
  var name = os == 'windows'
      ? p.windows.basename(installDir)
      : p.posix.basename(installDir);
  if (os == 'macos') {
    // The app bundle is always ClipForge.app; look at its folder.
    name = p.posix.basename(p.posix.dirname(installDir));
  }
  final found = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(name);
  if (found == null || found.group(0) == version) return null;
  return 'The folder is still called "$name": that is only its name, the '
      'app inside is $version. You can rename it to "ClipForge" while '
      'ClipForge is closed (shortcuts to it then need making again).';
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
    if (!Directory(d).existsSync()) continue;
    // Never a folder the updater did not make.
    if (d == newDir && !hasUpdateMarker(d, 'windows')) {
      throw UpdateException(
          'There is already a folder called "${p.windows.basename(d)}" next '
          'to ClipForge that ClipForge did not make. Move or rename it, '
          'then try again.',
          detail: 'no marker in $d');
    }
    Directory(d).deleteSync(recursive: true);
  }
  // The unpack folder is ours from its first moment.
  Directory(tmp).createSync(recursive: true);
  writeUpdateMarker(tmp, 'windows');
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
    writeUpdateMarker(newDir, 'windows');
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
  if (Directory(newDir).existsSync()) {
    if (!hasUpdateMarker(newDir, 'macos')) {
      throw UpdateException(
          'There is already something called "${p.posix.basename(newDir)}" '
          'next to ClipForge that ClipForge did not make. Move or rename '
          'it, then try again.',
          detail: 'no marker for $newDir');
    }
    Directory(newDir).deleteSync(recursive: true);
  }
  try {
    final app = await unpackMacUpdate(zipPath, tmp, unzip: unzip);
    Directory(app).renameSync(newDir);
    writeUpdateMarker(newDir, 'macos');
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
