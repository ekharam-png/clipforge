// Voice focus and the choice of audio track / side: model, JSON, editing
// rules and undo.

import 'dart:convert';

import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

EditorController editorFor(List<Clip> clips) =>
    EditorController(project(clips: clips), newId: () => 'n${clips.length}');

Clip clipOf(EditorController c, String id) =>
    c.project.clips.firstWhere((x) => x.id == id);

void main() {
  group('model', () {
    test('defaults: off, first track, both sides, streams not known', () {
      final c = video('a');
      expect(c.voiceFocus, 0);
      expect(c.audioTrack, 0);
      expect(c.audioChannel, AudioChannel.both);
      expect(c.audioStreams, isEmpty);
      expect(c.audioTrackInUse, 0);
      expect(c.audioChannelsInUse, 0);
      expect(c.audioChannelInUse, AudioChannel.both);
    });

    test('a project saved before these fields loads unchanged', () {
      final json = project(clips: [video('a')]).toJson();
      final clip = (json['clips'] as List).single as Map<String, dynamic>;
      for (final k in ['voiceFocus', 'audioTrack', 'audioChannel', 'audioStreams']) {
        expect(clip.remove(k), isNotNull, reason: k);
      }
      final back = Project.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(content(back), content(project(clips: [video('a')])));
      expect(back.toJson()['schemaVersion'], 2);
    });

    test('round trip; unknown side names fall back to both', () {
      final p = project(clips: [
        video('a').copyWith(
            voiceFocus: 0.65,
            audioTrack: 1,
            audioChannel: AudioChannel.right,
            audioStreams: const [1, 2]),
      ]);
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      final back = Project.fromJson(json);
      expect(content(back), content(p));
      final c = back.clips.single;
      expect([c.voiceFocus, c.audioTrack, c.audioChannel, c.audioStreams],
          [0.65, 1, AudioChannel.right, [1, 2]]);
      ((json['clips'] as List).single as Map)['audioChannel'] = 'centre';
      expect(Project.fromJson(json).clips.single.audioChannel, AudioChannel.both);
    });

    test('what is in use follows what the file has', () {
      final c = video('a').copyWith(
          audioTrack: 1, audioChannel: AudioChannel.left, audioStreams: const [2, 1]);
      // Track 2 is mono: no side.
      expect(c.audioTrackInUse, 1);
      expect(c.audioChannelsInUse, 1);
      expect(c.audioChannelInUse, AudioChannel.both);
      final first = c.copyWith(audioTrack: 0);
      expect(first.audioChannelInUse, AudioChannel.left);
      // A track the file does not have: the first.
      expect(c.copyWith(audioTrack: 5).audioTrackInUse, 0);
      expect(c.copyWith(audioStreams: const []).audioTrackInUse, 0);
      // 5.1 is not "stereo": no side.
      expect(first.copyWith(audioStreams: const [6]).audioChannelInUse,
          AudioChannel.both);
    });
  });

  group('editing', () {
    test('voice focus is clamped to 0..1, photos are ignored, one undo step', () {
      final e = editorFor([video('a'), photo('p')]);
      e.setClipVoiceFocus('a', 0.4);
      expect(clipOf(e, 'a').voiceFocus, 0.4);
      e.setClipVoiceFocus('a', 3);
      expect(clipOf(e, 'a').voiceFocus, 1);
      e.setClipVoiceFocus('a', -1);
      expect(clipOf(e, 'a').voiceFocus, 0);
      e.setClipVoiceFocus('a', double.nan);
      expect(clipOf(e, 'a').voiceFocus, 0);
      e.setClipVoiceFocus('p', 0.5);
      expect(clipOf(e, 'p').voiceFocus, 0);
      e.undo();
      expect(clipOf(e, 'a').voiceFocus, 1);
    });

    test('a slider drag is one undo step', () {
      final e = editorFor([video('a')]);
      e.transaction(() {
        for (final v in [0.1, 0.3, 0.55, 0.8]) {
          e.setClipVoiceFocus('a', v);
        }
      });
      expect(clipOf(e, 'a').voiceFocus, 0.8);
      e.undo();
      expect(clipOf(e, 'a').voiceFocus, 0);
      expect(e.canUndo, isFalse);
    });

    test('track and side are kept to what the file has', () {
      final e = editorFor([
        video('a').copyWith(audioStreams: const [2, 1]),
        video('old'), // added by an older version: streams not known
      ]);
      e.setClipAudioSource('a', channel: AudioChannel.left);
      expect(clipOf(e, 'a').audioChannel, AudioChannel.left);
      // Track 2 is mono, so the side goes back to both.
      e.setClipAudioSource('a', track: 1);
      expect([clipOf(e, 'a').audioTrack, clipOf(e, 'a').audioChannel],
          [1, AudioChannel.both]);
      e.setClipAudioSource('a', track: 7);
      expect(clipOf(e, 'a').audioTrack, 0);
      e.setClipAudioSource('a', track: 0, channel: AudioChannel.right);
      expect(clipOf(e, 'a').audioChannelInUse, AudioChannel.right);
      final steps = e.editor.project;
      e.setClipAudioSource('old', track: 1, channel: AudioChannel.left);
      expect(identical(e.editor.project, steps), isTrue,
          reason: 'nothing to choose without knowing the streams');
      // Once the streams are known (e.g. probed by the MCP server):
      e.editor.setClipAudioStreams('old', const [2, 2]);
      e.setClipAudioSource('old', track: 1, channel: AudioChannel.left);
      expect([clipOf(e, 'old').audioTrack, clipOf(e, 'old').audioChannel],
          [1, AudioChannel.left]);
    });

    test('split keeps the sound settings on both halves', () {
      final e = editorFor([
        video('a').copyWith(
            voiceFocus: 0.5, audioChannel: AudioChannel.left, audioStreams: const [2]),
      ]);
      expect(e.splitAt(4000), isTrue);
      for (final c in e.project.clips) {
        expect([c.voiceFocus, c.audioChannel, c.audioStreams],
            [0.5, AudioChannel.left, [2]]);
      }
    });

    test('apply sound to all copies voice focus and source, per file', () {
      final e = editorFor([
        video('a').copyWith(
            voiceFocus: 0.7,
            audioTrack: 1,
            audioChannel: AudioChannel.right,
            audioStreams: const [2, 2],
            volume: 0.5),
        video('b').copyWith(audioStreams: const [2, 2]),
        video('mono').copyWith(audioStreams: const [1]),
        photo('p'),
      ]);
      expect(e.applyClipSettingsToAll('a', sound: true), 2);
      final b = clipOf(e, 'b');
      expect([b.voiceFocus, b.audioTrack, b.audioChannel, b.volume],
          [0.7, 1, AudioChannel.right, 0.5]);
      final mono = clipOf(e, 'mono');
      expect([mono.voiceFocus, mono.audioTrack, mono.audioChannel],
          [0.7, 0, AudioChannel.both]);
      expect(clipOf(e, 'p').voiceFocus, 0);
      e.undo();
      expect(clipOf(e, 'b').voiceFocus, 0);
      expect(e.canUndo, isFalse);
    });

    test('added clips are normalised', () {
      final e = editorFor([]);
      e.addClip(video('a').copyWith(
          voiceFocus: 9, audioTrack: 3, audioChannel: AudioChannel.left));
      final c = clipOf(e, 'a');
      expect([c.voiceFocus, c.audioTrack, c.audioChannel],
          [1, 0, AudioChannel.both]);
    });
  });
}
