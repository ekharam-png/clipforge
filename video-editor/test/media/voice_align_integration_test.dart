// Real FFmpeg (on PATH): "Voice recorded separately" end to end.
//
// A "camera" video whose own sound is speech-like (bursts of noise with
// pauses) heard through a room (echo, noise, quieter), and "microphone"
// files with the same speech cut at a known offset, with another tone
// (band-limited) and level, as AAC. Checks that the offset is found within
// 20 ms, that unrelated sound and a silent video are refused, that the
// EXPORT has the voice in sync after trims and cuts (the exported sound is
// compared with what should be there), that the trim / silence rules hold
// (voice starting late, voice ending early) and that "Remove silences"
// listens to the voice, not to the muted camera.
// Skipped (with a message) without ffmpeg / ffprobe.

import 'dart:io';
import 'dart:typed_data';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/clip_silences.dart';
import 'package:clipforge/media/silence_levels.dart';
import 'package:clipforge/media/sound_align_job.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sound_align_test.dart' show speech, cut;
import 'support.dart';

/// Writes [x] (8 kHz, -1..1) as a 16-bit mono WAV.
void writeWav(String path, Float64List x) {
  final data = ByteData(44 + x.length * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + x.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, kAlignRate, Endian.little);
  data.setUint32(28, kAlignRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, x.length * 2, Endian.little);
  for (var i = 0; i < x.length; i++) {
    data.setInt16(44 + i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little);
  }
  File(path).writeAsBytesSync(data.buffer.asUint8List());
}

