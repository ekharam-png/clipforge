// 1.11 "gentle by default": which fillers are cut at Light / Normal /
// Strong, the guard rails (distance, cuts per minute, shortest piece), the
// jump check's effect, the automatic-cut log, and "Put back".
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/transcript/cut_plan.dart';
import 'package:clipforge/core/transcript/fillers.dart';
import 'package:clipforge/core/transcript/speech_edits.dart';
import 'package:clipforge/core/transcript/transcript.dart';
import 'package:clipforge/core/transcript/transcript_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ProjectEditor ed(Project p) {
  var n = 0;
  var now = t0;
  return ProjectEditor(p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'id${++n}');
}

/// Words given as (text, start, end).
Transcript talk(List<(String, int, int)> words, {String path = '/media/a.mp4'}) =>
    Transcript(
      sourcePath: path,
      audioTrack: 0,
      language: 'en',
      requestedLanguage: 'en',
      model: 'base.en',
      backend: 'whisper-cpp',
      wordTiming: WordTiming.measured,
      durationMs: words.last.$3,
      createdAt: t0,
      segments: segmentsFromWords(
          [for (final w in words) TranscriptWord(w.$1, w.$2, w.$3)]),
    );

List<FillerHit> hitsOf(Project p, Transcript t) => findFillers(
    timelineWords(p, (path, track) => path == t.sourcePath ? t : null),
    fillersFor('en'));

/// One filler every [everyMs]: "word um word", the um [umMs] long with
/// [gapMs] of silence on each side.
Transcript regular(int count, {int everyMs = 5000, int umMs = 300, int gapMs = 200}) {
  final w = <(String, int, int)>[];
  for (var i = 0; i < count; i++) {
    final t = 1000 + i * everyMs;
    w.add(('so', t, t + 300));
    w.add(('um', t + 300 + gapMs, t + 300 + gapMs + umMs));
    w.add(('yes', t + 300 + 2 * gapMs + umMs, t + 600 + 2 * gapMs + umMs));
  }
  return talk(w);
}

