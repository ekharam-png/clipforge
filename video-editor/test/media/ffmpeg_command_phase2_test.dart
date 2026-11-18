// Unit tests of the schema v2 parts of the export graph (speed, colour,
// zoom, clean audio, transitions, ducking, wrapped titles) and of the
// frame / silence helpers. No ffmpeg needed.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(regular: '/f/Regular.ttf', bold: '/f/Bold.ttf');
final t0 = DateTime.utc(2026);

Clip video(String id, {int w = 1920, int h = 1080, int inMs = 0, int outMs = 2000, FitMode fit = FitMode.fit}) => Clip(
    id: id,
    type: ClipType.video,
    path: '/media/$id.mp4',
    sourceDurationMs: 60000,
    inMs: inMs,
    outMs: outMs,
    width: w,
    height: h,
    fit: fit);

Clip photo(String id, {int w = 1920, int h = 1080, int ms = 3000}) => Clip(
    id: id,
    type: ClipType.photo,
    path: '/media/$id.jpg',
    sourceDurationMs: 0,
    inMs: 0,
    outMs: ms,
    width: w,
    height: h,
    hasAudio: false);

AudioClip music(String id, {int start = 0, int outMs = 60000}) => AudioClip(
    id: id, path: '/media/$id.mp3', sourceDurationMs: 60000, startMs: start, inMs: 0, outMs: outMs);

Project proj(List<Clip> clips,
        {List<AudioClip> audio = const [],
        List<TitleOverlay> titles = const [],
        bool duckMusic = false,
        CanvasAspect aspect = CanvasAspect.original}) =>
    Project(
        id: 'p',
        name: 'n',
        createdAt: t0,
        updatedAt: t0,
        aspect: aspect,
        clips: clips,
        audio: audio,
        titles: titles,
        duckMusic: duckMusic);

FfmpegCommand build(Project p, {ExportOptions options = const ExportOptions()}) =>
    buildExportCommand(project: p, outputPath: '/out/o.mp4', fonts: fonts, workDir: '/tmp/w', options: options);

/// The chain of the graph that ends in [label] (e.g. "[v0]").
String chainTo(String graph, String label) =>
    graph.split(';').firstWhere((c) => c.endsWith(label), orElse: () => fail('no chain ends in $label:\n$graph'));

