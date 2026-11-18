// 1.13: sound waves on the timeline and who is speaking. Every sound item
// shows its waveform (video clips a slim one along the bottom), drawn only
// for the part near the view; speech tracks show talk in the speaker's
// colour and pauses dimmed; snapping and "next / previous speech start"
// use the same stretches; "Show sound waves" turns it all off.
import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/sound_peaks_job.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/sound_wave.dart';
import 'package:clipforge/ui/speaker_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// Levels (dB) per 20 ms: [base], with [parts] (ms, ms, dB).
SoundPeaks levels(int ms, double base, List<(int, int, double)> parts) {
  final db = List<double>.filled(ms ~/ kPeakHopMs, base);
  for (final (a, b, v) in parts) {
    for (var i = a ~/ kPeakHopMs; i < b ~/ kPeakHopMs && i < db.length; i++) {
      // A little life in the level, so the waveform is not a block.
      db[i] = v + (i % 7) * 0.6 - (i % 3);
    }
  }
  return SoundPeaks.fromLevels(db);
}

/// An engine that "listens" to files: the pictures in [pictures].
class WaveEngine extends FakeMediaEngine implements SoundPeaksEngine {
  final Map<String, SoundPeaks> pictures = {};
  final List<String> asked = [];

  /// When set, a picture is only given once this completes.
  Completer<void>? gate;

  @override
  Future<SoundPeaks?> soundPeaks(String path,
      {int audioTrack = 0, String? cacheDir}) async {
    asked.add(path);
    await gate?.future;
    return pictures[path];
  }
}

class WaveFakes extends Fakes {
  WaveFakes({super.projects}) : super(missing: const {});
  final WaveEngine _engine = WaveEngine();

  // ignore: overridden_fields
  @override
  WaveEngine get engine => _engine;
}

const video = '/media/zoom.mp4';
const samFile = '/media/audioSam.m4a';
const danaFile = '/media/audioDana.m4a';
const song = '/media/song.mp3';

/// A two-person talk: one video, one voice file per speaker (linked),
/// and music. Sam talks 1-5 s and 12-18 s, Dana 6-11 s and 15-18 s.
Project talk({int length = 20000}) => Project(
      id: 'p1',
      name: 'Zoom talk',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
      aspect: CanvasAspect.landscape16x9,
      clips: [
        Clip(
          id: 'a',
          type: ClipType.video,
          path: video,
          sourceDurationMs: length,
          inMs: 0,
          outMs: length,
          width: 1920,
          height: 1080,
        ),
      ],
      tracks: const [
        SoundTrack(id: 'sam', name: 'Sam', speech: true),
        SoundTrack(id: 'dana', name: 'Dana', speech: true),
        SoundTrack(id: kMusicTrackId, name: 'Music', duck: true),
      ],
      audio: [
        for (final (id, path, track) in [
          ('v1', samFile, 'sam'),
          ('v2', danaFile, 'dana'),
        ])
          AudioClip(
            id: id,
            path: path,
            sourceDurationMs: length,
            startMs: 0,
            inMs: 0,
            outMs: length,
            trackId: track,
            sourceClipId: 'a',
            linked: true,
            syncOffsetMs: 0,
          ),
        AudioClip(
          id: 'm1',
          path: song,
          sourceDurationMs: 180000,
          startMs: 2000,
          inMs: 0,
          outMs: 12000,
          volume: 0.5,
        ),
      ],
    );

WaveFakes fakesFor(Project p) {
  final f = WaveFakes(projects: [p]);
  f.engine.pictures.addAll({
    samFile: levels(20000, -60, [
      (1000, 5000, -16), (6000, 11000, -40), (12000, 18000, -16), //
    ]),
    danaFile: levels(20000, -58, [
      (1000, 5000, -42), (6000, 11000, -18), (12000, 15000, -42), //
      (15000, 18000, -19),
    ]),
    video: levels(20000, -50, [(1000, 18000, -24)]),
    song: levels(180000, -30, [(0, 180000, -14)]),
  });
  return f;
}

