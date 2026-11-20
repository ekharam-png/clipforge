// "Send feedback" (1.16) as the user sees it: where it is (Help menu on
// computers, the three dots on phones, About, Help, Settings, the message
// of an update that did not work), the box that shows exactly what is
// sent, the draft that is kept, the answers (sent, not sent with the two
// other ways), the local limit, and the outside addresses a latest.json
// can change.

@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/feedback/feedback.dart';
import 'package:clipforge/core/links.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/feedback/feedback_screen.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:clipforge/ui/links.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:clipforge/ui/update/update_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

final ci160 = BuildInfo.fromValues(
  version: '1.16.0',
  buildNumber: '160',
  buildTime: '2026-11-20T07:20:00Z',
  commit: 'abc1234',
  channel: 'ci',
);

const k = ValueKey.new;

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

Future<Fakes> home(WidgetTester tester, Size size, {Fakes? fakes}) async {
  useScreen(tester, size);
  final f = (fakes ?? Fakes(projects: [sampleProject()]))..buildInfo = ci160;
  await tester.pumpWidget(f.app(const HomeScreen()));
  await tester.pumpAndSettle();
  return f;
}

/// Opens the page straight from the project list.
Future<void> open(WidgetTester tester,
    {bool updateFailed = false, String? problem}) async {
  openFeedback(tester.element(find.byType(HomeScreen)),
      updateFailed: updateFailed, problem: problem);
  await tester.pumpAndSettle();
}

Future<void> write(WidgetTester tester, String message, {String? email}) async {
  await tester.enterText(find.byKey(k('feedback-message')), message);
  if (email != null) {
    await tester.enterText(find.byKey(k('feedback-email')), email);
  }
  await tester.pump();
}

Future<void> pressSend(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(k('feedback-send')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(k('feedback-send')));
  await tester.pumpAndSettle();
}

/// The text of one row of the "What is sent" box.
String sent(WidgetTester tester, String row) =>
    tester.widget<Text>(find.byKey(ValueKey('feedback-sent-$row'))).data!;

