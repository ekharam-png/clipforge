// Chapters and the text that goes with a published video (1.14). Pure
// Dart; used by the Publishing notes panel, the kit's text file and
// Claude's make_chapters.

import '../model/project.dart';
import '../music/openverse.dart' show creditsText;
import '../text/text_document.dart';

/// THE RULES of a chapter list, in one place. They are YouTube's (as
/// known in November 2026; the site decides, check there): the list is
/// only turned into chapters when the first one is at 0:00, there are at
/// least three, and each is at least 10 seconds long.
class ChapterRules {
  const ChapterRules({
    this.firstAtZero = true,
    this.minGapMs = 10000,
    this.minCount = 3,
    this.maxTitleChars = 60,
    this.maxAutomatic = 12,
    this.firstTitle = 'Start',
  });

  /// The first chapter must start at 0:00.
  final bool firstAtZero;

  /// Shortest chapter.
  final int minGapMs;

  /// Fewest chapters a site shows as chapters.
  final int minCount;

  /// Longer chapter titles are cut at a word.
  final int maxTitleChars;

  /// "Chapters from titles / captions" never proposes more than this
  /// (a 40-minute talk would otherwise get a chapter per breath).
  final int maxAutomatic;

  /// What the 0:00 chapter is called when nothing better is known.
  final String firstTitle;
}

const ChapterRules kChapterRules = ChapterRules();

/// "0:00", "12:05", "1:02:03".
String chapterTime(int ms) {
  final s = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = s ~/ 3600, m = s ~/ 60 % 60, sec = s % 60;
  final two = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$two' : '$m:$two';
}

/// Reads "1:02:03", "12:05" or "75" (seconds) as ms; null when it is not
/// a time.
int? parseChapterTime(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  var total = 0;
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null || v < 0) return null;
    total = total * 60 + v;
  }
  return total * 1000;
}

/// The list as it is pasted into a description: one "0:00 Title" per line.
String formatChapters(List<Chapter> chapters) =>
    [for (final c in chapters) '${chapterTime(c.ms)} ${c.title}'].join('\n');

/// Reads a list typed or pasted as "0:00 Title" lines (a dash or dot after
/// the time is fine). Lines without a time are skipped.
List<Chapter> parseChapters(String text) {
  final out = <Chapter>[];
  final line = RegExp(r'^\s*\(?(\d{1,2}(?::\d{1,2}){1,2})\)?\s*[-–—.:]?\s*(.*)$');
  for (final raw in text.split('\n')) {
    final m = line.firstMatch(raw);
    if (m == null) continue;
    final ms = parseChapterTime(m.group(1)!);
    if (ms == null) continue;
    out.add(Chapter(ms, m.group(2)!.trim()));
  }
  out.sort((a, b) => a.ms.compareTo(b.ms));
  return out;
}

/// What is wrong with [chapters] as a site would see it; empty when it
/// keeps to [rules]. An empty list has no problems (there are simply no
/// chapters).
List<String> chapterProblems(List<Chapter> chapters, int durationMs,
    {ChapterRules rules = kChapterRules}) {
  if (chapters.isEmpty) return const [];
  final out = <String>[];
  if (rules.firstAtZero && chapters.first.ms != 0) {
    out.add('The first chapter must start at 0:00.');
  }
  if (chapters.length < rules.minCount) {
    out.add('Sites show chapters only when there are at least '
        '${rules.minCount}.');
  }
  for (var i = 0; i < chapters.length; i++) {
    final end = i + 1 < chapters.length ? chapters[i + 1].ms : durationMs;
    if (end - chapters[i].ms < rules.minGapMs) {
      out.add('"${chapterTime(chapters[i].ms)} ${chapters[i].title}" is '
          'shorter than ${rules.minGapMs ~/ 1000} seconds.');
      break;
    }
  }
  if (durationMs > 0 && chapters.last.ms >= durationMs) {
    out.add('The last chapter starts after the end of the video.');
  }
  return out;
}

