// Help > Connect to Claude… (1.12): whether the helper is installed, the
// extension file saved from the app itself, the one line for Claude Code
// with Copy, and that the app really puts the helper into the per-user
// folder at start (with a pretend extension file, in a temporary folder).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/claude/connect.dart';
import 'package:clipforge/core/claude/helper_install.dart';
import 'package:clipforge/ui/claude/claude_helper.dart';
import 'package:clipforge/ui/claude/connect_claude.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

const ci142 = BuildInfo(version: '1.12.0', buildNumber: '142', channel: 'ci');

/// What the page asks the service, answered from memory.
class FakeClaude extends ClaudeHelperService {
  FakeClaude(this.answer, {this.bytes})
      : super(build: ci142, os: 'windows', loadBundle: () async => bytes);
  ClaudeHelperState answer;
  final Uint8List? bytes;
  int installs = 0;

  @override
  Future<void> installAtStart() async => installs++;

  @override
  Future<ClaudeHelperState> state() async => answer;

  final List<String> written = [];
  @override
  Future<bool> writeBundle(String path) async {
    written.add(path);
    return bytes != null;
  }
}

const _dir = r'C:\Users\sam\AppData\Local\ClipForge\claude';
const _launcher = '$_dir\\clipforge-mcp.exe';

ClaudeHelperState installedState({bool hasBundle = true}) => ClaudeHelperState(
      supported: true,
      stableDir: _dir,
      launcherPath: _launcher,
      installed: true,
      hasBundle: hasBundle,
      current: const HelperCurrent(
          version: '1.12.0', build: 142, path: '$_dir\\versions\\1.12.0-b142-ab12cd34\\clipforge-mcp.exe'),
    );

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('installed: status, the extension file and the Claude Code line ($label)',
        (tester) async {
      useScreen(tester, size);
      final claude = FakeClaude(installedState(), bytes: Uint8List.fromList([80, 75, 3, 4]));
      final fakes = Fakes()..claude = claude;
      await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('The Claude helper is installed'), findsOneWidget);
      expect(find.textContaining('Version 1.12.0 (build 142)'), findsOneWidget);
      expect(find.text(_dir), findsOneWidget);
      expect(find.text('After connecting: close and reopen Claude once'), findsOneWidget);
      expect(find.textContaining('ClipForge does not have to be running'), findsOneWidget);
      expect(find.textContaining('Run the ClipForge self-test'), findsOneWidget);
      const command = 'claude mcp add --scope user clipforge -- "$_launcher"';
      expect(find.text(command), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      await fakes.screenshot(tester, 'connect_claude_$label');

      // Copy puts exactly that line on the clipboard.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await tester.ensureVisible(find.byKey(const ValueKey('claude-copy-command')));
      await tester.tap(find.byKey(const ValueKey('claude-copy-command')));
      await tester.pumpAndSettle();
      expect(copied, command);
      expect(find.text('The command was copied.'), findsOneWidget);

      // The extension file comes out of the app: nothing is downloaded.
      await tester.ensureVisible(find.byKey(const ValueKey('claude-save-extension')));
      await tester.tap(find.byKey(const ValueKey('claude-save-extension')));
      await tester.pumpAndSettle();
      expect(fakes.documents.savedFiles.single, endsWith('.mcpb'));
      expect(claude.written, fakes.documents.savedFiles);
      expect(find.textContaining('Install Extension…, and choose that file'), findsOneWidget);
    });
  }

  testWidgets('a build without the helper says so and offers nothing to save', (tester) async {
    useScreen(tester, desktop);
    final fakes = Fakes()
      ..claude = FakeClaude(const ClaudeHelperState(
          supported: true, stableDir: _dir, launcherPath: _launcher));
    await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('The Claude helper is not installed yet'), findsOneWidget);
    expect(find.textContaining('development build'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('claude-save-extension')))
            .onPressed,
        isNull);
    await fakes.screenshot(tester, 'connect_claude_no_helper_desktop');
  });

  testWidgets('not installed although the app has it: installed when the page opens',
      (tester) async {
    useScreen(tester, desktop);
    final claude = FakeClaude(
        const ClaudeHelperState(
            supported: true, stableDir: _dir, launcherPath: _launcher, hasBundle: true),
        bytes: Uint8List(4));
    final fakes = Fakes()..claude = claude;
    await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
    await tester.pumpAndSettle();
    expect(claude.installs, 1);
  });

  testWidgets('a phone is told that this is for the computer', (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(); // the default: a phone
    await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Claude works with ClipForge on a computer'), findsOneWidget);
    expect(find.byKey(const ValueKey('claude-save-extension')), findsNothing);
  });

  test('the real service installs the helper from the app\'s extension file at start', () async {
    final tmp = await Directory.systemTemp.createTemp('clipforge_claude_ui_test');
    addTearDown(() => tmp.delete(recursive: true));
    List<int> bundle(String program) => ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile.bytes('server/clipforge-mcp', utf8.encode(program)))
      ..addFile(ArchiveFile.bytes('server/fonts/DejaVuSans.ttf', [1])));
    ClaudeHelperService service(String program, BuildInfo build) => ClaudeHelperService(
        build: build,
        os: 'linux',
        environment: {'XDG_DATA_HOME': tmp.path},
        loadBundle: () async => Uint8List.fromList(bundle(program)));

    final first = service('v1', ci142);
    expect((await first.state()).installed, isFalse);
    await first.installAtStart();
    var s = await first.state();
    expect(s.installed, isTrue);
    expect(s.hasBundle, isTrue);
    expect(s.launcherPath, p.join(tmp.path, 'ClipForge', 'claude', 'clipforge-mcp'));
    expect([s.current!.version, s.current!.build], ['1.12.0', 142]);
    expect(File(s.current!.path).readAsStringSync(), 'v1');

    // After an app update the next start switches to the new helper.
    final next = service('v2', const BuildInfo(version: '1.13.0', buildNumber: '150', channel: 'ci'));
    await next.installAtStart();
    s = await next.state();
    expect([s.current!.version, s.current!.build], ['1.13.0', 150]);
    expect(File(s.current!.path).readAsStringSync(), 'v2');
    expect(s.launcherPath, p.join(tmp.path, 'ClipForge', 'claude', 'clipforge-mcp'),
        reason: 'the path given to Claude never changes');

    // A build without the file installs nothing and does not fail.
    final none = ClaudeHelperService(
        build: ci142,
        os: 'linux',
        environment: {'XDG_DATA_HOME': p.join(tmp.path, 'other')},
        loadBundle: () async => null);
    await none.installAtStart();
    expect((await none.state()).installed, isFalse);
    expect((await none.state()).hasBundle, isFalse);
  });

  // 1.14: the page does the set-up itself -----------------------------------

  const claudeCmd = r'C:\Users\sam\AppData\Roaming\npm\claude.cmd';
  const desktopDir = r'C:\Users\sam\AppData\Roaming\Claude';
  const desktopFile = '$desktopDir\\claude_desktop_config.json';
  String fixture(String name) =>
      File(p.join('test', 'core', 'fixtures', 'claude', name)).readAsStringSync();
  Finder key(String k) => find.byKey(ValueKey(k));
  String statusOf(WidgetTester tester, String id) =>
      tester.widget<Text>(key('$id-status')).data!;
  Color lightOf(WidgetTester tester, String id) =>
      (tester.widget<Container>(key('$id-light')).decoration! as BoxDecoration).color!;
  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  Future<Fakes> page(WidgetTester tester, Size size, void Function(Fakes f) setup) async {
    useScreen(tester, size);
    final fakes = Fakes()
      ..claude = FakeClaude(installedState(), bytes: Uint8List.fromList([80, 75, 3, 4]));
    setup(fakes);
    await tester.pumpWidget(fakes.app(const ConnectClaudeScreen()));
    await tester.pumpAndSettle();
    return fakes;
  }

  testWidgets('no Claude on this computer: both rows say so, nothing to press',
      (tester) async {
    final fakes = await page(tester, desktop, (_) {});
    expect(statusOf(tester, 'claude-desktop'), 'Claude Desktop not found');
    expect(statusOf(tester, 'claude-code'), 'Claude Code not found');
    expect(tester.widget<FilledButton>(key('claude-desktop-connect')).onPressed, isNull);
    expect(tester.widget<FilledButton>(key('claude-code-connect')).onPressed, isNull);
    expect(key('claude-code-disconnect'), findsNothing);
    expect(tester.widget<Text>(key('claude-in-use')).data,
        'Not in use right now (that is normal: Claude starts it when needed).');
    // The alternatives are still there.
    expect(key('claude-save-extension'), findsOneWidget);
    expect(key('claude-copy-command'), findsOneWidget);
    expect(find.textContaining('Install Extension…'), findsOneWidget);
    expect(fakes.connectHost.files, isEmpty, reason: 'looking writes nothing');
  });

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('Claude Desktop: Connect writes only the entry, with a backup; '
        'Disconnect takes it out ($label)', (tester) async {
      final fakes = await page(tester, size, (f) {
        f.connectHost.put(desktopFile, fixture('desktop_other_servers.json'));
      });
      final h = fakes.connectHost;
      expect(statusOf(tester, 'claude-desktop'), 'Not connected');
      await tapKey(tester, 'claude-desktop-connect');
      expect(statusOf(tester, 'claude-desktop'), 'Connected (ClipForge 1.12.0)');
      expect(lightOf(tester, 'claude-desktop'), const Color(0xFF4CD08A));
      expect(tester.widget<Text>(key('claude-desktop-outcome')).data,
          contains('Close Claude completely'));
      final json = jsonDecode(h.files[desktopFile]!) as Map;
      expect((json['mcpServers'] as Map).keys, ['notes', 'weather', 'clipforge']);
      expect(((json['mcpServers'] as Map)['clipforge'] as Map)['command'], _launcher);
      expect(json['globalShortcut'], 'Ctrl+Space');
      expect(h.files.keys.where((k) => k.contains('.backup-')).length, 1);
      expect(key('claude-desktop-connect'), findsNothing, reason: 'one button: now Disconnect');
      await fakes.screenshot(tester, 'connect_claude_connected_$label');
      await tapKey(tester, 'claude-desktop-disconnect');
      expect(statusOf(tester, 'claude-desktop'), 'Not connected');
      expect(h.files[desktopFile], fixture('desktop_other_servers.json'),
          reason: 'exactly the file as it was');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Claude Desktop: a settings file that is not plain JSON is '
      'never touched', (tester) async {
    final fakes = await page(tester, desktop, (f) {
      f.connectHost.put(desktopFile, fixture('desktop_with_comment.json'));
    });
    expect(statusOf(tester, 'claude-desktop'),
        'Its settings file cannot be read as plain JSON');
    expect(lightOf(tester, 'claude-desktop'), const Color(0xFFFFC56B));
    expect(tester.widget<FilledButton>(key('claude-desktop-connect')).onPressed, isNull);
    expect(fakes.connectHost.files[desktopFile], fixture('desktop_with_comment.json'));
  });

  testWidgets('Claude Desktop: connected and the extension installed too: '
      'one is enough', (tester) async {
    await page(tester, desktop, (f) {
      f.connectHost
        ..put(desktopFile,
            jsonEncode({'mcpServers': {'clipforge': {'command': _launcher}}}))
        ..mkdir('$desktopDir\\Claude Extensions\\local.mcpb.clipforge.clipforge');
    });
    expect(statusOf(tester, 'claude-desktop'), 'Connected (ClipForge 1.12.0)');
    expect(tester.widget<Text>(key('claude-desktop-twice')).data,
        allOf(contains('One of the two is enough'), contains('Disconnect here')));
  });

  testWidgets('Claude Code: an old copy is named, listed before it is '
      'replaced, and Connect runs the command itself', (tester) async {
    var connected = false;
    final fakes = await page(tester, desktop, (f) {
      f.connectHost
        ..put(claudeCmd, '')
        ..put(r'C:\Users\sam\.claude.json', fixture('claude_code_settings.json'))
        ..mkdir('C:/Users/sam/videos')
        ..claude = (args, cwd) {
          if (args[1] == 'get') {
            return RunResult(
                0, fixture(connected ? 'mcp_get_connected.txt' : 'mcp_get_old_copy.txt'), '');
          }
          if (args[1] == 'add') connected = true;
          return const RunResult(0, 'ok', '');
        };
    });
    final h = fakes.connectHost;
    expect(statusOf(tester, 'claude-code'),
        r'Connected to an old copy at D:\Apps\ClipForge-1.11.0\clipforge-mcp.exe');
    expect(lightOf(tester, 'claude-code'), const Color(0xFFFFC56B));
    h.runs.clear();
    await tapKey(tester, 'claude-code-connect');
    // Asked once, with what will be removed.
    expect(key('claude-code-replace'), findsOneWidget);
    expect(find.textContaining(r'For all your projects: D:\Apps\ClipForge-1.11.0'), findsOneWidget);
    expect(find.textContaining(r'In C:/Users/sam/videos: C:\old\ClipForge\clipforge-mcp.exe'),
        findsOneWidget);
    expect(find.textContaining('my-own-clipforge-tool'), findsNothing);
    expect(h.runs, isEmpty, reason: 'nothing before the answer');
    await tapKey(tester, 'claude-code-replace-go');
    expect(h.runs.take(3), [
      '$claudeCmd mcp remove clipforge -s user',
      '$claudeCmd mcp remove clipforge -s local @ C:/Users/sam/videos',
      '$claudeCmd mcp add --scope user clipforge -- $_launcher',
    ]);
    expect(statusOf(tester, 'claude-code'), 'Connected (ClipForge 1.12.0)');
    expect(tester.widget<Text>(key('claude-code-outcome')).data,
        contains('Start a new Claude Code session'));
    // Details show the commands and their answers.
    await tapKey(tester, 'claude-code-details');
    expect(find.textContaining('> claude mcp add --scope user clipforge --'), findsOneWidget);
    // Now the one button is Disconnect.
    expect(key('claude-code-connect'), findsNothing);
    connected = false;
    h.claude = (args, cwd) => args[1] == 'get'
        ? RunResult(1, '', fixture('mcp_get_missing.txt'))
        : const RunResult(0, 'Removed', '');
    h.files.remove(r'C:\Users\sam\.claude.json');
    await tapKey(tester, 'claude-code-disconnect');
    expect(h.runs.any((r) => r.endsWith('mcp remove clipforge -s user')), isTrue);
    expect(statusOf(tester, 'claude-code'), 'Not connected');
    await fakes.screenshot(tester, 'connect_claude_code_desktop');
  });

  testWidgets('"Is it running?" and the Test button', (tester) async {
    final fakes = await page(tester, desktop, (f) {
      final now = f.connectHost.time;
      f.connectHost
        ..put(
            '$_dir\\in-use\\4100.json',
            jsonEncode(HelperSession(
                    pid: 4100,
                    version: '1.12.0',
                    client: 'claude-ai',
                    startedAt: now.subtract(const Duration(minutes: 30)),
                    lastCallAt: now.subtract(const Duration(minutes: 2)))
                .toJson()))
        ..alive.add(4100);
    });
    expect(tester.widget<Text>(key('claude-in-use')).data,
        'In use by Claude Desktop now · last action 2 min ago');
    await tapKey(tester, 'claude-test');
    expect(fakes.helperTests, [_launcher]);
    expect(tester.widget<Text>(key('claude-test-result')).data,
        'PASS: the helper works by itself (ClipForge 1.14.0).');
    await fakes.screenshot(tester, 'connect_claude_test_desktop');
    fakes.helperTestResult = const HelperTestResult(
        false,
        'FAIL: the helper did not answer (it ended with code 1).',
        'cannot start: something is missing');
    await tapKey(tester, 'claude-test');
    expect(tester.widget<Text>(key('claude-test-result')).data, startsWith('FAIL: '));
    await tapKey(tester, 'claude-test-details');
    expect(find.textContaining('something is missing'), findsOneWidget);
  });
}
