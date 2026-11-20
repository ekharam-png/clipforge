// Shorts (1.14): everything the app's "Make a short" and Claude's
// make_short / suggest_shorts share. Pure Dart.
//
//  * the "Short" caption look and the title at the top, defined ONCE;
//  * [buildShort]: keep one part of the timeline, upright, 1080p, captions;
//  * [snapShortRange]: move a start and an end outward to a pause, never
//    into a word;
//  * [shortCandidates]: complete passages a short could be made of, with
//    simple signals. It does not judge what is worth posting: there is no
//    AI here. Claude (or the owner) does the picking.

import '../editor/project_editor.dart';
import '../model/project.dart';
import '../model/title_layout.dart';
import '../transcript/captions.dart';
import '../transcript/speech_edits.dart';
import '../transcript/transcript.dart' show endsSentence;
import '../transcript/transcript_timeline.dart';

/// Longest short that every short-form site is sure to take. The sites
/// change their limits; this is the conservative value the warnings use
/// (also the limit of the "Shorts / Reels / TikTok" row in
/// media/destinations.dart).
const int kShortMaxSeconds = 60;

/// The lengths "Make a short from here…" offers, in seconds.
const List<int> kShortLengths = [30, 45, 60];

/// "Make shorts from markers…": how much is kept before and after a
/// marker (before snapping to pauses).
const int kMarkerBeforeMs = 20000;
const int kMarkerAfterMs = 25000;

/// The "Short" look, defined once: captions bigger, centred in the lower
/// middle (clear of the sites' buttons at the very bottom), outlined, one
/// or two lines; the optional title at the top.
class ShortLook {
  static const double captionY = 0.68;
  static const double captionFontSize = 0.075;
  static const int captionMaxLines = 2;

  /// Characters per caption line to aim for (the real width decides).
  static const int captionLineChars = 20;
  static const double titleY = 0.13;
  static const double titleFontSize = 0.072;
  static const int titleMaxChars = 60;
}

/// [t] as a caption in the "Short" look; id, text and times are kept.
TitleOverlay shortCaptionStyle(TitleOverlay t) => t.copyWith(
      kind: TitleKind.caption,
      x: 0.5,
      y: ShortLook.captionY,
      fontSize: ShortLook.captionFontSize,
      colorArgb: 0xFFFFFFFF,
      bold: true,
      background: false,
      font: TitleFont.modern,
      outline: true,
      outlineColorArgb: 0xFF000000,
      shadow: false,
      align: TitleAlign.center,
    );

/// The "title at the top" of a short: [text] over the whole [durationMs].
TitleOverlay shortTopTitle(String id, String text, int durationMs) =>
    TitleOverlay(
      id: id,
      text: text.trim(),
      startMs: 0,
      endMs: durationMs,
      x: 0.5,
      y: ShortLook.titleY,
      fontSize: ShortLook.titleFontSize,
      bold: true,
      font: TitleFont.modern,
      outline: true,
      shadow: false,
      background: false,
      kind: TitleKind.title,
    );

/// The first sentence of [text], for the title at the top: up to the first
/// sentence mark, a speaker's "Name:" taken off, at most
/// [ShortLook.titleMaxChars] characters (cut at a word).
String firstSentence(String text, {int maxChars = ShortLook.titleMaxChars}) {
  final words =
      text.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ').where((w) => w.isNotEmpty);
  final out = <String>[];
  for (final w in words) {
    out.add(w);
    if (endsSentence(w)) break;
  }
  var t = out.join(' ');
  if (t.length > maxChars) {
    final cut = t.substring(0, maxChars);
    final space = cut.lastIndexOf(' ');
    t = '${(space > maxChars ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
  }
  return t;
}

