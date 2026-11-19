// 1.14: publishing notes (model, undo, History names), "good moment"
// markers (they follow their picture), the chapter rules, the kit's text
// file, and what shorts are made of: the "Short" caption look, snapping to
// pauses, and candidate passages (whole sentences only) from a fixture
// transcript.
import 'dart:convert';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/core/publish/chapters.dart';
import 'package:clipforge/core/publish/shorts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Project project({List<Clip>? clips, List<TitleOverlay> titles = const []}) =>
    Project(
      id: 'p',
      name: 'Bread talk',
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
      clips: clips ?? [video('a', source: 600000)],
      titles: titles,
    );

TitleOverlay title(String id, String text, int start, [int length = 3000]) =>
    TitleOverlay(id: id, text: text, startMs: start, endMs: start + length);

TitleOverlay caption(String id, String text, int start, int end) => TitleOverlay(
    id: id, text: text, startMs: start, endMs: end, kind: TitleKind.caption);

List<String> labels(ProjectEditor e) => [for (final s in e.history) s.label];

/// A made-up talk as a transcript would give it: sentences with a time
/// for every word (about 3 words a second), and the pause after each.
const _talk = <(String, String, int)>[
  ('Sam', 'Why does the first loaf always fail?', 1200),
  ('Sam', 'I baked forty of them before one worked.', 300),
  ('Sam', 'The mistake is always the same, and it costs about 2 hours.', 300),
  ('Sam', 'You stop kneading too early.', 1500),
  ('Dana', 'So how do you know when to stop?', 400),
  ('Sam', 'You stretch the dough until you can see light through it.', 300),
  ('Sam', 'Bakers call that the window test.', 300),
  ('Sam', 'If it tears, you keep going for another 3 minutes.', 2000),
  ('Dana', 'And the oven?', 300),
  ('Sam', 'As hot as it goes, with a tray of water on the bottom.', 300),
  ('Sam', 'The steam is what makes the crust.', 300),
  ('Sam', 'Without it the loaf sets before it has risen.', 300),
  ('Sam', 'That is the whole secret, really.', 2500),
  ('Dana', 'What about salt?', 300),
  ('Sam', 'Two percent of the flour, never more.', 300),
  ('Sam', 'My grandmother measured it with the same spoon for fifty years.', 300),
  ('Sam', 'I still have that spoon.', 1800),
];

List<Spoken> talkWords({bool marks = true}) {
  final out = <Spoken>[];
  var at = 500;
  for (final (who, sentence, pause) in _talk) {
    for (final w in sentence.split(' ')) {
      final text = marks ? w : w.replaceAll(RegExp(r'[.?!,]'), '');
      out.add(Spoken(at, at + 280, text, who));
      at += 330;
    }
    at += pause;
  }
  return out;
}

