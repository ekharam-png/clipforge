import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/claude/helper_install.dart';
import '../help/help_screen.dart';
import '../services.dart';
import '../theme.dart';
import 'claude_helper.dart';

// Help > Connect to Claude…: whether the Claude helper is installed, the
// extension file for Claude Desktop (saved from the app itself, nothing to
// download), and the one line for Claude Code. All of it needs doing once:
// the app keeps the helper up to date after that.

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = ref.read(claudeHelperProvider);
    var s = await service.state();
    if (s.supported && !s.installed && s.hasBundle) {
      // E.g. the folder was deleted while the app was open.
      await service.installAtStart();
      s = await service.state();
    }
    if (mounted) setState(() => _state = s);
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
        _say('Saved: $where. Now double-click that file; Claude asks whether '
            'to install it.');
      }
    } catch (e) {
      _say('The file could not be saved. ($e)');
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('$what copied.');
  }

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
      children = [
        Text(
          'Claude can edit your ClipForge videos when you ask it in plain '
          'words ("cut the pauses out of my podcast and add music"). '
          'Connect it once; after that ClipForge keeps the connection up '
          'to date by itself every time the app is updated.',
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
                  ? 'Version ${current?.version ?? '?'}'
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
            ],
          ),
        ),
        _Card(
          icon: Icons.looks_one_outlined,
          title: 'Claude Desktop (the Claude app)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Save the extension file.\n'
                  '2. Double-click the saved file. Claude opens and asks '
                  'whether to install "ClipForge": choose Install.\n'
                  '3. Close Claude completely and open it again.'),
              const SizedBox(height: 10),
              FilledButton.icon(
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
        _Card(
          icon: Icons.looks_two_outlined,
          title: 'Claude Code (in a terminal)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste this one line into a terminal and press Enter:'),
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
          title: 'You only do this once',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Both ways point Claude at the same helper in the folder '
                  'above. When ClipForge is updated it puts the new helper '
                  'there, and Claude uses it the next time Claude starts. '
                  'Nothing has to be installed or uploaded again.\n\n'
                  'To try it, ask Claude: "Run the ClipForge self-test." It '
                  'checks everything with its own sample video and never '
                  'touches your projects.\n\n'
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