Finder key(String k) => find.byKey(ValueKey(k));

Future<WaveFakes> open(WidgetTester tester, Size size,
    {Project? project, WaveFakes? fakes, bool menuBar = false}) async {
  useScreen(tester, size);
  final f = fakes ?? fakesFor(project ?? talk());
  await tester.pumpWidget(
      f.app(const EditorScreen(projectId: 'p1'), menuBar: menuBar));
  await tester.pumpAndSettle();
  return f;
}

EditorSession session(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

WavePainter wave(WidgetTester tester, String id) =>
    tester.widget<CustomPaint>(key('wave-$id')).painter! as WavePainter;

void main() {
  setUpAll(loadFonts);

  test('the bars of a block: only the window, any zoom, trim and speed', () {
    final peaks = levels(60000, -60, [(10000, 20000, -12)]);
    // 60 px a second, the whole file: 3600 px; a window of 400 px.
    var c = waveColumns(peaks,
        inMs: 0, outMs: 60000, speed: 1, pxPerMs: 0.06, fromX: 500, toX: 900);
    expect(c.heights.length, 200);
    expect(c.firstX, 500);
    // x 600 = 10 s: loud from there on.
    expect(c.heights[40], lessThan(0.1));
    expect(c.heights[51], greaterThan(0.5));
    expect(c.active.every((a) => a == 1), isTrue);
    // Zoomed far out (6 px a second): a bar stands for a third of a
    // second and shows its loudest moment.
    c = waveColumns(peaks,
        inMs: 0, outMs: 60000, speed: 1, pxPerMs: 0.006, fromX: 0, toX: 360);
    expect(c.heights.length, 180);
    expect(c.heights[29], lessThan(0.1)); // 9.7 s
    expect(c.heights[31], greaterThan(0.5)); // 10.3 s
    expect(c.heights[61], lessThan(0.1)); // 20.3 s
    // Zoomed far in (480 px a second): several bars per measured step.
    c = waveColumns(peaks,
        inMs: 0, outMs: 60000, speed: 1, pxPerMs: 0.48, fromX: 4790, toX: 4810);
    expect(c.heights.first, lessThan(0.1));
    expect(c.heights.last, greaterThan(0.5));
    // Trimmed to 15-30 s at double speed: the loud part is the first
    // 2.5 s of the block.
    c = waveColumns(peaks,
        inMs: 15000, outMs: 30000, speed: 2, pxPerMs: 0.06, fromX: 0, toX: 450);
    expect(c.heights[70], greaterThan(0.5)); // 140 px = 2.33 s -> 19.7 s
    expect(c.heights[80], lessThan(0.1)); // 160 px = 2.67 s -> 20.3 s
    // Past the end of the sound: nothing.
    expect(c.heights[224], lessThan(0.1)); // 448 px = 7.47 s -> 29.9 s
    c = waveColumns(peaks,
        inMs: 0, outMs: 1000, speed: 1, pxPerMs: 0.06, fromX: 0, toX: 200);
    expect(c.heights[40], 0);
    // Talk and pauses.
    c = waveColumns(peaks,
        inMs: 0, outMs: 60000, speed: 1, pxPerMs: 0.06, fromX: 500, toX: 900,
        stretches: const [(startMs: 10000, endMs: 12000)]);
    expect(c.active[40], 0);
    expect(c.active[55], 1);
    expect(c.active[120], 0);
    // An empty window.
    expect(
        waveColumns(peaks,
                inMs: 0, outMs: 60000, speed: 1, pxPerMs: 0.06, fromX: 10, toX: 10)
            .heights,
        isEmpty);
  });

  test('a 40-minute block: the bars of one window cost next to nothing', () {
    final peaks = levels(2400000, -60, [(0, 2400000, -20)]);
    final watch = Stopwatch()..start();
    for (final zoom in [6.0, 60.0, 480.0]) {
      for (var i = 0; i < 50; i++) {
        final c = waveColumns(peaks,
            inMs: 0,
            outMs: 2400000,
            speed: 1,
            pxPerMs: zoom / 1000,
            fromX: i * 100.0,
            toX: i * 100.0 + 6000);
        expect(c.heights.length, 3000);
      }
    }
    // 150 windows of 6000 px.
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });

  testWidgets('desktop: waveforms on every sound and along the video; '
      'speech tracks in their speaker\'s colour, talk bright', (tester) async {
    final fakes = await open(tester, desktop);
    final s = session(tester);
    expect(fakes.engine.asked.toSet(), {video, samFile, danaFile, song});
    // Each file was read once.
    expect(fakes.engine.asked.length, 4);
    expect(key('drawing-sound'), findsNothing);
    for (final id in ['v1', 'v2', 'm1', 'a']) {
      expect(key('wave-$id'), findsOneWidget, reason: id);
    }
    // Sam's row: his talk, not Dana's voice in his microphone.
    final sam = wave(tester, 'v1');
    expect(sam.stretches, [
      (startMs: 1000, endMs: 5000),
      (startMs: 12000, endMs: 18000),
    ]);
    expect(sam.band, kSpeakerColors[0].withValues(alpha: 0.75));
    final dana = wave(tester, 'v2');
    expect(dana.stretches, [
      (startMs: 6000, endMs: 11000),
      (startMs: 15000, endMs: 18000),
    ]);
    expect(dana.band, kSpeakerColors[1].withValues(alpha: 0.75));
    // Music: a waveform, no talk.
    expect(wave(tester, 'm1').stretches, isNull);
    expect(wave(tester, 'm1').band, isNull);
    // The video's own sound: a slim strip along the bottom of the clip.
    expect(wave(tester, 'a').fromBottom, isTrue);
    expect(tester.getSize(key('wave-a')).height, 15);
    expect(tester.getBottomLeft(key('wave-a')).dy,
        tester.getBottomLeft(block('clip-a')).dy);
    // The speakers for the rest of the app.
    expect(s.pictures.speakers.map((t) => (t.name, t.talkMs)),
        [('Sam', 10000), ('Dana', 8000)]);
    // The track headers carry the speaker's colour.
    final icon = tester.widget<Icon>(find.descendant(
        of: key('track-header-sam'), matching: find.byType(Icon)));
    expect(icon.color, kSpeakerColors[0]);
    await fakes.screenshot(tester, 'timeline_waves_desktop');

    // Zoomed in: the painter is given the visible window only.
    s.setZoom(480);
    await tester.pumpAndSettle();
    final zoomed = wave(tester, 'v1');
    expect(zoomed.pxPerMs, 0.48);
    expect(zoomed.toX - zoomed.fromX, lessThan(6000));
    expect(tester.getSize(key('wave-v1')).width, zoomed.toX - zoomed.fromX);
    await fakes.screenshot(tester, 'timeline_waves_desktop_zoomed');
    s.setZoom(12);
    await tester.pumpAndSettle();
    await fakes.screenshot(tester, 'timeline_waves_desktop_far');
  });

  testWidgets('a muted video clip has no waveform; a cut keeps each piece on '
      'its part of the sound', (tester) async {
    await open(tester, desktop);
    final s = session(tester);
    s.editor.setClipMuted('a', true);
    await tester.pumpAndSettle();
    expect(key('wave-a'), findsNothing);
    s.editor.undo();
    // Cut 5-12 s out: the linked voices are cut with the clip.
    s.editor.removeSourceRanges('a', [(startMs: 5000, endMs: 12000)]);
    await tester.pumpAndSettle();
    final pieces = s.project.audio.where((a) => a.trackId == 'sam').toList();
    expect(pieces.length, 2);
    final second = wave(tester, pieces[1].id);
    expect((second.inMs, second.outMs), (12000, 20000));
    // Sam talked up to the cut and goes on right after it: one stretch.
    expect(s.pictures.speakers.first.stretches, [(startMs: 1000, endMs: 11000)]);
    // Dana's 6-11 s went with the cut.
    expect(s.pictures.speakers.last.stretches, [(startMs: 8000, endMs: 11000)]);
  });

  testWidgets('pictures arrive in the background: "Drawing sound…", then '
      'the waves', (tester) async {
    final fakes = fakesFor(talk());
    fakes.engine.gate = Completer<void>();
    useScreen(tester, desktop);
    await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // The editor is there and usable; the blocks are plain.
    expect(block('audio-v1'), findsOneWidget);
    expect(key('wave-v1'), findsNothing);
    expect(key('drawing-sound'), findsOneWidget);
    expect(key('next-speech'), findsNothing);
    fakes.engine.gate!.complete();
    await tester.pumpAndSettle();
    expect(key('wave-v1'), findsOneWidget);
    expect(key('drawing-sound'), findsNothing);
    expect(key('next-speech'), findsOneWidget);
  });

  testWidgets('next / previous speech start: buttons and Ctrl+arrows; the '
      'selected track or any speaker change', (tester) async {
    await open(tester, desktop);
    final s = session(tester);
    int at() => s.playback.positionMs;
    // Nothing selected: wherever someone starts.
    await tester.tap(key('next-speech'));
    await tester.pump();
    expect(at(), 1000);
    await tester.tap(key('next-speech'));
    await tester.pump();
    expect(at(), 6000);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(at(), 12000);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(at(), 15000); // Dana joins in
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(at(), 15000); // no later start
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(at(), 12000);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(key('previous-speech'));
    await tester.pump();
    expect(at(), 6000);
    // Dana's sound selected: only her starts.
    s.select(ItemKind.audio, 'v2');
    s.playback.seek(0);
    await tester.pumpAndSettle();
    expect(s.goToSpeechStart(forward: true), isTrue);
    expect(at(), 6000);
    expect(s.goToSpeechStart(forward: true), isTrue);
    expect(at(), 15000);
    expect(s.goToSpeechStart(forward: true), isFalse);
    // Plain arrows still step a frame.
    s.clearSelection();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(at(), lessThan(15000));
    expect(at(), greaterThan(14900));
  });

  testWidgets('dragging snaps to where speech starts and ends', (tester) async {
    await open(tester, desktop);
    final s = session(tester);
    // The music starts at 2 s; drag it right so that it would start at
    // about 4.9 s: it lands on 5.0 s, where Sam stops talking.
    s.select(ItemKind.audio, 'm1');
    await tester.pumpAndSettle();
    final music = tester.getRect(block('audio-m1'));
    final gesture = await tester.startGesture(music.centerLeft + const Offset(30, 0),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(134, 0)); // 2.9 s at 60 px a second
    await tester.pump();
    expect(s.project.audio.firstWhere((a) => a.id == 'm1').startMs, 5000);
    expect(s.snapLine.value, 5000);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('"Show sound waves" off: plain blocks, nothing is read; it is '
      'remembered', (tester) async {
    final fakes = fakesFor(talk());
    fakes.prefs.flags.add(kSoundWavesOffFlag);
    await open(tester, desktop, fakes: fakes);
    final s = session(tester);
    expect(s.showWaves.value, isFalse);
    expect(key('wave-v1'), findsNothing);
    expect(key('wave-a'), findsNothing);
    expect(key('next-speech'), findsNothing);
    expect(s.pictures.speakers, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    // The Playback menu on a computer.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await open(tester, desktop, fakes: fakes, menuBar: true);
      await tester.tap(find.widgetWithText(SubmenuButton, 'Playback'));
      await tester.pumpAndSettle();
      expect(find.text('Previous speech start'), findsOneWidget);
      expect(find.text('Next speech start'), findsOneWidget);
      expect(tester.widget<MenuItemButton>(key('menu-next-speech')).onPressed, isNull);
      await tester.tap(key('menu-waves'));
      await tester.pumpAndSettle();
      expect(fakes.prefs.flags.contains(kSoundWavesOffFlag), isFalse);
      expect(key('wave-v1'), findsOneWidget);
      await tester.tap(find.widgetWithText(SubmenuButton, 'Playback'));
      await tester.pumpAndSettle();
      expect(tester.widget<MenuItemButton>(key('menu-next-speech')).onPressed,
          isNotNull);
      await tester.tap(key('menu-next-speech'));
      await tester.pumpAndSettle();
      expect(session(tester).playback.positionMs, 1000);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone: waves on the timeline; More has the switch and the '
      'speech starts', (tester) async {
    final fakes = await open(tester, phone);
    final s = session(tester);
    expect(key('wave-v1'), findsOneWidget);
    expect(key('wave-a'), findsOneWidget);
    expect(key('next-speech'), findsNothing); // no room next to Play
    await fakes.screenshot(tester, 'timeline_waves_phone');
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(key('more-speech-starts'), findsOneWidget);
    await tester.tap(key('more-next-speech'));
    await tester.pumpAndSettle();
    expect(s.playback.positionMs, 1000);
    expect(key('more-sound-waves'), findsOneWidget);
    await tester.ensureVisible(key('more-sound-waves'));
    await tester.tap(key('more-sound-waves'));
    await tester.pumpAndSettle();
    expect(fakes.prefs.flags.contains(kSoundWavesOffFlag), isTrue);
    expect(s.showWaves.value, isFalse);
    expect(key('more-speech-starts'), findsNothing);
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();
    expect(key('wave-v1'), findsNothing);
  });

  testWidgets('many captions, zoomed out: slim marks, and the caption under '
      'the playhead as one readable line', (tester) async {
    final p = talk(length: 600000).copyWith(titles: [
      for (var i = 0; i < 300; i++)
        TitleOverlay(
            id: 'c$i',
            text: '${i.isEven ? 'Sam' : 'Dana'}: caption number $i of this talk',
            startMs: i * 2000,
            endMs: i * 2000 + 1800,
            kind: TitleKind.caption),
    ]);
    final fakes = await open(tester, const Size(1600, 900), project: p);
    final s = session(tester);
    // At 60 px a second a caption is 108 px: just too narrow to read.
    expect(key('caption-strip'), findsOneWidget);
    s.setZoom(160);
    await tester.pumpAndSettle();
    expect(key('caption-strip'), findsNothing);
    s.setZoom(6);
    await tester.pumpAndSettle();
    expect(key('caption-strip'), findsOneWidget);
    String strip() => tester.widget<Text>(key('caption-strip-text')).data!;
    s.playback.seek(84500);
    await tester.pumpAndSettle();
    expect(strip(), 'Sam: caption number 42 of this talk');
    s.playback.seek(87900); // between two captions
    await tester.pumpAndSettle();
    expect(strip(), '');
    // 1.8 s at 6 px a second = 11 px: a slim mark, not a box; it can
    // still be clicked, and says what it is when pointed at.
    final mark = tester.getSize(block('title-c40'));
    expect(mark.width, closeTo(10.8, 0.01));
    await tester.tap(block('title-c40'));
    await tester.pumpAndSettle();
    expect(s.selection.value, const Selection(ItemKind.title, 'c40'));
    expect(
        find.byWidgetPredicate((w) =>
            w is Tooltip && w.message == 'Sam: caption number 40 of this talk'),
        findsOneWidget);
    // A click on the strip selects the caption under the playhead.
    s.playback.seek(84500);
    await tester.pumpAndSettle();
    await tester.tap(key('caption-strip'));
    await tester.pumpAndSettle();
    expect(s.selection.value, const Selection(ItemKind.title, 'c42'));
    await fakes.screenshot(tester, 'timeline_many_captions');
  });
}
