// The same words everywhere (1.15). The audit before 1.15 found the same
// thing called by different names in different places ("Stop" and "Pause"
// for K, "As first clip" and "Same as the first clip", "Check
// automatically"...). This test fails when one of those variants comes
// back in what people read: the strings of lib/ui, the help, the Claude
// guide and the changelog entry of the current version.
//
// To allow a use on purpose, add the exact line (trimmed) to [_allowed]
// with a word why.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (what is banned, what to write instead).
final _banned = <(RegExp, String)>[
  (RegExp(r'\bAs first clip\b'), '"Same as the first clip"'),
  (RegExp(r'\bMatch first clip\b', caseSensitive: false),
      '"Same as the first clip"'),
  (RegExp(r'\bBack to start\b'), '"Go to start"'),
  (RegExp(r'\bMove clip (earlier|later)\b'), '"Move earlier" / "Move later"'),
  (RegExp(r'\bCheck automatically\b'), '"Check for updates automatically"'),
  (RegExp(r'\bZoom (in|out) timeline\b'), '"Zoom in" / "Zoom out"'),
  (RegExp(r'\bSplit at playhead\b'), '"Split"'),
  (RegExp(r'\b(Start|End) clip at playhead\b'),
      '"Start at playhead" / "End at playhead"'),
  (RegExp(r'under Transcript\b'), 'the Text window'),
  (RegExp(r'\bTranscript window\b'), '"Text window"'),
  (RegExp(r'\bImport subtitles\b'), '"Subtitle file (.srt)…"'),
  (RegExp(r'\bSave as subtitle file\b'), '"Export subtitles (.srt)…"'),
  (RegExp(r'\bA line of subtitles\b'), 'a caption'),
  (RegExp(r'\bAdd media…'), '"Videos or photos…"'),
  (RegExp(r'\bAdd music…'), '"Music or sound…"'),
  (RegExp(r'\bAdd voice recording…'), '"Voice recording…"'),
  (RegExp(r'\bMark a good moment \(M\)'), '"Good moment marker"'),
  (RegExp(r'Edit > (Speech|Sound|Shorts)\b'),
      'the Text and speech, Sound or Clip menu'),
  (RegExp(r'Playback > \*?\*?(Show sound waves|Snap)'), 'the View menu'),
];

/// "audio" in a sentence people read: the app says "sound". (File formats,
/// identifiers and the words people search the help with are fine.)
final _audio = RegExp(r'\baudio\b', caseSensitive: false);

/// Lines that may keep a banned word, with the reason.
const _allowed = <String>{};

/// The string literals of a Dart source line (single or double quoted).
Iterable<String> _strings(String line) sync* {
  final code = line.trimLeft();
  if (code.startsWith('//') || code.startsWith('import ') ||
      code.startsWith('export ') || code.startsWith('part ')) {
    return;
  }
  const single = r"'((?:\\.|[^'\\])*)'";
  const double = r'"((?:\\.|[^"\\])*)"';
  for (final m in RegExp('$single|$double').allMatches(line)) {
    yield m.group(1) ?? m.group(2) ?? '';
  }
}

void main() {
  final problems = <String>[];
  void check(String where, String text, {bool audio = false}) {
    for (final (pattern, instead) in _banned) {
      if (pattern.hasMatch(text)) {
        problems.add('$where: "${pattern.firstMatch(text)!.group(0)}" '
            '-> write $instead');
      }
    }
    if (audio && _audio.hasMatch(text)) {
      problems.add('$where: "audio" -> write "sound"');
    }
  }

  test('the strings of lib/ui use the agreed words', () {
    problems.clear();
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_allowed.contains(lines[i].trim())) continue;
        for (final s in _strings(lines[i])) {
          // Keys, file names and identifiers are not sentences.
          final sentence = s.contains(' ') &&
              !s.contains(r'$') &&
              !s.contains('/') &&
              !s.contains('.m4a') &&
              !s.contains('.mp3');
          check('${f.path}:${i + 1}', s, audio: sentence);
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the help uses the agreed words', () {
    problems.clear();
    final lines = File('assets/help/help_en.md').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // The words people type into the search may be any words.
      if (line.startsWith('keywords:') || line.startsWith('#')) continue;
      check('help_en.md:${i + 1}', line,
          // "Podcast audio" is a destination's own name.
          audio: !line.contains('Podcast audio') &&
              !line.contains('podcast audio') &&
              // A file name the export really writes.
              !line.contains('audio.mp3'));
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the Claude guide names the menus as they are now', () {
    problems.clear();
    final dir = Directory('claude/guide');
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        check('${f.path}:${i + 1}', lines[i]);
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the checker itself: it finds a banned word and leaves keys alone',
      () {
    problems.clear();
    check('x', 'Tap Back to start');
    check('x', 'Check automatically');
    check('x', 'The audio is loud', audio: true);
    expect(problems, hasLength(3));
    expect(_strings("  final a = 'audio-\${a.id}';").toList(),
        [r'audio-${a.id}']);
    expect(_strings("import 'audio.dart';"), isEmpty);
  });
}
