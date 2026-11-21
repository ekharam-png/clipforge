// MediaEngine backed by the ffmpeg_kit_flutter_new plugin (FFmpeg linked
// into the app). Used on Android, iOS, macOS and Windows.

import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/log_redirection_strategy.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import '../core/background_work.dart';
import '../core/perf_log.dart';
import 'ffmpeg_command.dart';
import 'ffmpeg_lane.dart';
import 'kit_runner.dart';
import 'hardware_encoding.dart';
import 'media_api.dart';
import 'media_common.dart';
import 'media_jobs.dart';
import 'sound_filters.dart';
import 'sound_align_job.dart';
import 'jump_check.dart';
import 'sound_peaks_job.dart';
import 'sound_render_job.dart';
import 'media_fonts.dart';
import 'video_encoder.dart';

class FfmpegKitMediaEngine
    implements
        MediaEngine,
        ThumbnailStripEngine,
        SilenceJobEngine,
        SoundAlignEngine,
        SoundPeaksEngine,
        CancellableSoundPeaksEngine,
        SpeechWavEngine,
        JumpCheckEngine {
  FfmpegKitMediaEngine({
    FontResolver? fontResolver,
    this.thumbnailDir,
    this.preset = 'veryfast',
  }) : _fonts = fontResolver ?? bundledFonts;

  final Directory? thumbnailDir;
  final String preset;
  final FontResolver _fonts;
  final EncoderPlatform _platform = currentEncoderPlatform();

  /// The hardware encoder of the FFmpeg in the app, found once per run.
  late final HardwareEncoders _encoders = HardwareEncoders.shared(
      'ffmpeg-kit|${_platform.name}',
      () => HardwareEncoders(
            platform: _platform,
            listEncoders: _listEncoders,
            // Not in the lane: a short test that must not time out behind
            // a long run.
            run: _session,
          ));

  /// The filters of the FFmpeg in the app, asked once per run.
  late final FilterSupport _filters =
      FilterSupport.shared('ffmpeg-kit', () => FilterSupport(_listFilters));

  /// FFmpegKit prints the `-filters` table through its log, like
  /// `-encoders`.
  Future<String?> _listFilters() async =>
      (await _session(const ['-filters'])).log;

  /// FFmpegKit prints the `-encoders` table through its log.
  Future<String?> _listEncoders() async =>
      (await _session(const ['-encoders'])).log;

  @override
  Future<bool> hasHardwareEncoder() => _encoders.available();

  @override
  Future<VideoEncoder?> graphicsCardEncoder() => _encoders.current();

  Future<int?>? _major;

  /// Major version of the FFmpeg linked into the app (asked once); null
  /// when the plugin cannot tell, which is then treated as a current one.
  Future<int?> _majorVersion() => _major ??= () async {
        try {
          return ffmpegMajorVersion(await FFmpegKitConfig.getFFmpegVersion() ?? '');
        } catch (_) {
          return null;
        }
      }();

  @override
  Future<MediaInfo> probe(String path) async {
    // Never in the lane: a probe is what the user waits for when a file
    // is added, and it must not sit behind a sound picture.
    final log = PerfLog.instance;
    final quiet = log.span('probe: log messages off');
    await _quiet();
    quiet();
    // The size only (a stat; nothing of the file is read): a log that
    // ends inside a probe then says how big the file was.
    var size = '';
    try {
      size = ', ${formatProbeSize(await File(path).length())}';
    } catch (_) {}
    final end = log.span('probe$size');
    try {
      final info = await _probe(path);
      end('end (${info.hasVideo ? 'video' : 'sound'} '
          '${info.durationMs ~/ 1000} s)');
      return info;
    } catch (_) {
      end('failed');
      rethrow;
    }
  }

  Future<MediaInfo> _probe(String path) async {
    final log = PerfLog.instance;
    // Our own arguments also ask for the first frame of a photo (EXIF
    // orientation); fall back to the plugin's stock command if that yields
    // nothing. A video is asked for its index only.
    var step = log.span('probe: ffprobe'
        '${probeReadsFirstFrame(path) ? ' with first frame' : ''}');
    var session = await FFprobeKit.getMediaInformationFromCommandArguments(
        buildProbeCommand(path));
    var props = session.getMediaInformation()?.getAllProperties();
    step(props == null ? 'gave nothing' : 'end');
    if (props == null) {
      step = log.span('probe: ffprobe, plain command');
      session = await FFprobeKit.getMediaInformation(path);
      props = session.getMediaInformation()?.getAllProperties();
      step(props == null ? 'gave nothing' : 'end');
    }
    if (props == null) {
      String? log;
      try {
        log = await session.getAllLogsAsString(_logWaitMs);
      } catch (_) {}
      throw ExportException('Cannot read media file: $path', log: log);
    }
    return parseProbeJson(props);
  }

  @override
  Future<String> thumbnail(String path,
      {int timeMs = 0, int maxHeight = 160}) async {
    final out = await thumbnailPathFor(path, timeMs, maxHeight,
        cacheDir: thumbnailDir);
    final file = File(out);
    if (await file.exists() && await file.length() > 0) return out;

    Future<FfmpegRun> run(int t) => _ffmpeg([
          '-loglevel', 'error', '-nostats',
          ...buildThumbnailCommand(
              path: path, outputPath: out, timeMs: t, maxHeight: maxHeight),
        ]);
    Future<bool> ok(FfmpegRun r) async =>
        r.ok && await file.exists() && await file.length() > 0;

    var r = await run(timeMs);
    if (!await ok(r) && timeMs > 0) r = await run(0);
    if (!await ok(r)) {
      await deleteQuietly(file);
      throw ExportException('Cannot create a thumbnail of $path', log: r.log);
    }
    return out;
  }

  /// Every FFmpeg run of this engine goes through here: see
  /// kit_runner.dart for how FFmpeg inside the app is kept from holding
  /// up the app (no log messages to Dart, `-loglevel error -nostats`,
  /// throttled progress, one run at a time with the user's first).
  static final KitRunner _kit = () {
    final kit = KitRunner(_PluginPlatform());
    // The safety valve: thumbnail strips and sound decodes wait while
    // the app's background work is paused.
    BackgroundWork.instance.add(BackgroundTask('ffmpeg runs in the background',
        busy: () => kit.lane.backgroundBusy,
        pause: kit.lane.pauseBackground, resume: kit.lane.resumeBackground));
    return kit;
  }();

  /// The lane (the editor's status, tests).
  static FfmpegLane get lane => _kit.lane;

  static Future<void> _quiet() => _kit.quiet();

  /// Fetching a session's log waits (on the platform thread) for lines
  /// still on their way: never the plugin's default of five seconds.
  static const int _logWaitMs = kKitLogWaitMs;

  Future<FfmpegRun> _session(List<String> args) => _kit.session(args);

  Future<FfmpegRun> _ffmpeg(List<String> args) => _kit.user(args);

  Future<FfmpegRun> _ffmpegStreaming(List<String> args,
          void Function(int timeMs) onTimeMs, Future<void> cancel) =>
      _kit.streaming(args, onTimeMs, cancel);

  Future<FfmpegRun> _background(List<String> args, {Future<void>? cancel}) =>
      _kit.background(args, cancel: cancel);

  @override
  Future<void> speechWav(String input, String output,
      {required int audioTrack,
      required int durationMs,
      required void Function(double fraction) onProgress,
      required Future<void> cancelled}) async {
    var stopped = false;
    unawaited(cancelled.then((_) => stopped = true));
    final run = await _ffmpegStreaming(
        speechWavArgs(input, output, audioTrack),
        (ms) {
          if (durationMs > 0) onProgress((ms / durationMs).clamp(0.0, 1.0));
        },
        cancelled);
    if (stopped) throw ExportException('Stopped.', cancelled: true);
    if (!run.ok) {
      final why = summarizeFfmpegError(run.log);
      throw ExportException(
          'The sound of ${p.basename(input)} could not be read'
          '${why == null ? '.' : ': $why'}',
          log: run.log);
    }
  }

  @override
  Future<String> extractFrame(String path, int timeMs, String outputPath) =>
      extractFrameWith(_ffmpeg, path, timeMs, outputPath);

  @override
  Future<List<({int startMs, int endMs})>> detectSilence(String path,
          {double? thresholdDb,
          int minSilenceMs = 700,
          int audioTrack = 0,
          AudioChannel channel = AudioChannel.both}) =>
      detectSilenceWith(_ffmpeg, probe, path,
          thresholdDb: thresholdDb,
          minSilenceMs: minSilenceMs,
          audioTrack: audioTrack,
          channel: channel);

  @override
  Future<AlignResult> alignSound(String videoPath, String voicePath,
          {int videoAudioTrack = 0, int voiceAudioTrack = 0}) =>
      alignSoundWith(_ffmpeg, probe, videoPath, voicePath,
          videoAudioTrack: videoAudioTrack, voiceAudioTrack: voiceAudioTrack);

  @override
  Future<SoundPeaks?> soundPeaks(String path,
          {int audioTrack = 0, String? cacheDir}) =>
      soundPeaksWith(_background, probe, path,
          audioTrack: audioTrack, cacheDir: cacheDir);

  @override
  Future<SoundPeaks?> soundPeaksCancellable(String path,
          {int audioTrack = 0,
          String? cacheDir,
          required Future<void> cancel}) =>
      soundPeaksWith(_background, probe, path,
          audioTrack: audioTrack,
          cacheDir: cacheDir,
          streaming: (args, _, stop) => _background(args, cancel: stop),
          cancel: cancel);

  @override
  Future<List<double?>> jumpScores(
          String path, List<({int beforeMs, int afterMs})> cuts) =>
      jumpScoresWith(_ffmpeg, path, cuts);

  @override
  ExportJob renderClipSound(Clip clip, String outputPath) => SoundRenderJob(
        clip,
        outputPath,
        leaveOut: () async => (await _filters.check()).unavailable,
        launch: (args, {required onTimeMs, required onLog}) async {
          await _quiet();
          final finished = Completer<FFmpegSession>();
          final throttle = Throttle<int>(onTimeMs);
          final session = await FFmpegKit.executeWithArgumentsAsync(
            ['-hide_banner', '-loglevel', 'error', ...args],
            (s) async {
              throttle.close();
              // The log is asked for once, and only after a failure.
              if (!ReturnCode.isSuccess(await s.getReturnCode())) {
                try {
                  onLog(await s.getAllLogsAsString(_logWaitMs) ?? '');
                } catch (_) {}
              }
              if (!finished.isCompleted) finished.complete(s);
            },
            null,
            // Statistics time is the output position in milliseconds.
            (st) => throttle.add(st.getTime().round()),
          );
          return _KitRun(session, finished.future);
        },
      );

  @override
  Future<ThumbnailStrip> thumbnailStrip(String path,
          {int durationMs = 0, int height = kStripFrameHeight}) =>
      thumbnailStripWith(_background, probe, path,
          durationMs: durationMs, height: height, cacheDir: thumbnailDir);

  @override
  SilenceJob startSilenceDetection(String path,
          {double? thresholdDb,
          int minSilenceMs = 700,
          int audioTrack = 0,
          AudioChannel channel = AudioChannel.both,
          int fromMs = 0,
          int toMs = 0}) =>
      silenceJobWith(_ffmpegStreaming, probe, path,
          thresholdDb: thresholdDb,
          minSilenceMs: minSilenceMs,
          audioTrack: audioTrack,
          channel: channel,
          fromMs: fromMs,
          toMs: toMs);

  @override
  ExportJob export(Project project, String outputPath,
      {ExportOptions options = const ExportOptions()}) {
    return EncoderFallbackJob(
      encoders: _encoders,
      options: options,
      verify: outputCheck(probe, project.durationMs),
      start: (encoder) {
        final job = _KitExportJob(outputPath, encoder);
        job._run(this, project, options);
        return job;
      },
    );
  }
}

