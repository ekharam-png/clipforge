// Pure Dart: everything said or written in a project as a readable
// document (the Text window, 1.13). Lines come from the captions on the
// timeline (whatever made them), from the speech transcript or from the
// titles; they are grouped into paragraphs by speaker and by pauses.
// Also: finding text, the document as plain text, and find-and-replace
// over captions. Used by the app and by the MCP tools.

import '../model/project.dart';
import '../transcript/transcript_timeline.dart';

/// Where the lines of a [TextDocument] come from.
enum TextSource { captions, transcript, titles }

/// A pause between two lines from which a new paragraph starts.
const int kParagraphPauseMs = 2000;

/// A paragraph is closed at the end of a line once it is this long, and
/// at the end of a SENTENCE once it is two thirds of it.
const int kParagraphMaxChars = 600;

/// One caption, transcript phrase or title.
class TextLine {
  const TextLine({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.speaker,
    required this.text,
    required this.raw,
    this.named = false,
    this.words = const [],
  });

  /// The caption's / title's id; for a transcript phrase a made-up one.
  final String id;
  final int startMs;
  final int endMs;

  /// Who says it ('' when not known).
  final String speaker;

  /// What is read: one line, the speaker's name taken off.
  final String text;

  /// The text as it is stored (captions: with line breaks and name).
  final String raw;

  /// The line itself starts with the speaker's name ("Sam: …").
  final bool named;

  /// Transcript phrases: the words with their times.
  final List<TimelineWord> words;
}

/// Lines of one speaker that follow each other without a long pause.
class TextParagraph {
  TextParagraph(this.index, this.firstLine, this.lines);
  final int index;

  /// Index of [lines].first in [TextDocument.lines].
  final int firstLine;
  final List<TextLine> lines;
  String get speaker => lines.first.speaker;
  int get startMs => lines.first.startMs;
  int get endMs => lines.last.endMs;

  /// The lines joined with spaces, and where each starts in it.
  late final String text = lines.map((l) => l.text).join(' ');
  late final List<int> offsets = () {
    final out = <int>[];
    var at = 0;
    for (final l in lines) {
      out.add(at);
      at += l.text.length + 1;
    }
    return out;
  }();
}

class TextDocument {
  TextDocument(this.source, this.lines, this.paragraphs)
      : _indexOf = {for (var i = 0; i < lines.length; i++) lines[i].id: i},
        paragraphOfLine = [
          for (final p in paragraphs)
            for (var i = 0; i < p.lines.length; i++) p.index,
        ];

  static final TextDocument empty =
      TextDocument(TextSource.captions, const [], const []);

  final TextSource source;

  /// In time order.
  final List<TextLine> lines;
  final List<TextParagraph> paragraphs;
  final Map<String, int> _indexOf;

  /// For every line, the index of its paragraph.
  final List<int> paragraphOfLine;

  bool get isEmpty => lines.isEmpty;

  /// Index of the line with [id], or -1.
  int indexOf(String id) => _indexOf[id] ?? -1;

  /// The speakers in order of first appearance (without '').
  late final List<String> speakers = () {
    final seen = <String>{};
    return [
      for (final l in lines)
        if (l.speaker.isNotEmpty && seen.add(l.speaker)) l.speaker,
    ];
  }();

