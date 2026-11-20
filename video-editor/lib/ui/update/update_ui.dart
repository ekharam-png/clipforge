import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/update/tidy_up.dart';
import '../feedback/feedback_screen.dart';
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

/// "Updated to 1.15.0 · What's new": one quiet line on the project list
/// after the app became a newer version (by its own Update or by hand),
/// until it is closed. What's new is one tap.
class UpdatedLine extends StatelessWidget {
  const UpdatedLine({
    super.key,
    required this.version,
    required this.onWhatsNew,
    required this.onClose,
  });
  final String version;
  final VoidCallback onWhatsNew;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        key: const ValueKey('updated-line'),
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Updated to $version',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                key: const ValueKey('updated-line-whats-new'),
                onPressed: onWhatsNew,
                child: const Text("What's new"),
              ),
              IconButton(
                key: const ValueKey('updated-line-close'),
                tooltip: 'Close',
                icon: const Icon(Icons.close,
                    size: 18, semanticLabel: 'Close'),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "Copy details": this version, the app folder and the last lines of the
/// update log go to the clipboard, for a bug report.
Future<void> copyUpdateDetails(BuildContext context, UpdateController c,
    {String? problem}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final text = await c.details(problem: problem);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
        content: Text('Details copied. Paste them into your message.')));
}

