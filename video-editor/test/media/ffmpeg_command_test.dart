import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(regular: '/f/Regular.ttf', bold: '/f/Bold.ttf');
final t0 = DateTime.utc(2026);

Clip video(String id,
        {int w = 1920,
        int h = 1080,
        int inMs = 0,
        int outMs = 2000,
        bool hasAudio = true,
        bool muted = false,
        double volume = 1,
        FitMode fit = FitMode.fit}) =>
    Clip(
        id: id,
        type: ClipType.video,
        path: '/media/$id.mp4',
        sourceDurationMs: 10000,
        inMs: inMs,
        outMs: outMs,
        width: w,
        height: h,
        hasAudio: hasAudio,
        muted: muted,
        volume: volume,
        fit: fit);

Clip photo(String id, {int w = 1000, int h = 1000, int ms = 3000, FitMode fit = FitMode.fit}) =>
    Clip(
        id: id,
        type: ClipType.photo,
        path: '/media/$id.jpg',
        sourceDurationMs: 0,
        inMs: 0,
        outMs: ms,
        width: w,
        height: h,
        hasAudio: false,
        fit: fit);

Project proj(List<Clip> clips,
        {CanvasAspect aspect = CanvasAspect.original,
        List<AudioClip> audio = const [],
        List<TitleOverlay> titles = const []}) =>
    Project(
        id: 'p',
        name: 'n',
        createdAt: t0,
        updatedAt: t0,
        aspect: aspect,
        clips: clips,
        audio: audio,
        titles: titles);

FfmpegCommand build(Project p,
        {ExportOptions options = const ExportOptions(), FontPaths f = fonts, String work = '/tmp/w'}) =>
    buildExportCommand(
        project: p, outputPath: '/out/o.mp4', fonts: f, workDir: work, options: options);

String after(List<String> args, String flag) => args[args.indexOf(flag) + 1];

