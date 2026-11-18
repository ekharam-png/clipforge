// Real exports through ProcessMediaEngine with the system ffmpeg.
// Skipped (with a message) when ffmpeg / ffprobe are not installed.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {}, skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(setUpMedia);
  tearDownAll(tearDownMedia);

  group('probe', () {
    test('landscape video with audio', () async {
      final i = await engine.probe(f('land.mp4'));
      expect((i.width, i.height), (640, 360));
      expect(i.durationMs, closeTo(2000, 60));
      expect(i.hasVideo, isTrue);
      expect(i.hasAudio, isTrue);
    });
    test('portrait video without audio', () async {
      final i = await engine.probe(f('port.mp4'));
      expect((i.width, i.height), (360, 640));
      expect(i.durationMs, closeTo(2000, 60));
      expect(i.hasVideo, isTrue);
      expect(i.hasAudio, isFalse);
    });
    test('rotated video reports display size', () async {
      // Sanity: the coded size really is landscape.
      final raw = ffprobe(f('rot.mp4'));
      expect((raw.width, raw.height), (640, 360));
      final i = await engine.probe(f('rot.mp4'));
      expect((i.width, i.height), (360, 640));
      expect(i.hasAudio, isTrue);
    });
    test('photos have duration 0', () async {
      var i = await engine.probe(f('photo.png'));
      expect((i.width, i.height, i.durationMs), (400, 300, 0));
      expect(i.hasVideo, isTrue);
      expect(i.hasAudio, isFalse);
      i = await engine.probe(f('big.jpg'));
      expect((i.width, i.height, i.durationMs), (1620, 1080, 0));
    });
    test('JPEG with EXIF orientation reports the size ffmpeg will decode to', () async {
      // Minimal EXIF block: Orientation = 6 (rotate 90 CW), spliced into a
      // 400x200 JPEG right after the SOI marker.
      ff(['-f', 'lavfi', '-i', 'color=c=red:s=400x200', '-frames:v', '1', f('plain.jpg')]);
      final jpg = File(f('plain.jpg')).readAsBytesSync();
      const tiff = [
        0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big endian header
        0x00, 0x01, // one IFD entry
        0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, // no next IFD
      ];
      final payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
      final len = payload.length + 2;
      File(f('exif.jpg')).writeAsBytesSync(
          [0xFF, 0xD8, 0xFF, 0xE1, len >> 8, len & 0xFF, ...payload, ...jpg.skip(2)]);
      final i = await engine.probe(f('exif.jpg'));
      expect((i.width, i.height, i.durationMs), (200, 400, 0));
      // ... and an export using that size really is portrait content: no
      // bars at the top of a 200x400 canvas.
      final out = await exportAndCheck(proj([photo(ms: 400, file: 'exif.jpg', w: i.width, h: i.height)]),
          width: 200, height: 400);
      final fr = frameAt(out, 200, 200, 400);
      expect(fr.isBlack(100, 6), isFalse);
      expect(fr.isBlack(100, 394), isFalse);
    });

    test('audio only', () async {
      final i = await engine.probe(f('music.m4a'));
      expect(i.hasVideo, isFalse);
      expect(i.hasAudio, isTrue);
      expect((i.width, i.height), (0, 0));
      expect(i.durationMs, closeTo(4000, 80));
    });
    test('odd dimensions', () async {
      final i = await engine.probe(f('odd.mp4'));
      expect((i.width, i.height), (641, 361));
    });
    test('missing / broken file throws ExportException', () async {
      await expectLater(engine.probe(f('nope.mp4')), throwsA(isA<ExportException>()));
      File(f('broken.mp4')).writeAsStringSync('not a video');
      await expectLater(engine.probe(f('broken.mp4')), throwsA(isA<ExportException>()));
    });
  });

  group('thumbnail', () {
    test('video frame, scaled, cached', () async {
      final t = await engine.thumbnail(f('land.mp4'), timeMs: 1000, maxHeight: 90);
      expect(t, endsWith('.jpg'));
      final pr = ffprobe(t);
      expect((pr.width, pr.height), (160, 90));
      expect(pr.stream('video')!['codec_name'], 'mjpeg');
      final modified = File(t).lastModifiedSync();
      expect(await engine.thumbnail(f('land.mp4'), timeMs: 1000, maxHeight: 90), t);
      expect(File(t).lastModifiedSync(), modified);
      expect(await engine.thumbnail(f('land.mp4'), timeMs: 0, maxHeight: 90), isNot(t));
    });
    test('rotated video gives an upright thumbnail', () async {
      final pr = ffprobe(await engine.thumbnail(f('rot.mp4'), maxHeight: 160));
      expect((pr.width, pr.height), (90, 160));
    });
    test('photo, and no upscaling', () async {
      final pr = ffprobe(await engine.thumbnail(f('photo.png'), maxHeight: 1000));
      expect((pr.width, pr.height), (400, 300));
    });
    test('time past the end falls back to the first frame', () async {
      final t = await engine.thumbnail(f('land.mp4'), timeMs: 60000);
      expect(File(t).lengthSync(), greaterThan(0));
    });
    test('audio file throws', () async {
      await expectLater(engine.thumbnail(f('music.m4a')), throwsA(isA<ExportException>()));
    });
  });

  group('export: join with mixed orientations', () {
    for (final fit in FitMode.values) {
      test('FitMode.${fit.name}', () async {
        final project = proj([
          land(inMs: 300, outMs: 1500, fit: fit),
          port(inMs: 200, outMs: 1200, fit: fit),
          photo(ms: 800, fit: fit),
          rot(outMs: 1000, fit: fit),
        ]);
        expect(project.durationMs, 4000);
        final out = await exportAndCheck(project, width: 640, height: 360);
        // Portrait clip (t = 1.2 .. 2.2): what is at the far left?
        final fr = frameAt(out, 1700, 640, 360);
        final leftBlack = fr.isBlack(8, 180);
        final centreBlack = fr.isBlack(320, 100);
        expect(centreBlack, isFalse);
        expect(leftBlack, fit == FitMode.fit, reason: 'bars only in fit mode');
        // Rotated clip (t = 3.0 .. 4.0) must be upright => bars in fit mode.
        final fr2 = frameAt(out, 3500, 640, 360);
        expect(fr2.isBlack(8, 180), fit == FitMode.fit);
        // Tone from the first clip, silence for the audio-less clip + photo.
        expect(meanVolume(out, fromMs: 100, toMs: 1100), greaterThan(-40));
        expect(meanVolume(out, fromMs: 1400, toMs: 2900), lessThan(-70));
        expect(meanVolume(out, fromMs: 3100, toMs: 3900), greaterThan(-40));
      });
    }
  });

  group('export: canvas aspects', () {
    const expected = {
      CanvasAspect.original: (640, 360),
      CanvasAspect.portrait9x16: (360, 640),
      CanvasAspect.landscape16x9: (640, 360),
      CanvasAspect.square1x1: (360, 360),
      CanvasAspect.portrait4x5: (360, 450),
    };
    for (final aspect in CanvasAspect.values) {
      test(aspect.name, () async {
        final (w, h) = expected[aspect]!;
        final project = proj([
          land(outMs: 700, fit: FitMode.blur),
          port(outMs: 600, fit: FitMode.fill),
          photo(ms: 500, fit: FitMode.fit),
        ], aspect: aspect);
        await exportAndCheck(project, width: w, height: h);
      });
    }

    test('original follows a portrait first clip', () async {
      await exportAndCheck(proj([port(outMs: 600), land(outMs: 600)]), width: 360, height: 640);
    });
  });

  group('export: edge cases', () {
    test('single clip', () async {
      await exportAndCheck(proj([land(inMs: 500, outMs: 1300)]), width: 640, height: 360);
    });
    test('photo only', () async {
      final out = await exportAndCheck(proj([photo(ms: 1200)]), width: 400, height: 300);
      expect(meanVolume(out), lessThan(-70));
    });
    test('odd source dimensions', () async {
      final project = proj([clip('odd.mp4', 641, 361, hasAudio: false, outMs: 800), port(outMs: 500)]);
      final out = await exportAndCheck(project);
      final pr = ffprobe(out);
      expect(pr.width.isEven && pr.height.isEven, isTrue);
    });
    test('clip that claims more than the file holds still has the model duration', () async {
      // Source is 2.0 s long; the model asks for 1.5 .. 2.4.
      await exportAndCheck(proj([land(inMs: 1500, outMs: 2400), photo(ms: 500)]));
    });
    test('empty project fails with ExportException and no file', () async {
      final out = outPath();
      final job = engine.export(proj([]), out);
      await expectLater(job.done, throwsA(isA<ExportException>()));
      expect(File(out).existsSync(), isFalse);
    });
    test('missing sources are named before ffmpeg starts, and no file is left', () async {
      final out = outPath();
      final music = AudioClip(id: 'm', path: f('gone.mp3'), sourceDurationMs: 9000, startMs: 0, inMs: 0, outMs: 9000);
      final job = engine.export(
          proj([clip('nope.mp4', 640, 360), land(), clip('nope.mp4', 640, 360), photo(file: 'lost.jpg')], audio: [music]),
          out);
      Object? err;
      try {
        await job.done;
      } catch (e) {
        err = e;
      }
      expect(err, isA<ExportException>());
      expect((err as ExportException).cancelled, isFalse);
      expect(err.message, 'These files are missing: nope.mp4, lost.jpg, gone.mp3');
      expect(err.missingPaths, [f('nope.mp4'), f('lost.jpg'), f('gone.mp3')]);
      expect(File(out).existsSync(), isFalse);

      final one = engine.export(proj([land(), photo(file: 'lost.jpg')]), outPath());
      await expectLater(
          one.done,
          throwsA(isA<ExportException>()
              .having((e) => e.message, 'message', 'This file is missing: lost.jpg')
              .having((e) => e.missingPaths, 'missingPaths', [f('lost.jpg')])));
    });

    test('an unreadable source: the message says what ffmpeg could not do', () async {
      File(f('broken2.mp4')).writeAsStringSync('this is not a video at all ' * 200);
      final out = outPath();
      final job = engine.export(proj([land(), clip('broken2.mp4', 640, 360)]), out);
      Object? err;
      try {
        await job.done;
      } catch (e) {
        err = e;
      }
      expect(err, isA<ExportException>());
      err as ExportException;
      expect(err.missingPaths, isEmpty);
      expect(err.message, startsWith('ffmpeg failed (exit code '));
      expect(err.message, contains('Invalid data found when processing input'));
      expect(err.message, contains('broken2.mp4'));
      expect(err.message.length, lessThan(500));
      expect(err.log, contains('broken2.mp4'));
      expect(File(out).existsSync(), isFalse);
    });
  });

  group('export: audio', () {
    AudioClip music({int start = 0, int inMs = 0, int outMs = 4000, double vol = 1, int fi = 0, int fo = 0}) =>
        AudioClip(
            id: 'm${seq++}',
            path: f('music.m4a'),
            sourceDurationMs: 4000,
            startMs: start,
            inMs: inMs,
            outMs: outMs,
            volume: vol,
            fadeInMs: fi,
            fadeOutMs: fo);

    test('music with fades over a muted clip and a silent clip', () async {
      final project = proj([
        land(outMs: 1500, muted: true),
        port(outMs: 1500),
      ], audio: [
        music(start: 500, inMs: 1000, outMs: 3000, vol: 0.8, fi: 600, fo: 600), // 0.5 .. 2.5
      ]);
      final out = await exportAndCheck(project);
      // Before the music starts: the muted clip must be silent.
      expect(meanVolume(out, fromMs: 0, toMs: 400), lessThan(-70));
      // Middle of the music is loud, the faded edges are quieter.
      final mid = meanVolume(out, fromMs: 1200, toMs: 1800);
      expect(mid, greaterThan(-30));
      expect(meanVolume(out, fromMs: 520, toMs: 720), lessThan(mid - 6));
      expect(meanVolume(out, fromMs: 2300, toMs: 2480), lessThan(mid - 6));
      // After the music ended.
      expect(meanVolume(out, fromMs: 2600, toMs: 3000), lessThan(-70));
    });

    test('mix is not normalised: clip level is unchanged by adding music', () async {
      final alone = await exportAndCheck(proj([land(outMs: 1500)]));
      final mixed = await exportAndCheck(proj([land(outMs: 1500)], audio: [music(vol: 0.05, outMs: 1500)]));
      expect(meanVolume(mixed), closeTo(meanVolume(alone), 1.5));
    });

    test('clip volume lowers the level', () async {
      final full = await exportAndCheck(proj([land(outMs: 1000)]));
      final quiet = await exportAndCheck(proj([land(outMs: 1000, volume: 0.25)]));
      expect(meanVolume(quiet), closeTo(meanVolume(full) - 12, 1.5));
    });

    test('music longer than the video is cut at the main track end', () async {
      await exportAndCheck(proj([port(outMs: 1000)], audio: [music(start: 200), music(start: 5000)]));
    });
  });

  group('export: titles', () {
    Clip black({int ms = 2000}) => photo(ms: ms, file: 'black.png', w: 640, h: 360);
    const awkward = "It's 100% \"ok\": a\\b, [x]; %{pts}\nПривет, мир!\nשלום 'עולם'";

    test('awkward text renders, only inside its time range', () async {
      final project = proj([
        black()
      ], titles: [
        const TitleOverlay(id: 't', text: awkward, startMs: 500, endMs: 1500, fontSize: 0.08),
      ]);
      final out = await exportAndCheck(project);
      expect(frameAt(out, 200, 640, 360).countBright(), 0);
      final shown = frameAt(out, 1000, 640, 360);
      expect(shown.countBright(), greaterThan(1500));
      expect(frameAt(out, 1700, 640, 360).countBright(), 0);
      // Three lines: text is found above, at and below the centre.
      int rowBright(int y0, int y1) {
        var n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = 0; x < 640; x++) {
            final (r, g, b) = shown.at(x, y);
            if (r > 200 && g > 200 && b > 200) n++;
          }
        }
        return n;
      }

      expect(rowBright(130, 160), greaterThan(100));
      expect(rowBright(165, 195), greaterThan(100));
      expect(rowBright(200, 230), greaterThan(100));
      expect(rowBright(0, 100), 0);
      expect(rowBright(260, 360), 0);
    });

    test('position, colour, regular weight and background box', () async {
      final project = proj([
        black(ms: 1000)
      ], aspect: CanvasAspect.square1x1, titles: [
        const TitleOverlay(
            id: 't',
            text: 'Top left',
            startMs: 0,
            endMs: 1000,
            x: 0.25,
            y: 0.2,
            colorArgb: 0xFFFF0000,
            bold: false,
            background: true),
      ]);
      final out = await exportAndCheck(project, width: 360, height: 360);
      final fr = frameAt(out, 500, 360, 360);
      var red = 0, sx = 0, sy = 0;
      for (var y = 0; y < 360; y++) {
        for (var x = 0; x < 360; x++) {
          final (r, g, b) = fr.at(x, y);
          if (r > 150 && g < 80 && b < 80) {
            red++;
            sx += x;
            sy += y;
          }
        }
      }
      expect(red, greaterThan(100));
      expect(sx / red, closeTo(90, 6));
      expect(sy / red, closeTo(72, 6));
    });

    test('fonts and work dir in awkward locations', () async {
      final dir = Directory(f("fo'nt dir, [x];%1 шрифт"))..createSync();
      final weird = FontPaths(
          regular: File(fonts.regular).copySync(p.join(dir.path, 'R:1.ttf')).path,
          bold: File(fonts.bold).copySync(p.join(dir.path, "B 'b'.ttf")).path);
      final e = ProcessMediaEngine(ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe', fontResolver: () async => weird, preset: 'ultrafast');
      final project = proj([black(ms: 600)], titles: [
        const TitleOverlay(id: 'a', text: 'Bold', startMs: 0, endMs: 600, y: 0.3),
        const TitleOverlay(id: 'b', text: 'Regular', startMs: 0, endMs: 600, y: 0.7, bold: false),
      ]);
      final out = p.join(dir.path, 'вывод o\'ut.mp4');
      expect(await e.export(project, out).done, out);
      expect(frameAt(out, 300, 640, 360).countBright(), greaterThan(500));
    });
  });

  group('export: quality', () {
    test('small scales the short side to 720 with a smaller file', () async {
      final project = proj([photo(ms: 1000, file: 'big.jpg', w: 1620, h: 1080), land(outMs: 500, fit: FitMode.blur)]);
      final full = await exportAndCheck(project, width: 1620, height: 1080);
      final small = await exportAndCheck(project,
          options: const ExportOptions(quality: ExportQuality.small), width: 1080, height: 720);
      expect(File(small).lengthSync(), lessThan(File(full).lengthSync()));
    });

    test('fps option', () async {
      final out = await exportAndCheck(proj([land(outMs: 1000)]), options: const ExportOptions(fps: 24));
      expect(ffprobe(out).stream('video')!['r_frame_rate'], '24/1');
    });
  });

  group('export: job control', () {
    test('progress is monotonic and reaches 1.0', () async {
      final project = proj([land(outMs: 2000), port(outMs: 2000, fit: FitMode.blur), photo(ms: 2000)]);
      final out = outPath();
      final job = engine.export(project, out);
      final seen = <double>[];
      final sub = job.progress.listen((e) => seen.add(e.fraction));
      await job.done;
      await sub.asFuture<void>().timeout(const Duration(seconds: 5));
      expect(seen, isNotEmpty);
      expect(seen.first, 0);
      expect(seen.last, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
        expect(seen[i], inInclusiveRange(0, 1));
      }
      expect(seen.any((v) => v > 0 && v < 1), isTrue, reason: 'intermediate progress: $seen');
    });

    test('cancel stops ffmpeg, throws cancelled and removes the partial file', () async {
      // Long enough that it cannot finish before we cancel.
      final project = proj([photo(ms: 600000, file: 'big.jpg', w: 1620, h: 1080, fit: FitMode.blur)]);
      final out = outPath();
      final job = engine.export(project, out);
      final firstRealProgress = job.progress.firstWhere((e) => e.fraction > 0);
      await firstRealProgress.timeout(const Duration(seconds: 30));
      expect(File(out).existsSync(), isTrue, reason: 'partial file while running');
      final sw = Stopwatch()..start();
      await job.cancel();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      Object? err;
      try {
        await job.done;
      } catch (e) {
        err = e;
      }
      expect(err, isA<ExportException>());
      expect((err as ExportException).cancelled, isTrue);
      expect(File(out).existsSync(), isFalse);
      // Idempotent.
      await job.cancel();
    });

    test('cancel right after start', () async {
      final out = outPath();
      final job = engine.export(proj([land(outMs: 2000)]), out);
      await job.cancel();
      await expectLater(job.done, throwsA(isA<ExportException>().having((e) => e.cancelled, 'cancelled', isTrue)));
      expect(File(out).existsSync(), isFalse);
    });
  });
}