class _KitExportJob implements ExportJob {
  _KitExportJob(this._outputPath, this._encoder) {
    _done.future.ignore();
  }

  final String _outputPath;
  final VideoEncoder _encoder;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  FFmpegSession? _session;
  bool _cancelled = false;
  double _last = 0;

  @override
  Stream<ExportProgress> get progress => _progress.stream;

  @override
  Future<String> get done => _done.future;

  @override
  VideoEncoder? get videoEncoder => _done.isCompleted ? _encoder : null;

  List<String> _warnings = const [];

  @override
  List<String> get warnings => _warnings;

  void _emit(double f) {
    if (_progress.isClosed || f < _last) return;
    _last = f;
    _progress.add(ExportProgress(f));
  }

  Future<void> _run(
      FfmpegKitMediaEngine engine, Project project, ExportOptions options) async {
    Directory? work;
    final log = LogTail();
    var inLane = false;
    try {
      await Future<void>.delayed(Duration.zero);
      await checkSourcesExist(project);
      final fonts = await engine._fonts();
      // Sound stages this FFmpeg cannot run are left out (and said so)
      // instead of failing the whole export; see sound_filters.dart.
      final filters = await engine._filters.check();
      work = await createWorkDir();
      final cmd = buildExportCommand(
        project: project,
        outputPath: _outputPath,
        fonts: fonts,
        workDir: work.path,
        options: options,
        preset: engine.preset,
        encoder: _encoder,
        encoderPlatform: engine._platform,
        leaveOut: filters.unavailable,
      );
      final missing = filters.missingIn(cmd.filterGraph);
      if (missing.isNotEmpty) {
        throw ExportException(missingFiltersMessage(missing));
      }
      _warnings = filters.messagesFor(project);
      await writeTextFiles(cmd);
      final args = await exportArgs(cmd, work, engine._majorVersion);
      await Directory(p.dirname(_outputPath)).create(recursive: true);
      if (_cancelled) throw ExportException('Export cancelled', cancelled: true);
      _emit(0);

      await FfmpegKitMediaEngine._quiet();
      final finished = Completer<FFmpegSession>();
      final throttle = Throttle<double>(_emit);
      // Sound pictures and thumbnail strips wait while this runs.
      FfmpegKitMediaEngine.lane.exportStarted();
      inLane = true;
      final session = await FFmpegKit.executeWithArgumentsAsync(
        ['-hide_banner', '-loglevel', 'warning', ...args],
        (s) {
          if (!finished.isCompleted) finished.complete(s);
        },
        // No log callback: the lines stay with the session and are read
        // once, below, when the export failed.
        null,
        (st) {
          // Statistics time is the output position in milliseconds.
          final t = st.getTime();
          if (t > 0 && cmd.durationMs > 0) {
            final f = t / cmd.durationMs;
            throttle.add(f >= 1 ? 0.99 : f);
          }
        },
      );
      _session = session;
      if (_cancelled) await session.cancel();

      final ended = await finished.future;
      throttle.close();
      final rc = await ended.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        try {
          log.add(await ended.getAllLogsAsString(
                  FfmpegKitMediaEngine._logWaitMs) ??
              '');
        } catch (_) {}
      }
      if (_cancelled || ReturnCode.isCancel(rc)) {
        _cancelled = true;
        throw ExportException('Export cancelled', cancelled: true);
      }
      if (!ReturnCode.isSuccess(rc)) {
        throw ffmpegFailure(
            'ffmpeg failed (return code ${rc?.getValue()})', log.toString());
      }
      final out = File(_outputPath);
      if (!await out.exists() || await out.length() == 0) {
        throw ExportException('ffmpeg produced no output', log: log.toString());
      }
      _emit(1);
      _done.complete(_outputPath);
    } catch (e, st) {
      await deleteQuietly(File(_outputPath));
      if (!_done.isCompleted) {
        final ex = _cancelled
            ? ExportException('Export cancelled', cancelled: true)
            : (e is ExportException
                ? e
                : ExportException('Export failed: $e', log: '$st'));
        _done.completeError(ex);
      }
    } finally {
      if (inLane) FfmpegKitMediaEngine.lane.exportEnded();
      if (work != null) await deleteQuietly(work);
      await _progress.close();
    }
  }

  @override
  Future<void> cancel() async {
    if (_done.isCompleted) return;
    _cancelled = true;
    try {
      await _session?.cancel();
    } catch (_) {}
    try {
      await _done.future;
    } catch (_) {}
  }
}

