import 'package:material_ui/material_ui.dart';

import '../help/whats_new.dart';
import '../theme.dart';

// What the project list shows besides the projects (1.18): the "Start"
// row, the "What's new in <version>" card after an update, and one tip.
// Everything is compiled in or read from the bundled CHANGELOG.md:
// nothing comes from the internet, and nothing moves by itself.

/// The tips, one of which is shown on the project list. Short, each about
/// something that is easy to miss. The app's own labels as they are
/// written in the app.
const List<String> kTips = [
  'Press I at the start and O at the end to select a part of the timeline, '
      'then cut it out, silence it or slow it down.',
  'Remove silences finds the pauses in a clip and cuts them out. '
      'It is in the Clip menu.',
  'Recorded each speaker separately? Add the sound files as voices: '
      'ClipForge lines them up with the video by their sound.',
  'Only when speaking turns each microphone down while its speaker is '
      'quiet. It is in the Sound menu.',
  'Press M while the video plays to mark a good moment. '
      'Make shorts from markers turns each one into a short.',
  'Double-click a clip to select exactly its time.',
  'Drop a video file on this page to start a new video with it.',
  'Export > Several at once makes the YouTube, Shorts and WhatsApp '
      'versions in one go, with the text to paste.',
  'The Text window shows every caption as a page of text. '
      'Select a sentence there to cut it out of the video.',
  'Undo goes back as far as you like, and History lists every step '
      'by name.',
  'Share project file packs a project with its videos into one file '
      'for another computer or your phone.',
  'Lower music under speech turns the music down by itself whenever '
      'somebody talks.',
  'Q and W trim the selected clip to the playhead: Q the start, W the end.',
  'Help has a search box: type what you want to do in your own words.',
];

/// The tip for [day]: the same one all day, the next one tomorrow.
String tipFor(DateTime day, {List<String> tips = kTips}) {
  if (tips.isEmpty) return '';
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(2026))
      .inDays;
  return tips[days % tips.length];
}

/// The longest a highlight line is before it is shortened.
const int kHighlightChars = 150;

/// Two or three lines about [version] from the release notes [changelog]
/// (CHANGELOG.md): the first top-level points of its section, each cut to
/// its first sentence, without the `**` marks. Empty when the notes have
/// no section for [version].
List<String> changelogHighlights(String changelog, String version,
    {int max = 3}) {
  final entry = parseChangelog(changelog)
      .where((e) => e.version == version)
      .firstOrNull;
  if (entry == null) return const [];
  final out = <String>[];
  for (final line in entry.body.split('\n')) {
    if (!line.startsWith('- ')) continue; // Top-level points only.
    var text = line.substring(2).replaceAll('**', '').trim();
    // The first sentence; a point that ends in a colon introduces a list.
    final stop = RegExp(r'[.:](\s|$)').firstMatch(text);
    if (stop != null && stop.start >= 20) text = text.substring(0, stop.start);
    if (text.length > kHighlightChars) {
      final cut = text.lastIndexOf(' ', kHighlightChars);
      text = '${text.substring(0, cut < 40 ? kHighlightChars : cut)}…';
    }
    if (text.isEmpty) continue;
    out.add(text);
    if (out.length >= max) break;
  }
  return out;
}

/// One of the big buttons of the "Start" row.
class StartChoice {
  const StartChoice({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final String id;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
}

/// "Start": New video, Podcast, Make a short, side by side: with a line
/// of explanation each on a wide window, compact on a phone.
class StartRow extends StatelessWidget {
  const StartRow({super.key, required this.choices, this.wrapFirst});
  final List<StartChoice> choices;

  /// Wraps the first button (the tour points at "New video").
  final Widget Function(Widget child)? wrapFirst;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 560;
      final tiles = <Widget>[
        for (var i = 0; i < choices.length; i++)
          i == 0 && wrapFirst != null
              ? wrapFirst!(_tile(context, choices[i], narrow))
              : _tile(context, choices[i], narrow),
      ];
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) SizedBox(width: narrow ? 8 : 12),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      );
    });
  }

  Widget _tile(BuildContext context, StartChoice c, bool narrow) {
    final text = Theme.of(context).textTheme;
    final icon = Icon(c.icon,
        size: narrow ? 26 : 32,
        color: c.onTap == null ? AppColors.textDim : AppColors.accent);
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        // A phone has no room for the second line: it is the tooltip.
        message: narrow ? c.detail : '',
        child: InkWell(
          key: ValueKey('start-${c.id}'),
          onTap: c.onTap,
          child: Padding(
            padding: EdgeInsets.all(narrow ? 10 : 16),
            child: narrow
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      const SizedBox(height: 6),
                      Text(c.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: text.labelLarge),
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(c.detail,
                                style: text.bodySmall
                                    ?.copyWith(color: AppColors.textDim)),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// "What's new in 1.18.0": two or three lines and a link to the release
/// notes. Shown once per new version, until it is closed.
class WhatsNewCard extends StatelessWidget {
  const WhatsNewCard({
    super.key,
    required this.version,
    required this.highlights,
    required this.onReadAll,
    required this.onClose,
  });
  final String version;
  final List<String> highlights;
  final VoidCallback onReadAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('updated-line'),
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined,
                    size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("What's new in $version",
                      key: const ValueKey('whats-new-title'),
                      style: text.titleMedium),
                ),
                IconButton(
                  key: const ValueKey('updated-line-close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18, semanticLabel: 'Close'),
                  onPressed: onClose,
                ),
              ],
            ),
            for (final line in highlights)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, right: 10, left: 6),
                      child: Icon(Icons.circle, size: 5, color: AppColors.textDim),
                    ),
                    Expanded(child: Text(line, style: text.bodyMedium)),
                  ],
                ),
              ),
            Row(
              children: [
                Text('Updated to $version',
                    style: text.bodySmall?.copyWith(color: AppColors.textDim)),
                const Spacer(),
                TextButton(
                  key: const ValueKey('updated-line-whats-new'),
                  onPressed: onReadAll,
                  child: const Text('All release notes'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tip: …" with "Don't show tips".
class TipLine extends StatelessWidget {
  const TipLine({super.key, required this.tip, required this.onHide});
  final String tip;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      key: const ValueKey('home-tip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 8),
          child: Icon(Icons.lightbulb_outline, size: 16, color: AppColors.textDim),
        ),
        Expanded(
          child: Text('Tip: $tip',
              style: text.bodySmall?.copyWith(color: AppColors.textDim)),
        ),
        InkWell(
          key: const ValueKey('home-tip-hide'),
          onTap: onHide,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 1, bottom: 4),
            child: Text("Don't show tips",
                style: text.bodySmall?.copyWith(
                    color: AppColors.textDim,
                    decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }
}

/// The line for a Mac whose app is not in the Applications folder.
class MoveToApplicationsLine extends StatelessWidget {
  const MoveToApplicationsLine({
    super.key,
    required this.message,
    required this.onHow,
    required this.onClose,
  });
  final String message;
  final VoidCallback onHow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('move-to-applications'),
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            const Icon(Icons.drive_file_move_outline,
                size: 18, color: AppColors.textDim),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(
              key: const ValueKey('move-to-applications-how'),
              onPressed: onHow,
              child: const Text('Show me how'),
            ),
            IconButton(
              key: const ValueKey('move-to-applications-close'),
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 18, semanticLabel: 'Close'),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
