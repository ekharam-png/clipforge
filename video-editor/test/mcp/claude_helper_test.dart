// The Claude helper at a stable place (1.12): the app installs each
// version into its own folder and switches `current.json`; whatever copy
// Claude starts hands over to the current one. Tested here with small
// pretend "helpers" (text files / shell scripts); test/mcp/e2e_test.dart
// does the hand-over with the real compiled program.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clipforge/core/claude/helper_install.dart';
import 'package:clipforge/mcp/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A pretend extension file whose helper is [program].
List<int> bundleOf(String program, {String exe = 'clipforge-mcp'}) {
  final a = Archive()
    ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode('{}')))
    ..addFile(ArchiveFile.bytes('server/$exe', utf8.encode(program)))
    ..addFile(ArchiveFile.bytes('server/fonts/DejaVuSans.ttf', [1, 2, 3]))
    ..addFile(ArchiveFile.bytes('server/../evil.txt', [6]))
    ..addFile(ArchiveFile.bytes('icon.png', [9]));
  return ZipEncoder().encode(a);
}

void main() {
  late Directory tmp;
  late String dir;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipforge_helper_test');
    dir = p.join(tmp.path, 'ClipForge', 'claude');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<HelperInstallResult> install(String program, {int build = 142, String version = '1.12.0'}) =>
      installClaudeHelper(
          stableDir: dir,
          bundleBytes: bundleOf(program),
          version: version,
          build: build,
          os: 'linux',
          display: 'ClipForge $version (build $build)');

  test('the folder per system', () {
    expect(
        claudeStableDir('windows', {'LOCALAPPDATA': r'C:\Users\sam\AppData\Local'}),
        r'C:\Users\sam\AppData\Local\ClipForge\claude');
    expect(claudeStableDir('windows', {'USERPROFILE': r'C:\Users\sam'}),
        r'C:\Users\sam\AppData\Local\ClipForge\claude');
    expect(claudeStableDir('macos', {'HOME': '/Users/sam'}),
        '/Users/sam/Library/Application Support/ClipForge/claude');
    expect(claudeStableDir('linux', {'HOME': '/home/sam'}),
        '/home/sam/.local/share/ClipForge/claude');
    expect(claudeStableDir('android', {'HOME': '/x'}), isNull);
    expect(claudeStableDir('windows', const {}), isNull);
    expect(helperExeName('windows'), 'clipforge-mcp.exe');
    expect(claudeCodeCommand(r'C:\Users\sam\AppData\Local\ClipForge\claude\clipforge-mcp.exe'),
        r'claude mcp add --scope user clipforge -- "C:\Users\sam\AppData\Local\ClipForge\claude\clipforge-mcp.exe"');
  });

  test('first install: a version folder, current.json and the stable path', () async {
    expect(helperStatus(dir, 'linux').installed, isFalse);
    final r = await install('helper v1');
    expect(r.changed, isTrue);
    expect(r.launcherPath, p.join(dir, 'clipforge-mcp'));
    expect(p.isWithin(p.join(dir, 'versions'), r.currentPath), isTrue);
    expect(File(r.currentPath).readAsStringSync(), 'helper v1');
    expect(File(r.launcherPath).readAsStringSync(), 'helper v1');
    expect(File(p.join(p.dirname(r.currentPath), 'fonts', 'DejaVuSans.ttf')).existsSync(), isTrue,
        reason: 'the title fonts sit next to the helper');
    expect(File(p.join(dir, 'versions', 'evil.txt')).existsSync(), isFalse,
        reason: 'entries cannot climb out of the folder');
    // Runnable.
    expect(File(r.currentPath).statSync().modeString(), startsWith('rwx'));
    expect(File(r.launcherPath).statSync().modeString(), startsWith('rwx'));
    final current = HelperCurrent.read(dir)!;
    expect([current.version, current.build, current.path], ['1.12.0', 142, r.currentPath]);
    final status = helperStatus(dir, 'linux');
    expect(status.installed, isTrue);
  });

  test('the same app again changes nothing; a new version switches over', () async {
    final first = await install('helper v1');
    final again = await install('helper v1');
    expect(again.changed, isFalse);
    expect(again.currentPath, first.currentPath);

    final second = await install('helper v2', build: 150, version: '1.13.0');
    expect(second.changed, isTrue);
    expect(second.currentPath, isNot(first.currentPath));
    expect(File(second.currentPath).readAsStringSync(), 'helper v2');
    expect(HelperCurrent.read(dir)!.build, 150);
    expect(File(second.launcherPath).readAsStringSync(), 'helper v2',
        reason: 'the stable path is refreshed when it can be');
    expect(File(first.currentPath).existsSync(), isTrue,
        reason: 'the version Claude may still be running stays one update longer');

    final third = await install('helper v3', build: 160, version: '1.14.0');
    expect(File(first.currentPath).existsSync(), isFalse, reason: 'two updates back: removed');
    expect(File(second.currentPath).existsSync(), isTrue);
    expect(File(third.currentPath).readAsStringSync(), 'helper v3');
    expect(
        Directory(dir).listSync().whereType<File>().map((f) => p.basename(f.path)).toSet(),
        {'clipforge-mcp', 'current.json'},
        reason: 'no renamed-away copies or temp files are left');
  });

  test('a stable-path copy that cannot be replaced is no problem', () async {
    await install('helper v1');
    // "In use": the stable path is a folder here, so neither rename-over
    // nor copy can replace it the normal way... make it un-renamable by
    // being a non-empty directory with the same name.
    final launcher = p.join(dir, 'clipforge-mcp');
    File(launcher).deleteSync();
    Directory(launcher).createSync();
    File(p.join(launcher, 'busy')).writeAsStringSync('x');
    final r = await install('helper v2', build: 150);
    expect(r.changed, isTrue, reason: 'the new version is in place regardless');
    expect(File(r.currentPath).readAsStringSync(), 'helper v2');
    expect(HelperCurrent.read(dir)!.build, 150);
  });

  test('a damaged extension file leaves the old helper current', () async {
    final first = await install('helper v1');
    await expectLater(
        installClaudeHelper(
            stableDir: dir, bundleBytes: [1, 2, 3, 4], version: '9', build: 999, os: 'linux'),
        throwsA(anything));
    final noHelper = ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('manifest.json', [1])));
    await expectLater(
        installClaudeHelper(
            stableDir: dir, bundleBytes: noHelper, version: '9', build: 999, os: 'linux'),
        throwsA(isA<FormatException>()));
    expect(HelperCurrent.read(dir)!.path, first.currentPath);
    expect(Directory(p.join(dir, 'versions')).listSync().length, 1,
        reason: 'no half-unpacked version stays behind');
  });

  group('hand-over', () {
    Map<String, String> env() => {'XDG_DATA_HOME': tmp.path};

    test('to the installed helper when it is at least as new and a different file', () async {
      final r = await install('helper', build: 142);
      final other = p.join(tmp.path, 'extension', 'clipforge-mcp');
      File(other)
        ..createSync(recursive: true)
        ..writeAsStringSync('bundled copy');
      HelperCurrent? choose(String self, int own, [Map<String, String>? e]) =>
          chooseHandOver(selfPath: self, ownBuild: own, env: e ?? env(), os: 'linux');

      expect(choose(other, 139)?.path, r.currentPath, reason: 'older copy in the extension');
      expect(choose(other, 142)?.path, r.currentPath, reason: 'same build: the installed one');
      expect(choose(r.launcherPath, 142)?.path, r.currentPath, reason: 'the stable path hands over');
      expect(choose(other, 150), isNull, reason: 'this copy is newer than what the app installed');
      expect(choose(r.currentPath, 142), isNull, reason: 'it is the current one itself');
      expect(choose(other, 139, {...env(), kEnvNoHandOver: '1'}), isNull);
      expect(choose(other, 139, {...env(), kEnvStartedBy: '/x'}), isNull, reason: 'no loops');
      expect(choose('/usr/lib/dart/bin/dart', 0), isNull, reason: 'running from source');
      expect(choose(other, 139, {'XDG_DATA_HOME': p.join(tmp.path, 'empty')}), isNull,
          reason: 'the app never installed a helper');
      File(r.currentPath).deleteSync();
      expect(choose(other, 139), isNull, reason: 'the installed file is gone');
    });

    test('the started program gets the arguments and says who started it', () async {
      final out = p.join(tmp.path, 'out.txt');
      final r = await install(
          '#!/bin/sh\necho "\$CLIPFORGE_MCP_STARTED_BY|\$*" > "$out"\nexit 7\n');
      final code = await runHandedOver(HelperCurrent.read(dir)!, ['--projects-dir', '/p q'],
          selfPath: '/ext/clipforge-mcp');
      expect(code, 7, reason: 'its exit code is passed on');
      expect(File(out).readAsStringSync().trim(), '/ext/clipforge-mcp|--projects-dir /p q');
      expect(r.changed, isTrue);
      // A program that cannot be started: the caller runs itself.
      expect(
          await runHandedOver(
              HelperCurrent(version: '1', build: 1, path: p.join(tmp.path, 'missing')), const [],
              selfPath: '/ext/x'),
          isNull);
    });

    test('get_status says which helper runs and whether the app installed it', () async {
      final none = helperReport(environment: {'XDG_DATA_HOME': p.join(tmp.path, 'none')}, os: 'linux');
      expect(none['installedByApp'], isNull);
      expect(helperReportText(none), contains('has not installed a helper there yet'));
      await install('helper', build: 142);
      final report = helperReport(
          environment: {...env(), kEnvStartedBy: '/ext/clipforge-mcp'}, os: 'linux');
      expect(report['program'], Platform.resolvedExecutable);
      expect(report['stableFolder'], dir);
      expect(report['stablePathInstalled'], isTrue);
      expect((report['installedByApp'] as Map)['build'], 142);
      expect(report['isCurrent'], isFalse);
      final text = helperReportText(report);
      expect(text, contains('started through /ext/clipforge-mcp'));
      expect(text, contains('the app installed 1.12.0 (build 142)'));
    });
  });
}