/// Gives every caption of [e]'s project the "Short" look. A caption that
/// would then need more than two lines is divided into several that
/// follow each other (its time shared out by length), so nothing covers
/// the picture. One undo step. Returns how many captions there are after.
int applyShortCaptionLook(ProjectEditor e, {required String Function() newId}) {
  final p = e.project;
  final captions = [
    for (final t in p.titles)
      if (t.kind == TitleKind.caption) t,
  ];
  if (captions.isEmpty) return 0;
  final size = p.canvasSize;
  final probe = shortCaptionStyle(
      const TitleOverlay(id: '', text: '', startMs: 0, endMs: 1000));
  bool fits(String line) =>
      layoutTitleLines(probe.copyWith(text: line),
              canvasWidth: size.width, canvasHeight: size.height)
          .length <=
      1;
  var count = 0;
  e.transaction(() {
    for (final c in captions) {
      final words = c.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();
      final lines = <String>[];
      var line = '';
      for (final w in words) {
        final next = line.isEmpty ? w : '$line $w';
        if (line.isEmpty || fits(next)) {
          line = next;
        } else {
          lines.add(line);
          line = w;
        }
      }
      if (line.isNotEmpty) lines.add(line);
      if (lines.length <= ShortLook.captionMaxLines) {
        e.updateTitle(shortCaptionStyle(c.copyWith(text: lines.join('\n'))));
        count++;
        continue;
      }
      // Too long for two lines: several captions, one after the other.
      final parts = <String>[
        for (var i = 0; i < lines.length; i += ShortLook.captionMaxLines)
          lines.skip(i).take(ShortLook.captionMaxLines).join('\n'),
      ];
      final total = parts.fold<int>(0, (n, s) => n + s.length);
      final span = c.endMs - c.startMs;
      e.removeTitle(c.id);
      var at = c.startMs;
      var used = 0;
      final pieces = <TitleOverlay>[];
      for (var i = 0; i < parts.length; i++) {
        used += parts[i].length;
        final end = i == parts.length - 1
            ? c.endMs
            : c.startMs + (span * used / (total == 0 ? 1 : total)).round();
        pieces.add(shortCaptionStyle(c.copyWith(
            id: i == 0 ? c.id : newId(), text: parts[i], startMs: at, endMs: end)));
        at = end;
      }
      e.addTitles(pieces);
      count += pieces.length;
    }
  }, label: 'Short caption look');
  return count;
}

/// What [buildShort] did.
class ShortBuilt {
  const ShortBuilt({
    required this.ok,
    this.captionsFromSpeech = 0,
    this.captionsKept = 0,
    this.captionsAfter = 0,
    this.titleAdded = false,
    this.blurred = 0,
    this.notTranscribed = false,
    this.nothingSaid = false,
  });

  /// False: the range held no video and nothing was changed.
  final bool ok;

  /// Captions made from the transcript.
  final int captionsFromSpeech;

  /// Captions the part already had (kept; none are made then).
  final int captionsKept;

  /// Captions in the short at the end (after the "Short" look divided
  /// long ones).
  final int captionsAfter;
  final bool titleAdded;

  /// Clips that got the blurred background.
  final int blurred;

  /// Captions were wanted but the part has no transcript.
  final bool notTranscribed;

  /// It has one, but nothing is said in this part.
  final bool nothingSaid;
}

