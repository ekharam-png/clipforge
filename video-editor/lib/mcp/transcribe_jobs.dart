// Speech-to-text as a background job, on the pattern of export_jobs.dart:
// `transcribe` starts a JOB and answers at once (an MCP client gives up on
// a call after about a minute; a 30-minute talk takes much longer),
// `get_transcribe_status` reports on it, `cancel_transcribe` stops it.
//
//  * every job is a JSON file in `<ClipForge>/claude-jobs/transcribe/`
//    (its own folder: the export job list reads every .json next to it);
//  * the work runs in a separate process (this program started again with
//    `--transcribe-job <file>`), which writes progress and a heartbeat
//    every second and looks for a cancel request (<id>.cancel);
//  * each finished transcript is saved in the project's `transcripts`
//    folder straight away, so a job that is stopped half way keeps what it
//    had done, and a second run skips those files.
// Pure Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/build_info.dart';
import '../core/storage/project_lock.dart' show processAlive, localHostName;
import '../core/transcript/transcript_store.dart';
import '../media/transcribe/transcription_service.dart';
import 'export_jobs.dart'
    show
        kJobCancelled,
        startWorkerProcess,
        kJobFailed,
        kJobFinished,
        kJobHeartbeat,
        kJobKeepFor,
        kJobLost,
        kJobLostAfter,
        kJobRunning,
        kJobStarting,
        selfCommand;

/// One sound of a job.
class TranscribeItem {
  TranscribeItem({
    required this.path,
    required this.audioTrack,
    required this.speaker,
    required this.durationMs,
    this.state = 'pending',
    this.words = 0,
    this.language = '',
    this.wordTiming = '',
    this.error,
  });
  final String path;
  final int audioTrack;
  final String speaker;
  final int durationMs;

  /// pending, running, done, cached (already there), failed.
  String state;
  int words;
  String language;
  String wordTiming;
  String? error;

  Map<String, dynamic> toJson() => {
        'path': path,
        'audioTrack': audioTrack,
        'speaker': speaker,
        'durationMs': durationMs,
        'state': state,
        'words': words,
        'language': language,
        'wordTiming': wordTiming,
        'error': ?error,
      };

  factory TranscribeItem.fromJson(Map<String, dynamic> j) => TranscribeItem(
        path: '${j['path']}',
        audioTrack: (j['audioTrack'] as num?)?.toInt() ?? 0,
        speaker: '${j['speaker'] ?? ''}',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        state: '${j['state'] ?? 'pending'}',
        words: (j['words'] as num?)?.toInt() ?? 0,
        language: '${j['language'] ?? ''}',
        wordTiming: '${j['wordTiming'] ?? ''}',
        error: j['error'] as String?,
      );
}

class TranscribeJobRecord {
  TranscribeJobRecord({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.projectDir,
    required this.rootDir,
    required this.language,
    required this.quality,
    required this.backend,
    required this.force,
    required this.downloadPack,
    required this.createdAt,
    required this.items,
    this.status = kJobStarting,
    this.progress = 0,
    this.message = '',
    this.startedAt,
    this.heartbeatAt,
    this.finishedAt,
    this.host = '',
    this.workerPid,
    this.runner = '',
    this.backendUsed = '',
    this.error,
    this.errorKind,
  });
  final String id;
  final String projectId;
  final String projectName;

  /// The project's folder (its transcripts go in `transcripts/`).
  final String projectDir;

  /// The ClipForge folder (packs are in `models/`).
  final String rootDir;
  final String language;
  final String quality;
  final String backend;
  final bool force;
  final bool downloadPack;
  final DateTime createdAt;
  final List<TranscribeItem> items;
  String status;
  double progress;

  /// What it is doing now ("Downloading the pack ...", "Listening ...").
  String message;
  DateTime? startedAt;
  DateTime? heartbeatAt;
  DateTime? finishedAt;
  String host;
  int? workerPid;
  String runner;
  String backendUsed;
  String? error;
  String? errorKind;

