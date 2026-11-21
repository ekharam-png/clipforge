// 1.17, after a real Windows test: a 23-minute project with one video and
// two linked voices stalled while "Drawing sound…" was on screen. Nothing
// about the sound pictures may hold up the app's own (UI) isolate:
//
//  * a slow engine that delivers 40 minutes of samples for one video and
//    two voices must never keep the isolate busy for more than ~50 ms
//    (measured with a timer that should tick every 5 ms), including the
//    reduction to peaks, the speech map with the bleed comparison, the
//    gates and the waveform columns of a view;
//  * the real engine on generated 25-minute files: the same, plus
//    stopping a run in the middle.
//
// Second pass (same version), after a second real Windows test - simply
// IMPORTING one 25-minute video stalled with "Saving…" and "Drawing
// sound…" on screen and the import was not saved:
//
//  * a stand-in for the FFmpegKit plugin that prints 50 000 log lines and
//    reports 50 000 statistics during a long decode must not hold up the
//    isolate, and none of the log lines may be handed over one by one;
//  * importing a long file is saved at once, while its pictures are still
//    waiting;
//  * a probe and a save never wait behind a picture: what the user asked
//    for goes first in the lane, pictures are put back and wait while an
//    export runs;
//  * the safety valve: two seconds without an answer while pictures are
//    drawn pauses them.
//
// Plain `test` (real time, real isolates), not a widget test.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/editor/autosave.dart';
import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/perf_log.dart';
import 'package:clipforge/core/storage/file_project_store.dart';
import 'package:clipforge/media/kit_runner.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_jobs.dart' show SilenceJobEngine;
import 'package:clipforge/media/silence_levels.dart';
import 'package:clipforge/media/sound_peaks_job.dart';
import 'package:clipforge/media/speech_gate.dart';
import 'package:clipforge/media/speech_map.dart';
import 'package:clipforge/ui/editor/sound_pictures.dart';
import 'package:clipforge/ui/editor/sound_wave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../core/helpers.dart' show video;
import '../ui/fakes.dart' show FakeMediaEngine;
import 'support.dart';

/// Ticks every 5 ms and remembers the longest wait between two ticks: how
/// long something kept the isolate to itself.
class Watchdog {
  Watchdog() {
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = _watch.elapsedMicroseconds;
      final gap = now - _last;
      if (gap > worstUs) worstUs = gap;
      _last = now;
      ticks++;
    });
  }
  final Stopwatch _watch = Stopwatch()..start();
  late final Timer _timer;
  int _last = 0;
  int worstUs = 0;
  int ticks = 0;

  double get worstMs => worstUs / 1000;
  void stop() => _timer.cancel();
}

/// Speech-like 16-bit samples at 8 kHz: bursts of talk and pauses.
Uint8List talkSamples(int seconds, int seed, {double level = 0.3}) {
  final r = math.Random(seed);
  final out = Int16List(seconds * 8000);
  var i = 0;
  var talking = false;
  while (i < out.length) {
    final len = ((talking ? 0.6 + r.nextDouble() * 3 : 0.3 + r.nextDouble() * 2) * 8000).round();
    final amp = (talking ? level : level / 30) * 32767;
    for (var k = 0; k < len && i < out.length; k++, i++) {
      out[i] = ((r.nextDouble() * 2 - 1) * amp).round();
    }
    talking = !talking;
  }
  return out.buffer.asUint8List();
}

/// An engine that "decodes" slowly: the samples of each file arrive in
/// small pieces over a while (as ffmpeg writes them), then they are
/// reduced exactly as the real engines do it.
class SlowEngine extends FakeMediaEngine implements CancellableSoundPeaksEngine {
  SlowEngine(this.dir, this.seconds);
  final Directory dir;
  final int seconds;
  final List<String> asked = [];
  int cancelled = 0;

  @override
  Future<SoundPeaks?> soundPeaks(String path,
          {int audioTrack = 0, String? cacheDir}) =>
      soundPeaksCancellable(path,
          audioTrack: audioTrack,
          cacheDir: cacheDir,
          cancel: Completer<void>().future);

