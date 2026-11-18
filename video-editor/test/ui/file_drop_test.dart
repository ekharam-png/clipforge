import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/file_drop.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const _video = MediaInfo(
    durationMs: 4000, width: 1920, height: 1080, hasVideo: true, hasAudio: true);
const _photo = MediaInfo(
    durationMs: 0, width: 1920, height: 1080, hasVideo: true, hasAudio: false);
const _song = MediaInfo(
    durationMs: 60000, width: 0, height: 0, hasVideo: false, hasAudio: true);

const _srt = '1\n00:00:01,000 --> 00:00:02,500\nHello there\n';

Future<Fakes> openHome(WidgetTester tester, {List<Project> projects = const []}) async {
  useScreen(tester, desktop);
  final fakes = Fakes(projects: projects);
  await tester.pumpWidget(fakes.app(const HomeScreen()));
  await tester.pumpAndSettle();
  return fakes;
}

/// Where the timeline of the editor shows [ms] on the main track.
Offset timelineAt(WidgetTester tester, int ms) =>
    timelineOrigin(tester) + Offset(28 + ms * 60 / 1000, 32 + 28);

void main() {
  setUpAll(loadFonts);

  group('sorting a drop', () {
    test('by kind, in drop order; folder leftovers are only counted', () {
      final sorted = SortedDrop(const FileDrop(
        files: [
          DroppedFile('/d/b.MOV'),
          DroppedFile('/d/a.jpg'),
          DroppedFile('/d/song.m4a'),
          DroppedFile('/d/subs.srt'),
          DroppedFile('/d/trip.clipforge.zip'),
          DroppedFile('/d/notes.pdf'),
          DroppedFile('/f/1.mp4', folder: 'f'),
          DroppedFile('/f/readme.txt', folder: 'f'),
        ],
        folders: ['f'],
        globalPosition: Offset.zero,
      ));
      expect([for (final f in sorted.media) f.name], ['b.MOV', 'a.jpg', '1.mp4']);
      expect([for (final f in sorted.music) f.name], ['song.m4a']);
      expect([for (final f in sorted.subtitles) f.name], ['subs.srt']);
      expect([for (final f in sorted.projects) f.name], ['trip.clipforge.zip']);
      expect([for (final f in sorted.unsupported) f.name], ['notes.pdf']);
      expect(sorted.skippedInFolders, 1);
      expect(sorted.folderNote, contains('"f"'));
      expect(sorted.folderNote, contains('1 other file was left out'));
      expect(dropKindOf('/x/plain.zip'), DropKind.unsupported);
    });
  });

  group('home screen', () {
    testWidgets('dragging over shows where to drop; leaving hides it',
        (tester) async {
      final fakes = await openHome(tester);
      expect(find.text('Drop to start a new video'), findsNothing);
      fakes.drops.hover(const Offset(400, 300));
      await tester.pump();
      expect(find.text('Drop to start a new video'), findsOneWidget);
      await fakes.screenshot(tester, 'drop_home');
      fakes.drops.leave();
      await tester.pump();
      expect(find.text('Drop to start a new video'), findsNothing);
    });

    testWidgets('videos and photos start a new project in the dropped order',
        (tester) async {
      final fakes = await openHome(tester, projects: [sampleProject()]);
      fakes.engine.infos
        ..['/in/zeta.mp4'] = _video
        ..['/in/alpha.jpg'] = _photo
        ..['/in/beat.mp3'] = _song;
      fakes.drops.drop(['/in/zeta.mp4', '/in/alpha.jpg', '/in/beat.mp3']);
      await tester.pumpAndSettle();

      expect(find.byType(EditorScreen), findsOneWidget);
      // 1.10: the sound file is asked about (Music for a song).
      expect(find.text('What is this sound?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      final created = fakes.store.projects.values
          .firstWhere((p) => p.id != 'p1');
      // The editor saves after the files went in.
      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      final saved = fakes.store.projects[created.id]!;
      expect([for (final c in saved.clips) c.path],
          ['/in/zeta.mp4', '/in/alpha.jpg']);
      expect(saved.clips[1].type, ClipType.photo);
      expect([for (final a in saved.audio) a.path], ['/in/beat.mp3']);
      expect(saved.audio.single.startMs, 0);
    });

    testWidgets('a project file is opened as a project', (tester) async {
      final fakes = await openHome(tester);
      fakes.bundles.bundles['/in/trip.clipforge.zip'] =
          sampleProject(name: 'From the phone');
      fakes.drops.drop(['/in/trip.clipforge.zip']);
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsNothing);
      expect(find.text('From the phone'), findsOneWidget);
      expect(find.textContaining('was added to your projects'), findsOneWidget);
    });

    testWidgets('files that cannot be used are listed by name', (tester) async {
      final fakes = await openHome(tester);
      fakes.drops.drop(['/in/report.pdf', '/in/list.docx']);
      await tester.pumpAndSettle();
      expect(find.text('These files cannot be used'), findsOneWidget);
      expect(find.textContaining('report.pdf'), findsOneWidget);
      expect(find.textContaining('list.docx'), findsOneWidget);
      expect(fakes.store.projects, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    testWidgets('no drop area on phones', (tester) async {
      useScreen(tester, phone);
      final fakes = Fakes();
      fakes.drops.supported = false;
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(fakes.drops.activeTargets, 0);
      expect(find.text('No projects yet'), findsOneWidget);
    });
  });

  group('editor', () {
    testWidgets('dropped media goes at the end, music at the playhead, '
        'subtitles become captions, the rest is listed', (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.engine.infos
        ..['/in/new.mp4'] = _video
        ..['/in/beat.mp3'] = _song;
      fakes.documents.texts['/in/talk.srt'] = _srt;
      fakes.drops.hover(const Offset(400, 200));
      await tester.pump();
      expect(find.text('Drop to add to this video'), findsOneWidget);

      fakes.drops.drop(
          ['/in/new.mp4', '/in/beat.mp3', '/in/talk.srt', '/in/notes.pdf'],
          at: const Offset(400, 200));
      await tester.pumpAndSettle();
      expect(find.text('Drop to add to this video'), findsNothing);
      // 1.10: the sound file is asked about (Music for a song).
      expect(find.text('What is this sound?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      expect(find.text('A file could not be added'), findsOneWidget);
      expect(find.textContaining('notes.pdf'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      final p = saved(fakes);
      expect(p.clips.last.path, '/in/new.mp4');
      expect(p.clips, hasLength(5));
      expect(p.audio.last.path, '/in/beat.mp3');
      expect(p.titles.where((t) => t.text == 'Hello there'), hasLength(1));
    });

    testWidgets('dropped over the timeline: between the nearest clips',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.engine.infos['/in/new.mp4'] = _video;
      // 7 s is in the first half of the photo (6..9 s): before it.
      final at = timelineAt(tester, 7000);
      fakes.drops.hover(at);
      await tester.pump();
      expect(find.text('Drop to add here'), findsOneWidget);
      await fakes.screenshot(tester, 'drop_editor_timeline');
      fakes.drops.drop(['/in/new.mp4'], at: at);
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(5));

      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      expect([for (final c in saved(fakes).clips) c.path], [
        '/media/beach.mp4',
        '/in/new.mp4',
        '/media/sunset.jpg',
        '/media/gone.mp4',
        '/media/hike.mp4',
      ]);
    });

    testWidgets('a dropped folder: its media files, and a note', (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.engine.infos
        ..['/f/a.mp4'] = _video
        ..['/f/b.jpg'] = _photo;
      fakes.drops.drop(const [], files: const [
        DroppedFile('/f/a.mp4', folder: 'Holiday'),
        DroppedFile('/f/b.jpg', folder: 'Holiday'),
        DroppedFile('/f/notes.txt', folder: 'Holiday'),
      ], folders: const [
        'Holiday'
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('the folder "Holiday"'), findsOneWidget);
      expect(clipBlocks(), findsNWidgets(6));
    });

    testWidgets('no drops while a dialog covers the editor', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      expect(fakes.drops.activeTargets, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Export video'), findsOneWidget);
      expect(fakes.drops.activeTargets, 0);
    });

    testWidgets('an unreadable dropped file is reported like a picked one',
        (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      fakes.drops.drop(['/in/broken.mp4']);
      await tester.pumpAndSettle();
      expect(find.textContaining('broken.mp4 — the file could not be read'),
          findsOneWidget);
    });
  });

  group('export with the graphics card', () {
    testWidgets('the switch shows where there is one; the result says '
        'which part made the video', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      fakes.engine.hardwareEncoder = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Use graphics card (faster)'), findsOneWidget);
      // Before starting: which encoder will be used.
      expect(find.text('Will use: Graphics card — Media Foundation (Windows)'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      expect(fakes.engine.lastOptions!.useHardwareEncoder, isTrue);
      fakes.engine.jobs.last.finish('/out/movie.mp4',
          encoder: VideoEncoder.mediaFoundation);
      await tester.pumpAndSettle();
      // After: which encoder made it, and how long it took.
      final result = tester
          .widget<Text>(find.byKey(const ValueKey('export-encoder-result')))
          .data!;
      expect(result,
          startsWith('Made with the graphics card: Media Foundation (Windows). '
              'Took '));
      expect(result, endsWith(' s.'));
    });

    testWidgets('a graphics card that failed is said so', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      fakes.engine
        ..hardwareEncoder = true
        ..graphicsCardKind = VideoEncoder.videotoolbox;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Will use: Graphics card — VideoToolbox (Mac)'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      fakes.engine.jobs.last.finish('/out/movie.mp4');
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Made with the processor — the graphics card '
              '(VideoToolbox (Mac)) did not work'),
          findsOneWidget);
    });

    testWidgets('sound settings the export could not apply are listed',
        (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      fakes.engine.jobs.last
        ..warnings = const [
          'Clean up sound was left out: the FFmpeg on this device has no '
              '"afftdn" filter.'
        ]
        ..finish('/out/movie.mp4');
      await tester.pumpAndSettle();
      expect(find.textContaining('Clean up sound was left out'), findsOneWidget);
    });

    testWidgets('turned off: the processor', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: const {});
      fakes.engine.hardwareEncoder = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use graphics card (faster)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      expect(fakes.engine.lastOptions!.useHardwareEncoder, isFalse);
      fakes.engine.jobs.last.finish('/out/movie.mp4');
      await tester.pumpAndSettle();
      expect(find.textContaining('Made with the processor. Took '),
          findsOneWidget);
    });

    testWidgets('no switch without a graphics card encoder', (tester) async {
      await openEditor(tester, desktop, missingFiles: const {});
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Use graphics card (faster)'), findsNothing);
      expect(
          find.text('Will use: Processor (no graphics card encoder works on '
              'this device)'),
          findsOneWidget);
    });
  });
}
