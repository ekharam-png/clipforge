import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'update_controller.dart';

// What the user sees of updates: the quiet banner on the project list
// ("Version X is available"), the Update window with its progress, and the
// answer to "Check for updates".

/// The banner on the project list. Takes no room when there is nothing to
/// say.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final info = c.available;
        if (info == null || !c.showBanner) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            key: const ValueKey('update-banner'),
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_circle_up_outlined,
                          size: 20, color: AppColors.textDim),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('Version ${info.version} is available',
                            style: text.bodyMedium),
                      ),
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final problem = await c.openNotes();
                          if (problem != null && context.mounted) {
                            _say(context, problem);
                          }
                        },
                        child: const Text("What's new"),
                      ),
                      FilledButton.tonal(
                        onPressed: () => showUpdateDialog(context),
                        child: const Text('Update'),
                      ),
                      TextButton(
                        onPressed: c.later,
                        child: const Text('Later'),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'More about this update',
                        icon: const Icon(Icons.more_vert,
                            size: 20, semanticLabel: 'More about this update'),
                        onSelected: (choice) async {
                          if (choice == 0) {
                            await c.skip();
                            if (context.mounted) {
                              _say(context,
                                  'Version ${info.version} will not be offered '
                                  'again. "Check for updates" still shows it.');
                            }
                          } else {
                            final problem = await c.openDownloadPage();
                            if (problem != null && context.mounted) {
                              _say(context, problem);
                            }
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 0, child: Text('Skip this version')),
                          PopupMenuItem(
                              value: 1, child: Text('Open the download page')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "Check for updates" (Help menu, phones: More): asks now and says the
/// result - the banner when there is a newer version, a plain message
/// otherwise (also when offline).
Future<void> checkForUpdatesNow(BuildContext context) async {
  final c = ProviderScope.containerOf(context).read(updateControllerProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final answer = await c.check(manual: true);
  final text = answer ??
      (c.available == null
          ? null
          : 'Version ${c.available!.version} is available: see the top of '
              'the project list.');
  if (text == null) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The Update window: what will happen, progress, the last step.
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog();

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  late final UpdateController c = ref.read(updateControllerProvider);
  bool? _canInstall;

  @override
  void initState() {
    super.initState();
    // A window opened again after a failure starts from the beginning.
    c.reset(notify: false);
    c.canInstallHere().then((v) {
      if (mounted) setState(() => _canInstall = v);
    });
  }

  String get _intro => switch (c.platform.os) {
        'android' =>
          'ClipForge downloads the new version, checks it, and hands it to '
              'Android, which asks you to confirm the update. The first time, '
              'Android may say that installing from ClipForge is not allowed: '
              'tap Settings there, switch on "Allow from this source", go '
              'back and confirm. Your projects and videos stay as they are.',
        'macos' =>
          'ClipForge downloads the new version, checks it, then closes and '
              'opens again as the new version. Your projects and videos stay '
              'as they are.',
        _ =>
          'ClipForge downloads the new version, checks it, then closes and '
              'opens again as the new version. Your projects and videos '
              '(Documents > ClipForge) stay as they are.',
      };

  Future<void> _openPage() async {
    final problem = await c.openDownloadPage();
    if (problem != null && mounted) _say(context, problem);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final info = c.available;
        final stage = c.stage;
        final working = stage == UpdateStage.downloading ||
            stage == UpdateStage.verifying ||
            stage == UpdateStage.unpacking;
        final Widget content;
        final actions = <Widget>[];
        final pageButton = TextButton(
          onPressed: _openPage,
          child: const Text('Open the download page'),
        );
        void close() => Navigator.of(context).pop();
        if (info == null) {
          content = const Text('There is no update to install.');
          actions.add(FilledButton(onPressed: close, child: const Text('OK')));
        } else if (working) {
          final label = switch (stage) {
            UpdateStage.verifying => 'Checking the download…',
            UpdateStage.unpacking => 'Unpacking…',
            _ => 'Downloading… ${(c.progress * 100).floor()}%',
          };
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                minHeight: 6,
                value: stage == UpdateStage.downloading && c.progress > 0
                    ? c.progress
                    : null,
              ),
              const SizedBox(height: 12),
              const Text('You can keep this window open; nothing changes '
                  'until the download has been checked.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ],
          );
          if (stage == UpdateStage.downloading) {
            actions.add(TextButton(
              onPressed: () async {
                await c.cancelDownload();
                if (context.mounted) close();
              },
              child: const Text('Stop'),
            ));
          }
        } else if (stage == UpdateStage.readyToRestart) {
          content = Text('Version ${info.version} is ready. ClipForge now '
              'closes and opens again as the new version. This takes a few '
              'seconds.');
          actions
            ..add(TextButton(onPressed: close, child: const Text('Not now')))
            ..add(FilledButton(
              key: const ValueKey('update-restart'),
              onPressed: c.restartToUpdate,
              child: const Text('Restart ClipForge'),
            ));
        } else if (stage == UpdateStage.handedToSystem) {
          content = const Text('Android is now asking you to confirm the '
              'update. If nothing appeared, tap Update again.');
          actions.add(FilledButton(onPressed: close, child: const Text('OK')));
        } else if (stage == UpdateStage.shownInFinder) {
          content = Text(c.message ?? '');
          actions.add(FilledButton(onPressed: close, child: const Text('OK')));
        } else if (stage == UpdateStage.failed) {
          content = Text(c.message ?? 'The update did not work.');
          actions
            ..add(pageButton)
            ..add(TextButton(onPressed: close, child: const Text('Close')))
            ..add(FilledButton(
              onPressed: c.startUpdate,
              child: const Text('Try again'),
            ));
        } else {
          final can = _canInstall;
          content = Text(can == false
              ? 'This copy of ClipForge cannot update itself. The download '
                  'page has version ${info.version}: get it there and '
                  'install it over this one.'
              : _intro);
          actions
            ..add(TextButton(onPressed: close, child: const Text('Not now')))
            ..add(can == false
                ? FilledButton(
                    onPressed: () async {
                      await _openPage();
                      if (context.mounted) close();
                    },
                    child: const Text('Open the download page'),
                  )
                : FilledButton(
                    key: const ValueKey('update-start'),
                    onPressed: can == null ? null : c.startUpdate,
                    child: const Text('Download and update'),
                  ));
          if (can != false) actions.insert(0, pageButton);
        }
        return PopScope(
          canPop: !working,
          child: AlertDialog(
            title: Text(info == null
                ? 'Update'
                : 'Update to version ${info.version}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(child: content),
            ),
            actionsOverflowButtonSpacing: 4,
            actions: actions,
          ),
        );
      },
    );
  }
}
