// The cached clip start times of Project (prefix sums) give exactly what
// the original walk over the clips gave.
import 'dart:math';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// The maths as it was before the cache (O(n) per call).
int oldDuration(Project p) {
  var t = 0;
  for (var i = 0; i < p.clips.length; i++) {
    t += p.clips[i].durationMs - p.transitionOverlapMs(i);
  }
  return t;
}

int oldStart(Project p, int index) {
  var t = 0;
  for (var i = 0; i < index && i < p.clips.length; i++) {
    t += p.clips[i].durationMs - p.transitionOverlapMs(i);
  }
  if (index < p.clips.length) t -= p.transitionOverlapMs(index);
  return t;
}

int oldIndexAt(Project p, int timeMs) {
  if (p.clips.isEmpty) return -1;
  var found = 0;
  for (var i = 0; i < p.clips.length; i++) {
    if (oldStart(p, i) <= timeMs) found = i;
  }
  return found;
}

Project randomProject(Random r, {int maxClips = 40}) {
  const speeds = [0.25, 0.5, 0.75, 1.0, 1.0, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
  final clips = <Clip>[];
  final n = r.nextInt(maxClips + 1);
  for (var i = 0; i < n; i++) {
    final transition = r.nextInt(3) == 0
        ? TransitionType.none
        : TransitionType.values[r.nextInt(TransitionType.values.length)];
    final transitionMs = r.nextInt(2500);
    if (r.nextInt(4) == 0) {
      clips.add(photo('c$i',
          durationMs: 1 + r.nextInt(5000),
          transition: transition,
          transitionMs: transitionMs));
    } else {
      final inMs = r.nextInt(3000);
      clips.add(video('c$i',
          inMs: inMs,
          // Includes very short pieces (as left by Remove silences).
          outMs: inMs + 1 + r.nextInt(r.nextBool() ? 300 : 8000),
          speed: speeds[r.nextInt(speeds.length)],
          transition: transition,
          transitionMs: transitionMs));
    }
  }
  return project(clips: clips);
}

void expectSameAsOld(Project p, Random r) {
  final total = oldDuration(p);
  expect(p.durationMs, total);
  for (var i = -2; i <= p.clips.length + 2; i++) {
    expect(p.clipStartMs(i), oldStart(p, i), reason: 'clipStartMs($i)');
    if (i >= 0 && i < p.clips.length) {
      expect(p.clipEndMs(i), oldStart(p, i) + p.clips[i].durationMs);
    }
  }
  final times = <int>{
    -1000, -1, 0, 1, total - 1, total, total + 1, total + 5000,
    for (var i = 0; i < p.clips.length; i++) ...[
      oldStart(p, i) - 1,
      oldStart(p, i),
      oldStart(p, i) + 1,
    ],
    for (var k = 0; k < 30; k++) r.nextInt(max(1, total) + 2000) - 1000,
  };
  for (final t in times) {
    expect(p.clipIndexAt(t), oldIndexAt(p, t), reason: 'clipIndexAt($t)');
  }
}

void main() {
  test('random projects: same results as the walk over the clips', () {
    final r = Random(20261116);
    for (var round = 0; round < 1500; round++) {
      expectSameAsOld(randomProject(r), r);
    }
  });

  test('empty project', () {
    final p = project();
    expect(p.durationMs, 0);
    expect(p.clipIndexAt(0), -1);
    expect(p.clipStartMs(0), 0);
    expect(p.clipStartMs(3), 0);
  });

  test('invalid clips with negative lengths still match the old scan', () {
    final r = Random(7);
    for (var round = 0; round < 300; round++) {
      final clips = [
        for (var i = 0; i < 1 + r.nextInt(8); i++)
          video('c$i',
              inMs: 2000,
              outMs: 2000 + r.nextInt(3000) - 1500,
              transition: TransitionType.crossfade,
              transitionMs: r.nextInt(800)),
      ];
      expectSameAsOld(project(clips: clips), r);
    }
  });

  test('a project with 2000 pieces answers lookups quickly', () {
    final clips = [
      for (var i = 0; i < 2000; i++)
        video('c$i',
            source: 2400000,
            inMs: i * 1200,
            outMs: i * 1200 + 900,
            transition:
                i % 7 == 0 ? TransitionType.crossfade : TransitionType.none,
            transitionMs: 200),
    ];
    final p = project(clips: clips);
    final sw = Stopwatch()..start();
    var sum = 0;
    for (var t = 0; t < p.durationMs; t += 97) {
      sum += p.clipIndexAt(t);
      sum += p.clipStartMs(sum % 2000);
    }
    sw.stop();
    expect(sum, greaterThan(0));
    // The old walk took over two seconds for a tenth of these lookups.
    expect(sw.elapsedMilliseconds, lessThan(1000));
    // Spot checks against the old maths.
    for (final i in [0, 1, 7, 999, 1999]) {
      expect(p.clipStartMs(i), oldStart(p, i));
    }
    expect(p.durationMs, oldDuration(p));
  });
}
