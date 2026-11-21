import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/links.dart' show kAppName;
import '../about.dart';
import '../app_settings.dart';
import '../claude/claude_helper.dart';
import '../claude/connect_claude.dart';
import '../feedback/feedback_screen.dart';
import '../help/help_screen.dart';
import '../help/whats_new.dart' show kWhatsNewId;
import '../theme.dart';
import '../update/update_controller.dart';
import '../update/update_ui.dart';

// The ONE Settings page (1.15). Computers: File > Settings… (Ctrl/Cmd+,),
// a window; phones: the three dots on the project list and the editor's
// project menu, a page. Every switch here is the app's setting itself
// (AppSettings over AppPrefs, and the update controller for the automatic
// check), so the View menu and this page can never disagree.

/// True on Android and iOS (the phone-only settings are shown).
bool get settingsOnPhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// How many Settings pages are on screen (0 or 1).
int _settingsShown = 0;

/// Opens Settings: a window on a wide screen, a page on a phone. A second
/// request while it is open does nothing.
Future<void> openSettings(BuildContext context) async {
  if (_settingsShown > 0) return;
  {
    if (MediaQuery.sizeOf(context).width >= 700) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          key: const ValueKey('settings-dialog'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Settings',
                            style: Theme.of(dialog).textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, semanticLabel: 'Close'),
                        onPressed: () => Navigator.of(dialog).pop(),
                      ),
                    ],
                  ),
                ),
                const Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: SettingsBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          key: const ValueKey('settings-page'),
          appBar: AppBar(title: const Text('Settings')),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SettingsBody(),
            ),
          ),
        ),
      ));
    }
  }
}

/// The sections of Settings.
class SettingsBody extends ConsumerStatefulWidget {
  const SettingsBody({super.key});

