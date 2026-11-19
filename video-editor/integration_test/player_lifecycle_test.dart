// Stress run of the editor's player lifecycle with the REAL media_kit
// players: open a project, play across a cut, delete clips down to one,
// leave, reopen... several times, then ask the app to quit.
//
// Written for a crash seen on macOS: libmpv aborts the whole app
// ("Broken API use: mpv_render_context_free() not called") when a player's
// core is destroyed while the video output (render context) made for it
// still exists. media_kit destroys the core 5 s after Player.dispose, so
// every round waits longer than that before going on.
//
// Linux, headless:
//   E2E_NULL_AO=1 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x800x24" \
//     flutter test integration_test/player_lifecycle_test.dart -d linux
//
// Look for "LIFECYCLE" lines in the output. An abort ends the test run
// with no result at all.
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/ui/app.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/playback/media_kit_backend.dart';
import 'package:clipforge/ui/playback/timeline_player.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

void log(String m) => debugPrint('LIFECYCLE: $m');

/// The real backend; counts what it made and gives mpv a null audio
/// output on machines without sound (E2E_NULL_AO=1).
class CountingBackend implements PlayerBackend {
  final MediaKitBackend inner = const MediaKitBackend();
  final Set<Player> videoCores = {};
  int videoMade = 0;
  int audioMade = 0;

  static void _nullAudio(MediaKitTimelinePlayer player) {
    if (Platform.environment['E2E_NULL_AO'] != '1') return;
    (player.player.platform as NativePlayer).setProperty('ao', 'null');
  }

  @override
  TimelinePlayer createVideoPlayer() {
    final player = inner.createVideoPlayer() as MediaKitTimelinePlayer;
    videoMade++;
    videoCores.add(player.player);
    _nullAudio(player);
    return player;
  }

  @override
  TimelinePlayer createAudioPlayer() {
    final player = inner.createAudioPlayer() as MediaKitTimelinePlayer;
    audioMade++;
    _nullAudio(player);
    return player;
  }

  @override
  Widget buildVideoSurface(TimelinePlayer videoPlayer) =>
      inner.buildVideoSurface(videoPlayer);
}

