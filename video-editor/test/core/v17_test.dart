// 1.7: fades, colour filters, title styles, duplicate, copy / paste
// settings, sound track order, quiet probe data, snapping, History names.

import 'dart:math' as math;

import 'package:clipforge/core/editor/edit_labels.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/editor/snapping.dart';
import 'package:clipforge/core/model/look_filter.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  var n = 0;
  ProjectEditor make(Project p) {
    n = 0;
    return ProjectEditor(p, clock: () => t0, newId: () => 'n${++n}');
  }

  List<String> labels(ProjectEditor e) => [for (final s in e.history) s.label];

  group('model', () {
    test('new fields survive JSON and default to "no change"', () {
      final c = video('a').copyWith(
          fadeInMs: 500,
          fadeOutMs: 700,
          filter: LookFilter.vintage,
          warmth: -0.3,
          frameRate: 29.97);
      final t = title('t').copyWith(
          font: TitleFont.handwritten,
          outline: true,
          outlineColorArgb: 0xFFFF0000,
          shadow: false,
          align: TitleAlign.right,
          animIn: TitleAnimation.pop,
          animOut: TitleAnimation.slideUp);
      final p = project(clips: [c], titles: [t])
          .copyWith(fadeInMs: 1000, fadeOutMs: 2000);
      final back = Project.fromJson(p.toJson());
      expect(content(back), content(p));
      final c2 = back.clips.single;
      expect([c2.fadeInMs, c2.fadeOutMs, c2.filter, c2.warmth, c2.frameRate],
          [500, 700, LookFilter.vintage, -0.3, 29.97]);
      final t2 = back.titles.single;
      expect([t2.font, t2.outline, t2.shadow, t2.align, t2.animIn, t2.animOut],
          [TitleFont.handwritten, true, false, TitleAlign.right,
           TitleAnimation.pop, TitleAnimation.slideUp]);
      // A 1.6 project: none of the keys.
      final old = Project.fromJson(project(clips: [video('a')], titles: [title('t')])
          .toJson()
        ..remove('fadeInMs')
        ..remove('fadeOutMs'));
      expect(old.fadeInMs, 0);
      final oc = (project(clips: [video('a')]).toJson()['clips'] as List).first
          as Map<String, dynamic>;
      for (final k in ['fadeInMs', 'fadeOutMs', 'filter', 'warmth', 'frameRate']) {
        oc.remove(k);
      }
      final plain = Clip.fromJson(oc);
      expect([plain.fadeInMs, plain.filter, plain.warmth, plain.frameRate],
          [0, LookFilter.none, 0, 0]);
      expect(TitleOverlay.fromJson({'id': 'x', 'startMs': 0, 'endMs': 1}).shadow,
          isTrue);
    });

    test('an overlay item keeps its own fades, not the clip ones', () {
      final o = OverlayClip(clip: video('o'), startMs: 0, fadeInMs: 300);
      final back = OverlayClip.fromJson(o.toJson());
      expect(back.fadeInMs, 300);
      expect(back.clip.fadeInMs, 0);
    });

    test('fade gains', () {
      final c = video('a', source: 4000).copyWith(fadeInMs: 1000, fadeOutMs: 2000);
      expect(c.fadeGainAt(0), 0);
      expect(c.fadeGainAt(500), closeTo(0.5, 1e-9));
      expect(c.fadeGainAt(1500), 1);
      expect(c.fadeGainAt(3000), closeTo(0.5, 1e-9));
      expect(c.fadeGainAt(4000), 0);
      final p = project(clips: [video('a', source: 4000)])
          .copyWith(fadeInMs: 3000, fadeOutMs: 0);
      // At most half the video.
      expect(p.projectFades.inMs, 2000);
      expect(p.fadeGainAt(1000), closeTo(0.5, 1e-9));
      expect(p.fadeGainAt(3000), 1);
      expect(project(clips: [video('a')]).fadeGainAt(0), 1);
    });
  });

  group('editor', () {
    test('clip fades are clamped and named', () {
      final e = make(project(clips: [video('a', source: 3000), video('b')]));
      e.setClipFades('a', fadeInMs: 99999);
      expect(e.project.clips.first.fadeInMs, 3000);
      e.setClipFades('a', fadeOutMs: 500);
      // Together never longer than the clip.
      expect(e.project.clips.first.fadeOutMs, 0);
      e.setClipFades('a', fadeInMs: 1000, fadeOutMs: 500);
      expect([e.project.clips.first.fadeInMs, e.project.clips.first.fadeOutMs],
          [1000, 500]);
      e.setClipFades('b', fadeOutMs: 0); // no change
      expect(labels(e), ['Fade in on clip 1', 'Fade in on clip 1']);
      e.setProjectFades(fadeInMs: 1500);
      e.setProjectFades(fadeOutMs: 50000);
      expect([e.project.fadeInMs, e.project.fadeOutMs], [1500, Project.maxFadeMs]);
      e.setProjectFades(fadeInMs: 0);
      expect(labels(e).sublist(2),
          ['Fade in from black', 'Fade out to black', 'No fade at the start']);
    });

    test('filter, warmth, reset look', () {
      final e = make(project(clips: [video('a'), video('b')]));
      e.setClipFilter('a', LookFilter.warm);
      e.setClipWarmth('a', 3);
      expect(e.project.clips.first.warmth, 1);
      e.setClipAdjustments('a', brightness: 0.2);
      e.resetLook('a');
      final c = e.project.clips.first;
      expect([c.filter, c.warmth, c.brightness, c.zoom],
          [LookFilter.none, 0, 0, 1]);
      expect(labels(e), [
        'Filter Warm on clip 1',
        'Warmth on clip 1',
        'Brightness on clip 1',
        'Reset look on clip 1',
      ]);
      e.setClipFilter('a', LookFilter.blackWhite);
      expect(e.applyClipSettingsToAll('a', look: true), 1);
      expect(e.project.clips[1].filter, LookFilter.blackWhite);
      expect(labels(e).last, 'Look of clip 1 applied to all clips');
    });

    test('duplicate a clip and a title', () {
      final e = make(project(clips: [video('a'), video('b')], titles: [
        title('t', startMs: 1000, endMs: 2500),
      ]));
      final id = e.duplicateClip('a')!;
      expect([for (final c in e.project.clips) c.id], ['a', id, 'b']);
      expect(e.project.clips[1].inMs, e.project.clips[0].inMs);
      final tid = e.duplicateTitle('t')!;
      final copy = e.project.titles.firstWhere((t) => t.id == tid);
      expect([copy.startMs, copy.endMs, copy.text], [2500, 4000, 'Hi']);
      expect(labels(e), ['Duplicated clip 1', 'Duplicated title']);
      expect(e.duplicateClip('nope'), isNull);
      e.undo();
      e.undo();
      expect(e.project.clips, hasLength(2));
    });

    test('a duplicated clip with separated sound gets its own sound', () {
      final e = make(project(clips: [video('a', source: 4000)]));
      e.separateSound('a');
      final id = e.duplicateClip('a')!;
      expect(e.project.audio.where((x) => x.sourceClipId == id), hasLength(1));
    });

    test('paste settings: look, speed, sound, crop - never trim or fades', () {
      final from = video('a').copyWith(
          brightness: 0.3,
          filter: LookFilter.cool,
          warmth: 0.4,
          zoom: 2,
          fit: FitMode.fill,
          speed: 2,
          volume: 0.5,
          denoise: true,
          framing: const Framing(rotation: 90),
          fadeInMs: 800,
          transition: TransitionType.crossfade,
          inMs: 1000);
      final e = make(project(clips: [from, video('b'), photo('p')]));
      final changed =
          e.pasteClipSettings(['b', 'p'], ClipSettings.of(e.project.clips.first));
      expect(changed, 2);
      final b = e.project.clips[1], p = e.project.clips[2];
      expect([b.brightness, b.filter, b.warmth, b.zoom, b.fit, b.speed, b.volume,
              b.denoise, b.framing.rotation],
          [0.3, LookFilter.cool, 0.4, 2, FitMode.fill, 2, 0.5, true, 90]);
      expect([b.inMs, b.fadeInMs, b.transition], [0, 0, TransitionType.none]);
      // A photo gets the look and crop, not speed or sound.
      expect([p.filter, p.speed, p.volume], [LookFilter.cool, 1, 1]);
      expect(labels(e), ['Pasted settings on 2 clips']);
      expect(e.pasteClipSettings(['b'], ClipSettings.of(e.project.clips.first)), 0);
      e.pasteClipSettings(['b'], ClipSettings.of(video('z')));
      expect(labels(e).last, 'Pasted settings on clip 2');
    });

    test('sound track order', () {
      final e = make(project());
      final a = e.addSoundTrack()!;
      final b = e.addSoundTrack()!;
      expect(e.moveSoundTrack(a, -1), isFalse);
      expect(e.moveSoundTrack(a, 1), isTrue);
      expect([for (final t in e.project.soundTracks) t.id], [b, a]);
      expect(labels(e).last, 'Moved sound track');
      e.undo();
      expect([for (final t in e.project.soundTracks) t.id], [a, b]);
    });

    test('probe data is not an undo step and survives undo', () {
      final e = make(project(clips: [video('a'), video('b')]));
      e.setClipVolume('a', 0.5);
      e.setClipAudioStreams('a', const [2, 6]);
      expect(e.history, hasLength(1));
      expect(e.project.clips.first.audioStreams, [2, 6]);
      e.undo();
      expect(e.project.clips.first.audioStreams, [2, 6]);
      e.redo();
      e.setProbeData('/media/b.mp4', frameRate: 25, hasAudio: false);
      expect(e.history, hasLength(1));
      expect([e.project.clips[1].frameRate, e.project.clips[1].hasAudio],
          [25, false]);
      // Inside a transaction: part of no step either.
      e.transaction(() {
        e.setClipMuted('a', true);
        e.setClipAudioStreams('b', const [1]);
      });
      expect(e.history, hasLength(2));
      e.undo();
      expect(e.project.clips[1].audioStreams, [1]);
    });

    test('History names: photo split, sound clip tracks', () {
      final e = make(project(clips: [photo('p')]));
      expect(e.splitAt(1000), isTrue);
      expect(labels(e), ['Split photo 1']);
      final before = project(audio: [audio('m')]);
      final after = before.copyWith(audio: [audio('m').copyWith(audioStreams: [2, 2])]);
      expect(describeEdit(before, after), 'Read sound tracks of music');
      final t0p = project(titles: [title('t')]);
      expect(
          describeEdit(t0p,
              t0p.copyWith(titles: [title('t').copyWith(font: TitleFont.modern)])),
          "Font Modern on title 'Hi'");
      expect(
          describeEdit(t0p,
              t0p.copyWith(titles: [title('t').copyWith(animIn: TitleAnimation.fade)])),
          "Fade in on title 'Hi'");
    });
  });

  group('title animation and layout', () {
    test('animation curves', () {
      final t = title('t', startMs: 1000, endMs: 5000)
          .copyWith(animIn: TitleAnimation.pop, animOut: TitleAnimation.slideUp);
      expect(titleAnimationAt(t, 1000).alpha, 0);
      expect(titleAnimationAt(t, 1000).scale, closeTo(kTitlePopFrom, 1e-9));
      expect(titleAnimationAt(t, 1200).scale, greaterThan(1)); // overshoot
      expect(titleAnimationAt(t, 1400).scale, closeTo(1, 1e-9));
      expect(titleAnimationAt(t, 3000), (alpha: 1.0, dy: 0.0, scale: 1.0));
      final out = titleAnimationAt(t, 4800);
      expect(out.alpha, closeTo(0.5, 1e-9));
      expect(out.dy, lessThan(0)); // moving up
      final short = title('s', startMs: 0, endMs: 300)
          .copyWith(animIn: TitleAnimation.fade);
      expect(titleAnimationLengths(short).inMs, 150);
      expect(titleAnimationLengths(title('x')), (inMs: 0, outMs: 0));
    });

    test('each font measures with its own widths', () {
      double w(TitleFont f) =>
          estimateTextWidth('Привет שלום Hello', fontPx: 100, bold: false, font: f);
      expect(w(TitleFont.handwritten), lessThan(w(TitleFont.classic) * 0.7));
      expect(w(TitleFont.modern), isNot(w(TitleFont.classic)));
      expect(allTitleFontFiles, hasLength(8));
      expect(titleFontFileName(TitleFont.elegant, true), 'BonaNova-Bold.ttf');
    });

    test('styles keep text, time and place', () {
      final t = title('t', text: 'Yo').copyWith(x: 0.2, y: 0.3, fontSize: 0.1);
      for (final p in kTitleStylePresets) {
        final s = p.apply(t);
        expect([s.text, s.startMs, s.endMs, s.x, s.y, s.fontSize],
            [t.text, t.startMs, t.endMs, t.x, t.y, t.fontSize], reason: p.key);
      }
    });
  });

  group('colour filters', () {
    List<double> apply(List<double> m, List<double> rgb) => [
          for (var r = 0; r < 3; r++)
            m[r * 4] * rgb[0] + m[r * 4 + 1] * rgb[1] + m[r * 4 + 2] * rgb[2] + m[r * 4 + 3],
        ];

    test('what each filter does', () {
      expect(clipLookMatrix(video('a')), isNull);
      final bw = apply(lookFilterMatrix(LookFilter.blackWhite), [1, 0, 0]);
      expect(bw[0], closeTo(bw[1], 1e-9));
      expect(bw[1], closeTo(bw[2], 1e-9));
      final warm = apply(lookFilterMatrix(LookFilter.warm), [0.5, 0.5, 0.5]);
      expect(warm[0], greaterThan(warm[2]));
      final cool = apply(lookFilterMatrix(LookFilter.cool), [0.5, 0.5, 0.5]);
      expect(cool[2], greaterThan(cool[0]));
      final vivid = apply(lookFilterMatrix(LookFilter.vivid), [0.8, 0.4, 0.2]);
      expect(vivid[0] - vivid[2], greaterThan(0.6));
      final vintage = apply(lookFilterMatrix(LookFilter.vintage), [0, 0, 0]);
      expect(vintage.reduce(math.min), greaterThan(0)); // lifted blacks
      final warmer = apply(clipLookMatrix(video('a').copyWith(warmth: 1))!, [0.5, 0.5, 0.5]);
      expect(warmer[0], greaterThan(warmer[2]));
    });
  });

  group('snapping', () {
    test('targets and snapping', () {
      final p = project(clips: [video('a', source: 2000), video('b', source: 3000)],
          titles: [title('t', startMs: 700, endMs: 1300)],
          audio: [audio('m', startMs: 4000, outMs: 500)]);
      final targets = snapTargets(p, playheadMs: 2600, ignoreId: 't');
      expect(targets, [0, 2000, 2600, 4000, 4500, 5000]);
      expect(snapTime(2550, targets, 100), (ms: 2600, snapped: 2600));
      expect(snapTime(2300, targets, 100), (ms: 2300, snapped: null));
      // The end of a 600 ms item lines up with 2000.
      expect(snapSpan(1450, 600, targets, 100), (start: 1400, snapped: 2000));
    });

    test('frame rate for "same as the clips"', () {
      expect(ExportOptions.sameAsSourceFps([29.97, 0]), 30);
      expect(ExportOptions.sameAsSourceFps([23.976, 25]), 25);
      expect(ExportOptions.sameAsSourceFps([120]), 60);
      expect(ExportOptions.sameAsSourceFps([]), 30);
    });
  });
}
