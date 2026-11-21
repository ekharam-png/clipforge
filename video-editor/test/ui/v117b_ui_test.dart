// 1.17, second pass after a real Windows test of 1.15 (widget tests):
//
//  * the shortcuts do not depend on which panel has the keyboard focus:
//    each one is sent after focusing the timeline, the Text window's
//    list, a slider of the side panel, and nothing; text fields keep
//    their own Ctrl+Z / Ctrl+F;
//  * "Make shorts from markers…" in a short video: as many shorts as the
//    window promised, the choice when two would show the same part, and
//    an honest end message when one could not be made;
//  * "Use a model file I have…": an English-only file with the language
//    on Automatic, English and Russian, and forgetting it;
//  * the safety valve line of the sound pictures; the performance log in
//    Copy version info and in Send feedback;
//  * (small) the Text window follows playback, Delete with several
//    sentences selected, "Don't show again" - with the keys going
//    through the app-level handler.

import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/perf_log.dart';
import 'package:clipforge/core/publish/shorts.dart';
import 'package:clipforge/core/transcript/transcript.dart' show languageName;
import 'package:clipforge/ui/about.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/shorts_actions.dart';
import 'package:clipforge/ui/editor/speech_actions.dart';
import 'package:clipforge/ui/editor/text_panel.dart';
import 'package:clipforge/ui/feedback/feedback_screen.dart';
import 'package:clipforge/ui/services.dart' show PickedFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sound_waves_test.dart' show fakesFor, key, session, talk, WaveFakes;

const desk = Size(1400, 900);

/// The two-speaker talk of the sound tests, with captions to read.
Project talkWithCaptions() => talk().copyWith(titles: [
      for (var i = 0; i < 9; i++)
        TitleOverlay(
            id: 'c$i',
            text: 'Sentence number $i.',
            startMs: i * 2000 + 200,
            endMs: i * 2000 + 1900,
            kind: TitleKind.caption),
    ]);

Future<WaveFakes> openTalk(WidgetTester tester,
    {Project? project, bool menuBar = true}) async {
  useScreen(tester, desk);
  final f = fakesFor(project ?? talkWithCaptions());
  await tester.pumpWidget(
      f.app(const EditorScreen(projectId: 'p1'), menuBar: menuBar));
  await tester.pumpAndSettle();
  return f;
}

Future<void> withCtrl(WidgetTester tester, LogicalKeyboardKey k,
    {bool shift = false, PhysicalKeyboardKey? physical}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k, physicalKey: physical);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// The paragraphs of the Text window.
final Finder paragraph = find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> && k.value.startsWith('text-par-');
});

bool typing() =>
    FocusManager.instance.primaryFocus?.context?.widget is EditableText ||
    (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null);

/// A 35.3 s video with the two markers of the real test.
Project shortVideo({List<int> markers = const [11600, 23700]}) => Project(
      id: 'p1',
      name: 'Clip',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
      aspect: CanvasAspect.landscape16x9,
      clips: [videoClip('a', '/media/clip.mp4', 0, 35300)],
      markers: [
        for (final (i, ms) in markers.indexed) Marker(id: 'm$i', ms: ms),
      ],
    );