Future<void> closePage(WidgetTester tester) async {
  final close = find.byTooltip('Close');
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
  } else {
    await tester.pageBack();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('computer: Help > Send feedback… opens the window; Send posts what the box shows',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()])..buildInfo = ci160;
      await tester.pumpWidget(fakes.app(const HomeScreen(),
          menuBar: true,
          help: HelpMenuActions(
            openHelp: () {},
            showTour: () {},
            sendFeedback: () =>
                openFeedback(tester.element(find.byType(HomeScreen))),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('Send feedback…'), findsOneWidget);
      await tester.tap(find.byKey(k('menu-send-feedback')));
      await tester.pumpAndSettle();
      expect(find.byKey(k('feedback-dialog')), findsOneWidget);
      // The four kinds, by these names.
      for (final label in ['Problem', 'Idea', 'Praise', 'Question']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      // Before anything is written the box already says what would go.
      expect(sent(tester, 'kind'), 'Idea');
      expect(sent(tester, 'message'), '(nothing written yet)');
      expect(sent(tester, 'email'), 'not included');
      expect(sent(tester, 'version'), '1.16.0 (build 160)');
      expect(sent(tester, 'system'), 'TestOS 1.0, test_x64');
      final never = tester.widget<Text>(find.byKey(k('feedback-never-included'))).data!;
      expect(never, contains('only when you press Send'));
      expect(never, contains('Nothing about your projects, file names, videos, photos or music is ever included'));
      expect(never, contains(Uri.parse(AppLinks.builtIn.feedbackApi).host));

      await tester.tap(find.byKey(k('feedback-kind-problem')));
      await write(tester, 'The export stopped at 40%.', email: 'me@example.org');
      expect(sent(tester, 'kind'), 'Problem');
      expect(sent(tester, 'message'), 'The export stopped at 40%.');
      expect(sent(tester, 'email'), 'me@example.org');
      await fakes.screenshot(tester, 'feedback_desktop');
      // Nothing has been sent by writing.
      expect(fakes.feedbackPosts, isEmpty);

      await pressSend(tester);
      expect(fakes.feedbackPosts.length, 1);
      final post = fakes.feedbackPosts.single;
      expect(post.api.toString(), AppLinks.builtIn.feedbackApi);
      expect(post.payload, {
        'v': 1,
        'kind': 'problem',
        'message': 'The export stopped at 40%.',
        'email': 'me@example.org',
        'app': {'version': '1.16.0', 'build': '160', 'os': 'TestOS 1.0, test_x64'},
        'source': 'app',
      });
      expect(find.text('Sent. Thank you!'), findsOneWidget);
      expect(find.textContaining('it will come by e-mail'), findsOneWidget);
      // The draft is gone once it was sent.
      expect(fakes.prefs.texts[kFeedbackDraftText], isNull);
      await tester.tap(find.byKey(k('feedback-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(k('feedback-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone: the three dots > Send feedback opens a page that fits',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final fakes = await home(tester, const Size(360, 760));
      await tester.tap(find.byKey(k('home-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(k('home-more-feedback')));
      await tester.pumpAndSettle();
      expect(find.byKey(k('feedback-page')), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Send feedback'), findsOneWidget);
      await write(tester, 'Thank you for the captions!');
      await tester.tap(find.byKey(k('feedback-kind-praise')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(k('feedback-what-is-sent')));
      await tester.pumpAndSettle();
      expect(sent(tester, 'kind'), 'Praise');
      expect(sent(tester, 'message'), 'Thank you for the captions!');
      expect(tester.takeException(), isNull, reason: 'nothing overflows at 360 wide');
      await fakes.screenshot(tester, 'feedback_phone');
      await pressSend(tester);
      expect(fakes.feedbackPosts.single.payload['kind'], 'praise');
      expect(fakes.feedbackPosts.single.payload.containsKey('email'), isFalse);
      expect(find.text('Sent. Thank you!'), findsOneWidget);
      expect(find.textContaining('it will come by e-mail'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone: the project menu in the editor has Send feedback',
      (tester) async {
    await openEditor(tester, const Size(360, 760));
    await tester.tap(find.byKey(k('project-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(k('project-menu-feedback')));
    await tester.tap(find.byKey(k('project-menu-feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(k('feedback-page')), findsOneWidget);
  });

  testWidgets('About, Help and Settings have a Send feedback link; About shows the website',
      (tester) async {
    final fakes = await home(tester, desktop);
    // About.
    await tester.tap(find.byKey(k('version-line')));
    await tester.pumpAndSettle();
    expect(find.text(AppLinks.builtIn.siteLabel), findsOneWidget);
    await tester.tap(find.byKey(k('about-website')));
    await tester.pumpAndSettle();
    expect(fakes.updatePlatform.opened, [AppLinks.builtIn.site]);
    await tester.tap(find.byKey(k('about-send-feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(k('about-dialog')), findsNothing);
    expect(find.byKey(k('feedback-dialog')), findsOneWidget);
    await closePage(tester);
    // Help (the footer of the topic list).
    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(k('help-send-feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(k('feedback-dialog')), findsOneWidget);
    await closePage(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the draft is kept when the page is closed, and comes back',
      (tester) async {
    final fakes = await home(tester, desktop);
    await open(tester);
    await tester.tap(find.byKey(k('feedback-kind-question')));
    await write(tester, 'Is there an iPhone version?', email: 'ask@example.org');
    await closePage(tester);
    expect(fakes.feedbackPosts, isEmpty, reason: 'closing never sends');
    final kept = FeedbackDraft.decode(fakes.prefs.texts[kFeedbackDraftText])!;
    expect((kept.kind, kept.message, kept.email),
        (FeedbackKind.question, 'Is there an iPhone version?', 'ask@example.org'));

    await open(tester);
    expect(find.text('Is there an iPhone version?'), findsWidgets);
    expect(sent(tester, 'kind'), 'Question');
    expect(sent(tester, 'email'), 'ask@example.org');
    // Emptied by hand: nothing is kept.
    await write(tester, '', email: '');
    await closePage(tester);
    expect(fakes.prefs.texts[kFeedbackDraftText], isNull);
  });

  testWidgets('nothing written, or a wrong address: said on the page, nothing is sent',
      (tester) async {
    final fakes = await home(tester, desktop);
    await open(tester);
    await pressSend(tester);
    expect(find.text('Please write a message first.'), findsOneWidget);
    expect(find.byKey(k('feedback-open-page')), findsNothing);
    await write(tester, 'Hello', email: 'not an address');
    await pressSend(tester);
    expect(find.textContaining('e-mail address does not look right'), findsOneWidget);
    expect(fakes.feedbackPosts, isEmpty);
  });

  for (final (label, answer) in [
    (
      'offline',
      const FeedbackOutcome('offline',
          'The message could not be sent: ClipForge could not reach the feedback service. Check the internet connection and try again.')
    ),
    (
      'the website cannot pass it on',
      const FeedbackOutcome('failed',
          'The message could not be sent just now. Please try again later.',
          status: 502)
    ),
  ]) {
    testWidgets('not sent ($label): a plain message, the page in the browser, Copy my message',
        (tester) async {
      final copied = catchClipboard(tester);
      final fakes = await home(tester, desktop);
      fakes.feedbackAnswer = answer;
      fakes.updatePlatform.os = 'windows';
      await open(tester);
      await tester.tap(find.byKey(k('feedback-kind-problem')));
      await write(tester, 'The export stopped.', email: 'me@example.org');
      await pressSend(tester);
      expect(fakes.feedbackPosts.length, 1);
      expect(tester.widget<Text>(find.byKey(k('feedback-problem'))).data, answer.message);
      expect(find.text('Sent. Thank you!'), findsNothing);
      // Still one request: nothing is tried again by itself.
      await tester.pump(const Duration(seconds: 30));
      expect(fakes.feedbackPosts.length, 1);
      // The message is still there and still kept.
      expect(find.text('The export stopped.'), findsWidgets);
      expect(FeedbackDraft.decode(fakes.prefs.texts[kFeedbackDraftText])!.message,
          'The export stopped.');

      await tester.ensureVisible(find.byKey(k('feedback-open-page')));
      await tester.pumpAndSettle();
      expect(find.text('Open the feedback page in the browser'), findsOneWidget);
      await tester.tap(find.byKey(k('feedback-open-page')));
      await tester.pumpAndSettle();
      final opened = Uri.parse(fakes.updatePlatform.opened.single);
      expect('${opened.origin}${opened.path}', AppLinks.builtIn.feedbackPage);
      expect(opened.queryParameters, {
        'source': 'app',
        'kind': 'problem',
        'version': '1.16.0 (build 160)',
        'os': 'Windows',
      });
      // Neither the message nor the address travels in the page's address.
      expect(opened.toString(), isNot(contains('stopped')));
      expect(opened.toString(), isNot(contains('example.org')));

      await tester.tap(find.byKey(k('feedback-copy')));
      await tester.pumpAndSettle();
      expect(copied.single, 'The export stopped.');
      expect(find.textContaining('Message copied'), findsOneWidget);
    });
  }

  testWidgets('refused by the website: its words are shown', (tester) async {
    final fakes = await home(tester, desktop);
    fakes.feedbackAnswer = const FeedbackOutcome('refused',
        'That is a lot of messages in a short time. Please wait ten minutes and try again.',
        status: 429);
    await open(tester);
    await write(tester, 'Hello');
    await pressSend(tester);
    expect(find.textContaining('That is a lot of messages'), findsOneWidget);
    expect(find.byKey(k('feedback-open-page')), findsOneWidget);
  });

  testWidgets('at most 5 messages in 10 minutes from this device', (tester) async {
    final fakes = await home(tester, desktop);
    for (var i = 1; i <= kFeedbackMaxPerWindow; i++) {
      await open(tester);
      await write(tester, 'Message $i');
      await pressSend(tester);
      expect(find.text('Sent. Thank you!'), findsOneWidget, reason: 'message $i');
      await tester.tap(find.byKey(k('feedback-close')));
      await tester.pumpAndSettle();
    }
    expect(fakes.feedbackPosts.length, 5);
    await open(tester);
    await write(tester, 'Message 6');
    await pressSend(tester);
    expect(fakes.feedbackPosts.length, 5, reason: 'the sixth is not sent');
    expect(tester.widget<Text>(find.byKey(k('feedback-problem'))).data,
        startsWith('You have sent 5 messages in the last 10 minutes. Please wait about'));
    expect(find.text('Sent. Thank you!'), findsNothing);
    // What was written is not lost.
    await closePage(tester);
    expect(FeedbackDraft.decode(fakes.prefs.texts[kFeedbackDraftText])!.message, 'Message 6');
    // Sends that are older than ten minutes no longer count.
    final old = DateTime.now().subtract(const Duration(minutes: 11)).millisecondsSinceEpoch;
    fakes.prefs.texts[kFeedbackSentText] = List.filled(5, old).join(',');
    await open(tester);
    await pressSend(tester);
    expect(fakes.feedbackPosts.length, 6);
    // An attempt that never reached the website does not count.
    fakes.prefs.texts.remove(kFeedbackSentText);
    fakes.feedbackAnswer = const FeedbackOutcome('offline', 'No connection.');
    await tester.tap(find.byKey(k('feedback-close')));
    await tester.pumpAndSettle();
    await open(tester);
    await write(tester, 'Offline');
    await pressSend(tester);
    expect(fakes.prefs.texts[kFeedbackSentText], isNull);
  });

  group('an update that did not work', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('clipforge_feedback_ui');
      addTearDown(() => tmp.deleteSync(recursive: true));
    });

    Fakes withLog() {
      final fakes = Fakes(projects: [sampleProject()]);
      fakes.updatePlatform.dir = tmp.path;
      final state = Directory('${tmp.path}/state')..createSync(recursive: true);
      File('${state.path}/update-log.txt').writeAsStringSync([
        for (var i = 1; i <= 20; i++) '2026-11-20 10:00:${i.toString().padLeft(2, '0')} script: step $i',
      ].join('\r\n'));
      return fakes;
    }

    testWidgets('the tick box for the last update log lines is off, shows the lines, and adds them only when ticked',
        (tester) async {
      final fakes = await home(tester, desktop, fakes: withLog());
      await open(tester, updateFailed: true, problem: 'the folder could not be changed');
      // Opened from the update message: a problem, with the reason as a start.
      expect(sent(tester, 'kind'), 'Problem');
      expect(sent(tester, 'message'), 'The update did not work: the folder could not be changed');
      final box = find.byKey(k('feedback-include-log'));
      expect(box, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      expect(find.text('Include the last update log lines'), findsOneWidget);
      expect(sent(tester, 'message'), isNot(contains('script: step')));

      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pumpAndSettle();
      final shown = sent(tester, 'message');
      expect(shown, contains(kFeedbackLogHeading));
      expect(shown, contains('script: step 20'));
      expect(shown, contains('script: step 9'));
      expect(shown, isNot(contains('script: step 8\n')), reason: 'only the last $kFeedbackLogLines lines');
      await pressSend(tester);
      // What was sent is what the box showed.
      expect(fakes.feedbackPosts.single.payload['message'], shown);
      expect(fakes.feedbackPosts.single.payload['kind'], 'problem');
    });

    testWidgets('not ticked: the log lines are not sent; the ordinary page has no such box',
        (tester) async {
      final fakes = await home(tester, desktop, fakes: withLog());
      await open(tester, updateFailed: true, problem: 'it stopped');
      await pressSend(tester);
      expect(fakes.feedbackPosts.single.payload['message'], 'The update did not work: it stopped');
      await tester.tap(find.byKey(k('feedback-close')));
      await tester.pumpAndSettle();
      await open(tester);
      expect(find.byKey(k('feedback-include-log')), findsNothing);
    });

    testWidgets('"The update was not installed" has Send feedback', (tester) async {
      final fakes = await home(tester, desktop, fakes: withLog());
      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(updateControllerProvider);
      c.lastResult = UpdateResult('failed', 'The folder could not be changed.', '1.16.1');
      showUpdateOutcome(tester.element(find.byType(HomeScreen)), c);
      await tester.pumpAndSettle();
      expect(find.byKey(k('update-failed-dialog')), findsOneWidget);
      await tester.tap(find.byKey(k('update-failed-feedback')));
      await tester.pumpAndSettle();
      expect(find.byKey(k('feedback-dialog')), findsOneWidget);
      expect(find.byKey(k('feedback-include-log')), findsOneWidget);
      expect(sent(tester, 'message'), 'The update did not work: The folder could not be changed');
      expect(fakes.feedbackPosts, isEmpty);
    });
  });

  group('the outside addresses', () {
    const moved = {
      'site': 'https://newname.example',
      'download': 'https://newname.example/get',
      'feedback_api': 'https://newname.example/api/feedback',
      'feedback_page': 'https://newname.example/feedback',
      'help': 'https://newname.example/help',
      'privacy': 'https://newname.example/privacy',
    };
    UpdateInfo release({Map<String, String>? links}) =>
        UpdateInfo(version: '1.17.0', build: 170, links: links);

    testWidgets('an update check that carries new addresses: remembered and used at once',
        (tester) async {
      final fakes = Fakes(projects: [sampleProject()])..latest = release(links: moved);
      await home(tester, desktop, fakes: fakes);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      final updates = container.read(updateControllerProvider);
      updates.check(manual: true);
      await tester.pumpAndSettle();
      expect(container.read(linksProvider).current.toJson(), moved);
      final kept = jsonDecode(fakes.prefs.texts[kLinksSeenText]!) as Map;
      expect(kept['v'], '1.16.0');
      expect(kept['links'], moved);

      // The download page, the website in About and the feedback address follow.
      updates.openDownloadPage();
      await tester.pumpAndSettle();
      expect(fakes.updatePlatform.opened, ['https://newname.example/get']);
      await tester.tap(find.byKey(k('version-line')));
      await tester.pumpAndSettle();
      expect(find.text('newname.example'), findsOneWidget);
      await tester.tap(find.byKey(k('about-send-feedback')));
      await tester.pumpAndSettle();
      await write(tester, 'Hello');
      expect(tester.widget<Text>(find.byKey(k('feedback-never-included'))).data,
          contains('newname.example'));
      await pressSend(tester);
      expect(fakes.feedbackPosts.single.api.toString(), 'https://newname.example/api/feedback');

      // A later release without "links" changes nothing.
      fakes.latest = release();
      updates.check(manual: true);
      await tester.pumpAndSettle();
      expect(container.read(linksProvider).current.toJson(), moved);
    });

    testWidgets('addresses that fail the checks are ignored (feedback never goes to a foreign host)',
        (tester) async {
      final fakes = Fakes(projects: [sampleProject()])
        ..latest = release(links: {
          'download': 'http://insecure.example/get',
          'feedback_api': 'https://collector.example/api/feedback',
          'help': 'https://newname.example/help',
        });
      await home(tester, desktop, fakes: fakes);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      container.read(updateControllerProvider).check(manual: true);
      await tester.pumpAndSettle();
      final now = container.read(linksProvider).current;
      expect(now.download, AppLinks.builtIn.download);
      expect(now.feedbackApi, AppLinks.builtIn.feedbackApi);
      expect(now.help, 'https://newname.example/help');
    });

    test('what was remembered is used at the next start, by the same version only', () async {
      final prefs = MemoryAppPrefs()
        ..texts[kLinksSeenText] = jsonEncode({'v': '1.16.0', 'links': moved});
      var links = LinksController(prefs: prefs, build: ci160);
      expect(links.current, AppLinks.builtIn, reason: 'before it is read');
      expect((await links.ready()).toJson(), moved);

      // A newer version starts from its own built-in addresses.
      links = LinksController(
          prefs: prefs,
          build: BuildInfo.fromValues(version: '1.17.0', buildNumber: '170'));
      expect(await links.ready(), AppLinks.builtIn);

      // Damaged or tampered notes are no addresses.
      for (final text in [
        '{nonsense',
        '[]',
        jsonEncode({'v': '1.16.0', 'links': 'x'}),
        jsonEncode({'v': '1.16.0', 'links': {'feedback_api': 'https://collector.example/api'}}),
      ]) {
        prefs.texts[kLinksSeenText] = text;
        links = LinksController(prefs: prefs, build: ci160);
        expect(await links.ready(), AppLinks.builtIn, reason: text);
      }
    });
  });

  test('Claude has no tool that sends feedback', () {
    // Claude must not send e-mail on its own: no tool of the helper has
    // "feedback" in its name, and nothing under lib/mcp uses the sender.
    for (final file in Directory('lib/mcp').listSync(recursive: true).whereType<File>()) {
      final text = file.readAsStringSync();
      expect(text.contains('sendFeedback') || text.contains("feedback/feedback.dart"), isFalse,
          reason: file.path);
      expect(RegExp(r'''name:\s*['"][a-z_]*feedback[a-z_]*['"]''').hasMatch(text), isFalse,
          reason: file.path);
    }
  });
}
