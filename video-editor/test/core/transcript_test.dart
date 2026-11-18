// 1.11 speech-to-text, the pure core: transcripts, mapping source time to
// timeline time through cuts / speed / Remove silences / linked voices,
// captions (English, Russian, right-to-left Hebrew), filler words per
// language, and "keep one part" (shorts).
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/core/storage/file_project_store.dart';
import 'package:clipforge/core/transcript/captions.dart';
import 'package:clipforge/core/transcript/fillers.dart';
import 'package:clipforge/core/transcript/speech_edits.dart';
import 'package:clipforge/core/transcript/transcript.dart';
import 'package:clipforge/core/transcript/transcript_store.dart';
import 'package:clipforge/core/transcript/transcript_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ProjectEditor ed(Project p) {
  var n = 0;
  var now = t0;
  return ProjectEditor(p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'id${++n}');
}

/// A transcript of [path]: [text] spoken from [startMs], each word
/// [wordMs] long with [gapMs] between words; a new phrase after "." etc.
Transcript spoken(String path, String text,
    {int startMs = 0,
    int wordMs = 300,
    int gapMs = 100,
    String language = 'en',
    WordTiming timing = WordTiming.measured,
    Map<int, int> pauseBefore = const {}}) {
  final words = <TranscriptWord>[];
  var t = startMs;
  var i = 0;
  for (final w in text.split(' ')) {
    t += pauseBefore[i] ?? 0;
    words.add(TranscriptWord(w, t, t + wordMs));
    t += wordMs + gapMs;
    i++;
  }
  return Transcript(
    sourcePath: path,
    audioTrack: 0,
    language: language,
    requestedLanguage: language,
    model: 'base',
    backend: 'test',
    wordTiming: timing,
    durationMs: t,
    createdAt: t0,
    segments: segmentsFromWords(words),
  );
}

TranscriptLookup lookupOf(List<Transcript> all) => (path, track) {
      for (final t in all) {
        if (t.sourcePath == path && t.audioTrack == track) return t;
      }
      return null;
    };

String said(List<TimelineWord> words) => words.map((w) => w.text).join(' ');

const english = 'Welcome back to the show. Today we talk about bread. '
    'First you need flour, water, salt and a lot of patience. Then you wait.';
const russian = 'Привет, друзья! Сегодня мы говорим о хлебе. '
    'Сначала нужна мука, вода, соль и много терпения. Потом вы ждёте.';
const hebrew = 'שלום חברים, ברוכים הבאים! היום נדבר על לחם. '
    'קודם צריך קמח, מים, מלח והרבה סבלנות. אחר כך מחכים 20 דקות.';

