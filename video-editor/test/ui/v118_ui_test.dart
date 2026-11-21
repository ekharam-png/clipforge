// 1.18 (widget tests), after a real test of 1.17 on a Mac:
//
//  * "Adding file…" with an engine whose probe NEVER answers: Cancel,
//    Esc, File > Back to projects, the note after a few seconds and the
//    45-second limit with its message; the editor is usable afterwards
//    and nothing was added;
//  * the side panel: groups that open and close by themselves and are
//    remembered, the dot on a closed group with a changed setting, Crop
//    never opened from memory, hiding the whole panel;
//  * the project list: the Start row (New video, Podcast, Make a short),
//    the "What's new" card, the tip and "Don't show tips", the line for a
//    Mac that does not run from Applications;
//  * Connect to Claude: the FFmpeg card and "Updating the helper…".

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/claude/helper_install.dart';
import 'package:clipforge/core/install_place.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_common.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/app_settings.dart';
import 'package:clipforge/ui/claude/claude_helper.dart';
import 'package:clipforge/ui/claude/connect_claude.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/tools.dart';
import 'package:clipforge/ui/format.dart';
import 'package:clipforge/ui/home/home_extras.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:clipforge/ui/services.dart' show PickedFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const big = '/Volumes/Disk/Camera 1.mp4';
const small = '/videos/five minutes.mp4';
const video = MediaInfo(
    durationMs: 290000, width: 1920, height: 1080, hasVideo: true, hasAudio: true);

