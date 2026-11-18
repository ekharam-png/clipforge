import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/playback/look.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

Clip video(String id, String path, int inMs, int outMs,
        {double volume = 1,
        bool muted = false,
        int source = 60000,
        double speed = 1,
        TransitionType transition = TransitionType.none,
        int transitionMs = 500}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: source,
      inMs: inMs,
      outMs: outMs,
      width: 1920,
      height: 1080,
      volume: volume,
      muted: muted,
      speed: speed,
      transition: transition,
      transitionMs: transitionMs,
    );

Clip photo(String id, int ms,
        {TransitionType transition = TransitionType.none,
        int transitionMs = 500}) =>
    Clip(
      id: id,
      type: ClipType.photo,
      path: '/p/$id.jpg',
      sourceDurationMs: 0,
      inMs: 0,
      outMs: ms,
      width: 1000,
      height: 1000,
      hasAudio: false,
      transition: transition,
      transitionMs: transitionMs,
    );

Project project(List<Clip> clips, {List<AudioClip> audio = const []}) => Project(
      id: 'p',
      name: 'Test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: clips,
      audio: audio,
    );

/// A player whose [open] takes until [finishOpen] is called, like a real one.
class SlowOpenPlayer extends FakePlayer {
  Completer<void>? _opening;

  @override
  Future<void> open(String path,
      {required int positionMs, required bool play}) async {
    await super.open(path, positionMs: positionMs, play: play);
    _opening = Completer<void>();
    await _opening!.future;
  }

  void finishOpen() => _opening!.complete();
}

