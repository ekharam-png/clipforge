// "Lower music under speech" is ONE truth since 1.15: each track's own
// switch (SoundTrack.duck) is what the export uses; the project-level
// control reports all / some / none of the tracks that are not speech and
// sets them all (lib/core/editor/sound_tracks.dart, lowerMusicState).

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/editor/sound_tracks.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

Project _project({List<SoundTrack> tracks = const [], bool duckMusic = false}) =>
    Project(
      id: 'p',
      name: 'P',
      createdAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 19),
      duckMusic: duckMusic,
      clips: const [
        Clip(
            id: 'v',
            type: ClipType.video,
            path: '/v.mp4',
            sourceDurationMs: 20000,
            inMs: 0,
            outMs: 20000,
            width: 1920,
            height: 1080),
      ],
      tracks: tracks,
      audio: [
        for (final t in tracks)
          AudioClip(
              id: 'a-${t.id}',
              path: '/${t.id}.mp3',
              sourceDurationMs: 60000,
              startMs: 0,
              inMs: 0,
              outMs: 10000,
              trackId: t.id),
      ],
    );

const _voice = SoundTrack(id: 'voice', name: 'Voice', speech: true);
const _music = SoundTrack(id: 'm1', name: 'Music');
const _music2 = SoundTrack(id: 'm2', name: 'Music 2');

void main() {
  test('all / some / none over the tracks that are not speech', () {
    expect(lowerMusicState(_project(tracks: [_voice, _music, _music2])),
        LowerMusic.none);
    expect(
        lowerMusicState(_project(
            tracks: [_voice, _music.copyWith(duck: true), _music2])),
        LowerMusic.some);
    expect(
        lowerMusicState(_project(tracks: [
          _voice,
          _music.copyWith(duck: true),
          _music2.copyWith(duck: true),
        ])),
        LowerMusic.all);
    // A speech track is never counted, whatever its switch says.
    expect(
        lowerMusicState(_project(tracks: [
          _voice.copyWith(duck: true),
          _music,
        ])),
        LowerMusic.none);
    expect(lowerableTracks(_project(tracks: [_voice, _music])).single.id, 'm1');
  });

  test('no music track yet: the default for the next one', () {
    expect(lowerMusicState(_project()), LowerMusic.none);
    expect(lowerMusicState(_project(duckMusic: true)), LowerMusic.all);
  });

  test('the project control sets every music track; undo is one step', () {
    final e = ProjectEditor(_project(tracks: [
      _voice,
      _music.copyWith(duck: true),
      _music2,
    ]));
    expect(lowerMusicState(e.project), LowerMusic.some);
    e.setDuckMusic(true);
    expect(lowerMusicState(e.project), LowerMusic.all);
    expect(e.project.soundTracks.firstWhere((t) => t.id == 'voice').duck,
        isFalse);
    e.undo();
    expect(lowerMusicState(e.project), LowerMusic.some);
    e.setDuckMusic(false);
    expect(lowerMusicState(e.project), LowerMusic.none);
  });

  test('a track switch moves the project state, and the default with it',
      () {
    final e = ProjectEditor(_project(tracks: [_music, _music2]));
    e.setSoundTrack('m1', duck: true);
    expect(lowerMusicState(e.project), LowerMusic.some);
    expect(e.project.duckMusic, isFalse);
    e.setSoundTrack('m2', duck: true);
    expect(lowerMusicState(e.project), LowerMusic.all);
    // The default for music tracks made later follows the tracks.
    expect(e.project.duckMusic, isTrue);
    final id = e.addSoundTrack(name: 'Music 3');
    expect(id, isNotNull);
    expect(e.project.soundTracks.firstWhere((t) => t.id == id).duck, isTrue);
    e.setSoundTrack('m1', duck: false);
    expect(lowerMusicState(e.project), LowerMusic.some);
    expect(e.project.duckMusic, isFalse);
    // Making a track a speech track takes it out of the count.
    e.setSoundTrack('m1', speech: true);
    expect(lowerMusicState(e.project), LowerMusic.all);
    expect(e.project.duckMusic, isTrue);
  });

  test('History names one track by itself, and the project switch as such',
      () {
    final one = ProjectEditor(_project(tracks: [_voice, _music, _music2]))
      ..setSoundTrack('m1', duck: true);
    expect(one.history.last.label, 'Lower Music under speech on');
    final all = ProjectEditor(_project(tracks: [_voice, _music, _music2]))
      ..setDuckMusic(true);
    expect(all.history.last.label, 'Lower music under speech on');
    // The only music track: its own switch is still named as the track.
    final s = ProjectEditor(_project(tracks: [_voice, _music]))
      ..setSoundTrack('m1', duck: true);
    expect(s.project.duckMusic, isTrue);
    expect(s.history.last.label, 'Lower Music under speech on');
  });
}
