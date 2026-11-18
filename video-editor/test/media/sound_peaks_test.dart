// 1.13: the sound picture of a file (peaks for the waveform, levels for
// who is speaking), its cache on disk, speech stretches with two
// microphones that hear each other, and the map onto the timeline through
// trim, speed, the linked-voice offset and cuts.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/editor/snapping.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_common.dart';
import 'package:clipforge/media/sound_peaks_job.dart';
import 'package:clipforge/media/speech_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 16-bit mono at 8 kHz: a 220 Hz tone at [amp] (0..1) for the stretches
/// in [loud] (ms), a faint hiss elsewhere.
Uint8List pcm(int ms, List<(int, int)> loud, {double amp = 0.4, double hiss = 0.002}) {
  final n = ms * 8;
  final out = ByteData(n * 2);
  final rnd = math.Random(7);
  for (var i = 0; i < n; i++) {
    final t = i ~/ 8;
    final on = loud.any((r) => t >= r.$1 && t < r.$2);
    final v = on
        ? amp * math.sin(2 * math.pi * 220 * i / 8000)
        : hiss * (rnd.nextDouble() * 2 - 1);
    out.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Levels (dB) per 20 ms hop: [base] with the stretches of [parts] (ms)
/// at their own level.
SoundPeaks levels(int ms, double base, List<(int, int, double)> parts) {
  final db = List<double>.filled(ms ~/ kPeakHopMs, base);
  for (final (a, b, v) in parts) {
    for (var i = a ~/ kPeakHopMs; i < b ~/ kPeakHopMs && i < db.length; i++) {
      db[i] = v;
    }
  }
  return SoundPeaks.fromLevels(db);
}

AudioClip voice(String id, String path, String track,
        {int start = 0, int inMs = 0, int outMs = 60000, int offset = 0,
        String clip = 'a', double speed = 1}) =>
    AudioClip(
      id: id,
      path: path,
      sourceDurationMs: 600000,
      startMs: start,
      inMs: inMs,
      outMs: outMs,
      trackId: track,
      sourceClipId: clip,
      syncOffsetMs: offset,
      linked: true,
      speed: speed,
    );

Clip clip(String id, int inMs, int outMs, {double speed = 1, bool muted = true}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: '/m/zoom.mp4',
      sourceDurationMs: 600000,
      inMs: inMs,
      outMs: outMs,
      width: 1920,
      height: 1080,
      speed: speed,
      muted: muted,
    );

Project twoVoices({List<Clip>? clips, List<AudioClip>? audio}) => Project(
      id: 'p',
      name: 'Talk',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      clips: clips ?? [clip('a', 0, 60000)],
      tracks: const [
        SoundTrack(id: 'sam', name: 'Sam', speech: true),
        SoundTrack(id: 'dana', name: 'Dana', speech: true),
        SoundTrack(id: kMusicTrackId, name: 'Music'),
      ],
      audio: audio ??
          [
            voice('v1', '/m/sam.m4a', 'sam'),
            voice('v2', '/m/dana.m4a', 'dana'),
          ],
    );

void main() {
  group('peaks', () {
    test('from samples: loud where the tone is, level in dB', () {
      final peaks = SoundPeaks.fromPcm16(pcm(2000, [(500, 1000)]));
      expect(peaks.length, 100);
      expect(peaks.durationMs, 2000);
      expect(peaks.peakBetween(0, 400), lessThan(0.08));
      // sqrt(0.4) = 0.63
      expect(peaks.peakBetween(600, 900), closeTo(0.63, 0.02));
      expect(peaks.peakBetween(400, 620), closeTo(0.63, 0.02));
      // RMS of a sine of 0.4 = 0.283 = -11 dB.
      expect(SoundPeaks.dbOf(peaks.levels[35]), closeTo(-11, 0.5));
      expect(SoundPeaks.dbOf(peaks.levels[5]), lessThan(-55));
      expect(peaks.peakBetween(5000, 6000), 0);
      expect(peaks.peakBetween(-100, 0), lessThan(0.08));
    });

    test('samples arriving in odd pieces give the same picture', () {
      final bytes = pcm(1500, [(200, 700), (900, 1100)]);
      final whole = SoundPeaks.fromPcm16(bytes);
      final b = PeaksBuilder();
      for (var i = 0; i < bytes.length; i += 333) {
        b.add(bytes.sublist(i, math.min(bytes.length, i + 333)));
      }
      final pieces = b.finish();
      expect(pieces.peaks, whole.peaks);
      expect(pieces.levels, whole.levels);
    });

    test('the file format round-trips; anything else is refused', () {
      final peaks = SoundPeaks.fromPcm16(pcm(1000, [(100, 300)]));
      final back = SoundPeaks.fromBytes(peaks.toBytes())!;
      expect(back.peaks, peaks.peaks);
      expect(back.levels, peaks.levels);
      expect(back.hopMs, kPeakHopMs);
      expect(SoundPeaks.fromBytes(Uint8List(4)), isNull);
      expect(SoundPeaks.fromBytes(Uint8List.fromList(List.filled(40, 1))), isNull);
      final cut = peaks.toBytes().sublist(0, 30);
      expect(SoundPeaks.fromBytes(cut), isNull);
    });

    test('40 minutes: read in well under a few seconds, 240 KB', () {
      // One second of sound, fed 2400 times (what reading the decoded
      // file in pieces does).
      final second = pcm(1000, [(0, 600)]);
      final watch = Stopwatch()..start();
      final b = PeaksBuilder();
      for (var i = 0; i < 2400; i++) {
        b.add(second);
      }
      final peaks = b.finish();
      final built = watch.elapsedMilliseconds;
      watch.reset();
      final stretches = speechStretches(peaks);
      final found = watch.elapsedMilliseconds;
      expect(peaks.length, 120000);
      expect(peaks.toBytes().length, lessThan(250 * 1024));
      expect(stretches.length, 2400);
      expect(built, lessThan(4000), reason: 'building took $built ms');
      expect(found, lessThan(300), reason: 'stretches took $found ms');
    });
  });

  group('the cache on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cf_peaks_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('decoded once per file, then read from the folder', () async {
      final media = File(p.join(dir.path, 'talk.m4a'))
        ..writeAsBytesSync(List.filled(4000, 7));
      final cache = p.join(dir.path, 'peaks');
      var runs = 0;
      Future<FfmpegRun> run(List<String> args) async {
        runs++;
        expect(args, containsAllInOrder(['-i', media.path]));
        expect(args, contains(runs == 1 ? '0:a:1' : '0:a:0'));
        File(args.last).writeAsBytesSync(pcm(3000, [(1000, 2000)]));
        return const FfmpegRun(true, '');
      }

      Future<MediaInfo> probe(String path) async => const MediaInfo(
          durationMs: 3000, width: 0, height: 0, hasVideo: false, hasAudio: true,
          audioStreams: [2, 2]);

      final first = await soundPeaksWith(run, probe, media.path,
          audioTrack: 1, cacheDir: cache);
      expect(first!.durationMs, 3000);
      expect(runs, 1);
      final files = Directory(cache).listSync().map((e) => p.basename(e.path)).toList();
      expect(files, hasLength(1));
      expect(isSoundPeaksFileName(files.single), isTrue);
      expect(files.single, endsWith('_a1.cfpk'));
      final again = await soundPeaksWith(run, probe, media.path,
          audioTrack: 1, cacheDir: cache);
      expect(runs, 1, reason: 'the second time costs no decode');
      expect(again!.peaks, first.peaks);
      // The same recording under another name keeps its picture.
      final moved = media.copySync(p.join(dir.path, 'renamed.m4a'));
      await soundPeaksWith(run, probe, moved.path, audioTrack: 1, cacheDir: cache);
      expect(runs, 1);
      // Another stream is another picture.
      await soundPeaksWith(run, (_) async => const MediaInfo(
              durationMs: 3000, width: 0, height: 0, hasVideo: false, hasAudio: true),
          media.path, cacheDir: cache);
      expect(runs, 2);
    });

    test('a file without sound has no picture; a failed decode says so',
        () async {
      final media = File(p.join(dir.path, 'x.mp4'))..writeAsBytesSync([1, 2, 3]);
      Future<FfmpegRun> fail(List<String> args) async => const FfmpegRun(false, 'boom');
      expect(
          await soundPeaksWith(fail, (_) async => const MediaInfo(
                  durationMs: 1, width: 1, height: 1, hasVideo: true, hasAudio: false),
              media.path),
          isNull);
      await expectLater(
          soundPeaksWith(fail, (_) async => const MediaInfo(
                  durationMs: 1, width: 1, height: 1, hasVideo: true, hasAudio: true),
              media.path),
          throwsA(isA<ExportException>()));
    });

    test('the least recently used pictures go first', () async {
      final now = DateTime(2026, 11, 18, 12);
      for (var i = 0; i < 5; i++) {
        File(p.join(dir.path, 'pk_${i}_a0.cfpk'))
          ..writeAsBytesSync(List.filled(1000, 0))
          ..setLastModifiedSync(now.subtract(Duration(hours: 5 - i)));
      }
      File(p.join(dir.path, 'other.txt')).writeAsStringSync('keep');
      expect(await evictSoundPeaks(dir.path, maxBytes: 2500), 3000);
      expect(
          Directory(dir.path).listSync().map((e) => p.basename(e.path)).toSet(),
          {'pk_3_a0.cfpk', 'pk_4_a0.cfpk', 'other.txt'});
      expect(await evictSoundPeaks(p.join(dir.path, 'missing')), 0);
    });
  });

  group('who is speaking', () {
    test('one microphone: talk above the noise, short gaps bridged', () {
      final peaks = levels(20000, -55, [
        (1000, 3000, -18),
        (3200, 5000, -20), // a 200 ms gap: the same stretch
        (8000, 8060, -18), // a click: too short
        (10000, 14000, -22),
      ]);
      expect(speechStretches(peaks),
          [(startMs: 1000, endMs: 5000), (startMs: 10000, endMs: 14000)]);
      final l = analyseSpeechLevels(peaks);
      expect(l.hasSpeech, isTrue);
      expect(l.floorDb, closeTo(-55, 1));
      expect(l.thresholdDb, closeTo(-43, 1.5)); // floor + 12 (the cap)
    });

    test('digital silence, a muted track, a steady hum', () {
      expect(speechStretches(levels(10000, -120, const [])), isEmpty);
      expect(analyseSpeechLevels(levels(10000, -120, const [])).hasSpeech, isFalse);
      // A muted Zoom track with one short answer: found, although it is
      // far less than a tenth of the file.
      final rare = levels(100000, -120, [(50000, 53000, -20)]);
      expect(speechStretches(rare), [(startMs: 50000, endMs: 53000)]);
      // A quiet steady hum is nobody talking.
      expect(speechStretches(levels(10000, -60, const [])), isEmpty);
    });

    test('two microphones: the other speaker\'s bleed does not count', () {
      // Sam talks 1-5 s and 12-15 s, Dana 6-10 s; each is heard 22 dB
      // lower in the other's microphone. 15-18 s: both talk.
      final sam = levels(20000, -60, [
        (1000, 5000, -16),
        (6000, 10000, -38), // Dana, faintly
        (12000, 15000, -16),
        (15000, 18000, -17),
      ]);
      final dana = levels(20000, -58, [
        (1000, 5000, -40), // Sam, faintly
        (6000, 10000, -18),
        (12000, 15000, -40),
        (15000, 18000, -19),
      ]);
      // Alone, each microphone "hears" both.
      expect(speechStretches(dana).first.startMs, 1000);
      final both = groupSpeechStretches(
          [(peaks: sam, offsetMs: 0), (peaks: dana, offsetMs: 0)]);
      expect(both[0], [
        (startMs: 1000, endMs: 5000),
        (startMs: 12000, endMs: 18000),
      ]);
      expect(both[1], [
        (startMs: 6000, endMs: 10000),
        (startMs: 15000, endMs: 18000), // the overlap stays on both
      ]);
    });

    test('two microphones with different offsets are compared in step', () {
      final sam = levels(20000, -60, [(2000, 5000, -16), (8000, 11000, -40)]);
      // Dana's file starts 3 s earlier: everything is 3 s later in it.
      final dana = levels(23000, -60, [(5000, 8000, -40), (11000, 14000, -18)]);
      final both = groupSpeechStretches(
          [(peaks: sam, offsetMs: 0), (peaks: dana, offsetMs: 3000)]);
      expect(both[0], [(startMs: 2000, endMs: 5000)]);
      expect(both[1], [(startMs: 11000, endMs: 14000)]); // its own file time
    });

    test('a quiet reply under nobody else is kept', () {
      final sam = levels(10000, -60, [(1000, 4000, -16), (6000, 7000, -30)]);
      final dana = levels(10000, -60, [(1000, 4000, -40)]);
      final both = groupSpeechStretches(
          [(peaks: sam, offsetMs: 0), (peaks: dana, offsetMs: 0)]);
      expect(both[0], [(startMs: 1000, endMs: 4000), (startMs: 6000, endMs: 7000)]);
      expect(both[1], isEmpty);
    });
  });

  group('on the timeline', () {
    const file = [
      (startMs: 1000, endMs: 3000),
      (startMs: 5000, endMs: 6000),
      (startMs: 9000, endMs: 12000),
    ];

    test('trim, place and speed', () {
      expect(
          stretchesOnTimeline(file, startMs: 0, inMs: 0, outMs: 20000), file);
      // From 2 s to 10 s of the file, placed at 30 s.
      expect(stretchesOnTimeline(file, startMs: 30000, inMs: 2000, outMs: 10000), [
        (startMs: 30000, endMs: 31000),
        (startMs: 33000, endMs: 34000),
        (startMs: 37000, endMs: 38000),
      ]);
      // Twice as fast: half as long.
      expect(
          stretchesOnTimeline(file, startMs: 0, inMs: 0, outMs: 20000, speed: 2)
              .first,
          (startMs: 500, endMs: 1500));
      expect(stretchesOnTimeline(file, startMs: 0, inMs: 3000, outMs: 5000), isEmpty);
      expect(stretchesOnTimeline(const [], startMs: 0, inMs: 0, outMs: 10), isEmpty);
    });

    final samPeaks = levels(60000, -60, [(1000, 5000, -16), (20000, 30000, -16)]);
    final danaPeaks = levels(62000, -60, [(8000, 14000, -18), (40000, 46000, -18)]);
    SoundPeaks? lookup(String path, int track) => switch (path) {
          '/m/sam.m4a' => samPeaks,
          '/m/dana.m4a' => danaPeaks,
          _ => null,
        };

    test('speakers are the speech tracks; the linked-voice offset is undone',
        () {
      // Dana's file starts 2 s before the video: offset 2000.
      final p = twoVoices(audio: [
        voice('v1', '/m/sam.m4a', 'sam'),
        voice('v2', '/m/dana.m4a', 'dana', inMs: 2000, outMs: 62000, offset: 2000),
      ]);
      final tracks = speakerTracks(p, lookup);
      expect(tracks.map((t) => (t.id, t.name)), [('sam', 'Sam'), ('dana', 'Dana')]);
      expect(tracks[0].stretches,
          [(startMs: 1000, endMs: 5000), (startMs: 20000, endMs: 30000)]);
      expect(tracks[1].stretches,
          [(startMs: 6000, endMs: 12000), (startMs: 38000, endMs: 44000)]);
      expect(tracks[0].talkMs, 14000);
      expect(tracks.every((t) => !t.pending), isTrue);
    });

    test('a real cut and a speed change move the talk with the picture', () {
      final e = ProjectEditor(twoVoices(), newId: (() {
        var n = 0;
        return () => 'n${n++}';
      })());
      // Cut 6-18 s out of the video: the linked voices follow.
      e.removeSourceRanges('a', [(startMs: 6000, endMs: 18000)]);
      expect(e.project.durationMs, 48000);
      var tracks = speakerTracks(e.project, lookup);
      expect(tracks[0].stretches,
          [(startMs: 1000, endMs: 5000), (startMs: 8000, endMs: 18000)]);
      // Dana's 8-14 s went with the cut; 40-46 s is now 28-34 s.
      expect(tracks[1].stretches, [(startMs: 28000, endMs: 34000)]);
      // Twice as fast.
      for (final c in e.project.clips) {
        e.setClipSpeed(c.id, 2);
      }
      tracks = speakerTracks(e.project, lookup);
      expect(e.project.durationMs, 24000);
      expect(tracks[0].stretches,
          [(startMs: 500, endMs: 2500), (startMs: 4000, endMs: 9000)]);
      expect(tracks[1].stretches, [(startMs: 14000, endMs: 17000)]);
    });

    test('without speech tracks the video\'s own sound is the speaker', () {
      final p = Project(
        id: 'p',
        name: 'Clip',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        clips: [clip('a', 10000, 30000, muted: false)],
      );
      final tracks = speakerTracks(
          p, (path, _) => path == '/m/zoom.mp4' ? samPeaks : null);
      expect(tracks.single.id, SoundTrack.videoId);
      expect(tracks.single.stretches, [(startMs: 10000, endMs: 20000)]);
      // Not drawn yet: pending, nothing known.
      final waiting = speakerTracks(p, (_, _) => null);
      expect(waiting.single.pending, isTrue);
      expect(waiting.single.stretches, isEmpty);
      // A muted clip has no speaker.
      expect(
          speakerTracks(p.copyWith(clips: [clip('a', 0, 1000)]), lookup), isEmpty);
    });

    test('music is not speech', () {
      final p = twoVoices(audio: [
        const AudioClip(
            id: 'm', path: '/m/sam.m4a', sourceDurationMs: 60000,
            startMs: 0, inMs: 0, outMs: 60000),
      ]);
      final r = SpeechResolver(p, lookup, SpeechCache());
      expect(r.isSpeech(p.audio.single), isFalse);
      expect(r.fileStretches(p.audio.single), isNull);
    });

    final tracks = [
      SpeakerTrack('sam', 'Sam', const [
        (startMs: 1000, endMs: 5000),
        (startMs: 5400, endMs: 9000), // a breath: the same turn
        (startMs: 20000, endMs: 30000),
        (startMs: 34000, endMs: 36000), // after 4 s of quiet: a new turn
      ]),
      SpeakerTrack('dana', 'Dana', const [
        (startMs: 10000, endMs: 19000),
        (startMs: 25000, endMs: 25500), // "mm-hm" while Sam talks
      ]),
    ];

    test('speaker turns', () {
      expect([for (final t in speakerTurns(tracks)) (t.name, t.startMs, t.endMs)], [
        ('Sam', 1000, 9000),
        ('Dana', 10000, 19000),
        ('Sam', 20000, 30000),
        ('Dana', 25000, 25500),
        ('Sam', 34000, 36000),
      ]);
      expect(speakerTurns(const []), isEmpty);
    });

    test('next and previous speech start', () {
      // Nothing selected: where the speaker changes.
      final any = speechStarts(tracks);
      expect(any, [1000, 10000, 20000, 25000, 34000]);
      expect(neighbourStart(any, 0, forward: true), 1000);
      expect(neighbourStart(any, 1000, forward: true), 10000);
      expect(neighbourStart(any, 34000, forward: true), isNull);
      expect(neighbourStart(any, 12000, forward: false), 10000);
      // Just after a start (still playing): the one before.
      expect(neighbourStart(any, 10200, forward: false), 1000);
      expect(neighbourStart(any, 500, forward: false), isNull);
      // A track selected: that speaker's starts (short pauses ignored).
      expect(speechStarts(tracks, trackId: 'sam'), [1000, 20000, 34000]);
      expect(speechStarts(tracks, trackId: 'dana'), [10000, 25000]);
      expect(speechStarts(tracks, trackId: 'nobody'), any);
    });

    test('snapping catches the starts and ends of talk', () {
      final p = twoVoices();
      final edges = speechEdges(tracks);
      expect(edges, containsAll([1000, 5000, 5400, 19000, 36000]));
      final targets = snapTargets(p, playheadMs: 123, extra: edges);
      expect(targets, containsAll([0, 123, 60000, 5400, 25500]));
      expect(snapTime(5350, targets, 80), (ms: 5400, snapped: 5400));
      expect(snapTime(5350, snapTargets(p, playheadMs: 123), 80).snapped, isNull);
    });
  });
}