  bool get isActive => status == kJobStarting || status == kJobRunning;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'projectDir': projectDir,
        'rootDir': rootDir,
        'language': language,
        'quality': quality,
        'backend': backend,
        'force': force,
        'downloadPack': downloadPack,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'status': status,
        'progress': progress,
        'message': message,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'heartbeatAt': heartbeatAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'host': host,
        'workerPid': workerPid,
        'runner': runner,
        'backendUsed': backendUsed,
        'error': error,
        'errorKind': errorKind,
      };

  static DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v');

  factory TranscribeJobRecord.fromJson(Map<String, dynamic> j) =>
      TranscribeJobRecord(
        id: j['id'] as String,
        projectId: '${j['projectId']}',
        projectName: '${j['projectName']}',
        projectDir: '${j['projectDir']}',
        rootDir: '${j['rootDir']}',
        language: '${j['language'] ?? 'auto'}',
        quality: '${j['quality'] ?? 'auto'}',
        backend: '${j['backend'] ?? 'auto'}',
        force: j['force'] == true,
        downloadPack: j['downloadPack'] == true,
        createdAt: _time(j['createdAt']) ?? DateTime.now(),
        items: [
          for (final i in (j['items'] as List?) ?? const [])
            TranscribeItem.fromJson((i as Map).cast<String, dynamic>()),
        ],
        status: '${j['status'] ?? kJobStarting}',
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        message: '${j['message'] ?? ''}',
        startedAt: _time(j['startedAt']),
        heartbeatAt: _time(j['heartbeatAt']),
        finishedAt: _time(j['finishedAt']),
        host: '${j['host'] ?? ''}',
        workerPid: (j['workerPid'] as num?)?.toInt(),
        runner: '${j['runner'] ?? ''}',
        backendUsed: '${j['backendUsed'] ?? ''}',
        error: j['error'] as String?,
        errorKind: j['errorKind'] as String?,
      );
}

class TranscribeJobStore {
  TranscribeJobStore(this.dir);

  /// `<ClipForge>/claude-jobs/transcribe`.
  final String dir;

  File fileOf(String id) => File(p.join(dir, '$id.json'));
  File cancelFileOf(String id) => File(p.join(dir, '$id.cancel'));

