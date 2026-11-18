// The preview plays every sound track in step: overlapping clips on
// different tracks each get a player (two per track at most), track
// volume / mute / solo apply live, a separated sound plays at its clip's
// speed with its own sound options, and the video's own sound follows the
// video sound settings.
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Clip photo(String id, int ms) => Clip(
      id: id,
      type: ClipType.photo,
      path: '/p/$id.jpg',
      sourceDurationMs: 0,
      inMs: 0,
      outMs: ms,
      width: 1000,
      height: 1000,
      hasAudio: false,
    );

AudioClip snd(String id, String track, {int start = 0, int length = 4000}) =>
    AudioClip(
      id: id,
      path: '/s/$id.m4a',
      sourceDurationMs: 60000,
      startMs: start,
      inMs: 0,
      outMs: length,
      trackId: track,
    );

const tracks = [
  SoundTrack(id: 'v', name: 'Voice', speech: true),
  SoundTrack(id: 'm', name: 'Music'),
  SoundTrack(id: 'e', name: 'Effects'),
];

Project proj(List<Clip> clips, List<AudioClip> audio,
        {List<SoundTrack> t = tracks, SoundTrack video = SoundTrack.video}) =>
    Project(
      id: 'p',
      name: 'p',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: clips,
      audio: audio,
      tracks: t,
      videoSound: video,
    );

