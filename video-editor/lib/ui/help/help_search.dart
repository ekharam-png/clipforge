// Offline search over the help articles. Pure Dart.
//
// Every word of the query is compared with the words of each article's
// title, keywords and text:
//   exact word                      1.0
//   same stem (clips/clip, fading/fade)  0.9
//   start of a word (as you type: "mus" -> music)  0.85
//   a few letters wrong (typos: "musci", "vocie", "trascirpe")  0.7 .. 0.46
// Typos are measured as the number of letters added, missing, changed or
// swapped with their neighbour (optimal string alignment distance): at most
// 1 for words of 4-5 letters, 2 for 6-8 letters and 3 for longer ones.
// Shorter words must be spelled right (or be the start of a word).
// A match in the title counts 3x, in the keywords 2.5x, in the text 1x.
// Common little words ("how", "do", "the") are ignored.

import 'dart:math' as math;

import 'help_content.dart';

/// Words that say nothing about what is being looked for, per language.
const Map<String, Set<String>> kHelpStopWords = {
  'en': {
    'a', 'an', 'the', 'to', 'of', 'in', 'on', 'for', 'and', 'or', 'how', //
    'do', 'does', 'did', 'i', 'my', 'me', 'can', 'cant', 'is', 'it', 'its',
    'what', 'why', 'when', 'with', 'from', 'this', 'that', 'be',
    'are', 'was', 'you', 'your', 'at', 'as', 'by', 'not', 'there', 'want',
    'need', 'please', 'help', 'way', 'get', 'use', 'using', 'so', 'if',
    'into', 'out', 'up', 'some', 'any', 'all', 'one', 'will', 'would',
  },
};

final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// The words of [text], lower case, apostrophes dropped ("can't" -> cant).
List<String> helpWords(String text) => [
  for (final m in _wordPattern.allMatches(
    text.toLowerCase().replaceAll(RegExp("['’]"), ''),
  ))
    m.group(0)!,
];

/// A rough English stem: plural s, -ing, -ed, a final e, a doubled final
/// letter ("trimming", "trimmed", "trim" -> trim; "fades", "fading" -> fad).
String helpStem(String word) {
  var w = word;
  if (w.length > 5 && w.endsWith('ing')) {
    w = w.substring(0, w.length - 3);
  } else if (w.length > 4 && w.endsWith('ed')) {
    w = w.substring(0, w.length - 2);
  } else if (w.length > 4 && w.endsWith('ies')) {
    w = '${w.substring(0, w.length - 3)}y';
  } else if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
    w = w.substring(0, w.length - 1);
  }
  if (w.length > 3 && w.endsWith('e')) w = w.substring(0, w.length - 1);
  if (w.length > 3 && w[w.length - 1] == w[w.length - 2]) {
    w = w.substring(0, w.length - 1);
  }
  return w;
}

/// Edits allowed for a typo in a word of [length] letters.
int allowedTypos(int length) => length <= 3
    ? 0
    : length <= 5
    ? 1
    : length <= 8
    ? 2
    : 3;

/// Optimal string alignment distance (Levenshtein plus swapping two
/// neighbouring letters), or [max] + 1 as soon as it is known to exceed
/// [max].
int typoDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  if (a == b) return 0;
  final n = a.length, m = b.length;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        v = math.min(v, prev2[j - 2] + 1);
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[m];
}

/// How well the query word [q] matches the article word [t], 0 when not.
double wordMatch(String q, String t) {
  if (q == t) return 1;
  if (q.length >= 3 && helpStem(q) == helpStem(t)) return 0.9;
  if (q.length >= 2 && t.startsWith(q)) return 0.85;
  final allowed = allowedTypos(q.length);
  if (allowed == 0) return 0;
  final d = typoDistance(q, t, max: allowed);
  var best = d <= allowed ? 0.7 - 0.12 * (d - 1) : 0.0;
  // A misspelled start of a longer word, while typing ("vocie f" -> voice).
  if (t.length > q.length + 1) {
    for (final len in [q.length, q.length + 1]) {
      if (len >= t.length) continue;
      final dp = typoDistance(q, t.substring(0, len), max: allowed);
      if (dp <= allowed) best = math.max(best, 0.6 - 0.12 * (dp - 1));
    }
  }
  return math.max(best, 0);
}

/// One article found by [HelpSearch.search].
class HelpHit {
  const HelpHit(this.article, this.score, this.matchedWords);
  final HelpArticle article;
  final double score;

  /// The article's own words (lower case) that matched, for highlighting.
  final Set<String> matchedWords;
}

class _Indexed {
  _Indexed(this.article)
    : title = helpWords(article.title).toSet(),
      keywords = {for (final k in article.keywords) ...helpWords(k)},
      keywordPhrases = {
        for (final k in article.keywords) helpWords(k).join(' '),
      },
      body = helpWords(article.plainBody).toSet(),
      primary = article.keywords.isEmpty
          ? ''
          : helpWords(article.keywords.first).join(' ');