/// Turns the project in [e] (a COPY of the long one) into a short: only
/// [fromMs]..[toMs] of the timeline is kept ([keepTimelineRange]: titles,
/// captions and linked voices follow), the shape becomes [shape], the
/// video size 1080p; with [blur] clips of another shape get the blurred
/// background; with [captions] and no captions in the part, captions are
/// made from [words] (the words of the SHORT's timeline, from its
/// transcript; null = not transcribed); [shortCaptions] gives every
/// caption the "Short" look; a non-empty [title] is put at the top for
/// the whole short.
ShortBuilt buildShort(
  ProjectEditor e, {
  required int fromMs,
  required int toMs,
  CanvasAspect shape = CanvasAspect.portrait9x16,
  bool blur = false,
  bool captions = true,
  bool shortCaptions = false,
  String title = '',
  List<TimelineWord>? Function(Project short)? words,
  bool Function(TimelineWord word)? skipWord,
  required String Function() newId,
}) {
  if (!keepTimelineRange(e, fromMs, toMs)) return const ShortBuilt(ok: false);
  var blurred = 0;
  e.setAspect(shape);
  e.setVideoSize(VideoSize.p1080);
  if (blur) {
    final canvas = e.project.canvasSize;
    final want = canvas.width / canvas.height;
    for (final c in [...e.project.clips]) {
      final size = c.framedSize;
      if (c.fit != FitMode.fit || size.width <= 0 || size.height <= 0) continue;
      if ((size.width / size.height / want - 1).abs() <= 0.02) continue;
      e.setClipFit(c.id, FitMode.blur);
      blurred++;
    }
  }
  var made = 0, kept = 0;
  var notTranscribed = false, nothingSaid = false;
  if (captions) {
    kept = captionsInRange(e.project).length;
    if (kept == 0) {
      final spoken = words?.call(e.project);
      if (spoken == null) {
        notTranscribed = true;
      } else {
        final template = shortCaptions
            ? shortCaptionStyle(
                const TitleOverlay(id: '', text: '', startMs: 0, endMs: 1000))
            : captionTemplate(e.project);
        final cues = buildCaptions(spoken,
            options: shortCaptions
                ? const CaptionOptions(
                    maxLineChars: ShortLook.captionLineChars,
                    maxLines: ShortLook.captionMaxLines,
                    maxMs: 4000)
                : const CaptionOptions(),
            skip: skipWord,
            lineFits: captionLineFits(e.project, template));
        if (cues.isEmpty) {
          nothingSaid = true;
        } else {
          addSpeechCaptions(e, captionTitles(cues, template, newId: newId));
          made = cues.length;
        }
      }
    }
  }
  var after = captionsInRange(e.project).length;
  if (shortCaptions && after > 0) {
    after = applyShortCaptionLook(e, newId: newId);
  }
  var titled = false;
  if (title.trim().isNotEmpty) {
    e.addTitle(shortTopTitle(newId(), title, e.project.durationMs));
    titled = true;
  }
  return ShortBuilt(
    ok: true,
    captionsFromSpeech: made,
    captionsKept: kept,
    captionsAfter: after,
    titleAdded: titled,
    blurred: blurred,
    notTranscribed: notTranscribed,
    nothingSaid: nothingSaid,
  );
}

/// A stretch of the timeline.
typedef Span = ({int startMs, int endMs});

/// The pauses of at least [minMs] between the stretches of [talk]
/// (anybody's, in any order), from 0 to [totalMs].
List<Span> pausesBetween(Iterable<Span> talk, int totalMs, {int minMs = 300}) {
  final sorted = [...talk]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <Span>[];
  var at = 0;
  for (final t in sorted) {
    if (t.startMs - at >= minMs) out.add((startMs: at, endMs: t.startMs));
    if (t.endMs > at) at = t.endMs;
  }
  if (totalMs - at >= minMs) out.add((startMs: at, endMs: totalMs));
  return out;
}

/// [fromMs]..[toMs] moved OUTWARD so that the short does not start or end
/// in the middle of talk:
///  * to the nearest of [pauses] (who-is-speaking map, or the gaps between
///    captions) before the start / after the end, at most [maxMoveMs]
///    away; [padMs] of the quiet is kept;
///  * then never inside one of [words] (transcript words, or captions): a
///    start inside a word moves to its beginning, an end to its end.
/// Kept inside 0..[totalMs]. A start or end already in a pause stays.
({int fromMs, int toMs, bool movedStart, bool movedEnd}) snapShortRange(
  int fromMs,
  int toMs, {
  List<Span> pauses = const [],
  List<Span> words = const [],
  required int totalMs,
  int maxMoveMs = 4000,
  int padMs = 150,
}) {
  var from = fromMs.clamp(0, totalMs), to = toMs.clamp(0, totalMs);
  bool inPause(int t) => pauses.any((p) => t >= p.startMs && t <= p.endMs);
  if (from > 0 && !inPause(from)) {
    Span? best;
    for (final p in pauses) {
      if (p.endMs <= from && (best == null || p.endMs > best.endMs)) best = p;
    }
    if (best != null && from - best.endMs <= maxMoveMs) {
      final pad = best.endMs - padMs;
      from = pad < best.startMs ? best.startMs : pad;
    }
  }
  if (to < totalMs && !inPause(to)) {
    Span? best;
    for (final p in pauses) {
      if (p.startMs >= to && (best == null || p.startMs < best.startMs)) {
        best = p;
      }
    }
    if (best != null && best.startMs - to <= maxMoveMs) {
      final pad = best.startMs + padMs;
      to = pad > best.endMs ? best.endMs : pad;
    }
  }
  for (final w in words) {
    if (from > w.startMs && from < w.endMs) from = w.startMs;
    if (to > w.startMs && to < w.endMs) to = w.endMs;
  }
  from = from.clamp(0, totalMs);
  to = to.clamp(0, totalMs);
  return (
    fromMs: from,
    toMs: to,
    movedStart: from != fromMs,
    movedEnd: to != toMs,
  );
}

