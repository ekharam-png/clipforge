// The help articles: their file format and parser. Pure Dart.
//
// One Markdown-like file per language, `assets/help/help_<lang>.md`. Each
// article starts with a line `=== <id>`, then `key: value` lines, then a
// blank line and the body:
//
//   === clean-up-sound
//   title: Clean up sound
//   section: Sound
//   keywords: noise, hiss, hum, denoise
//   related: voice-focus, hear-a-sample
//   status: coming-later            (optional)
//
//   Body text. Paragraphs are separated by a blank line.
//   - a bullet
//   1. a numbered step
//   **bold** words, usually the app's own button labels.
//
// Lines starting with `#` before the first article are comments. The ids,
// `related` and `section` keys stay the same in every language; only
// title, keywords and body are translated.

/// One help article.
class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.title,
    required this.section,
    required this.keywords,
    required this.body,
    required this.related,
    this.comingLater = false,
  });

  final String id;
  final String title;
  final String section;
  final List<String> keywords;

  /// The text, in the small Markdown subset described above.
  final String body;

  /// Ids of other articles.
  final List<String> related;

  /// A feature that is not built yet.
  final bool comingLater;

  /// The body as blocks, for display and for search snippets.
  List<HelpBlock> get blocks => parseHelpBody(body);

  /// The body without Markdown marks.
  String get plainBody => blocks.map((b) => b.text).join('\n');
}

enum HelpBlockKind { paragraph, bullet, step, heading }

/// A paragraph, bullet, numbered step or small heading of an article.
class HelpBlock {
  const HelpBlock(
    this.kind,
    this.text, {
    this.number,
    this.boldRanges = const [],
  });
  final HelpBlockKind kind;

  /// The words, with `**` marks removed (see [boldRanges]).
  final String text;

  /// For [HelpBlockKind.step].
  final int? number;

  /// Ranges of [text] that were written in `**bold**`.
  final List<(int, int)> boldRanges;
}

/// Splits [body] into blocks and removes the `**` marks.
List<HelpBlock> parseHelpBody(String body) {
  final blocks = <HelpBlock>[];
  final paragraph = <String>[];

  HelpBlock make(HelpBlockKind kind, String raw, {int? number}) {
    final ranges = <(int, int)>[];
    final out = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final start = raw.indexOf('**', i);
      if (start < 0) {
        out.write(raw.substring(i));
        break;
      }
      final end = raw.indexOf('**', start + 2);
      if (end < 0) {
        out.write(raw.substring(i));
        break;
      }
      out.write(raw.substring(i, start));
      final from = out.length;
      out.write(raw.substring(start + 2, end));
      ranges.add((from, out.length));
      i = end + 2;
    }
    return HelpBlock(kind, out.toString(), number: number, boldRanges: ranges);
  }

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(make(HelpBlockKind.paragraph, paragraph.join(' ')));
    paragraph.clear();
  }

  final numbered = RegExp(r'^(\d+)\.\s+(.*)$');
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('- ')) {
      flush();
      blocks.add(make(HelpBlockKind.bullet, line.substring(2).trim()));
      continue;
    }
    if (line.startsWith('## ')) {
      flush();
      blocks.add(make(HelpBlockKind.heading, line.substring(3).trim()));
      continue;
    }
    final m = numbered.firstMatch(line);
    if (m != null) {
      flush();
      blocks.add(
        make(
          HelpBlockKind.step,
          m.group(2)!.trim(),
          number: int.parse(m.group(1)!),
        ),
      );
      continue;
    }
    // A line that continues the bullet or step above it.
    if (paragraph.isEmpty &&
        blocks.isNotEmpty &&
        blocks.last.kind != HelpBlockKind.paragraph &&
        blocks.last.kind != HelpBlockKind.heading &&
        raw.startsWith('  ')) {
      final last = blocks.removeLast();
      final joined = _rawOf(last);
      blocks.add(make(last.kind, '$joined $line', number: last.number));
      continue;
    }
    paragraph.add(line);
  }
  flush();
  return blocks;
}

/// [block]'s text with its bold marks put back.
String _rawOf(HelpBlock block) {
  final ranges = block.boldRanges;
  if (ranges.isEmpty) return block.text;
  final out = StringBuffer();
  var at = 0;
  for (final (from, to) in ranges) {
    out
      ..write(block.text.substring(at, from))
      ..write('**')
      ..write(block.text.substring(from, to))
      ..write('**');
    at = to;
  }
  out.write(block.text.substring(at));
  return out.toString();
}

class HelpFormatException implements Exception {
  HelpFormatException(this.message);
  final String message;
  @override
  String toString() => 'HelpFormatException: $message';
}

/// All articles of one language, in file order.
class HelpLibrary {
  HelpLibrary(List<HelpArticle> articles)
    : articles = List.unmodifiable(articles),
      _byId = {for (final a in articles) a.id: a};

  final List<HelpArticle> articles;
  final Map<String, HelpArticle> _byId;

  HelpArticle? byId(String id) => _byId[id];

  /// Section names in the order they first appear.
  List<String> get sections => [for (final a in articles) a.section]
      .fold<List<String>>(
        [],
        (list, s) => list.contains(s) ? list : (list..add(s)),
      );

  /// Parses a help file (see the top of this file). Throws
  /// [HelpFormatException] for an article without a title or body, or a
  /// repeated id.
  factory HelpLibrary.parse(String source) {
    final articles = <HelpArticle>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    var i = 0;
    while (i < lines.length && !lines[i].startsWith('=== ')) {
      i++;
    }
    final seen = <String>{};
    while (i < lines.length) {
      final id = lines[i].substring(4).trim();
      if (id.isEmpty) throw HelpFormatException('Article without an id');
      if (!seen.add(id)) throw HelpFormatException('Id "$id" is used twice');
      i++;
      final fields = <String, String>{};
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        final line = lines[i];
        final colon = line.indexOf(':');
        if (colon <= 0) {
          throw HelpFormatException(
            '"$id": expected "key: value", got "$line"',
          );
        }
        fields[line.substring(0, colon).trim().toLowerCase()] = line
            .substring(colon + 1)
            .trim();
        i++;
      }
      final body = <String>[];
      while (i < lines.length && !lines[i].startsWith('=== ')) {
        body.add(lines[i]);
        i++;
      }
      List<String> list(String? value) => [
        for (final part in (value ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
      final title = fields['title'] ?? '';
      final text = body.join('\n').trim();
      if (title.isEmpty) throw HelpFormatException('"$id" has no title');
      if (text.isEmpty) throw HelpFormatException('"$id" has no text');
      articles.add(
        HelpArticle(
          id: id,
          title: title,
          section: fields['section'] ?? 'More',
          keywords: list(fields['keywords']),
          related: list(fields['related']),
          body: text,
          comingLater: fields['status'] == 'coming-later',
        ),
      );
    }
    return HelpLibrary(articles);
  }

  /// Related links that point to no article, as `from -> to`.
  List<String> brokenLinks() => [
    for (final a in articles)
      for (final r in a.related)
        if (!_byId.containsKey(r)) '${a.id} -> $r',
  ];
}
