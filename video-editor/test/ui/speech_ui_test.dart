// 1.11 speech-to-text in the editor. Computers only: with no speech
// service (what a phone has) nothing about it is on screen; with one, the
// Transcribe dialog (language packs: sizes shown first, nothing downloads
// without a click, Remove, space used), Captions from speech, Remove
// filler words and the read-only Transcript column. Overflow errors fail
// these tests by themselves.
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/jump_check.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/speech/speech_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// An engine that "looks at the picture" around cuts.
class JumpEngine extends FakeMediaEngine implements JumpCheckEngine {
  double Function(int beforeMs) scoreAt = (_) => 0;

  @override
  Future<List<double?>> jumpScores(
          String path, List<({int beforeMs, int afterMs})> cuts) async =>
      [for (final c in cuts) scoreAt(c.beforeMs)];
}

class JumpFakes extends Fakes {
  JumpFakes({super.projects}) : super(missing: const {});
  final JumpEngine _engine = JumpEngine();

  // ignore: overridden_fields
  @override
  JumpEngine get engine => _engine;
}

const talkPath = '/media/talk.mp4';
const english = 'Welcome back to the show. So um today we talk about bread. '
    'First you need flour, uh water, salt and like a lot of patience. '
    'Then you wait.';
const hebrew = 'שלום חברים, ברוכים הבאים! היום נדבר על לחם. '
    'קודם צריך קמח, מים ומלח.';

Project talk() => Project(
      id: 'p1',
      name: 'Podcast',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
      aspect: CanvasAspect.landscape16x9,
      clips: [videoClip('a', talkPath, 0, 20000)],
    );

Future<Fakes> open(WidgetTester tester, Size size,
    {FakeSpeech? speech, bool menuBar = false, Project? project}) async {
  useScreen(tester, size);
  final fakes = Fakes(projects: [project ?? talk()], missing: const {})
    ..speech = speech;
  await tester.pumpWidget(
      fakes.app(const EditorScreen(projectId: 'p1'), menuBar: menuBar));
  await tester.pumpAndSettle();
  return fakes;
}

Future<void> selectClip(WidgetTester tester) async {
  await tester.tapAt(tester.getTopLeft(block('clip-a')) + const Offset(20, 20));
  await tester.pumpAndSettle();
}

