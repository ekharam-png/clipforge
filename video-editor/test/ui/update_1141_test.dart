// 1.14.1: what the app does when the helper script does not start (it
// stays open and says so), "Copy details" with the update log, and the
// tidy-up for an app that runs from a folder an earlier update unpacked
// into (the question, the list with versions, "Not now" for this version
// only). Real folders in a temp place stand in for the PC; no script is
// ever started (Fakes.swaps records what the app asked for).
import 'dart:io';

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:clipforge/core/update/update_log.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../core/tidy_up_test.dart' show makeInstall;
import 'about_test.dart' show catchClipboard;
import 'fakes.dart';
import 'home_screen_test.dart' show someProjects;

const b130 = BuildInfo(version: '1.14.1', buildNumber: '130', channel: 'ci');
const b131 = BuildInfo(version: '1.14.2', buildNumber: '131', channel: 'ci');

void main() {
  setUpAll(loadFonts);
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_1141_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Fakes> home(WidgetTester tester, Size size, BuildInfo build,
      {required String install,
      String? result,
      PendingUpdate? pending,
      Fakes? reuse,
      bool windows = true}) async {
    useScreen(tester, size);
    final fakes = reuse ?? Fakes(projects: someProjects());
    fakes.buildInfo = build;
    fakes.updatePlatform
      ..os = windows ? 'windows' : 'macos'
      ..dir = tmp.path
      ..installDir = install;
    Directory(install).createSync(recursive: true);
    final state = Directory(p.join(tmp.path, 'state'))..createSync();
    if (result != null) {
      File(p.join(state.path, kUpdateResultFile)).writeAsStringSync(result);
    }
    pending?.write(state.path);
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    return fakes;
  }

  /// The folders found on the real PC, plus this version in a third one.
  String realPc() {
    final apps = p.join(tmp.path, 'Apps');
    makeInstall(apps, 'ClipForge-1.12.0', '1.12.0+109');
    makeInstall(apps, 'ClipForge-1.12.0.update-new', '1.13.0+118');
    makeInstall(apps, 'ClipForge-1.12.0.update-new.update-new', '1.14.0+121');
    return makeInstall(apps, 'ClipForge-1.12.0.update-new.update-new.update-new',
        '1.14.1+130', versionFile: true);
  }

  UpdateController controllerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(updateControllerProvider);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$label: running from a download folder: the question, the '
        'place, the older folders with their versions; untick one; go',
        (tester) async {
      final running = realPc();
      final fakes = await home(tester, size, b130, install: running);
      expect(find.byKey(const ValueKey('tidy-dialog')), findsOneWidget);
      expect(find.text('Tidy up the ClipForge folder?'), findsOneWidget);
      expect(
          find.text('ClipForge is running from a download folder '
              '("ClipForge-1.12.0.update-new.update-new.update-new"). Tidy up?'),
          findsOneWidget);
      expect(find.textContaining('moves this version (1.14.1)'), findsOneWidget);
      expect(find.textContaining('Your projects and videos (Documents > ClipForge) are not touched'),
          findsOneWidget);
      expect(find.text('A new folder called "ClipForge"'), findsOneWidget);
      expect(find.textContaining('The folder "ClipForge-1.12.0" (it holds ClipForge 1.12.0'),
          findsOneWidget);
      expect(find.text('"ClipForge-1.12.0" (ClipForge 1.12.0)'), findsOneWidget);
      expect(find.text('"ClipForge-1.12.0.update-new" (ClipForge 1.13.0)'), findsOneWidget);
      expect(find.text('"ClipForge-1.12.0.update-new.update-new" (ClipForge 1.14.0)'),
          findsOneWidget);
      expect(find.textContaining('There are no desktop or Start-menu shortcuts to fix'),
          findsOneWidget);
      await fakes.screenshot(tester, 'tidy_up_$label');

      // Keep the 1.13 folder.
      final keep = find.byKey(const ValueKey('tidy-remove-ClipForge-1.12.0.update-new'));
      await tester.ensureVisible(keep);
      await tester.tap(keep);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tidy-go')));
      await tester.pumpAndSettle();
      final apps = p.dirname(running);
      expect(fakes.swaps.single.mode, 'move');
      expect(fakes.swaps.single.installDir, p.join(apps, 'ClipForge'));
      expect(fakes.swaps.single.newDir, running);
      expect(fakes.swaps.single.remove, [
        p.join(apps, 'ClipForge-1.12.0'),
        p.join(apps, 'ClipForge-1.12.0.update-new.update-new'),
      ]);
      expect(fakes.updatePlatform.quits, 1);
      // The app itself changed nothing on disk: the script does, after
      // the app has closed.
      expect(Directory(apps).listSync().length, 4);
      final log = UpdateLog.inDir(p.join(tmp.path, 'state')).read();
      expect(log, contains('tidy-up: move [$running] to [${p.join(apps, 'ClipForge')}] (free)'));
      expect(log, contains('closing now so that the script can work'));
    });
  }

  testWidgets('the original folder can be chosen instead: it is then not removed',
      (tester) async {
    final running = realPc();
    final fakes = await home(tester, desktop, b130, install: running);
    await tester.tap(find.byKey(const ValueKey('tidy-target-ClipForge-1.12.0')));
    await tester.pumpAndSettle();
    expect(find.text('"ClipForge-1.12.0" (ClipForge 1.12.0)'), findsNothing);
    expect(find.text('"ClipForge-1.12.0.update-new" (ClipForge 1.13.0)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tidy-go')));
    await tester.pumpAndSettle();
    final apps = p.dirname(running);
    expect(fakes.swaps.single.installDir, p.join(apps, 'ClipForge-1.12.0'));
    expect(fakes.swaps.single.remove, [
      p.join(apps, 'ClipForge-1.12.0.update-new'),
      p.join(apps, 'ClipForge-1.12.0.update-new.update-new'),
    ]);
  });

  testWidgets('"Not now" is remembered for this version only', (tester) async {
    final running = realPc();
    var fakes = await home(tester, desktop, b130, install: running);
    await tester.tap(find.byKey(const ValueKey('tidy-not-now')));
    await tester.pumpAndSettle();
    expect(fakes.swaps, isEmpty);
    expect(fakes.updatePlatform.quits, 0);
    expect(await fakes.prefs.text(kTidyUpDeclinedText), '1.14.1+130');
    final prefs = fakes.prefs;
    // The same version starts again: no question.
    await tester.pumpWidget(const SizedBox());
    fakes = await home(tester, desktop, b130, install: running, reuse: Fakes(projects: someProjects()));
    await fakes.prefs.setText(kTidyUpDeclinedText, await prefs.text(kTidyUpDeclinedText));
    expect(find.byKey(const ValueKey('tidy-dialog')), findsOneWidget,
        reason: 'another settings file: asked');
    await tester.tap(find.byKey(const ValueKey('tidy-not-now')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    final again = Fakes(projects: someProjects());
    await again.prefs.setText(kTidyUpDeclinedText, '1.14.1+130');
    await home(tester, desktop, b130, install: running, reuse: again);
    expect(find.byKey(const ValueKey('tidy-dialog')), findsNothing);
    // The next version asks again.
    await tester.pumpWidget(const SizedBox());
    final next = Fakes(projects: someProjects());
    await next.prefs.setText(kTidyUpDeclinedText, '1.14.1+130');
    await home(tester, desktop, b131, install: running, reuse: next);
    expect(find.byKey(const ValueKey('tidy-dialog')), findsOneWidget);
  });

  testWidgets('no question in a normal folder, on a Mac, or when the names '
      'are taken there is no button to press', (tester) async {
    final apps = p.join(tmp.path, 'Apps');
    final normal = makeInstall(apps, 'ClipForge', '1.14.1+130');
    await home(tester, desktop, b130, install: normal);
    expect(find.byKey(const ValueKey('tidy-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    final staged = makeInstall(apps, 'ClipForge.update-new', '1.14.1+130');
    await home(tester, desktop, b130, install: staged, windows: false);
    expect(find.byKey(const ValueKey('tidy-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // "ClipForge" holds the SAME version: not proven older, never replaced.
    final fakes = await home(tester, desktop, b130, install: staged);
    expect(find.byKey(const ValueKey('tidy-dialog')), findsOneWidget);
    expect(find.textContaining('ClipForge cannot do it here'), findsOneWidget);
    expect(find.textContaining('there is already something with this name'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('tidy-go'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('tidy-not-now')));
    await tester.pumpAndSettle();
    expect(fakes.swaps, isEmpty);
  });

  testWidgets('the helper does not start: ClipForge stays open and says so, '
      'with Copy details', (tester) async {
    final copied = catchClipboard(tester);
    final running = realPc();
    final fakes = Fakes(projects: someProjects())..swapConfirmed = false;
    await home(tester, desktop, b130, install: running, reuse: fakes);
    await tester.tap(find.byKey(const ValueKey('tidy-go')));
    await tester.pumpAndSettle();
    expect(fakes.swaps.length, 1);
    expect(fakes.updatePlatform.quits, 0, reason: 'never closes without a running script');
    expect(find.byKey(const ValueKey('tidy-not-started')), findsOneWidget);
    expect(find.textContaining('could not start the small helper'), findsOneWidget);
    expect(find.textContaining('PowerShell and the plain command line were both tried'),
        findsOneWidget);
    expect(find.textContaining(p.join(tmp.path, 'state', 'update-log.txt')), findsOneWidget);
    await tester.tap(find.text('Copy details'));
    await tester.pumpAndSettle();
    expect(copied.single, contains('ClipForge 1.14.1 (build 130)'));
    expect(copied.single, contains('Folder: $running'));
    expect(copied.single, contains('Problem: ClipForge could not start the small helper'));
    expect(copied.single, contains('Update log: ${p.join(tmp.path, 'state', 'update-log.txt')}'));
    expect(copied.single, contains('app: tidy-up: move ['));
    // Not "Not now": the question comes again at the next start.
    expect(await fakes.prefs.text(kTidyUpDeclinedText), isNull);
  });

  testWidgets('after the move: one line that says where ClipForge now lives',
      (tester) async {
    final install = makeInstall(p.join(tmp.path, 'Apps'), 'ClipForge', '1.14.1+130');
    await home(tester, desktop, b130,
        install: install,
        result: '{"status":"updated","message":"","version":"1.14.1","mode":"move"}');
    expect(find.byKey(const ValueKey('tidy-done-line')), findsOneWidget);
    expect(find.textContaining('Tidied up: ClipForge now runs from the folder "ClipForge".'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('update-done-line')), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('a move that failed: said plainly, nothing removed, then the '
      'question again', (tester) async {
    final running = realPc();
    final fakes = await home(tester, desktop, b130,
        install: running,
        result: '{"status":"failed","message":"ClipForge could not be moved '
            '(robocopy ended with 16). It still runs from where it was.",'
            '"version":"1.14.1","mode":"move"}');
    expect(find.byKey(const ValueKey('tidy-failed-dialog')), findsOneWidget);
    expect(find.text('The tidy-up was not finished'), findsOneWidget);
    expect(find.textContaining('robocopy ended with 16'), findsOneWidget);
    expect(find.textContaining('Nothing of yours was removed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-failed-dialog')), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tidy-dialog')), findsOneWidget);
    expect(fakes.swaps, isEmpty);
  });

  testWidgets('a failed update: "The update could not be finished: …", where '
      'the log is, and Copy details with its last lines', (tester) async {
    final copied = catchClipboard(tester);
    final install = p.join(tmp.path, 'Apps', 'ClipForge');
    final newDir = '$install$kUpdateNewSuffix';
    Directory(newDir).createSync(recursive: true);
    writeUpdateMarker(newDir, 'windows');
    final state = p.join(tmp.path, 'state');
    Directory(state).createSync();
    final log = File(p.join(state, kUpdateLogFile));
    for (var i = 1; i <= 50; i++) {
      log.writeAsStringSync('2026-11-19 10:00:00 script(ps): step $i\r\n',
          mode: FileMode.append);
    }
    await home(tester, desktop, const BuildInfo(version: '1.14.1', buildNumber: '130', channel: 'ci'),
        install: install,
        result: '{"status":"failed","message":"The file \'data\\\\app.so\' in the '
            'ClipForge folder is in use by another program (is ClipForge, or a '
            'program started from this folder, still running?). Nothing was '
            'changed.","version":"1.14.2"}',
        pending: PendingUpdate(
                version: '1.14.2', build: 131, installDir: install, newDir: newDir)
            .started(DateTime.utc(2026, 11, 19)));
    expect(find.byKey(const ValueKey('update-failed-dialog')), findsOneWidget);
    expect(find.textContaining("The update could not be finished: The file 'data\\app.so' in the "
        'ClipForge folder is in use by another program'), findsOneWidget);
    expect(find.textContaining('The steps are written down in:\n${log.path}'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open the download page'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-failed-copy')));
    await tester.pumpAndSettle();
    final text = copied.single;
    expect(text, contains('Problem: The file \'data\\app.so\''));
    expect(text, contains('Its last 40 lines:'));
    expect(text, contains('script(ps): step 50'));
    expect(text, contains(' app: start: 1.14.1+130 from [$install]; result=failed'),
        reason: 'the start that read the result is in the log too');
    expect(text, isNot(contains('script(ps): step 11\n')));
    // The dialog is still there for Try again.
    expect(find.byKey(const ValueKey('update-failed-dialog')), findsOneWidget);
  });

  testWidgets('Copy version info adds the app folder and the last lines of '
      'the update log', (tester) async {
    final copied = catchClipboard(tester);
    final install = makeInstall(p.join(tmp.path, 'Apps'), 'ClipForge', '1.14.1+130');
    final state = Directory(p.join(tmp.path, 'state'))..createSync();
    File(p.join(state.path, kUpdateLogFile))
        .writeAsStringSync('2026-11-19 10:00:00 script(cmd): robocopy (new version) exit code 1\r\n');
    await home(tester, phone, b130, install: install);
    await tester.tap(find.byKey(const ValueKey('home-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy version info'));
    await tester.pumpAndSettle();
    expect(copied.single, contains('Version: 1.14.1'));
    expect(copied.single, contains('Folder: $install'));
    expect(copied.single, contains('Update log: ${p.join(state.path, kUpdateLogFile)}'));
    expect(copied.single, contains('robocopy (new version) exit code 1'));
  });

  testWidgets('an update left by "Later" whose helper does not start: '
      'ClipForge stays open, says so, and keeps the download', (tester) async {
    final install = makeInstall(p.join(tmp.path, 'Apps'), 'ClipForge', '1.14.1+130');
    final newDir = '$install$kUpdateNewSuffix';
    Directory(newDir).createSync(recursive: true);
    writeUpdateMarker(newDir, 'windows');
    final fakes = Fakes(projects: someProjects())..swapConfirmed = false;
    // An update left by "Later": the start tries to finish it.
    await home(tester, desktop, b130,
        install: install,
        reuse: fakes,
        pending: PendingUpdate(
            version: '1.14.2', build: 131, installDir: install, newDir: newDir));
    expect(fakes.swaps.single.mode, 'update');
    expect(fakes.updatePlatform.quits, 0);
    expect(find.byKey(const ValueKey('update-failed-dialog')), findsOneWidget);
    expect(find.textContaining('could not start the small helper'), findsOneWidget);
    final c = controllerOf(tester);
    expect(c.pending, isNotNull, reason: 'the download is kept');
    expect(PendingUpdate.read(p.join(tmp.path, 'state'))!.swapStartedAt, isNull,
        reason: 'a swap that never started is not "started"');
  });
}
