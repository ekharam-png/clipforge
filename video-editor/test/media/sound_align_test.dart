import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/media/sound_align.dart';
import 'package:flutter_test/flutter_test.dart';

/// Speech-like test sound: bursts of noise ("syllables", 60-300 ms) with
/// pauses, and longer pauses between "sentences". 8 kHz, -1..1.
Float64List speech(int seconds, int seed, {double talk = 1.0}) {
  final r = math.Random(seed);
  final n = seconds * kAlignRate;
  final out = Float64List(n);
  var i = 0;
  while (i < n) {
    // A sentence, then a pause.
    final sentence = ((1.0 + r.nextDouble() * 3.0) * kAlignRate).round();
    final end = math.min(n, i + sentence);
    final speaking = r.nextDouble() < talk;
    while (i < end) {
      final syl = ((0.06 + r.nextDouble() * 0.24) * kAlignRate).round();
      final gap = ((0.03 + r.nextDouble() * 0.15) * kAlignRate).round();
      final level = 0.2 + r.nextDouble() * 0.5;
      for (var k = 0; k < syl && i < end; k++, i++) {
        if (!speaking) continue;
        final shape = math.sin(math.pi * k / syl);
        out[i] = (r.nextDouble() * 2 - 1) * level * shape;
      }
      i = math.min(end, i + gap);
    }
    i += ((0.3 + r.nextDouble() * 1.2) * kAlignRate).round();
  }
  return out;
}

Float64List noise(int n, int seed, double level) {
  final r = math.Random(seed);
  return Float64List.fromList(
      [for (var i = 0; i < n; i++) (r.nextDouble() * 2 - 1) * level]);
}

/// A duller microphone: one-pole low-pass at about [hz].
Float64List lowpass(Float64List x, double hz) {
  final a = 1 - math.exp(-2 * math.pi * hz / kAlignRate);
  final out = Float64List(x.length);
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    y += a * (x[i] - y);
    out[i] = y;
  }
  return out;
}

Float64List mix(List<Float64List> parts, [List<double>? gains]) {
  final n = parts.map((p) => p.length).reduce(math.min);
  final out = Float64List(n);
  for (var k = 0; k < parts.length; k++) {
    final g = gains == null ? 1.0 : gains[k];
    for (var i = 0; i < n; i++) {
      out[i] += parts[k][i] * g;
    }
  }
  return out;
}

/// [x] from [fromMs] for [lengthMs] (silence where there is no sound).
Float64List cut(Float64List x, int fromMs, int lengthMs) {
  final n = lengthMs * kAlignRate ~/ 1000;
  final from = fromMs * kAlignRate ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final j = from + i;
    if (j >= 0 && j < x.length) out[i] = x[j];
  }
  return out;
}

/// [x] played [factor] times slower (linear interpolation).
Float64List stretch(Float64List x, double factor) {
  final n = (x.length * factor).floor();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final p = i / factor;
    final j = p.floor();
    if (j + 1 >= x.length) break;
    final f = p - j;
    out[i] = x[j] * (1 - f) + x[j + 1] * f;
  }
  return out;
}