void main() {
  late List<FakePlayer> audioPlayers;
  late FakePlayer video;

  PlaybackController make(Project p, {String? Function(Clip)? processed}) {
    audioPlayers = [];
    video = FakePlayer();
    final c = PlaybackController(
      project: p,
      video: video,
      createAudioPlayer: () {
        final a = FakePlayer();
        audioPlayers.add(a);
        return a;
      },
      fileExists: (_) => true,
    );
    if (processed != null) c.processedSound = processed;
    addTearDown(c.dispose);
    return c;
  }

  FakePlayer playerOf(String file) =>
      audioPlayers.firstWhere((p) => p.path == file);

  test('three tracks overlap: one player each, all in step', () async {
    final c = make(proj([photo('p', 10000)], [
      snd('vo', 'v', start: 0),
      snd('mu', 'm', start: 0, length: 9000),
      snd('fx', 'e', start: 1000, length: 1000),
    ]));
    c.seek(1500);
    c.play();
    await settle();
    expect(audioPlayers.length, 3);
    for (final f in ['/s/vo.m4a', '/s/mu.m4a', '/s/fx.m4a']) {
      expect(playerOf(f).playing, isTrue, reason: f);
    }
    expect(playerOf('/s/vo.m4a').positionMs, 1500);
    expect(playerOf('/s/fx.m4a').positionMs, 500);
    c.tick(1000); // 2.5 s: the effect is over
    await settle();
    expect(playerOf('/s/fx.m4a').playing, isFalse);
    expect(playerOf('/s/mu.m4a').playing, isTrue);
  });

  test('clips one after another on a track reuse its two players', () async {
    final c = make(proj([photo('p', 30000)], [
      for (var i = 0; i < 12; i++) snd('a$i', 'v', start: i * 2000, length: 2000),
    ]));
    c.play();
    for (var t = 0; t < 24000; t += 100) {
      c.tick(100);
      await settle();
    }
    expect(audioPlayers.length, lessThanOrEqualTo(2));
    expect(audioPlayers.any((p) => p.log.contains('open /s/a11.m4a@0 paused')),
        isTrue, reason: 'the next clip waits loaded');
  });

  test('track volume, mute and solo apply while playing', () async {
    var p = proj([photo('p', 10000)], [
      snd('vo', 'v'),
      snd('mu', 'm'),
    ]);
    final c = make(p);
    c.seek(500);
    c.play();
    await settle();
    final music = playerOf('/s/mu.m4a');
    expect(music.volume, 1);
    final e = ProjectEditor(p);
    e.setSoundTrack('m', volume: 0.5);
    c.updateProject(e.project);
    await settle();
    expect(music.volume, closeTo(0.5, 0.001));
    e.setSoundTrack('m', muted: true);
    c.updateProject(e.project);
    await settle();
    expect(music.playing, isFalse);
    e.setSoundTrack('m', muted: false);
    e.setSoundTrack('v', solo: true);
    c.updateProject(e.project);
    await settle();
    expect(music.playing, isFalse);
    expect(playerOf('/s/vo.m4a').playing, isTrue);
    e.setSoundTrack('v', solo: false);
    p = e.project;
    c.updateProject(p);
    c.tick(16);
    await settle();
    expect(audioPlayers.where((a) => a.playing).length, 2);
  });

  test('the video sound settings set the level of the video player', () async {
    final clip = Clip(
        id: 'c',
        type: ClipType.video,
        path: '/v.mp4',
        sourceDurationMs: 9000,
        inMs: 0,
        outMs: 9000,
        width: 640,
        height: 360);
    final e = ProjectEditor(proj([clip], const []));
    final c = make(e.project);
    await settle();
    e.setSoundTrack(SoundTrack.videoId, volume: 0.5);
    c.updateProject(e.project);
    await settle();
    expect(video.volume, closeTo(0.5, 0.001));
    e.setSoundTrack(SoundTrack.videoId, muted: true);
    c.updateProject(e.project);
    await settle();
    expect(video.volume, 0);
  });

  test('separated sound: muted picture, sound at the clip speed, processed '
      'file when ready', () async {
    final clip = Clip(
      id: 'c',
      type: ClipType.video,
      path: '/talk.mp4',
      sourceDurationMs: 20000,
      inMs: 2000,
      outMs: 8000,
      width: 640,
      height: 360,
      speed: 1.5,
      denoise: true,
    );
    final e = ProjectEditor(proj([clip], const [], t: const []));
    e.separateSound('c');
    var ready = false;
    final c = make(e.project,
        processed: (x) => ready && x.id == e.project.audio.single.id ? '/cache/snd.flac' : null);
    c.seek(1000);
    c.play();
    await settle();
    expect(video.volume, 0, reason: 'the clip is muted');
    final s = audioPlayers.single;
    expect(s.path, '/talk.mp4');
    expect(s.rate, 1.5);
    expect(s.positionMs, 3500);
    // Clean-up's live part (low cut) is on until the processed file is there.
    expect(s.audioFilter, contains('equalizer'));
    ready = true;
    c.soundFilesChanged();
    await settle();
    expect(audioPlayers.where((a) => a.path == '/cache/snd.flac' && a.playing),
        hasLength(1));
    final now = audioPlayers.firstWhere((a) => a.path == '/cache/snd.flac');
    expect(now.audioFilter, '');
    c.hearOriginalSound = true;
    await settle();
    expect(audioPlayers.where((a) => a.path == '/talk.mp4' && a.playing), hasLength(1));
    c.hearOriginalSound = false;
  });

  test('a linked voice is kept in step with the picture; music is left alone',
      () async {
    // 1.10: a voice recorded separately plays its own file at the clip's
    // source time + offset, and is put back when it drifts from the
    // picture (lip sync), like processed clip sound.
    final clip = Clip(
      id: 'c',
      type: ClipType.video,
      path: '/cam.mp4',
      sourceDurationMs: 60000,
      inMs: 2000,
      outMs: 32000,
      width: 100,
      height: 100,
    );
    final e = ProjectEditor(proj([clip], [snd('song', 'm', length: 30000)]));
    e.addVoice(
        const AudioClip(
            id: 'x',
            path: '/mic.m4a',
            sourceDurationMs: 60000,
            startMs: 0,
            inMs: 0,
            outMs: 60000),
        clipId: 'c',
        offsetMs: 420);
    final c = make(e.project);
    c.play();
    await settle();
    expect(video.volume, 0, reason: 'the camera is muted');
    final voice = audioPlayers.firstWhere((a) => a.path == '/mic.m4a');
    final song = audioPlayers.firstWhere((a) => a.path == '/s/song.m4a');
    // Timeline 0 = camera file 2 s = voice file 2.42 s.
    expect(voice.positionMs, 2420);
    expect(voice.playing, isTrue);
    video.emitPosition(2000);
    await settle();
    voice.log.clear();
    song.log.clear();
    // The picture is at 7 s of its file; the voice 150 ms ahead of where
    // it belongs (7.42 s), several reports in a row.
    for (var i = 0; i < 6; i++) {
      video.emitPosition(7000 + i * 10);
      voice.emitPosition(7570 + i * 10);
      song.emitPosition(5300 + i * 10); // music, also off: not touched
    }
    await settle();
    expect(c.voiceCorrections, 1);
    final seeks = voice.log.where((l) => l.startsWith('seek')).toList();
    expect(seeks, hasLength(1));
    expect(int.parse(seeks.single.split(' ').last), closeTo(7470, 100));
    expect(song.log.where((l) => l.startsWith('seek')), isEmpty);
    // In step (a few ms) and a little late: left alone.
    voice.log.clear();
    for (var i = 0; i < 8; i++) {
      video.emitPosition(9000 + i * 10);
      voice.emitPosition(9425 + i * 10);
    }
    for (var i = 0; i < 8; i++) {
      video.emitPosition(11000 + i * 10);
      voice.emitPosition(11360 + i * 10);
    }
    await settle();
    expect(voice.log.where((l) => l.startsWith('seek')), isEmpty);
    expect(c.voiceCorrections, 1);
  });
}
