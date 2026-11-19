// Putting an update in place (1.12): where the app is installed, unpacking
// next to it, and the swap script. The macOS / Linux script
// (assets/update/clipforge-update.sh) is RUN here with pretend app folders,
// including every failure path (nothing may ever be left half done). The
// Windows scripts (clipforge-update.ps1 and .cmd; since 1.14.1 they
// replace the folder's contents with robocopy instead of renaming it) are
// run by the Windows job of the build workflow
// (tool/ci/windows_swap_test.py) and only checked for consistency here.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:clipforge/core/update/update_log.dart';
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

    test('leftovers are removed only when the updater made them (marker); '
        'the result is read once', () {
      final app = p.join(tmp.path, 'ClipForge');
      for (final d in [app, '$app.update-old', '$app.update-new']) {
        File(p.join(d, 'x.txt')).createSync(recursive: true);
      }
      // No marker: somebody's own folders. Nothing is touched.
      var report = cleanUpdateLeftovers(app, 'windows');
      expect(report.removed, isEmpty);
      expect(report.foreign, ['$app.update-new', '$app.update-old']);
      expect(tmp.listSync().length, 3);
      // With the marker they are the updater's.
      writeUpdateMarker('$app.update-old', 'windows', version: '1.13.0');
      writeUpdateMarker('$app.update-new', 'windows');
      expect(hasUpdateMarker('$app.update-new', 'windows'), isTrue);
      // An update that is still waiting is kept.
      report = cleanUpdateLeftovers(app, 'windows', keep: {'$app.update-new'});
      expect(report.removed, ['$app.update-old']);
      expect(report.kept, ['$app.update-new']);
      report = cleanUpdateLeftovers(app, 'windows');
      expect(report.removed, ['$app.update-new']);
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['ClipForge']);
      expect(File(p.join(app, 'x.txt')).existsSync(), isTrue);

      // macOS: the marker is NEXT TO the bundle (nothing is added inside
      // a signed app), and goes with it.
      final bundle = p.join(tmp.path, 'ClipForge.app');
      Directory('$bundle.update-old').createSync(recursive: true);
      expect(cleanUpdateLeftovers(bundle, 'macos').foreign, ['$bundle.update-old']);
      writeUpdateMarker('$bundle.update-old', 'macos');
      expect(File('$bundle.update-old.marker').existsSync(), isTrue);
      expect(cleanUpdateLeftovers(bundle, 'macos').removed, ['$bundle.update-old']);
      expect(File('$bundle.update-old.marker').existsSync(), isFalse);
      // A marker whose folder is gone is tidied too.
      File('$bundle.update-new.marker').writeAsStringSync('{}');
      cleanUpdateLeftovers(bundle, 'macos');
      expect(File('$bundle.update-new.marker').existsSync(), isFalse);

      // Written by Windows PowerShell 5.1 with a byte order mark.
      File(p.join(tmp.path, kUpdateResultFile)).writeAsStringSync(
          '\uFEFF{"status":"updated","message":"","version":"1.13.0"}');
      final r = takeUpdateResult(tmp.path)!;
      expect([r.status, r.updated, r.version], ['updated', true, '1.13.0']);
      expect(takeUpdateResult(tmp.path), isNull, reason: 'shown once');
    });

    test('an update that is waiting is remembered on disk', () {
      final state = p.join(tmp.path, 'state');
      expect(PendingUpdate.read(state), isNull);
      const waiting = PendingUpdate(
          version: '1.14.0', build: 150, installDir: r'C:\Apps\ClipForge', newDir: r'C:\Apps\ClipForge.update-new');
      waiting.write(state);
      var back = PendingUpdate.read(state)!;
      expect([back.version, back.build, back.installDir, back.newDir, back.attempts],
          ['1.14.0', 150, r'C:\Apps\ClipForge', r'C:\Apps\ClipForge.update-new', 0]);
      expect(back.swapStartedAt, isNull);
      back.started(DateTime.utc(2026, 11, 19, 8)).write(state);
      back = PendingUpdate.read(state)!;
      expect(back.swapStartedAt, DateTime.utc(2026, 11, 19, 8));
      expect(back.attempts, 1);
      File(p.join(state, PendingUpdate.fileName)).writeAsStringSync('not json');
      expect(PendingUpdate.read(state), isNull);
      PendingUpdate.clear(state);
      expect(File(p.join(state, PendingUpdate.fileName)).existsSync(), isFalse);
    });

    test('what the app does at its start', () {
      const waiting = PendingUpdate(version: '1.14.0', build: 150, installDir: 'i', newDir: 'n');
      final started = waiting.started(DateTime.utc(2026));
      UpdateStartAction at(
              {UpdateResult? result,
              PendingUpdate? pending,
              int? build = 142,
              bool same = true,
              bool staged = true}) =>
          decideUpdateAtStart(
              result: result,
              pending: pending,
              currentBuild: build,
              sameInstall: same,
              stagedReady: staged);
      expect(at(), UpdateStartAction.tidy);
      expect(at(result: const UpdateResult('updated', '', '1.14.0'), pending: started),
          UpdateStartAction.reportUpdated);
      expect(at(result: const UpdateResult('failed', 'in use', '1.14.0'), pending: started),
          UpdateStartAction.reportFailed);
      // "Later", or the app was closed another way: finish it now.
      expect(at(pending: waiting), UpdateStartAction.applyNow);
      // The swap was started and nothing came back.
      expect(at(pending: started), UpdateStartAction.reportUnfinished);
      // It is the new version already (the result file was not written).
      expect(at(pending: started, build: 150), UpdateStartAction.reportUpdated);
      // The unpacked update is gone, or this is another copy of the app.
      expect(at(pending: waiting, staged: false), UpdateStartAction.tidy);
      expect(at(pending: waiting, same: false), UpdateStartAction.tidy);
    });

    test('a folder named after an older version gets one sentence', () {
      expect(folderNameNote(r'C:\Apps\ClipForge', '1.13.0', 'windows'), isNull);
      expect(folderNameNote(r'C:\Apps\ClipForge-1.13.0', '1.13.0', 'windows'), isNull);
      final note = folderNameNote(r'C:\Users\sam\ClipForge-1.12.0', '1.13.0', 'windows')!;
      expect(note, contains('"ClipForge-1.12.0"'));
      expect(note, contains('the app inside is 1.13.0'));
      expect(note, contains('rename it to "ClipForge" while ClipForge is closed'));
      expect(folderNameNote('/Applications/ClipForge.app', '1.13.0', 'macos'), isNull);
      expect(folderNameNote('/Users/sam/ClipForge 1.12.0/ClipForge.app', '1.13.0', 'macos'),
          contains('"ClipForge 1.12.0"'));
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
        'ClipForge/Read me first.html': 'guide',
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
        'Read me first.html': 'guide',
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

    test('something called .update-old that the updater did not make is '
        'never removed: nothing changes', () async {
      File(p.join('$install.update-old', 'my-notes.txt')).createSync(recursive: true);
      final r = await swap();
      expect(r.exitCode, 2);
      expect(versionIn(install), 'old');
      expect(versionIn(fresh), 'new');
      expect(File(p.join('$install.update-old', 'my-notes.txt')).existsSync(), isTrue);
      expect(readResult()['status'], 'failed');
      expect(readResult()['message'], contains('did not make'));
      expect(await started(), install);
    });

    test('the markers: the old app is marked while it steps aside, and '
        'nothing is left when it worked', () async {
      writeUpdateMarker(fresh, 'macos');
      // The roll-back that fails leaves the old app, WITH its marker.
      var r = await swap(mvWrapper: failingMv([2, 3]));
      expect(r.exitCode, 5);
      expect(hasUpdateMarker('$install.update-old', 'macos'), isTrue);
      // Put things back and let it work.
      Directory('$install.update-old').renameSync(install);
      File('$install.update-old.marker').deleteSync();
      File(p.join(tmp.path, 'mv-count')).deleteSync();
      File(result).deleteSync();
      r = await swap();
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(versionIn(install), 'new');
      final left = Directory(p.dirname(install)).listSync().map((e) => p.basename(e.path));
      expect(left, ['ClipForge.app'], reason: 'no folder and no marker is left');
    });

    test('an older leftover of the updater next to the app is cleared first', () async {
      File(p.join('$install.update-old', 'junk.txt')).createSync(recursive: true);
      writeUpdateMarker('$install.update-old', 'macos');
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

  group('the Windows scripts match what the app passes', () {
    final ps = File('assets/update/clipforge-update.ps1').readAsStringSync();
    final cmd = File('assets/update/clipforge-update.cmd').readAsStringSync();

    test('every value the app puts into the environment is read by both '
        'scripts, and all of them are always set', () {
      final env = swapEnvironment(
          installDir: r'C:\Apps\ClipForge',
          newDir: r'C:\Apps\ClipForge.update-new',
          waitPid: 4321,
          resultFile: r'C:\Temp\update-result.json',
          logFile: r'C:\Temp\update-log.txt',
          version: '1.14.1',
          token: 't1',
          scriptPath: r'C:\Temp\clipforge-update.ps1',
          workDir: r'C:\Temp');
      expect(env['CF_UPD_MODE'], 'update');
      expect(env['CF_UPD_REMOVE_LIST'], '', reason: 'never left over from an earlier run');
      expect(env['CF_UPD_PID'], '4321');
      for (final name in env.keys) {
        if (name == 'CF_UPD_SCRIPT' || name == 'CF_UPD_WORKDIR') {
          expect(kWindowsSwapStartScript, contains('\$env:$name'));
          continue;
        }
        expect(ps, contains("'$name'"), reason: '$name in the PowerShell script');
        expect(cmd, contains('%$name'), reason: '$name in the cmd script');
      }
      // The script is started outside the app's process tree, hidden.
      expect(kWindowsSwapStartScript, contains('Start-Process'));
      expect(kWindowsSwapStartScript, contains("'-ExecutionPolicy', 'Bypass'"));
      expect(kWindowsSwapStartScript, contains('-WindowStyle Hidden'));
    });

    test('both are plain ASCII, replace the contents with robocopy /MIR, '
        'never rename the app folder, roll back, and log', () {
      for (final (name, text) in [('ps1', ps), ('cmd', cmd)]) {
        expect(text.codeUnits.every((c) => c < 128), isTrue,
            reason: '$name: Windows reads a file without a BOM in the system code page');
        expect(text, contains('/MIR'), reason: name);
        expect(text, contains('/R:2'), reason: name);
        expect(text, contains('/W:1'), reason: name);
        expect(text, contains('update-old'), reason: name);
        expect(text, contains('.clipforge-update-marker'), reason: name);
        expect(text, contains(r'data\clipforge-version.json'), reason: name);
        expect(text, contains('started token='), reason: '$name: what the app waits for');
        expect(text.toLowerCase(), isNot(contains(r'documents\clipforge\')),
            reason: 'user data is mentioned only in the comment as "never touched"');
        // robocopy: below 8 is success.
        expect(RegExp(r'(-ge 8|GEQ 8)').hasMatch(text), isTrue, reason: name);
        expect(RegExp(r'(-lt 8|LSS 8)').hasMatch(text), isTrue, reason: name);
      }
      expect(ps, isNot(contains('Directory]::Move')),
          reason: 'the folder itself is never renamed (1.14.1)');
      expect(cmd, isNot(matches(RegExp(r'^\s*(ren|move)\s', multiLine: true))));
      expect(ps, contains("Write-Result 'updated'"));
      expect(ps, contains("Write-Result 'broken'"));
      expect(ps, contains("Mirror \$OldDir \$InstallDir 'putting the old version back'"));
      expect(cmd, contains('"%ROBO%" "%OLD%" "%CF_UPD_INSTALL%"'));
      // The same exit codes in all three scripts.
      final sh = File(_script).readAsStringSync();
      for (final code in [2, 3, 4, 5, 6, 0]) {
        expect(ps, contains('return $code'), reason: 'ps1 $code');
        expect(cmd, contains('exit $code'), reason: 'cmd $code');
        expect(sh, contains('exit $code'), reason: 'sh $code');
      }
    });

    test('the cmd script has no ( ) blocks and no delayed expansion outside '
        'its log helper, and its remarks hold no special characters', () {
      final lines = const LineSplitter().convert(cmd);
      for (final line in lines) {
        if (line.startsWith('rem')) {
          expect(RegExp(r'[<>|&%^]').hasMatch(line), isFalse, reason: line);
        }
        expect(line.trimRight().endsWith('('), isFalse, reason: 'a block: $line');
      }
      expect('EnableDelayedExpansion'.allMatches(cmd).length, 1);
      // Every label that is jumped to exists.
      final labels = {
        for (final l in lines)
          if (l.startsWith(':')) l.substring(1).trim().toLowerCase(),
      };
      for (final m in RegExp(r'(?:goto|call) :?([A-Za-z]\w*)').allMatches(cmd)) {
        final name = m[1]!.toLowerCase();
        if (name == 'eof') continue;
        expect(labels, contains(name), reason: 'label $name');
      }
    });
  });

  group('which ClipForge a folder holds', () {
    test('versions compare by version first, then by build', () {
      final v = AppVersion.parse('1.12.0+109')!;
      expect(v.name, '1.12.0');
      expect(v.build, 109);
      expect('$v', '1.12.0+109');
      expect(AppVersion.parse('1.12.0.109')!.build, 109, reason: 'the file version form');
      expect(AppVersion.parse('nonsense'), isNull);
      expect(v.isOlderThan(AppVersion.parse('1.13.0+118')!), isTrue);
      expect(AppVersion.parse('1.14.0+121')!.isOlderThan(AppVersion.parse('1.14.1+1')!), isTrue,
          reason: 'a build made on a PC has build 1 and is still newer');
      expect(AppVersion.parse('1.14.1+120')!.isOlderThan(AppVersion.parse('1.14.1+125')!), isTrue);
      expect(AppVersion.parse('1.14.1')!.isOlderThan(AppVersion.parse('1.14.1+125')!), isFalse,
          reason: 'unknown build: not proven older');
    });

    /// A pretend program with a version block like the real one.
    List<int> exeWith(String version, {int pad = 1}) => [
          ...List.filled(301, 0x4D),
          for (final c in 'ProductName'.codeUnits) ...[c, 0],
          0, 0, 0, 0,
          for (final c in 'ClipForge'.codeUnits) ...[c, 0],
          0, 0,
          for (final c in 'ProductVersion'.codeUnits) ...[c, 0],
          for (var i = 0; i < pad; i++) ...[0, 0],
          for (final c in version.codeUnits) ...[c, 0],
          0, 0, 9, 9, 9,
        ];

    test('the version is read from the program file itself', () {
      expect(productVersionOfExe(exeWith('1.12.0+109')), '1.12.0+109');
      expect(productVersionOfExe(exeWith('1.13.0+118', pad: 2)), '1.13.0+118');
      expect(productVersionOfExe(List.filled(500, 7)), isNull);
      expect(productVersionOfExe(const []), isNull);
    });

    test('the version file wins; no program, no version', () {
      final dir = p.join(tmp.path, 'ClipForge');
      Directory(p.join(dir, 'data')).createSync(recursive: true);
      expect(readInstalledVersion(dir), isNull, reason: 'no clipforge.exe');
      File(p.join(dir, 'clipforge.exe')).writeAsBytesSync(exeWith('1.12.0+109'));
      expect('${readInstalledVersion(dir)}', '1.12.0+109');
      File(versionFilePath(dir)).writeAsStringSync('{"version":"1.14.1+130"}\n');
      expect('${readInstalledVersion(dir)}', '1.14.1+130');
      File(versionFilePath(dir)).writeAsStringSync('not json');
      expect(readInstalledVersion(dir), isNull, reason: 'nothing is guessed');
      File(p.join(dir, 'clipforge.exe')).writeAsStringSync('no version in here');
      File(versionFilePath(dir)).deleteSync();
      expect(readInstalledVersion(dir), isNull);
    });
  });

  group('starting the swap script', () {
    late String work, install, fresh, result, log;
    setUp(() {
      work = p.join(tmp.path, 'state');
      install = p.join(tmp.path, 'Apps', 'ClipForge.app');
      fresh = '$install.update-new';
      result = p.join(work, kUpdateResultFile);
      log = p.join(work, kUpdateLogFile);
      Directory(work).createSync(recursive: true);
      for (final (d, v) in [(install, 'old'), (fresh, 'new')]) {
        File(p.join(d, 'version.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync(v);
      }
    });

    Future<Map<String, dynamic>> waitForResult() async {
      for (var i = 0; i < 100 && !File(result).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return (jsonDecode(File(result).readAsStringSync()) as Map).cast<String, dynamic>();
    }

    test('the real sh script reports in through the log, and the app is told '
        'it runs', () async {
      File(result).writeAsStringSync('{"status":"failed","message":"stale"}');
      // This test process plays the app and does not close: the script
      // waits its (shortened) time, then leaves everything alone.
      final started = await startSwap(
          os: 'macos',
          scriptText: File(_script).readAsStringSync().replaceFirst(
              r'${CLIPFORGE_UPDATE_WAIT_SECONDS:-60}', '1'),
          workDir: work,
          installDir: install,
          newDir: fresh,
          resultFile: result,
          logFile: log,
          version: '1.14.1');
      expect(started.confirmed, isTrue);
      expect(started.method, 'sh');
      final r = await waitForResult();
      expect(r['status'], 'failed', reason: 'the stale result was removed first');
      expect(r['message'], contains('did not close'));
      expect(File(p.join(install, 'version.txt')).readAsStringSync(), 'old');
      expect(File(p.join(fresh, 'version.txt')).readAsStringSync(), 'new');
      final text = File(log).readAsStringSync();
      expect(text, contains(' app: swap: mode=update version=1.14.1'));
      expect(text, contains('script(sh): started token='));
      expect(text, contains('script(sh): args: install=[$install]'));
      expect(text, contains(' app: the script is running (started by sh)'));
      expect(text, contains('script(sh): result: failed ClipForge did not close'));
    });

    test('a script that never reports in: not confirmed, said in the log; '
        'the next way is tried and the first that reports wins', () async {
      final tried = <String>[];
      SwapLauncher silent(String name) => SwapLauncher(name, () async {
            tried.add(name);
            return 'pretended';
          });
      var started = await startSwap(
          os: 'windows',
          scriptText: 'echo one\necho two\n',
          fallbackScriptText: '@echo off\nrem x\n',
          workDir: work,
          installDir: install,
          newDir: fresh,
          resultFile: result,
          logFile: log,
          version: '1.14.1',
          confirmTimeout: const Duration(milliseconds: 300),
          launchers: [silent('PowerShell'), silent('cmd')]);
      expect(started.confirmed, isFalse);
      expect(tried, ['PowerShell', 'cmd']);
      var text = File(log).readAsStringSync();
      expect(text, contains('the script did not report in within 0 s (started by PowerShell)'));
      expect(text, contains('no script could be started: the app stays open'));
      // The scripts were written with CRLF line ends (cmd needs them).
      expect(File(p.join(work, kSwapScriptCmd)).readAsStringSync(), '@echo off\r\nrem x\r\n');
      expect(File(p.join(work, kSwapScriptPs)).readAsStringSync(), 'echo one\r\necho two\r\n');

      // PowerShell is blocked (it throws), cmd works.
      tried.clear();
      started = await startSwap(
          os: 'windows',
          scriptText: 'x',
          fallbackScriptText: 'y',
          workDir: work,
          installDir: install,
          newDir: fresh,
          resultFile: result,
          logFile: log,
          version: '1.14.1',
          confirmTimeout: const Duration(seconds: 2),
          launchers: [
            SwapLauncher('PowerShell',
                () async => throw const ProcessException('powershell.exe', [], 'blocked')),
            SwapLauncher('cmd', () async {
              // What the cmd script does first: its line in the log.
              final token = RegExp(r'token=(\S+)')
                  .allMatches(File(log).readAsStringSync())
                  .last[1]!;
              File(log).writeAsStringSync(
                  'Thu 19/11/2026 12:00:00.00 script(cmd): started token=$token mode=update\r\n',
                  mode: FileMode.append);
              return 'exit code 0';
            }),
          ]);
      expect(started.confirmed, isTrue);
      expect(started.method, 'cmd');
      text = File(log).readAsStringSync();
      expect(text, contains('start by PowerShell failed'));
      expect(text, contains('the script is running (started by cmd)'));
    });

    test('Windows: PowerShell first, then cmd; cmd only when its script is there', () {
      List<String> names(bool withCmd) => [
            for (final l in swapLaunchers(
                os: 'windows',
                workDir: work,
                environment: const {},
                shArguments: const [],
                withCmd: withCmd))
              l.name,
          ];
      expect(names(true), ['PowerShell', 'cmd']);
      expect(names(false), ['PowerShell']);
    });
  });

  group('the swap script (sh), 1.14.1', () {
    test('an app that does not close is left alone: nothing is renamed', () async {
      final install = p.join(tmp.path, 'Apps', 'ClipForge.app');
      final fresh = '$install.update-new';
      final result = p.join(tmp.path, 'r.json');
      final log = p.join(tmp.path, 'update-log.txt');
      for (final (d, v) in [(install, 'old'), (fresh, 'new')]) {
        File(p.join(d, 'version.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync(v);
      }
      final marker = p.join(tmp.path, 'started.txt');
      final r = await Process.run('/bin/sh', [
        _script, install, fresh, '$pid', result, '1.14.1', //
        '/bin/sh', '-c', 'echo again > "$marker"',
      ], environment: {
        'CLIPFORGE_UPDATE_WAIT_SECONDS': '1',
        'CLIPFORGE_UPDATE_LOG': log,
        'CLIPFORGE_UPDATE_TOKEN': 'abc',
      });
      expect(r.exitCode, 6);
      expect(File(p.join(install, 'version.txt')).readAsStringSync(), 'old');
      expect(Directory(fresh).existsSync(), isTrue);
      expect(File(marker).existsSync(), isFalse, reason: 'the app is not started a second time');
      expect(File(result).readAsStringSync(), contains('did not close'));
      expect(File(log).readAsStringSync(), contains('started token=abc pid='));
    });
  });
}
