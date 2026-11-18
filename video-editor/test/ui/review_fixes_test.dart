// Behaviour added after the product review: selecting shows the clip,
// "apply to all", titles laid out like the export, music past the end,
// missing files, failed saves, the "+" button and the keyboard.

import 'dart:io';

import 'package:clipforge/core/storage/project_lock.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/tools.dart';
import 'package:clipforge/ui/format.dart';
import 'package:clipforge/ui/playback/media_kit_backend.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const zoomedOut = 60 / 1.5 / 1.5;

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back to projects'));
  await tester.pumpAndSettle();
}

Future<void> undo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Undo'));
  await tester.pumpAndSettle();
}

const video60 = MediaInfo(
    durationMs: 20000,
    width: 1920,
    height: 1080,
    hasVideo: true,
    hasAudio: true,
    fps: 59.94);

Project withTransition() {
  final p = sampleProject();
  return p.copyWith(clips: [
    p.clips[0],
    p.clips[1].copyWith(transition: TransitionType.crossfade),
    ...p.clips.skip(2),
  ]);
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    // 1 ---------------------------------------------------------------------
    testWidgets('selecting a clip shows it in the preview on a $label screen',
        (tester) async {
      await openEditor(tester, size);
      await zoomOutTwice(tester);
      expect(find.textContaining('0:00.0 / 0:18.0'), findsOneWidget);

      // The playhead jumps into the clip that was tapped...
      await tester.tap(block('clip-c'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0:09.0 / 0:18.0'), findsOneWidget);
      expect(find.text('File not found'), findsOneWidget);

      // ...and stays where the user put it while it is inside that clip.
      await seekTo(tester, 11000, zoom: zoomedOut);
      await tester.tap(block('clip-c'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0:11.0 / 0:18.0'), findsOneWidget);

      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0:06.0 / 0:18.0'), findsOneWidget);
    });

    testWidgets(
        'a clip with a transition is shown after the overlap, and its badge '
        'opens the transition settings on a $label screen', (tester) async {
      await openEditor(tester, size, project: withTransition());
      await zoomOutTwice(tester);
      // b starts at 5.5 s, fading in until 6 s.
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0:06.0 / 0:17.5'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('How the clip before changes into this one.'),
          findsNothing);

      await tester.tap(block('transition-b'));
      await tester.pumpAndSettle();
      expect(find.text('How the clip before changes into this one.'),
          findsOneWidget);
      expect(find.text('Crossfade'), findsOneWidget);
      if (size == phone) {
        // A sheet, as if "More > Transition" had been tapped.
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.tap(find.text('Slide up'));
        await tester.pumpAndSettle();
        await closeSheet(tester, size);
        expect(find.byType(BottomSheet), findsNothing);
      }
    });

    // 2 ---------------------------------------------------------------------
    testWidgets('speed: 1.25× and apply to all clips on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Speed');
      await tester.tap(find.text('1.25×'));
      await tester.pumpAndSettle();
      expect(find.text('Length 4.8 s (6.0 s at normal speed)'), findsOneWidget);

      await tester.ensureVisible(find.text('Apply to all clips'));
      await tester.tap(find.text('Apply to all clips'));
      await tester.pumpAndSettle();
      // The two other videos; the photo has no speed.
      expect(find.text('Changed 2 clips. Undo puts them back.'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_apply_to_all');

      // Nothing left to change.
      await tester.tap(find.text('Apply to all clips'));
      await tester.pumpAndSettle();
      expect(find.text('The other clips already match.'), findsOneWidget);
      await closeSheet(tester, size);

      // One undo step for all of them.
      await undo(tester);
      await back(tester);
      expect([for (final c in saved(fakes).clips) c.speed], [1.25, 1, 1, 1]);
    });

    // 3 ---------------------------------------------------------------------
    testWidgets('a title on an upright video is drawn like the export does '
        'on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size,
          project: sampleProject().copyWith(aspect: CanvasAspect.portrait9x16));
      final title = sampleProject().titles.single;
      final expected =
          layoutTitleBlock(title, canvasWidth: 1080, canvasHeight: 1920);
      // The size goes by the short side: 9% of 1080, not of 1920.
      expect(expected.fontPx, 97);

      final canvas = tester.getRect(find.descendant(
          of: find.byType(PreviewView), matching: find.byType(AspectRatio)));
      final scale = canvas.width / 1080;
      final box = tester.getRect(block('preview-title-t1'));
      expect(box.width, closeTo(expected.boxWidth * scale, 0.01));
      expect(box.height, closeTo(expected.boxHeight * scale, 0.01));
      expect(box.center.dx,
          closeTo(canvas.left + expected.centerX * scale, 0.01));
      expect(box.center.dy, closeTo(canvas.top + expected.centerY * scale, 0.01));
      final text = tester.widget<Text>(
          find.descendant(of: block('preview-title-t1'), matching: find.byType(Text)));
      expect(text.style!.fontSize, closeTo(97 * scale, 0.001));
      expect(text.data, expected.lines.join('\n'));
      // The whole box is inside the picture.
      expect(box.left, greaterThanOrEqualTo(canvas.left));
      expect(box.right, lessThanOrEqualTo(canvas.right));
      await fakes.screenshot(tester, 'editor_${label}_title_9x16');

      // Dragged against the edge it stops there, and what is stored is the
      // place it is shown at.
      await tester.drag(block('preview-title-t1'), const Offset(400, 0));
      await tester.pumpAndSettle();
      final moved = tester.getRect(block('preview-title-t1'));
      expect(moved.right, lessThanOrEqualTo(canvas.right));
      expect(moved.center.dx, greaterThan(box.center.dx));
      await undo(tester);
      expect(undoEnabled(tester), isFalse);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await back(tester);
      final stored = saved(fakes).titles.single;
      final again =
          layoutTitleBlock(stored, canvasWidth: 1080, canvasHeight: 1920);
      expect(stored.x, lessThan(1));
      expect(again.centerX / 1080, closeTo(stored.x, 1e-6));
      expect(again.boxLeft + again.boxWidth, lessThanOrEqualTo(1080 * 0.98 + 0.5));
    });

    // 5 ---------------------------------------------------------------------
    testWidgets('export says which files are missing and lets them be found '
        'on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('A file is missing'), findsOneWidget);
      expect(find.text('gone.mp4'), findsOneWidget);
      expect(find.text('/media/gone.mp4'), findsOneWidget);
      expect(find.text('Export video'), findsNothing);
      await fakes.screenshot(tester, 'export_missing_$label');

      // A file that is too short cannot stand in.
      fakes.files.media = const [PickedFile('/in/short.mp4', 'short.mp4')];
      fakes.engine.infos['/in/short.mp4'] = const MediaInfo(
          durationMs: 3000,
          width: 1920,
          height: 1080,
          hasVideo: true,
          hasAudio: true);
      await tester.tap(find.text('Find file…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('short.mp4 is shorter (3.0 s)'), findsOneWidget);
      expect(find.text('A file is missing'), findsOneWidget);
      await waitForMessage(tester);

      fakes.files.media = const [PickedFile('/in/found.mp4', 'found.mp4')];
      fakes.engine.infos['/in/found.mp4'] = video60;
      await tester.tap(find.text('Find file…'));
      await tester.pumpAndSettle();
      expect(find.text('All files are back'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Export video'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await waitForMessage(tester);

      // One undo step puts the old path back.
      expect(find.textContaining('Missing'), findsNothing);
      await undo(tester);
      expect(find.textContaining('Missing'), findsOneWidget);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(saved(fakes).clips[2].path, '/in/found.mp4');
    });

    testWidgets('a missing clip offers "Find file" on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await zoomOutTwice(tester);
      await tester.tap(block('clip-c'));
      await tester.pumpAndSettle();
      // In the picture and among the clip's actions.
      expect(find.text('Find file…'), findsOneWidget);
      expect(find.text('Find file'), findsOneWidget);

      fakes.files.media = const [PickedFile('/in/found.mp4', 'found.mp4')];
      fakes.engine.infos['/in/found.mp4'] = video60;
      await tester.tap(find.text('Find file'));
      await tester.pumpAndSettle();
      expect(find.text('Now using found.mp4.'), findsOneWidget);
      expect(find.text('File not found'), findsNothing);
      expect(find.text('Find file'), findsNothing);
      await waitForMessage(tester);
      await back(tester);
      expect(saved(fakes).clips[2].path, '/in/found.mp4');
    });

    // 6 ---------------------------------------------------------------------
    testWidgets('a failed save keeps the user in the editor on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      fakes.store.failSaves = true;
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Not saved — retry'), findsNothing);

      // The autosave runs, fails, and the editor says so.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Not saved — retry'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_not_saved');

      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      expect(find.text('Your latest changes are not saved'), findsOneWidget);
      expect(find.textContaining('No space left on device'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_leave_unsaved');
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(clipBlocks(), findsNWidgets(3));

      await tester.tap(find.text('Not saved — retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Still not saved'), findsOneWidget);
      await waitForMessage(tester);

      // Room again: the retry works and the notice goes away.
      fakes.store.failSaves = false;
      await tester.tap(find.text('Not saved — retry'));
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Not saved — retry'), findsNothing);
      expect(saved(fakes).clips, hasLength(3));
      await waitForMessage(tester);
    });

    // 10 --------------------------------------------------------------------
    testWidgets('media can be added while a clip is selected on a $label '
        'screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await zoomOutTwice(tester);
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      fakes.engine.infos['/in/new.mp4'] = video60;
      fakes.files.media = const [PickedFile('/in/new.mp4', 'new.mp4')];
      if (size == phone) {
        await tester.tap(find.byTooltip('Add videos, photos, music or text'));
        await tester.pumpAndSettle();
        expect(find.text('Go in after the selected clip'), findsOneWidget);
        await fakes.screenshot(tester, 'editor_phone_add');
        await tester.tap(find.text('Videos or photos'));
      } else {
        await tester.ensureVisible(find.text('Add media'));
        await tester.tap(find.text('Add media'));
      }
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(5));
      // Right after the selected clip, and now selected itself.
      expect(find.textContaining('0:09.0 / 0:38.0'), findsOneWidget);
      await back(tester);
      expect(saved(fakes).clips[2].path, '/in/new.mp4');
      expect(clipIds(saved(fakes)).sublist(3), ['c', 'd']);
    });

    // 9 ---------------------------------------------------------------------
    testWidgets('60 fps is offered for fast footage on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size, missingFiles: {});
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.textContaining('high frame rate'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      fakes.engine.infos['/media/hike.mp4'] = video60;
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.textContaining('high frame rate'), findsOneWidget);
      expect(find.textContaining('Length 18.0 s.'), findsOneWidget);
      await tester.tap(find.text('60'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'export_60fps_$label');
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      expect(fakes.engine.lastOptions!.fps, 60);
      fakes.engine.jobs.single.finish('/out/movie.mp4');
      await tester.pumpAndSettle();
    });
  }

  // 1 -----------------------------------------------------------------------
  testWidgets('split cuts the clip under the playhead and the selection '
      'goes with it', (tester) async {
    final fakes = await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    expect(find.text('Video clip'), findsOneWidget);
    // The user moves the playhead onto the photo, then splits.
    await seekTo(tester, 7000);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(clipBlocks(), findsNWidgets(5));
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Video clip'), findsNothing);

    // What is highlighted is the piece under the playhead: Delete takes
    // the second half of the photo.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await back(tester);
    final clips = saved(fakes).clips;
    expect(clipIds(saved(fakes)), ['a', 'b', 'c', 'd']);
    expect(clips[0].outMs, 6000);
    expect(clips[1].durationMs, 1000);
  });

  testWidgets('freeze frame acts on the clip under the playhead',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    await zoomOutTwice(tester);
    await tester.tap(block('clip-b')); // the photo; playhead goes to 6 s
    await tester.pumpAndSettle();
    await seekTo(tester, 2000, zoom: zoomedOut); // back onto the first video
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Freeze frame'), findsNothing); // a photo is selected
    await closeSheet(tester, phone);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    // The selection followed the playhead onto the video.
    expect(find.text('Speed'), findsOneWidget);
    await back(tester);
    expect(saved(fakes).clips, hasLength(5));
    expect(saved(fakes).clips[0].outMs, 2000);
  });

  // 2 -----------------------------------------------------------------------
  testWidgets('look and sound can be applied to all clips', (tester) async {
    final fakes = await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Look');
    expect(find.text('Saturation'), findsOneWidget);
    expect(find.text('Colour'), findsNothing);
    await tester.ensureVisible(find.text('Fill'));
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply to all clips'));
    await tester.tap(find.text('Apply to all clips'));
    await tester.pumpAndSettle();
    expect(find.text('Changed 3 clips. Undo puts them back.'), findsOneWidget);

    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(find.text('Mute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply to all clips'));
    await tester.tap(find.text('Apply to all clips'));
    await tester.pumpAndSettle();
    // d was muted already; the photo has no sound.
    expect(find.text('Changed 1 clip. Undo puts it back.'), findsOneWidget);
    await back(tester);
    final clips = saved(fakes).clips;
    expect([for (final c in clips) c.fit], List.filled(4, FitMode.fill));
    expect([for (final c in clips) c.muted], [true, false, true, true]);
  });

  // 3 -----------------------------------------------------------------------
  testWidgets('titles follow their clip on the timeline', (tester) async {
    final fakes = await openEditor(tester, desktop);
    final before = tester.getRect(block('title-t1')).left;
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Move later'));
    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    // The clip now starts after the 3 s photo, and so does its title.
    expect(tester.getRect(block('title-t1')).left, closeTo(before + 180, 0.01));
    await undo(tester);
    expect(tester.getRect(block('title-t1')).left, closeTo(before, 0.01));
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    await back(tester);
    final title = saved(fakes).titles.single;
    expect((title.startMs, title.endMs), (3000, 7000));
  });

  // 4 -----------------------------------------------------------------------
  testWidgets('music that runs past the end of the video is dimmed there',
      (tester) async {
    final p = sampleProject();
    final fakes = await openEditor(tester, desktop,
        project: p.copyWith(audio: [p.audio.single.copyWith(outMs: 30000)]));
    final music = tester.getRect(block('audio-m1'));
    final dimmed = tester.getRect(block('past-the-end'));
    // From the end of the video (18 s; the music starts at 1 s) to its end.
    expect(dimmed.left, closeTo(music.left + 17 * 60, 0.01));
    expect(dimmed.right, closeTo(music.right, 0.01));
    await tester.tap(block('audio-m1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The video ends 13.0 s before this does'),
        findsOneWidget);
    await fakes.screenshot(tester, 'editor_desktop_music_past_end');
  });

  test('mpv volume: the cube root makes the level linear', () {
    // mpv plays at (volume / 100)³.
    double amplitude(double a) {
      final v = mpvVolumeFor(a) / 100;
      return v * v * v;
    }

    expect(mpvVolumeFor(0), 0);
    expect(mpvVolumeFor(1), 100);
    expect(mpvVolumeFor(0.5), closeTo(79.37, 0.005));
    expect(mpvVolumeFor(2), closeTo(125.99, 0.005));
    expect(mpvVolumeFor(2), lessThan(130)); // mpv's default volume-max
    expect(mpvVolumeFor(7), mpvVolumeFor(2));
    expect(mpvVolumeFor(-1), 0);
    for (final a in [0.05, 0.25, 0.5, 0.8, 1.0, 1.5, 2.0]) {
      expect(amplitude(a), closeTo(a, 1e-9));
    }
  });

  // 5 -----------------------------------------------------------------------
  testWidgets('files are checked again when the app comes back',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    expect(find.textContaining('Missing'), findsOneWidget);
    // The user puts the file back with a file manager and returns.
    fakes.missing.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing'), findsNothing);
  });

  testWidgets('a failed export lists the files the exporter could not find',
      (tester) async {
    final fakes = await openEditor(tester, phone, missingFiles: {});
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
    await tester.pump();
    await tester.pump();
    fakes.engine.jobs.last.fail(ExportException(
        'A file this video uses could not be found.',
        missingPaths: const ['/media/beach.mp4']));
    await tester.pumpAndSettle();
    expect(find.text('A file this video uses could not be found.'),
        findsOneWidget);
    expect(find.text('Missing file:'), findsOneWidget);
    expect(find.text('/media/beach.mp4'), findsOneWidget);
    // Nothing technical unless there is a log.
    expect(find.text('Technical details'), findsNothing);
  });

  testWidgets('a missing sound can be found again', (tester) async {
    final fakes = await openEditor(tester, phone,
        missingFiles: {'/media/song.mp3'});
    await zoomOutTwice(tester);
    await tester.tap(block('audio-m1'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    fakes.files.audio = const [PickedFile('/in/song2.mp3', 'song2.mp3')];
    fakes.engine.infos['/in/song2.mp3'] = const MediaInfo(
        durationMs: 60000, width: 0, height: 0, hasVideo: false, hasAudio: true);
    await tester.tap(find.text('Find file'));
    await tester.pumpAndSettle();
    expect(find.text('Now using song2.mp3.'), findsOneWidget);
    await waitForMessage(tester);
    await back(tester);
    expect(saved(fakes).audio.single.path, '/in/song2.mp3');
  });

  // 6 -----------------------------------------------------------------------
  testWidgets('leave anyway and try again after a failed save',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.store.failSaves = true;
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect(find.text('Your latest changes are not saved'), findsOneWidget);

    // Trying again while it still fails asks again.
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Your latest changes are not saved'), findsOneWidget);
    expect(find.byType(EditorScreen), findsOneWidget);

    await tester.tap(find.text('Leave anyway'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(saved(fakes).clips, hasLength(4)); // the edit is lost, knowingly
  });

  testWidgets('try again saves and leaves once there is room', (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.store.failSaves = true;
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    fakes.store.failSaves = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect(saved(fakes).clips, hasLength(3));
  });

  testWidgets('an open project is marked for Claude, and unmarked on leaving',
      (tester) async {
    useScreen(tester, desktop);
    final dir = Directory.systemTemp.createTempSync('clipforge_lock');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/p1').createSync();
    final fakes = Fakes(projects: [sampleProject()])..lockRoot = dir.path;
    await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
    await tester.pumpAndSettle();
    final lock = File('${dir.path}/p1/$kAppLockFileName');
    expect(lock.existsSync(), isTrue);
    final check = await tester.runAsync(() => checkProjectLock('${dir.path}/p1'));
    expect(check!.state, ProjectLockState.held);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(lock.existsSync(), isFalse);
  });

  test('damaged project folders are found next to the readable ones',
      () async {
    final dir = await Directory.systemTemp.createTemp('clipforge_damaged');
    addTearDown(() => dir.delete(recursive: true));
    final store = ProjectStore.atPath(dir.path);
    final good = await store.create('Fine');
    await Directory('${dir.path}/broken').create();
    await File('${dir.path}/broken/project.json').writeAsString('{ not json');
    await Directory('${dir.path}/empty').create(); // no project file: nothing
    await File('${dir.path}/stray.txt').writeAsString('x');

    final listed = {for (final info in await store.list()) info.id};
    expect(listed, {good.id});
    final damaged = await findDamagedProjects(store, listed);
    expect([for (final d in damaged) d.id], ['broken']);
    expect(damaged.single.modified, isNotNull);
    // A store that is not on disk has nothing to look at.
    expect(await findDamagedProjects(FakeProjectStore(), const {}), isEmpty);
  });

  // 10 ----------------------------------------------------------------------
  testWidgets('a title added at the very end is still seen', (tester) async {
    final fakes = await openEditor(tester, phone);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.textContaining('0:18.0 / 0:18.0'), findsOneWidget);
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(find.text('Edit title'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Text colour'), findsOneWidget);
    expect(find.text('Medium · 6%'), findsOneWidget);
    // The placeholder is selected, so typing replaces it.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Title');
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5));
    await closeSheet(tester, phone);
    await back(tester);
    final title = saved(fakes).titles.last;
    expect((title.startMs, title.endMs), (15000, 18000));
  });

  testWidgets('"lower music under speech" is shown as a project setting',
      (tester) async {
    final fakes = await openEditor(tester, desktop);
    // With nothing selected, under "Project".
    expect(find.text('All music in this project'), findsOneWidget);
    // This music ends before the video does: nothing is dimmed.
    expect(block('past-the-end'), findsNothing);
    await tester.tap(find.text('Lower music under speech'));
    await tester.pumpAndSettle();
    await tester.tap(block('audio-m1'));
    await tester.pumpAndSettle();
    // The music's own settings show its track's switch, already on.
    final perTrack = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('sound-duck')));
    expect(perTrack.value, isTrue);
    expect(find.textContaining('Starts at 0:01.0, plays for 12.0 s.'),
        findsOneWidget);
    await back(tester);
    expect(saved(fakes).duckMusic, isTrue);
    expect(saved(fakes).soundTracks.single.duck, isTrue);
  });

  test('lengths in running text and title sizes read the same everywhere', () {
    expect(formatLength(0), '0.0 s');
    expect(formatLength(2500), '2.5 s');
    expect(formatLength(59900), '59.9 s');
    expect(formatLength(59960), '1 min');
    expect(formatLength(65000), '1 min 5 s');
    expect(formatLength(600000), '10 min');
    expect(formatLength(3725000), '1 h 2 min');
    expect(titleSizeLabel(0.03), 'Small · 3%');
    expect(titleSizeLabel(0.06), 'Medium · 6%');
    expect(titleSizeLabel(0.09), 'Large · 9%');
    expect(titleSizeLabel(0.2), 'Huge · 20%');
  });

  // 11 ----------------------------------------------------------------------
  group('keyboard', () {
    Future<void> withKey(WidgetTester tester, LogicalKeyboardKey modifier,
        Future<void> Function() body) async {
      await tester.sendKeyDownEvent(modifier);
      await body();
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('space, arrows, home and end move through the video',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(fakes.backend.video.playing, isTrue);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.space);
      expect(find.byTooltip('Play'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.end);
      expect(find.textContaining('0:18.0 / 0:18.0'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.home);
      expect(find.textContaining('0:00.0 / 0:18.0'), findsOneWidget);

      // Shift: a second at a time. Plain: a frame.
      await withKey(tester, LogicalKeyboardKey.shiftLeft, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      });
      expect(find.textContaining('0:02.0 / 0:18.0'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(find.textContaining('0:02.0 / 0:18.0'), findsOneWidget); // 2.099
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.textContaining('0:02.1 / 0:18.0'), findsOneWidget); // 2.132
    });

    testWidgets('S splits, Delete deletes, Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y '
        'undo and redo', (tester) async {
      final fakes = await openEditor(tester, desktop);
      await seekTo(tester, 2000);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(clipBlocks(), findsNWidgets(5));

      await withKey(tester, LogicalKeyboardKey.controlLeft,
          () => tester.sendKeyEvent(LogicalKeyboardKey.keyZ));
      expect(clipBlocks(), findsNWidgets(4));
      await withKey(tester, LogicalKeyboardKey.controlLeft, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
      expect(clipBlocks(), findsNWidgets(5));
      await withKey(tester, LogicalKeyboardKey.metaLeft,
          () => tester.sendKeyEvent(LogicalKeyboardKey.keyZ));
      expect(clipBlocks(), findsNWidgets(4));
      await withKey(tester, LogicalKeyboardKey.controlLeft,
          () => tester.sendKeyEvent(LogicalKeyboardKey.keyY));
      expect(clipBlocks(), findsNWidgets(5));

      // Nothing selected: Delete does nothing.
      await press(tester, LogicalKeyboardKey.delete);
      expect(clipBlocks(), findsNWidgets(5));
      await tester.tap(block('clip-d'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(clipBlocks(), findsNWidgets(4));
      await tester.tap(block('title-t1'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.backspace);
      expect(block('title-t1'), findsNothing);
      await back(tester);
      expect(clipIds(saved(fakes)), hasLength(4));
      expect(clipIds(saved(fakes)), isNot(contains('d')));
      expect(saved(fakes).titles, isEmpty);
    });

    testWidgets('typing in a text field is never a shortcut', (tester) async {
      // On a computer a text field gives up the focus when something else
      // is clicked.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fakes = await openEditor(tester, desktop);
      await seekTo(tester, 2000);
      await tester.tap(block('title-t1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.home,
      ]) {
        await press(tester, key);
      }
      expect(clipBlocks(), findsNWidgets(4));
      expect(block('title-t1'), findsOneWidget);
      expect(fakes.backend.video.playing, isFalse);
      expect(find.textContaining('0:02.0 / 0:18.0'), findsOneWidget);

      // Clicking the timeline gives the keys back to the editor.
      await seekTo(tester, 3000);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyS);
      expect(clipBlocks(), findsNWidgets(5));
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
