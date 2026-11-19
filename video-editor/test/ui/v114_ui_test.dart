// 1.14 in the app: "Where is it going?" in the Export window (presets,
// warnings, a copy in the destination's shape or as it is), "Export
// several…" as one job, the finished screen (Share on phones; Show in
// folder, Copy title and description and upload pages on computers),
// Publishing notes (Copy buttons, chapters, undo with History names),
// "Make a short from this…" in the Text window, and good-moment markers
// with "Make shorts from markers…". Overflow errors fail these tests by
// themselves.
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/publish/shorts.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/shorts_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';
import 'text_window_test.dart' show podcast;

Finder key(String k) => find.byKey(ValueKey(k));

EditorSession session(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

List<String> catchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// A wide 95-second talk with titles (chapters) and notes.
Project talk({bool notes = true}) => Project(
      id: 'p1',
      name: 'Bread talk',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
      clips: [
        Clip(
            id: 'a',
            type: ClipType.video,
            path: '/media/talk.mp4',
            sourceDurationMs: 95000,
            inMs: 0,
            outMs: 95000,
            width: 1920,
            height: 1080),
      ],
      titles: const [
        TitleOverlay(id: 't1', text: 'Welcome', startMs: 1000, endMs: 4000),
        TitleOverlay(id: 't2', text: 'The dough', startMs: 30000, endMs: 33000),
        TitleOverlay(id: 't3', text: 'The oven', startMs: 62000, endMs: 65000),
      ],
      publishing: notes
          ? const PublishingNotes(
              title: 'Why the first loaf fails',
              description: 'Sam explains the window test.',
              hashtags: ['bread', 'baking'],
              shortTitle: 'The window test')
          : PublishingNotes.empty,
    );

Future<Fakes> open(WidgetTester tester, Size size, Project project) async {
  useScreen(tester, size);
  final f = Fakes(projects: [project], missing: const {});
  f.files.desktop = size.width >= 600;
  f.documents.phone = !f.files.desktop;
  await tester.pumpWidget(f.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  return f;
}

Future<void> openExport(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Export'));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

/// Presses the Export button (the window then shows a moving bar, so
/// nothing "settles").
Future<void> startExport(WidgetTester tester) async {
  await tester.ensureVisible(key('export-go'));
  await tester.pumpAndSettle();
  await tester.tap(key('export-go'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Finishes the export the fake engine is on, and lets the window go on.
Future<void> finishExport(WidgetTester tester, Fakes f) async {
  f.engine.jobs.last.report(0.5);
  await tester.pump();
  f.engine.jobs.last.finish(f.engine.lastExportPath!);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    final isPhone = label == 'phone';

    testWidgets('$label: Where is it going? The presets, the limit warning, '
        'and the question about another shape', (tester) async {
      final f = await open(tester, size, talk());
      await openExport(tester);
      expect(find.text('Where is it going?'), findsOneWidget);
      for (final id in ['youtube', 'shorts', 'instagram', 'whatsapp', 'podcast', 'custom']) {
        expect(key('export-dest-$id'), findsOneWidget);
      }
      // Custom is where it starts: the controls of before.
      expect(find.text('Full quality'), findsOneWidget);
      // YouTube: the same shape, no question.
      await tapKey(tester, 'export-dest-youtube');
      expect(find.text('Full quality'), findsNothing);
      expect(key('export-shape-differs'), findsNothing);
      expect(tester.widget<Text>(key('export-dest-size')).data, '1920 × 1080');
      expect(key('export-dest-warning'), findsNothing);
      // Shorts: another shape, and this video is longer than is safe.
      await tapKey(tester, 'export-dest-shorts');
      expect(tester.widget<Text>(key('export-shape-differs')).data,
          'Your video is 1920 × 1080; this needs 9:16.');
      expect(find.text('Make a copy in this shape'), findsOneWidget);
      expect(find.text('Export as it is'), findsOneWidget);
      expect(find.textContaining('Crop and position'), findsOneWidget);
      expect(tester.widget<Text>(key('export-dest-size')).data, '1080 × 1920');
      final warning = tester.widget<Text>(key('export-dest-warning')).data!;
      expect(warning, startsWith('This video is 1:35 long.'));
      expect(warning, contains('Check the site'));
      await f.screenshot(tester, 'export_${label}_destination');
      await tapKey(tester, 'export-shape-as-is');
      expect(tester.widget<Text>(key('export-dest-size')).data, '1920 × 1080');
      // Instagram: tall or square.
      await tapKey(tester, 'export-dest-instagram');
      expect(tester.widget<Text>(key('export-dest-size')).data, '1080 × 1350');
      await tester.tap(find.text('Square 1:1'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('export-dest-size')).data, '1080 × 1080');
      // WhatsApp: small; a podcast: sound only.
      await tapKey(tester, 'export-dest-whatsapp');
      expect(tester.widget<Text>(key('export-dest-size')).data,
          contains('made smaller for sending'));
      expect(tester.widget<Text>(key('export-dest-warning')).data, contains('16 MB'));
      await tapKey(tester, 'export-dest-podcast');
      expect(find.text('Export sound'), findsOneWidget);
      expect(key('export-dest-size'), findsNothing);
      expect(find.text('MP3'), findsOneWidget);
      expect(find.text('M4A'), findsOneWidget);
    });

    testWidgets('$label: a copy in the shape is a new project; the project '
        'itself is not changed', (tester) async {
      final f = await open(tester, size, talk());
      await openExport(tester);
      await tapKey(tester, 'export-dest-shorts');
      await startExport(tester);
      // The copy went to the project list, upright, blurred background.
      expect(f.store.projects.length, 2);
      final copy = f.store.projects.values.firstWhere((x) => x.id != 'p1');
      expect(copy.name, 'Bread talk - 9x16');
      expect(copy.aspect, CanvasAspect.portrait9x16);
      expect(copy.clips.single.fit, FitMode.blur);
      expect(f.engine.lastProject!.id, copy.id);
      expect(f.engine.lastProject!.canvasSize, (width: 1080, height: 1920));
      expect(f.engine.lastOptions!.quality, ExportQuality.full);
      if (!isPhone) expect(f.engine.lastExportPath, '/out/movie.mp4');
      final original = f.store.projects['p1']!;
      expect(original.aspect, CanvasAspect.original);
      expect(original.clips.single.fit, FitMode.fit);
      expect(session(tester).editor.canUndo, isFalse);
      await finishExport(tester, f);
      expect(tester.widget<Text>(key('export-copy-made')).data,
          contains('"Bread talk - 9x16" is in your project list'));
    });

    testWidgets('$label: Export as it is makes no copy', (tester) async {
      final f = await open(tester, size, talk());
      await openExport(tester);
      await tapKey(tester, 'export-dest-shorts');
      await tapKey(tester, 'export-shape-as-is');
      await startExport(tester);
      expect(f.store.projects.length, 1);
      expect(f.engine.lastProject!.canvasSize, (width: 1920, height: 1080));
      expect(f.engine.lastProject!.clips.single.fit, FitMode.fit);
      await finishExport(tester, f);
      expect(key('export-copy-made'), findsNothing);
    });

    testWidgets('$label: Export several is one job into one place', (tester) async {
      final f = await open(tester, size, talk());
      final dir = Directory.systemTemp.createTempSync('clipforge_ui_kit_');
      addTearDown(() => dir.deleteSync(recursive: true));
      f.publish
        ..folder = dir.path
        ..appFolder = dir.path;
      await openExport(tester);
      await tapKey(tester, 'export-several');
      expect(find.text('Export several'), findsOneWidget);
      // YouTube and Shorts are ticked to start with.
      expect(tester.widget<CheckboxListTile>(key('export-tick-youtube')).value, isTrue);
      expect(tester.widget<CheckboxListTile>(key('export-tick-shorts')).value, isTrue);
      expect(find.text('Bread talk - Short 9x16.mp4'), findsOneWidget);
      expect(key('export-tick-warning-shorts'), findsOneWidget);
      expect(tester.widget<Text>(key('export-several-shapes')).data,
          contains('Your project stays as it is'));
      await tapKey(tester, 'export-tick-podcast');
      expect(find.text('Export 3 files'), findsOneWidget);
      expect(tester.widget<Text>(key('export-several-summary')).data,
          contains(isPhone ? 'album called "Bread talk"' : 'You choose the folder next'));
      await f.screenshot(tester, 'export_${label}_several');
      await startExport(tester);
      // One after another.
      expect(f.engine.exports.length, 1);
      expect(p.basename(f.engine.lastExportPath!), 'Bread talk - YouTube.part.mp4');
      expect(tester.widget<Text>(key('export-progress')).data, contains('1 of 3: YouTube'));
      await finishExport(tester, f);
      expect(f.engine.exports.length, 2);
      expect(f.engine.lastProject!.aspect, CanvasAspect.portrait9x16);
      expect(tester.widget<Text>(key('export-progress')).data,
          contains('2 of 3: Shorts / Reels / TikTok'));
      await finishExport(tester, f);
      expect(f.engine.lastOptions!.format, ExportFormat.mp3);
      await finishExport(tester, f);
      await tester.pumpAndSettle();
      expect(find.text('Files saved'), findsOneWidget);
      for (final k in ['youtube', 'shorts', 'podcast']) {
        expect(key('export-file-$k'), findsOneWidget);
      }
      expect(tester.widget<Text>(key('export-text-file')).data,
          'Bread talk - text.txt - the text to paste');
      // Nothing was added to the project list, the project is as it was.
      expect(f.store.projects.length, 1);
      expect(session(tester).project.aspect, CanvasAspect.original);
      final text = File(p.join(dir.path, 'Bread talk - text.txt'));
      expect(text.readAsStringSync(), contains('TITLE\nWhy the first loaf fails'));
      expect(text.readAsStringSync(),
          contains('File: Bread talk - Short 9x16.mp4\nTitle: The window test'));
      if (isPhone) {
        // The videos went to an album named after the project.
        expect(f.publish.albumSaves.map((s) => (p.basename(s.path), s.album)), [
          ('Bread talk - YouTube.mp4', 'Bread talk'),
          ('Bread talk - Short 9x16.mp4', 'Bread talk'),
        ]);
        expect(find.textContaining('Saved to your gallery, album "Bread talk"'),
            findsOneWidget);
      }
      await f.screenshot(tester, 'export_${label}_several_done');
    });

    testWidgets('$label: cancelling a kit goes back to the choices', (tester) async {
      final f = await open(tester, size, talk());
      final dir = Directory.systemTemp.createTempSync('clipforge_ui_kit_');
      addTearDown(() => dir.deleteSync(recursive: true));
      f.publish
        ..folder = dir.path
        ..appFolder = dir.path;
      await openExport(tester);
      await tapKey(tester, 'export-several');
      await startExport(tester);
      await tester.tap(find.text('Cancel export'));
      await tester.pumpAndSettle();
      expect(f.engine.jobs.single.cancelled, isTrue);
      expect(find.text('Export several'), findsOneWidget);
      expect(f.engine.exports.length, 1);
    });

    testWidgets('$label: the finished screen', (tester) async {
      final copied = catchClipboard(tester);
      final f = await open(tester, size, talk());
      await openExport(tester);
      await tapKey(tester, 'export-dest-youtube');
      await startExport(tester);
      await finishExport(tester, f);
      await tester.pumpAndSettle();
      expect(find.text('Video saved'), findsOneWidget);
      // The notes, each with Copy.
      expect(find.text('Why the first loaf fails'), findsOneWidget);
      await tapKey(tester, 'export-copy-title');
      expect(copied.last, 'Why the first loaf fails');
      await tapKey(tester, 'export-copy-description');
      expect(copied.last, 'Sam explains the window test.\n\n#bread #baking');
      await tapKey(tester, 'export-copy-notes');
      expect(copied.last,
          'Why the first loaf fails\n\nSam explains the window test.\n\n#bread #baking');
      if (isPhone) {
        expect(find.text('Saved to your gallery (Movies)'), findsOneWidget);
        expect(key('export-show-folder'), findsNothing);
        expect(key('export-upload-youtube'), findsNothing);
        await tapKey(tester, 'export-share');
        final share = f.publish.shares.single;
        expect(share.paths, [f.engine.lastExportPath]);
        expect(share.text, startsWith('Why the first loaf fails\n\nSam explains'));
        expect(share.subject, 'Why the first loaf fails');
        // Still there after sharing: many apps ignore shared text.
        expect(key('export-copy-notes'), findsOneWidget);
        expect(find.textContaining('Many apps ignore text'), findsOneWidget);
      } else {
        expect(key('export-share'), findsNothing);
        await tapKey(tester, 'export-show-folder');
        expect(f.publish.shown, ['/out/movie.mp4']);
        await tapKey(tester, 'export-upload-youtube');
        expect(f.publish.opened, ['https://www.youtube.com/upload']);
        expect(find.textContaining('ClipForge does not sign in or post'), findsOneWidget);
      }
      await f.screenshot(tester, 'export_${label}_finished');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('$label: a short-form export offers the short title and '
        'three upload pages', (tester) async {
      final copied = catchClipboard(tester);
      final f = await open(tester, size, talk());
      await openExport(tester);
      await tapKey(tester, 'export-dest-shorts');
      await tapKey(tester, 'export-shape-as-is');
      await startExport(tester);
      await finishExport(tester, f);
      await tester.pumpAndSettle();
      await tapKey(tester, 'export-copy-title');
      expect(copied.last, 'The window test');
      if (!isPhone) {
        for (final site in ['youtube', 'instagram', 'tiktok']) {
          expect(key('export-upload-$site'), findsOneWidget);
        }
        await tapKey(tester, 'export-upload-tiktok');
        expect(f.publish.opened.single, 'https://www.tiktok.com/upload');
      }
    });

    testWidgets('$label: Publishing notes: fields with Copy, chapters from '
        'the titles, every change an undo step with a name', (tester) async {
      final copied = catchClipboard(tester);
      final f = await open(tester, size, talk(notes: false));
      final s = session(tester);
      if (isPhone) {
        // Phones: the project menu.
        await tapProjectMenu(tester, 'Publishing notes');
      } else {
        await tapKey(tester, 'panel-publishing-notes');
      }
      expect(key('notes-panel'), findsOneWidget);
      await tester.enterText(key('notes-title'), 'Why the first loaf fails');
      await tester.enterText(key('notes-description'), 'Sam explains.');
      await tester.enterText(key('notes-hashtags'), '#bread, baking');
      await tester.pumpAndSettle();
      await tapKey(tester, 'notes-copy-hashtags');
      expect(copied.last, '#bread #baking');
      // Chapters from the three titles.
      await tapKey(tester, 'notes-make-chapters');
      expect(tester.widget<TextField>(key('notes-chapters')).controller!.text,
          '0:00 Welcome\n0:30 The dough\n1:02 The oven');
      expect(tester.widget<Text>(key('notes-chapter-note')).data,
          '3 chapters from your titles.');
      expect(key('notes-chapter-problem'), findsNothing);
      await tapKey(tester, 'notes-copy-chapters');
      expect(copied.last, '0:00 Welcome\n0:30 The dough\n1:02 The oven');
      // A list that breaks the rules says so.
      await tester.enterText(key('notes-chapters'), '0:05 Late\n0:09 Soon');
      await tester.pumpAndSettle();
      expect(key('notes-chapter-problem'), findsWidgets);
      await tester.enterText(
          key('notes-chapters'), '0:00 Welcome\n0:30 The dough\n1:02 The oven');
      await tester.pumpAndSettle();
      await tapKey(tester, 'notes-show-short');
      await tester.enterText(key('notes-short-title'), 'The window test');
      await tester.pumpAndSettle();
      await f.screenshot(tester, 'publishing_notes_$label');
      await tapKey(tester, 'notes-copy-all');
      expect(copied.last, startsWith('Why the first loaf fails\n\nSam explains.\n\n0:00 Welcome'));
      await tapKey(tester, 'notes-done');
      expect(key('notes-panel'), findsNothing);
      final n = s.project.publishing;
      expect(n.title, 'Why the first loaf fails');
      expect(n.hashtags, ['bread', 'baking']);
      expect(n.chapters.map((c) => c.ms), [0, 30000, 62000]);
      expect(n.shortTitle, 'The window test');
      final labels = [for (final h in s.editor.history) h.label];
      expect(labels.first, anyOf('Publishing title', 'Publishing notes'));
      expect(labels, contains('Chapters (3)'));
      expect(labels.last, 'Short title');
      // Undo takes the last change back.
      s.editor.undo();
      await tester.pumpAndSettle();
      expect(s.project.publishing.shortTitle, '');
      expect(s.project.publishing.title, 'Why the first loaf fails');
    });

    testWidgets('$label: Text window: Make a short from this…', (tester) async {
      final f = await open(tester, size, podcast());
      final s = session(tester);
      if (isPhone) {
        await tapKey(tester, 'tool-text');
        await tapInTextWindow(tester, 'And what did they say?');
        await tester.pumpAndSettle();
      } else {
        await tester.tap(key('text-button'));
        await tester.pumpAndSettle();
        await tapInTextWindow(tester, 'And what did they say?');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tapInTextWindow(tester, 'So you added salt.');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
      }
      await tapKey(tester, 'text-make-short');
      expect(key('short-dialog'), findsOneWidget);
      // The length is shown; nothing here is over the limit.
      expect(tester.widget<Text>(key('short-length')).data, contains(' · '));
      expect(key('short-warning'), findsNothing);
      // The title at the top is the first sentence, and can be changed.
      expect(tester.widget<TextField>(key('short-title')).controller!.text,
          'And what did they say?');
      if (isPhone) {
        // One line is selected on a phone: 30 / 45 / 60 s from there.
        await tapKey(tester, 'short-length-30');
        expect(tester.widget<Text>(key('short-length')).data, contains('30'));
      }
      await tester.enterText(key('short-title'), 'It needed salt');
      await tester.enterText(key('short-name'), 'Salt short');
      await tester.pumpAndSettle();
      await f.screenshot(tester, 'short_dialog_$label');
      await tapKey(tester, 'short-go');
      expect(key('short-made'), findsOneWidget);
      final short = f.store.projects.values.singleWhere((x) => x.id != 'p1');
      expect(short.name, 'Salt short');
      expect(short.aspect, CanvasAspect.portrait9x16);
      expect(short.videoSize, VideoSize.p1080);
      expect(short.durationMs, lessThan(podcast().durationMs));
      expect(short.clips.single.fit, FitMode.blur);
      final captions = short.titles.where((t) => t.kind == TitleKind.caption).toList();
      expect(captions, isNotEmpty);
      expect(captions.every((c) => c.fontSize == ShortLook.captionFontSize && c.outline),
          isTrue);
      expect(captions.every((c) => c.text.split('\n').length <= 2), isTrue);
      expect(captions.first.text, contains('And what did they'));
      final top = short.titles.singleWhere((t) => t.kind == TitleKind.title);
      expect(top.text, 'It needed salt');
      expect((top.startMs, top.endMs), (0, short.durationMs));
      // This video was not changed, and nothing is on its undo list.
      expect(s.project.aspect, CanvasAspect.landscape16x9);
      expect(s.editor.canUndo, isFalse);
      await f.screenshot(tester, 'short_made_$label');
      // Open it: the editor shows the short.
      await tapKey(tester, 'short-open');
      await tester.pumpAndSettle();
      expect(find.text('Salt short'), findsOneWidget);
      expect(session(tester).project.id, short.id);
    });

    testWidgets('$label: good moments: mark, see them on the ruler, make '
        'shorts from the markers', (tester) async {
      final f = await open(tester, size, podcast(count: 60));
      final s = session(tester);
      Future<void> mark(int ms) async {
        s.playback.seek(ms);
        await tester.pumpAndSettle();
        if (isPhone) {
          await tester.tap(find.text('More'));
          await tester.pumpAndSettle();
          await tapKey(tester, 'more-mark-moment');
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Marked a good moment at'), findsOneWidget);
        // The message goes away by itself.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      await mark(30000);
      expect(s.project.markers.single.ms, 30000);
      await mark(75000);
      expect(s.project.markers.length, 2);
      expect([for (final h in s.editor.history) h.label], [
        'Marked a good moment at 0:30',
        'Marked a good moment at 1:15',
      ]);
      // A flag on the ruler for the one in view.
      s.playback.seek(28000);
      await tester.pumpAndSettle();
      expect(key('marker-${s.project.markers.first.id}'), findsOneWidget);
      await f.screenshot(tester, 'markers_$label');
      // The list.
      if (isPhone) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tapKey(tester, 'more-shorts');
        await tapKey(tester, 'panel-good-moments');
      } else {
        await tapKey(tester, 'panel-good-moments');
      }
      expect(key('markers-dialog'), findsOneWidget);
      expect(find.text('0:30.0'), findsOneWidget);
      await f.screenshot(tester, 'markers_list_$label');
      await tapKey(tester, 'markers-make-shorts');
      expect(key('markers-shorts-dialog'), findsOneWidget);
      expect(find.text('Make 2 shorts from the markers?'), findsOneWidget);
      await tapKey(tester, 'markers-shorts-go');
      await tester.pumpAndSettle();
      expect(find.text('2 shorts are ready'), findsOneWidget);
      final shorts = f.store.projects.values.where((x) => x.id != 'p1').toList();
      expect(shorts.length, 2);
      // Around each marker, starting and ending between captions: no
      // caption of a short is cut at its edge.
      final captions = podcast(count: 60)
          .titles
          .where((t) => t.kind == TitleKind.caption)
          .toList();
      for (final m in s.project.markers) {
        final plan = markerRange(m.ms, s.project.durationMs);
        final short = shorts.firstWhere((x) => x.name.endsWith(
            'short ${m.ms ~/ 60000}:${(m.ms ~/ 1000 % 60).toString().padLeft(2, '0')}'));
        expect(short.durationMs, greaterThanOrEqualTo(plan.endMs - plan.startMs));
        expect(short.durationMs, lessThan(plan.endMs - plan.startMs + 8000));
        expect(short.aspect, CanvasAspect.portrait9x16);
        expect(short.markers, isEmpty);
        final clip = short.clips.single;
        for (final c in captions) {
          final cutAtStart = c.startMs < clip.inMs && c.endMs > clip.inMs;
          final cutAtEnd = c.startMs < clip.outMs && c.endMs > clip.outMs;
          expect(cutAtStart || cutAtEnd, isFalse,
              reason: '${c.text} at ${c.startMs} is cut by ${clip.inMs}-${clip.outMs}');
        }
      }
      await tapKey(tester, 'short-stay');
      expect(s.project.markers.length, 2);
    });
  }

  testWidgets('desktop: the menu bar has the new items; a short from the '
      'playhead warns over the limit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    useScreen(tester, desktop);
    final f = Fakes(projects: [talk()], missing: const {});
    await tester.pumpWidget(f.app(const EditorScreen(projectId: 'p1'), menuBar: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(key('menu-publishing-notes'), findsOneWidget);
    expect(key('menu-export-several'), findsOneWidget);
    await tester.tap(key('menu-export-several'));
    await tester.pumpAndSettle();
    expect(find.text('Export several'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(key('menu-mark-moment'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clip'));
    await tester.pumpAndSettle();
    expect(key('menu-good-moments'), findsOneWidget);
    expect(key('menu-shorts-from-markers'), findsOneWidget);
    await tester.tap(key('menu-short-from-here'));
    await tester.pumpAndSettle();
    expect(key('short-dialog'), findsOneWidget);
    for (final n in kShortLengths) {
      expect(key('short-length-$n'), findsOneWidget);
    }
    expect(tester.widget<Text>(key('short-length')).data, 'From 0:00.0 to 0:30.0 · 30.0 s');
    expect(key('short-warning'), findsNothing);
    await tapKey(tester, 'short-length-60');
    expect(key('short-warning'), findsNothing, reason: '60 s is the limit, not over it');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(f.store.projects.length, 1);
  });

  testWidgets('a part longer than the limit is warned about, not refused',
      (tester) async {
    final f = await open(tester, desktop, podcast(count: 80));
    final s = session(tester);
    expect(s.project.durationMs, greaterThan(100000));
    showMakeShort(tester.element(find.byType(PreviewView)), s,
        fromMs: 0, toMs: 95000, firstText: 'Sam: A long story. And more.');
    await tester.pumpAndSettle();
    final warning = tester.widget<Text>(key('short-warning')).data!;
    expect(warning, startsWith('Longer than 60 seconds'));
    expect(warning, contains('check the site'));
    expect(tester.widget<TextField>(key('short-title')).controller!.text,
        'Sam: A long story.');
    await tapKey(tester, 'short-go');
    expect(f.store.projects.length, 2, reason: 'it is made all the same');
    await tapKey(tester, 'short-stay');
  });
}
