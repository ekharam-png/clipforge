// The 15-second sound sample: which part of the clip, and the two projects.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/editor/sound_sample.dart';
import 'package:flutter_test/flutter_test.dart';

Clip clip(String id, int inMs, int outMs, {double speed = 1}) => Clip(
    id: id, type: ClipType.video, path: '/m/$id.mp4', sourceDurationMs: 600000,
    inMs: inMs, outMs: outMs, width: 640, height: 360, speed: speed,
    denoise: true, voiceFocus: 0.8, audioTrack: 1,
    audioChannel: AudioChannel.left, audioStreams: const [2, 2],
    transition: TransitionType.crossfade);

Project proj(List<Clip> clips) => Project(
    id: 'p', name: 'n', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    clips: clips, audio: const [
      AudioClip(id: 'm', path: '/m/song.mp3', sourceDurationMs: 9000,
          startMs: 0, inMs: 0, outMs: 9000),
    ]);

void main() {
  test('5 s before and 10 s after the playhead, inside the trim range', () {
    final a = clip('a', 10000, 70000);
    final p = proj([a]);
    expect(soundSampleRange(p, a, 30000), (inMs: 35000, outMs: 50000));
    expect(soundSampleRange(p, a, 1000), (inMs: 10000, outMs: 25000));
    expect(soundSampleRange(p, a, 59000), (inMs: 55000, outMs: 70000));
    // Playhead in another clip: from the clip's start.
    final b = clip('b', 0, 8000);
    final p2 = proj([b, a]);
    expect(soundSampleRange(p2, b, 20000), (inMs: 0, outMs: 8000));
  });

  test('speed: 15 s of timeline', () {
    final a = clip('a', 0, 100000, speed: 2);
    expect(soundSampleRange(proj([a]), a, 20000), (inMs: 30000, outMs: 60000));
  });

  test('the projects: only the clip, with and without its sound changes', () {
    final a = clip('a', 0, 60000);
    final s = soundSampleProjects(proj([a]), a, (inMs: 1000, outMs: 16000));
    for (final p in [s.processed, s.original]) {
      expect(p.clips, hasLength(1));
      expect(p.audio, isEmpty);
      expect(p.titles, isEmpty);
      expect(p.durationMs, 15000);
      expect(p.clips.single.transition, TransitionType.none);
      expect(p.clips.single.audioTrack, 1);
    }
    final c = s.processed.clips.single;
    expect([c.denoise, c.voiceFocus, c.audioChannel], [true, 0.8, AudioChannel.left]);
    final o = s.original.clips.single;
    expect([o.denoise, o.voiceFocus, o.audioChannel], [false, 0, AudioChannel.both]);
  });
}
