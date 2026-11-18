import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const min = EditorController.minDurationMs;

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
}

void main() {
  group('basics', () {
    test('starts with the given project and no history', () {
      final p = project(clips: [video('a')]);
      final h = Harness(p);
      expect(identical(h.p, p), isTrue);
      expect(h.c.canUndo, isFalse);
      expect(h.c.canRedo, isFalse);
      expect(h.c.inTransaction, isFalse);
      h.c.undo();
      h.c.redo();
      expect(identical(h.p, p), isTrue);
      expect(h.notifications, 0);
    });

    test('default clock and id generator work', () {
      final c = EditorController(project(clips: [video('a')]));
      final before = DateTime.now();
      expect(c.splitAt(5000), isTrue);
      expect(c.project.clips[1].id, isNot('a'));
      expect(c.project.clips[1].id, isNotEmpty);
      expect(c.project.updatedAt.isBefore(before), isFalse);
    });

    test('every edit bumps updatedAt, notifies once and clears redo', () {
      final h = Harness(project());
      final edits = <void Function()>[
        () => h.c.addClip(video('a')),
        () => h.c.addClip(video('b')),
        () => h.c.moveClip(0, 1),
        () => h.c.trimClip('a', inMs: 500),
        () => h.c.splitAt(2000),
        () => h.c.setClipVolume('a', 0.3),
        () => h.c.setClipMuted('a', true),
        () => h.c.setClipFit('a', FitMode.blur),
        () => h.c.addAudio(audio('m')),
        () => h.c.updateAudio(audio('m', startMs: 50)),
        () => h.c.addTitle(title('t')),
        () => h.c.updateTitle(title('t', text: 'Yo')),
        () => h.c.setAspect(CanvasAspect.square1x1),
        () => h.c.removeTitle('t'),
        () => h.c.removeAudio('m'),
        () => h.c.removeClip('a'),
      ];
      for (var i = 0; i < edits.length; i++) {
        // Give every edit something to clear from the redo stack.
        h.c.setDuckMusic(!h.p.duckMusic);
        h.c.undo();
        expect(h.c.canRedo, isTrue);
        final beforeTime = h.p.updatedAt;
        final beforeContent = content(h.p);
        final beforeNotes = h.notifications;
        edits[i]();
        expect(content(h.p), isNot(beforeContent), reason: 'edit $i changed nothing');
        expect(h.p.updatedAt.isAfter(beforeTime), isTrue, reason: 'edit $i');
        expect(h.notifications, beforeNotes + 1, reason: 'edit $i');
        expect(h.c.canRedo, isFalse, reason: 'edit $i');
        expect(h.c.canUndo, isTrue);
      }
      expect(h.p.id, 'p1');
      expect(h.p.createdAt, t0);
    });

    test('unknown ids are complete no-ops', () {
      final start = project(clips: [video('a')], audio: [audio('m')], titles: [title('t')]);
      final h = Harness(start);
      h.c.removeClip('x');
      h.c.trimClip('x', inMs: 10, outMs: 500);
      h.c.setClipVolume('x', 0.5);
      h.c.setClipMuted('x', true);
      h.c.setClipFit('x', FitMode.fill);
      h.c.removeAudio('x');
      h.c.updateAudio(audio('x'));
      h.c.removeTitle('x');
      h.c.updateTitle(title('x'));
      // Ids are per list: an audio id is not a clip id.
      h.c.removeClip('m');
      h.c.removeAudio('t');
      h.c.removeTitle('a');
      expect(identical(h.p, start), isTrue);
      expect(h.c.canUndo, isFalse);
      expect(h.notifications, 0);
    });

    test('edits that change nothing are no-ops', () {
      final start = project(
        clips: [video('a'), photo('ph')],
        audio: [audio('m')],
        titles: [title('t')],
        aspect: CanvasAspect.square1x1,
      );
      final h = Harness(start);
      h.c.setClipVolume('a', 1.0);
      h.c.setClipMuted('a', false);
      h.c.setClipFit('a', FitMode.fit);
      h.c.trimClip('a');
      h.c.trimClip('a', inMs: 0, outMs: 10000);
      h.c.trimClip('a', inMs: -50, outMs: 999999);
      h.c.trimClip('ph', inMs: 700);
      h.c.moveClip(1, 1);
      h.c.moveClip(1, 7);
      h.c.updateAudio(audio('m'));
      h.c.updateTitle(title('t'));
      h.c.setAspect(CanvasAspect.square1x1);
      h.c.rename('Test');
      h.c.rename('  Test ');
      h.c.rename('   ');
      expect(identical(h.p, start), isTrue);
      expect(h.c.canUndo, isFalse);
      expect(h.notifications, 0);
    });
  });

  group('addClip / removeClip / moveClip', () {
    test('appends by default and inserts at a clamped index', () {
      final h = Harness(project());
      h.c.addClip(video('a'));
      h.c.addClip(video('b'));
      h.c.addClip(video('c'), index: 0);
      h.c.addClip(video('d'), index: 2);
      h.c.addClip(video('e'), index: 99);
      h.c.addClip(video('f'), index: -3);
      expect(h.clipIds, ['f', 'c', 'a', 'd', 'b', 'e']);
    });

    test('clamps the incoming video clip', () {
      final h = Harness(project());
      h.c.addClip(video('a', source: 5000, inMs: -100, outMs: 9000, volume: 7));
      expect([h.p.clips[0].inMs, h.p.clips[0].outMs], [0, 5000]);
      expect(h.p.clips[0].volume, 2.0);
      h.c.addClip(video('b', source: 5000, inMs: 4000, outMs: 4000));
      expect(h.p.clips[1].durationMs, min);
      expect(h.p.clips[1].outMs <= 5000, isTrue);
      h.c.addClip(video('c', source: 5000, inMs: 4990, outMs: 3000, volume: -1));
      expect([h.p.clips[2].inMs, h.p.clips[2].outMs], [4900, 5000]);
      expect(h.p.clips[2].volume, 0.0);
      h.c.addClip(video('d', volume: double.nan));
      expect(h.p.clips[3].volume, 1.0);
    });

    test('video with unknown source length is only kept positive', () {
      final h = Harness(project());
      h.c.addClip(video('a', source: 0, inMs: -5, outMs: 7000));
      expect([h.p.clips[0].inMs, h.p.clips[0].outMs], [0, 7000]);
      h.c.addClip(video('b', source: 0, inMs: 300, outMs: 300));
      expect([h.p.clips[1].inMs, h.p.clips[1].outMs], [300, 300 + min]);
    });

    test('clamps the incoming photo', () {
      final h = Harness(project());
      h.c.addClip(photo('a', durationMs: 10));
      h.c.addClip(photo('b', durationMs: 999999));
      h.c.addClip(photo('c', durationMs: 2000, inMs: 500));
      expect([for (final c in h.p.clips) c.inMs], [0, 0, 0]);
      expect([for (final c in h.p.clips) c.outMs],
          [min, EditorController.maxPhotoDurationMs, 2000]);
    });

    test('a duplicate id gets a fresh id', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.addClip(video('a'));
      expect(h.clipIds, ['a', 'new1']);
    });

    test('removeClip removes only that clip; music stays, titles follow', () {
      final h = Harness(project(
        clips: [video('a'), video('b'), video('c')],
        audio: [audio('m', startMs: 15000)],
        titles: [
          title('t', startMs: 22000, endMs: 24000),
          title('late', startMs: 40000, endMs: 41000),
        ],
      ));
      h.c.removeClip('b');
      expect(h.clipIds, ['a', 'c']);
      expect(h.p.durationMs, 20000);
      expect([h.p.titles.first.startMs, h.p.titles.first.endMs], [12000, 14000]);
      h.c.removeClip('a');
      expect([h.p.titles.first.startMs, h.p.titles.first.endMs], [2000, 4000]);
      h.c.removeClip('c');
      expect(h.p.clips, isEmpty);
      expect(h.p.audio.single.startMs, 15000);
      // The title on c went with it; the one past the end never moved.
      expect(h.p.titles.single.id, 'late');
      expect([h.p.titles.single.startMs, h.p.titles.single.endMs], [40000, 41000]);
    });

    test('moveClip puts the clip at the target index', () {
      final h = Harness(project(clips: [video('a'), video('b'), video('c'), video('d')]));
      h.c.moveClip(0, 2);
      expect(h.clipIds, ['b', 'c', 'a', 'd']);
      h.c.moveClip(3, 0);
      expect(h.clipIds, ['d', 'b', 'c', 'a']);
      h.c.moveClip(1, 99);
      expect(h.clipIds, ['d', 'c', 'a', 'b']);
      h.c.moveClip(2, -4);
      expect(h.clipIds, ['a', 'd', 'c', 'b']);
    });

    test('moveClip ignores a bad source index', () {
      final start = project(clips: [video('a'), video('b')]);
      final h = Harness(start);
      h.c.moveClip(-1, 0);
      h.c.moveClip(2, 0);
      expect(identical(h.p, start), isTrue);
      final empty = Harness(project());
      empty.c.moveClip(0, 0);
      expect(empty.c.canUndo, isFalse);
    });
  });

  group('trimClip', () {
    Clip only(Harness h) => h.p.clips.single;

    test('sets both edges', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.trimClip('a', inMs: 1000, outMs: 4000);
      expect([only(h).inMs, only(h).outMs], [1000, 4000]);
    });

    test('clamps to the source', () {
      final h = Harness(project(clips: [video('a', inMs: 2000, outMs: 6000)]));
      h.c.trimClip('a', inMs: -500);
      expect(only(h).inMs, 0);
      h.c.trimClip('a', outMs: 50000);
      expect(only(h).outMs, 10000);
      h.c.trimClip('a', inMs: -1, outMs: 10001);
      expect([only(h).inMs, only(h).outMs], [0, 10000]);
    });

    test('moving one edge never moves the other', () {
      final h = Harness(project(clips: [video('a', inMs: 2000, outMs: 6000)]));
      h.c.trimClip('a', inMs: 9000);
      expect([only(h).inMs, only(h).outMs], [6000 - min, 6000]);
      h.c.trimClip('a', outMs: 0);
      expect([only(h).inMs, only(h).outMs], [6000 - min, 6000]);
      h.c.trimClip('a', inMs: 1000);
      h.c.trimClip('a', outMs: 1050);
      expect([only(h).inMs, only(h).outMs], [1000, 1000 + min]);
    });

    test('both edges given keep the minimum length inside the source', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.trimClip('a', inMs: 5000, outMs: 5000);
      expect([only(h).inMs, only(h).outMs], [5000, 5000 + min]);
      h.c.trimClip('a', inMs: 10000, outMs: 10000);
      expect([only(h).inMs, only(h).outMs], [10000 - min, 10000]);
      h.c.trimClip('a', inMs: 8000, outMs: 2000);
      expect([only(h).inMs, only(h).outMs], [8000, 8000 + min]);
    });

    test('video with unknown source cannot be extended', () {
      final h = Harness(project(clips: [video('a', source: 0, inMs: 1000, outMs: 5000)]));
      h.c.trimClip('a', outMs: 9000);
      expect(only(h).outMs, 5000);
      h.c.trimClip('a', inMs: 0, outMs: 3000);
      expect([only(h).inMs, only(h).outMs], [0, 3000]);
    });

    test('photo: only outMs matters, clamped to 100ms..60s, inMs stays 0', () {
      final h = Harness(project(clips: [photo('a')]));
      h.c.trimClip('a', inMs: 500, outMs: 5000);
      expect([only(h).inMs, only(h).outMs], [0, 5000]);
      h.c.trimClip('a', outMs: 1);
      expect(only(h).outMs, min);
      h.c.trimClip('a', outMs: -400);
      expect(only(h).outMs, min);
      h.c.trimClip('a', outMs: 10 * 60 * 1000);
      expect(only(h).outMs, EditorController.maxPhotoDurationMs);
      expect(only(h).inMs, 0);
    });

    test('shortening a clip does not move audio; titles keep what is left', () {
      final h = Harness(project(
        clips: [video('a')],
        audio: [audio('m', startMs: 8000)],
        titles: [
          title('gone', startMs: 7000, endMs: 9500),
          title('cut', startMs: 500, endMs: 3000),
        ],
      ));
      h.c.trimClip('a', outMs: 1000);
      expect(h.p.durationMs, 1000);
      expect(h.p.audio.single.startMs, 8000);
      expect(h.p.titles.single.id, 'cut');
      expect([h.p.titles.single.startMs, h.p.titles.single.endMs], [500, 1000]);
    });
  });

  group('splitAt', () {
    test('splits a video and gives the second half a new id', () {
      final h = Harness(project(clips: [
        video('a', inMs: 1000, outMs: 5000).copyWith(volume: 0.5, muted: true, fit: FitMode.fill),
        video('b'),
      ]));
      expect(h.c.splitAt(1500), isTrue);
      expect(h.clipIds, ['a', 'new1', 'b']);
      final first = h.p.clips[0];
      final second = h.p.clips[1];
      expect([first.inMs, first.outMs], [1000, 2500]);
      expect([second.inMs, second.outMs], [2500, 5000]);
      expect(second.path, first.path);
      expect(second.sourceDurationMs, 10000);
      expect([second.volume, second.muted, second.fit], [0.5, true, FitMode.fill]);
      expect(h.p.durationMs, 14000);
      expect(h.notifications, 1);
    });

    test('splits a later clip using its timeline offset', () {
      final h = Harness(project(clips: [video('a', outMs: 2000), video('b', inMs: 3000, outMs: 9000)]));
      expect(h.c.splitAt(2000 + 1234), isTrue);
      expect(h.clipIds, ['a', 'b', 'new1']);
      expect([h.p.clips[1].inMs, h.p.clips[1].outMs], [3000, 4234]);
      expect([h.p.clips[2].inMs, h.p.clips[2].outMs], [4234, 9000]);
    });

    test('splits a photo into two display times', () {
      final h = Harness(project(clips: [photo('a', durationMs: 3000)]));
      expect(h.c.splitAt(1200), isTrue);
      expect([h.p.clips[0].inMs, h.p.clips[0].outMs], [0, 1200]);
      expect([h.p.clips[1].inMs, h.p.clips[1].outMs], [0, 1800]);
      expect(h.p.clips[1].type, ClipType.photo);
      expect(h.p.durationMs, 3000);
    });

    test('exactly minDurationMs from an edge is allowed, closer is not', () {
      final h = Harness(project(clips: [video('a', outMs: 1000), video('b', outMs: 1000)]));
      expect(h.c.splitAt(min - 1), isFalse);
      expect(h.c.splitAt(1000 - min + 1), isFalse);
      expect(h.c.splitAt(1000), isFalse, reason: 'on a clip boundary');
      expect(h.c.splitAt(1000 + min - 1), isFalse);
      expect(h.c.splitAt(0), isFalse);
      expect(h.c.canUndo, isFalse);
      expect(h.notifications, 0);
      expect(h.c.splitAt(min), isTrue);
      expect(h.c.splitAt(1000 - min), isTrue);
      expect([for (final c in h.p.clips) c.durationMs], [min, 1000 - 2 * min, min, 1000]);
    });

    test('returns false on an empty track or outside it', () {
      final empty = Harness(project());
      expect(empty.c.splitAt(0), isFalse);
      expect(empty.c.splitAt(500), isFalse);
      final h = Harness(project(clips: [video('a')]));
      expect(h.c.splitAt(-1), isFalse);
      expect(h.c.splitAt(10000), isFalse);
      expect(h.c.splitAt(20000), isFalse);
      expect(h.notifications, 0);
    });

    test('a clip shorter than twice the minimum cannot be split', () {
      final h = Harness(project(clips: [video('a', outMs: 2 * min - 1)]));
      for (var t = 0; t < 2 * min; t += 10) {
        expect(h.c.splitAt(t), isFalse);
      }
    });

    test('is one undo step', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.splitAt(4000);
      h.c.undo();
      expect(content(h.p), content(start));
      h.c.redo();
      expect(h.clipIds, ['a', 'new1']);
    });
  });

  group('clip properties', () {
    test('volume clamps to 0..2', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setClipVolume('a', 0.25);
      expect(h.p.clips.single.volume, 0.25);
      h.c.setClipVolume('a', 5);
      expect(h.p.clips.single.volume, 2.0);
      h.c.setClipVolume('a', -3);
      expect(h.p.clips.single.volume, 0.0);
      h.c.setClipVolume('a', double.infinity);
      expect(h.p.clips.single.volume, 2.0);
      final n = h.notifications;
      h.c.setClipVolume('a', double.nan);
      expect(h.p.clips.single.volume, 2.0);
      expect(h.notifications, n);
    });

    test('muted and fit', () {
      final h = Harness(project(clips: [video('a'), video('b')]));
      h.c.setClipMuted('b', true);
      h.c.setClipFit('b', FitMode.blur);
      expect(h.p.clips[0].muted, isFalse);
      expect(h.p.clips[0].fit, FitMode.fit);
      expect(h.p.clips[1].muted, isTrue);
      expect(h.p.clips[1].fit, FitMode.blur);
      h.c.setClipMuted('b', false);
      expect(h.p.clips[1].muted, isFalse);
    });
  });

  group('audio', () {
    AudioClip only(Harness h) => h.p.audio.single;

    test('add, update, remove', () {
      final h = Harness(project());
      h.c.addAudio(audio('m'));
      h.c.addAudio(audio('n', startMs: 4000));
      expect([for (final a in h.p.audio) a.id], ['m', 'n']);
      h.c.updateAudio(h.p.audio[1]
          .copyWith(startMs: 6000, inMs: 1000, outMs: 5000, volume: 0.5));
      final n = h.p.audio[1];
      expect([n.startMs, n.inMs, n.outMs, n.endMs], [6000, 1000, 5000, 10000]);
      expect(n.volume, 0.5);
      expect(h.p.audio[0].startMs, 0);
      h.c.removeAudio('m');
      expect(only(h).id, 'n');
    });

    test('duplicate id gets a fresh id', () {
      final h = Harness(project(audio: [audio('m')]));
      h.c.addAudio(audio('m', startMs: 700, fadeInMs: 200));
      expect([for (final a in h.p.audio) a.id], ['m', 'new1']);
      expect(h.p.audio[1].startMs, 700);
      expect(h.p.audio[1].fadeInMs, 200);
    });

    test('add clamps position, trim, volume and fades', () {
      final h = Harness(project());
      h.c.addAudio(audio('m', startMs: -900, inMs: -10, outMs: 99999, volume: 9, fadeInMs: -5, fadeOutMs: -5));
      expect([only(h).startMs, only(h).inMs, only(h).outMs], [0, 0, 30000]);
      expect(only(h).volume, 2.0);
      expect([only(h).fadeInMs, only(h).fadeOutMs], [0, 0]);
    });

    test('update keeps the trim inside the source and at least the minimum', () {
      final h = Harness(project(audio: [audio('m')]));
      h.c.updateAudio(audio('m', inMs: 5000, outMs: 5000));
      expect([only(h).inMs, only(h).outMs], [5000, 5000 + min]);
      h.c.updateAudio(audio('m', inMs: 40000, outMs: 50000));
      expect([only(h).inMs, only(h).outMs], [30000 - min, 30000]);
      h.c.updateAudio(audio('m', inMs: 2000, outMs: 100));
      expect([only(h).inMs, only(h).outMs], [2000, 2000 + min]);
      h.c.updateAudio(audio('m', startMs: -1, volume: -1));
      expect(only(h).startMs, 0);
      expect(only(h).volume, 0.0);
      h.c.updateAudio(audio('m', volume: double.nan));
      expect(only(h).volume, 1.0);
    });

    test('unknown source length only keeps the range positive', () {
      final h = Harness(project());
      h.c.addAudio(audio('m', source: 0, inMs: -3, outMs: 123456));
      expect([only(h).inMs, only(h).outMs], [0, 123456]);
      h.c.updateAudio(audio('m', source: 0, inMs: 500, outMs: 0));
      expect([only(h).inMs, only(h).outMs], [500, 500 + min]);
    });

    test('fades are never longer than the clip, together', () {
      final h = Harness(project(audio: [audio('m')]));
      h.c.updateAudio(audio('m', inMs: 0, outMs: 1000, fadeInMs: 5000, fadeOutMs: 5000));
      expect([only(h).fadeInMs, only(h).fadeOutMs], [1000, 0]);
      h.c.updateAudio(audio('m', inMs: 0, outMs: 1000, fadeInMs: 300, fadeOutMs: 5000));
      expect([only(h).fadeInMs, only(h).fadeOutMs], [300, 700]);
      h.c.updateAudio(audio('m', inMs: 0, outMs: 1000, fadeInMs: 400, fadeOutMs: 600));
      expect([only(h).fadeInMs, only(h).fadeOutMs], [400, 600]);
      // Shortening the clip shortens the fades with it.
      h.c.updateAudio(only(h).copyWith(outMs: 500));
      expect([only(h).fadeInMs, only(h).fadeOutMs], [400, 100]);
    });

    test('audio may sit past the end of the main track', () {
      final h = Harness(project(clips: [video('a', outMs: 1000)]));
      h.c.addAudio(audio('m', startMs: 50000));
      expect(only(h).startMs, 50000);
    });
  });

  group('titles', () {
    TitleOverlay only(Harness h) => h.p.titles.single;

    test('add, update, remove', () {
      final h = Harness(project());
      h.c.addTitle(title('t'));
      h.c.addTitle(title('u', startMs: 3000, endMs: 4000));
      h.c.updateTitle(const TitleOverlay(
        id: 'u',
        text: 'New',
        startMs: 3500,
        endMs: 4200,
        x: 0.1,
        y: 0.9,
        fontSize: 0.2,
        colorArgb: 0xFF00FF00,
        bold: false,
        background: true,
      ));
      final u = h.p.titles[1];
      expect(u.text, 'New');
      expect([u.startMs, u.endMs], [3500, 4200]);
      expect([u.x, u.y, u.fontSize], [0.1, 0.9, 0.2]);
      expect(u.colorArgb, 0xFF00FF00);
      expect(u.bold, isFalse);
      expect(u.background, isTrue);
      expect(h.p.titles[0].text, 'Hi');
      h.c.removeTitle('t');
      expect(only(h).id, 'u');
    });

    test('duplicate id gets a fresh id', () {
      final h = Harness(project(titles: [title('t')]));
      h.c.addTitle(title('t', text: 'Second'));
      expect([for (final t in h.p.titles) t.id], ['t', 'new1']);
      expect(h.p.titles[1].text, 'Second');
    });

    test('time range clamps: start >= 0, end at least the minimum later', () {
      final h = Harness(project());
      h.c.addTitle(title('t', startMs: -500, endMs: -100));
      expect([only(h).startMs, only(h).endMs], [0, min]);
      h.c.updateTitle(title('t', startMs: 2000, endMs: 2000));
      expect([only(h).startMs, only(h).endMs], [2000, 2000 + min]);
      h.c.updateTitle(title('t', startMs: 2000, endMs: 500));
      expect([only(h).startMs, only(h).endMs], [2000, 2000 + min]);
      h.c.updateTitle(title('t', startMs: 100, endMs: 999999));
      expect([only(h).startMs, only(h).endMs], [100, 999999]);
    });

    test('position and size clamp', () {
      final h = Harness(project(titles: [title('t')]));
      h.c.updateTitle(title('t').copyWith(x: -1, y: 4, fontSize: 9));
      expect([only(h).x, only(h).y], [0.0, 1.0]);
      expect(only(h).fontSize, EditorController.maxTitleFontSize);
      h.c.updateTitle(title('t').copyWith(fontSize: 0));
      expect(only(h).fontSize, EditorController.minTitleFontSize);
      h.c.updateTitle(title('t').copyWith(x: double.nan, y: double.nan, fontSize: double.nan));
      expect([only(h).x, only(h).y, only(h).fontSize], [0.5, 0.5, 0.06]);
    });

    test('empty text is allowed', () {
      final h = Harness(project(titles: [title('t')]));
      h.c.updateTitle(title('t', text: ''));
      expect(only(h).text, '');
    });
  });

  group('project', () {
    test('setAspect', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setAspect(CanvasAspect.portrait9x16);
      expect(h.p.aspect, CanvasAspect.portrait9x16);
      expect(h.p.canvasSize, (width: 1080, height: 1920));
    });

    test('rename trims', () {
      final h = Harness(project());
      h.c.rename('  My film  ');
      expect(h.p.name, 'My film');
    });
  });

  group('undo / redo', () {
    test('walks back and forward through every step', () {
      final h = Harness(project());
      final states = <String>[content(h.p)];
      void step(void Function() f) {
        f();
        states.add(content(h.p));
      }

      step(() => h.c.addClip(video('a')));
      step(() => h.c.addClip(photo('b')));
      step(() => h.c.trimClip('a', inMs: 2000, outMs: 8000));
      step(() => h.c.splitAt(3000));
      step(() => h.c.addAudio(audio('m')));
      step(() => h.c.addTitle(title('t')));
      step(() => h.c.moveClip(0, 2));
      step(() => h.c.removeClip('b'));
      step(() => h.c.setAspect(CanvasAspect.portrait4x5));
      expect(states.toSet(), hasLength(states.length));

      for (var i = states.length - 2; i >= 0; i--) {
        expect(h.c.canUndo, isTrue);
        h.c.undo();
        expect(content(h.p), states[i]);
      }
      expect(h.c.canUndo, isFalse);
      for (var i = 1; i < states.length; i++) {
        expect(h.c.canRedo, isTrue);
        h.c.redo();
        expect(content(h.p), states[i]);
      }
      expect(h.c.canRedo, isFalse);
    });

    test('undo and redo notify and bump updatedAt', () {
      final h = Harness(project());
      h.c.setDuckMusic(true);
      final t1 = h.p.updatedAt;
      h.c.undo();
      expect(h.notifications, 2);
      expect(h.p.duckMusic, isFalse);
      expect(h.p.updatedAt.isAfter(t1), isTrue);
      final t2 = h.p.updatedAt;
      h.c.redo();
      expect(h.notifications, 3);
      expect(h.p.duckMusic, isTrue);
      expect(h.p.updatedAt.isAfter(t2), isTrue);
    });

    test('a new edit after undo drops the redo branch', () {
      final h = Harness(project());
      h.c.setAspect(CanvasAspect.square1x1);
      h.c.setAspect(CanvasAspect.portrait4x5);
      h.c.undo();
      h.c.setAspect(CanvasAspect.landscape16x9);
      expect(h.c.canRedo, isFalse);
      h.c.redo();
      expect(h.p.aspect, CanvasAspect.landscape16x9);
      h.c.undo();
      expect(h.p.aspect, CanvasAspect.square1x1);
      h.c.undo();
      expect(h.p.aspect, CanvasAspect.original);
      expect(h.c.canUndo, isFalse);
    });

    test('a no-op edit keeps the redo branch', () {
      final h = Harness(project());
      h.c.setDuckMusic(true);
      h.c.undo();
      h.c.removeClip('nope');
      h.c.rename('Test');
      expect(h.c.splitAt(100), isFalse);
      expect(h.c.canRedo, isTrue);
    });

    test('history is capped', () {
      final h = Harness(project(clips: [video('a')]));
      const extra = 25;
      for (var i = 0; i < EditorController.maxUndoSteps + extra; i++) {
        h.c.trimClip('a', inMs: i + 1);
      }
      var undone = 0;
      while (h.c.canUndo) {
        h.c.undo();
        undone++;
      }
      expect(undone, EditorController.maxUndoSteps);
      expect(h.p.clips.single.inMs, extra);
      var redone = 0;
      while (h.c.canRedo) {
        h.c.redo();
        redone++;
      }
      expect(redone, EditorController.maxUndoSteps);
      expect(h.p.clips.single.inMs, EditorController.maxUndoSteps + extra);
    });
  });

  group('transaction', () {
    test('collapses many edits into one undo step', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.setDuckMusic(true);
      h.c.transaction(() {
        expect(h.c.inTransaction, isTrue);
        for (var i = 1; i <= 20; i++) {
          h.c.trimClip('a', inMs: i * 100);
        }
        h.c.setClipVolume('a', 0.2);
      });
      expect(h.c.inTransaction, isFalse);
      expect(h.p.clips.single.inMs, 2000);
      expect(h.p.clips.single.volume, 0.2);
      h.c.undo();
      expect(h.p.clips.single.inMs, 0);
      expect(h.p.clips.single.volume, 1.0);
      expect(h.p.duckMusic, isTrue);
      h.c.redo();
      expect(h.p.clips.single.inMs, 2000);
      expect(h.p.clips.single.volume, 0.2);
      h.c.undo();
      h.c.undo();
      expect(content(h.p), content(start));
      expect(h.c.canUndo, isFalse);
    });

    test('listeners follow each edit inside, plus one at the end', () {
      final h = Harness(project(clips: [video('a')]));
      final seen = <int>[];
      h.c.addListener(() => seen.add(h.p.clips.single.inMs));
      h.c.transaction(() {
        h.c.trimClip('a', inMs: 100);
        h.c.trimClip('a', inMs: 200);
        h.c.trimClip('a', inMs: 200); // no change, no notification
      });
      expect(seen, [100, 200, 200]);
      expect(h.c.canUndo, isTrue);
    });

    test('updatedAt moves with the edits inside', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.transaction(() => h.c.trimClip('a', inMs: 100));
      expect(h.p.updatedAt.isAfter(t0), isTrue);
    });

    test('nothing changed: no undo step, no notification', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.transaction(() {});
      h.c.transaction(() {
        h.c.removeClip('nope');
        h.c.setClipVolume('a', 1.0);
      });
      expect(identical(h.p, start), isTrue);
      expect(h.c.canUndo, isFalse);
      expect(h.notifications, 0);
    });

    test('dragging out and back leaves no undo step and keeps redo', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setDuckMusic(true);
      h.c.undo();
      final before = h.p;
      h.c.transaction(() {
        h.c.setClipVolume('a', 0.5);
        h.c.setClipVolume('a', 1.0);
      });
      expect(identical(h.p, before), isTrue);
      expect(h.c.canUndo, isFalse);
      expect(h.c.canRedo, isTrue);
    });

    test('a real change clears redo', () {
      final h = Harness(project(clips: [video('a')]));
      h.c.setDuckMusic(true);
      h.c.undo();
      h.c.transaction(() => h.c.setClipVolume('a', 0.5));
      expect(h.c.canRedo, isFalse);
      expect(h.c.canUndo, isTrue);
    });

    test('nested transactions join the outer one', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.transaction(() {
        h.c.setDuckMusic(true);
        h.c.transaction(() {
          h.c.setClipMuted('a', true);
          h.c.transaction(() => h.c.setClipFit('a', FitMode.fill));
          expect(h.c.inTransaction, isTrue);
        });
        expect(h.c.inTransaction, isTrue);
        expect(h.c.canUndo, isFalse);
        h.c.addTitle(title('t'));
      });
      expect(h.c.canUndo, isTrue);
      h.c.undo();
      expect(content(h.p), content(start));
      expect(h.c.canUndo, isFalse);
      h.c.redo();
      expect(h.p.duckMusic, isTrue);
      expect(h.p.clips.single.muted, isTrue);
      expect(h.p.clips.single.fit, FitMode.fill);
      expect(h.p.titles, hasLength(1));
    });

    test('undo and redo are ignored inside', () {
      final h = Harness(project());
      h.c.setAspect(CanvasAspect.square1x1);
      h.c.setAspect(CanvasAspect.portrait4x5);
      h.c.undo();
      h.c.transaction(() {
        h.c.undo();
        h.c.redo();
        expect(h.p.aspect, CanvasAspect.square1x1);
      });
      expect(h.p.aspect, CanvasAspect.square1x1);
      expect(h.c.canRedo, isTrue);
    });

    test('splitAt inside a transaction', () {
      final start = project(clips: [video('a')]);
      final h = Harness(start);
      h.c.transaction(() {
        expect(h.c.splitAt(3000), isTrue);
        expect(h.c.splitAt(6000), isTrue);
      });
      expect(h.p.clips, hasLength(3));
      h.c.undo();
      expect(content(h.p), content(start));
    });

    test('a throwing body keeps the edits as one step and rethrows', () {
      final start = project();
      final h = Harness(start);
      expect(
        () => h.c.transaction(() {
          h.c.setDuckMusic(true);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(h.c.inTransaction, isFalse);
      expect(h.p.duckMusic, isTrue);
      h.c.undo();
      expect(content(h.p), content(start));
      // The controller still works normally afterwards.
      h.c.setAspect(CanvasAspect.square1x1);
      expect(h.c.canUndo, isTrue);
    });
  });
}