/// "Check for updates" (Help menu, Settings; phones: the three dots): asks now and says the
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
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} is downloaded and checked. One '
                  'step is left: ClipForge closes, the old version is '
                  'swapped for the new one, and ClipForge opens again. This '
                  'takes a few seconds. Your projects are not touched.',
                  key: const ValueKey('update-ready')),
              const SizedBox(height: 10),
              Text(
                  c.message ??
                      'If you choose Later, the update is finished by itself '
                          'the next time you start ClipForge. Until then a '
                          'folder ending in ".update-new" sits next to the '
                          'ClipForge folder: leave it there.',
                  key: const ValueKey('update-later-note'),
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ],
          );
          actions
            ..add(TextButton(
                key: const ValueKey('update-later'),
                onPressed: close,
                child: const Text('Later')))
            ..add(FilledButton(
              key: const ValueKey('update-restart'),
              onPressed: c.restartToUpdate,
              child: const Text('Restart ClipForge to finish'),
            ));
        } else if (stage == UpdateStage.handedToSystem) {
          content = const Text('Android is now asking you to confirm the '
              'update. If nothing appeared, tap Update again.');
          actions.add(FilledButton(onPressed: close, child: const Text('OK')));
        } else if (stage == UpdateStage.shownInFinder) {
          content = Text(c.message ?? '');
          actions.add(FilledButton(onPressed: close, child: const Text('OK')));
        } else if (stage == UpdateStage.failed) {
          content = Text(c.message ?? 'The update did not work.',
              key: const ValueKey('update-failed-text'));
          final copy = TextButton(
            key: const ValueKey('update-copy-details'),
            onPressed: () => copyUpdateDetails(context, c, problem: c.message),
            child: const Text('Copy details'),
          );
          // "Send feedback": the page shows what would be sent; the last
          // lines of the update log go along only when ticked there.
          final tell = TextButton(
            key: const ValueKey('update-send-feedback'),
            onPressed: () =>
                openFeedback(context, updateFailed: true, problem: c.message),
            child: const Text('Send feedback'),
          );
          if (c.helperBlocked) {
            // Trying again would end the same way: the download page is
            // the way forward.
            actions
              ..add(tell)
              ..add(copy)
              ..add(TextButton(onPressed: close, child: const Text('Close')))
              ..add(FilledButton(
                key: const ValueKey('update-open-page'),
                onPressed: _openPage,
                child: const Text('Open the download page'),
              ));
          } else {
            actions
              ..add(tell)
              ..add(copy)
              ..add(pageButton)
              ..add(TextButton(onPressed: close, child: const Text('Close')))
              ..add(FilledButton(
                onPressed: c.startUpdate,
                child: const Text('Try again'),
              ));
          }
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


/// Shown once after a start that followed an update: one quiet line when
/// it worked ("Updated to 1.14.0", with What's new), a plain message with
/// the reason and "Try again" / "Open the download page" when it did not.
/// [whatsNew] opens the release notes inside the app.
Future<void> showUpdateOutcome(BuildContext context, UpdateController c,
    {VoidCallback? whatsNew, bool quietSuccess = false}) async {
  final result = c.lastResult;
  if (result == null) return;
  final note = c.folderNote;
  final canRetry = c.pending != null;
  c.clearLastResult();
  if (result.updated && result.wasMove) {
    final dir = c.platform.installDir;
    final name = dir?.split(RegExp(r'[\\/]')).last;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('tidy-done-line'),
        duration: const Duration(seconds: 10),
        persist: false,
        content: Text('Tidied up: ClipForge now runs from the folder '
            '${name == null ? 'you chose' : '"$name"'}. A shortcut you made '
            'to the old folder has to be made again.'),
      ));
    return;
  }
  if (result.updated) {
    // [quietSuccess]: the project list already shows "Updated to X".
    if (quietSuccess && note == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('update-done-line'),
        duration: Duration(seconds: note == null ? 6 : 14),
        persist: false,
        content: Text(
            'Updated to ${result.version.isEmpty ? 'the new version' : result.version}.'
            '${note == null ? '' : ' $note'}'),
        action: whatsNew == null
            ? null
            : SnackBarAction(label: "What's new", onPressed: whatsNew),
      ));
    return;
  }
  final broken = result.status == 'broken';
  final reason = result.message.isEmpty
      ? (result.wasMove
          ? 'ClipForge could not be moved'
          : 'The new version could not be put in place')
      : result.message.replaceFirst(RegExp(r'\.$'), '');
  final logPath = await c.logPath();
  if (!context.mounted) return;
  if (result.wasMove) {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        key: const ValueKey('tidy-failed-dialog'),
        title: const Text('The tidy-up was not finished'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text('$reason. '
              '${broken ? '' : 'ClipForge works as before, from the folder it was in. '}'
              'Nothing of yours was removed.'
              '${logPath == null ? '' : '\n\nThe steps are written down in:\n$logPath'}'),
        ),
        actions: [
          TextButton(
            onPressed: () => copyUpdateDetails(context, c, problem: reason),
            child: const Text('Copy details'),
          ),
          FilledButton(
              onPressed: () => Navigator.of(d).pop(), child: const Text('OK')),
        ],
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      key: const ValueKey('update-failed-dialog'),
      title: const Text('The update was not installed'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Text(
              'The update could not be finished: $reason. '
              '${broken ? '' : 'ClipForge is unchanged and works as before. '}'
              '${canRetry ? 'The download is still here: Try again closes ClipForge and puts the new version in place once more.' : 'You can get the new version from the download page.'}'
              '${logPath == null ? '' : '\n\nThe steps are written down in:\n$logPath'}'),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const ValueKey('update-failed-feedback'),
          onPressed: () =>
              openFeedback(context, updateFailed: true, problem: reason),
          child: const Text('Send feedback'),
        ),
        TextButton(
          key: const ValueKey('update-failed-copy'),
          onPressed: () => copyUpdateDetails(context, c, problem: reason),
          child: const Text('Copy details'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(d).pop();
            await c.dropPending();
            final problem = await c.openDownloadPage();
            if (problem != null && context.mounted) _say(context, problem);
          },
          child: const Text('Open the download page'),
        ),
        TextButton(
          key: const ValueKey('update-failed-later'),
          onPressed: () {
            Navigator.of(d).pop();
            c.dropPending();
          },
          child: const Text('Not now'),
        ),
        if (canRetry)
          FilledButton(
            key: const ValueKey('update-try-again'),
            onPressed: () async {
              Navigator.of(d).pop();
              final problem = await c.finishPending();
              if (problem != null && context.mounted) _say(context, problem);
            },
            child: const Text('Try again'),
          ),
      ],
    ),
  );
}


