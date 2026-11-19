// Putting a downloaded, checked update in place on a computer.
//
// Windows and macOS work the same way (decision, 1.12):
//   1. the new app is unpacked into a folder NEXT TO the installed one
//      (`<install>.update-new`);
//   2. a small script (assets/update/clipforge-update.ps1 / .cmd / .sh)
//      is started outside the app's process tree; the app waits until the
//      script has written its first line into the update log, then closes;
//   3. the script waits for the app to be gone and puts the new version
//      in place. macOS: by renaming the two bundles. Windows (1.14.1): by
//      replacing the CONTENTS of the folder (safety copy to
//      `<install>.update-old`, robocopy /MIR of the new files, a check,
//      the safety copy mirrored back on failure) - the folder itself is
//      never renamed, because on real PCs something always seemed to hold
//      it (an Explorer window, a terminal, a scanner) and the 1.12 - 1.14
//      rename then never happened. The outcome is written to a result
//      file that the app reads on its next start, and every step to
//      update-log.txt (update_log.dart).
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
import 'update_log.dart';

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
  const UpdateResult(this.status, this.message, this.version, {this.mode = 'update'});

  /// "update", or "move" for a tidy-up (tidy_up.dart).
  final String mode;
  bool get wasMove => mode == 'move';

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
    // (the cmd script may write a path in the system's own encoding)
    var text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    file.deleteSync();
    if (text.startsWith('﻿')) text = text.substring(1);
    final json = jsonDecode(text);
    if (json is! Map) return null;
    return UpdateResult('${json['status'] ?? ''}', '${json['message'] ?? ''}',
        '${json['version'] ?? ''}',
        mode: json['mode'] == 'move' ? 'move' : 'update');
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
    // A scanner may still be reading the fresh files: a few tries.
    for (var attempt = 0;; attempt++) {
      try {
        Directory(found).renameSync(newDir);
        break;
      } on FileSystemException {
        if (attempt >= 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
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

/// The version file inside a Windows app folder (1.14.1), written by the
/// build (windows/CMakeLists.txt): `{"version":"1.14.1+123"}`. The swap
/// scripts compare it after copying; the app reads it to tell which
/// version a ClipForge folder holds.
const String kVersionFileName = 'clipforge-version.json';
String versionFilePath(String installDir) =>
    p.join(installDir, 'data', kVersionFileName);

/// A version with its build number: "1.14.1+123" (the build may be
/// missing).
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build]);
  final int major, minor, patch;
  final int? build;

  /// "1.14.1+123", "1.14.1", "1.14.1.123"; null when [text] is not one.
  static AppVersion? parse(String? text) {
    final m = RegExp(r'^\s*(\d+)\.(\d+)\.(\d+)(?:[+.](\d+))?')
        .firstMatch(text ?? '');
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
        m[4] == null ? null : int.parse(m[4]!));
  }

  /// The version first; the build number only decides between two builds
  /// of the same version (and only when both are known).
  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    if (build == null || other.build == null) return 0;
    return build!.compareTo(other.build!);
  }

  bool isOlderThan(AppVersion other) => compareTo(other) < 0;

  /// "1.14.1" (what people know it as).
  String get name => '$major.$minor.$patch';

  @override
  String toString() => build == null ? name : '$name+$build';
}

/// The "ProductVersion" text in the version details of a Windows program
/// (what Explorer shows under Properties > Details), read straight from
/// the file's bytes; null when there is none. ClipForge's is
/// "version+build" ("1.12.0+109").
String? productVersionOfExe(List<int> bytes) {
  // UTF-16LE "ProductVersion", then zeros up to the value, then the value.
  final key = [for (final c in 'ProductVersion'.codeUnits) ...[c, 0]];
  outer:
  for (var i = 0; i + key.length + 4 <= bytes.length; i += 2) {
    // (resource strings are word aligned, but the section need not be)
    for (final start in [i, i + 1]) {
      if (start + key.length + 4 > bytes.length) continue;
      var same = true;
      for (var k = 0; k < key.length; k++) {
        if (bytes[start + k] != key[k]) {
          same = false;
          break;
        }
      }
      if (!same) continue;
      var at = start + key.length;
      while (at + 1 < bytes.length && bytes[at] == 0 && bytes[at + 1] == 0) {
        at += 2;
      }
      final out = StringBuffer();
      while (at + 1 < bytes.length && out.length < 64) {
        final unit = bytes[at] | (bytes[at + 1] << 8);
        if (unit == 0) break;
        out.writeCharCode(unit);
        at += 2;
      }
      if (out.isEmpty) continue outer;
      return out.toString();
    }
  }
  return null;
}

