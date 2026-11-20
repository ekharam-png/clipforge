import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/claude/connect.dart';
import '../../core/claude/helper_install.dart';
import '../help/help_screen.dart';
import '../services.dart';
import '../theme.dart';
import 'claude_connect.dart';
import 'claude_helper.dart';

// Help > Connect to Claude… (reworked in 1.14): the app does the set-up
// itself. Per target (Claude Desktop, Claude Code) a status light and one
// button: Connect, or Disconnect. Whether the helper is in use right now,
// and a Test button that runs the helper by itself. The extension file
// and the one line for a terminal stay as the alternatives. Only ever the
// entry called "clipforge" is touched (see lib/core/claude/connect.dart).
// There is no "start a server" switch: Claude starts the helper itself.

Future<void> openConnectClaude(BuildContext context) {
  return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ConnectClaudeScreen()));
}

class ConnectClaudeScreen extends ConsumerStatefulWidget {
  const ConnectClaudeScreen({super.key});

  @override
  ConsumerState<ConnectClaudeScreen> createState() => _ConnectClaudeState();
}

class _ConnectClaudeState extends ConsumerState<ConnectClaudeScreen> {
  ClaudeHelperState? _state;
  ClaudeCodeStatus? _code;
  ClaudeDesktopStatus? _desktop;
  List<HelperSession> _sessions = const [];

  /// What the last Connect / Disconnect of each target said.
  ConnectOutcome? _codeOutcome, _desktopOutcome;
  HelperTestResult? _test;
  bool _busy = false, _testing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  ConnectHost get _host => ref.read(connectHostProvider);