void main() {
  group('basics', () {
    test('empty project throws ExportException', () {
      expect(() => build(proj([])), throwsA(isA<ExportException>()));
      // Zero-length clips only is empty as well.
      expect(() => build(proj([video('a', inMs: 500, outMs: 500)])),
          throwsA(isA<ExportException>()));
    });

    test('single clip: inputs, codecs and output flags', () {
      final c = build(proj([video('a', inMs: 1500, outMs: 4250)]));
      final a = c.args;
      expect(a.sublist(0, 7), ['-y', '-ss', '1.500', '-t', '2.750', '-i', '/media/a.mp4']);
      expect(after(a, '-c:v'), 'libx264');
      expect(after(a, '-c:a'), 'aac');
      expect(after(a, '-pix_fmt'), 'yuv420p');
      expect(after(a, '-color_range'), 'tv');
      expect(after(a, '-movflags'), '+faststart');
      expect(after(a, '-t', ), isNotEmpty);
      expect(a[a.lastIndexOf('-t') + 1], '2.750');
      expect(a.last, '/out/o.mp4');
      expect(after(a, '-filter_complex'), c.filterGraph);
      expect(c.filterGraph, contains('concat=n=1:v=1:a=1[vcat][acat]'));
      expect(after(a, '-map'), '[vcat]');
      expect(a, containsAllInOrder(['-map', '[vcat]', '-map', '[acat]']));
      expect(c.width, 1920);
      expect(c.height, 1080);
      expect(c.durationMs, 2750);
      expect(c.textFiles, isEmpty);
      // No shell string: the graph is one argument.
      expect(a.where((x) => x.contains('concat=')).length, 1);
    });

    test('same-shape clip is scaled without pad/crop', () {
      final g = build(proj([video('a')])).filterGraph;
      expect(g, contains('[0:v:0]fps=30,scale=1920:1080:out_range=tv,setsar=1,format=yuv420p'));
      expect(g, isNot(contains(',pad=')));
      expect(g, isNot(contains('crop=')));
    });

    test('photo is decoded once and held by the graph, with silence as audio', () {
      final c = build(proj([photo('p', ms: 3000)]));
      expect(c.args.sublist(1, 5), ['-framerate', '30', '-i', '/media/p.jpg']);
      expect(c.args, isNot(contains('-loop')));
      expect(c.filterGraph, contains('tpad=stop=-1:stop_mode=clone,trim=end_frame=90,'));
      expect(c.filterGraph, contains('anullsrc=r=48000:cl=stereo'));
      expect(c.filterGraph, contains('atrim=end_sample=144000'));
      expect(c.filterGraph, isNot(contains('[0:a')));
      expect(c.width, 1000);
    });

    test('odd source dimensions give an even canvas', () {
      final c = build(proj([video('a', w: 641, h: 361)]));
      expect(c.width.isEven && c.height.isEven, isTrue);
      expect(c.filterGraph, contains('scale=${c.width}:${c.height}:out_range=tv,setsar=1'));
    });

    test('fps option is used', () {
      final c = build(proj([video('a')]), options: const ExportOptions(fps: 24));
      expect(c.filterGraph, contains('fps=24,'));
      expect(after(c.args, '-r'), '24');
    });
  });

  group('fit modes', () {
    Project p(FitMode fit) => proj([
          video('a'),
          video('b', w: 1080, h: 1920, fit: fit),
        ]);

    test('fit pads with black', () {
      final g = build(p(FitMode.fit)).filterGraph;
      expect(
          g,
          contains('[1:v:0]fps=30,scale=1920:1080:force_original_aspect_ratio=decrease'
              ':force_divisible_by=2:out_range=tv,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black'));
    });

    test('fill covers and crops', () {
      final g = build(p(FitMode.fill)).filterGraph;
      expect(
          g,
          contains('[1:v:0]fps=30,scale=1920:1080:force_original_aspect_ratio=increase:out_range=tv,'
              'crop=1920:1080,setsar=1'));
    });

    test('blur overlays the fitted clip on a blurred cover copy', () {
      final g = build(p(FitMode.blur)).filterGraph;
      expect(g, contains('split=2[bgsrc1][fgsrc1]'));
      expect(g, contains('[bgsrc1]scale=480:270:force_original_aspect_ratio=increase,crop=480:270,gblur=sigma='));
      expect(g, contains('scale=1920:1080:out_range=tv,setsar=1[bg1]'));
      expect(g, contains('[bg1][fg1]overlay=(W-w)/2:(H-h)/2'));
      expect(g, contains('concat=n=2:v=1:a=1'));
    });
  });

  group('canvas', () {
    test('aspects', () {
      ({int width, int height}) size(CanvasAspect a) {
        final c = build(proj([video('a')], aspect: a));
        return (width: c.width, height: c.height);
      }

      expect(size(CanvasAspect.original), (width: 1920, height: 1080));
      expect(size(CanvasAspect.portrait9x16), (width: 1080, height: 1920));
      expect(size(CanvasAspect.landscape16x9), (width: 1920, height: 1080));
      expect(size(CanvasAspect.square1x1), (width: 1080, height: 1080));
      expect(size(CanvasAspect.portrait4x5), (width: 1080, height: 1350));
    });

    test('small quality: short side 720, even, lower bitrate', () {
      const small = ExportOptions(quality: ExportQuality.small);
      var c = build(proj([video('a')]), options: small);
      expect((c.width, c.height), (1280, 720));
      expect(after(c.args, '-crf'), '27');
      expect(c.args, contains('-maxrate'));
      expect(after(c.args, '-b:a'), '128k');
      c = build(proj([video('a')], aspect: CanvasAspect.portrait4x5), options: small);
      expect((c.width, c.height), (720, 900));
      c = build(proj([video('a', w: 1080, h: 1920)]), options: small);
      expect((c.width, c.height), (720, 1280));
      // Never upscales.
      c = build(proj([video('a', w: 640, h: 360)]), options: small);
      expect((c.width, c.height), (640, 360));
      // Odd result is rounded to even.
      c = build(proj([video('a', w: 1000, h: 1414)]), options: small);
      expect(c.width, 720);
      expect(c.height.isEven, isTrue);
      final full = build(proj([video('a')]));
      expect(after(full.args, '-crf'), '21');
      expect(full.args, isNot(contains('-maxrate')));
    });
  });

  group('clip audio', () {
    test('volume, mute and missing audio', () {
      final g = build(proj([
        video('a', volume: 0.5),
        video('b', muted: true),
        video('c', hasAudio: false),
        video('d'),
      ])).filterGraph;
      expect(g, contains('[0:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,volume=0.5,apad,asetpts=N/SR/TB,atrim=end_sample=96000,asetpts=PTS-STARTPTS[a0]'));
      expect(g, isNot(contains('[1:a')));
      expect(g, isNot(contains('[2:a')));
      expect(RegExp('anullsrc').allMatches(g).length, 2);
      expect(g, contains('[3:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,asetpts=N/SR/TB,'));
      expect(g, contains('[v0][a0][v1][a1][v2][a2][v3][a3]concat=n=4:v=1:a=1[vcat][acat]'));
    });
  });

  group('music', () {
    AudioClip music({int start = 1000, int inMs = 500, int outMs = 2500, double vol = 0.8, int fi = 300, int fo = 400}) =>
        AudioClip(
            id: 'm',
            path: '/media/m.mp3',
            sourceDurationMs: 60000,
            startMs: start,
            inMs: inMs,
            outMs: outMs,
            volume: vol,
            fadeInMs: fi,
            fadeOutMs: fo);

    test('trim, fades, volume, delay and un-normalised mix', () {
      final c = build(proj([video('a', outMs: 5000)], audio: [music()]));
      expect(c.args, containsAllInOrder(['-ss', '0.500', '-t', '2.000', '-i', '/media/m.mp3']));
      final g = c.filterGraph;
      expect(
          g,
          contains('[1:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,'
              'atrim=duration=2.000,asetpts=PTS-STARTPTS,'
              'afade=t=in:st=0:d=0.300,afade=t=out:st=1.600:d=0.400,'
              'volume=0.8,adelay=delays=1000:all=1[m0]'));
      expect(g, contains('[m0]apad,asetpts=N/SR/TB,atrim=duration=5.000,aformat=sample_fmts=fltp:channel_layouts=stereo[t0]'));
      expect(g, contains('[acat][t0]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0'));
      expect(g, contains('atrim=duration=5.000,asetpts=PTS-STARTPTS[aout]'));
      expect(c.args, containsAllInOrder(['-map', '[vcat]', '-map', '[aout]']));
    });

    test('music longer than the video: the fade-out finishes at the end of the video', () {
      // Heard from 1.0 to 2.0 s of a 2 s video; the song itself is 5 s.
      final c = build(proj([video('a', outMs: 2000)], audio: [music(start: 1000, inMs: 0, outMs: 5000, fi: 0, fo: 400)]));
      expect(c.args, containsAllInOrder(['-ss', '0.000', '-t', '1.000', '-i', '/media/m.mp3']));
      expect(c.filterGraph, contains('atrim=duration=1.000,asetpts=PTS-STARTPTS,afade=t=out:st=0.600:d=0.400,'));
      // Fades longer than what is heard are shortened to it.
      final g = build(proj([video('a', outMs: 2000)], audio: [music(start: 1500, inMs: 0, outMs: 5000, fi: 900, fo: 900)]))
          .filterGraph;
      expect(g, contains('afade=t=in:st=0:d=0.500,afade=t=out:st=0.000:d=0.500,'));
      // Started before the timeline: the fade still ends with the video.
      final h = build(proj([video('a', outMs: 2000)], audio: [music(start: -1000, inMs: 0, outMs: 9000, fi: 300, fo: 400)]));
      expect(h.args, containsAllInOrder(['-ss', '1.000', '-t', '2.000', '-i', '/media/m.mp3']));
      expect(h.filterGraph, contains('asetpts=PTS-STARTPTS,afade=t=out:st=1.600:d=0.400,'));
    });

    test('music past the end is cut; music after the end is dropped', () {
      var c = build(proj([video('a', outMs: 2000)], audio: [music(start: 1000, inMs: 0, outMs: 5000, fo: 0, fi: 0)]));
      expect(c.args, containsAllInOrder(['-ss', '0.000', '-t', '1.000', '-i', '/media/m.mp3']));
      for (final start in [2000, 2500, 60000]) {
        c = build(proj([video('a', outMs: 2000)], audio: [music(start: start)]));
        expect(c.filterGraph, isNot(contains('amix')));
        expect(c.filterGraph, isNot(contains('afade')));
        expect(c.args.where((a) => a == '-i').length, 1);
        expect(c.args, containsAllInOrder(['-map', '[vcat]', '-map', '[acat]']));
      }
      // One heard, one not: the graph has just the first.
      c = build(proj([video('a', outMs: 2000)], audio: [music(start: 0), music(start: 2000)]));
      expect(c.filterGraph, contains('[acat][t0]amix=inputs=2'));
      expect(c.filterGraph, isNot(contains('[m1]')));
    });

    test('two music clips and zero start', () {
      final g = build(proj([video('a', outMs: 5000)], audio: [music(start: 0), music(start: 2000)])).filterGraph;
      // On one track: mixed as the track, then with the clips' sound.
      expect(g, contains('[m0][m1]amix=inputs=2'));
      expect(g, contains('[acat][t0]amix=inputs=2'));
      expect(RegExp('adelay').allMatches(g).length, 1);
    });
  });

  group('titles', () {
    test('drawtext per line with textfile, timing, colour, font', () {
      final c = build(proj([
        video('a', outMs: 5000)
      ], titles: [
        const TitleOverlay(
            id: 't', text: 'Hello', startMs: 500, endMs: 2500, x: 0.25, y: 0.75, fontSize: 0.1, colorArgb: 0x80FF8000),
        const TitleOverlay(id: 'u', text: 'One\nTwo', startMs: 0, endMs: 9000, bold: false, background: true),
      ]));
      final g = c.filterGraph;
      expect(c.textFiles, {
        '/tmp/w/title_0_0.txt': 'Hello',
        '/tmp/w/title_1_0.txt': 'One',
        '/tmp/w/title_1_1.txt': 'Two',
      });
      expect(g, contains('[vcat]drawtext=fontfile=/f/Bold.ttf:textfile=/tmp/w/title_0_0.txt:expansion=none:fontsize=108:fontcolor=0xff8000@0.502'));
      expect(g, contains(r':x=480-text_w/2:y=848.88-ascent:enable=gte(t\,0.500)*lt(t\,2.500)'));
      // Second title: regular font, box, end clamped to the project length.
      // Its box is a rectangle of its own, sized by the shared layout.
      final b = layoutTitleBlock(const TitleOverlay(id: 'u', text: 'One\nTwo', startMs: 0, endMs: 9000, bold: false, background: true),
          canvasWidth: 1920, canvasHeight: 1080);
      expect((b.fontPx, b.lineHeightPx, b.boxPadPx, b.centerX, b.centerY), (65, 78, 19.5, 960, 540));
      expect(
          g,
          contains('drawbox=x=${(960 - b.width / 2 - 19.5).round()}:y=443:w=${(b.width + 39).round()}:h=195'
              r':color=black@0.55:t=fill:enable=gte(t\,0.000)*lt(t\,5.000),'
              'drawtext=fontfile=/f/Regular.ttf:textfile=/tmp/w/title_1_0.txt:expansion=none:fontsize=65:fontcolor=0xffffff@1'
              r':x=960-text_w/2:y=524.4-ascent:enable='));
      expect(g, contains(r':x=960-text_w/2:y=602.4-ascent:enable=gte(t\,0.000)*lt(t\,5.000)'));
      expect(RegExp('drawtext=').allMatches(g).length, 3);
      expect(RegExp('drawbox=').allMatches(g).length, 1);
      expect(g, isNot(contains('box=1')));
      expect(g, endsWith('[vout]'));
      expect(c.args, containsAllInOrder(['-map', '[vout]', '-map', '[acat]']));
      // The text itself never appears in the arguments.
      expect(c.args.join(' '), isNot(contains('Hello')));
    });

    test('awkward text only ever goes to text files', () {
      const text = "It's 100% \"fine\": a\\b, [x]; {y} %{pts}\nПривет, мир!\r\nשלום";
      final c = build(proj([video('a')], titles: [const TitleOverlay(id: 't', text: text, startMs: 0, endMs: 1000)]));
      expect(c.textFiles.values.toList(), ["It's 100% \"fine\": a\\b, [x]; {y} %{pts}", 'Привет, мир!', 'שלום']);
      expect(c.filterGraph, contains('expansion=none'));
      for (final a in c.args) {
        expect(a, isNot(contains('Привет')));
        expect(a, isNot(contains('100%')));
      }
    });

    test('empty, whitespace and out-of-range titles are skipped', () {
      final c = build(proj([
        video('a')
      ], titles: [
        const TitleOverlay(id: '1', text: '', startMs: 0, endMs: 1000),
        const TitleOverlay(id: '2', text: ' \n ', startMs: 0, endMs: 1000),
        const TitleOverlay(id: '3', text: 'late', startMs: 2000, endMs: 3000),
        const TitleOverlay(id: '4', text: 'backwards', startMs: 1000, endMs: 500),
      ]));
      expect(c.filterGraph, isNot(contains('drawtext')));
      expect(c.textFiles, isEmpty);
    });

    test('blank inner lines keep spacing but create no drawtext', () {
      final c = build(proj([video('a')], titles: [const TitleOverlay(id: 't', text: '\nA\n\nB\n', startMs: 0, endMs: 1000)]));
      // Lines are exactly those of layoutTitleLines (shared with the preview):
      // blank ones, also at the ends, take up a line.
      expect(c.textFiles.keys, ['/tmp/w/title_0_1.txt', '/tmp/w/title_0_3.txt']);
    });

    test('portrait canvas: size from the short side, block kept inside the frame', () {
      // A caption near the bottom of a 1080x1920 canvas.
      final t = captionStyle(const TitleOverlay(
              id: 't', text: 'A long caption that surely needs more than one line on a phone', startMs: 0, endMs: 1000))
          .copyWith(y: 0.99);
      final p = proj([video('a', w: 1080, h: 1920)], titles: [t]);
      final b = layoutTitleBlock(t, canvasWidth: 1080, canvasHeight: 1920);
      expect(b.fontPx, (0.045 * 1080).round());
      expect(b.lines.length, greaterThan(1));
      final g = build(p).filterGraph;
      expect(g, contains('fontsize=${b.fontPx.round()}:'));
      final m = RegExp(r'drawbox=x=(-?\d+):y=(-?\d+):w=(\d+):h=(\d+):').firstMatch(g)!;
      final x = int.parse(m.group(1)!), y = int.parse(m.group(2)!);
      final w = int.parse(m.group(3)!), h = int.parse(m.group(4)!);
      expect(x, greaterThanOrEqualTo(20));
      expect(x + w, lessThanOrEqualTo(1060));
      expect(y + h, lessThanOrEqualTo(1920 - 37));
      expect(y + h, greaterThan(1920 - 45));
      expect(h, (b.height + 2 * b.boxPadPx).round());
      // Small quality: the same layout, scaled by output height / canvas height.
      final small = build(p, options: const ExportOptions(quality: ExportQuality.small));
      expect((small.width, small.height), (720, 1280));
      expect(small.textFiles.values.toList(), b.lines);
      expect(small.filterGraph, contains('fontsize=${(b.fontPx * 2 / 3).round()}:'));
      final ms = RegExp(r'drawbox=x=(-?\d+):y=(-?\d+):w=(\d+):h=(\d+):').firstMatch(small.filterGraph)!;
      expect(int.parse(ms.group(1)!), closeTo(x * 2 / 3, 1));
      expect(int.parse(ms.group(2)!), closeTo(y * 2 / 3, 1));
      expect(int.parse(ms.group(3)!), closeTo(w * 2 / 3, 1));
      expect(int.parse(ms.group(4)!), closeTo(h * 2 / 3, 1));
      expect(small.filterGraph, contains(':x=${(b.centerX * 2 / 3).round()}-text_w/2:'));
    });

    test('paths in the graph are escaped (Windows drive, quotes, commas)', () {
      final c = build(
          proj([video('a')], titles: [const TitleOverlay(id: 't', text: 'x', startMs: 0, endMs: 1000)]),
          f: const FontPaths(regular: r'C:\Users\O' "'" r'Brien\fonts\R.ttf', bold: r'C:\Users\O' "'" r'Brien\fonts\B.ttf'),
          work: r'C:\Temp\a, b [c];d');
      expect(c.filterGraph, contains(r"fontfile=C\\:/Users/O\\\'Brien/fonts/B.ttf:"));
      expect(c.filterGraph, contains(r'textfile=C\\:/Temp/a\,\ b\ \[c\]\;d/title_0_0.txt:'));
      expect(c.textFiles.keys.single, r'C:\Temp\a, b [c];d/title_0_0.txt');
    });
  });

  group('helpers', () {
    test('escapeFilterValue', () {
      expect(escapeFilterValue('plain/path.ttf'), 'plain/path.ttf');
      expect(escapeFilterValue('a:b'), r'a\\:b');
      expect(escapeFilterValue("a'b"), r"a\\\'b");
      expect(escapeFilterValue(r'a\b'), r'a\\\\b');
      expect(escapeFilterValue('a,b;c[d]'), r'a\,b\;c\[d\]');
      expect(escapeFilterValue('a b'), r'a\ b');
      expect(escapeFilterValue('Привет'), 'Привет');
    });

    test('ffSeconds and ffColor', () {
      expect(ffSeconds(0), '0.000');
      expect(ffSeconds(1234567), '1234.567');
      expect(ffSeconds(5), '0.005');
      expect(ffColor(0xFFFFFFFF), '0xffffff@1');
      expect(ffColor(0x00000000), '0x000000@0');
      expect(ffColor(0xFF00FF7F), '0x00ff7f@1');
    });

    test('parseProgressLine', () {
      expect(parseProgressLine('out_time_us=500000', 1000), 0.5);
      expect(parseProgressLine('out_time_ms=250000', 1000), 0.25);
      expect(parseProgressLine('out_time_us=9000000', 1000), 1.0);
      expect(parseProgressLine('out_time_us=N/A', 1000), isNull);
      expect(parseProgressLine('out_time_us=-5', 1000), isNull);
      expect(parseProgressLine('progress=end', 1000), 1.0);
      expect(parseProgressLine('progress=continue', 1000), isNull);
      expect(parseProgressLine('frame=12', 1000), isNull);
    });

    test('thumbnail command', () {
      final a = buildThumbnailCommand(path: '/a b.mp4', outputPath: '/t.jpg', timeMs: 1500, maxHeight: 90);
      expect(a, containsAllInOrder(['-ss', '1.500', '-i', '/a b.mp4', '-frames:v', '1']));
      expect(after(a, '-vf'), "scale=-2:'min(90,ih)'");
      expect(a.last, '/t.jpg');
      expect(buildThumbnailCommand(path: 'x', outputPath: 'y'), isNot(contains('-ss')));
    });
  });

  group('parseProbeJson', () {
    test('video with rotation side data swaps to display size', () {
      final i = parseProbeJson({
        'streams': [
          {
            'codec_type': 'video', 'codec_name': 'h264', 'width': 1920, 'height': 1080,
            'side_data_list': [
              {'side_data_type': 'Display Matrix', 'rotation': -90}
            ]
          },
          {'codec_type': 'audio', 'codec_name': 'aac'}
        ],
        'format': {'format_name': 'mov,mp4,m4a,3gp,3g2,mj2', 'duration': '12.345000'}
      });
      expect((i.width, i.height), (1080, 1920));
      expect(i.durationMs, 12345);
      expect(i.hasVideo && i.hasAudio, isTrue);
    });

    test('legacy rotate tag, 180 keeps size', () {
      Map s(String r) => {
            'streams': [
              {'codec_type': 'video', 'codec_name': 'h264', 'width': 640, 'height': 360, 'tags': {'rotate': r}}
            ],
            'format': {'format_name': 'mov', 'duration': '1.0'}
          };
      expect(parseProbeJson(s('270')).width, 360);
      expect(parseProbeJson(s('180')).width, 640);
      expect(parseProbeJson(s('180')).hasAudio, isFalse);
    });

    test('still image has duration 0', () {
      final i = parseProbeJson({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'png', 'width': 400, 'height': 300}
        ],
        'format': {'format_name': 'png_pipe'}
      });
      expect(i.durationMs, 0);
      expect(i.hasVideo, isTrue);
      final j = parseProbeJson({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'mjpeg', 'width': 400, 'height': 300, 'duration': '0.040000'}
        ],
        'format': {'format_name': 'image2', 'duration': '0.040000'}
      });
      expect(j.durationMs, 0);
    });

    test('photo with EXIF orientation on the first frame', () {
      final i = parseProbeJson({
        'frames': [
          {
            'media_type': 'video',
            'side_data_list': [
              {'side_data_type': '3x3 displaymatrix', 'rotation': -90}
            ]
          }
        ],
        'streams': [
          {'codec_type': 'video', 'codec_name': 'mjpeg', 'width': 4000, 'height': 3000}
        ],
        'format': {'format_name': 'image2', 'duration': '0.04'}
      });
      expect((i.width, i.height, i.durationMs), (3000, 4000, 0));
    });

    test('audio-only, also with cover art', () {
      final i = parseProbeJson({
        'streams': [
          {'codec_type': 'audio', 'codec_name': 'mp3'},
          {
            'codec_type': 'video', 'codec_name': 'mjpeg', 'width': 500, 'height': 500,
            'disposition': {'attached_pic': 1}
          }
        ],
        'format': {'format_name': 'mp3', 'duration': '180.5'}
      });
      expect(i.hasVideo, isFalse);
      expect(i.hasAudio, isTrue);
      expect((i.width, i.height), (0, 0));
      expect(i.durationMs, 180500);
    });

    test('garbage is tolerated', () {
      final i = parseProbeJson({});
      expect(i.hasVideo || i.hasAudio, isFalse);
      expect(i.durationMs, 0);
      expect(i.fps, 0);
    });

    test('frame rate: average rate, r_frame_rate as fallback, 0 when unknown', () {
      MediaInfo v(Map<String, Object?> extra, {String format = 'mov,mp4,m4a,3gp,3g2,mj2'}) => parseProbeJson({
            'streams': [
              {'codec_type': 'video', 'codec_name': 'h264', 'width': 1920, 'height': 1080, ...extra}
            ],
            'format': {'format_name': format, 'duration': '3.0'}
          });
      expect(v({'r_frame_rate': '30/1', 'avg_frame_rate': '30/1'}).fps, 30);
      expect(v({'r_frame_rate': '60000/1001', 'avg_frame_rate': '60000/1001'}).fps, closeTo(59.94, 0.001));
      // Variable frame rate from a phone: r_frame_rate is not the real rate.
      expect(v({'r_frame_rate': '90000/1', 'avg_frame_rate': '359/12'}).fps, closeTo(29.92, 0.01));
      expect(v({'r_frame_rate': '120/1', 'avg_frame_rate': '30/1'}).fps, 30);
      expect(v({'r_frame_rate': '25/1', 'avg_frame_rate': '0/0'}).fps, 25);
      expect(v({'r_frame_rate': '0/0', 'avg_frame_rate': '0/0'}).fps, 0);
      expect(v({}).fps, 0);
      expect(v({'avg_frame_rate': 'x', 'r_frame_rate': 50}).fps, 50);
      // Photos and audio files have none.
      expect(v({'codec_name': 'png', 'r_frame_rate': '25/1', 'avg_frame_rate': '25/1'}, format: 'png_pipe').fps, 0);
      expect(
          parseProbeJson({
            'streams': [
              {'codec_type': 'audio', 'codec_name': 'mp3'}
            ],
            'format': {'format_name': 'mp3', 'duration': '9'}
          }).fps,
          0);
      expect(const MediaInfo(durationMs: 1, width: 2, height: 2, hasVideo: true, hasAudio: false).fps, 0);
    });

    test('parseFrameRate', () {
      expect(parseFrameRate('30000/1001'), closeTo(29.97, 0.001));
      expect(parseFrameRate('24'), 24);
      expect(parseFrameRate(' 50/1 '), 50);
      for (final bad in ['0/0', '30/0', '-30/1', '', 'a/b', '1/2/3', null, double.nan]) {
        expect(parseFrameRate(bad), 0, reason: '$bad');
      }
    });
  });

  group('suggestedFps', () {
    test('60 when any source has 50 fps or more', () {
      expect(ExportOptions.suggestedFps(const []), 30);
      expect(ExportOptions.suggestedFps(const [0, 24, 25, 29.97, 30]), 30);
      expect(ExportOptions.suggestedFps(const [30, 49.9]), 30);
      expect(ExportOptions.suggestedFps(const [30, 50]), 60);
      expect(ExportOptions.suggestedFps(const [59.94]), 60);
      expect(ExportOptions.suggestedFps(const [0, 120, double.nan]), 60);
      expect(ExportOptions.suggestedFps(const [double.nan, double.infinity]), 30);
      expect(const ExportOptions().fps, 30);
    });
  });

  group('failures', () {
    test('ExportException: missingPaths is empty unless given', () {
      expect(ExportException('x').missingPaths, isEmpty);
      expect(ExportException('x', missingPaths: const ['/a/b.mp4']).missingPaths, ['/a/b.mp4']);
    });

    test('summarizeFfmpegError picks the line that explains the failure', () {
      expect(
          summarizeFfmpegError('[mov,mp4,m4a,3gp,3g2,mj2 @ 0x55d0c4e2a480] moov atom not found\n'
              '[in#0 @ 0x55d0c4e2a1c0] Error opening input: Invalid data found when processing input\n'
              'Error opening input file /videos/holiday.mp4.\n'
              'Error opening input files: Invalid data found when processing input\n'),
          '/videos/holiday.mp4: Invalid data found when processing input');
      // FFmpeg 6 style.
      expect(summarizeFfmpegError('/videos/holiday.mp4: Invalid data found when processing input\n'),
          '/videos/holiday.mp4: Invalid data found when processing input');
      expect(
          summarizeFfmpegError('[out#0/mp4 @ 0x5581] Error writing trailer: No space left on device\r\n'
              '[aac @ 0x77] Qavg: 120.000\n'
              'Conversion failed!\n'),
          'Error writing trailer: No space left on device');
      // Nothing well known: the last line that is not a closing remark.
      expect(
          summarizeFfmpegError('[Parsed_drawtext_3 @ 0x1] Cannot find a valid font for the family Sans\n'
              '[AVFilterGraph @ 0x2] Error initializing filters\n'
              'Error while filtering: Something odd\n'
              'Conversion failed!\n\n'),
          'Cannot find a valid font for the family Sans');
      expect(summarizeFfmpegError('Conversion failed!\n'), 'Conversion failed!');
      expect(summarizeFfmpegError(''), isNull);
      expect(summarizeFfmpegError(' \n\r\n'), isNull);
      final long = summarizeFfmpegError('x' * 5000);
      expect(long!.length, 300);
    });
  });
}