/// The project as the open editor has it now.
Project now(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session.project;

/// Runs [body] as on a Windows computer (the menu bar in the window).
Future<void> onWindows(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  setUpAll(loadFonts);

  test('speech-to-text exists on computers only', () {
    for (final os in ['windows', 'macos', 'linux']) {
      expect(speechSupportedOn(os), isTrue);
    }
    for (final os in ['android', 'ios', 'fuchsia']) {
      expect(speechSupportedOn(os), isFalse);
    }
  });

  for (final size in [phone, desktop]) {
    final name = size == phone ? 'phone' : 'desktop';
    testWidgets('$name without a speech service: nothing about speech',
        (tester) async {
      await open(tester, size);
      await selectClip(tester);
      await openClipTool(tester, size, 'Sound');
      expect(find.text('Clean up sound'), findsOneWidget);
      expect(find.textContaining('Transcribe'), findsNothing);
      expect(key('speech-row'), findsNothing);
      await closeSheet(tester, size);
      if (size == phone) {
        await tester.tap(find.text('More').last);
        await tester.pumpAndSettle();
        expect(find.text('History'), findsOneWidget);
        expect(find.textContaining('Transcri'), findsNothing);
        expect(find.textContaining('filler'), findsNothing);
      }
    });
  }

  testWidgets('the Text and speech menu has the speech items only with a speech service',
      (tester) async {
    await onWindows(() async {
      await open(tester, desktop, menuBar: true);
      await tester.tap(find.widgetWithText(SubmenuButton, 'Text and speech'));
      await tester.pumpAndSettle();
      expect(find.text('Text window'), findsOneWidget);
      expect(find.textContaining('Transcribe speech'), findsNothing);
      await tester.tapAt(const Offset(900, 500));
      await tester.pumpAndSettle();

      final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'});
      await open(tester, desktop, speech: speech, menuBar: true);
      await tester.tap(find.widgetWithText(SubmenuButton, 'Text and speech'));
      await tester.pumpAndSettle();
      expect(find.text('Transcribe speech…'), findsOneWidget);
      expect(find.text('Captions from speech…'), findsOneWidget);
      expect(find.text('Remove filler words…'), findsOneWidget);
      // The Transcript is a source of the Text window now (one place).
      expect(find.text('Transcript'), findsNothing);
      MenuItemButton item(String k) => tester.widget<MenuItemButton>(key(k));
      expect(item('menu-transcribe').onPressed, isNotNull);
      // Nothing transcribed: it asks to transcribe first.
      await tester.tap(key('menu-fillers'));
      await tester.pumpAndSettle();
      expect(key('speech-needed'), findsOneWidget);
      expect(find.textContaining('has to be transcribed first'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(key('fillers-dialog'), findsNothing);
    });
  });

  testWidgets('desktop: no speech program gives a plain explanation',
      (tester) async {
    final speech = FakeSpeech(backend: null);
    await open(tester, desktop, speech: speech);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('transcribe-button'));
    await tester.tap(key('transcribe-button'));
    await tester.pumpAndSettle();
    expect(key('transcribe-dialog'), findsOneWidget);
    expect(key('transcribe-nothing'), findsOneWidget);
    expect(find.textContaining('needs a speech program'), findsOneWidget);
    expect(find.textContaining('winget install ffmpeg'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('transcribe-go')).onPressed, isNull);
    expect(key('pack-small'), findsNothing);
  });

  testWidgets('desktop: packs show their size first, download only on a '
      'click, then transcribe; the Transcript column; remove a pack',
      (tester) async {
    final speech = FakeSpeech()
      ..hears[talkPath] = spokenTranscript(talkPath, english);
    final fakes = await open(tester, desktop, speech: speech);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('transcribe-button'));
    await tester.tap(key('transcribe-button'));
    await tester.pumpAndSettle();
    expect(find.text('The sound of talk.mp4'), findsOneWidget);
    expect(find.textContaining('Uses: FFmpeg on this computer'), findsOneWidget);
    // English: three sizes, none preselected, nothing fetched.
    await tester.tap(key('transcribe-language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Small · about 140 MB'), findsOneWidget);
    expect(find.text('Medium · about 470 MB'), findsOneWidget);
    expect(find.text('Large · about 1.6 GB'), findsOneWidget);
    expect(find.text('quick, more mistakes · English only'), findsOneWidget);
    expect(find.text('best, large download · all languages, shared'), findsOneWidget);
    expect(find.text('No packs on this computer yet.'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(3));
    expect(speech.downloadsStarted, isEmpty);
    expect(tester.widget<FilledButton>(key('transcribe-go')).onPressed, isNull);
    await fakes.screenshot(tester, 'editor_desktop_transcribe_packs');

    // Russian shares the all-languages files; Hebrew is told honestly.
    await tester.tap(key('transcribe-language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hebrew').last);
    await tester.pumpAndSettle();
    expect(find.text('quick, more mistakes · all languages, shared'), findsOneWidget);
    expect(find.textContaining('makes many mistakes in Hebrew'), findsOneWidget);
    await tester.tap(key('transcribe-language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    // Download the small English pack.
    await tester.tap(key('pack-download-small'));
    await tester.pump();
    expect(speech.downloadsStarted, ['base.en']);
    speech.downloadProgress(0.5);
    await tester.pump();
    expect(find.text('71 MB of 142 MB'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_desktop_transcribe_downloading');
    speech.finishDownload();
    await tester.pumpAndSettle();
    expect(key('pack-remove-small'), findsOneWidget);
    expect(find.text('Packs use 148 MB on this computer.'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('transcribe-go')).onPressed, isNotNull);

    // Transcribe: progress, then done.
    speech.instant = false;
    await tester.tap(key('transcribe-go'));
    await tester.pump();
    await tester.pump();
    expect(key('transcribe-progress'), findsOneWidget);
    expect(find.textContaining('Listening to the speech'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    speech.finishTranscribe();
    await tester.pumpAndSettle();
    expect(key('transcribe-dialog'), findsNothing);
    expect(find.textContaining('Speech transcribed: 28 words'), findsOneWidget);
    expect(speech.transcribed, ['$talkPath|en|small']);

    // The Sound panel now offers what follows.
    expect(key('speech-captions-button'), findsOneWidget);
    expect(key('fillers-button'), findsOneWidget);

    // The Text window, showing the transcript (there are no captions).
    await tester.tap(key('text-button'));
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsOneWidget);
    expect(textWindowBody('Welcome back to the show.'), findsOneWidget);
    expect(textWindowBody('Then you wait.'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_desktop_transcript');
    // Click a phrase: the playhead goes there.
    await tapInTextWindow(tester, 'Then you wait.');
    await tester.pumpAndSettle();
    // "Then" is the 26th word: 25 x 400 ms.
    expect(find.textContaining('0:10.0'), findsWidgets);
    // Search: every place is counted and marked; the text stays.
    await tester.enterText(key('text-search'), 'BREAD');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('text-match-count')).data, '1 of 1');
    expect(textWindowBody('Welcome back to the show.'), findsOneWidget);
    await tester.enterText(key('text-search'), 'pizza');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(key('text-match-count')).data, 'Not found');
    // A transcript cannot be edited here: no Edit, no Delete, and the
    // only text field is the search box.
    expect(key('text-edit'), findsNothing);
    expect(key('text-delete'), findsNothing);
    expect(
        find.descendant(of: key('text-panel'), matching: find.byType(TextField)),
        findsOneWidget);

    // Remove the pack again.
    await tester.tap(key('transcribe-button'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already transcribed'), findsOneWidget);
    expect(find.text('Transcribe again'), findsOneWidget);
    await tester.tap(key('pack-remove-small'));
    await tester.pumpAndSettle();
    expect(speech.removed, ['base.en']);
    expect(find.text('No packs on this computer yet.'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(3));
  });

  testWidgets('desktop: a failed download says why; a stored transcript is '
      'read when the project opens', (tester) async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp)
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, english);
    await open(tester, desktop, speech: speech);
    await tester.tap(key('text-button'));
    await tester.pumpAndSettle();
    expect(textWindowBody('Welcome back to the show.'), findsOneWidget);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('transcribe-button'));
    await tester.tap(key('transcribe-button'));
    await tester.pumpAndSettle();
    await tester.tap(key('pack-download-medium'));
    await tester.pump();
    speech.finishDownload(error: 'The pack could not be downloaded.');
    await tester.pumpAndSettle();
    expect(key('transcribe-error'), findsOneWidget);
    expect(find.text('The pack could not be downloaded.'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(3));
  });

  testWidgets('desktop: a pack whose check failed can be used anyway, or removed',
      (tester) async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp);
    for (final language in ['auto', 'en', '']) {
      for (final row in speech.packs(language)) {
        if (row.size == SpeechQuality.medium || row.size == SpeechQuality.small) {
          speech.checkFailedIds.add(row.model.id);
        }
      }
    }
    final fakes = await open(tester, desktop, speech: speech);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('transcribe-button'));
    await tester.tap(key('transcribe-button'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not the file ClipForge expected'), findsNWidgets(2));
    expect(key('pack-use-anyway-medium'), findsOneWidget);
    expect(key('pack-remove-medium'), findsNothing, reason: 'not counted as installed');
    await fakes.screenshot(tester, 'editor_desktop_pack_use_anyway');

    await tester.ensureVisible(key('pack-use-anyway-medium'));
    await tester.tap(key('pack-use-anyway-medium'));
    await tester.pumpAndSettle();
    expect(key('pack-use-anyway-medium'), findsNothing);
    expect(key('pack-remove-medium'), findsOneWidget, reason: 'it is the pack now');

    await tester.ensureVisible(key('pack-discard-small'));
    await tester.tap(key('pack-discard-small'));
    await tester.pumpAndSettle();
    expect(key('pack-discard-small'), findsNothing);
    expect(key('pack-download-small'), findsOneWidget, reason: 'back to "Download"');
  });

  testWidgets('desktop: Captions from speech, one undo step', (tester) async {
    {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'})
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, english);
    final fakes = await open(tester, desktop, speech: speech);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('speech-captions-button'));
    await tester.tap(key('speech-captions-button'));
    await tester.pumpAndSettle();
    expect(key('speech-captions-dialog'), findsOneWidget);
    expect(find.textContaining('This adds'), findsOneWidget);
    // "um" and "uh" are not in the captions.
    final preview = tester.widget<Text>(key('speech-captions-preview')).data!;
    expect(preview, contains('Welcome back to the show.'));
    expect(preview, isNot(contains('um')));
    await fakes.screenshot(tester, 'editor_desktop_speech_captions');
    await tester.tap(key('speech-captions-add'));
    await tester.pumpAndSettle();
    final project = now(tester);
    final n = project.titles.length;
    expect(n, inInclusiveRange(4, 7));
    expect(find.textContaining('This adds'), findsNothing);
    expect(project.titles.every((t) => t.kind == TitleKind.caption), isTrue);
    expect(project.titles.first.text, 'Welcome back to the show.');
    expect(find.textContaining('Added $n captions from the speech'), findsOneWidget);
    // One step back and they are gone.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
    await tester.pumpAndSettle();
    expect(now(tester).titles, isEmpty);
    }
  });

  testWidgets('desktop: Remove filler words is gentle by default: Light / '
      'Normal / Strong, a list to review with jump ratings, cuts in one '
      'step, and Automatic cuts to put them back', (tester) async {
    // "um" and "uh" with a clear pause on both sides, one of them where
    // the speaker moves; "er" glued inside fast speech.
    final t = Transcript(
      sourcePath: talkPath,
      audioTrack: 0,
      language: 'en',
      requestedLanguage: 'en',
      model: 'base.en',
      backend: 'whisper-cpp',
      wordTiming: WordTiming.measured,
      durationMs: 20000,
      createdAt: DateTime.utc(2026),
      segments: segmentsFromWords(const [
        TranscriptWord('Welcome', 1000, 1400),
        TranscriptWord('um', 1700, 2100),
        TranscriptWord('back.', 2400, 2800),
        TranscriptWord('Today', 6000, 6400),
        TranscriptWord('er', 6420, 6560),
        TranscriptWord('bread.', 6580, 7000),
        TranscriptWord('First', 10000, 10400),
        TranscriptWord('uh', 10700, 11200),
        TranscriptWord('flour.', 11500, 12000),
        TranscriptWord('And', 15000, 15300),
        TranscriptWord('um', 15600, 16000),
        TranscriptWord('like', 16300, 16600),
        TranscriptWord('salt.', 16700, 17100),
      ]),
    );
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base.en'})
      ..stored['$talkPath|0'] = t;
    useScreen(tester, desktop);
    final fakes = JumpFakes(projects: [talk()])..speech = speech;
    // The second "um" (at 15.6 s) is where the picture jumps; the "uh" a
    // little.
    fakes.engine.scoreAt = (beforeMs) =>
        beforeMs > 15000 ? 0.8 : (beforeMs > 10000 ? 0.3 : 0.02);
    await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
    await tester.pumpAndSettle();
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('fillers-button'));
    await tester.tap(key('fillers-button'));
    await tester.pumpAndSettle();
    expect(key('fillers-dialog'), findsOneWidget);
    bool ticked(int i) => tester.widget<Checkbox>(key('filler-$i')).value!;
    // Rows in time order: um, er, uh, um, like.
    expect(find.text('“um”'), findsNWidgets(2));
    expect(find.text('“like” · also a real word'), findsOneWidget);
    expect(find.text('smooth'), findsNWidgets(2));
    expect(find.text('slight'), findsOneWidget);
    expect(find.text('jumpy'), findsNWidgets(2));
    // Light: the clear ones; not the glued "er", not the jumpy "um", never
    // the real word.
    expect([for (var i = 0; i < 5; i++) ticked(i)],
        [true, false, true, false, false]);
    expect(find.textContaining('2 of 5 selected · saves 0:01 · about 6 cuts per minute'),
        findsOneWidget);
    expect(key('fillers-jumpy-left'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_desktop_fillers');
    // Normal adds the short one; Strong also the jumpy one.
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    expect([for (var i = 0; i < 5; i++) ticked(i)],
        [true, false, true, false, false],
        reason: 'the glued "er" is under 200 ms: still too short');
    await tester.tap(find.text('Strong'));
    await tester.pumpAndSettle();
    expect([for (var i = 0; i < 5; i++) ticked(i)],
        [true, true, true, true, false]);
    expect(find.textContaining('4 of 5 selected'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    // Untick one by hand; a word of your own.
    await tester.tap(key('filler-2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of 5 selected'), findsOneWidget);
    await tester.tap(key('filler-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Play it as it would be after the cut').first);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(key('fillers-remove'));
    await tester.pumpAndSettle();
    var project = now(tester);
    expect(project.clips.length, 3);
    expect(project.autoCuts.map((c) => [c.kind, c.word, c.by]), [
      ['filler', 'um', 'app'],
      ['filler', 'uh', 'app'],
    ]);
    // The slightly jumpy one got a short dissolve.
    expect(project.autoCuts.map((c) => c.smoothed), [false, true]);
    expect(project.clips.last.transition, TransitionType.crossfade);
    expect(find.textContaining('Removed 2 filler words'), findsOneWidget);

    // Automatic cuts: listed, put one back, then all.
    await tester.ensureVisible(key('auto-cuts-button'));
    await tester.tap(key('auto-cuts-button'));
    await tester.pumpAndSettle();
    expect(key('auto-cuts-dialog'), findsOneWidget);
    expect(find.textContaining('2 cuts · '), findsOneWidget);
    expect(find.textContaining('“uh” · talk.mp4 at 0:10'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_desktop_auto_cuts');
    await tester.tap(key('auto-cut-back-0'));
    await tester.pumpAndSettle();
    project = now(tester);
    expect([project.clips.length, project.autoCuts.length], [2, 1]);
    await tester.tap(key('auto-cuts-all'));
    await tester.pumpAndSettle();
    project = now(tester);
    expect([project.clips.length, project.autoCuts.length, project.durationMs],
        [1, 0, 20000]);
    expect(find.textContaining('Nothing was cut automatically'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // Three steps back: before any cut.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
      await tester.pumpAndSettle();
    }
    expect(now(tester).clips.length, 1);
    expect(now(tester).autoCuts, isEmpty);
  });

  testWidgets('desktop: estimated word times are said honestly and nothing '
      'is ticked', (tester) async {
    {
    final speech = FakeSpeech(packs: {'base'})
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, english,
          backend: 'ffmpeg-whisper', timing: WordTiming.estimated);
    await open(tester, desktop, speech: speech);
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('fillers-button'));
    await tester.tap(key('fillers-button'));
    await tester.pumpAndSettle();
    expect(key('fillers-estimated'), findsOneWidget);
    expect(key('fillers-filter-note'), findsOneWidget);
    expect(find.textContaining('0 of 3 selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('fillers-remove')).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    }
  });

  testWidgets('desktop: Hebrew transcript reads right to left; captions keep '
      'their order', (tester) async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'})
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, hebrew, language: 'he');
    final fakes = await open(tester, desktop, speech: speech);
    await tester.tap(key('text-button'));
    await tester.pumpAndSettle();
    final phrase = tester.widget<RichText>(textWindowBody('היום נדבר על לחם.'));
    expect(phrase.textDirection, TextDirection.rtl);
    await fakes.screenshot(tester, 'editor_desktop_transcript_hebrew');
    await selectClip(tester);
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(key('speech-captions-button'));
    await tester.tap(key('speech-captions-button'));
    await tester.pumpAndSettle();
    await tester.tap(key('speech-captions-add'));
    await tester.pumpAndSettle();
    final titles = now(tester).titles;
    expect(titles.map((t) => t.text.replaceAll('\n', ' ')).join(' '), hebrew);
    await tester.pump(const Duration(seconds: 5));
    await fakes.screenshot(tester, 'editor_desktop_hebrew_captions');
  });

  testWidgets('a narrow window on a computer has the Text window as a sheet',
      (tester) async {
    await onWindows(() async {
    final speech = FakeSpeech(backend: FakeSpeech.whisperCpp, packs: {'base'})
      ..stored['$talkPath|0'] = spokenTranscript(talkPath, english);
    await open(tester, const Size(700, 800), speech: speech, menuBar: true);
    await tester.tap(find.widgetWithText(SubmenuButton, 'Text and speech'));
    await tester.pumpAndSettle();
    await tester.tap(key('menu-text'));
    await tester.pumpAndSettle();
    expect(key('text-panel'), findsOneWidget);
    expect(textWindowBody('Welcome back to the show.'), findsOneWidget);
    });
  });
}
