// 1.10: a voice recorded separately, lined up with a video clip, follows
// that clip through every edit (the "separated sound follows its clip"
// rule extended to another file with an offset).
import 'dart:convert';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/editor/sound_tracks.dart';
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

AudioClip voiceFile(String name, {int length = 12000}) => AudioClip(
      id: 'tmp',
      path: '/media/$name.m4a',
      sourceDurationMs: length,
      startMs: 0,
      inMs: 0,
      outMs: length,
    );

/// Every linked voice item plays, at every moment, the voice file time
/// that belongs to the picture: clip source time + offset.
void expectInSync(Project p, {int? count}) {
  final voices = [for (final a in p.audio) if (a.isVoice && a.linked) a];
  if (count != null) expect(voices.length, count);
  for (final a in voices) {
    final i = p.clips.indexWhere((c) => c.id == a.sourceClipId);
    expect(i, greaterThanOrEqualTo(0), reason: 'clip of ${a.id}');
    final c = p.clips[i];
    final clipStart = p.clipStartMs(i);
    expect(a.speed, c.speed);
    // Source time of the clip's file shown when the sound item starts.
    final shown = c.inMs + (a.startMs - clipStart) * c.speed;
    expect(a.inMs, closeTo(shown + a.syncOffsetMs!, 1.5),
        reason: 'start of ${a.id}');
    expect(a.startMs, greaterThanOrEqualTo(clipStart));
    expect(a.endMs, lessThanOrEqualTo(clipStart + c.durationMs + 1));
    expect(a.inMs, greaterThanOrEqualTo(0));
    expect(a.outMs, lessThanOrEqualTo(a.sourceDurationMs));
  }
  // Nothing overlaps on a track.
  for (final t in p.soundTracks) {
    final on = p.clipsOnTrack(t.id);
    for (var i = 1; i < on.length; i++) {
      expect(on[i].startMs, greaterThanOrEqualTo(on[i - 1].endMs));
    }
  }
}