/// The envelope of the sound of [path] (decoded by ffmpeg like the app).
Future<SoundEnvelope> envelopeOf(String path) async {
  final raw = f('env_${seq++}.raw');
  final r = Process.runSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error',
    ...buildAlignDecodeCommand(path: path, outputPath: raw),
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final e = await SoundEnvelope.fromRawFile(raw);
  File(raw).deleteSync();
  return e;
}

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  // The speech everybody recorded: 40 s, with a 2 s pause at 10..12 s.
  late Float64List talk;
  const cameraLead = 2150; // the microphone started 2.15 s before the camera

  setUpAll(() {
    setUpMedia();
    talk = speech(40, 77);
    for (var i = 10 * kAlignRate; i < 12 * kAlignRate; i++) {
      talk[i] = 0;
    }
    writeWav(f('talk.wav'), talk);
    writeWav(f('other.wav'), speech(40, 78));
    // Camera: 30 s picture; its sound is the talk from 2.15 s on, through
    // a room: echo, quieter, with noise. AAC in MP4.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=30',
      '-ss', '2.150', '-i', f('talk.wav'),
      '-f', 'lavfi', '-i', 'anoisesrc=c=pink:r=48000:a=0.02:d=30',
      '-filter_complex',
      '[1:a]aresample=48000,aecho=0.8:0.6:45|90:0.35|0.2,volume=0.5[v];'
          '[v][2:a]amix=inputs=2:normalize=0[a]',
      '-map', '0:v', '-map', '[a]',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '96k', '-t', '30', f('camera.mp4'),
    ]);
    // The same picture with steady loud noise as its only sound, and one
    // without sound.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=30',
      '-f', 'lavfi', '-i', 'anoisesrc=c=white:r=48000:a=0.2:d=30',
      '-map', '0:v', '-map', '1:a',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-t', '30', f('silentcam.mp4'),
    ]);
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=10',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-an', f('mute.mp4'),
    ]);
    // Microphones: another tone (band-limited), another level, AAC in M4A.
    const mic = 'highpass=f=250,lowpass=f=2400,volume=0.3';
    ff(['-i', f('talk.wav'), '-af', mic, '-ar', '44100', '-c:a', 'aac',
        f('audioSamTaylor21406335665.m4a')]);
    // Started 5 s into the talk: 2.85 s AFTER the camera.
    ff(['-ss', '5', '-i', f('talk.wav'), '-af', mic, '-c:a', 'aac',
        f('late.m4a')]);
    // Stopped early: only the first 12 s of the talk.
    ff(['-t', '12', '-i', f('talk.wav'), '-af', mic, '-c:a', 'aac',
        f('short.m4a')]);
    ff(['-i', f('other.wav'), '-af', mic, '-c:a', 'aac', f('other.m4a')]);
  });
  tearDownAll(tearDownMedia);

  Clip camera({String file = 'camera.mp4', int inMs = 0, int outMs = 30000}) =>
      Clip(
        id: 'cam',
        type: ClipType.video,
        path: f(file),
        sourceDurationMs: 30000,
        inMs: inMs,
        outMs: outMs,
        width: 320,
        height: 180,
        frameRate: 30,
      );

  AudioClip voice(String file, int lengthMs) => AudioClip(
        id: 'v',
        path: f(file),
        sourceDurationMs: lengthMs,
        startMs: 0,
        inMs: 0,
        outMs: lengthMs,
      );

  Project base(Clip clip) => Project(
      id: 'p', name: 'p', createdAt: t0, updatedAt: t0, clips: [clip]);

  const mic = 'audioSamTaylor21406335665.m4a';

  test('finds the offset within 20 ms: mic earlier, mic later', () async {
    final sw = Stopwatch()..start();
    final a = await engine.alignSound(f('camera.mp4'), f(mic));
    // ignore: avoid_print
    print('mic earlier: $a (${sw.elapsedMilliseconds} ms)');
    expect(a.matched, isTrue);
    expect(a.offsetMs, closeTo(cameraLead, 20));
    expect(a.confidence, greaterThan(0.8));
    expect(a.drifts, isFalse);

    final b = await engine.alignSound(f('camera.mp4'), f('late.m4a'));
    // ignore: avoid_print
    print('mic later: $b');
    expect(b.matched, isTrue);
    expect(b.offsetMs, closeTo(cameraLead - 5000, 20));

    final c = await engine.alignSound(f('camera.mp4'), f('short.m4a'));
    expect(c.matched, isTrue);
    expect(c.offsetMs, closeTo(cameraLead, 20));
  });

  test('unrelated speech, a camera with only noise, no sound: not matched',
      () async {
    final other = await engine.alignSound(f('camera.mp4'), f('other.m4a'));
    // ignore: avoid_print
    print('unrelated: $other');
    expect(other.matched, isFalse);
    final noise = await engine.alignSound(f('silentcam.mp4'), f(mic));
    // ignore: avoid_print
    print('noise only: $noise');
    expect(noise.matched, isFalse);
    final none = await engine.alignSound(f('mute.mp4'), f(mic));
    expect(none.matched, isFalse);
    expect(none.reason, contains('no sound'));
  });

  test('export: the voice is in sync after a trim and a cut', () async {
    final found = await engine.alignSound(f('camera.mp4'), f(mic));
    final e = ProjectEditor(base(camera(inMs: 3000, outMs: 23000)));
    e.addVoice(voice(mic, 40000), clipId: 'cam', offsetMs: found.offsetMs);
    // Cut 8..12 s of the camera file out: two pieces.
    expect(e.removeSourceRanges('cam', [(startMs: 8000, endMs: 12000)]), 1);
    expect(e.project.clips.length, 2);
    expect(e.project.audio.length, 2);
    expect(e.project.clips.every((c) => c.muted), isTrue);
    final out = await exportAndCheck(e.project);

    // What should be heard: the talk at (camera time + 2.15 s) for camera
    // 3..8 s, then 12..23 s.
    final want = Float64List.fromList([
      ...cut(talk, 3000 + cameraLead, 5000),
      ...cut(talk, 12000 + cameraLead, 11000),
    ]);
    writeWav(f('want.wav'), want);
    final r = alignEnvelopes(
        await envelopeOf(f('want.wav')), await envelopeOf(out));
    // ignore: avoid_print
    print('export vs expected: $r, windows '
        '${[for (final w in r.windows) w.toJson()]}');
    expect(r.matched, isTrue);
    expect(r.offsetMs.abs(), lessThanOrEqualTo(20));
    expect(r.score, greaterThan(0.6));
    // Each piece on its own (a wrong cut would shift only the second).
    final first = alignEnvelopes(
        SoundEnvelope.fromPcm16(_pcm16(cut(want, 0, 5000))),
        await envelopeOf(_part(out, 0, 5000)));
    final second = alignEnvelopes(
        SoundEnvelope.fromPcm16(_pcm16(cut(want, 5000, 11000))),
        await envelopeOf(_part(out, 5000, 11000)));
    expect(first.offsetMs.abs(), lessThanOrEqualTo(20), reason: '$first');
    expect(second.offsetMs.abs(), lessThanOrEqualTo(20), reason: '$second');
    expect(first.matched && second.matched, isTrue);
  });

  test('export: with speed 2 the voice still matches the picture', () async {
    final e = ProjectEditor(base(camera(inMs: 4000, outMs: 24000)));
    e.addVoice(voice(mic, 40000), clipId: 'cam', offsetMs: cameraLead);
    e.setClipSpeed('cam', 2);
    final a = e.project.audio.single;
    expect([a.speed, a.inMs, a.outMs], [2, 4000 + cameraLead, 24000 + cameraLead]);
    final out = await exportAndCheck(e.project);
    // The talk at double speed: every second envelope value.
    final src = await envelopeOf(_wav(cut(talk, 4000 + cameraLead, 20000)));
    final half = Float32List(src.values.length ~/ 2);
    for (var i = 0; i < half.length; i++) {
      half[i] = (src.values[2 * i] + src.values[2 * i + 1]) / 2;
    }
    final r = alignEnvelopes(SoundEnvelope(half), await envelopeOf(out));
    // ignore: avoid_print
    print('speed 2: $r');
    expect(r.matched, isTrue);
    expect(r.offsetMs.abs(), lessThanOrEqualTo(25));
  });

  test('voice that started late: silence first, then in sync', () async {
    final e = ProjectEditor(base(camera(outMs: 12000)));
    e.addVoice(voice('late.m4a', 35000),
        clipId: 'cam', offsetMs: cameraLead - 5000);
    final a = e.project.audio.single;
    expect([a.startMs, a.inMs], [2850, 0]);
    final out = await exportAndCheck(e.project);
    expect(meanVolume(out, fromMs: 100, toMs: 2700), lessThan(-60));
    expect(meanVolume(out, fromMs: 3000, toMs: 7000), greaterThan(-45));
    final r = alignEnvelopes(
        await envelopeOf(_wav(cut(talk, cameraLead, 12000))),
        await envelopeOf(out));
    expect(r.matched, isTrue);
    expect(r.offsetMs.abs(), lessThanOrEqualTo(20), reason: '$r');
  });

  test('voice that ends early: silence after it', () async {
    final e = ProjectEditor(base(camera(inMs: 3000, outMs: 23000)));
    e.addVoice(voice('short.m4a', 12000), clipId: 'cam', offsetMs: cameraLead);
    final a = e.project.audio.single;
    // Camera 3 s is talk 5.15 s; the file ends at 12 s = 6.85 s later.
    expect([a.startMs, a.inMs, a.outMs], [0, 5150, 12000]);
    final out = await exportAndCheck(e.project);
    expect(meanVolume(out, fromMs: 500, toMs: 4500), greaterThan(-45));
    expect(meanVolume(out, fromMs: 7200, toMs: 19500), lessThan(-60));
  });

  test('remove silences listens to the voice, not to the muted camera',
      () async {
    // The camera hears steady loud noise: by itself it has no quiet part.
    final own = await startClipSilenceSearch(
            engine, base(camera(file: 'silentcam.mp4')),
            camera(file: 'silentcam.mp4'))
        .result;
    expect(own, isEmpty);

    final e = ProjectEditor(base(camera(file: 'silentcam.mp4')));
    e.addVoice(voice(mic, 40000), clipId: 'cam', offsetMs: cameraLead);
    final clip = e.project.clips.single;
    final search = startClipSilenceSearch(engine, e.project, clip);
    final found = await search.result;
    expect(search.listensToVoice, isTrue);
    expect(search.sources.length, 1, reason: 'the muted camera is not heard');
    // The 2 s pause at talk 10..12 s is camera 7.85..9.85 s.
    final pause = found.where((r) => r.startMs < 8600 && r.endMs > 9000);
    expect(pause, isNotEmpty, reason: '$found');
    expect(pause.first.startMs, closeTo(10000 - cameraLead, 200));
    expect(pause.first.endMs, closeTo(12000 - cameraLead, 200));
    expect(search.canAdjust, isTrue);
    expect(search.silencesFor(SilenceSensitivity.auto), found);

    // With the camera's noise switched back on nothing is silent.
    e.setVoiceClipsMuted(e.project.audio.single.id, false);
    final both = startClipSilenceSearch(
        engine, e.project, e.project.clips.single);
    expect(both.sources.length, 2);
    expect(await both.result, isEmpty);
  });
}

Uint8List _pcm16(Float64List x) {
  final b = ByteData(x.length * 2);
  for (var i = 0; i < x.length; i++) {
    b.setInt16(i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

String _wav(Float64List x) {
  final path = f('piece_${seq++}.wav');
  writeWav(path, x);
  return path;
}

/// [lengthMs] of the sound of [path] from [fromMs], as a WAV.
String _part(String path, int fromMs, int lengthMs) {
  final out = f('part_${seq++}.wav');
  ff(['-i', path, '-vn', '-af',
      'atrim=start=${fromMs / 1000}:duration=${lengthMs / 1000},asetpts=PTS-STARTPTS',
      out]);
  return out;
}
