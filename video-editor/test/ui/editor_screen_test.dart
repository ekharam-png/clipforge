import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('editor lays out on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      expect(find.text('Summer trip'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(clipBlocks(), findsNWidgets(4));
      expect(find.text('Summer 2026'), findsWidgets);
      expect(find.textContaining('0:00.0 / 0:18.0'), findsOneWidget);
      expect(find.textContaining('Missing'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_$label');

      // Select a clip: the actions for it appear.
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_clip_selected');

      // The playhead on the missing clip shows the notice, not a crash.
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      await seekTo(tester, 10000, zoom: 60 / 1.5 / 1.5);
      await tester.pumpAndSettle();
      expect(find.text('File not found'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_missing_file');

      // A title's properties.
      await tester.tap(block('title-t1'));
      await tester.pumpAndSettle();
      if (label == 'phone') {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Dark box behind text'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_title');
    });

    testWidgets('empty project asks for media on a $label screen',
        (tester) async {
      final empty = Project(
        id: 'p1',
        name: 'New video',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final fakes = await openEditor(tester, size, project: empty);
      expect(find.text('Add videos or photos'), findsOneWidget);
      expect(tester.widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Export'))
          .onPressed, isNull);
      await fakes.screenshot(tester, 'editor_${label}_empty');
    });

    testWidgets('select, split, undo on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pump();
      await seekTo(tester, 2000);
      expect(find.textContaining('0:02.0 / 0:18.0'), findsOneWidget);
      // seekTo taps the ruler, which keeps the selection.
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(5));

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(4));
      expect(tester.widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.undo))
          .onPressed, isNull);

      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(5));

      // Back flushes the autosave.
      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      expect(saved(fakes).clips, hasLength(5));
      expect(saved(fakes).clips[0].outMs, 2000);
      expect(saved(fakes).clips[1].inMs, 2000);
    });
  }

  testWidgets('split away from a clip explains itself', (tester) async {
    await openEditor(tester, phone);
    await tester.tap(find.text('Split')); // playhead at 0
    await tester.pump();
    expect(find.textContaining('Move the playhead inside a clip'),
        findsOneWidget);
    expect(clipBlocks(), findsNWidgets(4));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('dragging a trim handle is a single undo step', (tester) async {
    final fakes = await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    // 60 px per second: 120 px to the left takes 2 s off the end.
    await tester.drag(find.bySemanticsLabel('Trim end'), const Offset(-120, 0),
        touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(find.textContaining('/ 0:16.0'), findsOneWidget);

    await tester.drag(find.bySemanticsLabel('Trim start'), const Offset(60, 0),
        touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(find.textContaining('/ 0:15.0'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/ 0:16.0'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/ 0:18.0'), findsOneWidget);
    expect(tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.undo))
        .onPressed, isNull);
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect(saved(fakes).clips.first.outMs, 6000);
  });

  testWidgets('clip actions: mute, fit, move, delete', (tester) async {
    final fakes = await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();

    await openClipTool(tester, desktop, 'Sound');
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Look');
    await tester.ensureVisible(find.text('Fill'));
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Move later'));
    await tester.tap(find.text('Move later'));
    await tester.pumpAndSettle();
    await tester.tap(block('clip-d'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing); // selection cleared

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    final p = saved(fakes);
    expect([for (final c in p.clips) c.id], ['b', 'a', 'c']);
    expect(p.clips[1].muted, isTrue);
    expect(p.clips[1].fit, FitMode.fill);
  });

  testWidgets('play runs the clock and pause stops it', (tester) async {
    final fakes = await openEditor(tester, phone);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fakes.backend.video.playing, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    fakes.backend.video.emitPosition(40);
    fakes.backend.video.emitPosition(6000); // end of the first clip
    await tester.pump();
    // The photo is timed by the screen's ticker.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('0:07.0 / 0:18.0'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('adding media probes files and reports the unreadable ones',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.engine.infos['/in/new.mp4'] = const MediaInfo(
        durationMs: 4000, width: 1080, height: 1920, hasVideo: true, hasAudio: true);
    fakes.engine.infos['/in/pic.PNG'] = const MediaInfo(
        durationMs: 0, width: 800, height: 600, hasVideo: true, hasAudio: false);
    fakes.files.media = const [
      PickedFile('/in/new.mp4', 'new.mp4'),
      PickedFile('/in/pic.PNG', 'pic.PNG'),
      PickedFile('/in/broken.mov', 'broken.mov'),
    ];
    await tapAdd(tester, 'Add media');
    expect(find.text('A file could not be added'), findsOneWidget);
    expect(find.textContaining('broken.mov'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(clipBlocks(), findsNWidgets(6));
    // With nothing selected they went in at the end, and the first of them
    // is on show.
    expect(find.textContaining('0:18.0 / 0:25.0'), findsOneWidget);

    // Both files came in as one undo step.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(clipBlocks(), findsNWidgets(4));
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect(clipIds(saved(fakes)).sublist(0, 4), ['a', 'b', 'c', 'd']);
    final added = saved(fakes).clips.sublist(4);
    expect(added[0].type, ClipType.video);
    expect(added[0].outMs, 4000);
    expect(added[1].type, ClipType.photo);
    expect(added[1].durationMs, 3000);
    // A 4:3 photo in a 16:9 project sits on a blurred copy of itself.
    expect(added[1].fit, FitMode.blur);
  });

  testWidgets('music lands at the playhead; a title can be added and edited',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    await seekTo(tester, 3000);
    fakes.engine.infos['/in/tune.mp3'] = const MediaInfo(
        durationMs: 9000, width: 0, height: 0, hasVideo: false, hasAudio: true);
    fakes.files.audio = const [PickedFile('/in/tune.mp3', 'tune.mp3')];
    await tapAdd(tester, 'Music');
    // 1.10: "What is this sound?" - Music is chosen for a song.
    expect(find.text('What is this sound?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    expect(find.text('tune.mp3'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit music'), findsOneWidget);
    expect(find.text('Fade in'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tapAdd(tester, 'Title');
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dark box behind text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark box behind text'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsWidgets);

    // Typing a word is one undo step, the switch another.
    await tester.tap(find.byTooltip('Undo'));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsNothing);
    expect(block('title-t1'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    final p = saved(fakes);
    expect(p.audio.last.startMs, 3000);
    expect(p.audio.last.outMs, 9000);
    expect(p.audio.last.fadeOutMs, 1000);
    expect(p.titles.last.text, 'Title');
    expect(p.titles.last.startMs, 3000);
    expect(p.titles.last.endMs, 6000);
  });

  testWidgets('aspect menu and rename', (tester) async {
    final fakes = await openEditor(tester, phone);
    // Phones: the project menu has "Shape and size".
    await tapProjectMenu(tester, 'Shape and size');
    expect(find.textContaining('Original'), findsOneWidget);
    expect(find.text('4:5 upright'), findsOneWidget);
    await tester.tap(find.text('9:16 upright'));
    await tester.pumpAndSettle();
    await closeSheet(tester, phone);
    await fakes.screenshot(tester, 'editor_phone_9x16');

    await tester.tap(find.text('Summer trip'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road movie');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Road movie'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect(saved(fakes).aspect, CanvasAspect.portrait9x16);
    expect(saved(fakes).name, 'Road movie');
  });

  testWidgets('zoom buttons change the timeline scale', (tester) async {
    await openEditor(tester, phone);
    final before = tester.getSize(block('clip-a')).width;
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(tester.getSize(block('clip-a')).width, closeTo(before * 1.5, 0.01));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(tester.getSize(block('clip-a')).width, closeTo(before / 1.5, 0.01));
  });

  group('export', () {
    testWidgets('desktop: pick a place, progress, success', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: {});
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'export_options_desktop');
      await tester.tap(find.text('Small file'));
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      expect(find.text('Exporting…'), findsOneWidget);
      expect(fakes.engine.lastExportPath, '/out/movie.mp4');
      expect(fakes.engine.lastOptions!.quality, ExportQuality.small);
      fakes.engine.jobs.single.report(0.42);
      await tester.pump();
      await tester.pump();
      expect(find.text('42%'), findsOneWidget);
      await fakes.screenshot(tester, 'export_progress_desktop');
      fakes.engine.jobs.single.finish('/out/movie.mp4');
      await tester.pumpAndSettle();
      expect(find.text('Video saved'), findsOneWidget);
      expect(find.text('/out/movie.mp4'), findsOneWidget);
      expect(fakes.files.copiedTo, isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Video saved'), findsNothing);
    });

    testWidgets('phone: the finished video goes to the gallery',
        (tester) async {
      final fakes = await openEditor(tester, phone, missingFiles: {});
      fakes.files.desktop = false;
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      final path = fakes.engine.lastExportPath!;
      expect(path, startsWith('/app/exports/Summer trip '));
      fakes.engine.jobs.single.finish(path);
      await tester.pumpAndSettle();
      expect(fakes.files.copiedTo, path);
      expect(find.text('Saved to your gallery (Movies)'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      await fakes.screenshot(tester, 'export_done_phone');
    });

    testWidgets('phone: gallery refused keeps the video and offers a retry',
        (tester) async {
      final fakes = await openEditor(tester, phone, missingFiles: {});
      fakes.files
        ..desktop = false
        ..galleryAllowed = false;
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      final path = fakes.engine.lastExportPath!;
      fakes.engine.jobs.single.finish(path);
      await tester.pumpAndSettle();
      expect(find.textContaining('not allowed to add the video'),
          findsOneWidget);
      expect(find.text(path), findsOneWidget);
      await fakes.screenshot(tester, 'export_gallery_refused_phone');

      fakes.files.galleryAllowed = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(fakes.files.copiedTo, path);
      expect(find.text('Saved to your gallery (Movies)'), findsOneWidget);
    });

    testWidgets('failure shows the message; cancel returns to the options',
        (tester) async {
      final fakes = await openEditor(tester, phone, missingFiles: {});
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      fakes.engine.jobs.last.fail(ExportException(
          'A clip could not be read: gone.mp4',
          log: 'ffmpeg: No such file'));
      await tester.pumpAndSettle();
      expect(find.text('Export failed'), findsOneWidget);
      expect(find.text('A clip could not be read: gone.mp4'), findsOneWidget);
      await fakes.screenshot(tester, 'export_failed_phone');

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel export'));
      await tester.pumpAndSettle();
      expect(fakes.engine.jobs.last.cancelled, isTrue);
      expect(find.text('Export video'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('cancelling the save dialog stays on the options',
        (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: {});
      fakes.files.savePath = null;
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pumpAndSettle();
      expect(find.text('Export video'), findsOneWidget);
      expect(fakes.engine.jobs, isEmpty);
    });
  });
}
