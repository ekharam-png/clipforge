// From "what is said in a file" to "what is said in the video": pure Dart.
//
// Transcripts hold SOURCE times (transcript.dart). Where a word plays on
// the timeline follows from the clips, exactly like a clip's own picture:
//
//   timeline = clip start + (source time - clip in) / clip speed
//
// for every clip that uses the file, words outside the clip's trimmed part
// dropped. So a transcript made once keeps working after trims, cuts,
// speed changes, reordering and "Remove silences" - nothing is stored on
// the timeline.
//
// Which sound a clip is judged by: its own, or - when voices recorded
// separately are lined up with it (1.10, [AudioClip.syncOffsetMs]) - those
// voice files instead, one transcript per speaker, labelled with the name
// of the voice's sound track. For a voice,
//   time in the voice file = time in the clip's file + offset.

import '../editor/sound_tracks.dart' show linkedVoicesOf;
import '../model/project.dart';
import 'transcript.dart';

/// One sound whose speech belongs to a clip.
class SpeechSource {
  const SpeechSource({
    required this.path,
    this.audioTrack = 0,
    this.offsetMs = 0,
    this.speaker = '',
    this.isVoice = false,
    this.sourceDurationMs = 0,
  });
  final String path;
  final int audioTrack;

  /// time in this file = time in the clip's file + offset (0: the clip's
  /// own sound).
  final int offsetMs;

  /// The speaker's label (the voice track's name); '' for a clip's own
  /// sound.
  final String speaker;
  final bool isVoice;
  final int sourceDurationMs;

  /// Same file and stream = same transcript (whatever the offset).
  String get key => '$path|$audioTrack';
}

/// The sounds that carry the speech of [clip]: its linked voices when it
/// has any, else its own sound. Empty for photos and silent clips.
List<SpeechSource> speechSourcesOf(Project p, Clip clip) {
  if (clip.type != ClipType.video) return const [];
  final voices = <SpeechSource>[];
  final seen = <String>{};
  for (final a in linkedVoicesOf(p, clip.id)) {
    final s = a.soundClip;
    final track = p.trackById(a.trackId);
    final source = SpeechSource(
      path: a.path,
      audioTrack: s.audioTrackInUse,
      offsetMs: a.syncOffsetMs!,
      speaker: track?.name ?? 'Voice',
      isVoice: true,
      sourceDurationMs: a.sourceDurationMs,
    );
    if (seen.add('${source.key}|${source.offsetMs}')) voices.add(source);
  }
  if (voices.isNotEmpty) return voices;
  if (!clip.hasAudio) return const [];
  return [
    SpeechSource(
      path: clip.path,
      audioTrack: clip.audioTrackInUse,
      sourceDurationMs: clip.sourceDurationMs,
    ),
  ];
}

/// Every different sound to transcribe for [p] (or for the clip
/// [clipId] only), in timeline order, each file and stream once.
List<SpeechSource> speechSourcesOfProject(Project p, {String? clipId}) {
  final out = <SpeechSource>[];
  final seen = <String>{};
  for (final c in p.clips) {
    if (clipId != null && c.id != clipId) continue;
    for (final s in speechSourcesOf(p, c)) {
      if (seen.add(s.key)) out.add(s);
    }
  }
  return out;
}

/// Finds the stored transcript of a file and stream, or null.
typedef TranscriptLookup = Transcript? Function(String path, int audioTrack);

/// A word where it plays in the finished video.
class TimelineWord {
  const TimelineWord({
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.clipId,
    required this.clipIndex,
    required this.clipStartMs,
    required this.clipEndMs,
    required this.speaker,
    required this.segment,
    required this.sourceKey,
    required this.estimated,
  });
  final String text;

  /// Timeline times.
  final int startMs;
  final int endMs;
  final String clipId;
  final int clipIndex;

  /// The same word in the time of the CLIP's file (what
  /// `ProjectEditor.removeSourceRanges` cuts by), offsets of a voice file
  /// already taken off.
  final int clipStartMs;
  final int clipEndMs;
  final String speaker;

  /// Index of the phrase in its transcript (words of one phrase share it).
  final int segment;

