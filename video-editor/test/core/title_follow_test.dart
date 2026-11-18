// Titles and captions follow the picture when the main track changes.
import 'dart:math';

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
  }
  late final EditorController c;
  DateTime now = t0;
  int ids = 0;

  Project get p => c.project;

  /// `[startMs, endMs]` of a title, or null when it is gone.
  List<int>? at(String id) {
    for (final t in p.titles) {
      if (t.id == id) return [t.startMs, t.endMs];
    }
    return null;
  }
}

Harness three(List<TitleOverlay> titles, {List<AudioClip> music = const []}) =>
    Harness(project(
      clips: [video('a'), video('b'), video('c')],
      titles: titles,
      audio: music,
    ));

void main() {
  group('clips before the title change', () {
    test('removing an earlier clip shifts the title; one undo restores both', () {
      final h = three([title('t', startMs: 12000, endMs: 14000)],
          music: [audio('m', startMs: 12000)]);
      final start = content(h.p);
      h.c.removeClip('a');
      expect(h.at('t'), [2000, 4000]);
      expect(h.p.audio.single.startMs, 12000, reason: 'music stays absolute');
      h.c.undo();
      expect(content(h.p), start);
      expect(h.c.canUndo, isFalse);
      h.c.redo();
      expect(h.at('t'), [2000, 4000]);
    });

    test('adding a clip in front shifts it', () {
      final h = three([title('t', startMs: 12000, endMs: 14000)]);
      h.c.addClip(video('z', source: 3000), index: 0);
      expect(h.at('t'), [15000, 17000]);
    });

    test('trimming the start of its own clip shifts, clamps or removes', () {
      final h = three([
        title('later', startMs: 3000, endMs: 5000),
        title('partly', startMs: 1000, endMs: 3000),
        title('inside', startMs: 500, endMs: 1500),
        title('next', startMs: 12000, endMs: 13000),
      ]);
      h.c.trimClip('a', inMs: 2000);
      expect(h.at('later'), [1000, 3000]);
      expect(h.at('partly'), [0, 1000]);
      expect(h.at('inside'), isNull);
      expect(h.at('next'), [10000, 11000]);
    });

    test('a speed change scales the title with the clip', () {
      final h = three([
        title('t', startMs: 2000, endMs: 6000),
        title('next', startMs: 12000, endMs: 13000),
      ]);
      h.c.setClipSpeed('a', 2.0);
      expect(h.at('t'), [1000, 3000]);
      expect(h.at('next'), [7000, 8000]);
      h.c.setClipSpeed('a', 0.5);
      expect(h.at('t'), [4000, 12000]);
      expect(h.at('next'), [22000, 23000]);
      h.c.setClipSpeed('a', 1.0);
      expect(h.at('t'), [2000, 6000]);
    });

    test('a transition change moves the titles of the later clips', () {
      final h = three([
        title('t', startMs: 12000, endMs: 13000),
        title('first', startMs: 1000, endMs: 2000),
      ]);
      h.c.setClipTransition('b', TransitionType.crossfade, durationMs: 1000);
      expect(h.p.clipStartMs(1), 9000);
      expect(h.at('t'), [11000, 12000]);
      expect(h.at('first'), [1000, 2000]);
      h.c.setClipTransition('b', TransitionType.none);
      expect(h.at('t'), [12000, 13000]);
    });

    test('apply-to-all speed moves titles too, as one undo step', () {
      final h = three([title('t', startMs: 22000, endMs: 24000)]);
      h.c.setClipSpeed('a', 2.0);
      expect(h.at('t'), [17000, 19000]);
      expect(h.c.applyClipSettingsToAll('a', speed: true), 2);
      expect(h.at('t'), [11000, 12000]);
      h.c.undo();
      expect(h.at('t'), [17000, 19000]);
    });
  });

  group('deleting clips', () {
    test('a title wholly inside the deleted clip goes with it', () {
      final h = three([
        title('in', startMs: 12000, endMs: 14000),
        title('whole', startMs: 10000, endMs: 20000),
      ]);
      h.c.removeClip('b');
      expect(h.p.titles, isEmpty);
      h.c.undo();
      expect(h.at('in'), [12000, 14000]);
      expect(h.at('whole'), [10000, 20000]);
    });

    test('a title that reaches into a neighbour keeps what remains', () {
      var h = three([title('t', startMs: 8000, endMs: 12000)]);
      h.c.removeClip('b');
      expect(h.at('t'), [8000, 10000]);

      h = three([title('t', startMs: 8000, endMs: 12000)]);
      h.c.removeClip('a');
      expect(h.at('t'), [0, 2000]);

      // Across the whole deleted clip: the middle is cut out.
      h = three([title('t', startMs: 8000, endMs: 22000)]);
      h.c.removeClip('b');
      expect(h.at('t'), [8000, 12000]);
    });

    test('a transition into the deleted clip does not leave a ghost', () {
      final h = Harness(project(clips: [
        video('a'),
        video('b', transition: TransitionType.crossfade, transitionMs: 1000),
        video('c', transition: TransitionType.crossfade, transitionMs: 1000),
      ], titles: [
        title('t', startMs: 12000, endMs: 14000)
      ]));
      h.c.removeClip('b');
      expect(h.p.titles, isEmpty);
    });

    test('the part past the end of the track is kept', () {
      final h = three([title('t', startMs: 8000, endMs: 32000)]);
      h.c.removeClip('a');
      expect(h.at('t'), [0, 22000]);
    });

    test('titles at or after the end, or without clips, stay untouched', () {
      final h = three([
        title('end', startMs: 30000, endMs: 31000),
        title('late', startMs: 45000, endMs: 46000),
      ]);
      h.c.removeClip('a');
      h.c.setClipSpeed('b', 2.0);
      h.c.moveClip(0, 1);
      expect(h.at('end'), [30000, 31000]);
      expect(h.at('late'), [45000, 46000]);

      final empty = Harness(project(titles: [title('t', startMs: 500, endMs: 900)]));
      empty.c.addClip(video('a'));
      expect(empty.at('t'), [500, 900]);
      // From now on it is on clip a.
      empty.c.addClip(video('z', source: 1000), index: 0);
      expect(empty.at('t'), [1500, 1900]);
    });
  });

  group('reordering', () {
    test('a title moves with its clip', () {
      final h = three([
        title('t', startMs: 1000, endMs: 3000),
        title('other', startMs: 15000, endMs: 16000),
      ]);
      h.c.moveClip(0, 2);
      expect(h.at('t'), [21000, 23000]);
      expect(h.at('other'), [5000, 6000]);
    });

    test('a title across two clips keeps its start and length when they swap', () {
      final h = three([title('t', startMs: 9000, endMs: 11000)]);
      h.c.moveClip(0, 1);
      expect(h.at('t'), [19000, 21000]);
      // Swapping back puts it where it was.
      h.c.moveClip(1, 0);
      expect(h.at('t'), [9000, 11000]);
    });
  });

  group('splitting and cutting', () {
    test('the anchor follows the piece that holds its frame', () {
      final h = three([title('t', startMs: 6000, endMs: 8000)]);
      expect(h.c.splitAt(5000), isTrue);
      expect(h.at('t'), [6000, 8000]);
      h.c.removeClip('a'); // the first half
      expect(h.at('t'), [1000, 3000]);
    });

    test('split then slow motion on the second half', () {
      final h = three([
        title('t', startMs: 6000, endMs: 8000),
        title('first', startMs: 1000, endMs: 2000),
        title('b', startMs: 11000, endMs: 12000),
      ]);
      h.c.splitAt(5000);
      h.c.setClipSpeed('new1', 0.5);
      expect(h.at('t'), [7000, 11000]);
      expect(h.at('first'), [1000, 2000]);
      expect(h.at('b'), [16000, 17000]);
    });

    test('removeSourceRanges drops, shortens and shifts', () {
      final h = three([
        title('inside', startMs: 2500, endMs: 3500),
        title('tail', startMs: 1000, endMs: 3000),
        title('head', startMs: 3000, endMs: 5000),
        title('over', startMs: 1500, endMs: 6500),
        title('late', startMs: 8000, endMs: 9000),
        title('b', startMs: 12000, endMs: 13000),
      ]);
      expect(
          h.c.removeSourceRanges('a', [
            (startMs: 2000, endMs: 4000),
            (startMs: 6000, endMs: 7000),
          ]),
          2);
      // a is now 0-2000, 4000-6000, 7000-10000 back to back.
      expect(h.at('inside'), isNull);
      expect(h.at('tail'), [1000, 2000]);
      expect(h.at('head'), [2000, 3000]);
      expect(h.at('over'), [1500, 4000]);
      expect(h.at('late'), [5000, 6000]);
      expect(h.at('b'), [9000, 10000]);
      h.c.undo();
      expect(h.at('inside'), [2500, 3500]);
      expect(h.at('over'), [1500, 6500]);
      expect(h.c.canUndo, isFalse);
    });

    test('a freeze frame pushes later titles and stretches one across the cut', () {
      final h = three([
        title('after', startMs: 6000, endMs: 7000),
        title('across', startMs: 4000, endMs: 6000),
        title('endsAtCut', startMs: 3000, endMs: 5000),
        title('startsAtCut', startMs: 5000, endMs: 6000),
      ]);
      expect(h.c.insertFreezeFrame(5000, photo('f', durationMs: 2000)), isTrue);
      expect(h.at('after'), [8000, 9000]);
      expect(h.at('across'), [4000, 8000]);
      expect(h.at('endsAtCut'), [3000, 5000]);
      expect(h.at('startsAtCut'), [7000, 8000]);
      h.c.undo();
      expect(h.at('across'), [4000, 6000]);
    });

    test('titles on a photo follow its pieces', () {
      final h = Harness(project(
        clips: [photo('p'), video('a')],
        titles: [
          title('t', startMs: 1000, endMs: 2000),
          title('late', startMs: 2500, endMs: 2900),
        ],
      ));
      h.c.trimClip('p', outMs: 5000);
      expect(h.at('t'), [1000, 2000]);
      expect(h.c.splitAt(1500), isTrue);
      expect(h.at('t'), [1000, 2000]);
      expect(h.at('late'), [2500, 2900]);
      h.c.removeClip('p'); // the first piece, 1500 long
      expect(h.at('t'), [0, 500]);
      expect(h.at('late'), [1000, 1400]);
      // Shortening the photo below a title removes it.
      h.c.trimClip('new1', outMs: 900);
      expect(h.at('late'), isNull);
      expect(h.at('t'), [0, 500]);
    });
  });

  group('limits', () {
    test('a title never gets shorter than the minimum', () {
      final h = three([title('t', startMs: 950, endMs: 1500)]);
      h.c.trimClip('a', outMs: 1000);
      expect(h.at('t'), [950, 950 + min]);

      final fast = three([title('t', startMs: 1000, endMs: 1200)]);
      fast.c.setClipSpeed('a', 4.0);
      expect(fast.at('t'), [250, 250 + min]);
      // ... and gets its real length back with the picture.
      fast.c.setClipSpeed('a', 1.0);
      expect(fast.at('t'), [1000, 1200]);
    });

    test('settings that do not change timing leave titles alone', () {
      final h = three([title('t', startMs: 12345, endMs: 13579)]);
      final before = h.p.titles;
      h.c.setClipVolume('a', 0.5);
      h.c.setClipFit('a', FitMode.fill);
      h.c.setClipZoom('b', 2);
      h.c.relinkMedia('/media/a.mp4', '/elsewhere/a.mp4');
      expect(identical(h.p.titles, before), isTrue);
      // After a relink the title still follows.
      h.c.removeClip('a');
      expect(h.at('t'), [2345, 3579]);
    });

    test('a title the user moves is re-attached where it is put', () {
      final h = three([title('t', startMs: 1000, endMs: 2000)]);
      h.c.setClipSpeed('a', 2.0);
      expect(h.at('t'), [500, 1000]);
      h.c.updateTitle(h.p.titles.single.copyWith(startMs: 6000, endMs: 7000));
      h.c.setClipSpeed('a', 1.0); // a is 0-5000 before, so 6000 is on b
      expect(h.at('t'), [11000, 12000]);
    });
  });

  group('transactions (drags)', () {
    test('dragging a trim handle over a title and back restores it', () {
      final h = three([
        title('t', startMs: 1000, endMs: 2000),
        title('b', startMs: 12000, endMs: 13000),
      ]);
      final start = content(h.p);
      final seen = <List<int>?>[];
      h.c.transaction(() {
        for (final inMs in [500, 1500, 2500, 3000, 1500, 400, 0]) {
          h.c.trimClip('a', inMs: inMs);
          seen.add(h.at('t'));
        }
      });
      expect(seen, [
        [500, 1500],
        [0, 500],
        null,
        null,
        [0, 500],
        [600, 1600],
        [1000, 2000],
      ]);
      expect(content(h.p), start);
      expect(h.c.canUndo, isFalse);
    });

    test('a drag is one undo step, titles included', () {
      final h = three([
        title('t', startMs: 1000, endMs: 2000),
        title('gone', startMs: 100, endMs: 900),
        title('b', startMs: 12000, endMs: 13000),
      ]);
      final start = content(h.p);
      h.c.transaction(() {
        for (var inMs = 100; inMs <= 1500; inMs += 100) {
          h.c.trimClip('a', inMs: inMs);
        }
      });
      expect(h.at('t'), [0, 500]);
      expect(h.at('gone'), isNull);
      expect(h.at('b'), [10500, 11500]);
      // What the drag removed stays removed afterwards.
      h.c.trimClip('a', inMs: 0);
      expect(h.at('gone'), isNull);
      expect(h.at('t'), [1500, 2000]);
      h.c.undo();
      h.c.undo();
      expect(content(h.p), start);
      expect(h.c.canUndo, isFalse);
    });

    test('many small drag updates land where one edit would', () {
      Harness make() => Harness(project(clips: [
            video('a', source: 20000, speed: 0.75),
            video('b', speed: 3.0),
          ], titles: [
            title('t', startMs: 7001, endMs: 9004),
            title('b', startMs: 27011, endMs: 28003),
          ]));
      final dragged = make();
      dragged.c.transaction(() {
        for (var i = 1; i <= 300; i++) {
          dragged.c.trimClip('a', inMs: i * 7);
          dragged.c.setClipSpeed('a', 0.75 + i / 100);
        }
      });
      final direct = make();
      direct.c.transaction(() {
        direct.c.trimClip('a', inMs: 2100);
        direct.c.setClipSpeed('a', 3.75);
      });
      expect(dragged.at('t'), direct.at('t'));
      expect(dragged.at('b'), direct.at('b'));
    });

    test('a title edited inside the transaction is anchored where it was put', () {
      final h = three([title('t', startMs: 1000, endMs: 2000)]);
      h.c.transaction(() {
        h.c.trimClip('a', inMs: 500);
        h.c.updateTitle(h.p.titles.single.copyWith(startMs: 3000, endMs: 4000));
        h.c.trimClip('a', inMs: 1000);
      });
      expect(h.at('t'), [2500, 3500]);
    });
  });

  test('rounding does not add up over many speed changes and undo', () {
    final h = Harness(project(
      clips: [video('a', source: 60000), video('b')],
      titles: [title('t', startMs: 30001, endMs: 33334)],
    ));
    const speeds = [4.0, 0.25, 3.0, 0.75, 1.5, 0.3, 2.7, 0.9];
    for (var round = 0; round < 20; round++) {
      for (final s in speeds) {
        h.c.setClipSpeed('a', s);
        if (round.isOdd) {
          h.c.undo();
          h.c.redo();
        }
      }
    }
    h.c.setClipSpeed('a', 1.0);
    expect(h.at('t'), [30001, 33334]);
  });

  test('property: random edits keep every title on its source frame', () {
    for (var seed = 0; seed < 150; seed++) {
      _Run(seed).go();
    }
  });
}

