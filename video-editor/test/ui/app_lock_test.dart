// The "open in the app" mark (.open-in-app) follows the editor that is
// really open: opening project A, going back to the list and opening B
// must leave B marked and A not, and the list itself marks nothing.
// (Owner's Claude control test 3, 1.9.0: the mark stayed on the first
// project of the session. The 1.9 test only showed one editor alone and
// took it away - it never went back to the list or opened a second
// project, so it could not see a mark that outlives its editor.)
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/storage/project_lock.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('one mark per open editor: A, list, B, list', (tester) async {
    useScreen(tester, desktop);
    final dir = Directory.systemTemp.createTempSync('clipforge_lock2');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final id in ['a', 'b']) {
      Directory('${dir.path}/$id').createSync();
    }
    final fakes = Fakes(projects: [
      sampleProject(id: 'a', name: 'Empty one').copyWith(clips: const []),
      sampleProject(id: 'b', name: 'T3 Podcast'),
    ], missing: const {})
      ..lockRoot = dir.path;
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    bool marked(String id) => File('${dir.path}/$id/$kAppLockFileName').existsSync();
    ProjectLockInfo info(String id) => ProjectLockInfo.fromJson(jsonDecode(
        File('${dir.path}/$id/$kAppLockFileName').readAsStringSync()))!;
    expect([marked('a'), marked('b')], [false, false]);

    await tester.tap(find.text('Empty one'));
    await tester.pumpAndSettle();
    expect([marked('a'), marked('b')], [true, false]);
    final tokenA = info('a').token;

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect([marked('a'), marked('b')], [false, false],
        reason: 'the project list marks nothing');
    // No heartbeat brings A's mark back while the list is shown.
    await tester.pump(const Duration(minutes: 3));
    expect(marked('a'), isFalse);

    await tester.tap(find.text('T3 Podcast'));
    await tester.pumpAndSettle();
    expect([marked('a'), marked('b')], [false, true]);
    expect(info('b').token, isNot(tokenA));
    final opened = info('b').openedAt;
    // The heartbeat renews B's mark, and only B's.
    await tester.pump(const Duration(minutes: 2));
    expect([marked('a'), marked('b')], [false, true]);
    expect(info('b').openedAt, opened);

    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 3));
    expect([marked('a'), marked('b')], [false, false]);
  });

  test('a new lock ends any other lock of this app, heartbeat included',
      () async {
    final dir = Directory.systemTemp.createTempSync('clipforge_lock3');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final id in ['a', 'b']) {
      Directory('${dir.path}/$id').createSync();
    }
    File mark(String id) => File('${dir.path}/$id/$kAppLockFileName');
    const beat = Duration(milliseconds: 30);
    // The editor of A never cleans up (as when its dispose is cut short).
    final a = AppProjectLock('${dir.path}/a', heartbeat: beat)..acquire();
    expect(mark('a').existsSync(), isTrue);
    final b = AppProjectLock('${dir.path}/b', heartbeat: beat)..acquire();
    expect(a.isHeld, isFalse);
    expect(mark('a').existsSync(), isFalse);
    expect(mark('b').existsSync(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(mark('a').existsSync(), isFalse, reason: 'no heartbeat for A');
    expect((await checkProjectLock('${dir.path}/b')).state, ProjectLockState.held);
    b.release();
    expect(mark('b').existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(mark('b').existsSync(), isFalse);
    // Releasing twice, or a lock that was replaced, is harmless.
    a.release();
    b.release();
  });
}
