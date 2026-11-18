// Real exports for 1.6: crop, rotation, mirroring and position of a clip,
// and the overlay track (picture-in-picture, side by side, top and bottom,
// full, free, fades, sound). Synthetic colour fixtures; the checks sample
// pixel colours. System ffmpeg; skipped when it is not installed.

import 'package:clipforge/core/model/picture_layout.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Only the sound around [hz].
String band(int hz) =>
    'bandpass=f=$hz:width_type=q:w=20,bandpass=f=$hz:width_type=q:w=20,';

enum C { red, green, blue, yellow, magenta, cyan, black, other }

C colourOf((int, int, int) rgb) {
  final (r, g, b) = rgb;
  bool hi(int v) => v > 150;
  bool lo(int v) => v < 90;
  if (lo(r) && lo(g) && lo(b)) return C.black;
  if (hi(r) && lo(g) && lo(b)) return C.red;
  if (lo(r) && hi(g) && lo(b)) return C.green;
  if (lo(r) && lo(g) && hi(b)) return C.blue;
  if (hi(r) && hi(g) && lo(b)) return C.yellow;
  if (hi(r) && lo(g) && hi(b)) return C.magenta;
  if (lo(r) && hi(g) && hi(b)) return C.cyan;
  return C.other;
}

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // 640x360, four quarters: red | green over blue | yellow, 440 Hz tone.
    ff([
      '-f', 'lavfi', '-i', 'color=c=red:s=320x180:r=30:d=3',
      '-f', 'lavfi', '-i', 'color=c=lime:s=320x180:r=30:d=3',
      '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:r=30:d=3',
      '-f', 'lavfi', '-i', 'color=c=yellow:s=320x180:r=30:d=3',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=3',
      '-filter_complex', '[0][1]hstack[t];[2][3]hstack[u];[t][u]vstack[v]',
      '-map', '[v]', '-map', '4:a', ...x264, '-c:a', 'aac', '-shortest',
      f('quad.mp4'),
    ]);
    // 320x240 magenta video with a 1 kHz tone.
    ff([
      '-f', 'lavfi', '-i', 'color=c=magenta:s=320x240:r=30:d=3',
      '-f', 'lavfi', '-i', 'sine=f=1000:r=48000:d=3',
      ...x264, '-c:a', 'aac', '-shortest', f('magenta.mp4'),
    ]);
    // A cyan photo, 400x300.
    ff(['-f', 'lavfi', '-i', 'color=c=cyan:s=400x300', '-frames:v', '1',
        f('cyan.png')]);
  });
  tearDownAll(tearDownMedia);

  Clip quad({Framing framing = Framing.none, FitMode fit = FitMode.fit,
          double zoom = 1, bool muted = false}) =>
      Clip(
        id: 'quad-${seq++}',
        type: ClipType.video,
        path: f('quad.mp4'),
        sourceDurationMs: 3000,
        inMs: 0,
        outMs: 3000,
        width: 640,
        height: 360,
        fit: fit,
        zoom: zoom,
        muted: muted,
        framing: framing,
      );

  OverlayClip overlay(
    String file, {
    int startMs = 1000,
    int durationMs = 1500,
    OverlayLayout layout = OverlayLayout.pip,
    OverlayCorner corner = OverlayCorner.bottomRight,
    double size = 0.33,
    bool first = false,
    int fadeInMs = 0,
    bool photo = false,
    bool border = false,
  }) =>
      OverlayClip(
        clip: Clip(
          id: 'ov-${seq++}',
          type: photo ? ClipType.photo : ClipType.video,
          path: f(file),
          sourceDurationMs: photo ? 0 : 3000,
          inMs: 0,
          outMs: durationMs,
          width: photo ? 400 : 320,
          height: photo ? 300 : 240,
          hasAudio: !photo,
        ),
        startMs: startMs,
        layout: layout,
        corner: corner,
        size: size,
        overlayFirst: first,
        fadeInMs: fadeInMs,
        border: border,
      );

  Project withOverlays(List<Clip> clips, List<OverlayClip> overlays,
          {CanvasAspect aspect = CanvasAspect.original}) =>
      Project(
        id: 'p',
        name: 'n',
        createdAt: t0,
        updatedAt: t0,
        aspect: aspect,
        clips: clips,
        overlays: overlays,
      );

  C at(Frame fr, int x, int y) => colourOf(fr.at(x, y));

  group('crop and position', () {
    test('crop to the right half: green over yellow, fitted with bars',
        () async {
      final out = await exportAndCheck(proj([
        quad(framing: const Framing(crop: CropRect(0.5, 0, 0.5, 1))),
      ]));
      final fr = frameAt(out, 500, 640, 360);
      expect(at(fr, 320, 90), C.green);
      expect(at(fr, 320, 270), C.yellow);
      // 320x360 picture in a 640x360 frame: bars of 160 each side.
      expect(at(fr, 60, 180), C.black);
      expect(at(fr, 580, 180), C.black);
      expect(at(fr, 200, 90), C.green);
    });

    test('a quarter turn clockwise and the preview geometry agree', () async {
      final c = quad(framing: const Framing(rotation: 90));
      final out = await exportAndCheck(proj([c]));
      final fr = frameAt(out, 500, 640, 360);
      // Turned clockwise: blue | red over yellow | green.
      final place = placeClip(c, 640, 360);
      final l = place.picture.left, t = place.picture.top;
      final pw = place.picture.width, ph = place.picture.height;
      expect(pw, closeTo(202.5, 0.5));
      int x(double fx) => (l + fx * pw).round();
      int y(double fy) => (t + fy * ph).round();
      expect(at(fr, x(0.25), y(0.25)), C.blue);
      expect(at(fr, x(0.75), y(0.25)), C.red);
      expect(at(fr, x(0.25), y(0.75)), C.yellow);
      expect(at(fr, x(0.75), y(0.75)), C.green);
      expect(at(fr, 100, 180), C.black);
    });

    test('mirrored left to right and upside down', () async {
      final h = frameAt(
          await exportAndCheck(proj([quad(framing: const Framing(flipH: true))])),
          500, 640, 360);
      expect(at(h, 160, 90), C.green);
      expect(at(h, 480, 90), C.red);
      final v = frameAt(
          await exportAndCheck(proj([quad(framing: const Framing(flipV: true))])),
          500, 640, 360);
      expect(at(v, 160, 90), C.blue);
      expect(at(v, 480, 270), C.green);
    });

    test('vertical with Fill: the pan keeps the left or the right side',
        () async {
      for (final (pan, top, bottom) in [
        (-1.0, C.red, C.blue),
        (1.0, C.green, C.yellow),
      ]) {
        final c = quad(fit: FitMode.fill, framing: Framing(panX: pan));
        final p = proj([c], aspect: CanvasAspect.portrait9x16);
        final out = await exportAndCheck(p);
        final fr = frameAt(out, 500, 360, 640);
        for (final x in [20, 180, 340]) {
          expect(at(fr, x, 160), top, reason: 'pan $pan x $x');
          expect(at(fr, x, 480), bottom, reason: 'pan $pan x $x');
        }
      }
    });

    test('zoom with a pan goes to the corner the pan says', () async {
      final c = quad(zoom: 2, framing: const Framing(panX: 1, panY: 1));
      final fr = frameAt(await exportAndCheck(proj([c])), 500, 640, 360);
      // Zoomed 2x into the bottom-right quarter: all yellow.
      for (final (x, y) in [(20, 20), (620, 20), (320, 180), (20, 340)]) {
        expect(at(fr, x, y), C.yellow, reason: '$x,$y');
      }
    });

    test('crop + rotation are one input with pieces of a run', () async {
      // Two pieces of one file with the same framing share an input.
      final a = quad(framing: const Framing(rotation: 180));
      final b = a.copyWith(id: 'b', inMs: 1500, outMs: 3000);
      final out = await exportAndCheck(proj([a.copyWith(outMs: 1500), b]));
      final fr = frameAt(out, 2000, 640, 360);
      expect(at(fr, 160, 90), C.yellow);
    });
  });

  group('overlay track', () {
    test('picture-in-picture in the bottom right only while it shows',
        () async {
      final o = overlay('cyan.png', photo: true);
      final p = withOverlays([quad()], [o]);
      final out = await exportAndCheck(p);
      final box = overlayFrame(o, 640, 360).box;
      final inside = (box.centerX.round(), box.centerY.round());
      expect(box.right, greaterThan(560));
      expect(box.bottom, greaterThan(300));
      final before = frameAt(out, 500, 640, 360);
      final during = frameAt(out, 1700, 640, 360);
      final after = frameAt(out, 2800, 640, 360);
      expect(at(before, inside.$1, inside.$2), C.yellow);
      expect(at(during, inside.$1, inside.$2), C.cyan);
      expect(at(during, 100, 60), C.red, reason: 'main still shows');
      expect(at(after, inside.$1, inside.$2), C.yellow);
    });

    test('side by side: the middle of the main video on the left, the overlay '
        'on the right', () async {
      final o = overlay('magenta.mp4', layout: OverlayLayout.sideBySide);
      final out = await exportAndCheck(withOverlays([quad()], [o]));
      final fr = frameAt(out, 1500, 640, 360);
      expect(at(fr, 480, 180), C.magenta);
      expect(at(fr, 620, 20), C.magenta);
      // Left half shows main x 160..480: red then green at the top.
      expect(at(fr, 60, 90), C.red);
      expect(at(fr, 260, 90), C.green);
      expect(at(fr, 260, 270), C.yellow);
    });

    test('top and bottom, overlay on top', () async {
      final o = overlay('magenta.mp4',
          layout: OverlayLayout.topBottom, first: true);
      final fr =
          frameAt(await exportAndCheck(withOverlays([quad()], [o])), 1500, 640, 360);
      expect(at(fr, 320, 40), C.magenta);
      // The bottom half shows main y 90..270: red / green above y 180 of
      // the main picture, blue / yellow below.
      expect(at(fr, 100, 200), C.red, reason: 'main middle, left');
      expect(at(fr, 540, 200), C.green);
      expect(at(fr, 100, 340), C.blue);
    });

    test('full covers the main video (cut-away)', () async {
      final o = overlay('magenta.mp4', layout: OverlayLayout.full);
      final fr =
          frameAt(await exportAndCheck(withOverlays([quad()], [o])), 1500, 640, 360);
      for (final (x, y) in [(10, 10), (630, 10), (320, 180), (10, 350)]) {
        expect(at(fr, x, y), C.magenta);
      }
    });

    test('fade in: half way through it is a mix', () async {
      final o = overlay('magenta.mp4',
          layout: OverlayLayout.full, fadeInMs: 1000, startMs: 1000);
      final out = await exportAndCheck(withOverlays([quad()], [o]));
      final early = frameAt(out, 1100, 640, 360).at(160, 270); // over blue
      final late = frameAt(out, 2300, 640, 360).at(160, 270);
      expect(colourOf(late), C.magenta);
      // Blue (0,0,255) to magenta (255,0,255): red rises over the fade.
      expect(early.$1, lessThan(120));
      expect(colourOf(early), isNot(C.magenta));
    });

    test('its sound is mixed in while it plays', () async {
      final o = overlay('magenta.mp4', startMs: 1000, durationMs: 1500);
      final out = await exportAndCheck(withOverlays([quad(muted: true)], [o]));
      final quiet = meanVolume(out, fromMs: 100, toMs: 900, filter: band(1000));
      final loud = meanVolume(out, fromMs: 1200, toMs: 2300, filter: band(1000));
      expect(loud - quiet, greaterThan(30));
    });

    test('vertical canvas with a border around the picture-in-picture',
        () async {
      final o = overlay('magenta.mp4',
          corner: OverlayCorner.topLeft, border: true, size: 0.5);
      final p = withOverlays([quad(fit: FitMode.fill)], [o],
          aspect: CanvasAspect.portrait9x16);
      final out = await exportAndCheck(p);
      final fr = frameAt(out, 1500, 360, 640);
      final frame = overlayFrame(o, 360, 640);
      final box = frame.box;
      expect(frame.border, greaterThan(0));
      expect(at(fr, box.centerX.round(), box.centerY.round()), C.magenta);
      final (r, g, b) =
          fr.at(box.centerX.round(), (box.top - frame.border / 2).floor());
      expect(r > 200 && g > 200 && b > 200, isTrue, reason: 'white frame');
    });
  });
}
