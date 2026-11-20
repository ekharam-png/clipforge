// 1.15: the phone layout at 360 x 760 (bottom bar, the Add sheet, More
// grouped like the computer's menus, the one project menu, touch targets),
// the computer-style layout from 840 dp (tablets, phones held sideways),
// and the timeline's context menu: a right-click on a computer, a long
// press on a phone, the same list.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/editor/editor_actions.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/tools.dart';
import 'package:clipforge/ui/settings/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const small = Size(360, 760);
const tablet = Size(900, 600);

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// The labels of the bottom tool bar, left to right.
List<String> toolBar(WidgetTester tester) {
  final bar = find.byType(ToolBar);
  final texts = find.descendant(of: bar, matching: find.byType(Text));
  final found = [
    for (final e in texts.evaluate())
      (tester.getTopLeft(find.byWidget(e.widget)).dx, (e.widget as Text).data!),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// Every button of the bottom bar is at least 48 x 48.
void expectTouchTargets(WidgetTester tester) {
  final buttons = find.descendant(
      of: find.byType(ToolBar), matching: find.byType(InkWell));
  expect(buttons, findsWidgets);
  for (final e in buttons.evaluate()) {
    expect(e.size!.width, greaterThanOrEqualTo(48), reason: '$e');
    expect(e.size!.height, greaterThanOrEqualTo(48), reason: '$e');
  }
}

void main() {
  setUpAll(loadFonts);

  group('phone, 360 x 760', () {
    testWidgets('nothing selected: Add, Text, Split, More; the top bar has '
        'Back, the name, Undo, Redo, Export and ONE menu', (tester) async {
      final fakes = await openEditor(tester, small);
      expect(toolBar(tester), ['Add', 'Text', 'Split', 'More']);
      expectTouchTargets(tester);
      // No scrolling needed, and so no "more to the right" mark.
      expect(find.byKey(const ValueKey('tool-bar-more-to-the-right')),
          findsNothing);

      final top = find.byType(AppBar);
      Finder inTop(Finder f) => find.descendant(of: top, matching: f);
      expect(inTop(find.byTooltip('Back to projects')), findsOneWidget);
      expect(inTop(find.text('Summer trip')), findsOneWidget);
      expect(inTop(find.byTooltip('Undo')), findsOneWidget);
      expect(inTop(find.byTooltip('Redo')), findsOneWidget);
      expect(inTop(find.text('Export')), findsOneWidget);
      expect(inTop(find.byKey(const ValueKey('project-menu'))), findsOneWidget);
      // What phones had there before is in the menu now.
      expect(inTop(find.byTooltip('Help')), findsNothing);
      expect(inTop(find.text('Shape')), findsNothing);
      expect(inTop(find.byKey(const ValueKey('history-button'))), findsNothing);
      for (final tip in ['Undo', 'Redo', 'Project menu', 'Back to projects']) {
        // The button with its touch area (the drawn circle is smaller).
        final size = tester.getSize(find
            .ancestor(
                of: inTop(find.byTooltip(tip)),
                matching: find.bySubtype<ButtonStyleButton>())
            .first);
        expect(size.width, greaterThanOrEqualTo(48), reason: tip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tip);
      }
      expect(tester.getSize(inTop(find.text('Summer trip'))).width,
          greaterThan(30),
          reason: 'the name keeps some room');
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'phone115_editor');
    });

    testWidgets('Add: ONE sheet with everything addable, icons and a line '
        'each', (tester) async {
      final fakes = await openEditor(tester, small);
      await tester.tap(find.byKey(const ValueKey('tool-add')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('add-sheet'));
      expect(sheet, findsOneWidget);
      final tiles = tester
          .widgetList<ActionTile>(
              find.descendant(of: sheet, matching: find.byType(ActionTile)))
          .toList();
      expect([for (final t in tiles) t.entry.act], kAddActs);
      for (final label in [
        'Videos or photos', 'Music or sound', 'Voice recording', 'Title', //
        'Caption', 'Overlay (picture-in-picture)', 'Good moment marker',
      ]) {
        expect(find.descendant(of: sheet, matching: find.text(label)),
            findsOneWidget,
            reason: label);
      }
      for (final t in tiles) {
        expect(actHint(t.entry.act), isNotNull, reason: '${t.entry.act}');
      }
      for (final e in find
          .descendant(of: sheet, matching: find.byType(ListTile))
          .evaluate()) {
        expect(e.size!.height, greaterThanOrEqualTo(48));
      }
      await fakes.screenshot(tester, 'phone115_add_sheet');

      // It adds: a title, which opens its settings.
      await tester.tap(find.descendant(of: sheet, matching: find.text('Title')));
      await tester.pumpAndSettle();
      expect(sessionOf(tester).project.titles, hasLength(2));
      expect(find.text('Edit title'), findsOneWidget);
    });

    testWidgets('a clip selected: its tools and More, grouped Clip / Edit / '
        'Sound / Text, with Trim start / end to here', (tester) async {
      final fakes = await openEditor(tester, small);
      final s = sessionOf(tester);
      s.selectClipAndShow('a');
      await tester.pumpAndSettle();
      expect(toolBar(tester),
          ['Done', 'Split', 'Speed', 'Look', 'Sound', 'More', 'Delete']);
      expectTouchTargets(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('tool-more')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('more-sheet'));
      expect(
          tester
              .widgetList<SheetHeading>(find.descendant(
                  of: sheet, matching: find.byType(SheetHeading)))
              .map((h) => h.text),
          ['Clip', 'Edit', 'Sound', 'Text']);
      expect(find.text('Trim start to here'), findsOneWidget);
      expect(find.text('Trim end to here'), findsOneWidget);
      expect(find.text('Crop and position'), findsOneWidget);
      expect(find.text('Transition and fades'), findsOneWidget);
      // What cannot be done says why instead of hiding.
      expect(find.text('Not now: it is already the first clip'), findsOneWidget);
      expect(find.text('Not now: copy settings first'), findsOneWidget);
      await fakes.screenshot(tester, 'phone115_more_clip');

      // Trim start to here: the I key's action.
      s.playback.seek(2000);
      await tester.pumpAndSettle();
      final before = s.project.clips.first.durationMs;
      await tester.ensureVisible(find.byKey(const ValueKey('more-trim-start')));
      await tester.tap(find.byKey(const ValueKey('more-trim-start')));
      await tester.pumpAndSettle();
      expect(s.project.clips.first.durationMs, before - 2000);
      expect(find.byKey(const ValueKey('more-sheet')), findsNothing);
    });

    testWidgets('More with nothing selected; a sound selected: the Sound '
        'group', (tester) async {
      await openEditor(tester, small);
      final s = sessionOf(tester);
      await tester.tap(find.byKey(const ValueKey('tool-more')));
      await tester.pumpAndSettle();
      List<String> headings() => tester
          .widgetList<SheetHeading>(find.byType(SheetHeading))
          .map((h) => h.text)
          .toList();
      expect(headings(), ['Clip', 'Sound', 'Text', 'Edit']);
      expect(find.text('Lower music under speech'), findsOneWidget);
      // Settings are not mixed into More any longer.
      expect(find.text('Show sound waves'), findsNothing);
      expect(find.text('Smooth preview'), findsNothing);
      expect(find.text('Fade in and out'), findsNothing);
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      s.select(ItemKind.audio, 'm1');
      await tester.pumpAndSettle();
      expect(toolBar(tester), ['Done', 'Edit', 'Fit', 'More', 'Delete']);
      await tester.tap(find.byKey(const ValueKey('tool-more')));
      await tester.pumpAndSettle();
      expect(headings(), ['Sound', 'Text', 'Edit']);
      for (final label in [
        'Fit music to video', 'Line up voice with video', 'Add sound track', //
        'Lower music under speech', 'Copy music credits',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the project menu: Shape and size, Fade in and out, '
        'Publishing notes, Text, History, Markers, Settings', (tester) async {
      final fakes = await openEditor(tester, small);
      final s = sessionOf(tester);
      Future<void> openMenu() async {
        await tester.tap(find.byKey(const ValueKey('project-menu')));
        await tester.pumpAndSettle();
      }

      await openMenu();
      final items = tester
          .widgetList<PopupMenuItem<Object>>(find.byType(PopupMenuItem<Object>))
          .toList();
      expect([
        for (final i in items)
          ((i.child as Row).children.last as Text).data,
      ], [
        'Shape and size', 'Fade in and out', 'Publishing notes', 'Text', //
        'History', 'Markers', 'Settings', 'Help', 'Send feedback',
      ]);
      for (final i in items) {
        expect(i.height, greaterThanOrEqualTo(48));
      }
      await fakes.screenshot(tester, 'phone115_project_menu');

      await tester.tap(find.text('Shape and size'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shape-sheet')), findsOneWidget);
      expect(find.text('Same as the first clip'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shape-portrait9x16')));
      await tester.pumpAndSettle();
      expect(s.project.aspect, CanvasAspect.portrait9x16);
      await tester.ensureVisible(find.byKey(const ValueKey('video-size-p720')));
      await tester.tap(find.byKey(const ValueKey('video-size-p720')));
      await tester.pumpAndSettle();
      expect(s.project.videoSize, VideoSize.p720);
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      await openMenu();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-sheet')), findsOneWidget);
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      await openMenu();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsBody), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
    });

    testWidgets('too many buttons for the width: the bar scrolls and says so',
        (tester) async {
      // A clip whose file is missing gets "Find file" as well: 8 buttons.
      await openEditor(tester, const Size(320, 700));
      final s = sessionOf(tester);
      s.selectClipAndShow('c');
      await tester.pumpAndSettle();
      expect(toolBar(tester), contains('Find file'));
      expect(find.byKey(const ValueKey('tool-bar-more-to-the-right')),
          findsOneWidget);
      expectTouchTargets(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet and landscape (840 dp and wider)', () {
    testWidgets('the computer-style layout: side panel, no bottom bar',
        (tester) async {
      final fakes = await openEditor(tester, tablet);
      expect(kWideLayoutWidth, 840);
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(find.byType(ToolBar), findsNothing);
      expect(find.byKey(const ValueKey('project-menu')), findsNothing);
      expect(find.byTooltip('Help'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'tablet115_editor');
    });

    testWidgets('just under 840: the phone layout', (tester) async {
      await openEditor(tester, const Size(820, 600));
      expect(find.byType(InspectorPanel), findsNothing);
      expect(find.byType(ToolBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the timeline context menu', () {
    test('the same list for a right-click and a long press', () {
      // (The list is a function of what was pressed, not of how.)
      expect(const TimelineTarget.item(ItemKind.clip, 'a').kind, ItemKind.clip);
    });

    testWidgets('computer: right-click a clip, a sound, a title, an empty '
        'place', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final s = sessionOf(tester);
      Future<void> rightClick(Finder f) async {
        await tester.tap(f, buttons: kSecondaryButton);
        await tester.pumpAndSettle();
      }

      List<Act> shown() => [
            for (final i in tester.widgetList<PopupMenuItem<Object>>(
                find.byType(PopupMenuItem<Object>)))
              if (i.value is Act) i.value! as Act,
          ];

      // A clip: selected, and its actions.
      await rightClick(block('clip-b'));
      expect(s.selectedClip?.id, 'b');
      expect(shown(), [
        for (final a in contextActs(
            const TimelineTarget.item(ItemKind.clip, 'b'), s))
          ?a,
      ]);
      expect(shown().first, Act.split);
      expect(shown().last, Act.delete);
      // Greyed out with the reason (a photo has no silences).
      expect(
          find.text('Remove silences… (select a video clip with sound)'),
          findsOneWidget);
      await fakes.screenshot(tester, 'context_menu_clip_desktop');
      await tester.tap(find.byKey(const ValueKey('context-duplicate')));
      await tester.pumpAndSettle();
      expect(s.project.clips, hasLength(5));

      // A sound.
      await rightClick(block('audio-m1'));
      expect(s.selectedAudio?.id, 'm1');
      expect(shown(), [
        Act.fitMusic, Act.lineUpVoice, Act.putSoundBack, Act.lowerMusic, //
        Act.copyCredits, Act.delete,
      ]);
      await tester.tap(find.byKey(const ValueKey('context-lowerMusic')));
      await tester.pumpAndSettle();
      expect(s.project.soundTracks.every((t) => t.duck), isTrue);

      // A title.
      await rightClick(block('title-t1'));
      expect(s.selectedTitle?.id, 't1');
      expect(shown(), [Act.duplicate, Act.textWindow, Act.delete]);
      await tester.tap(find.byKey(const ValueKey('context-delete')));
      await tester.pumpAndSettle();
      expect(s.project.titles, isEmpty);
    });

    testWidgets('computer: right-click a marker', (tester) async {
      final p = sampleProject();
      await openEditor(tester, desktop,
          project: p.copyWith(markers: const [Marker(id: 'k1', ms: 3000)]));
      final s = sessionOf(tester);
      await tester.tap(find.byKey(const ValueKey('marker-k1')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(s.playback.positionMs, 3000);
      expect(find.byKey(const ValueKey('context-shortFromHere')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-goodMoments')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('context-remove-marker')));
      await tester.pumpAndSettle();
      expect(s.project.markers, isEmpty);
    });

    testWidgets('phone: holding a title, a sound or a clip opens the same '
        'list as a sheet', (tester) async {
      final fakes = await openEditor(tester, small);
      final s = sessionOf(tester);
      List<Act> shown() => [
            for (final t in tester.widgetList<ActionTile>(find.descendant(
                of: find.byKey(const ValueKey('context-sheet')),
                matching: find.byType(ActionTile))))
              t.entry.act,
          ];

      await tester.longPress(block('title-t1'));
      await tester.pumpAndSettle();
      expect(s.selectedTitle?.id, 't1');
      expect(shown(), [
        for (final a in contextActs(
            const TimelineTarget.item(ItemKind.title, 't1'), s))
          ?a,
      ]);
      expect(shown(), contains(Act.editItem));
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      await tester.longPressAt(
          tester.getTopLeft(block('audio-m1')) + const Offset(16, 10));
      await tester.pumpAndSettle();
      expect(s.selectedAudio?.id, 'm1');
      expect(shown(), contains(Act.fitMusic));
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();

      // A clip: holding without moving opens the list (holding and
      // dragging still moves the clip).
      await tester.longPress(block('clip-a'));
      await tester.pumpAndSettle();
      expect(s.selectedClip?.id, 'a');
      expect(shown(), [
        for (final a
            in contextActs(const TimelineTarget.item(ItemKind.clip, 'a'), s))
          ?a,
      ]);
      expect(find.text('Trim start to here'), findsOneWidget);
      await fakes.screenshot(tester, 'context_sheet_clip_phone');
      await tester.ensureVisible(find.byKey(const ValueKey('context-delete')));
      await tester.tap(find.byKey(const ValueKey('context-delete')));
      await tester.pumpAndSettle();
      expect(clipIds(s.project), ['b', 'c', 'd']);
    });

    testWidgets('an empty place on the timeline: what can be added there',
        (tester) async {
      await openEditor(tester, desktop);
      final s = sessionOf(tester);
      final origin = timelineOrigin(tester);
      // Far to the right of everything, on the main track's row.
      await tester.tapAt(origin + const Offset(28 + 18.5 * 60.0, 60),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(s.selection.value, isNull);
      expect(find.byKey(const ValueKey('context-addMedia')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-addTitle')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-markMoment')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('context-markMoment')));
      await tester.pumpAndSettle();
      expect(s.project.markers, hasLength(1));
    });
  });
}