  final HelpArticle article;

  /// The first keyword: what the article is mainly about.
  final String primary;
  final Set<String> title;
  final Set<String> keywords;
  final Set<String> keywordPhrases;
  final Set<String> body;
}

class HelpSearch {
  HelpSearch(this.library, {String language = 'en'})
    : _stop = kHelpStopWords[language] ?? const {},
      _index = [for (final a in library.articles) _Indexed(a)] {
    for (final i in _index) {
      for (final w in [...i.title, ...i.keywords, ...i.body]) {
        _frequency[w] = (_frequency[w] ?? 0) + 1;
      }
    }
  }

  final HelpLibrary library;
  final Set<String> _stop;
  final List<_Indexed> _index;

  /// How many articles each word is in.
  final Map<String, int> _frequency = {};

  /// The words of [query] that are searched for.
  List<String> queryWords(String query) {
    final words = helpWords(query);
    final useful = [
      for (final w in words)
        if (!_stop.contains(w)) w,
    ];
    return useful.isEmpty ? words : useful;
  }

  /// Every word of the articles that matches [q], with its score. A word
  /// the articles use as it is (or as the start of a word) is not also
  /// read as a typo of other words ("tour" is not "your").
  Map<String, double> _matches(String q) {
    final out = <String, double>{};
    var known = false;
    for (final t in _frequency.keys) {
      final s = wordMatch(q, t);
      if (s > 0) out[t] = s;
      if (s >= 0.85) known = true;
    }
    if (known) out.removeWhere((_, s) => s < 0.85);
    return out;
  }

  /// The articles that match [query], best first. Empty for an empty query.
  List<HelpHit> search(String query) {
    final words = queryWords(query);
    if (words.isEmpty) return const [];
    final perWord = [for (final w in words) _matches(w)];
    final phrase = words.join(' ');
    final hits = <HelpHit>[];
    for (final item in _index) {
      var score = 0.0;
      var covered = 0;
      final matched = <String>{};
      for (final candidates in perWord) {
        var best = 0.0;
        for (final MapEntry(key: t, value: s) in candidates.entries) {
          final weight = item.title.contains(t)
              ? 3.0
              : item.keywords.contains(t)
              ? 2.5
              : item.body.contains(t)
              ? 1.0
              : 0.0;
          if (weight == 0) continue;
          matched.add(t);
          best = math.max(best, weight * s + (t == item.primary ? 0.5 : 0));
        }
        if (best > 0) covered++;
        score += best;
      }
      if (covered == 0) continue;
      if (words.length > 1) {
        if (helpWords(item.article.title).join(' ').contains(phrase)) {
          score += 3;
        } else if (item.keywordPhrases.any((k) => k.contains(phrase))) {
          score += 2;
        }
      }
      // Articles that have every word come first; what is not built yet
      // comes after what is.
      score *= math.pow(covered / words.length, 2);
      if (item.article.comingLater) score *= 0.8;
      hits.add(HelpHit(item.article, score, matched));
    }
    if (hits.isEmpty) return const [];
    hits.sort((a, b) => b.score.compareTo(a.score));
    final cutoff = hits.first.score * 0.25;
    return [
      for (final h in hits)
        if (h.score >= cutoff) h,
    ];
  }

  /// For a query that found nothing: known words close to its words
  /// ("Did you mean ...?"), most common first.
  List<String> suggestions(String query) {
    final out = <String>[];
    for (final q in queryWords(query)) {
      if (q.length < 3) continue;
      String? best;
      var bestD = 99;
      final max = allowedTypos(q.length) + 2;
      for (final t in _frequency.keys) {
        if (t.length < 3) continue;
        final d = typoDistance(q, t, max: max);
        if (d > max) continue;
        if (d < bestD ||
            (d == bestD && (_frequency[t] ?? 0) > (_frequency[best] ?? 0))) {
          best = t;
          bestD = d;
        }
      }
      if (best != null && best != q && !out.contains(best)) out.add(best);
    }
    return out;
  }

  /// A short piece of [article]'s text that shows one of [words], or its
  /// beginning.
  static String snippet(
    HelpArticle article,
    Set<String> words, {
    int length = 140,
  }) {
    final text = article.plainBody.replaceAll('\n', ' ');
    var at = -1;
    if (words.isNotEmpty) {
      for (final m in _wordPattern.allMatches(text)) {
        if (words.contains(m.group(0)!.toLowerCase())) {
          at = m.start;
          break;
        }
      }
    }
    if (at < 0 || at < length ~/ 2) {
      return text.length <= length
          ? text
          : '${text.substring(0, length).trimRight()}…';
    }
    var start = at - 40;
    final space = text.lastIndexOf(' ', start);
    if (space > 0) start = space + 1;
    final end = math.min(text.length, start + length);
    return '…${text.substring(start, end).trimRight()}'
        '${end < text.length ? '…' : ''}';
  }
}
