// "Captions from speech": turns the words on the timeline into caption
// cues. Pure Dart.
//
// Rules (the usual subtitle guidelines): one or two lines of at most
// [CaptionOptions.maxLineChars] characters (32..42 is the comfortable
// range), a new caption at the end of a sentence, at a pause and when the
// speaker changes; a comma is preferred when a long sentence has to be
// split; never shorter than [CaptionOptions.minMs] where there is room and
// never longer than [CaptionOptions.maxMs]; captions never overlap.
//
// The text is kept in reading (logical) order for every language. Hebrew
// and Arabic are right-to-left: the drawing side (title_layout.dart
// `bidiLine`, used by preview and export) takes care of the direction, so
// nothing here reverses anything, and line length is counted in characters
// the same way.

import '../model/project.dart';
import '../model/title_layout.dart';
import 'transcript.dart' show endsClause, endsSentence;
import 'transcript_timeline.dart';

class CaptionOptions {
  const CaptionOptions({
    this.maxLineChars = 37,
    this.maxLines = 2,
    this.minMs = 1000,
    this.maxMs = 6000,
    this.pauseMs = 600,
    this.lingerMs = 200,
    this.gapMs = 40,
  });

  /// Longest line, in characters (clamped to 12..60).
  final int maxLineChars;

  /// 1 or 2.
  final int maxLines;
  final int minMs;
  final int maxMs;

  /// A silence this long starts a new caption.
  final int pauseMs;

  /// How long a caption stays after its last word (where there is room).
  final int lingerMs;

  /// Smallest gap kept between two captions.
  final int gapMs;

  int get lineChars => maxLineChars < 12 ? 12 : (maxLineChars > 60 ? 60 : maxLineChars);
  int get lines => maxLines <= 1 ? 1 : 2;
}

class CaptionCue {
  const CaptionCue(this.startMs, this.endMs, this.text, this.speaker);
  final int startMs;
  final int endMs;

  /// One or two lines (joined with a line break).
  final String text;
  final String speaker;
}

