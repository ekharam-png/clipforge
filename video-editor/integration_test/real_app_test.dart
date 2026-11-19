// End-to-end run of the REAL app: real media_kit (libmpv) players, real
// ProcessMediaEngine (system ffmpeg / ffprobe) and a real file-backed
// ProjectStore. Only the file dialogs are replaced.
//
// Linux, headless:
//   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x800x24" \
//     flutter test integration_test/real_app_test.dart -d linux
//
// Screenshots and the exported file go to $E2E_OUT (default: a temp dir).
// E2E_NULL_AO=1 gives mpv a null audio output (machines without sound).
//
// Besides the basic flow (import, play, seek, trim, split, export) it
// checks the preview of speed, cuts between files, transitions, colour,
// zoom, blurred backdrop and titles by reading pixels of what Flutter draws
// (plain red and blue fixtures make a frame recognisable from one pixel).
// Lines to look for in the output: BOUNDARY, HARD CUT, SPEED, CROSSFADE,
// SLIDE, FADE THROUGH BLACK, LOOK, PORTRAIT, BLUR, SELECT, TITLE 9:16.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/claude/helper_install.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/ui/about.dart';
import 'package:clipforge/ui/app.dart';
import 'package:clipforge/ui/claude/claude_helper.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/app_settings.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/media/processed_sound_cache.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/sound_renders.dart';
import 'package:clipforge/ui/playback/media_kit_backend.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:clipforge/ui/playback/timeline_player.dart';
import 'package:clipforge/ui/publish_service.dart';
import 'package:clipforge/ui/services.dart';
import 'package:clipforge/ui/speech/speech_service.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

void log(String m) => debugPrint('E2E: $m');

class FixtureFileService implements FileService {
  FixtureFileService(this.savePath);
  List<PickedFile> media = [];
  List<PickedFile> audio = [];
  final String savePath;

  @override
  Future<List<PickedFile>> pickMedia() async => media;
  @override
  Future<List<PickedFile>> pickAudio() async => audio;
  @override
  bool get canChooseSaveLocation => true;
  @override
  Future<String?> chooseSavePath(String fileName) async => savePath;
  @override
  Future<String> appExportPath(String fileName) async => savePath;
  @override
  Future<String?> saveCopy(String sourcePath, String fileName) async => null;
}

/// "Export several…" goes into [folder]; nothing else is offered.
class KitFolder implements PublishService {
  KitFolder(this.folder);
  final String folder;
  @override
  bool get canShare => false;
  @override
  Future<String?> chooseFolder() async => folder;
  @override
  Future<String> appKitFolder(String name) async => folder;
  @override
  Future<String?> saveToAlbum(String path, String album) async => null;
  @override
  Future<void> showInFolder(String path) async {}
  @override
  Future<void> openUrl(String url) async {}
  @override
  Future<bool> share(List<String> paths, {String? text, String? subject}) async => false;
}

/// The real media_kit backend; it only remembers the players it made so the
/// test can look at their state.
class ObservedBackend implements PlayerBackend {
  final MediaKitBackend inner = const MediaKitBackend();

  /// Warnings and errors mpv logged, for checks on the audio filters.
  final List<String> mpvProblems = [];
  final List<MediaKitTimelinePlayer> videoPlayers = [];
  final List<MediaKitTimelinePlayer> audioPlayers = [];

  /// With E2E_NULL_AO=1 mpv plays sound into its own real-time "null"
  /// output, for machines without any audio device.
  static void _useNullAudio(MediaKitTimelinePlayer player) {
    if (Platform.environment['E2E_NULL_AO'] != '1') return;
    (player.player.platform as NativePlayer).setProperty('ao', 'null');
  }

  @override
  TimelinePlayer createVideoPlayer() {
    final player = inner.createVideoPlayer() as MediaKitTimelinePlayer;
    final n = videoPlayers.length;
    videoPlayers.add(player);
    _useNullAudio(player);
    player.player.stream.error.listen((e) => log('VIDEO PLAYER $n ERROR: $e'));
    player.player.stream.log.listen((e) {
      log('mpv$n[${e.level}] ${e.prefix}: ${e.text}');
      if (e.level == 'error' || e.level == 'warn' || e.level == 'fatal') {
        mpvProblems.add('${e.prefix}: ${e.text}');
      }
    });
    return player;
  }

  @override
  TimelinePlayer createAudioPlayer() {
    final player = inner.createAudioPlayer() as MediaKitTimelinePlayer;
    audioPlayers.add(player);
    _useNullAudio(player);
    player.player.stream.error.listen((e) => log('MUSIC PLAYER ERROR: $e'));
    return player;
  }

  @override
  Widget buildVideoSurface(TimelinePlayer videoPlayer) =>
      inner.buildVideoSurface(videoPlayer);
}

Future<void> ffmpeg(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-hide_banner', '-y', ...args]);
  if (r.exitCode != 0) fail('ffmpeg ${args.join(' ')}\n${r.stderr}');
}