/// The busy window is up (its spinner never settles: pump by hand).
Future<void> startAdding(WidgetTester tester, Fakes fakes,
    {List<String> files = const [big]}) async {
  fakes.files.media = [for (final f in files) PickedFile(f, fileName(f))];
  fakes.engine.neverAnswers.add(big);
  fakes.engine.infos[small] = video;
  await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// The probe that was left alone still has its own time limit running:
/// let it pass (nothing may happen then).
Future<void> flush(WidgetTester tester) async {
  await tester.pump(kProbeTimeout + const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.textContaining('could not be read'), findsNothing);
}

MenuNode menuItem(List<MenuNode> nodes, String id) {
  MenuNode? found;
  void walk(List<MenuNode> list) {
    for (final n in list) {
      if (n.id == id) found ??= n;
      final c = n.children;
      if (c != null) walk(c);
    }
  }

  walk(nodes);
  return found ?? (throw StateError('no menu item $id'));
}

class _Claude extends ClaudeHelperService {
  _Claude(this.answer)
      : super(
            build: const BuildInfo(version: '1.18.0', buildNumber: '140'),
            os: 'macos',
            loadBundle: () async => null);
  ClaudeHelperState answer;
  @override
  Future<void> installAtStart() async {}
  @override
  Future<ClaudeHelperState> state() async => answer;
}

void main() {
  setUpAll(loadFonts);

  group('a probe that never answers', () {
    testWidgets('Cancel leaves "Adding file…"; nothing is added; the editor '
        'works', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final before = sessionOf(tester).project.clips.length;
      await startAdding(tester, fakes, files: [big, small]);
      expect(find.text('Adding 2 files…'), findsOneWidget);
      expect(find.byKey(const ValueKey('busy-cancel')), findsOneWidget);
      expect(fakes.engine.probes, 1);

      await tester.tap(find.byKey(const ValueKey('busy-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Adding 2 files…'), findsNothing);
      expect(sessionOf(tester).project.clips, hasLength(before));
      // The second file is not read after the cancel, and no message
      // about files that "could not be read" appears.
      expect(fakes.engine.probes, 1);
      expect(find.textContaining('could not be read'), findsNothing);

      // The editor answers: select a clip, split it, undo.
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(sessionOf(tester).selectedClip?.id, 'a');
      expect(tester.takeException(), isNull);
      await flush(tester);
    });

    testWidgets('Esc does the same', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final before = sessionOf(tester).project.clips.length;
      await startAdding(tester, fakes);
      expect(find.text('Adding file…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Adding file…'), findsNothing);
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(sessionOf(tester).project.clips, hasLength(before));
      await flush(tester);
    });

    testWidgets('after a few seconds it says so; after 45 it stops by '
        'itself with what to try', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final before = sessionOf(tester).project.clips.length;
      await startAdding(tester, fakes);
      expect(find.byKey(const ValueKey('busy-slow-note')), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('busy-slow-note')), findsOneWidget);
      expect(find.textContaining('taking longer than usual'), findsOneWidget);

      await tester.pump(kProbeTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Adding file…'), findsNothing);
      expect(
          find.textContaining('Camera 1.mp4 could not be read within '
              '45 seconds'),
          findsOneWidget);
      expect(find.textContaining('copy it to this computer first'),
          findsOneWidget);
      expect(find.textContaining('/Volumes/'), findsNothing,
          reason: 'the name, not the path');
      expect(sessionOf(tester).project.clips, hasLength(before));
    });

    testWidgets('a file that answers next to one that does not: the limit '
        'ends the wait, the good file is added', (tester) async {
      final fakes = await openEditor(tester, desktop);
      await startAdding(tester, fakes, files: [big, small]);
      await tester.pump(kProbeTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be read within'), findsOneWidget);
      expect(sessionOf(tester).project.clips.map((c) => c.path),
          contains(small));
    });

    testWidgets('File > Back to projects cancels it and goes back',
        (tester) async {
      useScreen(tester, desktop);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fakes = Fakes(projects: [sampleProject()]);
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summer trip'));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      await startAdding(tester, fakes);
      expect(find.text('Adding file…'), findsOneWidget);

      // The Mac's menu bar is above the window and stays usable.
      final back = menuItem(buildMenuTree(appMenu.editor), 'back-to-projects');
      expect(back.onSelected, isNotNull);
      back.onSelected!();
      await tester.pumpAndSettle();
      expect(find.text('Adding file…'), findsNothing);
      expect(find.byType(EditorScreen), findsNothing);
      expect(find.text('Summer trip'), findsOneWidget);
      await flush(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a sound file whose probe never answers (phone)',
        (tester) async {
      final fakes = await openEditor(tester, phone);
      fakes.files.audio = [const PickedFile(big, 'Camera 1.mp4')];
      fakes.engine.neverAnswers.add(big);
      await tester.tap(find.byKey(const ValueKey('tool-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-addVoice')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Reading the sound…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('busy-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Reading the sound…'), findsNothing);
      expect(sessionOf(tester).project.audio, hasLength(1));
      expect(tester.takeException(), isNull);
      await flush(tester);
    });
  });

  group('the side panel', () {
    testWidgets('groups open and close by themselves and are remembered',
        (tester) async {
      final fakes = await openEditor(tester, desktop);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      // The most used are open, the rest closed.
      expect(sectionIsOpen(tester, 'Speed'), isTrue);
      expect(sectionIsOpen(tester, 'Sound'), isTrue);
      expect(sectionIsOpen(tester, 'Look'), isFalse);
      expect(sectionIsOpen(tester, 'Transition and fades'), isFalse);
      expect(find.text('Saturation'), findsNothing);

      await openSection(tester, 'Look');
      expect(find.text('Saturation'), findsOneWidget);
      // Opening one does not close another.
      expect(sectionIsOpen(tester, 'Speed'), isTrue);
      await closeSection(tester, 'Speed');
      expect(sectionIsOpen(tester, 'Speed'), isFalse);
      expect(fakes.prefs.texts[kPanelSectionsText],
          allOf(contains('clip.look=1'), contains('clip.speed=0')));

      // Another clip, and the editor opened again: as it was left.
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      expect(sectionIsOpen(tester, 'Look'), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
      await tester.pumpAndSettle();
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(sectionIsOpen(tester, 'Look'), isTrue);
      expect(sectionIsOpen(tester, 'Speed'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a closed group with a changed setting shows a dot',
        (tester) async {
      final base = sampleProject();
      await openEditor(tester, desktop,
          project: base.copyWith(clips: [
            base.clips.first.copyWith(brightness: 0.3),
            ...base.clips.skip(1),
          ]));
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-dot-clip.look')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-dot-clip.transition')),
          findsNothing);
      // Open: the settings themselves show it, no dot.
      await openSection(tester, 'Look');
      expect(find.byKey(const ValueKey('section-dot-clip.look')), findsNothing);
      // A clip with nothing changed: no dot.
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      await closeSection(tester, 'Look');
      expect(find.byKey(const ValueKey('section-dot-clip.look')), findsNothing);
    });

    testWidgets('Crop is never opened from memory', (tester) async {
      final fakes = await openEditor(tester, desktop);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      final s = sessionOf(tester);
      await openSection(tester, 'Crop');
      expect(s.cropTarget.value, 'a');
      expect(fakes.prefs.texts[kPanelSectionsText] ?? '',
          isNot(contains('clip.crop')));
      // Another clip: back to closed, the preview is not in crop mode.
      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(s.openTool.value, ClipTool.crop,
          reason: 'still asked for until its heading closes it');
      await tester.ensureVisible(sectionHeading('Crop').first);
      await tester.pumpAndSettle();
      await tester.tap(sectionHeading('Crop').first);
      await tester.pumpAndSettle();
      expect(s.cropTarget.value, isNull);
      expect(sectionIsOpen(tester, 'Crop'), isFalse);
    });

    testWidgets('a title and a sound have groups too, also on a phone',
        (tester) async {
      await openEditor(tester, phone);
      await tester.tap(block('title-t1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Text size'), findsOneWidget);
      expect(find.text('Text colour'), findsNothing);
      await openSection(tester, 'Font and colour');
      expect(find.text('Text colour'), findsOneWidget);
      await openSection(tester, 'When it shows');
      expect(find.text('Start at playhead'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hide and show the whole panel: the button, the View menu '
        'and Ctrl+Shift+P', (tester) async {
      useScreen(tester, const Size(1400, 900));
      // The menu bar inside the window (Windows, Linux) has the keys.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fakes = Fakes(projects: [sampleProject()]);
      await tester.pumpWidget(
          fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      final wide = tester.getSize(find.byType(PreviewView)).width;

      await tester.tap(find.byKey(const ValueKey('side-panel-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsNothing);
      expect(fakes.prefs.flags, contains(kSidePanelOffFlag));
      expect(
          tester.getSize(find.byType(PreviewView)).width,
          greaterThan(wide + 250),
          reason: 'the preview gets the width');
      // The menu shows the switch off.
      expect(
          menuItem(buildMenuTree(appMenu.editor), 'side-panel').checked, isFalse);

      // The key brings it back.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(fakes.prefs.flags, isNot(contains(kSidePanelOffFlag)));
      // And the menu item hides it again.
      menuItem(buildMenuTree(appMenu.editor), 'side-panel').onSelected!();
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsNothing);
      // The button in the slim strip.
      await tester.tap(find.byKey(const ValueKey('side-panel-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('shortcut words', () {
    test('Ctrl on Windows and Linux, Cmd on a Mac', () {
      expect(
          shortcutText('Previous speech start (Ctrl+Left)',
              platform: TargetPlatform.macOS),
          'Previous speech start (Cmd+Left)');
      expect(
          shortcutText('Previous speech start (Ctrl+Left)',
              platform: TargetPlatform.windows),
          'Previous speech start (Ctrl+Left)');
    });

    test('a project file keeps its whole ending', () {
      const offered = 'Holiday.clipforge.zip';
      expect(savePathFor('/d/My trip.zip', offered), '/d/My trip.clipforge.zip');
      expect(savePathFor('/d/My trip', offered), '/d/My trip.clipforge.zip');
      expect(savePathFor('/d/My trip.clipforge.zip', offered),
          '/d/My trip.clipforge.zip');
      expect(savePathFor('/d/My trip.CLIPFORGE.ZIP', offered),
          '/d/My trip.CLIPFORGE.ZIP');
      expect(savePathFor('/d/film', 'film.mp4'), '/d/film.mp4');
      expect(savePathFor('/d/film.mp4', 'film.mp4'), '/d/film.mp4');
      expect(savePathFor('/d/film.mov', 'film.mp4'), '/d/film.mov.mp4');
    });

    test('a nearly 16:9 size gets the standard width', () {
      expect(Project.snapToWide(1278, 720), (width: 1280, height: 720));
      expect(Project.snapToWide(720, 1278), (width: 720, height: 1280));
      expect(Project.snapToWide(1080, 1918), (width: 1080, height: 1920));
      expect(Project.snapToWide(1280, 720), (width: 1280, height: 720));
      // Not close to 16:9, or not a standard height: as it is.
      expect(Project.snapToWide(960, 720), (width: 960, height: 720));
      expect(Project.snapToWide(1264, 720), (width: 1264, height: 720));
      expect(Project.snapToWide(1136, 640), (width: 1136, height: 640));
    });
  });

  group('the project list', () {
    Widget home(Fakes fakes, {String notes = '', InstallAdvice? advice}) {
      fakes
        ..changelog = notes
        ..installAdvice = advice;
      return fakes.app(const HomeScreen());
    }

    for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
      testWidgets('Start row, bigger cards and a tip on a $label screen',
          (tester) async {
        useScreen(tester, size);
        final fakes = Fakes(projects: [
          sampleProject(),
          sampleProject(id: 'p2', name: 'Garden'),
        ]);
        await tester.pumpWidget(home(fakes));
        await tester.pumpAndSettle();
        for (final t in ['New video', 'Podcast', 'Make a short']) {
          expect(find.text(t), findsOneWidget);
        }
        // Each card: its name, its length (on the picture) and when it
        // was last edited.
        expect(find.text('Summer trip'), findsOneWidget);
        expect(find.textContaining('Edited '), findsNWidgets(2));
        expect(find.text('0:18'), findsNWidgets(2));
        final card = tester.getSize(find
            .ancestor(of: find.text('Summer trip'), matching: find.byType(InkWell))
            .first);
        expect(card.height, size == phone ? 104 : 236);
        if (size == phone) {
          expect(card.width, size.width - 32, reason: 'one column');
        }
        // The tip of the day, from the compiled-in list.
        final tip = tipFor(DateTime(2026, 11, 21));
        expect(kTips, contains(tip));
        expect(find.text('Tip: $tip'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        await fakes.screenshot(tester, 'home_118_$label');

        await tester.tap(find.byKey(const ValueKey('home-tip-hide')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-tip')), findsNothing);
        expect(fakes.prefs.flags, contains(kTipsOffFlag));
      });
    }

    testWidgets('no projects yet: the same Start row with a welcome',
        (tester) async {
      useScreen(tester, phone);
      final fakes = Fakes();
      await tester.pumpWidget(home(fakes));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to ClipForge'), findsOneWidget);
      expect(find.text('New video'), findsOneWidget);
      expect(find.text('Podcast'), findsOneWidget);
      expect(find.text('Open project file'), findsOneWidget);
      // Make a short needs a video to make it from, and says so.
      await tester.tap(find.byKey(const ValueKey('start-short')));
      await tester.pump();
      expect(find.textContaining('A short is made from a video you already have'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Podcast: the video, then the sound files', (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()]);
      fakes.files.media = [const PickedFile(small, 'five minutes.mp4')];
      fakes.engine.infos[small] = video;
      await tester.pumpWidget(home(fakes));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-podcast')));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('podcast-start')), findsOneWidget);
      expect(find.textContaining('one for each speaker'), findsOneWidget);
      final made = fakes.store.projects.values
          .firstWhere((p) => p.name.startsWith('Podcast '));
      expect(made.clips, isEmpty);

      await tester.tap(find.byKey(const ValueKey('podcast-choose-video')));
      await tester.pumpAndSettle();
      expect(sessionOf(tester).project.clips.single.path, small);
      // Step 2 is offered; "Later" leaves the video in.
      expect(find.byKey(const ValueKey('podcast-voices')), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('podcast-voices')), findsNothing);
      expect(sessionOf(tester).project.clips, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Make a short: choose the video, its editor opens with the '
        'short window', (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [
        sampleProject(),
        sampleProject(id: 'p2', name: 'Garden'),
      ]);
      await tester.pumpWidget(home(fakes));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-short')));
      await tester.pumpAndSettle();
      expect(find.text('Make a short from which video?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('short-from-p2')));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(sessionOf(tester).project.id, 'p2');
      expect(find.textContaining('short'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets("What's new after an update: lines from the release notes, "
        'the link, closed for good', (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()]);
      final version = fakes.buildInfo.version;
      fakes.prefs.texts[kLastRunVersionText] = '1.17.0';
      fakes.prefs.texts.remove(kUpdatedLineSeenText);
      final notes = '# What is new\n\n## $version – 21 November 2026\n\n'
          'An intro line.\n\n'
          '- Adding a file always ends. There is a **Cancel** button now.\n'
          '  - A detail that is not a headline.\n'
          '- The side panel folds: every group opens and closes.\n'
          '- A Start row on the project list.\n'
          '- A fourth point that is not shown.\n\n'
          '## 0.9.0 – 1 January 2026\n\n- Something old.\n';
      await tester.pumpWidget(home(fakes, notes: notes));
      await tester.pumpAndSettle();
      expect(find.text("What's new in $version"), findsOneWidget);
      expect(find.text('Adding a file always ends'), findsOneWidget);
      expect(find.text('The side panel folds'), findsOneWidget);
      expect(find.text('A Start row on the project list'), findsOneWidget);
      expect(find.textContaining('fourth point'), findsNothing);
      expect(find.textContaining('Something old'), findsNothing);
      expect(find.text('Updated to $version'), findsOneWidget);
      await fakes.screenshot(tester, 'home_118_whats_new');

      await tester.ensureVisible(find.byKey(const ValueKey('updated-line-close')));
      await tester.tap(find.byKey(const ValueKey('updated-line-close')));
      await tester.pumpAndSettle();
      expect(find.text("What's new in $version"), findsNothing);
      expect(fakes.prefs.texts[kUpdatedLineSeenText], version);
    });

    test('highlights: the first sentence of the first three points', () {
      const notes = '## 1.18.0 – x\n\nIntro.\n\n'
          '- **Bold label** does a thing. More words.\n'
          '- Short\n'
          '- A point that introduces a list:\n  - child\n'
          '- Fourth.\n';
      expect(changelogHighlights(notes, '1.18.0'), [
        'Bold label does a thing',
        'Short',
        'A point that introduces a list',
      ]);
      expect(changelogHighlights(notes, '9.9.9'), isEmpty);
      // The tips: one a day, all of them come round.
      final seen = {
        for (var d = 0; d < kTips.length; d++)
          tipFor(DateTime(2026, 11, 21).add(Duration(days: d))),
      };
      expect(seen, hasLength(kTips.length));
      expect(tipFor(DateTime(2026, 11, 21, 8)), tipFor(DateTime(2026, 11, 21, 23)));
      for (final t in kTips) {
        expect(t.length, lessThan(170), reason: t);
      }
    });

    testWidgets('a Mac that runs from the download: one line, Show me how, '
        'closed for good', (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()]);
      const advice = InstallAdvice(
          translocated: true,
          bundlePath: '/private/var/folders/x/AppTranslocation/y/d/ClipForge.app',
          otherPath: '/Applications/ClipForge.app',
          otherVersion: '1.14.1',
          otherIsOlder: true);
      await tester.pumpWidget(home(fakes, advice: advice));
      await tester.pumpAndSettle();
      expect(
          find.text('Move ClipForge to the Applications folder so it can '
              'update itself. An older ClipForge (1.14.1) is in the '
              'Applications folder: replace it with this one.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('move-to-applications-how')));
      await tester.pumpAndSettle();
      expect(find.text('Move ClipForge to the Applications folder (Mac)'),
          findsWidgets);
      expect(find.textContaining('It never moves anything by itself'),
          findsOneWidget);
      Navigator.of(tester.element(find.textContaining(
              'It never moves anything by itself')))
          .pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move-to-applications-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('move-to-applications')), findsNothing);
      expect(fakes.prefs.flags, contains(kMoveToApplicationsSeenFlag));

      // The next start: not shown again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(home(fakes, advice: advice));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('move-to-applications')), findsNothing);
    });

    testWidgets('Settings has the tips switch next to the suggestions',
        (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()]);
      fakes.prefs.flags.add(kTipsOffFlag);
      await tester.pumpWidget(home(fakes));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-tip')), findsNothing);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)));
      await container.read(appSettingsProvider).setTips(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-tip')), findsOneWidget);
      expect(fakes.prefs.flags, isNot(contains(kTipsOffFlag)));
    });
  });

  group('Connect to Claude', () {
    ClaudeHelperState state() => const ClaudeHelperState(
          supported: true,
          stableDir: '/Users/sam/Library/Application Support/ClipForge/claude',
          launcherPath:
              '/Users/sam/Library/Application Support/ClipForge/claude/clipforge-mcp',
          installed: true,
          hasBundle: true,
          current: HelperCurrent(
              version: '1.18.0',
              build: 140,
              path: '/Users/sam/Library/Application Support/ClipForge/claude/'
                  'versions/1.18.0-b140-ab12cd34/clipforge-mcp'),
        );

    testWidgets('no FFmpeg for the helper: said before anything fails, with '
        'the command to copy', (tester) async {
      useScreen(tester, desktop);
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
      final fakes = Fakes()
        ..claude = _Claude(state())
        ..helperFfmpeg = false;
      await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('claude-needs-ffmpeg')), findsOneWidget);
      expect(find.textContaining('Claude control needs the free program FFmpeg'),
          findsOneWidget);
      expect(find.textContaining('The ClipForge app itself works without it'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('claude-ffmpeg-copy')));
      await tester.pump();
      expect(copied.single, anyOf('brew install ffmpeg', 'winget install ffmpeg',
          'sudo apt install ffmpeg'));
      await fakes.screenshot(tester, 'connect_claude_ffmpeg');

      // Installed meanwhile: the card goes.
      fakes.helperFfmpeg = true;
      await tester.tap(find.byKey(const ValueKey('claude-ffmpeg-recheck')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('claude-needs-ffmpeg')), findsNothing);
      expect(find.text('The Claude helper is installed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Updating the helper…" while it is put in place',
        (tester) async {
      useScreen(tester, desktop);
      final claude = _Claude(state());
      final fakes = Fakes()..claude = claude;
      await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version 1.18.0 (build 140)'), findsOneWidget);
      claude.refreshing.value = true;
      await tester.pump();
      expect(find.text('Updating the helper…'), findsOneWidget);
      expect(find.textContaining('Version 1.18.0'), findsNothing,
          reason: 'not the version that is being replaced');
      claude.refreshing.value = false;
      await tester.pumpAndSettle();
      expect(find.text('The Claude helper is installed'), findsOneWidget);
    });
  });
}
