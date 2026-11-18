// Unit tests of "many pieces of one file": consecutive clips cut from the
// same source become ONE ffmpeg input (see ClipRun). No ffmpeg needed.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(regular: '/f/Regular.ttf', bold: '/f/Bold.ttf');
final t0 = DateTime.utc(2026);

Clip piece(int inMs, int outMs, {String file = 'talk', int w = 1280, int h = 720}) => Clip(
    id: '$file-$inMs',
    type: ClipType.video,
    path: '/media/$file.mp4',
    sourceDurationMs: 600000,
    inMs: inMs,
    outMs: outMs,
    width: w,
    height: h);

Project proj(List<Clip> clips, {List<AudioClip> audio = const []}) =>
    Project(id: 'p', name: 'n', createdAt: t0, updatedAt: t0, clips: clips, audio: audio);

FfmpegCommand build(Project p, {int fps = 30}) => buildExportCommand(
    project: p, outputPath: '/out/o.mp4', fonts: fonts, workDir: '/tmp/w', options: ExportOptions(fps: fps));

int inputs(FfmpegCommand c) => c.args.where((a) => a == '-i').length;

List<ClipRun> runsOf(Project p, {int fps = 30}) => findClipRuns(p, layoutTimeline(p, fps).clips, fps);

void main() {
  group('findClipRuns', () {
    test('pieces of one file in source order form one run with frame ranges', () {
      // 1.1 s pieces every 1.8 s, like speech with the pauses removed.
      final p = proj([for (var i = 0; i < 5; i++) piece(4000 + i * 1800, 4000 + i * 1800 + 1100)]);
      final r = runsOf(p).single;
      expect((r.first, r.last), (0, 4));
      expect(r.frames, layoutTimeline(p, 30).totalFrames);
      expect(r.frames, 165);
      expect(r.ranges, [
        (start: 0, end: 33),
        (start: 54, end: 87),
        (start: 108, end: 141),
        (start: 162, end: 195),
        (start: 216, end: 249),
      ]);
      expect(r.sourceFrames, 249);
      expect(r.expression, 'between(n,0,32)+between(n,54,86)+between(n,108,140)+between(n,162,194)+between(n,216,248)');
    });

    test('every piece has exactly its timeline frames, whatever the rounding', () {
      // 0.75 s is 22.5 frames; starts that are not on the frame grid.
      final p = proj([for (var i = 0; i < 12; i++) piece(1017 + i * 1310, 1017 + i * 1310 + 750)]);
      final placed = layoutTimeline(p, 30).clips;
      final r = runsOf(p).single;
      expect(r.ranges.length, 12);
      for (var i = 0; i < 12; i++) {
        expect(r.ranges[i].end - r.ranges[i].start, placed[i].frames, reason: 'piece $i');
        expect(r.ranges[i].start, (i * 1310 * 30 / 1000).round());
        if (i > 0) expect(r.ranges[i].start, greaterThanOrEqualTo(r.ranges[i - 1].end));
      }
      expect(r.frames, 270);
    });

    test('touching pieces (a plain split) stay in the run', () {
      final p = proj([piece(0, 1000), piece(1000, 2500), piece(2500, 2600)]);
      expect(runsOf(p).single.ranges, [(start: 0, end: 30), (start: 30, end: 75), (start: 75, end: 78)]);
    });

    test('what ends a run', () {
      List<(int, int)> spans(List<Clip> clips, {int fps = 30}) =>
          [for (final r in runsOf(proj(clips), fps: fps)) (r.first, r.last)];
      final a = piece(0, 1000), b = piece(2000, 3000), c = piece(4000, 5000), d = piece(6000, 7000);
      expect(spans([a, b, c, d]), [(0, 3)]);
      expect(spans([a]), isEmpty);
      // Another file, a photo.
      expect(spans([a, b, piece(4000, 5000, file: 'other'), d]), [(0, 1)]);
      expect(
          spans([
            a,
            b,
            Clip(id: 'ph', type: ClipType.photo, path: '/media/talk.mp4', sourceDurationMs: 0, inMs: 0, outMs: 900, width: 1280, height: 720),
            c,
            d
          ]),
          [(0, 1), (3, 4)]);
      // Different settings.
      for (final other in [
        c.copyWith(volume: 0.5),
        c.copyWith(muted: true),
        c.copyWith(fit: FitMode.blur),
        c.copyWith(zoom: 2),
        c.copyWith(brightness: 0.2),
        c.copyWith(contrast: 0.2),
        c.copyWith(saturation: -1),
        c.copyWith(denoise: true),
      ]) {
        expect(spans([a, b, other, d]), [(0, 1)]);
        expect(spans([a, b, other, other.copyWith(inMs: 6000, outMs: 7000)]), [(0, 1), (2, 3)]);
      }
      // A different speed ends it; the same speed on every piece does not.
      expect(spans([a, b, c.copyWith(speed: 2), d]), [(0, 1)]);
      expect(spans([a, b, c.copyWith(speed: 2), d.copyWith(speed: 2)]), [(0, 1), (2, 3)]);
      expect(spans([for (final x in [a, b, c, d]) x.copyWith(speed: 1.5)]), [(0, 3)]);
      expect(spans([for (final x in [a, b, c, d]) x.copyWith(speed: 0.25)]), [(0, 3)]);
      // Slow motion uses a finer grid (here 4 x 30 and 4 x 50 per second).
      expect(spans([for (final x in [a, b, c, d]) x.copyWith(speed: 0.3)], fps: 30), [(0, 3)]);
      expect(spans([for (final x in [a, b, c, d]) x.copyWith(speed: 0.3)], fps: 50), [(0, 3)]);
      // A transition into a piece takes that piece and the one before out.
      expect(spans([a, b, c.copyWith(transition: TransitionType.crossfade, transitionMs: 300), d]), isEmpty);
      expect(spans([a, b, c, d.copyWith(transition: TransitionType.crossfade, transitionMs: 300)]), [(0, 1)]);
      // Going back in the source, overlapping, or a long way ahead.
      expect(spans([b, a, c, d]), [(1, 3)]);
      expect(spans([a, piece(900, 1900), c, d]), [(1, 3)]);
      expect(spans([a, piece(1000 + kMaxRunGapMs, 13000), piece(14000, 15000)]), [(0, 2)]);
      expect(spans([a, piece(1001 + kMaxRunGapMs, 13000), piece(14000, 15000)]), [(1, 2)]);
      // A frame rate that does not divide the sample rate: no runs.
      expect(spans([a, b, c, d], fps: 60), [(0, 3)]);
      expect(spans([a, b, c, d], fps: 25), [(0, 3)]);
      expect(spans([a, b, c, d], fps: 29), isEmpty);
    });

    test('pieces that would share a frame are not joined', () {
      // Overlapping in the source: the first stays on its own.
      expect([for (final r in runsOf(proj([piece(0, 50), piece(44, 1000), piece(2000, 3000)]))) (r.first, r.last)], [(1, 2)]);
      // Each piece is at least one frame long on the timeline, so 10 ms
      // pieces would need the same source frame twice.
      final q = proj([piece(0, 10), piece(10, 20), piece(20, 1000)]);
      expect(runsOf(q), isEmpty);
      expect(inputs(build(q)), 3);
    });

    test('a speed on every piece: source ranges on the grid, total from the timeline', () {
      // 1.5 s pieces every 1.8 s at 1.25x: 1.2 s = 36 frames each.
      final p = proj([for (var i = 0; i < 100; i++) piece(1600 + i * 1800, 3100 + i * 1800).copyWith(speed: 1.25)]);
      final r = runsOf(p).single;
      expect((r.speed, r.gridFps), (1.25, 30));
      expect(r.frames, layoutTimeline(p, 30).totalFrames);
      expect(r.frames, 3600);
      // Ranges are SOURCE frames: 45 per piece, 54 apart.
      expect(r.ranges.take(3), [(start: 0, end: 45), (start: 54, end: 99), (start: 108, end: 153)]);
      expect(r.sourceFrames, 99 * 54 + 45);
      // Odd lengths: the run total is still what the timeline says.
      final q = proj([for (var i = 0; i < 37; i++) piece(i * 1310 + 7, i * 1310 + 7 + 770 + i % 5).copyWith(speed: 1.5)]);
      final t = layoutTimeline(q, 30);
      expect(runsOf(q).single.frames, t.totalFrames);
      expect(t.totalFrames, (q.durationMs * 30 / 1000).round());
      // Slow motion: twice / four times the export rate.
      Project slow(double s) => proj([piece(0, 1000).copyWith(speed: s), piece(2000, 3000).copyWith(speed: s)]);
      expect(runsOf(slow(0.5)).single.gridFps, 60);
      expect(runsOf(slow(0.5)).single.ranges, [(start: 0, end: 60), (start: 120, end: 180)]);
      expect(runsOf(slow(0.5)).single.frames, 120);
      expect(runsOf(slow(0.25)).single.gridFps, 120);
      expect(runsOf(slow(0.75)).single.gridFps, 60);
    });

    test('very long runs are divided', () {
      final p = proj([for (var i = 0; i < 450; i++) piece(i * 1000, i * 1000 + 600)]);
      final r = runsOf(p);
      expect([for (final x in r) x.ranges.length], [200, 200, 50]);
      expect(inputs(build(p)), 3);
      expect(r.fold<int>(0, (s, x) => s + x.frames), layoutTimeline(p, 30).totalFrames);
    });
  });

  group('graph in a file', () {
    test('only graphs too long for an argument', () {
      final small = build(proj([for (var i = 0; i < 100; i++) piece(i * 1800, i * 1800 + 1100)]));
      expect(small.needsGraphFile, isFalse);
      // 500 clips that cannot share inputs.
      final big = build(proj([for (var i = 0; i < 500; i++) piece(0, 200, file: i.isEven ? 'a' : 'b')]));
      expect(big.filterGraph.length, greaterThan(131072));
      expect(big.needsGraphFile, isTrue);
      for (final option in ['-filter_complex_script', '-/filter_complex']) {
        final args = big.argsWithGraphFile('/w/graph.txt', option);
        expect(args.length, big.args.length);
        expect(args, isNot(contains('-filter_complex')));
        expect(args, isNot(contains(big.filterGraph)));
        final i = args.indexOf(option);
        expect(args[i + 1], '/w/graph.txt');
        expect(args.sublist(0, i), big.args.sublist(0, i));
        expect(args.sublist(i + 2), big.args.sublist(i + 2));
        expect(args.every((a) => a.length < 2000), isTrue);
      }
      expect(kMaxInlineGraphChars, lessThan(32767));
    });

    test('the option depends on the ffmpeg version', () {
      expect(ffmpegMajorVersion('ffmpeg version 6.1.1-3ubuntu5 Copyright (c) 2000-2023 the FFmpeg developers\nbuilt with gcc'), 6);
      expect(ffmpegMajorVersion('ffmpeg version n8.0.1 Copyright (c) 2000-2025'), 8);
      expect(ffmpegMajorVersion('ffmpeg version 7.1-full_build-www.gyan.dev Copyright'), 7);
      expect(ffmpegMajorVersion('ffmpeg version 4.4.2-0ubuntu0.22.04.1'), 4);
      expect(ffmpegMajorVersion('8.1'), 8);
      expect(ffmpegMajorVersion('n8.1'), 8);
      expect(ffmpegMajorVersion(' v6.0 '), 6);
      expect(ffmpegMajorVersion('ffmpeg version N-118193-g5f38c82536 Copyright'), isNull);
      expect(ffmpegMajorVersion('ffmpeg version git-2025-01-01-abcdef'), isNull);
      expect(ffmpegMajorVersion(''), isNull);
      expect(graphFileOption(4), '-filter_complex_script');
      expect(graphFileOption(6), '-filter_complex_script');
      expect(graphFileOption(7), '-/filter_complex');
      expect(graphFileOption(8), '-/filter_complex');
      expect(graphFileOption(null), '-/filter_complex');
    });
  });

  group('graph', () {
    test('one input, one picture chain, one sound chain', () {
      final p = proj([for (var i = 0; i < 100; i++) piece(i * 1800, i * 1800 + 1100)]);
      final c = build(p);
      expect(inputs(c), 1);
      // From the first piece's start to the last frame needed (+0.5 s).
      expect(c.args.sublist(1, 7), ['-ss', '0.000', '-t', '179.800', '-i', '/media/talk.mp4']);
      final g = c.filterGraph;
      final r = runsOf(p).single;
      expect(r.sourceFrames, 5379);
      expect(
          g,
          contains("[0:v:0]fps=30:start_time=0,tpad=stop=-1:stop_mode=clone,trim=end_frame=5379,"
              "select='${r.expression}',setpts=N/30/TB,"
              'scale=1280:720:out_range=tv,setsar=1,format=yuv420p,'
              'tpad=stop=-1:stop_mode=clone,trim=end_frame=3300,setpts=PTS-STARTPTS[v0]'));
      expect(
          g,
          contains('[0:a:0]aresample=48000:async=1:first_pts=0,aformat=sample_fmts=fltp:channel_layouts=stereo,'
              'apad,atrim=end_sample=${5379 * 1600},asplit=100[a0s0][a0s1]'));
      // The sound: one atrim per piece at the picture's frame numbers (in
      // samples), joined. Not aselect, which FFmpeg 8.0 ignores.
      expect(g, isNot(contains('aselect')));
      expect(g, contains('[a0s0]atrim=start_sample=0:end_sample=${33 * 1600},asetpts=PTS-STARTPTS[a0c0];'));
      expect(g, contains('[a0s1]atrim=start_sample=${54 * 1600}:end_sample=${87 * 1600},asetpts=PTS-STARTPTS[a0c1];'));
      expect(g, contains('[a0s99]atrim=start_sample=${5346 * 1600}:end_sample=${5379 * 1600},asetpts=PTS-STARTPTS[a0c99];'));
      expect(RegExp(r'\[a0s\d+\]atrim=').allMatches(g).length, 100);
      expect(
          g,
          contains('[a0c98][a0c99]concat=n=100:v=0:a=1,asetpts=N/SR/TB,'
              'atrim=end_sample=${3300 * 1600},asetpts=PTS-STARTPTS[a0]'));
      expect(g, endsWith('[v0][a0]concat=n=1:v=1:a=1[vcat][acat]'));
      expect(c.durationMs, 110000);
      // Far shorter than one chain per piece (about 30000 here): per piece
      // a `between` for the picture and a short atrim for the sound.
      expect(g.length, lessThan(15000));
    });

    test('settings of the pieces apply to the whole run', () {
      Clip s(Clip c) => c.copyWith(volume: 0.5, denoise: true, fit: FitMode.fill, zoom: 2, saturation: -1);
      final g = build(proj([s(piece(0, 1000, w: 720, h: 1280)), s(piece(2000, 3000, w: 720, h: 1280)), piece(0, 500, file: 'x')]))
          .filterGraph;
      final v = g.split(';').firstWhere((c) => c.endsWith('[v0]'));
      expect(v, contains("select='between(n,0,29)+between(n,60,89)',setpts=N/30/TB,scale=720:1280"));
      expect(v, contains('eq=brightness=0:contrast=1:saturation=0'));
      expect(v, contains('crop=360:640,scale=720:1280'));
      expect(v, endsWith('trim=end_frame=60,setpts=PTS-STARTPTS[v0]'));
      // Clean-up and volume once, on the source, before it is cut up.
      final src = g.split(';').firstWhere((c) => c.startsWith('[0:a:0]'));
      expect(src, endsWith('$kDenoiseChain,aformat=sample_fmts=fltp:channel_layouts=stereo,volume=0.5,apad,atrim=end_sample=144000,'
          'asplit=2[a0s0][a0s1]'));
      final a = g.split(';').firstWhere((c) => c.endsWith('[a0]'));
      expect(a, startsWith('[a0c0][a0c1]concat=n=2:v=0:a=1,asetpts=N/SR/TB,'));
      expect(a, endsWith('atrim=end_sample=96000,asetpts=PTS-STARTPTS[a0]'));
    });

    test('speed is applied once, to the joined pieces', () {
      final p = proj([for (var i = 0; i < 100; i++) piece(1600 + i * 1800, 3100 + i * 1800).copyWith(speed: 1.25)]);
      final c = build(p);
      expect(inputs(c), 1);
      expect(c.args.sublist(1, 7), ['-ss', '1.600', '-t', '180.200', '-i', '/media/talk.mp4']);
      final r = runsOf(p).single;
      final g = c.filterGraph;
      expect(RegExp('atempo=').allMatches(g).length, 1);
      expect(RegExp('setpts=N/37.5/TB').allMatches(g).length, 1);
      expect(
          g,
          contains("[0:v:0]fps=30:start_time=0,tpad=stop=-1:stop_mode=clone,trim=end_frame=5391,"
              "select='${r.expression}',setpts=N/37.5/TB,fps=30,"
              'scale=1280:720:out_range=tv,setsar=1,format=yuv420p,'
              // Held or cut to the frames the timeline gives the run.
              'tpad=stop=-1:stop_mode=clone,trim=end_frame=3600,setpts=PTS-STARTPTS[v0]'));
      expect(
          g,
          contains('apad,atrim=end_sample=${5391 * 1600},asplit=100[a0s0]'));
      expect(
          g,
          contains('[a0c99]concat=n=100:v=0:a=1,asetpts=N/SR/TB,atempo=1.25,apad,asetpts=N/SR/TB,'
              'atrim=end_sample=${3600 * 1600},asetpts=PTS-STARTPTS[a0]'));
      expect(c.durationMs, 120000);
      // 4x: two tempo stages; slow motion: finer grid for picture and sound.
      final fast = build(proj([piece(0, 4000).copyWith(speed: 4), piece(5000, 9000).copyWith(speed: 4)])).filterGraph;
      expect(fast, contains("setpts=N/120/TB,fps=30,"));
      expect(fast, contains('asetpts=N/SR/TB,atempo=2,atempo=2,apad,'));
      final slow = build(proj([piece(0, 1000).copyWith(speed: 0.5), piece(2000, 3000).copyWith(speed: 0.5)])).filterGraph;
      expect(slow, contains("[0:v:0]fps=60:start_time=0,tpad=stop=-1:stop_mode=clone,trim=end_frame=180,"
          "select='between(n,0,59)+between(n,120,179)',setpts=N/30/TB,fps=30,"));
      // 60 per second: 800 samples a frame.
      expect(slow, contains('[a0s1]atrim=start_sample=${120 * 800}:end_sample=${180 * 800},'));
      expect(slow, contains('atempo=0.5,apad,asetpts=N/SR/TB,atrim=end_sample=192000,'));
    });

    test('clean audio on every piece: the chain runs once, over the run', () {
      final g = build(proj([for (var i = 0; i < 20; i++) piece(i * 1800, i * 1800 + 1100).copyWith(denoise: true, speed: 1.25)]))
          .filterGraph;
      expect(RegExp('afftdn').allMatches(g).length, 1);
      expect(g, contains('$kDenoiseChain,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim='));
      expect(g.indexOf('afftdn'), lessThan(g.indexOf('asplit=20')));
      expect(g.indexOf('concat=n=20:v=0:a=1'), lessThan(g.indexOf('atempo')));
      expect(g.indexOf('asplit=20'), lessThan(g.indexOf('concat=n=20:v=0:a=1')));
    });

    test('muted pieces: silence of the run length', () {
      final g = build(proj([piece(0, 1000).copyWith(muted: true), piece(2000, 3000).copyWith(muted: true)])).filterGraph;
      expect(g, contains('anullsrc=r=48000:cl=stereo,aformat=sample_fmts=fltp,atrim=end_sample=96000,asetpts=PTS-STARTPTS[a0]'));
      expect(g, isNot(contains('asplit')));
      expect(g, isNot(contains('[0:a')));
    });

    test('runs between other clips: labels, input numbers, concat order, music', () {
      final p = proj([
        piece(0, 1000, file: 'intro'),
        piece(0, 1000),
        piece(1500, 2500),
        piece(3000, 4000),
        piece(0, 1000, file: 'mid').copyWith(transition: TransitionType.crossfade, transitionMs: 400),
        piece(5000, 6000),
        piece(6500, 7500),
      ], audio: [
        const AudioClip(id: 'm', path: '/media/m.mp3', sourceDurationMs: 60000, startMs: 0, inMs: 0, outMs: 60000)
      ]);
      // intro | run(1,2) | 3 -> mid with a crossfade | run(5,6)
      expect([for (final r in runsOf(p)) (r.first, r.last)], [(1, 2), (5, 6)]);
      final c = build(p);
      expect(inputs(c), 6);
      expect([for (var i = 0; i < c.args.length; i++) if (c.args[i] == '-i') c.args[i + 1]],
          ['/media/intro.mp4', '/media/talk.mp4', '/media/talk.mp4', '/media/mid.mp4', '/media/talk.mp4', '/media/m.mp3']);
      final g = c.filterGraph;
      expect(g, contains("[1:v:0]fps=30:start_time=0,tpad=stop=-1:stop_mode=clone,trim=end_frame=75,select='between(n,0,29)+between(n,45,74)'"));
      expect(g, contains('[2:v:0]fps=30,'));
      expect(g, contains('[v3t][v4h]xfade=transition=fade'));
      expect(g, contains("[4:a:0]aresample=48000:async=1:first_pts=0,"));
      expect(g, contains('[5:a:0]aresample=48000,'));
      expect(g, contains('[v0][a0][v1][a1][v3][a3][x4][xa4][v4][a4][v5][a5]concat=n=6:v=1:a=1[vcat][acat]'));
      expect(c.durationMs, p.durationMs);
    });

    test('60 fps', () {
      final g = build(proj([piece(0, 1000), piece(2000, 3000)]), fps: 60).filterGraph;
      expect(g, contains("fps=60:start_time=0,tpad=stop=-1:stop_mode=clone,trim=end_frame=180,select='between(n,0,59)+between(n,120,179)',setpts=N/60/TB,"));
      expect(g, contains('[a0s1]atrim=start_sample=${120 * 800}:end_sample=${180 * 800},'));
    });
  });
}
