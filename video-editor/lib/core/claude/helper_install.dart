// The Claude helper (clipforge-mcp) at a place that never changes.
//
// Before 1.12 the Claude Desktop extension carried its own copy of the
// helper, so every app update meant installing the extension again. Now
// the desktop app puts the helper it was shipped with into one fixed
// per-user folder on every start (and so after every update), and Claude
// is pointed at that folder once:
//
//   Windows: %LOCALAPPDATA%\ClipForge\claude\
//   macOS:   ~/Library/Application Support/ClipForge/claude/
//   Linux:   ~/.local/share/ClipForge/claude/   (development builds)
//
//   <folder>/clipforge-mcp(.exe)        the STABLE path (Claude Code, manual
//                                       config); a copy of the helper that
//                                       hands over to the current version
//   <folder>/current.json               which version is current, and where
//   <folder>/versions/<key>/clipforge-mcp(.exe), fonts/, CLAUDE.md
//
// Why versioned folders plus a hand-over (decision): on Windows a running
// program file cannot be overwritten or deleted, and Claude keeps the
// helper running. A new version therefore always goes into a NEW folder
// (nothing is in use there), and `current.json` is switched to it with one
// rename. Whatever copy of the helper Claude starts next - the stable
// path, or the copy inside the Claude Desktop extension - reads
// `current.json` first and starts the current version instead of itself
// (lib/mcp/delegate.dart). The stable-path copy is refreshed too when it
// can be (rename the old file out of the way, which Windows allows for a
// running program, then copy), but nothing depends on that succeeding.
//
// Pure Dart (dart:io); used by the app (install) and the helper (hand-over,
// get_status).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const String kHelperCurrentFile = 'current.json';

/// "clipforge-mcp.exe" on Windows, else "clipforge-mcp".
String helperExeName(String os) =>
    os == 'windows' ? 'clipforge-mcp.exe' : 'clipforge-mcp';

/// The fixed per-user folder of the Claude helper on [os], or null when it
/// cannot be worked out (no home folder; phones).
String? claudeStableDir(String os, Map<String, String> env) {
  String? nonEmpty(String? v) => v == null || v.trim().isEmpty ? null : v;
  switch (os) {
    case 'windows':
      final local = nonEmpty(env['LOCALAPPDATA']) ??
          (nonEmpty(env['USERPROFILE']) == null
              ? null
              : p.windows.join(env['USERPROFILE']!, 'AppData', 'Local'));
      return local == null ? null : p.windows.join(local, 'ClipForge', 'claude');
    case 'macos':
      final home = nonEmpty(env['HOME']);
      return home == null
          ? null
          : p.posix.join(home, 'Library', 'Application Support', 'ClipForge', 'claude');
    case 'linux':
      final data = nonEmpty(env['XDG_DATA_HOME']) ??
          (nonEmpty(env['HOME']) == null
              ? null
              : p.posix.join(env['HOME']!, '.local', 'share'));
      return data == null ? null : p.posix.join(data, 'ClipForge', 'claude');
  }
  return null;
}

/// What `current.json` says.
class HelperCurrent {
  const HelperCurrent({
    required this.version,
    required this.build,
    required this.path,
    this.display = '',
    this.bundleSha = '',
    this.installedAt,
  });

  /// e.g. "1.12.0".
  final String version;

  /// The build number (0 when unknown).
  final int build;

  /// Full path of the current helper program.
  final String path;

  /// The app's version line, e.g. "ClipForge 1.12.0 (build 142) · ...".
  final String display;

  /// SHA-256 of the bundle it was unpacked from.
  final String bundleSha;
  final DateTime? installedAt;

  Map<String, Object?> toJson() => {
        'version': version,
        'build': build,
        'path': path,
        'display': display,
        'bundleSha': bundleSha,
        'installedAt': installedAt?.toUtc().toIso8601String(),
      };