  @override
  Future<SoundPeaks?> soundPeaksCancellable(String path,
      {int audioTrack = 0, String? cacheDir, required Future<void> cancel}) async {
    asked.add(path);
    var stop = false;
    unawaited(cancel.then((_) => stop = true));
    final raw = File(p.join(dir.path, '${asked.length}.raw'));
    final sink = raw.openWrite();
    // The other "process": the samples are made on another isolate and
    // handed over in pieces of a minute.
    for (var done = 0; done < seconds; done += 60) {
      if (stop) {
        await sink.close();
        cancelled++;
        throw const SoundPeaksCancelled();
      }
      final n = math.min(60, seconds - done);
      final seed = path.hashCode + done;
      sink.add(await _samples(n, seed));
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    await sink.close();
    final peaks = await reduceRawSound(raw.path);
    await raw.delete();
    return peaks;
  }

  static Future<Uint8List> _samples(int seconds, int seed) =>
      Isolate.run(() => talkSamples(seconds, seed));
}


/// The FFmpegKit plugin as it behaves on a real PC, without the plugin:
/// every run "prints" [logLines] lines and reports [statistics] positions
/// in bursts while it runs for [runFor]. Lines are handed to Dart one by
/// one ONLY while the log messages are on (as the plugin does through the
/// platform thread); they are always kept with the session.
class FloodPlatform implements KitPlatform {
  FloodPlatform(
      {this.logLines = 50000,
      this.statistics = 50000,
      this.runFor = const Duration(milliseconds: 1500)});
  final int logLines;
  final int statistics;
  final Duration runFor;
  bool quietAsked = false;

  /// Log lines that travelled to Dart one at a time (must stay 0).
  int linesDelivered = 0;
  int logFetches = 0;
  final List<List<String>> started = [];
  final List<FloodSession> sessions = [];

  /// Runs with these arguments never end by themselves (a long decode).
  bool Function(List<String> args) endless = (_) => false;

  /// Sessions that ignore being cancelled (never end).
  bool deaf = false;

  /// Runs with these arguments end with an error.
  bool Function(List<String> args) fails = (_) => false;

  @override
  Future<void> quiet() async => quietAsked = true;

  @override
  Future<KitSession> start(List<String> args,
      {void Function(int timeMs)? onStatistics}) async {
    started.add(args);
    final s = FloodSession(this, args, onStatistics);
    sessions.add(s);
    return s;
  }
}

class FloodSession implements KitSession {
  FloodSession(this.platform, this.args, this.onStatistics) {
    const bursts = 100;
    final every = platform.runFor ~/ bursts;
    var n = 0;
    _timer = Timer.periodic(every, (t) {
      n++;
      // As the plugin does it: a burst of callbacks in one go.
      for (var i = 0; i < platform.statistics ~/ bursts; i++) {
        onStatistics?.call(n * 15000 + i);
      }
      for (var i = 0; i < platform.logLines ~/ bursts; i++) {
        printed++;
        if (!platform.quietAsked) platform.linesDelivered++;
      }
      if (n >= bursts && !platform.endless(args)) _end(!platform.fails(args));
    });
  }
  final FloodPlatform platform;
  final List<String> args;
  final void Function(int timeMs)? onStatistics;
  late final Timer _timer;
  final Completer<bool> _done = Completer<bool>();
  int printed = 0;
  bool cancelled = false;

  void _end(bool ok) {
    _timer.cancel();
    if (!_done.isCompleted) _done.complete(ok);
  }

  @override
  Future<bool> get finished => _done.future;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!platform.deaf) _end(false);
  }

  @override
  Future<String> log(int waitMs) async {
    platform.logFetches++;
    expect(waitMs, lessThanOrEqualTo(kKitLogWaitMs),
        reason: 'never the five-second wait on the platform thread');
    return 'size=N/A time=00:00:01\n' * 50;
  }
}

/// The engine as the FFmpegKit one is put together: the sound decode is
/// a BACKGROUND run of the lane, a probe is not in the lane at all.
class LaneEngine extends FakeMediaEngine implements CancellableSoundPeaksEngine {
  LaneEngine(this.runner);
  final KitRunner runner;

