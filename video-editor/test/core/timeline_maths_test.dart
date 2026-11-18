import 'dart:convert';
import 'dart:math';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const fade = TransitionType.crossfade;

/// Checks everything that must hold between the timeline helpers.
void expectConsistent(Project p, {String? reason}) {
  final n = p.clips.length;
  var sum = 0;
  for (var i = 0; i < n; i++) {
    final c = p.clips[i];
    final o = p.transitionOverlapMs(i);
    sum += c.durationMs - o;
    expect(o, greaterThanOrEqualTo(0), reason: reason);
    expect(p.clipEndMs(i), p.clipStartMs(i) + c.durationMs, reason: reason);
    if (i == 0) {
      expect(o, 0, reason: reason);
      expect(p.clipStartMs(0), 0, reason: reason);
    } else {
      // A transition never takes more than half of either clip, so two
      // transitions on one clip cannot meet.
      expect(o, lessThanOrEqualTo(c.durationMs ~/ 2), reason: reason);
      expect(o, lessThanOrEqualTo(p.clips[i - 1].durationMs ~/ 2), reason: reason);
      expect(o, lessThanOrEqualTo(c.transitionMs), reason: reason);
      if (c.transition == TransitionType.none) expect(o, 0, reason: reason);
      // The clip starts where the previous one ends, minus the overlap.
      expect(p.clipStartMs(i), p.clipEndMs(i - 1) - o, reason: reason);
      expect(p.clipStartMs(i), greaterThanOrEqualTo(p.clipStartMs(i - 1)),
          reason: reason);
      expect(p.clipEndMs(i), greaterThanOrEqualTo(p.clipEndMs(i - 1)),
          reason: reason);
    }
  }
  expect(p.durationMs, sum, reason: reason);
  expect(p.clipStartMs(n), p.durationMs, reason: reason);
  expect(p.transitionOverlapMs(n), 0, reason: reason);
  expect(p.transitionOverlapMs(-1), 0, reason: reason);
  if (n == 0) {
    expect(p.durationMs, 0);
    expect(p.clipIndexAt(0), -1);
    return;
  }
  expect(p.clipEndMs(n - 1), p.durationMs, reason: reason);
  expect(p.clipIndexAt(-100), 0, reason: reason);
  expect(p.clipIndexAt(p.durationMs + 100), n - 1, reason: reason);
  for (var i = 0; i < n; i++) {
    final start = p.clipStartMs(i);
    final next = i + 1 < n ? p.clipStartMs(i + 1) : p.durationMs;
    if (next == start) continue; // empty slot, a later clip wins
    for (final t in {start, (start + next) ~/ 2, next - 1}) {
      expect(p.clipIndexAt(t), i, reason: '$reason, t=$t');
      // The time is inside the clip that is reported for it.
      expect(t, lessThan(p.clipEndMs(i)), reason: reason);
    }
  }
}

Project randomProject(Random r) {
  const speeds = [0.25, 0.5, 0.75, 1.0, 1.0, 1.5, 2.0, 3.0, 4.0];
  final clips = <Clip>[];
  final n = r.nextInt(7);
  for (var i = 0; i < n; i++) {
    final transition =
        TransitionType.values[r.nextInt(TransitionType.values.length)];
    final transitionMs = 100 + r.nextInt(1901);
    if (r.nextInt(4) == 0) {
      clips.add(photo('c$i',
          durationMs: 100 + r.nextInt(5000),
          transition: transition,
          transitionMs: transitionMs));
    } else {
      final inMs = r.nextInt(3000);
      clips.add(video('c$i',
          inMs: inMs,
          outMs: inMs + 400 + r.nextInt(6000),
          speed: speeds[r.nextInt(speeds.length)],
          transition: transition,
          transitionMs: transitionMs));
    }
  }
  return project(clips: clips);
}