  /// [SpeechSource.key] of the sound it was heard in.
  final String sourceKey;

  /// Its time is spread over the phrase, not measured.
  final bool estimated;
}

/// The words of the project as they play on the timeline, in time order.
/// [fromMs] / [toMs] keep only words that start inside that part.
/// Clips whose sound has no transcript contribute nothing.
List<TimelineWord> timelineWords(Project p, TranscriptLookup lookup,
    {int? fromMs, int? toMs, String? clipId}) {
  final out = <TimelineWord>[];
  final cache = <String, Transcript?>{};
  final segOf = <Transcript, List<int>>{};
  for (var i = 0; i < p.clips.length; i++) {
    final c = p.clips[i];
    if (clipId != null && c.id != clipId) continue;
    final base = p.clipStartMs(i);
    if (toMs != null && base >= toMs) continue;
    if (fromMs != null && base + c.durationMs <= fromMs) continue;
    final speed = c.speed <= 0 || c.speed.isNaN ? 1.0 : c.speed;
    for (final s in speechSourcesOf(p, c)) {
      final t = cache.putIfAbsent(s.key, () => lookup(s.path, s.audioTrack));
      if (t == null) continue;
      final words = t.words;
      final segs = segOf.putIfAbsent(t, () {
        final l = <int>[];
        for (var k = 0; k < t.segments.length; k++) {
          for (var n = 0; n < t.segments[k].words.length; n++) {
            l.add(k);
          }
        }
        return l;
      });
      // First word that could reach into the clip's part of the file.
      final wantFrom = c.inMs + s.offsetMs;
      final wantTo = c.outMs + s.offsetMs;
      var lo = 0, hi = words.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (words[mid].endMs < wantFrom) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      // Word ends are not strictly ordered when words overlap; step back a
      // little to be safe.
      var k = lo > 3 ? lo - 3 : 0;
      for (; k < words.length; k++) {
        final w = words[k];
        if (w.startMs >= wantTo) break;
        final a = w.startMs - s.offsetMs;
        final b = w.endMs - s.offsetMs;
        final mid = (a + b) ~/ 2;
        if (mid < c.inMs || mid >= c.outMs) continue;
        final ca = a < c.inMs ? c.inMs : a;
        final cb = b > c.outMs ? c.outMs : b;
        final start = base + ((ca - c.inMs) / speed).round();
        final end = base + ((cb - c.inMs) / speed).round();
        if (fromMs != null && start < fromMs) continue;
        if (toMs != null && start >= toMs) continue;
        out.add(TimelineWord(
          text: w.text,
          startMs: start,
          endMs: end < start ? start : end,
          clipId: c.id,
          clipIndex: i,
          clipStartMs: ca,
          clipEndMs: cb < ca ? ca : cb,
          speaker: s.speaker,
          segment: segs[k],
          sourceKey: s.key,
          estimated: t.wordTiming == WordTiming.estimated,
        ));
      }
    }
  }
  // Stable by start time (clips are in order already; speakers interleave).
  final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
  indexed.sort((x, y) {
    final d = x.$2.startMs.compareTo(y.$2.startMs);
    return d != 0 ? d : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// A phrase on the timeline: words of one speaker that follow each other.
class TimelineSegment {
  TimelineSegment(this.words);
  final List<TimelineWord> words;
  int get startMs => words.first.startMs;
  int get endMs => words.last.endMs;
  String get speaker => words.first.speaker;
  String get clipId => words.first.clipId;
  late final String text = words.map((w) => w.text).join(' ');
}

/// Groups timeline [words] into phrases: the transcript's own phrases,
/// broken where a cut removed something in between, the speaker changes,
/// or a phrase would get longer than [maxChars].
List<TimelineSegment> timelineSegments(List<TimelineWord> words,
    {int maxChars = 240}) {
  // Per speaker and sound, so that two people talking at once do not
  // shred each other's phrases.
  final open = <String, List<TimelineWord>>{};
  final chars = <String, int>{};
  final out = <TimelineSegment>[];
  void flush(String key) {
    final l = open.remove(key);
    chars.remove(key);
    if (l != null && l.isNotEmpty) out.add(TimelineSegment(l));
  }

  for (final w in words) {
    final key = '${w.speaker}|${w.sourceKey}';
    final cur = open[key];
    if (cur != null && cur.isNotEmpty) {
      final prev = cur.last;
      final jump = w.clipId != prev.clipId &&
          (w.clipStartMs - prev.clipEndMs).abs() > 400;
      if (w.segment != prev.segment ||
          jump ||
          w.startMs - prev.endMs > 2500 ||
          (chars[key] ?? 0) + w.text.length + 1 > maxChars) {
        flush(key);
      }
    }
    (open[key] ??= []).add(w);
    chars[key] = (chars[key] ?? 0) + w.text.length + 1;
  }
  for (final key in open.keys.toList()) {
    flush(key);
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}

/// What part of a project's speech has a transcript.
class TranscriptCoverage {
  const TranscriptCoverage(this.sources, this.missing);

  /// Every sound that carries speech.
  final List<SpeechSource> sources;

  /// Those without a transcript.
  final List<SpeechSource> missing;
  bool get complete => sources.isNotEmpty && missing.isEmpty;
  bool get none => missing.length == sources.length;
}

TranscriptCoverage transcriptCoverage(Project p, TranscriptLookup lookup,
    {String? clipId}) {
  final sources = speechSourcesOfProject(p, clipId: clipId);
  return TranscriptCoverage(sources, [
    for (final s in sources)
      if (lookup(s.path, s.audioTrack) == null) s,
  ]);
}

/// Text used to compare words: lower case, punctuation and Hebrew points
/// removed.
String plainWord(String word) {
  final b = StringBuffer();
  for (final r in word.toLowerCase().runes) {
    if (r >= 0x0591 && r <= 0x05C7) continue; // Hebrew points
    if (r == 0x0301 || r == 0x0300) continue; // stress marks
    if (r == 0x451) {
      b.writeCharCode(0x435); // ё -> е
      continue;
    }
    final letter = (r >= 0x30 && r <= 0x39) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F) ||
        (r >= 0x370 && r <= 0x52F) ||
        (r >= 0x5D0 && r <= 0x5EA) ||
        (r >= 0x620 && r <= 0x64A) ||
        r >= 0x3040;
    if (letter) b.writeCharCode(r);
  }
  return b.toString();
}

/// One place where a phrase is said.
class PhraseHit {
  const PhraseHit(this.first, this.last, this.words);

  /// Index of the first / last word in the list that was searched.
  final int first;
  final int last;
  final List<TimelineWord> words;
  int get startMs => words.first.startMs;
  int get endMs => words.last.endMs;
}

/// Where [phrase] is said in [words] (whole words, in order, same speaker;
/// case and punctuation do not matter). A last word may be a beginning
/// ("edit" finds "editing") when [prefix] is true.
List<PhraseHit> findPhrase(List<TimelineWord> words, String phrase,
    {bool prefix = false, int limit = 200}) {
  final wanted = [
    for (final w in phrase.split(RegExp(r'\s+')))
      if (plainWord(w).isNotEmpty) plainWord(w),
  ];
  if (wanted.isEmpty) return const [];
  final plain = [for (final w in words) plainWord(w.text)];
  final hits = <PhraseHit>[];
  for (var i = 0; i < words.length && hits.length < limit; i++) {
    if (plain[i].isEmpty) continue;
    var k = i;
    var n = 0;
    final matched = <TimelineWord>[];
    while (n < wanted.length && k < words.length) {
      if (plain[k].isEmpty || words[k].speaker != words[i].speaker) {
        // Another speaker's word (or a bare dash) in between.
        k++;
        if (k - i > wanted.length + 6) break;
        continue;
      }
      final last = n == wanted.length - 1;
      final ok = plain[k] == wanted[n] ||
          (prefix && last && plain[k].startsWith(wanted[n]));
      if (!ok) break;
      matched.add(words[k]);
      n++;
      k++;
    }
    if (n == wanted.length) hits.add(PhraseHit(i, k - 1, matched));
  }
  return hits;
}
