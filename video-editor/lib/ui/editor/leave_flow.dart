import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'session.dart';

/// Why the editor is being left: back to the project list, or the whole app
/// is quitting (window closed, Cmd+Q, Alt+F4). Only the wording differs.
enum LeaveReason { backToProjects, quitApp }

/// The answer to "your latest changes are not saved".
enum SaveFailedChoice { retry, leaveWithoutSaving, stay }

/// Decides whether the editor may be left, asking only when something
/// would be lost:
///
/// 1. Writes pending changes ([flush]).
/// 2. A job is running ([jobs], e.g. an export): [askStopJobs]. Leaving
///    cancels every job that can be cancelled.
/// 3. The save failed ([saveError] not null): [askSaveFailed], which may
///    retry (back to 1) or leave without the latest changes.
///
/// Saved and nothing running: true straight away, no question.
Future<bool> confirmLeave({
  required Future<void> Function() flush,
  required Object? Function() saveError,
  required JobTracker jobs,
  required Future<bool> Function(List<RunningJob> running) askStopJobs,
  required Future<SaveFailedChoice?> Function(Object error) askSaveFailed,
}) async {
  await flush();
  if (!jobs.isEmpty) {
    if (!await askStopJobs(jobs.running)) return false;
    await jobs.cancelAll();
  }
  while (true) {
    final error = saveError();
    if (error == null) return true;
    switch (await askSaveFailed(error)) {
      case SaveFailedChoice.retry:
        await flush();
      case SaveFailedChoice.leaveWithoutSaving:
        return true;
      case SaveFailedChoice.stay:
      case null:
        return false;
    }
  }
}

String _jobName(JobKind kind) => switch (kind) {
      JobKind.export => 'An export',
      JobKind.analysis => 'A sound analysis',
    };

/// "An export is still running. Quit and cancel it?" True to go ahead.
Future<bool> askStopJobs(
  BuildContext context,
  List<RunningJob> running, {
  required LeaveReason reason,
}) async {
  final kinds = {for (final j in running) j.kind};
  final what = kinds.length == 1
      ? _jobName(kinds.single)
      : 'An export and a sound analysis';
  final verb = reason == LeaveReason.quitApp ? 'Quit' : 'Leave';
  final cancelWord = kinds.contains(JobKind.export) ? 'cancel' : 'stop';
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('$what ${kinds.length == 1 ? 'is' : 'are'} still running'),
      content: Text(kinds.contains(JobKind.export)
          ? '$verb and $cancelWord it? The video is not finished yet. '
              'Your project itself is saved.'
          : '$verb and $cancelWord it? Your project itself is saved.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('$verb and $cancelWord it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep working'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The save went wrong: try again, go without the latest changes, or stay.
Future<SaveFailedChoice?> askSaveFailed(
  BuildContext context,
  Object error, {
  required LeaveReason reason,
}) {
  final quit = reason == LeaveReason.quitApp;
  final text = '$error';
  return showDialog<SaveFailedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(quit
          ? 'Your latest changes could not be saved'
          : 'Your latest changes are not saved'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The project could not be written to this device. If '
                'you ${quit ? 'quit' : 'leave'} now, what you changed since '
                'the last save is lost. Check that there is free space, '
                'then try again.'),
            const SizedBox(height: 8),
            Text(text.length > 160 ? '${text.substring(0, 160)}…' : text,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(SaveFailedChoice.leaveWithoutSaving),
          child: Text(quit ? 'Quit without saving' : 'Leave anyway'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(SaveFailedChoice.stay),
          child: const Text('Stay'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(SaveFailedChoice.retry),
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