  Future<void> _refresh() async {
    final service = ref.read(claudeHelperProvider);
    var s = await service.state();
    if (s.supported && !s.installed && s.hasBundle) {
      // E.g. the folder was deleted while the app was open.
      await service.installAtStart();
      s = await service.state();
    }
    ClaudeCodeStatus? code;
    ClaudeDesktopStatus? desktop;
    var sessions = const <HelperSession>[];
    final launcher = s.launcherPath;
    if (s.supported && launcher != null) {
      try {
        code = await claudeCodeStatus(_host, launcher);
      } catch (_) {}
      try {
        desktop = claudeDesktopStatus(_host, launcher);
      } catch (_) {}
      try {
        sessions = await helperSessions(_host, s.stableDir!,
            listFiles: ref.read(helperFilesProvider));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _state = s;
      _code = code;
      _desktop = desktop;
      _sessions = sessions;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _extensionName => switch (Platform.operatingSystem) {
        'windows' => 'ClipForge-claude-windows.mcpb',
        'macos' => 'ClipForge-claude-macos.mcpb',
        _ => 'ClipForge-claude.mcpb',
      };

  Future<void> _saveExtension() async {
    final service = ref.read(claudeHelperProvider);
    try {
      final where = await ref
          .read(documentServiceProvider)
          .saveFile(_extensionName, service.writeBundle);
      if (where != null) {
        _say('Saved: $where. In Claude: Settings > Extensions > Advanced '
            'settings > Install Extension…, and choose that file.');
      }
    } catch (e) {
      _say('The file could not be saved. ($e)');
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('$what copied.');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  /// Connect for Claude Code. Entries that would be removed (an older
  /// connection, also those of single project folders that start an old
  /// ClipForge helper) are listed first, and asked about once.
  Future<void> _connectCode(String launcher) async {
    final status = _code;
    if (status == null) return;
    final old = <String>[
      if (status.state == ConnectState.connectedElsewhere)
        'For all your projects: ${status.command}',
      for (final e in status.others) 'In ${e.projectDir}: ${e.command}',
    ];
    if (old.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          key: const ValueKey('claude-code-replace'),
          title: const Text('Replace the old connection?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
                'Claude Code already has a ClipForge connection that starts '
                'an older copy of the helper. It will be removed and '
                'replaced by the one ClipForge keeps up to date:\n\n'
                '${old.map((o) => '• $o').join('\n')}\n\n'
                'Nothing else in Claude Code is changed.'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(d).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                key: const ValueKey('claude-code-replace-go'),
                onPressed: () => Navigator.of(d).pop(true),
                child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() async {
      final r = await connectClaudeCode(_host, launcher,
          removeOthers: status.others);
      if (mounted) setState(() => _codeOutcome = r);
    });
  }

  Future<void> _disconnectCode() => _run(() async {
        final r = await disconnectClaudeCode(_host);
        if (mounted) setState(() => _codeOutcome = r);
      });

  Future<void> _changeDesktop(String launcher, {bool remove = false}) =>
      _run(() async {
        final r = changeClaudeDesktop(_host, launcher, remove: remove);
        if (mounted) setState(() => _desktopOutcome = r);
      });

  Future<void> _runTest(String launcher) async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _test = null;
    });
    HelperTestResult r;
    try {
      r = await ref.read(helperTesterProvider)(launcher);
    } catch (e) {
      r = HelperTestResult(false, 'FAIL: the test could not be run.', '$e');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = r;
    });
    await _refresh();
  }

  static Color _light(ConnectState? s) => switch (s) {
        ConnectState.connected => const Color(0xFF4CD08A),
        ConnectState.connectedElsewhere ||
        ConnectState.unreadable =>
          const Color(0xFFFFC56B),
        _ => AppColors.textDim,
      };

  Widget _statusLine(String id, ConnectState? state, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 8),
            child: Container(
              key: ValueKey('$id-light'),
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: _light(state), shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text,
                key: ValueKey('$id-status'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _details(String id, String text) => text.trim().isEmpty
      ? const SizedBox.shrink()
      : Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('$id-details'),
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Details',
                style: TextStyle(fontSize: 13, color: AppColors.textDim)),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(text,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.textDim)),
              ),
            ],
          ),
        );

  Widget _outcome(String id, ConnectOutcome? o) => o == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(o.message, key: ValueKey('$id-outcome')),
        );

  String _codeText(ClaudeCodeStatus c, String version) => switch (c.state) {
        ConnectState.connected => 'Connected (ClipForge $version)',
        ConnectState.connectedElsewhere =>
          'Connected to an old copy at ${c.command}',
        ConnectState.notConnected => 'Not connected',
        ConnectState.unreadable => 'Could not ask Claude Code',
        ConnectState.notInstalled => 'Claude Code not found',
      };

  String _desktopText(ClaudeDesktopStatus d, String version) => switch (d.state) {
        ConnectState.connected => 'Connected (ClipForge $version)',
        ConnectState.connectedElsewhere =>
          'Connected to an old copy at ${d.command}',
        ConnectState.notConnected => d.extension != null
            ? 'Connected through the ClipForge extension'
            : 'Not connected',
        ConnectState.unreadable =>
          'Its settings file cannot be read as plain JSON',
        ConnectState.notInstalled => 'Claude Desktop not found',
      };

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final text = Theme.of(context).textTheme;
    final List<Widget> children;
    if (s == null) {
      children = const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (!s.supported) {
      children = [
        const _Card(
          icon: Icons.computer_outlined,
          title: 'Claude works with ClipForge on a computer',
          child: Text('Asking Claude to edit your videos needs ClipForge and '
              'the Claude app on a Windows PC or a Mac. Open this page '
              'there: Help > Connect to Claude…'),
        ),
      ];
    } else {
      final launcher = s.launcherPath!;
      final command = claudeCodeCommand(launcher);
      final current = s.current;
      final version = current?.version ?? '?';
      final code = _code;
      final desktop = _desktop;
      final codeConnected = code?.state == ConnectState.connected;
      final desktopConnected = desktop?.state == ConnectState.connected;
      children = [
        Text(
          'Claude can edit your ClipForge videos when you ask it in plain '
          'words ("cut the pauses out of my podcast and add music"). '
          'Connect it once with the buttons below; after that ClipForge '
          'keeps the connection up to date by itself every time the app is '
          'updated.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        _Card(
          key: const ValueKey('claude-helper-status'),
          icon: s.installed ? Icons.check_circle_outline : Icons.info_outline,
          title: s.installed
              ? 'The Claude helper is installed'
              : 'The Claude helper is not installed yet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.installed
                  ? 'Version $version'
                      '${(current?.build ?? 0) > 0 ? ' (build ${current!.build})' : ''}. '
                      'ClipForge refreshes it every time the app starts.'
                  : s.hasBundle
                      ? s.problem ??
                          'ClipForge could not put the helper in place. '
                              'Close this page and open it again.'
                      : 'This copy of ClipForge was built without the '
                          'Claude helper (a development build). The '
                          'versions from the download page include it.'),
              const SizedBox(height: 6),
              SelectableText(s.stableDir ?? '',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Text(inUseLine(_sessions, _host.now()),
                  key: const ValueKey('claude-in-use')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('claude-test'),
                    onPressed: s.installed && !_testing
                        ? () => _runTest(launcher)
                        : null,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(_testing ? 'Testing…' : 'Test'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('claude-refresh'),
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Check again'),
                  ),
                ],
              ),
              if (_test != null) ...[
                const SizedBox(height: 6),
                Text(_test!.summary,
                    key: const ValueKey('claude-test-result'),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _test!.pass
                            ? const Color(0xFF4CD08A)
                            : AppColors.danger)),
                _details('claude-test', _test!.report),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                      'Test starts the helper by itself and runs its quick '
                      'self-test: it shows that the helper works, with or '
                      'without Claude.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ),
            ],
          ),
        ),
        if (desktop != null)
          _Card(
            icon: Icons.desktop_windows_outlined,
            title: 'Claude Desktop (the Claude app)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusLine('claude-desktop', desktop.state,
                    _desktopText(desktop, version)),
                if (desktop.places.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 18),
                    child: Text(
                        desktop.places.map((p) => p.kind).toSet().join(', '),
                        style:
                            const TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ),
                if (desktop.twice)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'Claude also has the ClipForge extension installed '
                        '(${desktop.extension}). One of the two is enough: '
                        'remove the extension in Claude (Settings > '
                        'Extensions), or press Disconnect here.',
                        key: const ValueKey('claude-desktop-twice'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (!desktopConnected)
                      FilledButton(
                        key: const ValueKey('claude-desktop-connect'),
                        onPressed: _busy ||
                                !s.installed ||
                                desktop.state == ConnectState.notInstalled ||
                                desktop.state == ConnectState.unreadable
                            ? null
                            : () => _changeDesktop(launcher),
                        // An old copy is connected: ONE clear action.
                        child: Text(
                            desktop.state == ConnectState.connectedElsewhere
                                ? 'Replace with this version'
                                : 'Connect'),
                      ),
                    if (desktop.command != null)
                      desktop.state == ConnectState.connectedElsewhere
                          ? TextButton(
                              key: const ValueKey('claude-desktop-disconnect'),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                      _changeDesktop(launcher, remove: true),
                              child: const Text('Disconnect instead'),
                            )
                          : OutlinedButton(
                              key: const ValueKey('claude-desktop-disconnect'),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                      _changeDesktop(launcher, remove: true),
                              child: const Text('Disconnect'),
                            ),
                  ],
                ),
                if (desktop.state == ConnectState.connectedElsewhere)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                        '"Replace with this version" points Claude at the '
                        'ClipForge that is running now, in place of the old '
                        'copy. Restart Claude afterwards.',
                        key: ValueKey('claude-desktop-replace-note'),
                        style: TextStyle(fontSize: 13)),
                  ),
                _outcome('claude-desktop', _desktopOutcome),
                _details('claude-desktop',
                    [desktop.detail, ?_desktopOutcome?.log].join('\n')),
                const Divider(height: 20),
                const Text(
                    'Or use the extension file instead: save it, then in '
                    'Claude open Settings > Extensions > Advanced settings > '
                    'Install Extension… and choose the file (or drag the '
                    'file onto that page). Double-clicking the file works '
                    'only where Claude has registered itself for it.',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('claude-save-extension'),
                  onPressed: s.hasBundle ? _saveExtension : null,
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('Save the Claude extension file…'),
                ),
                if (!s.hasBundle)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Not included in this build.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                  ),
              ],
            ),
          ),
        if (code != null)
          _Card(
            icon: Icons.terminal,
            title: 'Claude Code (in a terminal)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusLine('claude-code', code.state, _codeText(code, version)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (!codeConnected)
                      FilledButton(
                        key: const ValueKey('claude-code-connect'),
                        onPressed:
                            _busy || !s.installed || code.program == null
                                ? null
                                : () => _connectCode(launcher),
                        child: Text(
                            code.state == ConnectState.connectedElsewhere
                                ? 'Replace with this version'
                                : 'Connect'),
                      ),
                    if (code.command != null && code.program != null)
                      code.state == ConnectState.connectedElsewhere
                          ? TextButton(
                              key: const ValueKey('claude-code-disconnect'),
                              onPressed: _busy ? null : _disconnectCode,
                              child: const Text('Disconnect instead'),
                            )
                          : OutlinedButton(
                              key: const ValueKey('claude-code-disconnect'),
                              onPressed: _busy ? null : _disconnectCode,
                              child: const Text('Disconnect'),
                            ),
                  ],
                ),
                if (code.state == ConnectState.connectedElsewhere)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                        '"Replace with this version" points Claude Code at '
                        'the ClipForge that is running now, in place of the '
                        'old copy.',
                        style: TextStyle(fontSize: 13)),
                  ),
                _outcome('claude-code', _codeOutcome),
                _details('claude-code', [code.detail, ?_codeOutcome?.log].join('\n')),
                const Divider(height: 20),
                const Text('Or paste this one line into a terminal yourself:',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.panelHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(command,
                      key: const ValueKey('claude-code-command'),
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('claude-copy-command'),
                  onPressed: () => _copy(command, 'The command was'),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ),
        _Card(
          icon: Icons.task_alt,
          title: 'After connecting: close and reopen Claude once',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Claude reads its list of tools when it starts, so it sees '
                  'ClipForge after it was closed and opened again. Claude '
                  'Desktop: quit it completely, also from the small icon '
                  'next to the clock. Claude Code: start a new session '
                  '("/mcp" there shows the list).\n\n'
                  'Claude starts the helper itself each time it needs it; '
                  'ClipForge does not have to be running, and there is '
                  'nothing to switch on here.\n\n'
                  'You only do this once. When ClipForge is updated it puts '
                  'the new helper in the same place, and Claude uses it the '
                  'next time Claude starts.\n\n'
                  'To try it, ask Claude: "Run the ClipForge self-test." '
                  'Adding videos, finding silences and exporting through '
                  'Claude need the free program FFmpeg on this computer; '
                  'Claude tells you the one line to install it.'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => openHelp(context, articleId: 'connect-claude'),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('More in Help'),
              ),
            ],
          ),
        ),
      ];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Claude')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AppColors.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: 6),
                    child,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