Future<Map<String, dynamic>> ffprobe(String path) async {
  final r = await Process.run('ffprobe', [
    '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path, //
  ]);
  if (r.exitCode != 0) fail('ffprobe $path\n${r.stderr}');
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

/// One sample of the playhead during real playback.
typedef Sample = ({int wallMs, int posMs, int srcMs, bool playing, String music});

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Frames are drawn in real time, like in the running app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('real app: import, play, seek, edit, export', (tester) async {
    MediaKit.ensureInitialized();
    final outEnv = Platform.environment['E2E_OUT'];
    final out = outEnv != null
        ? (Directory(outEnv)..createSync(recursive: true))
        : Directory.systemTemp.createTempSync('clipforge_e2e_');
    final fx = Directory(p.join(out.path, 'fixtures'))..createSync();
    final xdgData = p.join(out.path, 'xdg-data');
    if (Directory(xdgData).existsSync()) Directory(xdgData).deleteSync(recursive: true);
    final storeDir = Directory(p.join(out.path, 'store'));
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
    final shotKey = GlobalKey();
    final kitDir = p.join(out.path, 'kit');
    if (Directory(kitDir).existsSync()) Directory(kitDir).deleteSync(recursive: true);

    // Fixtures ------------------------------------------------------------
    final land = p.join(fx.path, 'land.mp4');
    final port = p.join(fx.path, 'port.mp4');
    final photo = p.join(fx.path, 'photo.png');
    final song = p.join(fx.path, 'song.mp3');
    // Plain colours, so that a frame of the preview can be told apart by
    // looking at a single pixel.
    final red = p.join(fx.path, 'red.mp4');
    final blue = p.join(fx.path, 'blue.mp4');
    const x264 = ['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '25'];
    await tester.runAsync(() async {
      await ffmpeg([
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=4', //
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=4',
        ...x264, '-c:a', 'aac', '-shortest', land,
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'testsrc=size=360x640:rate=25:duration=3', //
        '-f', 'lavfi', '-i', 'sine=frequency=880:duration=3',
        ...x264, '-c:a', 'aac', '-shortest', port,
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'smptebars=size=800x600', '-frames:v', '1', photo, //
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'color=c=red:size=640x360:rate=25:duration=4', //
        '-f', 'lavfi', '-i', 'sine=frequency=330:duration=4',
        ...x264, '-c:a', 'aac', '-shortest', red,
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'color=c=blue:size=640x360:rate=25:duration=3', //
        '-f', 'lavfi', '-i', 'sine=frequency=660:duration=3',
        ...x264, '-c:a', 'aac', '-shortest', blue,
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', 'sine=frequency=220:duration=6', '-c:a', //
        'libmp3lame', song,
      ]);
    });

    final exportPath = p.join(out.path, 'export.mp4');
    if (File(exportPath).existsSync()) File(exportPath).deleteSync();
    final files = FixtureFileService(exportPath);
    final backend = ObservedBackend();

    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));

    Future<void> waitFor(bool Function() ok, String what,
        {int timeoutMs = 15000}) async {
      final sw = Stopwatch()..start();
      while (!ok()) {
        if (sw.elapsedMilliseconds > timeoutMs) fail('Timed out: $what');
        await wait(50);
      }
    }

    Future<void> shot(String name) async {
      // 1. What Flutter itself composites.
      try {
        final boundary = shotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png));
        File(p.join(out.path, '$name-flutter.png'))
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      } catch (e) {
        log('flutter capture of $name failed: $e');
      }
      // 2. What is on the X display.
      final display = Platform.environment['DISPLAY'];
      if (display != null) {
        final r = await tester.runAsync(() => Process.run('import',
            ['-window', 'root', p.join(out.path, '$name-x11.png')]));
        if (r!.exitCode != 0) log('x11 capture of $name failed: ${r.stderr}');
      }
    }

    // App -----------------------------------------------------------------
    await tester.pumpWidget(ProviderScope(
      overrides: [
        projectStoreProvider
            .overrideWith((ref) => ProjectStore.atPath(storeDir.path)),
        fileServiceProvider.overrideWithValue(files),
        publishServiceProvider.overrideWithValue(KitFolder(kitDir)),
        playerBackendProvider.overrideWithValue(backend),
        // The first-launch tour question counts as answered.
        // No "What moved" note, and suggestions off until step 4b turns
        // them on (their line would move what the other steps aim at).
        appPrefsProvider.overrideWithValue(MemoryAppPrefs.settled('1.11.0')),
        // Processed clip sound goes to the run's folder, not the user's.
        processedSoundCacheProvider.overrideWithValue(FileProcessedSoundCache(
            () async => p.join(out.path, 'media'))),
        // Speech-to-text (1.11): the real service, with its packs and
        // settings in the run's folder (step 7j puts a pretend speech
        // program there).
        speechServiceProvider.overrideWithValue(DesktopSpeechService(
            rootDir: p.join(out.path, 'ClipForge'),
            projectsDir: storeDir.path)),
        // 1.12 updates: a release build (139) that is told a newer version
        // (142) exists; the check itself is not sent to the internet.
        buildInfoProvider.overrideWithValue(
            const BuildInfo(version: '1.11.0', buildNumber: '139', channel: 'ci')),
        updateFetcherProvider.overrideWithValue(() async => const UpdateInfo(
            version: '1.12.0',
            build: 142,
            notesUrl: 'https://example.org/releases/tag/v1.12.0')),
        // 1.12 Claude helper: the real service; its per-user folder is in
        // the run's folder. It installs the helper only when this build
        // carries the extension file (assets/claude/README.txt).
        claudeHelperProvider.overrideWithValue(ClaudeHelperService(
            build: const BuildInfo(version: '1.12.0', buildNumber: '1'),
            environment: {...Platform.environment, 'XDG_DATA_HOME': xdgData})),
      ],
      child: RepaintBoundary(key: shotKey, child: const ClipForgeApp()),
    ));
    await waitFor(() => find.text('New project').evaluate().isNotEmpty,
        'home screen');

    // 0. Updates and the Claude helper (1.12) ------------------------------
    await waitFor(
        () => find.byKey(const ValueKey('update-banner')).evaluate().isNotEmpty,
        'the update banner');
    expect(find.text('Version 1.12.0 is available'), findsOneWidget);
    await shot('00-update-banner');
    log('step 0: the banner "Version 1.12.0 is available" is on the project list');
    final claudeDir = claudeStableDir('linux', {'XDG_DATA_HOME': xdgData})!;
    var hasBundle = true;
    try {
      await rootBundle.load(kClaudeBundleAsset);
    } catch (_) {
      hasBundle = false;
    }
    if (hasBundle) {
      await waitFor(() => helperStatus(claudeDir, 'linux').installed,
          'the Claude helper in its per-user folder');
      final installed = helperStatus(claudeDir, 'linux');
      // What Claude would start: the stable path. It hands over to the
      // version the app just installed and answers with its version.
      final version = await tester.runAsync(() => Process.run(
          installed.launcherPath, const ['--version'],
          environment: const {'CLIPFORGE_MCP_NO_HANDOVER': ''}));
      expect(version!.exitCode, 0, reason: '${version.stderr}');
      expect('${version.stdout}', contains('clipforge-mcp'));
      expect(File(p.join(p.dirname(installed.current!.path), 'fonts', 'DejaVuSans.ttf'))
          .existsSync(), isTrue);
      log('step 0: the app installed the Claude helper at ${installed.launcherPath} '
          '(${'${version.stdout}'.trim()})');
    } else {
      log('step 0: this build carries no Claude extension file; helper install not run');
    }

    await tester.tap(find.text('New project').first);
    await waitFor(
        () => find.text('Add videos or photos').evaluate().isNotEmpty,
        'empty editor');

    EditorSession session() =>
        tester.widget<PreviewView>(find.byType(PreviewView)).session;
    final s = session();
    final PlaybackController pb = s.playback;

    /// The player of the clip under the playhead. The editor keeps two
    /// video players and swaps them at cuts.
    Player fp() =>
        (pb.videoPlayers[pb.frontDeck] as MediaKitTimelinePlayer).player;
    bool anyVideoPlaying() =>
        backend.videoPlayers.any((v) => v.player.state.playing);

    // 1. Import -------------------------------------------------------------
    files.media = [
      PickedFile(land, 'land.mp4'),
      PickedFile(port, 'port.mp4'),
      PickedFile(photo, 'photo.png'),
    ];
    await tester.tap(find.text('Add videos or photos'));
    await waitFor(() => s.project.clips.length == 3, 'import of 3 clips');
    await wait(300);
    for (final c in s.project.clips) {
      log('clip ${c.type.name} ${p.basename(c.path)} ${c.width}x${c.height} '
          'in=${c.inMs} out=${c.outMs} src=${c.sourceDurationMs} '
          'audio=${c.hasAudio}');
    }
    final c0 = s.project.clips[0], c1 = s.project.clips[1], c2 = s.project.clips[2];
    expect(c0.type, ClipType.video);
    expect((c0.width, c0.height), (640, 360));
    expect(c0.durationMs, closeTo(4000, 60));
    expect(c0.hasAudio, isTrue);
    expect((c1.width, c1.height), (360, 640));
    expect(c1.durationMs, closeTo(3000, 60));
    expect(c2.type, ClipType.photo);
    expect((c2.width, c2.height), (800, 600));
    expect(c2.durationMs, 3000);
    expect(find.text('A file could not be added'), findsNothing);

    // Thumbnails.
    for (final path in [land, port]) {
      final t = await tester.runAsync(() => s.thumbnails.get(path));
      log('thumbnail for ${p.basename(path)}: $t '
          '(${t == null ? 'none' : '${File(t).lengthSync()} bytes'})');
      expect(t, isNotNull);
      expect(File(t!).lengthSync(), greaterThan(500));
    }
    await wait(500);
    final thumbImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is ResizeImage || i.image is FileImage)
        .length;
    log('Image widgets on screen after import: $thumbImages');
    await shot('01-imported');

    // Music at 1s, a title at 0.
    files.audio = [PickedFile(song, 'song.mp3')];
    pb.seek(1000);
    await wait(200);
    await tester.tap(find.text('Music').first);
    // 1.8: "Add music" opens on Find free music; My files has the picker.
    await waitFor(() => find.text('My files').evaluate().isNotEmpty,
        'add music window');
    await tester.tap(find.text('My files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a music file…'));
    // 1.10: "What is this sound?" - Music is chosen for a song.
    await waitFor(() => find.text('What is this sound?').evaluate().isNotEmpty,
        'the sound question');
    expect(find.text('Add and line up'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await waitFor(() => s.project.audio.length == 1, 'music import');
    final music = s.project.audio.single;
    log('music start=${music.startMs} in=${music.inMs} out=${music.outMs} '
        'src=${music.sourceDurationMs}');
    expect(music.startMs, 1000);
    expect(music.durationMs, closeTo(6000, 120));
    s.clearSelection();
    pb.seek(0);
    await wait(300);
    await tester.tap(find.text('Title').first);
    await waitFor(() => s.project.titles.length == 1, 'title');
    s.clearSelection();
    await wait(500);

    final total = pb.durationMs;
    log('timeline duration $total ms');

    // 2. Playback -----------------------------------------------------------
    String musicState() => backend.audioPlayers.isEmpty
        ? '-'
        : [
            for (final a in backend.audioPlayers)
              '${a.player.state.playing ? 'P' : 's'}'
                  '${a.player.state.position.inMilliseconds}'
          ].join(',');

    Sample sample(int wallMs) => (
          wallMs: wallMs,
          posMs: pb.positionMs,
          srcMs: fp().state.position.inMilliseconds,
          playing: pb.playing,
          music: musicState(),
        );

    /// Every change of the playhead with the time it happened, which is
    /// finer than the samples taken between frames.
    final trace = <(int, int)>[];
    final traceClock = Stopwatch()..start();
    pb.position.addListener(
        () => trace.add((traceClock.elapsedMicroseconds, pb.positionMs)));

    /// How playback crossed timeline position [at] in the trace since
    /// [fromIndex]: wall time for the 400 ms around it minus 400 (time
    /// lost), and the longest time the playhead stood still in there.
    ({int lostMs, int longestGapMs}) crossing(int fromIndex, int at) {
      final part = trace
          .skip(fromIndex)
          .where((e) => e.$2 >= at - 200 && e.$2 <= at + 200)
          .toList();
      if (part.length < 2) return (lostMs: -1, longestGapMs: -1);
      var gap = 0;
      for (var i = 1; i < part.length; i++) {
        gap = math.max(gap, part[i].$1 - part[i - 1].$1);
      }
      final wall = part.last.$1 - part.first.$1;
      final timeline = part.last.$2 - part.first.$2;
      return (
        lostMs: ((wall - timeline * 1000) / 1000).round(),
        longestGapMs: (gap / 1000).round()
      );
    }

    final frames = <(String, ui.Image)>[];

    /// Samples the playhead every ~40 ms. While [grab] says so, also keeps
    /// what Flutter draws (saved later by [flushFrames]).
    Future<List<Sample>> record({
      required bool Function() until,
      int timeoutMs = 30000,
      bool Function()? grab,
      String grabName = 'frame',
    }) async {
      final samples = <Sample>[];
      final sw = Stopwatch()..start();
      while (!until()) {
        if (sw.elapsedMilliseconds > timeoutMs) break;
        samples.add(sample(sw.elapsedMilliseconds));
        if (grab != null && grab() && frames.length < 40) {
          final boundary = shotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          frames.add((
            '$grabName-w${sw.elapsedMilliseconds}-p${pb.positionMs}',
            boundary.toImageSync(pixelRatio: 0.5)
          ));
        }
        await wait(40);
      }
      samples.add(sample(sw.elapsedMilliseconds));
      return samples;
    }

    Future<void> flushFrames() async {
      for (final (name, image) in frames) {
        final bytes = await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
        File(p.join(out.path, '$name.png'))
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      }
      frames.clear();
    }

    void report(String name, List<Sample> samples) {
      log('--- $name: ${samples.length} samples, '
          '${samples.last.wallMs} ms wall, '
          'pos ${samples.first.posMs} -> ${samples.last.posMs}');
      // Longest time the playhead did not move, and where.
      var longest = 0, at = 0, since = samples.first.wallMs;
      for (var i = 1; i < samples.length; i++) {
        if (samples[i].posMs != samples[i - 1].posMs) {
          since = samples[i].wallMs;
        } else if (samples[i].wallMs - since > longest) {
          longest = samples[i].wallMs - since;
          at = samples[i].posMs;
        }
      }
      log('    longest stall $longest ms at pos $at');
      final b = StringBuffer();
      for (var i = 0; i < samples.length; i += 5) {
        b.write('${samples[i].wallMs}:${samples[i].posMs}/${samples[i].srcMs}'
            '/${samples[i].music} ');
      }
      log('    wall:pos/src/music  $b');
    }

    /// Wall time at which the playhead first reached [posMs].
    int reached(List<Sample> samples, int posMs) => samples
        .firstWhere((x) => x.posMs >= posMs, orElse: () => samples.last)
        .wallMs;

    Future<void> tapPlay() async {
      await tester.tap(find.byTooltip('Play'));
    }

    await tester.tap(find.byTooltip('Go to start'));
    await wait(800);
    log('before play: pos=${pb.positionMs} player=${fp().state.position} '
        '${fp().state.width}x${fp().state.height} '
        'playing=${fp().state.playing}');
    await shot('02-paused-at-start');

    final fullFrom = trace.length;
    await tapPlay();
    final full = await record(
      until: () => !pb.playing,
      grab: () =>
          (pb.positionMs > 3850 && pb.positionMs < 4500) ||
          (pb.positionMs > 6850 && pb.positionMs < 7200),
      grabName: 'boundary',
    );
    await flushFrames();
    report('full play', full);
    log('full play: reached 1000 at ${reached(full, 1000)}, '
        '3900 at ${reached(full, 3900)}, 4000 at ${reached(full, 4000)}, '
        '4200 at ${reached(full, 4200)}, 6900 at ${reached(full, 6900)}, '
        '7000 at ${reached(full, 7000)}, 9900 at ${reached(full, 9900)}, '
        'end at ${full.last.wallMs}');
    // Time lost at the cut between the two video files, and at the cut to
    // the photo: wall time for 400 ms of timeline around it, minus 400.
    final vv = crossing(fullFrom, 4000), vp = crossing(fullFrom, 7000);
    log('BOUNDARY video->video (land->port at 4000): ${vv.lostMs} ms lost '
        'over 3800..4200, playhead stood still for at most '
        '${vv.longestGapMs} ms; video->photo (at 7000): ${vp.lostMs} ms '
        'lost, longest standstill ${vp.longestGapMs} ms');
    expect(vv.lostMs, lessThan(150),
        reason: 'the cut between two files must not hold playback up');
    log('video players in use: ${backend.videoPlayers.length}');
    expect(backend.videoPlayers.length, 2);
    if (Platform.environment['E2E_NULL_AO'] == '1') {
      // With an audio output the music player really runs: it must be in
      // step with the playhead (music starts at 1000 on the timeline).
      final music = backend.audioPlayers.single.player;
      expect(music.state.position.inMilliseconds, greaterThan(5500),
          reason: 'the music must have played through');
      final mid = full.where((x) => x.posMs > 1800 && x.posMs < 3800);
      for (final x in mid) {
        expect(x.music.startsWith('P'), isTrue,
            reason: 'music must be playing at ${x.posMs}');
        final at = int.parse(x.music.substring(1));
        expect(at, closeTo(x.posMs - 1000, 250),
            reason: 'music position at timeline ${x.posMs}');
      }
    }
    expect(pb.playing, isFalse, reason: 'playback must stop at the end');
    expect(pb.positionMs, total);
    expect(full.last.wallMs, lessThan(total + 3000),
        reason: 'timeline of $total ms took ${full.last.wallMs} ms');
    expect(full.last.wallMs, greaterThan(total - 500));
    await wait(500);
    log('after end: player playing=${fp().state.playing}');

    // Seek while paused: middle of the 2nd clip.
    pb.seek(5500);
    await wait(1200);
    log('paused seek 5500: pos=${pb.positionMs} clip=${pb.clipIndex} '
        'player=${fp().state.position.inMilliseconds} '
        '${fp().state.width}x${fp().state.height} '
        'playing=${fp().state.playing}');
    expect(pb.positionMs, 5500);
    expect(fp().state.position.inMilliseconds, closeTo(1500, 100));
    expect((fp().state.width, fp().state.height), (360, 640));
    await shot('03-paused-portrait-5500');

    // Play from there, pause after ~1s.
    await tapPlay();
    final part = await record(until: () => pb.positionMs >= 6400, timeoutMs: 6000);
    await tester.tap(find.byTooltip('Pause'));
    report('play from 5500', part);
    final pausedAt = pb.positionMs;
    await wait(800);
    log('paused at $pausedAt, 800 ms later pos=${pb.positionMs} '
        'player=${fp().state.position.inMilliseconds} '
        'playing=${fp().state.playing}');
    expect(pb.playing, isFalse);
    expect(pb.positionMs, closeTo(pausedAt, 80));
    expect(fp().state.playing, isFalse);
    expect(part.last.wallMs, lessThan(2500));

    // Seek while playing: into the photo.
    await tapPlay();
    await wait(300);
    pb.seek(8000);
    final tail = await record(until: () => !pb.playing, timeoutMs: 8000);
    report('seek into photo while playing', tail);
    expect(tail.first.posMs, closeTo(8000, 100));
    expect(pb.positionMs, total);
    expect(tail.last.wallMs, closeTo(2000, 400));
    await wait(300);
    expect(anyVideoPlaying(), isFalse,
        reason: 'video players must be paused while the photo shows');

    // Seek from the photo back into the first clip while playing.
    pb.seek(8500);
    await wait(200);
    await shot('04-photo-8500');
    await tapPlay();
    await wait(300);
    pb.seek(2000);
    final back = await record(until: () => pb.positionMs >= 3000, timeoutMs: 5000);
    report('seek back to 2000 while playing', back);
    expect(back.last.posMs, greaterThanOrEqualTo(3000));
    expect(back.last.wallMs, lessThan(2500));
    await tester.tap(find.byTooltip('Pause'));
    await wait(300);

    // Trim: first clip starts at 1000 ms of its file.
    s.editor.trimClip(c0.id, inMs: 1000);
    await wait(300);
    expect(s.project.clips[0].inMs, 1000);
    final total2 = pb.durationMs;
    pb.seek(0);
    await wait(1000);
    log('trimmed, paused at 0: player=${fp().state.position.inMilliseconds}');
    expect(fp().state.position.inMilliseconds, closeTo(1000, 100));
    await tapPlay();
    final trimmed = await record(until: () => pb.positionMs >= 1000, timeoutMs: 5000);
    report('trimmed clip from its in point', trimmed);
    expect(trimmed.last.srcMs, closeTo(2000, 250));
    expect(trimmed.last.wallMs, closeTo(1000, 500));
    await tester.tap(find.byTooltip('Pause'));
    await wait(300);

    // Split the first clip at 1500 through the UI, then play across it.
    pb.seek(1500);
    await wait(500);
    await tester.tap(find.text('Split').first);
    await wait(300);
    expect(s.project.clips.length, 4);
    log('split: ${[for (final c in s.project.clips) '${c.inMs}-${c.outMs}']}');
    expect(pb.durationMs, total2);
    pb.seek(500);
    await wait(600);
    await tapPlay();
    final split = await record(until: () => pb.positionMs >= 2500, timeoutMs: 6000);
    report('across the split', split);
    expect(split.last.wallMs, closeTo(2000, 500));
    // Let it run on into the second file and the photo, to the end.
    final rest = await record(until: () => !pb.playing, timeoutMs: 15000);
    report('rest after split', rest);
    expect(pb.positionMs, total2);

    // 3b. Tapping a clip on the timeline selects it AND shows it: the
    // playhead goes to its first frame and the player loads that file.
    pb.seek(0);
    await wait(500);
    final tapped = s.project.clips[2];
    expect(tapped.path, port);
    await tester.tap(find.byKey(ValueKey('clip-${tapped.id}')));
    await wait(100);
    expect(s.selectedClip?.id, tapped.id);
    expect(pb.positionMs, s.project.clipStartMs(2));
    await waitFor(
        () =>
            pb.loadedVideoPath == port &&
            (fp().state.position.inMilliseconds - tapped.inMs).abs() < 150,
        'the tapped clip in the preview');
    log('SELECT: playhead ${pb.positionMs} (clip starts at '
        '${s.project.clipStartMs(2)}), player shows '
        '${p.basename(pb.loadedVideoPath!)} at '
        '${fp().state.position.inMilliseconds} ms');
    // Inside the clip the playhead is left alone.
    pb.seek(s.project.clipStartMs(2) + 1000);
    await wait(300);
    await tester.tap(find.byKey(ValueKey('clip-${tapped.id}')));
    await wait(100);
    expect(pb.positionMs, s.project.clipStartMs(2) + 1000);
    s.clearSelection();
    await shot('04b-selected-clip-shown');

    // 4. Picture ------------------------------------------------------------
    pb.seek(700);
    await wait(1500);
    log('for screenshot: pos=${pb.positionMs} '
        'player=${fp().state.position.inMilliseconds} '
        '${fp().state.width}x${fp().state.height}');
    await shot('05-landscape-with-title');
    s.editor.setAspect(CanvasAspect.portrait9x16);
    await wait(1000);
    await shot('06-landscape-on-9x16');
    s.editor.setAspect(CanvasAspect.original);
    await wait(300);

    // 4b. 1.15: the nine menus, Settings, the context menu, suggestions ------
    for (final m in [
      'File', 'Edit', 'Add', 'Clip', 'Sound', 'Text and speech', 'View', //
      'Playback', 'Help',
    ]) {
      expect(find.widgetWithText(SubmenuButton, m), findsOneWidget,
          reason: 'menu $m');
    }
    Future<void> openMenu(String m) async {
      await tester.tap(find.widgetWithText(SubmenuButton, m));
      await wait(400);
    }

    await openMenu('Clip');
    expect(find.byKey(const ValueKey('menu-split')), findsOneWidget);
    await shot('06a-menu-clip');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(300);
    await openMenu('Sound');
    // Nothing selected: greyed out, and it says why.
    expect(find.textContaining('Fit music to video (select a music clip)'),
        findsOneWidget);
    await shot('06b-menu-sound');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(300);
    // File > Settings…: the one page; its Snap switch is the editor's.
    await openMenu('File');
    await tester.tap(find.byKey(const ValueKey('menu-settings')));
    await waitFor(
        () => find
            .byKey(const ValueKey('settings-dialog'))
            .evaluate()
            .isNotEmpty,
        'the Settings window');
    await shot('06c-settings');
    expect(s.snapping.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings-snapping')));
    await wait(300);
    expect(s.snapping.value, isFalse, reason: 'Settings > Snap off');
    await tester.tap(find.byKey(const ValueKey('settings-snapping')));
    await wait(300);
    expect(s.snapping.value, isTrue);
    // Suggestions on: one quiet line may show under the top bar.
    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-suggestions')));
    await wait(200);
    await tester.tap(find.byKey(const ValueKey('settings-suggestions')));
    await wait(300);
    await tester.tap(find.byTooltip('Close'));
    await wait(1200);
    final hint = find.byKey(const ValueKey('suggestion-text'));
    log('suggestion: ${hint.evaluate().isEmpty ? 'none' : tester.widget<Text>(hint).data}');
    await shot('06d-suggestion');
    // Right-click the first clip: its context menu.
    final firstClip = find.byKey(ValueKey('clip-${s.project.clips.first.id}'));
    await tester.tapAt(tester.getTopLeft(firstClip) + const Offset(12, 12),
        buttons: kSecondaryButton);
    await waitFor(
        () => find
            .byKey(const ValueKey('context-split'))
            .evaluate()
            .isNotEmpty,
        'the context menu of a clip');
    await shot('06e-context-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(400);
    expect(find.byKey(const ValueKey('context-split')), findsNothing);
    s.clearSelection();
    // Off again: the line would move what the later steps aim at.
    await ProviderScope.containerOf(tester.element(find.byType(PreviewView)))
        .read(appSettingsProvider)
        .setSuggestions(false);
    await wait(300);

    // 5. Export ---------------------------------------------------------------
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await waitFor(() => find.text('Export video').evaluate().isNotEmpty,
        'export dialog');
    final sw = Stopwatch()..start();
    await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
    await waitFor(
        () =>
            find.text('Video saved').evaluate().isNotEmpty ||
            find.text('Export failed').evaluate().isNotEmpty,
        'export to finish',
        timeoutMs: 120000);
    log('export took ${sw.elapsedMilliseconds} ms');
    await shot('07-export-done');
    expect(find.text('Video saved'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await wait(300);
    final info = await tester.runAsync(() => ffprobe(exportPath));
    final streams = (info!['streams'] as List).cast<Map<String, dynamic>>();
    for (final st in streams) {
      log('export stream ${st['codec_type']} ${st['codec_name']} '
          '${st['width'] ?? ''}x${st['height'] ?? ''} dur=${st['duration']}');
    }
    final dur = double.parse(info['format']['duration'] as String);
    log('export duration $dur s, size ${File(exportPath).lengthSync()} bytes');
    final v = streams.firstWhere((x) => x['codec_type'] == 'video');
    expect(v['codec_name'], 'h264');
    expect((v['width'], v['height']), (640, 360));
    expect(streams.any((x) => x['codec_name'] == 'aac'), isTrue);
    expect(dur, closeTo(total2 / 1000, 0.25));

    // 5b. Export several (1.14): one job, real engine, one folder ------------
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await waitFor(() => find.text('Where is it going?').evaluate().isNotEmpty,
        'export dialog with destinations');
    await tester.tap(find.byKey(const ValueKey('export-several')));
    await wait(300);
    await tester.ensureVisible(find.byKey(const ValueKey('export-tick-podcast')));
    await tester.tap(find.byKey(const ValueKey('export-tick-podcast')));
    await wait(300);
    expect(find.text('Export 3 files'), findsOneWidget);
    await shot('07b-export-several');
    final kitClock = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('export-go')));
    await waitFor(
        () =>
            find.text('Files saved').evaluate().isNotEmpty ||
            find.text('Export failed').evaluate().isNotEmpty,
        'the kit to finish',
        timeoutMs: 240000);
    await shot('07c-export-several-done');
    expect(find.text('Files saved'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await wait(300);
    final kitName = s.project.name;
    final kitFiles = Directory(kitDir).listSync().map((e) => p.basename(e.path)).toList()
      ..sort();
    log('EXPORT SEVERAL took ${kitClock.elapsedMilliseconds} ms: $kitFiles');
    expect(kitFiles, [
      '$kitName - Short 9x16.mp4',
      '$kitName - YouTube.mp4',
      '$kitName - audio.mp3',
      '$kitName - text.txt',
    ]);
    Future<(int, int)> sizeOf(String name) async {
      final j = await tester.runAsync(() => ffprobe(p.join(kitDir, name)));
      final v = (j!['streams'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((x) => x['codec_type'] == 'video');
      return (v['width'] as int, v['height'] as int);
    }

    expect(await sizeOf('$kitName - YouTube.mp4'), (1920, 1080));
    expect(await sizeOf('$kitName - Short 9x16.mp4'), (1080, 1920));
    expect(File(p.join(kitDir, '$kitName - text.txt')).readAsStringSync(),
        contains('File: $kitName - Short 9x16.mp4'));
    // The project was not changed and no project was added.
    expect(s.project.aspect, CanvasAspect.original);


    // 6. Rougher handling -----------------------------------------------------
    List<String> layout() => [
          for (final c in s.project.clips)
            '${p.basename(c.path)}:${c.inMs}-${c.outMs}'
        ];
    log('layout ${layout()}');
    // land 1000-2500 | land 2500-4000 | port 0-3000 | photo 3000
    // A burst of seeks, as when the playhead is dragged.
    for (var i = 0; i < 40; i++) {
      pb.seek((i * 1777) % total2);
      await wait(20);
    }
    pb.seek(3500);
    final swSettle = Stopwatch()..start();
    await waitFor(
        () =>
            (fp().state.position.inMilliseconds - 500).abs() < 100 &&
            fp().state.width == 360,
        'player to settle on port.mp4 @500 after a burst of seeks '
        '(is at ${fp().state.position.inMilliseconds}, '
        '${fp().state.width}x${fp().state.height})',
        timeoutMs: 8000);
    log('burst of seeks settled after ${swSettle.elapsedMilliseconds} ms');
    await wait(300);
    await shot('09-after-seek-burst-3500');

    // Fast play / pause presses, ending in "playing".
    pb.seek(0);
    await wait(500);
    for (var i = 0; i < 7; i++) {
      pb.toggle();
      await wait(60);
    }
    expect(pb.playing, isTrue);
    final afterToggles =
        await record(until: () => pb.positionMs >= 1200, timeoutMs: 4000);
    report('after 7 fast play/pause presses', afterToggles);
    expect(pb.positionMs, greaterThanOrEqualTo(1200));
    expect(fp().state.playing, isTrue);
    pb.pause();
    await wait(400);
    expect(fp().state.playing, isFalse);

    // Trim the end of the portrait clip: playback must leave it at 1500.
    final portClip = s.project.clips[2];
    s.editor.trimClip(portClip.id, outMs: 1500);
    await wait(200);
    pb.seek(3000);
    await wait(800);
    pb.play();
    final trimmedOut =
        await record(until: () => pb.positionMs >= 5000, timeoutMs: 6000);
    report('trimmed end (port 0-1500), into the photo', trimmedOut);
    log('trimmed end: photo reached at ${reached(trimmedOut, 4500)} ms wall, '
        'player stopped at ${fp().state.position.inMilliseconds} '
        'playing=${fp().state.playing}');
    expect(trimmedOut.last.wallMs, closeTo(2000, 500));
    expect(anyVideoPlaying(), isFalse);
    for (final v in backend.videoPlayers) {
      // The player that holds the portrait file stopped at its trimmed end.
      if (v.player.state.width == 360) {
        expect(v.player.state.position.inMilliseconds, lessThan(1800));
      }
    }
    pb.pause();

    // Mute follows the clip under the playhead.
    s.editor.setClipMuted(portClip.id, true);
    pb.seek(3500);
    await wait(700);
    log('muted port clip: player volume ${fp().state.volume}');
    expect(fp().state.volume, 0);
    pb.seek(500);
    await wait(700);
    log('land clip: player volume ${fp().state.volume}');
    expect(fp().state.volume, 100);

    // Deleting the clip under the playhead while playing.
    pb.seek(200);
    await wait(500);
    pb.play();
    await wait(500);
    s.editor.removeClip(s.project.clips[0].id);
    final afterDelete = await record(
        until: () => pb.positionMs >= 1200 || !pb.playing, timeoutMs: 5000);
    report('after deleting the playing clip', afterDelete);
    log('layout ${layout()} playing=${pb.playing}');
    expect(pb.playing, isTrue);
    expect(fp().state.position.inMilliseconds, closeTo(2500 + 1200, 400));
    pb.pause();
    await wait(300);

    // A project that is one trimmed video: play to the end, then play again.
    s.editor.removeClip(s.project.clips[2].id);
    s.editor.removeClip(s.project.clips[1].id);
    s.editor.removeAudio(s.project.audio.single.id);
    await wait(300);
    log('layout ${layout()} duration=${pb.durationMs}');
    expect(pb.durationMs, 1500);
    pb.seek(0);
    await wait(500);
    pb.play();
    final single1 = await record(until: () => !pb.playing, timeoutMs: 6000);
    report('single clip, first run', single1);
    expect(pb.playing, isFalse);
    expect(pb.positionMs, 1500);
    expect(single1.last.wallMs, closeTo(1500, 500));
    await wait(500);
    await tapPlay();
    final single2 = await record(until: () => !pb.playing, timeoutMs: 6000);
    report('single clip, play again from the end', single2);
    expect(pb.playing, isFalse);
    expect(pb.positionMs, 1500);
    expect(single2.last.wallMs, closeTo(1500, 500));
    expect(single2[single2.length ~/ 2].srcMs, inInclusiveRange(2500, 4000));
    pb.seek(700);
    await wait(700);
    expect(fp().state.position.inMilliseconds, closeTo(3200, 100));

    // 7. Speed, gapless cuts, transitions and look ------------------------------
    // A timeline of its own: red.mp4 (4 s) | blue.mp4 (3 s).
    for (final c in [...s.project.clips]) {
      s.editor.removeClip(c.id);
    }
    // The title from the beginning sits in the middle of the picture,
    // where colours are measured below.
    for (final t in [...s.project.titles]) {
      s.editor.removeTitle(t.id);
    }
    await wait(300);
    Clip videoClip(String id, String path, int ms, int w, int h) => Clip(
          id: id,
          type: ClipType.video,
          path: path,
          sourceDurationMs: ms,
          inMs: 0,
          outMs: ms,
          width: w,
          height: h,
        );
    s.editor.addClip(videoClip('red', red, 4000, 640, 360));
    s.editor.addClip(videoClip('blue', blue, 3000, 640, 360));
    await wait(1000);
    expect(pb.durationMs, 7000);

    Rect previewRect() => tester.getRect(find
        .descendant(
            of: find.byType(PreviewView), matching: find.byType(AspectRatio))
        .first);

    /// Colour of the preview at ([fx], [fy]) (fractions of its size) in an
    /// image of the whole window taken at [scale].
    (int, int, int) pixelOf(ByteData data, int width, double scale,
        double fx, double fy) {
      final rect = previewRect();
      final x = ((rect.left + rect.width * fx) * scale).floor();
      final y = ((rect.top + rect.height * fy) * scale).floor();
      final o = (y * width + x) * 4;
      return (data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
    }

    /// What is on screen now at the given points of the preview.
    Future<List<(int, int, int)>> look(List<(double, double)> points) async {
      await wait(50);
      final boundary = shotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = boundary.toImageSync();
      final data = (await tester.runAsync(() => image.toByteData()))!;
      final out = [
        for (final (fx, fy) in points)
          pixelOf(data, image.width, 1, fx, fy),
      ];
      image.dispose();
      return out;
    }

    bool isRed((int, int, int) c) => c.$1 > 200 && c.$2 < 50 && c.$3 < 50;
    bool isBlue((int, int, int) c) => c.$1 < 50 && c.$2 < 50 && c.$3 > 200;
    bool isBlack((int, int, int) c) => c.$1 < 25 && c.$2 < 25 && c.$3 < 25;
    String kind((int, int, int) c) => isRed(c)
        ? 'red'
        : isBlue(c)
            ? 'blue'
            : isBlack(c)
                ? 'black'
                : 'mix(${c.$1},${c.$2},${c.$3})';

    /// Plays until [until], taking a picture of the window every ~33 ms.
    /// Returns for each one the wall time, the playhead and the colour in
    /// the middle of the preview. Pictures chosen by [keep] are saved.
    Future<List<({int wallMs, int posMs, (int, int, int) centre})>> film({
      required bool Function() until,
      int timeoutMs = 10000,
      String? saveAs,
      bool Function(int posMs)? keep,
    }) async {
      const scale = 0.25;
      final shots = <(int, int, ui.Image)>[];
      final sw = Stopwatch()..start();
      while (!until() && sw.elapsedMilliseconds < timeoutMs) {
        final boundary = shotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        shots.add((
          sw.elapsedMilliseconds,
          pb.positionMs,
          boundary.toImageSync(pixelRatio: scale)
        ));
        await wait(33);
      }
      final result = <({int wallMs, int posMs, (int, int, int) centre})>[];
      var saved = 0;
      for (final (wallMs, posMs, image) in shots) {
        final data = (await tester.runAsync(() => image.toByteData()))!;
        result.add((
          wallMs: wallMs,
          posMs: posMs,
          centre: pixelOf(data, image.width, scale, 0.5, 0.5)
        ));
        if (saveAs != null && keep != null && keep(posMs) && saved < 12) {
          saved++;
          final png = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png));
          File(p.join(out.path, '$saveAs-w$wallMs-p$posMs.png'))
              .writeAsBytesSync(png!.buffer.asUint8List());
        }
        image.dispose();
      }
      return result;
    }

    // 7a. A hard cut between two files: no black, no wait.
    pb.seek(3000);
    await wait(800);
    expect((await look([(0.5, 0.5)])).single, predicate(isRed));
    final cutFrom = trace.length;
    pb.play();
    final cut = await film(
        until: () => pb.positionMs >= 5000,
        saveAs: 'cut',
        keep: (pos) => pos > 3850 && pos < 4250);
    pb.pause();
    {
      final lastRed = cut.lastWhere((f) => isRed(f.centre));
      final firstBlue = cut.firstWhere((f) => isBlue(f.centre));
      final between = cut
          .where((f) => f.wallMs > lastRed.wallMs && f.wallMs < firstBlue.wallMs)
          .toList();
      log('HARD CUT red->blue: last red frame at wall ${lastRed.wallMs} '
          '(pos ${lastRed.posMs}), first blue at ${firstBlue.wallMs} '
          '(pos ${firstBlue.posMs}); pictures in between: '
          '${[for (final f in between) kind(f.centre)]}; '
          'playhead: ${crossing(cutFrom, 4000)}; '
          '3000->5000 took ${cut.last.wallMs} ms');
      expect(firstBlue.wallMs - lastRed.wallMs, lessThan(200),
          reason: 'the picture must go straight from one file to the next');
      expect(between.where((f) => isBlack(f.centre)), isEmpty,
          reason: 'no black frame at the cut');
      expect(crossing(cutFrom, 4000).lostMs, lessThan(150),
          reason: 'the playhead must not wait at the cut');
      expect(cut.last.wallMs, closeTo(2000, 400));
    }
    await wait(300);

    // 7b. Speed: 4 s of source at 2x take 2 s.
    s.editor.setClipSpeed('red', 2);
    await wait(300);
    expect(pb.durationMs, 5000);
    pb.seek(0);
    await wait(800);
    expect(fp().state.rate, 2);
    pb.play();
    final fast = await record(until: () => pb.clipIndex == 1, timeoutMs: 6000);
    final fastSrc = fast.lastWhere((x) => x.posMs < 1900).srcMs;
    final fastPos = fast.lastWhere((x) => x.posMs < 1900).posMs;
    await wait(300);
    pb.pause();
    report('red clip at 2x', fast);
    log('SPEED 2x: 2000 ms of timeline took ${fast.last.wallMs} ms wall; '
        'source was at $fastSrc when the playhead was at $fastPos; '
        'the next clip plays at rate ${fp().state.rate}');
    expect(fast.last.wallMs, closeTo(2000, 400));
    expect(fastSrc, closeTo(fastPos * 2, 200));
    expect(fp().state.rate, 1);
    // Half speed: 1 s of timeline is 0.5 s of source.
    s.editor.setClipSpeed('red', 0.5);
    await wait(300);
    expect(pb.durationMs, 11000);
    pb.seek(2000);
    await wait(800);
    expect(fp().state.position.inMilliseconds, closeTo(1000, 100));
    pb.play();
    final slow =
        await record(until: () => pb.positionMs >= 3000, timeoutMs: 4000);
    pb.pause();
    log('SPEED 0.5x: 1000 ms of timeline took ${slow.last.wallMs} ms wall, '
        'source at ${slow.last.srcMs}');
    expect(slow.last.wallMs, closeTo(1000, 350));
    expect(slow.last.srcMs, closeTo(1500, 150));
    s.editor.setClipSpeed('red', 1);
    await wait(300);
    expect(pb.durationMs, 7000);

    // 7c. Crossfade between the two files (1 s overlap: 3000..4000).
    s.editor.setClipTransition('blue', TransitionType.crossfade,
        durationMs: 1000);
    await wait(300);
    expect(pb.durationMs, 6000);
    expect(s.project.clipStartMs(1), 3000);
    pb.seek(3500);
    await wait(1500);
    final mid = (await look([(0.5, 0.5)])).single;
    log('CROSSFADE paused at its middle: centre pixel $mid');
    expect(mid.$1, closeTo(127, 45));
    expect(mid.$3, closeTo(127, 45));
    expect(mid.$2, lessThan(40));
    await shot('10-crossfade-paused-middle');
    pb.seek(2400);
    await wait(800);
    pb.play();
    var bothPlaying = 0;
    final fade = await film(
        until: () {
          if (pb.positionMs > 3200 &&
              pb.positionMs < 3800 &&
              backend.videoPlayers.every((v) => v.player.state.playing)) {
            bothPlaying++;
          }
          return pb.positionMs >= 4600;
        },
        saveAs: 'crossfade',
        keep: (pos) => pos >= 3000 && pos <= 4000);
    pb.pause();
    {
      final inside = fade.where((f) => f.posMs > 3000 && f.posMs < 4000).toList();
      final mixed = inside
          .where((f) => f.centre.$1 > 30 && f.centre.$3 > 30)
          .toList();
      log('CROSSFADE playing: ${inside.length} pictures inside the overlap, '
          '${mixed.length} of them a mix; '
          '${[for (final f in inside) '${f.posMs}:${kind(f.centre)}']}; '
          '2400->4600 took ${fade.last.wallMs} ms; both players were playing '
          'in $bothPlaying checks');
      expect(mixed.length, greaterThanOrEqualTo(4),
          reason: 'the crossfade must be visible while playing');
      // Red goes down and blue comes up as the playhead moves on.
      for (final f in mixed) {
        final p01 = (f.posMs - 3000) / 1000;
        expect(f.centre.$3 / 255, closeTo(p01, 0.3),
            reason: 'blue share at ${f.posMs}');
      }
      expect(isRed(fade.first.centre), isTrue);
      expect(isBlue(fade.last.centre), isTrue);
      expect(inside.where((f) => isBlack(f.centre)), isEmpty);
      expect(fade.last.wallMs, closeTo(2200, 450),
          reason: 'timeline timing through the transition');
      expect(bothPlaying, greaterThan(0));
    }
    await wait(500);
    expect(anyVideoPlaying(), isFalse);

    // Other transitions, paused at chosen places.
    s.editor.setClipTransition('blue', TransitionType.slideLeft);
    pb.seek(3500);
    await wait(1200);
    var px = await look([(0.25, 0.5), (0.75, 0.5)]);
    log('SLIDE LEFT at its middle: left ${kind(px[0])}, right ${kind(px[1])}');
    expect(isRed(px[0]), isTrue);
    expect(isBlue(px[1]), isTrue);
    await shot('11-slide-left-middle');
    s.editor.setClipTransition('blue', TransitionType.slideUp);
    pb.seek(3250);
    await wait(1200);
    px = await look([(0.5, 0.5), (0.5, 0.9)]);
    log('SLIDE UP a quarter in: middle ${kind(px[0])}, bottom ${kind(px[1])}');
    expect(isRed(px[0]), isTrue);
    expect(isBlue(px[1]), isTrue);
    s.editor.setClipTransition('blue', TransitionType.fadeBlack);
    // Like xfade=fadeblack: red is gone after a fifth, then blue comes up
    // (weights 0.45 red at 10 %, ~0 at 20 %, 0.51 blue at 60 %).
    pb.seek(3100);
    await wait(1200);
    final dimRed = (await look([(0.5, 0.5)])).single;
    pb.seek(3200);
    await wait(1000);
    final black = (await look([(0.5, 0.5)])).single;
    pb.seek(3600);
    await wait(1000);
    final dimBlue = (await look([(0.5, 0.5)])).single;
    log('FADE THROUGH BLACK at 10 %, 20 %, 60 %: $dimRed $black $dimBlue');
    expect(dimRed.$1, closeTo(115, 40));
    expect(dimRed.$3, lessThan(40));
    expect(isBlack(black), isTrue);
    expect(dimBlue.$3, closeTo(129, 40));
    expect(dimBlue.$1, lessThan(40));
    await shot('11b-fade-black-60');
    // A slide while playing, into a photo too.
    s.editor.setClipTransition('blue', TransitionType.slideLeft,
        durationMs: 800);
    s.editor.addClip(Clip(
      id: 'pic',
      type: ClipType.photo,
      path: photo,
      sourceDurationMs: 0,
      inMs: 0,
      outMs: 2000,
      width: 800,
      height: 600,
      hasAudio: false,
      transition: TransitionType.crossfade,
      transitionMs: 800,
    ));
    await wait(300);
    final withPhoto = pb.durationMs;
    expect(withPhoto, 4000 + 3000 + 2000 - 800 - 800);
    pb.seek(2800);
    await wait(800);
    pb.play();
    final slide = await film(
        until: () => !pb.playing,
        saveAs: 'slide-and-photo',
        keep: (pos) =>
            (pos > 3400 && pos < 3800) || (pos > 5600 && pos < 6100));
    log('SLIDE + PHOTO CROSSFADE playing: 2800->$withPhoto took '
        '${slide.last.wallMs} ms; centre over time '
        '${[for (var i = 0; i < slide.length; i += 4) '${slide[i].posMs}:${kind(slide[i].centre)}']}');
    expect(pb.positionMs, withPhoto);
    expect(slide.last.wallMs, closeTo(withPhoto - 2800, 600));
    pb.seek(5800); // middle of blue -> photo
    await wait(1000);
    px = await look([(0.5, 0.2)]);
    log('BLUE -> PHOTO crossfade paused at its middle: ${kind(px[0])}');
    expect(isBlue(px[0]), isFalse);
    expect(isBlack(px[0]), isFalse);
    expect(px[0].$3, greaterThan(100), reason: 'half of it is still blue');
    await shot('12-video-photo-crossfade-middle');
    s.editor.removeClip('pic');
    s.editor.setClipTransition('blue', TransitionType.none);
    await wait(300);
    expect(pb.durationMs, 7000);

    // 7d. Colour and zoom.
    pb.seek(1000);
    await wait(800);
    final plainRed = (await look([(0.5, 0.5)])).single;
    log('LOOK untouched red: $plainRed');
    expect(isRed(plainRed), isTrue);
    s.editor.setClipAdjustments('red', saturation: -1);
    await wait(300);
    final grey = (await look([(0.5, 0.5)])).single;
    log('LOOK saturation -1 on red: $grey');
    expect((grey.$1 - grey.$2).abs(), lessThan(25));
    expect((grey.$2 - grey.$3).abs(), lessThan(25));
    expect(grey.$1, inInclusiveRange(30, 110));
    s.editor.setClipAdjustments('red', saturation: 0, brightness: 1);
    await wait(300);
    final bright = (await look([(0.5, 0.5)])).single;
    log('LOOK brightness +1 on red: $bright');
    expect(bright.$1, greaterThan(230));
    expect(bright.$2, inInclusiveRange(30, 110));
    s.editor.setClipAdjustments('red', brightness: -1);
    await wait(300);
    final dark = (await look([(0.5, 0.5)])).single;
    log('LOOK brightness -1 on red: $dark');
    expect(dark.$1, inInclusiveRange(150, 220));
    s.editor.setClipAdjustments('red', brightness: 0, contrast: 1);
    await wait(300);
    log('LOOK contrast +1 on red: ${(await look([(0.5, 0.5)])).single}');
    await shot('13-look-contrast');
    s.editor.setClipAdjustments('red', contrast: 0);

    // A portrait clip on the landscape canvas: bars left and right.
    s.editor.addClip(videoClip('port', port, 3000, 360, 640));
    await wait(300);
    pb.seek(8000);
    await wait(1200);
    px = await look([(0.1, 0.5), (0.3, 0.5), (0.5, 0.5)]);
    log('PORTRAIT fit: at 10% ${kind(px[0])}, 30% ${kind(px[1])}, '
        'middle ${kind(px[2])}');
    expect(isBlack(px[0]), isTrue);
    expect(isBlack(px[1]), isTrue);
    expect(isBlack(px[2]), isFalse);
    s.editor.setClipZoom('port', 2);
    await wait(400);
    px = await look([(0.1, 0.5), (0.3, 0.5)]);
    log('PORTRAIT zoom 2: at 10% ${kind(px[0])}, 30% ${kind(px[1])}');
    expect(isBlack(px[0]), isTrue, reason: 'twice 28% is still not 80%');
    expect(isBlack(px[1]), isFalse, reason: 'the zoomed picture is wider');
    await shot('14-zoom-2');
    s.editor.setClipZoom('port', 1);
    s.editor.setClipFit('port', FitMode.blur);
    await wait(600);
    px = await look([(0.1, 0.5), (0.3, 0.5)]);
    log('PORTRAIT blur backdrop: at 10% ${kind(px[0])}, 30% ${kind(px[1])}');
    await shot('15-video-blur-backdrop');
    expect(isBlack(px[0]), isFalse,
        reason: 'the bars are filled with the blurred picture');
    pb.seek(7200);
    await wait(800);
    pb.play();
    final blurPlay =
        await record(until: () => pb.positionMs >= 9200, timeoutMs: 6000);
    pb.pause();
    report('portrait clip with blurred backdrop', blurPlay);
    log('BLUR playing: 2000 ms of timeline took ${blurPlay.last.wallMs} ms');
    expect(blurPlay.last.wallMs, closeTo(2000, 600));

    // 7d2. Crop and the overlay track (1.6), with the real players.
    s.editor.setClipFit('port', FitMode.fit);
    // Red cropped to its left half: half as wide, bars at the sides.
    s.editor.setPictureCrop('red', const CropRect(0, 0, 0.5, 1));
    pb.seek(1000);
    await wait(800);
    px = await look([(0.1, 0.5), (0.5, 0.5)]);
    log('CROP red left half: at 10% ${kind(px[0])}, middle ${kind(px[1])}');
    expect(isBlack(px[0]), isTrue);
    expect(isRed(px[1]), isTrue);
    await shot('15b-crop');
    s.editor.resetFraming('red');
    // Blue as an overlay over red, 500..2500 ms.
    final ovId = s.editor.addOverlay(OverlayClip(
      startMs: 500,
      layout: OverlayLayout.full,
      clip: videoClip('ov', blue, 2000, 640, 360),
    ));
    pb.seek(1000);
    await wait(1200);
    px = await look([(0.5, 0.5)]);
    log('OVERLAY full, paused at 1000: ${kind(px[0])}; overlay players '
        '${pb.overlayPlayers.length}');
    expect(isBlue(px[0]), isTrue);
    OverlayClip ov() => s.project.overlays.single;
    s.editor.updateOverlay(ov().copyWith(layout: OverlayLayout.pip));
    await wait(400);
    px = await look([(0.85, 0.82), (0.2, 0.2)]);
    log('OVERLAY pip: corner ${kind(px[0])}, top left ${kind(px[1])}');
    expect(isBlue(px[0]), isTrue);
    expect(isRed(px[1]), isTrue);
    s.editor.updateOverlay(ov().copyWith(layout: OverlayLayout.sideBySide));
    await wait(400);
    px = await look([(0.25, 0.5), (0.75, 0.5)]);
    log('OVERLAY side by side: left ${kind(px[0])}, right ${kind(px[1])}');
    expect(isRed(px[0]), isTrue);
    expect(isBlue(px[1]), isTrue);
    await shot('15c-overlay-side-by-side');
    // Playing through it: blue while it shows, red before and after.
    s.editor.updateOverlay(ov().copyWith(layout: OverlayLayout.full));
    pb.seek(0);
    await wait(800);
    pb.play();
    final through = await film(until: () => pb.positionMs >= 3200);
    pb.pause();
    final inside = through.where((f) => f.posMs > 800 && f.posMs < 2300);
    final blueShare = inside.where((f) => isBlue(f.centre)).length /
        (inside.isEmpty ? 1 : inside.length);
    final after = through.where((f) => f.posMs > 2700);
    log('OVERLAY playing: ${inside.length} pictures inside, '
        '${(blueShare * 100).round()} % blue; after it '
        '${after.where((f) => isRed(f.centre)).length}/${after.length} red; '
        'overlay player at ${pb.overlayPlayers.isEmpty ? '-' : (pb.overlayPlayers.first as MediaKitTimelinePlayer).player.state.position.inMilliseconds} ms');
    expect(blueShare, greaterThan(0.8));
    expect(after.where((f) => isRed(f.centre)).length,
        greaterThan(after.length * 0.8));
    s.editor.removeOverlay(ovId);
    await wait(300);

    // 7d3. 1.7 with the real players: a colour filter, the fade of a clip
    // and of the whole video, a styled and animated title in its own font.
    s.editor.setClipFilter('red', LookFilter.blackWhite);
    pb.seek(1000);
    await wait(800);
    final bw = (await look([(0.5, 0.5)])).single;
    log('FILTER black and white on red: $bw');
    expect((bw.$1 - bw.$2).abs(), lessThan(25));
    expect((bw.$2 - bw.$3).abs(), lessThan(25));
    s.editor.setClipFilter('red', LookFilter.warm);
    await wait(300);
    final warm = (await look([(0.5, 0.5)])).single;
    log('FILTER warm on red: $warm');
    expect(isRed(warm), isTrue);
    await shot('15d-filter-warm');
    s.editor.resetLook('red');
    s.editor.setClipFades('red', fadeInMs: 1000);
    pb.seek(0);
    await wait(800);
    final faded = (await look([(0.5, 0.5)])).single;
    pb.seek(500);
    await wait(500);
    final half = (await look([(0.5, 0.5)])).single;
    log('CLIP FADE in 1 s: at 0 $faded, at 500 $half');
    expect(isBlack(faded), isTrue);
    expect(half.$1, inInclusiveRange(80, 190));
    s.editor.setClipFades('red', fadeInMs: 0);
    s.editor.setProjectFades(fadeOutMs: 1000);
    pb.seek(pb.durationMs - 50);
    await wait(800);
    final end = (await look([(0.5, 0.5)])).single;
    log('PROJECT FADE out: near the end $end');
    expect(end.$1 + end.$2 + end.$3, lessThan(80));
    s.editor.setProjectFades(fadeOutMs: 0);
    s.editor.addTitle(const TitleOverlay(
      id: 'styled',
      text: 'Привет שלום',
      startMs: 0,
      endMs: 3000,
      fontSize: 0.12,
      font: TitleFont.modern,
      outline: true,
      animIn: TitleAnimation.fade,
    ));
    pb.seek(0);
    await wait(600);
    expect(
        tester
            .widgetList<Opacity>(find.ancestor(
                of: find.text('Привет שלום').first,
                matching: find.byType(Opacity)))
            .any((o) => o.opacity == 0),
        isTrue,
        reason: 'invisible at the start of its fade');
    pb.seek(1500);
    await wait(800);
    expect(find.text('Привет שלום'), findsWidgets);
    await shot('15e-styled-title');
    s.editor.removeTitle('styled');

    // 7e. A title of several lines with a box, and a caption.
    s.editor.addTitle(const TitleOverlay(
      id: 'multi',
      text: 'First line\nand a much longer second line that has to be '
          'wrapped because it does not fit',
      startMs: 0,
      endMs: 4000,
      y: 0.4,
      fontSize: 0.08,
      background: true,
    ));
    s.editor.addTitle(const TitleOverlay(
      id: 'cap',
      text: 'A caption at the bottom',
      startMs: 0,
      endMs: 4000,
      y: 0.86,
      fontSize: 0.045,
      background: true,
      kind: TitleKind.caption,
    ));
    pb.seek(1000);
    await wait(1200);
    expect(find.textContaining('First line\n'), findsOneWidget,
        reason: 'one text block for all lines');
    await shot('16-titles');
    s.editor.removeTitle('multi');
    s.editor.removeTitle('cap');

    // 7f. Titles on an upright (9:16) canvas: sized by the short side and
    // kept inside the picture, at the place the export puts them.
    s.editor.setAspect(CanvasAspect.portrait9x16);
    const upright = TitleOverlay(
      id: 'up',
      text: 'Upright title',
      startMs: 0,
      endMs: 4000,
      y: 0.3,
      fontSize: 0.09,
      background: true,
    );
    // Asked for at the very edge; it has to come back inside.
    final edge = upright.copyWith(text: 'At the edge', x: 0.99, y: 0.7);
    s.editor.addTitle(upright);
    s.editor.addTitle(TitleOverlay.fromJson({...edge.toJson(), 'id': 'edge'}));
    pb.seek(1000);
    await wait(1200);
    final canvasPx = s.project.canvasSize;
    expect(canvasPx.height, greaterThan(canvasPx.width));
    final canvasRect = tester.getRect(find.descendant(
        of: find.byType(PreviewView), matching: find.byType(AspectRatio)));
    final k = canvasRect.width / canvasPx.width;
    for (final t in s.project.titles.where((t) => t.id == 'up' || t.id == 'edge')) {
      final want = layoutTitleBlock(t,
          canvasWidth: canvasPx.width, canvasHeight: canvasPx.height);
      final got = tester.getRect(find.byKey(ValueKey('preview-title-${t.id}')));
      log('TITLE 9:16 ${t.id}: canvas ${canvasPx.width}x${canvasPx.height}, '
          'font ${want.fontPx} px (short side x ${t.fontSize}), box '
          '${want.boxWidth.round()}x${want.boxHeight.round()} at '
          '${want.boxLeft.round()},${want.boxTop.round()}; on screen '
          '${got.width.toStringAsFixed(1)}x${got.height.toStringAsFixed(1)} '
          'at ${(got.left - canvasRect.left).toStringAsFixed(1)},'
          '${(got.top - canvasRect.top).toStringAsFixed(1)} (scale '
          '${k.toStringAsFixed(4)})');
      expect(want.fontPx, (t.fontSize * canvasPx.width).round());
      expect(got.width, closeTo(want.boxWidth * k, 0.5));
      expect(got.height, closeTo(want.boxHeight * k, 0.5));
      expect(got.left - canvasRect.left, closeTo(want.boxLeft * k, 0.5));
      expect(got.top - canvasRect.top, closeTo(want.boxTop * k, 0.5));
      expect(got.left, greaterThanOrEqualTo(canvasRect.left));
      expect(got.right, lessThanOrEqualTo(canvasRect.right));
      // The drawn text is no wider than the box worked out for it.
      final text = tester.getSize(find.descendant(
          of: find.byKey(ValueKey('preview-title-${t.id}')),
          matching: find.byType(Text)));
      log('TITLE 9:16 ${t.id}: text drawn ${text.width.toStringAsFixed(1)} '
          'wide, estimated ${(want.width * k).toStringAsFixed(1)}');
      expect(text.width, closeTo(want.width * k, math.max(2.0, want.width * k * 0.03)));
    }
    await shot('17-titles-9x16');
    s.editor.removeTitle('up');
    s.editor.removeTitle('edge');
    s.editor.setAspect(CanvasAspect.original);
    s.editor.setClipFit('port', FitMode.fit);
    await wait(300);

    // 7g. The clip's own sound in the preview: second audio track, left
    // side only and voice focus reach mpv as `aid` / `af`, mpv takes the
    // filters (only `equalizer` and its own `format`, which every libmpv
    // build media_kit ships has) and keeps playing.
    final twoTracks = p.join(fx.path, 'two-tracks.mp4');
    await tester.runAsync(() => ffmpeg([
          '-f', 'lavfi', '-i', 'color=c=green:size=640x360:rate=25:duration=3', //
          '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
          '-f', 'lavfi', '-i',
          "aevalsrc='0.3*sin(2*PI*1000*t)|0.3*sin(2*PI*660*t)':s=48000:d=3:c=stereo",
          '-map', '0:v', '-map', '1:a', '-map', '2:a', ...x264, '-c:a', 'aac',
          '-t', '3', twoTracks,
        ]));
    final soundInfo = (await tester.runAsync(() => s.engine.probe(twoTracks)))!;
    log('SOUND two-tracks.mp4 audio streams ${soundInfo.audioStreams}');
    expect(soundInfo.audioStreams, [1, 2]);
    s.editor.addClip(Clip(
      id: 'sound',
      type: ClipType.video,
      path: twoTracks,
      sourceDurationMs: soundInfo.durationMs,
      inMs: 0,
      outMs: soundInfo.durationMs,
      width: soundInfo.width,
      height: soundInfo.height,
      audioStreams: soundInfo.audioStreams,
    ));
    s.editor.setClipAudioSource('sound', track: 1, channel: AudioChannel.left);
    s.editor.setClipVoiceFocus('sound', 1);
    final soundStart = s.project.clipStartMs(s.project.clips.length - 1);
    final problemsBefore = backend.mpvProblems.length;
    pb.seek(soundStart + 200);
    await waitFor(() => pb.loadedVideoPath == twoTracks, 'two-tracks loaded');
    await wait(500);
    Future<String> prop2(Player pl, String name) async =>
        (await tester.runAsync(
            () => (pl.platform as NativePlayer).getProperty(name)))!;
    Future<String> prop(String name) => prop2(fp(), name);
    final af = await prop('af');
    final aid = await prop('aid');
    final current = await prop('current-tracks/audio/id');
    log('SOUND preview: aid=$aid current=$current af=$af');
    expect(aid, '2');
    expect(current, '2');
    expect(af, contains('equalizer'));
    expect(af, contains('format'));
    pb.play();
    await wait(1200);
    pb.pause();
    log('SOUND preview played to ${pb.positionMs} (from ${soundStart + 200})');
    expect(pb.positionMs, greaterThan(soundStart + 200 + 700));
    final problems = backend.mpvProblems.sublist(problemsBefore);
    log('SOUND mpv warnings while playing: $problems');
    expect(problems.where((m) => m.contains('filter') || m.contains('af')),
        isEmpty);
    s.editor.removeClip('sound');
    await wait(300);
    // Back on a clip with one track and no filters: both decks play its
    // sound again (a deck that had track 2 must not stay silent).
    pb.seek(500);
    await waitFor(() => pb.loadedVideoPath == s.project.clips.first.path,
        'first clip loaded again');
    await wait(500);
    final backAid = await prop2(fp(), 'current-tracks/audio/id');
    final backAf = await prop2(fp(), 'af');
    log('SOUND back on ${p.basename(s.project.clips.first.path)}: '
        'audio track $backAid, af "$backAf"');
    expect(backAid, '1');
    expect(backAf, '');

    // 7h. Instant sound processing: Clean up sound on a talking clip is
    // rendered in the background with the export chain into a processed
    // file; the preview then plays that file on a sound player in step
    // with the (silent) picture.
    final talk = p.join(fx.path, 'talk.mp4');
    await tester.runAsync(() => ffmpeg([
          '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=12', //
          '-f', 'lavfi', '-i',
          "aevalsrc='0.2*sin(2*PI*220*t)*gt(sin(2*PI*0.5*t),0)':s=48000:d=12",
          '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.03:d=12',
          '-filter_complex', '[1:a][2:a]amix=inputs=2:normalize=0[a]',
          '-map', '0:v', '-map', '[a]', ...x264, '-c:a', 'aac', '-t', '12', talk,
        ]));
    final talkInfo = (await tester.runAsync(() => s.engine.probe(talk)))!;
    s.editor.addClip(Clip(
      id: 'talk',
      type: ClipType.video,
      path: talk,
      sourceDurationMs: talkInfo.durationMs,
      inMs: 1000,
      outMs: 11000,
      width: talkInfo.width,
      height: talkInfo.height,
      audioStreams: talkInfo.audioStreams,
    ));
    pb.seek(0);
    await wait(300);
    final renderClock = Stopwatch()..start();
    s.editor.setClipDenoise('talk', true);
    Clip talkClip() => s.project.clips.firstWhere((c) => c.id == 'talk');
    await waitFor(
        () => s.sounds.statusOf(talkClip()).state == SoundState.ready,
        'processed sound of talk.mp4',
        timeoutMs: 30000);
    final processedPath = s.sounds.readyPath(talkClip())!;
    log('PROCESSED talk.mp4 (${talkInfo.durationMs} ms of sound) ready after '
        '${renderClock.elapsedMilliseconds} ms (800 ms of it the settling '
        'wait): $processedPath, ${File(processedPath).lengthSync()} bytes');
    expect(p.isWithin(p.join(out.path, 'media', 'processed'), processedPath),
        isTrue);
    expect(File(processedPath).existsSync(), isTrue);
    final talkStart = s.project.clipStartMs(s.project.clips.length - 1);
    pb.seek(talkStart + 500);
    await waitFor(() => pb.loadedVideoPath == talk, 'talk.mp4 loaded');
    await waitFor(() => pb.playingProcessedSound == processedPath,
        'sound player holds the processed file');
    await shot('18-processed-sound');
    pb.play();
    await wait(800);
    // Sample both players' clocks; the sound player is the clip's own
    // sound now, the video player is silent.
    final soundPlayer =
        (pb.clipSoundPlayers.firstWhere((_) => true) as MediaKitTimelinePlayer)
            .player;
    final offsets = <double>[];
    for (var i = 0; i < 12; i++) {
      await wait(250);
      final r = await tester.runAsync(() async {
        final v = fp().platform as NativePlayer;
        final a = soundPlayer.platform as NativePlayer;
        final sw = Stopwatch()..start();
        final vt = double.parse(await v.getProperty('time-pos'));
        final t1 = sw.elapsedMicroseconds;
        final at = double.parse(await a.getProperty('time-pos'));
        final t2 = sw.elapsedMicroseconds;
        // The two reads are t2 - t1 apart: the sound has moved on by that.
        return (at - vt) * 1000 - (t2 - t1) / 1000;
      });
      offsets.add(r!);
    }
    final videoVolume = await prop2(fp(), 'volume');
    final soundFile = await prop2(soundPlayer, 'path');
    pb.pause();
    offsets.sort();
    final median = offsets[offsets.length ~/ 2];
    log('PROCESSED sync: sound minus picture (mpv time-pos) median '
        '${median.toStringAsFixed(1)} ms, range '
        '${offsets.first.toStringAsFixed(1)}..${offsets.last.toStringAsFixed(1)} '
        'ms; controller estimate ${pb.soundOffsetMs?.toStringAsFixed(1)} ms, '
        '${pb.soundCorrections} corrections; video volume $videoVolume, '
        'sound file $soundFile');
    expect(soundFile, processedPath);
    expect(double.parse(videoVolume), 0);
    // Within what is not noticed: sound up to 45 ms early or 80 ms late.
    expect(median, inInclusiveRange(-PlaybackController.soundLagLimitMs,
        PlaybackController.soundDriftLimitMs));
    // "Hear original": the video's own sound at once.
    pb.hearOriginalSound = true;
    await wait(300);
    final originalVolume = await prop2(fp(), 'volume');
    log('PROCESSED hear original: video volume $originalVolume');
    expect(double.parse(originalVolume), greaterThan(90));
    pb.hearOriginalSound = false;
    await wait(300);
    expect(double.parse(await prop2(fp(), 'volume')), 0);
    // The export reads the processed file.
    expect(s.sounds.readyFiles(s.project), {'talk': processedPath});
    s.editor.removeClip('talk');
    await wait(300);
    pb.seek(500);
    await wait(500);

    // 7i. Voice recorded separately (1.10): a "camera" clip whose own sound
    // is speech-like (a tone switched on and off without a pattern, plus
    // noise) and a "microphone" file with the same speech that started
    // 0.8 s earlier, duller and quieter. Added through the Music button:
    // the question opens with Voice chosen (Zoom-style file name), the
    // real engine lines it up, it is linked on a track named after the
    // speaker, the camera is muted, it follows a split, and the preview
    // plays the voice file in step with the picture.
    final cam = p.join(fx.path, 'cam.mp4');
    final mic = p.join(fx.path, 'audioAnnaLee21406335665.m4a');
    String speechAt(String t) => "0.3*sin(2*PI*330*$t)*gt(sin(2*PI*0.7*$t)"
        "+sin(2*PI*1.13*$t)+sin(2*PI*0.31*$t+1)+sin(2*PI*2.3*$t),0.5)";
    await tester.runAsync(() async {
      await ffmpeg([
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=14', //
        '-f', 'lavfi', '-i',
        "aevalsrc='${speechAt('(t+0.8)')}':s=48000:d=14",
        '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.02:d=14',
        '-filter_complex', '[1:a][2:a]amix=inputs=2:normalize=0[a]',
        '-map', '0:v', '-map', '[a]', ...x264, '-c:a', 'aac', '-t', '14', cam,
      ]);
      await ffmpeg([
        '-f', 'lavfi', '-i', "aevalsrc='${speechAt('t')}':s=48000:d=16",
        '-af', 'lowpass=f=2000,volume=0.4', '-c:a', 'aac', mic,
      ]);
    });
    final camInfo = (await tester.runAsync(() => s.engine.probe(cam)))!;
    s.editor.addClip(Clip(
      id: 'cam',
      type: ClipType.video,
      path: cam,
      sourceDurationMs: camInfo.durationMs,
      inMs: 0,
      outMs: camInfo.durationMs,
      width: camInfo.width,
      height: camInfo.height,
      audioStreams: camInfo.audioStreams,
      frameRate: camInfo.fps,
    ));
    s.clearSelection();
    await wait(300);
    files.audio = [PickedFile(mic, 'audioAnnaLee21406335665.m4a')];
    final tracksBefore = s.project.soundTracks.length;
    await tester.tap(find.byIcon(Icons.library_music_outlined).first);
    await waitFor(() => find.text('My files').evaluate().isNotEmpty,
        'add music window');
    await tester.tap(find.text('My files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a music file…'));
    await waitFor(() => find.text('What is this sound?').evaluate().isNotEmpty,
        'the sound question');
    // Voice is chosen (the file name), with the speaker's name.
    expect(find.text('Add and line up'), findsOneWidget);
    expect(find.text('Anna Lee'), findsOneWidget);
    await shot('19-sound-question');
    final alignClock = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await waitFor(() => s.project.audio.any((a) => a.isVoice), 'voice lined up',
        timeoutMs: 60000);
    final voice = s.project.audio.firstWhere((a) => a.isVoice);
    log('VOICE lined up in ${alignClock.elapsedMilliseconds} ms: offset '
        '${voice.syncOffsetMs} ms (true 800), linked ${voice.linked}, track '
        '"${s.project.trackById(voice.trackId)?.name}", '
        '${s.project.soundTracks.length} tracks (was $tracksBefore)');
    expect(voice.syncOffsetMs, closeTo(800, 20));
    expect(voice.linked, isTrue);
    expect(voice.sourceClipId, 'cam');
    expect(s.project.trackById(voice.trackId)!.name, 'Anna Lee');
    expect(s.project.trackById(voice.trackId)!.speech, isTrue);
    Clip camClip() => s.project.clips.firstWhere((c) => c.id == 'cam');
    expect(camClip().muted, isTrue);
    await wait(600);
    await shot('20-voice-linked');
    // It follows a split of its clip.
    final camStart = s.project.clipStartMs(s.project.clips.length - 1);
    expect(s.editor.splitAt(camStart + 6000), isTrue);
    final voices = [for (final a in s.project.audio) if (a.isVoice) a]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    expect(voices.length, 2);
    expect([voices[0].startMs, voices[0].inMs, voices[0].outMs],
        [camStart, voice.syncOffsetMs!, 6000 + voice.syncOffsetMs!]);
    expect([voices[1].startMs, voices[1].inMs],
        [camStart + 6000, 6000 + voice.syncOffsetMs!]);
    // The preview: the voice file plays in step with the picture, the
    // camera's own sound is off.
    pb.seek(camStart + 1500);
    await waitFor(() => pb.loadedVideoPath == cam, 'cam.mp4 loaded');
    await wait(500);
    pb.play();
    await wait(1500);
    Player? voicePlayer;
    for (final a in backend.audioPlayers) {
      // Players of sounds that are gone were let go: skip those.
      final path = await tester.runAsync(() async {
        try {
          return await (a.player.platform as NativePlayer).getProperty('path');
        } catch (_) {
          return '';
        }
      });
      if (path == mic) voicePlayer = a.player;
    }
    expect(voicePlayer, isNotNull, reason: 'a sound player holds the voice');
    final gaps = <double>[];
    for (var i = 0; i < 10; i++) {
      await wait(200);
      final r = await tester.runAsync(() async {
        final v = fp().platform as NativePlayer;
        final a = voicePlayer!.platform as NativePlayer;
        final sw = Stopwatch()..start();
        final vt = double.parse(await v.getProperty('time-pos'));
        final t1 = sw.elapsedMicroseconds;
        final at = double.parse(await a.getProperty('time-pos'));
        final t2 = sw.elapsedMicroseconds;
        return (at - vt) * 1000 - (t2 - t1) / 1000;
      });
      gaps.add(r!);
    }
    final camVolume = await prop2(fp(), 'volume');
    pb.pause();
    gaps.sort();
    final gap = gaps[gaps.length ~/ 2];
    log('VOICE preview: voice file time minus picture time median '
        '${gap.toStringAsFixed(1)} ms (offset ${voice.syncOffsetMs}), range '
        '${gaps.first.toStringAsFixed(1)}..${gaps.last.toStringAsFixed(1)}; '
        'controller estimate ${pb.voiceOffsetMs?.toStringAsFixed(1)} ms, '
        '${pb.voiceCorrections} corrections; camera volume $camVolume');
    // Like processed clip sound: up to 45 ms early or 80 ms late.
    expect(
        gap - voice.syncOffsetMs!,
        inInclusiveRange(-PlaybackController.soundLagLimitMs,
            PlaybackController.soundDriftLimitMs));
    expect(double.parse(camVolume), 0);
    // Deleting the clips deletes their voice.
    for (final c in [...s.project.clips]) {
      if (c.path == cam) s.editor.removeClip(c.id);
    }
    expect(s.project.audio.any((a) => a.isVoice), isFalse);
    await wait(300);
    pb.seek(500);
    await wait(500);

    // 7j. Speech-to-text (1.11) in the real app: the REAL service and the
    // real ffmpeg (which turns the clip's sound into a WAV file), with a
    // pretend speech program - a shell script named whisper-cli that
    // answers --help like whisper.cpp and writes a recorded-style result -
    // and a pretend language pack. Transcribe from the Sound panel, read
    // the Text window (transcript), jump to a phrase, make captions.
    final speechRoot = p.join(out.path, 'ClipForge');
    final fakeWhisper = p.join(out.path, 'bin', 'whisper-cli');
    final fixtureJson = p.join(Directory.current.path, 'test', 'media',
        'fixtures', 'speech', 'whispercpp_words_ru.json');
    await tester.runAsync(() async {
      await Directory(p.dirname(fakeWhisper)).create(recursive: true);
      await File(fakeWhisper).writeAsString('''
#!/bin/sh
case "\$1" in --help) echo "usage: whisper-cli -oj --output-json -ojf -sow --split-on-word"; exit 0;; esac
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-of" ]; then out="\$2"; fi
  if [ "\$1" = "-f" ] && [ ! -s "\$2" ]; then echo "no sound file" >&2; exit 3; fi
  shift
done
echo "whisper_print_progress_callback: progress =  50%" >&2
cp "$fixtureJson" "\$out.json"
''');
      await Process.run('chmod', ['+x', fakeWhisper]);
      final models = Directory(p.join(speechRoot, 'models'));
      await models.create(recursive: true);
      await File(p.join(models.path, 'ggml-base.bin')).writeAsBytes(List.filled(64, 1));
      await File(p.join(models.path, 'speech-settings.json'))
          .writeAsString(jsonEncode({'programPath': fakeWhisper}));
    });
    s.editor.addClip(Clip(
      id: 'speech-clip',
      type: ClipType.video,
      path: cam,
      sourceDurationMs: camInfo.durationMs,
      inMs: 0,
      outMs: camInfo.durationMs,
      width: camInfo.width,
      height: camInfo.height,
    ));
    final speechIndex = s.project.clips.indexWhere((c) => c.id == 'speech-clip');
    final speechStart = s.project.clipStartMs(speechIndex);
    s.selectClipAndShow('speech-clip');
    s.openTool.value = ClipTool.sound;
    await waitFor(
        () => find.byKey(const ValueKey('transcribe-button')).evaluate().isNotEmpty,
        'Transcribe speech… in the Sound panel');
    await tester.ensureVisible(find.byKey(const ValueKey('transcribe-button')));
    await wait(200);
    await tester.tap(find.byKey(const ValueKey('transcribe-button')));
    await waitFor(
        () => find.textContaining('whisper.cpp on this computer').evaluate().isNotEmpty,
        'the speech program was found');
    expect(find.text('Small · about 140 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('pack-remove-small')), findsOneWidget);
    await shot('09-transcribe');
    await tester.tap(find.byKey(const ValueKey('transcribe-go')));
    await waitFor(
        () => find.byKey(const ValueKey('transcribe-dialog')).evaluate().isEmpty,
        'the speech was transcribed', timeoutMs: 60000);
    final transcript = s.transcriptOf(cam, 0);
    expect(transcript, isNotNull);
    expect(transcript!.backend, 'whisper-cpp');
    expect(transcript.wordTiming, WordTiming.measured);
    expect(transcript.wordCount, 20);
    // Its own file in the project folder, not in project.json.
    final stored = await tester.runAsync(() async =>
        Directory(p.join(storeDir.path, s.project.id, 'transcripts')).list().length);
    expect(stored, 1);
    log('SPEECH: ${transcript.wordCount} words via ${transcript.backend} '
        '(${transcript.model}), language ${transcript.language}');
    // The Text window (1.13) shows the transcript while there are no
    // captions.
    Finder inText(String phrase) => find.byWidgetPredicate((w) =>
        w is RichText &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('text-body-') &&
        w.text.toPlainText().contains(phrase));
    Future<void> tapInText(String phrase) async {
      final render = tester.renderObject<RenderParagraph>(inText(phrase).first);
      final at = render.text.toPlainText().indexOf(phrase);
      final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + phrase.length));
      await tester.tapAt(render.localToGlobal(boxes.first.toRect().center));
    }

    s.showText.value = true;
    await waitFor(() => inText('Привет, друзья!').evaluate().isNotEmpty,
        'the Text window with the transcript');
    await tapInText('Потом вы ждёте.');
    await wait(400);
    expect(pb.positionMs, closeTo(speechStart + 10000, 60));
    await shot('09-transcript');
    await tester.ensureVisible(find.byKey(const ValueKey('speech-captions-button')));
    await wait(200);
    await tester.tap(find.byKey(const ValueKey('speech-captions-button')));
    await waitFor(
        () => find.byKey(const ValueKey('speech-captions-add')).evaluate().isNotEmpty,
        'Captions from speech');
    await tester.tap(find.byKey(const ValueKey('speech-captions-add')));
    await wait(500);
    final speechCaptions =
        s.project.titles.where((t) => t.kind == TitleKind.caption).toList();
    expect(speechCaptions.length, greaterThanOrEqualTo(4));
    expect(speechCaptions.any((t) => t.text.contains('Привет')), isTrue);
    pb.seek(speechStart + 600);
    await wait(600);
    await shot('09-speech-captions');
    log('SPEECH: ${speechCaptions.length} captions from speech; first '
        '"${speechCaptions.first.text.replaceAll('\n', ' / ')}"');
    // With captions, the Text window shows those; one is fixed in place.
    await waitFor(
        () => find.byKey(const ValueKey('text-source-captions')).evaluate().isNotEmpty,
        'the Text window switches to the captions');
    final fix = speechCaptions.first;
    await tester.tap(find.byKey(const ValueKey('text-search')));
    await tapInText(fix.text.split('\n').first.split(' ').first);
    await wait(300);
    expect(s.selection.value?.id, fix.id);
    await tester.tap(find.byKey(const ValueKey('text-edit')));
    await wait(300);
    await tester.enterText(
        find.byKey(const ValueKey('text-edit-field')), 'Исправлено.');
    await tester.tap(find.byKey(const ValueKey('text-edit-save')));
    await wait(300);
    expect(s.project.titles.firstWhere((t) => t.id == fix.id).text, 'Исправлено.');
    expect(s.editor.history.last.label, startsWith('Edited caption'));
    await shot('09-text-window');
    log('TEXT WINDOW: transcript and captions shown, a caption edited in place');
    s.editor.undo();
    // The sound pictures of the real files: drawn in the background.
    await waitFor(() => !s.pictures.busy, 'the sound pictures', timeoutMs: 60000);
    final spoken = s.project.clips.firstWhere((c) => c.id == 'speech-clip');
    final picture = s.pictures.peaksOf(spoken.path, spoken.audioTrackInUse);
    expect(picture, isNotNull);
    expect(picture!.durationMs, greaterThan(1000));
    expect(find.byKey(const ValueKey('wave-speech-clip')), findsOneWidget);
    log('SOUND WAVES: ${picture.durationMs} ms of "${p.basename(spoken.path)}" drawn, '
        '${s.pictures.speakers.map((t) => '${t.name}: ${t.stretches.length} stretch(es)').join(', ')}');
    s.showText.value = false;
    s.editor.removeClip('speech-clip');
    expect(s.project.titles.where((t) => t.kind == TitleKind.caption &&
        speechCaptions.any((c) => c.id == t.id)), isEmpty);
    await wait(300);
    pb.seek(500);
    await wait(500);

    final finalDuration = pb.durationMs;

    // Leave the editor: the project is saved to disk and listed.
    await tester.tap(find.byTooltip('Back to projects'));
    await waitFor(() => find.byType(PreviewView).evaluate().isEmpty,
        'back on the home screen');
    await wait(500);
    final saved = await tester
        .runAsync(() => ProjectStore.atPath(storeDir.path).list());
    log('saved projects: ${[for (final i in saved!) '${i.name} ${i.durationMs}']}');
    expect(saved.single.durationMs, finalDuration);
    await shot('08-home');
  });
}
