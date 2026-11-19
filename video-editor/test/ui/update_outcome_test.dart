// 1.14: what the app says at the first start after an update - one quiet
// line when it worked (with a sentence about a folder still named after
// the old version), a plain window with the reason, Try again and the
// download page when it did not - and the last step of the Update window.
import 'dart:io';

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';
import 'home_screen_test.dart' show someProjects;

const now142 = BuildInfo(version: '1.13.0', buildNumber: '142', channel: 'ci');
const old139 = BuildInfo(version: '1.12.0', buildNumber: '139', channel: 'ci');

void main() {
  setUpAll(loadFonts);
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_outcome_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Fakes> home(WidgetTester tester, Size size, BuildInfo build,
      {required String install, String? result, PendingUpdate? pending}) async {
    useScreen(tester, size);
    final fakes = Fakes(projects: someProjects())..buildInfo = build;
    fakes.updatePlatform
      ..os = 'windows'
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

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$label: updated: one quiet line, with the note about the '
        'folder name', (tester) async {
      final install = p.join(tmp.path, 'ClipForge-1.12.0');
      final fakes = await home(tester, size, now142,
          install: install,
          result: '{"status":"updated","message":"","version":"1.13.0"}');
      expect(find.byKey(const ValueKey('update-done-line')), findsOneWidget);
      expect(find.textContaining('Updated to 1.13.0.'), findsOneWidget);
      expect(find.textContaining('still called "ClipForge-1.12.0"'), findsOneWidget);
      expect(find.textContaining('rename it to "ClipForge" while ClipForge is closed'),
          findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(Directory(install).existsSync(), isTrue);
      await fakes.screenshot(tester, 'update_done_$label');
      // It goes away by itself.
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-done-line')), findsNothing);
    });

    testWidgets('$label: failed: the reason, Try again and the download page',
        (tester) async {
      final install = p.join(tmp.path, 'ClipForge');
      final newDir = '$install$kUpdateNewSuffix';
      Directory(newDir).createSync(recursive: true);
      writeUpdateMarker(newDir, 'windows');
      final fakes = await home(tester, size, old139,
          install: install,
          result: '{"status":"failed","message":"A file of ClipForge is still '
              'in use (is ClipForge or its Claude helper running from this '
              'folder?).","version":"1.13.0"}',
          pending: PendingUpdate(
                  version: '1.13.0', build: 142, installDir: install, newDir: newDir)
              .started(DateTime.utc(2026, 11, 19)));
      expect(find.byKey(const ValueKey('update-failed-dialog')), findsOneWidget);
      expect(find.text('The update was not installed'), findsOneWidget);
      expect(find.textContaining('still in use'), findsOneWidget);
      expect(find.textContaining('ClipForge is unchanged and works as before'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Open the download page'), findsOneWidget);
      await fakes.screenshot(tester, 'update_failed_$label');
      // Not now: the download goes, nothing else.
      await tester.tap(find.byKey(const ValueKey('update-failed-later')));
      await tester.pumpAndSettle();
      expect(Directory(newDir).existsSync(), isFalse);
      expect(Directory(install).existsSync(), isTrue);
      expect(fakes.updatePlatform.quits, 0);
    });
  }

  testWidgets('a quiet start: nothing is said, a marked leftover is removed, '
      'an unmarked one is not', (tester) async {
    final install = p.join(tmp.path, 'ClipForge');
    final ours = Directory('$install$kUpdateOldSuffix')..createSync(recursive: true);
    writeUpdateMarker(ours.path, 'windows');
    final theirs = Directory('$install$kUpdateNewSuffix')..createSync(recursive: true);
    await home(tester, desktop, now142, install: install);
    expect(find.byKey(const ValueKey('update-done-line')), findsNothing);
    expect(find.byKey(const ValueKey('update-failed-dialog')), findsNothing);
    expect(ours.existsSync(), isFalse);
    expect(theirs.existsSync(), isTrue);
  });
}