class NoFiles implements FileService {
  @override
  Future<List<PickedFile>> pickMedia() async => const [];
  @override
  Future<List<PickedFile>> pickAudio() async => const [];
  @override
  bool get canChooseSaveLocation => true;
  @override
  Future<String?> chooseSavePath(String fileName) async => null;
  @override
  Future<String> appExportPath(String fileName) async => fileName;
  @override
  Future<String?> saveCopy(String sourcePath, String fileName) async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('editor players survive open / play / delete / leave / quit',
      (tester) async {
    MediaKit.ensureInitialized();
    final outEnv = Platform.environment['E2E_OUT'];
    final out = outEnv != null
        ? (Directory(p.join(outEnv, 'lifecycle'))..createSync(recursive: true))
        : Directory.systemTemp.createTempSync('clipforge_lifecycle_');
    final fx = Directory(p.join(out.path, 'fixtures'))..createSync();
    final storeDir = Directory(p.join(out.path, 'store'));
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
    final rounds = int.tryParse(Platform.environment['LIFECYCLE_ROUNDS'] ?? '') ?? 5;

    final colours = ['red', 'blue', 'green'];
    final paths = [for (final c in colours) p.join(fx.path, '$c.mp4')];
    final song = p.join(fx.path, 'song.mp3');
    await tester.runAsync(() async {
      for (var i = 0; i < colours.length; i++) {
        final r = await Process.run('ffmpeg', [
          '-hide_banner', '-y', //
          '-f', 'lavfi', '-i', 'color=c=${colours[i]}:size=320x180:rate=25:duration=2',
          '-f', 'lavfi', '-i', 'sine=frequency=${300 + 100 * i}:duration=2',
          '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '25',
          '-c:a', 'aac', '-shortest', paths[i],
        ]);
        if (r.exitCode != 0) fail('ffmpeg: ${r.stderr}');
      }
      final r = await Process.run('ffmpeg', [
        '-hide_banner', '-y', '-f', 'lavfi', '-i', 'sine=frequency=220:duration=6', //
        '-c:a', 'libmp3lame', song,
      ]);
      if (r.exitCode != 0) fail('ffmpeg: ${r.stderr}');
    });

    final now = DateTime(2026, 11, 16);
    final project = Project(
      id: 'stress',
      name: 'Stress test',
      createdAt: now,
      updatedAt: now,
      originalWidth: 320,
      originalHeight: 180,
      clips: [
        for (var i = 0; i < paths.length; i++)
          Clip(
            id: 'c$i',
            type: ClipType.video,
            path: paths[i],
            sourceDurationMs: 2000,
            inMs: 0,
            outMs: 2000,
            width: 320,
            height: 180,
          ),
      ],
      audio: [
        AudioClip(
            id: 'm', path: song, sourceDurationMs: 6000, startMs: 500,
            inMs: 0, outMs: 5000),
      ],
    );
    final store = ProjectStore.atPath(storeDir.path);
    await tester.runAsync(() => store.save(project));

    final backend = CountingBackend();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        projectStoreProvider.overrideWith((ref) => store),
        fileServiceProvider.overrideWithValue(NoFiles()),
        playerBackendProvider.overrideWithValue(backend),
        // The first-launch tour question counts as answered.
        // (and no 1.15 notes or suggestions: this run is about players).
        appPrefsProvider.overrideWithValue(
            MemoryAppPrefs.settled(BuildInfo.current.version)),
      ],
      child: const ClipForgeApp(),
    ));

    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));
    Future<void> waitFor(bool Function() ok, String what,
        {int timeoutMs = 20000}) async {
      final sw = Stopwatch()..start();
      while (!ok()) {
        if (sw.elapsedMilliseconds > timeoutMs) fail('Timed out: $what');
        await wait(50);
      }
    }

    bool inEditor() => find.byType(PreviewView).evaluate().isNotEmpty;
    EditorSession session() =>
        tester.widget<PreviewView>(find.byType(PreviewView)).session;

    Future<void> openProject() async {
      await waitFor(() => find.text('Stress test').evaluate().isNotEmpty,
          'project on the home screen');
      await tester.tap(find.text('Stress test').first);
      await waitFor(inEditor, 'editor open');
      await waitFor(() => session().playback.videoPlayers.length == 2,
          'second video player');
    }

    for (var round = 1; round <= rounds; round++) {
      await openProject();
      final s = session();
      final pb = s.playback;
      // Play across the first cut (with the music), then stop.
      pb.seek(1200);
      await waitFor(() => pb.loadedVideoPath == paths[0], 'first clip loaded');
      pb.play();
      await waitFor(() => pb.positionMs > 2600, 'played across the cut',
          timeoutMs: 10000);
      pb.pause();
      log('round $round: played to ${pb.positionMs} ms, '
          '${pb.videoPlayers.length} video players');
      // Delete down to one clip: the second player has nothing left to do.
      s.editor.removeClip('c2');
      await wait(100);
      s.editor.removeClip('c1');
      await wait(300);
      expect(s.project.clips.length, 1);
      if (round.isEven) {
        // Leave while a file is still being opened.
        pb.seek(1500);
        pb.play();
      }
      await tester.tap(find.byTooltip('Back to projects'));
      await waitFor(() => !inEditor(), 'back on the home screen');
      // The project is put back for the next round.
      await tester.runAsync(() => store.save(project));
      // media_kit destroys a disposed player's core 5 s later: give it the
      // time, on the home screen with no video surface left.
      await wait(6000);
      log('round $round done: video players made ${backend.videoMade}, '
          'distinct video cores ${backend.videoCores.length}, '
          'music players made ${backend.audioMade}');
    }

    // Quit with the editor open and playing.
    await openProject();
    session().playback.play();
    await wait(800);
    final answer = await tester.binding.handleRequestAppExit();
    log('quit request answered: ${answer.name}');
    expect(answer, AppExitResponse.exit);
    await wait(6000);
    log('done: video players made ${backend.videoMade}, distinct video '
        'cores ${backend.videoCores.length}');
    // The editors borrowed the same two video players again and again; no
    // video player's core was destroyed (see VideoPlayerPool).
    expect(backend.videoCores.length, 2);
  });
}
