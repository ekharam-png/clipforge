import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'session.dart';

/// The small save indicator of the editor's top bar: "Saved" (the time on
/// hover or tap), "Saving…", or "Not saved" (tap to try again). [compact]
/// (phones) shows the icon only; its name is still read out and shown on
/// tap.
class SaveStatusIndicator extends StatelessWidget {
  const SaveStatusIndicator({
    super.key,
    required this.status,
    required this.onRetry,
    this.compact = false,
  });

  final ValueListenable<SaveStatus> status;
  final VoidCallback onRetry;
  final bool compact;

  static const Color _warn = Color(0xFFFFC56B);

  /// The words for [s], short and long (for the tooltip).
  static ({String label, String detail}) describe(
      SaveStatus s, MaterialLocalizations l) {
    switch (s.state) {
      case SaveState.saving:
        return (label: 'Saving…', detail: 'Saving your latest changes…');
      case SaveState.failed:
        return (
          label: 'Not saved',
          detail: 'Your latest changes are not saved yet. Tap to try again.'
        );
      case SaveState.saved:
        final at = s.savedAt;
        return (
          label: 'Saved',
          detail: at == null
              ? 'All changes are saved on this device.'
              : 'All changes saved at '
                  '${l.formatTimeOfDay(TimeOfDay.fromDateTime(at))}.'
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SaveStatus>(
      valueListenable: status,
      builder: (context, s, _) {
        final words = describe(s, MaterialLocalizations.of(context));
        final (icon, color) = switch (s.state) {
          SaveState.saved => (Icons.cloud_done_outlined, AppColors.textDim),
          SaveState.saving => (Icons.cloud_upload_outlined, AppColors.textDim),
          SaveState.failed => (Icons.cloud_off, _warn),
        };
        final failed = s.state == SaveState.failed;
        Widget content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(words.label,
                  style: TextStyle(fontSize: 12, color: color)),
            ],
          ],
        );
        content = Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 8),
          child: content,
        );
        return Semantics(
          container: true,
          button: failed,
          label: words.label,
          hint: words.detail,
          excludeSemantics: true,
          onTap: failed ? onRetry : null,
          child: Tooltip(
            message: words.detail,
            triggerMode: TooltipTriggerMode.tap,
            child: failed
                ? InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onRetry,
                    child: content,
                  )
                : content,
          ),
        );
      },
    );
  }
}
