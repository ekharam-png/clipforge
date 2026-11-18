// 1.13: the Text window's document (pure): speakers from "Name:", lines
// grouped into paragraphs by speaker and pauses, the line being spoken,
// search, the document as text, find-and-replace over captions, where to
// scroll to while following, and "Cut this part out of the video".
import 'package:clipforge/core/editor/edit_labels.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/text/text_document.dart';
import 'package:clipforge/core/transcript/speech_edits.dart';
import 'package:flutter_test/flutter_test.dart';

TitleOverlay cap(String id, String text, int start, int end) => TitleOverlay(
    id: id, text: text, startMs: start, endMs: end, kind: TitleKind.caption);

Clip clip(String id, String path, int inMs, int outMs, {double speed = 1}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: 600000,
      inMs: inMs,
      outMs: outMs,
      width: 1920,
      height: 1080,
      speed: speed,
    );

Project project({List<TitleOverlay> titles = const [], List<Clip>? clips}) =>
    Project(
      id: 'p',
      name: 'Podcast',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      clips: clips ?? [clip('a', '/m/talk.mp4', 0, 600000)],
      titles: titles,
    );

TextDocument captionsOf(Project p) =>
    buildTextDocument(TextSource.captions, captionLines(p));

void main() {
  group('speaker names', () {
    test('"Name:" at the start is the speaker', () {
      expect(splitSpeaker("Sam: it's okay to have"),
          (speaker: 'Sam', text: "it's okay to have"));
      expect(splitSpeaker('Dana Levi:  two\nlines'),
          (speaker: 'Dana Levi', text: 'two lines'));
      expect(splitSpeaker('- Sam: with a dash').speaker, 'Sam');
      expect(splitSpeaker('דנה: שלום לכולם'),
          (speaker: 'דנה', text: 'שלום לכולם'));
      expect(splitSpeaker('Анна: привет').speaker, 'Анна');
    });

    test('times, sentences and long openers are not speakers', () {
      for (final t in [
        'At 10:30 we start',
        '10:30 is the time',
        'Remember this. One thing: patience',
        'He said, and I quote: no',
        'This is a rather long opening phrase that goes on: x',
        'No colon here',
        'Trailing colon:',
      ]) {
        expect(splitSpeaker(t).speaker, '', reason: t);
      }
      expect(splitSpeaker('two\nlines').text, 'two lines');
    });
  });

  group('paragraphs', () {
    final p = project(titles: [
      cap('3', 'Dana: Thanks for having me.', 5000, 7000),
      cap('1', 'Sam: Welcome back', 0, 2000),
      cap('2', 'to the show.', 2100, 4000),
      cap('4', 'It is good to be here.', 7100, 9000),
      // A pause of two seconds: a new paragraph, same speaker.
      cap('5', 'So, bread.', 11000, 12000),
      cap('6', 'Sam: Yes!', 12100, 13000),
    ]);

    test('by speaker and by pauses, in time order', () {
      final doc = captionsOf(p);
      expect(doc.lines.map((l) => l.id), ['1', '2', '3', '4', '5', '6']);
      expect(doc.speakers, ['Sam', 'Dana']);
      expect([for (final par in doc.paragraphs) '${par.speaker}|${par.text}'], [
        'Sam|Welcome back to the show.',
        'Dana|Thanks for having me. It is good to be here.',
        'Dana|So, bread.',
        'Sam|Yes!',
      ]);
      // A caption without a name belongs to whoever spoke last.
      expect(doc.lines[1].speaker, 'Sam');
      expect(doc.lines[1].named, isFalse);
      expect(doc.lines[0].raw, 'Sam: Welcome back');
      expect(doc.paragraphOfLine, [0, 0, 1, 1, 2, 3]);
      expect(doc.paragraphs[1].firstLine, 2);
      expect(doc.paragraphs[1].offsets, [0, 22]);
      expect(doc.paragraphs[1].startMs, 5000);
      expect(doc.indexOf('5'), 4);
      expect(doc.indexOf('nope'), -1);
    });

    test('a long monologue is broken at a sentence end', () {
      final doc = captionsOf(project(titles: [
        for (var i = 0; i < 60; i++)
          cap('c$i', i == 0 ? 'Sam: And so it goes on.' : 'And so it goes on.',
              i * 1000, i * 1000 + 900),
      ]));
      expect(doc.paragraphs.length, greaterThan(1));
      for (final par in doc.paragraphs) {
        expect(par.text.length, lessThanOrEqualTo(kParagraphMaxChars + 40));
        expect(par.speaker, 'Sam');
      }
      expect(doc.paragraphs.fold<int>(0, (n, x) => n + x.lines.length), 60);
    });

    test('titles are one paragraph each; captions are left out', () {
      final p = project(titles: [
        cap('c', 'a caption', 0, 1000),
        const TitleOverlay(id: 't2', text: 'The\nEnd', startMs: 9000, endMs: 9500),
        const TitleOverlay(id: 't1', text: 'Bread', startMs: 0, endMs: 3000),
      ]);
      final doc = buildTextDocument(TextSource.titles, titleLines(p));
      expect(doc.paragraphs.map((x) => x.text), ['Bread', 'The End']);
      expect(captionsOf(p).lines.single.id, 'c');
    });

    test('1500 captions are grouped quickly', () {
      final big = project(titles: [
        for (var i = 0; i < 1500; i++)
          cap('c$i', '${i % 7 == 0 ? (i % 2 == 0 ? 'Sam: ' : 'Dana: ') : ''}line $i of the talk',
              i * 1600, i * 1600 + 1500),
      ]);
      final watch = Stopwatch()..start();
      final doc = captionsOf(big);
      final matches = findInText(doc, 'talk');
      watch.stop();
      expect(doc.lines.length, 1500);
      expect(matches.length, 1500);
      expect(watch.elapsedMilliseconds, lessThan(400));
    });
  });

  test('the line being spoken', () {
    final doc = captionsOf(project(titles: [
      cap('1', 'one', 1000, 2000),
      cap('2', 'two', 2000, 3000),
      // Two rows: this one overlaps the next.
      cap('3', 'three', 5000, 8000),
      cap('4', 'four', 6000, 6500),
    ]));
    expect(doc.activeLineAt(0), -1);
    expect(doc.activeLineAt(1000), 0);
    expect(doc.activeLineAt(1999), 0);
    expect(doc.activeLineAt(2000), 1);
    expect(doc.activeLineAt(4000), -1); // a pause
    expect(doc.activeLineAt(6200), 3);
    expect(doc.activeLineAt(7000), 2); // the later one ended, this one not
    expect(doc.activeLineAt(9000), -1);
    expect(doc.lineIndexBefore(4000), 1);
    expect(doc.lineIndexBefore(500), -1);
    expect(TextDocument.empty.activeLineAt(100), -1);
  });

  test('search: every place, whatever the case', () {
    final doc = captionsOf(project(titles: [
      cap('1', 'Sam: Bread, bread and more BREAD', 0, 1000),
      cap('2', 'no match', 1000, 2000),
      cap('3', 'Dana: fresh   bread', 2000, 3000),
    ]));
    final m = findInText(doc, 'bread');
    expect([for (final x in m) (x.line, x.start, x.end)],
        [(0, 0, 5), (0, 7, 12), (0, 22, 27), (2, 6, 11)]);
    // The speaker's name is not part of the text that is searched.
    expect(findInText(doc, 'sam'), isEmpty);
    expect(findInText(doc, '  '), isEmpty);
    expect(findInText(doc, 'fresh bread').single.line, 2);
  });

  test('the document as text, with or without times and names', () {
    final doc = captionsOf(project(titles: [
      cap('1', 'Sam: Welcome back', 0, 2000),
      cap('2', 'to the show.', 2100, 4000),
      cap('3', 'Dana: Thanks.', 65000, 66000),
    ]));
    expect(documentAsText(doc, speakers: false),
        'Welcome back to the show.\n\nThanks.\n');
    expect(documentAsText(doc),
        'Sam: Welcome back to the show.\n\nDana: Thanks.\n');
    expect(documentAsText(doc, times: true),
        '[0:00] Sam: Welcome back to the show.\n\n[1:05] Dana: Thanks.\n');
    expect(documentAsText(TextDocument.empty), '');
  });

  group('following playback', () {
    double? to(double top, double bottom, double offset) => followOffset(
        top: top, bottom: bottom, offset: offset, viewport: 400, maxOffset: 5000);

    test('a line in view is left where it is', () {
      expect(to(100, 124, 0), isNull);
      expect(to(300, 318, 0), isNull);
    });

    test('a line near the bottom, below or above comes to the upper part', () {
      expect(to(330, 354, 0), 230); // lower than four fifths
      expect(to(900, 924, 0), 800);
      expect(to(900, 924, 2000), 800);
      expect(to(20, 44, 0), isNull);
      expect(to(20, 44, 30), 0); // clamped at the top
      expect(to(6000, 6024, 0), 5000); // and at the end
    });

    test('nothing to do without a view', () {
      expect(
          followOffset(top: 10, bottom: 20, offset: 0, viewport: 0, maxOffset: 0),
          isNull);
    });
  });

  group('find and replace in captions', () {
    final p = project(titles: [
      cap('1', 'Sem: hello, Sem here', 0, 1000),
      cap('2', 'Semester starts', 1000, 2000),
      cap('3', 'sem', 2000, 3000),
      const TitleOverlay(id: 't', text: 'Sem show', startMs: 0, endMs: 500),
    ]);

    test('all places, case ignored, titles left alone', () {
      final r = replaceInCaptions(p, 'Sem', 'Sam');
      expect(r.total, 4);
      expect(r.changes.map((c) => c.after.text),
          ['Sam: hello, Sam here', 'Samester starts', 'Sam']);
      expect(r.changes.first.count, 2);
      expect(replaceInCaptions(p, 'Sem', 'Sam', titlesToo: true).changes.length, 4);
    });

    test('whole words, case, a time range', () {
      expect(
          replaceInCaptions(p, 'Sem', 'Sam', wholeWord: true)
              .changes
              .map((c) => c.before.id),
          ['1', '3']);
      expect(
          replaceInCaptions(p, 'Sem', 'Sam', wholeWord: true, caseSensitive: true)
              .changes
              .map((c) => c.before.id),
          ['1']);
      expect(
          replaceInCaptions(p, 'sem', 'Sam', fromMs: 1000, toMs: 2000)
              .changes
              .single
              .before
              .id,
          '2');
    });

    test('a caption is never emptied; special characters are literal', () {
      final r = replaceInCaptions(p, 'sem', '', caseSensitive: true);
      expect(r.changes, isEmpty);
      expect(r.skipped, 1);
      final q = project(titles: [cap('1', 'a.b (c)', 0, 1000)]);
      expect(replaceInCaptions(q, '.', '!').changes.single.after.text, 'a!b (c)');
      expect(replaceInCaptions(q, '(c)', r'$1').changes.single.after.text, r'a.b $1');
      expect(replaceInCaptions(q, '', 'x').total, 0);
    });
  });

  group('History names', () {
    test('editing and deleting captions', () {
      final before = project(titles: [
        cap('1', 'Sam: helo there, everyone', 0, 1000),
        cap('2', 'two', 1000, 2000),
        cap('3', 'three', 2000, 3000),
      ]);
      final e = ProjectEditor(before);
      e.updateTitle(before.titles[0].copyWith(text: 'Sam: hello there, everyone'));
      expect(describeEdit(before, e.project), "Edited caption 'Sam: hello there, e…'");
      final mid = e.project;
      e.transaction(() {
        e.removeTitle('2');
        e.removeTitle('3');
      });
      expect(describeEdit(mid, e.project), 'Deleted 2 captions');
      expect(e.project.titles.single.id, '1');
      e.undo();
      expect(e.project.titles.length, 3);
      e.undo();
      expect(e.project.titles.first.text, 'Sam: helo there, everyone');
    });
  });

  group('cut a part out of the video', () {
    var n = 0;
    String id() => 'new${n++}';

    test('inside one clip: the source range, logged, and put back', () {
      final p = project(
          clips: [clip('a', '/m/talk.mp4', 10000, 70000)],
          titles: [
            cap('before', 'kept', 1000, 2000),
            cap('gone', 'cut me', 20500, 24000),
            cap('after', 'kept too', 40000, 42000),
          ]);
      final plan = planTimelineCut(p, 20000, 25000);
      expect(plan.removedMs, 5000);
      expect(plan.parts.single,
          (clipId: 'a', path: '/m/talk.mp4', startMs: 30000, endMs: 35000, whole: false, timelineMs: 5000));
      final e = ProjectEditor(p, newId: id);
      expect(applyTimelineCut(e, plan, word: 'cut me', newId: id), 1);
      expect(e.project.durationMs, 55000);
      expect(e.project.clips.map((c) => (c.inMs, c.outMs)),
          [(10000, 30000), (35000, 70000)]);
      // The caption on the removed part went with it; the later one moved.
      expect(e.project.titles.map((t) => t.id), ['before', 'after']);
      expect(e.project.titles.last.startMs, 35000);
      final cut = e.project.autoCuts.single;
      expect((cut.kind, cut.word, cut.startMs, cut.endMs, cut.by),
          ('text', 'cut me', 30000, 35000, 'app'));
      // One undo step.
      e.undo();
      expect(e.project.durationMs, 60000);
      expect(e.project.titles.length, 3);
      expect(e.project.autoCuts, isEmpty);
      e.redo();
      // Put back from the log: one clip again.
      expect(restoreAutoCut(e, cut.id, newId: id), RestoreResult.healed);
      expect(e.project.clips.single.outMs, 70000);
      expect(e.project.durationMs, 60000);
      expect(e.project.autoCuts, isEmpty);
    });

    test('across clips, with speed; a whole clip goes', () {
      final p = project(clips: [
        clip('a', '/m/one.mp4', 0, 10000),
        clip('b', '/m/two.mp4', 0, 4000),
        clip('c', '/m/one.mp4', 20000, 40000, speed: 2),
      ]);
      // a: 0-10 s, b: 10-14 s, c: 14-24 s (20 s of file at 2x).
      final plan = planTimelineCut(p, 8000, 16000);
      expect(plan.removedMs, 8000);
      expect([for (final x in plan.parts) (x.clipId, x.startMs, x.endMs, x.whole)], [
        ('a', 8000, 10000, false),
        ('b', 0, 4000, true),
        ('c', 20000, 24000, false),
      ]);
      final e = ProjectEditor(p, newId: id);
      expect(applyTimelineCut(e, plan, newId: id), 3);
      expect(e.project.durationMs, 16000);
      expect(e.project.clips.map((c) => (c.id, c.inMs, c.outMs)),
          [('a', 0, 8000), ('c', 24000, 40000)]);
      expect(e.project.autoCuts.map((c) => (c.path, c.startMs, c.endMs)), [
        ('/m/one.mp4', 8000, 10000),
        ('/m/two.mp4', 0, 4000),
        ('/m/one.mp4', 20000, 24000),
      ]);
      e.undo();
      expect(e.project.clips.length, 3);
      expect(e.project.durationMs, 24000);
    });

    test('photos partly inside stay; nothing outside the video', () {
      final photo = Clip(
          id: 'ph',
          type: ClipType.photo,
          path: '/m/pic.jpg',
          sourceDurationMs: 0,
          inMs: 0,
          outMs: 3000,
          width: 100,
          height: 100,
          hasAudio: false);
      final p = project(clips: [clip('a', '/m/one.mp4', 0, 10000), photo]);
      final plan = planTimelineCut(p, 9000, 11000);
      expect(plan.photosLeft, 1);
      expect(plan.removedMs, 1000);
      expect(planTimelineCut(p, 10000, 13000).parts.single.whole, isTrue);
      expect(planTimelineCut(p, 20000, 30000).isEmpty, isTrue);
      expect(planTimelineCut(p, 500, 500).isEmpty, isTrue);
      final e = ProjectEditor(p, newId: id);
      expect(applyTimelineCut(e, planTimelineCut(p, 20000, 30000), newId: id), 0);
      expect(e.canUndo, isFalse);
    });
  });
}
