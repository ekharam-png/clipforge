@Timeout(Duration(seconds: 90))
library;

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/help/help_screen.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Finder article(String id) => find.byKey(ValueKey('help-article-$id'));

Future<Fakes> openHelpFromHome(WidgetTester tester, Size size) async {
  useScreen(tester, size);
  final fakes = Fakes(projects: [sampleProject()]);
  await tester.pumpWidget(fakes.app(const HomeScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Help'));
  await tester.pumpAndSettle();
  expect(find.byType(HelpScreen), findsOneWidget);
  return fakes;
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('help-search')), text);
  await tester.pumpAndSettle();
}

/// The text of the search results' titles, in order.
List<String> resultTitles(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.descendant(
          of: find.byType(HelpScreen), matching: find.byType(ListTile))))
        if (tile.title case final Text t) t.textSpan!.toPlainText(),
    ];

/// True when some text on screen shows [word] highlighted.
bool highlighted(WidgetTester tester, String word) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    var found = false;
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor != null &&
          (span.text ?? '').toLowerCase() == word) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return true;
  }
  return false;
}

void main() {
  setUpAll(loadFonts);

  for (final size in [phone, desktop]) {
    final label = size == phone ? 'phone' : 'desktop';

    testWidgets('$label: topics by section, search with typos, related links',
        (tester) async {
      final fakes = await openHelpFromHome(tester, size);
      expect(find.text('Getting started'), findsWidgets);
      expect(find.text('Show the tour'), findsOneWidget);
      await fakes.screenshot(tester, 'help_$label');

      // The owner's typos.
      for (final (typo, title) in [
        ('trascirpe', 'Transcribe speech (computer only)'),
        ('musci', 'Adding music, volume and fades'),
        ('vocie', 'Voice focus'),
      ]) {
        await search(tester, typo);
        expect(resultTitles(tester).first, title, reason: typo);
      }
      await search(tester, 'musci');
      expect(highlighted(tester, 'music'), isTrue);
      expect(find.textContaining('topics found'), findsOneWidget);
      await fakes.screenshot(tester, 'help_${label}_search');

      await tester.tap(find.text('Adding music, volume and fades'));
      await tester.pumpAndSettle();
      expect(article('music'), findsOneWidget);
      // The word searched for is marked in the article too.
      expect(highlighted(tester, 'music'), isTrue);
      await fakes.screenshot(tester, 'help_${label}_article');

      final related = find.byKey(const ValueKey('help-related-lower-music'));
      await tester.ensureVisible(related);
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(article('lower-music'), findsOneWidget);
    });

    testWidgets('$label: nothing found offers spellings and popular topics',
        (tester) async {
      final fakes = await openHelpFromHome(tester, size);
      await search(tester, 'musiccccc');
      expect(find.textContaining('Nothing found'), findsOneWidget);
      expect(find.text('Did you mean:'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'music'), findsOneWidget);
      expect(find.text('Popular topics:'), findsOneWidget);
      await fakes.screenshot(tester, 'help_${label}_no_results');
      await tester.tap(find.widgetWithText(ActionChip, 'music'));
      await tester.pumpAndSettle();
      expect(resultTitles(tester), contains('Adding music, volume and fades'));
    });

    testWidgets('$label: Help from the editor', (tester) async {
      final fakes = await openEditor(tester, size);
      if (size == phone) {
        // Phones: Help is in the project menu.
        await tapProjectMenu(tester, 'Help');
      } else {
        await tester.tap(find.byTooltip('Help'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(HelpScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsNothing);
      expect(fakes.store.projects, contains('p1'));
    });
  }

  group('"?" next to settings opens the right article', () {
    Future<void> tapHint(WidgetTester tester, String id) async {
      final hint = find.byKey(ValueKey('help-hint-$id'));
      expect(hint, findsOneWidget, reason: id);
      await tester.ensureVisible(hint);
      await tester.pumpAndSettle();
      await tester.tap(hint);
      await tester.pumpAndSettle();
    }

    Future<void> expectArticle(
        WidgetTester tester, Size size, String id, Fakes fakes) async {
      expect(article(id), findsOneWidget, reason: id);
      // A sheet on the phone, a dialog on the computer.
      expect(find.byType(Dialog), size == phone ? findsNothing : findsOneWidget);
      expect(find.byType(BottomSheet),
          size == phone ? findsWidgets : findsNothing);
      await fakes.screenshot(
          tester, 'help_hint_${size == phone ? 'phone' : 'desktop'}_$id');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(article(id), findsNothing);
    }

    Project stereo() {
      final p = sampleProject();
      return p.copyWith(clips: [
        p.clips.first.copyWith(audioStreams: const [2]),
        ...p.clips.skip(1),
      ]);
    }

    for (final size in [phone, desktop]) {
      final label = size == phone ? 'phone' : 'desktop';

      testWidgets('$label: sound settings', (tester) async {
        final fakes = await openEditor(tester, size, project: stereo());
        await tester.tap(block('clip-a'));
        await tester.pumpAndSettle();
        await openClipTool(tester, size, 'Sound');
        for (final id in [
          'sound-from',
          'clean-up-sound',
          'voice-focus',
          'remove-silences',
        ]) {
          await tapHint(tester, id);
          await expectArticle(tester, size, id, fakes);
        }
      });

      testWidgets('$label: Fit / Fill / Blur', (tester) async {
        final fakes = await openEditor(tester, size);
        await tester.tap(block('clip-a'));
        await tester.pumpAndSettle();
        await openClipTool(tester, size, 'Look');
        await tapHint(tester, 'fit-fill-blur');
        await expectArticle(tester, size, 'fit-fill-blur', fakes);
      });

      testWidgets('$label: Lower music under speech', (tester) async {
        final fakes = await openEditor(tester, size);
        await zoomOutTwice(tester);
        await tester.tap(block('audio-m1'));
        await tester.pumpAndSettle();
        if (size == phone) {
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
        }
        await tapHint(tester, 'lower-music');
        await expectArticle(tester, size, 'lower-music', fakes);
      });

      testWidgets('$label: Shape', (tester) async {
        final fakes = await openEditor(tester, size);
        if (size == phone) {
          await tapProjectMenu(tester, 'Shape and size');
          await tester.ensureVisible(find.text('Which shape should I use?'));
        } else {
          await tester.tap(find.textContaining('Shape'));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Which shape should I use?'));
        await tester.pumpAndSettle();
        await expectArticle(tester, size, 'shape', fakes);
      });

      testWidgets('$label: Use graphics card', (tester) async {
        final fakes = await openEditor(tester, size, missingFiles: const {});
        fakes.engine.hardwareEncoder = true;
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        await tapHint(tester, 'graphics-card');
        expect(article('graphics-card'), findsOneWidget);
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
        expect(article('graphics-card'), findsNothing);
        expect(find.text('Export video'), findsOneWidget);
      });
    }

    testWidgets('"All help" goes on to the help screen', (tester) async {
      await openEditor(tester, desktop);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, desktop, 'Sound');
      await tapHint(tester, 'voice-focus');
      await tester.tap(find.text('All help'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
      expect(article('voice-focus'), findsOneWidget);
    });
  });
}
