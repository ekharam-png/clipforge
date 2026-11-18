// The "What's new" help article, made from CHANGELOG.md (bundled as an
// asset) when Help loads, so it cannot drift from the release notes.
// Pure Dart.
//
// CHANGELOG.md format: an optional title line "# ..." and intro, then one
// section per version, newest first:
//
//   ## 1.4.0 – 16 November 2026
//
//   - What changed, in plain words. **Bold** only for the app's own labels.
//
// The section text uses the help body format (help_content.dart).

import 'help_content.dart';

/// Id of the generated article.
const String kWhatsNewId = 'whats-new';

/// The asset the release notes are read from.
const String kChangelogAsset = 'CHANGELOG.md';

/// One version's section of CHANGELOG.md.
class ChangelogEntry {
  const ChangelogEntry(
      {required this.version, required this.date, required this.body});

  /// "1.4.0".
  final String version;

  /// "16 November 2026" (as written).
  final String date;

  /// The section's text, without its heading.
  final String body;
}

final _heading = RegExp(r'^##\s+(\d+\.\d+\.\d+)\s*(?:[–—-]\s*(.*))?$');

/// The version sections of [source], newest (first in the file) first.
List<ChangelogEntry> parseChangelog(String source) {
  final entries = <ChangelogEntry>[];
  String? version;
  var date = '';
  final body = <String>[];
  void flush() {
    if (version != null) {
      entries.add(ChangelogEntry(
          version: version, date: date, body: body.join('\n').trim()));
    }
    body.clear();
  }

  for (final line in source.replaceAll('\r\n', '\n').split('\n')) {
    final m = _heading.firstMatch(line.trim());
    if (m != null) {
      flush();
      version = m.group(1);
      date = (m.group(2) ?? '').trim();
      continue;
    }
    if (version != null) body.add(line);
  }
  flush();
  return entries;
}

/// The help article listing every version, newest first. Null when
/// [changelog] has no version sections.
HelpArticle? whatsNewArticle(String changelog, {String? currentVersion}) {
  final entries = parseChangelog(changelog);
  if (entries.isEmpty) return null;
  final out = StringBuffer();
  if (currentVersion != null) {
    out
      ..writeln('You have ClipForge $currentVersion. Help > **About ClipForge** '
          'shows the exact build; **Copy version info** copies it for a bug '
          'report.')
      ..writeln();
  }
  for (final e in entries) {
    out
      ..writeln('## ${e.version}${e.date.isEmpty ? '' : ' – ${e.date}'}')
      ..writeln(e.body)
      ..writeln();
  }
  return HelpArticle(
    id: kWhatsNewId,
    title: "What's new",
    section: 'Getting started',
    keywords: const [
      'whats new', 'new', 'changes', 'changelog', 'release notes', //
      'version', 'update', 'updated', 'build', 'latest',
    ],
    related: const ['about-version', 'getting-started'],
    body: out.toString().trim(),
  );
}

/// [library] with the "What's new" article added after the first
/// article (or unchanged when [changelog] has no versions).
HelpLibrary withWhatsNew(HelpLibrary library, String changelog,
    {String? currentVersion}) {
  final article = whatsNewArticle(changelog, currentVersion: currentVersion);
  if (article == null || library.byId(kWhatsNewId) != null) return library;
  final articles = [...library.articles];
  articles.insert(articles.isEmpty ? 0 : 1, article);
  return HelpLibrary(articles);
}
