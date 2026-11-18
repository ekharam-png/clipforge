// The two guides that tell Claude how to work with ClipForge must not drift
// away from the tools the server really has:
//  - claude/CLAUDE.md (read by Claude Code, shipped next to clipforge-mcp),
//  - the skill claude/skill/clipforge-editing (uploaded to Claude; its
//    tools.md is the full tool reference).
// Every registered tool must be named in both, neither may name a tool that
// does not exist, and the skill must keep the shape Claude's skill upload
// expects (docs/tools/build_claude_bundles.py checks the same in CI).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  final skillDir = p.join('claude', 'skill', 'clipforge-editing');
  late Set<String> toolNames;

  setUpAll(() {
    final b = Bench();
    toolNames = {for (final t in b.tools.tools) t.name};
    b.dispose();
  });

  String read(String path) => File(path).readAsStringSync();

  /// Words in `backticks` that look like tool names (snake_case verbs).
  Set<String> backticked(String text) => {
        for (final m in RegExp(r'`([a-z]+(?:_[a-z]+)+)`').allMatches(text))
          m.group(1)!,
      };

  test('the skill tools.md names every tool', () {
    final text = read(p.join(skillDir, 'tools.md'));
    final missing = [
      for (final t in toolNames)
        if (!text.contains('`$t`')) t,
    ];
    expect(missing, isEmpty,
        reason: 'add these tools to $skillDir/tools.md');
    expect(text, contains('All ${toolNames.length} tools'),
        reason: 'tools.md says how many tools there are');
  });

  test('claude/CLAUDE.md names every tool', () {
    final text = read(p.join('claude', 'CLAUDE.md'));
    final missing = [
      for (final t in toolNames)
        if (!text.contains('`$t`')) t,
    ];
    expect(missing, isEmpty, reason: 'add these tools to claude/CLAUDE.md');
  });

  test('the guides name no tool that does not exist', () {
    // Verb-first snake_case words in backticks are tool names; everything
    // else in backticks is an argument (duck_under_speech, crop_shape…).
    const verbs = {
      'get', 'list', 'create', 'duplicate', 'rename', 'set', 'add', 'trim',
      'split', 'remove', 'move', 'import', 'export', 'update', 'separate',
      'reattach', 'copy', 'apply', 'freeze', 'fit', 'relink', 'cancel', 'align',
      'find', 'captions', 'make', 'restore',
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
    };
    for (final file in [
      p.join('claude', 'CLAUDE.md'),
      for (final f in ['SKILL.md', 'tools.md', 'recipes.md', 'troubleshooting.md'])
        p.join(skillDir, f),
    ]) {
      final unknown = backticked(read(file))
          .where((w) => verbs.contains(w.split('_').first))
          .where((w) => !toolNames.contains(w) && !arguments.contains(w))
          .toList();
      expect(unknown, isEmpty, reason: '$file names tools that do not exist');
    }
  });

  test('the skill has the shape Claude expects', () {
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
    expect(body.split('\n').length, lessThan(500));
    // Every reference file it links to exists.
    for (final link in RegExp(r'\]\(([A-Za-z0-9_./-]+\.md)\)').allMatches(text)) {
      expect(File(p.join(skillDir, link.group(1)!)).existsSync(), isTrue,
          reason: 'SKILL.md links to ${link.group(1)}');
    }
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
      expect(body, contains(must));
    }
  });
}