/// Which ClipForge the folder [dir] holds: from its version file, else
/// from the program's version details. Null when [dir] has no
/// [exeName] or no version can be read - then nothing is known about it.
AppVersion? readInstalledVersion(String dir, {String exeName = 'clipforge.exe'}) {
  try {
    final exe = File(p.join(dir, exeName));
    if (!exe.existsSync()) return null;
    final file = File(versionFilePath(dir));
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync());
      final v = json is Map ? AppVersion.parse('${json['version']}') : null;
      if (v != null) return v;
    }
    // The runner is small (well under a megabyte); anything huge is not it.
    if (exe.lengthSync() > 64 * 1024 * 1024) return null;
    return AppVersion.parse(productVersionOfExe(exe.readAsBytesSync()));
  } catch (_) {
    return null;
  }
}

/// The values the Windows scripts read from the environment (no path is
/// ever quoted on a command line). ALL of them are always set, so that a
/// value left over from an earlier run can never be picked up.
Map<String, String> swapEnvironment({
  required String installDir,
  required String newDir,
  required int waitPid,
  required String resultFile,
  required String logFile,
  required String version,
  required String token,
  required String scriptPath,
  required String workDir,
  String exeName = 'clipforge.exe',
  String mode = 'update',
  String removeListFile = '',
}) =>
    {
      'CF_UPD_INSTALL': installDir,
      'CF_UPD_NEW': newDir,
      'CF_UPD_PID': '$waitPid',
      'CF_UPD_EXE': exeName,
      'CF_UPD_RESULT': resultFile,
      'CF_UPD_LOG': logFile,
      'CF_UPD_VERSION': version,
      'CF_UPD_TOKEN': token,
      'CF_UPD_MODE': mode,
      'CF_UPD_REMOVE_LIST': removeListFile,
      'CF_UPD_SCRIPT': scriptPath,
      'CF_UPD_WORKDIR': workDir,
    };

/// Windows: the PowerShell command that starts the update script OUTSIDE
/// this app's process tree, the way 1.12 starts export workers
/// (lib/mcp/export_jobs.dart): a short-lived PowerShell runs
/// `Start-Process -WindowStyle Hidden` and exits, so the script's parent
/// is gone before the app closes. The script gets its own hidden console
/// and inherits the environment ([swapEnvironment]).
const String kWindowsSwapStartScript = r"$q = [char]34; "
    r"$a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', "
    r"'-WindowStyle', 'Hidden', '-File', ($q + $env:CF_UPD_SCRIPT + $q)); "
    r"$p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a "
    r"-WorkingDirectory $env:CF_UPD_WORKDIR -WindowStyle Hidden -PassThru; "
    r"[Console]::Out.Write($p.Id)";

/// The file names the scripts are written under in the work folder.
const String kSwapScriptPs = 'clipforge-update.ps1';
const String kSwapScriptCmd = 'clipforge-update.cmd';
const String kSwapScriptSh = 'clipforge-update.sh';

/// One way of starting the swap script; [start] returns a note for the log.
class SwapLauncher {
  const SwapLauncher(this.name, this.start);

  /// "PowerShell", "cmd", "sh".
  final String name;
  final Future<String> Function() start;
}

/// How [startSwap] went.
class SwapStart {
  const SwapStart({required this.confirmed, required this.method, required this.logFile});

  /// The script wrote its first line into the log: it is running and
  /// waiting for the app to close. When false the app must NOT close.
  final bool confirmed;

  /// The launcher that worked ("PowerShell", "cmd", "sh"); "" when none.
  final String method;
  final String logFile;
}

/// The ways to start the script on [os], best first. Windows: PowerShell
/// (outside the process tree), then plain cmd for PCs where PowerShell is
/// blocked. Others: /bin/sh, detached.
List<SwapLauncher> swapLaunchers({
  required String os,
  required String workDir,
  required Map<String, String> environment,
  required List<String> shArguments,
  bool withCmd = true,
}) {
  if (os == 'windows') {
    return [
      SwapLauncher('PowerShell', () async {
        final r = await Process.run(
          'powershell.exe',
          [
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', //
            '-WindowStyle', 'Hidden', '-Command', kWindowsSwapStartScript,
          ],
          environment: environment,
          workingDirectory: workDir,
        ).timeout(const Duration(seconds: 30));
        final err = '${r.stderr}'.trim();
        return 'exit code ${r.exitCode}, script process id "${'${r.stdout}'.trim()}"'
            '${err.isEmpty ? '' : ', said: ${err.length > 300 ? err.substring(0, 300) : err}'}';
      }),
      if (withCmd)
        SwapLauncher('cmd', () async {
          // No spaces and no quotes on this command line: the script is
          // named relative to the work folder, everything else comes from
          // the environment. "start" gives it its own (minimised) window
          // and the cmd that ran "start" ends at once.
          final proc = await Process.start(
            'cmd.exe',
            ['/d', '/c', 'start', '/min', 'cmd.exe', '/d', '/c', kSwapScriptCmd],
            environment: environment,
            workingDirectory: workDir,
          );
          proc.stdout.drain<void>().ignore();
          proc.stderr.drain<void>().ignore();
          proc.stdin.close().ignore();
          final code = await proc.exitCode.timeout(const Duration(seconds: 15));
          return 'exit code $code';
        }),
    ];
  }
  return [
    SwapLauncher('sh', () async {
      final proc = await Process.start('/bin/sh', shArguments,
          workingDirectory: workDir,
          environment: environment,
          mode: ProcessStartMode.detached);
      return 'process id ${proc.pid}';
    }),
  ];
}

