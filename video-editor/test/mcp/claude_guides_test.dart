// The guide that tells Claude how to work with ClipForge lives INSIDE the
// helper since 1.12 (the `get_guide` tool): claude/guide/*.md, compiled in
// through lib/mcp/guide_content.dart. It must not drift away from the
// tools the server really has:
//  - the generated Dart file is exactly what tool/gen_guide.dart makes of
//    the Markdown files;
//  - every registered tool is documented in the "tools" section;
//  - no section names a tool that does not exist;
//  - the skill (claude/skill/clipforge-editing) and claude/CLAUDE.md are
//    thin pointers to get_guide that never need to change, and keep the
//    shape Claude's skill upload expects (docs/tools/build_claude_bundles.py
//    checks the same in CI).

import 'dart:io';

import 'package:clipforge/mcp/guide_content.dart';
import 'package:clipforge/mcp/tools.dart' show kServerInstructions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/gen_guide.dart';
import 'support.dart';

void main() {
  final skillDir = p.join('claude', 'skill', 'clipforge-editing');
  late Bench b;
  late Set<String> toolNames;

  setUpAll(() {
    b = Bench(ffmpeg: false);
    toolNames = {for (final t in b.tools.tools) t.name};
  });
  tearDownAll(() => b.dispose());

  String read(String path) => File(path).readAsStringSync();

  /// Words in `backticks` that look like tool names (snake_case verbs).
  Set<String> backticked(String text) => {
        for (final m in RegExp(r'`([a-z]+(?:_[a-z]+)+)`').allMatches(text))
          m.group(1)!,
      };

  test('the guide in the helper is the Markdown in claude/guide', () {
    expect(read(p.join('lib', 'mcp', 'guide_content.dart')),
        generateGuideDart(p.join('claude', 'guide')),
        reason: 'run: dart run tool/gen_guide.dart');
    expect(kGuideSections.keys, ['start', 'recipes', 'tools', 'troubleshooting']);
    expect(kGuideSummaries.keys, kGuideSections.keys);
    for (final e in kGuideSections.entries) {
      expect(e.value.trim(), read(p.join('claude', 'guide', '${e.key}.md')).trim());
    }
  });

  test('the bundled tools section documents every tool', () {
    final text = kGuideSections['tools']!;
    final missing = [
      for (final t in toolNames)
        if (!text.contains('`$t`')) t,
    ];
    expect(missing, isEmpty, reason: 'add these tools to claude/guide/tools.md');
    expect(text, contains('All ${toolNames.length} tools'),
        reason: 'tools.md says how many tools there are');
  });

  test('the guide names no tool that does not exist', () {
    // Verb-first snake_case words in backticks are tool names; everything
    // else in backticks is an argument (duck_under_speech, crop_shape…).
    const verbs = {
      'get', 'list', 'create', 'duplicate', 'rename', 'set', 'add', 'trim',
      'split', 'remove', 'move', 'import', 'export', 'update', 'separate',
      'reattach', 'copy', 'apply', 'freeze', 'fit', 'relink', 'cancel', 'align',
      'find', 'captions', 'make', 'restore', 'self', 'replace',
    };
    final verbFirst = {
      for (final t in toolNames)
        if (t.contains('_')) t.split('_').first,
    };
    expect(verbs.containsAll(verbFirst), isTrue,
        reason: 'a tool starts with a new verb: add it to this test '
            '(${verbFirst.difference(verbs)})');
    // Arguments that also start with one of those verbs.
    const arguments = {
      'fit_music', 'export_job', 'match_first_clip', 'remove_fillers_strength', //
      'replace_existing', 'replace_existing_captions',
    };
    final texts = {
      for (final e in kGuideSections.entries) 'guide section ${e.key}': e.value,
      'claude/CLAUDE.md': read(p.join('claude', 'CLAUDE.md')),
      'SKILL.md': read(p.join(skillDir, 'SKILL.md')),
    };
    for (final e in texts.entries) {
      final unknown = backticked(e.value)
          .where((w) => verbs.contains(w.split('_').first))
          .where((w) => !toolNames.contains(w) && !arguments.contains(w))
          .toList();
      expect(unknown, isEmpty, reason: '${e.key} names tools that do not exist');
    }
  });

  test('get_guide serves every section; start is the default', () async {
    final start = await b.client.ok('get_guide');
    expect(start.data['section'], 'start');
    expect(start.text, startsWith(kGuideSections['start']!.substring(0, 60)));
    expect(start.text, contains('Other sections'));
    for (final s in kGuideSections.keys) {
      final r = await b.client.ok('get_guide', {'section': s});
      expect(r.data['text'], kGuideSections[s]);
    }
    expect(await b.client.fails('get_guide', {'section': 'nope'}), contains('must be one of'));
    // The rules the owner asked for are in the part Claude always reads.
    for (final must in [
      'get_status',
      'dry_run',
      'get_export_status',
      'duplicate_project',
      'cannot see the picture',
      'download_pack',
      'strength: "light"',
      'restore_cut',
      'home screen',
      'Go ahead?',
    ]) {
      expect(kGuideSections['start'], contains(must));
    }
    expect(kGuideSections['troubleshooting'], contains('`self_test`'));
  });

  test('the server tells Claude to read the guide first', () {
    expect(kServerInstructions, contains('get_guide'));
    expect(kServerInstructions.indexOf('get_guide'),
        lessThan(kServerInstructions.indexOf('Workflow:')));
  });

  test('the skill is a thin pointer with the shape Claude expects', () {
    // Only SKILL.md: nothing in the skill has to follow the app's versions.
    expect(
        Directory(skillDir).listSync().map((e) => p.basename(e.path)), ['SKILL.md']);
    final text = read(p.join(skillDir, 'SKILL.md'));
    final m = RegExp(r'^---\n(.*?)\n---\n(.*)$', dotAll: true).firstMatch(text);
    expect(m, isNotNull, reason: 'SKILL.md starts with frontmatter');
    final front = m!.group(1)!;
    final body = m.group(2)!;
    final name = RegExp(r'^name: (.+)$', multiLine: true).firstMatch(front)?.group(1);
    final description =
        RegExp(r'^description: (.+)$', multiLine: true).firstMatch(front)?.group(1);
    // The folder (and the root of the zip) is named like the skill.
    expect(name, p.basename(skillDir));
    expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name!), isTrue);
    expect(description, isNotNull);
    expect(description!.length, lessThanOrEqualTo(1024));
    expect(description, contains('ClipForge'));
    expect(body.split('\n').length, lessThan(60), reason: 'thin: the guide is in the helper');
    expect(body, contains('`get_guide`'));
    expect(body, contains('Connect to Claude'));
    // Nothing that changes from version to version.
    expect(RegExp(r'\b1\.\d+\b').hasMatch(body), isFalse,
        reason: 'no version numbers in the skill');
    expect(RegExp(r'\]\([A-Za-z0-9_./-]+\.md\)').hasMatch(text), isFalse,
        reason: 'no links to files that are not in the skill');
  });

  test('claude/CLAUDE.md is a thin pointer too', () {
    final text = read(p.join('claude', 'CLAUDE.md'));
    expect(text.split('\n').length, lessThan(50));
    expect(text, contains('`get_guide`'));
    expect(text, contains('`self_test`'));
  });
}
