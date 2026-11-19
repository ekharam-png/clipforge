// "Is the helper in use?" (1.14): while a Claude session has this helper
// open it keeps one small file in the per-user helper folder
// (`<ClipForge>/claude/in-use/<pid>.json`: process id, version, what the
// Claude program called itself in the handshake, when it started and when
// a tool was last used). The app's Connect page reads these files. The
// file is removed when the helper ends; one left by a crash is stale (its
// process is gone) and the app deletes it. Nothing else is written, and
// nothing about what Claude does. Pure Dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/claude/connect.dart';
import '../core/claude/helper_install.dart';

class HelperHeartbeat {
  HelperHeartbeat(this.dir, {required this.version, DateTime Function()? now, int? processId})
      : _now = now ?? DateTime.now,
        _pid = processId ?? pid;

  /// The helper's per-user folder; null: nothing is written.
  final String? dir;
  final String version;
  final DateTime Function() _now;
  final int _pid;
  DateTime? _started;
  DateTime? _written;
  String _client = '';

  /// The heartbeat of the helper folder of this user.
  /// (Not under tests and CI checks, which set CLIPFORGE_MCP_NO_HANDOVER:
  /// they must not write into the real user's folder.)
  factory HelperHeartbeat.forThisUser(String version) => HelperHeartbeat(
      Platform.environment['CLIPFORGE_MCP_NO_HANDOVER'] == '1'
          ? null
          : claudeStableDir(Platform.operatingSystem, Platform.environment),
      version: version);

  File? get _file =>
      dir == null ? null : File(p.join(dir!, kInUseFolder, '$_pid.json'));

  void _write(DateTime lastCall) {
    final f = _file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(HelperSession(
              pid: _pid,
              version: version,
              client: _client,
              startedAt: _started ?? lastCall,
              lastCallAt: lastCall)
          .toJson()));
      _written = lastCall;
    } catch (_) {
      // Never in the way of the tools.
    }
  }

  /// The handshake: a Claude program has this helper open.
  void opened(String client) {
    _client = client;
    _started = _now();
    _write(_started!);
  }

  /// A tool was called (written at most every 5 seconds).
  void used() {
    if (_started == null) return;
    final now = _now();
    if (_written != null && now.difference(_written!).inSeconds < 5) return;
    _write(now);
  }

  /// The helper ends.
  void closed() {
    try {
      final f = _file;
      if (f != null && f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
