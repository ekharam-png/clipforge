// The preview's music fades over time, and what happens when mpv refuses
// the sound filters of a clip.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/playback/media_kit_backend.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

/// A music player that records the level it is given and when.
class _LevelPlayer extends FakePlayer {
  _LevelPlayer(this.now);
  final int Function() now;
  final List<(int, double)> levels = [];

  @override
  Future<void> setVolume(double volume) async {
    levels.add((now(), volume));
    await super.setVolume(volume);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _music = AudioClip(
  id: 'm',
  path: '/m.mp3',
  sourceDurationMs: 60000,
  startMs: 1000,
  inMs: 0,
  outMs: 10000, // heard from 1 s to 11 s
  volume: 0.8,
  fadeInMs: 2000,
  fadeOutMs: 3000,
);

Project _project(Clip clip) => Project(
      id: 'p',
      name: 'p',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: [clip],
      audio: const [_music],
    );

void main() {
  test('the gain curve across a fade, and mpv volume that gives it', () {
    double g(int t) => PlaybackController.audioGain(_music, t);
    var last = -1.0;
    // Fade-in, 1 s .. 3 s: linear from 0 to 0.8.
    for (var t = 1000; t <= 3000; t += 50) {
      final v = g(t);
      expect(v, closeTo(0.8 * (t - 1000) / 2000, 1e-9));
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
    // Full level in between.
    for (var t = 3000; t <= 8000; t += 250) {
      expect(g(t), closeTo(0.8, 1e-9));
    }
    // Fade-out, 8 s .. 11 s: linear down to 0.
    for (var t = 8000; t < 11000; t += 50) {
      final v = g(t);
      expect(v, closeTo(0.8 * (11000 - t) / 3000, 1e-9));
      expect(v, lessThanOrEqualTo(last));
      last = v;
    }
    expect(g(11000), 0);
    // mpv multiplies the samples by (volume / 100)^3: the volume the
    // player is given turns back into exactly the gain.
    for (var t = 1000; t <= 11000; t += 125) {
      final mpv = mpvVolumeFor(g(t));
      final amplitude = (mpv / 100) * (mpv / 100) * (mpv / 100);
      expect(amplitude, closeTo(g(t), 1e-9), reason: 't=$t');
      expect(mpv, lessThanOrEqualTo(130)); // mpv's volume-max
    }
  });

  Future<List<(int, double)>> play(Clip clip, {bool reportVideo = false}) async {
    late PlaybackController c;
    final music = _LevelPlayer(() => c.positionMs);
    final video = FakePlayer();
    c = PlaybackController(
      project: _project(clip),
      video: video,
      createAudioPlayer: () => music,
      fileExists: (_) => true,
    );
    addTearDown(c.dispose);
    await _settle();
    c.play();
    await _settle();
    // 60 frames a second for 12 s; a video player reports its position
    // once per 30 fps frame.
    for (var t = 16; t <= 12000; t += 16) {
      if (reportVideo && t % 32 == 0) video.emitPosition(t);
      c.tick(16);
      await _settle();
    }
    await _settle();
    return music.levels;
  }

  void checkFollowsTheCurve(List<(int, double)> levels) {
    // Each level set is the curve's level at that moment (within the
    // 0.01 step the controller allows itself).
    for (final (t, v) in levels) {
      expect(v, closeTo(PlaybackController.audioGain(_music, t), 0.011),
          reason: 'at $t ms');
    }
    final fadeIn = levels.where((e) => e.$1 > 1000 && e.$1 < 3000).toList();
    final fadeOut = levels.where((e) => e.$1 > 8000 && e.$1 < 11000).toList();
    // Updated all along the fades, not only at their ends: about every
    // 1 % of the level (0.8 over 2 s = a step every ~25 ms).
    expect(fadeIn.length, greaterThan(40));
    expect(fadeOut.length, greaterThan(40));
    for (var i = 1; i < fadeIn.length; i++) {
      expect(fadeIn[i].$2, greaterThan(fadeIn[i - 1].$2));
      expect(fadeIn[i].$1 - fadeIn[i - 1].$1, lessThanOrEqualTo(100));
    }
    for (var i = 1; i < fadeOut.length; i++) {
      expect(fadeOut[i].$2, lessThan(fadeOut[i - 1].$2));
      expect(fadeOut[i].$1 - fadeOut[i - 1].$1, lessThanOrEqualTo(100));
    }
    expect(levels.map((e) => e.$2).reduce((a, b) => a > b ? a : b),
        closeTo(0.8, 0.011));
    expect(fadeOut.last.$2, lessThan(0.03));
  }

  test('during playback over a photo the music level follows its fades',
      () async {
    final levels = await play(const Clip(
      id: 'p1', type: ClipType.photo, path: '/p.jpg', sourceDurationMs: 0,
      inMs: 0, outMs: 12000, width: 100, height: 100, hasAudio: false,
    ));
    checkFollowsTheCurve(levels);
  });

  test('during playback over a video the music level follows its fades',
      () async {
    final levels = await play(
        const Clip(
          id: 'v1', type: ClipType.video, path: '/v.mp4',
          sourceDurationMs: 20000, inMs: 0, outMs: 12000,
          width: 100, height: 100,
        ),
        reportVideo: true);
    checkFollowsTheCurve(levels);
  });

  group('a sound filter mpv refused', () {
    const af = 'format=format=floatp,lavfi=[equalizer=f=3000:t=o:w=1.5:g=3]';
    test('is recognised by the silent audio track', () {
      // What mpv 0.37 reports after "Audio filter initialized failed!".
      expect(
          filterSilencedSound(
              filter: af, aid: 'no', aidOption: 'auto',
              trackTypes: ['video', 'audio']),
          isTrue);
      expect(
          filterSilencedSound(
              filter: af, aid: 'no', aidOption: '2',
              trackTypes: ['video', 'audio', 'audio']),
          isTrue);
    });

    test('is not blamed for other silences', () {
      // Sound playing.
      expect(
          filterSilencedSound(
              filter: af, aid: '1', aidOption: 'auto',
              trackTypes: ['video', 'audio']),
          isFalse);
      // No filter set.
      expect(
          filterSilencedSound(
              filter: '', aid: 'no', aidOption: 'auto',
              trackTypes: ['video', 'audio']),
          isFalse);
      // A file without sound.
      expect(
          filterSilencedSound(
              filter: af, aid: 'no', aidOption: 'auto',
              trackTypes: ['video']),
          isFalse);
      // The track choice turned the option off (a track the file lacks).
      expect(
          filterSilencedSound(
              filter: af, aid: 'no', aidOption: 'no',
              trackTypes: ['video', 'audio']),
          isFalse);
    });
  });
}
