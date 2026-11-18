// "This project is open in the app": a small lock file in the project's
// folder, written by the app while a project is open in the editor and
// read by the Claude control server (lib/mcp), which refuses to edit a
// project that is open (the app autosaves its own copy and would overwrite
// the edits). Pure Dart.
//
// File: `<project folder>/.open-in-app`, JSON:
//   {"pid": 1234, "host": "LAPTOP", "app": "ClipForge 1.9.0 (build 1) · …",
//    "openedAt": "...Z", "heartbeatAt": "...Z", "token": "..."}
// The app rewrites heartbeatAt every [kLockHeartbeat] and deletes the file
// when the project is closed. A lock is STALE (ignored, and replaced) when
// its heartbeat is older than [kLockStaleAfter], or when it was written on
// this computer by a process that no longer runs (the app crashed or was
// killed). Nothing is deleted by readers; the app removes stale locks it
// finds (see [removeStaleLocks]).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Name of the lock file inside a project's folder.
const String kAppLockFileName = '.open-in-app';

/// How often the app renews its lock.
const Duration kLockHeartbeat = Duration(minutes: 1);

/// A lock whose heartbeat is older than this is ignored (the app renews it
/// every minute; a sleeping computer does not, so this is generous).
const Duration kLockStaleAfter = Duration(minutes: 3);

/// Contents of a lock file.
class ProjectLockInfo {
  const ProjectLockInfo({
    required this.pid,
    required this.host,
    required this.openedAt,
    required this.heartbeatAt,
    this.app = '',
    this.token = '',
  });

  final int pid;
  final String host;

  /// Version line of the app that holds it.
  final String app;
  final DateTime openedAt;
  final DateTime heartbeatAt;

  /// Random per opening, so an editor only ever deletes its own lock.
  final String token;

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'host': host,
        'app': app,
        'openedAt': openedAt.toUtc().toIso8601String(),
        'heartbeatAt': heartbeatAt.toUtc().toIso8601String(),
        'token': token,
      };

  static ProjectLockInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final pid = json['pid'];
    final opened = DateTime.tryParse('${json['openedAt']}');
    final beat = DateTime.tryParse('${json['heartbeatAt']}');
    if (pid is! num || opened == null || beat == null) return null;
    return ProjectLockInfo(
      pid: pid.toInt(),
      host: '${json['host'] ?? ''}',
      app: '${json['app'] ?? ''}',
      openedAt: opened,
      heartbeatAt: beat,
      token: '${json['token'] ?? ''}',
    );
  }
}

/// What [checkProjectLock] found.
enum ProjectLockState {
  /// No lock file (or an unreadable one).
  none,

  /// Open in the app right now.
  held,

  /// A leftover (crash, killed app, old heartbeat): treated as not open.
  stale,
}

class LockCheck {
  const LockCheck(this.state, [this.info, this.reason]);
  final ProjectLockState state;
  final ProjectLockInfo? info;

  /// Why a lock counts as stale.
  final String? reason;

  bool get isHeld => state == ProjectLockState.held;
}

/// This computer's name as written into locks.
String localHostName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return '';
  }
}

