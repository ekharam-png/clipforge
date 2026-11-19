// 1.13: the Text window. Everything said or written in the project as a
// readable document: captions (whatever made them), the transcript, the
// titles; paragraphs by speaker; the line being spoken followed; click to
// jump; search; light editing of captions; one confirmed "cut this part
// out"; copy and save; at the right or under the preview on computers, a
// full-screen sheet on phones. Overflow errors fail these tests by
// themselves.
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/text/text_document.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/text_panel.dart';
import 'package:clipforge/ui/speaker_colors.dart';
import 'package:clipforge/ui/widgets.dart' show textDirectionOf;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const talkPath = '/media/talk.mp4';

/// What two made-up people say, in turns of a few captions.
const _said = [
  "it's okay to have a plan and then throw it away.",
  'That is what the first year taught me.',
  'We baked the same loaf forty times',
  'before anyone outside the family tasted it.',
  'And what did they say?',
  'They said it needed salt.',
  'So you added salt.',
  'We added salt, and patience.',
  'Flour, water, salt and time: that is the whole recipe.',
  'Everything else is practice.',
];

/// A podcast of two speakers with [count] captions that were imported
/// from a subtitle file: each speaker's first caption of a turn starts
/// with the name.
Project podcast({int count = 40, bool hebrew = false, bool title = true}) {
  final captions = <TitleOverlay>[];
  var at = 400;
  for (var i = 0; i < count; i++) {
    final turn = i ~/ 3;
    final name = turn.isEven ? 'Sam' : 'Dana';
    final first = i % 3 == 0;
    final text = hebrew
        ? (first ? 'דנה: היום נדבר על לחם.' : 'קודם צריך קמח, מים ומלח.')
        : '${first ? '$name: ' : ''}${_said[i % _said.length]}';
    captions.add(TitleOverlay(
      id: 'c$i',
      text: i == 1 && !hebrew ? 'That is what the first\nyear taught me.' : text,
      startMs: at,
      endMs: at + 1500,
      kind: TitleKind.caption,
      y: 0.86,
      fontSize: 0.045,
    ));
    // A longer pause after every sixth caption.
    at += i % 6 == 5 ? 4200 : 1600;
  }
  final length = at + 2000;
  return Project(
    id: 'p1',
    name: 'Bread talk',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 2),
    aspect: CanvasAspect.landscape16x9,
    clips: [
      Clip(
        id: 'a',
        type: ClipType.video,
        path: talkPath,
        sourceDurationMs: length,
        inMs: 0,
        outMs: length,
        width: 1920,
        height: 1080,
      ),
    ],
    titles: [
      ...captions,
      if (title)
        const TitleOverlay(
            id: 't1', text: 'Bread talk', startMs: 0, endMs: 3000, y: 0.3),
    ],
  );
}

Finder key(String k) => find.byKey(ValueKey(k));

Future<Fakes> open(WidgetTester tester, Size size,
    {Project? project, FakeSpeech? speech, bool menuBar = false, Fakes? fakes}) async {
  useScreen(tester, size);
  final f = fakes ?? Fakes(projects: [project ?? podcast()], missing: const {});
  f.speech = speech ?? f.speech;
  await tester.pumpWidget(f.app(const EditorScreen(projectId: 'p1'), menuBar: menuBar));
  await tester.pumpAndSettle();
  return f;
}