  @override
  ConsumerState<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<SettingsBody> {
  int? _hidden;
  ClaudeHelperState? _claude;

  @override
  void initState() {
    super.initState();
    _settingsShown++;
    _refresh();
  }

  @override
  void dispose() {
    _settingsShown--;
    super.dispose();
  }

  Future<void> _refresh() async {
    final settings = ref.read(appSettingsProvider);
    await settings.load();
    final hidden = await settings.hiddenHints();
    ClaudeHelperState? claude;
    try {
      claude = await ref.read(claudeHelperProvider).state();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _hidden = hidden.length;
      _claude = claude;
    });
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final updates = ref.watch(updateControllerProvider);
    final claude = ref.watch(claudeHelperProvider);
    final phone = settingsOnPhone;
    const dim = TextStyle(color: AppColors.textDim, fontSize: 12);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 2),
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        );
    Widget toggle(String key, String title, String subtitle, bool value,
            ValueChanged<bool> onChanged, {String? articleId}) =>
        SwitchListTile(
          key: ValueKey(key),
          contentPadding: EdgeInsets.zero,
          title: articleId == null
              ? Text(title)
              : LabelWithHint(title, articleId: articleId),
          subtitle: Text(subtitle, style: dim),
          value: value,
          onChanged: onChanged,
        );
    return ListenableBuilder(
      listenable: Listenable.merge([settings, updates]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          heading('Editing'),
          toggle(
              'settings-snapping',
              'Snap to playhead and edges',
              'What you drag on the timeline stops at the playhead and at '
                  'the edges of clips, sounds and titles.',
              settings.snapping,
              settings.setSnapping,
              articleId: 'snapping'),
          toggle(
              'settings-sound-waves',
              'Show sound waves',
              'The sound drawn on the timeline, and who is speaking. Turn '
                  'off on a slow device.',
              settings.soundWaves,
              settings.setSoundWaves,
              articleId: 'who-is-speaking'),
          if (!phone)
            toggle(
                'settings-side-panel',
                'Show the side panel',
                'The settings at the right of the editor. Hidden, the '
                    'picture gets the room; View > Show the side panel '
                    'brings it back.',
                settings.sidePanel,
                settings.setSidePanel),
          if (phone)
            toggle(
                'settings-smooth-preview',
                'Smooth preview',
                'Lighter video decoding while editing; the preview may look '
                    'a little softer. Exports are not affected.',
                settings.smoothPreview,
                settings.setSmoothPreview,
                articleId: 'phone-speed'),
          if (!phone) ...[
            heading('Text window'),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: Text('Where it opens')),
                SegmentedButton<bool>(
                  key: const ValueKey('settings-text-dock'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('At the right')),
                    ButtonSegment(value: true, label: Text('Below')),
                  ],
                  selected: {settings.textBelow},
                  onSelectionChanged: (v) => settings.setTextBelow(v.first),
                ),
              ],
            ),
          ],
          heading('Export'),
          toggle(
              'settings-graphics-card',
              'Use graphics card (faster)',
              'Remembered between exports. Usually several times quicker; '
                  'if a video ever looks wrong, turn this off.',
              settings.graphicsCard,
              settings.setGraphicsCard,
              articleId: 'graphics-card'),
          heading('Suggestions'),
          toggle(
              'settings-suggestions',
              'Show suggestions',
              'One quiet line with a tip when ClipForge sees something it '
                  'can help with. Never while the video plays.',
              settings.suggestions,
              settings.setSuggestions,
              articleId: 'suggestions'),
          toggle(
              'settings-tips',
              'Show a tip on the project list',
              'One line about something that is easy to miss, a new one '
                  'each day.',
              settings.tips,
              settings.setTips),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('settings-show-hidden'),
              onPressed: (_hidden ?? 0) == 0
                  ? null
                  : () async {
                      final n = await settings.showHiddenHintsAgain();
                      if (!mounted) return;
                      setState(() => _hidden = 0);
                      _say(n == 1
                          ? 'One suggestion can show again.'
                          : '$n suggestions can show again.');
                    },
              child: Text((_hidden ?? 0) == 0
                  ? 'Show hidden suggestions again (none hidden)'
                  : 'Show hidden suggestions again ($_hidden)'),
            ),
          ),
          heading('Updates'),
          toggle(
              'settings-auto-updates',
              'Check for updates automatically',
              'Once a day, quietly. Nothing is installed without asking.',
              updates.autoCheck,
              updates.setAutoCheck),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('settings-check-now'),
              onPressed: () => checkForUpdatesNow(context),
              child: const Text('Check now'),
            ),
          ),
          const VersionLine(
              padding: EdgeInsets.only(top: 8, bottom: 2),
              textAlign: TextAlign.left),
          if (claude.supported) ...[
            heading('Claude'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                key: const ValueKey('settings-claude-status'),
                _claude == null
                    ? 'Checking…'
                    : _claude!.problem != null
                        ? 'The helper for Claude could not be put in place: '
                            '${_claude!.problem}'
                        : _claude!.installed
                            ? 'The helper for Claude is on this computer. '
                                '"Connect…" shows whether Claude uses it.'
                            : 'The helper for Claude is not on this computer '
                                'yet.',
                style: dim,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('settings-connect-claude'),
                onPressed: () => openConnectClaude(context),
                child: const Text('Connect…'),
              ),
            ),
          ],
          heading('About'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-about'),
                onPressed: () => showAboutClipForge(context),
                child: const Text('About ClipForge'),
              ),
              OutlinedButton(
                key: const ValueKey('settings-copy-version'),
                onPressed: () => copyVersionInfo(context),
                child: const Text('Copy version info'),
              ),
              OutlinedButton(
                key: const ValueKey('settings-whats-new'),
                onPressed: () => openHelp(context, articleId: kWhatsNewId),
                child: const Text("What's new"),
              ),
              OutlinedButton(
                key: const ValueKey('settings-send-feedback'),
                onPressed: () => openFeedback(context),
                child: const Text('Send feedback'),
              ),
              OutlinedButton(
                key: const ValueKey('settings-licences'),
                onPressed: () => showLicensePage(
                    context: context, applicationName: kAppName),
                child: const Text('Licences'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
