// Real exports of the schema v2 features (speed, colour, zoom, clean audio,
// transitions, ducking, wrapped titles) plus extractFrame / detectSilence,
// through ProcessMediaEngine with the system ffmpeg.
// Skipped (with a message) when ffmpeg / ffprobe are not installed.
//
// Assertions are about what a viewer would notice (lengths, which clip is
// visible, brighter / darker, louder / quieter), with wide margins: they
// must hold for every FFmpeg from 6.1 on and for any encoder settings.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// Only the sound around [hz] (two narrow band-passes: one octave away is
/// about 60 dB down).
String band(int hz) => 'bandpass=f=$hz:width_type=q:w=20,bandpass=f=$hz:width_type=q:w=20,';

Clip red({int outMs = 1500}) => clip('red.mp4', 640, 360, outMs: outMs);
Clip sky({int outMs = 1500}) => clip('sky.mp4', 640, 360, outMs: outMs);
Clip ramp({int inMs = 0, int outMs = 4000}) =>
    clip('ramp.mp4', 320, 180, inMs: inMs, outMs: outMs).copyWith();
Clip black({int ms = 1000}) => photo(ms: ms, file: 'black.png', w: 640, h: 360);

/// Brightness the ramp fixture shows at source time [ms], as RGB level.
double rampLevel(int ms) => (60.0 * ms / 1000 - 16) * 255 / 219;

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {}, skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // Solid colours with a tone: easy to tell apart in a blended frame.
    ff([
      '-f', 'lavfi', '-i', 'color=c=red:s=640x360:r=30:d=2',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=2',
      ...x264, '-c:a', 'aac', '-shortest', f('red.mp4')
    ]);
    ff([
      '-f', 'lavfi', '-i', 'color=c=0x40C0FF:s=640x360:r=30:d=2',
      '-f', 'lavfi', '-i', 'sine=f=660:r=48000:d=2',
      ...x264, '-c:a', 'aac', '-shortest', f('sky.mp4')
    ]);
    // Brightness rises with time (luma = 60 per second); the 440 Hz tone is
    // on in every even second and off in every odd one.
    ff([
      '-f', 'lavfi', '-i', "color=c=black:s=320x180:r=30:d=4,geq=lum='clip(60*T,0,255)':cb=128:cr=128",
      '-f', 'lavfi', '-i', "sine=f=440:r=48000:d=4,volume='lt(mod(t,2),1)':eval=frame",
      ...x264, '-c:a', 'aac', '-b:a', '128k', '-shortest', f('ramp.mp4')
    ]);
    // White square (64x36) in the middle of a black picture.
    ff([
      '-f', 'lavfi', '-i', 'color=c=black:s=640x360,drawbox=x=288:y=162:w=64:h=36:color=white:t=fill',
      '-frames:v', '1', f('dot.png')
    ]);
    // "Speech" (a loud tone) for 1.5 s, then only hiss for another 1.5 s.
    ff([
      '-f', 'lavfi', '-i', 'color=c=gray:s=160x90:r=30:d=3',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=1.5',
      '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.005:c=white:d=3:seed=7',
      '-filter_complex', '[1:a]volume=4,apad=whole_dur=3[t];[t][2:a]amix=inputs=2:normalize=0[a]',
      '-map', '0:v', '-map', '[a]', ...x264, '-c:a', 'pcm_s16le', '-t', '3', f('noisy.mov')
    ]);
    // Tone 0..1 s, silence 1..2.5 s, tone 2.5..3.5 s, silence 3.5..5 s.
    ff([
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=5',
      '-af', "volume='lt(t,1)+between(t,2.5,3.5)':eval=frame",
      '-c:a', 'pcm_s16le', f('gaps.wav')
    ]);
  });
  tearDownAll(tearDownMedia);

  group('speed', () {
    test('2x: half the length, picture and sound run twice as fast, pitch kept', () async {
      final project = proj([ramp().copyWith(speed: 2)]);
      expect(project.durationMs, 2000);
      final out = await exportAndCheck(project, width: 320, height: 180);
      expect(countFrames(out), 60);
      expect(ffprobe(out).stream('video')!['r_frame_rate'], '30/1');
      // Output time 1.0 s shows source time 2.0 s.
      expect(frameAt(out, 1000, 320, 180).luma(), closeTo(rampLevel(2000), 10));
      expect(frameAt(out, 1500, 320, 180).luma(), closeTo(rampLevel(3000), 10));
      // Tone on 0..0.5 s, off 0.5..1 s, on 1..1.5 s.
      expect(meanVolume(out, fromMs: 100, toMs: 400), greaterThan(-30));
      expect(meanVolume(out, fromMs: 620, toMs: 880), lessThan(-45));
      expect(meanVolume(out, fromMs: 1100, toMs: 1400), greaterThan(-30));
      // Still 440 Hz, not an octave up.
      final at440 = meanVolume(out, fromMs: 100, toMs: 400, filter: band(440));
      final at880 = meanVolume(out, fromMs: 100, toMs: 400, filter: band(880));
      expect(at440, greaterThan(at880 + 20));
    });

    test('0.5x: twice the length, frames repeat at the export rate', () async {
      final project = proj([ramp(inMs: 1000, outMs: 3000).copyWith(speed: 0.5)]);
      expect(project.durationMs, 4000);
      final out = await exportAndCheck(project, width: 320, height: 180);
      expect(countFrames(out), 120);
      // Output time 1.0 s shows source time 1.5 s; 3.0 s shows 2.5 s.
      expect(frameAt(out, 1000, 320, 180).luma(), closeTo(rampLevel(1500), 10));
      expect(frameAt(out, 3000, 320, 180).luma(), closeTo(rampLevel(2500), 10));
      // Source: silent 1..2 s, tone 2..3 s => silent 0..2 s, tone 2..4 s.
      expect(meanVolume(out, fromMs: 300, toMs: 1700), lessThan(-45));
      expect(meanVolume(out, fromMs: 2300, toMs: 3700), greaterThan(-30));
      final at440 = meanVolume(out, fromMs: 2300, toMs: 3700, filter: band(440));
      final at220 = meanVolume(out, fromMs: 2300, toMs: 3700, filter: band(220));
      expect(at440, greaterThan(at220 + 20));
    });

    test('the ends of the range: 4x and 0.25x', () async {
      var project = proj([ramp().copyWith(speed: 4), land(outMs: 500)]);
      expect(project.durationMs, 1500);
      var out = await exportAndCheck(project, width: 320, height: 180);
      expect(frameAt(out, 500, 320, 180).luma(), closeTo(rampLevel(2000), 14));
      project = proj([ramp(inMs: 2000, outMs: 2500).copyWith(speed: 0.25)]);
      expect(project.durationMs, 2000);
      out = await exportAndCheck(project, width: 320, height: 180);
      expect(frameAt(out, 1000, 320, 180).luma(), closeTo(rampLevel(2250), 10));
      expect(meanVolume(out, fromMs: 300, toMs: 1700), greaterThan(-30));
    });

    test('a photo ignores speed', () async {
      final project = proj([photo(ms: 900).copyWith(speed: 3)]);
      expect(project.durationMs, 900);
      await exportAndCheck(project, width: 400, height: 300);
    });
  });

  group('transitions', () {
    Project two(TransitionType type, {Clip? a, Clip? b}) =>
        proj([a ?? red(), (b ?? sky()).copyWith(transition: type, transitionMs: 600)]);

    for (final type in TransitionType.values) {
      test('${type.name}: length is Project.durationMs', () async {
        final project = two(type);
        expect(project.durationMs, type == TransitionType.none ? 3000 : 2400);
        final out = await exportAndCheck(project);
        expect(countFrames(out), project.durationMs * 30 ~/ 1000);
        // Before and after the transition the clips are untouched.
        final (r0, g0, b0) = frameAt(out, 300, 640, 360).mean();
        expect((r0 > 200, g0 < 40, b0 < 40), (true, true, true));
        final (r1, g1, b1) = frameAt(out, project.durationMs - 300, 640, 360).mean();
        expect(r1, closeTo(0x40, 16));
        expect(g1, closeTo(0xC0, 16));
        expect(b1, greaterThan(225));
        // Sound: the first clip's tone, then the second one's.
        expect(meanVolume(out, fromMs: 100, toMs: 700, filter: band(440)), greaterThan(-35));
        expect(meanVolume(out, fromMs: project.durationMs - 700, toMs: project.durationMs - 100, filter: band(660)),
            greaterThan(-35));
        expect(meanVolume(out, fromMs: project.durationMs - 700, toMs: project.durationMs - 100, filter: band(440)),
            lessThan(-60));
      });
    }

    test('none is a hard cut: last frame of one clip, first of the next', () async {
      final out = await exportAndCheck(two(TransitionType.none));
      final (ra, _, ba) = frameAt(out, 1450, 640, 360).mean();
      expect((ra > 200, ba < 40), (true, true));
      final (rb, _, bb) = frameAt(out, 1510, 640, 360).mean();
      expect(rb, closeTo(0x40, 16));
      expect(bb, greaterThan(225));
    });

    test('crossfade: the middle frame is a mix of both clips, the sound too', () async {
      final out = await exportAndCheck(two(TransitionType.crossfade));
      // Transition 0.9 .. 1.5 s; half way each clip counts 50 %.
      final (r, g, b) = frameAt(out, 1200, 640, 360).mean();
      expect(r, closeTo((255 + 0x40) / 2, 22));
      expect(g, closeTo((0 + 0xC0) / 2, 22));
      expect(b, closeTo((0 + 255) / 2, 22));
      // It moves steadily from one to the other.
      final early = frameAt(out, 1000, 640, 360).mean().$3;
      final late = frameAt(out, 1400, 640, 360).mean().$3;
      expect(early, lessThan(b - 30));
      expect(late, greaterThan(b + 30));
      // Both tones are heard during the overlap, each lower than alone.
      final a440 = meanVolume(out, fromMs: 1050, toMs: 1350, filter: band(440));
      final a660 = meanVolume(out, fromMs: 1050, toMs: 1350, filter: band(660));
      final full440 = meanVolume(out, fromMs: 300, toMs: 600, filter: band(440));
      expect(a440, inInclusiveRange(full440 - 14, full440 - 2));
      expect(a660, inInclusiveRange(full440 - 14, full440 - 2));
    });

    test('fadeBlack: dark at its midpoint', () async {
      final out = await exportAndCheck(two(TransitionType.fadeBlack, a: sky()));
      final full = frameAt(out, 300, 640, 360).luma();
      expect(full, greaterThan(150));
      final mid = frameAt(out, 1200, 640, 360).luma();
      expect(mid, lessThan(full * 0.5));
      // A plain crossfade between the same two clips would not dip at all.
      final plain = await exportAndCheck(two(TransitionType.crossfade, a: sky()));
      expect(frameAt(plain, 1200, 640, 360).luma(), closeTo(full, 12));
    });

    test('slideLeft: the new clip comes in from the right', () async {
      final out = await exportAndCheck(two(TransitionType.slideLeft));
      final fr = frameAt(out, 1200, 640, 360);
      final (rl, _, bl) = fr.mean(x0: 40, x1: 280);
      final (rr, _, br) = fr.mean(x0: 360, x1: 600);
      expect((rl > 200, bl < 40), (true, true), reason: 'left half still shows the old clip');
      expect((rr < 100, br > 225), (true, true), reason: 'right half shows the new clip');
    });

    test('slideUp: the new clip comes in from the bottom', () async {
      final out = await exportAndCheck(two(TransitionType.slideUp));
      final fr = frameAt(out, 1200, 640, 360);
      final (rt, _, bt) = fr.mean(y0: 20, y1: 160);
      final (rb, _, bb) = fr.mean(y0: 200, y1: 340);
      expect((rt > 200, bt < 40), (true, true), reason: 'top half still shows the old clip');
      expect((rb < 100, bb > 225), (true, true), reason: 'bottom half shows the new clip');
    });

    test('several transitions, cuts, mixed sources and fit modes in one project', () async {
      final project = proj([
        land(outMs: 1200),
        port(outMs: 1500, fit: FitMode.blur).copyWith(transition: TransitionType.crossfade, transitionMs: 400),
        photo(ms: 800), // hard cut
        // All of this clip is transition: fades in for 0.5 s, out for 0.5 s.
        red(outMs: 1000).copyWith(transition: TransitionType.slideLeft, transitionMs: 800, speed: 1),
        rot(outMs: 1000).copyWith(transition: TransitionType.fadeBlack, transitionMs: 500),
      ], audio: [
        AudioClip(id: 'm', path: f('music.m4a'), sourceDurationMs: 4000, startMs: 0, inMs: 0, outMs: 4000, volume: 0.3),
      ], titles: const [
        TitleOverlay(id: 't', text: 'Across the joins', startMs: 500, endMs: 3500),
      ]);
      expect(project.durationMs, 1200 + 1500 - 400 + 800 + 1000 - 400 + 1000 - 500);
      final out = await exportAndCheck(project, width: 640, height: 360);
      expect(countFrames(out), (project.durationMs * 30 / 1000).round());
    });

    test('a clip whose range lies beyond the end of its file still exports', () async {
      // The file was replaced by a shorter one after it was put on the
      // timeline: nothing to show or play, but no hang and the right length.
      final gone = clip('land.mp4', 640, 360, inMs: 5000, outMs: 6000);
      for (final project in [
        proj([gone, red(outMs: 1000).copyWith(transition: TransitionType.slideUp)]),
        proj([red(outMs: 1000), gone.copyWith(transition: TransitionType.crossfade), sky(outMs: 1000).copyWith(transition: TransitionType.crossfade)]),
      ]) {
        final out = outPath();
        await engine.export(project, out).done.timeout(const Duration(seconds: 30));
        final pr = ffprobe(out);
        expect(pr.durationMs, closeTo(project.durationMs, 150));
        expect(pr.streamMs('audio'), closeTo(project.durationMs, 150));
      }
    });

    test('many odd-length clips do not drift', () async {
      // 0.75 s is 22.5 frames; twelve of them must be 9 s = 270 frames.
      final project = proj([for (var i = 0; i < 12; i++) photo(ms: 750)]);
      final out = await exportAndCheck(project, width: 400, height: 300);
      expect(countFrames(out), 270);
      expect(ffprobe(out).streamMs('audio'), closeTo(9000, 40));
    });
  });

  group('zoom', () {
    Clip dot() => photo(ms: 500, file: 'dot.png', w: 640, h: 360);

    test('2x doubles the size of what is in the centre', () async {
      final plain = frameAt(await exportAndCheck(proj([dot()])), 200, 640, 360);
      final zoomed = frameAt(await exportAndCheck(proj([dot().copyWith(zoom: 2)])), 200, 640, 360);
      // The square is 64x36 around (320,180); zoomed it is 128x72.
      expect(plain.at(320, 180).$1, greaterThan(200));
      expect(zoomed.at(320, 180).$1, greaterThan(200));
      for (final (x, y) in [(270, 180), (370, 180), (320, 152), (320, 208)]) {
        expect(plain.isBlack(x, y), isTrue, reason: 'plain $x,$y');
        expect(zoomed.at(x, y).$1, greaterThan(200), reason: 'zoomed $x,$y');
      }
      for (final (x, y) in [(246, 180), (394, 180), (320, 136), (320, 224)]) {
        expect(zoomed.isBlack(x, y), isTrue, reason: 'zoomed, outside: $x,$y');
      }
      expect(zoomed.countBright() / plain.countBright(), closeTo(4, 0.5));
    });

    test('fit: the picture grows over its bars', () async {
      // A 360x640 clip on 640x360 is 202 px wide (x = 219..421); zoomed 2x
      // it is 405 px wide (x = 118..522) and shows its middle half.
      int leftEdge(Frame fr) {
        for (var x = 0; x < fr.w; x++) {
          for (var y = 0; y < fr.h; y += 4) {
            if (!fr.isBlack(x, y)) return x;
          }
        }
        return fr.w;
      }

      final unzoomed = frameAt(await exportAndCheck(proj([land(outMs: 400), port(outMs: 600)])), 700, 640, 360);
      expect(leftEdge(unzoomed), closeTo(219, 4));
      final project = proj([land(outMs: 400), port(outMs: 600).copyWith(zoom: 2)]);
      final fr = frameAt(await exportAndCheck(project), 700, 640, 360);
      expect(leftEdge(fr), closeTo(118, 5));
      expect(fr.isBlack(60, 180), isTrue);
      expect(fr.isBlack(580, 180), isTrue);
      // Same content, twice as big: what was at (229, 150) is at (138, 120).
      final (r0, g0, b0) = unzoomed.mean(x0: 226, x1: 232, y0: 147, y1: 153);
      final (r1, g1, b1) = fr.mean(x0: 132, x1: 144, y0: 114, y1: 126);
      expect((r1 - r0).abs() + (g1 - g0).abs() + (b1 - b0).abs(), lessThan(40));
    });

    test('blur: the picture grows, the blurred background stays', () async {
      Project p(double zoom) => proj([land(outMs: 400), port(outMs: 600, fit: FitMode.blur).copyWith(zoom: zoom)]);
      final plain = frameAt(await exportAndCheck(p(1)), 700, 640, 360);
      final zoomed = frameAt(await exportAndCheck(p(2)), 700, 640, 360);
      // Far left is background in both: same (blurred) colour.
      final (r0, g0, b0) = plain.mean(x0: 10, x1: 80);
      final (r1, g1, b1) = zoomed.mean(x0: 10, x1: 80);
      expect(r1, closeTo(r0, 6));
      expect(g1, closeTo(g0, 6));
      expect(b1, closeTo(b0, 6));
      expect(plain.isBlack(40, 180), isFalse);
      // x = 130..200 is background without zoom, sharp picture with it.
      final (ra, ga, ba) = plain.mean(x0: 130, x1: 200);
      final (rz, gz, bz) = zoomed.mean(x0: 130, x1: 200);
      expect((ra - rz).abs() + (ga - gz).abs() + (ba - bz).abs(), greaterThan(20));
      // The zoom limit: still a valid export.
      await exportAndCheck(p(4));
    });
  });

  group('colour', () {
    // 4:3 colour bars on a 16:9 canvas: bars left and right of the picture.
    Project p(Clip Function(Clip) change) => proj([black(ms: 300), change(photo(ms: 600))]);
    Future<Frame> shot(Clip Function(Clip) change) async => frameAt(await exportAndCheck(p(change)), 600, 640, 360);
    late Frame plain;

    setUpAll(() async => plain = await shot((c) => c));

    test('brightness moves the mean level, the bars stay black', () async {
      final up = await shot((c) => c.copyWith(brightness: 1));
      final down = await shot((c) => c.copyWith(brightness: -1));
      final half = await shot((c) => c.copyWith(brightness: 0.5));
      // Inside the picture (x 80..560).
      double l(Frame fr) => fr.luma(x0: 100, x1: 540);
      expect(l(up), greaterThan(l(plain) + 25));
      expect(l(down), lessThan(l(plain) - 25));
      expect(l(half), inExclusiveRange(l(plain) + 8, l(up) - 8));
      for (final fr in [up, down, half]) {
        expect(fr.isBlack(20, 180), isTrue);
        expect(fr.isBlack(620, 180), isTrue);
      }
      // "Not destructive": at +1 the dark part is not white, at -1 the
      // bright part is not black.
      expect(l(up), lessThan(235));
      expect(l(down), greaterThan(20));
    });

    test('contrast spreads or narrows bright and dark', () async {
      // Bright bar (left, grey/yellow) against the dark blue bar (right).
      double spread(Frame fr) => fr.luma(x0: 90, x1: 140, y0: 20, y1: 200) - fr.luma(x0: 500, x1: 550, y0: 20, y1: 200);
      final more = await shot((c) => c.copyWith(contrast: 1));
      final less = await shot((c) => c.copyWith(contrast: -1));
      expect(spread(plain), greaterThan(60));
      expect(spread(more), greaterThan(spread(plain) * 1.1));
      expect(spread(less), lessThan(spread(plain) * 0.75));
      expect(spread(less), greaterThan(spread(plain) * 0.3));
    });

    test('saturation: -1 is black and white, +1 is more colourful', () async {
      final grey = await shot((c) => c.copyWith(saturation: -1));
      final vivid = await shot((c) => c.copyWith(saturation: 1));
      final some = await shot((c) => c.copyWith(saturation: -0.5));
      expect(plain.chroma(), greaterThan(40));
      expect(grey.chroma(), lessThan(6));
      expect(vivid.chroma(), greaterThan(plain.chroma() * 1.15));
      expect(some.chroma(), inExclusiveRange(grey.chroma() + 8, plain.chroma() - 8));
      // Brightness is untouched by saturation.
      expect(grey.luma(x0: 100, x1: 540), closeTo(plain.luma(x0: 100, x1: 540), 8));
    });

    test('all at once on video, with blur fit and zoom', () async {
      final project = proj([
        land(outMs: 500),
        port(outMs: 700, fit: FitMode.blur).copyWith(brightness: 0.4, contrast: 0.3, saturation: -1, zoom: 1.5),
      ]);
      final fr = frameAt(await exportAndCheck(project), 900, 640, 360);
      // Black and white everywhere, background included.
      expect(fr.chroma(), lessThan(6));
    });
  });

  group('clean audio', () {
    Clip noisy({bool denoise = false}) => clip('noisy.mov', 160, 90, outMs: 3000).copyWith(denoise: denoise);

    test('hiss drops, speech level and timing stay, length unchanged', () async {
      final raw = await exportAndCheck(proj([noisy()]));
      final clean = await exportAndCheck(proj([noisy(denoise: true)]));
      expect(ffprobe(clean).streamMs('audio'), closeTo(ffprobe(raw).streamMs('audio'), 30));
      // Noise-only stretch.
      final noiseRaw = meanVolume(raw, fromMs: 1900, toMs: 2900);
      final noiseClean = meanVolume(clean, fromMs: 1900, toMs: 2900);
      expect(noiseRaw, inInclusiveRange(-62, -46));
      expect(noiseClean, lessThan(noiseRaw - 5));
      // The tone is not lowered (it may be raised a little by the leveller).
      final toneRaw = meanVolume(raw, fromMs: 300, toMs: 1300);
      final toneClean = meanVolume(clean, fromMs: 300, toMs: 1300);
      expect(toneClean, inInclusiveRange(toneRaw - 2, toneRaw + 8));
      // So the distance between speech and hiss grew.
      expect(toneClean - noiseClean, greaterThan(toneRaw - noiseRaw + 5));
      // No delay: the tone still stops at 1.5 s.
      expect(meanVolume(clean, fromMs: 1250, toMs: 1450), greaterThan(toneClean - 3));
      expect(meanVolume(clean, fromMs: 1600, toMs: 1800), lessThan(toneClean - 25));
    });

    test('together with speed and volume', () async {
      final project = proj([noisy(denoise: true).copyWith(speed: 2, volume: 0.5), noisy(denoise: true).copyWith(muted: true)]);
      expect(project.durationMs, 4500);
      final out = await exportAndCheck(project);
      expect(meanVolume(out, fromMs: 100, toMs: 650), greaterThan(-30));
      expect(meanVolume(out, fromMs: 1700, toMs: 4400), lessThan(-80));
    });
  });

  group('ducking', () {
    AudioClip song() =>
        AudioClip(id: 'm${seq++}', path: f('music.m4a'), sourceDurationMs: 4000, startMs: 0, inMs: 0, outMs: 4000);
    // 440 Hz "speech" for 1.5 s, then a muted clip (which has a tone too).
    Project p({required bool duck}) =>
        proj([land(outMs: 1500), land(outMs: 2000, muted: true)], audio: [song()], duckMusic: duck);
    double musicLevel(String out, int from, int to) => meanVolume(out, fromMs: from, toMs: to, filter: band(880));

    test('music drops under speech and comes back within about half a second', () async {
      final plain = await exportAndCheck(p(duck: false));
      final ducked = await exportAndCheck(p(duck: true));
      final ref = musicLevel(plain, 300, 1300);
      expect(musicLevel(plain, 2300, 3300), closeTo(ref, 1.5));
      // Under the tone: clearly lower, but not gone.
      final under = musicLevel(ducked, 300, 1300);
      expect(under, lessThan(ref - 6));
      expect(under, greaterThan(ref - 16));
      // Speech ends at 1.5 s; from 2.1 s the music is back.
      expect(musicLevel(ducked, 2100, 2400), closeTo(ref, 2));
      // A muted clip does not duck (it lasts until 3.5 s).
      expect(musicLevel(ducked, 2400, 3400), closeTo(ref, 1.5));
      // The speech itself is untouched.
      expect(meanVolume(ducked, fromMs: 300, toMs: 1300, filter: band(440)),
          closeTo(meanVolume(plain, fromMs: 300, toMs: 1300, filter: band(440)), 1.5));
    });

    test('photos and clips without sound never duck; two songs', () async {
      final project = proj([photo(ms: 1000), port(outMs: 1000)],
          audio: [song().copyWith(outMs: 1200), song().copyWith(startMs: 800, volume: 0.5)], duckMusic: true);
      final out = await exportAndCheck(project);
      final same = await exportAndCheck(project.copyWith(duckMusic: false));
      expect(musicLevel(out, 100, 700), closeTo(musicLevel(same, 100, 700), 1));
      expect(musicLevel(out, 1300, 1900), closeTo(musicLevel(same, 1300, 1900), 1));
    });
  });

  group('titles', () {
    const long = 'The quick brown fox jumps over the lazy dog and then keeps on running';
    List<int> columns(Frame fr) => [
          for (var x = 0; x < fr.w; x++)
            [for (var y = 0; y < fr.h; y++) fr.at(x, y)].where((c) => c.$1 > 200 && c.$2 > 200 && c.$3 > 200).length,
        ];
    List<int> rows(Frame fr) => [
          for (var y = 0; y < fr.h; y++)
            [for (var x = 0; x < fr.w; x++) fr.at(x, y)].where((c) => c.$1 > 200 && c.$2 > 200 && c.$3 > 200).length,
        ];

    test('long text wraps like layoutTitleLines says and stays inside the picture', () async {
      const t = TitleOverlay(id: 't', text: long, startMs: 0, endMs: 1000, fontSize: 0.1);
      final project = proj([black()], titles: [t]);
      final lines = layoutTitleLines(t, canvasWidth: 640, canvasHeight: 360);
      expect(lines.length, inInclusiveRange(3, 6));
      final fr = frameAt(await exportAndCheck(project), 500, 640, 360);
      // Nothing touches the left or right edge (an unwrapped line would be
      // about 2400 px wide).
      final cols = columns(fr);
      expect(cols.sublist(0, 16).every((n) => n == 0), isTrue);
      expect(cols.sublist(624).every((n) => n == 0), isTrue);
      expect(cols.sublist(200, 440).where((n) => n > 0).length, greaterThan(150));
      // One band of text per line, 1.2 font sizes apart, centred on y = 0.5.
      final r = rows(fr);
      const fs = 36, pitch = 43.2;
      final top = 180 - lines.length * pitch / 2;
      for (var i = 0; i < lines.length; i++) {
        final y0 = (top + i * pitch).round();
        final inBand = r.sublist(y0, (y0 + pitch).round()).fold<int>(0, (a, b) => a + b);
        expect(inBand, greaterThan(150), reason: 'line $i "${lines[i]}"');
      }
      expect(r.sublist(0, (top - fs / 2).round()).every((n) => n == 0), isTrue);
      expect(r.sublist((top + lines.length * pitch + fs / 2).round()).every((n) => n == 0), isTrue);
      // The widest line fills most of the allowed 90 %.
      final used = cols.lastIndexWhere((n) => n > 0) - cols.indexWhere((n) => n > 0);
      expect(used, inInclusiveRange(380, 580));
    });

    test('caption: one box behind the whole wrapped block', () async {
      // On the colour bars the box is visible as a darker area.
      final t = captionStyle(const TitleOverlay(id: 't', text: 'A caption that is long enough to need two lines here', startMs: 300, endMs: 900))
          .copyWith(fontSize: 0.08, y: 0.5);
      final project = proj([photo(ms: 900, file: 'big.jpg', w: 1620, h: 1080)], aspect: CanvasAspect.landscape16x9, titles: [t]);
      final size = exportSize(project, ExportQuality.small);
      final lines = layoutTitleLines(t, canvasWidth: project.canvasSize.width, canvasHeight: project.canvasSize.height);
      expect(lines.length, 2);
      final out = await exportAndCheck(project, options: const ExportOptions(quality: ExportQuality.small));
      final w = size.width, h = size.height;
      final before = frameAt(out, 100, w, h);
      final shown = frameAt(out, 600, w, h);
      final fs = titleFontPx(t, h);
      // Widths of the two lines.
      final w0 = estimateTextWidth(lines[0], fontPx: fs, bold: true);
      final w1 = estimateTextWidth(lines[1], fontPx: fs, bold: true);
      final wide = w0 > w1 ? w0 : w1;
      final narrow = w0 > w1 ? w1 : w0;
      expect(wide - narrow, greaterThan(fs * 2), reason: 'the test needs lines of clearly different width: $lines');
      final narrowY = (h / 2 + (w0 > w1 ? 0.6 : -0.6) * fs).round();
      double darkening(int x0, int x1, int y0, int y1) =>
          before.luma(x0: x0, x1: x1, y0: y0, y1: y1) - shown.luma(x0: x0, x1: x1, y0: y0, y1: y1);
      // Beside the short line, but inside the block: boxed as well.
      final x0 = (w / 2 + narrow / 2 + fs * 0.4).round();
      final x1 = (w / 2 + wide / 2 - fs * 0.2).round();
      expect(x1 - x0, greaterThan(8));
      final beside = before.luma(x0: x0, x1: x1, y0: narrowY - 4, y1: narrowY + 4);
      if (beside > 40) {
        expect(darkening(x0, x1, narrowY - 4, narrowY + 4), greaterThan(beside * 0.3));
      }
      // Well outside the block nothing changed.
      expect(darkening(0, w, 0, (h / 2 - fs * 2.2).round()).abs(), lessThan(2));
      expect(darkening(0, w, (h / 2 + fs * 2.2).round(), h).abs(), lessThan(2));
      // Somewhere in the block the picture did get darker overall.
      expect(darkening((w / 2 - wide / 2).round(), (w / 2 + wide / 2).round(), (h / 2 - fs).round(), (h / 2 + fs).round()),
          greaterThan(15));
    });

    test('an engine without fonts exports projects without titles, and says why it cannot do others', () async {
      final bare = ProcessMediaEngine(ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe', preset: 'ultrafast');
      await exportAndCheck(proj([black(ms: 400)]), using: bare);
      final job = bare.export(proj([black(ms: 400)], titles: const [TitleOverlay(id: 't', text: 'x', startMs: 0, endMs: 400)]), outPath());
      await expectLater(job.done, throwsA(isA<ExportException>().having((e) => e.message, 'message', contains('fonts'))));
      // `fonts:` is the plain-Dart way to supply them.
      final withFonts = ProcessMediaEngine(ffmpegPath: 'ffmpeg', ffprobePath: 'ffprobe', fonts: fonts, preset: 'ultrafast');
      final out = await exportAndCheck(
          proj([black(ms: 400)], titles: const [TitleOverlay(id: 't', text: 'x', startMs: 0, endMs: 400)]),
          using: withFonts);
      expect(frameAt(out, 200, 640, 360).countBright(), greaterThan(50));
    });
  });

  group('extractFrame', () {
    String png(String name) => f(p.join('frames', '$name.png'));
    double diff(Frame a, Frame b) {
      var s = 0;
      for (var i = 0; i < a.rgb.length; i++) {
        s += (a.rgb[i] - b.rgb[i]).abs();
      }
      return s / a.rgb.length;
    }

    test('full-size PNG of the frame at a time', () async {
      final out = await engine.extractFrame(f('ramp.mp4'), 2000, png('ramp2000'));
      expect(out, png('ramp2000'));
      final pr = ffprobe(out);
      expect(pr.stream('video')!['codec_name'], 'png');
      expect((pr.width, pr.height), (320, 180));
      // The picture at 2.0 s, not the key frame before it or the start.
      expect(frameAt(out, 0, 320, 180).luma(), closeTo(rampLevel(2000), 6));
      final later = await engine.extractFrame(f('ramp.mp4'), 2700, png('ramp2700'));
      expect(frameAt(later, 0, 320, 180).luma(), closeTo(rampLevel(2700), 6));
      final first = await engine.extractFrame(f('ramp.mp4'), 0, png('ramp0'));
      expect(frameAt(first, 0, 320, 180).luma(), lessThan(8));
      // Same picture as decoding the video at that time.
      final land1 = await engine.extractFrame(f('land.mp4'), 1000, png('land1000'));
      expect(diff(frameAt(land1, 0, 640, 360), frameAt(f('land.mp4'), 1000, 640, 360)), lessThan(3));
      expect(diff(frameAt(land1, 0, 640, 360), frameAt(f('land.mp4'), 500, 640, 360)), greaterThan(3));
    });

    test('rotation is applied', () async {
      final out = await engine.extractFrame(f('rot.mp4'), 500, png('rot'));
      final pr = ffprobe(out);
      expect((pr.width, pr.height), (360, 640));
    });

    test('times at or past the end give the last frame; negative gives the first', () async {
      final last = frameAt(f('ramp.mp4'), 3960, 320, 180); // frame 119 of 120
      for (final t in [3990, 4000, 60000]) {
        final out = await engine.extractFrame(f('ramp.mp4'), t, png('end$t'));
        final fr = frameAt(out, 0, 320, 180);
        expect(fr.luma(), closeTo(last.luma(), 2), reason: 't=$t');
        expect(fr.luma(), greaterThan(rampLevel(3800)));
      }
      final neg = await engine.extractFrame(f('ramp.mp4'), -500, png('neg'));
      expect(frameAt(neg, 0, 320, 180).luma(), lessThan(8));
    });

    test('overwrites an existing file; failures throw and leave no file', () async {
      File(png('again'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      await engine.extractFrame(f('land.mp4'), 300, png('again'));
      expect(ffprobe(png('again')).width, 640);
      await expectLater(engine.extractFrame(f('nope.mp4'), 0, png('nope')), throwsA(isA<ExportException>()));
      expect(File(png('nope')).existsSync(), isFalse);
      await expectLater(engine.extractFrame(f('music.m4a'), 0, png('audio')), throwsA(isA<ExportException>()));
      expect(File(png('audio')).existsSync(), isFalse);
    });
  });

  group('detectSilence', () {
    test('finds the silent stretches, including the one at the end', () async {
      final s = await engine.detectSilence(f('gaps.wav'));
      expect(s.length, 2, reason: '$s');
      expect(s[0].startMs, closeTo(1000, 60));
      expect(s[0].endMs, closeTo(2500, 60));
      expect(s[1].startMs, closeTo(3500, 60));
      expect(s[1].endMs, closeTo(5000, 60));
    });

    test('minSilenceMs and thresholdDb', () async {
      expect(await engine.detectSilence(f('gaps.wav'), minSilenceMs: 2000), isEmpty);
      expect((await engine.detectSilence(f('gaps.wav'), minSilenceMs: 100)).length, 2);
      // The tone is at about -21 dB: with a threshold above it everything
      // counts as silence.
      final all = await engine.detectSilence(f('gaps.wav'), thresholdDb: -6);
      expect(all.length, 1);
      expect(all.single.startMs, lessThan(60));
      expect(all.single.endMs, closeTo(5000, 60));
    });

    test('sound of a video file, in source time; steady tone has none', () async {
      // ramp.mp4: tone in every even second.
      final s = await engine.detectSilence(f('ramp.mp4'), minSilenceMs: 500);
      expect(s.length, 2, reason: '$s');
      expect(s[0].startMs, closeTo(1000, 90));
      expect(s[0].endMs, closeTo(2000, 90));
      expect(s[1].startMs, closeTo(3000, 90));
      expect(s[1].endMs, closeTo(4000, 90));
      expect(await engine.detectSilence(f('land.mp4')), isEmpty);
    });

    test('files without audio give an empty list; unreadable files throw', () async {
      expect(await engine.detectSilence(f('port.mp4')), isEmpty);
      expect(await engine.detectSilence(f('photo.png')), isEmpty);
      await expectLater(engine.detectSilence(f('nope.mp4')), throwsA(isA<ExportException>()));
    });
  });

  group('plain Dart', () {
    String? dart() {
      final exe = Platform.isWindows ? 'dart.exe' : 'dart';
      final candidates = <String>[
        if (Platform.environment['FLUTTER_ROOT'] case final root?) p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', exe),
      ];
      // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<os>/.
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 6; i++) {
        candidates.add(p.join(dir.path, 'dart-sdk', 'bin', exe));
        dir = dir.parent;
      }
      for (final c in candidates) {
        if (File(c).existsSync()) return c;
      }
      try {
        if (Process.runSync(exe, const ['--version']).exitCode == 0) return exe;
      } catch (_) {}
      return null;
    }

    final dartExe = dart();
    test('a program without Flutter imports the export layer and exports', () async {
      final out = f('plain_dart.mp4');
      final r = await Process.run(dartExe!, ['run', p.join('test', 'media', 'plain_dart_export.dart'), out]);
      expect(r.exitCode, 0, reason: 'stdout: ${r.stdout}\nstderr: ${r.stderr}');
      expect(r.stdout as String, contains('OK 320x180 1000ms'));
      final pr = ffprobe(out);
      expect(pr.stream('video')!['pix_fmt'], 'yuv420p');
      expect(pr.durationMs, closeTo(1000, 150));
    }, skip: dartExe == null ? 'no dart executable found' : false, timeout: const Timeout(Duration(minutes: 2)));
  });
}
