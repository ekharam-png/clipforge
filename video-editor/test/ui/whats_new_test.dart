// CHANGELOG.md, pubspec.yaml's version and the "What's new" help article
// (lib/ui/help/whats_new.dart) must agree: bump both for a release.

import 'dart:io';

import 'package:clipforge/ui/help/help_content.dart';
import 'package:clipforge/ui/help/help_screen.dart';
import 'package:clipforge/ui/help/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

import 'help_content_test.dart' show kNotAppLabels;

void main() {
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final entries = parseChangelog(changelog);

  test('the newest CHANGELOG version is pubspec.yaml\'s version', () {
    final version = RegExp(r'^version:\s*([^\s+#]+)', multiLine: true)
        .firstMatch(pubspec)![1];
    expect(entries, isNotEmpty);
    expect(entries.first.version, version,
        reason: 'pubspec.yaml says $version but the top of CHANGELOG.md is '
            '${entries.first.version}. Add a "## $version – <date>" section '
            'at the top of CHANGELOG.md (or fix pubspec.yaml).');
  });

  test('CHANGELOG.md is bundled with the app (pubspec assets)', () {
    expect(pubspec, contains('    - $kChangelogAsset\n'));
  });

  test('versions go down, each has a date and some text', () {
    List<int> parts(String v) => [for (final p in v.split('.')) int.parse(p)];
    int compare(List<int> a, List<int> b) {
      for (var i = 0; i < 3; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return 0;
    }

    final versions = [for (final e in entries) e.version];
    expect(versions.toSet().length, versions.length, reason: 'no repeats');
    for (var i = 1; i < entries.length; i++) {
      expect(compare(parts(entries[i - 1].version), parts(entries[i].version)),
          greaterThan(0),
          reason: 'newest first: ${entries[i - 1].version} before '
              '${entries[i].version}');
    }
    for (final e in entries) {
      expect(e.date, matches(RegExp(r'^\d{1,2} [A-Z][a-z]+ \d{4}$')),
          reason: e.version);
      expect(e.body, isNotEmpty, reason: e.version);
    }
    expect(versions, containsAllInOrder(['1.4.0', '1.3.0', '1.2.0', '1.1.0', '1.0.0']));
  });

  test('bold words in CHANGELOG.md are labels the app shows', () {
    final code = StringBuffer();
    for (final f in Directory('lib/ui').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) code.write(f.readAsStringSync());
    }
    final missing = [
      for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(changelog))
        if (!kNotAppLabels.contains(m[1]) && !code.toString().contains(m[1]!))
          m[1],
    ];
    expect(missing, isEmpty);
  });

  test('parsing', () {
    final parsed = parseChangelog('''
# Title

Intro text.

## 2.0.0 – 1 December 2026

- New thing.

## 1.9.1 - 2 November 2026
- Fix.
## 1.9.0
Plain.
''');
    expect([for (final e in parsed) e.version], ['2.0.0', '1.9.1', '1.9.0']);
    expect(parsed[0].date, '1 December 2026');
    expect(parsed[0].body, '- New thing.');
    expect(parsed[1].date, '2 November 2026');
    expect(parsed[2].date, '');
    expect(parsed[2].body, 'Plain.');
    expect(parseChangelog('# Nothing yet'), isEmpty);
  });

  test('the What\'s new article lists every version, newest first', () {
    final article = whatsNewArticle(changelog, currentVersion: '1.4.0 (build 7)')!;
    expect(article.id, kWhatsNewId);
    expect(article.plainBody, startsWith('You have ClipForge 1.4.0 (build 7).'));
    final headings = [
      for (final b in article.blocks)
        if (b.kind == HelpBlockKind.heading) b.text,
    ];
    expect(headings, [
      for (final e in entries) '${e.version} – ${e.date}',
    ]);
    expect(article.plainBody.contains('**'), isFalse);
    expect(whatsNewArticle('nothing'), isNull);
  });

  test('Help gets the article second, after Getting started', () {
    final help = HelpLibrary.parse(File(helpAssetFor('en')).readAsStringSync());
    final withIt = withWhatsNew(help, changelog);
    expect(withIt.articles.length, help.articles.length + 1);
    expect(withIt.articles[1].id, kWhatsNewId);
    expect(withIt.brokenLinks(), isEmpty);
    // Not added twice, nor when there are no versions.
    expect(withWhatsNew(withIt, changelog).articles.length, withIt.articles.length);
    expect(withWhatsNew(help, '# empty').articles.length, help.articles.length);
  });
}