SoundEnvelope env(Float64List x) {
  final b = Uint8List(x.length * 2);
  final d = ByteData.sublistView(b);
  for (var i = 0; i < x.length; i++) {
    d.setInt16(i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  // In uneven pieces, as a file read would deliver it.
  final builder = EnvelopeBuilder();
  var at = 0;
  var size = 4097;
  while (at < b.length) {
    final end = math.min(b.length, at + size);
    builder.add(Uint8List.sublistView(b, at, end));
    at = end;
    size = size == 4097 ? 8191 : 4097;
  }
  return builder.finish();
}

void main() {
  group('alignEnvelopes', () {
    final talk = speech(120, 1);

    test('voice started 1.337 s before the camera: offset +1337', () {
      final camera = cut(talk, 1337, 100000);
      final r = alignEnvelopes(env(camera), env(talk));
      expect(r.offsetMs, closeTo(1337, 5));
      expect(r.matched, isTrue, reason: '$r');
      expect(r.confidence, greaterThan(0.8));
      expect(r.driftMs, 0);
    });

    test('voice started 2.5 s after the camera: offset -2500', () {
      final voice = cut(talk, 2500, 90000);
      final r = alignEnvelopes(env(talk), env(voice));
      expect(r.offsetMs, closeTo(-2500, 5));
      expect(r.matched, isTrue, reason: '$r');
    });

    test('offsets between envelope steps are found to a few ms', () {
      for (final off in [3, 418, 12346]) {
        final camera = cut(talk, off, 100000);
        final r = alignEnvelopes(env(camera), env(talk));
        expect(r.offsetMs, closeTo(off, 4), reason: '$off: $r');
      }
    });

    test('room noise, 26 dB quieter, a duller microphone', () {
      final camera = mix([
        cut(talk, 800, 100000),
        noise(100 * kAlignRate, 7, 0.05),
      ]);
      final voice = lowpass(talk, 900);
      for (var i = 0; i < voice.length; i++) {
        voice[i] *= 0.05;
      }
      final r = alignEnvelopes(env(camera), env(voice));
      expect(r.offsetMs, closeTo(800, 10), reason: '$r');
      expect(r.matched, isTrue, reason: '$r');
    });

    test('one speaker\'s microphone against a camera that hears two', () {
      // Zoom: the video has everybody, each sound file one person.
      final a = speech(120, 21, talk: 0.5);
      final b = speech(120, 22, talk: 0.6);
      final camera = cut(mix([a, b, noise(a.length, 3, 0.01)]), 640, 110000);
      final ra = alignEnvelopes(env(camera), env(a));
      expect(ra.offsetMs, closeTo(640, 10), reason: '$ra');
      expect(ra.matched, isTrue, reason: '$ra');
      final rb = alignEnvelopes(env(camera), env(lowpass(b, 1500)));
      expect(rb.offsetMs, closeTo(640, 10), reason: '$rb');
      expect(rb.matched, isTrue, reason: '$rb');
    });

    test('a short voice file inside a long video', () {
      final long = speech(300, 5);
      final voice = cut(long, 200000, 20000);
      final r = alignEnvelopes(env(long), env(voice));
      expect(r.offsetMs, closeTo(-200000, 6), reason: '$r');
      expect(r.matched, isTrue, reason: '$r');
    });

    test('unrelated sounds: low confidence', () {
      for (var seed = 40; seed < 52; seed++) {
        final r = alignEnvelopes(
            env(speech(120, seed)), env(speech(120, seed + 100)));
        expect(r.matched, isFalse, reason: '$seed: $r');
        expect(r.confidence, lessThan(0.35), reason: '$seed: $r');
      }
    });

    test('music against speech: low confidence', () {
      final n = 60 * kAlignRate;
      final music = Float64List(n);
      for (var i = 0; i < n; i++) {
        final beat = (i % 4000) < 400 ? 1.0 : 0.3;
        music[i] = math.sin(2 * math.pi * 220 * i / kAlignRate) * 0.4 * beat;
      }
      final r = alignEnvelopes(env(speech(60, 33)), env(music));
      expect(r.matched, isFalse, reason: '$r');
    });

    test('silence on either side: no match, with a reason', () {
      final quiet = Float64List(30 * kAlignRate);
      final a = alignEnvelopes(env(quiet), env(talk));
      expect(a.matched, isFalse);
      expect(a.reason, contains('video has no sound'));
      final b = alignEnvelopes(env(talk), env(quiet));
      expect(b.matched, isFalse);
      expect(b.reason, isNotNull);
      final c = alignEnvelopes(env(cut(talk, 0, 1000)), env(talk));
      expect(c.reason, contains('short'));
    });

    test('drift is reported, the offset is the best constant one', () {
      final long = speech(300, 9);
      // The voice recorder's clock runs 0.05 % slow: 150 ms over 5 minutes
      // (far more than two real devices differ in 40 minutes).
      final voice = stretch(long, 1.0005);
      final r = alignEnvelopes(env(long), env(voice));
      expect(r.matched, isTrue, reason: '$r');
      expect(r.driftMs, closeTo(150, 40), reason: '$r');
      expect(r.drifts, isTrue);
      // Somewhere between the offset at the start (0) and at the end (150).
      expect(r.offsetMs, inInclusiveRange(0, 150));
      expect(r.windows.length, greaterThanOrEqualTo(3));

      final steady = alignEnvelopes(env(long), env(long));
      expect(steady.driftMs, 0);
      expect(steady.drifts, isFalse);
      expect(steady.offsetMs, 0);
    });

    test('a 40 minute pair is quick', () {
      // Envelopes only (the decode is ffmpeg's job): 480 000 values each.
      final r = math.Random(4);
      final n = 40 * 60 * 1000 ~/ kAlignHopMs;
      final e = List<double>.generate(n, (i) => 0.0);
      var i = 0;
      while (i < n) {
        final len = 12 + r.nextInt(50);
        final level = r.nextDouble() < 0.7 ? r.nextDouble() : 0.0;
        for (var k = 0; k < len && i < n; k++, i++) {
          e[i] = level * level;
        }
      }
      const shift = 1234; // hops = 6.17 s
      final video = SoundEnvelope.fromEnergy(e.sublist(shift));
      final voice = SoundEnvelope.fromEnergy(e);
      final sw = Stopwatch()..start();
      final res = alignEnvelopes(video, voice);
      sw.stop();
      expect(res.offsetMs, closeTo(shift * kAlignHopMs, 5), reason: '$res');
      expect(res.matched, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(8000));
    });
  });

  group('file names', () {
    test('guess', () {
      expect(guessSoundRole('audioSamTaylor21406335665.m4a'),
          SoundRole.voice);
      expect(guessSoundRole('My Voice take 2.wav'), SoundRole.voice);
      expect(guessSoundRole('podcast-ep4.mp3'), SoundRole.voice);
      expect(guessSoundRole('zoom_0.m4a'), SoundRole.voice);
      expect(guessSoundRole('mic.wav'), SoundRole.voice);
      expect(guessSoundRole('Summer Vibes.mp3'), SoundRole.music);
      expect(guessSoundRole('dynamic-beat.mp3'), SoundRole.music);
      expect(guessSoundRole('invoice.mp3'), SoundRole.music);
      // Length within 10 % of a video clip's file.
      expect(
          guessSoundRole('track01.mp3',
              durationMs: 1380000, videoDurationsMs: [1406000]),
          SoundRole.voice);
      expect(
          guessSoundRole('track01.mp3',
              durationMs: 180000, videoDurationsMs: [1406000]),
          SoundRole.music);
      expect(
          guessSoundRole('click.wav', durationMs: 900, videoDurationsMs: [950]),
          SoundRole.music);
    });

    test('speaker name', () {
      expect(speakerNameFromFile('audioSamTaylor21406335665.m4a'),
          'Sam Taylor');
      expect(speakerNameFromFile(r'C:\Zoom\audioAlexK11406335665.m4a'),
          'Alex K');
      expect(speakerNameFromFile('/x/audio1406335665.m4a'), isNull);
      expect(speakerNameFromFile('mic - Anna.wav'), 'Anna');
      expect(speakerNameFromFile('voice_Tom Baker.mp3'), 'Tom Baker');
      expect(speakerNameFromFile('Summer Vibes.mp3'), isNull);
      expect(speakerNameFromFile('audio.m4a'), isNull);
    });
  });
}