EditorSession session(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

TextPanelState panel(WidgetTester tester) =>
    tester.state<TextPanelState>(find.byType(TextPanel));

Future<void> openText(WidgetTester tester) async {
  await tester.tap(key('text-button'));
  await tester.pumpAndSettle();
}

double scrollOf(WidgetTester tester) => tester
    .widget<ListView>(key('text-list'))
    .controller!
    .offset;

List<String> catchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('desktop: imported captions read as a document, by speaker',
      (tester) async {
    final fakes = await open(tester, const Size(1600, 900));
    expect(key('text-panel'), findsNothing);
    await openText(tester);
    expect(key('text-panel'), findsOneWidget);
    // Captions are the source when the project has any; with titles too
    // there is a switch.
    expect(panel(tester).source, TextSource.captions);
    expect(key('text-source'), findsOneWidget);
    expect(key('text-source-captions'), findsOneWidget);
    expect(key('text-source-titles'), findsOneWidget);
    expect(key('text-source-transcript'), findsNothing);
    // Three captions of one speaker are one paragraph; the name is shown
    // once and is not repeated in the text.
    final first = tester.widget<RichText>(textWindowBody("it's okay to have").first);
    expect(first.text.toPlainText(),
        "it's okay to have a plan and then throw it away. "
        'That is what the first year taught me. '
        'We baked the same loaf forty times');
    final sam = tester.widget<Text>(find.text('Sam').first);
    final dana = tester.widget<Text>(find.text('Dana').first);
    expect(sam.style!.color, kSpeakerColors[0]);
    expect(dana.style!.color, kSpeakerColors[1]);
    // A time mark at each paragraph.
    expect(find.descendant(of: key('text-panel'), matching: find.text('0:00')),
        findsOneWidget);
    expect(find.descendant(of: key('text-panel'), matching: find.text('0:05')),
        findsOneWidget);
    // At least 420 wide.
    expect(tester.getSize(key('text-panel')).width, greaterThanOrEqualTo(420));
    await fakes.screenshot(tester, 'text_window_desktop_wide');

    // The titles.
    await tester.tap(key('text-source-titles'));
    await tester.pumpAndSettle();
    expect(textWindowBody('Bread talk'), findsOneWidget);
    expect(textWindowBody("it's okay to have"), findsNothing);
    await tester.tap(key('text-source-captions'));
    await tester.pumpAndSettle();
    await tester.tap(key('text-close'));
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsNothing);
  });

  testWidgets('desktop: the measured heights are the real ones', (tester) async {
    await open(tester, const Size(1280, 800));
    await openText(tester);
    final tops = panel(tester).debugTops;
    final doc = panel(tester).document;
    final list = tester.getTopLeft(key('text-list')).dy;
    for (var i = 0; i < 4; i++) {
      final par = doc.paragraphs[i];
      final body = find.byKey(ValueKey('text-body-${par.lines.first.id}'));
      // Top padding 7, and the name (20) on a paragraph that shows it.
      final named = i == 0 || doc.paragraphs[i - 1].speaker != par.speaker;
      expect(tester.getTopLeft(body).dy, list + tops[i] + 7 + (named ? 20 : 0));
      expect(tester.getBottomLeft(body).dy, list + tops[i + 1] - 7);
    }
  });

  testWidgets('desktop: click a sentence, the playhead goes there and the '
      'caption is selected; a caption picked on the timeline is shown',
      (tester) async {
    await open(tester, const Size(1280, 800));
    await openText(tester);
    final s = session(tester);
    await tapInTextWindow(tester, 'They said it needed salt.');
    await tester.pumpAndSettle();
    final c5 = s.project.titles.firstWhere((t) => t.id == 'c5');
    expect(s.playback.positionMs, c5.startMs);
    expect(s.selection.value, const Selection(ItemKind.title, 'c5'));
    expect(panel(tester).selectedIds, {'c5'});
    expect(find.text('1 caption · ${'0:08.4'}–${'0:09.9'}'), findsOneWidget);
    // The time mark of a paragraph goes to its start.
    await tester.tap(find.descendant(
        of: key('text-panel'), matching: find.text('0:00')));
    await tester.pumpAndSettle();
    expect(s.playback.positionMs, 400);

    // Far down the document: not built until the timeline selects it.
    expect(textWindowBody('Everything else is practice.').evaluate().length,
        lessThan(4));
    final before = scrollOf(tester);
    s.select(ItemKind.title, 'c39');
    await tester.pumpAndSettle();
    expect(scrollOf(tester), greaterThan(before + 200));
    expect(panel(tester).selectedIds, {'c39'});
    final box = tester.getRect(key('text-list'));
    final place = textWindowPlace(tester, 'Everything else is practice.');
    expect(box.contains(place), isTrue);
  });

  testWidgets('desktop: the line being spoken is followed; scrolling by hand '
      'stops that; Now comes back', (tester) async {
    await open(tester, const Size(1280, 800));
    await openText(tester);
    final s = session(tester);
    expect(panel(tester).follow, isTrue);
    expect(key('text-now'), findsNothing);
    final late = s.project.titles.firstWhere((t) => t.id == 'c36');
    s.playback.seek(late.startMs + 100);
    await tester.pumpAndSettle();
    final followed = scrollOf(tester);
    expect(followed, greaterThan(300));
    expect(
        tester.getRect(key('text-list')).contains(
            textWindowPlace(tester, s.project.titles.firstWhere((t) => t.id == 'c36').text.replaceFirst(RegExp(r'^\w+: '), ''))),
        isTrue);
    expect(panel(tester).follow, isTrue, reason: 'following is not "by hand"');

    // By hand.
    await tester.drag(key('text-list'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(panel(tester).follow, isFalse);
    expect(key('text-now'), findsOneWidget);
    final byHand = scrollOf(tester);
    expect(byHand, lessThan(followed));
    // The playhead moves on; the window stays where it was put.
    s.playback.seek(late.startMs + 1700);
    await tester.pumpAndSettle();
    expect(scrollOf(tester), byHand);

    await tester.tap(key('text-now'));
    await tester.pumpAndSettle();
    expect(panel(tester).follow, isTrue);
    expect(key('text-now'), findsNothing);
    expect(scrollOf(tester), greaterThan(byHand));
    // The follow button toggles too.
    await tester.tap(key('text-follow'));
    await tester.pumpAndSettle();
    expect(panel(tester).follow, isFalse);
  });

  testWidgets('desktop: search with a count, next and previous; Ctrl+F',
      (tester) async {
    await open(tester, const Size(1280, 800));
    final s = session(tester);
    // Ctrl+F opens the window and puts the cursor in the search box.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsOneWidget);
    final field = tester.widget<TextField>(key('text-search'));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(key('text-match-count'), findsNothing);

    await tester.enterText(key('text-search'), 'SALT');
    await tester.pumpAndSettle();
    // "salt" is said in 4 of every 10 lines, once each: 16 in 40 lines.
    String count() => tester.widget<Text>(key('text-match-count')).data!;
    expect(count(), '1 of 16');
    await tester.tap(key('text-next'));
    await tester.pumpAndSettle();
    expect(count(), '2 of 16');
    await tester.tap(key('text-prev'));
    await tester.tap(key('text-prev'));
    await tester.pumpAndSettle();
    expect(count(), '16 of 16');
    // The last match is far down: it was scrolled to.
    expect(scrollOf(tester), greaterThan(300));
    expect(panel(tester).follow, isFalse);
    // Enter: next (wraps around).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count(), '1 of 16');
    await tester.enterText(key('text-search'), 'pizza');
    await tester.pumpAndSettle();
    expect(count(), 'Not found');
    expect(tester.widget<IconButton>(key('text-next')).onPressed, isNull);
    // Typing in the box is not a shortcut of the editor.
    await tester.enterText(key('text-search'), 's');
    await tester.pumpAndSettle();
    expect(s.project.clips.length, 1);
  });

  testWidgets('desktop: double-click fixes a caption in place: one undo step '
      'named in the History', (tester) async {
    await open(tester, const Size(1280, 800));
    await openText(tester);
    final s = session(tester);
    await tapInTextWindow(tester, 'So you added salt.');
    await tapInTextWindow(tester, 'So you added salt.');
    await tester.pumpAndSettle();
    expect(key('text-edit-field'), findsOneWidget);
    // The caption as it is stored: with the speaker's name.
    expect(tester.widget<TextField>(key('text-edit-field')).controller!.text,
        'Sam: So you added salt.');
    await tester.enterText(key('text-edit-field'), 'Sam: So you added more salt.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(key('text-edit-field'), findsNothing);
    expect(s.project.titles.firstWhere((t) => t.id == 'c6').text,
        'Sam: So you added more salt.');
    expect(textWindowBody('So you added more salt.'), findsOneWidget);
    expect(s.editor.history.last.label, "Edited caption 'Sam: So you added m…'");
    expect(s.editor.history.length, 1);
    s.editor.undo();
    await tester.pumpAndSettle();
    expect(textWindowBody('So you added salt.'), findsOneWidget);

    // The Edit button; Escape leaves it as it was; an empty one is refused.
    await tapInTextWindow(tester, 'And what did they say?');
    await tester.pumpAndSettle();
    await tester.tap(key('text-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(key('text-edit-field'), 'changed my mind');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('text-edit-field'), findsNothing);
    expect(s.project.titles.firstWhere((t) => t.id == 'c4').text,
        'And what did they say?');
    await tester.tap(key('text-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(key('text-edit-field'), '   ');
    await tester.tap(key('text-edit-save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be empty'), findsOneWidget);
    expect(key('text-edit-field'), findsOneWidget);
    await tester.tap(key('text-edit-cancel'));
    await tester.pumpAndSettle();
    // A caption of two lines keeps its line break in the editor.
    await tapInTextWindow(tester, 'year taught me.');
    await tester.pumpAndSettle();
    await tester.tap(key('text-edit'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(key('text-edit-field')).controller!.text,
        'That is what the first\nyear taught me.');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(s.editor.canUndo, isFalse);
  });

  testWidgets('desktop: Shift-click selects several; Delete captions is one '
      'undo step', (tester) async {
    await open(tester, const Size(1280, 800));
    await openText(tester);
    final s = session(tester);
    await tapInTextWindow(tester, 'And what did they say?');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tapInTextWindow(tester, 'So you added salt.');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(panel(tester).selectedIds, {'c4', 'c5', 'c6'});
    expect(find.textContaining('3 captions · '), findsOneWidget);
    // Several: no Edit.
    expect(key('text-edit'), findsNothing);
    await tester.tap(key('text-delete'));
    await tester.pumpAndSettle();
    expect(s.project.titles.where((t) => t.kind == TitleKind.caption).length, 37);
    expect(s.editor.history.last.label, 'Deleted 3 captions');
    expect(s.editor.history.length, 1);
    expect(key('text-selection-bar'), findsNothing);
    // The message offers Undo.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.project.titles.where((t) => t.kind == TitleKind.caption).length, 40);

    // The Delete key with several selected takes them all, too.
    await tapInTextWindow(tester, 'And what did they say?');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tapInTextWindow(tester, 'They said it needed salt.');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(s.project.titles.where((t) => t.kind == TitleKind.caption).length, 38);
    expect(s.editor.history.last.label, 'Deleted 2 captions');
    // One: "Deleted caption …".
    await tapInTextWindow(tester, 'So you added salt.');
    await tester.pumpAndSettle();
    await tester.tap(key('text-delete'));
    await tester.pumpAndSettle();
    expect(s.editor.history.last.label, "Deleted caption 'Sam: So you added s…'");
  });

  testWidgets('desktop: "Cut this part out of the video" says what goes, '
      'asks, cuts in one step and logs it', (tester) async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'});
    await open(tester, const Size(1280, 800), speech: speech);
    await openText(tester);
    final s = session(tester);
    final length = s.project.durationMs;
    await tapInTextWindow(tester, 'And what did they say?');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tapInTextWindow(tester, 'They said it needed salt.');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    // c4: 6800-8300, c5: 8400-9900.
    await tester.tap(key('text-cut'));
    await tester.pumpAndSettle();
    expect(key('text-cut-dialog'), findsOneWidget);
    expect(tester.widget<Text>(key('text-cut-what')).data,
        'From 0:06.8 to 0:09.9: 3.1 s of the picture and its sound will be removed.');
    expect(find.textContaining('“And what did they say? They said it needed salt.”'),
        findsOneWidget);
    expect(find.textContaining('Automatic cuts'), findsOneWidget);
    // Cancel: nothing happens.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.project.durationMs, length);
    expect(s.editor.canUndo, isFalse);

    await tester.tap(key('text-cut'));
    await tester.pumpAndSettle();
    await tester.tap(key('text-cut-go'));
    await tester.pumpAndSettle();
    expect(s.project.durationMs, length - 3100);
    expect(s.project.clips.map((c) => (c.inMs, c.outMs)),
        [(0, 6800), (9900, length)]);
    expect(s.project.titles.any((t) => t.id == 'c4' || t.id == 'c5'), isFalse);
    final cut = s.project.autoCuts.single;
    expect((cut.kind, cut.startMs, cut.endMs), ('text', 6800, 9900));
    expect(cut.word, 'And what did they say? They said it nee…');
    expect(s.editor.history.single.label, 'Cut a part out of the video');
    expect(find.textContaining('Cut 3.1 s out of the video.'), findsOneWidget);
    s.editor.undo();
    await tester.pumpAndSettle();
    expect(s.project.durationMs, length);
    expect(s.project.autoCuts, isEmpty);
    expect(textWindowBody('And what did they say? They said'), findsOneWidget);
  });

  testWidgets('desktop: copy all text, with or without times and names; save '
      'as a text file and as subtitles', (tester) async {
    final fakes = await open(tester, const Size(1280, 800),
        project: podcast(count: 6));
    final copied = catchClipboard(tester);
    await openText(tester);
    Future<void> menu(String item) async {
      await tester.tap(key('text-menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    await menu('Copy all text');
    expect(copied.single,
        "it's okay to have a plan and then throw it away. That is what the "
        'first year taught me. We baked the same loaf forty times\n\n'
        'before anyone outside the family tasted it. And what did they say? '
        'They said it needed salt.\n');
    await menu('Copy with times and names');
    expect(copied.last, startsWith("[0:00] Sam: it's okay to have"));
    expect(copied.last, contains('\n\n[0:05] Dana: before anyone'));
    await menu('Save as text file…');
    expect(fakes.documents.savedTexts['Bread talk.txt'], copied.last);
    expect(find.textContaining('Text saved: /out/Bread talk.txt'), findsOneWidget);
    await menu('Export subtitles (.srt)…');
    expect(fakes.documents.savedTexts['Bread talk.srt'],
        contains('00:00:00,400 --> 00:00:01,900'));
  });

  testWidgets('desktop: at the right or under the preview, resizable, '
      'remembered', (tester) async {
    final fakes = await open(tester, const Size(1600, 900));
    await openText(tester);
    final s = session(tester);
    expect(tester.getSize(key('text-panel')).width, kTextDefaultWidth);
    // At the right edge of the window, the timeline under everything.
    expect(tester.getTopRight(key('text-panel')).dx, 1600);
    // Drag the edge to the left: wider. To the right: never under 420.
    await tester.drag(key('text-size-handle'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(key('text-panel')).width, kTextDefaultWidth + 200);
    expect(fakes.prefs.texts[kTextWidthText], '660');
    await tester.drag(key('text-size-handle'), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(key('text-panel')).width, kTextMinWidth);
    expect(textWindowBody("it's okay to have"), findsWidgets);

    // Under the preview.
    await tester.tap(key('text-menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        CheckedPopupMenuItem<String>, 'Show under the preview'));
    await tester.pumpAndSettle();
    expect(s.textDock.value, TextDock.below);
    expect(fakes.prefs.texts[kTextDockText], 'below');
    final text = tester.getRect(key('text-panel'));
    final preview = tester.getRect(find.byType(PreviewView));
    expect(text.top, greaterThan(preview.bottom));
    expect(text.left, preview.left);
    expect(text.height, kTextDefaultHeight);
    expect(text.width, greaterThan(800));
    expect(preview.height, greaterThan(120));
    await fakes.screenshot(tester, 'text_window_desktop_below');
    await tester.drag(key('text-size-handle'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.getSize(key('text-panel')).height, kTextDefaultHeight + 60);
    expect(fakes.prefs.texts[kTextHeightText], '340');

    // The next time the editor opens it sits where it was put.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open(tester, const Size(1600, 900), fakes: fakes);
    await openText(tester);
    expect(session(tester).textDock.value, TextDock.below);
    expect(tester.getSize(key('text-panel')).height, 340);
  });

  testWidgets('desktop, a 1000 px window: the window still fits (420 wide)',
      (tester) async {
    final fakes = await open(tester, const Size(1000, 700));
    await openText(tester);
    expect(tester.getSize(key('text-panel')).width, kTextMinWidth);
    expect(textWindowBody("it's okay to have"), findsWidgets);
    await tapInTextWindow(tester, 'That is what the first year taught me.');
    await tester.pumpAndSettle();
    await fakes.screenshot(tester, 'text_window_desktop_narrow');
  });

  testWidgets('desktop: the menus have Text window and Find in the text',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await open(tester, const Size(1280, 800), menuBar: true);
      await tester.tap(find.widgetWithText(SubmenuButton, 'Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Find in the text…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SubmenuButton, 'Text and speech'));
      await tester.pumpAndSettle();
      expect(find.text('Text window'), findsOneWidget);
      await tester.tap(key('menu-text'));
      await tester.pumpAndSettle();
      expect(key('text-panel'), findsOneWidget);
      // Ctrl+Shift+T closes it again.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(key('text-panel'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop: nothing to read yet: how to get text, with buttons',
      (tester) async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'});
    await open(tester, const Size(1280, 800),
        speech: speech, project: podcast(count: 0, title: false));
    await openText(tester);
    expect(key('text-empty'), findsOneWidget);
    expect(find.textContaining('No text yet.'), findsOneWidget);
    expect(key('text-source'), findsNothing);
    expect(key('text-search'), findsNothing);
    expect(key('text-transcribe'), findsOneWidget);
    expect(key('text-import'), findsOneWidget);
    expect(key('text-add-caption'), findsOneWidget);
    // Add a caption from here: it shows up.
    await tester.tap(key('text-add-caption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Sam: hello');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(textWindowBody('hello'), findsOneWidget);
    expect(key('text-empty'), findsNothing);
  });

  testWidgets('desktop: with a transcript too, the switch has Transcript; '
      'the word being spoken is marked', (tester) async {
    const english = 'Welcome back to the show. So today we talk about bread.';
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'})
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, english);
    await open(tester, const Size(1280, 800), speech: speech);
    await openText(tester);
    // Captions first (the project has them).
    expect(panel(tester).source, TextSource.captions);
    expect(key('text-source-transcript'), findsOneWidget);
    await tester.tap(key('text-source-transcript'));
    await tester.pumpAndSettle();
    expect(textWindowBody('Welcome back to the show.'), findsOneWidget);
    // No editing of a transcript.
    await tapInTextWindow(tester, 'So today we talk');
    await tapInTextWindow(tester, 'So today we talk');
    await tester.pumpAndSettle();
    expect(key('text-edit-field'), findsNothing);
    expect(key('text-delete'), findsNothing);
    expect(key('text-cut'), findsOneWidget);
    // The word under the playhead has its own background.
    session(tester).playback.seek(2 * 400 + 50); // the third word: "to"
    await tester.pumpAndSettle();
    final body = tester.widget<RichText>(textWindowBody('Welcome back'));
    final marked = <String>[];
    body.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor == const Color(0x807C9BFF)) {
        marked.add(span.text!);
      }
      return true;
    });
    expect(marked, ['to']);
  });

  testWidgets('Hebrew reads right to left, paragraph by paragraph',
      (tester) async {
    expect(textDirectionOf('דנה: שלום'), TextDirection.rtl);
    expect(textDirectionOf('12: hello'), TextDirection.ltr);
    expect(textDirectionOf('123 ...'), TextDirection.ltr);
    final fakes = await open(tester, const Size(1280, 800),
        project: podcast(count: 6, hebrew: true));
    await openText(tester);
    final body = tester.widget<RichText>(textWindowBody('היום נדבר על לחם.').first);
    expect(body.textDirection, TextDirection.rtl);
    expect(find.text('דנה'), findsWidgets);
    // The time is on the right, the text to its left.
    final time = tester.getRect(find.descendant(
        of: key('text-panel'), matching: find.text('0:00')));
    expect(time.left, greaterThan(tester.getRect(textWindowBody('היום').first).right));
    await fakes.screenshot(tester, 'text_window_desktop_hebrew');
  });

  testWidgets('phone: More > Text is a full-screen sheet: read, search, tap '
      'to jump, edit a caption', (tester) async {
    final fakes = await open(tester, phone);
    expect(key('text-button'), findsNothing);
    // Text has its own button in the tool bar (and is under More too).
    await tester.tap(key('tool-text'));
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsOneWidget);
    final size = tester.getSize(key('text-panel'));
    expect(size.width, phone.width);
    expect(size.height, greaterThan(phone.height * 0.85));
    expect(textWindowBody("it's okay to have"), findsWidgets);
    expect(key('text-play'), findsOneWidget);
    await fakes.screenshot(tester, 'text_window_phone');
    final s = session(tester);
    // Tap to jump; the sheet stays.
    await tapInTextWindow(tester, 'They said it needed salt.');
    await tester.pumpAndSettle();
    expect(s.playback.positionMs, 8400);
    expect(key('text-panel'), findsOneWidget);
    // Edit, Delete; no cutting of the video from a phone.
    expect(key('text-edit'), findsOneWidget);
    expect(key('text-delete'), findsOneWidget);
    expect(key('text-cut'), findsNothing);
    await tester.tap(key('text-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(key('text-edit-field'), 'They said it needed sugar.');
    await tester.tap(key('text-edit-save'));
    await tester.pumpAndSettle();
    expect(s.project.titles.firstWhere((t) => t.id == 'c5').text,
        'They said it needed sugar.');
    expect(s.editor.history.single.label, "Edited caption 'They said it needed…'");
    // Search.
    await tester.enterText(key('text-search'), 'sugar');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('text-match-count')).data, '1 of 1');
    await fakes.screenshot(tester, 'text_window_phone_search');
    await tester.tap(key('text-close'));
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsNothing);
  });

  testWidgets('1500 captions, 40 minutes: only what is in view is built, '
      'jumping to the end is immediate', (tester) async {
    final big = podcast(count: 1500);
    expect(big.durationMs, greaterThan(40 * 60 * 1000));
    await open(tester, const Size(1280, 800), project: big);
    final watch = Stopwatch()..start();
    final before = TextPanel.debugParagraphBuilds;
    await openText(tester);
    final opened = watch.elapsedMilliseconds;
    final built = TextPanel.debugParagraphBuilds - before;
    final doc = panel(tester).document;
    expect(doc.lines.length, 1500);
    expect(doc.paragraphs.length, 500);
    expect(built, lessThan(40), reason: '$built paragraphs were built');
    expect(opened, lessThan(5000), reason: 'opening took $opened ms');
    // The whole document has a height, although little of it was built.
    final tops = panel(tester).debugTops;
    expect(tops.length, 501);
    expect(tops.last, greaterThan(500 * 40));

    // Playing near the end: the window is there in one step.
    final s = session(tester);
    watch.reset();
    final mid = TextPanel.debugParagraphBuilds;
    s.playback.seek(big.titles[1490].startMs + 10);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final jumped = watch.elapsedMilliseconds;
    expect(scrollOf(tester), greaterThan(tops[480]));
    expect(TextPanel.debugParagraphBuilds - mid, lessThan(80));
    expect(jumped, lessThan(2000), reason: 'jumping took $jumped ms');
    // A new position inside the same view builds next to nothing.
    final still = TextPanel.debugParagraphBuilds;
    s.playback.seek(big.titles[1491].startMs + 10);
    await tester.pump();
    expect(TextPanel.debugParagraphBuilds - still, lessThan(30));
    // Search over everything.
    watch.reset();
    await tester.enterText(key('text-search'), 'salt');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('text-match-count')).data, endsWith(' of 600'));
    expect(watch.elapsedMilliseconds, lessThan(3000));
    // Fixing one caption measures one paragraph again, not 500.
    await tester.enterText(key('text-search'), '');
    await tester.pumpAndSettle();
    watch.reset();
    s.editor.updateTitle(big.titles[1490].copyWith(text: 'A fixed word.'));
    await tester.pump();
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });
}