// Property test ---------------------------------------------------------------

/// Where one edge of a title is expected: a source position of a file.
typedef _Spot = ({String path, double src});

class _Expect {
  _Spot? start;
  _Spot? end;
  bool absolute = false;
  int absStart = 0;
  int absEnd = 0;

  /// The edge is on a photo, which has no source frames: it is not checked
  /// here (photos have their own tests above).
  bool looseStart = false;
  bool looseEnd = false;
}

class _Run {
  _Run(this.seed) : r = Random(seed) {
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.0, 1.5, 2.0, 3.0, 4.0];
    final clips = <Clip>[];
    final n = 3 + r.nextInt(4);
    for (var i = 0; i < n; i++) {
      final inMs = r.nextInt(3000);
      clips.add(video('c$i',
          inMs: inMs,
          outMs: inMs + 1500 + r.nextInt(6000),
          speed: speeds[r.nextInt(speeds.length)],
          transition:
              TransitionType.values[r.nextInt(TransitionType.values.length)],
          transitionMs: 100 + r.nextInt(1500)));
    }
    final p0 = project(clips: clips, audio: [audio('m', startMs: 1234)]);
    final titles = <TitleOverlay>[];
    for (var i = 0; i < 10; i++) {
      titles.add(_randomTitle('t$i', p0.durationMs));
    }
    h = Harness(p0.copyWith(titles: titles));
    for (final t in h.p.titles) {
      expected[t.id] = _derive(h.p, t);
    }
  }

  final int seed;
  final Random r;
  late final Harness h;
  int counter = 0;
  String log = '';

  Map<String, _Expect> expected = {};
  final List<Map<String, _Expect>> myUndo = [];
  final List<Map<String, _Expect>> myRedo = [];

  TitleOverlay _randomTitle(String id, int duration) {
    final start = r.nextInt(duration + 500);
    return title(id, startMs: start, endMs: start + min + r.nextInt(4000));
  }

  static Map<String, _Expect> _copy(Map<String, _Expect> m) => {
        for (final e in m.entries)
          e.key: (_Expect()
            ..start = e.value.start
            ..end = e.value.end
            ..absolute = e.value.absolute
            ..absStart = e.value.absStart
            ..absEnd = e.value.absEnd
            ..looseStart = e.value.looseStart
            ..looseEnd = e.value.looseEnd),
      };

  static _Spot? _spotAt(Project p, int index, int timeMs) {
    final c = p.clips[index];
    if (c.type == ClipType.photo) return null;
    final src = c.inMs + (timeMs - p.clipStartMs(index)) * c.speed;
    // A clip's length on the timeline is rounded, so its last millisecond
    // can stand for a position just past the end of the source range.
    return (path: c.path, src: src.clamp(c.inMs, c.outMs).toDouble());
  }

  static _Spot? _startSpot(Project p, TitleOverlay t) =>
      _spotAt(p, p.clipIndexAt(t.startMs), t.startMs);

  static _Spot? _endSpot(Project p, TitleOverlay t) {
    if (t.endMs > p.durationMs) return null;
    final i = p.clipIndexAt(t.startMs);
    final j = t.endMs <= p.clipEndMs(i) ? i : p.clipIndexAt(t.endMs - 1);
    return _spotAt(p, j, t.endMs);
  }

  static _Expect _derive(Project p, TitleOverlay t) {
    final e = _Expect();
    if (p.clips.isEmpty || t.startMs >= p.durationMs) {
      return e
        ..absolute = true
        ..absStart = t.startMs
        ..absEnd = t.endMs;
    }
    e.start = _startSpot(p, t);
    e.looseStart = e.start == null;
    _deriveEnd(e, p, t);
    return e;
  }

  static void _deriveEnd(_Expect e, Project p, TitleOverlay t) {
    e.end = _endSpot(p, t);
    // Past the end of the track it is derived again once clips follow.
    e.looseEnd = e.end == null && t.endMs <= p.durationMs;
  }

  /// Timeline position of [s] (and the speed it plays at there), or null
  /// when that frame is not on the track.
  static double? _locate(Project p, _Spot s, {required bool end}) =>
      _locateClip(p, s, end: end)?.at;

  static ({double at, double speed})? _locateClip(Project p, _Spot s,
      {required bool end}) {
    for (var i = 0; i < p.clips.length; i++) {
      final c = p.clips[i];
      if (c.path != s.path) continue;
      if (end
          ? c.inMs < s.src && s.src <= c.outMs
          : c.inMs <= s.src && s.src < c.outMs) {
        return (
          at: p.clipStartMs(i) + (s.src - c.inMs) / c.speed,
          speed: c.speed,
        );
      }
    }
    return null;
  }

  void go() {
    final first = content(h.p);
    for (var step = 0; step < 45; step++) {
      // Titles that are free (past the end) get attached once the track
      // reaches them; work that out before the edit, like the editor does.
      for (final t in h.p.titles) {
        final e = expected[t.id]!;
        if (e.absolute) {
          expected[t.id] = _derive(h.p, t);
        } else {
          if (e.end == null && !e.looseEnd) _deriveEnd(e, h.p, t);
        }
      }
      final before = h.p;
      final beforeContent = content(before);
      _before = '${[
        for (var i = 0; i < h.p.clips.length; i++)
          '${h.p.clips[i].id}@${h.p.clipStartMs(i)} ${h.p.clips[i].inMs}-${h.p.clips[i].outMs} x${h.p.clips[i].speed}'
      ]} ${[for (final t in h.p.titles) '${t.id} ${t.startMs}-${t.endMs}']}';
      final snapshot = _copy(expected);
      final kind = _edit();
      log += '$kind; ';
      if (kind == 'undo' || kind == 'redo') {
        _check(before, afterUndo: true);
        continue;
      }
      if (content(h.p) != beforeContent) {
        myUndo.add(snapshot);
        myRedo.clear();
      } else {
        expect(identical(h.p, before), isTrue, reason: _why('no-op $kind'));
      }
      _check(before);
    }
    // Every edit was exactly one undo step.
    while (h.c.canUndo) {
      h.c.undo();
      expect(myUndo, isNotEmpty, reason: _why('more undo steps than edits'));
      myUndo.removeLast();
    }
    expect(myUndo, isEmpty, reason: _why('fewer undo steps than edits'));
    expect(content(h.p), first, reason: _why('undo all'));
  }

  String _why(String what) => 'seed $seed: $what after [$log]\n'
      'clips: ${[
        for (var i = 0; i < h.p.clips.length; i++)
          '${h.p.clips[i].id}@${h.p.clipStartMs(i)} ${h.p.clips[i].inMs}-${h.p.clips[i].outMs} x${h.p.clips[i].speed}'
      ]}\n'
      'titles: ${[for (final t in h.p.titles) '${t.id} ${t.startMs}-${t.endMs}']}\n'
      'before: $_before';

  String _before = '';

  /// Applies one random edit and names it.
  String _edit() {
    final p = h.p;
    final c = h.c;
    final clips = p.clips;
    Clip any() => clips[r.nextInt(clips.length)];
    final videos = [
      for (final c in clips)
        if (c.type == ClipType.video) c,
    ];
    switch (r.nextInt(16)) {
      case 0:
        if (clips.length > 2) {
          final id = any().id;
          c.removeClip(id);
          return 'remove $id';
        }
        final id = 'x${counter++}';
        c.addClip(video(id, source: 3000 + r.nextInt(3000)),
            index: r.nextInt(clips.length + 1));
        return 'add $id';
      case 1:
        if (clips.isEmpty) return 'skip';
        final from = r.nextInt(clips.length), to = r.nextInt(clips.length);
        c.moveClip(from, to);
        return 'move $from $to';
      case 2:
      case 3:
        // Trims only shrink here, so that pieces of one file never overlap
        // and a source frame is in at most one place.
        if (videos.isEmpty) return 'skip';
        final v = videos[r.nextInt(videos.length)];
        if (r.nextBool()) {
          final inMs = v.inMs + r.nextInt(v.sourceSpanMs);
          c.trimClip(v.id, inMs: inMs);
          return 'trimIn ${v.id} $inMs';
        }
        final outMs = v.outMs - r.nextInt(v.sourceSpanMs);
        c.trimClip(v.id, outMs: outMs);
        return 'trimOut ${v.id} $outMs';
      case 4:
      case 5:
        if (videos.isEmpty) return 'skip';
        final v = videos[r.nextInt(videos.length)];
        final s = 0.25 + r.nextInt(376) / 100;
        c.setClipSpeed(v.id, s);
        return 'speed ${v.id} $s';
      case 6:
      case 7:
        final at = r.nextInt(p.durationMs + 1);
        return 'split $at ${c.splitAt(at)}';
      case 8:
        if (videos.isEmpty) return 'skip';
        final v = videos[r.nextInt(videos.length)];
        final ranges = [
          for (var i = 0; i < 1 + r.nextInt(3); i++)
            () {
              final s = v.inMs - 200 + r.nextInt(v.sourceSpanMs + 200);
              return (startMs: s, endMs: s + 50 + r.nextInt(1500));
            }(),
        ];
        return 'cut ${v.id} $ranges ${c.removeSourceRanges(v.id, ranges)}';
      case 9:
        if (clips.isEmpty) return 'skip';
        final v = any();
        final type =
            TransitionType.values[r.nextInt(TransitionType.values.length)];
        final ms = 100 + r.nextInt(1900);
        c.setClipTransition(v.id, type, durationMs: ms);
        return 'transition ${v.id} $type $ms';
      case 10:
        final at = r.nextInt(p.durationMs + 1);
        final ok = c.insertFreezeFrame(
            at, photo('f${counter++}', durationMs: 300 + r.nextInt(2000)));
        return 'freeze $at $ok';
      case 11:
        // A drag: many updates of one clip inside a transaction, staying
        // inside the range the clip has when the drag starts.
        if (videos.isEmpty) return 'skip';
        final v = videos[r.nextInt(videos.length)];
        final moves = <String>[];
        c.transaction(() {
          for (var i = 0; i < 2 + r.nextInt(8); i++) {
            switch (r.nextInt(3)) {
              case 0:
                final inMs = v.inMs + r.nextInt(v.sourceSpanMs);
                c.trimClip(v.id, inMs: inMs);
                moves.add('in $inMs');
              case 1:
                final outMs = v.outMs - r.nextInt(v.sourceSpanMs);
                c.trimClip(v.id, outMs: outMs);
                moves.add('out $outMs');
              default:
                final s = 0.25 + r.nextInt(376) / 100;
                c.setClipSpeed(v.id, s);
                moves.add('speed $s');
            }
          }
        });
        return 'drag ${v.id} $moves';
      case 12:
        final id = 'n${counter++}';
        c.addTitle(_randomTitle(id, p.durationMs));
        expected[id] = _derive(h.p, h.p.titles.last);
        return 'addTitle $id';
      case 13:
        if (p.titles.isEmpty) return 'skip';
        final t = p.titles[r.nextInt(p.titles.length)];
        final moved = _randomTitle(t.id, p.durationMs);
        c.updateTitle(moved);
        expected[t.id] = _derive(h.p, h.p.titles.firstWhere((e) => e.id == t.id));
        return 'moveTitle ${t.id}';
      case 14:
        if (!c.canUndo) return 'skip';
        c.undo();
        myRedo.add(expected);
        expected = myUndo.removeLast();
        return 'undo';
      default:
        if (!c.canRedo) return 'skip';
        c.redo();
        myUndo.add(expected);
        expected = myRedo.removeLast();
        return 'redo';
    }
  }

  void _check(Project before, {bool afterUndo = false}) {
    final p = h.p;
    expect(p.audio.single.startMs, 1234, reason: _why('music moved'));
    final now = {for (final t in p.titles) t.id: t};
    expect(now.length, p.titles.length, reason: _why('duplicate title ids'));
    final was = {for (final t in before.titles) t.id: t};

    for (final id in expected.keys.toList()) {
      final e = expected[id]!;
      final t = now[id];
      final startAt = e.start == null ? null : _locate(p, e.start!, end: false);
      if (t == null) {
        // A title may only disappear when its start frame is gone.
        expect(e.absolute, isFalse, reason: _why('free title $id removed'));
        expect(startAt, isNull,
            reason: _why('title $id removed but its frame is on the track'));
        expected.remove(id);
        continue;
      }
      expect(t.startMs, greaterThanOrEqualTo(0), reason: _why(id));
      expect(t.endMs - t.startMs, greaterThanOrEqualTo(min),
          reason: _why('title $id too short'));

      if (e.absolute) {
        if (!afterUndo && was[id] != null) {
          expect([t.startMs, t.endMs], [e.absStart, e.absEnd],
              reason: _why('free title $id moved'));
        }
        continue;
      }
      if (e.looseStart) continue;
      if (startAt == null) {
        // Its start frame was trimmed, cut or deleted: from here on it
        // belongs to the frame it was clamped to.
        final fresh = _derive(p, t);
        e
          ..start = fresh.start
          ..looseStart = fresh.looseStart
          ..absolute = fresh.absolute
          ..absStart = fresh.absStart
          ..absEnd = fresh.absEnd;
        if (e.end != null && _locate(p, e.end!, end: true) == null) {
          e
            ..end = fresh.end
            ..looseEnd = fresh.looseEnd;
        }
        continue;
      }
      // Same file, same frame: within half a timeline millisecond, which is
      // at most 2 ms of source at 4x.
      expect((t.startMs - startAt).abs(), lessThanOrEqualTo(0.5 + 1e-6),
          reason: _why('title $id start ${t.startMs}, frame at $startAt'));
      final speed = _locateClip(p, e.start!, end: false)!.speed;
      expect((t.startMs - startAt).abs() * speed, lessThanOrEqualTo(2 + 1e-6),
          reason: _why('title $id source frame'));

      if (e.end == null) continue;
      final endAt = _locate(p, e.end!, end: true);
      if (endAt == null) {
        _deriveEnd(e, p, t);
        continue;
      }
      if (endAt.round() - t.startMs >= min) {
        expect((t.endMs - endAt).abs(), lessThanOrEqualTo(0.5 + 1e-6),
            reason: _why('title $id end ${t.endMs}, frame at $endAt'));
      }
    }
    expect(now.keys.toSet().difference(expected.keys.toSet()), isEmpty,
        reason: _why('a removed title came back'));
  }
}