class _KitRun implements FfmpegRunHandle {
  _KitRun(this._session, Future<FFmpegSession> ended)
      : finished = ended.then((s) async =>
            ReturnCode.isSuccess(await s.getReturnCode()));

  final FFmpegSession _session;

  @override
  final Future<bool> finished;

  @override
  Future<void> stop() => _session.cancel();
}

/// The plugin behind [KitRunner].
class _PluginPlatform implements KitPlatform {
  @override
  Future<void> quiet() async {
    await FFmpegKitConfig.init();
    FFmpegKitConfig.setLogRedirectionStrategy(
        LogRedirectionStrategy.neverPrintLogs);
    // From here on no log line of FFmpeg is sent to Dart; the native
    // session still keeps them for [KitSession.log].
    await FFmpegKitConfig.disableLogs();
  }

  @override
  Future<KitSession> start(List<String> args,
      {void Function(int timeMs)? onStatistics}) async {
    final finished = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (s) {
        if (!finished.isCompleted) finished.complete(s);
      },
      // Never a log callback.
      null,
      onStatistics == null
          ? null
          : (st) {
              // Statistics time is the output position in milliseconds.
              final t = st.getTime();
              if (t > 0) onStatistics(t.round());
            },
    );
    return _PluginSession(session, finished.future);
  }
}

class _PluginSession implements KitSession {
  _PluginSession(this._session, this._ended);
  final FFmpegSession _session;
  final Future<FFmpegSession> _ended;

  @override
  Future<bool> get finished async =>
      ReturnCode.isSuccess(await (await _ended).getReturnCode());

  @override
  Future<void> cancel() async {
    try {
      await _session.cancel();
    } catch (_) {}
  }

  @override
  Future<String> log(int waitMs) async {
    try {
      return await (await _ended).getAllLogsAsString(waitMs) ?? '';
    } catch (_) {
      return '';
    }
  }
}
