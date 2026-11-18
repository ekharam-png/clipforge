// "Remove filler words": finds hesitation sounds and filler words in the
// words on the timeline and works out what to cut. Pure Dart.
//
// Two kinds per language, both configurable ([FillerList]):
//  * SOUNDS - "um", "uh", "er"; "э-э", "эм"; "אה", "אממ": never a word,
//    safe to cut;
//  * WORDS - "like", "you know"; "ну", "как бы", "типа"; "כאילו": fillers
//    that are also real words ("типа" = "of the type"), so they are listed
//    for review but not ticked until the user (or Claude, with the owner's
//    go-ahead) says so.
//
// A cut never touches the words next to it: it runs from just after the
// previous word to just before the next one ([padMs] of air is left on
// each side) and reaches at most [maxExtendMs] beyond the filler itself,
// so pauses stay natural. Cuts are given in the time of the CLIP's file,
// ready for `ProjectEditor.removeSourceRanges`.

import 'transcript_timeline.dart';

class FillerList {
  const FillerList({required this.language, this.sounds = const [], this.words = const []});
  final String language;
  final List<String> sounds;
  final List<String> words;

  FillerList copyWith({List<String>? sounds, List<String>? words}) => FillerList(
      language: language, sounds: sounds ?? this.sounds, words: words ?? this.words);

  Map<String, dynamic> toJson() =>
      {'language': language, 'sounds': sounds, 'words': words};

  factory FillerList.fromJson(Map<String, dynamic> j) => FillerList(
        language: '${j['language'] ?? ''}',
        sounds: [for (final s in (j['sounds'] as List?) ?? const []) '$s'],
        words: [for (final s in (j['words'] as List?) ?? const []) '$s'],
      );
}

/// The lists ClipForge starts with.
const Map<String, FillerList> kDefaultFillers = {
  'en': FillerList(
    language: 'en',
    sounds: ['um', 'uh', 'er', 'erm', 'uhm', 'hmm', 'mm', 'ah', 'eh'],
    words: ['like', 'you know', 'i mean', 'sort of', 'kind of'],
  ),
  'ru': FillerList(
    language: 'ru',
    sounds: ['э-э', 'э', 'эм', 'мм', 'м-м', 'хм'],
    words: ['ну', 'как бы', 'типа', 'это самое', 'короче', 'значит', 'вот'],
  ),
  'he': FillerList(
    language: 'he',
    sounds: ['אה', 'אממ', 'אמ', 'אהמ', 'המ', 'ממ'],
    words: ['כאילו', 'אז', 'בעצם', 'כזה'],
  ),
};

/// The list for [language] ('' / unknown: every language's sounds, no
/// words).
FillerList fillersFor(String language, [Map<String, FillerList> lists = kDefaultFillers]) {
  final l = lists[language];
  if (l != null) return l;
  return FillerList(
      language: language,
      sounds: [for (final x in lists.values) ...x.sounds]);
}

/// How a filler and a spoken word are compared: lower case, no
/// punctuation or hyphens, drawn-out letters collapsed ("ummm" = "um",
/// "э-э-э" = "э").
String fillerKey(String text) {
  final plain = plainWord(text);
  final b = StringBuffer();
  int? last;
  for (final r in plain.runes) {
    if (r == last) continue;
    b.writeCharCode(r);
    last = r;
  }
  return b.toString();
}

class FillerHit {
  const FillerHit({
    required this.entry,
    required this.isSound,
    required this.words,
    required this.cutStartMs,
    required this.cutEndMs,
    required this.overlapsSpeech,
    this.gapBeforeMs = 100000,
    this.gapAfterMs = 100000,
  });

  /// The silence between the word before and the filler, and between the
  /// filler and the word after (large when there is no such word).
  final int gapBeforeMs;
  final int gapAfterMs;

  /// The list entry it matched ("um", "как бы").
  final String entry;
  final bool isSound;
  final List<TimelineWord> words;

  /// What to cut, in the time of the clip's file.
  final int cutStartMs;
  final int cutEndMs;

  /// Someone else is talking at the same moment (two speakers): cutting
  /// it would cut them too, so it is never ticked by default.
  final bool overlapsSpeech;

  String get clipId => words.first.clipId;
  int get clipIndex => words.first.clipIndex;
  int get startMs => words.first.startMs;
  int get endMs => words.last.endMs;
  String get text => words.map((w) => w.text).join(' ');
  String get speaker => words.first.speaker;
  int get cutMs => cutEndMs - cutStartMs;
  bool get estimated => words.any((w) => w.estimated);
}