  /// Index of the last line that starts at or before [ms]; -1 before the
  /// first.
  int lineIndexBefore(int ms) {
    var lo = 0, hi = lines.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startMs <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  /// Index of the line that is on screen / being said at [ms]: the latest
  /// one that has started and not yet ended; -1 in a pause.
  int activeLineAt(int ms) {
    // Captions on two rows can overlap: look a few lines back.
    final last = lineIndexBefore(ms);
    for (var i = last; i >= 0 && i > last - 4; i--) {
      if (ms < lines[i].endMs) return i;
    }
    return -1;
  }
}

final RegExp _speakerRe =
    RegExp(r'^\s*(?:[-–—>]+\s*)?([^\s:：][^:：\n]{0,39})[:：]\s+(\S[\s\S]*)$');
final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _space = RegExp(r'\s+');

/// "Sam: it's okay" -> (Sam, "it's okay"). A name is at most four words
/// and 40 characters, starts with a letter and holds no sentence
/// punctuation; anything else ("10:30", "Note that: x. y: z") is plain
/// text with no speaker.
({String speaker, String text}) splitSpeaker(String raw) {
  final flat = raw.replaceAll(_space, ' ').trim();
  final m = _speakerRe.firstMatch(flat);
  if (m != null) {
    final name = m.group(1)!.trim();
    final okStart = _letter.matchAsPrefix(name) != null;
    if (okStart &&
        name.split(' ').length <= 4 &&
        !RegExp(r'[.,;!?…"“”()\[\]/]').hasMatch(name)) {
      return (speaker: name, text: m.group(2)!.trim());
    }
  }
  return (speaker: '', text: flat);
}

List<TitleOverlay> _sorted(Project p, TitleKind kind) {
  final list = [
    for (final t in p.titles)
      if (t.kind == kind) t,
  ];
  // Stable by start.
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final d = a.$2.startMs.compareTo(b.$2.startMs);
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// The captions of [p] as lines. A caption that starts with "Name:" is
/// that speaker's; captions without a name belong to whoever spoke last
/// (subtitle files often name the speaker only when it changes).
List<TextLine> captionLines(Project p) {
  final out = <TextLine>[];
  var current = '';
  for (final t in _sorted(p, TitleKind.caption)) {
    final s = splitSpeaker(t.text);
    if (s.speaker.isNotEmpty) current = s.speaker;
    out.add(TextLine(
      id: t.id,
      startMs: t.startMs,
      endMs: t.endMs,
      speaker: current,
      text: s.text,
      raw: t.text,
      named: s.speaker.isNotEmpty,
    ));
  }
  return out;
}

/// The plain titles of [p] as lines (no speakers).
List<TextLine> titleLines(Project p) => [
      for (final t in _sorted(p, TitleKind.title))
        TextLine(
          id: t.id,
          startMs: t.startMs,
          endMs: t.endMs,
          speaker: '',
          text: t.text.replaceAll(_space, ' ').trim(),
          raw: t.text,
        ),
    ];

/// Transcript phrases as lines.
List<TextLine> transcriptLines(List<TimelineSegment> segments) => [
      for (var i = 0; i < segments.length; i++)
        TextLine(
          id: 'phrase-$i-${segments[i].startMs}',
          startMs: segments[i].startMs,
          endMs: segments[i].endMs,
          speaker: segments[i].speaker,
          text: segments[i].text,
          raw: segments[i].text,
          words: segments[i].words,
        ),
    ];

final RegExp _sentenceEnd = RegExp(r'[.!?…。؟]["”»)]?$');

/// Groups [lines] (in time order) into paragraphs: a new one where the
/// speaker changes, after a pause of [pauseMs], and when one gets long.
/// Titles ([TextSource.titles]) are one paragraph each.
TextDocument buildTextDocument(TextSource source, List<TextLine> lines,
    {int pauseMs = kParagraphPauseMs, int maxChars = kParagraphMaxChars}) {
  final paragraphs = <TextParagraph>[];
  var open = <TextLine>[];
  var first = 0;
  var chars = 0;
  void close(int next) {
    if (open.isEmpty) return;
    paragraphs.add(TextParagraph(paragraphs.length, first, open));
    open = <TextLine>[];
    first = next;
    chars = 0;
  }

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (open.isNotEmpty) {
      final prev = open.last;
      final full = chars >= maxChars ||
          (chars >= maxChars * 2 ~/ 3 && _sentenceEnd.hasMatch(prev.text));
      if (source == TextSource.titles ||
          l.speaker != prev.speaker ||
          l.startMs - prev.endMs >= pauseMs ||
          full) {
        close(i);
      }
    }
    open.add(l);
    chars += l.text.length + 1;
  }
  close(lines.length);
  return TextDocument(source, List.unmodifiable(lines), paragraphs);
}

/// A place where the search text was found.
class TextMatch {
  const TextMatch(this.line, this.start, this.end);

