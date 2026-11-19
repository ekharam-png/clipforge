// 1.14 "Connect to Claude" done by the app: finding Claude Code and Claude
// Desktop (also the Microsoft Store build), reading what `claude mcp`
// answers (recorded-style outputs, written from memory - see the note in
// lib/core/claude/connect.dart), editing Claude Desktop's settings file
// without touching anything but the clipforge entry, backups, refusing
// files that are not plain JSON, and whether the helper is in use.
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/claude/connect.dart';
import 'package:clipforge/mcp/heartbeat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'connect_support.dart';

String fx(String name) =>
    File(p.join('test', 'core', 'fixtures', 'claude', name)).readAsStringSync();

const launcher = r'C:\Users\sam\AppData\Local\ClipForge\claude\clipforge-mcp.exe';
const claudeCmd = r'C:\Users\sam\AppData\Roaming\npm\claude.cmd';
const desktopDir = r'C:\Users\sam\AppData\Roaming\Claude';
const desktopFile = '$desktopDir\\claude_desktop_config.json';
const storeDir = r'C:\Users\sam\AppData\Local\Packages\Claude_pzs8sxrjxfjjc'
    r'\LocalCache\Roaming\Claude';

Map<String, dynamic> decode(String text) =>
    (jsonDecode(text) as Map).cast<String, dynamic>();

