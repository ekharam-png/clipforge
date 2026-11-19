// "Publishing notes" (1.14): the text that goes with the video when the
// user posts it - title, description, hashtags, chapters, and an optional
// shorter title and description for Shorts / Reels / TikTok. Every field
// has a Copy button. Nothing is ever posted from here: ClipForge has no
// logins and uploads nothing.
//
// Reached from the Export window and from the project menu (File >
// Publishing notes…; phones: More). A dialog on computers, a full-screen
// page on phones.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/model/project.dart';
import '../../core/music/openverse.dart' show creditsText;
import '../../core/publish/chapters.dart';
import '../help/help_screen.dart';
import '../theme.dart';

/// Who speaks when, for chapters of a project without titles or captions.
typedef SpeakerTurns = List<({String name, int startMs, int endMs})>;

/// Opens the notes of [project] (asked for again after every change, so
/// it is always the current one). [onChanged] stores them (one undo step
/// each time a field is left).
Future<void> showPublishingNotes(
  BuildContext context, {
  required Project Function() project,
  required ValueChanged<PublishingNotes> onChanged,
  SpeakerTurns Function()? turns,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  final panel = PublishingNotesPanel(
      project: project, onChanged: onChanged, turns: turns);
  return showDialog<void>(
    context: context,
    builder: (_) => phone
        ? Dialog.fullscreen(child: panel)
        : Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              child: panel,
            ),
          ),
  );
}

class PublishingNotesPanel extends StatefulWidget {
  const PublishingNotesPanel({
    super.key,
    required this.project,
    required this.onChanged,
    this.turns,
  });
  final Project Function() project;
  final ValueChanged<PublishingNotes> onChanged;
  final SpeakerTurns Function()? turns;

  @override
  State<PublishingNotesPanel> createState() => _PublishingNotesPanelState();
}

class _PublishingNotesPanelState extends State<PublishingNotesPanel> {
  late final PublishingNotes _start = widget.project().publishing;
  late final _title = TextEditingController(text: _start.title);
  late final _description = TextEditingController(text: _start.description);
  late final _hashtags = TextEditingController(text: _start.hashtagLine);
  late final _chapters =
      TextEditingController(text: formatChapters(_start.chapters));
  late final _shortTitle = TextEditingController(text: _start.shortTitle);
  late final _shortDescription =
      TextEditingController(text: _start.shortDescription);
  late bool _showShort = _start.shortTitle.isNotEmpty ||
      _start.shortDescription.isNotEmpty;
  String? _chapterNote;
  String? _copied;

  PublishingNotes get _notes => PublishingNotes(
        title: _title.text.trim(),
        description: _description.text.trim(),
        hashtags: parseHashtags(_hashtags.text),
        chapters: parseChapters(_chapters.text),
        shortTitle: _shortTitle.text.trim(),
        shortDescription: _shortDescription.text.trim(),
      );

  /// Stores what the fields hold now (nothing happens when it is what the
  /// project already has).
  void _commit() {
    final next = _notes;
    if (next != widget.project().publishing) widget.onChanged(next);
  }