/// Wraps [words] greedily into lines of at most [maxChars] characters (a
/// single longer word gets a line of its own); [fits], when given, must
/// also accept every line (the real width on the canvas).
List<String> _wrap(List<String> words, int maxChars, bool Function(String line)? fits) {
  final lines = <String>[];
  var line = '';
  for (final w in words) {
    final next = line.isEmpty ? w : '$line $w';
    if (line.isEmpty || (next.length <= maxChars && (fits == null || fits(next)))) {
      line = next;
    } else {
      lines.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

/// The words as one line when they fit, else as two lines of similar
/// length, preferring to break after punctuation.
String _layout(List<String> words, int maxChars, int maxLines,
    bool Function(String line)? fits) {
  bool ok(String l) => l.length <= maxChars && (fits == null || fits(l));
  final one = words.join(' ');
  if (maxLines == 1 || words.length < 2 || ok(one)) return one;
  var best = -1;
  var bestScore = double.infinity;
  for (var i = 1; i < words.length; i++) {
    final a = words.sublist(0, i).join(' ');
    final b = words.sublist(i).join(' ');
    if (!ok(a) || !ok(b)) continue;
    var score = (a.length - b.length).abs().toDouble();
    final before = words[i - 1];
    if (endsSentence(before) || endsClause(before)) score -= 6;
    // A short word left hanging at the end of the first line reads badly.
    if (before.length <= 2) score += 3;
    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  if (best < 0) return _wrap(words, maxChars, fits).join('\n');
  return '${words.sublist(0, best).join(' ')}\n${words.sublist(best).join(' ')}';
}

/// Builds captions from [words] (timeline order, see [timelineWords]).
/// [skip] leaves a word out of the text (hesitation sounds). [lineFits]
/// tells whether a line fits the picture at the caption's size (see
/// [captionLineFits]); without it only the character count decides.
List<CaptionCue> buildCaptions(
  List<TimelineWord> words, {
  CaptionOptions options = const CaptionOptions(),
  bool Function(TimelineWord word)? skip,
  bool Function(String line)? lineFits,
}) {
  final maxChars = options.lineChars;
  final maxLines = options.lines;
  bool fitsAll(List<String> texts) =>
      _wrap(texts, maxChars, lineFits).length <= maxLines;

  final groups = <List<TimelineWord>>[];
  var cur = <TimelineWord>[];
  void flush() {
    if (cur.isNotEmpty) groups.add(cur);
    cur = <TimelineWord>[];
  }

  int chars(List<TimelineWord> l) =>
      l.fold<int>(0, (n, w) => n + w.text.length + 1) - 1;

  for (final w in words) {
    if (w.text.trim().isEmpty) continue;
    if (skip != null && skip(w)) continue;
    if (cur.isNotEmpty) {
      final prev = cur.last;
      final cut = w.clipId != prev.clipId &&
          (w.clipStartMs - prev.clipEndMs).abs() > 400;
      final full = !fitsAll([for (final x in cur) x.text, w.text]);
      final long = w.endMs - cur.first.startMs > options.maxMs;
      final size = chars(cur);
      final sentence = endsSentence(prev.text) && size >= 12;
      // Past two thirds of the room, a comma is a good place to stop.
      final clause = endsClause(prev.text) &&
          size >= (maxChars * maxLines * 2) ~/ 3;
      if (w.speaker != prev.speaker ||
          cut ||
          w.startMs - prev.endMs >= options.pauseMs ||
          full ||
          long ||
          sentence ||
          clause) {
        flush();
      }
    }
    cur.add(w);
  }
  flush();

  final cues = <CaptionCue>[];
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final start = g.first.startMs;
    final nextStart = i + 1 < groups.length ? groups[i + 1].first.startMs : null;
    var end = g.last.endMs + options.lingerMs;
    if (end - start < options.minMs) end = start + options.minMs;
    if (nextStart != null && end > nextStart - options.gapMs) {
      end = nextStart - options.gapMs;
    }
    if (end < g.last.endMs) {
      end = nextStart != null && g.last.endMs > nextStart ? nextStart : g.last.endMs;
    }
    if (end - start < 100) end = start + 100;
    cues.add(CaptionCue(
        start,
        end,
        _layout([for (final w in g) w.text], maxChars, maxLines, lineFits),
        g.first.speaker));
  }
  return cues;
}

/// The look new captions get in [p]: that of its newest caption when it
/// has one ("the current caption style"), else the standard caption look.
TitleOverlay captionTemplate(Project p) {
  final existing = p.titles.where((t) => t.kind == TitleKind.caption);
  const blank = TitleOverlay(id: '', text: '', startMs: 0, endMs: 1000);
  if (existing.isEmpty) return captionStyle(blank);
  return existing.last.copyWith(id: '', text: '', startMs: 0, endMs: 1000);
}

/// Whether one line of caption text fits the picture of [p] at the size of
/// [template] without being wrapped by the title layout (so the line
/// breaks chosen here are the ones drawn).
bool Function(String line) captionLineFits(Project p, TitleOverlay template) {
  final size = p.canvasSize;
  return (line) =>
      layoutTitleLines(template.copyWith(text: line),
              canvasWidth: size.width, canvasHeight: size.height)
          .length <=
      1;
}

/// [cues] as caption titles with the look of [template].
List<TitleOverlay> captionTitles(List<CaptionCue> cues, TitleOverlay template,
        {required String Function() newId}) =>
    [
      for (final c in cues)
        template.copyWith(
          id: newId(),
          text: c.text,
          startMs: c.startMs,
          endMs: c.endMs,
          kind: TitleKind.caption,
        ),
    ];

/// The captions of [p] that overlap [fromMs]..[toMs] (whole video when
/// null).
List<TitleOverlay> captionsInRange(Project p, {int? fromMs, int? toMs}) => [
      for (final t in p.titles)
        if (t.kind == TitleKind.caption &&
            (toMs == null || t.startMs < toMs) &&
            (fromMs == null || t.endMs > fromMs))
          t,
    ];
