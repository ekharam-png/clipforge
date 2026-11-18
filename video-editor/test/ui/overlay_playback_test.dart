// The overlay track in the preview's PlaybackController: its own players
// on the timeline clock, the next item loaded ahead, the frame shown while
// paused, its sound level, putting a drifting player back.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

Clip still(String id, int ms) => Clip(
      id: id,
      type: ClipType.photo,
      path: '/p/$id.jpg',
      sourceDurationMs: 0,
      inMs: 0,
      outMs: ms,
      width: 1920,
      height: 1080,
      hasAudio: false,
    );

OverlayClip ov(String id, int startMs,
        {int inMs = 0,
        int outMs = 2000,
        double speed = 1,
        double volume = 1,
        bool muted = false,
        bool photo = false,
        int fadeInMs = 0}) =>
    OverlayClip(
      startMs: startMs,
      fadeInMs: fadeInMs,
      clip: Clip(
        id: id,
        type: photo ? ClipType.photo : ClipType.video,
        path: '/o/$id.${photo ? 'jpg' : 'mp4'}',
        sourceDurationMs: photo ? 0 : 60000,
        inMs: inMs,
        outMs: outMs,
        width: 1280,
        height: 720,
        speed: speed,
        volume: volume,
        muted: muted,
        hasAudio: !photo,
      ),
    );

Project project(List<OverlayClip> overlays, {int mainMs = 10000}) => Project(
      id: 'p',
      name: 'Test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: [still('m', mainMs)],
      overlays: overlays,
    );

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<FakePlayer> made;
  PlaybackController controller(Project p) {
    made = [];
    final c = PlaybackController(
      project: p,
      video: FakePlayer(name: 'main'),
      createVideoPlayer: () {
        final pl = FakePlayer(name: 'video ${made.length}');
        made.add(pl);
        return pl;
      },
      createAudioPlayer: FakePlayer.new,
      fileExists: (_) => true,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('no overlays, no overlay players', () async {
    final c = controller(project(const []));
    c.play();
    c.tick(500);
    await settle();
    expect(c.overlayPlayers, isEmpty);
    expect(c.overlay, isNull);
  });

  test('paused on an overlay: its frame is loaded, then shown', () async {
    final c = controller(project([ov('a', 1000, inMs: 5000, outMs: 7000)]));
    c.seek(1500);
    await settle();
    expect(c.overlayPlayers, hasLength(1));
    final pl = made.single;
    expect(pl.log, contains('open /o/a.mp4@5500 paused'));
    final view = c.overlay!;
    expect(view.kind, PreviewLayerKind.video);
    expect(view.deck, 0);
    // Scrubbing seeks.
    c.seek(2000);
    await settle();
    expect(pl.log.last, 'pause');
    expect(pl.log, contains('seek 6000'));
    // Outside it: nothing shows.
    c.seek(5000);
    await settle();
    expect(c.overlay, isNull);
  });

  test('plays along at its speed and level; the next one waits loaded',
      () async {
    final c = controller(project([
      ov('a', 1000, outMs: 4000, speed: 2, volume: 0.5), // 1000..3000
      ov('b', 3000, inMs: 100, outMs: 2100), // 3000..5000
    ]));
    c.seek(1000);
    await settle();
    c.play();
    await settle();
    final a = made.first;
    expect(a.rate, 2);
    expect(a.volume, closeTo(0.5, 1e-9));
    expect(a.playing, isTrue);
    // 1.5 s before b: a second player loads it, paused, silent.
    c.tick(600);
    c.tick(600);
    await settle();
    expect(made, hasLength(2));
    final b = made[1];
    expect(b.log, contains('open /o/b.mp4@100 paused'));
    expect(b.volume, 0);
    // Into b: it just starts playing.
    for (var i = 0; i < 10; i++) {
      c.tick(100);
    }
    await settle();
    expect(c.overlayItem!.id, 'b');
    expect(b.playing, isTrue);
    expect(b.log.where((l) => l.startsWith('open')), hasLength(1));
    expect(c.overlay!.deck, 1);
    expect(a.playing, isFalse);
  });

  test('muted, faded and the video sound level', () async {
    final c = controller(project([ov('a', 0, fadeInMs: 1000)]));
    c.play();
    await settle();
    c.tick(500);
    await settle();
    expect(made.single.volume, closeTo(0.5, 0.05));
    c.updateProject(c.project.copyWith(
        videoSound: c.project.videoSound.copyWith(volume: 0.5)));
    c.tick(500);
    await settle();
    expect(made.single.volume, closeTo(0.5, 0.05));
    final muted = c.project.copyWith(overlays: [ov('a', 0, muted: true)]);
    c.updateProject(muted);
    c.tick(100);
    await settle();
    expect(made.single.volume, 0);
  });

  test('a photo overlay needs no player', () async {
    final c = controller(project([ov('p', 0, photo: true)]));
    c.seek(500);
    await settle();
    expect(c.overlay!.kind, PreviewLayerKind.photo);
    expect(c.overlayPlayers, isEmpty);
  });

  test('a player that drifts away from the clock is put back', () async {
    final c = controller(project([ov('a', 0, outMs: 9000)]));
    c.play();
    await settle();
    final pl = made.single;
    pl.emitPosition(0); // settles
    c.tick(3000);
    await settle();
    // The player says 1 s while the clock says 3 s.
    pl.emitPosition(1000);
    await settle();
    expect(pl.log.last, 'seek 3000');
  });

  test('an edit of the item under the playhead re-seeks it', () async {
    final c = controller(project([ov('a', 1000)]));
    c.seek(1500);
    await settle();
    c.updateProject(c.project.copyWith(overlays: [ov('a', 1000, inMs: 700)]));
    await settle();
    expect(made.single.log, contains('seek 1200'));
  });

  test('the next item is not loaded while paused', () {
    final c = controller(project([ov('a', 3000)]));
    c.seek(2000);
    expect(c.overlayPlayers, isEmpty);
  });
}
