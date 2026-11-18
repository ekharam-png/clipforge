// Help > Connect to Claude… (1.12): whether the helper is installed, the
// extension file saved from the app itself, the one line for Claude Code
// with Copy, and that the app really puts the helper into the per-user
// folder at start (with a pretend extension file, in a temporary folder).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clipforge/core/build_info.dart';
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
      expect(find.text('You only do this once'), findsOneWidget);
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
      expect(find.textContaining('double-click that file'), findsOneWidget);
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
            .widget<FilledButton>(find.byKey(const ValueKey('claude-save-extension')))
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
}
