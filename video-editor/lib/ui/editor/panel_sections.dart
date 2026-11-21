import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app_settings.dart';
import '../theme.dart';

// The collapsible sections of the editor's side panel and of the phone's
// sheets (1.18). One tap or click on a heading opens or closes it; each
// section is remembered by its id across runs of the app (AppSettings,
// settings.json); a closed section whose settings are not the defaults
// shows a small dot, so nothing is hidden silently.

/// The sections that are OPEN until the user closes them: what is used
/// most. Every other section starts closed.
const Set<String> kSectionsOpenByDefault = {
  'clip.sound',
  'clip.speed',
  'overlay.layout',
  'project.fades',
  'project.music',
  'project.shorts',
  'title.style',
  'title.position',
  'sound.level',
  'sound.clean',
  'sound.place',
};

/// A group of settings under a heading that opens and closes.
class PanelSection extends ConsumerWidget {
  const PanelSection({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.icon,
    this.summary = '',
    this.changed = false,
    this.forceOpen = false,
    this.remember = true,
    this.onToggle,
  });

  /// What it is remembered by, e.g. `clip.sound`.
  final String id;
  final String title;
  final IconData? icon;

  /// A few words about the current setting, shown while closed.
  final String summary;

  /// True when something in the section is not at its default: a closed
  /// section then shows a dot.
  final bool changed;

  /// Something asked for this section just now (the Crop button, a
  /// transition mark on the timeline): it is shown open.
  final bool forceOpen;

  /// False: open exactly while [forceOpen] (Crop: an open Crop section
  /// puts the preview in crop mode, so it is never opened from memory).
  final bool remember;

  /// Called with the new state after the heading was used.
  final ValueChanged<bool>? onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final open = forceOpen ||
            (remember &&
                settings.sectionOpen(id,
                    byDefault: kSectionsOpenByDefault.contains(id)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            Semantics(
              button: true,
              expanded: open,
              child: InkWell(
                key: ValueKey('section-$id'),
                onTap: () {
                  if (remember) settings.setSectionOpen(id, !open);
                  onToggle?.call(!open);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: AppColors.textDim),
                        const SizedBox(width: 12),
                      ],
                      Flexible(
                        child: Text(title,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      if (!open && changed)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Tooltip(
                            message: 'Something here was changed',
                            child: Container(
                              key: ValueKey('section-dot-$id'),
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (!open && summary.isNotEmpty)
                        Flexible(
                          child: Text(summary,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textDim, fontSize: 13)),
                        ),
                      const SizedBox(width: 4),
                      Icon(open ? Icons.expand_less : Icons.expand_more,
                          size: 20, color: AppColors.textDim),
                    ],
                  ),
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: child,
              ),
          ],
        );
      },
    );
  }
}
