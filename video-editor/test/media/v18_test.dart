// 1.8 export parts: looped music (command + a real FFmpeg export).

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _fonts = FontPaths(regular: '/f/R.ttf', bold: '/f/B.ttf');

Clip _v(String path, int ms) => Clip(
    id: 'v',
    type: ClipType.video,
    path: path,
    sourceDurationMs: ms,
    inMs: 0,
    outMs: ms,
    width: 640,
    height: 360,
    hasAudio: false);

AudioClip _music(String path, {int source = 2000, int loopMs = 0}) => AudioClip(
    id: 'm',
    path: path,
    sourceDurationMs: source,
    startMs: 0,
    inMs: 0,
    outMs: source,
    loopMs: loopMs);

Project _p(Clip c, AudioClip a) => Project(
    id: 'p',
    name: 'n',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    clips: [c],
    audio: [a]);

void main() {
  test('a looped sound is mixed as its repeats, cross-faded', () {
    final g = buildExportCommand(
            project: _p(_v('/m/v.mp4', 5000),
                _music('/m/s.mp3', loopMs: 5000)),
            outputPath: '/o/o.mp4',
            fonts: _fonts,
            workDir: '/w')
        .filterGraph;
    // 2 s passes, 0.3 s cross-fade: starts at 0, 1.7, 3.4 s.
    expect(g, contains('adelay=delays=1700:all=1'));
    expect(g, contains('adelay=delays=3400:all=1'));
    expect(g, contains('afade=t=in:st=0:d=0.300'));
    expect(g, contains('afade=t=out:st=1.700:d=0.300'));
    expect(g, contains('amix=inputs=3'));
  });

  group('real export', () {
    if (!ffmpegOk) {
      test('needs ffmpeg', () {}, skip: 'ffmpeg not found');
      return;
    }
    setUpAll(setUpMedia);
    tearDownAll(tearDownMedia);

    test('looped music fills the video without a gap at the repeats',
        () async {
      ff(['-f', 'lavfi', '-i', 'color=c=gray:s=640x360:r=30:d=6',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        f('v.mp4')]);
      // A steady tone, 2 s.
      ff(['-f', 'lavfi', '-i', 'sine=f=330:r=48000:d=2', '-c:a', 'aac',
        f('s.m4a')]);
      final out = await exportAndCheck(_p(_v(f('v.mp4'), 6000),
          _music(f('s.m4a'), loopMs: 6000)));
      final mid = meanVolume(out, fromMs: 500, toMs: 1500);
      // Around the repeats (1.7-2.0 s and 3.4-3.7 s): no drop out.
      final seam1 = meanVolume(out, fromMs: 1650, toMs: 2050);
      final seam2 = meanVolume(out, fromMs: 3350, toMs: 3750);
      final late = meanVolume(out, fromMs: 4500, toMs: 5000);
      expect(mid, greaterThan(-30));
      expect(seam1, greaterThan(mid - 4));
      expect(seam2, greaterThan(mid - 4));
      expect(late, closeTo(mid, 2));
      expect(File(out).existsSync(), isTrue);
    });
  });
}
