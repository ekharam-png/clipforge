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
// Plain `test` (real time, real isolates), not a widget test.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/sound_peaks_job.dart';
import 'package:clipforge/media/speech_gate.dart';
import 'package:clipforge/media/speech_map.dart';
import 'package:clipforge/ui/editor/sound_pictures.dart';
import 'package:clipforge/ui/editor/sound_wave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  test('ExportException import is used', () {
    expect(const SoundPeaksCancelled().toString(), contains('stopped'));
    expect(ExportException('x').message, 'x');
  });
}
