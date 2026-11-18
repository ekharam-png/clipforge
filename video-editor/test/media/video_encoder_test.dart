import 'dart:async';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/hardware_encoding.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_common.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:clipforge/media/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart' as media;

String? after(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

List<String> argsFor(VideoEncoder e,
        {EncoderPlatform platform = EncoderPlatform.windows,
        ExportQuality quality = ExportQuality.full,
        int width = 1920,
        int height = 1080,
        int fps = 30}) =>
    videoEncoderArgs(e,
        platform: platform,
        quality: quality,
        width: width,
        height: height,
        fps: fps);

/// An export job that the test finishes by hand.
class _Job implements ExportJob {
  _Job(this.encoder);
  final VideoEncoder encoder;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  bool cancelled = false;

  void report(double f) => _progress.add(ExportProgress(f));
  void finish(String path) => _done.complete(path);
  void fail({String? log = 'ffmpeg log'}) =>
      _done.completeError(ExportException('ffmpeg failed', log: log));

  @override
  Stream<ExportProgress> get progress => _progress.stream;
  @override
  Future<String> get done => _done.future;
  @override
  VideoEncoder? get videoEncoder => encoder;
  @override
  List<String> get warnings => const [];
  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_done.isCompleted) {
      _done.completeError(ExportException('Export cancelled', cancelled: true));
    }
  }
}

HardwareEncoders encodersThat({
  EncoderPlatform platform = EncoderPlatform.macosAppleSilicon,
  String? listing,
  bool Function(List<String> args)? works,
  List<List<String>>? ran,
}) =>
    HardwareEncoders(
      platform: platform,
      listEncoders: () async => listing,
      run: (args) async {
        ran?.add(args);
        return FfmpegRun(works?.call(args) ?? true, '');
      },
    );

const _macListing = '''
Encoders:
 V..... = Video
 ------
 V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC (codec h264)
 V....D h264_videotoolbox    VideoToolbox H.264 Encoder (codec h264)
 A....D aac                  AAC (Advanced Audio Coding)
''';

