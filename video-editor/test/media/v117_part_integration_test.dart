// Real exports for 1.17 "select a part" (FFmpeg on PATH): a silenced /
// lowered range on ONE track while the others are untouched, fades
// without clicks, ranges that follow trim and speed, ranges on pieces of
// one file that share an input, a speed change on a part with a linked
// voice in sync, and "Only when speaking" on a synthetic two-microphone
// recording. Skipped (with a message) without ffmpeg / ffprobe.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/sound_peaks.dart';
import 'package:clipforge/media/speech_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Float32List pcm(String path) {
  final r = Process.runSync(
      'ffmpeg',
      ['-v', 'error', '-i', path, '-vn', '-ac', '1', '-ar', '48000', '-f', 'f32le', '-'],
      stdoutEncoding: null);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final bytes = Uint8List.fromList(r.stdout as List<int>);
  return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
}

/// Level of the band around [hz] between [fromMs] and [toMs].
double band(String path, int hz, int fromMs, int toMs) => meanVolume(path,
    fromMs: fromMs,
    toMs: toMs,
    filter: 'bandpass=f=$hz:width_type=q:w=8,bandpass=f=$hz:width_type=q:w=8,');

/// Biggest step between two neighbouring samples in [fromMs]..[toMs].
double maxStep(Float32List x, int fromMs, int toMs) {
  var m = 0.0;
  final b = math.min(x.length - 1, toMs * 48);
  for (var i = math.max(1, fromMs * 48); i < b; i++) {
    final d = (x[i] - x[i - 1]).abs();
    if (d > m) m = d;
  }
  return m;
}

