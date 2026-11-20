// 1.17, second pass after a real Windows test of 1.15:
//
//  * shorts from markers in a SHORT video (two markers at 0:11.6 and
//    0:23.7 of 35.3 s gave 0:00-0:35 twice, and one short was made);
//  * "Put back" brings the captions and titles of a cut back too (text
//    cuts and part cuts), with a cap on what is stored;
//  * the performance log: ring buffer, gaps, the watchdog that writes the
//    file when the app stops responding;
//  * the lane FFmpeg runs go through inside the app: user first,
//    background pre-empted, exports make background wait; throttled
//    progress;
//  * "Use a model file I have": an English-only file with the language on
//    Automatic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/perf_log.dart';
import 'package:clipforge/core/publish/shorts.dart';
import 'package:clipforge/core/transcript/speech_edits.dart';
import 'package:clipforge/media/ffmpeg_lane.dart';
import 'package:clipforge/media/transcribe/speech_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

ProjectEditor ed(Project project) {
  var n = 0;
  var now = t0;
  return ProjectEditor(project,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'id${++n}');
}

TitleOverlay caption(String id, int from, int to) => TitleOverlay(
    id: id, text: 'said $id', startMs: from, endMs: to, kind: TitleKind.caption);

/// One 60 s video with a caption every 2 s and a title at 20 s.
Project talk() => Project(
      id: 'p',
      name: 'p',
      createdAt: t0,
      updatedAt: t0,
      clips: [video('a', source: 60000)],
      titles: [
        for (var i = 0; i < 30; i++) caption('c$i', i * 2000, i * 2000 + 1800),
        title('big', startMs: 20000, endMs: 24000),
      ],
    );