  @override
  Future<MediaInfo> probe(String path) async {
    probes++;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    return const MediaInfo(
        durationMs: 1539000,
        width: 1280,
        height: 720,
        hasVideo: true,
        hasAudio: true);
  }

  @override
  Future<SoundPeaks?> soundPeaks(String path,
          {int audioTrack = 0, String? cacheDir}) =>
      soundPeaksCancellable(path,
          audioTrack: audioTrack,
          cacheDir: cacheDir,
          cancel: Completer<void>().future);

  @override
  Future<SoundPeaks?> soundPeaksCancellable(String path,
      {int audioTrack = 0, String? cacheDir, required Future<void> cancel}) async {
    var stopped = false;
    unawaited(cancel.then((_) => stopped = true));
    final r = await runner.background(
        ['-threads', '1', '-i', path, '-f', 's16le', 'sound.raw'],
        cancel: cancel);
    if (stopped) throw const SoundPeaksCancelled();
    if (!r.ok) throw ExportException('Cannot read the sound');
    return (PeaksBuilder()..add(talkSamples(2, 1))).finish();
  }
}

Clip longClip(String path) => Clip(
    id: 'long',
    type: ClipType.video,
    path: path,
    sourceDurationMs: 1539000,
    inMs: 0,
    outMs: 1539000,
    width: 1280,
    height: 720);

