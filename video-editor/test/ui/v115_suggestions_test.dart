// 1.15: suggestions (lib/ui/editor/suggestions.dart). One quiet line, the
// highest priority that applies; ✕ closes it for the project, "Don't show
// again" for good; Settings turns them all off; never while the video
// plays or a dialog is open. Every trigger of the registry has a test.

import 'package:clipforge/core/editor/sound_tracks.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/app_settings.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/suggestions.dart';
import 'package:clipforge/ui/help/help_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// The editor with suggestions turned on (the harness has them off).
Future<Fakes> open(WidgetTester tester, Size size,
    {Project? project, bool speech = false}) async {
  useScreen(tester, size);
  final fakes = Fakes(projects: [project ?? sampleProject()], missing: const {});
  fakes.prefs.flags.remove(kSuggestionsOffFlag);
  if (speech) fakes.speech = FakeSpeech();
  await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  // The line appears a moment after the editor (it is never in a hurry).
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return fakes;
}

Suggestion byId(String id) => kSuggestions.firstWhere((s) => s.id == id);

final _bar = find.byKey(const ValueKey('suggestion-bar'));
String barText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('suggestion-text'))).data!;

Project plain({
  List<Clip>? clips,
  List<AudioClip> audio = const [],
  List<TitleOverlay> titles = const [],
  List<SoundTrack> tracks = const [],
  CanvasAspect aspect = CanvasAspect.landscape16x9,
  VideoSize videoSize = VideoSize.p1080,
}) =>
    Project(
      id: 'p1',
      name: 'Test',
      createdAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 19),
      aspect: aspect,
      videoSize: videoSize,
      clips: clips ??
          [
            const Clip(
                id: 'v',
                type: ClipType.video,
                path: '/media/talk.mp4',
                sourceDurationMs: 90000,
                inMs: 0,
                outMs: 90000,
                width: 1920,
                height: 1080),
          ],
      audio: audio,
      titles: titles,
      tracks: tracks,
    );

AudioClip music(String id,
        {int startMs = 0,
        int ms = 30000,
        String path = '/media/song.mp3',
        int sourceMs = 180000,
        String trackId = kMusicTrackId}) =>
    AudioClip(
        id: id,
        path: path,
        sourceDurationMs: sourceMs,
        startMs: startMs,
        inMs: 0,
        outMs: ms,
        trackId: trackId);

const _caption = TitleOverlay(
    id: 'c1', text: 'Hello', startMs: 0, endMs: 2000, kind: TitleKind.caption);