void main() {
  group('encoderCandidates (pure choice)', () {
    test('per platform: hardware first, libx264 always last', () {
      final all = {
        'libx264', 'h264_videotoolbox', 'h264_nvenc', 'h264_qsv', 'h264_amf',
        'h264_mf', 'h264_mediacodec',
      };
      List<VideoEncoder> c(EncoderPlatform p) =>
          encoderCandidates(platform: p, available: all);
      expect(c(EncoderPlatform.macosAppleSilicon),
          [VideoEncoder.videotoolbox, VideoEncoder.libx264]);
      expect(c(EncoderPlatform.macosIntel),
          [VideoEncoder.videotoolbox, VideoEncoder.libx264]);
      expect(c(EncoderPlatform.windows), [
        VideoEncoder.nvenc,
        VideoEncoder.qsv,
        VideoEncoder.amf,
        VideoEncoder.mediaFoundation,
        VideoEncoder.libx264,
      ]);
      expect(c(EncoderPlatform.android),
          [VideoEncoder.mediacodec, VideoEncoder.libx264]);
      expect(c(EncoderPlatform.linux),
          [VideoEncoder.nvenc, VideoEncoder.qsv, VideoEncoder.libx264]);
      expect(c(EncoderPlatform.other), [VideoEncoder.libx264]);
    });

    test('only encoders FFmpeg has; the bundled Windows build has only h264_mf',
        () {
      expect(
          encoderCandidates(
              platform: EncoderPlatform.windows,
              available: {'libx264', 'h264_mf'}),
          [VideoEncoder.mediaFoundation, VideoEncoder.libx264]);
      expect(
          encoderCandidates(
              platform: EncoderPlatform.macosAppleSilicon,
              available: {'libx264'}),
          [VideoEncoder.libx264]);
    });

    test('unknown list: every candidate is tried; hardware off: only libx264',
        () {
      expect(
          encoderCandidates(platform: EncoderPlatform.android, available: null),
          [VideoEncoder.mediacodec, VideoEncoder.libx264]);
      expect(
          encoderCandidates(
              platform: EncoderPlatform.windows,
              available: null,
              hardware: false),
          [VideoEncoder.libx264]);
    });

    test('parseEncoderList reads video encoders only', () {
      expect(parseEncoderList(_macListing), {'libx264', 'h264_videotoolbox'});
      expect(parseEncoderList(''), isEmpty);
    });
  });

  group('videoEncoderArgs', () {
    test('libx264 keeps the CRF 21 / 27 settings', () {
      final full = argsFor(VideoEncoder.libx264);
      expect(full, [
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '21',
        '-profile:v', 'high', '-pix_fmt', 'yuv420p',
      ]);
      final small = argsFor(VideoEncoder.libx264, quality: ExportQuality.small);
      expect(after(small, '-crf'), '27');
      expect(after(small, '-maxrate'), '2500k');
      expect(after(small, '-bufsize'), '5000k');
    });

    test('VideoToolbox: constant quality on Apple silicon, bitrate on Intel',
        () {
      final arm = argsFor(VideoEncoder.videotoolbox,
          platform: EncoderPlatform.macosAppleSilicon);
      expect(after(arm, '-c:v'), 'h264_videotoolbox');
      expect(after(arm, '-q:v'), '65');
      expect(arm, isNot(contains('-b:v')));
      expect(after(arm, '-allow_sw'), '0');
      expect(after(arm, '-profile:v'), 'high');
      expect(after(arm, '-pix_fmt'), 'nv12');
      final armSmall = argsFor(VideoEncoder.videotoolbox,
          platform: EncoderPlatform.macosAppleSilicon,
          quality: ExportQuality.small,
          width: 1280,
          height: 720);
      expect(after(armSmall, '-q:v'), '55');
      expect(after(armSmall, '-maxrate'), '2500k');

      final intel = argsFor(VideoEncoder.videotoolbox,
          platform: EncoderPlatform.macosIntel);
      expect(intel, isNot(contains('-q:v')));
      expect(after(intel, '-b:v'), '7465k');
      expect(after(intel, '-maxrate'), '14930k');
    });

    test('every hardware encoder: 8-bit 4:2:0 (nv12), High profile', () {
      for (final e in VideoEncoder.values.where((e) => e.hardware)) {
        for (final q in ExportQuality.values) {
          final a = argsFor(e, quality: q);
          expect(after(a, '-c:v'), e.ffmpegName);
          expect(after(a, '-pix_fmt'), 'nv12', reason: e.name);
          expect(after(a, '-profile:v'),
              e == VideoEncoder.mediaFoundation ? '100' : 'high',
              reason: e.name);
          if (q == ExportQuality.small) {
            // Small files are capped for messaging apps by every encoder.
            expect(after(a, '-maxrate'), '2500k', reason: e.name);
          }
        }
      }
    });

    test('vendor encoders use constant quality, others a bitrate', () {
      final nv = argsFor(VideoEncoder.nvenc);
      expect(after(nv, '-rc'), 'vbr');
      expect(after(nv, '-cq'), '23');
      expect(after(nv, '-b:v'), '0');
      expect(after(argsFor(VideoEncoder.qsv), '-global_quality'), '23');
      expect(after(argsFor(VideoEncoder.mediaFoundation), '-hw_encoding'), '1');
      expect(after(argsFor(VideoEncoder.mediaFoundation), '-rate_control'),
          'pc_vbr');
      expect(after(argsFor(VideoEncoder.mediacodec), '-bitrate_mode'), 'vbr');
      expect(after(argsFor(VideoEncoder.amf), '-rc'), 'vbr_peak');
    });

    test('bitrate grows with picture size and frame rate, within limits', () {
      int kbps(int w, int h, int fps, [ExportQuality q = ExportQuality.full]) =>
          hardwareBitrateKbps(width: w, height: h, fps: fps, quality: q);
      expect(kbps(1920, 1080, 30), 7465);
      expect(kbps(1080, 1920, 60), 14930);
      expect(kbps(3840, 2160, 30), 29860);
      expect(kbps(320, 240, 30), 1500);
      expect(kbps(7680, 4320, 120), 60000);
      expect(kbps(1280, 720, 30, ExportQuality.small), 2000);
    });

    test('the export command carries the chosen encoder', () {
      final p = media.proj([
        Clip(
            id: 'a',
            type: ClipType.video,
            path: '/m/a.mp4',
            sourceDurationMs: 1000,
            inMs: 0,
            outMs: 1000,
            width: 1920,
            height: 1080,
            hasAudio: true),
      ]);
      final c = buildExportCommand(
        project: p,
        outputPath: '/out/o.mp4',
        fonts: const FontPaths(regular: '', bold: ''),
        workDir: '/tmp/w',
        encoder: VideoEncoder.videotoolbox,
        encoderPlatform: EncoderPlatform.macosAppleSilicon,
      );
      expect(after(c.args, '-c:v'), 'h264_videotoolbox');
      expect(after(c.args, '-q:v'), '65');
      expect(c.args, isNot(contains('-crf')));
      // Range, audio and faststart stay the same for every encoder.
      expect(after(c.args, '-color_range'), 'tv');
      expect(after(c.args, '-c:a'), 'aac');
      expect(after(c.args, '-movflags'), '+faststart');
      final plain = buildExportCommand(
        project: p,
        outputPath: '/out/o.mp4',
        fonts: const FontPaths(regular: '', bold: ''),
        workDir: '/tmp/w',
      );
      expect(after(plain.args, '-c:v'), 'libx264');
    });
  });

  group('HardwareEncoders (detection, cached)', () {
    test('tries the listed candidate once and remembers it', () async {
      final ran = <List<String>>[];
      final h = encodersThat(listing: _macListing, ran: ran);
      expect(await h.detect(), VideoEncoder.videotoolbox);
      expect(await h.available(), isTrue);
      expect(await h.choose(hardware: true), VideoEncoder.videotoolbox);
      expect(await h.choose(hardware: false), VideoEncoder.libx264);
      expect(ran, hasLength(1));
      expect(after(ran.single, '-c:v'), 'h264_videotoolbox');
      expect(ran.single.last, '-');
    });

    test('a listed encoder that fails its test is not used', () async {
      final h = encodersThat(listing: _macListing, works: (_) => false);
      expect(await h.detect(), isNull);
      expect(await h.available(), isFalse);
      expect(await h.choose(hardware: true), VideoEncoder.libx264);
    });

    test('Windows: first working one in order; unreadable list tries all',
        () async {
      final ran = <String>[];
      final h = encodersThat(
          platform: EncoderPlatform.windows,
          listing: null,
          works: (a) {
            ran.add(after(a, '-c:v')!);
            return after(a, '-c:v') == 'h264_mf';
          });
      expect(await h.detect(), VideoEncoder.mediaFoundation);
      expect(ran, ['h264_nvenc', 'h264_qsv', 'h264_amf', 'h264_mf']);
    });

    test('a test encode that hangs counts as failed', () async {
      final h = HardwareEncoders(
        platform: EncoderPlatform.android,
        listEncoders: () async => null,
        run: (_) => Completer<FfmpegRun>().future,
        testTimeout: const Duration(milliseconds: 20),
      );
      expect(await h.detect(), isNull);
    });

    test('markFailed turns the graphics card off for the rest of the run',
        () async {
      final h = encodersThat(listing: _macListing);
      h.markFailed(VideoEncoder.videotoolbox);
      expect(await h.available(), isFalse);
      expect(await h.choose(hardware: true), VideoEncoder.libx264);
    });
  });

  group('EncoderFallbackJob', () {
    late List<_Job> started;
    ExportJob Function(VideoEncoder) starter() => (e) {
          final j = _Job(e);
          started.add(j);
          return j;
        };
    setUp(() => started = []);

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('uses the hardware encoder and reports it', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h, options: const ExportOptions(), start: starter());
      final seen = <double>[];
      job.progress.listen((p) => seen.add(p.fraction));
      while (started.isEmpty) {
        await settle();
      }
      expect(started.single.encoder, VideoEncoder.videotoolbox);
      started.single.report(0.5);
      started.single.finish('/out/a.mp4');
      expect(await job.done, '/out/a.mp4');
      expect(job.videoEncoder, VideoEncoder.videotoolbox);
      expect(seen, [0.5]);
    });

    test('a failed hardware export is redone once with libx264 and the card '
        'is not used again', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h, options: const ExportOptions(), start: starter());
      while (started.isEmpty) {
        await settle();
      }
      started.first.fail();
      while (started.length < 2) {
        await settle();
      }
      expect(started[1].encoder, VideoEncoder.libx264);
      started[1].finish('/out/a.mp4');
      expect(await job.done, '/out/a.mp4');
      expect(job.videoEncoder, VideoEncoder.libx264);
      expect(await h.available(), isFalse);
      expect(await h.choose(hardware: true), VideoEncoder.libx264);
    });

    test('when the processor fails too, its error is reported and the card '
        'stays', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h, options: const ExportOptions(), start: starter());
      while (started.isEmpty) {
        await settle();
      }
      started.first.fail();
      while (started.length < 2) {
        await settle();
      }
      started[1].fail(log: 'disk full');
      await expectLater(job.done, throwsA(isA<ExportException>()
          .having((e) => e.log, 'log', 'disk full')));
      expect(await h.available(), isTrue);
    });

    test('an incomplete hardware file is deleted and redone', () async {
      final dir = Directory.systemTemp.createTempSync('cf_fallback_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File('${dir.path}/a.mp4')..writeAsStringSync('x');
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h,
          options: const ExportOptions(),
          start: starter(),
          verify: (path) async => started.length > 1);
      while (started.isEmpty) {
        await settle();
      }
      started.first.finish(bad.path);
      while (started.length < 2) {
        await settle();
      }
      expect(bad.existsSync(), isFalse);
      expect(started[1].encoder, VideoEncoder.libx264);
      started[1].finish(bad.path);
      expect(await job.done, bad.path);
      expect(job.videoEncoder, VideoEncoder.libx264);
    });

    test('no retry for failures that are not the encoder\'s', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h, options: const ExportOptions(), start: starter());
      while (started.isEmpty) {
        await settle();
      }
      started.first.fail(log: null); // e.g. missing files, no ffmpeg run
      await expectLater(job.done, throwsA(isA<ExportException>()));
      expect(started, hasLength(1));
    });

    test('cancel stops without a retry', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h, options: const ExportOptions(), start: starter());
      while (started.isEmpty) {
        await settle();
      }
      await job.cancel();
      await expectLater(job.done,
          throwsA(isA<ExportException>().having((e) => e.cancelled, 'c', true)));
      expect(started, hasLength(1));
      expect(started.single.cancelled, isTrue);
    });

    test('hardware off: straight to libx264', () async {
      final h = encodersThat(listing: _macListing);
      final job = EncoderFallbackJob(
          encoders: h,
          options: const ExportOptions(useHardwareEncoder: false),
          start: starter());
      while (started.isEmpty) {
        await settle();
      }
      expect(started.single.encoder, VideoEncoder.libx264);
      started.single.finish('/o.mp4');
      await job.done;
      expect(job.videoEncoder, VideoEncoder.libx264);
    });
  });

  group('with the system ffmpeg', () {
    setUpAll(() {
      if (media.ffmpegOk) media.setUpMedia();
    });
    tearDownAll(() {
      if (media.ffmpegOk) media.tearDownMedia();
    });

    test('Linux: the candidates are checked for real and the export falls '
        'back cleanly when they do not work', () async {
      final engine = ProcessMediaEngine(
          fonts: media.fonts, encoderPlatform: EncoderPlatform.linux);
      final hardware = await engine.hasHardwareEncoder();
      final p = media.proj([media.land(outMs: 1000)]);
      final out = media.outPath();
      final job = engine.export(p, out);
      await job.done;
      expect(File(out).existsSync(), isTrue);
      // Without a usable NVIDIA / Intel encoder (as in the build container)
      // the processor made it; with one, the graphics card did.
      expect(job.videoEncoder!.hardware, hardware);
      final pr = media.ffprobe(out);
      expect(pr.stream('video')!['codec_name'], 'h264');
      expect(pr.stream('video')!['pix_fmt'], 'yuv420p');
    }, skip: media.ffmpegOk ? false : 'ffmpeg not installed');

    test('the test encode is valid ffmpeg (libx264 passes it)', () async {
      final r = await Process.run('ffmpeg', [
        '-hide_banner', '-nostdin',
        ...encoderTestArgs(VideoEncoder.libx264, EncoderPlatform.linux),
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }, skip: media.ffmpegOk ? false : 'ffmpeg not installed');
  });
}
