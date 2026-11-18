import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../theme.dart';
import 'session.dart';

/// "14:32" today, "Mon 14:32" on another day.
String historyTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  if (sameDay) return hm;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[t.weekday - 1]} $hm';
}

/// The steps of the editing history, newest first, with the state the
/// project was opened in at the bottom. The current step is highlighted;
/// steps that were undone are shown faded and can be brought back. A tap
/// jumps to the state after that step (several undos or redos in one go).
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.session, this.onJumped, this.shrinkWrap = false});
  final EditorSession session;

  /// Called after a tap moved to another step (the phone sheet closes).
  final VoidCallback? onJumped;

  /// Sized by its content (inside a sheet that scrolls itself).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final steps = editor.history;
        final position = editor.historyPosition;
        // Newest first; index 0 of the list is the newest step.
        final rows = <Widget>[
          for (var i = steps.length - 1; i >= 0; i--)
            _HistoryRow(
              key: ValueKey('history-step-${i + 1}'),
              label: steps[i].label,
              time: historyTime(steps[i].time),
              current: position == i + 1,
              undone: i + 1 > position,
              onTap: () => _jump(editor, i + 1),
            ),
          _HistoryRow(
            key: const ValueKey('history-step-0'),
            label: steps.length >= EditorController.maxUndoSteps
                ? 'Earlier steps'
                : 'Opened',
            time: '',
            current: position == 0,
            undone: false,
            start: true,
            onTap: () => _jump(editor, 0),
          ),
        ];
        if (steps.isEmpty) {
          rows.insert(
            0,
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                'Your changes will be listed here. Tap one to go back to it.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          );
        }
        return ListView(
          key: const ValueKey('history-list'),
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: rows,
        );
      },
    );
  }

  void _jump(EditorController editor, int position) {
    if (position == editor.historyPosition) return;
    session.playback.pause();
    editor.jumpToHistory(position);
    onJumped?.call();
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.label,
    required this.time,
    required this.current,
    required this.undone,
    required this.onTap,
    this.start = false,
  });
  final String label;
  final String time;
  final bool current;
  final bool undone;
  final bool start;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = undone ? AppColors.textDim : null;
    return Material(
      color: current ? AppColors.accent.withValues(alpha: 0.18) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: current ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
          child: Row(
            children: [
              Icon(
                start
                    ? Icons.flag_outlined
                    : (undone ? Icons.redo : Icons.history_toggle_off),
                size: 16,
                color: undone || start ? AppColors.textDim : AppColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontStyle: undone ? FontStyle.italic : null,
                    fontWeight: current ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(time,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textDim)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide windows: the History column next to the side panel.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('history-panel'),
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('History',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Close history',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => session.showHistory.value = false,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text('Tap a step to go back to it. Later steps stay '
                'until you make a new change.',
                style: TextStyle(fontSize: 11, color: AppColors.textDim)),
          ),
          const Divider(height: 1),
          Expanded(child: HistoryList(session: session)),
        ],
      ),
    );
  }
}

/// Phones: the history in a sheet.
Future<void> showHistorySheet(BuildContext context, EditorSession s) {
  s.playback.pause();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: Colors.black26,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.6),
        child: Column(
          key: const ValueKey('history-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('History',
                  style: Theme.of(sheet).textTheme.titleMedium),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Tap a step to go back to it. Later steps stay '
                  'until you make a new change.',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ),
            Flexible(child: HistoryList(session: s)),
          ],
        ),
      ),
    ),
  );
}