/// Finds the fillers of [list] in [words] ([timelineWords] order).
/// Longest entry first, so "как бы" wins over a bare "как".
List<FillerHit> findFillers(List<TimelineWord> words, FillerList list,
    {int padMs = 40, int maxExtendMs = 150, int minCutMs = 80}) {
  final entries = <({List<String> keys, String entry, bool sound})>[];
  void add(List<String> from, bool sound) {
    for (final e in from) {
      final keys = [
        for (final part in e.trim().split(RegExp(r'\s+')))
          if (fillerKey(part).isNotEmpty) fillerKey(part),
      ];
      if (keys.isNotEmpty) entries.add((keys: keys, entry: e.trim(), sound: sound));
    }
  }

  add(list.sounds, true);
  add(list.words, false);
  entries.sort((a, b) => b.keys.length.compareTo(a.keys.length));

  final keys = [for (final w in words) fillerKey(w.text)];
  final hits = <FillerHit>[];
  final taken = List<bool>.filled(words.length, false);

  // Neighbours of the same clip, whoever speaks.
  int? prevEnd(int i, String clipId) {
    for (var k = i - 1; k >= 0 && i - k < 40; k--) {
      if (words[k].clipId != clipId) continue;
      if (words[k].clipEndMs <= words[i].clipStartMs + 1) return words[k].clipEndMs;
    }
    return null;
  }

  int? nextStart(int i, String clipId) {
    for (var k = i + 1; k < words.length && k - i < 40; k++) {
      if (words[k].clipId != clipId) continue;
      if (words[k].clipStartMs >= words[i].clipEndMs - 1) return words[k].clipStartMs;
    }
    return null;
  }

  for (var i = 0; i < words.length; i++) {
    if (taken[i] || keys[i].isEmpty) continue;
    for (final e in entries) {
      // The entry's words must follow each other: same speaker, same clip.
      final idx = <int>[i];
      var k = i + 1;
      var ok = keys[i] == e.keys.first;
      while (ok && idx.length < e.keys.length) {
        while (k < words.length &&
            (words[k].speaker != words[i].speaker || keys[k].isEmpty)) {
          k++;
        }
        if (k >= words.length ||
            taken[k] ||
            words[k].clipId != words[i].clipId ||
            keys[k] != e.keys[idx.length]) {
          ok = false;
        } else {
          idx.add(k);
          k++;
        }
      }
      if (!ok) continue;
      final first = words[idx.first], last = words[idx.last];
      final a = first.clipStartMs, b = last.clipEndMs;
      final before = prevEnd(idx.first, first.clipId);
      final after = nextStart(idx.last, first.clipId);
      var start = before == null ? a - maxExtendMs : before + padMs;
      if (start < a - maxExtendMs) start = a - maxExtendMs;
      if (start > a) start = a;
      var end = after == null ? b + maxExtendMs : after - padMs;
      if (end > b + maxExtendMs) end = b + maxExtendMs;
      if (end < b) end = b;
      if (start < 0) start = 0;
      if (end - start < minCutMs) break;
      var overlaps = false;
      for (var n = (idx.first - 30).clamp(0, words.length);
          n < words.length && n < idx.last + 30;
          n++) {
        final w = words[n];
        if (idx.contains(n) || w.clipId != first.clipId) continue;
        if (w.speaker == first.speaker && keys[n].isNotEmpty) continue;
        if (keys[n].isEmpty) continue;
        if (w.clipStartMs < end && w.clipEndMs > start) {
          overlaps = true;
          break;
        }
      }
      for (final n in idx) {
        taken[n] = true;
      }
      hits.add(FillerHit(
        entry: e.entry,
        isSound: e.sound,
        words: [for (final n in idx) words[n]],
        cutStartMs: start,
        cutEndMs: end,
        overlapsSpeech: overlaps,
        gapBeforeMs: before == null ? 100000 : (a - before < 0 ? 0 : a - before),
        gapAfterMs: after == null ? 100000 : (after - b < 0 ? 0 : after - b),
      ));
      break;
    }
  }
  return hits;
}

/// Counts and time per list entry, most frequent first.
class FillerGroup {
  FillerGroup(this.entry, this.isSound, this.hits);
  final String entry;
  final bool isSound;
  final List<FillerHit> hits;
  int get count => hits.length;
  int get totalMs => hits.fold(0, (n, h) => n + h.cutMs);
}

List<FillerGroup> groupFillers(List<FillerHit> hits) {
  final map = <String, FillerGroup>{};
  for (final h in hits) {
    (map[h.entry] ??= FillerGroup(h.entry, h.isSound, [])).hits.add(h);
  }
  return map.values.toList()
    ..sort((a, b) {
      if (a.isSound != b.isSound) return a.isSound ? -1 : 1;
      return b.count.compareTo(a.count);
    });
}

/// The cuts for [hits] per clip id, in the time of each clip's file,
/// sorted and merged.
Map<String, List<({int startMs, int endMs})>> fillerCuts(Iterable<FillerHit> hits) {
  final out = <String, List<({int startMs, int endMs})>>{};
  for (final h in hits) {
    (out[h.clipId] ??= []).add((startMs: h.cutStartMs, endMs: h.cutEndMs));
  }
  for (final e in out.entries) {
    e.value.sort((a, b) => a.startMs.compareTo(b.startMs));
    final merged = <({int startMs, int endMs})>[];
    for (final r in e.value) {
      if (merged.isNotEmpty && r.startMs <= merged.last.endMs) {
        final l = merged.removeLast();
        merged.add((startMs: l.startMs, endMs: r.endMs > l.endMs ? r.endMs : l.endMs));
      } else {
        merged.add(r);
      }
    }
    out[e.key] = merged;
  }
  return out;
}

/// True for a word that is a hesitation sound of [list] (captions leave
/// those out).
bool Function(TimelineWord word) isFillerSound(FillerList list) {
  final keys = {
    for (final s in list.sounds)
      if (!s.trim().contains(' ')) fillerKey(s),
  };
  return (w) => keys.contains(fillerKey(w.text));
}