  /// Reads `<stableDir>/current.json`; null when missing or unreadable.
  static HelperCurrent? read(String stableDir) {
    try {
      final file = File(p.join(stableDir, kHelperCurrentFile));
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map || json['path'] is! String) return null;
      final build = json['build'];
      return HelperCurrent(
        version: '${json['version'] ?? ''}',
        build: build is num ? build.toInt() : int.tryParse('$build') ?? 0,
        path: json['path'] as String,
        display: '${json['display'] ?? ''}',
        bundleSha: '${json['bundleSha'] ?? ''}',
        installedAt: DateTime.tryParse('${json['installedAt'] ?? ''}'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What [installClaudeHelper] did.
class HelperInstallResult {
  const HelperInstallResult({
    required this.stableDir,
    required this.launcherPath,
    required this.currentPath,
    required this.changed,
    required this.launcherRefreshed,
    this.notes = const [],
  });
  final String stableDir;

  /// The stable path to give to Claude.
  final String launcherPath;

  /// The program of the current version.
  final String currentPath;

  /// True when a new version was put in place by this call.
  final bool changed;

  /// False when the stable-path copy could not be replaced (in use); it
  /// still hands over to the current version.
  final bool launcherRefreshed;
  final List<String> notes;
}

/// Whether [stableDir] holds a usable helper (for the "Connect to Claude"
/// page).
({bool installed, HelperCurrent? current, String launcherPath}) helperStatus(
    String stableDir, String os) {
  final launcher = p.join(stableDir, helperExeName(os));
  final current = HelperCurrent.read(stableDir);
  final ok = current != null &&
      File(current.path).existsSync() &&
      File(launcher).existsSync();
  return (installed: ok, current: current, launcherPath: launcher);
}

void _makeExecutable(String path) {
  if (Platform.isWindows) return;
  try {
    Process.runSync('chmod', ['755', path]);
  } catch (_) {}
}

/// Puts the helper from [bundleBytes] (the Claude Desktop extension file
/// the app carries: a zip with `server/clipforge-mcp(.exe)`,
/// `server/fonts/...`) into [stableDir] and makes it current. Does nothing
/// when that exact bundle is already current. Never throws for a file in
/// use; throws a [FileSystemException] / [FormatException] only when the
/// new version itself cannot be unpacked (the old one then stays current).
Future<HelperInstallResult> installClaudeHelper({
  required String stableDir,
  required List<int> bundleBytes,
  required String version,
  required int build,
  required String os,
  String display = '',
  DateTime? now,
}) async {
  final exe = helperExeName(os);
  final launcher = p.join(stableDir, exe);
  final sha = sha256.convert(bundleBytes).toString();
  final notes = <String>[];
  final before = HelperCurrent.read(stableDir);
  var changed = false;
  var currentPath = before?.path ?? '';

  if (before == null ||
      before.bundleSha != sha ||
      !File(before.path).existsSync()) {
    final key = '${version.replaceAll(RegExp(r'[^0-9A-Za-z.]'), '_')}-b$build-'
        '${sha.substring(0, 8)}';
    final versions = Directory(p.join(stableDir, 'versions'));
    final target = Directory(p.join(versions.path, key));
    currentPath = p.join(target.path, exe);
    if (!File(currentPath).existsSync()) {
      // Unpacked next to its final place, then renamed: a half-written
      // version is never seen.
      final stage = Directory('${target.path}.tmp-$pid');
      if (stage.existsSync()) stage.deleteSync(recursive: true);
      stage.createSync(recursive: true);
      try {
        final archive = ZipDecoder().decodeBytes(bundleBytes);
        var found = false;
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final name = entry.name.replaceAll('\\', '/');
          if (!name.startsWith('server/')) continue;
          final relative = name.substring('server/'.length);
          if (relative.isEmpty ||
              relative.split('/').any((s) => s == '..' || s.isEmpty)) {
            continue;
          }
          final out = File(p.joinAll([stage.path, ...relative.split('/')]));
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(entry.content as List<int>, flush: true);
          if (relative == exe) found = true;
        }
        if (!found) {
          throw FormatException('The extension file holds no server/$exe');
        }
        _makeExecutable(p.join(stage.path, exe));
        if (target.existsSync()) target.deleteSync(recursive: true);
        stage.renameSync(target.path);
      } catch (_) {
        try {
          stage.deleteSync(recursive: true);
        } catch (_) {}
        rethrow;
      }
    }
    final current = HelperCurrent(
      version: version,
      build: build,
      path: currentPath,
      display: display,
      bundleSha: sha,
      installedAt: now ?? DateTime.now(),
    );
    final file = File(p.join(stableDir, kHelperCurrentFile));
    final temp = File('${file.path}.tmp-$pid');
    temp.writeAsStringSync(jsonEncode(current.toJson()), flush: true);
    temp.renameSync(file.path);
    changed = true;
  }

  // The stable-path copy. In use (Windows) -> rename it away, then copy.
  var refreshed = true;
  final source = File(currentPath);
  final existing = File(launcher);
  bool same() {
    if (!existing.existsSync()) return false;
    if (existing.lengthSync() != source.lengthSync()) return false;
    return sha256.convert(existing.readAsBytesSync()) ==
        sha256.convert(source.readAsBytesSync());
  }

  if (source.existsSync() && !same()) {
    String? aside;
    try {
      if (existing.existsSync()) {
        aside = p.join(stableDir,
            '${p.basenameWithoutExtension(exe)}.old-${DateTime.now().microsecondsSinceEpoch}${p.extension(exe)}');
        existing.renameSync(aside);
      }
      source.copySync(launcher);
      _makeExecutable(launcher);
    } catch (e) {
      refreshed = false;
      notes.add('The helper at the stable path is in use and was not replaced '
          '($e); it starts the current version anyway.');
      // Put the old one back if the copy failed after the rename.
      try {
        if (aside != null && !File(launcher).existsSync()) {
          File(aside).renameSync(launcher);
        }
      } catch (_) {}
    }
  }

  // Tidy up: copies renamed away earlier and versions that are not current.
  // Anything still in use simply stays until a later start.
  try {
    for (final f in Directory(stableDir).listSync(followLinks: false)) {
      final name = p.basename(f.path);
      if (f is File &&
          (name.startsWith('clipforge-mcp.old-') || name.contains('.tmp-'))) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    final versions = Directory(p.join(stableDir, 'versions'));
    if (versions.existsSync()) {
      // The version that was current until now may still be running in
      // Claude (it needs its fonts): it goes one update later.
      final keep = [
        p.dirname(currentPath),
        if (before != null) p.dirname(before.path),
      ];
      for (final d in versions.listSync(followLinks: false)) {
        if (d is! Directory || keep.any((k) => p.equals(d.path, k))) continue;
        // The program first: when it is in use (Windows) the folder stays
        // whole.
        final old = File(p.join(d.path, exe));
        if (old.existsSync()) {
          try {
            old.deleteSync();
          } catch (_) {
            continue;
          }
        }
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}

  return HelperInstallResult(
    stableDir: stableDir,
    launcherPath: launcher,
    currentPath: currentPath,
    changed: changed,
    launcherRefreshed: refreshed,
    notes: notes,
  );
}

/// The one line that connects Claude Code to the helper at [launcherPath].
String claudeCodeCommand(String launcherPath) =>
    'claude mcp add --scope user clipforge -- "$launcherPath"';
