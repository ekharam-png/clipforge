// Real exports for 1.7: fades (whole video and per clip), colour filters
// and warmth, text styles (font, outline, alignment, animations, animated
// box), sound-only export (M4A, MP3) and the frame rate. Synthetic
// fixtures; the checks sample pixels and sound levels. System ffmpeg;
// skipped when it is not installed.

import 'dart:io';

import 'package:clipforge/core/model/look_filter.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    final root = Directory.current.path;
    fonts = FontPaths(
      regular: fonts.regular,
      bold: fonts.bold,
      files: {
        for (final name in allTitleFontFiles)
          name: p.join(root, 'assets', 'fonts', name),
      },
    );
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // Mid grey with a 440 Hz tone, 3 s, 30 fps.
    ff([
      '-f', 'lavfi', '-i', 'color=c=0x808080:s=640x360:r=30:d=3',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=3',
      ...x264, '-c:a', 'aac', '-shortest', f('grey.mp4'),
    ]);
    // Plain colours, 2 s, no sound.
    for (final c in ['red', 'blue']) {
      ff(['-f', 'lavfi', '-i', 'color=c=$c:s=640x360:r=30:d=2', ...x264, f('$c.mp4')]);
    }
  });
  tearDownAll(tearDownMedia);

  Clip plain(String file, {int outMs = 2000, bool sound = false}) => Clip(
        id: '$file-${seq++}',
        type: ClipType.video,
        path: f(file),
        sourceDurationMs: file == 'grey.mp4' ? 3000 : 2000,
        inMs: 0,
        outMs: outMs,
        width: 640,
        height: 360,
        hasAudio: sound,
      );

  TitleOverlay notDrawn() => const TitleOverlay(
      id: 'x', text: 'Not drawn', startMs: 0, endMs: 1000);

  group('fades', () {
    test('the whole video fades in from black and out to black, with its sound',
        () async {
      final project = proj([plain('grey.mp4', outMs: 3000, sound: true)])
          .copyWith(fadeInMs: 1000, fadeOutMs: 1000);
      final out = await exportAndCheck(project);
      expect(frameAt(out, 0, 640, 360).luma(), lessThan(20));
      final mid = frameAt(out, 1500, 640, 360).luma();
      expect(mid, closeTo(128, 12));
      expect(frameAt(out, 500, 640, 360).luma(), inInclusiveRange(30, mid - 20));
      expect(frameAt(out, 2950, 640, 360).luma(), lessThan(25));
      final start = meanVolume(out, fromMs: 0, toMs: 200);
      final full = meanVolume(out, fromMs: 1200, toMs: 1800);
      final end = meanVolume(out, fromMs: 2800, toMs: 3000);
      expect(full - start, greaterThan(10));
      expect(full - end, greaterThan(10));
    });

    test('a clip fades out to black and the next one starts full', () async {
      final a = plain('grey.mp4', outMs: 1000, sound: true)
          .copyWith(fadeOutMs: 500);
      final b = plain('grey.mp4', outMs: 1000, sound: true).copyWith(inMs: 0);
      final out = await exportAndCheck(proj([a, b]));
      expect(frameAt(out, 200, 640, 360).luma(), closeTo(128, 12));
      expect(frameAt(out, 966, 640, 360).luma(), lessThan(25));
      expect(frameAt(out, 1100, 640, 360).luma(), closeTo(128, 12));
      expect(meanVolume(out, fromMs: 100, toMs: 400) -
              meanVolume(out, fromMs: 900, toMs: 1000),
          greaterThan(8));
    });

    test('a clip fade inside a transition still exports', () async {
      final a = plain('grey.mp4', outMs: 1500, sound: true).copyWith(fadeInMs: 400);
      final b = plain('red.mp4', outMs: 1500).copyWith(
          transition: TransitionType.crossfade, transitionMs: 500, fadeOutMs: 300);
      final out = await exportAndCheck(proj([a, b]));
      expect(frameAt(out, 0, 640, 360).luma(), lessThan(25));
      expect(frameAt(out, 2450, 640, 360).luma(), lessThan(30));
    });
  });

  group('colour filters', () {
    (double, double, double) expected(Clip c, (double, double, double) rgb) {
      final m = clipLookMatrix(c)!;
      final v = [rgb.$1 / 255, rgb.$2 / 255, rgb.$3 / 255];
      double row(int r) =>
          ((m[r * 4] * v[0] + m[r * 4 + 1] * v[1] + m[r * 4 + 2] * v[2] + m[r * 4 + 3])
                      .clamp(0.0, 1.0) *
                  255)
              .toDouble();
      return (row(0), row(1), row(2));
    }

    test('black and white, warm, cool, vintage, vivid and warmth match the preview maths',
        () async {
      final source = frameAt(await exportAndCheck(proj([plain('red.mp4')])), 500, 640, 360)
          .mean();
      final grey = frameAt(
              await exportAndCheck(proj([plain('grey.mp4', outMs: 1000)])), 500, 640, 360)
          .mean();
      for (final (file, base, look) in [
        ('red.mp4', source, (LookFilter.blackWhite, 0.0)),
        ('red.mp4', source, (LookFilter.vintage, 0.0)),
        ('red.mp4', source, (LookFilter.vivid, 0.0)),
        ('grey.mp4', grey, (LookFilter.warm, 0.0)),
        ('grey.mp4', grey, (LookFilter.cool, 0.0)),
        ('grey.mp4', grey, (LookFilter.none, 1.0)),
      ]) {
        final c = plain(file, outMs: 1000).copyWith(filter: look.$1, warmth: look.$2);
        final got = frameAt(await exportAndCheck(proj([c])), 500, 640, 360).mean();
        final want = expected(c, base);
        final what = '${look.$1.name} ${look.$2}: got $got, want $want';
        expect(got.$1, closeTo(want.$1, 8), reason: what);
        expect(got.$2, closeTo(want.$2, 8), reason: what);
        expect(got.$3, closeTo(want.$3, 8), reason: what);
      }
    });

    test('bars stay black with a filter', () async {
      final c = Clip(
          id: 'port',
          type: ClipType.video,
          path: f('port.mp4'),
          sourceDurationMs: 2000,
          inMs: 0,
          outMs: 1000,
          width: 360,
          height: 640,
          hasAudio: false,
          filter: LookFilter.vintage);
      final out = await exportAndCheck(proj([plain('grey.mp4', outMs: 1000), c]));
      final fr = frameAt(out, 1500, 640, 360);
      expect(fr.isBlack(10, 180), isTrue);
    });
  });

  group('text styles', () {
    TitleOverlay t({
      TitleFont font = TitleFont.classic,
      bool outline = false,
      TitleAlign align = TitleAlign.center,
      TitleAnimation animIn = TitleAnimation.none,
      bool background = false,
      double x = 0.5,
    }) =>
        TitleOverlay(
          id: 't${seq++}',
          text: 'Hello Привет שלום',
          startMs: 0,
          endMs: 2000,
          x: x,
          fontSize: 0.12,
          colorArgb: 0xFFFFFFFF,
          shadow: false,
          font: font,
          outline: outline,
          outlineColorArgb: 0xFFFF0000,
          align: align,
          animIn: animIn,
          background: background,
        );

    int count(Frame fr, bool Function(int r, int g, int b) test) {
      var n = 0;
      for (var i = 0; i < fr.rgb.length; i += 3) {
        if (test(fr.rgb[i], fr.rgb[i + 1], fr.rgb[i + 2])) n++;
      }
      return n;
    }

    bool white(int r, int g, int b) => r > 200 && g > 200 && b > 200;
    bool red(int r, int g, int b) => r > 150 && g < 90 && b < 110;

    ({int left, int right}) whiteSpan(Frame fr, {bool light = false}) {
      var l = fr.w, r = -1;
      for (var y = 0; y < fr.h; y++) {
        for (var x = 0; x < fr.w; x++) {
          final (a, b, c) = fr.at(x, y);
          if (light ? a > 150 && b > 150 : white(a, b, c)) {
            if (x < l) l = x;
            if (x > r) r = x;
          }
        }
      }
      return (left: l, right: r);
    }

    test('fonts differ, outline is drawn, alignment holds', () async {
      Future<Frame> draw(TitleOverlay title) async => frameAt(
          await exportAndCheck(proj([plain('blue.mp4', outMs: 1000)], titles: [title])),
          500, 640, 360);
      final classic = await draw(t());
      final hand = await draw(t(font: TitleFont.handwritten));
      final modern = await draw(t(font: TitleFont.modern));
      final cw = whiteSpan(classic), hw = whiteSpan(hand), mw = whiteSpan(modern);
      // Amatic SC is a narrow font: the same words are far narrower.
      expect(hw.right - hw.left, lessThan((cw.right - cw.left) * 0.8));
      expect((mw.right - mw.left) - (cw.right - cw.left), isNot(0));
      expect(count(classic, red), lessThan(50));
      final outlined = await draw(t(outline: true));
      expect(count(outlined, red), greaterThan(300));
      // Left aligned: the text starts at the left margin (2 % of 640).
      final left = whiteSpan(await draw(t(align: TitleAlign.left, x: 0)));
      expect(left.left, inInclusiveRange(10, 30));
      final right = whiteSpan(await draw(t(align: TitleAlign.right, x: 1)));
      expect(right.right, inInclusiveRange(640 - 30, 640 - 10));
    });

    test('animations: fade, pop, slide up and an animated box', () async {
      Future<String> render(TitleOverlay title) =>
          exportAndCheck(proj([plain('blue.mp4', outMs: 2000)], titles: [title]));
      final fade = await render(t(animIn: TitleAnimation.fade));
      expect(count(frameAt(fade, 0, 640, 360), white), lessThan(20));
      final full = count(frameAt(fade, 1000, 640, 360), white);
      expect(full, greaterThan(500));
      final pop = await render(t(animIn: TitleAnimation.pop));
      // 100 ms in: about 92 % of the size (and 75 % opaque).
      final early = whiteSpan(frameAt(pop, 100, 640, 360), light: true);
      final late = whiteSpan(frameAt(pop, 1000, 640, 360), light: true);
      expect(early.right - early.left, lessThan((late.right - late.left) * 0.96));
      expect(early.right - early.left, greaterThan((late.right - late.left) * 0.85));
      final slide = await render(t(animIn: TitleAnimation.slideUp));
      expect(count(frameAt(slide, 1000, 640, 360), white), closeTo(full, full * 0.15));
      final boxed = await render(t(animIn: TitleAnimation.fade, background: true));
      // Blue background; the box darkens it once it has faded in.
      bool darkBlue(int r, int g, int b) => b > 40 && b < 170 && r < 60;
      expect(count(frameAt(boxed, 0, 640, 360), darkBlue), lessThan(100));
      expect(count(frameAt(boxed, 1000, 640, 360), darkBlue), greaterThan(5000));
      // Half way through its fade-in the box is about half as dark.
      final halfBox = frameAt(boxed, 200, 640, 360);
      bool midBlue(int r, int g, int b) => b >= 170 && b < 235 && r < 60;
      expect(count(halfBox, midBlue), greaterThan(5000));
      // 1.8: a box that slides up and pops out, with a two-line title.
      final both = await render(t(animIn: TitleAnimation.slideUp, background: true)
          .copyWith(animOut: TitleAnimation.pop, text: 'Hello\nПривет שלום'));
      expect(count(frameAt(both, 1000, 640, 360), darkBlue), greaterThan(5000));
      expect(count(frameAt(both, 1000, 640, 360), white), greaterThan(300));
      expect(count(frameAt(both, 1960, 640, 360), darkBlue), lessThan(100));
    });
  });

  group('sound only and frame rate', () {
    test('M4A: AAC sound, no picture, the full length', () async {
      final project = proj([plain('grey.mp4', outMs: 1500, sound: true), photo()],
          titles: [notDrawn()]);
      final out = p.setExtension(outPath(), '.m4a');
      await engine
          .export(project, out, options: const ExportOptions(format: ExportFormat.m4a))
          .done;
      final pr = ffprobe(out);
      expect(pr.stream('video'), isNull);
      expect(pr.stream('audio')!['codec_name'], 'aac');
      expect(pr.durationMs, closeTo(project.durationMs, 150));
      expect(meanVolume(out, fromMs: 200, toMs: 1200), greaterThan(-30));
    });

    test('MP3', () async {
      final project = proj([plain('grey.mp4', outMs: 1500, sound: true)])
          .copyWith(fadeInMs: 500);
      final out = p.setExtension(outPath(), '.mp3');
      await engine
          .export(project, out, options: const ExportOptions(format: ExportFormat.mp3))
          .done;
      final pr = ffprobe(out);
      expect(pr.stream('video'), isNull);
      expect(pr.stream('audio')!['codec_name'], 'mp3');
      expect(pr.durationMs, closeTo(1500, 150));
      expect(meanVolume(out, fromMs: 700, toMs: 1300) - meanVolume(out, fromMs: 0, toMs: 100),
          greaterThan(8));
    });

    for (final fps in [24, 25, 60]) {
      test('$fps frames per second', () async {
        final project = proj([plain('grey.mp4', outMs: 2000, sound: true)]);
        final out = await exportAndCheck(project, options: ExportOptions(fps: fps));
        expect(ffprobe(out).stream('video')!['r_frame_rate'], '$fps/1');
        expect(countFrames(out), closeTo(2 * fps, 1));
      });
    }
  });

}