void main() {
  group('publishing notes', () {
    test('an old project has none; nothing is written until there is some',
        () {
      final p = project();
      final json = p.toJson();
      expect(json.containsKey('publishing'), isFalse);
      expect(json.containsKey('markers'), isFalse);
      expect(json['schemaVersion'], 2);
      final back = Project.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.publishing.isEmpty, isTrue);
      expect(back.markers, isEmpty);
    });

    test('round trip through JSON, unknown and odd values tolerated', () {
      const notes = PublishingNotes(
        title: 'Why the first loaf fails',
        description: 'Sam bakes.\nDana asks.',
        hashtags: ['bread', 'baking'],
        chapters: [Chapter(0, 'Start'), Chapter(62000, 'The window test')],
        shortTitle: 'The window test',
      );
      final p = project().copyWith(publishing: notes);
      final back = Project.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.publishing, notes);
      expect(back.publishing.hashtagLine, '#bread #baking');
      expect(back.publishing.tagLine, 'bread, baking');
      expect(back.publishing.titleForShort, 'The window test');
      expect(back.publishing.descriptionForShort, 'Sam bakes.\nDana asks.');
      final odd = Project.fromJson({
        ...project().toJson(),
        'publishing': {
          'title': 'T',
          'hashtags': ['#a', 'b c'],
          'chapters': [
            {'ms': 9000, 'title': 'Later'},
            'nonsense',
            {'ms': 0, 'title': 'First'},
          ],
          'somethingNew': 1,
        },
      });
      expect(odd.publishing.hashtags, ['a', 'b', 'c']);
      expect(odd.publishing.chapters.map((c) => c.ms), [0, 9000]);
    });

    test('hashtags as people type them', () {
      expect(parseHashtags('#bread, baking  #Home-made\n#bread'),
          ['bread', 'baking', 'Homemade']);
      expect(parseHashtags('  '), isEmpty);
      expect(parseHashtags('#לחם хлеб 2026'), ['לחם', 'хлеб', '2026']);
      expect(parseHashtags(List.generate(50, (i) => 't$i').join(' ')).length,
          kMaxHashtags);
    });

    test('every change is one undo step with a name in the History', () {
      final e = ProjectEditor(project());
      e.setPublishingNotes(const PublishingNotes(title: 'A title'));
      e.setPublishingNotes(e.project.publishing.copyWith(description: 'D'));
      e.setPublishingNotes(e.project.publishing.copyWith(hashtags: ['x']));
      e.setPublishingNotes(e.project.publishing.copyWith(
          chapters: const [Chapter(0, 'a'), Chapter(20000, 'b')]));
      e.setPublishingNotes(e.project.publishing.copyWith(shortTitle: 'S'));
      e.setPublishingNotes(
          e.project.publishing.copyWith(title: 'B', description: 'E'));
      e.setPublishingNotes(e.project.publishing.copyWith(chapters: const []));
      expect(labels(e), [
        'Publishing title',
        'Publishing description',
        'Hashtags',
        'Chapters (2)',
        'Short title',
        'Publishing notes',
        'Removed chapters',
      ]);
      // The same notes again: no step.
      e.setPublishingNotes(e.project.publishing);
      expect(e.history.length, 7);
      e.undo();
      expect(e.project.publishing.chapters.length, 2);
      for (var i = 0; i < 6; i++) {
        e.undo();
      }
      expect(e.project.publishing.isEmpty, isTrue);
      e.redo();
      expect(e.project.publishing.title, 'A title');
    });
  });

  group('markers', () {
    test('add, refuse a second one at the same place, remove; named steps',
        () {
      final e = ProjectEditor(project());
      final id = e.addMarker(12300)!;
      expect(e.addMarker(12400), isNull, reason: 'within 0.2 s');
      final second = e.addMarker(5000, label: ' the joke ')!;
      expect(e.project.markers.map((m) => m.ms), [5000, 12300]);
      expect(e.project.markers.first.label, 'the joke');
      expect(e.addMarker(999999999), isNotNull, reason: 'kept inside');
      expect(e.project.markers.last.ms, e.project.durationMs);
      expect(e.removeMarker(id), isTrue);
      expect(e.removeMarker('nope'), isFalse);
      expect(labels(e), [
        'Marked a good moment at 0:12',
        'Marked a good moment at 0:05',
        'Marked a good moment at 10:00',
        'Removed marker at 0:12',
      ]);
      e.undo();
      expect(e.project.markers.length, 3);
      expect(ProjectEditor(project(clips: const [])).addMarker(0), isNull);
      final back = Project.fromJson(
          jsonDecode(jsonEncode(e.project.toJson())) as Map<String, dynamic>);
      expect(back.markers, e.project.markers);
      expect(back.markers.any((m) => m.id == second), isTrue);
    });

    test('a marker follows its picture through cuts, trims, moves and speed',
        () {
      final e = ProjectEditor(project(clips: [
        video('a', source: 20000),
        video('b', source: 20000),
      ]));
      e.addMarker(25000); // 5 s into b
      e.addMarker(3000); // 3 s into a
      // Cut 10 s out of the middle of a.
      e.removeSourceRanges('a', const [(startMs: 5000, endMs: 15000)]);
      expect(e.project.markers.map((m) => m.ms), [3000, 15000]);
      // Trim the start of the first piece.
      e.trimClip(e.project.clips.first.id, inMs: 2000);
      expect(e.project.markers.map((m) => m.ms), [1000, 13000]);
      // b twice as fast: its marker is 2.5 s into it now.
      e.setClipSpeed('b', 2);
      final bStart = e.project.clipStartMs(e.project.clips.indexWhere((c) => c.id == 'b'));
      expect(e.project.markers.last.ms, bStart + 2500);
      // b first.
      e.moveClip(e.project.clips.length - 1, 0);
      expect(e.project.markers.first.ms, 2500);
      // One undo step each: the markers go back with the clips.
      e.undo();
      e.undo();
      expect(e.project.markers.map((m) => m.ms), [1000, 13000]);
    });

    test('a marker whose moment is cut away stays at the cut', () {
      final e = ProjectEditor(project(clips: [video('a', source: 20000)]));
      e.addMarker(8000);
      e.removeSourceRanges('a', const [(startMs: 5000, endMs: 15000)]);
      expect(e.project.durationMs, 10000);
      expect(e.project.markers.single.ms, 5000);
      // Other edits leave it alone.
      e.addTitle(title('t', 'x', 0));
      expect(e.project.markers.single.ms, 5000);
    });
  });

  group('chapters', () {
    test('the rules are in one place', () {
      expect(kChapterRules.firstAtZero, isTrue);
      expect(kChapterRules.minGapMs, 10000);
      expect(kChapterRules.minCount, 3);
    });

    test('from titles: first at 0:00, none closer than 10 s', () {
      final p = project(titles: [
        title('t1', 'Welcome\nto the show', 2000),
        title('t2', 'The dough', 60000),
        title('t3', 'Too close', 65000),
        title('t4', 'The oven.', 185000),
        title('t5', 'Almost at the end', 596000),
        caption('c1', 'Sam: not a chapter', 30000, 32000),
      ]);
      final built = buildChapters(p);
      expect(built.source, ChapterSource.titles);
      expect(formatChapters(built.chapters),
          '0:00 Welcome\n1:00 The dough\n3:05 The oven');
      expect(chapterProblems(built.chapters, p.durationMs), isEmpty);
    });

    test('a first title later than 10 s gets a Start chapter in front', () {
      final built = buildChapters(project(titles: [
        title('t1', 'Part one', 30000),
        title('t2', 'Part two', 90000),
      ]));
      expect(formatChapters(built.chapters),
          '0:00 Start\n0:30 Part one\n1:30 Part two');
    });

    test('without titles: from the captions, at speaker changes and pauses',
        () {
      final p = project(clips: [
        video('a', source: 240000)
      ], titles: [
        caption('c1', 'Sam: Why does the first loaf always fail?', 500, 3000),
        caption('c2', 'I baked forty of them.', 3100, 5000),
        caption('c3', 'Dana: So how do you know when to stop?', 40000, 43000),
        caption('c4', 'Sam: You stretch the dough.', 43200, 46000),
        caption('c5', 'After a long pause, the oven.', 120000, 123000),
        caption('c6', 'Dana: And the salt?', 200000, 202000),
      ]);
      final built = buildChapters(p);
      expect(built.source, ChapterSource.captions);
      expect(built.chapters.first.ms, 0);
      expect(built.chapters.first.title, startsWith('Sam: Why does the first loaf'));
      expect(built.chapters.map((c) => c.ms), [0, 40000, 120000, 200000],
          reason: '43.2 s is closer than the automatic gap (240 s / 12 = 20 s)');
      expect(chapterProblems(built.chapters, p.durationMs), isEmpty);
    });

    test('without any text: from who speaks when', () {
      final built = buildChapters(project(clips: [video('a', source: 120000)]),
          turns: const [
            (name: 'Sam', startMs: 300, endMs: 30000),
            (name: 'Dana', startMs: 31000, endMs: 33000),
            (name: 'Sam', startMs: 60000, endMs: 100000),
          ]);
      expect(built.source, ChapterSource.speakers);
      expect(formatChapters(built.chapters),
          '0:00 Part 1 - Sam\n0:31 Part 2 - Dana\n1:00 Part 3 - Sam');
      expect(buildChapters(project()).source, ChapterSource.none);
    });

    test('never more than twelve automatic chapters', () {
      final p = project(clips: [
        video('a', source: 2400000)
      ], titles: [
        for (var i = 0; i < 300; i++)
          caption('c$i', '${i.isEven ? 'Sam' : 'Dana'}: line $i', i * 8000,
              i * 8000 + 2000),
      ]);
      final built = buildChapters(p);
      expect(built.chapters.length, lessThanOrEqualTo(12));
      expect(built.chapters.length, greaterThan(8));
    });

    test('typed lists are read back; problems are named', () {
      final typed = parseChapters('0:00 Start\n1:05 - The dough\n'
          'no time here\n(1:02:03) The end');
      expect(typed, const [
        Chapter(0, 'Start'),
        Chapter(65000, 'The dough'),
        Chapter(3723000, 'The end'),
      ]);
      expect(chapterTime(3723000), '1:02:03');
      expect(parseChapterTime('75'), 75000);
      expect(parseChapterTime('a:b'), isNull);
      final problems = chapterProblems(const [
        Chapter(4000, 'Late start'),
        Chapter(9000, 'Too soon'),
      ], 600000);
      expect(problems, [
        'The first chapter must start at 0:00.',
        'Sites show chapters only when there are at least 3.',
        '"0:04 Late start" is shorter than 10 seconds.',
      ]);
      expect(chapterProblems(const [], 1000), isEmpty);
    });
  });

  group('the text file of a kit', () {
    test('holds everything to paste, with a section per file', () {
      final p = project().copyWith(
        publishing: const PublishingNotes(
          title: 'Why the first loaf fails',
          description: 'Sam explains the window test.',
          hashtags: ['bread', 'baking'],
          chapters: [Chapter(0, 'Start'), Chapter(62000, 'The window test')],
          shortTitle: 'The window test',
        ),
        audio: [
          audio('m').copyWith(
              credit: const MusicCredit(
                  title: 'Morning Flour',
                  creator: 'Lina Vale',
                  licence: 'by',
                  licenceVersion: '4.0')),
        ],
      );
      final text = kitText(p, sections: const [
        (heading: 'YouTube', shortForm: false, file: 'Bread talk - YouTube.mp4'),
        (
          heading: 'Shorts / Reels / TikTok',
          shortForm: true,
          file: 'Bread talk - Short 9x16.mp4'
        ),
      ]);
      expect(text, startsWith('TITLE\nWhy the first loaf fails\n\nDESCRIPTION\n'));
      expect(text, contains('HASHTAGS\n#bread #baking\n'));
      expect(text, contains('TAGS\nbread, baking\n'));
      expect(text, contains('CHAPTERS\n0:00 Start\n1:02 The window test\n'));
      expect(text, contains('MUSIC CREDITS\n'));
      expect(text, contains('Morning Flour'));
      expect(text, contains('SHORT TITLE (SHORTS, REELS, TIKTOK)\nThe window test'));
      expect(text, contains('YOUTUBE\nFile: Bread talk - YouTube.mp4\n'
          'Title: Why the first loaf fails\n'));
      expect(
          text,
          contains('SHORTS / REELS / TIKTOK\nFile: Bread talk - Short 9x16.mp4\n'
              'Title: The window test\n'));
      // The short's section has no chapters; the long one's has.
      final short = text.substring(text.indexOf('SHORTS / REELS / TIKTOK'));
      expect(short, isNot(contains('0:00 Start')));
      expect(kitText(p, lineEnd: '\r\n'), contains('TITLE\r\nWhy'));
      // Without notes: the project's name is the title.
      expect(kitText(project()), 'TITLE\nBread talk\n');
      expect(titleAndDescription(p),
          startsWith('Why the first loaf fails\n\nSam explains the window test.\n\n0:00 Start'));
      expect(titleAndDescription(p, shortForm: true), startsWith('The window test\n\n'));
      expect(titleAndDescription(project()), 'Bread talk');
    });
  });

  group('shorts', () {
    test('the Short look is defined once: bigger, lower middle, outlined', () {
      final c = shortCaptionStyle(caption('c', 'x', 0, 1000));
      expect(c.fontSize, greaterThan(CaptionDefaults.fontSize));
      expect(c.y, inInclusiveRange(0.6, 0.8));
      expect(c.x, 0.5);
      expect(c.outline, isTrue);
      expect(c.background, isFalse);
      final t = shortTopTitle('t', ' Why the first loaf fails ', 30000);
      expect(t.y, lessThan(0.2));
      expect(t.startMs, 0);
      expect(t.endMs, 30000);
      expect(t.text, 'Why the first loaf fails');
      expect(firstSentence('Sam says: Why does it fail? Because of you.'),
          'Sam says: Why does it fail?');
      expect(firstSentence('word ' * 40).length, lessThanOrEqualTo(61));
    });

    test('buildShort: only that part, upright 1080p, blurred, Short '
        'captions of at most two lines, a title at the top', () {
      var n = 0;
      final e = ProjectEditor(
          project(clips: [
            video('a', source: 120000)
          ], titles: [
            caption('c1', 'before the part', 2000, 4000),
            caption('c2', 'Sam: Why does the first loaf always fail?', 21000, 24000),
            caption(
                'c3',
                'The mistake is always the same and it costs about two '
                    'hours of your Sunday morning every single time',
                25000,
                33000),
          ]),
          newId: () => 'n${n++}');
      final built = buildShort(e,
          fromMs: 20000,
          toMs: 50000,
          blur: true,
          shortCaptions: true,
          title: 'Why the first loaf fails',
          newId: () => 'n${n++}');
      expect(built.ok, isTrue);
      final p = e.project;
      expect(p.durationMs, 30000);
      expect(p.aspect, CanvasAspect.portrait9x16);
      expect(p.canvasSize, (width: 1080, height: 1920));
      expect(p.clips.single.fit, FitMode.blur);
      expect(built.blurred, 1);
      expect(built.captionsKept, 2);
      final captions = [
        for (final t in p.titles)
          if (t.kind == TitleKind.caption) t,
      ]..sort((a, b) => a.startMs.compareTo(b.startMs));
      expect(captions.length, greaterThan(2), reason: 'the long one was divided');
      expect(built.captionsAfter, captions.length);
      for (final c in captions) {
        expect(c.text.split('\n').length, lessThanOrEqualTo(2), reason: c.text);
        expect(c.fontSize, ShortLook.captionFontSize);
        expect(
            layoutTitleLines(c, canvasWidth: 1080, canvasHeight: 1920).length,
            lessThanOrEqualTo(2),
            reason: c.text);
      }
      // In order, without overlap, and the words are all still there.
      for (var i = 1; i < captions.length; i++) {
        expect(captions[i].startMs, greaterThanOrEqualTo(captions[i - 1].endMs));
      }
      expect(captions.map((c) => c.text.replaceAll('\n', ' ')).join(' '),
          contains('costs about two hours of your Sunday morning every single time'));
      expect(captions.first.startMs, 1000);
      final top = p.titles.singleWhere((t) => t.kind == TitleKind.title);
      expect(top.text, 'Why the first loaf fails');
      expect((top.startMs, top.endMs), (0, 30000));
      // Outside the video: nothing is made.
      expect(
          buildShort(ProjectEditor(project(clips: const [])),
                  fromMs: 0, toMs: 5000, newId: () => 'x')
              .ok,
          isFalse);
    });

    test('snapping moves outward to pauses and never into a word', () {
      const pauses = [
        (startMs: 0, endMs: 500),
        (startMs: 9000, endMs: 10200),
        (startMs: 30500, endMs: 31400),
        (startMs: 58000, endMs: 60000),
      ];
      var r = snapShortRange(12000, 28000, pauses: pauses, totalMs: 60000);
      expect((r.fromMs, r.toMs), (10050, 30650));
      expect(r.movedStart && r.movedEnd, isTrue);
      // Already in a pause: stays.
      r = snapShortRange(9500, 31000, pauses: pauses, totalMs: 60000);
      expect((r.fromMs, r.toMs, r.movedStart, r.movedEnd), (9500, 31000, false, false));
      // No pause near enough: only the word guard applies.
      r = snapShortRange(20000, 22000,
          pauses: pauses,
          words: const [
            (startMs: 19800, endMs: 20300),
            (startMs: 21900, endMs: 22400),
          ],
          totalMs: 60000,
          maxMoveMs: 1000);
      expect((r.fromMs, r.toMs), (19800, 22400));
      // Never past the ends of the video.
      r = snapShortRange(-50, 99999, pauses: pauses, totalMs: 60000);
      expect((r.fromMs, r.toMs), (0, 60000));
      expect(pausesBetween(const [
        (startMs: 1000, endMs: 5000),
        (startMs: 5100, endMs: 9000),
        (startMs: 4000, endMs: 6000),
      ], 10000), const [
        (startMs: 0, endMs: 1000),
        (startMs: 9000, endMs: 10000),
      ]);
      expect(markerRange(10000, 60000), (startMs: 0, endMs: 35000));
      expect(markerRange(50000, 60000), (startMs: 30000, endMs: 60000));
    });

    test('mid-sentence starts and ends are noticed', () {
      final words = talkWords();
      // The second sentence starts right after the first: fine.
      final second = words.indexWhere((w) => w.text == 'I');
      expect(startsMidSentence(words, words[second].startMs - 20), isFalse);
      // Two words into it: mid-sentence.
      expect(startsMidSentence(words, words[second + 2].startMs - 20), isTrue);
      expect(endsMidSentence(words, words[second + 2].endMs + 10), isTrue);
      final end = words.indexWhere((w) => w.text == 'worked.');
      expect(endsMidSentence(words, words[end].endMs + 10), isFalse);
      expect(startsMidSentence(words, 0), isFalse);
    });

    test('candidates from the fixture transcript: whole sentences only, '
        'within the length window, with signals', () {
      final words = talkWords();
      final all = shortCandidates(words, minMs: 8000, maxMs: 25000);
      expect(all, isNotEmpty);
      final starts = <int>{}, ends = <int>{};
      var at = 0;
      // Where sentences start and end in the fixture.
      for (var i = 0; i < words.length; i++) {
        if (i == 0 || RegExp(r'[.?!]$').hasMatch(words[i - 1].text)) {
          starts.add(words[i].startMs);
        }
        if (RegExp(r'[.?!]$').hasMatch(words[i].text)) ends.add(words[i].endMs);
        at = words[i].endMs;
      }
      expect(at, greaterThan(40000));
      for (final c in all) {
        expect(starts, contains(c.startMs), reason: 'starts a sentence: ${c.text}');
        expect(ends, contains(c.endMs), reason: 'ends a sentence: ${c.text}');
        expect(c.durationMs, inInclusiveRange(8000, 25000));
        expect(c.completeSentences, isTrue);
        expect(RegExp(r'[.?!]$').hasMatch(c.text), isTrue);
        expect(c.text[0], c.text[0].toUpperCase());
      }
      final first = all.first;
      expect(first.text, startsWith('Why does the first loaf always fail?'));
      expect(first.startsWithQuestion, isTrue);
      expect(first.hasNumbers, isTrue, reason: '"forty", "2 hours"');
      expect(first.afterPause, isTrue);
      expect(first.speakers, ['Sam']);
      expect(first.text, endsWith('You stop kneading too early.'),
          reason: 'runs to the pause before Dana, not into her question');
      expect(first.beforePause, isTrue);
      // Dana's question with Sam's answer is offered as one passage.
      final exchange = all.firstWhere((c) => c.text.startsWith('So how do you know'));
      expect(exchange.speakers, ['Dana', 'Sam']);
      expect(exchange.startsWithQuestion, isTrue);
      // A window nothing fits in: nothing is made up.
      expect(shortCandidates(words, minMs: 200000, maxMs: 300000), isEmpty);
      expect(shortCandidates(const []), isEmpty);
      // Text without sentence marks: passages between pauses, and it says so.
      final plain = shortCandidates(talkWords(marks: false), minMs: 8000, maxMs: 25000);
      expect(plain, isNotEmpty);
      expect(plain.every((c) => !c.completeSentences), isTrue);
      expect(plain.every((c) => c.afterPause), isTrue);
    });
  });
}