  /// Index in [TextDocument.lines]; [start]..[end] in that line's text.
  final int line;
  final int start;
  final int end;
}

/// Every place [query] occurs in the lines' text (case does not matter;
/// several spaces count as one). Empty for an empty query.
List<TextMatch> findInText(TextDocument doc, String query) {
  final q = query.replaceAll(_space, ' ').trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <TextMatch>[];
  for (var i = 0; i < doc.lines.length; i++) {
    final text = doc.lines[i].text.toLowerCase();
    // toLowerCase can change the length of a few exotic letters; then the
    // positions would be off, so such a line is matched as a whole.
    final same = text.length == doc.lines[i].text.length;
    var at = text.indexOf(q);
    while (at >= 0) {
      out.add(same ? TextMatch(i, at, at + q.length) : TextMatch(i, 0, text.length));
      if (!same) break;
      at = text.indexOf(q, at + q.length);
    }
  }
  return out;
}

String _clock(int ms) {
  if (ms < 0) ms = 0;
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s ~/ 60) % 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// The document as plain text, one paragraph per block: optionally with
/// the time ("[1:05]") and the speaker's name in front.
String documentAsText(TextDocument doc,
    {bool times = false, bool speakers = true}) {
  final b = StringBuffer();
  String? last;
  for (final p in doc.paragraphs) {
    final head = [
      if (times) '[${_clock(p.startMs)}]',
      if (speakers && p.speaker.isNotEmpty && (times || p.speaker != last))
        '${p.speaker}:',
    ].join(' ');
    last = p.speaker;
    if (b.isNotEmpty) b.write('\n\n');
    b.write(head.isEmpty ? p.text : '$head ${p.text}');
  }
  if (b.isNotEmpty) b.write('\n');
  return b.toString();
}

/// Where the Text window should scroll to so that something between
/// [top] and [bottom] (content coordinates) is comfortably in view, or
/// null when it already is. [offset]: the scroll position, [viewport]:
/// the height shown, [maxOffset]: the furthest it can scroll.
double? followOffset({
  required double top,
  required double bottom,
  required double offset,
  required double viewport,
  required double maxOffset,
}) {
  if (viewport <= 0) return null;
  const pad = 8.0;
  // In view: not above the top, and not lower than four fifths down
  // (while playing, the text ahead should be readable).
  final lowest = offset + viewport * 0.8;
  if (top >= offset + pad && bottom <= lowest) return null;
  // Taller than the comfortable band but fully visible: leave it.
  if (top >= offset + pad && bottom <= offset + viewport - pad &&
      bottom - top > viewport * 0.6) {
    return null;
  }
  final target = (top - viewport * 0.25).clamp(0.0, maxOffset < 0 ? 0.0 : maxOffset);
  return (target - offset).abs() < 1 ? null : target.toDouble();
}

/// What a find-and-replace over captions would change.
class CaptionReplacement {
  const CaptionReplacement(this.before, this.after, this.count);
  final TitleOverlay before;
  final TitleOverlay after;

  /// Places changed in this caption.
  final int count;
}

/// Replaces [find] by [replace] in the captions of [p] (those that start
/// inside [fromMs]..[toMs] when given). [wholeWord]: only where it is not
/// part of a longer word. Captions that would become empty are left
/// alone (reported in `skipped`).
({List<CaptionReplacement> changes, int total, int skipped}) replaceInCaptions(
  Project p,
  String find,
  String replace, {
  bool caseSensitive = false,
  bool wholeWord = false,
  int? fromMs,
  int? toMs,
  bool titlesToo = false,
}) {
  if (find.isEmpty) return (changes: const [], total: 0, skipped: 0);
  var pattern = RegExp.escape(find);
  if (wholeWord) {
    pattern = '(?<![\\p{L}\\p{N}_])$pattern(?![\\p{L}\\p{N}_])';
  }
  final re = RegExp(pattern, caseSensitive: caseSensitive, unicode: true);
  final changes = <CaptionReplacement>[];
  var total = 0, skipped = 0;
  for (final t in p.titles) {
    if (t.kind != TitleKind.caption && !titlesToo) continue;
    if (fromMs != null && t.startMs < fromMs) continue;
    if (toMs != null && t.startMs >= toMs) continue;
    final n = re.allMatches(t.text).length;
    if (n == 0) continue;
    final text = t.text.replaceAll(re, replace);
    if (text.trim().isEmpty) {
      skipped++;
      continue;
    }
    if (text == t.text) continue;
    total += n;
    changes.add(CaptionReplacement(t, t.copyWith(text: text), n));
  }
  return (changes: changes, total: total, skipped: skipped);
}