void main() {
  group('what Claude Code says', () {
    test('claude mcp get: connected, an old copy, missing, a project entry', () {
      var info = parseMcpGet(fx('mcp_get_connected.txt'));
      expect(info.found, isTrue);
      expect(info.command, launcher);
      expect(info.scope, 'user');
      expect(info.connected, isTrue);
      info = parseMcpGet(fx('mcp_get_old_copy.txt'));
      expect(info.command, r'D:\Apps\ClipForge-1.11.0\clipforge-mcp.exe',
          reason: 'quotes around the path are taken off');
      expect(info.connected, isFalse);
      expect(parseMcpGet(fx('mcp_get_missing.txt'), exitCode: 1).found, isFalse);
      expect(parseMcpGet('', exitCode: 1).found, isFalse);
      expect(parseMcpGet('error: unknown command "mcp"', exitCode: 1).found, isFalse);
      expect(parseMcpGet(fx('mcp_get_local.txt')).scope, 'local');
      // Other wording, other case, Windows line ends: still read.
      info = parseMcpGet('CLIPFORGE\r\n   command :  /opt/x/clipforge-mcp \r\n'
          '   SCOPE: user\r\n');
      expect([info.found, info.command, info.scope], [true, '/opt/x/clipforge-mcp', 'user']);
    });

    test('claude mcp list: the clipforge line among others', () {
      final info = parseMcpList(fx('mcp_list.txt'));
      expect(info.found, isTrue);
      expect(info.command, launcher);
      expect(info.connected, isTrue);
      expect(parseMcpList('notes: npx - ✓ Connected\n').found, isFalse);
    });

    test('its settings file: the user-wide entry and those of project folders', () {
      final entries = codeConfigEntries(fx('claude_code_settings.json'));
      expect(entries.map((e) => (e.scope, e.projectDir)), [
        ('user', null),
        ('local', 'C:/Users/sam/videos'),
        ('local', 'C:/Users/sam/code/site'),
      ]);
      expect(entries.first.command, r'D:\Apps\ClipForge-1.11.0\clipforge-mcp.exe');
      expect(codeConfigEntries('not json'), isEmpty);
      expect(codeConfigEntries(null), isEmpty);
      expect(looksLikeClipForgeHelper(r'C:\old\ClipForge\clipforge-mcp.exe'), isTrue);
      expect(looksLikeClipForgeHelper('/x/clipforge-mcp'), isTrue);
      expect(looksLikeClipForgeHelper('node'), isFalse);
    });
  });

  group('Claude Code', () {
    test('found on the PATH or in the usual places; .cmd on Windows', () {
      final h = FakeConnectHost();
      expect(findClaudeCode(h), isNull);
      h.put(claudeCmd, '');
      expect(findClaudeCode(h), claudeCmd);
      final mac = FakeConnectHost(os: 'macos')..put('/Users/sam/.local/bin/claude', '');
      expect(findClaudeCode(mac), '/Users/sam/.local/bin/claude');
    });

    test('status: not found, not connected, connected, an old copy', () async {
      final h = FakeConnectHost();
      expect((await claudeCodeStatus(h, launcher)).state, ConnectState.notInstalled);
      h.put(claudeCmd, '');
      var s = await claudeCodeStatus(h, launcher);
      expect(s.state, ConnectState.notConnected);
      expect(s.detail, contains('> claude mcp get clipforge'));
      h.claude = (args, cwd) => RunResult(0, fx('mcp_get_connected.txt'), '');
      s = await claudeCodeStatus(h, launcher);
      expect(s.state, ConnectState.connected);
      // Windows paths compare whatever the case and slashes.
      expect((await claudeCodeStatus(h, launcher.toUpperCase().replaceAll(r'\', '/'))).state,
          ConnectState.connected);
      h.claude = (args, cwd) => RunResult(0, fx('mcp_get_old_copy.txt'), '');
      s = await claudeCodeStatus(h, launcher);
      expect(s.state, ConnectState.connectedElsewhere);
      expect(s.command, r'D:\Apps\ClipForge-1.11.0\clipforge-mcp.exe');
    });

    test('without the program its settings file still tells', () async {
      final h = FakeConnectHost()
        ..put(r'C:\Users\sam\.claude.json', fx('claude_code_settings.json'));
      final s = await claudeCodeStatus(h, launcher);
      expect(s.state, ConnectState.connectedElsewhere);
      expect(s.program, isNull);
      // Only project entries that start an OLD ClipForge helper are offered
      // for removal; someone's own "clipforge" tool is not.
      expect(s.others.map((e) => e.projectDir), ['C:/Users/sam/videos']);
      expect(h.runs, isEmpty);
    });

    test('Connect: removes the old entries, then adds ours; the log shows '
        'every command', () async {
      final h = FakeConnectHost()
        ..put(claudeCmd, '')
        ..put(r'C:\Users\sam\.claude.json', fx('claude_code_settings.json'))
        ..mkdir('C:/Users/sam/videos');
      final status = await claudeCodeStatus(h, launcher);
      h.runs.clear();
      final r = await connectClaudeCode(h, launcher, removeOthers: status.others);
      expect(r.ok, isTrue);
      expect(h.runs, [
        '$claudeCmd mcp remove clipforge -s user',
        '$claudeCmd mcp remove clipforge -s local @ C:/Users/sam/videos',
        '$claudeCmd mcp add --scope user clipforge -- $launcher',
      ]);
      expect(r.log, contains('> claude mcp add --scope user clipforge -- $launcher'));
      expect(r.message, contains('Start a new Claude Code session'));
      // Nothing was written by ClipForge itself.
      expect(h.files[r'C:\Users\sam\.claude.json'], fx('claude_code_settings.json'));
    });

    test('Connect that Claude Code refuses, Disconnect, and no program', () async {
      final h = FakeConnectHost()..put(claudeCmd, '');
      h.claude = (args, cwd) => args[1] == 'add'
          ? const RunResult(1, '', 'error: unknown option --scope')
          : const RunResult(0, '', '');
      var r = await connectClaudeCode(h, launcher);
      expect(r.ok, isFalse);
      expect(r.message, contains('did not accept'));
      expect(r.log, contains('unknown option --scope'));
      h.claude = (args, cwd) => const RunResult(0, 'Removed MCP server clipforge', '');
      r = await disconnectClaudeCode(h);
      expect(r.ok, isTrue);
      expect(h.runs.last, '$claudeCmd mcp remove clipforge -s user');
      expect((await connectClaudeCode(FakeConnectHost(), launcher)).ok, isFalse);
    });
  });

  group('the Claude Desktop settings file', () {
    test('other servers present: only the clipforge entry is added, every '
        'other byte stays', () {
      final before = fx('desktop_other_servers.json');
      final edit = editDesktopConfig(before, launcher);
      expect(edit.problem, isNull);
      expect(edit.changed, isTrue);
      expect(edit.previous, isNull);
      final after = edit.text!;
      final json = decode(after);
      expect((json['mcpServers'] as Map).keys, ['notes', 'weather', 'clipforge']);
      expect((json['mcpServers'] as Map)['clipforge'], {'command': launcher, 'args': <String>[]});
      expect(json['globalShortcut'], 'Ctrl+Space');
      expect(json['preferences'], {'sidebar': true, 'zoom': 1.25});
      // Byte for byte the same around the new entry.
      final at = before.indexOf('"weather": { "command": "weather-mcp.exe" }') +
          '"weather": { "command": "weather-mcp.exe" }'.length;
      expect(after.substring(0, at), before.substring(0, at));
      expect(after.endsWith(before.substring(at)), isTrue);
      expect(after, contains('    "clipforge": {\n      "command": '));
      // Again: nothing to do.
      final again = editDesktopConfig(after, launcher);
      expect(again.changed, isFalse);
      expect(again.text, after);
      // And taken out again: exactly the file as it was.
      final removed = editDesktopConfig(after, launcher, remove: true);
      expect(removed.text, before);
      expect(removed.previous, launcher);
    });

    test('an old clipforge entry pointing elsewhere is replaced (and said)', () {
      final before = fx('desktop_old_clipforge.json');
      final edit = editDesktopConfig(before, launcher);
      expect(edit.previous, r'D:\Apps\ClipForge-1.11.0\clipforge-mcp.exe');
      final json = decode(edit.text!);
      expect((json['mcpServers'] as Map).keys, ['clipforge', 'notes'], reason: 'order kept');
      expect((json['mcpServers'] as Map)['clipforge'], {'command': launcher, 'args': <String>[]});
      expect(edit.text, contains('"notes": { "command": "npx", "args": ["-y", "@example/notes-mcp"] }'),
          reason: 'the other server keeps its own layout');
      expect(edit.text, contains('        "clipforge": {\n            "command"'),
          reason: 'the file\'s own indent (4 spaces) is used');
      final removed = editDesktopConfig(edit.text!, launcher, remove: true);
      expect((decode(removed.text!)['mcpServers'] as Map).keys, ['notes']);
    });

    test('tabs and Windows line ends are kept; an empty server list is filled', () {
      final before = fx('desktop_tabs_crlf.json');
      final edit = editDesktopConfig(before, launcher);
      final after = edit.text!;
      expect(decode(after)['theme'], 'dark');
      expect((decode(after)['mcpServers'] as Map).keys, ['clipforge']);
      expect(after, startsWith('{\r\n\t"theme": "dark",\r\n\t"mcpServers": {\r\n\t\t"clipforge": {'));
      expect(after.replaceAll('\r\n', '').contains('\n'), isFalse, reason: 'no lone line feed');
      expect(editDesktopConfig(after, launcher, remove: true).text!.contains('clipforge'), isFalse);
    });

    test('no mcpServers yet: it is added as the last part', () {
      final edit = editDesktopConfig(fx('desktop_no_servers.json'), launcher);
      final json = decode(edit.text!);
      expect(json.keys, ['preferences', 'mcpServers']);
      expect(json['preferences'], {'sidebar': true});
    });

    test('comments or a stray comma: refused cleanly, nothing to write', () {
      final edit = editDesktopConfig(fx('desktop_with_comment.json'), launcher);
      expect(edit.text, isNull);
      expect(edit.changed, isFalse);
      expect(edit.problem, contains('not plain JSON'));
      expect(edit.problem, contains('Nothing was written'));
      expect(editDesktopConfig('[1, 2]', launcher).problem, isNotNull);
      expect(editDesktopConfig('{"mcpServers": 3}', launcher).problem, isNotNull);
    });

    test('a missing or empty file becomes a minimal valid one', () {
      for (final empty in [null, '', '  \n']) {
        final edit = editDesktopConfig(empty, launcher);
        expect(decode(edit.text!), {
          'mcpServers': {
            'clipforge': {'command': launcher, 'args': <String>[]},
          },
        });
      }
      expect(editDesktopConfig(null, launcher, remove: true).text, isNull);
    });
  });

  group('Claude Desktop', () {
    test('found in the normal place and in the Microsoft Store place', () {
      final h = FakeConnectHost();
      expect(findClaudeDesktop(h), isEmpty);
      expect(claudeDesktopStatus(h, launcher).state, ConnectState.notInstalled);
      h.mkdir(storeDir);
      h.mkdir(r'C:\Users\sam\AppData\Local\Packages\Microsoft.WindowsNotepad_8wekyb');
      var places = findClaudeDesktop(h);
      expect(places.single.dir, storeDir);
      expect(places.single.kind, 'Claude from the Microsoft Store');
      h.mkdir(desktopDir);
      places = findClaudeDesktop(h);
      expect(places.map((x) => x.kind), ['the Claude app', 'Claude from the Microsoft Store']);
      final mac = FakeConnectHost(os: 'macos')
        ..mkdir('/Users/sam/Library/Application Support/Claude');
      expect(findClaudeDesktop(mac).single.dir, '/Users/sam/Library/Application Support/Claude');
    });

    test('Connect: a backup with the date, then only the entry; the Store '
        'folder with no file yet gets a minimal one', () {
      final h = FakeConnectHost()
        ..put(desktopFile, fx('desktop_old_clipforge.json'))
        ..mkdir(storeDir);
      expect(claudeDesktopStatus(h, launcher).state, ConnectState.connectedElsewhere);
      final r = changeClaudeDesktop(h, launcher);
      expect(r.ok, isTrue);
      expect(r.message, contains('an older ClipForge entry pointing at D:\\Apps'));
      expect(r.message, contains('Close Claude completely'));
      const backup = '$desktopDir\\claude_desktop_config.backup-20261119-143005.json';
      expect(h.files[backup], fx('desktop_old_clipforge.json'));
      expect(desktopEntryCommand(h.files[desktopFile]), launcher);
      const storeFile = '$storeDir\\claude_desktop_config.json';
      expect(desktopEntryCommand(h.files[storeFile]), launcher);
      expect(h.files.keys.where((k) => k.startsWith(storeDir)).length, 1,
          reason: 'no backup of a file that did not exist');
      expect(r.log, contains('backup: $backup'));
      expect(claudeDesktopStatus(h, launcher).state, ConnectState.connected);
      // Connect again: nothing is written, no second backup.
      final count = h.files.length;
      changeClaudeDesktop(h, launcher);
      expect(h.files.length, count);
      // Disconnect: backup, the entry goes, the other server stays.
      h.time = DateTime(2026, 11, 19, 15, 0, 0);
      final off = changeClaudeDesktop(h, launcher, remove: true);
      expect(off.ok, isTrue);
      expect((decode(h.files[desktopFile]!)['mcpServers'] as Map).keys, ['notes']);
      expect(h.files.containsKey('$desktopDir\\claude_desktop_config.backup-20261119-150000.json'),
          isTrue);
      expect(claudeDesktopStatus(h, launcher).state, ConnectState.notConnected);
    });

    test('a file that is not plain JSON stops everything before any write', () {
      final h = FakeConnectHost()
        ..put(desktopFile, fx('desktop_other_servers.json'))
        ..put('$storeDir\\claude_desktop_config.json', fx('desktop_with_comment.json'));
      final before = Map.of(h.files);
      final r = changeClaudeDesktop(h, launcher);
      expect(r.ok, isFalse);
      expect(r.message, contains('not plain JSON'));
      expect(h.files, before, reason: 'neither file changed, no backup');
      expect(claudeDesktopStatus(h, launcher).state, ConnectState.unreadable);
    });

    test('not installed: nothing is created; an installed extension is noticed', () {
      final h = FakeConnectHost();
      expect(changeClaudeDesktop(h, launcher).ok, isFalse);
      expect(h.files, isEmpty);
      h
        ..put(desktopFile, '{"mcpServers":{"clipforge":{"command":"${launcher.replaceAll(r'\', r'\\')}"}}}')
        ..mkdir('$desktopDir\\Claude Extensions\\local.mcpb.clipforge.clipforge');
      final s = claudeDesktopStatus(h, launcher);
      expect(s.state, ConnectState.connected);
      expect(s.extension, 'local.mcpb.clipforge.clipforge');
      expect(s.twice, isTrue);
    });
  });

  group('is the helper in use?', () {
    const stable = r'C:\Users\sam\AppData\Local\ClipForge\claude';

    test('a running helper is listed; one whose process is gone is stale '
        'and removed', () async {
      final h = FakeConnectHost();
      final now = h.time;
      h.put(
          '$stable\\in-use\\4100.json',
          jsonEncode(HelperSession(
                  pid: 4100,
                  version: '1.14.0',
                  client: 'claude-ai',
                  startedAt: now.subtract(const Duration(hours: 1)),
                  lastCallAt: now.subtract(const Duration(minutes: 2)))
              .toJson()));
      h.put(
          '$stable\\in-use\\977.json',
          jsonEncode(HelperSession(
                  pid: 977,
                  version: '1.13.0',
                  client: 'claude-code',
                  startedAt: now.subtract(const Duration(days: 2)),
                  lastCallAt: now.subtract(const Duration(days: 2)))
              .toJson()));
      h.put('$stable\\in-use\\junk.json', 'not json');
      h.alive.add(4100);
      final sessions = await helperSessions(h, stable, listFiles: h.listFiles);
      expect(sessions.single.pid, 4100);
      expect(sessions.single.clientName, 'Claude Desktop');
      expect(h.listFiles('$stable\\in-use'), ['4100.json'], reason: 'stale files are deleted');
      expect(inUseLine(sessions, now), 'In use by Claude Desktop now · last action 2 min ago');
      expect(inUseLine(const [], now),
          'Not in use right now (that is normal: Claude starts it when needed).');
      expect(agoText(now.subtract(const Duration(seconds: 10)), now), 'just now');
      expect(agoText(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    });

    test('the helper writes its file at the handshake, refreshes it when a '
        'tool is used, and removes it when it ends', () {
      final dir = Directory.systemTemp.createTempSync('clipforge_heartbeat_');
      addTearDown(() => dir.deleteSync(recursive: true));
      var now = DateTime.utc(2026, 11, 19, 12);
      final beat = HelperHeartbeat(dir.path,
          version: '1.14.0', now: () => now, processId: 4242);
      final file = File(p.join(dir.path, 'in-use', '4242.json'));
      beat.used();
      expect(file.existsSync(), isFalse, reason: 'nothing before a client said hello');
      beat.opened('claude-code');
      var s = HelperSession.fromJson(jsonDecode(file.readAsStringSync()))!;
      expect([s.pid, s.version, s.clientName], [4242, '1.14.0', 'Claude Code']);
      expect(s.lastCallAt, s.startedAt);
      now = now.add(const Duration(seconds: 2));
      beat.used();
      expect(HelperSession.fromJson(jsonDecode(file.readAsStringSync()))!.lastCallAt,
          s.startedAt, reason: 'written at most every 5 seconds');
      now = now.add(const Duration(seconds: 30));
      beat.used();
      s = HelperSession.fromJson(jsonDecode(file.readAsStringSync()))!;
      expect(s.lastCallAt.difference(s.startedAt).inSeconds, 32);
      beat.closed();
      expect(file.existsSync(), isFalse);
      // Without a folder (no home): nothing happens, nothing throws.
      HelperHeartbeat(null, version: 'x')
        ..opened('c')
        ..used()
        ..closed();
    });
  });

  group('the Test button', () {
    test('what the helper wrote back becomes PASS or FAIL', () {
      String reply(int id, Map<String, dynamic> result) =>
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
      final hello = reply(1, {
        'protocolVersion': '2025-06-18',
        'serverInfo': {'name': 'clipforge', 'version': '1.14.0'},
      });
      final pass = readHelperTest('$hello\n${reply(2, {
            'content': [
              {'type': 'text', 'text': 'ClipForge self-test: PASS (13 passed, 2 skipped)\n...'},
            ],
          })}\n');
      expect(pass.pass, isTrue);
      expect(pass.summary, 'PASS: the helper works by itself (ClipForge 1.14.0).');
      expect(pass.report, contains('13 passed'));
      final fail = readHelperTest('$hello\n${reply(2, {
            'content': [
              {'type': 'text', 'text': 'ClipForge self-test: FAIL (1 failed)\nSample media: FAIL'},
            ],
          })}\n');
      expect(fail.pass, isFalse);
      expect(fail.summary, contains('a check did not pass'));
      final silent = readHelperTest('', stderr: 'cannot start', exitCode: 1);
      expect(silent.pass, isFalse);
      expect(silent.summary, 'FAIL: the helper did not answer (it ended with code 1).');
      expect(silent.report, 'cannot start');
      expect(readHelperTest('$hello\n').summary, contains('the test did not finish'));
      // The messages are a handshake and the QUICK self-test.
      final sent = helperTestMessages().map(jsonDecode).toList();
      expect((sent[0] as Map)['method'], 'initialize');
      expect((sent[2] as Map)['params'], {
        'name': 'self_test',
        'arguments': {'quick': true},
      });
    });
  });
}