/// True when a process with [pid] runs on this computer. When that cannot
/// be found out, true (the heartbeat still makes an old lock stale).
Future<bool> processAlive(int pid) async {
  if (pid <= 0) return false;
  if (pid == currentPid) return true;
  try {
    if (Platform.isLinux || Platform.isAndroid) {
      return Directory('/proc/$pid').existsSync();
    }
    if (Platform.isWindows) {
      final r = await Process.run(
          'tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
      if (r.exitCode != 0) return true;
      return '${r.stdout}'.contains('"$pid"');
    }
    final r = await Process.run('kill', ['-0', '$pid']);
    if (r.exitCode == 0) return true;
    // Someone else's process: it exists, we may only not signal it.
    return '${r.stderr}'.toLowerCase().contains('not permitted');
  } catch (_) {
    return true;
  }
}

/// The pid of this program (a getter so tests can tell it apart).
int get currentPid => pid;

File lockFileOf(String projectDir) => File(p.join(projectDir, kAppLockFileName));

/// Reads the lock of the project in [projectDir] and decides whether it is
/// held. [isAlive] and [hostName] can be replaced in tests.
Future<LockCheck> checkProjectLock(
  String projectDir, {
  DateTime? now,
  Future<bool> Function(int pid)? isAlive,
  String? hostName,
}) async {
  final file = lockFileOf(projectDir);
  String text;
  try {
    if (!file.existsSync()) return const LockCheck(ProjectLockState.none);
    text = await file.readAsString();
  } catch (_) {
    return const LockCheck(ProjectLockState.none);
  }
  ProjectLockInfo? info;
  try {
    info = ProjectLockInfo.fromJson(jsonDecode(text));
  } catch (_) {
    info = null;
  }
  if (info == null) {
    return const LockCheck(ProjectLockState.stale, null, 'the lock file is unreadable');
  }
  final at = now ?? DateTime.now();
  final age = at.difference(info.heartbeatAt);
  if (age > kLockStaleAfter) {
    return LockCheck(ProjectLockState.stale, info,
        'its heartbeat is ${age.inMinutes} minutes old');
  }
  final here = hostName ?? localHostName();
  if (info.host == here && !(await (isAlive ?? processAlive)(info.pid))) {
    return LockCheck(ProjectLockState.stale, info,
        'the app that wrote it (process ${info.pid}) is no longer running');
  }
  return LockCheck(ProjectLockState.held, info);
}

/// Deletes the stale locks under [rootPath] (one folder per project).
/// Returns how many were removed. Locks that are held are kept.
Future<int> removeStaleLocks(String rootPath,
    {Future<bool> Function(int pid)? isAlive}) async {
  var removed = 0;
  final root = Directory(rootPath);
  try {
    if (!root.existsSync()) return 0;
    for (final entry in root.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final check = await checkProjectLock(entry.path, isAlive: isAlive);
      if (check.state == ProjectLockState.stale) {
        try {
          lockFileOf(entry.path).deleteSync();
          removed++;
        } catch (_) {}
      }
    }
  } catch (_) {}
  return removed;
}

/// The app's lock on one open project: [acquire] writes it and keeps it
/// fresh, [release] removes it (only if it is still this one).
class AppProjectLock {
  AppProjectLock(this.projectDir, {this.app = '', Duration? heartbeat})
      : heartbeat = heartbeat ?? kLockHeartbeat;

  final String projectDir;
  final String app;
  final Duration heartbeat;
  final String _token =
      List.generate(16, (_) => Random().nextInt(16).toRadixString(16)).join();
  DateTime? _openedAt;
  Timer? _timer;
  bool _released = false;

  String get token => _token;

  /// The locks this app process holds now. The app shows one editor at a
  /// time, so a new lock ends every other one: whatever happened to the
  /// editor that held it (1.9 left the mark, and its heartbeat, on the
  /// first project of a session when that editor's clean-up did not get
  /// as far as the lock), the mark is always on the project that is open.
  static final Set<AppProjectLock> _held = {};

  /// True between [acquire] and [release].
  bool get isHeld => _held.contains(this);

  /// Writes the lock (replacing a leftover one) and starts the heartbeat.
  /// Any other lock of this app is released first. Failures are ignored:
  /// the lock is a safety net, not a requirement. Synchronous (a tiny
  /// file), so it also works inside widget tests.
  void acquire() {
    for (final other in _held.toList()) {
      if (!identical(other, this)) other.release();
    }
    _held.add(this);
    _released = false;
    _openedAt = DateTime.now();
    _write();
    _timer?.cancel();
    _timer = Timer.periodic(heartbeat, (_) => _write());
  }

  void _write() {
    if (_released) return;
    final now = DateTime.now();
    final info = ProjectLockInfo(
      pid: currentPid,
      host: localHostName(),
      app: app,
      openedAt: _openedAt ?? now,
      heartbeatAt: now,
      token: _token,
    );
    try {
      final dir = Directory(projectDir);
      if (!dir.existsSync()) return;
      final file = lockFileOf(projectDir);
      final tmp = File('${file.path}.$currentPid.tmp');
      tmp.writeAsStringSync(jsonEncode(info.toJson()), flush: true);
      tmp.renameSync(file.path);
    } catch (_) {}
  }

  /// Stops the heartbeat and deletes the lock when it is still ours.
  void release() {
    _released = true;
    _held.remove(this);
    _timer?.cancel();
    _timer = null;
    try {
      final file = lockFileOf(projectDir);
      if (!file.existsSync()) return;
      final info = ProjectLockInfo.fromJson(jsonDecode(file.readAsStringSync()));
      if (info == null || info.token == _token) file.deleteSync();
    } catch (_) {}
  }
}