void main() {
  group('transcript', () {
    test('estimated words share the phrase by length, in order', () {
      final w = estimateWords('I am extraordinarily happy.', 1000, 3000);
      expect(w.map((x) => x.text), ['I', 'am', 'extraordinarily', 'happy.']);
      expect(w.first.startMs, 1000);
      expect(w.last.endMs, 3000);
      for (var i = 1; i < w.length; i++) {
        expect(w[i].startMs, w[i - 1].endMs);
      }
      expect(w[2].endMs - w[2].startMs, greaterThan(4 * (w[0].endMs - w[0].startMs)));
    });

    test('tidy: markers dropped, words estimated only where missing', () {
      final r = tidySegments([
        RawSegment(5000, 6000, ' second one. '),
        RawSegment(0, 2000, '[MUSIC]'),
        RawSegment(2000, 4000, 'Hello there', [
          const TranscriptWord(' Hello', 2000, 2500),
          const TranscriptWord('there', 2600, 3000),
          const TranscriptWord('[_TT_150]', 3000, 3000),
        ]),
        RawSegment(8000, 7000, '(music) ♪♪'),
      ]);
      expect(r.estimated, isTrue);
      expect(r.segments.map((s) => s.text), ['Hello there', 'second one.']);
      expect(r.segments.first.words.first.text, 'Hello');
    });

    test('JSON round trip; a newer format is refused', () {
      final t = spoken('/media/a.mp4', russian, language: 'ru');
      final back = Transcript.fromJson(
          jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      expect(back.text, t.text);
      expect(back.words.length, t.words.length);
      expect(back.words[3].startMs, t.words[3].startMs);
      expect(back.language, 'ru');
      expect(back.wordTiming, WordTiming.measured);
      expect(() => Transcript.fromJson({...t.toJson(), 'version': 99}),
          throwsFormatException);
    });

    test('language names and codes', () {
      expect(languageCode('Russian'), 'ru');
      expect(languageCode('iw'), 'he');
      expect(languageCode('auto'), '');
      expect(languageName('he'), 'Hebrew');
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cf_transcripts_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('one file per source, found again by content after a move', () async {
      final media = File('${dir.path}/talk.mp4')..writeAsBytesSync(List.filled(5000, 7));
      final store = TranscriptStore.ofProject('${dir.path}/proj');
      expect(await store.load(media.path, 0), isNull);
      final saved = await store.save(spoken(media.path, english));
      expect(saved.fingerprint, isNotEmpty);
      expect(Directory('${dir.path}/proj/transcripts').listSync().length, 1);
      expect((await store.load(media.path, 0))!.text, saved.text);
      // Another audio stream of the same file is another transcript.
      expect(await store.load(media.path, 1), isNull);
      // Moved: same content, new path.
      final moved = media.renameSync('${dir.path}/moved.mp4');
      expect((await store.load(moved.path, 0))!.text, saved.text);
      // Saved again: replaced, not added.
      await store.save(spoken(moved.path, 'Short.'));
      expect((await store.list()).single.text, 'Short.');
      // The file is gone: found by the path it had.
      moved.deleteSync();
      expect((await store.load(moved.path, 0))!.text, 'Short.');
    });

    test('duplicating a project takes its transcripts along', () async {
      final media = File('${dir.path}/talk.mp4')..writeAsBytesSync(List.filled(900, 3));
      final projects = FileProjectStore('${dir.path}/projects');
      final p = await projects.create('Talk');
      await TranscriptStore.ofProject('${dir.path}/projects/${p.id}')
          .save(spoken(media.path, english));
      final copy = await projects.duplicate(p.id);
      final t = await TranscriptStore.ofProject('${dir.path}/projects/${copy.id}')
          .load(media.path, 0);
      expect(t!.text, english);
    });
  });

  group('timeline mapping', () {
    // One word every 400 ms: word k starts at 400k in the file.
    final t = spoken('/media/a.mp4',
        List.generate(20, (i) => 'w$i').join(' '));
    final lookup = lookupOf([t]);

    test('untouched clip: source time is timeline time', () {
      final p = project(clips: [video('a')]);
      final w = timelineWords(p, lookup);
      expect(w.length, 20);
      expect([w[5].startMs, w[5].endMs], [2000, 2300]);
      expect(w[5].clipStartMs, 2000);
    });

    test('trim: words outside are gone, the rest moves up', () {
      final p = project(clips: [video('a', inMs: 2000, outMs: 4000)]);
      final w = timelineWords(p, lookup);
      expect(said(w), 'w5 w6 w7 w8 w9');
      expect(w.first.startMs, 0);
      expect(w.last.startMs, 1600);
    });

    test('a clip before it and speed 2', () {
      final e = ed(project(clips: [video('x', source: 3000), video('a')]));
      e.setClipSpeed('a', 2);
      final w = timelineWords(e.project, lookupOf([t]));
      // w5 is at 2000 ms of the file: 3000 + 2000 / 2.
      expect([w[5].startMs, w[5].endMs], [4000, 4150]);
      expect(w[5].clipStartMs, 2000);
    });

    test('split, reorder and remove silences keep every word on its picture',
        () {
      final e = ed(project(clips: [video('a')]));
      e.splitAt(4000);
      e.moveClip(1, 0);
      var w = timelineWords(e.project, lookup);
      expect(w.first.text, 'w10');
      expect(w.first.startMs, 0);
      expect(w.firstWhere((x) => x.text == 'w0').startMs, 6000);
      // Cut 800..2000 of the file out (w2, w3, w4).
      e.removeSourceRanges('a', [(startMs: 800, endMs: 2000)]);
      w = timelineWords(e.project, lookup);
      expect(w.any((x) => ['w2', 'w3', 'w4'].contains(x.text)), isFalse);
      expect(w.firstWhere((x) => x.text == 'w5').startMs, 6000 + 800);
      // Source time is unchanged by any of it.
      expect(w.firstWhere((x) => x.text == 'w5').clipStartMs, 2000);
      e.undo();
      expect(timelineWords(e.project, lookup).length, 20);
    });

    test('a range of the timeline', () {
      final p = project(clips: [video('a')]);
      expect(said(timelineWords(p, lookup, fromMs: 1000, toMs: 2000)), 'w3 w4');
    });

    test('a clip without a transcript, and a photo, say nothing', () {
      final p = project(clips: [photo('ph'), video('b'), video('a')]);
      final w = timelineWords(p, lookup);
      expect(w.length, 20);
      expect(w.first.startMs, 3000 + 10000);
      final cover = transcriptCoverage(p, lookup);
      expect(cover.sources.map((s) => s.path), ['/media/b.mp4', '/media/a.mp4']);
      expect(cover.missing.single.path, '/media/b.mp4');
    });

    test('linked voices are read instead of the camera, one per speaker', () {
      final e = ed(project(clips: [video('a')]));
      AudioClip mic(String name) => AudioClip(
          id: 'tmp',
          path: '/media/$name.m4a',
          sourceDurationMs: 12000,
          startMs: 0,
          inMs: 0,
          outMs: 12000);
      e.addVoice(mic('anna'), clipId: 'a', offsetMs: 500, trackName: 'Anna');
      e.addVoice(mic('ben'), clipId: 'a', offsetMs: -1000, trackName: 'Ben');
      final p = e.project;
      final sources = speechSourcesOf(p, p.clips.single);
      expect(sources.map((s) => s.speaker), ['Anna', 'Ben']);
      expect(sources.map((s) => s.offsetMs), [500, -1000]);
      final anna = spoken('/media/anna.m4a', 'hello from anna', startMs: 1500);
      final ben = spoken('/media/ben.m4a', 'and ben', startMs: 2000);
      final camera = spoken('/media/a.mp4', 'muffled camera sound');
      final w = timelineWords(p, lookupOf([anna, ben, camera]));
      expect(w.any((x) => x.text == 'muffled'), isFalse);
      // voice file time = clip time + offset.
      final hello = w.firstWhere((x) => x.text == 'hello');
      expect([hello.startMs, hello.speaker], [1000, 'Anna']);
      final and = w.firstWhere((x) => x.text == 'and');
      expect([and.startMs, and.speaker], [3000, 'Ben']);
      // After a cut the voices still follow.
      e.removeSourceRanges('a', [(startMs: 0, endMs: 900)]);
      final w2 = timelineWords(e.project, lookupOf([anna, ben]));
      expect(w2.firstWhere((x) => x.text == 'hello').startMs, 100);
      final segs = timelineSegments(w2);
      expect(segs.map((s) => '${s.speaker}: ${s.text}'),
          ['Anna: hello from anna', 'Ben: and ben']);
    });

    test('segments break where a cut removed words', () {
      final e = ed(project(clips: [video('a')]));
      final talk = spoken('/media/a.mp4', 'one two three four five six seven eight.');
      e.removeSourceRanges('a', [(startMs: 1200, endMs: 2400)]);
      final segs = timelineSegments(timelineWords(e.project, lookupOf([talk])));
      expect(segs.map((s) => s.text), ['one two three', 'seven eight.']);
    });

    test('find a phrase: case, punctuation and ё do not matter', () {
      final p = project(clips: [video('a')]);
      final w = timelineWords(p, lookupOf([spoken('/media/a.mp4', russian, language: 'ru')]));
      final hits = findPhrase(w, 'МНОГО терпения');
      expect(hits.single.startMs, w.firstWhere((x) => x.text == 'много').startMs);
      expect(findPhrase(w, 'ждете').length, 1);
      expect(findPhrase(w, 'терпен', prefix: true).length, 1);
      expect(findPhrase(w, 'пицца'), isEmpty);
    });
  });

  group('captions', () {
    List<TimelineWord> wordsOf(String text, {String language = 'en'}) =>
        timelineWords(project(clips: [video('a', source: 60000)]),
            lookupOf([spoken('/media/a.mp4', text, language: language)]));

    void expectWellFormed(List<CaptionCue> cues, CaptionOptions o) {
      expect(cues, isNotEmpty);
      for (var i = 0; i < cues.length; i++) {
        final lines = cues[i].text.split('\n');
        expect(lines.length, lessThanOrEqualTo(o.lines), reason: cues[i].text);
        for (final l in lines) {
          expect(l.length, lessThanOrEqualTo(o.lineChars), reason: l);
          expect(l.trim(), l);
        }
        expect(cues[i].endMs - cues[i].startMs, lessThanOrEqualTo(o.maxMs + o.lingerMs));
        if (i > 0) expect(cues[i].startMs, greaterThanOrEqualTo(cues[i - 1].endMs));
      }
    }

    test('English: sentences, two balanced lines, nothing lost', () {
      const o = CaptionOptions();
      final words = wordsOf(english);
      final cues = buildCaptions(words, options: o);
      expectWellFormed(cues, o);
      expect(cues.map((c) => c.text.replaceAll('\n', ' ')).join(' '), english);
      expect(cues.first.text, 'Welcome back to the show.');
      expect(cues[1].text, 'Today we talk about bread.');
      // The long sentence is on two lines, broken after a comma.
      final long = cues.firstWhere((c) => c.text.contains('\n'));
      expect(long.text.split('\n').first, endsWith(','));
    });

    test('Russian (Cyrillic) keeps its words and lengths', () {
      const o = CaptionOptions(maxLineChars: 32);
      final cues = buildCaptions(wordsOf(russian, language: 'ru'), options: o);
      expectWellFormed(cues, o);
      expect(cues.map((c) => c.text.replaceAll('\n', ' ')).join(' '), russian);
      expect(cues.first.text, 'Привет, друзья!');
    });

    test('Hebrew stays in reading order; the drawing side marks direction',
        () {
      const o = CaptionOptions(maxLineChars: 32);
      final cues = buildCaptions(wordsOf(hebrew, language: 'he'), options: o);
      expectWellFormed(cues, o);
      // Logical order is untouched (nothing reversed).
      expect(cues.map((c) => c.text.replaceAll('\n', ' ')).join(' '), hebrew);
      for (final c in cues) {
        for (final line in c.text.split('\n')) {
          expect(isRtlLine(line), isTrue, reason: line);
          final drawn = bidiLine(line);
          expect(drawn.runes.first, 0x200F);
          expect(drawn.runes.last, 0x200F);
          expect(drawn.replaceAll('‏', ''), line);
          // Idempotent, and no wider.
          expect(bidiLine(drawn), drawn);
          expect(estimateTextWidth(drawn, fontPx: 40, bold: true),
              estimateTextWidth(line, fontPx: 40, bold: true));
        }
      }
      // A line that starts with a number but is Hebrew is still RTL.
      expect(isRtlLine('20 דקות.'), isTrue);
      expect(isRtlLine('Hello שלום'), isFalse);
      expect(bidiLine('Привет, мир.'), 'Привет, мир.');
      expect(isRtlLine('2024.'), isFalse);
    });

    test('the layout keeps the chosen lines for Hebrew and Russian captions',
        () {
      for (final text in [hebrew, russian]) {
        final p = project(clips: [video('a', source: 60000)]);
        final template = captionTemplate(p);
        final cues = buildCaptions(wordsOf(text),
            options: const CaptionOptions(), lineFits: captionLineFits(p, template));
        for (final t in captionTitles(cues, template, newId: () => 'c')) {
          final lines = layoutTitleLines(t, canvasWidth: 1920, canvasHeight: 1080);
          expect(lines, t.text.split('\n'));
        }
      }
    });

    test('a narrow (9:16) picture gets shorter lines that still fit', () {
      final p = project(
          clips: [video('a', source: 60000)], aspect: CanvasAspect.portrait9x16);
      final template = captionTemplate(p);
      final cues = buildCaptions(wordsOf(english),
          options: const CaptionOptions(), lineFits: captionLineFits(p, template));
      final size = p.canvasSize;
      for (final t in captionTitles(cues, template, newId: () => 'c')) {
        expect(
            layoutTitleLines(t, canvasWidth: size.width, canvasHeight: size.height),
            t.text.split('\n'));
        expect(t.text.split('\n').length, lessThanOrEqualTo(2));
      }
    });

    test('pauses, minimum and maximum time, one line only', () {
      final talk = spoken('/media/a.mp4', 'Yes. And then we went all the way home',
          pauseBefore: {1: 3000});
      final words = timelineWords(
          project(clips: [video('a', source: 60000)]), lookupOf([talk]));
      final cues = buildCaptions(words,
          options: const CaptionOptions(maxLines: 1, maxLineChars: 20, minMs: 1200));
      expect(cues.first.text, 'Yes.');
      // 300 ms word, kept on screen for the minimum.
      expect(cues.first.endMs - cues.first.startMs, 1200);
      expect(cues.every((c) => !c.text.contains('\n')), isTrue);
      expect(cues.length, greaterThanOrEqualTo(3));
      // Slow speech: a caption never stays longer than the maximum.
      final slow = timelineWords(
          project(clips: [video('a', source: 60000)]),
          lookupOf([spoken('/media/a.mp4', 'a b c d e f g h', wordMs: 900, gapMs: 400)]));
      for (final c in buildCaptions(slow, options: const CaptionOptions(maxMs: 4000))) {
        expect(c.endMs - c.startMs, lessThanOrEqualTo(4200));
      }
    });

    test('hesitation sounds can be left out; current caption style is used',
        () {
      final words = wordsOf('So um we start uh now.');
      final cues = buildCaptions(words, skip: isFillerSound(fillersFor('en')));
      expect(cues.single.text, 'So we start now.');
      final styled = project(clips: [
        video('a')
      ], titles: [
        const TitleOverlay(
            id: 'c1',
            text: 'old',
            startMs: 0,
            endMs: 1000,
            kind: TitleKind.caption,
            y: 0.2,
            colorArgb: 0xFFFFEE00,
            font: TitleFont.modern),
      ]);
      final t = captionTitles(cues, captionTemplate(styled), newId: () => 'n').single;
      expect([t.y, t.colorArgb, t.font, t.kind],
          [0.2, 0xFFFFEE00, TitleFont.modern, TitleKind.caption]);
      final plain = captionTitles(cues, captionTemplate(project(clips: [video('a')])),
              newId: () => 'n')
          .single;
      expect(plain.y, CaptionDefaults.y);
      expect(plain.background, isTrue);
    });

    test('added in one undo step, replacing the old ones when asked', () {
      final e = ed(project(clips: [
        video('a', source: 60000)
      ], titles: [
        const TitleOverlay(
            id: 'old', text: 'old', startMs: 0, endMs: 1000, kind: TitleKind.caption),
      ]));
      final cues = buildCaptions(wordsOf(english));
      final titles = captionTitles(cues, captionTemplate(e.project), newId: () => 'x');
      addSpeechCaptions(e.editorOrSelf, titles,
          replaceIds: [for (final t in captionsInRange(e.project)) t.id]);
      expect(e.project.titles.length, cues.length);
      expect(e.project.titles.any((t) => t.id == 'old'), isFalse);
      expect(e.history.last.label, 'Added ${cues.length} captions from speech');
      e.undo();
      expect(e.project.titles.single.id, 'old');
    });
  });

  group('filler words', () {
    List<TimelineWord> wordsOf(String text) => timelineWords(
        project(clips: [video('a', source: 60000)]),
        lookupOf([spoken('/media/a.mp4', text)]));

    test('English sounds; drawn-out and punctuated forms; words unticked', () {
      final hits = findFillers(
          wordsOf('So, um, I think, uhh, it is like really good. Er, yes ummm.'),
          fillersFor('en'));
      expect(hits.map((h) => '${h.entry}:${h.isSound}'),
          ['um:true', 'uh:true', 'like:false', 'er:true', 'um:true']);
      final groups = groupFillers(hits);
      expect(groups.first.entry, 'um');
      expect(groups.first.count, 2);
      expect(groups.first.totalMs, greaterThan(400));
      expect(groups.last.isSound, isFalse);
    });

    test('Russian: э-э, ну, как бы, типа', () {
      final hits = findFillers(
          wordsOf('Ну, э-э, это как бы хлеб, типа вкусный. Как дела? Эээ да.'),
          fillersFor('ru'));
      expect(hits.map((h) => h.entry), ['ну', 'э-э', 'как бы', 'типа', 'э-э']);
      expect(hits[2].words.length, 2);
      // "Как" on its own is not a filler.
      expect(hits.any((h) => h.text.startsWith('Как дела')), isFalse);
      expect(hits.where((h) => h.isSound).map((h) => h.text), ['э-э,', 'Эээ']);
    });

    test('Hebrew: אה, אממ, כאילו', () {
      final hits = findFillers(
          wordsOf('אז אה, אני חושב אממ שזה כאילו טוב אם תרצה.'), fillersFor('he'));
      expect(hits.map((h) => h.entry), ['אז', 'אה', 'אממ', 'כאילו']);
      expect(hits.where((h) => h.isSound).length, 2);
      // "אם" (if) is a word, not "אממ".
      expect(hits.any((h) => h.text.contains('אם')), isFalse);
    });

    test('unknown language: every language\'s sounds, no words', () {
      final hits = findFillers(wordsOf('um ну э-э like אה'), fillersFor(''));
      expect(hits.map((h) => h.text), ['um', 'э-э', 'אה']);
    });

    test('a list of your own', () {
      const mine = FillerList(language: 'en', sounds: ['basically']);
      expect(findFillers(wordsOf('It is basically um done'), mine).single.entry,
          'basically');
      final back = FillerList.fromJson(
          jsonDecode(jsonEncode(mine.toJson())) as Map<String, dynamic>);
      expect(back.sounds, ['basically']);
    });

    test('a cut leaves the neighbours alone, with a little air', () {
      // words: I(0-300) um(400-700) agree(800-1100)
      final hit = findFillers(wordsOf('I um agree'), fillersFor('en')).single;
      expect(hit.cutStartMs, 300 + 40);
      expect(hit.cutEndMs, 800 - 40);
      // A long pause around it: only 150 ms beyond the sound goes.
      final lonely = timelineWords(
          project(clips: [video('a', source: 60000)]),
          lookupOf([
            spoken('/media/a.mp4', 'I um agree', pauseBefore: {1: 2000, 2: 2000})
          ]));
      final h = findFillers(lonely, fillersFor('en')).single;
      expect(h.cutStartMs, h.words.first.clipStartMs - 150);
      expect(h.cutEndMs, h.words.last.clipEndMs + 150);
    });

    test('cuts are one undo step and the rest of the speech moves up', () {
      final e = ed(project(clips: [video('a', source: 60000)]));
      final talk = spoken('/media/a.mp4', 'So um I think uh it works');
      final lookup = lookupOf([talk]);
      final hits = findFillers(timelineWords(e.project, lookup), fillersFor('en'));
      final before = e.project.durationMs;
      final removed = applyFillerCuts(e.editorOrSelf, hits);
      expect(removed, 2);
      expect(e.project.clips.length, 3);
      expect(e.history.last.label, 'Removed 2 filler words');
      final total = hits.fold<int>(0, (n, h) => n + h.cutMs);
      expect(before - e.project.durationMs, total);
      final after = timelineWords(e.project, lookup);
      expect(said(after), 'So I think it works');
      // Nothing left to remove.
      expect(findFillers(after, fillersFor('en')), isEmpty);
      e.undo();
      expect(e.project.clips.length, 1);
    });

    test('two speakers: a filler under the other voice is flagged', () {
      final e = ed(project(clips: [video('a')]));
      AudioClip mic(String name) => AudioClip(
          id: 'tmp',
          path: '/media/$name.m4a',
          sourceDurationMs: 12000,
          startMs: 0,
          inMs: 0,
          outMs: 12000);
      e.addVoice(mic('anna'), clipId: 'a', offsetMs: 0, trackName: 'Anna');
      e.addVoice(mic('ben'), clipId: 'a', offsetMs: 0, trackName: 'Ben');
      final w = timelineWords(
          e.project,
          lookupOf([
            spoken('/media/anna.m4a', 'well um yes'),
            spoken('/media/ben.m4a', 'absolutely', startMs: 350, wordMs: 500),
            ]));
      final hit = findFillers(w, fillersFor('en')).single;
      expect(hit.speaker, 'Anna');
      expect(hit.overlapsSpeech, isTrue);
    });
  });

  group('keep one part (shorts)', () {
    test('main track cut to the range; titles and music follow', () {
      final e = ed(project(clips: [
        video('a'),
        video('b'),
        video('c')
      ], audio: [
        audio('m', startMs: 5000, source: 60000),
        audio('early', startMs: 0, source: 3000),
      ], titles: [
        title('in', startMs: 14000, endMs: 16000, text: 'inside'),
        title('out', startMs: 1000, endMs: 3000, text: 'outside'),
      ]));
      expect(keepTimelineRange(e.editorOrSelf, 12000, 22000), isTrue);
      final p = e.project;
      expect(p.durationMs, 10000);
      expect(p.clips.map((c) => [c.path, c.inMs, c.outMs]), [
        ['/media/b.mp4', 2000, 10000],
        ['/media/c.mp4', 0, 2000],
      ]);
      // The title on kept footage moved with it; the other is gone.
      expect(p.titles.single.id, 'in');
      expect([p.titles.single.startMs, p.titles.single.endMs], [2000, 4000]);
      // Music that started before the range now starts inside its file.
      final m = p.audio.single;
      expect([m.id, m.startMs, m.inMs], ['m', 0, 7000]);
      expect(e.history.length, 1);
      e.undo();
      expect(e.project.clips.length, 3);
      expect(e.project.audio.length, 2);
    });

    test('linked voice follows; an empty range changes nothing', () {
      final e = ed(project(clips: [video('a', source: 30000)]));
      e.addVoice(
          AudioClip(
              id: 'tmp',
              path: '/media/mic.m4a',
              sourceDurationMs: 31000,
              startMs: 0,
              inMs: 0,
              outMs: 31000),
          clipId: 'a',
          offsetMs: 400);
      expect(keepTimelineRange(e.editorOrSelf, 10000, 15000), isTrue);
      final v = e.project.audio.single;
      expect([v.startMs, v.inMs, v.outMs], [0, 10400, 15400]);
      expect(e.project.durationMs, 5000);
      final steps = e.history.length;
      expect(keepTimelineRange(e.editorOrSelf, 99000, 99500), isFalse);
      expect(e.history.length, steps);
    });
  });
}

extension on ProjectEditor {
  ProjectEditor get editorOrSelf => this;
}
