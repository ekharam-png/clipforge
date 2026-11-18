// "Which build is this?" (lib/ui/about.dart): the version line on the
// project list, About ClipForge, Copy version info, the Help footer, the
// What's new article and the About entries of the menu bars.

@Timeout(Duration(seconds: 90))
library;

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/ui/about.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/help/help_screen.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

final ciBuild = BuildInfo.fromValues(
  version: '1.4.0',
  buildNumber: '21',
  buildTime: '2026-11-16T07:20:00Z',
  commit: '877e482',
  channel: 'ci',
);

/// Catches what the app puts on the clipboard.
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

Future<Fakes> home(WidgetTester tester, Size size, {BuildInfo? build}) async {
  useScreen(tester, size);
  final fakes = Fakes(projects: [sampleProject()]);
  if (build != null) fakes.buildInfo = build;
  await tester.pumpWidget(fakes.app(const HomeScreen()));
  await tester.pumpAndSettle();
  return fakes;
}

void main() {
  setUpAll(loadFonts);

  for (final size in [phone, desktop]) {
    final label = size == phone ? 'phone' : 'desktop';

    testWidgets('$label: the project list shows the version, in local time',
        (tester) async {
      final fakes = await home(tester, size, build: ciBuild);
      final line = find.byKey(const ValueKey('version-line'));
      expect(line, findsOneWidget);
      expect(find.text(ciBuild.describe(utc: false)), findsOneWidget);
      expect(ciBuild.describe(utc: false),
          startsWith('ClipForge 1.4.0 (build 21) · 16 Nov 2026, '));
      // Small and out of the way: below the project list, never under the
      // New project button.
      final lineBox = tester.getRect(line);
      expect(lineBox.bottom, lessThanOrEqualTo(size.height));
      expect(
          tester.getRect(find.byType(FloatingActionButton)).bottom,
          lessThanOrEqualTo(lineBox.top + 0.5));
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'version_home_$label');

      // Tapping it opens About ClipForge.
      await tester.tap(line);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-dialog')), findsOneWidget);
    });

    testWidgets('$label: About ClipForge and Copy version info',
        (tester) async {
      final copied = catchClipboard(tester);
      final fakes = await home(tester, size, build: ciBuild);
      // Phones (and these tests, which run as Android): the More menu.
      await tester.tap(find.byKey(const ValueKey('home-more')));
      await tester.pumpAndSettle();
      expect(find.text('Copy version info'), findsOneWidget);
      await tester.tap(find.text('About ClipForge'));
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('about-dialog'));
      expect(dialog, findsOneWidget);
      expect(find.text('ClipForge 1.4.0'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('877e482'), findsOneWidget);
      final time = ciBuild.buildTime!;
      expect(
          find.text('${formatBuildTime(time, utc: false)}\n'
              '16 Nov 2026, 07:20 UTC'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'about_$label');

      await tester.tap(find.byKey(const ValueKey('copy-version-info')));
      await tester.pumpAndSettle();
      expect(copied, [
        versionReport(ciBuild,
            system: 'TestOS 1.0, test_x64',
            screen: '${size.width.round()}x${size.height.round()} (scale 1.0)'),
      ]);
      expect(copied.single, startsWith(
          'ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482\n'));
      expect(find.textContaining('Version info copied'), findsOneWidget);

      // What's new opens Help at the release notes.
      await tester.tap(find.text("What's new"));
      await tester.pumpAndSettle();
      // (On a phone the article opens over the topic list.)
      expect(find.byType(HelpScreen, skipOffstage: false), findsOneWidget);
      expect(find.text('1.4.0 – 16 November 2026'), findsOneWidget);
    });

    testWidgets('$label: Help shows the version at the bottom',
        (tester) async {
      final copied = catchClipboard(tester);
      final fakes = await home(tester, size, build: ciBuild);
      await tester.tap(find.byTooltip('Help'));
      await tester.pumpAndSettle();
      final footer = find.byKey(const ValueKey('help-version-footer'));
      expect(footer, findsOneWidget);
      expect(
          find.descendant(
              of: footer, matching: find.text(ciBuild.describe(utc: false))),
          findsOneWidget);
      expect(tester.getRect(footer).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'help_version_$label');

      await tester.tap(
          find.descendant(of: footer, matching: find.text('About ClipForge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-dialog')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Copy version info'));
      await tester.pumpAndSettle();
      expect(copied.single, contains('Build: 21 (ci)'));
      ScaffoldMessenger.of(tester.element(footer)).removeCurrentSnackBar();
      await tester.pumpAndSettle();

      // What's new is a topic in the list too.
      await tester.enterText(
          find.byKey(const ValueKey('help-search')), 'whats new');
      await tester.pumpAndSettle();
      await tester.tap(find.text("What's new").first);
      await tester.pumpAndSettle();
      expect(find.textContaining('You have ClipForge'), findsWidgets);
    });
  }

  testWidgets('a local build says so instead of a time', (tester) async {
    await home(tester, phone,
        build: BuildInfo.fromValues(version: '1.4.0', buildNumber: '1'));
    expect(find.text('ClipForge 1.4.0 (build 1) · local build'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version-line')));
    await tester.pumpAndSettle();
    expect(find.text('local build (made on a computer, not by GitHub)'),
        findsOneWidget);
    expect(find.text('unknown'), findsOneWidget, reason: 'no commit');
  });

  testWidgets('Windows and Linux: Help > About ClipForge and Copy version info',
      (tester) async {
    var about = 0, copy = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppMenuBar(
        controller: AppMenuController(),
        help: HelpMenuActions(
          openHelp: () {},
          showTour: () {},
          showAbout: () => about++,
          copyVersionInfo: () => copy++,
        ),
        child: child!,
      ),
      home: const Scaffold(body: Text('page')),
    ));
    expect(aboutInMenuBar, isTrue);
    await tester.tap(find.widgetWithText(SubmenuButton, 'Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-about')));
    await tester.pumpAndSettle();
    expect(about, 1);
    await tester.tap(find.widgetWithText(SubmenuButton, 'Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy version info'));
    await tester.pumpAndSettle();
    expect(copy, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('computers have no More menu: About is in the menu bar',
      (tester) async {
    await home(tester, desktop);
    expect(find.byKey(const ValueKey('home-more')), findsNothing);
    expect(find.byKey(const ValueKey('version-line')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('macOS: the app menu\'s About is ClipForge\'s own', () {
    var about = 0;
    final menus = buildAppMenus(null,
        help: HelpMenuActions(
            openHelp: () {}, showTour: () {}, showAbout: () => about++));
    final app = menus.first as PlatformMenu;
    expect(app.label, 'ClipForge');
    final first = (app.menus.first as PlatformMenuItemGroup).members.single;
    expect(first.label, 'About ClipForge');
    first.onSelected!();
    expect(about, 1);
    final help = menus.last as PlatformMenu;
    expect([for (final m in help.menus) m.label],
        contains('Copy version info'));
  });

  test('aboutInMenuBar is false on phones', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(aboutInMenuBar, isFalse);
  });
}