/// Waits until a script has written "started token=[token]" into [log].
Future<bool> waitForSwapStarted(UpdateLog log, String token,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final until = DateTime.now().add(timeout);
  while (true) {
    if (log.hasStarted(token)) return true;
    if (DateTime.now().isAfter(until)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// Writes the scripts to [workDir] (never inside the app folder: that
/// would lock it) and starts one so that it outlives this app. Each way in
/// [launchers] (default: [swapLaunchers]) is tried until a script has
/// CONFIRMED that it runs, by its first line in [logFile]. The app closes
/// only when the answer says [SwapStart.confirmed].
///
/// [mode] "move" and [removeListFile] are for the tidy-up (tidy_up.dart).
Future<SwapStart> startSwap({
  required String os,
  required String scriptText,
  required String workDir,
  required String installDir,
  required String newDir,
  required String resultFile,
  required String logFile,
  required String version,
  String exeName = 'clipforge.exe',
  String? fallbackScriptText,
  String mode = 'update',
  String removeListFile = '',
  List<SwapLauncher>? launchers,
  Duration confirmTimeout = const Duration(seconds: 15),
}) async {
  final log = UpdateLog(logFile);
  await Directory(workDir).create(recursive: true);
  final windows = os == 'windows';
  // cmd needs CRLF line ends (labels are not found reliably otherwise);
  // PowerShell does not mind them.
  String crlf(String text) => text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  final script = File(p.join(workDir, windows ? kSwapScriptPs : kSwapScriptSh));
  await script.writeAsString(windows ? crlf(scriptText) : scriptText, flush: true);
  if (windows && fallbackScriptText != null) {
    await File(p.join(workDir, kSwapScriptCmd))
        .writeAsString(crlf(fallbackScriptText), flush: true);
  }
  // A stale result must not be read as this run's.
  try {
    final old = File(resultFile);
    if (old.existsSync()) old.deleteSync();
  } catch (_) {}
  // The scripts' "only one of us" folders of earlier runs.
  try {
    for (final d in Directory(p.dirname(resultFile)).listSync().whereType<Directory>()) {
      if (d.path.endsWith('.lock')) d.deleteSync(recursive: true);
    }
  } catch (_) {}
  final token = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  final environment = windows
      ? swapEnvironment(
          installDir: installDir,
          newDir: newDir,
          waitPid: pid,
          resultFile: resultFile,
          logFile: logFile,
          version: version,
          token: token,
          scriptPath: script.path,
          workDir: workDir,
          exeName: exeName,
          mode: mode,
          removeListFile: removeListFile)
      : {'CLIPFORGE_UPDATE_LOG': logFile, 'CLIPFORGE_UPDATE_TOKEN': token};
  log.add('swap: mode=$mode version=$version install=[$installDir] '
      'new=[$newDir] app pid=$pid work folder=[$workDir] token=$token');
  final ways = launchers ??
      swapLaunchers(
          os: os,
          workDir: workDir,
          environment: environment,
          shArguments: [script.path, installDir, newDir, '$pid', resultFile, version],
          withCmd: fallbackScriptText != null);
  for (final way in ways) {
    try {
      final note = await way.start();
      log.add('start by ${way.name}: $note');
    } catch (e) {
      log.add('start by ${way.name} failed: $e');
      continue;
    }
    if (await waitForSwapStarted(log, token, timeout: confirmTimeout)) {
      log.add('the script is running (started by ${way.name})');
      return SwapStart(confirmed: true, method: way.name, logFile: logFile);
    }
    log.add('the script did not report in within '
        '${confirmTimeout.inSeconds} s (started by ${way.name})');
  }
  log.add('no script could be started: the app stays open, nothing was changed');
  return SwapStart(confirmed: false, method: '', logFile: logFile);
}
