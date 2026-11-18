import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const min = EditorController.minDurationMs;
const fade = TransitionType.crossfade;

class Harness {
  Harness(Project p) {
    c = EditorController(
      p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'new${++ids}',
    );
    c.addListener(() => notifications++);
  }
  late final EditorController c;
  DateTime now = t0;
  int ids = 0;
  int notifications = 0;

  Project get p => c.project;
  List<String> get clipIds => [for (final c in p.clips) c.id];
  Clip clip(String id) => p.clips.firstWhere((c) => c.id == id);

  /// Undo steps available.
  int get undoSteps {
    var n = 0;
    while (c.canUndo) {
      c.undo();
      n++;
    }
    for (var i = 0; i < n; i++) {
      c.redo();
    }
    return n;
  }
}

void main() {
  group('speed', () {
    test('setClipSpeed clamps, changes the timeline length, keeps the trim', () {
      final h = Harness(project(clips: [video('a', inMs: 1000, outMs: 9000)]));
      h.c.setClipSpeed('a', 2);
      expect(h.clip('a').speed, 2);
      expect(h.clip('a').inMs, 1000);
      expect(h.clip('a').outMs, 9000);
      expect(h.p.durationMs, 4000);
      h.c.setClipSpeed('a', 100);
      expect(h.clip('a').speed, EditorController.maxSpeed);
      expect(h.p.durationMs, 2000);
      h.c.setClipSpeed('a', 0);
      expect(h.clip('a').speed, EditorController.minSpeed);
      expect(h.p.durationMs, 32000);
      h.c.setClipSpeed('a', double.negativeInfinity);
      expect(h.clip('a').speed, 0.25);
      h.c.setClipSpeed('a', double.infinity);
      expect(h.clip('a').speed, 4);
    });

    test('NaN, same value, photos and unknown ids are no-ops', () {
      final start = project(clips: [video('a'), photo('ph')]);
      final h = Harness(start);
      h.c.setClipSpeed('a', double.nan);
      h.c.setClipSpeed('a', 1.0);
      h.c.setClipSpeed('ph', 2.0);
      h.c.setClipSpeed('x', 2.0);
      expect(identical(h.p, start), isTrue);
      expect(h.notifications, 0);
      expect(h.c.canUndo, isFalse);
    });

    test('speed is limited so the clip keeps the minimum timeline length', () {
      final h = Harness(project(clips: [video('a', inMs: 0, outMs: 250)]));
      h.c.setClipSpeed('a', 4);
      expect(h.clip('a').speed, 2.5);
      expect(h.clip('a').durationMs, min);
    });

    test('trim keeps min * speed of source on a fast clip', () {
      final h = Harness(project(clips: [video('a', speed: 4)]));
      h.c.trimClip('a', outMs: 50);
      expect(h.clip('a').outMs, 400);
      expect(h.clip('a').durationMs, min);
      h.c.trimClip('a', outMs: 10000);
      h.c.trimClip('a', inMs: 9990);
      expect(h.clip('a').inMs, 9600);
      h.c.trimClip('a', inMs: 5000, outMs: 5001);
      expect(h.clip('a').inMs, 5000);
      expect(h.clip('a').outMs, 5400);
    });

    test('trim on a slow clip still keeps the minimum of source', () {
      final h = Harness(project(clips: [video('a', speed: 0.25)]));
      h.c.trimClip('a', outMs: 10);
      expect(h.clip('a').outMs, min);
      expect(h.clip('a').durationMs, 400);
    });

    test('trim arguments are source times whatever the speed', () {
      final h = Harness(project(clips: [video('a', speed: 2)]));
      h.c.trimClip('a', inMs: 2000, outMs: 6000);
      expect(h.clip('a').inMs, 2000);
      expect(h.clip('a').outMs, 6000);
      expect(h.p.durationMs, 2000);
    });
  });

  group('look', () {
    test('adjustments: null leaves a value alone, values clamp', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setClipAdjustments('a', brightness: 0.4);
      h.c.setClipAdjustments('a', contrast: -3, saturation: 7);
      final c = h.clip('a');
      expect(c.brightness, 0.4);
      expect(c.contrast, -1);
      expect(c.saturation, 1);
      expect(h.undoSteps, 2);
    });

    test('adjustment no-ops', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.setClipAdjustments('a');
      h.c.setClipAdjustments('a', brightness: 0, contrast: 0, saturation: 0);
      h.c.setClipAdjustments('a', brightness: double.nan);
      h.c.setClipAdjustments('x', brightness: 0.5);
      expect(identical(h.p, start), isTrue);
      expect(h.notifications, 0);
    });

    test('zoom clamps to 1..4 and ignores NaN', () {
      final h = Harness(project(clips: [video('a'), photo('ph')]));
      h.c.setClipZoom('a', 2.5);
      expect(h.clip('a').zoom, 2.5);
      h.c.setClipZoom('a', 0.2);
      expect(h.clip('a').zoom, 1);
      h.c.setClipZoom('a', 9);
      expect(h.clip('a').zoom, 4);
      final before = h.notifications;
      h.c.setClipZoom('a', double.nan);
      h.c.setClipZoom('a', 4);
      h.c.setClipZoom('x', 2);
      expect(h.notifications, before);
      h.c.setClipZoom('ph', 2);
      expect(h.clip('ph').zoom, 2);
    });

    test('denoise', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setClipDenoise('a', true);
      expect(h.clip('a').denoise, isTrue);
      h.c.setClipDenoise('a', true);
      h.c.setClipDenoise('x', true);
      expect(h.notifications, 1);
      h.c.undo();
      expect(h.clip('a').denoise, isFalse);
    });

    test('duck music', () {
      final h = Harness(project());
      h.c.setDuckMusic(false);
      expect(h.notifications, 0);
      h.c.setDuckMusic(true);
      expect(h.p.duckMusic, isTrue);
      expect(h.notifications, 1);
      h.c.undo();
      expect(h.p.duckMusic, isFalse);
      h.c.redo();
      expect(h.p.duckMusic, isTrue);
    });

    test('addClip clamps the new fields and survives NaN', () {
      final h = Harness(project());
      h.c.addClip(const Clip(
        id: 'a',
        type: ClipType.video,
        path: '/a.mp4',
        sourceDurationMs: 10000,
        inMs: 0,
        outMs: 10000,
        width: 100,
        height: 100,
        speed: 9,
        brightness: 5,
        contrast: -5,
        saturation: double.nan,
        zoom: 0.5,
        transition: TransitionType.slideLeft,
        transitionMs: 5,
      ));
      var c = h.clip('a');
      expect(c.speed, 4);
      expect(c.brightness, 1);
      expect(c.contrast, -1);
      expect(c.saturation, 0);
      expect(c.zoom, 1);
      expect(c.transition, TransitionType.slideLeft);
      expect(c.transitionMs, EditorController.minTransitionMs);

      h.c.addClip(const Clip(
        id: 'b',
        type: ClipType.video,
        path: '/b.mp4',
        sourceDurationMs: 10000,
        inMs: 0,
        outMs: 200,
        width: 100,
        height: 100,
        speed: double.nan,
        brightness: double.nan,
        contrast: double.nan,
        zoom: double.nan,
        transitionMs: 99999,
      ));
      c = h.clip('b');
      expect(c.speed, 1);
      expect(c.brightness, 0);
      expect(c.contrast, 0);
      expect(c.zoom, 1);
      expect(c.transitionMs, EditorController.maxTransitionMs);
      // The whole project still serialises (no NaN anywhere).
      expect(Project.fromJson(h.p.toJson()).clips.length, 2);

      // Speed is capped by the trimmed length, photos never have a speed.
      h.c.addClip(video('c', outMs: 200, speed: 4));
      expect(h.clip('c').speed, 2);
      h.c.addClip(photo('ph').copyWith(speed: 3, zoom: 8));
      expect(h.clip('ph').speed, 1);
      expect(h.clip('ph').zoom, 4);
      expect(h.clip('ph').durationMs, 3000);
    });
  });

  group('transitions', () {
    test('setClipTransition sets type and clamps the length', () {
      final h = Harness(project(clips: [video('a'), video('b')]));
      h.c.setClipTransition('b', fade);
      expect(h.clip('b').transition, fade);
      expect(h.clip('b').transitionMs, 500);
      expect(h.p.durationMs, 19500);
      h.c.setClipTransition('b', TransitionType.slideUp, durationMs: 5000);
      expect(h.clip('b').transition, TransitionType.slideUp);
      expect(h.clip('b').transitionMs, 2000);
      expect(h.p.durationMs, 18000);
      h.c.setClipTransition('b', TransitionType.slideUp, durationMs: 1);
      expect(h.clip('b').transitionMs, 100);
      // Removing the transition keeps the remembered length.
      h.c.setClipTransition('b', TransitionType.none);
      expect(h.clip('b').transitionMs, 100);
      expect(h.p.durationMs, 20000);
      expect(h.undoSteps, 4);
    });

    test('no-ops and the first clip', () {
      final h = Harness(project(clips: [video('a'), video('b')]));
      h.c.setClipTransition('b', TransitionType.none);
      h.c.setClipTransition('b', TransitionType.none, durationMs: 500);
      h.c.setClipTransition('x', fade);
      expect(h.notifications, 0);
      // Stored on the first clip, but without effect there.
      h.c.setClipTransition('a', fade, durationMs: 1000);
      expect(h.clip('a').transition, fade);
      expect(h.p.durationMs, 20000);
      expect(h.p.clipStartMs(0), 0);
      // It starts to count once another clip is in front.
      h.c.moveClip(0, 1);
      expect(h.p.durationMs, 19000);
    });

    test('trimming a neighbour shortens an over-long transition', () {
      final h = Harness(project(
          clips: [video('a'), video('b', transition: fade, transitionMs: 2000)]));
      expect(h.p.transitionOverlapMs(1), 2000);
      h.c.trimClip('a', outMs: 1000);
      expect(h.p.transitionOverlapMs(1), 500);
      expect(h.p.durationMs, 10500);
    });
  });

  group('split with speed and transitions', () {
    test('timeline position maps to the source through speed', () {
      final h = Harness(project(clips: [
        video('a', inMs: 1000, outMs: 9000, speed: 2)
            .copyWith(brightness: 0.3, zoom: 2, denoise: true, volume: 0.5),
      ]));
      expect(h.c.splitAt(1500), isTrue);
      final first = h.p.clips[0];
      final second = h.p.clips[1];
      expect(first.id, 'a');
      expect(second.id, 'new1');
      expect([first.inMs, first.outMs], [1000, 4000]);
      expect([second.inMs, second.outMs], [4000, 9000]);
      for (final c in [first, second]) {
        expect(c.speed, 2);
        expect(c.brightness, 0.3);
        expect(c.zoom, 2);
        expect(c.denoise, isTrue);
        expect(c.volume, 0.5);
      }
      expect(h.p.durationMs, 4000);
      expect(h.p.clipStartMs(1), 1500);
      expect(h.undoSteps, 1);
    });

    test('slow clip', () {
      final h = Harness(project(clips: [video('a', speed: 0.5)]));
      expect(h.p.durationMs, 20000);
      expect(h.c.splitAt(15000), isTrue);
      expect(h.p.clips[0].outMs, 7500);
      expect(h.p.clips[1].inMs, 7500);
    });

    test('pieces must be long enough in the source and on the timeline', () {
      var h = Harness(project(clips: [video('a', speed: 4)]));
      expect(h.c.splitAt(99), isFalse);
      expect(h.c.splitAt(2401), isFalse); // leaves 99 ms
      expect(h.ids, 0);
      expect(h.notifications, 0);
      expect(h.c.splitAt(100), isTrue);
      expect(h.p.clips[0].sourceSpanMs, 400);

      h = Harness(project(clips: [video('a', speed: 0.25)]));
      // Below 400 ms on the timeline is less than 100 ms of source.
      expect(h.c.splitAt(100), isFalse);
      expect(h.c.splitAt(397), isFalse);
      expect(h.c.splitAt(400), isTrue);
      expect(h.p.clips[0].sourceSpanMs, 100);
    });

    test('first half keeps the transition, second half has none', () {
      final h = Harness(project(clips: [
        video('a'),
        video('b', transition: fade, transitionMs: 1000),
      ]));
      expect(h.p.clipStartMs(1), 9000);
      expect(h.c.splitAt(14000), isTrue);
      expect(h.clipIds, ['a', 'b', 'new1']);
      expect(h.p.clips[1].transition, fade);
      expect(h.p.clips[1].transitionMs, 1000);
      expect(h.p.clips[2].transition, TransitionType.none);
      // 14000 is 5000 into b, which starts at 9000.
      expect(h.p.clips[1].outMs, 5000);
      expect(h.p.clips[2].inMs, 5000);
      expect(h.p.clipStartMs(2), 14000);
      expect(h.p.durationMs, 19000);
    });

    test('inside a transition the incoming clip is split', () {
      final h = Harness(project(clips: [
        video('a', speed: 2),
        video('b', transition: fade, transitionMs: 1000),
      ]));
      // a lasts 5000; b starts (fading in) at 4000.
      expect(h.c.splitAt(4050), isFalse); // 50 ms into b
      expect(h.c.splitAt(4500), isTrue);
      expect(h.clipIds, ['a', 'b', 'new1']);
      expect(h.clip('a').outMs, 10000);
      expect(h.clip('b').outMs, 500);
      expect(h.clip('b').transition, fade);
      expect(h.p.clips[2].inMs, 500);
      // The 500 ms piece can only carry a 250 ms transition now.
      expect(h.p.transitionOverlapMs(1), 250);
    });

    test('just before a transition the outgoing clip is split', () {
      final h = Harness(project(clips: [
        video('a', speed: 2),
        video('b', transition: fade, transitionMs: 1000),
      ]));
      expect(h.c.splitAt(3999), isTrue);
      expect(h.clipIds, ['a', 'new1', 'b']);
      expect(h.clip('a').outMs, 7998);
      expect(h.p.clips[1].inMs, 7998);
      expect(h.p.clips[1].speed, 2);
    });

    test('photo with a transition', () {
      final h = Harness(project(clips: [
        video('a'),
        photo('ph', durationMs: 4000, transition: TransitionType.fadeBlack),
      ]));
      expect(h.c.splitAt(9500 + 1000), isTrue);
      expect(h.clip('ph').durationMs, 1000);
      expect(h.clip('ph').transition, TransitionType.fadeBlack);
      expect(h.p.clips[2].durationMs, 3000);
      expect(h.p.clips[2].transition, TransitionType.none);
      expect(h.p.clips[2].inMs, 0);
    });

    test('a new id never collides with a clip on the track', () {
      final c = EditorController(project(clips: [video('new1'), video('new2')]),
          newId: (() {
        var n = 0;
        return () => 'new${++n}';
      })());
      expect(c.splitAt(5000), isTrue);
      expect([for (final x in c.project.clips) x.id], ['new1', 'new3', 'new2']);
    });
  });

  group('removeSourceRanges', () {
    test('cuts ranges out and keeps the rest as clips', () {
      final h = Harness(project(clips: [
        video('z'),
        video('a', inMs: 1000, outMs: 9000, transition: fade)
            .copyWith(zoom: 2, saturation: -0.5),
        video('y', transition: fade),
      ]));
      final removed = h.c.removeSourceRanges('a', [
        (startMs: 8950, endMs: 20000),
        (startMs: 3500, endMs: 5000),
        (startMs: 0, endMs: 1500),
        (startMs: 3000, endMs: 4000),
        (startMs: 6000, endMs: 6000),
        (startMs: 7000, endMs: 6500),
      ]);
      expect(removed, 3);
      expect(h.clipIds, ['z', 'a', 'new1', 'y']);
      final a = h.p.clips[1];
      final b = h.p.clips[2];
      expect([a.inMs, a.outMs], [1500, 3000]);
      expect([b.inMs, b.outMs], [5000, 8950]);
      expect(a.transition, fade);
      expect(b.transition, TransitionType.none);
      expect(h.clip('y').transition, fade);
      for (final c in [a, b]) {
        expect(c.zoom, 2);
        expect(c.saturation, -0.5);
        expect(c.path, '/media/a.mp4');
      }
      expect(h.notifications, 1);
      expect(h.undoSteps, 1);
      h.c.undo();
      expect(h.clipIds, ['z', 'a', 'y']);
      expect(h.clip('a').outMs, 9000);
    });

    test('kept pieces that are too short go as well', () {
      final h = Harness(project(clips: [video('a', inMs: 1000, outMs: 9000)]));
      final removed = h.c.removeSourceRanges('a', [
        (startMs: 2000, endMs: 3000),
        (startMs: 3050, endMs: 4000),
        (startMs: 8950, endMs: 9000), // leaves nothing after it
        (startMs: 1000, endMs: 1001),
      ]);
      // [1001,2000] kept, [3000,3050] too short, [4000,8950] kept.
      expect(removed, 3);
      expect(h.clipIds, ['a', 'new1']);
      expect([h.p.clips[0].inMs, h.p.clips[0].outMs], [1001, 2000]);
      expect([h.p.clips[1].inMs, h.p.clips[1].outMs], [4000, 8950]);
    });

    test('the minimum piece follows the speed', () {
      final h = Harness(project(clips: [video('a', speed: 4)]));
      final removed = h.c.removeSourceRanges('a', [
        (startMs: 1000, endMs: 2000),
        (startMs: 2300, endMs: 3000), // 300 ms of source = 75 ms at 4x
      ]);
      expect(removed, 1);
      expect(h.clipIds, ['a', 'new1']);
      expect(h.p.clips[0].outMs, 1000);
      expect(h.p.clips[1].inMs, 3000);
      expect(h.p.clips[1].speed, 4);
    });

    test('a cut at one end only trims the clip', () {
      final h = Harness(project(clips: [video('a')]));
      expect(h.c.removeSourceRanges('a', [(startMs: -50, endMs: 2000)]), 1);
      expect(h.clipIds, ['a']);
      expect(h.clip('a').inMs, 2000);
      expect(h.ids, 0);
    });

    test('nothing to do returns 0 and changes nothing', () {
      final start = project(
          clips: [video('a', inMs: 1000, outMs: 9000), photo('ph')]);
      final h = Harness(start);
      expect(h.c.removeSourceRanges('a', []), 0);
      expect(h.c.removeSourceRanges('a', [(startMs: 0, endMs: 1000)]), 0);
      expect(h.c.removeSourceRanges('a', [(startMs: 9000, endMs: 9999)]), 0);
      expect(h.c.removeSourceRanges('a', [(startMs: 5000, endMs: 4000)]), 0);
      // Would remove everything.
      expect(h.c.removeSourceRanges('a', [(startMs: 0, endMs: 10000)]), 0);
      expect(
          h.c.removeSourceRanges('a', [
            (startMs: 1050, endMs: 5000),
            (startMs: 5050, endMs: 8990),
          ]),
          0);
      expect(h.c.removeSourceRanges('ph', [(startMs: 0, endMs: 1000)]), 0);
      expect(h.c.removeSourceRanges('x', [(startMs: 0, endMs: 1000)]), 0);
      expect(identical(h.p, start), isTrue);
      expect(h.notifications, 0);
      expect(h.c.canUndo, isFalse);
      expect(h.ids, 0);
    });
  });

  group('insertFreezeFrame', () {
    test('puts the still between the two halves in one step', () {
      final h = Harness(project(clips: [
        video('a', speed: 2).copyWith(
            fit: FitMode.fill, zoom: 1.5, brightness: 0.2, contrast: -0.1),
        video('b', transition: fade),
      ]));
      final still = photo('still', durationMs: 2000, transition: fade);
      expect(h.c.insertFreezeFrame(1000, still), isTrue);
      expect(h.clipIds, ['a', 'still', 'new1', 'b']);
      expect(h.clip('a').outMs, 2000);
      expect(h.p.clips[2].inMs, 2000);
      final s = h.clip('still');
      expect(s.type, ClipType.photo);
      expect(s.durationMs, 2000);
      expect(s.transition, TransitionType.none);
      expect(s.fit, FitMode.fill);
      expect(s.zoom, 1.5);
      expect(s.brightness, 0.2);
      expect(s.contrast, -0.1);
      expect(h.p.clips[2].transition, TransitionType.none);
      expect(h.p.clipStartMs(1), 1000);
      expect(h.p.clipStartMs(2), 3000);
      expect(h.notifications, 1);
      expect(h.undoSteps, 1);
      h.c.undo();
      expect(h.clipIds, ['a', 'b']);
      expect(h.clip('a').outMs, 10000);
    });

    test('returns false and changes nothing where a split is impossible', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      expect(h.c.insertFreezeFrame(50, photo('s')), isFalse);
      expect(h.c.insertFreezeFrame(10000, photo('s')), isFalse);
      expect(h.c.insertFreezeFrame(-1, photo('s')), isFalse);
      expect(identical(h.p, start), isTrue);
      expect(h.notifications, 0);
      expect(h.ids, 0);
      expect(Harness(project()).c.insertFreezeFrame(0, photo('s')), isFalse);
    });

    test('a still whose id is taken gets a new one; its time is clamped', () {
      final h = Harness(project(clips: [video('a')]));
      expect(h.c.insertFreezeFrame(5000, photo('a', durationMs: 10)), isTrue);
      expect(h.clipIds, ['a', 'new2', 'new1']);
      expect(h.p.clips[1].type, ClipType.photo);
      expect(h.p.clips[1].durationMs, min);
    });
  });

  group('addTitles', () {
    test('adds all in one undo step, clamped, with unique ids', () {
      final h = Harness(project(titles: [title('t1')]));
      h.c.addTitles([
        const TitleOverlay(
            id: 't1', text: 'A', startMs: -5, endMs: 10, kind: TitleKind.caption),
        const TitleOverlay(id: 'c', text: 'B', startMs: 1000, endMs: 2000, x: 7),
        const TitleOverlay(
            id: 'c', text: 'C', startMs: 2000, endMs: 3000, kind: TitleKind.caption),
      ]);
      expect([for (final t in h.p.titles) t.id], ['t1', 'new1', 'c', 'new2']);
      expect(h.p.titles[1].kind, TitleKind.caption);
      expect(h.p.titles[1].startMs, 0);
      expect(h.p.titles[1].endMs, min);
      expect(h.p.titles[2].x, 1.0);
      expect(h.p.titles[2].kind, TitleKind.title);
      expect(h.p.titles[3].kind, TitleKind.caption);
      expect(h.notifications, 1);
      expect(h.undoSteps, 1);
      h.c.undo();
      expect(h.p.titles.length, 1);
    });

    test('an empty list is a no-op', () {
      final h = Harness(project());
      h.c.addTitles(const []);
      expect(h.notifications, 0);
      expect(h.c.canUndo, isFalse);
    });

    test('addTitle keeps the kind when it has to change the id', () {
      final h = Harness(project(titles: [title('t')]));
      h.c.addTitle(
          title('t').copyWith(kind: TitleKind.caption, background: true));
      expect(h.p.titles[1].id, 'new1');
      expect(h.p.titles[1].kind, TitleKind.caption);
      expect(h.p.titles[1].background, isTrue);
    });

    test('updateTitle can change the kind', () {
      final h = Harness(project(titles: [title('t')]));
      h.c.updateTitle(title('t').copyWith(kind: TitleKind.caption));
      expect(h.p.titles.single.kind, TitleKind.caption);
      expect(h.notifications, 1);
    });
  });

  group('undo sees every new field', () {
    final changes = <String, void Function(EditorController c)>{
      'speed': (c) => c.setClipSpeed('a', 2),
      'denoise': (c) => c.setClipDenoise('a', true),
      'voiceFocus': (c) => c.setClipVoiceFocus('a', 0.5),
      'brightness': (c) => c.setClipAdjustments('a', brightness: 0.1),
      'contrast': (c) => c.setClipAdjustments('a', contrast: 0.1),
      'saturation': (c) => c.setClipAdjustments('a', saturation: 0.1),
      'zoom': (c) => c.setClipZoom('a', 2),
      'transition': (c) => c.setClipTransition('a', fade),
      'transitionMs': (c) =>
          c.setClipTransition('a', TransitionType.none, durationMs: 900),
      'duckMusic': (c) => c.setDuckMusic(true),
      'title kind': (c) =>
          c.updateTitle(title('t').copyWith(kind: TitleKind.caption)),
    };
    for (final e in changes.entries) {
      test(e.key, () {
        final start = project(clips: [video('a')], titles: [title('t')]);
        final h = Harness(start);
        // A transaction only records a step when the content differs, so
        // this fails if the comparison misses the field.
        h.c.transaction(() => e.value(h.c));
        expect(h.c.canUndo, isTrue, reason: e.key);
        expect(content(h.p), isNot(content(start)));
        h.c.undo();
        expect(content(h.p), content(start));
        h.c.redo();
        expect(content(h.p), isNot(content(start)));
      });
    }

    test('a transaction that ends where it began records nothing', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.transaction(() {
        h.c.setClipSpeed('a', 3);
        h.c.setClipZoom('a', 2);
        h.c.setClipTransition('a', fade, durationMs: 800);
        h.c.setDuckMusic(true);
        h.c.setDuckMusic(false);
        h.c.setClipTransition('a', TransitionType.none, durationMs: 500);
        h.c.setClipZoom('a', 1);
        h.c.setClipSpeed('a', 1);
      });
      expect(h.c.canUndo, isFalse);
      expect(identical(h.p, start), isTrue);
    });

    test('a slider drag is one step', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.transaction(() {
        for (var i = 1; i <= 10; i++) {
          h.c.setClipAdjustments('a', brightness: i / 10);
        }
      });
      expect(h.clip('a').brightness, 1);
      expect(h.undoSteps, 1);
    });
  });

  group('ProjectEditor without the controller', () {
    test('listeners, undo and redo', () {
      final e = ProjectEditor(project(clips: [video('a')]), newId: () => 'n');
      var calls = 0;
      void listener() => calls++;
      e.addListener(listener);
      e.setClipSpeed('a', 2);
      expect(e.splitAt(1000), isTrue);
      expect(calls, 2);
      e.undo();
      e.undo();
      expect(e.project.clips.single.speed, 1);
      expect(e.canRedo, isTrue);
      expect(calls, 4);
      e.removeListener(listener);
      e.redo();
      expect(calls, 4);
      expect(e.project.clips.single.speed, 2);
    });

    test('a listener may remove itself or others while being called', () {
      final e = ProjectEditor(project());
      final log = <String>[];
      late void Function() a;
      void b() => log.add('b');
      a = () {
        log.add('a');
        e.removeListener(a);
        e.removeListener(b);
      };
      e
        ..addListener(a)
        ..addListener(b);
      e.rename('x');
      e.rename('y');
      expect(log, ['a']);
    });

    test('constants match the controller', () {
      expect(ProjectEditor.minDurationMs, EditorController.minDurationMs);
      expect(ProjectEditor.maxPhotoDurationMs, EditorController.maxPhotoDurationMs);
      expect(ProjectEditor.maxUndoSteps, EditorController.maxUndoSteps);
      expect(EditorController.minSpeed, 0.25);
      expect(EditorController.maxSpeed, 4);
      expect(EditorController.minZoom, 1);
      expect(EditorController.maxZoom, 4);
      expect(EditorController.minAdjustment, -1);
      expect(EditorController.maxAdjustment, 1);
      expect(EditorController.minTransitionMs, 100);
      expect(EditorController.maxTransitionMs, 2000);
    });

    test('the controller mirrors an editor it wraps', () {
      final e = ProjectEditor(project(clips: [video('a')]));
      final c = EditorController.wrap(e);
      var calls = 0;
      c.addListener(() => calls++);
      e.setClipZoom('a', 2); // edit made directly on the core
      expect(calls, 1);
      expect(identical(c.project, e.project), isTrue);
      expect(identical(c.editor, e), isTrue);
      c.setClipZoom('a', 3);
      expect(e.project.clips.single.zoom, 3);
      expect(c.canUndo, isTrue);
      c.dispose();
      e.setClipZoom('a', 1); // must not call a disposed notifier
      expect(calls, 2);
    });
  });
}