Future<Fakes> openProject(WidgetTester tester, Project project,
    {FakeSpeech? speech}) async {
  useScreen(tester, desk);
  final f = Fakes(projects: [project], missing: const {})..speech = speech;
  await tester.pumpWidget(f.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  return f;
}

void main() {
  setUpAll(loadFonts);

  group('shortcuts wherever the keyboard focus is', () {
    var textTaps = 0;
    /// Puts the keyboard focus somewhere, as a click there does.
    Future<void> focus(WidgetTester tester, String where) async {
      final s = session(tester);
      switch (where) {
        case 'timeline':
          await tester.pump(const Duration(milliseconds: 700));
          await tester.tap(key('audio-v1'));
          await tester.pumpAndSettle();
        case 'text':
          if (!s.showText.value) {
            await tester.tap(key('text-button'));
            await tester.pumpAndSettle();
          }
          // (Another sentence each time: twice the same one quickly is
          // a double-click, which opens the sentence to edit.)
          await tapInTextWindow(
              tester, 'Sentence number ${1 + (textTaps++ % 3)}.');
          await tester.pumpAndSettle();
        case 'slider':
          // A sound is selected: its settings with their sliders are in
          // the side panel. A slider takes the focus as after a click
          // on it.
          await tester.tap(key('audio-m1'));
          await tester.pumpAndSettle();
          expect(find.byType(Slider), findsWidgets);
          final node = FocusManager.instance.rootScope.traversalDescendants
              .firstWhere((n) =>
                  n.context?.findAncestorWidgetOfExactType<Slider>() != null);
          node.requestFocus();
          await tester.pumpAndSettle();
          expect(
              FocusManager.instance.primaryFocus!.context!
                  .findAncestorWidgetOfExactType<Slider>(),
              isNotNull,
              reason: 'a slider has the keyboard focus');
        case 'nothing':
          FocusManager.instance.primaryFocus?.unfocus(
              disposition: UnfocusDisposition.scope);
          await tester.pumpAndSettle();
          FocusManager.instance.rootScope.requestFocus();
          await tester.pumpAndSettle();
      }
      expect(typing(), isFalse);
    }

    for (final where in ['timeline', 'text', 'slider', 'nothing']) {
      testWidgets('focus on: $where', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await openTalk(tester);
          final s = session(tester);

          // Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z.
          await focus(tester, where);
          s.editor.addMarker(9000);
          await tester.pumpAndSettle();
          await focus(tester, where);
          expect(s.project.markers, hasLength(1));
          await withCtrl(tester, LogicalKeyboardKey.keyZ);
          expect(s.project.markers, isEmpty, reason: 'Ctrl+Z ($where)');
          await withCtrl(tester, LogicalKeyboardKey.keyY);
          expect(s.project.markers, hasLength(1), reason: 'Ctrl+Y ($where)');
          await withCtrl(tester, LogicalKeyboardKey.keyZ);
          await withCtrl(tester, LogicalKeyboardKey.keyZ, shift: true);
          expect(s.project.markers, hasLength(1),
              reason: 'Ctrl+Shift+Z ($where)');

          // Ctrl+Shift+H: the History column, on and off.
          await focus(tester, where);
          expect(key('history-panel'), findsNothing);
          await withCtrl(tester, LogicalKeyboardKey.keyH, shift: true);
          expect(key('history-panel'), findsOneWidget,
              reason: 'Ctrl+Shift+H ($where)');
          await focus(tester, where);
          await withCtrl(tester, LogicalKeyboardKey.keyH, shift: true);
          expect(key('history-panel'), findsNothing);

          // Ctrl+Right / Ctrl+Left: where speech starts.
          await focus(tester, where);
          s.clearSelection();
          s.playback.seek(0);
          await tester.pumpAndSettle();
          if (where != 'nothing') await focus(tester, where);
          s.clearSelection();
          await tester.pumpAndSettle();
          final before = s.playback.positionMs;
          await withCtrl(tester, LogicalKeyboardKey.arrowRight);
          final next = s.playback.positionMs;
          expect(next, greaterThan(before), reason: 'Ctrl+Right ($where)');
          await withCtrl(tester, LogicalKeyboardKey.arrowRight);
          expect(s.playback.positionMs, greaterThan(next));
          await withCtrl(tester, LogicalKeyboardKey.arrowLeft);
          expect(s.playback.positionMs, next, reason: 'Ctrl+Left ($where)');

          // Plain keys too: Space plays, the arrows step, S splits.
          await focus(tester, where);
          final at = s.playback.positionMs;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(s.playback.positionMs, greaterThan(at),
              reason: 'the right arrow steps a frame ($where)');
          expect(s.playback.playing, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(s.playback.playing, isTrue, reason: 'Space ($where)');
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(s.playback.playing, isFalse);

          // Ctrl+comma: Settings (by the key's place, too).
          await focus(tester, where);
          await withCtrl(tester, LogicalKeyboardKey.keyB,
              physical: PhysicalKeyboardKey.comma);
          expect(key('settings-dialog'), findsOneWidget,
              reason: 'Ctrl+comma ($where)');
          // While it is open the editor's shortcuts are off.
          await withCtrl(tester, LogicalKeyboardKey.keyZ);
          expect(s.project.markers, hasLength(1),
              reason: 'nothing is undone behind a dialog');
          Navigator.of(tester.element(key('settings-dialog'))).pop();
          await tester.pumpAndSettle();

          // Ctrl+F: the Text window opens with the search field; and in
          // a text field Ctrl+Z belongs to the field.
          await focus(tester, where);
          await withCtrl(tester, LogicalKeyboardKey.keyF);
          expect(s.showText.value, isTrue, reason: 'Ctrl+F ($where)');
          expect(typing(), isTrue, reason: 'the search field has the focus');
          await tester.enterText(key('text-search'), 'number 3');
          await tester.pumpAndSettle();
          final steps = s.editor.history.length;
          await withCtrl(tester, LogicalKeyboardKey.keyZ);
          expect(s.project.markers, hasLength(1),
              reason: 'Ctrl+Z in a text field does not undo the project');
          expect(s.editor.history.length, steps);
          // A letter typed there is text, not a shortcut.
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
          await tester.pumpAndSettle();
          expect(s.project.clips, hasLength(1), reason: 'S did not split');
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('Tab to a control: its own keys belong to it again; a click '
        'ends that', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await openTalk(tester);
        final s = session(tester);
        await tester.tap(key('audio-m1'));
        await tester.pumpAndSettle();
        // Tab says: the keyboard is being used to move between controls.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final at = s.playback.positionMs;
        final node = FocusManager.instance.rootScope.traversalDescendants
            .firstWhere((n) =>
                n.context?.findAncestorWidgetOfExactType<Slider>() != null);
        node.requestFocus();
        await tester.pumpAndSettle();
        final volume = s.project.audio.firstWhere((a) => a.id == 'm1').volume;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(s.playback.positionMs, at,
            reason: 'the arrow went to the slider, not to the playhead');
        expect(s.project.audio.firstWhere((a) => a.id == 'm1').volume,
            isNot(volume));
        // Ctrl shortcuts work all the same.
        await withCtrl(tester, LogicalKeyboardKey.keyZ);
        expect(s.project.audio.firstWhere((a) => a.id == 'm1').volume, volume);
        // A click anywhere: plain keys are the editor's again.
        await tester.tap(key('audio-v1'));
        await tester.pumpAndSettle();
        node.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(s.playback.positionMs, greaterThan(at));
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the Text window: follows playback; Delete with several '
        'sentences selected deletes those captions, wherever the focus '
        'was', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await openTalk(tester);
        final s = session(tester);
        await tester.tap(key('text-button'));
        await tester.pumpAndSettle();
        final panel = tester.state<TextPanelState>(find.byType(TextPanel));
        expect(panel.follow, isTrue);
        // Playback moves on: the sentence being spoken is the active one.
        s.playback.seek(6500);
        await tester.pumpAndSettle();
        expect(panel.follow, isTrue, reason: 'seeking is not "by hand"');
        expect(find.text('Sentence number 3.'), findsWidgets);
        // A sentence, then Shift+click another: those and what is
        // between. Delete removes those captions (not what is selected
        // on the timeline).
        expect(paragraph, findsWidgets);
        await tapInTextWindow(tester, 'Sentence number 1.');
        await tester.pumpAndSettle();
        expect(panel.selectedIds, {'c1'});
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tapInTextWindow(tester, 'Sentence number 3.');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(panel.selectedIds, {'c1', 'c2', 'c3'});
        final chosen = panel.selectedIds.length;
        final captions = s.project.titles.length;
        final sounds = s.project.audio.length;
        // The focus goes somewhere else first (a click on the History
        // button and back): the key still reaches the editor.
        await withCtrl(tester, LogicalKeyboardKey.keyH, shift: true);
        await withCtrl(tester, LogicalKeyboardKey.keyH, shift: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        expect(s.project.titles.length, captions - chosen);
        expect(s.project.audio.length, sounds);
        await withCtrl(tester, LogicalKeyboardKey.keyZ);
        expect(s.project.titles.length, captions, reason: 'one undo step');
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('shorts from markers', () {
    Future<void> start(WidgetTester tester) async {
      final s = session(tester);
      unawaited(makeShortsFromMarkers(
          tester.element(find.byType(EditorScreen)), s));
      await tester.pumpAndSettle();
      expect(key('markers-shorts-dialog'), findsOneWidget);
    }

    List<Project> shortsOf(Fakes f) =>
        f.store.projects.values.where((x) => x.id != 'p1').toList();

    testWidgets('the real case (35.3 s, markers at 0:11.6 and 0:23.7): two '
        'different parts are shown, two shorts are made, the message says '
        'two', (tester) async {
      final f = await openProject(tester, shortVideo());
      await start(tester);
      expect(find.text('Make 2 shorts from the markers?'), findsOneWidget);
      expect(key('markers-overlap-note'), findsNothing);
      final shown = [
        for (final i in [0, 1])
          tester.widget<Text>(key('markers-short-range-$i')).data!,
      ];
      expect(shown[0], isNot(shown[1]));
      for (final line in shown) {
        expect(line, isNot(contains('0:00.0 – 0:35.3')),
            reason: 'not the whole video');
      }
      expect(key('markers-short-range-2'), findsNothing);
      await tester.tap(key('markers-shorts-go'));
      await tester.pumpAndSettle();
      expect(find.text('2 shorts are ready'), findsOneWidget);
      final made = shortsOf(f);
      expect(made, hasLength(2), reason: 'as many as promised');
      expect(made.map((p) => p.name).toSet(),
          {'Clip - short 0:11', 'Clip - short 0:23'});
      final a = markerRange(11600, 35300), b = markerRange(23700, 35300);
      expect(made.map((p) => p.durationMs).toList()..sort(),
          [a.endMs - a.startMs, b.endMs - b.startMs]..sort());
      for (final p in made) {
        expect(p.durationMs, lessThan(35300 * 0.6));
        expect(p.aspect, CanvasAspect.portrait9x16);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('two markers close together: the window says so and asks; '
        'one short covering both is made as one, with a message for one',
        (tester) async {
      final f = await openProject(
          tester, shortVideo(markers: const [15000, 17000]));
      await start(tester);
      expect(key('markers-overlap-note'), findsOneWidget);
      expect(find.text('One short covering both'), findsOneWidget);
      expect(find.text('Two shorts'), findsOneWidget);
      // "One short covering both" is what is ticked.
      expect(find.text('Make 1 short from the 2 markers?'), findsOneWidget);
      expect(key('markers-short-range-0'), findsOneWidget);
      expect(key('markers-short-range-1'), findsNothing);
      await tester.tap(key('markers-shorts-go'));
      await tester.pumpAndSettle();
      expect(find.text('The short is ready'), findsOneWidget);
      expect(shortsOf(f), hasLength(1));
      final a = markerRange(15000, 35300), b = markerRange(17000, 35300);
      expect(shortsOf(f).single.durationMs, b.endMs - a.startMs);
    });

    testWidgets('... or two shorts: two are made and counted',
        (tester) async {
      final f = await openProject(
          tester, shortVideo(markers: const [15000, 17000]));
      await start(tester);
      await tester.tap(key('markers-separate'));
      await tester.pumpAndSettle();
      expect(find.text('Make 2 shorts from the markers?'), findsOneWidget);
      expect(key('markers-short-range-1'), findsOneWidget);
      await tester.tap(key('markers-shorts-go'));
      await tester.pumpAndSettle();
      expect(find.text('2 shorts are ready'), findsOneWidget);
      expect(shortsOf(f), hasLength(2));
      // Both start within the same second: the names still differ.
      expect(shortsOf(f).map((p) => p.name).toSet(), hasLength(2));
    });

    testWidgets('one of two cannot be made: the message counts and says '
        'which, and nothing half-made stays in the project list',
        (tester) async {
      final f = await openProject(tester, shortVideo());
      f.store.failWhen = (p) => p.name.endsWith('short 0:23');
      await start(tester);
      await tester.tap(key('markers-shorts-go'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 shorts was made'), findsOneWidget);
      expect(find.textContaining('Not made:'), findsOneWidget);
      expect(find.text('The short is ready'), findsNothing);
      expect(shortsOf(f).map((p) => p.name), ['Clip - short 0:11']);
      expect(tester.takeException(), isNull);
    });
  });

  group('Transcribe speech: a model file I have', () {
    Future<FakeSpeech> openDialog(WidgetTester tester,
        {String? language}) async {
      final speech = FakeSpeech();
      final f = await openProject(
          tester,
          Project(
            id: 'p1',
            name: 'Talk',
            createdAt: DateTime(2026, 11, 1),
            updatedAt: DateTime(2026, 11, 2),
            aspect: CanvasAspect.landscape16x9,
            clips: [videoClip('a', '/media/talk.mp4', 0, 20000)],
          ),
          speech: speech);
      f.documents.pick =
          const PickedFile('/models/ggml-base.en.bin', 'ggml-base.en.bin');
      unawaited(showTranscribeDialog(
          tester.element(find.byType(EditorScreen)), session(tester)));
      await tester.pumpAndSettle();
      expect(key('transcribe-dialog'), findsOneWidget);
      if (language != null) {
        await tester.tap(key('transcribe-language'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language).last);
        await tester.pumpAndSettle();
      }
      return speech;
    }

    bool canGo(WidgetTester tester) =>
        tester.widget<FilledButton>(key('transcribe-go')).onPressed != null;

    String languageShown(WidgetTester tester) => tester
        .widget<DropdownButton<String>>(key('transcribe-language'))
        .value!;

    testWidgets('with Automatic: the language becomes English, one line '
        'says why, Transcribe is on; forgetting the file turns it off again',
        (tester) async {
      final speech = await openDialog(tester);
      expect(languageShown(tester), 'auto');
      expect(canGo(tester), isFalse, reason: 'no pack, no file');
      await tester.ensureVisible(key('own-model-choose'));
      await tester.tap(key('own-model-choose'));
      await tester.pumpAndSettle();
      expect(find.text('Your own file: ggml-base.en.bin'), findsOneWidget);
      expect(languageShown(tester), 'en');
      expect(
          tester.widget<Text>(key('own-model-note')).data,
          'This file understands English only, so the language was set to '
          'English.');
      expect(canGo(tester), isTrue);
      // It is what gets used.
      speech.hears['/media/talk.mp4'] =
          spokenTranscript('/media/talk.mp4', 'Hello there.');
      await tester.tap(key('transcribe-go'));
      await tester.pumpAndSettle();
      expect(speech.transcribed.single, '/media/talk.mp4|en|auto');
    });

    testWidgets('with English: on, nothing to explain', (tester) async {
      await openDialog(tester, language: 'English');
      expect(canGo(tester), isFalse);
      await tester.ensureVisible(key('own-model-choose'));
      await tester.tap(key('own-model-choose'));
      await tester.pumpAndSettle();
      expect(languageShown(tester), 'en');
      expect(key('own-model-note'), findsNothing);
      expect(canGo(tester), isTrue);
      // Back to Automatic by hand: still usable, and it says how.
      await tester.tap(key('transcribe-language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(languageName('auto')).last);
      await tester.pumpAndSettle();
      expect(canGo(tester), isTrue);
      expect(tester.widget<Text>(key('own-model-note')).data,
          contains('the speech is taken as English'));
    });

    testWidgets('with Russian: stays off and one line explains; removing '
        'the file takes the line away', (tester) async {
      await openDialog(tester, language: 'Russian');
      await tester.ensureVisible(key('own-model-choose'));
      await tester.tap(key('own-model-choose'));
      await tester.pumpAndSettle();
      expect(languageShown(tester), 'ru', reason: 'the language is kept');
      expect(canGo(tester), isFalse);
      expect(
          tester.widget<Text>(key('own-model-note')).data,
          allOf(contains('English only'), contains('cannot be used for Russian'),
              contains('Choose English')));
      // Choosing English makes it usable.
      await tester.tap(key('transcribe-language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(canGo(tester), isTrue);
      // Forget it: off again, the lines are gone.
      await tester.ensureVisible(key('own-model-forget'));
      await tester.tap(key('own-model-forget'));
      await tester.pumpAndSettle();
      expect(key('own-model-name'), findsNothing);
      expect(key('own-model-note'), findsNothing);
      expect(canGo(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('the safety valve and the performance log', () {
    testWidgets('no answer for two seconds while sound is drawn: one line, '
        'and "Turn back on"', (tester) async {
      final fakes = fakesFor(talk());
      fakes.engine.gate = Completer<void>();
      useScreen(tester, desk);
      await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
      await tester.pumpAndSettle();
      final s = session(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(key('drawing-sound'), findsOneWidget);
      // A short gap changes nothing.
      PerfLog.instance.reportGap(900);
      await tester.pump();
      expect(key('sound-waves-paused'), findsNothing);
      // The app could not respond for 2.4 s.
      PerfLog.instance.reportGap(2400);
      fakes.engine.gate!.complete();
      await tester.pumpAndSettle();
      expect(
          find.text('Sound waves were paused to keep ClipForge responsive · '),
          findsOneWidget);
      expect(find.text('Turn back on'), findsOneWidget);
      expect(key('drawing-sound'), findsNothing);
      expect(s.pictures.busy, isFalse);
      expect(s.showWaves.value, isTrue, reason: 'Settings unchanged');
      final asked = fakes.engine.asked.length;
      // Another edit does not start them again.
      s.editor.rename('Other');
      await tester.pumpAndSettle();
      expect(fakes.engine.asked.length, asked);
      await tester.tap(key('sound-waves-resume'));
      await tester.pumpAndSettle();
      expect(key('sound-waves-paused'), findsNothing);
      expect(fakes.engine.asked.toSet().length, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Copy version info has the last lines of the performance '
        'log; Send feedback sends them only when ticked', (tester) async {
      final log = PerfLog()
        ..note('project opened: 2 clips, 0 sounds, 1567 s')
        ..note('save start')
        ..reportGap(2600);
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
      useScreen(tester, desk);
      final f = Fakes()..perfLog = log;
      await tester.pumpWidget(ProviderScope(
        child: f.app(Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              TextButton(
                  onPressed: () => copyVersionInfo(context),
                  child: const Text('copy')),
              TextButton(
                  onPressed: () => openFeedback(context),
                  child: const Text('feedback')),
            ]),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('copy'));
      await tester.pumpAndSettle();
      expect(copied.single, contains('Performance log (longest gap 2600 ms):'));
      expect(copied.single, contains('project opened: 2 clips, 0 sounds, 1567 s'));
      expect(copied.single, contains('gap 2600 ms'));

      await tester.tap(find.text('feedback'));
      await tester.pumpAndSettle();
      await tester.enterText(
          key('feedback-message'), 'It stopped answering after an import.');
      await tester.pumpAndSettle();
      expect(key('feedback-include-details'), findsOneWidget);
      // Not ticked: nothing of the log is in what is sent.
      expect(find.textContaining('gap 2600 ms'), findsNothing);
      await tester.ensureVisible(key('feedback-include-details'));
      await tester.tap(key('feedback-include-details'));
      await tester.pumpAndSettle();
      // Shown before it is sent.
      expect(find.textContaining('gap 2600 ms'), findsWidgets);
      await tester.ensureVisible(key('feedback-send'));
      await tester.tap(key('feedback-send'));
      await tester.pumpAndSettle();
      final message = f.feedbackPosts.single.payload['message'] as String;
      expect(message, startsWith('It stopped answering after an import.'));
      expect(message, contains('How ClipForge ran (performance log, no file '
          'names):'));
      expect(message, contains('save start'));
      expect(tester.takeException(), isNull);
    });
  });
}