/// A marker's short is never shorter than this (where the video allows).
const int kMarkerMinMs = 8000;

/// From this length of the video on, a marker's short takes the full
/// [kMarkerBeforeMs] + [kMarkerAfterMs]; in a shorter video, half of it.
const int kMarkerFullFromMs = 60000;

/// Two marker shorts that share more than this much of the shorter one
/// show mostly the same part: the user is asked whether one short should
/// cover both.
const double kMarkerOverlapShare = 0.7;

/// The part of the video a short around a marker at [markerMs] takes
/// (before snapping): [kMarkerBeforeMs] before to [kMarkerAfterMs] after,
/// inside the video.
///
/// A SHORT video (under [kMarkerFullFromMs], a minute) gets a smaller
/// window in the same proportion - half the video, at least
/// [kMarkerMinMs] - so that two markers in a 35-second video do not both
/// become the whole video (1.17; a real test got 0:00-0:35 twice). A
/// window cut off by the start or the end of the video is made up on the
/// other side to [kMarkerMinMs].
Span markerRange(int markerMs, int totalMs) {
  if (totalMs <= 0) return (startMs: 0, endMs: 0);
  const full = kMarkerBeforeMs + kMarkerAfterMs;
  var window = full;
  if (totalMs < kMarkerFullFromMs) {
    window = totalMs ~/ 2;
    if (window < kMarkerMinMs) window = kMarkerMinMs;
    if (window > totalMs) window = totalMs;
  }
  final before = window * kMarkerBeforeMs ~/ full;
  final m = markerMs.clamp(0, totalMs);
  var start = (m - before).clamp(0, totalMs);
  var end = (m - before + window).clamp(0, totalMs);
  final least = kMarkerMinMs < totalMs ? kMarkerMinMs : totalMs;
  if (end - start < least) {
    if (start == 0) {
      end = least;
    } else {
      start = end - least;
    }
  }
  return (startMs: start, endMs: end);
}

/// How much of the shorter of [a] and [b] the two share (0..1).
double spanOverlapShare(Span a, Span b) {
  final from = a.startMs > b.startMs ? a.startMs : b.startMs;
  final to = a.endMs < b.endMs ? a.endMs : b.endMs;
  if (to <= from) return 0;
  final la = a.endMs - a.startMs, lb = b.endMs - b.startMs;
  final shorter = la < lb ? la : lb;
  return shorter <= 0 ? 0 : (to - from) / shorter;
}

/// [ranges] (in time order of their markers) in groups of neighbours
/// that overlap by more than [share]: each group is a list of indexes
/// into [ranges]. A group of one is a range that stands by itself.
List<List<int>> overlappingGroups(List<Span> ranges,
    {double share = kMarkerOverlapShare}) {
  final order = [for (var i = 0; i < ranges.length; i++) i]
    ..sort((a, b) => ranges[a].startMs != ranges[b].startMs
        ? ranges[a].startMs.compareTo(ranges[b].startMs)
        : a.compareTo(b));
  final groups = <List<int>>[];
  Span? union;
  for (final i in order) {
    final r = ranges[i];
    if (union != null && spanOverlapShare(union, r) > share) {
      groups.last.add(i);
      union = (
        startMs: union.startMs < r.startMs ? union.startMs : r.startMs,
        endMs: union.endMs > r.endMs ? union.endMs : r.endMs,
      );
    } else {
      groups.add([i]);
      union = r;
    }
  }
  return groups;
}

