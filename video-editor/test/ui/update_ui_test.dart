// Updates (1.12) as the user sees them: the banner on the project list
// (phone and desktop), the Update window, "Check for updates" in the Help
// menu and on phones, and the switch for the automatic check.

import 'package:clipforge/core/links.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/update/update_download.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'home_screen_test.dart' show someProjects;

const ci139 = BuildInfo(version: '1.11.0', buildNumber: '139', channel: 'ci');
const apk = UpdateAsset(
    url: 'https://example.org/dl/ClipForge-android.apk', size: 3, sha256: 'abc');

UpdateInfo release(int build, {Map<String, UpdateAsset> files = const {}}) => UpdateInfo(
    version: '1.12.0',
    build: build,
    notesUrl: 'https://example.org/releases/tag/v1.12.0',
    platforms: files);

void main() {
  setUpAll(loadFonts);

  Future<Fakes> home(WidgetTester tester, Size size,
      {UpdateInfo? latest, bool menuBar = false, void Function(Fakes)? setup}) async {
    useScreen(tester, size);
    final fakes = Fakes(projects: someProjects())
      ..buildInfo = ci139
      ..latest = latest;
    setup?.call(fakes);
    await tester.pumpWidget(fakes.app(const HomeScreen(), menuBar: menuBar));
    await tester.pumpAndSettle();
    return fakes;
  }

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('a newer version: a quiet banner on the project list ($label)', (tester) async {
      final fakes = await home(tester, size, latest: release(142));
      expect(fakes.updateChecks, 1);
      expect(find.byKey(const ValueKey('update-banner')), findsOneWidget);
      expect(find.text('Version 1.12.0 is available'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      // The projects are all still there and usable under it.
      expect(find.text('Summer trip'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fakes.screenshot(tester, 'update_banner_$label');

      await tester.tap(find.text("What's new"));
      await tester.pumpAndSettle();
      expect(fakes.updatePlatform.opened, ['https://example.org/releases/tag/v1.12.0']);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-banner')), findsNothing);
    });
  }

  testWidgets('no banner when up to date, offline, or the check is switched off',
      (tester) async {
    var fakes = await home(tester, phone, latest: release(139));
    expect(fakes.updateChecks, 1);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    fakes = await home(tester, phone, latest: null);
    expect(fakes.updateChecks, 1);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
    expect(find.byType(SnackBar), findsNothing, reason: 'the automatic check is silent');

    await tester.pumpWidget(const SizedBox());
    fakes = await home(tester, phone,
        latest: release(142), setup: (f) => f.prefs.flags.add(kUpdateCheckOffFlag));
    expect(fakes.updateChecks, 0);
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
  });

  testWidgets('Skip this version is remembered', (tester) async {
    final fakes = await home(tester, desktop, latest: release(142));
    await tester.tap(find.byTooltip('More about this update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-banner')), findsNothing);
    expect(fakes.prefs.texts[kUpdateSkipBuildText], '142');
    expect(find.textContaining('will not be offered again'), findsOneWidget);
  });

  testWidgets('phones: Check for updates is under More, its switch in Settings', (tester) async {
    final fakes = await home(tester, phone, latest: null);
    await tester.tap(find.byKey(const ValueKey('home-more')));
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);
    // The switch for the automatic check is in Settings since 1.15.
    expect(find.text('Check automatically'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    await fakes.screenshot(tester, 'update_more_phone');
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not reach the update server'), findsOneWidget,
        reason: 'a check by hand says why it did not work');

    fakes.latest = release(139);
    await tester.tap(find.byKey(const ValueKey('home-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You have the newest version'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('settings-auto-updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-auto-updates')));
    await tester.pumpAndSettle();
    expect(fakes.prefs.flags, contains(kUpdateCheckOffFlag));
  });

  testWidgets('computers: the Help menu has Check for updates, its switch and Connect to Claude',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: someProjects())
        ..buildInfo = ci139
        ..latest = release(142);
      var checks = 0, settings = 0, claude = 0;
      await tester.pumpWidget(fakes.app(const HomeScreen(),
          menuBar: true,
          help: HelpMenuActions(
            openHelp: () {},
            showTour: () {},
            checkForUpdates: () => checks++,
            openSettings: () => settings++,
            connectClaude: () => claude++,
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('Check for updates…'), findsOneWidget);
      // The switch for the automatic check lives in Settings since 1.15.
      expect(find.text('Check for updates automatically'), findsNothing);
      expect(find.text('Connect to Claude…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-check-updates')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-connect-claude')));
      await tester.pumpAndSettle();
      expect([checks, settings, claude], [1, 1, 1]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('Update where the app cannot install by itself: the download page ($label)',
        (tester) async {
      final fakes = await home(tester, size, latest: release(142));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update to version 1.12.0'), findsOneWidget);
      expect(find.textContaining('cannot update itself'), findsOneWidget);
      await fakes.screenshot(tester, 'update_dialog_page_$label');
      await tester.tap(find.text('Open the download page'));
      await tester.pumpAndSettle();
      expect(fakes.updatePlatform.opened, [AppLinks.builtIn.download]);
      expect(find.text('Update to version 1.12.0'), findsNothing);
    });
  }

  testWidgets('Update on Android: explained, downloaded, handed to the system installer',
      (tester) async {
    final fakes = await home(tester, phone,
        latest: release(142, files: {'android': apk}),
        setup: (f) {
          f.updatePlatform
            ..os = 'android'
            ..key = 'android';
          f.downloader = (asset, dir, build) => UpdateDownload.of(
              asset, Future.value('$dir/b$build-${asset.fileName}'),
              steps: const [UpdateProgress(1, 3)]);
        });
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow from this source'), findsOneWidget,
        reason: 'the Android prompt is explained before it appears');
    expect(find.textContaining('Your projects and videos stay'), findsOneWidget);
    expect(find.text('Open the download page'), findsOneWidget, reason: 'plan B is always there');
    await fakes.screenshot(tester, 'update_dialog_android_phone');
    await tester.tap(find.byKey(const ValueKey('update-start')));
    await tester.pumpAndSettle();
    expect(fakes.updatePlatform.installed.single, endsWith('b142-ClipForge-android.apk'));
    expect(find.textContaining('Android is now asking you to confirm'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed download: the reason, Try again and the download page', (tester) async {
    final fakes = await home(tester, desktop,
        latest: release(142, files: {'android': apk}),
        setup: (f) {
          f.updatePlatform
            ..os = 'android'
            ..key = 'android';
          f.downloader = (asset, dir, build) => UpdateDownload.of(
              asset,
              Future<String>.error(UpdateException(
                  'The update was downloaded, but it is not the file ClipForge '
                  'expected, so it was deleted and nothing was installed. Try '
                  'again, or use the download page.',
                  kind: 'check')));
        });
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-start')));
    await tester.pumpAndSettle();
    expect(find.textContaining('nothing was installed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open the download page'), findsOneWidget);
    expect(fakes.updatePlatform.installed, isEmpty);
    await fakes.screenshot(tester, 'update_dialog_failed_desktop');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-banner')), findsOneWidget,
        reason: 'the banner stays for another try');
  });
}
