// 1.7 parts of the export command: fades, colour look, title styles, sound
// only. Pure: no ffmpeg needed (the real exports are in
// v17_integration_test.dart).

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(
    regular: '/f/R.ttf', bold: '/f/B.ttf', files: {'Rubik-Bold.ttf': '/f/RB.ttf'});

Clip v(String id, {int outMs = 2000}) => Clip(
    id: id,
    type: ClipType.video,
    path: '/m/$id.mp4',
    sourceDurationMs: 4000,
    inMs: 0,
    outMs: outMs,
    width: 1280,
    height: 720);

Project proj(List<Clip> clips, {List<TitleOverlay> titles = const []}) => Project(
    id: 'p',
    name: 'n',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    clips: clips,
    titles: titles);

FfmpegCommand build(Project p, {ExportOptions options = const ExportOptions()}) =>
    buildExportCommand(
        project: p, outputPath: '/o/out.mp4', fonts: fonts, workDir: '/w', options: options);

void main() {
  test('clip and project fades are frame / sample exact', () {
    final p = proj([v('a').copyWith(fadeInMs: 500, fadeOutMs: 1000)])
        .copyWith(fadeInMs: 1000, fadeOutMs: 200);
    final g = build(p).filterGraph;
    expect(g, contains('trim=end_frame=60,fade=t=in:s=0:n=15,fade=t=out:s=30:n=30'));
    expect(g, contains('afade=t=in:ss=0:ns=24000,afade=t=out:ss=48000:ns=48000'));
    expect(g, contains('fade=t=in:s=0:n=30,fade=t=out:s=54:n=6[vfade]'));
    expect(build(p).args, containsAllInOrder(['-map', '[vfade]', '-map', '[afade]']));
  });

  test('pieces with fades are not joined into one input', () {
    final a = v('a', outMs: 1000);
    final b = a.copyWith(id: 'b', inMs: 1000, outMs: 2000, fadeInMs: 300);
    final cmd = build(proj([a, b]));
    expect(cmd.args.where((x) => x == '-i'), hasLength(2));
  });

  test('a colour look adds one colour matrix after the eq', () {
    final g = build(proj([v('a').copyWith(filter: LookFilter.warm, brightness: 0.2)]))
        .filterGraph;
    expect(g, contains(',eq=brightness=0.04:contrast=1:saturation=1,format=gbrap,'
        'colorchannelmixer=rr=1.06:rg=0:rb=0:ra=0.02:gr=0:gg=1:gb=0:ga=0.01:'
        'br=0:bg=0:bb=0.86:ba=0,scale=out_range=tv,format=yuv420p'));
    expect(build(proj([v('a')])).filterGraph, isNot(contains('colorchannelmixer')));
  });

  test('title: font file, outline, no shadow, alignment, animation', () {
    final t = TitleOverlay(
        id: 't',
        text: 'Hi',
        startMs: 0,
        endMs: 2000,
        font: TitleFont.modern,
        outline: true,
        shadow: false,
        align: TitleAlign.left,
        animIn: TitleAnimation.pop);
    final g = build(proj([v('a')], titles: [t])).filterGraph;
    expect(g, contains('fontfile=/f/RB.ttf'));
    expect(g, contains(':borderw='));
    expect(g, isNot(contains('shadowcolor')));
    expect(g, contains(r'alpha=min(1\,3*clip((t-0.000)/0.400\,0\,1))'));
    // 1.8: no size expression (FFmpeg on CI crashed on it): every frame
    // of the pop has its own fixed size, enabled for that frame only.
    expect(g, isNot(contains('fontsize=4' r'4\\*')));
    expect(g, isNot(contains('sin(PI*')));
    final sizes = RegExp(r'fontsize=(\d+):').allMatches(g).map((m) => int.parse(m.group(1)!)).toList();
    expect(sizes.length, 13); // 12 frames of 0.4 s at 30 fps + the steady part
    expect(sizes.first, lessThan(sizes.last)); // grows
    expect(sizes.reduce((a, b) => a > b ? a : b), greaterThan(sizes.last)); // overshoot
    expect(g, contains(r'enable=gte(t\,0.400)*lt(t\,2.000)'));
    // A font that is not there is drawn in DejaVu Sans.
    final elegant = build(proj([v('a')], titles: [t.copyWith(font: TitleFont.elegant)]));
    expect(elegant.filterGraph, contains('fontfile=/f/B.ttf'));
  });

  test('an animated box is a colour picture faded and moved by overlay, '
      'not a drawtext box (1.8)', () {
    final t = TitleOverlay(
        id: 't',
        text: 'Hi',
        startMs: 0,
        endMs: 2000,
        background: true,
        animIn: TitleAnimation.slideUp,
        animOut: TitleAnimation.pop);
    final g = build(proj([v('a')], titles: [t])).filterGraph;
    expect(g, isNot(contains('boxw=')));
    expect(g, isNot(contains('box=1')));
    expect(g, contains('color=c=black@$kTitleBoxOpacity:s='));
    expect(g, contains('format=yuva420p,fade=t=in:st=0.000:d=0.400:alpha=1,'
        'fade=t=out:st=1.867:d=0.133:alpha=1[tb0b]'));
    expect(g, contains('[tb0a][tb0b]overlay=x='));
    expect(g, contains(':eval=frame:eof_action=pass:enable='));
  });

  test('sound only: no picture inputs or chains', () {
    final p = proj([
      v('a'),
      Clip(
          id: 'ph',
          type: ClipType.photo,
          path: '/m/p.jpg',
          sourceDurationMs: 0,
          inMs: 0,
          outMs: 1000,
          width: 100,
          height: 100,
          hasAudio: false),
    ], titles: [const TitleOverlay(id: 't', text: 'x', startMs: 0, endMs: 500)]);
    final m4a = build(p, options: const ExportOptions(format: ExportFormat.m4a));
    expect(m4a.filterGraph, isNot(contains('[0:v')));
    expect(m4a.filterGraph, isNot(contains('drawtext')));
    expect(m4a.filterGraph, contains('concat=n=2:v=0:a=1[acat]'));
    expect(m4a.args, containsAllInOrder(['-vn', '-i', '/m/a.mp4']));
    expect(m4a.args, isNot(contains('/m/p.jpg')));
    expect(m4a.args, containsAllInOrder(['-c:a', 'aac', '-f', 'ipod']));
    expect(m4a.textFiles, isEmpty);
    final mp3 = build(p, options: const ExportOptions(format: ExportFormat.mp3));
    expect(mp3.args, containsAllInOrder(['-c:a', 'libmp3lame', '-b:a', '192k', '-f', 'mp3']));
  });
}
