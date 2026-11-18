import 'dart:convert';
import 'dart:io';

import 'package:clipforge/ui/help/help_content.dart';
import 'package:clipforge/ui/help/help_screen.dart';
import 'package:clipforge/ui/help/help_search.dart';
import 'package:clipforge/ui/help/tour_sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ids of the articles that the app opens directly ("?" buttons, popular
/// topics); they must exist.
const kLinkedFromApp = [
  'clean-up-sound',
  'voice-focus',
  'sound-from',
  'lower-music',
  'remove-silences',
  'shape',
  'fit-fill-blur',
  'graphics-card',
  'sound-tracks',
  'separate-sound',
  ...kPopularHelp,
];

/// Topics the help must cover.
const kRequiredTopics = [
  'getting-started', 'importing', 'timeline', 'split', 'undo-and-saving', //
  'music', 'lower-music', 'volume-and-mute', 'clean-up-sound', 'voice-focus',
  'sound-from', 'hear-a-sample', 'remove-silences', 'speed', 'transitions',
  'look', 'fit-fill-blur', 'freeze-frame', 'titles', 'captions',
  'other-languages', 'shape', 'export', 'graphics-card', 'where-files-go',
  'phone-and-computer', 'missing-files', 'storage', 'keyboard-shortcuts',
  'claude-control', 'mac-cant-open', 'windows-smartscreen', 'android-install',
  'crashes', 'voice-separation', 'auto-subtitles', 'assistant',
  'updates', 'connect-claude', 'claude-self-test',
];

/// Bold words in the help that are not labels of this app: the systems'
/// own buttons, keys, and labels the app builds from numbers.
const kNotAppLabels = {
  'Allow from this source', 'Install', 'Install anyway', 'More info', //
  'Run anyway', 'Open Anyway', 'System Settings', 'Privacy & Security',
  'Report…', 'Settings', 'Open', 'Backspace', 'Ctrl+Z', 'Ctrl+Shift+Z',
  'Ctrl+Y', 'Cmd', 'Space', 'S', 'Delete', 'Left', 'Right', 'Shift', 'Home',
  'End', 'Esc', 'Track 1', 'Track 2', 'Remove 5 gaps', '+', '?',
  // Keys (1.7).
  'J', 'K', 'L', 'I', 'O', '-', 'Ctrl+D', 'Ctrl+Shift+C', 'Ctrl+Shift+V',
  'Ctrl+Shift+H', 'Ctrl+E', 'Alt', 'F1', 'Cmd+?', 'Ctrl+N', 'Ctrl+O',
  'Alt+F4', 'Ctrl+Q', 'Cmd+Q',
  // Keys (1.13).
  'Ctrl+Shift+T', 'Ctrl+F', 'Ctrl+Left', 'Ctrl+Right', 'Enter', 'Shift+Enter',
};

