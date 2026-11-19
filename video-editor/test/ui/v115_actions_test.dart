// 1.15: ONE source for "can this be done, and why not" (EditorActions,
// lib/ui/editor/editor_actions.dart), used by the menu bar, the side
// panel, the phone's bars and the timeline's context menu; and ONE truth
// for "Lower music under speech".

import 'package:clipforge/core/editor/sound_tracks.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/editor/editor_actions.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/tools.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

Project _twoMusicTracks() {
  final p = sampleProject();
  return p.copyWith(
    tracks: const [
      SoundTrack(id: kMusicTrackId, name: 'Music'),
      SoundTrack(id: 'm2', name: 'Music 2'),
    ],
    audio: [
      ...p.audio,
      const AudioClip(
          id: 'm2a',
          path: '/media/other.mp3',
          sourceDurationMs: 60000,
          startMs: 0,
          inMs: 0,
          outMs: 8000,
          trackId: 'm2'),
    ],
  );
}

void main() {
  setUpAll(loadFonts);

  testWidgets('every action has a label and an icon; reasons are short',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    final actions = EditorActions(s);
    for (final a in Act.values) {
      expect(actLabel(a), isNotEmpty);
      final why = actions.whyNot(a);
      if (why != null) {
        expect(why.length, lessThan(48), reason: '$a: $why');
        expect(why.endsWith('.'), isFalse, reason: '$a: $why');
        expect(why[0], why[0].toLowerCase(), reason: '$a: $why');
      }
    }
  });

  testWidgets('the reasons follow the selection, the playhead and the project',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    EditorActions a() => EditorActions(s);
    // Nothing selected.
    expect(a().whyNot(Act.fitMusic), 'select a music clip');
    expect(a().whyNot(Act.delete), 'select something first');
    expect(a().whyNot(Act.moveEarlier), 'select a clip');
    expect(a().whyNot(Act.pasteSettings), 'copy settings first');
    expect(a().whyNot(Act.undo), 'nothing to undo');
    expect(a().whyNot(Act.crop), 'select a clip or an overlay');
    expect(a().whyNot(Act.exportSubtitles), 'no captions yet');
    expect(a().whyNot(Act.shortsFromMarkers), 'no good moment markers yet');
    expect(a().whyNot(Act.transcribe), 'on computers only',
        reason: 'the test harness has no speech engine, like a phone');
    expect(a().whyNot(Act.split), isNull);
    expect(a().whyNot(Act.export), isNull);

    // The first clip: cannot move earlier, can move later.
    s.selectClipAndShow('a');
    await tester.pumpAndSettle();
    expect(a().whyNot(Act.moveEarlier), 'it is already the first clip');
    expect(a().whyNot(Act.moveLater), isNull);
    expect(a().whyNot(Act.crop), isNull);
    expect(a().whyNot(Act.delete), isNull);
    expect(a().whyNot(Act.removeSilences), isNull);
    // A photo has no sound.
    s.selectClipAndShow('b');
    await tester.pumpAndSettle();
    expect(a().whyNot(Act.removeSilences), 'select a video clip with sound');
    expect(a().whyNot(Act.freezeFrame), 'move the playhead onto a video clip');
    expect(a().whyNot(Act.separateSound), isNotNull);
    // Music selected.
    s.select(ItemKind.audio, 'm1');
    await tester.pumpAndSettle();
    expect(a().whyNot(Act.fitMusic), isNull);
    expect(a().whyNot(Act.lineUpVoice), isNull);
    expect(a().whyNot(Act.moveEarlier), 'select a clip');
    // Copy, then paste is possible on a clip.
    s.selectClipAndShow('a');
    a().run(tester.element(find.byType(PreviewView)), Act.copySettings);
    await tester.pumpAndSettle();
    expect(a().whyNot(Act.pasteSettings), isNull);
    await waitForMessage(tester);
  });

  testWidgets('an empty project: adding is possible, the rest says why',
      (tester) async {
    final empty = Project(
        id: 'p1',
        name: 'Empty',
        createdAt: DateTime(2026, 11, 19),
        updatedAt: DateTime(2026, 11, 19));
    await openEditor(tester, desktop, project: empty);
    final a = EditorActions(sessionOf(tester));
    expect(a.whyNot(Act.addMedia), isNull);
    for (final act in [
      Act.addMusic, Act.addTitle, Act.split, Act.export, Act.addOverlay, //
      Act.markMoment,
    ]) {
      expect(a.whyNot(act), 'add a video first', reason: '$act');
    }
    expect(a.whyNot(Act.playPause), 'nothing to play yet');
    expect(a.whyNot(Act.lowerMusic), 'add music first');
  });

  testWidgets('the menu bar shows exactly what EditorActions says',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    void same() {
      final menu = appMenu.editor!;
      final actions = EditorActions(s);
      for (final a in menu.entries.keys) {
        expect(menu.entries[a]!.reason, actions.whyNot(a), reason: '$a');
        expect(menu.entries[a]!.checked, actions.checked(a), reason: '$a');
        expect(menu.run(a) != null, actions.whyNot(a) == null, reason: '$a');
      }
    }

    same();
    s.selectClipAndShow('b');
    await tester.pumpAndSettle();
    same();
    s.select(ItemKind.audio, 'm1');
    await tester.pumpAndSettle();
    same();
    s.editor.removeClip('a');
    await tester.pumpAndSettle();
    same();
    final labels = describeMenuTree(buildMenuTree(appMenu.editor,
        platform: TargetPlatform.windows));
    expect(labels, contains('Clip > Move earlier (select a clip)'));
    expect(labels, contains('Sound > Fit music to video'));
    expect(labels,
        contains('Edit > Redo (nothing to redo)  [Ctrl+Shift+Z]'));
  });

  testWidgets('the bar in the window: every menu opens (pictures)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()], missing: const {});
      fakes.speech = FakeSpeech();
      await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1'),
          menuBar: true, help: HelpMenuActions(openHelp: () {}, showTour: () {})));
      await tester.pumpAndSettle();
      for (final menu in [
        'File', 'Edit', 'Add', 'Clip', 'Sound', 'Text and speech', 'View', //
        'Playback', 'Help',
      ]) {
        await tester.tap(find.widgetWithText(SubmenuButton, menu));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsWidgets, reason: menu);
        expect(tester.takeException(), isNull, reason: menu);
        await fakes.screenshot(tester,
            'menu115_${menu.toLowerCase().replaceAll(' ', '_')}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('Lower music under speech is one truth', () {
    String menuLabel() => describeMenuTree(buildMenuTree(appMenu.editor,
            platform: TargetPlatform.windows))
        .firstWhere((l) => l.contains('Lower music under speech'));

    testWidgets('menu, side panel and track switches agree: none, all, some',
        (tester) async {
      await openEditor(tester, desktop, project: _twoMusicTracks());
      final s = sessionOf(tester);
      SwitchListTile panel() => tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('lower-music-all')));
      ActionEntry menu() => appMenu.editor!.entries[Act.lowerMusic]!;

      // None.
      expect(lowerMusicState(s.project), LowerMusic.none);
      expect(panel().value, isFalse);
      expect((menu().checked, menu().mixed), (false, false));
      expect(menuLabel(), 'Sound > Lower music under speech');

      // The side panel turns every music track on; the menu follows.
      await tester.ensureVisible(find.byKey(const ValueKey('lower-music-all')));
      await tester.tap(find.byKey(const ValueKey('lower-music-all')));
      await tester.pumpAndSettle();
      expect(s.project.soundTracks.map((t) => t.duck), [true, true]);
      expect(panel().value, isTrue);
      expect((menu().checked, menu().mixed), (true, false));

      // One track's own switch off (as its track menu does): "some".
      s.editor.setSoundTrack('m2', duck: false);
      await tester.pumpAndSettle();
      expect(lowerMusicState(s.project), LowerMusic.some);
      expect(panel().value, isFalse);
      expect(find.textContaining('On for some tracks only'), findsOneWidget);
      expect((menu().checked, menu().mixed), (false, true));
      expect(menuLabel(),
          'Sound > Lower music under speech — on for some tracks');

      // The menu item from "some": all on. Again: all off.
      menu().onTap!();
      await tester.pumpAndSettle();
      expect(s.project.soundTracks.map((t) => t.duck), [true, true]);
      expect(panel().value, isTrue);
      appMenu.editor!.entries[Act.lowerMusic]!.onTap!();
      await tester.pumpAndSettle();
      expect(s.project.soundTracks.map((t) => t.duck), [false, false]);
      expect(panel().value, isFalse);
      expect(s.project.duckMusic, isFalse);
    });

    testWidgets('the track menu switch is the same switch', (tester) async {
      await openEditor(tester, desktop, project: _twoMusicTracks());
      final s = sessionOf(tester);
      s.select(ItemKind.audio, 'm1');
      await tester.pumpAndSettle();
      // The selected sound's panel has its track's switch.
      await tester.ensureVisible(find.byKey(const ValueKey('sound-duck')));
      await tester.tap(find.byKey(const ValueKey('sound-duck')));
      await tester.pumpAndSettle();
      expect(lowerMusicState(s.project), LowerMusic.some);
      expect(appMenu.editor!.entries[Act.lowerMusic]!.mixed, isTrue);
      s.clearSelection();
      await tester.pumpAndSettle();
      expect(find.textContaining('On for some tracks only'), findsOneWidget);
      expect(find.byType(DuckMusicSwitch), findsOneWidget);
    });
  });
}