  @override
  void dispose() {
    for (final c in [
      _title, _description, _hashtags, _chapters, _shortTitle, //
      _shortDescription,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _copy(String what, String text) async {
    _commit();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = what);
  }

  Future<void> _makeChapters() async {
    _commit();
    final project = widget.project();
    final built =
        buildChapters(project, turns: widget.turns?.call() ?? const []);
    if (built.chapters.isEmpty) {
      setState(() => _chapterNote = project.durationMs < 30000
          ? 'This video is too short for chapters (each is at least '
              '${kChapterRules.minGapMs ~/ 1000} seconds).'
          : 'Nothing to make chapters from yet: add titles where the parts '
              'begin, or captions, then try again.');
      return;
    }
    if (_chapters.text.trim().isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Replace the chapters?'),
          content: Text('The ${parseChapters(_chapters.text).length} '
              'chapters you have now are replaced by '
              '${built.chapters.length} new ones. Undo brings them back.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(d).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                key: const ValueKey('chapters-replace'),
                onPressed: () => Navigator.of(d).pop(true),
                child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _chapters.text = formatChapters(built.chapters);
      _chapterNote = switch (built.source) {
        ChapterSource.titles =>
          '${built.chapters.length} chapters from your titles.',
        ChapterSource.captions =>
          '${built.chapters.length} chapters from the captions, named by '
              'the first words said. Give them better names.',
        ChapterSource.speakers =>
          '${built.chapters.length} chapters from who is speaking. Give '
              'them names.',
        ChapterSource.none => null,
      };
    });
    _commit();
  }

  Widget _field(
    String label,
    String id,
    TextEditingController c, {
    int lines = 1,
    String? hint,
    String Function()? copyText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment:
            lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Focus(
              // Leaving a field stores it: one History step per field.
              onFocusChange: (has) {
                if (!has) _commit();
              },
              child: TextField(
                key: ValueKey('notes-$id'),
                controller: c,
                minLines: lines,
                maxLines: lines == 1 ? 1 : lines + 4,
                textInputAction:
                    lines == 1 ? TextInputAction.next : TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_copied != null) setState(() => _copied = null);
                },
              ),
            ),
          ),
          IconButton(
            key: ValueKey('notes-copy-$id'),
            tooltip: 'Copy ${label.toLowerCase()}',
            icon: Icon(_copied == id ? Icons.check : Icons.copy, size: 20,
                semanticLabel: 'Copy ${label.toLowerCase()}'),
            onPressed: () => _copy(id, (copyText ?? () => c.text.trim())()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final project = widget.project();
    final problems =
        chapterProblems(parseChapters(_chapters.text), project.durationMs);
    final credits = creditsText(project);
    return PopScope(
      onPopInvokedWithResult: (_, _) => _commit(),
      child: Column(
        key: const ValueKey('notes-panel'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Publishing notes', style: text.titleLarge),
                ),
                IconButton(
                  tooltip: 'Help',
                  icon: const Icon(Icons.help_outline, semanticLabel: 'Help'),
                  onPressed: () => showHelpArticle(context, 'publishing-notes'),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, right: 12),
                    child: Text(
                      'The text to paste when you post the video. ClipForge '
                      'does not post anything itself: copy from here, or '
                      'from the text file saved next to the exported video.',
                      style: text.bodySmall?.copyWith(color: AppColors.textDim),
                    ),
                  ),
                  _field('Title', 'title', _title),
                  _field('Description', 'description', _description, lines: 4),
                  _field('Hashtags', 'hashtags', _hashtags,
                      hint: 'bread baking sourdough',
                      copyText: () => parseHashtags(_hashtags.text)
                          .map((h) => '#$h')
                          .join(' ')),
                  _field('Chapters', 'chapters', _chapters,
                      lines: 4,
                      hint: '0:00 Start\n1:20 The recipe\n4:05 Tasting',
                      copyText: () =>
                          formatChapters(parseChapters(_chapters.text))),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, right: 12),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('notes-make-chapters'),
                          onPressed: _makeChapters,
                          icon: const Icon(Icons.format_list_numbered, size: 18),
                          label: const Text('Chapters from titles / captions…'),
                        ),
                        if (_chapterNote != null)
                          Text(_chapterNote!,
                              key: const ValueKey('notes-chapter-note'),
                              style: text.bodySmall),
                        if (problems.isNotEmpty)
                          Text(problems.join(' '),
                              key: const ValueKey('notes-chapter-problem'),
                              style: text.bodySmall
                                  ?.copyWith(color: const Color(0xFFFFC56B))),
                      ],
                    ),
                  ),
                  if (!_showShort)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('notes-show-short'),
                        onPressed: () => setState(() => _showShort = true),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                            'A different title for Shorts, Reels and TikTok'),
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: Text('For Shorts, Reels and TikTok (optional)',
                          style: text.labelLarge),
                    ),
                    _field('Short title', 'short-title', _shortTitle),
                    _field('Short description', 'short-description',
                        _shortDescription,
                        lines: 2),
                  ],
                  if (credits.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 12),
                      child: Text(
                          'Music credits are added by themselves when you '
                          'copy the description:\n$credits',
                          key: const ValueKey('notes-credits'),
                          style:
                              text.bodySmall?.copyWith(color: AppColors.textDim)),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('notes-copy-all'),
                    onPressed: () {
                      _commit();
                      _copy('all', titleAndDescription(widget.project()));
                    },
                    icon: Icon(_copied == 'all' ? Icons.check : Icons.copy_all,
                        size: 18),
                    label: const FittedBox(
                        child: Text('Copy title and description')),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('notes-done'),
                  onPressed: () {
                    _commit();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
