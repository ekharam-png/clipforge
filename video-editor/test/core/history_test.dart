// The editing history: a short name for every step, and jumping back and
// forth to any step.

import 'package:clipforge/core/editor/edit_labels.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

Clip video(String id, {int inMs = 0, int outMs = 6000, String path = '/v/a.mp4'}) => Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: 20000,
      inMs: inMs,
      outMs: outMs,
      width: 1920,
      height: 1080,
    );

Clip photo(String id) => Clip(
      id: id,
      type: ClipType.photo,
      path: '/p/$id.jpg',
      sourceDurationMs: 0,
      inMs: 0,
      outMs: 3000,
      width: 1000,
      height: 1000,
      hasAudio: false,
    );

void main() {
  var ids = 0;
  var minutes = 0;
  ProjectEditor make([List<Clip>? clips]) {
    ids = 0;
    minutes = 0;
    return ProjectEditor(
      Project(
        id: 'p',
        name: 'Test',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        clips: clips ?? [video('a'), video('b', path: '/v/b.mp4'), video('c')],
      ),
      clock: () => DateTime(2026, 11, 16, 14, minutes++),
      newId: () => 'n${ids++}',
    );
  }

  List<String> labels(ProjectEditor e) => [for (final s in e.history) s.label];

  group('names of edits', () {
    test('clip settings name the setting, the value and the clip', () {
      final e = make();
      e.setClipSpeed('b', 1.25);
      e.setClipVoiceFocus('a', 0.85);
      e.setClipDenoise('c', true);
      e.setClipVolume('a', 0.5);
      e.setClipMuted('a', true);
      e.trimClip('c', inMs: 1000);
      e.setClipTransition('b', TransitionType.crossfade);
      e.setClipZoom('a', 1.5);
      e.setClipAdjustments('a', brightness: 0.2);
      e.setClipFit('a', FitMode.fill);
      e.setClipAudioSource('a', channel: AudioChannel.left);
      expect(labels(e), [
        'Speed 1.25× on clip 2',
        'Voice focus 85% on clip 1',
        'Clean up sound on clip 3',
        'Volume 50% on clip 1',
        'Muted clip 1',
        'Trimmed clip 3',
        'Crossfade on clip 2',
        'Zoom 1.5× on clip 1',
        'Brightness on clip 1',
        'Fill on clip 1',
        // A side needs a stereo stream the clip is not known to have.
      ]);
    });

    test('adding, deleting, moving, splitting', () {
      final e = make();
      e.addClip(photo('x'));
      e.removeClip('x');
      e.moveClip(0, 2);
      e.splitAt(1000);
      e.addTitle(const TitleOverlay(
          id: 't', text: 'Summer holidays in Crete', startMs: 0, endMs: 2000));
      e.updateTitle(const TitleOverlay(
          id: 't', text: 'Summer', startMs: 0, endMs: 2000));
      e.addTitles(const [
        TitleOverlay(id: 'c1', text: 'Hi', startMs: 0, endMs: 900, kind: TitleKind.caption),
        TitleOverlay(id: 'c2', text: 'Ho', startMs: 1000, endMs: 1900, kind: TitleKind.caption),
      ]);
      e.setAspect(CanvasAspect.portrait9x16);
      e.addAudio(const AudioClip(
          id: 'm', path: '/m.mp3', sourceDurationMs: 9000, startMs: 0, inMs: 0, outMs: 9000));
      e.updateAudio(const AudioClip(
          id: 'm', path: '/m.mp3', sourceDurationMs: 9000, startMs: 0, inMs: 0, outMs: 9000,
          volume: 0.5));
      e.setDuckMusic(true);
      expect(labels(e), [
        'Added photo',
        'Deleted photo 4',
        'Moved clip',
        'Split clip 1',
        "Added title 'Summer holidays in…'",
        "Edited title 'Summer'",
        'Added 2 captions',
        'Shape 9:16',
        'Added music',
        'Music volume 50%',
        'Lower music under speech on',
      ]);
    });

    test('removing silences and freeze frames say so', () {
      final e = make();
      e.removeSourceRanges('a', const [
        (startMs: 1000, endMs: 1500),
        (startMs: 3000, endMs: 3600),
      ]);
      e.insertFreezeFrame(9000, photo('still'));
      expect(labels(e), ['Removed 2 silences', startsWith('Freeze frame on clip')]);
    });

    test('a transaction is one step with one name', () {
      final e = make();
      e.transaction(() {
        e.setClipVoiceFocus('a', 0.3);
        e.setClipVoiceFocus('a', 0.6);
        e.setClipVoiceFocus('a', 0.85);
      });
      e.transaction(() {
        e.addClip(video('x'));
        e.addClip(video('y'));
      }, label: 'Added 2 clips from the gallery');
      e.transaction(() => e.setClipSpeed('a', 2));
      expect(labels(e), [
        'Voice focus 85% on clip 1',
        'Added 2 clips from the gallery',
        'Speed 2× on clip 1',
      ]);
    });

    test('nameNextEdit names one edit', () {
      final e = make();
      e.nameNextEdit('Applied voice focus');
      e.setClipVoiceFocus('a', 0.5);
      e.setClipVoiceFocus('a', 0.6);
      expect(labels(e), ['Applied voice focus', 'Voice focus 60% on clip 1']);
    });

    test('apply to all clips', () {
      final e = make();
      e.setClipSpeed('a', 1.5);
      e.applyClipSettingsToAll('a', speed: true);
      expect(labels(e).last, 'Speed of clip 1 applied to all clips');
    });

    test('describeEdit falls back to a plain word', () {
      final p = make().project;
      expect(describeEdit(p, p), 'Edit');
      expect(quoteText('  two\nlines '), "'two'");
    });
  });

  group('jumping to a step', () {
    test('several undos as one jump, later steps stay redoable', () {
      final e = make();
      var notes = 0;
      e.addListener(() => notes++);
      e.setClipSpeed('a', 2);
      e.setClipMuted('b', true);
      e.setClipDenoise('c', true);
      expect(e.historyPosition, 3);
      notes = 0;
      e.jumpToHistory(1);
      expect(notes, 1, reason: 'one jump, one notification');
      expect(e.historyPosition, 1);
      expect(e.project.clips[0].speed, 2);
      expect(e.project.clips[1].muted, isFalse);
      expect(e.project.clips[2].denoise, isFalse);
      // The list still shows all three, in order.
      expect(labels(e), ['Speed 2× on clip 1', 'Muted clip 2', 'Clean up sound on clip 3']);
      expect(e.canRedo, isTrue);

      e.jumpToHistory(3);
      expect(e.project.clips[2].denoise, isTrue);
      e.jumpToHistory(0);
      expect(e.project.clips[0].speed, 1);
      expect(e.canUndo, isFalse);
      // Out of range and the current step do nothing.
      notes = 0;
      e.jumpToHistory(0);
      e.jumpToHistory(9);
      e.jumpToHistory(-1);
      expect(notes, 0);
    });

    test('a new edit after a jump drops the later steps', () {
      final e = make();
      e.setClipSpeed('a', 2);
      e.setClipMuted('b', true);
      e.jumpToHistory(1);
      e.setClipVolume('c', 0.5);
      expect(labels(e), ['Speed 2× on clip 1', 'Volume 50% on clip 3']);
      expect(e.canRedo, isFalse);
    });

    test('names and times survive undo, redo and renames', () {
      final e = make();
      e.removeSourceRanges('a', const [(startMs: 1000, endMs: 2000)]);
      e.setClipSpeed('b', 0.5);
      final times = [for (final s in e.history) s.time];
      e.undo();
      e.undo();
      e.rename('Holiday');
      e.redo();
      expect(labels(e), ['Removed 1 silence', 'Speed 0.5× on clip 3']);
      expect([for (final s in e.history) s.time], times);
      expect(e.historyPosition, 1);
      expect(e.project.name, 'Holiday');
    });

    test('ignored inside a transaction', () {
      final e = make();
      e.setClipSpeed('a', 2);
      e.transaction(() {
        e.setClipMuted('a', true);
        e.jumpToHistory(0);
      });
      expect(e.project.clips[0].speed, 2);
      expect(e.historyPosition, 2);
    });

    test('keeps at most the undo limit', () {
      final e = make();
      for (var i = 0; i < ProjectEditor.maxUndoSteps + 5; i++) {
        e.setClipVolume('a', i.isEven ? 0.5 : 0.6);
      }
      expect(e.history, hasLength(ProjectEditor.maxUndoSteps));
      e.jumpToHistory(0);
      expect(e.canUndo, isFalse);
    });
  });
}
