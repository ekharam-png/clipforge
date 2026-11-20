import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/editor/acts.dart';
import 'package:clipforge/ui/editor/clip_actions.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/leave_flow.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/save_status.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';
import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// What the app answers when the window is closed or Cmd+Q pressed.
Future<AppExitResponse> requestQuit(WidgetTester tester) async {
  final answer = tester.binding.handleRequestAppExit();
  await tester.pumpAndSettle();
  return answer;
}

/// Lets dialogs open and close while a progress bar keeps animating
/// (pumpAndSettle would wait for it forever).
Future<void> busyPump(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Starts an export from the desktop editor and leaves it running.
Future<void> startExport(WidgetTester tester) async {
  await tester.tap(find.text('Export'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
  await tester.pump();
  await tester.pump();
  expect(find.text('Exporting…'), findsOneWidget);
}

void main() {
  setUpAll(loadFonts);

  group('confirmLeave', () {
    late JobTracker jobs;
    late List<String> asked;
    Object? error;
    var flushes = 0;
    setUp(() {
      jobs = JobTracker();
      asked = [];
      error = null;
      flushes = 0;
    });

    Future<bool> run({
      bool stopJobs = false,
      List<SaveFailedChoice?> saveAnswers = const [],
      void Function()? onRetry,
    }) {
      final answers = [...saveAnswers];
      return confirmLeave(
        flush: () async => flushes++,
        saveError: () => error,
        jobs: jobs,
        askStopJobs: (running) async {
          asked.add('jobs ${[for (final j in running) j.kind.name]}');
          return stopJobs;
        },
        askSaveFailed: (e) async {
          asked.add('save');
          final a = answers.removeAt(0);
          if (a == SaveFailedChoice.retry) onRetry?.call();
          return a;
        },
      );
    }

    test('saved and nothing running: leaves without a question', () async {
      expect(await run(), isTrue);
      expect(asked, isEmpty);
      expect(flushes, 1);
    });

    test('an export running: asks; keep working stays and keeps it',
        () async {
      var cancelled = false;
      jobs.start(JobKind.export, cancel: () async => cancelled = true);
      expect(await run(stopJobs: false), isFalse);
      expect(asked, ['jobs [export]']);
      expect(cancelled, isFalse);
      expect(jobs.isEmpty, isFalse);
    });

    test('an export running: quitting cancels it', () async {
      var cancelled = false;
      jobs.start(JobKind.export, cancel: () async => cancelled = true);
      jobs.start(JobKind.analysis);
      expect(await run(stopJobs: true), isTrue);
      expect(asked, ['jobs [export, analysis]']);
      expect(cancelled, isTrue);
      expect(jobs.isEmpty, isTrue);
    });

    test('save failed: stay, quit without saving, or try again', () async {
      error = 'disk full';
      expect(await run(saveAnswers: [SaveFailedChoice.stay]), isFalse);
      expect(await run(saveAnswers: [null]), isFalse); // dialog dismissed
      expect(await run(saveAnswers: [SaveFailedChoice.leaveWithoutSaving]),
          isTrue);
      asked.clear();
      flushes = 0;
      // Try again: still failing asks again; then it works and leaves.
      var tries = 0;
      expect(
          await run(
            saveAnswers: [SaveFailedChoice.retry, SaveFailedChoice.retry],
            onRetry: () {
              if (++tries == 2) error = null;
            },
          ),
          isTrue);
      expect(asked, ['save', 'save']);
      expect(flushes, 3);
    });

    test('jobs are asked about before a failed save', () async {
      error = 'disk full';
      jobs.start(JobKind.export);
      expect(await run(stopJobs: false), isFalse);
      expect(asked, ['jobs [export]']);
    });

    test('a tracker ended after dispose does not complain', () {
      final job = jobs.start(JobKind.analysis);
      jobs.dispose();
      jobs.end(job);
      jobs.end(job);
    });
  });

  group('quitting the app with the editor open', () {
    testWidgets('saved and nothing running: quits without a question',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      final s = sessionOf(tester);
      s.editor.rename('Renamed');
      s.playback.play();
      await tester.pump();
      expect(await requestQuit(tester), AppExitResponse.exit);
      expect(find.byType(AlertDialog), findsNothing);
      // The pending change was written first, and playback stopped.
      expect(saved(fakes).name, 'Renamed');
      expect(s.playback.playing, isFalse);
    });

    testWidgets('save failed: try again / quit without saving / stay',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.store.failSaves = true;
      sessionOf(tester).editor.rename('Renamed');

      var answer = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Your latest changes could not be saved'),
          findsOneWidget);
      expect(find.text('Quit without saving'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(await answer, AppExitResponse.cancel);
      expect(find.byType(EditorScreen), findsOneWidget);

      // Try again once there is room: saved, and the app quits.
      answer = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      fakes.store.failSaves = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(await answer, AppExitResponse.exit);
      expect(saved(fakes).name, 'Renamed');

      // Quit without saving, knowingly.
      fakes.store.failSaves = true;
      sessionOf(tester).editor.rename('Lost');
      answer = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quit without saving'));
      await tester.pumpAndSettle();
      expect(await answer, AppExitResponse.exit);
      expect(saved(fakes).name, 'Renamed');
    });

    testWidgets('an export is running: keep working, or quit and cancel it',
        (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: {});
      await startExport(tester);
      expect(sessionOf(tester).jobs.running.single.kind, JobKind.export);

      var answer = tester.binding.handleRequestAppExit();
      await busyPump(tester);
      expect(find.text('An export is still running'), findsOneWidget);
      await tester.tap(find.text('Keep working'));
      await busyPump(tester);
      expect(await answer, AppExitResponse.cancel);
      expect(fakes.engine.jobs.single.cancelled, isFalse);
      expect(find.text('Exporting…'), findsOneWidget);

      answer = tester.binding.handleRequestAppExit();
      await busyPump(tester);
      await tester.tap(find.text('Quit and cancel it'));
      await busyPump(tester);
      expect(await answer, AppExitResponse.exit);
      expect(fakes.engine.jobs.single.cancelled, isTrue);
      expect(sessionOf(tester).jobs.isEmpty, isTrue);
    });

    testWidgets('a finished export no longer counts', (tester) async {
      final fakes = await openEditor(tester, desktop, missingFiles: {});
      await startExport(tester);
      fakes.engine.jobs.single.finish('/out/movie.mp4');
      await tester.pumpAndSettle();
      expect(sessionOf(tester).jobs.isEmpty, isTrue);
      expect(await requestQuit(tester), AppExitResponse.exit);
    });

    testWidgets('a silence search is running: asks the same way',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.engine.silenceGate = Completer<void>();
      final s = sessionOf(tester);
      unawaited(removeSilences(
          tester.element(find.byType(PreviewView)), s, s.project.clips.first));
      await tester.pump();
      await tester.pump();
      expect(s.jobs.running.single.kind, JobKind.analysis);

      final answer = tester.binding.handleRequestAppExit();
      await busyPump(tester);
      expect(find.text('A sound analysis is still running'), findsOneWidget);
      await tester.tap(find.text('Keep working'));
      await busyPump(tester);
      expect(await answer, AppExitResponse.cancel);

      fakes.engine.silenceGate!.complete();
      await busyPump(tester);
      expect(s.jobs.isEmpty, isTrue);
    });

    testWidgets('back to projects asks about a running job too',
        (tester) async {
      await openEditor(tester, desktop);
      final s = sessionOf(tester);
      var cancelled = false;
      s.jobs.start(JobKind.export, cancel: () async => cancelled = true);
      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      expect(find.text('An export is still running'), findsOneWidget);
      await tester.tap(find.text('Keep working'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(cancelled, isFalse);

      await tester.tap(find.byTooltip('Back to projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave and cancel it'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.byType(EditorScreen), findsNothing);
    });

    testWidgets('closing the silence search ends its job', (tester) async {
      final fakes = await openEditor(tester, desktop);
      fakes.engine.silenceGate = Completer<void>();
      final s = sessionOf(tester);
      unawaited(removeSilences(
          tester.element(find.byType(PreviewView)), s, s.project.clips.first));
      await tester.pump();
      await tester.pump();
      expect(s.jobs.isEmpty, isFalse);
      await tester.tap(find.text('Cancel'));
      await busyPump(tester);
      expect(s.jobs.isEmpty, isTrue);
      fakes.engine.silenceGate!.complete();
      await busyPump(tester);
    });
  });

  group('save status in the top bar', () {
    testWidgets('desktop: Saved, Saving…, Not saved', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final indicator = find.byType(SaveStatusIndicator);
      expect(find.descendant(of: indicator, matching: find.text('Saved')),
          findsOneWidget);

      sessionOf(tester).editor.rename('Renamed');
      await tester.pump();
      expect(find.descendant(of: indicator, matching: find.text('Saving…')),
          findsOneWidget);

      // The autosave writes it a moment later.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.descendant(of: indicator, matching: find.text('Saved')),
          findsOneWidget);
      final status = sessionOf(tester).saveStatus.value;
      expect(status.state, SaveState.saved);
      expect(status.savedAt, isNotNull);
      expect(find.byTooltip(RegExp(r'^All changes saved at ')), findsOneWidget);

      fakes.store.failSaves = true;
      sessionOf(tester).editor.rename('Again');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.descendant(of: indicator, matching: find.text('Not saved')),
          findsOneWidget);
      // Tapping it tries again.
      fakes.store.failSaves = false;
      await tester.tap(indicator);
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(saved(fakes).name, 'Again');
    });

    testWidgets('phone: only an icon, still named for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openEditor(tester, phone);
      final indicator = find.byType(SaveStatusIndicator);
      expect(find.descendant(of: indicator, matching: find.byType(Text)),
          findsNothing);
      expect(find.bySemanticsLabel('Saved'), findsOneWidget);
      semantics.dispose();
    });

    test('words for each state', () {
      const l = DefaultMaterialLocalizations();
      expect(
          SaveStatusIndicator.describe(const SaveStatus(SaveState.saving), l)
              .label,
          'Saving…');
      expect(
          SaveStatusIndicator.describe(
                  SaveStatus(SaveState.saved,
                      savedAt: DateTime(2026, 11, 16, 14, 5)),
                  l)
              .detail,
          'All changes saved at 2:05 PM.');
      expect(
          SaveStatusIndicator.describe(const SaveStatus(SaveState.failed), l)
              .label,
          'Not saved');
    });
  });

  group('players are let go of in order', () {
    Project twoVideos() => sampleProject().copyWith(clips: [
          videoClip('a', '/media/beach.mp4', 0, 6000),
          videoClip('d', '/media/hike.mp4', 1000, 5000),
        ]);

    testWidgets('surfaces leave the tree before any player is disposed',
        (tester) async {
      final fakes = await openEditor(tester, desktop, project: twoVideos());
      final events = fakes.backend.events;
      // Two decks, each with its picture on screen.
      expect(fakes.backend.videoPlayers, hasLength(2));
      expect(events.where((e) => e.endsWith('surface mounted')), isNotEmpty);

      // Leave the editor.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final firstDispose = events.indexWhere((e) => e.endsWith('disposed'));
      final lastSurfaceGone =
          events.lastIndexWhere((e) => e.endsWith('surface gone'));
      expect(firstDispose, greaterThan(-1), reason: '$events');
      expect(lastSurfaceGone, lessThan(firstDispose), reason: '$events');
      for (final p in fakes.backend.videoPlayers) {
        expect(p.disposed, isTrue);
        expect(p.log.where((c) => c == 'dispose'), hasLength(1));
      }
    });

    test('dispose is safe twice, and commands after it do nothing', () {
      final video = FakePlayer();
      final pb = PlaybackController(
        project: sampleProject(),
        video: video,
        createVideoPlayer: FakePlayer.new,
        createAudioPlayer: FakePlayer.new,
        fileExists: (_) => true,
      );
      pb.dispose();
      pb.dispose();
      final before = video.log.length;
      pb.play();
      pb.seek(3000);
      pb.tick(16);
      pb.pause();
      pb.updateProject(sampleProject(name: 'x'));
      pb.recheckFiles();
      expect(video.log.length, before);
      expect(video.log.where((c) => c == 'dispose'), hasLength(1));
    });
  });

  group('menu bar', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    PlatformMenuItem item(List<PlatformMenuItem> menus, String label) {
      PlatformMenuItem? found;
      void walk(List<PlatformMenuItem> items) {
        for (final i in items) {
          if (i is PlatformMenu) walk(i.menus);
          if (i is PlatformMenuItemGroup) walk(i.members);
          if (i.label == label && i is! PlatformMenu) found ??= i;
        }
      }

      walk(menus);
      return found ?? (throw StateError('No menu item $label'));
    }

    test('without an editor the editing items are off', () {
      final menus = buildAppMenus(null);
      expect([for (final m in menus) m.label],
          [
        'ClipForge', 'File', 'Edit', 'Add', 'Clip', 'Part', 'Sound', //
        'Text and speech', 'View', 'Playback', 'Window', 'Help',
      ]);
      // Off, and each says why (1.17).
      for (final label in [
        'Undo', 'Redo', 'Delete', 'Play/Pause', 'Back to projects', 'Export…',
      ]) {
        expect(item(menus, '$label (open a project first)').onSelected, isNull,
            reason: label);
      }
      for (final label in ['New project', 'Open project file…']) {
        expect(item(menus, label).onSelected, isNull, reason: label);
      }
    });

    testWidgets('follows the open editor and runs its actions',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      final s = sessionOf(tester);
      var e = appMenu.editor!;
      expect(e.run(Act.undo), isNull);
      expect(e.run(Act.delete), isNull);
      expect(e.run(Act.playPause), isNotNull);
      // Greyed out, and the label says why.
      expect(item(buildAppMenus(e), 'Undo (nothing to undo)').onSelected,
          isNull);

      // Select a photo and delete it from the menu.
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      e = appMenu.editor!;
      expect(e.run(Act.delete), isNotNull);
      item(buildAppMenus(e), 'Delete').onSelected!();
      await tester.pumpAndSettle();
      expect(s.project.clips.map((c) => c.id), ['a', 'c', 'd']);

      e = appMenu.editor!;
      expect(e.run(Act.undo), isNotNull);
      item(buildAppMenus(e), 'Undo').onSelected!();
      await tester.pumpAndSettle();
      expect(s.project.clips, hasLength(4));
      item(buildAppMenus(appMenu.editor), 'Redo').onSelected!();
      await tester.pumpAndSettle();
      expect(s.project.clips, hasLength(3));

      item(buildAppMenus(appMenu.editor), 'Play/Pause').onSelected!();
      await tester.pump();
      expect(s.playback.playing, isTrue);
      expect(appMenu.editor!.playing, isTrue);
      expect(item(buildAppMenus(appMenu.editor), 'Pause').onSelected,
          isNotNull);
      s.playback.pause();

      // Gone with the editor.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(appMenu.editor, isNull);
      expect(fakes.store.saves, greaterThan(0));
    });

    testWidgets('macOS: Cmd+Z undoes one step, not two', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await openEditor(tester, desktop);
      final s = sessionOf(tester);
      s.editor.removeClip('a');
      s.editor.removeClip('b');
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(s.project.clips.map((c) => c.id), ['b', 'c', 'd']);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('macOS gets a platform menu bar, other systems do not',
        (tester) async {
      await tester.pumpWidget(const AppMenuBar(child: SizedBox()));
      expect(find.byType(PlatformMenuBar), findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.menu, null));
      await tester.pumpWidget(const AppMenuBar(child: SizedBox()));
      expect(find.byType(PlatformMenuBar), findsOneWidget);
      expect(calls.map((c) => c.method), contains('Menu.setMenus'));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
