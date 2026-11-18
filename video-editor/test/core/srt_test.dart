import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/core/subtitles/srt.dart';
import 'package:flutter_test/flutter_test.dart';

List<TitleOverlay> parse(String s) {
  var n = 0;
  return parseSrt(s, newId: () => 's${++n}');
}

List<List<Object>> cues(String s) =>
    [for (final t in parse(s)) [t.startMs, t.endMs, t.text]];

void main() {
  group('parseSrt', () {
    test('a plain file', () {
      final titles = parse('''
1
00:00:01,000 --> 00:00:04,250
Hello there

2
00:01:02,500 --> 01:00:00,007
Second cue
on two lines
''');
      expect(titles.length, 2);
      final a = titles[0];
      expect(a.id, 's1');
      expect(a.text, 'Hello there');
      expect(a.startMs, 1000);
      expect(a.endMs, 4250);
      expect(titles[1].id, 's2');
      expect(titles[1].startMs, 62500);
      expect(titles[1].endMs, 3600007);
      expect(titles[1].text, 'Second cue\non two lines');
    });

    test('cues are caption-kind titles with the caption look', () {
      final t = parse('1\n00:00:01,000 --> 00:00:02,000\nHi\n').single;
      expect(t.kind, TitleKind.caption);
      expect(t.x, CaptionDefaults.x);
      expect(t.y, CaptionDefaults.y);
      expect(t.fontSize, CaptionDefaults.fontSize);
      expect(t.colorArgb, 0xFFFFFFFF);
      expect(t.bold, isTrue);
      expect(t.background, isTrue);
    });

    test('byte order mark and CRLF / CR line ends', () {
      const body = '1\r\n00:00:01,000 --> 00:00:02,000\r\nOne\r\nmore\r\n\r\n'
          '2\r\n00:00:03,000 --> 00:00:04,000\r\nTwo\r\n';
      final expected = [
        [1000, 2000, 'One\nmore'],
        [3000, 4000, 'Two'],
      ];
      expect(cues('﻿$body'), expected);
      expect(cues(body.replaceAll('\r\n', '\r')), expected);
      expect(cues(body.replaceAll('\r\n', '\n')), expected);
    });

    test('missing index lines', () {
      expect(
          cues('00:00:01,000 --> 00:00:02,000\nOne\n\n'
              '00:00:03,000 --> 00:00:04,000\nTwo'),
          [
            [1000, 2000, 'One'],
            [3000, 4000, 'Two'],
          ]);
    });

    test('missing blank lines between cues', () {
      expect(
          cues('1\n00:00:01,000 --> 00:00:02,000\nOne\n'
              '2\n00:00:03,000 --> 00:00:04,000\nTwo\n'
              '00:00:05,000 --> 00:00:06,000\nThree'),
          [
            [1000, 2000, 'One'],
            [3000, 4000, 'Two'],
            [5000, 6000, 'Three'],
          ]);
    });

    test('a number as subtitle text is kept', () {
      expect(
          cues('1\n00:00:01,000 --> 00:00:02,000\n42\n\n'
              '2\n00:00:03,000 --> 00:00:04,000\n3\n2\n1'),
          [
            [1000, 2000, '42'],
            [3000, 4000, '3\n2\n1'],
          ]);
    });

    test('time formats: dot, short fraction, no hours, no fraction, spacing', () {
      expect(cues('00:00:01.500 --> 00:00:02.750\nA').single, [1500, 2750, 'A']);
      expect(cues('00:00:01,5 --> 00:00:02,25\nA').single, [1500, 2250, 'A']);
      expect(cues('01:02,000 --> 01:03,000\nA').single, [62000, 63000, 'A']);
      expect(cues('00:00:01 --> 00:00:02\nA').single, [1000, 2000, 'A']);
      expect(cues('  0:00:01,000-->0:00:02,000  \nA').single, [1000, 2000, 'A']);
      expect(cues('00:00:01,000 ->  00:00:02,000\nA').single, [1000, 2000, 'A']);
      expect(cues('100:00:00,000 --> 100:00:01,000\nA').single,
          [360000000, 360001000, 'A']);
      // Position info after the times is ignored.
      expect(
          cues('00:00:01,000 --> 00:00:02,000 X1:100 X2:200 Y1:50 Y2:80\nA')
              .single,
          [1000, 2000, 'A']);
    });

    test('formatting tags are removed, other angle brackets stay', () {
      expect(
          cues('1\n00:00:01,000 --> 00:00:02,000\n'
                  '<i>Italic</i> and <b>bold</B> <u>u</u>\n'
                  '{\\an8}<font color="#ff0000">Top red</font>\n'
                  '{\\pos(10,20)}I <3 you, 1 < 2 > 0')
              .single[2],
          'Italic and bold u\nTop red\nI <3 you, 1 < 2 > 0');
    });

    test('a line with only tags does not make an empty line', () {
      expect(
          cues('00:00:01,000 --> 00:00:02,000\n<i></i>\nText\n{\\an2}').single[2],
          'Text');
    });

    test('malformed cues are skipped, good ones survive', () {
      expect(
          cues('''
1
00:00:01,000 --> 00:00:02,000
Good one

2
00:00:05,000 --> 00:00:04,000
Ends before it starts

3
00:00:06,000 --> 00:00:06,000
Zero length

4
00:00:07,000 --> 00:00:08,000

5
garbage --> more garbage
No time

6
00:00:09,000
Half a time line

7
00:00:10,000 --> 00:00:11,000
<i> </i>

8
00:00:12,000 --> 00:00:13,000
Good two
'''),
          [
            [1000, 2000, 'Good one'],
            [12000, 13000, 'Good two'],
          ]);
    });

    test('ids are only taken for cues that are kept', () {
      final titles = parse('00:00:02,000 --> 00:00:01,000\nBad\n\n'
          '00:00:03,000 --> 00:00:04,000\nGood');
      expect(titles.single.id, 's1');
    });

    test('not subtitles at all gives an empty list', () {
      expect(parse(''), isEmpty);
      expect(parse('﻿'), isEmpty);
      expect(parse('\n\n\n'), isEmpty);
      expect(parse('Just some text\nwith lines\n\n123\n'), isEmpty);
      expect(parse('{"json": true, "a": "-->"}'), isEmpty);
    });

    test('a WebVTT style header and cue names are tolerated', () {
      expect(
          cues('WEBVTT\n\nintro\n00:00:01.000 --> 00:00:02.000\nHi'),
          [
            [1000, 2000, 'Hi'],
          ]);
    });

    test('file order is kept, also when times are out of order', () {
      expect(
          [for (final c in cues('00:00:05,000 --> 00:00:06,000\nB\n\n'
              '00:00:01,000 --> 00:00:02,000\nA')) c[2]],
          ['B', 'A']);
    });

    test('other scripts', () {
      expect(
          cues('1\n00:00:01,000 --> 00:00:02,000\nПривет, мир\n\n'
              '2\n00:00:03,000 --> 00:00:04,000\nשלום עולם'),
          [
            [1000, 2000, 'Привет, мир'],
            [3000, 4000, 'שלום עולם'],
          ]);
    });
  });

  group('toSrt', () {
    TitleOverlay cap(String id, int start, int end, String text,
            {TitleKind kind = TitleKind.caption}) =>
        TitleOverlay(id: id, text: text, startMs: start, endMs: end, kind: kind);

    test('captions only, sorted, numbered', () {
      final srt = toSrt([
        cap('b', 62500, 3723004, 'Later\nsecond line'),
        cap('t', 0, 5000, 'A big title', kind: TitleKind.title),
        cap('a', 1000, 4250, 'First'),
      ]);
      expect(
          srt,
          '1\n00:00:01,000 --> 00:00:04,250\nFirst\n\n'
          '2\n00:01:02,500 --> 01:02:03,004\nLater\nsecond line\n\n');
    });

    test('nothing to write', () {
      expect(toSrt(const []), '');
      expect(toSrt([cap('t', 0, 1000, 'Title', kind: TitleKind.title)]), '');
      expect(toSrt([cap('a', 0, 1000, '  \n ')]), '');
      expect(toSrt([cap('a', 1000, 1000, 'Zero')]), '');
    });

    test('blank lines inside a caption are dropped', () {
      expect(toSrt([cap('a', 0, 1000, 'One\n\n  Two  \r\n')]),
          '1\n00:00:00,000 --> 00:00:01,000\nOne\nTwo\n\n');
    });

    test('same start: shorter first, then input order', () {
      final srt = toSrt([
        cap('a', 0, 3000, 'long'),
        cap('b', 0, 1000, 'short'),
        cap('c', 0, 1000, 'short too'),
      ]);
      expect(parse(srt).map((t) => t.text), ['short', 'short too', 'long']);
    });

    test('very long times', () {
      expect(toSrt([cap('a', 360000000, 360001001, 'x')]),
          startsWith('1\n100:00:00,000 --> 100:00:01,001\n'));
    });

    test('round trip', () {
      final original = [
        captionStyle(cap('1', 1000, 2500, 'Hello')),
        captionStyle(cap('2', 3000, 4000, 'Two\nlines')),
        captionStyle(cap('3', 3600000, 3600500, 'Привет שלום')),
      ];
      final back = parse(toSrt(original));
      expect(back.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(back[i].text, original[i].text);
        expect(back[i].startMs, original[i].startMs);
        expect(back[i].endMs, original[i].endMs);
        expect(back[i].kind, TitleKind.caption);
        expect(back[i].y, original[i].y);
      }
      expect(toSrt(back), toSrt(original));
    });
  });
}