Project zoomProject(int ms, String video, String a, String b) {
  var n = 0;
  final e = ProjectEditor(
      Project(
        id: 'long',
        name: 'Long talk',
        createdAt: t0,
        updatedAt: t0,
        clips: [
          Clip(
              id: 'v',
              type: ClipType.video,
              path: video,
              sourceDurationMs: ms,
              inMs: 0,
              outMs: ms,
              width: 1280,
              height: 720),
        ],
      ),
      newId: () => 'id${n++}');
  for (final (path, name) in [(a, 'Sam'), (b, 'Dana')]) {
    e.addVoice(
        AudioClip(
            id: 'x',
            path: path,
            sourceDurationMs: ms,
            startMs: 0,
            inMs: 0,
            outMs: ms),
        clipId: 'v',
        offsetMs: 0,
        trackName: name);
  }
  for (final t in e.project.soundTracks) {
    e.setOnlyWhenSpeaking(t.id, on: true);
  }
  return e.project;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('clipforge_resp_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a slow 40-minute decode never holds the isolate for 50 ms', () async {
    const minutes = 40;
    final engine = SlowEngine(dir, minutes * 60);
    final project =
        zoomProject(minutes * 60000, '/m/zoom.mp4', '/m/sam.m4a', '/m/dana.m4a');
    var playing = false;
    final pictures = SoundPictures(
      engine: engine,
      cacheDir: () async => null,
      playing: () => playing,
      startDelay: const Duration(milliseconds: 60),
    );
    addTearDown(pictures.dispose);
    final seen = <String>[];
    pictures.addListener(() {
      if (pictures.busy) {
        seen.add('${pictures.doneCount + 1} of ${pictures.totalCount}');
      }
    });
    // The test runs unoptimised code that is compiled when first used:
    // use the maths once on a short sound, so that what is measured is
    // the work and not the compiler.
    final warm = PeaksBuilder()..add(talkSamples(30, 1));
    final small = warm.finish();
    groupSpeechStretches(
        [(peaks: small, offsetMs: 0), (peaks: small, offsetMs: 40)]);
    waveColumns(small,
        inMs: 0, outMs: 30000, speed: 1, pxPerMs: 0.06, fromX: 0, toX: 900,
        stretches: speechStretches(small));
    await reduceRawSound((File(p.join(dir.path, 'warm.raw'))
          ..writeAsBytesSync(talkSamples(5, 2)))
        .path);
    final dog = Watchdog();
    addTearDown(dog.stop);
    pictures.update(project);
    // A long project: the players first. Nothing is asked for at once,
    // and nothing while the video plays.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(engine.asked, isEmpty, reason: 'the preview comes first');
    playing = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(engine.asked, isEmpty, reason: 'not while the video plays');
    playing = false;

    final clock = Stopwatch()..start();
    while (pictures.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // What the timeline does on every frame while pictures arrive:
      // who speaks, the gates, and the bars of a screenful.
      final speakers = pictures.speakers;
      speechEdges(speakers);
      projectGates(project, pictures.peaksFor, pictures.speechCache);
      for (final a in project.audio) {
        final peaks = pictures.peaksOf(a.path, 0);
        if (peaks == null) continue;
        waveColumns(peaks,
            inMs: a.inMs,
            outMs: a.outMs,
            speed: 1,
            pxPerMs: 0.06,
            fromX: 40000,
            toX: 43000,
            stretches: pictures.speechOf(a));
      }
      expect(clock.elapsed, lessThan(const Duration(minutes: 2)));
    }
    dog.stop();
    expect(engine.asked, hasLength(3), reason: 'one at a time, all three');
    expect(seen, containsAll(['1 of 3', '2 of 3', '3 of 3']));
    final speakers = pictures.speakers;
    expect(speakers.map((t) => t.name), ['Sam', 'Dana']);
    expect(speakers.first.stretches.length, greaterThan(100));
    expect(projectGates(project, pictures.peaksFor), hasLength(2));
    // ignore: avoid_print
    print('40 min x 3 files: longest wait of the isolate ${dog.worstMs} ms '
        'over ${dog.ticks} ticks, ${clock.elapsedMilliseconds} ms in all');
    expect(dog.ticks, greaterThan(50));
    expect(dog.worstMs, lessThan(50),
        reason: 'the UI isolate was held up for ${dog.worstMs} ms');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the ✕ and "Show sound waves" off stop a running computation',
      () async {
    final engine = SlowEngine(dir, 40 * 60);
    final project = zoomProject(40 * 60000, '/m/z.mp4', '/m/s.m4a', '/m/d.m4a')
        .copyWith(tracks: [
      // No gate here: with one, the pictures are needed whatever the
      // setting says.
      const SoundTrack(id: 'a', name: 'Sam', speech: true),
    ]);
    final pictures = SoundPictures(
        engine: engine, cacheDir: () async => null, startDelay: Duration.zero);
    addTearDown(pictures.dispose);
    pictures.update(project);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(pictures.busy, isTrue);
    expect(engine.asked, hasLength(1));
    pictures.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(pictures.busy, isFalse);
    expect(engine.cancelled, 1);
    expect(engine.asked, hasLength(1), reason: 'the queue was emptied');
    // Asked for again.
    pictures.resume();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(pictures.busy, isTrue);
    // The setting off: the run is stopped, nothing more starts.
    pictures.enabled = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(pictures.busy, isFalse);
    expect(engine.cancelled, 2);
  });

  group('the real engine, 25-minute files', () {
    if (!ffmpegOk) {
      test('needs ffmpeg + ffprobe', () {}, skip: 'ffmpeg/ffprobe not found');
      return;
    }
    setUpAll(() {
      setUpMedia();
      // 25 minutes: a small video with sound, and two voice files with
      // bursts of talk (noise switched on and off).
      ff([
        '-f', 'lavfi', '-i', 'color=c=gray:s=160x90:r=5:d=1500',
        '-f', 'lavfi', '-i',
        "anoisesrc=d=1500:c=pink:r=16000:a=0.2,volume='0.02+0.98*lt(mod(t,7),3)':eval=frame",
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-g', '50', '-c:a', 'aac', '-b:a', '32k', '-shortest', f('long.mp4'),
      ]);
      for (final (name, on) in [('sam', 'lt(mod(t,9),4)'), ('dana', 'gte(mod(t,9),5)')]) {
        ff([
          '-f', 'lavfi', '-i',
          "anoisesrc=d=1500:c=pink:r=16000:a=0.2,volume='0.02+0.98*$on':eval=frame",
          '-c:a', 'aac', '-b:a', '32k', f('$name.m4a'),
        ]);
      }
    });
    tearDownAll(tearDownMedia);

    test('pictures are read while the isolate stays responsive', () async {
      final project = zoomProject(1500000, f('long.mp4'), f('sam.m4a'), f('dana.m4a'));
      final pictures = SoundPictures(
          engine: engine,
          cacheDir: () async => f('peaks'),
          startDelay: const Duration(milliseconds: 20));
      addTearDown(pictures.dispose);
      final dog = Watchdog();
      addTearDown(dog.stop);
      final clock = Stopwatch()..start();
      pictures.update(project);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      while (pictures.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        pictures.speakers;
        projectGates(project, pictures.peaksFor, pictures.speechCache);
      }
      dog.stop();
      // ignore: avoid_print
      print('25 min x 3 real files: ${clock.elapsedMilliseconds} ms, longest '
          'wait of the isolate ${dog.worstMs} ms over ${dog.ticks} ticks');
      for (final file in ['long.mp4', 'sam.m4a', 'dana.m4a']) {
        final peaks = pictures.peaksOf(f(file), 0);
        expect(peaks, isNotNull, reason: file);
        expect(peaks!.length * peaks.hopMs, closeTo(1500000, 3000));
      }
      final speakers = pictures.speakers;
      expect(speakers, hasLength(2));
      // Sam talks 4 s of every 9: about 166 turns of talk.
      expect(speakers.first.stretches.length, inInclusiveRange(150, 180));
      expect(dog.worstMs, lessThan(100),
          reason: 'the UI isolate was held up for ${dog.worstMs} ms');
      // Kept on disk: the second time nothing is decoded.
      final again = Stopwatch()..start();
      expect(await engine.soundPeaks(f('sam.m4a'), cacheDir: f('peaks')),
          isNotNull);
      expect(again.elapsedMilliseconds, lessThan(1000));
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('a run can be stopped in the middle', () async {
      final cancel = Completer<void>();
      final started = Stopwatch()..start();
      final run = engine.soundPeaksCancellable(f('long.mp4'),
          cacheDir: f('peaks2'), cancel: cancel.future);
      Object? error;
      unawaited(run.then<void>((_) {}, onError: (Object e) => error = e));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      cancel.complete();
      await run.then<void>((_) {}, onError: (_) {});
      expect(error, isA<SoundPeaksCancelled>());
      expect(started.elapsedMilliseconds, lessThan(3000));
      expect(Directory(f('peaks2')).existsSync() &&
          Directory(f('peaks2')).listSync().isNotEmpty, isFalse,
          reason: 'nothing half-made is kept');
    });
  });


  group('FFmpeg inside the app (a stand-in for the plugin)', () {
    test('50 000 log lines and 50 000 statistics during a long decode do '
        'not hold up the isolate; no line is handed over one by one',
        () async {
      final platform = FloodPlatform();
      final log = PerfLog();
      final runner = KitRunner(platform, log: log);
      final dog = Watchdog();
      addTearDown(dog.stop);
      final positions = <int>[];
      final clock = Stopwatch()..start();
      // A sound picture (background, no progress wanted) ...
      final picture = runner.background(
          ['-threads', '1', '-i', 'long.mp4', '-f', 's16le', 'sound.raw']);
      // ... and afterwards Remove silences with its progress bar.
      final scan = runner.streaming(
          buildLevelScanCommand(path: 'long.mp4', outputFile: 'levels.txt'),
          positions.add,
          Completer<void>().future);
      final results = await Future.wait([picture, scan]);
      dog.stop();
      final seconds = clock.elapsedMilliseconds / 1000;
      // ignore: avoid_print
      print('2 runs, 100 000 log lines and 100 000 statistics in '
          '${clock.elapsedMilliseconds} ms: longest wait of the isolate '
          '${dog.worstMs} ms, ${positions.length} progress updates');
      expect(results.every((r) => r.ok), isTrue);
      expect(platform.quietAsked, isTrue);
      expect(platform.linesDelivered, 0,
          reason: 'the log messages were switched off before the first run');
      // (The scan is what the user waits for: the picture was put back
      // for it and read again afterwards.)
      expect(platform.sessions.first.cancelled, isTrue);
      expect(
          platform.sessions.where((s) => !s.cancelled).map((s) => s.printed),
          [50000, 50000]);
      expect(platform.logFetches, 0,
          reason: 'the log of a run that went well is never fetched');
      for (final args in platform.started) {
        expect(args.first, '-hide_banner');
        final level = args.indexOf('-loglevel');
        expect(args[level + 1], 'error');
      }
      expect(platform.started.first, contains('-nostats'));
      // The level scan writes to a file, not to the log.
      expect(
          platform.started
              .any((args) => args.any((a) => a.contains(':file=levels.txt'))),
          isTrue);
      // Progress: at most four a second (and it did move).
      expect(positions, isNotEmpty);
      expect(positions.length, lessThanOrEqualTo((seconds * 4).ceil() + 2));
      expect(dog.worstMs, lessThan(60),
          reason: 'the isolate was held up for ${dog.worstMs} ms');
      final noted = log.last().join('\n');
      expect(noted, contains('lane: sound decode start'));
      expect(noted, contains('lane: sound decode put back'));
      expect(noted, contains('lane: sound decode end after'));
      expect(noted, contains('lane: level scan end after'));
    });

    test('a run that fails: its log is fetched once, with a short wait; '
        'not when it was stopped on purpose', () async {
      final platform = FloodPlatform(
          runFor: const Duration(milliseconds: 100), logLines: 200, statistics: 0);
      platform.fails = (args) => args.contains('broken.mp4');
      platform.endless = (args) => args.contains('long.mp4');
      final runner = KitRunner(platform, log: PerfLog());
      final bad = await runner.user(['-i', 'broken.mp4', 'out.wav']);
      expect(bad.ok, isFalse);
      expect(bad.log, isNotEmpty);
      expect(platform.logFetches, 1);
      final stop = Completer<void>();
      final run =
          runner.streaming(['-i', 'long.mp4', 'out.wav'], (_) {}, stop.future);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      stop.complete();
      final r = await run;
      expect(r.ok, isFalse);
      expect(platform.sessions.last.cancelled, isTrue);
      expect(platform.logFetches, 1, reason: 'stopped: no log is asked for');
      // What prints its result (the encoder list) is fetched too.
      final quick = FloodPlatform(
          runFor: const Duration(milliseconds: 100), logLines: 200, statistics: 0);
      final list =
          await KitRunner(quick, log: PerfLog()).session(const ['-encoders']);
      expect(quick.logFetches, 1);
      expect(list.ok, isTrue);
      expect(list.log, isNotEmpty);
      expect(KitRunner.wantsLog(const ['-loglevel', 'info', '-i', 'a']), isTrue);
      expect(KitRunner.wantsLog(const ['-loglevel', 'error', '-i', 'a']), isFalse);
      expect(KitRunner.args(const ['-i', 'a'], progress: true),
          ['-hide_banner', '-loglevel', 'error', '-i', 'a']);
    });

    test('a session that does not end when it is stopped does not hold '
        'the lane for ever', () async {
      final platform = FloodPlatform(logLines: 0, statistics: 0);
      platform.endless = (args) => args.contains('s16le');
      platform.deaf = true;
      final log = PerfLog();
      final runner = KitRunner(platform,
          log: log, stopGrace: const Duration(milliseconds: 150));
      final cancel = Completer<void>();
      final picture = runner.background(
          ['-i', 'long.mp4', '-f', 's16le', 'sound.raw'],
          cancel: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancel.complete();
      expect((await picture).ok, isFalse, reason: 'the caller is let go');
      // The lane is free again after the grace time: the next run goes.
      platform.deaf = false;
      final watch = Stopwatch()..start();
      final frame = await runner.user(['-i', 'a.mp4', 'frame.jpg']);
      expect(frame.ok, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(3000));
      expect(log.last().any((l) => l.contains('did not end within 150 ms')),
          isTrue);
      platform.sessions.first._end(false);
    });

    test('a probe and a save do not wait behind a picture; what the user '
        'asks for goes first and the picture starts again', () async {
      final platform = FloodPlatform(logLines: 0, statistics: 0)
        ..endless = (args) => args.contains('s16le');
      final log = PerfLog();
      final runner = KitRunner(platform, log: log);
      final engine = LaneEngine(runner);
      final store = FileProjectStore(p.join(dir.path, 'projects'));
      final created = await store.create('Talk');
      final controller = EditorController(created);
      final saver = Autosaver(controller, store);
      addTearDown(saver.dispose);
      final pictures = SoundPictures(
          engine: engine, cacheDir: () async => null, startDelay: Duration.zero);
      addTearDown(pictures.dispose);
      controller.addListener(() => pictures.update(controller.project));

      // A long file is already in the project and its picture is being
      // read (a decode that does not end by itself).
      controller.addClip(longClip('/m/first.mp4'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(pictures.busy, isTrue);
      expect(runner.lane.busy, isTrue);
      expect(platform.sessions, hasLength(1));

      // 1. The probe of a newly added file answers at once.
      final watch = Stopwatch()..start();
      final info = await engine.probe('/m/second.mp4');
      expect(watch.elapsedMilliseconds, lessThan(300));
      expect(info.durationMs, 1539000);
      expect(platform.sessions.single.cancelled, isFalse,
          reason: 'a probe is not in the lane: the picture runs on');

      // 2. The save of the import does not wait for the picture either.
      watch.reset();
      controller.addClip(longClip('/m/second.mp4').copyWith(id: 'second'));
      while (saver.isSaving || saver.hasPendingChanges) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(watch.elapsedMilliseconds, lessThan(2000));
      }
      expect(watch.elapsedMilliseconds, lessThan(700),
          reason: 'saved at once, not after the quiet time');
      expect(saver.lastError, isNull);
      expect((await store.load(created.id)).clips.map((c) => c.id),
          ['long', 'second']);
      expect(pictures.busy, isTrue, reason: 'pictures are still pending');

      // 3. Something the user asked for (a frame): the picture is put
      // back, the frame is made, the picture starts again.
      watch.reset();
      final frame = await runner.user(['-i', '/m/first.mp4', 'frame.jpg']);
      expect(frame.ok, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(2500));
      expect(platform.sessions.first.cancelled, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.started.where((a) => a.contains('s16le')).length, 2,
          reason: 'the picture started again');
      expect(pictures.busy, isTrue);
      expect(log.last().any((l) => l.contains('put back')), isTrue);

      // 4. An export: the picture waits until it is over.
      runner.lane.exportStarted();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runner.lane.busy, isFalse);
      expect(pictures.busy, isTrue);
      runner.lane.exportEnded();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(runner.lane.busy, isTrue);

      // The performance log has the saves, without a file name.
      final lines = PerfLog.instance.last(200).join('\n');
      expect(lines, contains('save: a file was added, saving at once'));
      expect(lines, contains('sound picture 1 of'));
      expect(lines, isNot(contains('first.mp4')));
      expect(lines, isNot(contains('second.mp4')));
      pictures.stop();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(pictures.busy, isFalse);
    });

    test('importing a long file reaches "Saved" while its pictures are '
        'still waiting', () async {
      // An engine whose decode takes "forever" (as on the PC that stalled).
      final platform = FloodPlatform(logLines: 0, statistics: 0)
        ..endless = (_) => true;
      final engine = LaneEngine(KitRunner(platform, log: PerfLog()));
      final store = FileProjectStore(p.join(dir.path, 'projects'));
      final created = await store.create('Import');
      final controller = EditorController(created);
      final saver = Autosaver(controller, store);
      addTearDown(saver.dispose);
      final pictures = SoundPictures(
          engine: engine, cacheDir: () async => null);
      addTearDown(pictures.dispose);
      controller.addListener(() => pictures.update(controller.project));
      // What the editor's save indicator shows.
      String status() => saver.lastError != null
          ? 'Not saved'
          : (saver.isSaving || saver.hasPendingChanges ? 'Saving…' : 'Saved');

      controller.addClip(video('short', source: 28000));
      await saver.flush();
      expect(status(), 'Saved');

      // The import: probe, then the clip is on the timeline.
      final info = await engine.probe('/m/meeting.mp4');
      final watch = Stopwatch()..start();
      expect(info.durationMs, 1539000);
      controller.addClip(longClip('/m/meeting.mp4'));
      expect(status(), 'Saving…');
      while (status() != 'Saved') {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(watch.elapsedMilliseconds, lessThan(2000),
            reason: 'the save hangs');
      }
      // ignore: avoid_print
      print('import saved after ${watch.elapsedMilliseconds} ms; pictures '
          'busy: ${pictures.busy}');
      expect(watch.elapsedMilliseconds, lessThan(700));
      expect(pictures.busy, isTrue, reason: 'pictures are still pending');
      // After a restart the import is there.
      final again = await FileProjectStore(p.join(dir.path, 'projects'))
          .load(created.id);
      expect(again.clips.map((c) => c.id), ['short', 'long']);
      expect(again.durationMs, 28000 + 1539000);
    });

    test('the safety valve: no answer for two seconds while pictures are '
        'drawn pauses them; "Turn back on" resumes', () async {
      final platform = FloodPlatform(logLines: 0, statistics: 0)
        ..endless = (_) => true;
      final engine = LaneEngine(KitRunner(platform, log: PerfLog()));
      final pictures = SoundPictures(
          engine: engine, cacheDir: () async => null, startDelay: Duration.zero);
      addTearDown(pictures.dispose);
      // Nothing in work: a gap pauses nothing.
      pictures.pauseForResponsiveness(5000);
      expect(pictures.pausedForApp, isFalse);
      final project =
          zoomProject(1500000, '/m/z.mp4', '/m/s.m4a', '/m/d.m4a');
      pictures.update(project);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(pictures.busy, isTrue);
      pictures.pauseForResponsiveness(2400);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(pictures.pausedForApp, isTrue);
      expect(pictures.busy, isFalse);
      expect(pictures.enabled, isTrue, reason: 'the setting is unchanged');
      expect(platform.sessions.single.cancelled, isTrue);
      expect(
          PerfLog.instance.last().any((l) => l.contains('sound pictures '
              'paused: the app did not respond for 2400 ms')),
          isTrue);
      // An edit does not start them again by itself.
      pictures.update(project.copyWith(name: 'x'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(pictures.busy, isFalse);
      pictures.resume();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(pictures.pausedForApp, isFalse);
      expect(pictures.busy, isTrue);
      expect(platform.sessions, hasLength(2));
    });
  });

  group('the level scan through a file (real ffmpeg)', () {
    if (!ffmpegOk) {
      test('needs ffmpeg + ffprobe', () {}, skip: 'ffmpeg/ffprobe not found');
      return;
    }
    setUpAll(() {
      setUpMedia();
      // 5 minutes: talk for 3 s of every 7.
      ff([
        '-f', 'lavfi', '-i',
        "anoisesrc=d=300:c=pink:r=16000:a=0.2,volume='0.02+0.98*lt(mod(t,7),3)':eval=frame",
        '-c:a', 'aac', '-b:a', '32k', f('five.m4a'),
      ]);
    });
    tearDownAll(tearDownMedia);

    test('Remove silences reads the levels from a file, on another '
        'isolate, and finds the pauses', () async {
      final dog = Watchdog();
      addTearDown(dog.stop);
      final job = (engine as SilenceJobEngine).startSilenceDetection(
          f('five.m4a'));
      final silences = await job.result;
      dog.stop();
      // 300 s / 7 s: 42 or 43 pauses of about 4 s.
      expect(silences.length, inInclusiveRange(40, 44));
      for (final s in silences.skip(1).take(10)) {
        expect(s.endMs - s.startMs, closeTo(4000, 200));
      }
      expect(job.levels!.levels.length, closeTo(300000 / kLevelWindowMs, 20));
      expect(dog.worstMs, lessThan(100),
          reason: 'the UI isolate was held up for ${dog.worstMs} ms');
      // The one-shot call finds the same.
      final again = await engine.detectSilence(f('five.m4a'));
      expect(again.length, silences.length);
      // Nothing is left in the temp folder.
      expect(
          Directory.systemTemp
              .listSync()
              .where((e) => p.basename(e.path).startsWith('clipforge_levels_')),
          isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('ExportException import is used', () {
    expect(const SoundPeaksCancelled().toString(), contains('stopped'));
    expect(ExportException('x').message, 'x');
  });
}