  void write(TranscribeJobRecord r, {bool createDir = true}) {
    if (createDir) {
      Directory(dir).createSync(recursive: true);
    } else if (!Directory(dir).existsSync()) {
      return;
    }
    final tmp = File(p.join(dir, '${r.id}.json.$pid.tmp'));
    tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(r.toJson()),
        flush: true);
    tmp.renameSync(fileOf(r.id).path);
  }

  TranscribeJobRecord? read(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) return null;
    final f = fileOf(id);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (!f.existsSync()) return null;
        return TranscribeJobRecord.fromJson(
            (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
      } catch (_) {
        sleep(const Duration(milliseconds: 40));
      }
    }
    return null;
  }

  /// Every job, newest first; old finished ones are deleted on the way.
  List<TranscribeJobRecord> list() {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <TranscribeJobRecord>[];
    for (final e in d.listSync()) {
      final name = p.basename(e.path);
      if (e is! File || !name.endsWith('.json')) continue;
      final r = read(name.substring(0, name.length - 5));
      if (r == null) continue;
      if (!r.isActive &&
          DateTime.now().difference(r.finishedAt ?? r.createdAt) > kJobKeepFor) {
        for (final f in [fileOf(r.id), cancelFileOf(r.id)]) {
          try {
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
        continue;
      }
      out.add(r);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  void requestCancel(String id) {
    Directory(dir).createSync(recursive: true);
    cancelFileOf(id).writeAsStringSync('cancel', flush: true);
  }
}

/// How a job is started (see ExportLauncher).
class TranscribeLauncher {
  const TranscribeLauncher(this.launch, {required this.description});
  final Future<int?> Function(TranscribeJobStore store, String id) launch;
  final String description;
}

/// Runs jobs inside this process with [service] (tests, and when a
/// separate process cannot be started).
TranscribeLauncher inProcessTranscribeLauncher(
        TranscriptionService Function(TranscribeJobRecord r) service,
        {Duration heartbeat = kJobHeartbeat}) =>
    TranscribeLauncher((store, id) async {
      final r = store.read(id);
      if (r == null) return null;
      unawaited(runTranscribeJob(store, id, service(r),
          runner: 'inside the server', heartbeat: heartbeat));
      return pid;
    }, description: 'inside this server');

/// Starts each job as `<this program> --transcribe-job <file>` in a
/// process that outlives the server and its client (see
/// startWorkerProcess in export_jobs.dart).
TranscribeLauncher separateTranscribeLauncher({List<String>? command}) =>
    TranscribeLauncher((store, id) async {
      final cmd = command ?? selfCommand();
      final args = [...cmd.skip(1), '--transcribe-job', store.fileOf(id).path];
      return startWorkerProcess(cmd.first, args, workingDirectory: store.dir);
    }, description: 'a separate process');

/// Entry point of `--transcribe-job <file>`.
Future<int> runTranscribeWorker(String jobFile) async {
  final store = TranscribeJobStore(p.dirname(jobFile));
  final id = p.basenameWithoutExtension(jobFile);
  final r = store.read(id);
  if (r == null) return 2;
  await runTranscribeJob(
      store,
      id,
      TranscriptionService(
          rootDir: r.rootDir, appVersion: BuildInfo.current.version),
      runner: 'a separate process');
  return 0;
}

/// Works through job [id]. Never throws.
Future<void> runTranscribeJob(
    TranscribeJobStore store, String id, TranscriptionService service,
    {String runner = '', Duration heartbeat = kJobHeartbeat}) async {
  final r = store.read(id);
  if (r == null || r.status != kJobStarting) return;
  final now = DateTime.now();
  r
    ..status = kJobRunning
    ..startedAt = now
    ..heartbeatAt = now
    ..host = localHostName()
    ..workerPid = pid
    ..runner = runner.isEmpty ? r.runner : runner;
  void save() {
    try {
      store.write(r, createDir: false);
    } catch (_) {}
  }

  TranscribeJob? current;
  var cancelling = false;
  final timer = Timer.periodic(heartbeat, (_) {
    if (!r.isActive) return;
    r.heartbeatAt = DateTime.now();
    save();
    if (!cancelling && store.cancelFileOf(id).existsSync()) {
      cancelling = true;
      current?.cancel();
    }
  });
  final transcripts = TranscriptStore.ofProject(r.projectDir);
  final quality = SpeechQuality.parse(r.quality);
  final total = r.items.fold<int>(0, (n, i) => n + (i.durationMs > 0 ? i.durationMs : 60000));
  var doneWeight = 0;
  try {
    save();
    for (final item in r.items) {
      final weight = item.durationMs > 0 ? item.durationMs : 60000;
      if (cancelling || store.cancelFileOf(id).existsSync()) {
        throw SpeechException('Stopped.', cancelled: true);
      }
      if (item.state == 'cached' || item.state == 'done') {
        doneWeight += weight;
        continue;
      }
      if (!r.force) {
        final have = await transcripts.load(item.path, item.audioTrack);
        if (have != null &&
            have.madeWith(
                language: r.language,
                models: quality == SpeechQuality.auto
                    ? null
                    : modelIdsFor(r.language == 'auto' ? '' : r.language, quality),
                backend: r.backend)) {
          item
            ..state = 'cached'
            ..words = have.wordCount
            ..language = have.language
            ..wordTiming = have.wordTiming.name;
          doneWeight += weight;
          continue;
        }
      }
      item.state = 'running';
      final job = current = service.transcribe(item.path,
          audioTrack: item.audioTrack,
          durationMs: item.durationMs,
          language: r.language,
          quality: quality,
          backendId: r.backend,
          allowDownload: r.downloadPack);
      if (cancelling) unawaited(job.cancel());
      final sub = job.progress.listen((pr) {
        r.message = '${p.basename(item.path)}: ${pr.message}';
        // Downloading and reading the sound count for the first tenth.
        final inItem = switch (pr.phase) {
          SpeechPhase.preparing => 0.0,
          SpeechPhase.downloading => 0.05 * pr.fraction,
          SpeechPhase.readingSound => 0.05 + 0.05 * pr.fraction,
          SpeechPhase.transcribing => 0.1 + 0.9 * pr.fraction,
        };
        final f = (doneWeight + weight * inItem) / total;
        if (f > r.progress) r.progress = f > 0.99 ? 0.99 : f;
      });
      final Transcript t;
      try {
        t = await job.done;
      } finally {
        unawaited(sub.cancel());
        current = null;
      }
      final saved = await transcripts.save(t);
      r.backendUsed = saved.backend;
      item
        ..state = 'done'
        ..words = saved.wordCount
        ..language = saved.language
        ..wordTiming = saved.wordTiming.name;
      doneWeight += weight;
      r.progress = (doneWeight / total).clamp(0.0, 0.99);
      save();
    }
    final end = DateTime.now();
    r
      ..status = kJobFinished
      ..progress = 1
      ..message = ''
      ..finishedAt = end
      ..heartbeatAt = end;
  } catch (e) {
    final ex = e is SpeechException
        ? e
        : SpeechException('Speech-to-text failed: $e', kind: 'failed');
    for (final i in r.items) {
      if (i.state == 'running') {
        i.state = ex.cancelled ? 'pending' : 'failed';
        if (!ex.cancelled) i.error = ex.message;
      }
    }
    r
      ..finishedAt = DateTime.now()
      ..heartbeatAt = DateTime.now()
      ..message = '';
    if (ex.cancelled) {
      r.status = kJobCancelled;
    } else {
      r
        ..status = kJobFailed
        ..error = ex.message
        ..errorKind = ex.kind;
    }
  } finally {
    timer.cancel();
    save();
    try {
      final c = store.cancelFileOf(id);
      if (c.existsSync()) c.deleteSync();
    } catch (_) {}
  }
}

/// The status of [r] as reported: as stored, or "lost" when it should be
/// running but its heartbeat stopped and its process is gone.
Future<String> transcribeJobStatus(TranscribeJobRecord r,
    {Future<bool> Function(int pid)? isAlive}) async {
  final beat = r.heartbeatAt ?? r.createdAt;
  final quiet = DateTime.now().difference(beat).inMilliseconds;
  if (r.isActive && quiet > kJobLostAfter.inMilliseconds) {
    final alive = r.workerPid != null &&
        (r.host.isEmpty || r.host == localHostName()) &&
        await (isAlive ?? processAlive)(r.workerPid!);
    if (!alive) return kJobLost;
  }
  return r.status;
}
