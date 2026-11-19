// 1.14.1: the tidy-up plan for an app that runs from a folder the updater
// unpacked into ("ClipForge-1.12.0.update-new.update-new", what 1.12 -
// 1.14 left on real PCs). Real folders in a temp place stand in for the
// PC; clipforge.exe is a small file with a version block like the real
// one, or the folder has the version file. Nothing may be offered for
// removal that is not PROVEN to be an older ClipForge.

import 'dart:io';

import 'package:clipforge/core/update/tidy_up.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A pretend clipforge.exe whose version details say [version].
List<int> exeWith(String version) => [
      ...List.filled(64, 0x4D),
      for (final c in 'ProductVersion'.codeUnits) ...[c, 0],
      0, 0,
      for (final c in version.codeUnits) ...[c, 0],
      0, 0,
    ];

/// Makes a ClipForge folder; [versionFile] also writes the 1.14.1 file.
String makeInstall(String parent, String name, String version, {bool versionFile = false}) {
  final dir = p.join(parent, name);
  Directory(p.join(dir, 'data')).createSync(recursive: true);
  File(p.join(dir, 'clipforge.exe')).writeAsBytesSync(exeWith(version));
  if (versionFile) {
    File(versionFilePath(dir)).writeAsStringSync('{"version":"$version"}\n');
  }
  return dir;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_tidy_test'));
  tearDown(() => tmp.deleteSync(recursive: true));
  final v1141 = AppVersion.parse('1.14.1+130')!;

  test('names: the endings are counted and taken off', () {
    expect(stagedName('ClipForge'), (base: 'ClipForge', depth: 0));
    expect(stagedName('ClipForge-1.12.0.update-new'), (base: 'ClipForge-1.12.0', depth: 1));
    expect(stagedName('ClipForge-1.12.0.update-new.UPDATE-NEW.update-new'),
        (base: 'ClipForge-1.12.0', depth: 3));
    expect(stagedName('.update-new'), (base: '.update-new', depth: 0));
    expect(stagedName('ClipForge.update-old'), (base: 'ClipForge.update-old', depth: 0));
  });

  test('an app in its own folder has nothing to tidy', () {
    final dir = makeInstall(tmp.path, 'ClipForge', '1.14.1+130');
    expect(planTidyUp(installDir: dir, current: v1141), isNull);
    final named = makeInstall(tmp.path, 'ClipForge-1.12.0', '1.14.1+130');
    expect(planTidyUp(installDir: named, current: v1141), isNull,
        reason: 'only a name with a version: that is not a download folder');
  });

  test('what was found on the real PC: three folders, each one version newer', () {
    final a = makeInstall(tmp.path, 'ClipForge-1.12.0', '1.12.0+109');
    final b = makeInstall(tmp.path, 'ClipForge-1.12.0.update-new', '1.13.0+118');
    final c = makeInstall(tmp.path, 'ClipForge-1.12.0.update-new.update-new', '1.14.0+121');
    final running = makeInstall(
        tmp.path, 'ClipForge-1.12.0.update-new.update-new.update-new', '1.14.1+130',
        versionFile: true);
    // Things that must never be listed.
    final other = makeInstall(tmp.path, 'OtherApp', '0.1.0+1');
    final notes = Directory(p.join(tmp.path, 'ClipForge-1.12.0 notes'))..createSync();
    final plan = planTidyUp(installDir: running, current: v1141)!;
    expect(plan.runningName, 'ClipForge-1.12.0.update-new.update-new.update-new');
    expect([for (final t in plan.targets) (t.name, t.state)], [
      ('ClipForge', TidyTargetState.free),
      ('ClipForge-1.12.0', TidyTargetState.olderClipForge),
    ]);
    expect(plan.defaultTarget!.name, 'ClipForge');
    expect(plan.targets[1].version!.name, '1.12.0');
    expect([for (final o in plan.older) (o.path, '${o.version}')], [
      (a, '1.12.0+109'),
      (b, '1.13.0+118'),
      (c, '1.14.0+121'),
    ]);
    // Moving to "ClipForge": all three older ones can go.
    expect(plan.removable(plan.targets[0]).length, 3);
    // Moving into the original folder: that one is brought up to date,
    // not removed.
    expect([for (final o in plan.removable(plan.targets[1])) o.name],
        ['ClipForge-1.12.0.update-new', 'ClipForge-1.12.0.update-new.update-new']);
    expect(plan.older.any((o) => o.path == other || o.path == notes.path), isFalse);
    // Nothing was changed by planning.
    expect(tmp.listSync().length, 6);
    expect(File(p.join(running, '.clipforge-update-marker')).existsSync(), isFalse);
  });

  test('never listed: same or newer versions, folders without the program, '
      'unreadable versions, other names', () {
    final running = makeInstall(tmp.path, 'App.update-new', '1.14.1+130');
    makeInstall(tmp.path, 'App', '1.14.1+130'); // the same version
    makeInstall(tmp.path, 'App.update-new.update-new', '1.15.0+140'); // newer
    Directory(p.join(tmp.path, 'App.update-new.update-new.update-new', 'data'))
        .createSync(recursive: true); // no program
    final odd = p.join(tmp.path, 'App.UPDATE-NEW.update-new.update-new.update-new');
    Directory(odd).createSync();
    File(p.join(odd, 'clipforge.exe')).writeAsStringSync('no version details');
    makeInstall(tmp.path, 'App2', '1.0.0+1'); // another name
    makeInstall(tmp.path, 'App.update-old', '1.0.0+1'); // not this kind of folder
    final plan = planTidyUp(installDir: running, current: v1141)!;
    expect(plan.older, isEmpty);
    expect([for (final t in plan.targets) (t.name, t.state)], [
      ('ClipForge', TidyTargetState.free),
      ('App', TidyTargetState.taken),
    ]);
    expect(plan.targets[1].usable, isFalse);
  });

  test('"ClipForge" is taken by something else: the original name is offered; '
      'when both are taken there is no place', () {
    final running = makeInstall(tmp.path, 'ClipForge-1.12.0.update-new', '1.14.1+130');
    final theirs = Directory(p.join(tmp.path, 'ClipForge'))..createSync();
    File(p.join(theirs.path, 'holiday.txt')).writeAsStringSync('mine');
    var plan = planTidyUp(installDir: running, current: v1141)!;
    expect(plan.targets[0].state, TidyTargetState.taken);
    expect(plan.defaultTarget!.name, 'ClipForge-1.12.0');
    expect(plan.defaultTarget!.state, TidyTargetState.free);
    // A FILE with the original name.
    File(p.join(tmp.path, 'ClipForge-1.12.0')).writeAsStringSync('x');
    plan = planTidyUp(installDir: running, current: v1141)!;
    expect(plan.targets.every((t) => !t.usable), isTrue);
    expect(plan.defaultTarget, isNull);
  });

  test('"ClipForge" holds an older ClipForge: it is the place, and is not '
      'in the list of folders to remove', () {
    final base = makeInstall(tmp.path, 'ClipForge', '1.13.0+118');
    final running = makeInstall(tmp.path, 'ClipForge.update-new', '1.14.1+130');
    final plan = planTidyUp(installDir: running, current: v1141)!;
    expect(plan.targets.length, 1, reason: 'the original name IS "ClipForge"');
    expect(plan.targets.single.state, TidyTargetState.olderClipForge);
    expect(plan.older.single.path, base);
    expect(plan.removable(plan.targets.single), isEmpty);
  });
}