/// The ranges to make shorts of when overlapping ones are joined
/// ([joinOverlapping]): one range per group of [overlappingGroups],
/// from the earliest start to the latest end. Otherwise [ranges] as they
/// are.
List<Span> shortRangesFor(List<Span> ranges, {required bool joinOverlapping}) {
  if (!joinOverlapping) return [...ranges];
  return [
    for (final g in overlappingGroups(ranges))
      (
        startMs: g.map((i) => ranges[i].startMs).reduce((a, b) => a < b ? a : b),
        endMs: g.map((i) => ranges[i].endMs).reduce((a, b) => a > b ? a : b),
      ),
  ];
}

/// Something said: a word of a transcript, or a caption.
class Spoken {
  const Spoken(this.startMs, this.endMs, this.text, [this.speaker = '']);
  final int startMs;
  final int endMs;
  final String text;
  final String speaker;
}

/// True when a short starting at [fromMs] would begin in the middle of a
/// sentence: something is said right before it (less than [pauseMs]
/// earlier) that does not end a sentence. Only meaningful when the text
/// has sentence marks.
bool startsMidSentence(List<Spoken> spoken, int fromMs, {int pauseMs = 700}) {
  Spoken? before, first;
  for (final s in spoken) {
    final mid = (s.startMs + s.endMs) ~/ 2;
    if (mid < fromMs) {
      before = s;
    } else {
      first = s;
      break;
    }
  }
  if (before == null || first == null) return false;
  if (first.startMs - before.endMs >= pauseMs) return false;
  return !endsSentence(before.text);
}

/// True when a short ending at [toMs] would stop before its last sentence
/// is finished.
bool endsMidSentence(List<Spoken> spoken, int toMs, {int pauseMs = 700}) {
  Spoken? last, next;
  for (final s in spoken) {
    final mid = (s.startMs + s.endMs) ~/ 2;
    if (mid < toMs) {
      last = s;
    } else {
      next = s;
      break;
    }
  }
  if (last == null || next == null) return false;
  if (next.startMs - last.endMs >= pauseMs) return false;
  return !endsSentence(last.text);
}

/// A passage a short could be made of. See [shortCandidates].
class ShortCandidate {
  const ShortCandidate({
    required this.startMs,
    required this.endMs,
    required this.speakers,
    required this.text,
    required this.sentences,
    required this.startsWithQuestion,
    required this.hasQuestion,
    required this.hasNumbers,
    required this.afterPause,
    required this.beforePause,
    required this.completeSentences,
  });
  final int startMs;
  final int endMs;
  int get durationMs => endMs - startMs;

  /// Who talks in it, in order of first word ('' when not known).
  final List<String> speakers;
  final String text;
  final int sentences;

  /// Signals (facts about the text and timing, not a judgement):
  /// the first sentence is a question (a hook);
  final bool startsWithQuestion;
  final bool hasQuestion;

  /// figures are said (a number, a year, a price);
  final bool hasNumbers;

  /// there is a pause, a speaker change or the start of the video right
  /// before it / right after it (it stands by itself);
  final bool afterPause;
  final bool beforePause;

  /// it starts at the beginning of a sentence and ends at the end of one.
  /// False only when the text has no sentence marks at all (the starts
  /// and ends are then pauses).
  final bool completeSentences;
}

class _Sentence {
  _Sentence(this.items, this.marked);
  final List<Spoken> items;

  /// Ended by a sentence mark (not by a pause or a speaker change).
  final bool marked;
  int get startMs => items.first.startMs;
  int get endMs => items.last.endMs;
  String get speaker => items.first.speaker;
  String get text => items.map((s) => s.text.trim()).join(' ');
}

