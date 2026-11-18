// Putting an update in place (1.12): where the app is installed, unpacking
// next to it, and the swap script. The macOS / Linux script
// (assets/update/clipforge-update.sh) is RUN here with pretend app folders,
// including every failure path (nothing may ever be left half done). The
// Windows script (clipforge-update.ps1) has the same steps; it is run by
// the Windows job of the build workflow (tool/ci/windows_swap_test.py) and
// only checked for consistency here.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _script = 'assets/update/clipforge-update.sh';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('clipforge_swap_test'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('where the app is', () {
    test('Windows: the folder of clipforge.exe; macOS: the .app bundle', () {
      expect(installDirOf(r'C:\Apps\ClipForge\clipforge.exe', 'windows'), r'C:\Apps\ClipForge');
      expect(installDirOf('/Applications/ClipForge.app/Contents/MacOS/clipforge', 'macos'),
          '/Applications/ClipForge.app');
      expect(installDirOf('/usr/local/bin/clipforge', 'macos'), isNull);
      expect(installDirOf('/opt/clipforge/clipforge', 'linux'), isNull);
    });

    test('macOS app translocation is recognised', () {
      const t = '/private/var/folders/ab/T/AppTranslocation/1234-AB/d/ClipForge.app';
      expect(isTranslocated(t), isTrue);
      expect(isTranslocated('/Applications/ClipForge.app'), isFalse);
      expect(replaceInPlaceProblem(t, 'macos'), contains('temporary place'));
    });

    test('a place that is missing or unknown cannot be replaced in place', () {
      expect(replaceInPlaceProblem(null, 'windows'), isNotNull);
      expect(replaceInPlaceProblem(p.join(tmp.path, 'nope'), 'windows'), contains('not found'));
      final app = Directory(p.join(tmp.path, 'ClipForge'))..createSync();
      expect(replaceInPlaceProblem(app.path, 'windows'), isNull);
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['ClipForge'],
          reason: 'the write test leaves nothing behind');
    });

    test('leftovers of an earlier update are removed; the result is read once', () {
      final app = p.join(tmp.path, 'ClipForge');
      for (final d in [app, '$app.update-old', '$app.update-new']) {
        File(p.join(d, 'x.txt')).createSync(recursive: true);
      }
      cleanUpdateLeftovers(app);
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['ClipForge']);

      // Written by Windows PowerShell 5.1 with a byte order mark.
      File(p.join(tmp.path, kUpdateResultFile)).writeAsStringSync(
          '\uFEFF{"status":"updated","message":"","version":"1.13.0"}');
      final r = takeUpdateResult(tmp.path)!;
      expect([r.status, r.updated, r.version], ['updated', true, '1.13.0']);
      expect(takeUpdateResult(tmp.path), isNull, reason: 'shown once');
    });
  });

  group('unpacking next to the app', () {
    Future<String> zipOf(Map<String, String> files) async {
      final path = p.join(tmp.path, 'update.zip');
      final encoder = ZipFileEncoder()..create(path);
      for (final e in files.entries) {
        encoder.addArchiveFile(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
      }
      await encoder.close();
      return path;
    }

    test('Windows zip: the folder with clipforge.exe becomes <install>.update-new', () async {
      final app = Directory(p.join(tmp.path, 'My ClipForge'))..createSync();
      File(p.join(app.path, 'clipforge.exe')).writeAsStringSync('old');
      final zip = await zipOf({
        'ClipForge/clipforge.exe': 'new',
        'ClipForge/data/app.so': 'code',
        'ClipForge/Release notes.txt': 'notes',
      });
      final staged = await stageWindowsUpdate(zip, app.path);
      expect(staged, '${app.path}.update-new');
      expect(File(p.join(staged, 'clipforge.exe')).readAsStringSync(), 'new');
      expect(File(p.join(staged, 'data', 'app.so')).existsSync(), isTrue);
      expect(File(p.join(app.path, 'clipforge.exe')).readAsStringSync(), 'old',
          reason: 'the installed app is not touched by unpacking');
      expect(Directory('${app.path}.update-unpack').existsSync(), isFalse);
    });

    test('a zip without the app is refused and leaves nothing', () async {
      final app = Directory(p.join(tmp.path, 'ClipForge'))..createSync();
      final zip = await zipOf({'readme.txt': 'hello'});
      await expectLater(stageWindowsUpdate(zip, app.path),
          throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', 'check')));
      expect(tmp.listSync().map((e) => p.basename(e.path)).toSet(), {'ClipForge', 'update.zip'});
    });

    test('macOS zip: the .app inside becomes <bundle>.update-new', () async {
      final app = Directory(p.join(tmp.path, 'ClipForge.app'))..createSync();
      final zip = await zipOf({
        'ClipForge.app/Contents/MacOS/clipforge': 'new',
        'Release notes.txt': 'notes',
      });
      // ditto is macOS only; any unzip shows the same logic.
      Future<ProcessResult> unzip(String z, String d) async {
        await extractFileToDisk(z, d);
        return ProcessResult(0, 0, '', '');
      }

      final staged = await stageMacUpdate(zip, app.path, unzip: unzip);
      expect(staged, '${app.path}.update-new');
      expect(File(p.join(staged, 'Contents', 'MacOS', 'clipforge')).readAsStringSync(), 'new');
      await expectLater(
          stageMacUpdate(await zipOf({'x.txt': '1'}), app.path, unzip: unzip),
          throwsA(isA<UpdateException>()));
    });
  });

  group('the swap script (sh)', () {
    late String install, fresh, result, marker, userData;

    setUp(() {
      install = p.join(tmp.path, 'Apps', 'ClipForge.app');
      fresh = '$install.update-new';
      result = p.join(tmp.path, 'state', 'update-result.json');
      marker = p.join(tmp.path, 'started.txt');
      userData = p.join(tmp.path, 'Documents', 'ClipForge', 'projects', 'p1', 'project.json');
      File(p.join(install, 'version.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      File(p.join(fresh, 'version.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('new');
      Directory(p.dirname(result)).createSync(recursive: true);
      File(userData)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"name":"Holiday"}');
    });

    /// Runs the script; the "restart" writes which folder it would start.
    Future<ProcessResult> swap(
        {int waitPid = 0, String? mvWrapper, String version = '1.13.0'}) {
      final env = <String, String>{...Platform.environment};
      if (mvWrapper != null) {
        final bin = Directory(p.join(tmp.path, 'fakebin'))..createSync();
        final mv = File(p.join(bin.path, 'mv'))..writeAsStringSync(mvWrapper);
        Process.runSync('chmod', ['755', mv.path]);
        env['PATH'] = '${bin.path}:${env['PATH']}';
        env['MV_COUNT_FILE'] = p.join(tmp.path, 'mv-count');
      }
      return Process.run(
          '/bin/sh',
          [
            _script, install, fresh, '$waitPid', result, version, //
            '/bin/sh', '-c', 'echo "\$CLIPFORGE_APP_DIR" > "$marker"',
          ],
          environment: env);
    }

    Map<String, dynamic> readResult() =>
        (jsonDecode(File(result).readAsStringSync()) as Map).cast<String, dynamic>();
    String versionIn(String dir) => File(p.join(dir, 'version.txt')).readAsStringSync();
    Future<String> started() async {
      for (var i = 0; i < 50 && !File(marker).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return File(marker).readAsStringSync().trim();
    }

    /// A pretend `mv` that fails on the calls listed in [failOn] (1-based).
    String failingMv(List<int> failOn) => '#!/bin/sh\n'
        'n=\$(cat "\$MV_COUNT_FILE" 2>/dev/null || echo 0)\n'
        'n=\$((n + 1))\n'
        'echo \$n > "\$MV_COUNT_FILE"\n'
        'case " ${failOn.join(' ')} " in *" \$n "*) exit 1;; esac\n'
        'exec /bin/mv "\$@"\n';

    test('waits for the app to close, swaps, restarts, tidies up', () async {
      // The "running app".
      final app = await Process.start('sleep', ['30']);
      final run = swap(waitPid: app.pid);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(versionIn(install), 'old', reason: 'nothing happens while the app runs');
      expect(File(result).existsSync(), isFalse);
      app.kill();
      await app.exitCode;
      final r = await run;
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(versionIn(install), 'new');
      expect(readResult(), containsPair('status', 'updated'));
      expect(readResult(), containsPair('version', '1.13.0'));
      expect(await started(), install, reason: 'the new app is started');
      expect(Directory('$install.update-old').existsSync(), isFalse);
      expect(Directory(fresh).existsSync(), isFalse);
      expect(File(userData).readAsStringSync(), '{"name":"Holiday"}',
          reason: 'projects are never touched');
    });

    test('the download is incomplete: nothing changes, the old app starts again', () async {
      Directory(fresh).deleteSync(recursive: true);
      final r = await swap();
      expect(r.exitCode, 2);
      expect(versionIn(install), 'old');
      expect(readResult(), containsPair('status', 'failed'));
      expect(await started(), install);
    });

    test('the old app cannot be moved: nothing has changed', () async {
      final r = await swap(mvWrapper: failingMv([1]));
      expect(r.exitCode, 3);
      expect(versionIn(install), 'old');
      expect(versionIn(fresh), 'new', reason: 'the download stays for another try');
      expect(readResult()['status'], 'failed');
      expect(Directory('$install.update-old').existsSync(), isFalse);
      expect(await started(), install);
    });

    test('the new app cannot be moved in: the old one is put back', () async {
      final r = await swap(mvWrapper: failingMv([2]));
      expect(r.exitCode, 4);
      expect(versionIn(install), 'old', reason: 'rolled back');
      expect(readResult()['status'], 'failed');
      expect(readResult()['message'], contains('unchanged'));
      expect(Directory('$install.update-old').existsSync(), isFalse);
      expect(await started(), install);
    });

    test('even when the roll-back fails there is a complete, working app', () async {
      final r = await swap(mvWrapper: failingMv([2, 3]));
      expect(r.exitCode, 5);
      final old = '$install.update-old';
      expect(versionIn(old), 'old', reason: 'the old app is whole, only renamed');
      expect(readResult()['status'], 'broken');
      expect(readResult()['message'], contains(old));
      expect(await started(), old, reason: 'and it is the one that is started');
    });

    test('an older leftover next to the app is cleared first', () async {
      File(p.join('$install.update-old', 'junk.txt')).createSync(recursive: true);
      final r = await swap();
      expect(r.exitCode, 0);
      expect(versionIn(install), 'new');
      expect(Directory('$install.update-old').existsSync(), isFalse);
    });

    test('quotes and backslashes in a path do not break the result file', () async {
      final odd = p.join(tmp.path, 'Apps', 'Clip "Forge".app');
      Directory(install).renameSync(odd);
      Directory(fresh).renameSync('$odd.update-new');
      install = odd;
      fresh = '$odd.update-new';
      final r = await swap(mvWrapper: failingMv([2, 3]));
      expect(r.exitCode, 5);
      expect(readResult()['message'], contains('Clip "Forge".app.update-old'));
    });
  });

  group('the Windows script matches what the app passes', () {
    final ps = File('assets/update/clipforge-update.ps1').readAsStringSync();

    test('every argument the app passes is a parameter of the script', () {
      final cmd = swapCommand(
          os: 'windows',
          scriptPath: r'C:\Temp\clipforge-update.ps1',
          installDir: r'C:\Apps\ClipForge',
          newDir: r'C:\Apps\ClipForge.update-new',
          waitPid: 4321,
          resultFile: r'C:\Temp\update-result.json',
          version: '1.13.0');
      expect(cmd.executable, 'powershell.exe');
      expect(cmd.arguments, containsAllInOrder(['-File', r'C:\Temp\clipforge-update.ps1']));
      final passed = [
        for (final a in cmd.arguments.skip(cmd.arguments.indexOf('-File') + 2))
          if (RegExp(r'^-[A-Z]').hasMatch(a)) a.substring(1),
      ];
      expect(passed, ['InstallDir', 'NewDir', 'WaitPid', 'ExeName', 'ResultFile', 'Version']);
      final params = ps.substring(ps.indexOf('param('), ps.indexOf(r"$ErrorActionPreference"));
      for (final name in passed) {
        expect(params, contains('\$$name'), reason: '-$name');
      }
    });

    test('it is plain ASCII, rolls back, and names only the three folders', () {
      expect(ps.codeUnits.every((c) => c < 128), isTrue,
          reason: 'Windows PowerShell 5.1 reads files without a BOM as ANSI');
      expect(ps, contains('update-old'));
      expect(ps, contains("Write-Result 'updated'"));
      expect(ps, contains("Write-Result 'broken'"));
      expect('Move-Folder \$OldDir \$InstallDir'.allMatches(ps).length, 1, reason: 'the roll-back');
      expect(ps.toLowerCase(), isNot(contains('documents\\clipforge\\')),
          reason: 'user data is mentioned only in the comment as "never touched"');
      // The same steps and exit codes as the sh script.
      final sh = File(_script).readAsStringSync();
      for (final code in ['exit 2', 'exit 3', 'exit 4', 'exit 5', 'exit 0']) {
        expect(ps, contains(code));
        expect(sh, contains(code));
      }
    });

    test('macOS: the script is run by /bin/sh with the same five values', () {
      final cmd = swapCommand(
          os: 'macos',
          scriptPath: '/tmp/s.sh',
          installDir: '/Applications/ClipForge.app',
          newDir: '/Applications/ClipForge.app.update-new',
          waitPid: 77,
          resultFile: '/tmp/r.json',
          version: '1.13.0');
      expect(cmd.executable, '/bin/sh');
      expect(cmd.arguments, [
        '/tmp/s.sh', '/Applications/ClipForge.app', //
        '/Applications/ClipForge.app.update-new', '77', '/tmp/r.json', '1.13.0',
      ]);
    });
  });
}
