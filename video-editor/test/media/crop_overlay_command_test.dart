// 1.6: the export graph for crop and position and for the overlay track
// (pure: no ffmpeg needed). Real exports are in
// crop_overlay_integration_test.dart.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(regular: '/f/Regular.ttf', bold: '/f/Bold.ttf');
final t0 = DateTime.utc(2026);

Clip video(String id,
        {int inMs = 0,
        int outMs = 2000,
        FitMode fit = FitMode.fit,
        Framing framing = Framing.none,
        double zoom = 1}) =>
    Clip(
        id: id,
        type: ClipType.video,
        path: '/media/$id.mp4',
        sourceDurationMs: 10000,
        inMs: inMs,
        outMs: outMs,
        width: 1920,
        height: 1080,
        fit: fit,
        zoom: zoom,
        framing: framing);

OverlayClip overlay(String id,
        {int startMs = 500,
        int outMs = 1000,
        OverlayLayout layout = OverlayLayout.pip,
        bool muted = false,
        int fadeInMs = 0,
        bool photo = false,
        Framing framing = Framing.none}) =>
    OverlayClip(
      startMs: startMs,
      layout: layout,
      fadeInMs: fadeInMs,
      clip: Clip(
          id: id,
          type: photo ? ClipType.photo : ClipType.video,
          path: '/media/$id.${photo ? 'png' : 'mp4'}',
          sourceDurationMs: photo ? 0 : 5000,
          inMs: 0,
          outMs: outMs,
          width: 640,
          height: 480,
          hasAudio: !photo,
          muted: muted,
          framing: framing),
    );

Project proj(List<Clip> clips,
        {CanvasAspect aspect = CanvasAspect.original,
        List<OverlayClip> overlays = const []}) =>
    Project(
        id: 'p',
        name: 'n',
        createdAt: t0,
        updatedAt: t0,
        aspect: aspect,
        clips: clips,
        overlays: overlays);

FfmpegCommand build(Project p) => buildExportCommand(
    project: p, outputPath: '/out/x.mp4', fonts: fonts, workDir: '/tmp/w');