double rmsDb(Float32List x, int fromMs, int toMs) {
  var s = 0.0;
  final a = fromMs * 48, b = math.min(x.length, toMs * 48);
  for (var i = a; i < b; i++) {
    s += x[i] * x[i];
  }
  return 10 * math.log(s / math.max(1, b - a) + 1e-20) / math.ln10;
}

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    // 6 s picture with a 200 Hz tone as its own sound.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=6',
      '-f', 'lavfi', '-i', 'sine=f=200:r=48000:d=6',
      '-filter_complex', '[1:a]volume=0.4[a]', '-map', '0:v', '-map', '[a]',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-g', '15', '-c:a', 'aac', '-t', '6', f('pic.mp4'),
    ]);
    ff(['-f', 'lavfi', '-i', "aevalsrc='0.3*sin(2*PI*1000*t)':s=48000:d=6", f('voice.wav')]);
    ff(['-f', 'lavfi', '-i', "aevalsrc='0.2*sin(2*PI*300*t)':s=48000:d=6", f('music.wav')]);
    // A voice that only "says" something from 2.5 s to 3.5 s of its file.
    ff(['-f', 'lavfi', '-i',
        "aevalsrc='0.3*sin(2*PI*1000*t)*between(t,2.5,3.5)':s=48000:d=6", f('beep.wav')]);
    // Two microphones recorded together: A talks 0-2 s and 4-6 s (1 kHz),
    // B talks 2-4 s (2 kHz); each hears the other 20 dB down, over a
    // little room noise.
    ff(['-f', 'lavfi', '-i',
        "aevalsrc='0.3*sin(2*PI*1000*t)*(lt(t,2)+gte(t,4))"
            "+0.03*sin(2*PI*2000*t)*between(t,2,4)+0.002*sin(2*PI*90*t)'"
            ':s=48000:d=6',
        f('micA.wav')]);
    ff(['-f', 'lavfi', '-i',
        "aevalsrc='0.3*sin(2*PI*2000*t)*between(t,2,4)"
            "+0.03*sin(2*PI*1000*t)*(lt(t,2)+gte(t,4))+0.002*sin(2*PI*90*t)'"
            ':s=48000:d=6',
        f('micB.wav')]);
  });
  tearDownAll(tearDownMedia);

  Clip pic({int inMs = 0, int outMs = 6000, double speed = 1, String id = 'pic'}) =>
      Clip(
        id: id,
        type: ClipType.video,
        path: f('pic.mp4'),
        sourceDurationMs: 6000,
        inMs: inMs,
        outMs: outMs,
        width: 320,
        height: 180,
        speed: speed,
        frameRate: 30,
      );

  AudioClip snd(String id, String file, String track) => AudioClip(
        id: id,
        path: f(file),
        sourceDurationMs: 6000,
        startMs: 0,
        inMs: 0,
        outMs: 6000,
        trackId: track,
      );

  Project mix({List<Clip>? clips, List<AudioClip>? audio}) => Project(
        id: 'p',
        name: 'p',
        createdAt: t0,
        updatedAt: t0,
        clips: clips ?? [pic()],
        tracks: const [
          SoundTrack(id: 'v', name: 'Voice', speech: true),
          SoundTrack(id: 'm', name: 'Music'),
        ],
        audio: audio ??
            [snd('vo', 'voice.wav', 'v'), snd('mu', 'music.wav', 'm')],
      );

  var n = 0;
  String id() => 'id${n++}';

  test('silence on one row: that row is silent there, the others untouched',
      () async {
    final base = await exportAndCheck(mix());
    final e = ProjectEditor(mix(), newId: id);
    final r = e.silencePart(const TimelinePart(2000, 3000), rows: {'v'});
    expect(r.ok, isTrue);
    expect(e.project.audio.first.quiet, [const QuietRange(2000, 3000)]);
    expect(e.project.audio.last.quiet, isEmpty);
    expect(e.project.clips.single.quiet, isEmpty);
    final out = await exportAndCheck(e.project);

    final inside = band(out, 1000, 2100, 2900);
    final was = band(base, 1000, 2100, 2900);
    // ignore: avoid_print
    print('1 kHz inside the range: $inside dB (was $was dB)');
    expect(inside, lessThan(was - 40), reason: 'the voice is silent there');
    expect(band(out, 1000, 500, 1900), closeTo(band(base, 1000, 500, 1900), 0.7));
    expect(band(out, 1000, 3100, 5500), closeTo(band(base, 1000, 3100, 5500), 0.7));
    // The other rows, inside the range.
    expect(band(out, 300, 2100, 2900), closeTo(band(base, 300, 2100, 2900), 0.7),
        reason: 'the music plays on');
    expect(band(out, 200, 2100, 2900), closeTo(band(base, 200, 2100, 2900), 0.7),
        reason: "the video's own sound plays on");
  });

  test('the fades: no click (no sample jump), a straight ramp of 40 ms',
      () async {
    // The voice alone, sound only (WAV-like precision is not needed: the
    // comparison is with the same export without a range).
    Project solo(List<QuietRange> quiet) => mix(
          clips: [pic().copyWith(muted: true)],
          audio: [snd('vo', 'voice.wav', 'v').copyWith(quiet: quiet)],
        );
    final plain = pcm(await exportAndCheck(solo(const [])));
    final cut = pcm(await exportAndCheck(solo(const [QuietRange(2000, 3000)])));
    final step = maxStep(plain, 500, 5500);
    final stepAtEdges = math.max(maxStep(cut, 1950, 2100), maxStep(cut, 2900, 3050));
    // ignore: avoid_print
    print('largest sample step: plain $step, at the range edges $stepAtEdges');
    expect(stepAtEdges, lessThanOrEqualTo(step * 1.1),
        reason: 'switching down and up adds no jump');
    final full = rmsDb(plain, 1000, 1900);
    expect(rmsDb(cut, 1990, 1999), closeTo(full, 1.0), reason: 'full before');
    // Half way down the 40 ms ramp: about half the level (-6 dB).
    // (The AAC coder smears a 40 ms ramp by a few ms: a range, not a point.)
    expect(rmsDb(cut, 2015, 2025), inInclusiveRange(full - 10, full - 2));
    expect(rmsDb(cut, 2045, 2955), lessThan(full - 45), reason: 'silent inside');
    expect(rmsDb(cut, 2975, 2985), inInclusiveRange(full - 10, full - 2));
    expect(rmsDb(cut, 3002, 3012), closeTo(full, 1.0), reason: 'full after');
  });

  test('lower volume: -12 dB inside, nothing outside', () async {
    final base = await exportAndCheck(mix());
    final e = ProjectEditor(mix(), newId: id);
    expect(
        e.silencePart(const TimelinePart(1000, 4000),
            rows: {'m'}, level: levelFromDb(-12)).ok,
        isTrue);
    final out = await exportAndCheck(e.project);
    expect(band(out, 300, 1200, 3800),
        closeTo(band(base, 300, 1200, 3800) - 12, 0.8));
    expect(band(out, 300, 4200, 5500), closeTo(band(base, 300, 4200, 5500), 0.7));
    expect(band(out, 1000, 1200, 3800), closeTo(band(base, 1000, 1200, 3800), 0.7));
  });

  test("the video's own sound: the range follows trim and speed", () async {
    // 1 s..5 s of the file at double speed = 2 s of video. Silence 0.5 s
    // to 1.0 s of the TIMELINE = 2 s..3 s of the file.
    final p0 = mix(clips: [pic(inMs: 1000, outMs: 5000, speed: 2)], audio: []);
    final e = ProjectEditor(p0, newId: id);
    expect(e.silencePart(const TimelinePart(500, 1000)).ok, isTrue);
    expect(e.project.clips.single.quiet, [const QuietRange(2000, 3000)]);
    final base = await exportAndCheck(p0);
    final out = await exportAndCheck(e.project);
    expect(band(out, 200, 580, 920), lessThan(band(base, 200, 580, 920) - 35));
    expect(band(out, 200, 100, 420), closeTo(band(base, 200, 100, 420), 1));
    expect(band(out, 200, 1100, 1900), closeTo(band(base, 200, 1100, 1900), 1));
    // Trimming the clip later keeps the range on the same sound.
    e.trimClip(e.project.clips.single.id, inMs: 2000);
    final trimmed = await exportAndCheck(e.project);
    // The file's 2 s..3 s is now the first 0.5 s of the video.
    expect(band(trimmed, 200, 60, 420), lessThan(band(base, 200, 100, 420) - 35));
    expect(band(trimmed, 200, 620, 1400), closeTo(band(base, 200, 100, 420), 1));
  });

  test('pieces of one file that share an input keep their own ranges',
      () async {
    // Three pieces of the file with hard cuts (a run: one input).
    final clips = [
      pic(inMs: 0, outMs: 2000, id: 'a'),
      pic(inMs: 2000, outMs: 4000, id: 'b'),
      pic(inMs: 4000, outMs: 6000, id: 'c'),
    ];
    final p0 = mix(clips: clips, audio: []);
    final e = ProjectEditor(p0, newId: id);
    // Across the first cut: 1.5 s .. 2.5 s.
    expect(e.silencePart(const TimelinePart(1500, 2500)).changed, 2);
    final cmd = buildExportCommand(
        project: e.project,
        outputPath: 'o.mp4',
        fonts: fonts,
        workDir: tmp.path,
        options: const ExportOptions());
    expect(cmd.args.where((a) => a == '-i').length, 1,
        reason: 'still one input for the three pieces');
    final base = await exportAndCheck(p0);
    final out = await exportAndCheck(e.project);
    expect(band(out, 200, 1600, 2400), lessThan(band(base, 200, 1600, 2400) - 35));
    expect(band(out, 200, 300, 1400), closeTo(band(base, 200, 300, 1400), 1));
    expect(band(out, 200, 2700, 5500), closeTo(band(base, 200, 2700, 5500), 1));
  });

  test('speed on a part: length, and the linked voice stays in sync',
      () async {
    final e = ProjectEditor(mix(audio: []), newId: id);
    e.addVoice(snd('x', 'beep.wav', 'v'), clipId: 'pic', offsetMs: 0);
    // 2 s..4 s at half speed: that part now takes 4 s, the video 8 s.
    final r = e.speedPart(const TimelinePart(2000, 4000), 0.5);
    expect(r.ok, isTrue);
    expect(r.part, const TimelinePart(2000, 6000));
    expect(e.project.durationMs, 8000);
    expect(e.project.clips.map((c) => c.speed), [1.0, 0.5, 1.0]);
    final out = await exportAndCheck(e.project);
    // The voice's 2.5 s..3.5 s (of the file) is heard at 3 s..5 s.
    final talk = band(out, 1000, 3200, 4800);
    expect(talk, greaterThan(-30));
    expect(band(out, 1000, 800, 2700), lessThan(talk - 30),
        reason: 'not early');
    expect(band(out, 1000, 5300, 7600), lessThan(talk - 30), reason: 'not late');
    // Exactly where it starts and ends (within two frames).
    final x = pcm(out);
    int firstLoud(int from, int to, {bool loud = true}) {
      for (var ms = from; ms < to; ms += 5) {
        if ((bandRms(x, ms, 1000) > 0.05) == loud) return ms;
      }
      return -1;
    }

    expect(firstLoud(2500, 3500), closeTo(3000, 70));
    expect(firstLoud(4500, 5500, loud: false), closeTo(5000, 70));
  });

  test('only when speaking: a two-microphone recording', () async {
    final e = ProjectEditor(mix(audio: []), newId: id);
    final a = e.addVoice(snd('a', 'micA.wav', 'v'),
        clipId: 'pic', offsetMs: 0, trackName: 'A');
    final b = e.addVoice(snd('b', 'micB.wav', 'v'),
        clipId: 'pic', offsetMs: 0, trackName: 'B');
    final trackA = e.project.audio.firstWhere((x) => x.id == a.single).trackId;
    final trackB = e.project.audio.firstWhere((x) => x.id == b.single).trackId;
    expect(trackA, isNot(trackB));
    final peaks = <String, SoundPeaks>{};
    for (final file in ['micA.wav', 'micB.wav']) {
      peaks[f(file)] = (await engine.soundPeaks(f(file)))!;
    }
    SoundPeaks? lookup(String path, int track) => peaks[path];

    expect(projectGates(e.project, lookup), isEmpty, reason: 'off by default');
    // Only microphone A is heard, to measure what it lets through.
    e.setSoundTrack(trackB, muted: true);
    final open = await exportAndCheck(e.project);
    e.setOnlyWhenSpeaking(trackA, on: true);
    final gates = projectGates(e.project, lookup);
    final ranges = gates[a.single]!;
    // ignore: avoid_print
    print('gate of A: $ranges');
    // Closed while B talks (2 s..4 s), open before the talk starts again.
    expect(ranges, hasLength(1));
    expect(ranges.single.fromMs, closeTo(2000 + kGateHoldMs, 60));
    expect(ranges.single.toMs, closeTo(4000 - kGatePreRollMs, 60));
    expect(ranges.single.level, kGateDefaultLevel);
    final gated =
        await exportAndCheck(e.project, options: ExportOptions(gates: gates));
    // B's voice in A's microphone: 18 dB lower. A's own talk: untouched.
    expect(band(gated, 2000, 2400, 3700),
        closeTo(band(open, 2000, 2400, 3700) - 18, 1.2));
    expect(band(gated, 1000, 300, 1900), closeTo(band(open, 1000, 300, 1900), 0.7));
    expect(band(gated, 1000, 4100, 5700), closeTo(band(open, 1000, 4100, 5700), 0.7));
    // The first 100 ms of A's talk after the pause are not clipped.
    final x = pcm(gated), y = pcm(open);
    expect(rmsDb(x, 4000, 4100), closeTo(rmsDb(y, 4000, 4100), 0.8));
    expect(rmsDb(x, 1900, 2000), closeTo(rmsDb(y, 1900, 2000), 0.8),
        reason: 'the end of the talk is not cut');
    // Full silence instead of room sound.
    e.setOnlyWhenSpeaking(trackA, level: 0);
    final silent = await exportAndCheck(e.project,
        options: ExportOptions(gates: projectGates(e.project, lookup)));
    expect(band(silent, 2000, 2400, 3700),
        lessThan(band(open, 2000, 2400, 3700) - 40));
  });
}

/// RMS of the [hz] component in the 20 ms from [ms] (a single-bin DFT).
double bandRms(Float32List x, int ms, int hz) {
  final a = ms * 48, n = 20 * 48;
  if (a + n > x.length) return 0;
  var re = 0.0, im = 0.0;
  for (var i = 0; i < n; i++) {
    final w = 2 * math.pi * hz * i / 48000;
    re += x[a + i] * math.cos(w);
    im += x[a + i] * math.sin(w);
  }
  return math.sqrt(re * re + im * im) * 2 / n / math.sqrt2;
}
