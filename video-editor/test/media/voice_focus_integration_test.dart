// Real exports of the clip sound stages (lib/media/clip_audio.dart): voice
// focus, the choice of audio track and side, and how they combine with
// clean-up, speed and the single-input "runs" of pieces of one file.
// Skipped (with a message) when ffmpeg / ffprobe are not installed.
//
// The fixtures are synthetic: a "voice" of tone bursts at 250 / 500 / 1000 /
// 2500 Hz that is the same on both sides (centre), and "music" with a bass
// in the middle, different chords left and right and independent hiss
// above 7 kHz on each side (spread wide). Margins are wide: the numbers
// must hold for every FFmpeg from 6.1 on.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Only the sound around [hz] (two narrow band-passes).
String band(int hz) =>
    'bandpass=f=$hz:width_type=q:w=20,bandpass=f=$hz:width_type=q:w=20,';

/// Only the left / right channel.
const left = 'pan=mono|c0=c0,';
const right = 'pan=mono|c0=c1,';

/// Loudest sample in dBFS.
double maxVolume(String path) {
  final r = Process.runSync('ffmpeg', [
    '-hide_banner', '-nostats', '-i', path, '-vn', '-af', 'volumedetect', //
    '-f', 'null', '-',
  ]);
  final m = RegExp(r'max_volume: (-?[\d.]+) dB').firstMatch(r.stderr as String);
  expect(m, isNotNull, reason: r.stderr as String);
  return double.parse(m!.group(1)!);
}

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    const video = ['-f', 'lavfi', '-i', 'color=c=gray:s=160x90:r=30:d=6'];
    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // 0..2 s music only, 2..4 s voice only, 4..6 s both.
    const voice = '(0.10*sin(2*PI*250*t)+0.08*sin(2*PI*500*t)'
        '+0.06*sin(2*PI*1000*t)+0.04*sin(2*PI*2500*t))'
        '*(0.6+0.4*sin(2*PI*4*t))*gte(t,2)';
    const bass = '0.12*sin(2*PI*55*t)';
    const music = 'lt(t,2)+gte(t,4)';
    ff([
      ...video,
      '-f', 'lavfi', '-i',
      "aevalsrc='$voice+($bass+0.08*sin(2*PI*330*t)+0.05*sin(2*PI*1500*t))*($music)"
          "|$voice+($bass+0.08*sin(2*PI*523*t)+0.05*sin(2*PI*2300*t))*($music)'"
          ':s=48000:d=6:c=stereo',
      '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.2:c=white:d=6:seed=3',
      '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.2:c=white:d=6:seed=9',
      '-filter_complex',
      '[2:a]highpass=f=7000,highpass=f=7000[nl];[3:a]highpass=f=7000,highpass=f=7000[nr];'
          "[nl][nr]amerge=inputs=2,volume='lt(t,2)+gte(t,4)':eval=frame[n];"
          '[1:a][n]amix=inputs=2:normalize=0[a]',
      '-map', '0:v', '-map', '[a]', ...x264, '-c:a', 'pcm_s16le', '-t', '6',
      f('stereo_mix.mov'),
    ]);
    // The same, but one channel (a phone recording: everything in the
    // middle).
    ff([
      '-i', f('stereo_mix.mov'), '-map', '0:v', '-map', '0:a', '-c:v', 'copy',
      '-af', 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1',
      '-c:a', 'pcm_s16le', f('mono_mix.mov'),
    ]);
    // Stereo: 440 Hz on the left, 1000 Hz on the right.
    ff([
      ...video,
      '-f', 'lavfi', '-i',
      "aevalsrc='0.3*sin(2*PI*440*t)|0.3*sin(2*PI*1000*t)':s=48000:d=6:c=stereo",
      '-map', '0:v', '-map', '1:a', ...x264, '-c:a', 'aac', '-t', '6',
      f('sides.mp4'),
    ]);
    // Two audio streams: #1 mono 440 Hz; #2 stereo, 1000 Hz on the left
    // (silent from 1 to 2 s) and 660 Hz on the right.
    ff([
      ...video,
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=6',
      '-f', 'lavfi', '-i',
      "aevalsrc='0.3*sin(2*PI*1000*t)*not(between(t,1,2))|0.3*sin(2*PI*660*t)'"
          ':s=48000:d=6:c=stereo',
      '-map', '0:v', '-map', '1:a', '-map', '2:a', ...x264, '-c:a', 'aac',
      '-t', '6', f('tracks.mp4'),
    ]);
  });
  tearDownAll(tearDownMedia);

  Clip from(String file, {int outMs = 6000, List<int> streams = const [2]}) =>
      clip(file, 160, 90, outMs: outMs).copyWith(audioStreams: streams);

  group('probe', () {
    test('reports the channels of every audio stream', () async {
      expect((await engine.probe(f('tracks.mp4'))).audioStreams, [1, 2]);
      expect((await engine.probe(f('sides.mp4'))).audioStreams, [2]);
      expect((await engine.probe(f('port.mp4'))).audioStreams, isEmpty);
    });
  });

  group('voice focus', () {
    // Levels of the music-only (0.3..1.7 s) and voice-only (2.3..3.7 s)
    // stretches; voice band = its 1000 Hz partial.
    ({double music, double voice, double voiceBand, double hiss}) levels(String out) => (
          music: meanVolume(out, fromMs: 300, toMs: 1700),
          voice: meanVolume(out, fromMs: 2300, toMs: 3700),
          voiceBand: meanVolume(out, fromMs: 2300, toMs: 3700, filter: band(1000)),
          hiss: meanVolume(out, fromMs: 300, toMs: 1700, filter: 'highpass=f=9000,highpass=f=9000,'),
        );

    test('stereo mix: music drops, the voice stays; length and timing kept', () async {
      final rawOut = await exportAndCheck(proj([from('stereo_mix.mov')]),
          width: 160, height: 90);
      final raw = levels(rawOut);
      final half = levels(await exportAndCheck(
          proj([from('stereo_mix.mov').copyWith(voiceFocus: 0.5)]),
          width: 160, height: 90));
      final fullOut = await exportAndCheck(
          proj([from('stereo_mix.mov').copyWith(voiceFocus: 1)]),
          width: 160, height: 90);
      final full = levels(fullOut);
      // ignore: avoid_print
      print('VOICE FOCUS stereo mix: music-only ${(half.music - raw.music).toStringAsFixed(1)} dB at 50 %, '
          '${(full.music - raw.music).toStringAsFixed(1)} dB at 100 %; '
          'voice-only ${(half.voice - raw.voice).toStringAsFixed(1)} / ${(full.voice - raw.voice).toStringAsFixed(1)} dB, '
          '1 kHz part ${(half.voiceBand - raw.voiceBand).toStringAsFixed(1)} / ${(full.voiceBand - raw.voiceBand).toStringAsFixed(1)} dB; '
          'hiss ${(half.hiss - raw.hiss).toStringAsFixed(1)} / ${(full.hiss - raw.hiss).toStringAsFixed(1)} dB');
      expect(half.music, lessThan(raw.music - 3));
      expect(full.music, lessThan(half.music - 1));
      expect(full.music, lessThan(raw.music - 6));
      expect(full.hiss, lessThan(raw.hiss - 10));
      // The voice (in the middle) keeps its level.
      expect(half.voiceBand, closeTo(raw.voiceBand, 1.5));
      expect(full.voiceBand, closeTo(raw.voiceBand, 1.5));
      expect(full.voice, greaterThan(raw.voice - 3));
      // In sync: the voice starts at 2.0 s, not 32 ms later
      // (dialoguenhance's delay is taken out).
      // The centre stage takes about 0.2 s to settle after silence: an
      // onset comes out up to about 2 dB softer at first. A delay of 32 ms
      // would leave the first window nearly silent.
      double at(String out, int from, int to) =>
          meanVolume(out, fromMs: from, toMs: to, filter: band(1000));
      final before = at(fullOut, 1960, 1990);
      expect(at(fullOut, 2005, 2030), greaterThan(before + 15));
      expect(at(fullOut, 2005, 2030), closeTo(at(rawOut, 2005, 2030), 5));
      expect(at(fullOut, 2050, 2100), closeTo(at(rawOut, 2050, 2100), 3));
      expect(at(fullOut, 2250, 2500), closeTo(at(rawOut, 2250, 2500), 1.5));
      // No overload.
      expect(maxVolume(fullOut), lessThan(0));
    });

    test('one-channel (phone) recording: the voice passes, music drops less', () async {
      final raw = levels(await exportAndCheck(proj([from('mono_mix.mov')]),
          width: 160, height: 90));
      final full = levels(await exportAndCheck(
          proj([from('mono_mix.mov').copyWith(voiceFocus: 1)]),
          width: 160, height: 90));
      // ignore: avoid_print
      print('VOICE FOCUS mono mix 100 %: music-only ${(full.music - raw.music).toStringAsFixed(1)} dB, '
          'voice-only ${(full.voice - raw.voice).toStringAsFixed(1)} dB, '
          '1 kHz part ${(full.voiceBand - raw.voiceBand).toStringAsFixed(1)} dB');
      expect(full.voiceBand, closeTo(raw.voiceBand, 1.5));
      expect(full.music, lessThan(raw.music - 1));
      expect(full.hiss, lessThan(raw.hiss - 10));
    });

    test('after clean-up, with speed, as a run of pieces of one file', () async {
      Clip piece(int inMs, int outMs) => from('stereo_mix.mov')
          .copyWith(inMs: inMs, outMs: outMs, voiceFocus: 0.75, denoise: true, speed: 1.5);
      final project = proj([piece(0, 1500), piece(2200, 3800), piece(4200, 6000)]);
      final cmd = buildExportCommand(
          project: project, outputPath: '/o.mp4', fonts: fonts, workDir: '/w');
      // Identical settings: one input for the three pieces.
      expect(cmd.args.where((a) => a == '-i'), hasLength(1));
      expect(cmd.filterGraph, contains('dynaudnorm'));
      expect(cmd.filterGraph.indexOf('dynaudnorm'),
          lessThan(cmd.filterGraph.indexOf('dialoguenhance')));
      final out = await exportAndCheck(project, width: 160, height: 90);
      // Second piece (voice) is on the timeline from 1000 to ~2067 ms.
      // (sped up, the 1000 Hz part keeps its pitch).
      expect(meanVolume(out, fromMs: 1200, toMs: 1900, filter: band(1000)),
          greaterThan(-40));
      expect(maxVolume(out), lessThan(0));
    });
  });

  group('sound from', () {
    test('left only / right only put that side on both', () async {
      final l = await exportAndCheck(
          proj([from('sides.mp4').copyWith(audioChannel: AudioChannel.left)]),
          width: 160, height: 90);
      final r = await exportAndCheck(
          proj([from('sides.mp4').copyWith(audioChannel: AudioChannel.right)]),
          width: 160, height: 90);
      final both = await exportAndCheck(proj([from('sides.mp4')]), width: 160, height: 90);
      double lv(String out, String side, int hz) =>
          meanVolume(out, fromMs: 500, toMs: 5500, filter: '$side${band(hz)}');
      for (final side in [left, right]) {
        expect(lv(l, side, 440), closeTo(lv(both, left, 440), 1.5));
        expect(lv(l, side, 1000), lessThan(lv(both, right, 1000) - 40));
        expect(lv(r, side, 1000), closeTo(lv(both, right, 1000), 1.5));
        expect(lv(r, side, 440), lessThan(lv(both, left, 440) - 40));
      }
    });

    test('a second audio stream, and one side of it', () async {
      final first = await exportAndCheck(proj([from('tracks.mp4', streams: [1, 2])]),
          width: 160, height: 90);
      final second = await exportAndCheck(
          proj([from('tracks.mp4', streams: [1, 2]).copyWith(audioTrack: 1)]),
          width: 160, height: 90);
      final secondRight = await exportAndCheck(
          proj([
            from('tracks.mp4', streams: [1, 2])
                .copyWith(audioTrack: 1, audioChannel: AudioChannel.right)
          ]),
          width: 160, height: 90);
      double lv(String out, int hz, [String side = left]) =>
          meanVolume(out, fromMs: 2500, toMs: 5500, filter: '$side${band(hz)}');
      expect(lv(first, 440), greaterThan(-40));
      expect(lv(first, 1000), lessThan(lv(second, 1000) - 30));
      expect(lv(second, 440), lessThan(lv(first, 440) - 30));
      expect(lv(second, 1000), greaterThan(-40));
      expect(lv(second, 660, right), greaterThan(-40));
      for (final side in [left, right]) {
        expect(lv(secondRight, 660, side), greaterThan(-40));
        expect(lv(secondRight, 1000, side), lessThan(lv(second, 1000) - 40));
      }
      // A track the file is not known to have falls back to the first.
      final unknown = await exportAndCheck(
          proj([from('tracks.mp4', streams: const []).copyWith(audioTrack: 1)]),
          width: 160, height: 90);
      expect(lv(unknown, 440), greaterThan(-40));
    });

    test('remove silences listens to the chosen track and side', () async {
      final path = f('tracks.mp4');
      expect(await engine.detectSilence(path), isEmpty);
      expect(await engine.detectSilence(path, audioTrack: 1), isEmpty);
      final gaps = await engine.detectSilence(path,
          audioTrack: 1, channel: AudioChannel.left, minSilenceMs: 500);
      expect(gaps, hasLength(1));
      expect(gaps.single.startMs, closeTo(1000, 120));
      expect(gaps.single.endMs, closeTo(2000, 120));
    });
  });
}
