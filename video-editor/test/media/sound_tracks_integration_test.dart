// Real exports of sound tracks (FFmpeg on PATH): three tracks mixed, mute,
// solo and track volume, "lower under speech" per track keyed by a speech
// track, separated sound with clean-up read from its processed file, the
// adaptive "Remove silences" threshold on noisy recordings, and the video
// size setting. Skipped (with a message) without ffmpeg / ffprobe.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/silence_levels.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Float32List pcm(String path) {
  final r = Process.runSync(
      'ffmpeg',
      ['-v', 'error', '-i', path, '-vn', '-ac', '2', '-ar', '48000', '-f', 'f32le', '-'],
      stdoutEncoding: null);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final bytes = Uint8List.fromList(r.stdout as List<int>);
  return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
}

double rmsDb(Float32List x, int fromMs, int toMs) {
  var s = 0.0;
  final a = fromMs * 48 * 2, b = math.min(x.length, toMs * 48 * 2);
  for (var i = a; i < b; i++) {
    s += x[i] * x[i];
  }
  return 10 * math.log(s / math.max(1, b - a) + 1e-20) / math.ln10;
}

/// Level of the band around [hz] between [fromMs] and [toMs].
double band(String path, int hz, int fromMs, int toMs) => meanVolume(path,
    fromMs: fromMs,
    toMs: toMs,
    filter: 'bandpass=f=$hz:width_type=q:w=8,bandpass=f=$hz:width_type=q:w=8,');

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    // 6 s picture with a quiet 200 Hz tone as its own sound.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=6',
      '-f', 'lavfi', '-i', 'sine=f=200:r=48000:d=6',
      '-filter_complex', '[1:a]volume=0.4[a]', '-map', '0:v', '-map', '[a]',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-t', '6', f('pic.mp4'),
    ]);
    // "Voice": 1 kHz in the first 3 s only; "music": 300 Hz; "effects":
    // 2.5 kHz. 6 s each, WAV.
    ff(['-f', 'lavfi', '-i',
        "aevalsrc='0.3*sin(2*PI*1000*t)*lt(t,3)':s=48000:d=6", f('voice.wav')]);
    ff(['-f', 'lavfi', '-i', "aevalsrc='0.2*sin(2*PI*300*t)':s=48000:d=6", f('music.wav')]);
    ff(['-f', 'lavfi', '-i', "aevalsrc='0.2*sin(2*PI*2500*t)':s=48000:d=6", f('fx.wav')]);
  });
  tearDownAll(tearDownMedia);

  Clip pic() => Clip(
        id: 'pic',
        type: ClipType.video,
        path: f('pic.mp4'),
        sourceDurationMs: 6000,
        inMs: 0,
        outMs: 6000,
        width: 320,
        height: 180,
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

  Project mix({
    SoundTrack voice = const SoundTrack(id: 'v', name: 'Voice', speech: true),
    SoundTrack music = const SoundTrack(id: 'm', name: 'Music'),
    SoundTrack fx = const SoundTrack(id: 'e', name: 'Effects'),
    SoundTrack video = SoundTrack.video,
  }) =>
      Project(
        id: 'p',
        name: 'p',
        createdAt: t0,
        updatedAt: t0,
        clips: [pic()],
        tracks: [voice, music, fx],
        videoSound: video,
        audio: [
          snd('vo', 'voice.wav', 'v'),
          snd('mu', 'music.wav', 'm'),
          snd('ef', 'fx.wav', 'e'),
        ],
      );

  test('three tracks are mixed; mute, solo and track volume', () async {
    final all = await exportAndCheck(mix());
    final l1k = band(all, 1000, 500, 2500);
    final l300 = band(all, 300, 500, 5500);
    final l2k5 = band(all, 2500, 500, 5500);
    final l200 = band(all, 200, 500, 5500);
    // ignore: avoid_print
    print('bands: 1k $l1k, 300 $l300, 2k5 $l2k5, 200 $l200');
    for (final l in [l1k, l300, l2k5, l200]) {
      expect(l, greaterThan(-45), reason: 'every sound is heard ($l)');
    }

    final muted = await exportAndCheck(
        mix(music: const SoundTrack(id: 'm', name: 'Music', muted: true)));
    expect(band(muted, 300, 500, 5500), lessThan(l300 - 12));
    expect(band(muted, 2500, 500, 5500), closeTo(l2k5, 1));

    final solo = await exportAndCheck(
        mix(fx: const SoundTrack(id: 'e', name: 'Effects', solo: true)));
    expect(band(solo, 2500, 500, 5500), closeTo(l2k5, 1));
    expect(band(solo, 1000, 500, 2500), lessThan(l1k - 12));
    expect(band(solo, 200, 500, 5500), lessThan(l200 - 12),
        reason: 'the video sound is not solo');

    final half = await exportAndCheck(
        mix(voice: const SoundTrack(id: 'v', name: 'Voice', speech: true, volume: 0.5)));
    expect(band(half, 1000, 500, 2500), closeTo(l1k - 6.02, 1));

    final noVideo =
        await exportAndCheck(mix(video: SoundTrack.video.copyWith(muted: true)));
    expect(band(noVideo, 200, 500, 5500), lessThan(l200 - 12));
    expect(band(noVideo, 300, 500, 5500), closeTo(l300, 1));
  });

  test('lower under speech: per track, keyed by the voice track', () async {
    final p = mix(
      music: const SoundTrack(id: 'm', name: 'Music', duck: true),
      video: SoundTrack.video.copyWith(muted: true),
    );
    final out = await exportAndCheck(p);
    final during = band(out, 300, 800, 2800);
    final after = band(out, 300, 3800, 5800);
    // ignore: avoid_print
    print('music under the voice ${during.toStringAsFixed(1)} dB, '
        'after it ${after.toStringAsFixed(1)} dB');
    expect(after - during, greaterThan(4), reason: 'music lowered under the voice');
    // The effects track does not duck.
    expect(band(out, 2500, 800, 2800), closeTo(band(out, 2500, 3800, 5800), 1));
  });

  group('separated sound', () {
    setUpAll(() {
      // A noisy "talk": tone bursts over pink noise, as a camera file.
      const voice = '(0.12*sin(2*PI*250*t)+0.08*sin(2*PI*1000*t))'
          '*gt(sin(2*PI*0.4*t),-0.3)';
      ff([
        '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=8',
        '-f', 'lavfi', '-i', "aevalsrc='$voice|$voice':s=48000:d=8:c=stereo",
        '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.02:c=pink:d=8:seed=3',
        '-filter_complex', '[1:a][2:a]amix=inputs=2:normalize=0[a]',
        '-map', '0:v', '-map', '[a]',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'pcm_s16le', '-t', '8', f('talk.mov'),
      ]);
    });

    Project talkProject({double speed = 1}) => Project(
          id: 'p',
          name: 'p',
          createdAt: t0,
          updatedAt: t0,
          clips: [
            Clip(
              id: 'c',
              type: ClipType.video,
              path: f('talk.mov'),
              sourceDurationMs: 8000,
              inMs: 1000,
              outMs: 7000,
              width: 320,
              height: 180,
              speed: speed,
              denoise: true,
              audioStreams: const [2],
            ),
          ],
        );

    test('sounds like the clip did; clean-up read from the processed file',
        () async {
      final before = talkProject();
      final e = ProjectEditor(before);
      final id = e.separateSound('c')!;
      final p = e.project;
      final a = p.audio.firstWhere((a) => a.id == id);
      final original = pcm(await exportAndCheck(before));
      final separated = pcm(await exportAndCheck(p));
      expect(rmsDb(separated, 1000, 5500),
          closeTo(rmsDb(original, 1000, 5500), 0.5));

      // Instant sound processing: the sound clip shares the clip's file.
      final processed = f('processed/snd_sep.flac');
      await engine.renderClipSound(a.soundClip, processed).done;
      final cmd = buildExportCommand(
          project: p,
          outputPath: f('x.mp4'),
          fonts: fonts,
          workDir: tmp.path,
          options: ExportOptions(processedSound: {id: processed}));
      expect(cmd.filterGraph, isNot(contains('afftdn')));
      final reused = pcm(await exportAndCheck(p,
          options: ExportOptions(processedSound: {id: processed})));
      // Away from the start, where the normal chain's clean-up starts cold.
      expect(rmsDb(reused, 1500, 5500), closeTo(rmsDb(separated, 1500, 5500), 0.5));
    });

    test('a sped-up clip: same length and level as the clip', () async {
      final before = talkProject(speed: 1.5);
      final e = ProjectEditor(before);
      e.separateSound('c');
      final p = e.project;
      expect(p.audio.single.endMs, p.durationMs);
      final original = pcm(await exportAndCheck(before));
      final separated = pcm(await exportAndCheck(p));
      expect(rmsDb(separated, 500, 3500), closeTo(rmsDb(original, 500, 3500), 0.6));
    });

    test('after Remove silences the sound pieces share one input', () async {
      final e = ProjectEditor(talkProject());
      e.separateSound('c');
      e.removeSourceRanges('c', [
        (startMs: 2000, endMs: 2600),
        (startMs: 4500, endMs: 5000),
      ]);
      final p = e.project;
      expect(p.audio.length, 3);
      final cmd = buildExportCommand(
          project: p, outputPath: f('y.mp4'), fonts: fonts, workDir: tmp.path);
      expect(cmd.args.where((a) => a == f('talk.mov')).length, 2);
      await exportAndCheck(p);
    });
  });

  group('adaptive silence threshold', () {
    // Speech-like bursts (1.2 s on, 1.4 s off) over steady noise whose
    // level is the "noise floor" of the recording.
    void makeNoisy(String name, double noiseAmp) {
      const burst = '(0.25*sin(2*PI*220*t)+0.15*sin(2*PI*660*t)'
          '+0.1*sin(2*PI*1700*t))*(0.7+0.3*sin(2*PI*4*t))'
          '*lt(mod(t,2.6),1.2)';
      ff([
        '-f', 'lavfi', '-i', "aevalsrc='$burst':s=48000:d=13",
        '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=$noiseAmp:c=white:d=13:seed=7',
        '-filter_complex', '[0:a][1:a]amix=inputs=2:normalize=0',
        f(name),
      ]);
    }

    setUpAll(() {
      makeNoisy('floor45.wav', 0.01); // floor about -45 dB
      makeNoisy('floor30.wav', 0.056); // floor about -30 dB
    });

    test('finds the gaps at a -45 dB and at a -30 dB noise floor', () async {
      for (final name in ['floor45.wav', 'floor30.wav']) {
        final job = engine.startSilenceDetection(f(name), minSilenceMs: 700);
        final found = await job.result;
        final l = job.levels!;
        // ignore: avoid_print
        print('$name: floor ${l.noiseFloorDb.toStringAsFixed(1)} dB, loud '
            '${l.loudDb.toStringAsFixed(1)} dB, threshold '
            '${l.autoThresholdDb.toStringAsFixed(1)} dB, ${found.length} gaps');
        expect(l.noiseFloorDb,
            closeTo(name == 'floor45.wav' ? -45 : -30, 2));
        // Gaps at 1.2..2.6, 3.8..5.2, ... : 5 in 13 s.
        expect(found.length, 5, reason: '$name $found');
        expect(found.first.startMs, closeTo(1200, 80));
        expect(found.first.endMs, closeTo(2600, 80));
        expect(await engine.detectSilence(f(name)), found);
      }
      // The old fixed -35 dB finds nothing on the noisy one.
      expect(await engine.detectSilence(f('floor30.wav'), thresholdDb: -35),
          isEmpty);
    });

    test('sensitivity moves the threshold without listening again', () async {
      final job = engine.startSilenceDetection(f('floor30.wav'));
      await job.result;
      final l = job.levels!;
      expect(l.thresholdFor(SilenceSensitivity.moreCuts),
          l.autoThresholdDb + kSensitivityStepDb);
      expect(l.thresholdFor(SilenceSensitivity.fewerCuts),
          l.autoThresholdDb - kSensitivityStepDb);
      // Far below the floor nothing is quiet enough.
      expect(l.silences(thresholdDb: l.noiseFloorDb - 10), isEmpty);
    });

    test('a steady tone has no quiet parts', () async {
      final job = engine.startSilenceDetection(f('music.wav'));
      expect(await job.result, isEmpty);
      expect(job.levels!.hasQuietParts, isFalse);
    });
  });

  test('video size: a small phone clip exported at 1080p', () async {
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=464x824:r=30:d=1',
      '-f', 'lavfi', '-i', 'sine=f=440:d=1',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-shortest', f('whatsapp.mp4'),
    ]);
    final p = Project(
      id: 'p',
      name: 'p',
      createdAt: t0,
      updatedAt: t0,
      videoSize: VideoSize.p1080,
      clips: [
        Clip(
          id: 'w',
          type: ClipType.video,
          path: f('whatsapp.mp4'),
          sourceDurationMs: 1000,
          inMs: 0,
          outMs: 1000,
          width: 464,
          height: 824,
        ),
      ],
    );
    expect(p.canvasSize, (width: 1080, height: 1918));
    await exportAndCheck(p, width: 1080, height: 1918);
    await exportAndCheck(p.copyWith(videoSize: VideoSize.matchFirstClip),
        width: 464, height: 824);
  });
}
