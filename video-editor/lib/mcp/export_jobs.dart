// Exports that outlive a tool call (and the server): export_video starts a
// JOB, get_export_status reports on it, cancel_export stops it.
//
// Why: a long project takes longer to render than an MCP client waits for
// one tool call (Claude Code gave up after about a minute, restarted the
// server, and FFmpeg died with it). Now:
//  * every job is a small JSON file in the job folder (<id>.json, next to
//    the projects folder: `<ClipForge>/claude-jobs/`), with a copy of the
//    project as it was when the export was asked for (<id>.project.json),
//    so a NEW server process can report on a job an older one started and
//    edits made meanwhile do not change what is rendered;
//  * the render runs in a separate process (this program started again
//    with `--export-job <file>`, detached from the server) that writes its
//    progress and a heartbeat into the job file every second and looks for
//    a cancel request (<id>.cancel);
//  * it renders into `<name>.part.<ext>` next to the target and renames it
//    when the file is complete and checked, so a failed or cancelled export
//    never leaves a half file under the real name.
// Pure Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import '../core/storage/project_lock.dart' show processAlive, localHostName;
import '../media/ffmpeg_command.dart' show exportSize;
import '../media/media_api.dart';
import '../media/process_media_engine.dart';
import '../media/video_encoder.dart' show encoderDescription;
import 'environment.dart' show locateFonts;

/// States of a job as stored. [kJobLost] is only ever reported (worked out
/// from an old heartbeat), never written.
const String kJobStarting = 'starting';
const String kJobRunning = 'running';
const String kJobFinished = 'finished';
const String kJobFailed = 'failed';
const String kJobCancelled = 'cancelled';
const String kJobLost = 'lost';

/// How often a running job writes its progress and heartbeat.
const Duration kJobHeartbeat = Duration(seconds: 1);

/// A running job whose heartbeat is older than this (and whose process is
/// gone) has stopped without finishing.
const Duration kJobLostAfter = Duration(seconds: 30);

/// Finished jobs are forgotten after this long.
const Duration kJobKeepFor = Duration(days: 7);

/// One export job (the JSON file).
class ExportJobRecord {
  ExportJobRecord({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.outputPath,
    required this.partPath,
    required this.format,
    required this.quality,
    required this.fps,
    required this.hardware,
    required this.overwrite,
    required this.createdAt,
    required this.projectDurationMs,
    required this.estimateMs,
    this.estimateBasis = '',
    this.status = kJobStarting,
    this.progress = 0,
    this.startedAt,
    this.heartbeatAt,
    this.finishedAt,
    this.host = '',
    this.workerPid,
    this.runner = '',
    this.ffmpegPath,
    this.ffprobePath,
    this.fontsDir,
    this.notes = const [],
    this.details = const {},
    this.result,
    this.error,
    this.log,
  });

  final String id;
  final String projectId;
  final String projectName;
  final String outputPath;
  final String partPath;
  final String format;
  final String quality;
  final int fps;
  final bool hardware;
  final bool overwrite;
  final DateTime createdAt;
  final int projectDurationMs;

  /// Rough render time worked out before it started.
  final int estimateMs;
  final String estimateBasis;
  String status;
  double progress;
  DateTime? startedAt;
  DateTime? heartbeatAt;
  DateTime? finishedAt;
  String host;
  int? workerPid;

  /// Where it runs ("a separate process", "inside the server").
  String runner;
  final String? ffmpegPath;
  final String? ffprobePath;
  final String? fontsDir;

  /// Facts for the result (what "small" changed, the ducking report, ...).
  final List<String> notes;

  /// The same facts as data (canvasReason, small, ducking).
  final Map<String, dynamic> details;
  Map<String, dynamic>? result;
  String? error;
  String? log;

