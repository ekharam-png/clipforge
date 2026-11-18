// MediaEngine backed by ffmpeg / ffprobe executables (dart:io Process).
// Used on Linux and as a desktop fallback.
//
// Pure Dart (dart:io + package:path): also usable from command-line tools.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import 'ffmpeg_command.dart';
import 'hardware_encoding.dart';
import 'media_api.dart';
import 'media_common.dart';
import 'media_jobs.dart';
import 'sound_filters.dart';
import 'processed_sound.dart' show parseProgressTimeMs;
import 'sound_align_job.dart';
import 'jump_check.dart';
import 'sound_render_job.dart';
import 'video_encoder.dart';

class ProcessMediaEngine
    implements
        MediaEngine,
        ThumbnailStripEngine,
        SilenceJobEngine,
        SoundAlignEngine,
        JumpCheckEngine {
  /// [ffmpegPath] / [ffprobePath]: executables to run. When null, a binary
  /// next to the application executable is preferred, then the PATH.
  ///
  /// Titles are drawn with font FILES: give their paths as [fonts], or a
  /// [fontResolver] that finds them when an export starts (the Flutter app
  /// passes `bundledFonts` from media_fonts.dart, which unpacks the bundled
  /// assets). With neither, projects without titles still export and
  /// projects with titles fail with an [ExportException].
  /// [thumbnailDir] overrides where thumbnails are cached.
  /// [encoderPlatform] overrides the platform the hardware encoder is
  /// chosen for (tests); by default the one this program runs on.
  ProcessMediaEngine({
    String? ffmpegPath,
    String? ffprobePath,
    FontPaths? fonts,
    FontResolver? fontResolver,
    this.thumbnailDir,
    this.preset = 'veryfast',
    EncoderPlatform? encoderPlatform,
  })  : encoderPlatform = encoderPlatform ?? currentEncoderPlatform(),
        ffmpegPath = ffmpegPath ?? _locate('ffmpeg', null),
        ffprobePath = ffprobePath ?? _locate('ffprobe', ffmpegPath),
        _fonts = fontResolver ?? (fonts == null ? null : () async => fonts);

  final String ffmpegPath;
  final String ffprobePath;
  final Directory? thumbnailDir;
  final String preset;
  final EncoderPlatform encoderPlatform;
  final FontResolver? _fonts;

  /// The hardware encoder of this ffmpeg, found once per program run.
  late final HardwareEncoders _encoders = HardwareEncoders.shared(
      'process|$ffmpegPath|${encoderPlatform.name}',
      () => HardwareEncoders(
            platform: encoderPlatform,
            listEncoders: _listEncoders,
            run: _ffmpegWithin(const Duration(seconds: 20)),
          ));

  /// The filters of this ffmpeg, asked once per program run.
  late final FilterSupport _filters = FilterSupport.shared(
      'process|$ffmpegPath', () => FilterSupport(_listFilters));

  Future<String?> _listFilters() async {
    final r = await Process.run(ffmpegPath, const ['-hide_banner', '-filters'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    return r.exitCode == 0 ? '${r.stdout}' : null;
  }

  Future<String?> _listEncoders() async {
    final r = await Process.run(ffmpegPath, const ['-hide_banner', '-encoders'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    return r.exitCode == 0 ? '${r.stdout}' : null;
  }

  /// Runs ffmpeg like [_ffmpeg], but kills it after [limit] (a test encode
  /// on a broken driver must not hang the export).
  FfmpegRunner _ffmpegWithin(Duration limit) => (args) async {
        final Process proc;
        try {
          proc = await Process.start(
              ffmpegPath, ['-hide_banner', '-nostdin', ...args]);
        } on ProcessException catch (e) {
          return FfmpegRun(false, '$e');
        }
        final err = StringBuffer();
        final errDone = proc.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(err.write)
            .asFuture<void>();
        proc.stdout.drain<void>().ignore();
        final code = await proc.exitCode.timeout(limit, onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        });
        await errDone.timeout(const Duration(seconds: 2), onTimeout: () {});
        return FfmpegRun(code == 0, err.toString());
      };

  @override
  Future<bool> hasHardwareEncoder() => _encoders.available();

  @override
  Future<VideoEncoder?> graphicsCardEncoder() => _encoders.current();

  static String _locate(String name, String? sibling) {
    final exe = Platform.isWindows ? '$name.exe' : name;
    final dirs = <String>[
      if (sibling != null && p.dirname(sibling) != '.') p.dirname(sibling),
      p.dirname(Platform.resolvedExecutable),
    ];
    for (final d in dirs) {
      final candidate = p.join(d, exe);
      if (File(candidate).existsSync()) return candidate;
    }
    return name; // resolved through PATH by the OS
  }

  Future<int?>? _major;

  /// Major version of the ffmpeg executable (asked once); null when it
  /// cannot be told.
  Future<int?> majorVersion() => _major ??= () async {
        try {
          final r = await Process.run(ffmpegPath, const ['-hide_banner', '-version'],
              stdoutEncoding: utf8, stderrEncoding: utf8);
          return ffmpegMajorVersion('${r.stdout}');
        } catch (_) {
          return null;
        }
      }();

  /// True when the ffmpeg executable can be started.
  Future<bool> isAvailable() async {
    try {
      final r = await Process.run(ffmpegPath, const ['-hide_banner', '-version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MediaInfo> probe(String path) async {
    final ProcessResult r;
    try {
      r = await Process.run(ffprobePath, buildProbeCommand(path),
          stdoutEncoding: utf8, stderrEncoding: utf8);
    } on ProcessException catch (e) {
      throw ExportException('Cannot start ffprobe ($ffprobePath): ${e.message}');
    }
    if (r.exitCode != 0) {
      throw ExportException('Cannot read media file: $path', log: '${r.stderr}');
    }
    final Object? json;
    try {
      json = jsonDecode(r.stdout as String);
    } on FormatException catch (e) {
      throw ExportException('Unexpected ffprobe output for $path', log: '$e');
    }
    if (json is! Map) {
      throw ExportException('Unexpected ffprobe output for $path');
    }
    return parseProbeJson(json);
  }

  @override
  Future<String> thumbnail(String path,
      {int timeMs = 0, int maxHeight = 160}) async {
    final out = await thumbnailPathFor(path, timeMs, maxHeight,
        cacheDir: thumbnailDir);
    final file = File(out);
    if (await file.exists() && await file.length() > 0) return out;

    Future<ProcessResult> run(int t) => Process.run(
        ffmpegPath,
        [
          '-hide_banner', '-loglevel', 'error', '-nostdin',
          ...buildThumbnailCommand(
              path: path, outputPath: out, timeMs: t, maxHeight: maxHeight),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);

    ProcessResult r;
    try {
      r = await run(timeMs);
      // Seeking past the end produces no frame: fall back to the start.
      if ((r.exitCode != 0 || !await file.exists() || await file.length() == 0) &&
          timeMs > 0) {
        r = await run(0);
      }
    } on ProcessException catch (e) {
      throw ExportException('Cannot start ffmpeg ($ffmpegPath): ${e.message}');
    }
    if (r.exitCode != 0 || !await file.exists() || await file.length() == 0) {
      await deleteQuietly(file);
      throw ExportException('Cannot create a thumbnail of $path',
          log: '${r.stderr}');
    }
    return out;
  }

  Future<FfmpegRun> _ffmpeg(List<String> args) async {
    try {
      final r = await Process.run(
          ffmpegPath, ['-hide_banner', '-nostdin', ...args],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      return FfmpegRun(r.exitCode == 0, '${r.stderr}');
    } on ProcessException catch (e) {
      throw ExportException('Cannot start ffmpeg ($ffmpegPath): ${e.message}');
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
  Future<List<double?>> jumpScores(
          String path, List<({int beforeMs, int afterMs})> cuts) =>
      jumpScoresWith(_ffmpeg, path, cuts);

  @override
  ExportJob renderClipSound(Clip clip, String outputPath) => SoundRenderJob(
        clip,
        outputPath,
        leaveOut: () async => (await _filters.check()).unavailable,
        launch: (args, {required onTimeMs, required onLog}) async {
          final Process proc;
          try {
            proc = await Process.start(ffmpegPath, [
              '-hide_banner', '-loglevel', 'error', '-nostdin', '-nostats',
              '-progress', 'pipe:1',
              ...args,
            ]);
          } on ProcessException catch (e) {
            throw ExportException(
                'Cannot start ffmpeg ($ffmpegPath): ${e.message}');
          }
          final outDone = proc.stdout
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())
              .listen((line) {
            final ms = parseProgressTimeMs(line);
            if (ms != null) onTimeMs(ms);
          }).asFuture<void>();
          final errDone = proc.stderr
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(onLog)
              .asFuture<void>();
          return _ProcessRun(proc, outDone, errDone);
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

  /// Runs ffmpeg reporting its position (`-progress`) as it goes; killed
  /// when [cancel] completes. The whole log is kept (silencedetect writes
  /// its findings there).
  Future<FfmpegRun> _ffmpegStreaming(List<String> args,
      void Function(int timeMs) onTimeMs, Future<void> cancel) async {
    final Process proc;
    try {
      proc = await Process.start(ffmpegPath, [
        '-hide_banner', '-nostdin', '-nostats', '-progress', 'pipe:1',
        ...args,
      ]);
    } on ProcessException catch (e) {
      throw ExportException('Cannot start ffmpeg ($ffmpegPath): ${e.message}');
    }
    var finished = false;
    unawaited(cancel.then((_) {
      if (!finished) proc.kill(ProcessSignal.sigkill);
    }));
    final err = StringBuffer();
    final errDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(err.write)
        .asFuture<void>();
    final outDone = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      final us = line.startsWith('out_time_us=')
          ? int.tryParse(line.substring(12))
          : null;
      if (us != null && us >= 0) onTimeMs(us ~/ 1000);
    }).asFuture<void>();
    final code = await proc.exitCode;
    finished = true;
    await Future.wait([outDone, errDone]).catchError((Object _) => <void>[]);
    return FfmpegRun(code == 0, err.toString());
  }

  @override
  ExportJob export(Project project, String outputPath,
      {ExportOptions options = const ExportOptions()}) {
    return EncoderFallbackJob(
      encoders: _encoders,
      options: options,
      verify: outputCheck(probe, project.durationMs),
      start: (encoder) {
        final job = _ProcessExportJob(outputPath, encoder);
        job._run(this, project, options);
        return job;
      },
    );
  }
}

class _ProcessExportJob implements ExportJob {
  _ProcessExportJob(this._outputPath, this._encoder) {
    // The error is still delivered to everyone awaiting [done]; this only
    // stops it from being reported as unhandled when nobody listens yet.
    _done.future.ignore();
  }

  final String _outputPath;
  final VideoEncoder _encoder;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  Process? _process;
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
    if (_progress.isClosed) return;
    if (f < _last) return; // keep it monotonic
    _last = f;
    _progress.add(ExportProgress(f));
  }

  Future<void> _run(
      ProcessMediaEngine engine, Project project, ExportOptions options) async {
    Directory? work;
    final log = LogTail();
    try {
      // Let the caller attach listeners before anything happens.
      await Future<void>.delayed(Duration.zero);
      await checkSourcesExist(project);
      if (options.format == ExportFormat.mp3 &&
          !((await engine._listEncoders()) ?? '').contains('libmp3lame')) {
        throw ExportException('This FFmpeg cannot make MP3 files (it has no '
            '"libmp3lame" encoder). Export the sound as M4A instead.');
      }
      final fonts = await fontsFor(project, engine._fonts);
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
        encoderPlatform: engine.encoderPlatform,
        leaveOut: filters.unavailable,
      );
      final missing = filters.missingIn(cmd.filterGraph);
      if (missing.isNotEmpty) {
        throw ExportException(missingFiltersMessage(missing));
      }
      _warnings = filters.messagesFor(project);
      await writeTextFiles(cmd);
      final args = await exportArgs(cmd, work, engine.majorVersion);
      await Directory(p.dirname(_outputPath)).create(recursive: true);
      if (_cancelled) throw ExportException('Export cancelled', cancelled: true);
      _emit(0);

      final Process proc;
      try {
        proc = await Process.start(engine.ffmpegPath, [
          '-hide_banner', '-loglevel', 'error', '-nostdin', '-nostats',
          '-progress', 'pipe:1',
          ...args,
        ]);
      } on ProcessException catch (e) {
        throw ExportException(
            'Cannot start ffmpeg (${engine.ffmpegPath}): ${e.message}');
      }
      _process = proc;
      if (_cancelled) proc.kill(ProcessSignal.sigkill);

      final outDone = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        final f = parseProgressLine(line, cmd.durationMs);
        // 1.0 is only reported once the file is really finished.
        if (f != null) _emit(f >= 1 ? 0.99 : f);
      }).asFuture<void>();
      final errDone = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(log.add)
          .asFuture<void>();

      final code = await proc.exitCode;
      await Future.wait([outDone, errDone]).catchError((Object _) => <void>[]);

      if (_cancelled) throw ExportException('Export cancelled', cancelled: true);
      if (code != 0) {
        throw ffmpegFailure('ffmpeg failed (exit code $code)', log.toString());
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
    _process?.kill(ProcessSignal.sigkill);
    try {
      await _done.future;
    } catch (_) {}
  }
}

class _ProcessRun implements FfmpegRunHandle {
  _ProcessRun(this._proc, Future<void> out, Future<void> err)
      : finished = _finish(_proc, out, err);

  static Future<bool> _finish(
      Process proc, Future<void> out, Future<void> err) async {
    final code = await proc.exitCode;
    await Future.wait([out, err]).catchError((Object _) => <void>[]);
    return code == 0;
  }

  final Process _proc;

  @override
  final Future<bool> finished;

  @override
  Future<void> stop() async => _proc.kill(ProcessSignal.sigkill);
}