void main() {
  group('shorts from markers', () {
    test('the real case: 35.3 s, markers at 0:11.6 and 0:23.7', () {
      const total = 35300;
      final a = markerRange(11600, total);
      final b = markerRange(23700, total);
      // Not the whole video, twice.
      expect(a, isNot((startMs: 0, endMs: total)));
      expect(a, isNot(b));
      for (final (r, m) in [(a, 11600), (b, 23700)]) {
        expect(r.startMs, greaterThanOrEqualTo(0));
        expect(r.endMs, lessThanOrEqualTo(total));
        expect(r.startMs, lessThan(m), reason: 'the marker is inside');
        expect(r.endMs, greaterThan(m));
        expect(r.endMs - r.startMs, greaterThanOrEqualTo(kMarkerMinMs));
        expect(r.endMs - r.startMs, lessThan(total * 0.6),
            reason: 'a short video gets a smaller window');
        // More after the marker than before it, as in a long video.
        expect(r.endMs - m, greaterThan(m - r.startMs));
      }
      expect(spanOverlapShare(a, b), lessThan(kMarkerOverlapShare));
      expect(overlappingGroups([a, b]), [
        [0],
        [1]
      ]);
      expect(shortRangesFor([a, b], joinOverlapping: true), [a, b]);
    });

    test('a long video keeps 20 s before and 25 s after, inside the video',
        () {
      expect(markerRange(60000, 600000), (startMs: 40000, endMs: 85000));
      expect(markerRange(5000, 600000), (startMs: 0, endMs: 30000));
      expect(markerRange(598000, 600000), (startMs: 578000, endMs: 600000));
    });

    test('at the very edge the window is made up on the other side', () {
      final first = markerRange(0, 30000);
      expect(first.startMs, 0);
      expect(first.endMs, inInclusiveRange(kMarkerMinMs, 15000));
      final last = markerRange(30000, 30000);
      expect(last.endMs, 30000);
      expect(last.endMs - last.startMs, greaterThanOrEqualTo(kMarkerMinMs));
      // A video shorter than the minimum is taken whole.
      expect(markerRange(2000, 5000), (startMs: 0, endMs: 5000));
      expect(markerRange(100, 0), (startMs: 0, endMs: 0));
    });

    test('markers close together overlap by more than 70 %: one group, one '
        'short covering both, or one each', () {
      const total = 600000;
      final a = markerRange(100000, total);
      final b = markerRange(104000, total);
      final c = markerRange(300000, total);
      expect(spanOverlapShare(a, b), greaterThan(kMarkerOverlapShare));
      expect(overlappingGroups([a, b, c]), [
        [0, 1],
        [2]
      ]);
      expect(shortRangesFor([a, b, c], joinOverlapping: true), [
        (startMs: a.startMs, endMs: b.endMs),
        c,
      ]);
      expect(shortRangesFor([a, b, c], joinOverlapping: false), [a, b, c]);
      // Whatever order the markers are in.
      expect(overlappingGroups([c, b, a]), [
        [2, 1],
        [0]
      ]);
    });
  });

  group('Put back brings the captions back', () {
    test('a text cut: the captions and the title on that part come back '
        'where they were', () {
      final e = ed(talk());
      final before = e.project;
      final plan = planTimelineCut(before, 18000, 26000);
      var n = 0;
      expect(applyTimelineCut(e, plan, newId: () => 'cut${++n}'), 1);
      expect(e.project.durationMs, 52000);
      final cut = e.project.autoCuts.single;
      expect(cut.kind, 'text');
      // c9 (18.0-19.8) .. c12 (24.0-25.8) and the title went with it.
      final gone = [for (final t in cut.titles) t.title.id];
      expect(gone, containsAll(['c9', 'c10', 'c11', 'c12', 'big']));
      expect(e.project.titles.any((t) => t.id == 'c10'), isFalse);
      // Through the project file.
      final again = Project.fromJson(
          jsonDecode(jsonEncode(e.project.toJson())) as Map<String, dynamic>);
      expect(again.autoCuts.single.titles.length, cut.titles.length);
      expect(again.autoCuts.single.titles.first.title.text,
          cut.titles.first.title.text);

      expect(restoreAutoCut(e, cut.id, newId: () => 'r${++n}'),
          isNot(RestoreResult.failed));
      expect(e.project.durationMs, 60000);
      expect(e.project.autoCuts, isEmpty);
      for (final id in ['c9', 'c10', 'c11', 'c12', 'big']) {
        final was = before.titles.firstWhere((t) => t.id == id);
        final now = e.project.titles.where((t) => t.text == was.text).toList();
        expect(now, hasLength(1), reason: '$id is back once');
        expect(now.single.startMs, closeTo(was.startMs, 2), reason: id);
        expect(now.single.endMs, closeTo(was.endMs, 2), reason: id);
        expect(now.single.kind, was.kind);
      }
      // The captions after the cut are where they were, too.
      final late = e.project.titles.firstWhere((t) => t.id == 'c20');
      expect(late.startMs, 40000);
      // One undo step.
      expect(e.history.last.label, 'Put back 1 automatic cut');
      e.undo();
      expect(e.project.durationMs, 52000);
      expect(e.project.titles.any((t) => t.text == 'said c10'), isFalse);
    });

    test('a part cut (1.17 Cut out): the same', () {
      final e = ed(talk());
      final before = e.project;
      final r = e.cutPart(const TimelinePart(30000, 37000));
      expect(r.problem, isNull);
      final cut = e.project.autoCuts.single;
      expect(cut.kind, 'part');
      expect(cut.titles, isNotEmpty);
      expect(e.project.titles.any((t) => t.id == 'c16'), isFalse);
      var n = 0;
      expect(restoreAutoCut(e, cut.id, newId: () => 'r${++n}'),
          isNot(RestoreResult.failed));
      expect(e.project.durationMs, before.durationMs);
      final was = before.titles.firstWhere((t) => t.id == 'c16');
      final now = e.project.titles.singleWhere((t) => t.text == was.text);
      expect(now.startMs, closeTo(was.startMs, 2));
      expect(now.endMs, closeTo(was.endMs, 2));
    });

    test('put back all: every cut brings its own captions', () {
      final e = ed(talk());
      final texts = {for (final t in e.project.titles) t.text};
      var n = 0;
      applyTimelineCut(e, planTimelineCut(e.project, 40000, 46000),
          newId: () => 'cut${++n}');
      applyTimelineCut(e, planTimelineCut(e.project, 10000, 15000),
          newId: () => 'cut${++n}');
      expect(e.project.autoCuts, hasLength(2));
      expect(restoreAllAutoCuts(e, newId: () => 'r${++n}'), 2);
      expect(e.project.durationMs, 60000);
      expect({for (final t in e.project.titles) t.text}, texts);
      expect(e.project.titles.length, texts.length, reason: 'none twice');
    });

    test('what is stored is capped', () {
      final many = Project(
        id: 'p',
        name: 'p',
        createdAt: t0,
        updatedAt: t0,
        clips: [video('a', source: 600000)],
        titles: [
          for (var i = 0; i < 500; i++)
            caption('c$i', i * 1000, i * 1000 + 900),
        ],
      );
      final e = ed(many);
      var n = 0;
      applyTimelineCut(e, planTimelineCut(e.project, 0, 400000),
          newId: () => 'cut${++n}');
      final cut = e.project.autoCuts.single;
      expect(cut.titles.length, kAutoCutTitlesMax);
      // The first ones of the cut are the ones kept.
      expect(cut.titles.first.title.id, 'c0');
      expect(cut.titles.first.offsetMs, 0);
    });

    test('an old project file without the list still loads', () {
      final cut = AutoCut.fromJson({
        'id': 'x',
        'kind': 'text',
        'path': '/m/a.mp4',
        'startMs': 1,
        'endMs': 2,
        'at': '2026-11-01T00:00:00Z',
      });
      expect(cut.titles, isEmpty);
      expect(cut.toJson().containsKey('titles'), isFalse);
      expect(
          AutoCut.fromJson({
            ...cut.toJson(),
            'titles': [
              'nonsense',
              {'offsetMs': 5},
              {
                'offsetMs': 7,
                'title': caption('k', 0, 1000).toJson(),
              },
            ],
          }).titles.single.offsetMs,
          7);
    });
  });

  group('performance log', () {
    test('a ring buffer of stamped lines; spans say how long', () {
      var now = DateTime(2026, 11, 20, 9, 30, 0, 5);
      final log = PerfLog(now: () => now, capacity: 5);
      log.note('first');
      now = now.add(const Duration(milliseconds: 1234));
      final end = log.span('save');
      end();
      end('twice does nothing');
      expect(log.last(), hasLength(3));
      expect(log.last().first, '09:30:00.005 +0 first');
      expect(log.last()[1], '09:30:01.239 +1234 save start');
      expect(log.last()[2], startsWith('09:30:01.239 +1234 save end after '));
      for (var i = 0; i < 10; i++) {
        log.note('n$i');
      }
      expect(log.last(), hasLength(5));
      expect(log.last().last, endsWith('n9'));
      expect(log.last(2).map((l) => l.split(' ').last), ['n8', 'n9']);
    });

    test('gaps: the longest is kept, long ones are noted and told', () {
      final log = PerfLog();
      final told = <int>[];
      log.addGapListener(told.add);
      log.reportGap(40);
      expect(log.longestGapMs, 40);
      expect(log.last(), isEmpty, reason: 'short gaps are not written');
      log.reportGap(2600);
      log.reportGap(120);
      expect(log.longestGapMs, 2600);
      expect(told, [2600]);
      expect(log.last().single, contains('gap 2600 ms'));
      expect(log.shared(), contains('longest gap 2600 ms'));
      log.removeGapListener(told.add);
    });

    test('written on demand, with a header', () async {
      final dir = Directory.systemTemp.createTempSync('clipforge_perf_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = PerfLog();
      expect(await log.write(), isNull, reason: 'no folder yet');
      await log.start(dir: dir.path, watchdog: false);
      addTearDown(log.stop);
      log.note('project opened: 2 clips, 0 sounds, 1565 s');
      final path = await log.write(header: 'ClipForge 1.17.0');
      expect(path, p.join(dir.path, kPerfLogFileName));
      final text = File(path!).readAsStringSync();
      expect(text, startsWith('ClipForge 1.17.0\nlongest gap '));
      expect(text, contains('project opened: 2 clips'));
    });

    test('the watchdog writes the file when the app stops responding, and '
        'the next start shows the end of that run', () async {
      final dir = Directory.systemTemp.createTempSync('clipforge_perf_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = PerfLog();
      await log.start(dir: dir.path);
      log.note('save start');
      log.note('sound picture 1 of 3 (1539 s) start');
      // Let a few heartbeats through, then hold this isolate for 3 s (what
      // a stalled app looks like from outside).
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final file = File(p.join(dir.path, kPerfLogFileName));
      expect(file.existsSync(), isFalse, reason: 'nothing is written while '
          'all is well');
      sleep(const Duration(milliseconds: 3200));
      // Written while this isolate could not do anything.
      expect(file.existsSync(), isTrue);
      final stalled = file.readAsStringSync();
      expect(stalled, contains(kNotRespondingMark));
      expect(stalled, contains('sound picture 1 of 3 (1539 s) start'));
      // What the next start would read (from a copy: the watchdog is
      // about to add that the app answers again).
      final copy = File(p.join(dir.path, 'copy.txt'))
        ..writeAsStringSync(stalled);
      final previous = await readStalledRun(copy.path);
      expect(previous.last, contains(kNotRespondingMark));
      expect(previous.any((l) => l.contains('save start')), isTrue);
      // The app answers again: said so, and the gap is in the log.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(file.readAsStringSync(), contains('responding again'));
      expect(await readStalledRun(file.path), isEmpty,
          reason: 'it recovered: not a run that ended stalled');
      expect(log.longestGapMs, greaterThan(2500));
      expect(log.last().any((l) => l.contains('gap ')), isTrue);
      log.stop();

      // A new start finds a file that ended stalled.
      file.writeAsStringSync(stalled);
      final next = PerfLog();
      await next.start(dir: dir.path, watchdog: false);
      addTearDown(next.stop);
      expect(next.previousRun, isNotEmpty);
      expect(next.shared(), contains('Previous run (ended while not '
          'responding)'));
      expect(next.shared(), contains('sound picture 1 of 3'));
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  group('the lane', () {
    late PerfLog log;
    late FfmpegLane lane;
    setUp(() {
      log = PerfLog();
      lane = FfmpegLane(log: log);
    });

    /// A background job that runs until it is released or pre-empted.
    Future<String> background(String name, List<String> events,
        {Completer<void>? release}) {
      return lane.run(LanePriority.background, name, (run) async {
        events.add('$name start');
        final done = release ?? Completer<void>();
        await Future.any([done.future, run.preempted]);
        events.add(run.isPreempted ? '$name stopped' : '$name end');
        return name;
      });
    }

    test('one at a time; user runs go before background runs', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final first = lane.run(LanePriority.user, 'u1', (_) async {
        events.add('u1 start');
        await gate.future;
        events.add('u1 end');
        return 1;
      });
      final picture = background('picture', events,
          release: Completer<void>()..complete());
      final second = lane.run(LanePriority.user, 'u2', (_) async {
        events.add('u2');
        return 2;
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, ['u1 start'], reason: 'one at a time');
      expect(lane.waiting, 2);
      gate.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(await picture, 'picture');
      expect(events,
          ['u1 start', 'u1 end', 'u2', 'picture start', 'picture end']);
    });

    test('a background run is stopped for a user run and starts again '
        'afterwards; its caller only sees the final result', () async {
      final events = <String>[];
      final release = Completer<void>();
      final picture = background('picture', events, release: release);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['picture start']);
      // The probe of a new file is never in the lane; a frame the user
      // asked for is, and goes first.
      final frame = lane.run(LanePriority.user, 'frame', (_) async {
        events.add('frame');
        return 'frame';
      });
      expect(await frame, 'frame');
      await Future<void>.delayed(Duration.zero);
      expect(events,
          ['picture start', 'picture stopped', 'frame', 'picture start']);
      release.complete();
      expect(await picture, 'picture');
      expect(log.last().any((l) => l.contains('picture put back')), isTrue);
    });

    test('an export makes background runs wait; user runs go on', () async {
      final events = <String>[];
      final release = Completer<void>()..complete();
      lane.exportStarted();
      final picture = background('picture', events, release: release);
      final frame = lane.run(LanePriority.user, 'frame', (_) async {
        events.add('frame');
        return 0;
      });
      await frame;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, ['frame'], reason: 'the picture waits for the export');
      lane.exportEnded();
      expect(await picture, 'picture');
      // An export that starts while a picture is drawn stops it.
      final hold = Completer<void>();
      final other = background('strip', events, release: hold);
      await Future<void>.delayed(Duration.zero);
      lane.exportStarted();
      await Future<void>.delayed(Duration.zero);
      expect(events.last, 'strip stopped');
      lane.exportEnded();
      await Future<void>.delayed(Duration.zero);
      expect(events.last, 'strip start');
      hold.complete();
      expect(await other, 'strip');
    });

    test('a failing run fails for its caller only', () async {
      final bad = lane.run<int>(
          LanePriority.user, 'bad', (_) async => throw StateError('no'));
      final good = lane.run(LanePriority.user, 'good', (_) async => 7);
      await expectLater(bad, throwsStateError);
      expect(await good, 7);
      expect(lane.busy, isFalse);
    });

    test('progress is passed on at most four times a second', () async {
      final seen = <int>[];
      final t = Throttle<int>(seen.add);
      for (var i = 0; i < 1000; i++) {
        t.add(i);
      }
      expect(seen, [0], reason: 'the first at once');
      await Future<void>.delayed(const Duration(milliseconds: 320));
      expect(seen, [0, 999], reason: 'then the latest');
      final watch = Stopwatch()..start();
      var n = 0;
      while (watch.elapsedMilliseconds < 1000) {
        t.add(1000 + n++);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      t.close();
      expect(seen.length, lessThanOrEqualTo(2 + 5),
          reason: 'about four in a second, from $n values');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seen.length, lessThanOrEqualTo(7), reason: 'none after close');
    });
  });

  group('a model file the user has', () {
    late Directory dir;
    late ModelStore store;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('clipforge_models_');
      store = ModelStore(p.join(dir.path, 'models'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> own(String name) async {
      final f = File(p.join(dir.path, name))..writeAsBytesSync([1, 2, 3]);
      store.saveSettings(SpeechSettings(modelPath: f.path));
      return f.path;
    }

    test('an English-only file is used with Automatic and with English, '
        'not with Russian', () async {
      expect(store.choose('auto', SpeechQuality.auto).ready, isFalse);
      final path = await own('ggml-base.en.bin');
      expect(isEnglishOnlyModelFile(path), isTrue);
      for (final language in ['auto', 'en']) {
        final c = store.choose(language, SpeechQuality.auto);
        expect(c.ready, isTrue, reason: language);
        expect(c.installed!.path, path);
        expect(c.installed!.model.englishOnly, isTrue);
      }
      expect(store.choose('ru', SpeechQuality.auto).ready, isFalse);
    });

    test('a file for all languages is used for any language', () async {
      final path = await own('ggml-small.bin');
      expect(isEnglishOnlyModelFile(path), isFalse);
      for (final language in ['auto', 'en', 'ru', 'he']) {
        expect(store.choose(language, SpeechQuality.auto).installed?.path, path,
            reason: language);
      }
    });

    test('forgetting it: nothing to use again', () async {
      await own('ggml-base.en.bin');
      store.saveSettings(const SpeechSettings());
      expect(store.userModel, isNull);
      expect(store.choose('auto', SpeechQuality.auto).ready, isFalse);
    });
  });
}