final RegExp _number = RegExp(r'\d|%|\b(one|two|three|four|five|six|seven|'
    r'eight|nine|ten|twenty|thirty|forty|fifty|hundred|thousand|million|'
    r'billion|half|double|twice|percent)\b', caseSensitive: false);

bool _isQuestion(String text) {
  var t = text.trimRight();
  while (t.isNotEmpty && '"\'”’»)]'.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  return t.endsWith('?') || t.endsWith('？') || t.endsWith('؟');
}

/// Candidate passages for shorts from what is [spoken] (transcript words
/// or captions, in time order): runs of WHOLE sentences that are between
/// [minMs] and [maxMs] long. A sentence ends at a sentence mark, at a
/// pause of twice [pauseMs], or when the speaker changes. Candidates
/// start where a passage naturally starts (the beginning, after a pause
/// of [pauseMs], when another speaker takes over, and - in talk without
/// such breaks - about every half [maxMs]) and run to the last natural
/// end that fits (a pause or speaker change), else to the last sentence
/// end that fits. They may overlap. This judges nothing: it only makes
/// sure that whoever picks is offered complete thoughts with times.
List<ShortCandidate> shortCandidates(
  List<Spoken> spoken, {
  int minMs = 15000,
  int maxMs = 60000,
  int pauseMs = 700,
}) {
  final items = [
    for (final s in spoken)
      if (s.text.trim().isNotEmpty) s,
  ];
  if (items.isEmpty || maxMs < minMs) return const [];
  final sentences = <_Sentence>[];
  var open = <Spoken>[];
  for (var i = 0; i < items.length; i++) {
    final s = items[i];
    open.add(s);
    final next = i + 1 < items.length ? items[i + 1] : null;
    final marked = endsSentence(s.text);
    if (marked ||
        next == null ||
        next.speaker != s.speaker ||
        next.startMs - s.endMs >= pauseMs * 2) {
      sentences.add(_Sentence(open, marked));
      open = <Spoken>[];
    }
  }
  final n = sentences.length;
  final anyMarks = sentences.any((s) => s.marked);
  bool breakBefore(int i) =>
      i == 0 ||
      sentences[i].speaker != sentences[i - 1].speaker ||
      sentences[i].startMs - sentences[i - 1].endMs >= pauseMs;
  bool breakAfter(int j) => j == n - 1 || breakBefore(j + 1);

  final out = <ShortCandidate>[];
  final seen = <String>{};
  var lastStart = -1 << 40;
  for (var i = 0; i < n; i++) {
    final start = sentences[i].startMs;
    final natural = breakBefore(i);
    if (!natural && start - lastStart < maxMs ~/ 2) continue;
    // The sentences a passage from here could end at: every natural end
    // that fits, else the furthest sentence end that fits.
    int? fit;
    final natural_ = <int>[];
    for (var j = i; j < n; j++) {
      final d = sentences[j].endMs - start;
      if (d > maxMs) break;
      if (d >= minMs) {
        fit = j;
        if (breakAfter(j)) natural_.add(j);
      }
    }
    // The shortest complete one and the longest (one idea, or with what
    // follows): the reader chooses.
    final ends = natural_.isEmpty
        ? [?fit]
        : {natural_.first, natural_.last}.toList();
    if (ends.isEmpty) continue;
    lastStart = start;
    for (final j in ends) {
      if (!seen.add('$i-$j')) continue;
      final part = sentences.sublist(i, j + 1);
      final speakers = <String>[];
      for (final s in part) {
        for (final item in s.items) {
          if (!speakers.contains(item.speaker)) speakers.add(item.speaker);
        }
      }
      final text = part.map((s) => s.text).join(' ');
      out.add(ShortCandidate(
        startMs: start,
        endMs: sentences[j].endMs,
        speakers: speakers,
        text: text,
        sentences: part.length,
        startsWithQuestion: _isQuestion(part.first.text),
        hasQuestion: part.any((s) => _isQuestion(s.text)),
        hasNumbers: _number.hasMatch(text),
        afterPause: natural,
        beforePause: breakAfter(j),
        completeSentences: anyMarks,
      ));
    }
  }
  return out;
}