void main() {
  setUpAll(loadFonts);

  test('the registry: ids are unique and stable, priorities are distinct',
      () {
    expect(kSuggestions.map((s) => s.id).toList(), [
      'voice-as-music', 'fit-music', 'lower-music', 'small-first-clip', //
      'clip-shape', 'only-when-speaking', 'remove-silences', //
      'captions-from-speech', 'open-text',
      'who-is-speaking',
    ]);
    final priorities = kSuggestions.map((s) => s.priority).toList();
    expect(priorities.toSet().length, priorities.length);
    expect([...priorities]..sort((a, b) => b.compareTo(a)), priorities,
        reason: 'listed from the most to the least important');
    expect(byId('open-text').scope, SuggestionScope.onceEver);
    expect(byId('who-is-speaking').scope, SuggestionScope.onceEver);
    expect(byId('fit-music').scope, SuggestionScope.oncePerProject);
  });

  group('triggers', () {
    test('music longer or shorter than the video', () {
      // Longer by more than 2 s.
      expect(musicToFit(plain(audio: [music('m', ms: 120000)]))?.id, 'm');
      // Stops more than 3 s before the end, having started at the start.
      expect(musicToFit(plain(audio: [music('m', ms: 60000)]))?.id, 'm');
      // Ends with the video (within the margins): nothing to say.
      expect(musicToFit(plain(audio: [music('m', ms: 90000)])), isNull);
      expect(musicToFit(plain(audio: [music('m', ms: 88000)])), isNull);
      // A short sound effect, music that starts late, and looped music.
      expect(musicToFit(plain(audio: [music('m', ms: 4000)])), isNull);
      expect(
          musicToFit(plain(audio: [music('m', startMs: 40000, ms: 20000)])),
          isNull);
      expect(
          musicToFit(plain(audio: [
            music('m', ms: 90000, sourceMs: 30000).copyWith(loopMs: 30000),
          ])),
          isNull);
      // A voice that belongs to a clip is not music.
      expect(
          musicToFit(plain(audio: [
            music('m', ms: 60000).copyWith(sourceClipId: 'v', syncOffsetMs: 0),
          ])),
          isNull);
    });

    test('a sound that looks like a voice was added as music', () {
      expect(
          voiceAddedAsMusic(plain(audio: [
            music('m', path: '/rec/audioSamTaylor21406335665.m4a'),
          ]))?.id,
          'm');
      // The same length as the video file.
      expect(
          voiceAddedAsMusic(plain(audio: [
            music('m', path: '/rec/take.m4a', sourceMs: 91000),
          ]))?.id,
          'm');
      expect(voiceAddedAsMusic(plain(audio: [music('m')])), isNull);
      // Already lined up as a voice.
      expect(
          voiceAddedAsMusic(plain(audio: [
            music('m', path: '/rec/voice.m4a')
                .copyWith(sourceClipId: 'v', syncOffsetMs: 0),
          ])),
          isNull);
    });

    test('a small first clip while the size is "Same as the first clip"', () {
      const small = Clip(
          id: 's',
          type: ClipType.video,
          path: '/chat.mp4',
          sourceDurationMs: 9000,
          inMs: 0,
          outMs: 9000,
          width: 848,
          height: 480);
      expect(
          smallFirstClip(
              plain(clips: [small], videoSize: VideoSize.matchFirstClip)),
          isTrue);
      expect(smallFirstClip(plain(clips: [small])), isFalse,
          reason: '1080p was chosen already');
      expect(smallFirstClip(plain(videoSize: VideoSize.matchFirstClip)),
          isFalse,
          reason: 'a Full HD first clip');
    });

    testWidgets('a clip of another shape; long talk with pauses; music over '
        'speech; captions; voice track', (tester) async {
      const upright = Clip(
          id: 'u',
          type: ClipType.video,
          path: '/media/phone.mp4',
          sourceDurationMs: 8000,
          inMs: 0,
          outMs: 8000,
          width: 1080,
          height: 1920);
      await open(tester, desktop,
          project: plain(clips: [
            const Clip(
                id: 'v',
                type: ClipType.video,
                path: '/media/talk.mp4',
                sourceDurationMs: 90000,
                inMs: 0,
                outMs: 90000,
                width: 1920,
                height: 1080),
            upright,
          ], audio: [
            music('m', ms: 98000),
          ]));
      final s = sessionOf(tester);
      SuggestionContext c(
              {List<({int startMs, int endMs})> speech = const [],
              bool textOpened = false}) =>
          SuggestionContext(s, textOpened: textOpened, speech: speech);

      // Shape: the upright clip in a wide video, still between bars.
      expect(clipOfOtherShape(s)?.id, 'u');
      expect(byId('clip-shape').when(c()), isTrue);
      expect(byId('clip-shape').buttons(c()).map((b) => b.label),
          ['Fill', 'Blur', 'Crop…']);
      s.editor.setClipFit('u', FitMode.fill);
      expect(clipOfOtherShape(s), isNull);
      s.editor.undo();

      // Pauses: only from what is already known; none known, none said.
      expect(byId('remove-silences').when(c()), isFalse);
      const talk = [
        (startMs: 1000, endMs: 20000),
        (startMs: 27000, endMs: 50000),
        (startMs: 58000, endMs: 85000),
      ];
      expect(clipWithPauses(c(speech: talk))?.id, 'v');
      // Talking all the way through: no pauses to remove.
      expect(clipWithPauses(c(speech: const [(startMs: 0, endMs: 89500)])),
          isNull);

      // Music over speech with lowering not on for every track.
      expect(musicOverSpeech(c()), isFalse, reason: 'no speech known');
      expect(musicOverSpeech(c(speech: talk)), isTrue);
      s.editor.setDuckMusic(true);
      expect(lowerMusicState(s.project), LowerMusic.all);
      expect(musicOverSpeech(c(speech: talk)), isFalse);
      s.editor.undo();

      // Captions from speech: computers with speech-to-text only (this
      // editor has none, like a phone).
      expect(byId('captions-from-speech').when(c(speech: talk)), isFalse);

      // Captions exist and Text was never opened.
      expect(byId('open-text').when(c()), isFalse);
      s.editor.addTitles(const [_caption]);
      expect(byId('open-text').when(c()), isTrue);
      expect(byId('open-text').when(c(textOpened: true)), isFalse);

      // The first voice track.
      expect(byId('who-is-speaking').when(c()), isFalse);
      s.editor.updateAudio(s.project.audio.first
          .copyWith(sourceClipId: 'v', syncOffsetMs: 0));
      expect(s.project.audio.first.isVoice, isTrue);
      expect(byId('who-is-speaking').when(c()), isTrue);
    });

    testWidgets('captions from speech needs a speech engine, talking and no '
        'captions', (tester) async {
      await open(tester, desktop, project: plain(), speech: true);
      final s = sessionOf(tester);
      const talk = [(startMs: 1000, endMs: 30000)];
      final when = byId('captions-from-speech').when;
      expect(when(SuggestionContext(s, speech: talk)), isTrue);
      expect(when(SuggestionContext(s, speech: const [])), isFalse);
      s.editor.addTitles(const [_caption]);
      expect(when(SuggestionContext(s, speech: talk)), isFalse);
    });
  });

  group('the line', () {
    testWidgets('computer: a thin bar under the top bar with a button, '
        '"Don\'t show again" and a cross; the button acts', (tester) async {
      final fakes = await open(tester, desktop);
      final s = sessionOf(tester);
      expect(_bar, findsOneWidget);
      expect(barText(tester), 'The music stops before the video ends.');
      expect(find.text('Fit to video'), findsOneWidget);
      expect(find.text("Don't show again"), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-close')), findsOneWidget);
      // Under the top bar, above the preview, and thin.
      final bar = tester.getRect(_bar);
      expect(bar.top, closeTo(tester.getBottomLeft(find.byType(AppBar)).dy, 1));
      expect(bar.bottom,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(PreviewView)).dy));
      expect(bar.height, lessThanOrEqualTo(40));
      await fakes.screenshot(tester, 'suggestion_desktop');

      await tester.tap(find.text('Fit to video'));
      await tester.pumpAndSettle();
      // The music was selected and "Fit music to video" has started (its
      // question, or the edit itself).
      expect(s.selectedAudio?.id, 'm1');
      // Used: closed for this project.
      expect(await fakes.prefs.flag('hint.fit-music.p1'), isTrue);
    });

    testWidgets('phone: a thin line just above the tool bar; a swipe sends it '
        'away for this project', (tester) async {
      final fakes = await open(tester, const Size(360, 760));
      expect(_bar, findsOneWidget);
      final bar = tester.getRect(_bar);
      final tools = tester.getRect(find.text('Split').first);
      expect(bar.bottom, lessThanOrEqualTo(tools.top));
      expect(bar.top, greaterThan(380), reason: 'below the timeline');
      // Touch targets.
      expect(tester.getSize(find.text('Fit to video')).height, isNonZero);
      expect(
          tester
              .getSize(find.ancestor(
                  of: find.text('Fit to video'),
                  matching: find.byType(TextButton)))
              .height,
          greaterThanOrEqualTo(48));
      expect(
          tester.getSize(find.byKey(const ValueKey('suggestion-close'))),
          const Size(48, 48));
      await fakes.screenshot(tester, 'suggestion_phone');
      expect(tester.takeException(), isNull);

      await tester.drag(_bar, const Offset(-340, 0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('The music stops before the video ends.'), findsNothing);
      expect(await fakes.prefs.flag('hint.fit-music.p1'), isTrue);
      expect(await fakes.prefs.flag('hint.fit-music.off'), isFalse);
    });

    testWidgets('one at a time, the most important first; the cross brings '
        'the next', (tester) async {
      // Small first clip (60) and music to fit (80).
      final fakes = await open(tester, desktop,
          project: plain(
              clips: [
                const Clip(
                    id: 's',
                    type: ClipType.video,
                    path: '/chat.mp4',
                    sourceDurationMs: 60000,
                    inMs: 0,
                    outMs: 60000,
                    width: 848,
                    height: 480),
              ],
              videoSize: VideoSize.matchFirstClip,
              audio: [music('m', ms: 120000)]));
      final s = sessionOf(tester);
      expect(_bar, findsOneWidget);
      expect(barText(tester), 'The music is longer than the video.');
      expect(find.text('Use 1080p'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('suggestion-close')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(await fakes.prefs.flag('hint.fit-music.p1'), isTrue);
      expect(barText(tester), contains('The first clip is small (848×480)'));
      await tester.tap(find.text('Use 1080p'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(s.project.videoSize, VideoSize.p1080);
      expect(_bar, findsNothing);

      // The same project opened again: what was closed stays closed.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
    });

    testWidgets('"Don\'t show again" turns one off for good; Settings brings '
        'it back', (tester) async {
      final fakes = await open(tester, desktop);
      await tester.tap(find.text("Don't show again"));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(await fakes.prefs.flag('hint.fit-music.off'), isTrue);
      expect(await fakes.prefs.flag('hint.fit-music.p1'), isFalse);
      final settings = ProviderScope.containerOf(
              tester.element(find.byType(MaterialApp)))
          .read(appSettingsProvider);
      expect(await settings.hiddenHints(), ['fit-music']);

      // Settings > "Show hidden suggestions again".
      await settings.showHiddenHintsAgain();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
    });

    testWidgets('Settings > Show suggestions off: none at all, at once',
        (tester) async {
      final fakes = await open(tester, desktop);
      expect(_bar, findsOneWidget);
      final settings = ProviderScope.containerOf(
              tester.element(find.byType(MaterialApp)))
          .read(appSettingsProvider);
      await settings.setSuggestions(false);
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(fakes.prefs.flags, contains(kSuggestionsOffFlag));
      await settings.setSuggestions(true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
    });

    testWidgets('never while the video plays', (tester) async {
      await open(tester, desktop);
      final s = sessionOf(tester);
      expect(_bar, findsOneWidget);
      s.playback.toggle();
      await tester.pump();
      expect(s.playback.playing, isTrue);
      expect(_bar, findsNothing);
      // An edit while playing does not bring one up either.
      s.editor.setDuckMusic(true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_bar, findsNothing);
      s.playback.pause();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
    });

    testWidgets('not changed while a dialog is open', (tester) async {
      await open(tester, desktop,
          project: plain(audio: [music('m', ms: 90000)]));
      final s = sessionOf(tester);
      expect(_bar, findsNothing);
      // A dialog over the editor; meanwhile the music becomes too long.
      showHelpArticle(tester.element(find.byType(PreviewView)), 'fit-music');
      await tester.pumpAndSettle();
      s.editor.updateAudio(s.project.audio.first.copyWith(outMs: 150000));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      // Closed: the next change brings the line.
      Navigator.of(tester.element(find.byType(PreviewView)),
              rootNavigator: true)
          .pop();
      await tester.pumpAndSettle();
      s.clearSelection();
      s.select(ItemKind.audio, 'm');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
      expect(barText(tester), 'The music is longer than the video.');
    });

    testWidgets('a once-ever suggestion never comes back, in any project',
        (tester) async {
      final project = plain(titles: const [_caption]);
      final fakes = await open(tester, desktop, project: project);
      expect(barText(tester), contains('Text shows every caption'));
      await tester.tap(find.byKey(const ValueKey('suggestion-close')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(await fakes.prefs.flag('hint.open-text.ever'), isTrue);
      expect(_bar, findsNothing);
    });

    testWidgets('the suggestion with three small buttons fits a phone',
        (tester) async {
      await open(tester, const Size(360, 760),
          project: plain(clips: [
            const Clip(
                id: 'v',
                type: ClipType.video,
                path: '/media/talk.mp4',
                sourceDurationMs: 30000,
                inMs: 0,
                outMs: 30000,
                width: 1920,
                height: 1080),
            const Clip(
                id: 'u',
                type: ClipType.video,
                path: '/media/phone.mp4',
                sourceDurationMs: 8000,
                inMs: 0,
                outMs: 8000,
                width: 1080,
                height: 1920),
          ]));
      final s = sessionOf(tester);
      expect(barText(tester), contains('another shape'));
      for (final label in ['Fill', 'Blur', 'Crop…']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Blur'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(s.project.clips[1].fit, FitMode.blur);
      expect(s.selectedClip?.id, 'u');
    });
  });
}
