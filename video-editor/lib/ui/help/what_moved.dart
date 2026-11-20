import 'package:material_ui/material_ui.dart';

import '../settings/settings_screen.dart';
import '../theme.dart';
import 'help_screen.dart';
import 'whats_new.dart' show kWhatsNewId;

// "What moved" (1.15): shown once, the first time a version from 1.15 on
// starts on a device that ran an older one. The menus and the phone's bars
// were reorganised; this lists the biggest moves so nothing seems gone.

/// The moves, as (what, where it is now): computers first, then phones.
const List<(String, String)> kWhatMovedComputer = [
  ('Settings', 'One page: File > Settings… (Ctrl or Cmd + ,)'),
  ('Adding things', 'The new Add menu: videos, music, voice, titles, '
      'captions, overlays, markers'),
  ('Split, trim, freeze, crop', 'The new Clip menu'),
  ('Everything about sound', 'The new Sound menu'),
  ('Text window and speech', 'The new Text and speech menu'),
  ('Zoom, snapping, sound waves, shape, video size', 'The new View menu'),
  ('Check for updates automatically', 'Settings > Updates'),
  ('Right-click on the timeline', 'A menu with what you can do with that '
      'clip, sound or title'),
  kKeysMoved117,
];

/// 1.17: the one shortcut that changed its meaning.
const (String, String) kKeysMoved117 = (
  'The I and O keys',
  'Now mark the start and end of a selected part (the new Part menu). '
      'To trim the clip to the playhead: Q and W (Clip menu)'
);

/// True when [version] ("1.16.0") is older than 1.[minor], or unknown.
bool olderThanMinor(String? version, int minor) {
  if (version == null) return true;
  final parts = version.split('.');
  final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return major < 1 || (major == 1 && m < minor);
}

/// The one-time note of 1.17 for people who come from 1.15 or 1.16 (the
/// bigger "What moved" has the same line for older versions): I and O
/// changed their meaning. Computers only; phones have no keys.
Future<void> showKeysMoved(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const ValueKey('keys-moved-dialog'),
      title: const Text('Two keys changed'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: const Text(
          'I and O now mark the start and the end of a selected part of '
          'the timeline, as in most editors. With a part selected you can '
          'cut it out, silence it or slow it down (the new Part menu).\n\n'
          'To make the clip start or end at the playhead, which I and O '
          'did until now, press Q and W. Both are still in the Clip menu.',
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('keys-moved-help'),
          onPressed: () {
            Navigator.of(dialog).pop();
            openHelp(context, articleId: 'select-a-part');
          },
          child: const Text('Select a part'),
        ),
        FilledButton(
          key: const ValueKey('keys-moved-ok'),
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

const List<(String, String)> kWhatMovedPhone = [
  ('Add', 'One button at the bottom lists everything you can add'),
  ('Text', 'Has its own button at the bottom'),
  ('Shape, fades, notes, History', 'The three dots at the top of a project'),
  ('Settings', 'One page: the three dots on the project list or in a '
      'project'),
  ('Sound waves, smooth preview', 'Settings > Editing'),
  ('More', 'Now grouped: Clip, Sound, Text'),
  ('Hold a clip, sound or title', 'A list of what you can do with it'),
  ('Trim start / end to here', 'More, under Clip'),
];

/// True when [version] ("1.14.1") is older than 1.15, or unknown.
bool olderThan115(String? version) {
  if (version == null) return true;
  final parts = version.split('.');
  final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minor = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return major < 1 || (major == 1 && minor < 15);
}

/// The one-time note. "Show me Settings" opens Settings; "What's new"
/// opens the release notes.
Future<void> showWhatMoved(BuildContext context) {
  final phone = MediaQuery.sizeOf(context).width < 700;
  final moves = phone ? kWhatMovedPhone : kWhatMovedComputer;
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const ValueKey('what-moved-dialog'),
      title: const Text('Things are easier to find now'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nothing was removed. Some things have a new place:',
              ),
              const SizedBox(height: 10),
              for (final (what, where) in moves)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$what  ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: where,
                        style: const TextStyle(color: AppColors.textDim)),
                  ])),
                ),
              const SizedBox(height: 8),
              const Text(
                'An item you cannot use right now stays in its menu and '
                'says why.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const ValueKey('what-moved-whats-new'),
          onPressed: () {
            Navigator.of(dialog).pop();
            openHelp(context, articleId: kWhatsNewId);
          },
          child: const Text("What's new"),
        ),
        TextButton(
          key: const ValueKey('what-moved-settings'),
          onPressed: () {
            Navigator.of(dialog).pop();
            openSettings(context);
          },
          child: const Text('Show me Settings'),
        ),
        FilledButton(
          key: const ValueKey('what-moved-ok'),
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