void main() {
  final long = project(clips: [video('a', source: 600000)]);

  test('Light: only clear fillers that stand alone between pauses', () {
    final t = talk([
      ('Well', 2000, 2300),
      // A clear one: 400 ms of um with 300 ms of silence on both sides.
      ('um', 2600, 3000),
      ('I', 3300, 3500),
      ('think', 3500, 3900),
      // Glued to the next word.
      ('uh', 7000, 7300),
      ('it', 7320, 7500),
      ('works', 7500, 8000),
      // Short and quick.
      ('er', 11000, 11100),
      ('yes', 11200, 11500),
    ]);
    final hits = hitsOf(long, t);
    expect(hits.length, 3);
    final light = planFillerCuts(long, hits, CutRules.of(CutStrength.light));
    expect(light.map((c) => c.decision), [
      CutDecision.cut,
      CutDecision.inSpeech,
      CutDecision.tooShort,
    ]);
    final normal = planFillerCuts(long, hits, CutRules.of(CutStrength.normal));
    expect(normal.map((c) => c.decision),
        [CutDecision.cut, CutDecision.cut, CutDecision.cut]);
    // The short "er": 100 ms + 40 ms pad kept... its cut is under 200 ms
    // only when the pauses around it are tiny.
    final tight = talk([
      ('a', 3000, 3300), ('er', 3320, 3420), ('b', 3440, 3800), //
    ]);
    final one = hitsOf(long, tight).single;
    expect(one.cutMs, lessThan(200));
    expect(planFillerCuts(long, [one], CutRules.of(CutStrength.normal)).single.decision,
        CutDecision.tooShort);
    expect(planFillerCuts(long, [one], CutRules.of(CutStrength.strong)).single.decision,
        CutDecision.cut);
  });

  test('guard rails: distance between cuts, the longer cut wins', () {
    final t = talk([
      ('a', 5000, 5300),
      ('um', 5500, 5800),
      ('b', 6200, 6500),
      ('uh', 6900, 7500), // the longer one, 1.4 s after the first
      ('c', 8000, 8300),
    ]);
    final hits = hitsOf(long, t);
    expect(hits[1].cutMs, greaterThan(hits[0].cutMs));
    final light = planFillerCuts(long, hits, CutRules.of(CutStrength.light));
    expect(light.map((c) => c.decision), [CutDecision.tooClose, CutDecision.cut]);
    // Normal allows 1.5 s... these are 1.4 s apart.
    final normal = planFillerCuts(long, hits, CutRules.of(CutStrength.normal));
    expect(normal.map((c) => c.decision), [CutDecision.tooClose, CutDecision.cut]);
    final strong = planFillerCuts(long, hits, CutRules.of(CutStrength.strong));
    expect(strong.every((c) => c.isCut), isTrue);
    // Advanced override.
    final loose = planFillerCuts(
        long, hits, CutRules.of(CutStrength.light).copyWith(minDistanceMs: 500));
    expect(loose.every((c) => c.isCut), isTrue);
  });

  test('guard rails: cuts per minute (4 Light, 8 Normal, no limit Strong)', () {
    // 24 clear fillers in 2 minutes = 12 a minute.
    final t = regular(24);
    final hits = hitsOf(long, t);
    expect(hits.length, 24);
    int perMinuteMax(List<PlannedCut> plan) {
      final times = [for (final c in plan) if (c.isCut) c.hit.startMs];
      var most = 0;
      for (final a in times) {
        final n = times.where((b) => b >= a && b < a + 60000).length;
        if (n > most) most = n;
      }
      return most;
    }

    final light = planFillerCuts(long, hits, CutRules.of(CutStrength.light));
    expect(perMinuteMax(light), lessThanOrEqualTo(4));
    expect(light.where((c) => c.isCut).length, inInclusiveRange(6, 10));
    expect(light.where((c) => c.decision == CutDecision.minuteFull), isNotEmpty);
    final normal = planFillerCuts(long, hits, CutRules.of(CutStrength.normal));
    expect(perMinuteMax(normal), lessThanOrEqualTo(8));
    expect(normal.where((c) => c.isCut).length,
        greaterThan(light.where((c) => c.isCut).length));
    final strong = planFillerCuts(long, hits, CutRules.of(CutStrength.strong));
    expect(strong.where((c) => c.isCut).length, 24);

    final sum = CutSummary(light, 120000);
    expect(sum.found, 24);
    expect(sum.cuts + sum.skippedTooClose + sum.skippedSmall, 24);
    expect(sum.cutsPerMinute, sum.cuts / 2);
    expect(sum.perMinuteText, 'about ${(sum.cuts / 2).round()}');
    expect(sum.savedMs, greaterThan(sum.cuts * 350));
  });

  test('guard rails: never leaves a piece shorter than 0.6 s', () {
    // The clip starts 300 ms before the filler.
    final p = project(clips: [video('a', source: 60000, inMs: 4900, outMs: 30000)]);
    final t = talk([
      ('um', 5200, 5700),
      ('hello', 6000, 6400),
      ('there', 6400, 6800),
    ]);
    final hit = hitsOf(p, t).single;
    for (final s in CutStrength.values) {
      expect(planFillerCuts(p, [hit], CutRules.of(s)).single.decision,
          CutDecision.shortPiece);
    }
  });

  test('jump check: jumpy cuts are left in on Light and Normal, slight ones '
      'get a dissolve; unknown = not held back', () {
    final hits = hitsOf(long, regular(4, everyMs: 20000));
    final jumps = {0: 0.05, 1: 0.3, 2: 0.8};
    final light = planFillerCuts(long, hits, CutRules.of(CutStrength.light), jumps: jumps);
    expect(light.map((c) => c.decision),
        [CutDecision.cut, CutDecision.cut, CutDecision.jumpy, CutDecision.cut]);
    expect(light.map((c) => c.smooth), [false, true, false, false]);
    expect(light.map((c) => c.jumpRating), ['smooth', 'slight', 'jumpy', '']);
    final strong =
        planFillerCuts(long, hits, CutRules.of(CutStrength.strong), jumps: jumps);
    expect(strong.every((c) => c.isCut), isTrue);
    expect(strong[2].smooth, isTrue);
    final sum = CutSummary(light, 80000);
    expect([sum.cuts, sum.skippedJumpy, sum.smoothed], [3, 1, 1]);
  });

  group('log and put back', () {
    late ProjectEditor e;
    late Transcript t;
    late List<PlannedCut> plan;

    setUp(() {
      e = ed(project(clips: [
        video('a', source: 60000)
      ], titles: [
        title('late', startMs: 30000, endMs: 32000, text: 'on the later piece'),
      ]));
      t = regular(3, everyMs: 12000);
      plan = planFillerCuts(e.project, hitsOf(e.project, t),
          CutRules.of(CutStrength.light),
          jumps: {0: 0.0, 1: 0.3});
    });

    test('every cut is recorded, one undo step, slight jumps dissolve', () {
      final n = applyPlannedCuts(e, plan, by: 'claude', newId: () => 'cut${e.project.autoCuts.length}', now: t0);
      expect(n, 3);
      expect(e.history.length, 1);
      expect(e.history.single.label, 'Removed 3 filler words');
      final p = e.project;
      expect(p.clips.length, 4);
      expect(p.autoCuts.map((c) => [c.kind, c.word, c.by, c.path]),
          everyElement(['filler', 'um', 'claude', '/media/a.mp4']));
      expect(p.autoCuts.map((c) => c.jump), [0.0, 0.3, null]);
      expect(p.autoCuts.map((c) => c.smoothed), [false, true, false]);
      // The piece after the second cut starts with a 150 ms dissolve.
      expect(p.clips[2].transition, TransitionType.crossfade);
      expect(p.clips[2].transitionMs, kSmoothMs);
      expect(p.clips[1].transition, TransitionType.none);
      // Round trip through JSON; old projects have none.
      final back = Project.fromJson(p.toJson());
      expect(back.autoCuts.length, 3);
      expect(back.autoCuts[1].jump, 0.3);
      expect(project().toJson().containsKey('autoCuts'), isFalse);
      final totals = autoCutTotals(p);
      expect(totals.count, 3);
      expect(totals.savedMs, plan.fold<int>(0, (s, c) => s + c.hit.cutMs));
      e.undo();
      expect(e.project.autoCuts, isEmpty);
      expect(e.project.clips.length, 1);
    });

    test('put back heals the two pieces; titles after it move back', () {
      var k = 0;
      applyPlannedCuts(e, plan, newId: () => 'cut${k++}', now: t0);
      final cutLen = plan.first.hit.cutMs;
      final titleAt = e.project.titles.single.startMs;
      final steps = e.history.length;
      expect(restoreAutoCut(e, 'cut0', newId: () => 'n'), RestoreResult.healed);
      expect(e.history.length, steps + 1);
      expect(e.history.last.label, 'Put back 1 automatic cut');
      expect(e.project.clips.length, 3);
      expect(e.project.autoCuts.map((c) => c.id), ['cut1', 'cut2']);
      expect(e.project.clips.first.outMs, plan[1].hit.cutStartMs);
      expect(e.project.titles.single.startMs, titleAt + cutLen);
      expect(restoreAutoCut(e, 'nope', newId: () => 'n'), RestoreResult.unknown);
      // All the rest: the clip is whole and the title where it started.
      expect(restoreAllAutoCuts(e, newId: () => 'n'), 2);
      expect(e.project.clips.single.outMs, 60000);
      expect(e.project.clips.single.transition, TransitionType.none);
      expect(e.project.titles.single.startMs, 30000);
      expect(e.project.autoCuts, isEmpty);
      expect(e.history.last.label, 'Put back 2 automatic cuts');
    });

    test('pieces that changed since: the part comes back as its own clip', () {
      var k = 0;
      applyPlannedCuts(e, plan, newId: () => 'cut${k++}', now: t0);
      final cut = e.project.autoCuts.first;
      // The piece before the cut was trimmed since.
      e.trimClip(e.project.clips.first.id, outMs: cut.startMs - 500);
      expect(restoreAutoCut(e, cut.id, newId: () => 'new'), RestoreResult.asClip);
      final p = e.project;
      expect(p.clips.length, 5);
      expect([p.clips[1].id, p.clips[1].inMs, p.clips[1].outMs],
          ['new', cut.startMs, cut.endMs]);
      expect(p.autoCuts.length, 2);
    });

    test('silences are logged too, and "all" can take only one kind', () {
      var k = 0;
      applyPlannedCuts(e, plan, newId: () => 'f${k++}', now: t0);
      final clip = e.project.clips.last;
      e.transaction(() {
        final r = [(startMs: clip.inMs + 5000, endMs: clip.inMs + 7000)];
        e.removeSourceRanges(clip.id, r);
        logSilenceCuts(e, clip.path, r, newId: () => 's0', now: t0);
      });
      expect(e.project.autoCuts.map((c) => c.kind),
          ['filler', 'filler', 'filler', 'silence']);
      expect(restoreAllAutoCuts(e, kind: 'silence', newId: () => 'n'), 1);
      expect(e.project.autoCuts.map((c) => c.kind), everyElement('filler'));
      expect(e.project.clips.length, 4);
    });
  });
}
