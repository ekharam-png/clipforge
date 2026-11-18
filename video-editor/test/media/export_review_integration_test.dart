// Real exports for the product-review fixes: title layout on portrait
// canvases, music that outlasts the video, capped canvas for big photos,
// many pieces of one file through a single input, 60 fps, source frame
// rate in probe. System ffmpeg; skipped when it is not installed.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Only the sound around [hz].
String band(int hz) => 'bandpass=f=$hz:width_type=q:w=20,bandpass=f=$hz:width_type=q:w=20,';

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {}, skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // Mid grey: a title box shows as a darker rectangle, text as white.
    ff(['-f', 'lavfi', '-i', 'color=c=0x808080:s=360x640', '-frames:v', '1', f('grey_tall.png')]);
    ff(['-f', 'lavfi', '-i', 'color=c=0x808080:s=640x360', '-frames:v', '1', f('grey_wide.png')]);
    ff(['-f', 'lavfi', '-i', 'color=c=0x808080:s=1620x1080', '-frames:v', '1', f('grey_big.png')]);
    // A 12 megapixel photo.
    ff(['-f', 'lavfi', '-i', 'testsrc2=s=4000x3000', '-frames:v', '1', '-q:v', '3', f('huge.jpg')]);
    // "Speech": every 2 s the picture turns white and a 1 kHz tone sounds,
    // both for 0.5 s; black and silent in between. 24 s.
    ff([
      '-f', 'lavfi', '-i', "color=c=black:s=320x180:r=30:d=24,geq=lum='if(lt(mod(T,2),0.5),235,16)':cb=128:cr=128",
      '-f', 'lavfi', '-i', "sine=f=1000:r=48000:d=24,volume='lt(mod(t,2),0.5)':eval=frame",
      ...x264, '-g', '30', '-c:a', 'aac', '-b:a', '128k', '-shortest', f('bursts.mp4')
    ]);
    // 60 fps source.
    ff(['-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=60:d=1', ...x264, f('fast.mp4')]);
  });
  tearDownAll(tearDownMedia);

  /// Rows / columns of [after] that are clearly darker than in [before]
  /// (the title box on grey), as inclusive bounds.
  ({int left, int right, int top, int bottom}) darkArea(Frame before, Frame after) {
    var left = after.w, right = -1, top = after.h, bottom = -1;
    for (var y = 0; y < after.h; y++) {
      for (var x = 0; x < after.w; x++) {
        final (r0, _, _) = before.at(x, y);
        final (r1, _, _) = after.at(x, y);
        if (r0 - r1 > 30) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return (left: left, right: right, top: top, bottom: bottom);
  }

  /// Bounds of the white text pixels.
  ({int left, int right, int top, int bottom, int count}) textArea(Frame fr) {
    var left = fr.w, right = -1, top = fr.h, bottom = -1, n = 0;
    for (var y = 0; y < fr.h; y++) {
      for (var x = 0; x < fr.w; x++) {
        final (r, g, b) = fr.at(x, y);
        if (r > 200 && g > 200 && b > 200) {
          n++;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return (left: left, right: right, top: top, bottom: bottom, count: n);
  }

  group('titles from the shared layout', () {
    test('9:16: a long caption keeps its size in check and stays inside the frame', () async {
      const text = 'Captions on a phone screen have to wrap and still fit';
      for (final y in [CaptionDefaults.y, 0.99]) {
        final t = captionStyle(const TitleOverlay(id: 't', text: text, startMs: 300, endMs: 900)).copyWith(y: y);
        final project = proj([photo(ms: 900, file: 'grey_tall.png', w: 360, h: 640)], titles: [t]);
        expect(project.canvasSize, (width: 360, height: 640));
        final b = layoutTitleBlock(t, canvasWidth: 360, canvasHeight: 640);
        // Size from the SHORT side: 0.045 * 360, not 0.045 * 640.
        expect(b.fontPx, 16);
        expect(b.lines.length, 2);
        final out = await exportAndCheck(project, width: 360, height: 640);
        final before = frameAt(out, 100, 360, 640);
        final shown = frameAt(out, 600, 360, 640);
        // The box is where the layout (and so the preview) puts it.
        final box = darkArea(before, shown);
        expect(box.left, closeTo(b.boxLeft, 3), reason: 'y=$y');
        expect(box.right, closeTo(b.boxLeft + b.boxWidth, 3));
        expect(box.top, closeTo(b.boxTop, 3));
        expect(box.bottom, closeTo(b.boxTop + b.boxHeight, 3));
        // Inside the frame with the 2 % margin, at the bottom edge too.
        expect(box.left, greaterThanOrEqualTo(5));
        expect(box.right, lessThanOrEqualTo(354));
        expect(box.bottom, lessThanOrEqualTo(640 - 11));
        for (var yy = 632; yy < 640; yy++) {
          for (var x = 0; x < 360; x += 7) {
            expect(shown.at(x, yy), before.at(x, yy), reason: 'bottom rows are untouched ($x,$yy)');
          }
        }
        // Both lines are inside the box.
        final txt = textArea(shown);
        expect(txt.count, greaterThan(300));
        expect(txt.left, greaterThan(box.left));
        expect(txt.right, lessThan(box.right));
        expect(txt.top, greaterThan(box.top));
        expect(txt.bottom, lessThan(box.bottom));
        expect((txt.left + txt.right) / 2, closeTo(b.centerX, 4));
        expect((txt.top + txt.bottom) / 2, closeTo(b.centerY, 5));
        if (y > 0.9) {
          expect(b.centerY, lessThan(0.99 * 640 - 10), reason: 'the layout moved the block up');
        }
      }
    });

    test('16:9: a boxed multi-line title sits where it did, box sized by the layout', () async {
      const t = TitleOverlay(
          id: 't', text: 'Summer in the mountains\n2026', startMs: 0, endMs: 600, x: 0.4, y: 0.3, fontSize: 0.08, background: true);
      final project = proj([photo(ms: 900, file: 'grey_wide.png', w: 640, h: 360)], titles: [t]);
      final b = layoutTitleBlock(t, canvasWidth: 640, canvasHeight: 360);
      expect(b.lines, ['Summer in the mountains', '2026']);
      // Phase 1/2 numbers: 0.08 * 360 px text, lines 1.2 sizes apart,
      // centred on (0.4 w, 0.3 h).
      expect((b.fontPx, b.centerX, b.centerY), (29.0, 256.0, 108.0));
      expect(b.lineHeightPx, closeTo(34.8, 1e-9));
      final out = await exportAndCheck(project, width: 640, height: 360);
      final shown = frameAt(out, 300, 640, 360);
      final after = frameAt(out, 750, 640, 360);
      final box = darkArea(after, shown);
      expect(box.left, closeTo(b.boxLeft, 3));
      expect(box.right, closeTo(b.boxLeft + b.boxWidth, 3));
      expect(box.top, closeTo(b.boxTop, 3));
      expect(box.bottom, closeTo(b.boxTop + b.boxHeight, 3));
      final txt = textArea(shown);
      expect((txt.left + txt.right) / 2, closeTo(256, 4));
      // First line: capitals centred on 108 - 17.4; second line below it.
      int rowCount(int y0, int y1) {
        var n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = 0; x < 640; x++) {
            final (r, g, bl) = shown.at(x, y);
            if (r > 200 && g > 200 && bl > 200) n++;
          }
        }
        return n;
      }

      expect(rowCount(78, 104), greaterThan(400));
      expect(rowCount(113, 138), greaterThan(80));
      expect(txt.top, closeTo(108 - 17.4 - 29 * 0.36, 4));
      // The short second line is centred under the first.
      var l2 = 640, r2 = -1;
      for (var y = 113; y < 138; y++) {
        for (var x = 0; x < 640; x++) {
          final (r, g, bl) = shown.at(x, y);
          if (r > 200 && g > 200 && bl > 200) {
            if (x < l2) l2 = x;
            if (x > r2) r2 = x;
          }
        }
      }
      expect((l2 + r2) / 2, closeTo(256, 4));
      expect(r2 - l2, lessThan(b.width / 2));
    });

    test('small quality: the same block, scaled', () async {
      final t = captionStyle(const TitleOverlay(id: 't', text: 'Scaled down together with the picture', startMs: 0, endMs: 500));
      // 1620x1080 canvas -> 1080x720 output.
      final project = proj([photo(ms: 800, file: 'grey_big.png', w: 1620, h: 1080)], titles: [t]);
      final b = layoutTitleBlock(t, canvasWidth: 1620, canvasHeight: 1080);
      final out = await exportAndCheck(project, options: const ExportOptions(quality: ExportQuality.small), width: 1080, height: 720);
      final txt = textArea(frameAt(out, 250, 1080, 720));
      const k = 720 / 1080;
      expect((txt.left + txt.right) / 2, closeTo(b.centerX * k, 5));
      expect((txt.top + txt.bottom) / 2, closeTo(b.centerY * k, 6));
      expect(txt.right - txt.left, closeTo(b.width * k, 8));
    });
  });

  group('music that outlasts the video', () {
    AudioClip music({int start = 0, int fo = 0}) => AudioClip(
        id: 'm${seq++}', path: f('music.m4a'), sourceDurationMs: 4000, startMs: start, inMs: 0, outMs: 4000, fadeOutMs: fo);

    test('fades out at the end of the video instead of being cut', () async {
      // 3 s of silent video, 4 s of music.
      final faded = await exportAndCheck(proj([port(outMs: 3000)], audio: [music(fo: 1000)]));
      final mid = meanVolume(faded, fromMs: 1000, toMs: 1800);
      expect(mid, greaterThan(-30));
      // Still at full level right before the fade starts.
      expect(meanVolume(faded, fromMs: 1700, toMs: 1950), closeTo(mid, 1.5));
      expect(meanVolume(faded, fromMs: 2500, toMs: 3000), lessThan(mid - 8));
      expect(meanVolume(faded, fromMs: 2850, toMs: 2990), lessThan(mid - 18));
      // Without a fade it plays at full level to the end.
      final cut = await exportAndCheck(proj([port(outMs: 3000)], audio: [music()]));
      expect(meanVolume(cut, fromMs: 2500, toMs: 2950), closeTo(meanVolume(cut, fromMs: 1000, toMs: 1800), 1.5));
    });

    test('music that ends inside the video still fades at its own end', () async {
      final out = await exportAndCheck(proj([port(outMs: 2000), port(outMs: 2000), port(outMs: 2000)], audio: [music(start: 500, fo: 1000)]));
      final mid = meanVolume(out, fromMs: 1500, toMs: 3000);
      expect(meanVolume(out, fromMs: 4350, toMs: 4490), lessThan(mid - 18));
      expect(meanVolume(out, fromMs: 4700, toMs: 5900), lessThan(-70));
    });

    test('music lying wholly after the end adds nothing and breaks nothing', () async {
      final out = await exportAndCheck(
          proj([port(outMs: 1000)], audio: [music(start: 1000, fo: 500), music(start: 7000, fo: 500)], duckMusic: true));
      expect(meanVolume(out), lessThan(-70));
      final withOne = await exportAndCheck(proj([port(outMs: 1000)], audio: [music(start: 5000, fo: 500), music(fo: 300)]));
      expect(meanVolume(withOne, fromMs: 100, toMs: 600), greaterThan(-30));
    });
  });

  group('canvas', () {
    test('a 12 megapixel photo first: the output is capped and encodes quickly', () async {
      final info = await engine.probe(f('huge.jpg'));
      expect((info.width, info.height), (4000, 3000));
      final project = proj([
        photo(ms: 3000, file: 'huge.jpg', w: 4000, h: 3000),
        land(outMs: 1000, fit: FitMode.blur),
        photo(ms: 2000, file: 'huge.jpg', w: 4000, h: 3000, fit: FitMode.blur)
            .copyWith(transition: TransitionType.crossfade, transitionMs: 400, zoom: 1.5),
      ]);
      // Short side 1080 for a canvas that comes from a photo.
      expect(project.canvasSize, (width: 1440, height: 1080));
      final sw = Stopwatch()..start();
      final out = await exportAndCheck(project, width: 1440, height: 1080);
      sw.stop();
      // 5.6 s of 1440x1080; about 2 s here. The photo is decoded once, not
      // once per frame (that alone took longer than real time).
      expect(sw.elapsed, lessThan(const Duration(seconds: 25)), reason: 'took ${sw.elapsed}');
      expect(countFrames(out), layoutTimeline(project, 30).totalFrames);
      // The photo fills the frame (same shape as the canvas) and is held.
      final a = frameAt(out, 200, 1440, 1080), b = frameAt(out, 2700, 1440, 1080);
      expect(a.isBlack(4, 540), isFalse);
      expect(a.luma(), closeTo(b.luma(), 1));
    });

    test('the canvas does not have to be the first clip', () async {
      // Captured from a landscape video that has since moved to the back.
      final project = Project(
          id: 'p', name: 'n', createdAt: t0, updatedAt: t0, originalWidth: 640, originalHeight: 360,
          clips: [port(outMs: 600), photo(ms: 500, file: 'huge.jpg', w: 4000, h: 3000), land(outMs: 600)]);
      expect(project.canvasSize, (width: 640, height: 360));
      final out = await exportAndCheck(project, width: 640, height: 360);
      // The portrait clip is fitted: bars left and right.
      final fr = frameAt(out, 300, 640, 360);
      expect(fr.isBlack(8, 180), isTrue);
      expect(fr.isBlack(320, 100), isFalse);
    });
  });

  group('many pieces of one file', () {
    // Piece j shows source 2 s * (j + 1) - 0.233 .. + 0.700: 0.233 s of
    // black and silence, the 0.5 s burst, 0.2 s of black and silence.
    const pieceMs = 933;
    List<Clip> pieces({bool sameSettings = true}) => [
          for (var j = 0; j < 11; j++)
            clip('bursts.mp4', 320, 180, inMs: (j + 1) * 2000 - 233, outMs: (j + 1) * 2000 + 700)
                // An inaudible difference keeps neighbours from being joined
                // (the volume filter is left out below 0.0005).
                .copyWith(volume: sameSettings || j.isEven ? 1.0 : 1.0001),
        ];

    test('one input; same length and frames as one input per piece; in sync at the last piece', () async {
      final joined = proj(pieces());
      final separate = proj(pieces(sameSettings: false));
      int inputs(Project p) => buildExportCommand(project: p, outputPath: 'o.mp4', fonts: fonts, workDir: tmp.path)
          .args
          .where((a) => a == '-i')
          .length;
      expect(inputs(joined), 1);
      expect(inputs(separate), 11);
      expect(joined.durationMs, 11 * pieceMs);

      final a = await exportAndCheck(joined, width: 320, height: 180);
      final b = await exportAndCheck(separate, width: 320, height: 180);
      final frames = layoutTimeline(joined, 30).totalFrames;
      expect(frames, 308);
      expect(countFrames(a), frames);
      expect(countFrames(b), frames);
      expect(ffprobe(a).streamMs('audio'), closeTo(ffprobe(b).streamMs('audio'), 25));
      expect(ffprobe(a).streamMs('video'), ffprobe(b).streamMs('video'));

      for (final out in [a, b]) {
        for (final j in [0, 5, 10]) {
          final t = j * pieceMs;
          final why = '${out == a ? 'one input' : 'separate inputs'}, piece $j';
          // Picture: black, white during the burst, black again.
          expect(frameAt(out, t + 120, 320, 180).luma(), lessThan(40), reason: why);
          expect(frameAt(out, t + 233 + 80, 320, 180).luma(), greaterThan(200), reason: why);
          expect(frameAt(out, t + 733 - 80, 320, 180).luma(), greaterThan(200), reason: why);
          expect(frameAt(out, t + 733 + 80, 320, 180).luma(), lessThan(40), reason: why);
          // Sound: the beep is there exactly while the picture is white.
          final beep = meanVolume(out, fromMs: t + 233 + 60, toMs: t + 733 - 60, filter: band(1000));
          expect(beep, greaterThan(-25), reason: why);
          expect(meanVolume(out, fromMs: t + 20, toMs: t + 233 - 70, filter: band(1000)), lessThan(beep - 30), reason: why);
          expect(meanVolume(out, fromMs: t + 733 + 70, toMs: t + pieceMs - 20, filter: band(1000)), lessThan(beep - 30),
              reason: why);
        }
      }
    });

    for (final speed in [1.25, 2.0, 0.5]) {
      test('all pieces at ${speed}x: one input, timeline length, still in sync at the last piece', () async {
        final project = proj([for (final c in pieces()) c.copyWith(speed: speed)]);
        final cmd = buildExportCommand(project: project, outputPath: 'o.mp4', fonts: fonts, workDir: tmp.path);
        expect(cmd.args.where((a) => a == '-i').length, 1);
        expect(RegExp('atempo=${speed == 2 ? '2' : speed}').allMatches(cmd.filterGraph).length, 1);
        final out = await exportAndCheck(project, width: 320, height: 180);
        expect(countFrames(out), layoutTimeline(project, 30).totalFrames);
        expect(ffprobe(out).streamMs('audio'), closeTo(project.durationMs, 40));
        // Where the bursts are on the output: piece j starts at j * 933 ms
        // of joined source, and all of it plays `speed` times as fast.
        int at(num sourceMs) => (sourceMs / speed).round();
        final m = (70 / speed).round() + 35; // a frame of slack, more when slow
        for (final j in [0, 10]) {
          final t = j * pieceMs;
          final why = 'piece $j at ${speed}x';
          expect(frameAt(out, at(t + 233) - m, 320, 180).luma(), lessThan(40), reason: why);
          expect(frameAt(out, at(t + 233) + m, 320, 180).luma(), greaterThan(200), reason: why);
          expect(frameAt(out, at(t + 733) - m, 320, 180).luma(), greaterThan(200), reason: why);
          final after = at(t + 733) + m;
          expect(frameAt(out, after < project.durationMs - 60 ? after : project.durationMs - 60, 320, 180).luma(), lessThan(40),
              reason: why);
          final beep = meanVolume(out, fromMs: at(t + 233) + m, toMs: at(t + 733) - m, filter: band(1000));
          expect(beep, greaterThan(-25), reason: why);
          expect(meanVolume(out, fromMs: at(t + 20), toMs: at(t + 233) - m, filter: band(1000)), lessThan(beep - 25), reason: why);
          expect(meanVolume(out, fromMs: at(t + 733) + m, toMs: at(t + pieceMs - 20), filter: band(1000)), lessThan(beep - 25),
              reason: why);
        }
      });
    }

    test('500 clips that cannot share inputs: the graph goes through a file', () async {
      const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
      for (final (name, colour, hz) in [('tiny_a.mp4', 'red', 440), ('tiny_b.mp4', 'blue', 880)]) {
        ff([
          '-f', 'lavfi', '-i', 'color=c=$colour:s=64x36:r=10:d=1',
          '-f', 'lavfi', '-i', 'sine=f=$hz:r=48000:d=1',
          ...x264, '-g', '1', '-c:a', 'aac', '-shortest', f(name)
        ]);
      }
      final project = proj([
        for (var i = 0; i < 500; i++) clip(i.isEven ? 'tiny_a.mp4' : 'tiny_b.mp4', 64, 36, inMs: (i % 8) * 100, outMs: (i % 8) * 100 + 100),
      ]);
      const options = ExportOptions(fps: 10);
      final cmd = buildExportCommand(project: project, outputPath: 'o.mp4', fonts: fonts, workDir: tmp.path, options: options);
      expect(cmd.args.where((a) => a == '-i').length, 500);
      // More than Linux accepts as one argument.
      expect(cmd.filterGraph.length, greaterThan(131072));
      expect(cmd.needsGraphFile, isTrue);
      expect(await engine.majorVersion(), isNotNull);
      final out = await exportAndCheck(project, options: options, width: 64, height: 36);
      expect(countFrames(out), 500);
      // Red and blue alternate every frame.
      final (r0, _, b0) = frameAt(out, 0, 64, 36).mean();
      final (r1, _, b1) = frameAt(out, 100, 64, 36).mean();
      expect(r0, greaterThan(b0 + 100));
      expect(b1, greaterThan(r1 + 100));
    }, timeout: const Timeout(Duration(minutes: 2))); // 500 inputs: slow under load

    test('a 25 fps source without sound, and a run between other clips', () async {
      final project = proj([
        land(outMs: 500),
        port(inMs: 0, outMs: 400),
        port(inMs: 600, outMs: 1000),
        port(inMs: 1200, outMs: 1750),
        photo(ms: 500).copyWith(transition: TransitionType.crossfade, transitionMs: 200),
        land(inMs: 0, outMs: 300),
        land(inMs: 700, outMs: 1300),
      ]);
      final cmd = buildExportCommand(project: project, outputPath: 'o.mp4', fonts: fonts, workDir: tmp.path);
      // land | port x2 as a run | port into the photo | photo | land x2 as a run
      expect(cmd.args.where((a) => a == '-i').length, 5);
      final out = await exportAndCheck(project, width: 640, height: 360);
      expect(countFrames(out), layoutTimeline(project, 30).totalFrames);
      // The tone of the last two pieces is there to the end.
      expect(meanVolume(out, fromMs: project.durationMs - 800, toMs: project.durationMs - 100), greaterThan(-40));
      // Silent while the portrait pieces play.
      expect(meanVolume(out, fromMs: 600, toMs: 1700), lessThan(-70));
    });
  });

  group('frame rate', () {
    test('probe reports the source frame rate; 60 is suggested from 50 fps on', () async {
      final land = await engine.probe(f('land.mp4'));
      final port = await engine.probe(f('port.mp4'));
      final fast = await engine.probe(f('fast.mp4'));
      expect(land.fps, closeTo(30, 0.01));
      expect(port.fps, closeTo(25, 0.01));
      expect(fast.fps, closeTo(60, 0.01));
      expect((await engine.probe(f('photo.png'))).fps, 0);
      expect((await engine.probe(f('big.jpg'))).fps, 0);
      expect((await engine.probe(f('music.m4a'))).fps, 0);
      expect(ExportOptions.suggestedFps([land.fps, port.fps, 0]), 30);
      expect(ExportOptions.suggestedFps([land.fps, fast.fps]), 60);
    });

    test('60 fps export: transitions, speed, photos, pieces of one file', () async {
      final project = proj([
        clip('fast.mp4', 320, 180, outMs: 1000, hasAudio: false),
        land(outMs: 1000).copyWith(transition: TransitionType.crossfade, transitionMs: 300),
        port(outMs: 1000, fit: FitMode.blur).copyWith(transition: TransitionType.slideLeft, transitionMs: 250),
        land(outMs: 2000).copyWith(speed: 2),
        land(inMs: 400, outMs: 1200).copyWith(speed: 0.5),
        photo(ms: 700).copyWith(transition: TransitionType.fadeBlack, transitionMs: 200),
        land(inMs: 0, outMs: 450),
        land(inMs: 900, outMs: 1350),
      ]);
      const options = ExportOptions(fps: 60);
      final timeline = layoutTimeline(project, 60);
      expect(timeline.totalFrames, (project.durationMs * 60 / 1000).round());
      final out = await exportAndCheck(project, options: options, width: 320, height: 180);
      final v = ffprobe(out).stream('video')!;
      expect(v['r_frame_rate'], '60/1');
      expect(v['avg_frame_rate'], '60/1');
      expect(countFrames(out), timeline.totalFrames);
      expect((await engine.probe(out)).fps, closeTo(60, 0.01));
      // The 60 fps source keeps all its frames: two neighbours differ
      // (testsrc2 moves every frame), in the 2x clip as well.
      double diff(int ms) {
        final a = frameAt(out, ms, 320, 180), b = frameAt(out, ms + 17, 320, 180);
        var d = 0;
        for (var i = 0; i < a.rgb.length; i += 3) {
          d += (a.rgb[i] - b.rgb[i]).abs();
        }
        return d / (a.rgb.length / 3);
      }

      expect(diff(300), greaterThan(0.5));
      // Sound of the sped-up clip is still there and the file ends in sync.
      expect(meanVolume(out, fromMs: project.durationMs - 400, toMs: project.durationMs - 50), greaterThan(-40));
    });
  });
}
