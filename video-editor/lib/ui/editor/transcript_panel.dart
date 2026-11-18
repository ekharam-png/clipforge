// The read-only "Transcript" column (1.11, computers only): what is said,
// phrase by phrase, with times and speakers; click a phrase to go there;
// a search box. The text cannot be edited here - cutting by text is
// Claude's job (see docs/HANDOVER.md).

import 'package:material_ui/material_ui.dart';

import '../../core/model/project.dart';
import '../format.dart';
import '../speech/speech_service.dart';
import '../theme.dart';
import 'session.dart';
import 'speech_actions.dart';

class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({super.key, required this.session});
  final EditorSession session;

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final _search = TextEditingController();
  Project? _for;
  Map<String, Transcript>? _with;
  List<TimelineSegment> _segments = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The phrases of the project as it is cut now (worked out again only
  /// when the project or the transcripts changed).
  List<TimelineSegment> _phrases() {
    final s = widget.session;
    if (!identical(_for, s.project) || !identical(_with, s.transcripts.value)) {
      _for = s.project;
      _with = s.transcripts.value;
      _segments = timelineSegments(timelineWords(s.project, s.transcriptOf));
    }
    return _segments;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Container(
      key: const ValueKey('transcript-panel'),
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                const Icon(Icons.subject, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Transcript',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Close transcript',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => s.showTranscript.value = false,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: const ValueKey('transcript-search'),
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find a word…',
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 0),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([s.editor, s.transcripts]),
              builder: (context, _) {
                final all = _phrases();
                if (s.transcripts.value.isEmpty || all.isEmpty) {
                  return _Empty(session: s, any: s.transcripts.value.isNotEmpty);
                }
                final query = plainWord(_search.text);
                final shown = query.isEmpty
                    ? all
                    : [
                        for (final seg in all)
                          if (plainWord(seg.text).contains(query)) seg,
                      ];
                if (shown.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('“${_search.text.trim()}” is not said in this '
                        'video.',
                        key: const ValueKey('transcript-no-match'),
                        style: const TextStyle(color: AppColors.textDim)),
                  );
                }
                return ListView.builder(
                  key: const ValueKey('transcript-list'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: shown.length + (query.isEmpty ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (query.isNotEmpty && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Text(
                            'Said in ${shown.length} '
                            '${shown.length == 1 ? 'place' : 'places'}',
                            key: const ValueKey('transcript-matches'),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textDim)),
                      );
                    }
                    final seg = shown[query.isEmpty ? i : i - 1];
                    return _PhraseRow(
                      key: ValueKey('phrase-${seg.startMs}-${seg.speaker}'),
                      segment: seg,
                      onTap: () {
                        s.playback.pause();
                        s.playback.seek(seg.startMs);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({super.key, required this.segment, required this.onTap});
  final TimelineSegment segment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(formatDuration(segment.startMs),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.accent,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (segment.speaker.isNotEmpty)
                    Text(segment.speaker,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDim)),
                  // The text's own direction: Hebrew reads right to left.
                  Text(segment.text,
                      textDirection: _direction(segment.text),
                      style: const TextStyle(fontSize: 13, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextDirection _direction(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x52F)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

class _Empty extends StatelessWidget {
  const _Empty({required this.session, required this.any});
  final EditorSession session;

  /// There are transcripts, but nothing of them is in the video now.
  final bool any;

  @override
  Widget build(BuildContext context) {
    final can = canTranscribe(session.project);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              any
                  ? 'Nothing is said in the video as it is cut now.'
                  : can
                      ? 'No transcript yet. Transcribe the speech to read '
                          'here what is said, jump to a phrase and search.'
                      : 'Add a video with sound first; then its speech can '
                          'be transcribed.',
              key: const ValueKey('transcript-empty'),
              style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 12),
          if (can && !any)
            OutlinedButton.icon(
              key: const ValueKey('transcript-transcribe'),
              onPressed: () => showTranscribeDialog(context, session),
              icon: const Icon(Icons.record_voice_over_outlined, size: 18),
              label: const Text('Transcribe speech…'),
            ),
        ],
      ),
    );
  }
}