void main() {
  group('clip duration', () {
    test('speed divides the timeline length; photos ignore it', () {
      expect(video('a', speed: 2).durationMs, 5000);
      expect(video('a', speed: 0.25).durationMs, 40000);
      expect(video('a', outMs: 1000, speed: 3).durationMs, 333);
      expect(video('a', speed: 2).sourceSpanMs, 10000);
      expect(photo('p').copyWith(speed: 4).durationMs, 3000);
    });

    test('sourceMsAt converts timeline time inside the clip to source time', () {
      final c = video('a', inMs: 1000, outMs: 9000, speed: 2);
      expect(c.sourceMsAt(0), 1000);
      expect(c.sourceMsAt(1500), 4000);
      expect(c.sourceMsAt(c.durationMs), 9000);
      expect(c.sourceMsAt(999999), 9000);
      expect(c.sourceMsAt(-5), 1000);
      expect(video('a', speed: 0.5).sourceMsAt(3000), 1500);
      expect(photo('p').sourceMsAt(1234), 0);
    });
  });

  group('timeline with speed and transitions', () {
    test('worked example', () {
      final p = project(clips: [
        video('a', speed: 2), // 5000
        video('b', outMs: 4000, transition: fade, transitionMs: 1000), // 4000
        photo('c', durationMs: 1000, transition: fade, transitionMs: 2000),
        video('d', speed: 0.5, outMs: 2000), // 4000, no transition
      ]);
      expect([for (var i = 0; i < 4; i++) p.transitionOverlapMs(i)],
          [0, 1000, 500, 0]);
      expect([for (var i = 0; i < 4; i++) p.clipStartMs(i)],
          [0, 4000, 7500, 8500]);
      expect([for (var i = 0; i < 4; i++) p.clipEndMs(i)],
          [5000, 8000, 8500, 12500]);
      expect(p.durationMs, 12500);
      expect(p.clipIndexAt(3999), 0);
      // During a transition the incoming clip is reported.
      expect(p.clipIndexAt(4000), 1);
      expect(p.clipIndexAt(4999), 1);
      expect(p.clipIndexAt(7499), 1);
      expect(p.clipIndexAt(7500), 2);
      expect(p.clipIndexAt(8500), 3);
      expect(p.clipIndexAt(99999), 3);
      expectConsistent(p);
    });

    test('a transition on the first clip or of type none has no effect', () {
      final p = project(clips: [
        video('a', transition: fade, transitionMs: 2000),
        video('b', transitionMs: 2000),
      ]);
      expect(p.transitionOverlapMs(0), 0);
      expect(p.transitionOverlapMs(1), 0);
      expect(p.durationMs, 20000);
      expectConsistent(p);
    });

    test('the overlap is at most half of the shorter neighbour', () {
      final p = project(clips: [
        video('a', outMs: 600),
        video('b', transition: fade, transitionMs: 2000),
        video('c', outMs: 301, transition: fade, transitionMs: 2000),
      ]);
      expect(p.transitionOverlapMs(1), 300);
      expect(p.transitionOverlapMs(2), 150);
      expectConsistent(p);
    });

    test('consistency holds for random projects', () {
      final r = Random(20261115);
      for (var i = 0; i < 400; i++) {
        final p = randomProject(r);
        expectConsistent(p, reason: 'project $i ${jsonEncode(p.toJson())}');
      }
    });

    test('consistency holds through random edits', () {
      final r = Random(7);
      for (var round = 0; round < 60; round++) {
        var ids = 0;
        final e = ProjectEditor(randomProject(r), newId: () => 'n${++ids}');
        for (var step = 0; step < 25; step++) {
          final p = e.project;
          final n = p.clips.length;
          final id = n == 0 ? 'none' : p.clips[r.nextInt(n)].id;
          final before = p;
          switch (r.nextInt(8)) {
            case 0:
              final t = r.nextInt(p.durationMs + 200) - 100;
              final ok = e.splitAt(t);
              if (ok) {
                expect(e.project.clips.length, n + 1);
                // No picture is lost or repeated.
                int source(Project q) =>
                    q.clips.fold(0, (s, c) => s + c.sourceSpanMs);
                expect(source(e.project), source(before));
              }
            case 1:
              e.setClipSpeed(id, 0.1 + r.nextDouble() * 5);
            case 2:
              e.setClipTransition(
                  id, TransitionType.values[r.nextInt(TransitionType.values.length)],
                  durationMs: r.nextInt(2500));
            case 3:
              e.trimClip(id, inMs: r.nextInt(4000), outMs: r.nextInt(9000));
            case 4:
              if (n > 0) e.moveClip(r.nextInt(n), r.nextInt(n));
            case 5:
              final a = r.nextInt(9000);
              e.removeSourceRanges(id, [
                (startMs: a, endMs: a + r.nextInt(1500)),
                (startMs: r.nextInt(9000), endMs: r.nextInt(9000)),
              ]);
            case 6:
              e.insertFreezeFrame(r.nextInt(p.durationMs + 1),
                  photo('still$step', durationMs: 500 + r.nextInt(2000)));
            case 7:
              if (n > 2) e.removeClip(id);
          }
          final after = e.project;
          expectConsistent(after, reason: 'round $round step $step');
          final seen = <String>{};
          for (final c in after.clips) {
            expect(seen.add(c.id), isTrue, reason: 'duplicate id ${c.id}');
            expect(c.durationMs, greaterThanOrEqualTo(ProjectEditor.minDurationMs),
                reason: 'round $round step $step ${jsonEncode(c.toJson())}');
            expect(c.sourceSpanMs,
                greaterThanOrEqualTo(ProjectEditor.minDurationMs));
            expect(c.speed, inInclusiveRange(0.25, 4));
            expect(c.transitionMs, inInclusiveRange(100, 2000));
            expect(c.inMs, greaterThanOrEqualTo(0));
            if (c.type == ClipType.video) {
              expect(c.outMs, lessThanOrEqualTo(c.sourceDurationMs));
            }
          }
        }
        // Undo all the way back gives the starting project again.
        final end = content(e.project);
        var steps = 0;
        while (e.canUndo) {
          e.undo();
          steps++;
        }
        for (var i = 0; i < steps; i++) {
          e.redo();
        }
        expect(content(e.project), end);
      }
    });

    test('a split without transitions keeps the project length', () {
      final r = Random(3);
      for (var i = 0; i < 200; i++) {
        final speed = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0][r.nextInt(7)];
        final e = ProjectEditor(project(clips: [
          video('a', inMs: r.nextInt(500), outMs: 3000 + r.nextInt(7000), speed: speed),
        ]));
        final before = e.project.durationMs;
        final t = r.nextInt(before);
        if (!e.splitAt(t)) continue;
        // Each half is rounded to a millisecond on its own.
        expect((e.project.durationMs - before).abs(), lessThanOrEqualTo(1));
        // The cut lands on a whole source millisecond, which is up to 4 ms
        // of timeline at 0.25x.
        expect((e.project.clipStartMs(1) - t).abs(), lessThanOrEqualTo(2));
      }
    });
  });

  group('schema', () {
    // Exactly what version 1 of the app wrote.
    const v1 = '''
{
  "schemaVersion": 1,
  "id": "0b0e5a3c-58a7-4c1d-9a55-2f3c8d1e7a10",
  "name": "Holiday",
  "createdAt": "2026-03-01T10:00:00.000Z",
  "updatedAt": "2026-03-02T11:30:00.000Z",
  "aspect": "portrait9x16",
  "clips": [
    {
      "id": "c1",
      "type": "video",
      "path": "/storage/emulated/0/DCIM/a.mp4",
      "sourceDurationMs": 12000,
      "inMs": 1000,
      "outMs": 9000,
      "width": 1080,
      "height": 1920,
      "hasAudio": true,
      "volume": 0.8,
      "muted": false,
      "fit": "blur"
    },
    {
      "id": "c2",
      "type": "photo",
      "path": "/storage/emulated/0/DCIM/b.jpg",
      "sourceDurationMs": 0,
      "inMs": 0,
      "outMs": 3000,
      "width": 4000,
      "height": 3000,
      "hasAudio": false,
      "volume": 1.0,
      "muted": false,
      "fit": "fit"
    }
  ],
  "audio": [
    {
      "id": "m1",
      "path": "/storage/emulated/0/Music/song.mp3",
      "sourceDurationMs": 180000,
      "startMs": 500,
      "inMs": 0,
      "outMs": 11000,
      "volume": 0.5,
      "fadeInMs": 300,
      "fadeOutMs": 1000
    }
  ],
  "titles": [
    {
      "id": "t1",
      "text": "Summer",
      "startMs": 0,
      "endMs": 2500,
      "x": 0.5,
      "y": 0.2,
      "fontSize": 0.08,
      "colorArgb": 4294967295,
      "bold": true,
      "background": true
    }
  ]
}''';

    test('a version 1 file loads with defaults for the new fields', () {
      final p = Project.fromJson(jsonDecode(v1) as Map<String, dynamic>);
      expect(p.name, 'Holiday');
      expect(p.aspect, CanvasAspect.portrait9x16);
      expect(p.duckMusic, isFalse);
      expect(p.clips.length, 2);
      for (final c in p.clips) {
        expect(c.speed, 1.0);
        expect(c.denoise, isFalse);
        expect(c.brightness, 0);
        expect(c.contrast, 0);
        expect(c.saturation, 0);
        expect(c.zoom, 1.0);
        expect(c.transition, TransitionType.none);
        expect(c.transitionMs, 500);
      }
      expect(p.clips[0].fit, FitMode.blur);
      expect(p.clips[0].volume, 0.8);
      expect(p.clips[0].durationMs, 8000);
      expect(p.clips[0].sourceSpanMs, 8000);
      expect(p.titles.single.kind, TitleKind.title);
      expect(p.titles.single.background, isTrue);
      expect(p.audio.single.fadeOutMs, 1000);
      // Same timeline as version 1 computed.
      expect(p.durationMs, 11000);
      expect(p.clipStartMs(1), 8000);
      expect(p.clipIndexAt(8000), 1);
      expectConsistent(p);
    });

    test('it is written back as the current version with every field', () {
      final p = Project.fromJson(jsonDecode(v1) as Map<String, dynamic>);
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      expect(json['schemaVersion'], kSchemaVersion);
      expect(kSchemaVersion, 2);
      expect(json['duckMusic'], isFalse);
      final clip = (json['clips'] as List).first as Map;
      for (final key in [
        'speed', 'denoise', 'brightness', 'contrast', 'saturation', 'zoom',
        'transition', 'transitionMs',
      ]) {
        expect(clip.containsKey(key), isTrue, reason: key);
      }
      expect(((json['titles'] as List).first as Map)['kind'], 'title');
      expect(content(Project.fromJson(json)), content(p));
    });

    test('new fields round-trip and unknown enum names fall back', () {
      final p = project(
        clips: [
          video('a', speed: 1.5, transition: TransitionType.slideUp, transitionMs: 700)
              .copyWith(denoise: true, brightness: -0.2, contrast: 0.3, saturation: 1, zoom: 2.5),
        ],
        titles: [title('t').copyWith(kind: TitleKind.caption)],
      ).copyWith(duckMusic: true);
      final back = Project.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(content(back), content(p));
      expect(back.duckMusic, isTrue);
      expect(back.clips.single.transition, TransitionType.slideUp);
      expect(back.titles.single.kind, TitleKind.caption);

      final json = p.toJson();
      ((json['clips'] as List).first as Map)['transition'] = 'wipeFromTheFuture';
      ((json['titles'] as List).first as Map)['kind'] = 'karaoke';
      final odd = Project.fromJson(json);
      expect(odd.clips.single.transition, TransitionType.none);
      expect(odd.titles.single.kind, TitleKind.title);
    });
  });
}