String _shorten(String text, int maxChars) {
  var t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // A caption's sentence mark is not part of a chapter title.
  t = t.replaceFirst(RegExp(r'[.,;:!…]+$'), '');
  if (t.length <= maxChars) return t;
  final cut = t.substring(0, maxChars);
  final space = cut.lastIndexOf(' ');
  return '${(space > maxChars ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Somewhere a chapter could start.
typedef ChapterPoint = ({int ms, String title});

/// Turns [points] (in time order) into a list that keeps to [rules]: the
/// first at 0:00 (a point within the first chapter's length moves there,
/// else a [ChapterRules.firstTitle] chapter is put in front), none closer
/// than [minGapMs] to the one before or to the end, titles shortened.
List<Chapter> chaptersFromPoints(List<ChapterPoint> points, int durationMs,
    {ChapterRules rules = kChapterRules, int? minGapMs}) {
  final gap = minGapMs == null || minGapMs < rules.minGapMs
      ? rules.minGapMs
      : minGapMs;
  final sorted = [...points]..sort((a, b) => a.ms.compareTo(b.ms));
  final out = <Chapter>[];
  for (final p in sorted) {
    final title = _shorten(p.title, rules.maxTitleChars);
    if (title.isEmpty) continue;
    var ms = p.ms < 0 ? 0 : p.ms;
    if (out.isEmpty) {
      if (rules.firstAtZero && ms > 0) {
        if (ms < rules.minGapMs) {
          ms = 0;
        } else {
          out.add(Chapter(0, rules.firstTitle));
        }
      }
    }
    if (out.isNotEmpty && ms - out.last.ms < gap) continue;
    if (durationMs > 0 && durationMs - ms < rules.minGapMs) continue;
    out.add(Chapter(ms, title));
  }
  return out;
}

/// Where the chapters of [project] came from.
enum ChapterSource { titles, captions, speakers, none }

/// "Chapters from titles / captions…": a chapter list for [project].
///  * From its TITLES (not captions, not the music credits box): one
///    chapter where each title appears, named by its first line.
///  * Without titles, from its CAPTIONS: where a new paragraph of the
///    Text window starts (the speaker changes, or a pause of 2 s), named
///    by the first words said (with the speaker's name when known).
///  * Without captions, from [turns] (who speaks when, worked out from
///    the sound): where the speaker changes or talk starts again after a
///    long pause, named "Part n" (with the speaker's name).
/// The automatic sources are thinned to at most
/// [ChapterRules.maxAutomatic] chapters, evenly: the smallest gap is the
/// video's length divided by that number.
({List<Chapter> chapters, ChapterSource source}) buildChapters(
  Project project, {
  List<({String name, int startMs, int endMs})> turns = const [],
  ChapterRules rules = kChapterRules,
}) {
  final total = project.durationMs;
  final titles = [
    for (final t in titleLines(project))
      if (t.text.trim().isNotEmpty && !_isCredits(project, t)) t,
  ];
  if (titles.isNotEmpty) {
    return (
      chapters: chaptersFromPoints([
        for (final t in titles)
          (ms: t.startMs, title: t.raw.trim().split('\n').first),
      ], total, rules: rules),
      source: ChapterSource.titles,
    );
  }
  final autoGap = rules.maxAutomatic <= 0 ? 0 : total ~/ rules.maxAutomatic;
  final captions = captionLines(project);
  if (captions.isNotEmpty) {
    final doc = buildTextDocument(TextSource.captions, captions);
    return (
      chapters: chaptersFromPoints([
        for (final p in doc.paragraphs)
          (
            ms: p.startMs,
            title: '${p.speaker.isEmpty ? '' : '${p.speaker}: '}'
                '${_firstWords(p.text)}',
          ),
      ], total, rules: rules, minGapMs: autoGap),
      source: ChapterSource.captions,
    );
  }
  if (turns.isNotEmpty) {
    var n = 0;
    final named = turns.map((t) => t.name).toSet().length > 1;
    final chapters = chaptersFromPoints([
      for (final t in turns)
        (ms: t.startMs, title: 'Part ${++n}${named ? ' - ${t.name}' : ''}'),
    ], total, rules: rules, minGapMs: autoGap);
    // Number the ones that were kept.
    var k = 0;
    return (
      chapters: [
        for (final c in chapters)
          c.ms == 0 && c.title == rules.firstTitle
              ? c
              : Chapter(
                  c.ms, c.title.replaceFirst(RegExp(r'^Part \d+'), 'Part ${++k}')),
      ],
      source: ChapterSource.speakers,
    );
  }
  return (chapters: const <Chapter>[], source: ChapterSource.none);
}

/// The boxed "music credits" title at the end is not a chapter.
bool _isCredits(Project project, TextLine line) {
  final t = project.titles.where((x) => x.id == line.id).firstOrNull;
  if (t == null || !t.background) return false;
  final credits = creditsText(project);
  return credits.isNotEmpty &&
      t.endMs >= project.durationMs - 200 &&
      line.text.toLowerCase().contains('music');
}

String _firstWords(String text, {int words = 7}) {
  final all = text.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
  // Up to the end of the first sentence when that comes early.
  final out = <String>[];
  for (final w in all) {
    out.add(w);
    if (out.length >= words) break;
    if (out.length >= 3 && RegExp(r'[.!?…]$').hasMatch(w)) break;
  }
  return out.join(' ');
}

/// One "what to paste where" section of the kit's text file.
typedef KitSection = ({String heading, bool shortForm, String file});

/// The text file that goes into the kit folder ("(Project) - text.txt"):
/// title, description, hashtags, tags, chapters, the credits of free music
/// when the project uses any, the short-form title and description when
/// they differ, and a section per exported file saying what to paste
/// there. Everything is plain text made for copy and paste. A project
/// without notes still gets its name as the title.
String kitText(Project project,
    {List<KitSection> sections = const [], String lineEnd = '\n'}) {
  final n = project.publishing;
  final b = StringBuffer();
  void block(String heading, String body) {
    if (body.trim().isEmpty) return;
    if (b.isNotEmpty) b.writeln();
    b
      ..writeln(heading.toUpperCase())
      ..writeln(body.trimRight());
  }

  final title = n.title.trim().isEmpty ? project.name : n.title.trim();
  final credits = creditsText(project);
  block('Title', title);
  block('Description', n.description);
  block('Hashtags', n.hashtagLine);
  block('Tags', n.tagLine);
  block('Chapters', formatChapters(n.chapters));
  block('Music credits', credits);
  final hasShort =
      n.shortTitle.trim().isNotEmpty || n.shortDescription.trim().isNotEmpty;
  if (hasShort) {
    block('Short title (Shorts, Reels, TikTok)', n.titleForShort);
    block('Short description', n.descriptionForShort);
  }
  for (final s in sections) {
    final lines = <String>[
      'File: ${s.file}',
      if (s.file.toLowerCase().endsWith('.txt'))
        ''
      else ...[
        'Title: ${s.shortForm ? (n.titleForShort.trim().isEmpty ? title : n.titleForShort.trim()) : title}',
        ...pasteText(project, shortForm: s.shortForm).split('\n'),
      ],
    ];
    block(s.heading, lines.where((l) => l.isNotEmpty).join('\n'));
  }
  final text = b.toString().trimRight();
  return '${lineEnd == '\n' ? text : text.replaceAll('\n', lineEnd)}$lineEnd';
}

/// What "Copy title and description" puts on the clipboard after the
/// title: the description, then the chapters (long form only), the
/// hashtags and the music credits, with blank lines between.
String pasteText(Project project, {bool shortForm = false}) {
  final n = project.publishing;
  final credits = creditsText(project);
  return [
    (shortForm ? n.descriptionForShort : n.description).trim(),
    if (!shortForm && n.chapters.isNotEmpty) formatChapters(n.chapters),
    n.hashtagLine,
    if (credits.isNotEmpty) 'Music: $credits',
  ].where((s) => s.isNotEmpty).join('\n\n');
}

/// Title, a blank line, then [pasteText].
String titleAndDescription(Project project, {bool shortForm = false}) {
  final n = project.publishing;
  final title = (shortForm ? n.titleForShort : n.title).trim();
  final rest = pasteText(project, shortForm: shortForm);
  return [
    title.isEmpty ? project.name : title,
    if (rest.isNotEmpty) rest,
  ].join('\n\n');
}
