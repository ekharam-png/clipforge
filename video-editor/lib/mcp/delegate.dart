// Hand-over to the current version of the helper.
//
// Claude is pointed at ONE copy of clipforge-mcp for good: the stable path
// in the per-user folder, or the copy inside the Claude Desktop extension.
// The app installs each new version next to it and records it in
// `current.json` (lib/core/claude/helper_install.dart). Whatever copy is
// started reads that file first and, when it names a different program
// that is at least as new, starts that one with the same arguments and the
// same standard input / output, and waits for it. So an app update reaches
// Claude with the next start of the helper, without reinstalling anything.
//
// Not handed over: the internal worker modes (--export-job, ...), --help /
// --version, running from source (`dart bin/clipforge_mcp.dart`), a copy
// that was itself started by a hand-over, and when CLIPFORGE_MCP_NO_HANDOVER
// is set (tests, CI). Pure Dart.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/build_info.dart';
import '../core/claude/helper_install.dart';

/// Set (to anything) to always run the program that was started.
const String kEnvNoHandOver = 'CLIPFORGE_MCP_NO_HANDOVER';

/// Set by a hand-over for the program it starts: the path of the copy
/// that Claude started.
const String kEnvStartedBy = 'CLIPFORGE_MCP_STARTED_BY';

String _real(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } catch (_) {
    return p.normalize(p.absolute(path));
  }
}

bool _samePath(String a, String b, String os) {
  final x = _real(a), y = _real(b);
  return os == 'windows' ? x.toLowerCase() == y.toLowerCase() : x == y;
}

/// This program's build number (0 when unknown).
int ownBuildNumber([BuildInfo? info]) =>
    int.tryParse((info ?? BuildInfo.current).buildNumber ?? '') ?? 0;

/// The program to hand over to, or null to run this one.
HelperCurrent? chooseHandOver({
  required String selfPath,
  required int ownBuild,
  required Map<String, String> env,
  required String os,
}) {
  if ((env[kEnvNoHandOver] ?? '').isNotEmpty) return null;
  if ((env[kEnvStartedBy] ?? '').isNotEmpty) return null;
  // From source: `dart <script>`.
  if (p.basenameWithoutExtension(selfPath).toLowerCase() == 'dart') return null;
  final dir = claudeStableDir(os, env);
  if (dir == null) return null;
  final current = HelperCurrent.read(dir);
  if (current == null || current.build < ownBuild) return null;
  if (!File(current.path).existsSync()) return null;
  if (_samePath(current.path, selfPath, os)) return null;
  return current;
}

/// Starts [target] with [args] on this program's standard input / output
/// and returns its exit code; null when it could not be started (the
/// caller then runs itself).
Future<int?> runHandedOver(HelperCurrent target, List<String> args,
    {required String selfPath, void Function(String)? log}) async {
  final Process child;
  try {
    child = await Process.start(target.path, args,
        mode: ProcessStartMode.inheritStdio,
        environment: {kEnvStartedBy: selfPath});
  } catch (e) {
    log?.call('could not start the current helper ${target.path} ($e); '
        'running this copy instead');
    return null;
  }
  final subs = <StreamSubscription<ProcessSignal>>[];
  try {
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      subs.add(signal.watch().listen((s) => child.kill(s)));
    }
  } catch (_) {}
  final code = await child.exitCode;
  for (final s in subs) {
    await s.cancel();
  }
  return code;
}

/// Which helper is running and where, for get_status.
Map<String, dynamic> helperReport({Map<String, String>? environment, String? os}) {
  final env = environment ?? Platform.environment;
  final system = os ?? Platform.operatingSystem;
  final exe = Platform.resolvedExecutable;
  final startedBy = env[kEnvStartedBy];
  final dir = claudeStableDir(system, env);
  final current = dir == null ? null : HelperCurrent.read(dir);
  final stable = dir == null ? null : p.join(dir, helperExeName(system));
  return {
    'program': exe,
    'version': BuildInfo.current.versionLabel,
    'startedThrough':
        startedBy == null || startedBy.isEmpty ? null : startedBy,
    'stableFolder': dir,
    'stablePath': stable,
    'stablePathInstalled': stable != null && File(stable).existsSync(),
    'installedByApp': current == null
        ? null
        : {
            'version': current.version,
            'build': current.build,
            'path': current.path,
            'installedAt': current.installedAt?.toUtc().toIso8601String(),
          },
    'isCurrent':
        current != null && _samePath(current.path, exe, system),
  };
}

/// [helperReport] as two or three lines of text.
String helperReportText(Map<String, dynamic> r) {
  final out = StringBuffer(
      'Helper: ${r['program']} (${r['version']})');
  if (r['startedThrough'] != null) {
    out.write(', started through ${r['startedThrough']}');
  }
  final installed = r['installedByApp'] as Map?;
  if (r['stableFolder'] == null) {
    out.write('\nHelper folder: not available on this system.');
  } else if (installed == null) {
    out.write('\nHelper folder: ${r['stableFolder']} - the ClipForge app '
        'has not installed a helper there yet (it does when it starts, '
        'from version 1.12 on), so this copy does not update with the app.');
  } else {
    out.write('\nHelper folder: ${r['stableFolder']} - the app installed '
        '${installed['version']} (build ${installed['build']})'
        '${r['isCurrent'] == true ? '; this is it' : '; this copy is a different one (restart Claude to get the installed one)'}.');
  }
  return out.toString();
}