  bool get isActive => status == kJobStarting || status == kJobRunning;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'outputPath': outputPath,
        'partPath': partPath,
        'format': format,
        'quality': quality,
        'fps': fps,
        'hardware': hardware,
        'overwrite': overwrite,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'projectDurationMs': projectDurationMs,
        'estimateMs': estimateMs,
        'estimateBasis': estimateBasis,
        'status': status,
        'progress': progress,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'heartbeatAt': heartbeatAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'host': host,
        'workerPid': workerPid,
        'runner': runner,
        'ffmpegPath': ffmpegPath,
        'ffprobePath': ffprobePath,
        'fontsDir': fontsDir,
        'notes': notes,
        'details': details,
        'result': result,
        'error': error,
        'log': log,
      };

  static DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v');

  factory ExportJobRecord.fromJson(Map<String, dynamic> j) => ExportJobRecord(
        id: j['id'] as String,
        projectId: '${j['projectId']}',
        projectName: '${j['projectName']}',
        outputPath: j['outputPath'] as String,
        partPath: j['partPath'] as String,
        format: '${j['format'] ?? 'video'}',
        quality: '${j['quality'] ?? 'full'}',
        fps: (j['fps'] as num?)?.toInt() ?? 30,
        hardware: j['hardware'] != false,
        overwrite: j['overwrite'] == true,
        createdAt: _time(j['createdAt']) ?? DateTime.now(),
        projectDurationMs: (j['projectDurationMs'] as num?)?.toInt() ?? 0,
        estimateMs: (j['estimateMs'] as num?)?.toInt() ?? 0,
        estimateBasis: '${j['estimateBasis'] ?? ''}',
        status: '${j['status'] ?? kJobStarting}',
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        startedAt: _time(j['startedAt']),
        heartbeatAt: _time(j['heartbeatAt']),
        finishedAt: _time(j['finishedAt']),
        host: '${j['host'] ?? ''}',
        workerPid: (j['workerPid'] as num?)?.toInt(),
        runner: '${j['runner'] ?? ''}',
        ffmpegPath: j['ffmpegPath'] as String?,
        ffprobePath: j['ffprobePath'] as String?,
        fontsDir: j['fontsDir'] as String?,
        notes: [for (final n in (j['notes'] as List?) ?? const []) '$n'],
        details: (j['details'] as Map?)?.cast<String, dynamic>() ?? const {},
        result: (j['result'] as Map?)?.cast<String, dynamic>(),
        error: j['error'] as String?,
        log: j['log'] as String?,
      );
}

/// The job folder.
class ExportJobStore {
  ExportJobStore(this.dir);
  final String dir;

  File fileOf(String id) => File(p.join(dir, '$id.json'));
  File projectFileOf(String id) => File(p.join(dir, '$id.project.json'));
  File cancelFileOf(String id) => File(p.join(dir, '$id.cancel'));

  /// Writes [r] atomically (temporary file, then rename). With
  /// [createDir] false nothing is written when the folder is gone (a render
  /// whose job folder was deleted does not bring it back).
  void write(ExportJobRecord r, {bool createDir = true}) {
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

  /// The job [id], or null when there is none. Retries briefly: on
  /// Windows a file being replaced cannot be read for a moment.
  ExportJobRecord? read(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) return null;
    final f = fileOf(id);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (!f.existsSync()) return null;
        return ExportJobRecord.fromJson(
            (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
      } catch (_) {
        sleep(const Duration(milliseconds: 40));
      }
    }
    return null;
  }

