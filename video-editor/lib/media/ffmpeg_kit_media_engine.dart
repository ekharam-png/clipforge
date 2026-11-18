// MediaEngine backed by the ffmpeg_kit_flutter_new plugin (FFmpeg linked
// into the app). Used on Android, iOS, macOS and Windows.

import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import 'ffmpeg_command.dart';
import 'hardware_encoding.dart';
import 'media_api.dart';
import 'media_common.dart';
import 'media_jobs.dart';
import 'sound_filters.dart';
import 'sound_align_job.dart';
import 'jump_check.dart';
import 'sound_render_job.dart';
import 'media_fonts.dart';
import 'video_encoder.dart';

class FfmpegKitMediaEngine
    implements
        MediaEngine,
        ThumbnailStripEngine,
        SilenceJobEngine,
        SoundAlignEngine,
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
            run: _ffmpeg,
          ));

  /// The filters of the FFmpeg in the app, asked once per run.
  late final FilterSupport _filters =
      FilterSupport.shared('ffmpeg-kit', () => FilterSupport(_listFilters));

  /// FFmpegKit prints the `-filters` table through its log, like
  /// `-encoders`.
  Future<String?> _listFilters() async {
    final session =
        await FFmpegKit.executeWithArguments(const ['-hide_banner', '-filters']);
    return session.getAllLogsAsString();
  }

  /// FFmpegKit prints the `-encoders` table through its log.
  Future<String?> _listEncoders() async {
    final session =
        await FFmpegKit.executeWithArguments(const ['-hide_banner', '-encoders']);
    return session.getAllLogsAsString();
  }

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
    // Our own arguments also ask for the first frame (EXIF orientation of
    // photos); fall back to the plugin's stock command if that yields nothing.
    var session = await FFprobeKit.getMediaInformationFromCommandArguments(
        buildProbeCommand(path));
    var props = session.getMediaInformation()?.getAllProperties();
    if (props == null) {
      session = await FFprobeKit.getMediaInformation(path);
      props = session.getMediaInformation()?.getAllProperties();
    }
    if (props == null) {
      String? log;
      try {
        log = await session.getAllLogsAsString();
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

    Future<FFmpegSession> run(int t) => FFmpegKit.executeWithArguments([
          '-hide_banner', '-loglevel', 'error',
          ...buildThumbnailCommand(
              path: path, outputPath: out, timeMs: t, maxHeight: maxHeight),
        ]);
    Future<bool> ok(FFmpegSession s) async =>
        ReturnCode.isSuccess(await s.getReturnCode()) &&
        await file.exists() &&
        await file.length() > 0;

    var session = await run(timeMs);
    if (!await ok(session) && timeMs > 0) session = await run(0);
    if (!await ok(session)) {
      await deleteQuietly(file);
      String? log;
      try {
        log = await session.getAllLogsAsString();
      } catch (_) {}
      throw ExportException('Cannot create a thumbnail of $path', log: log);
    }
    return out;
  }

  Future<FfmpegRun> _ffmpeg(List<String> args) async {
    final session =
        await FFmpegKit.executeWithArguments(['-hide_banner', ...args]);
    var log = '';
    try {
      log = await session.getAllLogsAsString() ?? '';
    } catch (_) {}
    return FfmpegRun(ReturnCode.isSuccess(await session.getReturnCode()), log);
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
  Future<List<double?>> jumpScores(
          String path, List<({int beforeMs, int afterMs})> cuts) =>
      jumpScoresWith(_ffmpeg, path, cuts);

  @override
  ExportJob renderClipSound(Clip clip, String outputPath) => SoundRenderJob(
        clip,
        outputPath,
        leaveOut: () async => (await _filters.check()).unavailable,
        launch: (args, {required onTimeMs, required onLog}) async {
          final finished = Completer<FFmpegSession>();
          final session = await FFmpegKit.executeWithArgumentsAsync(
            ['-hide_banner', '-loglevel', 'warning', ...args],
            (s) {
              if (!finished.isCompleted) finished.complete(s);
            },
            (l) => onLog(l.getMessage()),
            // Statistics time is the output position in milliseconds.
            (st) => onTimeMs(st.getTime().round()),
          );
          return _KitRun(session, finished.future);
        },
      );

  @override
  Future<ThumbnailStrip> thumbnailStrip(String path,
          {int durationMs = 0, int height = kStripFrameHeight}) =>
      thumbnailStripWith(_ffmpeg, probe, path,
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

  /// Runs FFmpeg in the background, reporting its position through the
  /// statistics callback; the session is cancelled when [cancel]
  /// completes. No `-nostats`: FFmpegKit's statistics come from the same
  /// report that option turns off.
  Future<FfmpegRun> _ffmpegStreaming(List<String> args,
      void Function(int timeMs) onTimeMs, Future<void> cancel) async {
    final log = StringBuffer();
    final finished = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      ['-hide_banner', ...args],
      (s) {
        if (!finished.isCompleted) finished.complete(s);
      },
      (l) => log.write(l.getMessage()),
      (st) {
        final t = st.getTime();
        if (t > 0) onTimeMs(t.round());
      },
    );
    unawaited(cancel.then((_) async {
      if (finished.isCompleted) return;
      try {
        await session.cancel();
      } catch (_) {}
    }));
    final ended = await finished.future;
    var text = log.toString();
    if (!text.contains('silence_')) {
      // The log callback can miss lines that arrive after completion.
      try {
        text = await ended.getAllLogsAsString() ?? text;
      } catch (_) {}
    }
    return FfmpegRun(ReturnCode.isSuccess(await ended.getReturnCode()), text);
  }

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

      final finished = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        ['-hide_banner', '-loglevel', 'warning', ...args],
        (s) {
          if (!finished.isCompleted) finished.complete(s);
        },
        (l) => log.add(l.getMessage()),
        (st) {
          // Statistics time is the output position in milliseconds.
          final t = st.getTime();
          if (t > 0 && cmd.durationMs > 0) {
            final f = t / cmd.durationMs;
            _emit(f >= 1 ? 0.99 : f);
          }
        },
      );
      _session = session;
      if (_cancelled) await session.cancel();

      final ended = await finished.future;
      final rc = await ended.getReturnCode();
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
