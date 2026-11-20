// 1.17 "select a part": the part and its rows, "why not" per action, the
// quiet-range model (and how it follows trims, cuts and speed), and every
// edit on a part - across clip boundaries, with speed other than 1, with
// linked voices, with transitions at the edges - each one undo step with
// a History label, and put back from the automatic-cut log.

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/editor/snapping.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/transcript/speech_edits.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ProjectEditor ed(Project p) {
  var n = 0;
  var now = t0;
  return ProjectEditor(p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'id${++n}');
}

List<String> labels(ProjectEditor e) => [for (final h in e.history) h.label];

AudioClip voiceFile(String name, {int length = 30000}) => AudioClip(
      id: 'tmp',
      path: '/media/$name.m4a',
      sourceDurationMs: length,
      startMs: 0,
      inMs: 0,
      outMs: length,
    );

/// Three clips of 10 s, music over all of it on "Music", a title on the
/// second clip, a caption on the third, a marker at 25 s.
Project three({List<Clip>? clips}) => Project(
      id: 'p',
      name: 'p',
      createdAt: t0,
      updatedAt: t0,
      clips: clips ?? [video('a'), video('b'), video('c')],
      tracks: const [SoundTrack(id: 'm', name: 'Music')],
      audio: [
        AudioClip(
            id: 'mu',
            path: '/media/mu.mp3',
            sourceDurationMs: 60000,
            startMs: 0,
            inMs: 0,
            outMs: 30000,
            trackId: 'm'),
      ],
      titles: [
        title('t1', startMs: 12000, endMs: 14000),
        title('t2', startMs: 21000, endMs: 23000),
      ],
      markers: const [Marker(id: 'k', ms: 25000)],
    );