/// Asks once per version, on Windows, when the app runs from a folder the
/// updater unpacked a download into ("ClipForge-1.12.0.update-new"):
/// "Tidy up?". See lib/core/update/tidy_up.dart for what is proven before
/// anything is offered for removal. Returns true when the app is closing
/// to do it.
Future<bool> offerTidyUp(BuildContext context, UpdateController c,
    {bool evenIfDeclined = false}) async {
  final plan = await c.tidyPlan(evenIfDeclined: evenIfDeclined);
  if (plan == null || !context.mounted) return false;
  final choice = await showDialog<TidyChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TidyDialog(plan: plan),
  );
  if (choice == null) {
    await c.declineTidyUp();
    return false;
  }
  final problem = await c.tidyUp(plan, choice);
  if (problem == null) return true;
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        key: const ValueKey('tidy-not-started'),
        title: const Text('The tidy-up was not started'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(problem),
        ),
        actions: [
          TextButton(
            onPressed: () => copyUpdateDetails(context, c, problem: problem),
            child: const Text('Copy details'),
          ),
          FilledButton(
              onPressed: () => Navigator.of(d).pop(), child: const Text('OK')),
        ],
      ),
    );
  }
  return false;
}

class _TidyDialog extends StatefulWidget {
  const _TidyDialog({required this.plan});
  final TidyPlan plan;

  @override
  State<_TidyDialog> createState() => _TidyDialogState();
}

class _TidyDialogState extends State<_TidyDialog> {
  late TidyTarget? _target = widget.plan.defaultTarget;

  /// Paths of older folders the user unticked.
  final Set<String> _keep = {};

  String _targetLabel(TidyTarget t) => switch (t.state) {
        TidyTargetState.free => 'A new folder called "${t.name}"',
        TidyTargetState.olderClipForge =>
          'The folder "${t.name}" (it holds ClipForge ${t.version!.name}, '
              'which is replaced by this version)',
        TidyTargetState.taken =>
          '"${t.name}": there is already something with this name that is '
              'not an older ClipForge, so it is left alone',
      };

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final target = _target;
    final older = target == null ? const <OlderInstall>[] : plan.removable(target);
    const dim = TextStyle(color: AppColors.textDim, fontSize: 13);
    return AlertDialog(
      key: const ValueKey('tidy-dialog'),
      title: const Text('Tidy up the ClipForge folder?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ClipForge is running from a download folder '
                  '("${plan.runningName}"). Tidy up?'),
              const SizedBox(height: 10),
              Text(
                  target == null
                      ? 'ClipForge cannot do it here: the names it would use '
                          'are taken by something else. You can do it by '
                          'hand: close ClipForge and rename this folder to '
                          '"ClipForge".'
                      : 'An earlier update left this version in the folder '
                          'it was downloaded to. If you say yes, ClipForge '
                          'closes, moves this version (${plan.current.name}) '
                          'to the folder below, and opens again from there. '
                          'Your projects and videos (Documents > ClipForge) '
                          'are not touched.',
                  style: dim),
              const SizedBox(height: 12),
              const Text('Where ClipForge should live:'),
              RadioGroup<String>(
                groupValue: target?.path,
                onChanged: (path) => setState(() => _target =
                    plan.targets.firstWhere((t) => t.path == path)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in plan.targets)
                      RadioListTile<String>(
                        key: ValueKey('tidy-target-${t.name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: t.path,
                        enabled: t.usable,
                        title: Text(_targetLabel(t)),
                      ),
                  ],
                ),
              ),
              if (older.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Older ClipForge folders next to it, to remove:'),
                for (final o in older)
                  CheckboxListTile(
                    key: ValueKey('tidy-remove-${o.name}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: !_keep.contains(o.path),
                    onChanged: (on) => setState(() =>
                        on == true ? _keep.remove(o.path) : _keep.add(o.path)),
                    title: Text('"${o.name}" (ClipForge ${o.version.name})'),
                  ),
                const Text(
                    'Only folders that hold an older ClipForge are listed. '
                    'Untick one to keep it.',
                    style: dim),
              ],
              const SizedBox(height: 10),
              const Text(
                  'There are no desktop or Start-menu shortcuts to fix: '
                  'unpacking the zip makes none. A shortcut you made '
                  'yourself has to be made again.',
                  style: dim),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const ValueKey('tidy-not-now'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('tidy-go'),
          onPressed: target == null
              ? null
              : () => Navigator.of(context).pop(TidyChoice(target, [
                    for (final o in older)
                      if (!_keep.contains(o.path)) o,
                  ])),
          child: const Text('Tidy up and restart'),
        ),
      ],
    );
  }
}
