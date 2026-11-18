// The preview playing a clip's processed sound (instant sound processing):
// the video player goes quiet and a sound player plays the processed file
// in step with the picture.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

Clip talk(String id, int inMs, int outMs,
        {String path = '/a.mp4',
        double speed = 1,
        double volume = 1,
        TransitionType transition = TransitionType.none}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: 60000,
      inMs: inMs,
      outMs: outMs,
      width: 1920,
      height: 1080,
      speed: speed,
      volume: volume,
      denoise: true,
      transition: transition,
      transitionMs: 1000,
    );

Project project(List<Clip> clips) => Project(
      id: 'p',
      name: 'Test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: clips,
    );

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePlayer video;
  late List<FakePlayer> videos;
  late List<FakePlayer> sounds;

  /// Processed files that are "ready", by source path.
  late Map<String, String> ready;

  PlaybackController make(Project p) {
    video = FakePlayer(name: 'video 0');
    videos = [video];
    sounds = [];
    ready = {};
    final c = PlaybackController(
      project: p,
      video: video,
      createVideoPlayer: () {
        final b = FakePlayer(name: 'video ${videos.length}');
        videos.add(b);
        return b;
      },
      createAudioPlayer: () {
        final a = FakePlayer(name: 'sound ${sounds.length}');
        sounds.add(a);
        return a;
      },
      fileExists: (_) => true,
    );
    c.processedSound = (clip) => ready[clip.path];
    addTearDown(c.dispose);
    return c;
  }

  test('without a processed file the video plays its own sound', () async {
    final c = make(project([talk('a', 2000, 6000)]));
    await settle();
    c.play();
    await settle();
    expect(video.volume, 1);
    expect(video.audioFilter, contains('equalizer'), reason: 'light live version');
    expect(sounds, isEmpty);
    expect(c.playingProcessedSound, isNull);
  });

  test('once ready: a sound player waits at the playhead, the video goes quiet',
      () async {
    final c = make(project([talk('a', 2000, 6000)]));
    c.seek(1000);
    await settle();
    expect(video.volume, 1);
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    await settle();
    expect(sounds, hasLength(1));
    final s = sounds.single;
    // Source timing: 1 s into a clip that starts 2 s into the file.
    expect(s.log, contains('open /cache/a.flac@3000 paused'));
    expect(video.volume, 0, reason: 'muted once the sound player has the file');
    expect(c.playingProcessedSound, '/cache/a.flac');

    c.play();
    await settle();
    expect(s.playing, isTrue);
    expect(s.log.last, 'play');
    expect(s.log, contains('seek 3000'));
    expect(video.volume, 0);
  });

  test('speed becomes the playback rate, volume and mute the level', () async {
    final c = make(project([talk('a', 2000, 8000, speed: 1.5, volume: 0.5)]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    await settle();
    final s = sounds.single;
    expect(s.rate, 1.5);
    expect(s.volume, 0.5);
    c.updateProject(project([
      talk('a', 2000, 8000, speed: 1.5, volume: 0.5).copyWith(muted: true),
    ]));
    await settle();
    expect(s.volume, 0);
    expect(video.volume, 0);
  });

  test('"Hear original" switches back at once, and forth again', () async {
    final c = make(project([talk('a', 0, 6000)]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    c.play();
    await settle();
    final s = sounds.single;
    expect(video.volume, 0);
    expect(s.playing, isTrue);

    c.hearOriginalSound = true;
    await settle();
    expect(video.volume, 1);
    expect(video.audioFilter, '');
    expect(s.playing, isFalse);
    expect(c.playingProcessedSound, isNull);

    c.hearOriginalSound = false;
    await settle();
    expect(s.playing, isTrue);
    expect(video.volume, 0);
  });

  test('pieces of one file play through; a jump in the source seeks',
      () async {
    final c = make(project([
      talk('a', 0, 2000),
      talk('b', 2000, 4000), // continues where a ends
      talk('c', 6000, 8000), // 2 s later in the file
    ]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    c.play();
    await settle();
    final s = sounds.single;
    s.log.clear();
    video.emitPosition(10);
    video.emitPosition(1990);
    video.emitPosition(2010);
    await settle();
    expect(c.clipIndex, 1);
    expect(s.log.where((l) => l.startsWith('seek')), isEmpty,
        reason: 'the sound runs on into the next piece');
    // Into c: the video seeks, and so does the sound.
    video.emitPosition(3995);
    video.emitPosition(4005);
    await settle();
    expect(c.clipIndex, 2);
    expect(s.log, contains('seek 6000'));
    expect(sounds, hasLength(1), reason: 'one file, one player');
  });

  test('a transition crossfades two sound players', () async {
    final c = make(project([
      talk('a', 0, 4000),
      talk('b', 0, 4000, path: '/b.mp4', transition: TransitionType.crossfade),
    ]));
    ready['/a.mp4'] = '/cache/a.flac';
    ready['/b.mp4'] = '/cache/b.flac';
    c.soundFilesChanged();
    // Half way through the 1 s transition (3000..4000).
    c.seek(3500);
    c.play();
    await settle();
    expect(sounds, hasLength(2));
    final byFile = {for (final s in sounds) s.path: s};
    expect(byFile['/cache/a.flac']!.volume, closeTo(0.5, 0.05));
    expect(byFile['/cache/b.flac']!.volume, closeTo(0.5, 0.05));
    expect(byFile['/cache/a.flac']!.playing, isTrue);
    expect(byFile['/cache/b.flac']!.playing, isTrue);
    for (final v in videos) {
      expect(v.volume, 0);
    }
  });

  test('a sound player that drifts away is put back in step', () async {
    final c = make(project([talk('a', 0, 20000)]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    c.play();
    await settle();
    final s = sounds.single;
    // Both settle at the start.
    video.emitPosition(0);
    s.emitPosition(0);
    await settle();
    s.log.clear();
    // The picture is at 5 s, the sound 200 ms ahead, several times.
    for (var i = 0; i < 6; i++) {
      video.emitPosition(5000 + i * 10);
      s.emitPosition(5200 + i * 10);
    }
    await settle();
    expect(c.soundOffsetMs, greaterThan(PlaybackController.soundDriftLimitMs));
    expect(s.log.where((l) => l.startsWith('seek')), hasLength(1));
    expect(c.soundCorrections, 1);
    // Small differences are left alone, and a sound a little late too.
    s.log.clear();
    for (var i = 0; i < 6; i++) {
      video.emitPosition(6000 + i * 10);
      s.emitPosition(6010 + i * 10);
    }
    for (var i = 0; i < 8; i++) {
      video.emitPosition(7000 + i * 10);
      s.emitPosition(6940 + i * 10);
    }
    await settle();
    expect(s.log.where((l) => l.startsWith('seek')), isEmpty);
  });

  test('pause and the end of the timeline stop the sound player', () async {
    final c = make(project([talk('a', 0, 2000)]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    c.play();
    await settle();
    final s = sounds.single;
    c.pause();
    await settle();
    expect(s.playing, isFalse);
    c.play();
    await settle();
    video.emitPosition(10);
    video.emitPosition(2000);
    await settle();
    expect(c.playing, isFalse);
    expect(s.playing, isFalse);
  });

  test('a file that stops being ready gives the sound back to the video',
      () async {
    final c = make(project([talk('a', 0, 4000)]));
    ready['/a.mp4'] = '/cache/a.flac';
    c.soundFilesChanged();
    c.play();
    await settle();
    expect(video.volume, 0);
    ready.clear(); // e.g. Voice focus changed: a new file is needed
    c.soundFilesChanged();
    await settle();
    expect(video.volume, 1);
    expect(sounds.single.playing, isFalse);
  });
}