void main() {
  final source = File(helpAssetFor('en')).readAsStringSync();
  final library = HelpLibrary.parse(source);

  group('help file', () {
    test('every article parses and has what it needs', () {
      expect(library.articles.length, inInclusiveRange(25, 64));
      for (final a in library.articles) {
        expect(a.title, isNotEmpty, reason: a.id);
        expect(a.keywords, isNotEmpty, reason: a.id);
        expect(a.blocks, isNotEmpty, reason: a.id);
        expect(a.section, isNot('More'), reason: '${a.id} has no section');
        expect(RegExp(r'^[a-z0-9-]+$').hasMatch(a.id), isTrue, reason: a.id);
        // No Markdown left over in the text.
        expect(a.plainBody.contains('**'), isFalse, reason: a.id);
      }
    });

    test('every related link and every link from the app resolves', () {
      expect(library.brokenLinks(), isEmpty);
      for (final a in library.articles) {
        expect(a.related, isNot(contains(a.id)), reason: a.id);
      }
      for (final id in [...kLinkedFromApp, ...kRequiredTopics]) {
        expect(library.byId(id), isNotNull, reason: id);
      }
    });

    test('what is not built yet is marked "Coming later"', () {
      for (final id in ['voice-separation', 'auto-subtitles', 'assistant']) {
        final a = library.byId(id)!;
        expect(a.comingLater, isTrue, reason: id);
        expect(a.plainBody, startsWith('Coming later'), reason: id);
      }
      expect(
          library.articles.where((a) => a.comingLater).map((a) => a.id),
          unorderedEquals(['voice-separation', 'auto-subtitles', 'assistant']));
    });

    test('button names in bold are the ones the app shows', () {
      final ui = StringBuffer();
      for (final f in Directory('lib/ui').listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          ui.write(f.readAsStringSync());
        }
      }
      final code = ui.toString();
      final missing = <String>{};
      for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(source)) {
        final label = m.group(1)!;
        if (kNotAppLabels.contains(label)) continue;
        if (!code.contains(label)) missing.add(label);
      }
      expect(missing, isEmpty,
          reason: 'Bold words in the help that the app does not show. Fix '
              'the help text, or add system labels to kNotAppLabels.');
    });

    test('blocks: paragraphs, bullets, steps, headings, bold', () {
      final blocks = parseHelpBody('''
One line
and its continuation.

- a **bold** bullet
  that goes on
1. first step
2. second
## Small heading
Last.''');
      expect([for (final b in blocks) b.kind], [
        HelpBlockKind.paragraph,
        HelpBlockKind.bullet,
        HelpBlockKind.step,
        HelpBlockKind.step,
        HelpBlockKind.heading,
        HelpBlockKind.paragraph,
      ]);
      expect(blocks[0].text, 'One line and its continuation.');
      expect(blocks[1].text, 'a bold bullet that goes on');
      expect(blocks[1].boldRanges, [(2, 6)]);
      expect(blocks[3].number, 2);
    });

    test('a broken file is reported', () {
      expect(() => HelpLibrary.parse('=== a\ntitle: A\n'),
          throwsA(isA<HelpFormatException>()));
      expect(() => HelpLibrary.parse('=== a\ntitle: A\n\nx\n=== a\ntitle: B\n\ny'),
          throwsA(isA<HelpFormatException>()));
    });
  });

  group('search', () {
    final search = HelpSearch(library);
    String? top(String q) => search.search(q).firstOrNull?.article.id;

    test('finds the right article despite typos', () {
      expect(top('trascirpe'), 'transcribe-speech');
      expect(top('musci'), 'music');
      expect(top('vocie'), 'voice-focus');
      expect(top('vocie focus'), 'voice-focus');
      expect(top('sloww motoin'), 'speed');
      expect(top('smartscren'), 'windows-smartscreen');
      expect(top('subtitels'), 'captions');
      expect(top('grafics card'), 'graphics-card');
      expect(top('trnasition'), 'transitions');
    });

    test('plain words, phrases and questions', () {
      expect(top('clean up sound'), 'clean-up-sound');
      expect(top('noise'), 'clean-up-sound');
      expect(top('slow motion'), 'speed');
      expect(top('where is my video'), 'where-files-go');
      expect(top('srt'), 'captions');
      expect(top('aspect ratio'), 'shape');
      expect(top('how do I undo'), 'undo-and-saving');
      expect(top('Lower music under speech'), 'lower-music');
      expect(top('black bars'), 'fit-fill-blur');
      expect(top('MOVE PROJECT to my computer'), 'phone-and-computer');
    });

    test('as you type: the start of a word is enough', () {
      expect(top('expo'), 'export');
      expect(top('freez'), 'freeze-frame');
      expect(search.search('m').length, 0, reason: 'one letter: no guess');
    });

    test('a word that exists is not read as a typo of another', () {
      final ids = [for (final h in search.search('tour')) h.article.id];
      expect(ids, isNot(contains('export')), reason: '"tour" is not "your"');
    });

    test('nothing found: suggestions', () {
      expect(search.search('xyzzy'), isEmpty);
      expect(search.search('qwrtp'), isEmpty);
      expect(search.search('musiccccc'), isEmpty);
      expect(search.suggestions('musiccccc'), contains('music'));
    });

    test('matched words are reported for highlighting', () {
      final hit = search.search('musci').first;
      expect(hit.matchedWords, contains('music'));
      final snippet = HelpSearch.snippet(hit.article, hit.matchedWords);
      expect(snippet.toLowerCase(), contains('music'));
    });

    test('typo distance counts swapped letters once', () {
      expect(typoDistance('vocie', 'voice'), 1);
      expect(typoDistance('musci', 'music'), 1);
      expect(typoDistance('trascirpe', 'transcribe'), 3);
      expect(typoDistance('abc', 'xyzabc', max: 2), 3);
    });
  });

  test('the tour video is what the sample project says it is', () async {
    final file = File(kTourVideoAsset);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), lessThan(200 * 1024), reason: 'keep it tiny');
    ProcessResult r;
    try {
      r = await Process.run('ffprobe', [
        '-v', 'error', '-print_format', 'json', '-show_streams', //
        '-show_format', file.path,
      ]);
    } on ProcessException {
      markTestSkipped('ffprobe is not installed');
      return;
    }
    final info = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final streams = (info['streams'] as List).cast<Map<String, dynamic>>();
    final video = streams.firstWhere((s) => s['codec_type'] == 'video');
    final audio = streams.where((s) => s['codec_type'] == 'audio').toList();
    expect(video['width'], kTourVideoWidth);
    expect(video['height'], kTourVideoHeight);
    expect(audio.map((s) => s['channels']), [2]);
    final ms = (double.parse(info['format']['duration'] as String) * 1000)
        .round();
    expect((ms - kTourVideoMs).abs(), lessThan(50));
    final clip = tourVideoClip('v', file.path);
    expect(clip.audioStreams, [2]);
    expect(clip.sourceDurationMs, kTourVideoMs);
  });
}
