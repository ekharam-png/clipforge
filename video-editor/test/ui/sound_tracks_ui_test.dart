// Sound tracks in the editor, on a phone and a desktop screen: the track
// rows and their headers, adding / renaming / muting / solo, dragging a
// sound onto another track, "Separate sound to track…", the sound clip's
// options, the video size and Remove silences' sensitivity. Overflow
// errors fail these tests by themselves.
import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_jobs.dart';
import 'package:clipforge/media/silence_levels.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// An engine whose silence search has measured levels (the automatic
/// threshold), like the real ones.
class LevelEngine extends FakeMediaEngine implements SilenceJobEngine {
  final Map<String, SilenceLevels> silenceLevels = {};

  @override
  SilenceJob startSilenceDetection(String path,
      {double? thresholdDb,
      int minSilenceMs = 700,
      int audioTrack = 0,
      AudioChannel channel = AudioChannel.both,
      int fromMs = 0,
      int toMs = 0}) {
    final l = silenceLevels[path]!;
    return _Job(l, l.silences(thresholdDb: l.autoThresholdDb));
  }
}

class _Job implements SilenceJob {
  _Job(this.levels, this.found);
  @override
  final SilenceLevels levels;
  final List<SourceRange> found;
  @override
  Stream<double> get progress => const Stream.empty();
  @override
  Future<List<SourceRange>> get result async => found;
  @override
  Future<void> cancel() async {}
}

class LevelFakes extends Fakes {
  LevelFakes({super.projects});
  final LevelEngine _engine = LevelEngine();

  // ignore: overridden_fields
  @override
  LevelEngine get engine => _engine;
}

/// The project as the editor has it now (saving waits a moment).
Project now(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session.project;

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back to projects'));
  await tester.pumpAndSettle();
}

