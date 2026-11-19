// 1.15: the ONE Settings page (lib/ui/settings/settings_screen.dart) and
// the single source behind it (AppSettings over AppPrefs): every switch
// that exists elsewhere (View menu, the Export window, the editor) is the
// same setting.

import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/app_settings.dart';
import 'package:clipforge/ui/editor/acts.dart';
import 'package:clipforge/ui/editor/export_dialog.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/help/what_moved.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:clipforge/ui/settings/settings_screen.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

AppSettings settingsOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)))
    .read(appSettingsProvider);

Future<void> _tapSwitch(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

bool _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value;

void main() {
  setUpAll(loadFonts);

  test('AppSettings reads and writes the same keys as before 1.15', () async {
    final prefs = MemoryAppPrefs(answered: true)
      ..flags.addAll({kSnappingOffFlag, kSoundWavesOffFlag})
      ..texts[kTextDockText] = 'below';
    final s = AppSettings(prefs);
    expect((s.snapping, s.soundWaves, s.graphicsCard), (true, true, true),
        reason: 'the defaults until it is loaded');
    await s.load();
    expect((s.snapping, s.soundWaves, s.textBelow), (false, false, true));
    expect((s.smoothPreview, s.graphicsCard, s.suggestions), (true, true, true));
    var notified = 0;
    s.addListener(() => notified++);
    await s.setSnapping(true);
    await s.setGraphicsCard(false);
    await s.setSuggestions(false);
    await s.setTextBelow(false);
    await s.setSmoothPreview(false);
    expect(notified, 5);
    expect(prefs.flags, {
      kSoundWavesOffFlag, kGraphicsCardOffFlag, kSuggestionsOffFlag, //
      kSmoothPreviewOffFlag,
    });
    expect(prefs.texts[kTextDockText], 'right');
    // A second object over the same store sees what the first wrote.
    final again = AppSettings(prefs);
    await again.load();
    expect((again.snapping, again.graphicsCard, again.suggestions),
        (true, false, false));
    // Don't show again, and bringing them back.
    await s.hideHint('fit-music');
    await s.hideHint('lower-music');
    await s.hideHint('fit-music');
    expect(await s.hiddenHints(), ['fit-music', 'lower-music']);
    expect(await prefs.flag('hint.fit-music.off'), isTrue);
    expect(await s.showHiddenHintsAgain(), 2);
    expect(await prefs.flag('hint.fit-music.off'), isFalse);
    expect(await s.hiddenHints(), isEmpty);
  });

  testWidgets('computer: File > Settings… and Ctrl+comma open the window; '
      'its sections', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()], missing: const {});
      await tester.pumpWidget(fakes.app(const HomeScreen(),
          menuBar: true,
          help: HelpMenuActions(
              openHelp: () {},
              showTour: () {},
              openSettings: () => openSettings(
                  tester.element(find.byType(HomeScreen))))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SubmenuButton, 'File'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
      for (final heading in [
        'Editing', 'Text window', 'Export', 'Suggestions', 'Updates', 'About',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      for (final label in [
        'Snap to playhead and edges', 'Show sound waves', //
        'Use graphics card (faster)', 'Show suggestions',
        'Check for updates automatically', 'Check now', 'Copy version info',
        "What's new", 'Licences',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Phones only.
      expect(find.text('Smooth preview'), findsNothing);
      await fakes.screenshot(tester, 'settings_desktop');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-dialog')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone: Settings from the project list; a page with Smooth '
      'preview and without the computer-only parts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      useScreen(tester, const Size(360, 760));
      final fakes = Fakes(projects: [sampleProject()], missing: const {});
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-more')));
      await tester.pumpAndSettle();
      // The automatic check is in Settings now, not in this menu.
      expect(find.text('Check automatically'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-more-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
      expect(find.text('Smooth preview'), findsOneWidget);
      expect(find.text('Text window'), findsNothing);
      expect(find.text('Claude'), findsNothing);
      // Every switch is at least 48 high.
      for (final e in find.byType(SwitchListTile).evaluate()) {
        expect(e.size!.height, greaterThanOrEqualTo(48));
      }
      await fakes.screenshot(tester, 'settings_phone');
      await _tapSwitch(tester, 'settings-smooth-preview');
      expect(fakes.prefs.flags, contains(kSmoothPreviewOffFlag));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the page and the stored settings stay in sync, both ways',
      (tester) async {
    // A computer (the Text window section is not on phones).
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    useScreen(tester, desktop);
    final fakes = Fakes(projects: [sampleProject()], missing: const {});
    await tester.pumpWidget(fakes.app(const Scaffold(
        body: SingleChildScrollView(child: SettingsBody()))));
    await tester.pumpAndSettle();
    final settings = settingsOf(tester);
    final updates = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)))
        .read(updateControllerProvider);

    // Page -> store.
    for (final (key, flag) in const [
      ('settings-snapping', kSnappingOffFlag),
      ('settings-sound-waves', kSoundWavesOffFlag),
      ('settings-graphics-card', kGraphicsCardOffFlag),
      ('settings-auto-updates', kUpdateCheckOffFlag),
    ]) {
      expect(_switch(tester, key), isTrue, reason: key);
      await _tapSwitch(tester, key);
      expect(_switch(tester, key), isFalse, reason: key);
      expect(fakes.prefs.flags, contains(flag), reason: key);
      await _tapSwitch(tester, key);
      expect(fakes.prefs.flags, isNot(contains(flag)), reason: key);
    }
    expect(updates.autoCheck, isTrue);
    // Suggestions are off in the test harness: turn them on here.
    expect(_switch(tester, 'settings-suggestions'), isFalse);
    await _tapSwitch(tester, 'settings-suggestions');
    expect(fakes.prefs.flags, isNot(contains(kSuggestionsOffFlag)));

    // Store -> page (as the View menu or the Export window would).
    await settings.setSnapping(false);
    await settings.setGraphicsCard(false);
    await updates.setAutoCheck(false);
    await tester.pumpAndSettle();
    expect(_switch(tester, 'settings-snapping'), isFalse);
    expect(_switch(tester, 'settings-graphics-card'), isFalse);
    expect(_switch(tester, 'settings-auto-updates'), isFalse);

    // The Text window's place.
    await tester.ensureVisible(find.text('Below'));
    await tester.tap(find.text('Below'));
    await tester.pumpAndSettle();
    expect(fakes.prefs.texts[kTextDockText], 'below');
    expect(settings.textBelow, isTrue);

    // "Show hidden suggestions again".
    expect(find.text('Show hidden suggestions again (none hidden)'),
        findsOneWidget);
    await settings.hideHint('fit-music');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(fakes.app(const Scaffold(
        body: SingleChildScrollView(child: SettingsBody()))));
    await tester.pumpAndSettle();
    await _tapSwitch(tester, 'settings-show-hidden');
    expect(await fakes.prefs.flag('hint.fit-music.off'), isFalse);
    expect(find.text('Show hidden suggestions again (none hidden)'),
        findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the View menu and Settings are one switch; the open editor '
      'follows at once', (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    final settings = settingsOf(tester);
    expect((s.snapping.value, s.showWaves.value), (true, true));

    // View > Snap…  (the menu's action) writes the setting.
    appMenu.editor!.run(Act.snapping)!();
    await tester.pumpAndSettle();
    expect(s.snapping.value, isFalse);
    expect(settings.snapping, isFalse);
    expect(appMenu.editor!.entries[Act.snapping]!.checked, isFalse);

    // Settings -> the editor and the menu's tick.
    await settings.setSnapping(true);
    await settings.setSoundWaves(false);
    await tester.pumpAndSettle();
    expect((s.snapping.value, s.showWaves.value), (true, false));
    expect(s.pictures.enabled, isFalse);
    expect(appMenu.editor!.entries[Act.snapping]!.checked, isTrue);
    expect(appMenu.editor!.entries[Act.soundWaves]!.checked, isFalse);

    // Where the Text window sits.
    await settings.setTextBelow(true);
    await tester.pumpAndSettle();
    expect(s.textDock.value, TextDock.below);
  });

  testWidgets('Use graphics card is remembered between exports',
      (tester) async {
    final fakes = await openEditor(tester, desktop, missingFiles: const {});
    fakes.engine.hardwareEncoder = true;
    final settings = settingsOf(tester);
    await settings.setGraphicsCard(false);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportDialog), findsOneWidget);
    final dialog = tester.widget<ExportDialog>(find.byType(ExportDialog));
    expect(dialog.settings, same(settings));
    // Turned off in Settings: this export starts with it off.
    expect(find.textContaining('graphics card turned off'), findsOneWidget);
    // The first export on this device: one line says what it is.
    expect(find.byKey(const ValueKey('export-first-note')), findsOneWidget);
    await fakes.screenshot(tester, 'export_first_note_desktop');
  });

  group('"What moved", once, for people who had an older version', () {
    Future<Fakes> start(WidgetTester tester, Size size,
        {required void Function(MemoryAppPrefs prefs) prepare}) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: [sampleProject()], missing: const {});
      fakes.prefs.flags.remove(kWhatMovedSeenFlag);
      fakes.prefs.texts.remove(kLastRunVersionText);
      fakes.prefs.texts.remove(kUpdatedLineSeenText);
      prepare(fakes.prefs);
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      return fakes;
    }

    for (final (label, size) in [('desktop', desktop), ('phone', phone)]) {
      testWidgets('an existing user sees it once, with Show me Settings '
          '($label)', (tester) async {
        final fakes = await start(tester, size, prepare: (_) {});
        if (olderThan115(fakes.buildInfo.version)) {
          // A build older than 1.15 has nothing to say.
          expect(find.byKey(const ValueKey('what-moved-dialog')), findsNothing);
          return;
        }
        expect(find.byKey(const ValueKey('what-moved-dialog')), findsOneWidget);
        expect(find.text('Things are easier to find now'), findsOneWidget);
        expect(find.textContaining('every keyboard shortcut works'),
            findsOneWidget);
        await fakes.screenshot(tester, 'what_moved_$label');
        expect(fakes.prefs.flags, contains(kWhatMovedSeenFlag));
        await tester.tap(find.byKey(const ValueKey('what-moved-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsBody), findsOneWidget);
        // The project list also says which version this is now, with
        // What's new one tap away.
        if (size == desktop) {
          await tester.tap(find.descendant(
              of: find.byKey(const ValueKey('settings-dialog')),
              matching: find.byTooltip('Close')));
          await tester.pumpAndSettle();
        } else {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('updated-line')), findsOneWidget);
        expect(find.text('Updated to ${fakes.buildInfo.version}'),
            findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('updated-line-whats-new')));
        await tester.pumpAndSettle();
        expect(find.textContaining("What's new"), findsWidgets);
        expect(fakes.prefs.texts[kUpdatedLineSeenText],
            fakes.buildInfo.version);

        // Not a second time.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(fakes.app(const HomeScreen()));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('what-moved-dialog')), findsNothing);
        expect(find.byKey(const ValueKey('updated-line')), findsNothing);
      });
    }

    testWidgets('a first install sees neither note', (tester) async {
      final fakes = await start(tester, desktop,
          prepare: (prefs) => prefs.answered = false);
      // The tour question instead.
      expect(find.byKey(const ValueKey('what-moved-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('updated-line')), findsNothing);
      expect(fakes.prefs.flags, contains(kWhatMovedSeenFlag));
      expect(fakes.prefs.texts[kLastRunVersionText], fakes.buildInfo.version);
    });

    testWidgets('someone already on 1.15 or newer: only the updated line',
        (tester) async {
      await start(tester, desktop,
          prepare: (prefs) => prefs.texts[kLastRunVersionText] = '1.15.0-x');
      expect(find.byKey(const ValueKey('what-moved-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('updated-line')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('updated-line-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updated-line')), findsNothing);
    });

    test('which versions are "older than 1.15"', () {
      expect(olderThan115(null), isTrue);
      expect(olderThan115('1.14.1'), isTrue);
      expect(olderThan115('1.9.0'), isTrue);
      expect(olderThan115('0.9'), isTrue);
      expect(olderThan115('1.15.0'), isFalse);
      expect(olderThan115('1.16.2'), isFalse);
      expect(olderThan115('2.0.0'), isFalse);
    });
  });
}