void main() {
  group('the part', () {
    test('either order, clamping, contains and overlaps', () {
      final p = TimelinePart.between(5000, 2000);
      expect(p, const TimelinePart(2000, 5000));
      expect(p.lengthMs, 3000);
      expect(p.contains(2000), isTrue);
      expect(p.contains(5000), isFalse);
      expect(p.overlaps(4999, 9000), isTrue);
      expect(p.overlaps(5000, 9000), isFalse);
      expect(const TimelinePart(-500, 99999).clampTo(30000),
          const TimelinePart(0, 30000));
      expect(const TimelinePart(40000, 50000).clampTo(30000).isEmpty, isTrue);
    });

    test('labels', () {
      expect(partLengthLabel(2340), '2.3 s');
      expect(partLengthLabel(65200), '1:05.2');
      expect(levelLabel(0), 'silence');
      expect(levelLabel(levelFromDb(-12)), '−12 dB');
      expect(levelFromDb(-6), closeTo(0.501, 0.001));
    });

    test('quick selections: clip, between markers, stretch, pause', () {
      final p = three().copyWith(markers: const [
        Marker(id: 'k1', ms: 4000),
        Marker(id: 'k2', ms: 25000),
      ]);
      expect(partOfClip(p, 'b'), const TimelinePart(10000, 20000));
      expect(partOfClip(p, 'nope'), isNull);
      expect(partBetweenMarkers(p, 9000), const TimelinePart(4000, 25000));
      expect(partBetweenMarkers(p, 1000), const TimelinePart(0, 4000),
          reason: 'from the start to the first marker');
      expect(partBetweenMarkers(p, 26000), const TimelinePart(25000, 30000));
      expect(partBetweenMarkers(three().copyWith(markers: const []), 5), isNull);
      const talk = [
        (startMs: 1000, endMs: 3000),
        (startMs: 5000, endMs: 9000),
      ];
      expect(stretchAt(talk, 2000), const TimelinePart(1000, 3000));
      expect(stretchAt(talk, 4000), isNull);
      expect(pauseAt(talk, 4000, 30000), const TimelinePart(3000, 5000));
      expect(pauseAt(talk, 500, 30000), const TimelinePart(0, 1000));
      expect(pauseAt(talk, 12000, 30000), const TimelinePart(9000, 30000));
      expect(pauseAt(talk, 6000, 30000), isNull, reason: 'someone is talking');
    });

    test('edges snap to cuts, markers, the playhead and speech edges', () {
      final p = three();
      final targets = snapTargets(p,
          playheadMs: 7777,
          extra: [for (final m in p.markers) m.ms, 16400]);
      expect(snapTime(10030, targets, 100).ms, 10000, reason: 'a cut');
      expect(snapTime(24950, targets, 100).ms, 25000, reason: 'a marker');
      expect(snapTime(7700, targets, 100).ms, 7777, reason: 'the playhead');
      expect(snapTime(16450, targets, 100).ms, 16400, reason: 'speech');
      expect(snapTime(11950, targets, 100).ms, 12000, reason: 'a title');
      // Nothing near: it stays (and with snapping off nothing is asked).
      expect(snapTime(15000, targets, 100).snapped, isNull);
    });
  });

  group('rows', () {
    test('the rows of a project, top to bottom', () {
      final p = three();
      expect(partRowsOf(p).map((r) => r.id), [kRowVideo, 'm', kRowTitles]);
      expect(partRowsOf(project()).map((r) => r.id), isEmpty);
      expect(allRowsTicked(p, null), isTrue);
      expect(allRowsTicked(p, {kRowVideo, 'm', kRowTitles}), isTrue);
      expect(allRowsTicked(p, {kRowVideo}), isFalse);
      expect(rowTicked({'m'}, 'm'), isTrue);
      expect(rowTicked({'m'}, kRowVideo), isFalse);
    });

    test('why an action cannot change a row', () {
      final p = three();
      const part = TimelinePart(11000, 15000);
      String? why(PartAction a, String row) => partRowProblem(
          p, part, a, partRowsOf(p).firstWhere((r) => r.id == row));
      expect(why(PartAction.silence, kRowVideo), isNull);
      expect(why(PartAction.silence, 'm'), isNull);
      expect(why(PartAction.silence, kRowTitles), 'titles have no sound');
      expect(why(PartAction.deleteGap, kRowVideo),
          'the video row cannot have a gap: use Cut out');
      expect(why(PartAction.deleteGap, 'm'), isNull);
      expect(why(PartAction.deleteGap, kRowTitles), isNull);
      expect(why(PartAction.speed, kRowVideo), isNull);
      expect(why(PartAction.speed, 'm'), 'music and other sound keep their speed');
      expect(why(PartAction.speed, kRowTitles), 'titles stay on their picture');
      expect(why(PartAction.clean, 'm'), isNull);
      expect(why(PartAction.cutOut, kRowTitles), isNull);
      // Where nothing is.
      const empty = TimelinePart(2000, 3000);
      expect(
          partRowProblem(p, empty, PartAction.deleteGap,
              partRowsOf(p).firstWhere((r) => r.id == kRowTitles)),
          'nothing on this row here');
      // The camera's sound switched off.
      final muted = p.copyWith(clips: [
        for (final c in p.clips) c.copyWith(muted: true),
      ]);
      expect(
          partRowProblem(muted, part, PartAction.silence,
              partRowsOf(muted).first),
          "the video's own sound is switched off here");
      // Photos only.
      final photos = three(clips: [photo('x', durationMs: 20000)]);
      expect(
          partRowProblem(photos, const TimelinePart(1000, 3000),
              PartAction.speed, partRowsOf(photos).first),
          'no video clip here (photos have no speed)');
    });

    test('why an action cannot be done at all', () {
      final p = three();
      const part = TimelinePart(11000, 15000);
      String? why(PartAction a, [Set<String>? rows, TimelinePart? at = part]) =>
          partActionProblem(p, at, a, rows);
      expect(why(PartAction.cutOut), isNull);
      expect(why(PartAction.cutOut, {kRowVideo}),
          'tick every row: lips and voice would no longer match afterwards');
      expect(why(PartAction.cutOut, null, null), 'select a part first');
      expect(why(PartAction.cutOut, null, const TimelinePart(100, 150)),
          'the part is too short');
      expect(why(PartAction.cutOut, null, const TimelinePart(0, 30000)),
          'that would remove the whole video');
      expect(why(PartAction.cutOut, null, const TimelinePart(31000, 35000)),
          'the part is after the video');
      expect(why(PartAction.silence, {kRowTitles}), 'titles have no sound');
      expect(why(PartAction.silence, <String>{}), 'tick a row first');
      expect(why(PartAction.silence, {'m'}), isNull);
      expect(why(PartAction.deleteGap, {kRowVideo}),
          'the video row cannot have a gap: use Cut out');
      expect(why(PartAction.deleteGap), isNull, reason: 'music and titles can');
      expect(why(PartAction.speed, {'m'}), 'tick the video row');
      expect(why(PartAction.speed), isNull);
      expect(why(PartAction.addTitle), isNull);
      expect(partActionProblem(project(), part, PartAction.silence, null),
          'add a video first');
    });
  });

  group('quiet ranges', () {
    test('the level: 1 outside, the level inside, a 40 ms line at the edges',
        () {
      const r = QuietRange(1000, 2000);
      expect(r.gainAt(999), 1);
      expect(r.gainAt(1000), 1);
      expect(r.gainAt(1020), closeTo(0.5, 1e-9));
      expect(r.gainAt(1040), 0);
      expect(r.gainAt(1500), 0);
      expect(r.gainAt(1980), closeTo(0.5, 1e-9));
      expect(r.gainAt(2000), 1);
      const low = QuietRange(1000, 2000, 0.25);
      expect(low.gainAt(1500), 0.25);
      expect(low.gainAt(1020), closeTo(0.625, 1e-9));
      // Shorter than two fades: half each.
      const short = QuietRange(0, 40);
      expect(short.fadeMs, 20);
      expect(short.gainAt(20), 0);
      expect(quietGainAt(const [r, low], 1500), 0);
      expect(quietGainAt(const [], 1500), 1);
    });

    test('a new range lies over the old ones; neighbours of one level join',
        () {
      var q = addQuietRange(const [], const QuietRange(1000, 2000));
      q = addQuietRange(q, const QuietRange(2000, 3000));
      expect(q, [const QuietRange(1000, 3000)]);
      q = addQuietRange(q, const QuietRange(1500, 2500, 0.5));
      expect(q, [
        const QuietRange(1000, 1500),
        const QuietRange(1500, 2500, 0.5),
        const QuietRange(2500, 3000),
      ]);
      // Level 1 clears ("Remove").
      q = addQuietRange(q, const QuietRange(1200, 2800, 1));
      expect(q, [const QuietRange(1000, 1200), const QuietRange(2800, 3000)]);
      q = addQuietRange(q, const QuietRange(0, 9000, 1));
      expect(q, isEmpty);
    });

    test('in the project file only when there are any; old files read', () {
      final c = video('a');
      expect(c.toJson().containsKey('quiet'), isFalse);
      final q = c.copyWith(quiet: const [QuietRange(1000, 2000, 0.25)]);
      final back = Clip.fromJson(q.toJson());
      expect(back.quiet, [const QuietRange(1000, 2000, 0.25)]);
      final a = audio('x').copyWith(quiet: const [QuietRange(5, 900)]);
      expect(AudioClip.fromJson(a.toJson()).quiet, [const QuietRange(5, 900)]);
      expect(audio('x').toJson().containsKey('quiet'), isFalse);
      // Rubbish is dropped, not an error.
      expect(
          QuietRange.listFromJson([
            {'fromMs': 5, 'toMs': 2},
            'x',
            {'fromMs': 1, 'toMs': 9, 'level': 7},
          ]),
          [const QuietRange(1, 9, 1)]);
      // A track's gate.
      const t = SoundTrack(id: 'v', name: 'Voice', speech: true);
      expect(t.toJson().containsKey('gate'), isFalse);
      final g = SoundTrack.fromJson(
          t.copyWith(gate: true, gateLevel: 0).toJson());
      expect([g.gate, g.gateLevel], [true, 0.0]);
      expect(SoundTrack.fromJson(t.toJson()).gateLevel, kGateDefaultLevel);
    });
  });

  group('silence and lower', () {
    test('silence across a cut, on every row: one step, nothing moves', () {
      final e = ed(three());
      final before = e.project;
      final r = e.silencePart(const TimelinePart(8000, 12000));
      expect(r.ok, isTrue);
      expect(r.changed, 3, reason: 'two clips and the music');
      final p = e.project;
      // The part runs past each clip's edge at the cut: the range is made
      // longer there, so its fade lies outside the clip.
      expect(p.clips[0].quiet, [const QuietRange(8000, 10080)]);
      expect(p.clips[1].quiet, [const QuietRange(-80, 2000)]);
      expect(p.clips[2].quiet, isEmpty);
      expect(p.audio.single.quiet, [const QuietRange(8000, 12000)]);
      expect(p.durationMs, before.durationMs);
      expect(p.titles.map((t) => t.startMs), [12000, 21000]);
      expect(labels(e), ['Silenced a part (4.0 s) on Video, Music']);
      e.undo();
      expect(content(e.project), content(before));
      e.redo();
      expect(e.project.clips[0].quiet, isNotEmpty);
    });

    test('only one row; lower by 12 dB; doing it again changes nothing', () {
      final e = ed(three());
      expect(
          e.silencePart(const TimelinePart(11000, 13000),
              rows: {'m'}, level: levelFromDb(-12)).changed,
          1);
      expect(e.project.clips.every((c) => c.quiet.isEmpty), isTrue);
      expect(e.project.audio.single.quiet.single.level, closeTo(0.251, 0.001));
      expect(labels(e).single, 'Lowered a part (2.0 s) to −12 dB on Music');
      final again = e.silencePart(const TimelinePart(11000, 13000),
          rows: {'m'}, level: levelFromDb(-12));
      expect(again.problem, 'it is already like that');
      expect(e.history.length, 1);
      // A row that cannot: the reason, and no undo step.
      expect(
          e.silencePart(const TimelinePart(11000, 13000),
              rows: {kRowTitles}).problem,
          'titles have no sound');
      expect(e.history.length, 1);
    });

    test('the range is in source time: it follows speed, trim, split, cuts',
        () {
      // 2 s..8 s of the file at double speed: 3 s on the timeline.
      final e = ed(three(clips: [video('a', inMs: 2000, outMs: 8000, speed: 2)])
          .copyWith(audio: const [], titles: const []));
      expect(e.silencePart(const TimelinePart(1000, 2000)).ok, isTrue);
      expect(e.project.clips.single.quiet, [const QuietRange(4000, 6000)]);
      // Split in the middle of it: both pieces keep the list.
      expect(e.splitAt(1500), isTrue);
      expect(e.project.clips.map((c) => c.quiet.single),
          [const QuietRange(4000, 6000), const QuietRange(4000, 6000)]);
      expect(e.project.clips.map((c) => c.quietInUse.length), [1, 1]);
      // Trim the second piece past it: nothing of it is in use any more.
      e.trimClip(e.project.clips[1].id, inMs: 6500);
      expect(e.project.clips[1].quietInUse, isEmpty);
      // Speed back to 1: still the same sound.
      e.setClipSpeed(e.project.clips[0].id, 1);
      expect(e.project.clips[0].quiet, [const QuietRange(4000, 6000)]);
      // A piece cut out of the first (Remove silences): the pieces keep it.
      e.removeSourceRanges(e.project.clips[0].id, [(startMs: 3000, endMs: 3500)]);
      expect(e.project.clips.take(2).every((c) => c.quiet.length == 1), isTrue);
    });

    test('linked voices: their own row, their own file time', () {
      final e = ed(three(clips: [video('a', source: 30000)])
          .copyWith(audio: const [], titles: const []));
      final ids =
          e.addVoice(voiceFile('sam'), clipId: 'a', offsetMs: 500, trackName: 'Sam');
      final track = e.project.audio.single.trackId;
      expect(e.silencePart(const TimelinePart(4000, 6000), rows: {track}).ok,
          isTrue);
      final v = e.project.audio.firstWhere((a) => a.id == ids.single);
      // time in the voice file = time in the clip's file + offset
      expect(v.quiet, [const QuietRange(4500, 6500)]);
      expect(e.project.clips.single.quiet, isEmpty,
          reason: 'the camera row was not ticked');
      expect(labels(e).last, 'Silenced a part (2.0 s) on Sam');
      // The clip is split and its second half sped up: the voice pieces
      // follow, and both still carry the range.
      e.splitAt(5000);
      e.setClipSpeed(e.project.clips[1].id, 2);
      final voices = e.project.audio.where((a) => a.isVoice).toList();
      expect(voices, hasLength(2));
      expect(voices.every((a) => a.quiet.single == const QuietRange(4500, 6500)),
          isTrue);
      expect(voices[1].speed, 2);
    });

    test('a separated sound takes the ranges along, and gives them back', () {
      final e = ed(three().copyWith(audio: const []));
      e.silencePart(const TimelinePart(2000, 3000), rows: {kRowVideo});
      final id = e.separateSound('a')!;
      expect(e.project.audio.firstWhere((a) => a.id == id).quiet,
          [const QuietRange(2000, 3000)]);
      e.silencePart(const TimelinePart(5000, 6000));
      expect(e.reattachSound(id), isTrue);
      expect(e.project.clips.first.quiet,
          [const QuietRange(2000, 3000), const QuietRange(5000, 6000)]);
    });

    test('a looped sound: the stretch of the pass that plays there', () {
      final loop = AudioClip(
          id: 'lp',
          path: '/media/lp.mp3',
          sourceDurationMs: 4000,
          startMs: 0,
          inMs: 0,
          outMs: 4000,
          loopMs: 30000,
          trackId: 'm');
      final step = loop.passMs - loop.loopCrossfadeMs;
      final r = soundSourceRange(loop, TimelinePart(step + 1000, step + 2000));
      expect(r, (from: 1000, to: 2000));
    });

    test('remove a quiet part: only that stretch, one step', () {
      final e = ed(three());
      e.silencePart(const TimelinePart(2000, 6000), rows: {'m'});
      expect(e.removeQuiet('mu', 3000, 4000), isTrue);
      expect(e.project.audio.single.quiet,
          [const QuietRange(2000, 3000), const QuietRange(4000, 6000)]);
      expect(labels(e).last, 'Removed a quiet part');
      expect(e.removeQuiet('mu', 3000, 4000), isFalse);
      expect(e.removeQuiet('nope', 0, 9), isFalse);
      expect(e.history.length, 2);
      // On a main-track clip too.
      e.silencePart(const TimelinePart(2000, 6000), rows: {kRowVideo});
      expect(e.removeQuiet('a', 0, 99999), isTrue);
      expect(e.project.clips.first.quiet, isEmpty);
    });
  });

  group('cut out', () {
    test('across a cut: time goes from everything, the gap closes', () {
      var k = 0;
      final e = ProjectEditor(three(),
          clock: () => t0, newId: () => 'n${k++}');
      final before = e.project;
      final r = e.cutPart(const TimelinePart(8000, 12000));
      expect(r.ok, isTrue);
      expect(r.removedMs, 4000);
      final p = e.project;
      expect(p.durationMs, 26000);
      expect(p.clips.map((c) => [c.id, c.inMs, c.outMs]), [
        ['a', 0, 8000],
        ['b', 2000, 10000],
        ['c', 0, 10000],
      ]);
      // The title was at 12 s..14 s on clip b (its 2 s..4 s): now 8 s.
      expect(p.titles.map((t) => [t.startMs, t.endMs]), [
        [8000, 10000],
        [17000, 19000],
      ]);
      expect(p.markers.single.ms, 21000, reason: 'the marker follows its picture');
      // The music lost the same 4 s and is in two pieces that join.
      final music = p.audio.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(music.map((a) => [a.startMs, a.endMs, a.inMs, a.outMs]), [
        [0, 8000, 0, 8000],
        [8000, 26000, 12000, 30000],
      ]);
      expect([music[0].fadeOutMs, music[1].fadeInMs], [kJoinFadeMs, kJoinFadeMs]);
      // One step, one name, and the log knows the two removed pieces.
      expect(labels(e), ['Cut out a part (4.0 s)']);
      expect(p.autoCuts.map((c) => [c.kind, c.path, c.startMs, c.endMs]), [
        ['part', '/media/a.mp4', 8000, 10000],
        ['part', '/media/b.mp4', 0, 2000],
      ]);
      e.undo();
      expect(content(e.project), content(before));
    });

    test('put back: the video and the music are whole again', () {
      var k = 0;
      final e = ProjectEditor(three(), clock: () => t0, newId: () => 'n${k++}');
      final before = e.project;
      e.cutPart(const TimelinePart(13000, 16000));
      expect(e.project.durationMs, 27000);
      expect(e.project.audio, hasLength(2));
      final cut = e.project.autoCuts.single;
      expect(restoreAutoCut(e, cut.id, newId: () => 'r${k++}'),
          RestoreResult.healed);
      final p = e.project;
      expect(p.durationMs, 30000);
      expect(p.clips.map((c) => [c.inMs, c.outMs]), before.clips.map((c) => [c.inMs, c.outMs]));
      expect(p.audio.single.startMs, 0);
      expect([p.audio.single.inMs, p.audio.single.outMs], [0, 30000]);
      expect(p.titles.map((t) => t.startMs), [12000, 21000]);
      expect(p.autoCuts, isEmpty);
      expect(labels(e).last, 'Put back 1 automatic cut');
    });

    test('with a speed other than 1 and a linked voice', () {
      final e = ed(three(clips: [video('a', source: 30000, speed: 2)])
          .copyWith(audio: const [], titles: const [], markers: const []));
      e.addVoice(voiceFile('sam'), clipId: 'a', offsetMs: 0);
      // 15 s of video; cut 5 s..7 s of the timeline = 10 s..14 s of the file.
      final r = e.cutPart(const TimelinePart(5000, 7000));
      expect(r.removedMs, 2000);
      final p = e.project;
      expect(p.clips.map((c) => [c.inMs, c.outMs, c.speed]), [
        [0, 10000, 2.0],
        [14000, 30000, 2.0],
      ]);
      final voices = p.audio.where((a) => a.isVoice).toList()
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(voices.map((a) => [a.startMs, a.inMs, a.outMs, a.speed]), [
        [0, 0, 10000, 2.0],
        [5000, 14000, 30000, 2.0],
      ]);
      expect(p.autoCuts.single.startMs, 10000);
      expect(p.autoCuts.single.endMs, 14000);
    });

    test('with transitions at the edges; whole clips; photos', () {
      final e = ed(three(clips: [
        video('a'),
        video('b', transition: TransitionType.crossfade, transitionMs: 1000),
        photo('ph', durationMs: 4000),
        video('c'),
      ]).copyWith(audio: const [], titles: const [], markers: const []));
      final total = e.project.durationMs; // 10 + 10 - 1 + 4 + 10
      expect(total, 33000);
      // From inside a, over the whole of b, to the middle of the photo.
      final r = e.cutPart(const TimelinePart(6000, 21000));
      expect(r.ok, isTrue);
      final p = e.project;
      expect(p.clips.map((c) => c.id), ['a', 'ph', 'c']);
      expect(p.clips[0].outMs, 6000);
      expect(p.clips[1].durationMs, 2000, reason: 'the photo lost 2 s');
      expect(p.durationMs, total - r.removedMs);
      expect(r.removedMs, 15000);
      expect(labels(e), ['Cut out a part (15.0 s)']);
    });

    test('needs every row, a part inside the video, and not all of it', () {
      final e = ed(three());
      expect(e.cutPart(const TimelinePart(0, 30000)).problem,
          'that would remove the whole video');
      expect(e.cutPart(const TimelinePart(40000, 45000)).problem,
          'the part is after the video');
      expect(e.history, isEmpty);
    });
  });

  group('delete and leave a gap', () {
    test('music and titles lose the part; nothing moves; the video stays',
        () {
      final e = ed(three());
      final r = e.deletePart(const TimelinePart(13000, 22000));
      expect(r.ok, isTrue);
      final p = e.project;
      expect(p.durationMs, 30000);
      expect(p.clips.map((c) => c.durationMs), [10000, 10000, 10000]);
      final music = p.audio.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(music.map((a) => [a.startMs, a.endMs, a.inMs]), [
        [0, 13000, 0],
        [22000, 30000, 22000],
      ]);
      expect(p.titles.map((t) => [t.startMs, t.endMs]), [
        [12000, 13000],
        [22000, 23000],
      ]);
      expect(labels(e),
          ['Deleted a part (9.0 s) on Music, Titles and captions, leaving a gap']);
    });

    test('a title in the middle of the part goes; one that spans it is two',
        () {
      final e = ed(three().copyWith(titles: [
        title('in', startMs: 12000, endMs: 13000),
        title('over', startMs: 5000, endMs: 20000),
      ]));
      e.deletePart(const TimelinePart(11000, 14000), rows: {kRowTitles});
      expect(e.project.titles.map((t) => [t.startMs, t.endMs]), [
        [5000, 11000],
        [14000, 20000],
      ]);
      expect(e.project.audio.single.durationMs, 30000, reason: 'not ticked');
    });

    test('linked sound and the video row are left alone, with the reason',
        () {
      final e = ed(three(clips: [video('a', source: 30000)])
          .copyWith(audio: const [], titles: const []));
      e.addVoice(voiceFile('sam'), clipId: 'a', offsetMs: 0);
      final track = e.project.audio.single.trackId;
      expect(e.deletePart(const TimelinePart(2000, 4000), rows: {track}).problem,
          'this sound follows its video clip: use Silence');
      expect(e.deletePart(const TimelinePart(2000, 4000)).problem,
          'nothing on the ticked rows can leave a gap');
    });
  });

  group('speed', () {
    test('the part is split out and slowed; what follows moves, music stays',
        () {
      final e = ed(three());
      final before = e.project;
      final r = e.speedPart(const TimelinePart(12000, 14000), 0.5);
      expect(r.ok, isTrue);
      expect(r.part, const TimelinePart(12000, 16000));
      final p = e.project;
      expect(p.clips.map((c) => [c.inMs, c.outMs, c.speed]), [
        [0, 10000, 1.0],
        [0, 2000, 1.0],
        [2000, 4000, 0.5],
        [4000, 10000, 1.0],
        [0, 10000, 1.0],
      ]);
      expect(p.durationMs, 32000);
      expect([p.audio.single.startMs, p.audio.single.endMs], [0, 30000],
          reason: 'music keeps its speed and its place');
      // The title was on b's 2 s..4 s: it stays on that picture, twice as long.
      expect([p.titles[0].startMs, p.titles[0].endMs], [12000, 16000]);
      expect(labels(e), ['Speed 0.5× on a part (2.0 s)']);
      e.undo();
      expect(content(e.project), content(before));
    });

    test('across a cut, with linked voices, muting the part', () {
      final e = ed(three(clips: [
        video('a', source: 30000, outMs: 10000),
        video('b'),
      ]).copyWith(audio: const [], titles: const [], markers: const []));
      e.addVoice(voiceFile('sam'), clipId: 'a', offsetMs: 0);
      final r = e.speedPart(const TimelinePart(8000, 12000), 0.25,
          muteOwnSound: true);
      expect(r.ok, isTrue);
      final p = e.project;
      expect(p.clips.map((c) => [c.speed, c.muted]), [
        [1.0, true], // muted like the whole file since the voice was added
        [0.25, true],
        [0.25, true],
        [1.0, false],
      ]);
      expect(r.part, const TimelinePart(8000, 24000));
      // The voice piece of the slowed part follows, and is silenced there.
      final slowed = p.audio.where((a) => a.isVoice && a.speed == 0.25).single;
      expect([slowed.startMs, slowed.inMs, slowed.outMs], [8000, 8000, 10000]);
      expect(quietGainAt(slowed.quiet, 9000), 0);
      final other = p.audio.where((a) => a.isVoice && a.speed == 1).single;
      expect(other.quiet, isEmpty);
      expect(labels(e).last, 'Speed 0.25× on a part (4.0 s), its sound off');
    });

    test('a transition at the edge of the part is kept', () {
      final e = ed(three(clips: [
        video('a'),
        video('b', transition: TransitionType.crossfade, transitionMs: 1000),
      ]).copyWith(audio: const [], titles: const [], markers: const []));
      // b starts at 9 s (1 s of overlap). Slow down 9 s..12 s.
      final r = e.speedPart(const TimelinePart(9000, 12000), 0.5);
      expect(r.ok, isTrue);
      final p = e.project;
      expect(p.clips.map((c) => c.speed), [1.0, 0.5, 1.0]);
      expect(p.clips[1].transition, TransitionType.crossfade);
      expect(p.clips[1].outMs, 3000);
    });

    test('nothing to do: no step', () {
      final e = ed(three());
      expect(e.speedPart(const TimelinePart(12000, 14000), 1).problem,
          'it already plays at that speed');
      expect(e.history, isEmpty);
      expect(e.project.clips, hasLength(3));
      expect(e.speedPart(const TimelinePart(12000, 14000), 2, rows: {'m'}).problem,
          'tick the video row');
    });
  });

  group('clean up sound here', () {
    test('the video and the music are split; only the middle is cleaned', () {
      final e = ed(three());
      final r = e.cleanPart(const TimelinePart(12000, 14000));
      expect(r.ok, isTrue);
      final p = e.project;
      expect(p.clips.map((c) => [c.inMs, c.outMs, c.denoise]), [
        [0, 10000, false],
        [0, 2000, false],
        [2000, 4000, true],
        [4000, 10000, false],
        [0, 10000, false],
      ]);
      final music = p.audio.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(music.map((a) => [a.startMs, a.endMs, a.inMs, a.outMs, a.denoise]), [
        [0, 12000, 0, 12000, false],
        [12000, 14000, 12000, 14000, true],
        [14000, 30000, 14000, 30000, false],
      ]);
      expect(p.durationMs, 30000);
      expect(labels(e), ['Cleaned up sound on a part (2.0 s)']);
      expect(e.cleanPart(const TimelinePart(12000, 14000)).problem,
          'the sound there is already cleaned');
      expect(e.history.length, 1);
    });

    test('only a linked voice row: its piece is cleaned, the camera not', () {
      final e = ed(three(clips: [video('a', source: 30000)])
          .copyWith(audio: const [], titles: const [], markers: const []));
      e.addVoice(voiceFile('sam'), clipId: 'a', offsetMs: 0, muteClips: false);
      final track = e.project.audio.single.trackId;
      expect(e.cleanPart(const TimelinePart(5000, 9000), rows: {track}).ok, isTrue);
      final p = e.project;
      expect(p.clips.map((c) => c.denoise), [false, false, false]);
      final voices = p.audio.toList()..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(voices.map((a) => [a.startMs, a.denoise]), [
        [0, false],
        [5000, true],
        [9000, false],
      ]);
    });
  });

  group('duplicate, and only when speaking', () {
    test('a copy of the part right after it', () {
      final e = ed(three().copyWith(audio: const [], titles: const []));
      final r = e.duplicatePart(const TimelinePart(8000, 12000));
      expect(r.ok, isTrue);
      expect(r.part, const TimelinePart(12000, 16000));
      final p = e.project;
      expect(p.durationMs, 34000);
      expect(p.clips.map((c) => [c.path.split('/').last, c.inMs, c.outMs]), [
        ['a.mp4', 0, 8000],
        ['a.mp4', 8000, 10000],
        ['b.mp4', 0, 2000],
        ['a.mp4', 8000, 10000],
        ['b.mp4', 0, 2000],
        ['b.mp4', 2000, 10000],
        ['c.mp4', 0, 10000],
      ]);
      expect(labels(e), ['Duplicated a part (4.0 s)']);
    });

    test('the switch and the level of a speech track', () {
      final e = ed(three().copyWith(tracks: const [
        SoundTrack(id: 'v', name: 'Sam', speech: true),
        SoundTrack(id: 'm', name: 'Music'),
      ]));
      e.setOnlyWhenSpeaking('v', on: true);
      expect(e.project.trackById('v')!.gate, isTrue);
      expect(e.project.trackById('v')!.gateLevel, kGateDefaultLevel);
      e.setOnlyWhenSpeaking('v', level: 0);
      expect(e.project.trackById('v')!.gateLevel, 0);
      e.setOnlyWhenSpeaking('v', on: false);
      expect(labels(e), [
        'Only when speaking on for Sam',
        'Only when speaking: silence between turns on Sam',
        'Only when speaking off for Sam',
      ]);
      e.setOnlyWhenSpeaking(SoundTrack.videoId, on: true);
      expect(e.history.length, 3, reason: 'not for the video sound');
    });
  });
}