void main() {
  group('framingFilters', () {
    test('nothing for the default', () {
      expect(framingFilters(Framing.none), '');
    });

    test('turns, mirrors and crops in that order', () {
      expect(framingFilters(const Framing(rotation: 90)), 'transpose=clock,');
      expect(framingFilters(const Framing(rotation: 270)), 'transpose=cclock,');
      expect(framingFilters(const Framing(rotation: 180)), 'hflip,vflip,');
      // 180 + mirror sideways = upside down only.
      expect(framingFilters(const Framing(rotation: 180, flipH: true)), 'vflip,');
      expect(
          framingFilters(const Framing(
              rotation: 90, flipV: true, crop: CropRect(0.25, 0, 0.5, 1))),
          'transpose=clock,vflip,'
          'crop=w=trunc(iw*0.5/2)*2:h=trunc(ih*1/2)*2:x=trunc(iw*0.25):y=trunc(ih*0),');
    });
  });

  group('main track', () {
    test('a default clip makes the same graph as before 1.6', () {
      final g = build(proj([video('a')])).filterGraph;
      expect(g, isNot(contains('transpose')));
      expect(g, isNot(contains('flip')));
      expect(g, isNot(contains(':x=(iw-ow)')));
      expect(g, isNot(contains('overlay')));
    });

    test('framing comes right after the frame rate, before the fit', () {
      final g = build(proj([
        video('a', framing: const Framing(rotation: 90)),
      ])).filterGraph;
      expect(g, contains('fps=30,transpose=clock,scale=1920:1080:force_original_aspect_ratio=decrease'));
    });

    test('a crop to the frame\'s shape counts as the same shape', () {
      // 16:9 cut to its left half (8:9) on an 8:9 canvas: simply scaled.
      final c = video('a', framing: const Framing(crop: CropRect(0, 0, 0.5, 1)));
      final p = Project(
          id: 'p', name: 'n', createdAt: t0, updatedAt: t0,
          clips: [c], originalWidth: 960, originalHeight: 1080);
      final g = build(p).filterGraph;
      expect(g, contains('x=trunc(iw*0):y=trunc(ih*0),scale=960:1080:out_range=tv,setsar=1'));
    });

    test('fill and zoom crops follow the pan', () {
      final g = build(proj([
        video('a',
            fit: FitMode.fill,
            zoom: 2,
            framing: const Framing(panX: -1, panY: 0.5)),
      ], aspect: CanvasAspect.portrait9x16)).filterGraph;
      expect(g, contains('crop=1080:1920:x=(iw-ow)*0:y=(ih-oh)*0.75'));
      expect(g, contains('crop=540:960:x=(iw-ow)*0:y=(ih-oh)*0.75,scale=1080:1920'));
    });

    test('pieces of one file with different framing are not one input', () {
      final a = video('a', outMs: 1000);
      final b = video('a', inMs: 1000, outMs: 2000).copyWith(
          id: 'b', framing: const Framing(flipH: true));
      expect(build(proj([a, b])).args.where((x) => x == '-i'), hasLength(2));
      final same = b.copyWith(framing: Framing.none);
      expect(build(proj([a, same])).args.where((x) => x == '-i'), hasLength(1));
    });
  });

  group('overlay track', () {
    test('picture-in-picture: input, chain, overlay switched on in time', () {
      final cmd = build(proj([video('m')], overlays: [overlay('o')]));
      final g = cmd.filterGraph;
      expect(cmd.args.join(' '), contains('-ss 0.000 -t 1.000 -i /media/o.mp4'));
      // 640x480 in a third of 1920x1080: 475x356 -> even 476x356.
      expect(g, contains('[1:v:0]fps=30,scale=476:356:force_original_aspect_ratio=increase:out_range=tv,crop=476:356,setsar=1,format=yuva420p,tpad=stop=-1:stop_mode=clone,trim=end_frame=30,setpts=PTS-STARTPTS,setpts=PTS+0.500000/TB[ov0]'));
      expect(g, contains(r'[vcat][ov0]overlay=1412:691:eof_action=pass:repeatlast=0:enable=gte(t\,0.500000)*lt(t\,1.500000)[ovo0]'));
      // Titles would be drawn on [ovo0]; the video output is it.
      expect(cmd.args[cmd.args.indexOf('-map') + 1], '[ovo0]');
    });

    test('side by side moves the middle of the main picture', () {
      final g = build(proj([video('m')],
              overlays: [overlay('o', layout: OverlayLayout.sideBySide)]))
          .filterGraph;
      expect(g, contains('[vcat]split=2[ovb0][ovs0]'));
      expect(g, contains('[ovs0]crop=960:1080:480:0[ovm0]'));
      expect(g, contains('[ovb0][ovm0]overlay=0:0:enable='));
      expect(g, contains('[ovh0][ov0]overlay=960:0:'));
      expect(g, contains('scale=960:1080:force_original_aspect_ratio=increase'));
    });

    test('fades on the transparency, framing and pan of the overlay', () {
      final g = build(proj([video('m')], overlays: [
        overlay('o',
            layout: OverlayLayout.full,
            fadeInMs: 300,
            framing: const Framing(rotation: 90, panY: 1)),
      ])).filterGraph;
      expect(g, contains('fps=30,transpose=clock,scale=1920:1080'));
      expect(g, contains('crop=1920:1080:x=(iw-ow)*0.5:y=(ih-oh)*1'));
      expect(g, contains('fade=t=in:st=0:d=0.300:alpha=1'));
    });

    test('items past the end of the video are left out, long ones cut', () {
      final cmd = build(proj([video('m')], overlays: [
        overlay('late', startMs: 2500),
        overlay('long', startMs: 1500, outMs: 3000),
      ]));
      final g = cmd.filterGraph;
      expect(g, isNot(contains('late')));
      expect(g, contains('trim=end_frame=15,'));
    });

    test('a photo overlay is decoded once and held', () {
      final cmd = build(proj([video('m')], overlays: [overlay('p', photo: true)]));
      expect(cmd.args.join(' '), contains('-framerate 30 -i /media/p.png'));
    });

    test('its sound is a speech track at the video sound level', () {
      final g = build(proj([video('m')], overlays: [overlay('o')])).filterGraph;
      // Read once more for the sound, delayed to its start, mixed.
      expect(g, contains('adelay=delays=500:all=1'));
      expect(g, contains('amix=inputs=2'));
      final muted = build(proj([video('m')],
              overlays: [overlay('o', muted: true)]))
          .filterGraph;
      expect(muted, isNot(contains('adelay')));
      expect(muted, isNot(contains('[aout]')));
    });
  });
}