void main() {
  group('speed', () {
    test('video: source range as input, setpts before fps, atempo, timeline length', () {
      final c = build(proj([video('a', inMs: 1000, outMs: 5000).copyWith(speed: 2)]));
      expect(c.args.sublist(0, 7), ['-y', '-ss', '1.000', '-t', '4.000', '-i', '/media/a.mp4']);
      expect(c.durationMs, 2000);
      expect(c.args[c.args.lastIndexOf('-t') + 1], '2.000');
      final g = c.filterGraph;
      expect(g, contains('[0:v:0]setpts=PTS/2,fps=30,scale='));
      expect(g, contains('trim=end_frame=60,setpts=PTS-STARTPTS[v0]'));
      expect(g, contains('channel_layouts=stereo,atempo=2,apad,asetpts=N/SR/TB,atrim=end_sample=96000,asetpts=PTS-STARTPTS[a0]'));
      expect(c.args[c.args.indexOf('-r') + 1], '30');
    });

    test('atempo is chained in stages of 0.5..2', () {
      String tempo(double s) => RegExp(r'(atempo=[\d.]+,)+')
          .firstMatch(build(proj([video('a', outMs: 8000).copyWith(speed: s)])).filterGraph)!
          .group(0)!;
      expect(tempo(4), 'atempo=2,atempo=2,');
      expect(tempo(0.25), 'atempo=0.5,atempo=0.5,');
      expect(tempo(3), 'atempo=2,atempo=1.5,');
      expect(tempo(0.4), 'atempo=0.5,atempo=0.8,');
      expect(tempo(1.25), 'atempo=1.25,');
      for (final s in [0.25, 0.3, 0.5, 0.75, 1.5, 2.0, 2.5, 3.999, 4.0]) {
        final stages = atempoStages(s);
        expect(stages.every((f) => f >= 0.5 && f <= 2.0), isTrue, reason: '$s -> $stages');
        expect(stages.fold<double>(1, (a, b) => a * b), closeTo(s, 1e-9));
      }
      expect(atempoStages(1), isEmpty);
    });

    test('slow motion keeps the frame rate and has the stretched length', () {
      final c = build(proj([video('a', outMs: 1000).copyWith(speed: 0.25)]));
      expect(c.durationMs, 4000);
      expect(c.filterGraph, contains('setpts=PTS/0.25,fps=30,'));
      expect(c.filterGraph, contains('trim=end_frame=120,'));
      expect(c.args.sublist(1, 5), ['-ss', '0.000', '-t', '1.000']);
    });

    test('speed 1 and photos add nothing', () {
      var g = build(proj([video('a')])).filterGraph;
      expect(g, isNot(contains('atempo')));
      expect(g, contains('[0:v:0]fps=30,'));
      final c = build(proj([photo('p', ms: 3000).copyWith(speed: 2)]));
      expect(c.durationMs, 3000);
      expect(c.filterGraph, contains('[0:v:0]fps=30,'));
      expect(c.filterGraph, isNot(contains('atempo')));
      expect(c.args.sublist(1, 5), ['-framerate', '30', '-i', '/media/p.jpg']);
    });

    test('muted fast clip has silence of the timeline length', () {
      final g = build(proj([video('a', outMs: 3000).copyWith(speed: 1.5, muted: true)])).filterGraph;
      expect(g, contains('anullsrc=r=48000:cl=stereo,aformat=sample_fmts=fltp,atrim=end_sample=96000,'));
      expect(g, isNot(contains('atempo')));
    });
  });

  group('colour', () {
    test('documented mapping to eq', () {
      final v = eqValues(video('a').copyWith(brightness: 1, contrast: -1, saturation: 0.5));
      expect(v.brightness, closeTo(0.2, 1e-9));
      expect(v.contrast, closeTo(0.5, 1e-9));
      expect(v.saturation, closeTo(1.5, 1e-9));
      expect(kEqBrightnessGain, 0.2);
      expect(kEqContrastGain, 0.5);
      expect(eqFilter(video('a').copyWith(brightness: -0.5, contrast: 1, saturation: -1)),
          'eq=brightness=-0.1:contrast=1.5:saturation=0');
      // Out-of-range values are clamped to -1..1.
      expect(eqFilter(video('a').copyWith(brightness: 9, saturation: -9)), 'eq=brightness=0.2:contrast=1:saturation=0');
    });

    test('no filter when everything is 0', () {
      expect(eqFilter(video('a')), isNull);
      expect(build(proj([video('a')])).filterGraph, isNot(contains('eq=')));
    });

    test('same shape and fill: after the canvas scale, on yuv420p', () {
      var g = build(proj([video('a').copyWith(saturation: 1)])).filterGraph;
      expect(g, contains('scale=1920:1080:out_range=tv,format=yuv420p,eq=brightness=0:contrast=1:saturation=2,setsar=1'));
      g = build(proj([video('a'), video('b', w: 1080, h: 1920, fit: FitMode.fill).copyWith(contrast: 0.5)])).filterGraph;
      expect(g, contains('crop=1920:1080,format=yuv420p,eq=brightness=0:contrast=1.25:saturation=1,setsar=1'));
    });

    test('fit: before the bars are added, so they stay black', () {
      final g = build(proj([video('a'), video('b', w: 1080, h: 1920).copyWith(brightness: 1)])).filterGraph;
      expect(
          g,
          contains(':force_divisible_by=2:out_range=tv,format=yuv420p,'
              'eq=brightness=0.2:contrast=1:saturation=1,pad=1920:1080:'));
    });

    test('blur: once, after the overlay (picture and blurred background)', () {
      final g = build(proj([video('a'), video('b', w: 1080, h: 1920, fit: FitMode.blur).copyWith(brightness: -1)]))
          .filterGraph;
      expect(g, contains('[bg1][fg1]overlay=(W-w)/2:(H-h)/2,eq=brightness=-0.2:contrast=1:saturation=1,setsar=1'));
      expect(RegExp('eq=').allMatches(g).length, 1);
    });
  });

  group('zoom', () {
    test('centre crop then scale back, after fit', () {
      var g = build(proj([video('a').copyWith(zoom: 2)])).filterGraph;
      expect(g, contains('scale=1920:1080:out_range=tv,crop=960:540,scale=1920:1080:out_range=tv,setsar=1'));
      g = build(proj([video('a'), video('b', w: 1080, h: 1920).copyWith(zoom: 1.5)])).filterGraph;
      expect(g, contains('pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,crop=1280:720,scale=1920:1080:out_range=tv,'));
      g = build(proj([video('a'), video('b', w: 1080, h: 1920, fit: FitMode.fill).copyWith(zoom: 4)])).filterGraph;
      expect(g, contains('crop=1920:1080,crop=480:270,scale=1920:1080:out_range=tv,'));
    });

    test('1 (and less) is no zoom; more than 4 is 4; crop sizes are even', () {
      expect(build(proj([video('a').copyWith(zoom: 1)])).filterGraph, isNot(contains('crop=')));
      expect(build(proj([video('a').copyWith(zoom: 0.5)])).filterGraph, isNot(contains('crop=')));
      expect(build(proj([video('a').copyWith(zoom: 9)])).filterGraph, contains('crop=480:270,'));
      final m = RegExp(r'crop=(\d+):(\d+),').firstMatch(build(proj([video('a').copyWith(zoom: 1.7)])).filterGraph)!;
      expect(int.parse(m.group(1)!).isEven && int.parse(m.group(2)!).isEven, isTrue);
    });

    test('blur: only the fitted picture grows, the background chain is unchanged', () {
      final plain = build(proj([video('a'), video('b', w: 1080, h: 1920, fit: FitMode.blur)])).filterGraph;
      final g = build(proj([video('a'), video('b', w: 1080, h: 1920, fit: FitMode.blur).copyWith(zoom: 2)])).filterGraph;
      expect(chainTo(g, '[bg1]'), chainTo(plain, '[bg1]'));
      expect(
          chainTo(g, '[fg1]'),
          "[fgsrc1]scale=1920:1080:force_original_aspect_ratio=decrease:force_divisible_by=2:out_range=tv,"
          "crop='min(iw,960)':'min(ih,540)',scale='min(1920,2*round(iw*2/2))':'min(1080,2*round(ih*2/2))',setsar=1[fg1]");
      expect(g, contains('[bg1][fg1]overlay=(W-w)/2:(H-h)/2,setsar=1'));
    });

    test('zoom and colour together: colour first', () {
      final g = build(proj([video('a').copyWith(zoom: 2, saturation: -1)])).filterGraph;
      expect(g, contains('format=yuv420p,eq=brightness=0:contrast=1:saturation=0,crop=960:540,scale=1920:1080'));
    });
  });

  group('clean audio', () {
    test('chain: rumble filter, noise reduction, gentle levelling; no model files', () {
      expect(kDenoiseChain, 'highpass=f=80,afftdn=nr=12:nf=-35,dynaudnorm=f=250:g=7:p=0.8:m=2:b=1');
      expect(kDenoiseChain, isNot(contains('arnndn')));
      expect(kDenoiseChain, isNot(contains('loudnorm')));
    });

    test('applied per clip, before speed and volume', () {
      final g = build(proj([
        video('a').copyWith(denoise: true, speed: 2, volume: 0.5),
        video('b'),
      ])).filterGraph;
      expect(
          g,
          contains('[0:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,'
              '$kDenoiseChain,aformat=sample_fmts=fltp:channel_layouts=stereo,'
              'atempo=2,volume=0.5,apad,asetpts=N/SR/TB,atrim=end_sample=48000,'));
      expect(RegExp('afftdn').allMatches(g).length, 1);
    });

    test('nothing for muted clips, clips without sound and photos', () {
      final g = build(proj([
        video('a').copyWith(denoise: true, muted: true),
        photo('p').copyWith(denoise: true),
      ])).filterGraph;
      expect(g, isNot(contains('afftdn')));
    });
  });

  group('timeline in frames', () {
    test('cuts: boundaries are the model times rounded, so nothing adds up', () {
      // 0.75 s is 22.5 frames: rounding every clip up would drift.
      final p = proj([for (var i = 0; i < 12; i++) photo('p$i', ms: 750)]);
      final t = layoutTimeline(p, 30);
      expect(t.totalMs, 9000);
      expect(t.totalFrames, 270);
      expect(t.clips.map((c) => c.frames).toSet(), {22, 23});
      for (var i = 1; i < t.clips.length; i++) {
        expect(t.clips[i].start, t.clips[i - 1].end);
        expect(t.clips[i].overlapIn, 0);
      }
      final g = build(p).filterGraph;
      expect(g, contains('trim=end_frame=23,setpts=PTS-STARTPTS[v0]'));
      expect(g, contains('atrim=end_sample=36800,asetpts=PTS-STARTPTS[a0]'));
      expect(g, contains('trim=end_frame=22,setpts=PTS-STARTPTS[v1]'));
      expect(g, contains('atrim=end_sample=35200,asetpts=PTS-STARTPTS[a1]'));
    });

    test('transitions overlap; total equals Project.durationMs', () {
      final p = proj([
        video('a', outMs: 2000),
        video('b', outMs: 3000).copyWith(transition: TransitionType.crossfade, transitionMs: 500),
        video('c', outMs: 1000).copyWith(transition: TransitionType.slideLeft, transitionMs: 2000), // capped at 500
        video('d', outMs: 1000),
      ]);
      expect(p.durationMs, 6000);
      final t = layoutTimeline(p, 30);
      expect(t.totalMs, p.durationMs);
      expect(t.totalFrames, 180);
      expect(t.clips.map((c) => (c.start, c.frames, c.overlapIn, c.overlapOut)).toList(), [
        (0, 60, 0, 15),
        (45, 90, 15, 15),
        (120, 30, 15, 0),
        (150, 30, 0, 0),
      ]);
      expect(build(p).durationMs, 6000);
    });

    test('zero-length clips are left out and never take part in a transition', () {
      final p = proj([
        video('a', outMs: 1000),
        video('z', inMs: 500, outMs: 500),
        video('b', outMs: 1000).copyWith(transition: TransitionType.crossfade),
      ]);
      final t = layoutTimeline(p, 30);
      expect(t.clips.map((c) => c.clipIndex), [0, 2]);
      expect(t.clips.every((c) => c.overlapIn == 0 && c.overlapOut == 0), isTrue);
      expect(t.totalMs, p.durationMs);
    });

    test('transitionMs 0 and the first clip: no overlap', () {
      final p = proj([
        video('a').copyWith(transition: TransitionType.crossfade),
        video('b').copyWith(transition: TransitionType.crossfade, transitionMs: 0),
      ]);
      expect(build(p).filterGraph, isNot(contains('xfade')));
      expect(build(p).filterGraph, contains('[v0][a0][v1][a1]concat=n=2:v=1:a=1[vcat][acat]'));
    });

    test('other frame rates', () {
      final p = proj([
        video('a', outMs: 1000),
        video('b', outMs: 1000).copyWith(transition: TransitionType.crossfade, transitionMs: 400),
      ]);
      final c = build(p, options: const ExportOptions(fps: 25));
      expect(c.filterGraph, contains('xfade=transition=fade:duration=0.400000:offset=0'));
      expect(c.filterGraph, contains('acrossfade=ns=19200:'));
      expect(layoutTimeline(p, 25).totalFrames, 40);
      expect(layoutTimeline(p, 24).totalFrames, 38); // 1.6 s = 38.4 frames
    });
  });

  group('transitions', () {
    test('xfade names', () {
      expect(xfadeName(TransitionType.none), isNull);
      expect(xfadeName(TransitionType.crossfade), 'fade');
      expect(xfadeName(TransitionType.fadeBlack), 'fadeblack');
      expect(xfadeName(TransitionType.slideLeft), 'slideleft');
      expect(xfadeName(TransitionType.slideUp), 'slideup');
    });

    test('two clips: tail and head are split off, blended, and joined by concat', () {
      final p = proj([
        video('a', outMs: 2000),
        video('b', outMs: 2000).copyWith(transition: TransitionType.crossfade, transitionMs: 500),
      ]);
      final c = build(p);
      final g = c.filterGraph;
      expect(c.durationMs, 3500);
      expect(c.args[c.args.lastIndexOf('-t') + 1], '3.500');
      // Clip a: 60 frames = 45 alone + 15 shared.
      expect(g, contains('trim=end_frame=60,split=2[v0p1][v0p2]'));
      expect(g, contains('[v0p1]trim=start_frame=0:end_frame=45,setpts=PTS-STARTPTS[v0]'));
      expect(g, contains('[v0p2]trim=start_frame=45[v0t]'));
      expect(g, contains('atrim=end_sample=96000,asplit=2[a0p1][a0p2]'));
      expect(g, contains('[a0p1]atrim=start_sample=0:end_sample=72000,asetpts=PTS-STARTPTS[a0]'));
      expect(g, contains('[a0p2]atrim=start_sample=72000[a0t]'));
      // Clip b: 15 shared + 45 alone.
      expect(g, contains('trim=end_frame=60,split=2[v1p0][v1p1]'));
      expect(g, contains('[v1p0]trim=end_frame=15[v1h]'));
      expect(g, contains('[v1p1]trim=start_frame=15:end_frame=60,setpts=PTS-STARTPTS[v1]'));
      expect(g, contains('[a1p0]atrim=end_sample=24000[a1h]'));
      // The blend itself.
      expect(g, contains('[v0t][v1h]xfade=transition=fade:duration=0.500000:offset=0,setpts=PTS-STARTPTS[x1]'));
      expect(g, contains('[a0t][a1h]acrossfade=ns=24000:c1=tri:c2=tri,asetpts=N/SR/TB[xa1]'));
      expect(g, contains('[v0][a0][x1][xa1][v1][a1]concat=n=3:v=1:a=1[vcat][acat]'));
      // xfade needs equal size / SAR / pixel format / frame rate on both
      // inputs: every clip chain ends the same way.
      for (final label in ['[v0p1][v0p2]', '[v1p0][v1p1]']) {
        expect(chainTo(g, label), contains('fps=30,'));
        expect(chainTo(g, label), contains(',setsar=1,format=yuv420p,tpad=stop=-1:stop_mode=clone,trim=end_frame=60,'));
      }
    });

    test('every transition type', () {
      const names = {
        TransitionType.crossfade: 'fade',
        TransitionType.fadeBlack: 'fadeblack',
        TransitionType.slideLeft: 'slideleft',
        TransitionType.slideUp: 'slideup',
      };
      names.forEach((type, name) {
        final g = build(proj([video('a'), photo('b').copyWith(transition: type)])).filterGraph;
        expect(g, contains('xfade=transition=$name:duration=0.500000:offset=0'), reason: type.name);
        expect(g, contains('acrossfade=ns=24000'));
      });
    });

    test('hard cuts and transitions mixed', () {
      final g = build(proj([
        video('a'),
        video('b'),
        video('c').copyWith(transition: TransitionType.slideUp, transitionMs: 300),
        video('d'),
      ])).filterGraph;
      expect(RegExp('xfade=').allMatches(g).length, 1);
      expect(g, contains('[v1t][v2h]xfade=transition=slideup:duration=0.300000:offset=0'));
      expect(g, contains('[v0][a0][v1][a1][x2][xa2][v2][a2][v3][a3]concat=n=5:v=1:a=1[vcat][acat]'));
      // Untouched clips are not split.
      expect(g, contains('trim=end_frame=60,setpts=PTS-STARTPTS[v0]'));
      expect(g, contains('trim=end_frame=60,setpts=PTS-STARTPTS[v3]'));
    });

    test('a clip that is all transition has no body', () {
      // b (1 s) fades in over its first half and out over its second half.
      final p = proj([
        video('a'),
        video('b', outMs: 1000).copyWith(transition: TransitionType.crossfade, transitionMs: 500),
        video('c').copyWith(transition: TransitionType.fadeBlack, transitionMs: 500),
      ]);
      final c = build(p);
      final g = c.filterGraph;
      expect(c.durationMs, p.durationMs);
      expect(c.durationMs, 4000);
      expect(g, contains('trim=end_frame=30,split=2[v1p0][v1p2]'));
      expect(g, contains('[v1p0]trim=end_frame=15[v1h]'));
      expect(g, contains('[v1p2]trim=start_frame=15[v1t]'));
      expect(g, isNot(contains('[v1]')));
      expect(g, contains('[v0][a0][x1][xa1][x2][xa2][v2][a2]concat=n=4:v=1:a=1[vcat][acat]'));
    });

    test('titles and music still attach to the joined track', () {
      final c = build(proj([
        video('a'),
        video('b').copyWith(transition: TransitionType.crossfade),
      ], audio: [
        music('m')
      ], titles: [
        const TitleOverlay(id: 't', text: 'Hi', startMs: 0, endMs: 9000),
      ]));
      expect(c.filterGraph, contains('[vcat]drawtext='));
      // Title end and music length are clamped to the overlapped length.
      expect(c.filterGraph, contains(r'lt(t\,3.500)'));
      expect(c.args, containsAllInOrder(['-ss', '0.000', '-t', '3.500', '-i', '/media/m.mp3']));
    });
  });

  group('ducking', () {
    test('off: music is mixed straight in', () {
      final g = build(proj([video('a')], audio: [music('m')])).filterGraph;
      expect(g, isNot(contains('sidechaincompress')));
      expect(g, contains('[m0]apad,asetpts=N/SR/TB,atrim=duration=2.000,aformat=sample_fmts=fltp:channel_layouts=stereo[t0]'));
      expect(g, contains('[acat][t0]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,alimiter='));
    });

    test('on: the music is compressed with the main track as side chain', () {
      final g = build(proj([video('a')], audio: [music('m')], duckMusic: true)).filterGraph;
      expect(kDuckFilter, 'sidechaincompress=threshold=0.012:ratio=12:attack=30:release=400:mix=0.78');
      expect(g, contains('[m0]apad,asetpts=N/SR/TB,atrim=duration=2.000,aformat=sample_fmts=fltp:channel_layouts=stereo[t0]'));
      expect(g, contains('[acat]asplit=2[acatu0][acatu1]'));
      expect(g, contains('[t0][acatu1]$kDuckFilter[t0d]'));
      expect(
          g,
          contains('[acatu0][t0d]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,'
              'alimiter=limit=0.97:level=0,apad,atrim=duration=2.000,asetpts=PTS-STARTPTS[aout]'));
    });

    test('several music clips are ducked together', () {
      final g =
          build(proj([video('a')], audio: [music('m'), music('n', start: 500)], duckMusic: true)).filterGraph;
      expect(g, contains('[m0][m1]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,apad,asetpts=N/SR/TB,atrim=duration=2.000,'));
      expect(RegExp('sidechaincompress').allMatches(g).length, 1);
    });

    test('no music: nothing to duck', () {
      final c = build(proj([video('a')], duckMusic: true));
      expect(c.filterGraph, isNot(contains('sidechaincompress')));
      expect(c.args, containsAllInOrder(['-map', '[vcat]', '-map', '[acat]']));
    });
  });

  group('wrapped titles', () {
    const long = 'The quick brown fox jumps over the lazy dog and keeps on running far away';

    test('lines come from layoutTitleLines', () {
      const t = TitleOverlay(id: 't', text: long, startMs: 0, endMs: 1000, fontSize: 0.1);
      final p = proj([video('a')], titles: [t]);
      final lines = layoutTitleLines(t, canvasWidth: 1920, canvasHeight: 1080);
      expect(lines.length, greaterThan(1));
      final c = build(p);
      expect(c.textFiles.values.toList(), lines);
      expect(c.textFiles.keys.toList(), [for (var i = 0; i < lines.length; i++) '/tmp/w/title_0_$i.txt']);
      expect(RegExp('drawtext=').allMatches(c.filterGraph).length, lines.length);
      expect(c.filterGraph, contains('fontsize=${titleFontPx(t, 1080)}:'));
    });

    test('line breaks do not depend on the export quality', () {
      const t = TitleOverlay(id: 't', text: long, startMs: 0, endMs: 1000, fontSize: 0.0537);
      final p = proj([video('a')], titles: [t]);
      final full = build(p);
      final small = build(p, options: const ExportOptions(quality: ExportQuality.small));
      expect(small.textFiles.values.toList(), full.textFiles.values.toList());
      expect(small.filterGraph, contains('fontsize=${titleFontPx(t, 720)}:'));
    });

    test('caption with a box: one box around the whole wrapped block', () {
      final t = captionStyle(const TitleOverlay(id: 't', text: long, startMs: 0, endMs: 1000)).copyWith(fontSize: 0.1);
      expect(t.kind, TitleKind.caption);
      final c = build(proj([video('a')], titles: [t]));
      final lines = layoutTitleLines(t, canvasWidth: 1920, canvasHeight: 1080);
      expect(lines.length, greaterThan(1));
      // The box is one rectangle (drawbox), drawn before the lines.
      expect(c.textFiles.values.toList(), lines);
      expect(RegExp('drawbox=').allMatches(c.filterGraph).length, 1);
      expect(c.filterGraph, isNot(contains('box=1')));
      expect(c.filterGraph.indexOf('drawbox='), lessThan(c.filterGraph.indexOf('drawtext=')));
      expect(RegExp('drawtext=').allMatches(c.filterGraph).length, lines.length);
      // Lines of a boxed title have no shadow.
      expect(c.filterGraph, isNot(contains('shadowcolor')));
    });

    test('explicit newlines still work', () {
      final c = build(proj([video('a')], titles: [const TitleOverlay(id: 't', text: 'One\r\nTwo', startMs: 0, endMs: 1000)]));
      expect(c.textFiles.values.toList(), ['One', 'Two']);
    });

    test('projectNeedsFonts', () {
      expect(projectNeedsFonts(proj([video('a')])), isFalse);
      expect(projectNeedsFonts(proj([video('a')], titles: [const TitleOverlay(id: 't', text: ' ', startMs: 0, endMs: 1000)])), isFalse);
      expect(projectNeedsFonts(proj([video('a')], titles: [const TitleOverlay(id: 't', text: 'x', startMs: 0, endMs: 1000)])), isTrue);
    });
  });

  group('extractFrame commands', () {
    test('frame at a time: accurate seek before the input, one PNG', () {
      expect(buildExtractFrameCommand(path: '/m/a.mp4', outputPath: '/o/f.png', timeMs: 1234), [
        '-y', '-ss', '1.234', '-i', '/m/a.mp4', '-map', '0:v:0', '-frames:v', '1', //
        '-c:v', 'png', '-update', '1', '-f', 'image2', '/o/f.png',
      ]);
      final first = buildExtractFrameCommand(path: '/m/a.mp4', outputPath: '/o/f.png');
      expect(first, isNot(contains('-ss')));
      // Full resolution, rotation applied: no scaling and autorotate left on.
      expect(first, isNot(contains('-vf')));
      expect(first, isNot(contains('-noautorotate')));
    });

    test('last frame: the tail is decoded and every frame overwrites the file', () {
      final a = buildLastFrameCommand(path: '/m/a.mp4', outputPath: '/o/f.png', tailMs: 400);
      expect(a.sublist(0, 5), ['-y', '-sseof', '-0.400', '-i', '/m/a.mp4']);
      expect(a, isNot(contains('-frames:v')));
      expect(a, containsAllInOrder(['-update', '1', '-f', 'image2', '/o/f.png']));
    });
  });

  group('silence detection', () {
    test('command', () {
      expect(buildSilenceDetectCommand(path: '/m/a.mp4'),
          ['-i', '/m/a.mp4', '-map', '0:a:0', '-af', 'silencedetect=noise=-35dB:d=0.700', '-f', 'null', '-']);
      expect(buildSilenceDetectCommand(path: 'x', thresholdDb: -42.5, minSilenceMs: 1500)[5],
          'silencedetect=noise=-42.5dB:d=1.500');
    });

    test('pairs of silence_start / silence_end', () {
      const log = '''
Input #0, wav, from 'gaps.wav':
  Duration: 00:00:05.00, bitrate: 768 kb/s
[silencedetect @ 0x55d0c8a3b2c0] silence_start: 1.00002
[silencedetect @ 0x55d0c8a3b2c0] silence_end: 2.5 | silence_duration: 1.49998
[silencedetect @ 0x55d0c8a3b2c0] silence_start: 3.5
size=N/A time=00:00:05.00 bitrate=N/A speed= 964x
[silencedetect @ 0x55d0c8a3b2c0] silence_end: 5 | silence_duration: 1.5
''';
      expect(parseSilenceLog(log), [(startMs: 1000, endMs: 2500), (startMs: 3500, endMs: 5000)]);
    });

    test('trailing silence without an end line ends at the duration', () {
      const log = '[silencedetect @ 0x1] silence_start: 0.5\n'
          '[silencedetect @ 0x1] silence_end: 1.25 | silence_duration: 0.75\n'
          '[silencedetect @ 0x1] silence_start: 3.2\n';
      expect(parseSilenceLog(log, durationMs: 4000), [(startMs: 500, endMs: 1250), (startMs: 3200, endMs: 4000)]);
      // Without a known duration the open one cannot be closed.
      expect(parseSilenceLog(log), [(startMs: 500, endMs: 1250)]);
    });

    test('negative start, exponent notation, CRLF, split log chunks, clamping', () {
      // ffmpeg-kit delivers the log in pieces; they are simply concatenated.
      final log = ['[silencedetect @ 0x7f] ', 'silence_start: -0.0213', '\r\n', '[silencedetect @ 0x7f] ', 'silence_end: 1.5e+00 | silence_duration: 1.5213\r\n', '[silencedetect @ 0x7f] silence_start: 9.75\n', '[silencedetect @ 0x7f] silence_end: 10.02 | silence_duration: 0.27\n']
          .join();
      expect(parseSilenceLog(log, durationMs: 10000), [(startMs: 0, endMs: 1500), (startMs: 9750, endMs: 10000)]);
    });

    test('no silence, no audio, garbage', () {
      expect(parseSilenceLog(''), isEmpty);
      expect(parseSilenceLog('size=N/A time=00:00:05.00 bitrate=N/A', durationMs: 5000), isEmpty);
      expect(parseSilenceLog('silence_end: 2.0 | silence_duration: 1', durationMs: 5000), isEmpty);
      expect(parseSilenceLog('silence_start: abc\nsilence_end: 3', durationMs: 5000), isEmpty);
      // An empty range (start at the very end) is dropped.
      expect(parseSilenceLog('silence_start: 5.0', durationMs: 5000), isEmpty);
    });
  });

  group('plain Dart', () {
    // A command-line tool (no Flutter) must be able to import these files.
    test('builder, API types and ProcessMediaEngine import no Flutter or plugin code', () {
      final lib = Directory('lib').absolute.uri;
      final seen = <String>{};
      final foreign = <String>{};
      void visit(Uri file) {
        if (!seen.add(file.toFilePath())) return;
        final src = File.fromUri(file).readAsStringSync();
        for (final m in RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(src)) {
          final target = m.group(1)!;
          if (target.startsWith('dart:')) {
            if (target == 'dart:ui') foreign.add('$target (in $file)');
          } else if (target.startsWith('package:clipforge/')) {
            visit(lib.resolve(target.substring('package:clipforge/'.length)));
          } else if (target.startsWith('package:')) {
            if (!target.startsWith('package:path/')) foreign.add('$target (in $file)');
          } else {
            visit(file.resolve(target));
          }
        }
      }

      for (final f in ['media/ffmpeg_command.dart', 'media/media_api.dart', 'media/process_media_engine.dart']) {
        visit(lib.resolve(f));
      }
      expect(foreign, isEmpty);
      expect(seen.any((f) => f.endsWith('title_layout.dart')), isTrue);
      expect(seen.any((f) => f.endsWith('media_fonts.dart') || f.endsWith('ffmpeg_kit_media_engine.dart')), isFalse);
    });
  });
}
