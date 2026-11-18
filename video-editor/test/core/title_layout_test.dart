import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:flutter_test/flutter_test.dart';

TitleOverlay t(String text, {double fontSize = 0.06, bool bold = true}) =>
    TitleOverlay(
        id: 't', text: text, startMs: 0, endMs: 1000, fontSize: fontSize, bold: bold);

List<String> lay(String text,
        {double fontSize = 0.06, bool bold = true, int w = 1080, int h = 1920}) =>
    layoutTitleLines(t(text, fontSize: fontSize, bold: bold),
        canvasWidth: w, canvasHeight: h);

const english =
    'The quick brown fox jumps over the lazy dog and keeps running through '
    'the forest until the evening comes, then it rests by the river.';
const russian =
    'Съешь же ещё этих мягких французских булок да выпей чаю, пока он совсем '
    'не остыл на столе, а потом расскажи мне, как прошёл твой день.';
const hebrew =
    'דג סקרן שט בים מאוכזב ולפתע מצא חברה, שלום לכולם, היום אנחנו מדברים על '
    'עריכת וידאו ועל כתוביות ארוכות שצריכות להתפצל לכמה שורות.';

void main() {
  group('layoutTitleLines', () {
    test('short text is one line, unchanged', () {
      expect(lay('Hello'), ['Hello']);
      expect(lay('Привет, мир'), ['Привет, мир']);
      expect(lay('שלום עולם'), ['שלום עולם']);
    });

    test('always at least one line', () {
      expect(lay(''), ['']);
      expect(lay('   '), ['']);
      expect(lay('x', w: 0, h: 0), ['x']);
      expect(lay('some words here', w: 0), ['some words here']);
    });

    test('explicit newlines are kept, in every flavour', () {
      expect(lay('one\ntwo'), ['one', 'two']);
      expect(lay('one\r\ntwo\rthree'), ['one', 'two', 'three']);
      expect(lay('one\n\ntwo'), ['one', '', 'two']);
      expect(lay('one\n'), ['one', '']);
    });

    test('spaces collapse and lines are trimmed', () {
      expect(lay('  a   b \t c  '), ['a b c']);
      expect(lay(' a \n b '), ['a', 'b']);
    });

    for (final sample in {'English': english, 'Russian': russian, 'Hebrew': hebrew}.entries) {
      for (final bold in [true, false]) {
        test('${sample.key} ${bold ? 'bold' : 'regular'} wraps inside 90% of the width', () {
          for (final size in [(w: 1080, h: 1920), (w: 1920, h: 1080), (w: 720, h: 720)]) {
            for (final fontSize in [0.03, 0.045, 0.06, 0.1]) {
              final lines = lay(sample.value,
                  fontSize: fontSize, bold: bold, w: size.w, h: size.h);
              // The font follows the SHORT side of the canvas.
              final fontPx =
                  (fontSize * (size.w < size.h ? size.w : size.h)).round();
              expect(lines.length, greaterThan(1), reason: '$size $fontSize');
              // Nothing lost, nothing reordered (a word wider than the
              // canvas may have been broken in two).
              expect(lines.join().replaceAll(' ', ''),
                  sample.value.replaceAll(' ', ''));
              if (fontSize < 0.1) expect(lines.join(' '), sample.value);
              for (var i = 0; i < lines.length; i++) {
                final width =
                    estimateTextWidth(lines[i], fontPx: fontPx, bold: bold);
                expect(width, lessThanOrEqualTo(size.w * 0.9 + 0.001),
                    reason: '$size $fontSize "${lines[i]}"');
                expect(lines[i], isNot(startsWith(' ')));
                expect(lines[i], isNot(endsWith(' ')));
                // Greedy: the next word would not have fitted.
                if (i + 1 < lines.length && fontSize < 0.1) {
                  final next = lines[i + 1].split(' ').first;
                  expect(
                      estimateTextWidth('${lines[i]} $next',
                          fontPx: fontPx, bold: bold),
                      greaterThan(size.w * 0.9),
                      reason: '"${lines[i]}" + "$next"');
                }
              }
            }
          }
        });
      }
    }

    test('bold text needs at least as many lines as regular', () {
      for (final s in [english, russian, hebrew]) {
        expect(lay(s, bold: true).length,
            greaterThanOrEqualTo(lay(s, bold: false).length));
      }
      expect(lay(english, fontSize: 0.12).length,
          greaterThan(lay(english, fontSize: 0.04).length));
    });

    test('a very long word is broken, the rest still wraps by words', () {
      final word = 'Donaudampfschifffahrtsgesellschaftskapitän' * 3;
      final lines = lay('see $word now', fontSize: 0.06);
      expect(lines.length, greaterThan(2));
      expect(lines.first, 'see');
      expect(lines.join().replaceAll(' ', ''), 'see${word}now');
      final fontPx = (0.06 * 1080).round();
      for (final l in lines) {
        expect(estimateTextWidth(l, fontPx: fontPx, bold: true),
            lessThanOrEqualTo(1080 * 0.9 + 0.001));
        expect(l, isNotEmpty);
      }
      // The tail of the broken word shares its line with the next word.
      expect(lines.last, endsWith(' now'));
    });

    test('a huge font still gives one character per line, never loops', () {
      final lines = lay('abc de', fontSize: 5, w: 100, h: 1000);
      expect(lines, ['a', 'b', 'c', 'd', 'e']);
    });

    test('marks stay with their letter when a word is broken', () {
      // Hebrew with points, and e + combining acute.
      final pointed = 'שָׁלוֹם' * 30;
      for (final l in lay(pointed, fontSize: 0.1)) {
        final first = l.runes.first;
        expect(first >= 0x05D0 && first <= 0x05EA, isTrue, reason: l);
      }
      final accents = 'é' * 200;
      final lines = lay(accents, fontSize: 0.1);
      expect(lines.length, greaterThan(1));
      for (final l in lines) {
        expect(l.runes.first, 0x65);
        expect(l.runes.length.isEven, isTrue);
      }
    });

    test('odd font sizes do not break it', () {
      expect(lay('a b', fontSize: 0), ['a b']);
      expect(lay('a b', fontSize: double.nan), ['a b']);
      expect(lay('a b', fontSize: -1), ['a b']);
      expect(lay('a b', fontSize: double.infinity), isNotEmpty);
    });

    test('captions and titles wrap the same way', () {
      final asTitle = t(english, fontSize: 0.045);
      final asCaption = captionStyle(asTitle);
      expect(
          layoutTitleLines(asCaption, canvasWidth: 1080, canvasHeight: 1920),
          layoutTitleLines(asTitle, canvasWidth: 1080, canvasHeight: 1920));
    });
  });

  group('estimateTextWidth', () {
    test('uses the measured DejaVu advances', () {
      // Advances from the font files, in 1/1000 em.
      expect(estimateTextWidth('A', fontPx: 1000, bold: false), 684);
      expect(estimateTextWidth('A', fontPx: 1000, bold: true), 774);
      expect(estimateTextWidth(' ', fontPx: 1000, bold: false), 318);
      expect(estimateTextWidth('il', fontPx: 100, bold: false), closeTo(55.6, 0.01));
      expect(estimateTextWidth('', fontPx: 100, bold: true), 0);
      // Scales with the font size.
      expect(estimateTextWidth('Hello', fontPx: 50, bold: true) * 2,
          closeTo(estimateTextWidth('Hello', fontPx: 100, bold: true), 1e-9));
    });

    test('average advance per character matches the documented factors', () {
      double avg(String s, bool bold) =>
          estimateTextWidth(s, fontPx: 1, bold: bold) / s.runes.length;
      expect(avg(english, false), closeTo(0.52, 0.02));
      expect(avg(english, true), closeTo(0.58, 0.02));
      expect(avg(russian, false), closeTo(0.58, 0.02));
      expect(avg(russian, true), closeTo(0.64, 0.02));
      expect(avg(hebrew, false), closeTo(0.49, 0.02));
      expect(avg(hebrew, true), closeTo(0.53, 0.02));
    });

    test('other scripts, wide characters and marks', () {
      expect(estimateTextWidth('ω', fontPx: 1000, bold: false),
          kFallbackAdvanceRegular * 1000);
      expect(estimateTextWidth('ω', fontPx: 1000, bold: true),
          kFallbackAdvanceBold * 1000);
      expect(estimateTextWidth('日本', fontPx: 100, bold: false), 200);
      expect(estimateTextWidth('é', fontPx: 1000, bold: false),
          estimateTextWidth('e', fontPx: 1000, bold: false));
      expect(estimateTextWidth('ָ', fontPx: 1000, bold: false), 0);
      expect(estimateTextWidth('ё', fontPx: 1000, bold: false), greaterThan(0));
    });
  });

  group('caption style', () {
    test('captionStyle applies the defaults and keeps id, text and times', () {
      const original = TitleOverlay(
          id: 'x', text: 'Hi', startMs: 5, endMs: 900, x: 0.1, y: 0.1,
          fontSize: 0.2, colorArgb: 0xFF00FF00, bold: false);
      final c = captionStyle(original);
      expect(c.id, 'x');
      expect(c.text, 'Hi');
      expect(c.startMs, 5);
      expect(c.endMs, 900);
      expect(c.kind, TitleKind.caption);
      expect(c.x, 0.5);
      expect(c.y, closeTo(0.86, 0.001));
      expect(c.fontSize, closeTo(0.045, 0.0001));
      expect(c.colorArgb, 0xFFFFFFFF);
      expect(c.bold, isTrue);
      expect(c.background, isTrue);
      expect(CaptionDefaults.kind, TitleKind.caption);
    });

    test('titleFontPx rounds like the export does', () {
      expect(titleFontPx(t('x', fontSize: 0.045), 1920), 86);
      expect(titleFontPx(t('x', fontSize: 0.06), 1080), 65);
      expect(titleFontPx(t('x', fontSize: 0), 1080), 1);
    });
  });
}