/// Lets queued player commands run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePlayer player;
  late List<FakePlayer> players;
  late List<FakePlayer> audioPlayers;

  /// [player] is the first video player (deck 0); a second one is added to
  /// [players] when the controller asks for it.
  PlaybackController make(Project p,
      {Set<String> missing = const {}, bool twoDecks = true}) {
    player = FakePlayer();
    players = [player];
    audioPlayers = [];
    final c = PlaybackController(
      project: p,
      video: player,
      createVideoPlayer: twoDecks
          ? () {
              final b = FakePlayer();
              players.add(b);
              return b;
            }
          : null,
      createAudioPlayer: () {
        final a = FakePlayer();
        audioPlayers.add(a);
        return a;
      },
      fileExists: (path) => !missing.contains(path),
    );
    addTearDown(c.dispose);
    return c;
  }

  test('loads the first frame paused at the clip in-point', () async {
    final c = make(project([video('a', '/a.mp4', 2000, 5000)]));
    await settle();
    expect(player.log, ['volume 1.00', 'open /a.mp4@2000 paused']);
    expect(c.positionMs, 0);
    expect(c.playing, isFalse);
    expect(c.durationMs, 3000);
  });

  test('maps source position to timeline position while playing', () async {
    final c = make(project([
      video('a', '/a.mp4', 2000, 5000),
      video('b', '/b.mp4', 0, 4000),
    ]));
    await settle();
    c.play();
    await settle();
    expect(player.playing, isTrue);
    player.emitPosition(2000);
    player.emitPosition(3500);
    expect(c.positionMs, 1500);
    expect(c.clipIndex, 0);
  });

  test('advances to the next clip at the trim end by swapping players',
      () async {
    final c = make(project([
      video('a', '/a.mp4', 2000, 5000),
      video('b', '/b.mp4', 1000, 4000),
    ]));
    await settle();
    // The second player exists from the start but has nothing to do.
    expect(players, hasLength(2));
    expect(players[1].log, isEmpty);
    c.play();
    await settle();
    // The clip ends within the lead time: the next file is made ready.
    expect(players[1].log, ['volume 1.00', 'open /b.mp4@1000 paused']);
    player.emitPosition(2040); // the player reports from where it was put
    player.emitPosition(4990);
    expect(c.clipIndex, 0);
    expect(c.frontDeck, 0);
    player.log.clear();
    player.emitPosition(5010);
    expect(c.clipIndex, 1);
    expect(c.positionMs, 3000);
    expect(c.frontDeck, 1);
    expect(c.scene.current, PreviewLayer(PreviewLayerKind.video, c.currentClip!, 1));
    await settle();
    // No load at the cut: the waiting player starts, the old one stops.
    expect(players[1].log.last, 'play');
    expect(player.log, ['pause']);
    // A leftover position from the old file must not move the playhead.
    player.emitPosition(5030);
    expect(c.positionMs, 3000);
    players[1].emitPosition(1500);
    expect(c.positionMs, 3500);
  });

  test('with one player the next file is opened at the cut', () async {
    final c = make(
        project([
          video('a', '/a.mp4', 2000, 5000),
          video('b', '/b.mp4', 1000, 4000),
        ]),
        twoDecks: false);
    await settle();
    c.play();
    await settle();
    player.emitPosition(2040);
    player.emitPosition(5010);
    expect(c.clipIndex, 1);
    await settle();
    expect(player.log.last, 'open /b.mp4@1000 play');
    player.emitPosition(5030);
    expect(c.positionMs, 3000);
    player.emitPosition(1500);
    expect(c.positionMs, 3500);
  });

  test('advances when the file ends before outMs is reported', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 3000, source: 3000),
      video('b', '/b.mp4', 0, 1000),
    ]));
    await settle();
    c.play();
    await settle();
    player.emitPosition(2960);
    player.emitCompleted();
    expect(c.clipIndex, 1);
    expect(c.positionMs, 3000);
  });

  test('two halves of a split clip play through without reopening', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 2000),
      video('b', '/a.mp4', 2000, 6000, volume: 0.5),
    ]));
    await settle();
    c.play();
    await settle();
    player.log.clear();
    player.emitPosition(40);
    player.emitPosition(1990);
    player.emitPosition(2010);
    await settle();
    expect(c.clipIndex, 1);
    expect(player.log, ['volume 0.50']);
    player.emitPosition(2500);
    expect(c.positionMs, 2500);
  });

  test('split halves leave the second player alone', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 2000),
      video('b', '/a.mp4', 2000, 6000),
    ]));
    await settle();
    c.play();
    await settle();
    player.emitPosition(40);
    player.emitPosition(1990);
    player.emitPosition(2010);
    await settle();
    expect(c.clipIndex, 1);
    expect(players[1].log, isEmpty);
  });

  test('a project of one clip makes do with one player', () async {
    final c = make(project([video('a', '/a.mp4', 0, 2000)]));
    await settle();
    c.play();
    await settle();
    expect(players, hasLength(1));
    // The second one is made when a second clip arrives (not while the
    // picture has to be loaded in a hurry).
    c.updateProject(project([
      video('a', '/a.mp4', 0, 2000),
      photo('p1', 1000),
    ]));
    expect(players, hasLength(2));
  });

  test('same file but a jump in source time: the other player waits there',
      () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 2000),
      video('b', '/a.mp4', 9000, 10000),
    ]));
    await settle();
    c.play();
    await settle();
    expect(players[1].log, ['volume 1.00', 'open /a.mp4@9000 paused']);
    player.emitPosition(40);
    player.emitPosition(2000);
    await settle();
    expect(players[1].log.last, 'play');
    expect(c.positionMs, 2000);
    players[1].emitPosition(9500);
    expect(c.positionMs, 2500);
  });

  test('same file but a jump in source time, one player: seeks', () async {
    final c = make(
        project([
          video('a', '/a.mp4', 0, 2000),
          video('b', '/a.mp4', 9000, 10000),
        ]),
        twoDecks: false);
    await settle();
    c.play();
    await settle();
    player.log.clear();
    player.emitPosition(40);
    player.emitPosition(2000);
    await settle();
    expect(player.log, ['seek 9000', 'play']);
    expect(c.positionMs, 2000);
  });

  test('stops at the end of the timeline and restarts from zero', () async {
    final c = make(project([video('a', '/a.mp4', 0, 2000)]));
    await settle();
    c.play();
    await settle();
    player.emitPosition(40);
    player.emitPosition(2000);
    await settle();
    expect(c.playing, isFalse);
    expect(c.positionMs, 2000);
    expect(player.playing, isFalse);
    c.play();
    await settle();
    expect(c.positionMs, 0);
    expect(player.log.sublist(player.log.length - 2), ['seek 0', 'play']);
  });

  test('photos are timed by tick and hand over to the next clip', () async {
    final c = make(project([
      photo('p1', 3000),
      video('a', '/a.mp4', 500, 1500),
      photo('p2', 1000),
    ]));
    await settle();
    expect(player.log, isEmpty); // nothing to load for a photo
    c.play();
    c.tick(1000);
    expect(c.positionMs, 1000);
    expect(c.clipIndex, 0);
    expect(c.scene.current!.kind, PreviewLayerKind.photo);
    await settle();
    // The video after the photo waits in the second player.
    expect(players[1].log, ['volume 1.00', 'open /a.mp4@500 paused']);
    c.tick(2100);
    expect(c.clipIndex, 1);
    expect(c.positionMs, 3000);
    expect(c.frontDeck, 1);
    await settle();
    expect(players[1].log.last, 'play');
    expect(player.log, isEmpty);
    // The clock does not move a playing video; the player does.
    c.tick(300);
    expect(c.positionMs, 3000);
    players[1].emitPosition(1000);
    expect(c.positionMs, 3500);
    players[1].emitPosition(1500);
    expect(c.clipIndex, 2);
    expect(c.positionMs, 4000);
    await settle();
    expect(players[1].playing, isFalse);
    c.tick(600);
    expect(c.positionMs, 4600);
    c.tick(600);
    expect(c.playing, isFalse);
    expect(c.positionMs, 5000);
  });

  test('a cut that comes before the next file is ready loads it in place',
      () async {
    final c = make(project([
      photo('p1', 3000),
      video('a', '/a.mp4', 500, 1500),
    ]));
    c.play();
    c.tick(1000);
    // No time for the second player to finish loading.
    c.tick(2100);
    expect(c.clipIndex, 1);
    expect(c.frontDeck, 0);
    await settle();
    expect(player.log.last, 'open /a.mp4@500 play');
    player.emitPosition(1000);
    expect(c.positionMs, 3500);
  });

  test('reports the file the player holds, not the one it is loading',
      () async {
    final slow = SlowOpenPlayer();
    final c = PlaybackController(
      project: project(
          [video('a', '/a.mp4', 0, 4000), video('b', '/b.mp4', 0, 3000)]),
      video: slow,
      createAudioPlayer: FakePlayer.new,
      fileExists: (_) => true,
    );
    addTearDown(c.dispose);
    await settle();
    expect(c.loadedVideoPath, isNull);
    slow.finishOpen();
    await settle();
    expect(c.loadedVideoPath, '/a.mp4');
    var notified = 0;
    c.addListener(() => notified++);
    c.seek(5000);
    await settle();
    expect(c.currentClip!.path, '/b.mp4');
    expect(c.loadedVideoPath, isNull);
    notified = 0;
    slow.finishOpen();
    await settle();
    expect(c.loadedVideoPath, '/b.mp4');
    expect(notified, 1);
  });

  test('seek resolves the clip and source position', () async {
    final c = make(project([
      video('a', '/a.mp4', 2000, 5000),
      photo('p1', 2000),
      video('b', '/b.mp4', 1000, 4000),
    ]));
    await settle();
    player.log.clear();
    c.seek(6500);
    await settle();
    expect(c.clipIndex, 2);
    expect(player.log, ['open /b.mp4@2500 paused']);
    player.log.clear();
    c.seek(4000);
    await settle();
    expect(c.clipIndex, 1);
    expect(player.log, isEmpty);
    c.seek(1000);
    await settle();
    expect(player.log, ['open /a.mp4@3000 paused']);
    c.seek(999999);
    expect(c.positionMs, 8000);
    c.seek(-5);
    expect(c.positionMs, 0);
  });

  test('a burst of seeks only performs the last one', () async {
    final c = make(project([video('a', '/a.mp4', 0, 10000)]));
    await settle();
    player.log.clear();
    for (var t = 100; t <= 5000; t += 100) {
      c.seek(t);
    }
    await settle();
    expect(player.log, ['seek 5000', 'pause']);
  });

  test('seeking while playing keeps playing from the new place', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 4000),
      video('b', '/b.mp4', 0, 4000),
    ]));
    await settle();
    c.play();
    await settle();
    player.emitPosition(1000);
    c.seek(5000);
    await settle();
    expect(player.log.last, 'open /b.mp4@1000 play');
    // Stale event from the first file is ignored.
    player.emitPosition(3999);
    expect(c.positionMs, 5000);
    player.emitPosition(1200);
    expect(c.positionMs, 5200);
  });

  test('clip volume and mute reach the player', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 2000, volume: 0.4),
      video('b', '/b.mp4', 0, 2000, muted: true),
    ]));
    await settle();
    expect(player.volume, closeTo(0.4, 1e-9));
    c.seek(2500);
    await settle();
    expect(player.volume, 0);
    // An edit that only changes the volume does not reload the picture.
    player.log.clear();
    c.updateProject(project([
      video('a', '/a.mp4', 0, 2000, volume: 0.4),
      video('b', '/b.mp4', 0, 2000, volume: 0.8),
    ]));
    await settle();
    expect(player.log, ['volume 0.80']);
  });

  group('clip sound (track, side, voice focus)', () {
    Clip stereo(String id, String path, int inMs, int outMs) =>
        video(id, path, inMs, outMs).copyWith(audioStreams: const [2, 2]);

    test('reach the player before the file opens; edits apply without reload',
        () async {
      final c = make(project([
        stereo('a', '/a.mp4', 0, 2000)
            .copyWith(audioTrack: 1, audioChannel: AudioChannel.left),
        stereo('b', '/b.mp4', 0, 2000),
      ]));
      await settle();
      final open = player.log.indexWhere((l) => l.startsWith('open'));
      final track = player.log.indexOf('track 1');
      final af = player.log.indexWhere((l) => l.startsWith('af '));
      expect(track, inInclusiveRange(0, open));
      expect(af, inInclusiveRange(0, open));
      expect(player.audioFilter, contains('c=FR'));
      // Voice focus on the clip under the playhead: no reload, no seek.
      player.log.clear();
      c.updateProject(project([
        stereo('a', '/a.mp4', 0, 2000).copyWith(
            audioTrack: 1, audioChannel: AudioChannel.left, voiceFocus: 1),
        stereo('b', '/b.mp4', 0, 2000),
      ]));
      await settle();
      expect(player.log, hasLength(1));
      expect(player.log.single, startsWith('af '));
      expect(player.audioFilter, contains('f=25.5'));
      // The next clip has none of it.
      c.seek(2500);
      await settle();
      final front = players.firstWhere((p) => p.path == '/b.mp4');
      expect(front.audioFilter, '');
      expect(front.audioTrack, 0);
    });

    test('pieces of one file with different settings play through, '
        'changing the filter at the cut', () async {
      final c = make(project([
        stereo('a', '/a.mp4', 0, 2000),
        stereo('b', '/a.mp4', 2000, 6000).copyWith(voiceFocus: 0.5),
      ]));
      await settle();
      c.play();
      await settle();
      player.log.clear();
      player.emitPosition(40);
      player.emitPosition(1990);
      player.emitPosition(2010);
      await settle();
      expect(c.clipIndex, 1);
      expect(player.log, hasLength(1));
      expect(player.log.single, startsWith('af format=format=floatp,lavfi=[equalizer=f=25.5'));
    });

    test('hear original takes the filters off and puts them back', () async {
      final c = make(project([
        stereo('a', '/a.mp4', 0, 2000).copyWith(voiceFocus: 1, audioTrack: 1),
      ]));
      await settle();
      expect(player.audioFilter, isNotEmpty);
      c.hearOriginalSound = true;
      await settle();
      expect(c.hearOriginal.value, isTrue);
      expect(player.audioFilter, '');
      expect(player.audioTrack, 1, reason: 'the track stays');
      // Edits while comparing do not bring the filters back.
      c.updateProject(project([
        stereo('a', '/a.mp4', 0, 2000).copyWith(voiceFocus: 0.5, audioTrack: 1),
      ]));
      await settle();
      expect(player.audioFilter, '');
      c.hearOriginalSound = false;
      await settle();
      expect(player.audioFilter, contains('equalizer'));
    });

    test('a different track at a cut of one file is not played through',
        () async {
      final c = make(project([
        stereo('a', '/a.mp4', 0, 2000),
        stereo('b', '/a.mp4', 2000, 6000).copyWith(audioTrack: 1),
      ]));
      await settle();
      c.play();
      await settle();
      player.emitPosition(40);
      player.emitPosition(1990);
      player.emitPosition(2010);
      await settle();
      expect(c.clipIndex, 1);
      expect(players.any((p) => p.audioTrack == 1), isTrue);
    });
  });

  test('a missing video is skipped by the clock instead of hanging', () async {
    final c = make(
      project([video('a', '/gone.mp4', 0, 2000), video('b', '/b.mp4', 0, 1000)]),
      missing: {'/gone.mp4'},
    );
    await settle();
    expect(c.isMissing('/gone.mp4'), isTrue);
    expect(player.log, isEmpty);
    c.play();
    c.tick(1500);
    expect(c.positionMs, 1500);
    c.tick(600);
    expect(c.clipIndex, 1);
    await settle();
    expect(player.log.last, 'open /b.mp4@0 play');
  });

  test('a video that never reports a position is treated as unplayable',
      () async {
    final c = make(project([video('a', '/a.mp4', 0, 6000)]));
    await settle();
    c.play();
    for (var i = 0; i < 50; i++) {
      c.tick(100);
    }
    expect(c.isMissing('/a.mp4'), isTrue);
    c.tick(500);
    expect(c.positionMs, greaterThan(0));
  });

  test('editing the project keeps the playhead inside the timeline', () async {
    final c = make(project([
      video('a', '/a.mp4', 0, 4000),
      video('b', '/b.mp4', 0, 4000),
    ]));
    await settle();
    c.seek(7000);
    await settle();
    player.log.clear();
    c.updateProject(project([video('a', '/a.mp4', 0, 4000)]));
    await settle();
    expect(c.positionMs, 4000);
    expect(c.clipIndex, 0);
    c.updateProject(project([]));
    expect(c.positionMs, 0);
    expect(c.clipIndex, -1);
    expect(c.currentClip, isNull);
    c.play();
    expect(c.playing, isFalse);
  });

  test('trimming the in-point under a paused playhead shows the new frame',
      () async {
    final c = make(project([video('a', '/a.mp4', 0, 4000)]));
    await settle();
    player.log.clear();
    c.updateProject(project([video('a', '/a.mp4', 1000, 4000)]));
    await settle();
    expect(player.log, ['seek 1000', 'pause']);
  });

  group('speed', () {
    test('sets the player rate and maps positions through it', () async {
      // 4 s of source at double speed: 2 s on the timeline.
      final c = make(project([
        video('a', '/a.mp4', 2000, 6000, speed: 2),
        video('b', '/b.mp4', 0, 1000, speed: 0.5),
      ]));
      await settle();
      expect(player.log,
          ['volume 1.00', 'rate 2.00', 'open /a.mp4@2000 paused']);
      expect(c.durationMs, 4000);
      c.seek(500);
      await settle();
      expect(player.log.sublist(3), ['seek 3000', 'pause']);
      c.play();
      await settle();
      expect(players[1].log,
          ['volume 1.00', 'rate 0.50', 'open /b.mp4@0 paused']);
      player.emitPosition(3000);
      player.emitPosition(4000);
      expect(c.positionMs, 1000);
      player.emitPosition(5998);
      expect(c.clipIndex, 0);
      expect(c.positionMs, 1999);
      player.emitPosition(6000);
      expect(c.clipIndex, 1);
      expect(c.positionMs, 2000);
      await settle();
      // Half speed: 250 ms of source are 500 ms of timeline.
      players[1].emitPosition(0);
      players[1].emitPosition(250);
      expect(c.positionMs, 2500);
      players[1].emitPosition(1000);
      expect(c.playing, isFalse);
      expect(c.positionMs, 4000);
    });

    test('a change of speed between split halves resets the rate', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 2000),
        video('b', '/a.mp4', 2000, 6000, speed: 2),
      ]));
      await settle();
      c.play();
      await settle();
      // Not a seamless seam any more: the second half waits at its rate.
      expect(players[1].log,
          ['volume 1.00', 'rate 2.00', 'open /a.mp4@2000 paused']);
      player.emitPosition(40);
      player.emitPosition(2000);
      expect(c.frontDeck, 1);
      await settle();
      players[1].emitPosition(2000);
      players[1].emitPosition(4000);
      expect(c.positionMs, 3000);
    });

    test('editing the speed re-seeks and changes the rate', () async {
      final c = make(project([video('a', '/a.mp4', 0, 8000)]));
      await settle();
      c.seek(2000);
      await settle();
      player.log.clear();
      c.updateProject(project([video('a', '/a.mp4', 0, 8000, speed: 4)]));
      await settle();
      expect(c.durationMs, 2000);
      expect(c.positionMs, 2000);
      expect(player.log, ['rate 4.00', 'seek 8000', 'pause']);
    });

    test('music stays on timeline time under a sped-up clip', () async {
      final c = make(project(
        [video('a', '/a.mp4', 0, 8000, speed: 2)],
        audio: [
          const AudioClip(
              id: 'm',
              path: '/m.mp3',
              sourceDurationMs: 9000,
              startMs: 1000,
              inMs: 0,
              outMs: 3000),
        ],
      ));
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(2400); // 1200 ms on the timeline
      c.tick(16);
      await settle();
      expect(c.positionMs, 1200);
      final music = audioPlayers.single.log;
      expect(music.sublist(music.length - 2), ['seek 200', 'play']);
      expect(audioPlayers.single.log, isNot(contains(startsWith('rate'))));
    });
  });

  group('preload', () {
    test('starts only within the lead time and only while playing', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 10000),
        video('b', '/b.mp4', 0, 4000),
      ]));
      await settle();
      c.seek(9000); // paused next to the cut: nothing is loaded
      await settle();
      expect(players[1].log, isEmpty);
      c.seek(0);
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(6900);
      await settle();
      expect(players[1].log, isEmpty);
      player.emitPosition(7000);
      await settle();
      expect(players[1].log, ['volume 1.00', 'open /b.mp4@0 paused']);
      // Never more than two video players.
      player.emitPosition(10000);
      await settle();
      players[1].emitPosition(0);
      players[1].emitPosition(4000);
      await settle();
      expect(players, hasLength(2));
      expect(c.playing, isFalse);
    });

    test('three files alternate between the two players', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 1000),
        video('b', '/b.mp4', 0, 1000),
        video('c', '/c.mp4', 0, 1000),
      ]));
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(1000);
      await settle();
      expect(c.frontDeck, 1);
      // The freed player takes the third file.
      expect(player.log.last, 'open /c.mp4@0 paused');
      expect(player.playing, isFalse);
      players[1].emitPosition(20);
      players[1].emitPosition(1000);
      expect(c.frontDeck, 0);
      expect(c.clipIndex, 2);
      await settle();
      expect(player.log.last, 'play');
      expect(players, hasLength(2));
    });

    test('a seek keeps a waiting file, a pause lets go of it', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 3000),
        video('b', '/b.mp4', 500, 4000),
      ]));
      await settle();
      c.play();
      await settle();
      players[1].log.clear();
      c.seek(1000);
      await settle();
      expect(players[1].log, isEmpty);
      c.pause();
      c.play();
      await settle();
      expect(players[1].log, ['seek 500', 'pause']);
    });

    test('deleting the playing clip moves on to the waiting player',
        () async {
      final a = video('a', '/a.mp4', 0, 3000);
      final b = video('b', '/b.mp4', 500, 4000);
      final c = make(project([a, b]));
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(1000);
      c.updateProject(project([b]));
      await settle();
      expect(c.playing, isTrue);
      expect(c.frontDeck, 1);
      // Already loaded: a seek, not another open.
      expect(players[1].log.sublist(2), ['seek 1500', 'play']);
      expect(player.log.last, 'pause');
      players[1].emitPosition(1600);
      expect(c.positionMs, 1100);
    });

    test('deleting the waiting clip makes the one after it ready', () async {
      final a = video('a', '/a.mp4', 0, 3000);
      final b = video('b', '/b.mp4', 500, 4000);
      final d = video('d', '/d.mp4', 0, 4000);
      final c = make(project([a, b, d]));
      await settle();
      c.play();
      await settle();
      expect(players[1].path, '/b.mp4');
      player.log.clear();
      c.updateProject(project([a, d]));
      await settle();
      expect(players[1].log.last, 'open /d.mp4@0 paused');
      expect(player.log, isEmpty, reason: 'the playing clip is left alone');
    });

    test('a missing next file is not loaded; the clock shows its notice',
        () async {
      final c = make(
        project([
          video('a', '/a.mp4', 0, 1000),
          video('gone', '/gone.mp4', 0, 1000),
        ]),
        missing: {'/gone.mp4'},
      );
      await settle();
      c.play();
      await settle();
      expect(players[1].log, isEmpty);
      player.emitPosition(0);
      player.emitPosition(1000);
      expect(c.clipIndex, 1);
      expect(c.scene.current!.kind, PreviewLayerKind.missing);
      await settle();
      expect(player.playing, isFalse);
      c.tick(400);
      expect(c.positionMs, 1400);
    });

    test('leaves the clip on time between two position reports', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 2000, source: 2000),
        video('b', '/b.mp4', 0, 2000, source: 2000),
      ]));
      await settle();
      c.play();
      await settle();
      // Without a report from the player the clock does not guess.
      c.tick(50);
      expect(c.positionMs, 0);
      player.emitPosition(0);
      player.emitPosition(1960); // last frame of a 25 fps file
      c.tick(16);
      expect(c.clipIndex, 0);
      c.tick(16);
      c.tick(16); // 1960 + 48 >= 2000
      expect(c.clipIndex, 1);
      expect(c.positionMs, 2000);
      // The same at the end of the timeline.
      await settle();
      players[1].emitPosition(0);
      players[1].emitPosition(1960);
      c.tick(20);
      expect(c.playing, isTrue);
      c.tick(20);
      expect(c.playing, isFalse);
      expect(c.positionMs, 4000);
    });

    test('a player that stops reporting is not carried on for long',
        () async {
      final c = make(project([video('a', '/a.mp4', 0, 2000)]));
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(1800);
      for (var i = 0; i < 20; i++) {
        c.tick(16);
      }
      expect(c.playing, isTrue);
      expect(c.positionMs, 1800);
    });
  });

  group('transitions', () {
    // a: 0..4000, b: 3000..6000 on the timeline (1 s overlap).
    List<Clip> ab({TransitionType type = TransitionType.crossfade}) => [
          video('a', '/a.mp4', 0, 4000, volume: 0.8),
          video('b', '/b.mp4', 1000, 4000,
              transition: type, transitionMs: 1000),
        ];

    test('both clips play during the overlap', () async {
      final c = make(project(ab()));
      await settle();
      expect(c.durationMs, 6000);
      c.play();
      await settle();
      // The incoming clip waits silently: it will fade in.
      expect(players[1].log, ['volume 0.00', 'open /b.mp4@1000 paused']);
      player.emitPosition(0);
      player.emitPosition(2990);
      expect(c.clipIndex, 0);
      expect(c.scene.outgoing, isNull);
      expect(c.transitionProgress, 1);
      player.log.clear();
      player.emitPosition(3000);
      expect(c.clipIndex, 1);
      expect(c.positionMs, 3000);
      expect(c.frontDeck, 1);
      await settle();
      expect(players[1].log.last, 'play');
      expect(player.playing, isTrue, reason: 'the outgoing clip plays on');
      expect(player.log, isEmpty);
      var scene = c.scene;
      expect(scene.transition, TransitionType.crossfade);
      expect(scene.progress, 0);
      expect(scene.current, PreviewLayer(PreviewLayerKind.video, c.project.clips[1], 1));
      expect(scene.outgoing, PreviewLayer(PreviewLayerKind.video, c.project.clips[0], 0));

      // The incoming clip is the clock; the outgoing one runs along.
      player.emitPosition(3300);
      expect(c.positionMs, 3000);
      players[1].emitPosition(1000);
      players[1].emitPosition(1500);
      expect(c.positionMs, 3500);
      expect(c.transitionProgress, closeTo(0.5, 1e-9));
      await settle();
      expect(players[1].volume, closeTo(0.5, 1e-9));
      expect(player.volume, closeTo(0.4, 1e-9));

      players[1].emitPosition(2000);
      expect(c.positionMs, 4000);
      scene = c.scene;
      expect(scene.outgoing, isNull);
      expect(scene.transition, TransitionType.none);
      await settle();
      expect(players[1].volume, 1);
      expect(player.playing, isFalse);
      players[1].emitPosition(4000);
      expect(c.playing, isFalse);
      expect(c.positionMs, 6000);
    });

    test('the outgoing clip stops at its own end', () async {
      final c = make(project(ab()));
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(3000);
      await settle();
      players[1].emitPosition(1000);
      player.emitPosition(3990);
      expect(player.playing, isTrue);
      player.emitPosition(4000);
      await settle();
      expect(player.playing, isFalse);
      expect(c.scene.outgoing, isNotNull); // its last frame fades on
      expect(c.playing, isTrue);
    });

    test('seek into an overlap shows both clips at the right frames',
        () async {
      final c = make(project(ab(type: TransitionType.slideLeft)));
      await settle();
      c.seek(3400);
      await settle();
      expect(c.clipIndex, 1);
      // The player that holds the outgoing file keeps it.
      expect(c.frontDeck, 1);
      expect(player.log.sublist(2), ['volume 0.48', 'seek 3400', 'pause']);
      expect(players[1].log, ['volume 0.40', 'open /b.mp4@1400 paused']);
      final scene = c.scene;
      expect(scene.transition, TransitionType.slideLeft);
      expect(scene.progress, closeTo(0.4, 1e-9));
      expect(scene.current!.deck, 1);
      expect(scene.outgoing!.deck, 0);

      // Play from there: both run, the incoming one is the clock.
      c.play();
      await settle();
      expect(player.playing, isTrue);
      expect(players[1].playing, isTrue);
      players[1].emitPosition(1400);
      players[1].emitPosition(1900);
      expect(c.positionMs, 3900);

      // Out of the overlap, into the first clip alone.
      c.seek(1000);
      await settle();
      expect(c.frontDeck, 0);
      expect(player.log.sublist(player.log.length - 2), ['seek 1000', 'play']);
      expect(players[1].playing, isFalse);
      expect(c.scene.outgoing, isNull);
    });

    test('pausing inside an overlap pauses both', () async {
      final c = make(project(ab()));
      await settle();
      c.seek(3500);
      c.play();
      await settle();
      expect(player.playing, isTrue);
      expect(players[1].playing, isTrue);
      c.pause();
      await settle();
      expect(player.playing, isFalse);
      expect(players[1].playing, isFalse);
      expect(c.scene.outgoing, isNotNull);
    });

    test('video into photo: the video plays on under the photo', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 2000),
        photo('p1', 2000, transition: TransitionType.fadeBlack, transitionMs: 600),
      ]));
      await settle();
      expect(c.durationMs, 3400);
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(1400);
      expect(c.clipIndex, 1);
      expect(c.positionMs, 1400);
      await settle();
      expect(player.playing, isTrue);
      var scene = c.scene;
      expect(scene.current!.kind, PreviewLayerKind.photo);
      expect(scene.outgoing!.kind, PreviewLayerKind.video);
      expect(scene.outgoing!.deck, 0);
      expect(scene.transition, TransitionType.fadeBlack);
      // The photo is timed by the clock.
      c.tick(300);
      expect(c.positionMs, 1700);
      expect(c.scene.progress, closeTo(0.5, 1e-9));
      await settle();
      expect(player.volume, closeTo(0.5, 1e-9));
      c.tick(300);
      expect(c.scene.outgoing, isNull);
      await settle();
      expect(player.playing, isFalse);
      c.tick(1400);
      expect(c.playing, isFalse);
      expect(c.positionMs, 3400);
    });

    test('photo into video and photo into photo', () async {
      final c = make(project([
        photo('p1', 2000),
        video('a', '/a.mp4', 1000, 3000,
            transition: TransitionType.slideUp, transitionMs: 400),
        photo('p2', 2000, transition: TransitionType.crossfade, transitionMs: 400),
        photo('p3', 2000, transition: TransitionType.crossfade, transitionMs: 400),
      ]));
      // 2000 + 2000 + 2000 + 2000 - 3 * 400
      expect(c.durationMs, 6800);
      c.play();
      c.tick(100);
      await settle();
      c.tick(1500);
      expect(c.clipIndex, 1);
      expect(c.positionMs, 1600);
      await settle();
      expect(players[1].playing, isTrue);
      var scene = c.scene;
      expect(scene.outgoing!.kind, PreviewLayerKind.photo);
      expect(scene.current!.kind, PreviewLayerKind.video);
      expect(scene.transition, TransitionType.slideUp);
      players[1].emitPosition(1000);
      players[1].emitPosition(1200);
      expect(c.scene.progress, closeTo(0.5, 1e-9));
      players[1].emitPosition(2600);
      // Hands over to the photo 400 ms before its own end.
      expect(c.clipIndex, 2);
      expect(c.positionMs, 3200);
      scene = c.scene;
      expect(scene.outgoing!.kind, PreviewLayerKind.video);
      expect(scene.current!.clip.id, 'p2');
      c.tick(400);
      expect(c.scene.outgoing, isNull);
      c.tick(1200); // 4800: start of p3, which overlaps p2
      expect(c.clipIndex, 3);
      scene = c.scene;
      expect(scene.outgoing!.clip.id, 'p2');
      expect(scene.current!.clip.id, 'p3');
      expect(scene.progress, 0);
      c.tick(100);
      expect(c.scene.progress, closeTo(0.25, 1e-9));
    });

    test('with one player a transition is a cut at its start', () async {
      final c = make(project(ab()), twoDecks: false);
      await settle();
      c.play();
      await settle();
      player.emitPosition(0);
      player.emitPosition(3000);
      expect(c.clipIndex, 1);
      expect(c.positionMs, 3000);
      await settle();
      expect(player.log.last, 'open /b.mp4@1000 play');
      expect(c.scene.outgoing, isNull);
      expect(c.scene.transition, TransitionType.none);
      // Timeline timing is the same as with two players.
      player.emitPosition(1000);
      player.emitPosition(4000);
      expect(c.positionMs, 6000);
    });

    test('an overlap never exceeds half of either clip', () async {
      final c = make(project([
        video('a', '/a.mp4', 0, 1000),
        video('b', '/b.mp4', 0, 4000,
            transition: TransitionType.crossfade, transitionMs: 3000),
      ]));
      await settle();
      expect(c.durationMs, 4500);
      c.seek(750);
      expect(c.clipIndex, 1);
      expect(c.transitionProgress, closeTo(0.5, 1e-9));
    });

    test('a missing side turns the transition into a cut', () async {
      final c = make(project(ab()), missing: {'/a.mp4'});
      await settle();
      c.seek(3500);
      await settle();
      final scene = c.scene;
      expect(scene.outgoing, isNull);
      expect(scene.current!.kind, PreviewLayerKind.video);
      expect(scene.transition, TransitionType.none);
    });
  });

  group('picture', () {
    test('a loading file shows the last frame in its own shape', () async {
      final slow = SlowOpenPlayer();
      final a = video('a', '/a.mp4', 0, 4000);
      final b = video('b', '/b.mp4', 0, 3000);
      final c = PlaybackController(
        project: project([a, b, photo('p1', 1000)]),
        video: slow,
        createVideoPlayer: FakePlayer.new,
        createAudioPlayer: FakePlayer.new,
        fileExists: (_) => true,
      );
      addTearDown(c.dispose);
      await settle();
      expect(c.scene.current!.kind, PreviewLayerKind.blank);
      slow.finishOpen();
      await settle();
      expect(c.scene.current, PreviewLayer(PreviewLayerKind.video, a, 0));
      c.seek(5000);
      await settle();
      // Clip b is current, but the player still holds a's picture.
      expect(c.currentClip, b);
      expect(c.scene.current, PreviewLayer(PreviewLayerKind.video, a, 0));
      slow.finishOpen();
      await settle();
      expect(c.scene.current, PreviewLayer(PreviewLayerKind.video, b, 0));
      // Coming from a photo there is no frame worth keeping.
      c.seek(7500);
      expect(c.scene.current!.kind, PreviewLayerKind.photo);
      c.seek(1000);
      await settle();
      expect(c.scene.current!.kind, PreviewLayerKind.blank);
      slow.finishOpen();
      await settle();
      expect(c.scene.current, PreviewLayer(PreviewLayerKind.video, a, 0));
    });

    test('colour matrix mirrors eq', () {
      Clip look({double b = 0, double c = 0, double s = 0}) => Clip(
            id: 'x',
            type: ClipType.photo,
            path: '/x.jpg',
            sourceDurationMs: 0,
            inMs: 0,
            outMs: 1000,
            width: 10,
            height: 10,
            brightness: b,
            contrast: c,
            saturation: s,
          );
      List<double> apply(List<double> m, List<double> rgb) => [
            for (var row = 0; row < 3; row++)
              m[row * 5] * rgb[0] +
                  m[row * 5 + 1] * rgb[1] +
                  m[row * 5 + 2] * rgb[2] +
                  m[row * 5 + 4] / 255,
          ];
      expect(hasColorAdjustments(look()), isFalse);
      expect(apply(clipColorMatrix(look()), [0.2, 0.5, 0.9]),
          [closeTo(0.2, 1e-9), closeTo(0.5, 1e-9), closeTo(0.9, 1e-9)]);
      // Brightness shifts every channel by the eq brightness (limited
      // range steps are 255/219 of full range ones).
      final bright = apply(clipColorMatrix(look(b: 1)), [0.2, 0.5, 0.6]);
      final shift = 1.164 * eqBrightness(1);
      expect(eqBrightness(1), 0.2);
      expect(bright, [
        closeTo(0.2 + shift, 1e-9),
        closeTo(0.5 + shift, 1e-9),
        closeTo(0.6 + shift, 1e-9)
      ]);
      // No saturation: grey of the same luma (Rec. 709 for a photo).
      final grey = apply(clipColorMatrix(look(s: -1)), [1, 0, 0]);
      expect(grey[0], closeTo(0.2126, 1e-9));
      expect(grey[1], closeTo(grey[0], 1e-9));
      expect(grey[2], closeTo(grey[0], 1e-9));
      // Contrast scales the luma about the pivot (limited-range mid grey).
      final k = eqContrast(1);
      expect(k, 1.5);
      final hard = apply(clipColorMatrix(look(c: 1)), [0.75, 0.75, 0.75]);
      expect(hard[0], closeTo(0.511 + (0.75 - 0.511) * k, 1e-9));
      expect(apply(clipColorMatrix(look(c: -1)), [0.511, 0.511, 0.511])[1],
          closeTo(0.511, 1e-9));
      // The example of the export documentation: saturated colours keep
      // their distance from the luma under contrast.
      final red = apply(clipColorMatrix(look(c: 1)), [1, 0, 0]);
      expect(red[0] - red[1], closeTo(1, 1e-9));
      // Out-of-range settings are clamped like in the export.
      expect(clipColorMatrix(look(b: 5)), clipColorMatrix(look(b: 1)));
    });

    test('transition poses', () {
      ({double opacity, Offset offset}) pose(TransitionType t, double p,
              {required bool incoming, bool upper = true}) =>
          transitionPose(t, p, incoming: incoming, upper: upper);
      // Crossfade: the lower layer is solid, the upper one carries the mix.
      expect(pose(TransitionType.crossfade, 0.25, incoming: true).opacity, 0.25);
      expect(pose(TransitionType.crossfade, 0.25, incoming: false).opacity, 0.75);
      expect(
          pose(TransitionType.crossfade, 0.25, incoming: true, upper: false)
              .opacity,
          1);
      // Fade through black, with the weights measured from ffmpeg's
      // xfade=fadeblack: out within the first fifth, then in.
      double fb(double p, {required bool incoming}) =>
          pose(TransitionType.fadeBlack, p, incoming: incoming).opacity;
      expect(fb(0, incoming: false), 1);
      expect(fb(0, incoming: true), 0);
      expect(fb(0.1, incoming: false), closeTo(0.45, 0.005));
      expect(fb(0.2, incoming: false), 0);
      expect(fb(0.2, incoming: true), closeTo(0.031, 0.005));
      expect(fb(0.5, incoming: true), closeTo(0.342, 0.005));
      expect(fb(0.8, incoming: true), closeTo(0.8, 0.005));
      expect(fb(1, incoming: true), 1);
      expect(fb(1, incoming: false), 0);
      // Slides push: the two layers always sit side by side.
      expect(pose(TransitionType.slideLeft, 0.25, incoming: true).offset,
          const Offset(0.75, 0));
      expect(pose(TransitionType.slideLeft, 0.25, incoming: false).offset,
          const Offset(-0.25, 0));
      expect(pose(TransitionType.slideUp, 1, incoming: true).offset, Offset.zero);
      expect(pose(TransitionType.slideUp, 1, incoming: false).offset,
          const Offset(0, -1));
    });
  });

  group('music', () {
    AudioClip music({int start = 1000, int fadeIn = 0, int fadeOut = 0}) =>
        AudioClip(
          id: 'm',
          path: '/m.mp3',
          sourceDurationMs: 60000,
          startMs: start,
          inMs: 5000,
          outMs: 8000,
          volume: 0.8,
          fadeInMs: fadeIn,
          fadeOutMs: fadeOut,
        );

    test('starts in sync when the playhead reaches it and stops after',
        () async {
      final c = make(project([photo('p1', 10000)], audio: [music()]));
      c.play();
      c.tick(16);
      await settle();
      // Loaded ahead of time, waiting at its first sample.
      expect(audioPlayers.single.log, ['open /m.mp3@5000 paused']);
      c.tick(984); // t = 1000
      c.tick(16);
      await settle();
      expect(audioPlayers.single.log,
          ['open /m.mp3@5000 paused', 'volume 0.80', 'play']);
      expect(audioPlayers.single.playing, isTrue);
      c.tick(3200); // t = 4216, past the end at 4000
      await settle();
      expect(audioPlayers.single.playing, isFalse);
    });

    test('is not loaded long before its turn', () async {
      final c = make(project([photo('p1', 10000)],
          audio: [music(start: 5000)]));
      c.play();
      c.tick(3000);
      await settle();
      expect(audioPlayers, isEmpty);
      c.tick(600);
      await settle();
      expect(audioPlayers.single.log, ['open /m.mp3@5000 paused']);
      // A jump into it does not rely on the waiting player's position.
      c.seek(6000);
      await settle();
      expect(audioPlayers.single.log.sublist(1),
          ['volume 0.80', 'seek 6000', 'play']);
    });

    test('a playhead that arrives late moves the waiting music on', () async {
      final c = make(project([photo('p1', 10000)], audio: [music()]));
      c.play();
      c.tick(500);
      await settle();
      c.tick(700); // t = 1200, 200 ms into the music
      await settle();
      expect(audioPlayers.single.log.sublist(1),
          ['volume 0.80', 'seek 5200', 'play']);
    });

    test('pause, resume and seek keep it aligned', () async {
      final c = make(project([photo('p1', 10000)], audio: [music()]));
      c.seek(2000);
      c.play();
      await settle();
      final a = audioPlayers.single;
      expect(a.log.last, 'open /m.mp3@6000 play');
      c.pause();
      await settle();
      expect(a.playing, isFalse);
      c.seek(3000);
      c.play();
      await settle();
      expect(a.log.sublist(a.log.length - 2), ['seek 7000', 'play']);
      c.seek(500);
      await settle();
      expect(a.playing, isFalse);
    });

    test('catches up when loading the file took a while', () async {
      final slow = SlowOpenPlayer();
      final c = PlaybackController(
        project: project([photo('p1', 10000)], audio: [music()]),
        video: FakePlayer(),
        createAudioPlayer: () => slow,
        fileExists: (_) => true,
      );
      addTearDown(c.dispose);
      c.seek(1200);
      c.play();
      await settle();
      expect(slow.log.last, 'open /m.mp3@5200 play');
      c.tick(400); // the picture plays on while the music file loads
      slow.finishOpen();
      await settle();
      expect(slow.log.last, 'seek 5600');
    });

    test('fades scale the volume', () {
      final a = music(fadeIn: 1000, fadeOut: 1000);
      expect(PlaybackController.audioGain(a, 999), 0);
      expect(PlaybackController.audioGain(a, 1500), closeTo(0.4, 1e-9));
      expect(PlaybackController.audioGain(a, 2500), closeTo(0.8, 1e-9));
      expect(PlaybackController.audioGain(a, 3500), closeTo(0.4, 1e-9));
      expect(PlaybackController.audioGain(a, 4000), 0);

      // Cut off by the end of the video at 3 s: the fade-out ends there.
      expect(PlaybackController.audioGain(a, 2500, audibleEndMs: 3000),
          closeTo(0.4, 1e-9));
      expect(PlaybackController.audioGain(a, 2000, audibleEndMs: 3000),
          closeTo(0.8, 1e-9));
      expect(PlaybackController.audioGain(a, 3000, audibleEndMs: 3000), 0);
      // An end after its own end changes nothing.
      expect(PlaybackController.audioGain(a, 3500, audibleEndMs: 9000),
          closeTo(0.4, 1e-9));
    });

    test('music that outlasts the video fades out at the video\'s end',
        () async {
      // The video is 3 s long; the music would play from 1 s to 4 s.
      final c = make(
          project([photo('p1', 3000)], audio: [music(fadeOut: 1000)]));
      c.seek(2500);
      c.play();
      await settle();
      expect(audioPlayers.single.log.first, 'volume 0.40');
      c.tick(250); // 2.75 s
      await settle();
      expect(audioPlayers.single.volume, closeTo(0.2, 0.005));
    });

    test('removing the clip disposes its player', () async {
      final c = make(project([photo('p1', 10000)], audio: [music()]));
      c.seek(2000);
      c.play();
      await settle();
      c.updateProject(project([photo('p1', 10000)]));
      await settle();
      expect(audioPlayers.single.disposed, isTrue);
    });
  });
}
