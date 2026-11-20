// The outside addresses (1.16): lib/core/links.dart is the app's copy of
// tool/ci/links.json, what a latest.json says about them is checked before
// it is used, and the site's address is written nowhere else in lib/,
// tool/ or web/.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/links.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Map<String, Object?> linksFile() =>
    jsonDecode(File(p.join('tool', 'ci', 'links.json')).readAsStringSync())
        as Map<String, Object?>;

/// links.json with every address written out.
Map<String, String> fullLinks() {
  final file = linksFile();
  final site = file['site'] as String;
  return {
    'site': site,
    for (final e in (file['links'] as Map).entries)
      '${e.key}': '${e.value}'.startsWith('/') ? '$site${e.value}' : '${e.value}',
  };
}

void main() {
  group('the built-in addresses', () {
    test('are the ones in tool/ci/links.json', () {
      final file = linksFile();
      expect(AppLinks.builtIn.toJson(), fullLinks(),
          reason: 'tool/ci/links.json changed: copy it into lib/core/links.dart');
      expect(AppLinks.builtIn.toJson().keys, kLinkNames);
      expect(kRepositoryUrl, file['repository']);
      expect(kFeedbackApiHosts, file['feedback_api_hosts']);
      expect(kLatestJsonUrl,
          '${file['repository']}/releases/latest/download/latest.json');
      expect(kReleasesUrl, '${file['repository']}/releases');
    });

    test('pass their own checks', () {
      for (final e in AppLinks.builtIn.toJson().entries) {
        expect(checkedLink(e.value), e.value, reason: e.key);
      }
      expect(AppLinks.builtIn.withOverrides(AppLinks.builtIn.toJson()),
          AppLinks.builtIn);
      expect(AppLinks.builtIn.siteLabel, isNot(contains('/')));
    });
  });

  group('what a latest.json says about the addresses', () {
    const moved = {
      'site': 'https://newname.example',
      'download': 'https://newname.example/get',
      'feedback_api': 'https://newname.example/api/feedback',
      'feedback_page': 'https://newname.example/feedback',
      'help': 'https://newname.example/help',
      'privacy': 'https://newname.example/privacy',
    };

    test('a complete, valid set replaces the built-in ones', () {
      final links = AppLinks.builtIn.withOverrides(moved);
      expect(links.toJson(), moved);
      expect(links.siteLabel, 'newname.example');
    });

    test('only https, a real host, a sane length; bad values are ignored one by one', () {
      for (final bad in <Object?>[
        'http://newname.example/get',
        'ftp://newname.example/get',
        'javascript:alert(1)',
        'https://user:secret@newname.example/get',
        'https:///get',
        'https://localhost/get',
        'https://newname.example/a b',
        'https://newname.example/a\nb',
        'https://newname.example/${'x' * 200}',
        '//newname.example/get',
        '/get',
        '',
        42,
        null,
        ['https://newname.example/get'],
      ]) {
        final links = AppLinks.builtIn.withOverrides({...moved, 'download': bad});
        expect(links.download, AppLinks.builtIn.download, reason: '$bad');
        // The others still apply.
        expect(links.help, moved['help'], reason: '$bad');
      }
      expect(AppLinks.builtIn.withOverrides('nonsense'), AppLinks.builtIn);
      expect(AppLinks.builtIn.withOverrides(null), AppLinks.builtIn);
      expect(AppLinks.builtIn.withOverrides(const <String, String>{}), AppLinks.builtIn);
    });

    test('feedback goes to the site\'s own host only', () {
      // Another host: ignored, the built-in address stays.
      var links = AppLinks.builtIn.withOverrides(
          {...moved, 'feedback_api': 'https://collector.example/api/feedback'});
      expect(links.feedbackApi, AppLinks.builtIn.feedbackApi);
      expect(links.site, moved['site']);
      // Only the feedback address, pointing away from the built-in site.
      links = AppLinks.builtIn
          .withOverrides({'feedback_api': 'https://collector.example/api/feedback'});
      expect(links, AppLinks.builtIn);
      // A look-alike host is another host.
      links = AppLinks.builtIn.withOverrides(
          {...moved, 'feedback_api': 'https://newname.example.evil.example/api'});
      expect(links.feedbackApi, AppLinks.builtIn.feedbackApi);
      // Same host as the (new) site: taken.
      links = AppLinks.builtIn.withOverrides(moved);
      expect(links.feedbackApi, moved['feedback_api']);
      // Same host as the built-in site, other path: taken.
      final other = '${AppLinks.builtIn.site}/api/v2/feedback';
      expect(AppLinks.builtIn.withOverrides({'feedback_api': other}).feedbackApi, other);
    });

    test('http is for tests with a local server only', () {
      const local = {'site': 'http://127.0.0.1:8080', 'feedback_api': 'http://127.0.0.1:8080/api/feedback'};
      expect(AppLinks.builtIn.withOverrides(local), AppLinks.builtIn);
      final links = AppLinks.builtIn.withOverrides(local, allowHttp: true);
      expect(links.feedbackApi, local['feedback_api']);
    });

    String latest({Object? links, bool withLinks = true}) => jsonEncode({
          'version': '1.16.0',
          'build': 160,
          'date': '2026-11-20T10:00:00Z',
          'notes_url': 'https://example.org/releases/tag/v1.16.0',
          'platforms': {
            'windows': {
              'url': 'https://example.org/ClipForge-windows.zip',
              'size': 10,
              'sha256': 'a' * 64,
            },
          },
          if (withLinks) 'links': links,
        });

    test('latest.json: "links" is read; files without it still work', () {
      final withLinks = UpdateInfo.parse(latest(links: moved));
      expect(withLinks.links, moved);
      expect(withLinks.platforms.keys, ['windows']);
      expect(AppLinks.builtIn.withOverrides(withLinks.links).download, moved['download']);

      // 1.12 - 1.15: no "links".
      final old = UpdateInfo.parse(latest(withLinks: false));
      expect(old.links, isNull);
      expect(old.version, '1.16.0');
      expect(old.build, 160);
      expect(old.platforms['windows']!.size, 10);
      expect(AppLinks.builtIn.withOverrides(old.links), AppLinks.builtIn);

      // Before 1.12: no "platforms" either.
      final oldest = UpdateInfo.parse('{"version":"1.11.0","build":120}');
      expect(oldest.links, isNull);
      expect(oldest.platforms, isEmpty);
    });

    test('latest.json: odd "links" never break the update check', () {
      for (final odd in <Object?>[null, 'x', 7, <Object?>[], <String, Object?>{}, {'site': 5}, {'unknown': 'https://a.example'}]) {
        final info = UpdateInfo.parse(latest(links: odd));
        expect(info.links, isNull, reason: '$odd');
        expect(info.build, 160);
      }
      // Unknown names are dropped, known ones kept as text (checked later).
      final info = UpdateInfo.parse(latest(links: {...moved, 'extra': 'https://x.example', 'help': 3}));
      expect(info.links!.keys, ['site', 'download', 'feedback_api', 'feedback_page', 'privacy']);
    });
  });

  test('the site\'s address is written in ONE place (lib/, tool/, web/)', () {
    final file = linksFile();
    // What must not be copied around: the site's host, and the old pages'.
    final needles = {
      Uri.parse(file['site'] as String).host,
      Uri.parse(file['old_pages'] as String).host,
    };
    expect(needles.every((n) => n.contains('.')), isTrue);
    // The only files that may hold them.
    final allowed = {
      p.join('lib', 'core', 'links.dart'),
      p.join('tool', 'ci', 'links.json'),
    };
    const skipDirs = {'node_modules', '.next', 'generated', '__pycache__', '.vercel', 'shots'};
    const textTypes = {
      '.dart', '.py', '.json', '.md', '.ts', '.tsx', '.mjs', '.js', '.css', '.html', //
      '.txt', '.yaml', '.yml', '.sh', '.ps1', '.cmd', '.example', '',
    };
    final found = <String>[];
    var scanned = 0;
    void scan(String root) {
      final dir = Directory(root);
      if (!dir.existsSync()) return;
      final pending = [dir];
      while (pending.isNotEmpty) {
        for (final entry in pending.removeLast().listSync(followLinks: false)) {
          final name = p.basename(entry.path);
          if (entry is Directory) {
            if (!skipDirs.contains(name)) pending.add(entry);
            continue;
          }
          if (entry is! File || !textTypes.contains(p.extension(name).toLowerCase())) continue;
          if (allowed.contains(p.normalize(entry.path))) continue;
          if (entry.lengthSync() > 2 * 1024 * 1024) continue;
          final String text;
          try {
            text = entry.readAsStringSync();
          } on FileSystemException {
            continue;
          }
          scanned++;
          for (final needle in needles) {
            if (text.contains(needle)) found.add('${entry.path}: $needle');
          }
        }
      }
    }

    scan('lib');
    scan('tool');
    scan('bin');
    scan('assets');
    final web = p.join('..', 'web');
    scan(web);
    expect(scanned, greaterThan(100));
    expect(Directory(web).existsSync(), isTrue, reason: 'the website sits next to the app');
    expect(found, isEmpty,
        reason: 'An outside address is written outside tool/ci/links.json and '
            'lib/core/links.dart. Read it from there instead (docs/RENAMING.md).');
  });
}