/// The sample project with a Voice track holding a separated sound of clip
/// a, and the music on a Music track.
Project withTracks() {
  final p = sampleProject();
  return p.copyWith(
    tracks: const [
      SoundTrack(id: 'voice', name: 'Voice', speech: true),
      SoundTrack(id: kMusicTrackId, name: 'Music', duck: true),
    ],
    clips: [p.clips.first.copyWith(muted: true), ...p.clips.skip(1)],
    audio: [
      ...p.audio,
      AudioClip(
        id: 's1',
        path: '/media/beach.mp4',
        sourceDurationMs: 60000,
        startMs: 0,
        inMs: 0,
        outMs: 6000,
        trackId: 'voice',
        sourceClipId: 'a',
        linked: true,
      ),
    ],
  );
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('track rows, add a track, the track menu on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size, project: withTracks());
      final phoneScreen = size == phone;
      // Rows: video, Voice, Music; each sound in its row.
      expect(find.byKey(const ValueKey('track-header-video')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-header-voice')), findsOneWidget);
      expect(find.byKey(const ValueKey('track-header-music')), findsOneWidget);
      final voiceRow = tester.getCenter(find.byKey(const ValueKey('track-header-voice'))).dy;
      final musicRow = tester.getCenter(find.byKey(const ValueKey('track-header-music'))).dy;
      expect(tester.getCenter(block('audio-s1')).dy, closeTo(voiceRow, 1));
      expect(tester.getCenter(block('audio-m1')).dy, closeTo(musicRow, 1));
      if (!phoneScreen) expect(find.text('Voice'), findsWidgets);
      await fakes.screenshot(tester, 'editor_${label}_sound_tracks');

      // Add a third track: Effects. Then no more.
      await tester.tap(find.byKey(const ValueKey('add-sound-track')));
      await tester.pumpAndSettle();
      expect(now(tester).soundTracks.map((t) => t.name),
          ['Voice', 'Music', 'Effects']);
      final add = tester.widget<TextButton>(find.byKey(const ValueKey('add-sound-track')));
      expect(add.onPressed, isNull);
      await waitForMessage(tester);

      // Mute and solo: buttons on the desktop, the menu on a phone.
      if (!phoneScreen) {
        await tester.tap(find.byKey(const ValueKey('track-mute-music')));
        await tester.pumpAndSettle();
        expect(now(tester).trackById(kMusicTrackId)!.muted, isTrue);
        await tester.tap(find.byKey(const ValueKey('track-solo-voice')));
        await tester.pumpAndSettle();
        expect(now(tester).trackById('voice')!.solo, isTrue);
        await tester.tap(find.byKey(const ValueKey('track-solo-voice')));
        await tester.tap(find.byKey(const ValueKey('track-mute-music')));
        await tester.pumpAndSettle();
      }

      // The menu: rename, volume, solo, lower under speech, delete.
      await tester.tap(find.byKey(const ValueKey('track-header-music')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('track-name')), 'Songs');
      await tester.tap(find.byKey(const ValueKey('track-menu-mute')));
      await tester.pumpAndSettle();
      expect(now(tester).trackById(kMusicTrackId)!.muted, isTrue);
      await tester.ensureVisible(find.byKey(const ValueKey('track-menu-duck')));
      await tester.tap(find.byKey(const ValueKey('track-menu-duck')));
      await tester.pumpAndSettle();
      expect(now(tester).trackById(kMusicTrackId)!.duck, isFalse);
      // A track with sound cannot be deleted.
      await tester.ensureVisible(find.byKey(const ValueKey('track-menu-delete')));
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('track-menu-delete'))).onPressed,
          isNull);
      await fakes.screenshot(tester, 'editor_${label}_track_menu');
      if (phoneScreen) {
        await tester.tapAt(const Offset(10, 60));
      } else {
        await tester.tap(find.text('Done'));
      }
      await tester.pumpAndSettle();
      expect(now(tester).trackById(kMusicTrackId)!.name, 'Songs');

      // The empty Effects track can be deleted.
      final fx = now(tester).soundTracks.last.id;
      await tester.tap(find.byKey(ValueKey('track-header-$fx')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('track-menu-delete')));
      await tester.tap(find.byKey(const ValueKey('track-menu-delete')));
      await tester.pumpAndSettle();
      if (!phoneScreen && find.text('Done').evaluate().isNotEmpty) {
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
      expect(now(tester).soundTracks.length, 2);

      // The video sound: muted from its header menu.
      await tester.tap(find.byKey(const ValueKey('track-header-video')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('track-menu-mute')));
      await tester.pumpAndSettle();
      expect(now(tester).videoSound.muted, isTrue);
      expect(find.byKey(const ValueKey('track-name')), findsNothing);
    });

    testWidgets('drag a sound onto another track on a $label screen',
        (tester) async {
      await openEditor(tester, size, project: withTracks());
      final from = tester.getTopLeft(block('audio-m1')) + const Offset(30, 15);
      await tester.tapAt(from);
      await tester.pumpAndSettle();
      final voiceRow = tester.getCenter(find.byKey(const ValueKey('track-header-voice'))).dy;
      // Up onto the Voice row; it is busy 0..6 s, so the music lands at the
      // nearest free place there.
      final g = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        await g.moveTo(Offset(from.dx + 6 * i, from.dy + (voiceRow - from.dy) * i / 5));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      final m = now(tester).audio.firstWhere((a) => a.id == 'm1');
      expect(m.trackId, 'voice');
      final voice = now(tester).clipsOnTrack('voice');
      for (var i = 1; i < voice.length; i++) {
        expect(voice[i].startMs, greaterThanOrEqualTo(voice[i - 1].endMs));
      }
      expect(tester.getRect(block('audio-m1')).center.dy, closeTo(voiceRow, 1));
      // One undo step.
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(now(tester).audio.firstWhere((a) => a.id == 'm1').trackId, kMusicTrackId);
    });

    testWidgets('separate sound, then the sound\'s options on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Sound');
      await tester.ensureVisible(find.byKey(const ValueKey('separate-sound')));
      await tester.tap(find.byKey(const ValueKey('separate-sound')));
      await tester.pumpAndSettle();
      expect(find.text('A new Voice track'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_separate_dialog');
      await tester.tap(find.byKey(const ValueKey('separate-confirm')));
      await tester.pumpAndSettle();
      var p = now(tester);
      final s = p.audio.firstWhere((a) => a.sourceClipId == 'a');
      expect(p.trackById(s.trackId)!.name, 'Voice');
      expect(p.clips.first.muted, isTrue);
      expect(s.linked, isTrue);
      // The new sound is selected; its settings show the sound options.
      if (size == phone) {
        await tester.tapAt(const Offset(10, 60));
        await tester.pumpAndSettle();
        await waitForMessage(tester);
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Edit sound').evaluate().isNotEmpty ||
          find.text('Sound').evaluate().isNotEmpty, isTrue);
      await tester.ensureVisible(find.byKey(const ValueKey('sound-denoise')));
      await tester.tap(find.byKey(const ValueKey('sound-denoise')));
      await tester.pumpAndSettle();
      p = now(tester);
      expect(p.audio.firstWhere((a) => a.id == s.id).denoise, isTrue);
      await fakes.screenshot(tester, 'editor_${label}_sound_options');
      await tester.ensureVisible(find.byKey(const ValueKey('reattach-from-sound')));
      await tester.tap(find.byKey(const ValueKey('reattach-from-sound')));
      await tester.pumpAndSettle();
      p = now(tester);
      expect(p.audio.where((a) => a.sourceClipId == 'a'), isEmpty);
      expect(p.clips.first.muted, isFalse);
      expect(p.clips.first.denoise, isTrue);
    });

    testWidgets('video size in the Shape menu on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size, missingFiles: const {});
      if (size == phone) {
        await tapProjectMenu(tester, 'Shape and size');
        await tester
            .ensureVisible(find.byKey(const ValueKey('video-size-p1080')));
      } else {
        await tester.tap(
            find.byTooltip('Shape of the video: upright, wide or square'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-size-p1080')));
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      expect(now(tester).videoSize, VideoSize.p1080);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Video size'), findsOneWidget);
      await fakes.screenshot(tester, 'export_${label}_video_size');
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(now(tester).videoSize, VideoSize.p720);
      expect(find.textContaining('1280 × 720'), findsOneWidget);
    });
  }

  testWidgets('remove silences: sensitivity without listening again',
      (tester) async {
    useScreen(tester, desktop);
    final fakes = LevelFakes(projects: [sampleProject()]);
    await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
    await tester.pumpAndSettle();
    // Levels: 1 s loud, 1 s at -40 dB, 1 s loud, 1 s at -28 dB, loud.
    final levels = <double>[];
    final starts = <int>[];
    for (var t = 0; t < 6000; t += kLevelWindowMs) {
      starts.add(t);
      levels.add(switch (t ~/ 1000) { 1 => -40, 3 => -28, _ => -12 });
    }
    fakes.engine.silenceLevels['/media/beach.mp4'] =
        SilenceLevels(fromMs: 0, spanMs: 6000, starts: starts, levels: levels);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(find.text('Remove silences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove silences'));
    await tester.pumpAndSettle();
    expect(find.text('Sensitivity'), findsOneWidget);
    final auto = find.textContaining('Found');
    expect(auto, findsOneWidget);
    final before = (tester.widget(auto) as Text).data!;
    await tester.tap(find.text('More cuts'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('silence-threshold')), findsOneWidget);
    final after = (tester.widget(find.textContaining('Found')) as Text).data!;
    expect(after, isNot(before));
    await fakes.screenshot(tester, 'editor_desktop_silence_sensitivity');
  });
}