  /// Every job, newest first. Jobs older than [kJobKeepFor] that are over
  /// are deleted on the way.
  List<ExportJobRecord> list() {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <ExportJobRecord>[];
    for (final e in d.listSync()) {
      final name = p.basename(e.path);
      if (e is! File || !name.endsWith('.json') || name.endsWith('.project.json')) {
        continue;
      }
      final r = read(name.substring(0, name.length - 5));
      if (r == null) continue;
      if (!r.isActive &&
          DateTime.now().difference(r.finishedAt ?? r.createdAt) > kJobKeepFor) {
        for (final f in [fileOf(r.id), projectFileOf(r.id), cancelFileOf(r.id)]) {
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

/// How a job is started: in a separate process (the shipped server) or
/// inside this one (tests, and when starting a process fails).
class ExportLauncher {
  const ExportLauncher(this.launch,
      {required this.description, this.needsFfmpeg = true, this.survivesServer = false});

  /// Starts job [id] and returns the process id that runs it.
  final Future<int?> Function(ExportJobStore store, String id) launch;

  /// "a separate process", "inside this server".
  final String description;

  /// The job uses the ffmpeg / ffprobe found by the server.
  final bool needsFfmpeg;

  /// The render keeps going when this server stops.
  final bool survivesServer;
}

/// Runs jobs inside this process with [engine].
ExportLauncher inProcessLauncher(Future<MediaEngine> Function() engine,
        {bool needsFfmpeg = true}) =>
    ExportLauncher((store, id) async {
      final e = await engine();
      unawaited(runExportJob(store, id, e, runner: 'inside the server'));
      return pid;
    }, description: 'inside this server', needsFfmpeg: needsFfmpeg);

/// The command that starts this program again: the executable itself, or
/// `dart <script>` when it runs from source.
List<String> selfCommand() {
  final exe = Platform.resolvedExecutable;
  final name = p.basenameWithoutExtension(exe).toLowerCase();
  if (name == 'dart') {
    return [exe, Platform.script.toFilePath()];
  }
  return [exe];
}

/// Set to "child" to start workers the pre-1.12 way on Windows (a normal
/// child process); for tests and as an escape hatch.
const String kEnvWorkerStart = 'CLIPFORGE_WORKER_START';

/// The PowerShell command that starts a worker OUTSIDE this server's
/// process tree on Windows and prints its process id. Everything it needs
/// comes in through environment variables (no quoting of paths on a
/// command line): CF_WORKER_EXE, CF_WORKER_DIR, CF_WORKER_ARGC and
/// CF_WORKER_ARG0..n.
const String kWindowsWorkerStartScript =
    r"$q = [char]34; $a = @(); "
    r"for ($i = 0; $i -lt [int]$env:CF_WORKER_ARGC; $i++) { "
    r"$a += $q + [Environment]::GetEnvironmentVariable('CF_WORKER_ARG' + $i) + $q }; "
    r"$p = Start-Process -FilePath $env:CF_WORKER_EXE -ArgumentList $a "
    r"-WorkingDirectory $env:CF_WORKER_DIR -WindowStyle Hidden -PassThru; "
    r"[Console]::Out.Write($p.Id)";

/// How the last worker was started ("outside the process tree",
/// "child process", "detached"); shown by get_status.
String lastWorkerStart = '';

/// Starts `<exe> <args>` as a job worker that outlives this server and
/// the program that started the server, and returns its process id.
///
/// macOS / Linux: detached (its own session).
///
/// Windows (decision, 1.12): Claude Code ends the server's whole process
/// TREE when it disconnects or quits, and a normal child (what 1.9 - 1.11
/// started) is part of that tree. The worker is therefore started by a
/// short-lived PowerShell (`Start-Process -WindowStyle Hidden -PassThru`):
/// PowerShell exits at once, so the worker's parent is gone and a tree
/// kill of the server (`taskkill /T`) no longer reaches it; it gets its
/// own hidden console, so FFmpeg opens no window; it inherits the
/// server's environment (PATH, CLIPFORGE_* settings). WMI
/// (Win32_Process.Create) would also leave the tree but drops the
/// environment; scheduled tasks need no thought. When PowerShell cannot be
/// run the worker is started as a normal child, as before. Checked by the
/// Windows job of the build workflow (tool/ci/job_survives_test.py).
Future<int> startWorkerProcess(String exe, List<String> args,
    {required String workingDirectory}) async {
  if (!Platform.isWindows) {
    final proc = await Process.start(exe, args,
        workingDirectory: workingDirectory, mode: ProcessStartMode.detached);
    lastWorkerStart = 'detached';
    return proc.pid;
  }
  if (Platform.environment[kEnvWorkerStart] != 'child') {
    try {
      final r = await Process.run(
        'powershell.exe',
        [
          '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', //
          '-WindowStyle', 'Hidden', '-Command', kWindowsWorkerStartScript,
        ],
        environment: {
          'CF_WORKER_EXE': exe,
          'CF_WORKER_DIR': workingDirectory,
          'CF_WORKER_ARGC': '${args.length}',
          for (var i = 0; i < args.length; i++) 'CF_WORKER_ARG$i': args[i],
        },
        workingDirectory: workingDirectory,
      ).timeout(const Duration(seconds: 30));
      final started = int.tryParse('${r.stdout}'.trim());
      if (r.exitCode == 0 && started != null && started > 0) {
        lastWorkerStart = 'outside the process tree';
        return started;
      }
    } catch (_) {
      // No PowerShell, or it hung: the old way below.
    }
  }
  final proc = await Process.start(exe, args,
      workingDirectory: workingDirectory, mode: ProcessStartMode.normal);
  // Nothing is written there; drained so the pipes never fill.
  proc.stdout.drain<void>().ignore();
  proc.stderr.drain<void>().ignore();
  proc.stdin.close().ignore();
  lastWorkerStart = 'child process';
  return proc.pid;
}

/// Starts each job as `<this program> --export-job <file>` in its own
/// process that outlives the server and its client: see
/// [startWorkerProcess].
ExportLauncher separateProcessLauncher({List<String>? command}) => ExportLauncher(
      (store, id) async {
        final cmd = command ?? selfCommand();
        final args = [...cmd.skip(1), '--export-job', store.fileOf(id).path];
        return startWorkerProcess(cmd.first, args, workingDirectory: store.dir);
      },
      description: 'a separate process',
      survivesServer: true,
    );

/// Entry point of `--export-job <file>`: renders the job and exits.
Future<int> runExportWorker(String jobFile) async {
  final store = ExportJobStore(p.dirname(jobFile));
  final id = p.basenameWithoutExtension(jobFile);
  final r = store.read(id);
  if (r == null) return 2;
  try {
    final fonts = r.fontsDir == null ? null : locateFonts(explicitDir: r.fontsDir).fonts;
    final engine = ProcessMediaEngine(
        ffmpegPath: r.ffmpegPath, ffprobePath: r.ffprobePath, fonts: fonts);
    await runExportJob(store, id, engine, runner: 'a separate process');
  } catch (e) {
    final now = store.read(id) ?? r;
    if (now.isActive) {
      now
        ..status = kJobFailed
        ..error = 'The export process could not run: $e'
        ..finishedAt = DateTime.now();
      store.write(now);
    }
    return 1;
  }
  return 0;
}

/// Renders job [id] with [engine]: progress and heartbeat into the job
/// file, the `.part` file renamed when done, the result (size, length,
/// encoder) or the error written at the end. Never throws.
Future<void> runExportJob(ExportJobStore store, String id, MediaEngine engine,
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

  Timer? timer;
  final part = File(r.partPath);
  try {
    save();
    if (store.cancelFileOf(id).existsSync()) {
      throw ExportException('Export cancelled', cancelled: true);
    }
    final Project project;
    try {
      project = Project.fromJson((jsonDecode(store.projectFileOf(id).readAsStringSync()) as Map)
          .cast<String, dynamic>());
    } catch (e) {
      throw ExportException('The copy of the project for this export cannot be read: $e');
    }
    await Directory(p.dirname(r.partPath)).create(recursive: true);
    final format = ExportFormat.values.byName(r.format);
    final quality = ExportQuality.values.byName(r.quality);
    final running = engine.export(project, r.partPath,
        options: ExportOptions(
            quality: quality,
            fps: r.fps,
            useHardwareEncoder: r.hardware,
            format: format));
    final progress = running.progress.listen((pr) {
      final f = pr.fraction.clamp(0.0, 0.99);
      if (f > r.progress) r.progress = f;
    });
    var cancelling = false;
    timer = Timer.periodic(heartbeat, (_) {
      if (!r.isActive) return;
      r.heartbeatAt = DateTime.now();
      save();
      if (!cancelling && store.cancelFileOf(id).existsSync()) {
        cancelling = true;
        running.cancel();
      }
    });
    try {
      await running.done;
    } finally {
      await progress.cancel();
    }
    timer.cancel();
    final out = File(r.outputPath);
    if (out.existsSync()) {
      if (!r.overwrite) {
        throw ExportException('"${r.outputPath}" appeared while the export ran '
            'and is kept; the new video is in "${r.partPath}".');
      }
      out.deleteSync();
    }
    await part.rename(r.outputPath);
    final size = out.lengthSync();
    MediaInfo? info;
    try {
      info = await engine.probe(r.outputPath);
    } on ExportException {
      info = null;
    }
    final encoder = running.videoEncoder;
    final finished = DateTime.now();
    final took = finished.difference(r.startedAt!).inMilliseconds;
    r
      ..status = kJobFinished
      ..progress = 1
      ..finishedAt = finished
      ..heartbeatAt = finished
      ..result = {
        'outputPath': r.outputPath,
        'sizeBytes': size,
        'renderMs': took,
        if (info != null) ...{
          'durationMs': info.durationMs,
          'width': info.width,
          'height': info.height,
          'hasVideo': info.hasVideo,
          'hasAudio': info.hasAudio,
        },
        if (encoder != null && r.format == 'video') ...{
          'videoEncoder': encoder.ffmpegName,
          'hardwareEncoder': encoder.hardware,
          'encoderDescription': encoderDescription(encoder),
        },
        if (running.warnings.isNotEmpty) 'warnings': running.warnings,
        // Speed of this computer, for the next estimate of this kind.
        if (took > 0 && info != null && info.durationMs > 0)
          'timesRealTime': info.durationMs / took,
        if (took > 0 && info != null && r.format == 'video')
          'megapixelSecondsPerSecond': info.width *
              info.height /
              1e6 *
              (info.durationMs / 1000) /
              (took / 1000),
      };
    save();
  } catch (e) {
    timer?.cancel();
    final ex = e is ExportException ? e : ExportException('Export failed: $e');
    r
      ..finishedAt = DateTime.now()
      ..heartbeatAt = DateTime.now();
    if (ex.cancelled) {
      r.status = kJobCancelled;
    } else {
      r
        ..status = kJobFailed
        ..error = ex.message;
      final log = (ex.log ?? '').trim();
      if (log.isNotEmpty) {
        r.log = log.length > 1500 ? log.substring(log.length - 1500) : log;
      }
    }
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
    save();
  } finally {
    for (final f in [store.cancelFileOf(id), store.projectFileOf(id)]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// What get_export_status reports: the stored state plus what is worked
/// out from it (lost jobs, elapsed time, time left).
class JobView {
  JobView(this.record, this.status, this.elapsedMs, this.etaMs, this.quietForMs);
  final ExportJobRecord record;

  /// As stored, or [kJobLost].
  final String status;
  final int elapsedMs;

  /// Time left; null when unknown.
  final int? etaMs;

  /// How long since the last heartbeat of a running job.
  final int quietForMs;
}

Future<JobView> viewJob(ExportJobRecord r,
    {DateTime? now, Future<bool> Function(int pid)? isAlive}) async {
  final at = now ?? DateTime.now();
  var status = r.status;
  final beat = r.heartbeatAt ?? r.createdAt;
  final quiet = at.difference(beat).inMilliseconds;
  if (r.isActive && quiet > kJobLostAfter.inMilliseconds) {
    final alive = r.workerPid != null &&
        (r.host.isEmpty || r.host == localHostName()) &&
        await (isAlive ?? processAlive)(r.workerPid!);
    if (!alive) status = kJobLost;
  }
  final start = r.startedAt ?? r.createdAt;
  final end = r.isActive ? at : (r.finishedAt ?? at);
  final elapsed = end.difference(start).inMilliseconds;
  int? eta;
  if (status == kJobRunning || status == kJobStarting) {
    if (r.progress >= 0.03 && elapsed > 3000) {
      eta = (elapsed * (1 - r.progress) / r.progress).round();
    } else if (r.estimateMs > 0) {
      eta = r.estimateMs - elapsed;
      if (eta < 1000) eta = null;
    }
  }
  return JobView(r, status, elapsed < 0 ? 0 : elapsed, eta, quiet);
}

/// Output megapixel-seconds rendered per second when nothing better is
/// known: libx264 "veryfast" on an ordinary 4-core laptop does 1280x720
/// at about 3x real time.
const double kDefaultRenderRate = 2.7;

/// Sound-only exports when nothing better is known: about 20x real time
/// (the owner's 22:41 M4A took 1:10).
const double kDefaultAudioSpeed = 20;

/// What kind of export a job is, for remembering speeds: "sound",
/// "video on the graphics card" or "video on the processor". Speeds are
/// only comparable within one kind (the owner's graphics card rendered
/// 22 minutes in 1:28 where the processor estimate said 7:48).
String exportKind({required bool audioOnly, required bool hardware}) =>
    audioOnly ? 'sound' : (hardware ? 'video-gpu' : 'video-cpu');

/// The kind a finished job turned out to be (the encoder that really ran).
String? exportKindOf(ExportJobRecord r) {
  final res = r.result;
  if (r.status != kJobFinished || res == null) return null;
  return exportKind(
      audioOnly: r.format != 'video',
      hardware: res['hardwareEncoder'] == true);
}

/// The speed this computer showed in its last finished export of [kind]
/// among [jobs] (newest first): megapixel-seconds per second for video,
/// times real time for sound. Null when there is none.
double? rememberedSpeed(List<ExportJobRecord> jobs, String kind, {String? host}) {
  for (final r in jobs) {
    if (host != null && r.host != host) continue;
    if (exportKindOf(r) != kind) continue;
    final v = kind == 'sound'
        ? r.result!['timesRealTime']
        : r.result!['megapixelSecondsPerSecond'];
    if (v is num && v > 0.05) return v.toDouble();
  }
  return null;
}

/// A rough render time for [project], with a range:
///  * video: output pixels x length / the speed of the last export OF THE
///    SAME KIND on this computer ([speeds]: kind -> speed, see
///    [rememberedSpeed]); with the graphics card asked for, the card's
///    remembered speed, else the processor's; [kDefaultRenderRate] when
///    nothing is remembered;
///  * what else there is to draw and mix slows it down: titles and
///    captions (2 % each, at most +60 %), overlay items (+25 % while any
///    is used), sound items beyond the first (1 % each, at most +20 %);
///  * sound only: length / remembered speed ([kDefaultAudioSpeed]).
/// The range is wide on purpose (0.6x..1.7x; 0.4x..2.5x without a
/// remembered speed): once the render runs, the time left is worked out
/// from its real progress instead.
({int ms, int lowMs, int highMs, String basis, bool rough}) estimateRenderMs(
    Project project, ExportOptions options,
    {double? measuredRate, Map<String, double> speeds = const {}}) {
  final seconds = project.durationMs / 1000;
  final perClipMs = 40 * project.clips.length;
  ({int ms, int lowMs, int highMs, String basis, bool rough}) range(
      int ms, bool known, String basis) {
    final lo = known ? 0.6 : 0.4, hi = known ? 1.7 : 2.5;
    return (
      ms: ms,
      lowMs: (ms * lo).round(),
      highMs: (ms * hi).round(),
      basis: basis,
      rough: !known,
    );
  }

  if (options.format.audioOnly) {
    final known = speeds['sound'];
    final speed = known ?? kDefaultAudioSpeed;
    final mix = 1 + (project.audio.length * 0.02).clamp(0.0, 0.5);
    return range(
        (seconds / speed * mix * 1000).round() + perClipMs ~/ 4 + 1000,
        known != null,
        known != null
            ? 'from the speed of the last sound-only export on this computer'
            : 'rough: sound only usually renders at about '
                '${kDefaultAudioSpeed.round()}x real time');
  }
  final size = exportSize(project, options.quality);
  final mp = size.width * size.height / 1e6 * (options.fps / 30);
  final gpu = options.useHardwareEncoder ? speeds['video-gpu'] : null;
  final cpu = speeds['video-cpu'] ?? measuredRate;
  final rate = gpu ?? cpu ?? kDefaultRenderRate;
  final known = gpu != null || cpu != null;
  final titles = (project.titles.length * 0.02).clamp(0.0, 0.6);
  final overlays = project.overlays.isEmpty ? 0.0 : 0.25;
  final sounds =
      ((project.audio.length - 1).clamp(0, 1000) * 0.01).clamp(0.0, 0.2);
  final work = 1 + titles + overlays + sounds;
  final ms = (mp * seconds / rate * work * 1000).round() + perClipMs + 2000;
  final extras = [
    if (project.titles.isNotEmpty) '${project.titles.length} title(s) / caption(s)',
    if (project.overlays.isNotEmpty) '${project.overlays.length} overlay item(s)',
    if (project.audio.length > 1) '${project.audio.length} sound items',
  ];
  return range(
      ms,
      known,
      '${gpu != null ? 'from the speed of the last export on the graphics card here' : cpu != null ? 'from the speed of the last export on the processor here${options.useHardwareEncoder ? ' (a graphics card, if this computer has one, is faster)' : ''}' : 'rough: a guess for an ordinary computer without a graphics card encoder; the next estimate uses the speed this export measures'}'
      '${extras.isEmpty ? '' : '; counted in: ${extras.join(', ')}'}');
}

/// "1 min 05 s", "12 s".
String durationText(int ms) {
  if (ms < 0) ms = 0;
  final s = (ms / 1000).round();
  if (s < 60) return '$s s';
  final h = s ~/ 3600, m = s ~/ 60 % 60, rest = s % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  return '$m min ${rest.toString().padLeft(2, '0')} s';
}
