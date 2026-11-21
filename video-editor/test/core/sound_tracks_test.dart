// Sound tracks: the model (old projects, JSON), the overlap rules, per-track
// settings, separating a clip's sound and how it follows its clip, undo and
// History names.
import 'dart:convert';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ProjectEditor ed(Project p) {
  var n = 0;
  var now = t0;
  return ProjectEditor(p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'id${++n}');
}

List<String> labels(ProjectEditor e) => [for (final h in e.history) h.label];

AudioClip music(String id, {int start = 0, int length = 4000, String? track}) =>
    AudioClip(
      id: id,
      path: '/media/$id.mp3',
      sourceDurationMs: 60000,
      startMs: start,
      inMs: 0,
      outMs: length,
      trackId: track ?? kMusicTrackId,
    );

Map<String, dynamic> roundTrip(Project p) =>
    jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;

void main() {
  group('model', () {
    test('an old project gets a Music track that keeps "lower music"', () {
      final old = project(audio: [music('m'), music('n', start: 8000)])
          .copyWith(duckMusic: true)
          .toJson()
        ..remove('tracks')
        ..remove('videoSound')
        ..remove('videoSize');
      for (final a in old['audio'] as List) {
        (a as Map).remove('trackId');
      }
      final p = Project.fromJson(jsonDecode(jsonEncode(old)));
      expect([for (final t in p.tracks) t.name], ['Music']);
      expect(p.tracks.single.duck, isTrue);
      expect({for (final a in p.audio) a.trackId}, {kMusicTrackId});
      expect(p.videoSound.volume, 1);
      expect(p.videoSize, VideoSize.matchFirstClip);
    });

    test('old overlapping music is spread over Music, Music 2, ...', () {
      final old = project(audio: [
        music('a', start: 0, length: 5000),
        music('b', start: 1000, length: 5000),
        music('c', start: 5000, length: 1000),
        music('d', start: 2000, length: 1000),
      ]).toJson()
        ..remove('tracks');
      final p = Project.fromJson(jsonDecode(jsonEncode(old)));
      expect([for (final t in p.tracks) t.name], ['Music', 'Music 2', 'Music 3']);
      final track = {for (final a in p.audio) a.id: a.trackId};
      expect(track['a'], kMusicTrackId);
      expect(track['c'], kMusicTrackId);
      expect(track['b'], isNot(kMusicTrackId));
      expect(track['d'], isNot(anyOf(kMusicTrackId, track['b'])));
    });

    test('tracks, video sound, size and separated sound round-trip', () {
      final p = project(audio: [
        music('m').copyWith(
            trackId: 't1',
            speed: 1.25,
            denoise: true,
            voiceFocus: 0.5,
            audioTrack: 1,
            audioChannel: AudioChannel.left,
            audioStreams: [2, 2],
            sourceClipId: 'c1',
            linked: true),
      ]).copyWith(
        tracks: const [
          SoundTrack(id: 't1', name: 'Voice', speech: true, volume: 0.8),
          SoundTrack(id: 't2', name: 'FX', muted: true, solo: true, duck: true),
        ],
        videoSound: SoundTrack.video.copyWith(muted: true, volume: 0.5),
        videoSize: VideoSize.p1080,
      );
      final back = Project.fromJson(roundTrip(p));
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
      expect(back.audio.single.durationMs, (4000 / 1.25).round());
      expect(back.audio.single.soundClip.denoise, isTrue);
      expect(back.audio.single.soundClip.audioChannelInUse, AudioChannel.left);
    });

    test('music without a listed track still has one', () {
      final p = project(audio: [music('m', track: 'x')]);
      expect([for (final t in p.soundTracks) t.name], ['Sound']);
      expect(project(audio: [music('m')]).soundTracks.single.name, 'Music');
    });

    test('solo and mute decide the gain of a track', () {
      final p = project().copyWith(tracks: const [
        SoundTrack(id: 'a', name: 'A', volume: 0.5),
        SoundTrack(id: 'b', name: 'B', solo: true),
        SoundTrack(id: 'c', name: 'C', muted: true, solo: true),
      ]);
      expect(p.anySolo, isTrue);
      expect(p.trackGainOf('a'), 0);
      expect(p.trackGainOf('b'), 1);
      expect(p.trackGainOf('c'), 0);
      expect(p.trackGain(p.videoSound), 0);
    });

    test('video size scales the canvas by its short side', () {
      final small = Clip(
          id: 'w',
          type: ClipType.video,
          path: '/w.mp4',
          sourceDurationMs: 5000,
          inMs: 0,
          outMs: 5000,
          width: 464,
          height: 824);
      final p = project(clips: [small]);
      expect(p.canvasSize, (width: 464, height: 824));
      expect(p.copyWith(videoSize: VideoSize.p1080).canvasSize,
          (width: 1080, height: 1920),
          reason: '1.18: the standard width, not 1918');
      expect(p.copyWith(videoSize: VideoSize.p720).canvasSize.width, 720);
      expect(
          p
              .copyWith(
                  videoSize: VideoSize.p2160, aspect: CanvasAspect.landscape16x9)
              .canvasSize,
          (width: 3840, height: 2160));
      expect(project().copyWith(videoSize: VideoSize.p720).canvasSize,
          (width: 1280, height: 720));
    });
  });

  group('overlap rules', () {
    test('adding at a busy spot: first free track, else a new one, else after',
        () {
      final e = ed(project(clips: [video('v')]));
      e.addAudio(music('a', start: 0));
      e.addAudio(music('b', start: 1000));
      e.addAudio(music('c', start: 2000));
      expect(e.project.soundTracks.length, 3);
      final tracks = {for (final a in e.project.audio) a.id: a.trackId};
      expect(tracks.values.toSet().length, 3);
      // A fourth at a spot where all three are busy goes after the overlap
      // on the wanted track (the Music track).
      e.addAudio(music('d', start: 500));
      final d = e.project.audio.firstWhere((a) => a.id == 'd');
      expect(d.trackId, kMusicTrackId);
      expect(d.startMs, 4000);
      expect(e.project.soundTracks.length, ProjectEditor.maxSoundTracks);
      // A free spot on another track is used before a new track.
      e.addAudio(music('e', start: 6000, length: 500).copyWith(trackId: tracks['b']));
      expect(e.project.audio.last.trackId, tracks['b']);
    });

    test('moving stops at the neighbour or jumps past it, never overlaps', () {
      final e = ed(project(audio: [
        music('a', start: 0, length: 2000),
        music('b', start: 5000, length: 2000),
      ]));
      final b = e.project.audio[1];
      e.updateAudio(b.copyWith(startMs: 1500)); // into a: nearest free is 2000
      expect(e.project.audio[1].startMs, 2000);
      e.updateAudio(e.project.audio[1].copyWith(startMs: 300)); // nearer past a? no: 2000 is 1700 away, before a not possible
      expect(e.project.audio[1].startMs, 2000);
      e.updateAudio(music('a', start: 0, length: 2000).copyWith(startMs: 2500));
      // a moved right next to b's new place: nearest free start of a (2 s)
      // around 2500 is 4000 (b occupies 2000..4000).
      expect(e.project.audio[0].startMs, 4000);
    });

    test('trimming stops at the neighbours', () {
      final e = ed(project(audio: [
        music('a', start: 0, length: 2000),
        music('b', start: 3000, length: 2000).copyWith(inMs: 1000, outMs: 3000),
      ]));
      final b = e.project.audio[1];
      // Start edge dragged 2 s earlier: stops at the end of a.
      e.updateAudio(b.copyWith(inMs: 0, startMs: 2000));
      expect([e.project.audio[1].startMs, e.project.audio[1].inMs], [2000, 0]);
      final a = e.project.audio[0];
      e.updateAudio(a.copyWith(outMs: 5000));
      expect(e.project.audio[0].endMs, 2000);
    });

    test('moving to another track lands at the nearest free spot there', () {
      final e = ed(project(audio: [
        music('a', start: 0, length: 3000),
        music('b', start: 0, length: 3000, track: 'fx'),
      ]).copyWith(tracks: const [
        SoundTrack(id: kMusicTrackId, name: 'Music'),
        SoundTrack(id: 'fx', name: 'Effects'),
      ]));
      e.moveAudioToTrack('b', kMusicTrackId, startMs: 1000);
      final b = e.project.audio[1];
      expect(b.trackId, kMusicTrackId);
      expect(b.startMs, 3000);
      expect(labels(e).last, 'Moved music to Music track');
      e.moveAudioToTrack('b', 'nope');
      expect(e.project.audio[1].trackId, kMusicTrackId);
    });
  });

  group('tracks', () {
    test('add (max 3), rename, settings, delete only when empty; history', () {
      final e = ed(project(clips: [video('v')]));
      final voice = e.addSoundTrack()!;
      final musicT = e.addSoundTrack()!;
      final fx = e.addSoundTrack()!;
      expect(e.addSoundTrack(), isNull);
      expect([for (final t in e.project.soundTracks) t.name],
          ['Voice', 'Music', 'Effects']);
      expect(e.project.trackById(voice)!.speech, isTrue);
      e.renameSoundTrack(fx, '  Crowd  ');
      e.setSoundTrack(musicT, volume: 3);
      e.setSoundTrack(musicT, muted: true);
      e.setSoundTrack(musicT, muted: false);
      e.setSoundTrack(voice, solo: true);
      e.setSoundTrack(musicT, duck: true);
      e.setSoundTrack(SoundTrack.videoId, muted: true, duck: true);
      e.setSoundTrack(SoundTrack.videoId, volume: 0.5);
      expect(e.project.trackById(musicT)!.volume, ProjectEditor.maxVolume);
      expect(e.project.videoSound.duck, isFalse);
      e.addAudio(music('m', track: musicT));
      expect(e.removeSoundTrack(musicT), isFalse);
      expect(e.removeSoundTrack(fx), isTrue);
      expect(labels(e), [
        'Added sound track Voice',
        'Added sound track Music',
        'Added sound track Effects',
        "Renamed track to 'Crowd'",
        'Music track volume 200%',
        'Muted Music track',
        'Unmuted Music track',
        'Solo Voice track',
        'Lower Music under speech on',
        'Muted video sound',
        'Video sound volume 50%',
        'Added music',
        'Deleted sound track Crowd',
      ]);
      e.undo();
      expect(e.project.soundTracks.length, 3);
    });

    test('lower music under speech: all music tracks, and the default', () {
      final e = ed(project());
      e.setDuckMusic(true);
      e.addAudio(music('m'));
      expect(e.project.soundTracks.single.duck, isTrue);
      final v = e.addSoundTrack(name: 'Voice')!;
      e.setDuckMusic(false);
      expect(e.project.trackById(kMusicTrackId)!.duck, isFalse);
      expect(e.project.trackById(v)!.duck, isFalse);
      expect(labels(e).last, 'Lower music under speech off');
    });
  });

  group('separate sound', () {
    Project podcast() => project(clips: [
          video('a', source: 10000, inMs: 1000, outMs: 5000)
              .copyWith(denoise: true, voiceFocus: 0.4, volume: 0.8),
          video('b', source: 10000, inMs: 0, outMs: 3000, speed: 1.5),
        ]);

    test('makes a linked sound on a new Voice track and mutes the clip', () {
      final e = ed(podcast());
      final id = e.separateSound('a')!;
      final a = e.project.audio.single;
      expect(a.id, id);
      expect(e.project.soundTracks.single.name, 'Voice');
      expect(e.project.soundTracks.single.speech, isTrue);
      expect([a.startMs, a.inMs, a.outMs], [0, 1000, 5000]);
      expect(a.volume, 0.8);
      expect(a.denoise, isTrue);
      expect(a.voiceFocus, 0.4);
      expect(a.linked, isTrue);
      expect(a.sourceClipId, 'a');
      expect(e.project.clips.first.muted, isTrue);
      expect(ProjectEditor.separateSoundProblem(e.project, 'a'),
          'The sound of this clip is already separated.');
      expect(e.separateSound('a'), isNull);
      expect(labels(e), ['Separated sound of clip 1']);
      e.undo();
      expect(e.project.audio, isEmpty);
      expect(e.project.clips.first.muted, isFalse);
    });

    test('carries the speed over', () {
      final e = ed(podcast());
      e.separateSound('b');
      final b = e.project.audio.single;
      expect(b.speed, 1.5);
      expect(b.startMs, 4000);
      expect(b.durationMs, 2000);
      expect(b.endMs, e.project.durationMs);
    });

    test('refuses photos and silent clips', () {
      final e = ed(project(clips: [photo('p'), video('v')]));
      expect(e.separateSound('p'), isNull);
      expect(ProjectEditor.separateSoundProblem(e.project, 'p'),
          contains('photo'));
      expect(e.history, isEmpty);
    });

    test('all clips at once, one undo step; transitions do not overlap', () {
      final e = ed(project(clips: [
        video('a', source: 4000),
        video('b', source: 4000, transition: TransitionType.crossfade),
      ]));
      expect(e.separateAllSound(), 2);
      final s = e.project.clipsOnTrack(e.project.soundTracks.single.id);
      expect(s.length, 2);
      expect(s[0].endMs, lessThanOrEqualTo(s[1].startMs));
      expect(s[1].startMs, 4000); // after the 500 ms crossfade
      expect(s[1].inMs, 500);
      expect(labels(e), ['Separated sound of 2 clips']);
    });

    test('a linked sound follows trims, moves, speed, splits and deletes', () {
      final e = ed(project(clips: [video('x', source: 6000), video('a')]));
      e.separateSound('a');
      String one() => e.project.audio.single.id;
      final first = one();
      e.removeClip('x');
      expect(e.project.audio.single.startMs, 0);
      e.trimClip('a', inMs: 2000);
      expect([e.project.audio.single.inMs, e.project.audio.single.startMs],
          [2000, 0]);
      e.setClipSpeed('a', 2);
      expect(e.project.audio.single.speed, 2);
      expect(e.project.audio.single.durationMs, 4000);
      expect(e.splitAt(2000), isTrue);
      expect(e.project.audio.length, 2);
      final pieces = e.project.audio;
      expect(pieces.first.id, first);
      expect(pieces.map((a) => a.sourceClipId).toSet(),
          {for (final c in e.project.clips) c.id});
      expect(pieces[1].startMs, pieces[0].endMs);
      expect(pieces.every((a) => a.linked && a.denoise == false), isTrue);
      expect(labels(e).last, 'Split clip 1');
      e.removeClip(e.project.clips.last.id);
      expect(e.project.audio.length, 1);
      e.undo();
      e.undo();
      expect(e.project.audio.length, 1);
    });

    test('remove silences gives every piece its own linked sound', () {
      final e = ed(project(clips: [video('a', source: 10000)]));
      e.separateSound('a');
      expect(
          e.removeSourceRanges('a', [
            (startMs: 2000, endMs: 3000),
            (startMs: 6000, endMs: 7000),
          ]),
          2);
      expect(e.project.clips.length, 3);
      expect(e.project.audio.length, 3);
      for (var i = 0; i < 3; i++) {
        final c = e.project.clips[i];
        final a = e.project.audio.firstWhere((a) => a.sourceClipId == c.id);
        expect([a.startMs, a.inMs, a.outMs],
            [e.project.clipStartMs(i), c.inMs, c.outMs]);
      }
      expect(labels(e).last, 'Removed 2 silences');
    });

    test('moving the sound by hand unlinks it; then it stays put', () {
      final e = ed(project(clips: [video('x', source: 3000), video('a')]));
      e.separateSound('a');
      final s = e.project.audio.single;
      e.updateAudio(s.copyWith(startMs: s.startMs - 1000)); // J-cut
      expect(e.project.audio.single.linked, isFalse);
      expect(e.project.audio.single.startMs, 2000);
      expect(labels(e).last, 'Moved sound');
      e.removeClip('x');
      expect(e.project.audio.single.startMs, 2000);
      // A volume change keeps the link.
      final e2 = ed(project(clips: [video('a')]));
      e2.separateSound('a');
      e2.updateAudio(e2.project.audio.single.copyWith(volume: 0.5));
      expect(e2.project.audio.single.linked, isTrue);
    });

    test('reattach puts the sound back on the clip', () {
      final e = ed(project(clips: [video('a')]));
      final id = e.separateSound('a')!;
      e.setAudioDenoise(id, true);
      e.updateAudio(e.project.audio.single.copyWith(volume: 0.6));
      expect(e.reattachSound(id), isTrue);
      expect(e.project.audio, isEmpty);
      final c = e.project.clips.single;
      expect([c.muted, c.denoise, c.volume], [false, true, 0.6]);
      expect(labels(e).last, 'Put sound back on clip 1');
      expect(e.reattachSound('nope'), isFalse);
    });

    test('uses an existing speech track, and the chosen one', () {
      final e = ed(project(clips: [video('a'), video('b')]));
      final fx = e.addSoundTrack(name: 'Effects')!;
      final v = e.addSoundTrack(name: 'Voice')!;
      e.separateSound('a');
      expect(e.project.audio.single.trackId, v);
      e.separateSound('b', trackId: fx);
      expect(e.project.audio.last.trackId, fx);
      expect(e.project.soundTracks.length, 2);
    });

    test('sound settings of a sound clip are clamped and named', () {
      final e = ed(project(clips: [video('a')]));
      final id = e.separateSound('a')!;
      e.setAudioVoiceFocus(id, 3);
      e.setAudioSource(id, channel: AudioChannel.left); // no stereo known
      expect(e.project.audio.single.voiceFocus, 1);
      expect(e.project.audio.single.audioChannel, AudioChannel.both);
      expect(labels(e).last, 'Voice focus 100% on sound');
    });
  });
}