void main() {
  group('model', () {
    test('syncOffsetMs round-trips; older projects have none', () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: 420);
      final back = Project.fromJson(
          jsonDecode(jsonEncode(e.project.toJson())) as Map<String, dynamic>);
      final a = back.audio.single;
      expect(a.syncOffsetMs, 420);
      expect(a.linked, isTrue);
      expect(a.sourceClipId, 'a');
      expect(a.isVoice, isTrue);
      expect(a.isSeparated, isFalse);
      expect(back.soundRoleOf(a), 'voice');
      expect(content(back), content(e.project));
      // Versions before 1.10 must not take it for a sound of the clip's
      // own file (they would swap the file): no 'sourceClipId' in the JSON.
      final json = e.project.audio.single.toJson();
      expect(json.containsKey('sourceClipId'), isFalse);
      expect(json.containsKey('linked'), isFalse);
      expect(json['voiceClipId'], 'a');
      expect(json['voiceLinked'], isTrue);
      // A separated sound is stored as before.
      final sep = ed(project(clips: [video('a')]))..separateSound('a');
      final sj = sep.project.audio.single.toJson();
      expect([sj['sourceClipId'], sj['linked']], ['a', true]);
      expect(sj.containsKey('voiceClipId'), isFalse);

      final plain = audio('m');
      expect(plain.toJson().containsKey('syncOffsetMs'), isFalse);
      expect(AudioClip.fromJson(plain.toJson()).isVoice, isFalse);
      expect(project(audio: [plain]).soundRoleOf(plain), 'music');
    });
  });

  group('addVoice', () {
    test('lines it up, own speech track, mutes the camera, one undo step', () {
      final e = ed(project(clips: [video('x', source: 3000), video('a')]));
      final ids = e.addVoice(voiceFile('audioSamTaylor21406335665'),
          clipId: 'a', offsetMs: 420, trackName: 'Sam Taylor');
      expect(ids.length, 1);
      final a = e.project.audio.single;
      expect([a.startMs, a.inMs, a.outMs], [3000, 420, 10420]);
      expect(a.linked, isTrue);
      final t = e.project.trackById(a.trackId)!;
      expect(t.name, 'Sam Taylor');
      expect(t.speech, isTrue);
      expect(t.duck, isFalse);
      expect(e.project.clips[1].muted, isTrue);
      expect(e.project.clips[0].muted, isFalse);
      expect(labels(e).last, 'Added voice for clip 2, lined up (+0.42 s)');
      expectInSync(e.project, count: 1);
      e.undo();
      expect(e.project.audio, isEmpty);
      expect(e.project.clips[1].muted, isFalse);
      expect(e.project.soundTracks, isEmpty);
    });

    test('voice started later than the camera: the start is trimmed', () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: -1500);
      final a = e.project.audio.single;
      // Nothing recorded for the first 1.5 s of the clip.
      expect([a.startMs, a.inMs, a.outMs], [1500, 0, 8500]);
      expect(labels(e).last, 'Added voice for clip 1, lined up (−1.50 s)');
      expectInSync(e.project, count: 1);
    });

    test('voice shorter than the clip: it ends early (silence)', () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic', length: 6000), clipId: 'a', offsetMs: 1000);
      final a = e.project.audio.single;
      expect([a.startMs, a.inMs, a.outMs], [0, 1000, 6000]);
      expect(a.endMs, 5000);
      expectInSync(e.project, count: 1);
    });

    test('not lined up, camera sound kept', () {
      final e = ed(project(clips: [video('a', inMs: 2000)]));
      e.addVoice(voiceFile('mic'),
          clipId: 'a', offsetMs: -2000, muteClips: false, linedUp: false);
      final a = e.project.audio.single;
      expect([a.startMs, a.inMs], [0, 0]);
      expect(e.project.clips.single.muted, isFalse);
      expect(labels(e).last, 'Added voice for clip 1 (not lined up)');
    });

    test('a project already cut up: every clip of the file gets its piece',
        () {
      final e = ed(project(clips: [
        video('a', source: 20000, inMs: 1000, outMs: 4000),
        video('other', source: 5000),
        video('a2', source: 20000, inMs: 9000, outMs: 12000)
            .copyWith(path: '/media/a.mp4'),
        video('a3', source: 20000, inMs: 15000, outMs: 19000)
            .copyWith(path: '/media/a.mp4'),
      ]));
      final ids = e.addVoice(voiceFile('mic', length: 16000),
          clipId: 'a2', offsetMs: 500);
      // a3 runs past the end of the voice file: 15.5 .. 16 s only.
      expect(ids.length, 3);
      expect({for (final a in e.project.audio) a.trackId}.length, 1);
      expect([for (final c in e.project.clips) c.muted],
          [true, false, true, true]);
      expectInSync(e.project, count: 3);
      final last = e.project.audio.firstWhere((a) => a.sourceClipId == 'a3');
      expect([last.inMs, last.outMs], [15500, 16000]);
      expect(labels(e).last, 'Added voice for clip 3, lined up (+0.50 s)');
    });

    test('several speakers: each on its own track, up to the limit', () {
      final e = ed(project(clips: [video('a')], audio: [audio('m')]));
      e.addVoice(voiceFile('one'), clipId: 'a', offsetMs: 0, trackName: 'Ann');
      e.addVoice(voiceFile('two'), clipId: 'a', offsetMs: 30, trackName: 'Bob');
      expect([for (final t in e.project.soundTracks) t.name],
          ['Music', 'Ann', 'Bob']);
      expect(linkedVoicesOf(e.project, 'a').length, 2);
      // A third voice overlaps the others all the way: no room.
      final before = content(e.project);
      expect(
          () => e.addVoice(voiceFile('three'), clipId: 'a', offsetMs: 0),
          throwsA(isA<VoiceProblem>().having((p) => p.message, 'message',
              allOf(contains('at most 3 sound tracks'), contains('Delete')))));
      expect(content(e.project), before);
      expect(e.history.length, 2);
    });

    test('no room, but a speech track is free there: shares it', () {
      final e = ed(project(clips: [
        video('a', source: 5000),
        video('b', source: 5000),
      ], audio: [
        audio('m')
      ]));
      e.addVoice(voiceFile('one', length: 5000), clipId: 'a', offsetMs: 0);
      e.addSoundTrack(name: 'Effects');
      expect(e.project.soundTracks.length, 3);
      e.addVoice(voiceFile('two', length: 5000), clipId: 'b', offsetMs: 0);
      expect(e.project.soundTracks.length, 3);
      expect({for (final a in e.project.audio) if (a.isVoice) a.trackId}.length,
          1);
      expectInSync(e.project, count: 2);
    });

    test('default names: Voice, Voice 2; an empty Voice track is used', () {
      final e = ed(project(clips: [video('a')]));
      e.addSoundTrack(name: 'Voice');
      e.addVoice(voiceFile('one'), clipId: 'a', offsetMs: 0, trackName: 'Ann');
      expect([for (final t in e.project.soundTracks) t.name], ['Ann']);
      e.addVoice(voiceFile('two'), clipId: 'a', offsetMs: 0);
      e.addVoice(voiceFile('three'), clipId: 'a', offsetMs: 0, trackName: 'ann');
      expect([for (final t in e.project.soundTracks) t.name],
          ['Ann', 'Voice', 'ann 2']);
    });

    test('refuses photos, unknown clips, an offset with nothing in it', () {
      final e = ed(project(clips: [photo('p'), video('a')]));
      expect(() => e.addVoice(voiceFile('m'), clipId: 'p', offsetMs: 0),
          throwsA(isA<VoiceProblem>()));
      expect(() => e.addVoice(voiceFile('m'), clipId: 'zz', offsetMs: 0),
          throwsA(isA<VoiceProblem>()));
      expect(() => e.addVoice(voiceFile('m'), clipId: 'a', offsetMs: 60000),
          throwsA(isA<VoiceProblem>()));
      expect(e.canUndo, isFalse);
    });
  });

  group('follows its clip', () {
    ProjectEditor start({int offset = 700}) {
      final e = ed(project(clips: [
        video('x', source: 6000),
        video('a', source: 20000),
      ]));
      e.addVoice(voiceFile('mic', length: 30000), clipId: 'a', offsetMs: offset);
      return e;
    }

    test('trim, move, speed, delete the clip before it', () {
      final e = start();
      e.trimClip('a', inMs: 2000, outMs: 15000);
      expectInSync(e.project, count: 1);
      expect(e.project.audio.single.inMs, 2700);
      expect(e.project.audio.single.outMs, 15700);
      e.moveClip(1, 0);
      expectInSync(e.project, count: 1);
      expect(e.project.audio.single.startMs, 0);
      e.setClipSpeed('a', 2);
      expectInSync(e.project, count: 1);
      expect(e.project.audio.single.speed, 2);
      expect(e.project.audio.single.durationMs, 6500);
      e.removeClip('x');
      expectInSync(e.project, count: 1);
      // One undo step each, the sound with it.
      e.undo();
      e.undo();
      expect(e.project.audio.single.speed, 1);
      expectInSync(e.project, count: 1);
    });

    test('split: both halves keep the voice, in sync, same undo step', () {
      final e = start();
      final steps = e.history.length;
      expect(e.splitAt(6000 + 8000), isTrue);
      expect(e.history.length, steps + 1);
      expect(labels(e).last, 'Split clip 2');
      expectInSync(e.project, count: 2);
      final parts = e.project.clipsOnTrack(e.project.audio.first.trackId);
      expect([parts[0].inMs, parts[0].outMs], [700, 8700]);
      expect([parts[1].inMs, parts[1].outMs], [8700, 20700]);
      expect(parts.every((a) => a.syncOffsetMs == 700 && a.linked), isTrue);
      expect(e.project.clips.where((c) => c.muted).length, 2);
      e.undo();
      expectInSync(e.project, count: 1);
    });

    test('remove silences: every piece gets its part of the voice', () {
      final e = start();
      expect(
          e.removeSourceRanges('a', [
            (startMs: 3000, endMs: 5000),
            (startMs: 9000, endMs: 12000),
          ]),
          2);
      expect(e.project.clips.length, 4);
      expectInSync(e.project, count: 3);
      expect(labels(e).last, 'Removed 2 silences');
      e.undo();
      expectInSync(e.project, count: 1);
    });

    test('several speakers follow together', () {
      final e = start();
      e.addVoice(voiceFile('mic2', length: 30000), clipId: 'a', offsetMs: -250);
      expect(e.splitAt(6000 + 5000), isTrue);
      e.setClipSpeed(e.project.clips.last.id, 0.5);
      e.removeSourceRanges('a', [(startMs: 1000, endMs: 2000)]);
      expectInSync(e.project, count: 6);
      expect({for (final a in e.project.audio) a.trackId}.length, 2);
      e.removeClip('a');
      expectInSync(e.project, count: 4);
    });

    test('transition between two pieces: the sounds do not overlap', () {
      final e = start();
      e.splitAt(6000 + 8000);
      final second = e.project.clips.last;
      e.setClipTransition(second.id, TransitionType.crossfade, durationMs: 600);
      expectInSync(e.project, count: 2);
    });

    test('a copy of the clip, and the same file added again, get the voice',
        () {
      final e = start();
      final copy = e.duplicateClip('a')!;
      expectInSync(e.project, count: 2);
      expect(e.project.audio.any((a) => a.sourceClipId == copy), isTrue);
      e.addClip(video('again', source: 20000).copyWith(path: '/media/a.mp4'));
      expectInSync(e.project, count: 3);
      // The camera's sound stays off for the whole file.
      expect(e.project.clips.last.muted, isTrue);
      // Another file gets nothing.
      e.addClip(video('b'));
      expectInSync(e.project, count: 3);
    });

    test('a piece the voice file has no sound for gets no item', () {
      final e = ed(project(clips: [video('a', source: 20000)]));
      e.addVoice(voiceFile('mic', length: 8000), clipId: 'a', offsetMs: 0);
      e.splitAt(10000);
      expectInSync(e.project, count: 1);
      expect(e.project.audio.single.sourceClipId, 'a');
      e.trimClip('a', inMs: 8500);
      expect(e.project.audio, isEmpty);
      e.undo();
      expectInSync(e.project, count: 1);
    });

    test('deleting the clip deletes its voice; undo brings both back', () {
      final e = start();
      e.removeClip('a');
      expect(e.project.audio, isEmpty);
      e.undo();
      expectInSync(e.project, count: 1);
    });

    test('moving it by hand unlinks that item; volume keeps the link', () {
      final e = start();
      final a = e.project.audio.single;
      e.updateAudio(a.copyWith(volume: 0.5));
      expect(e.project.audio.single.linked, isTrue);
      expect(labels(e).last, 'Voice volume 50%');
      e.updateAudio(e.project.audio.single.copyWith(startMs: 4000));
      expect(e.project.audio.single.linked, isFalse);
      expect(labels(e).last, 'Moved voice');
      e.removeClip('x');
      expect(e.project.audio.single.startMs, 4000);
      expect(e.project.audio.single.isVoice, isTrue);
    });
  });

  group('nudge, unlink, line up again', () {
    test('nudge later / earlier moves every piece and keeps the link', () {
      final e = ed(project(clips: [video('a', source: 20000)]));
      e.addVoice(voiceFile('mic', length: 30000), clipId: 'a', offsetMs: 700);
      e.splitAt(8000);
      expect(e.nudgeVoice(e.project.audio.first.id, 100), isTrue);
      expect(labels(e).last, 'Nudged voice 100 ms later');
      expect({for (final a in e.project.audio) a.syncOffsetMs}, {600});
      expectInSync(e.project, count: 2);
      // Later = the same picture gets an earlier part of the voice file.
      expect(e.project.clipsOnTrack(e.project.audio.first.trackId).first.inMs,
          600);
      expect(e.nudgeVoice(e.project.audio.last.id, -10), isTrue);
      expect(labels(e).last, 'Nudged voice 10 ms earlier');
      expect({for (final a in e.project.audio) a.syncOffsetMs}, {610});
      e.undo();
      expect({for (final a in e.project.audio) a.syncOffsetMs}, {600});
      expect(e.nudgeVoice('nope', 10), isFalse);
      expect(e.nudgeVoice(e.project.audio.first.id, 0), isFalse);
    });

    test('nudging past the start of the voice file trims its start', () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: 20);
      final id = e.project.audio.single.id;
      e.nudgeVoice(id, 100);
      final a = e.project.audio.single;
      expect([a.syncOffsetMs, a.startMs, a.inMs], [-80, 80, 0]);
      expectInSync(e.project, count: 1);
    });

    test('unlink keeps the sound in place and unmutes the camera', () {
      final e = ed(project(clips: [video('x', source: 3000), video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: 300);
      e.splitAt(3000 + 4000);
      final placed = [
        for (final a in e.project.audio) [a.startMs, a.inMs, a.outMs]
      ];
      expect(e.unlinkVoice(e.project.audio.first.id), isTrue);
      expect(labels(e).last, 'Unlinked voice from clip 2');
      expect(e.project.audio.every((a) => !a.linked && a.isVoice), isTrue);
      expect([for (final a in e.project.audio) [a.startMs, a.inMs, a.outMs]],
          placed);
      expect(e.project.clips.any((c) => c.muted), isFalse);
      // It no longer follows.
      e.removeClip('x');
      expect([for (final a in e.project.audio) a.startMs],
          [for (final r in placed) r[0]]);
      e.undo();
      e.undo();
      expect(e.project.audio.every((a) => a.linked), isTrue);
      expect(e.project.clips.where((c) => c.muted).length, 2);
      // Keeping the camera muted.
      expect(e.unlinkVoice(e.project.audio.first.id, unmuteClips: false),
          isTrue);
      expect(e.project.clips.where((c) => c.muted).length, 2);
      expect(e.unlinkVoice(e.project.audio.first.id), isFalse);
    });

    test('line up again: a broken link is rebuilt for every piece', () {
      final e = ed(project(clips: [video('a', source: 20000)]));
      e.addVoice(voiceFile('mic', length: 30000), clipId: 'a', offsetMs: 700);
      e.splitAt(8000);
      final track = e.project.audio.first.trackId;
      e.updateAudio(e.project.audio.first.copyWith(volume: 0.7));
      e.unlinkVoice(e.project.audio.first.id);
      final ids = e.linkVoice(e.project.audio.first.id,
          clipId: 'a', offsetMs: 730, muteClips: true);
      expect(ids.length, 2);
      expect(labels(e).last, 'Lined up voice with clip 1 (+0.73 s)');
      expectInSync(e.project, count: 2);
      expect({for (final a in e.project.audio) a.trackId}, {track});
      expect(e.project.audio.every((a) => a.syncOffsetMs == 730), isTrue);
      expect(e.project.audio.first.volume, 0.7);
      expect(e.project.clips.every((c) => c.muted), isTrue);
      expect(e.project.soundTracks.length, 1);
    });

    test('plain music that is really a voice: moves to its own speech track',
        () {
      final e = ed(project(
          clips: [video('a')],
          audio: [audio('audioSamTaylor2140633', source: 12000)]));
      final m = e.project.audio.single;
      expect(e.project.soundRoleOf(m), 'music');
      e.linkVoice(m.id,
          clipId: 'a', offsetMs: 0, trackName: 'Sam Taylor', muteClips: true);
      final a = e.project.audio.single;
      expect(e.project.trackById(a.trackId)!.name, 'Sam Taylor');
      expect(e.project.trackById(a.trackId)!.speech, isTrue);
      expect(a.path, m.path);
      expect(e.project.soundRoleOf(a), 'voice');
      expect(e.project.clips.single.muted, isTrue);
      expectInSync(e.project, count: 1);
      e.undo();
      expect(e.project.audio.single.trackId, kMusicTrackId);
    });

    test('camera sound switch', () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: 0, muteClips: false);
      final id = e.project.audio.single.id;
      expect(e.setVoiceClipsMuted(id, true), isTrue);
      expect(e.project.clips.single.muted, isTrue);
      expect(labels(e).last, 'Muted the camera sound');
      expect(e.setVoiceClipsMuted(id, true), isFalse);
      expect(e.setVoiceClipsMuted(id, false), isTrue);
      expect(e.project.clips.single.muted, isFalse);
    });

    test('separated sound is not a voice: put back still works, voice not',
        () {
      final e = ed(project(clips: [video('a')]));
      e.addVoice(voiceFile('mic'), clipId: 'a', offsetMs: 0);
      expect(e.reattachSound(e.project.audio.single.id), isFalse);
      // The camera's own (muted) sound can still be separated.
      expect(ProjectEditor.separateSoundProblem(e.project, 'a'), isNull);
      final sep = e.separateSound('a')!;
      expect(e.project.audio.length, 2);
      expect(e.reattachSound(sep), isTrue);
      expect(e.project.audio.single.isVoice, isTrue);
    });
  });
}
