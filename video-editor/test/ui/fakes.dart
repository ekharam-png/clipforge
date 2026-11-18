import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clipforge/core/update/update_download.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/ui/claude/claude_helper.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:clipforge/core/storage/project_lock.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/ui/about.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/processed_sound.dart';
import 'package:clipforge/media/processed_sound_cache.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/timeline_view.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/help/tour.dart';
import 'package:clipforge/ui/help/tour_sample.dart';
import 'package:clipforge/core/music/openverse.dart';
import 'package:clipforge/ui/gallery_search.dart';
import 'package:clipforge/ui/music_search.dart';
import 'package:clipforge/ui/services.dart';
import 'package:clipforge/ui/speech/speech_service.dart';
import 'package:clipforge/ui/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

class FakeProjectStore implements ProjectStore {
  FakeProjectStore([List<Project> projects = const []]) {
    for (final p in projects) {
      this.projects[p.id] = p;
    }
  }

  final Map<String, Project> projects = {};
  int saves = 0;

  /// Set to make every [save] fail, like a full disk.
  bool failSaves = false;

  @override
  Future<List<ProjectInfo>> list() async {
    final sorted = projects.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final p in sorted)
        ProjectInfo(
          id: p.id,
          name: p.name,
          updatedAt: p.updatedAt,
          durationMs: p.durationMs,
          thumbnailSourcePath: p.clips.isEmpty ? null : p.clips.first.path,
        ),
    ];
  }

  @override
  Future<Project> create(String name) async {
    final now = DateTime(2026, 11, 15, 12);
    final p = Project(
        id: 'new${projects.length}', name: name, createdAt: now, updatedAt: now);
    projects[p.id] = p;
    return p;
  }

  @override
  Future<Project> load(String id) async =>
      projects[id] ?? (throw StateError('No project $id'));

  @override
  Future<void> save(Project project) async {
    if (failSaves) throw const FileSystemException('No space left on device');
    saves++;
    projects[project.id] = project;
  }

  @override
  Future<void> delete(String id) async => projects.remove(id);

  @override
  Future<Project> duplicate(String id, {String? name}) async {
    final source = await load(id);
    final now = DateTime(2026, 11, 15, 12);
    final copy = Project.fromJson({
      ...source.toJson(),
      'id': 'copy${projects.length}',
      'name': name ?? '${source.name} copy',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    projects[copy.id] = copy;
    return copy;
  }
}

class FakeExportJob implements ExportJob {
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  bool cancelled = false;

  void report(double fraction) => _progress.add(ExportProgress(fraction));
  void finish(String path, {VideoEncoder encoder = VideoEncoder.libx264}) {
    videoEncoder = encoder;
    _done.complete(path);
  }

  @override
  VideoEncoder? videoEncoder;

  @override
  List<String> warnings = const [];
  void fail(ExportException e) => _done.completeError(e);

  @override
  Stream<ExportProgress> get progress => _progress.stream;

  @override
  Future<String> get done => _done.future;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_done.isCompleted) _done.completeError(ExportException('Cancelled'));
  }
}

class FakeMediaEngine implements MediaEngine {
  final Map<String, MediaInfo> infos = {};
  final Map<String, String> thumbnails = {};
  final List<FakeExportJob> jobs = [];
  String? lastExportPath;
  ExportOptions? lastOptions;

  /// What [detectSilence] answers, per file.
  final Map<String, List<({int startMs, int endMs})>> silences = {};

  /// When set, [detectSilence] waits for it (to show the progress state).
  Completer<void>? silenceGate;
  final List<String> silenceRequests = [];

  /// `path@timeMs -> output` for every [extractFrame] call.
  final List<String> frames = [];

  @override
  Future<String> extractFrame(
      String path, int timeMs, String outputPath) async {
    frames.add('$path@$timeMs -> $outputPath');
    infos[outputPath] = const MediaInfo(
        durationMs: 0, width: 1920, height: 1080, hasVideo: true, hasAudio: false);
    return outputPath;
  }

  @override
  Future<List<({int startMs, int endMs})>> detectSilence(String path,
      {double? thresholdDb,
      int minSilenceMs = 700,
      int audioTrack = 0,
      AudioChannel channel = AudioChannel.both}) async {
    silenceRequests.add(path);
    await silenceGate?.future;
    return silences[path] ?? const [];
  }

  @override
  Future<MediaInfo> probe(String path) async =>
      infos[path] ?? (throw const FileSystemException('unreadable'));

  @override
  Future<String> thumbnail(String path,
          {int timeMs = 0, int maxHeight = 160}) async =>
      thumbnails[path] ?? (throw const FileSystemException('no thumbnail'));

  /// What [hasHardwareEncoder] answers.
  bool hardwareEncoder = false;

  @override
  Future<bool> hasHardwareEncoder() async => hardwareEncoder;

  /// Which graphics card encoder [graphicsCardEncoder] names when
  /// [hardwareEncoder] is true.
  VideoEncoder graphicsCardKind = VideoEncoder.mediaFoundation;

  @override
  Future<VideoEncoder?> graphicsCardEncoder() async =>
      hardwareEncoder ? graphicsCardKind : null;

  /// Every [renderClipSound] call: the clip, where it goes, and its job
  /// (finish it with [FakeExportJob.finish]).
  final List<({Clip clip, String path, FakeExportJob job})> soundRenders = [];

  @override
  ExportJob renderClipSound(Clip clip, String outputPath) {
    final job = FakeExportJob();
    soundRenders.add((clip: clip, path: outputPath, job: job));
    return job;
  }

  @override
  ExportJob export(Project project, String outputPath,
      {ExportOptions options = const ExportOptions()}) {
    lastExportPath = outputPath;
    lastOptions = options;
    final job = FakeExportJob();
    jobs.add(job);
    return job;
  }
}

class FakeFileService implements FileService {
  List<PickedFile> media = [];
  List<PickedFile> audio = [];
  String? savePath = '/out/movie.mp4';
  bool desktop = true;
  String? copiedTo;

  @override
  Future<List<PickedFile>> pickMedia() async => media;

  @override
  Future<List<PickedFile>> pickAudio() async => audio;

  @override
  bool get canChooseSaveLocation => desktop;

  @override
  Future<String?> chooseSavePath(String fileName) async => savePath;

  @override
  Future<String> appExportPath(String fileName) async => '/app/exports/$fileName';

  /// Set to false to act like a user who refuses the storage permission.
  bool galleryAllowed = true;

  @override
  Future<String?> saveCopy(String sourcePath, String fileName) async {
    if (!galleryAllowed) return null;
    copiedTo = sourcePath;
    return 'your gallery (Movies)';
  }
}

class FakeDocumentService implements DocumentService {
  /// What the next [pickFile] returns (null = cancelled).
  PickedFile? pick;
  final Map<String, String> texts = {};
  final Map<String, String> savedTexts = {};
  final List<String> savedFiles = [];
  bool cancelSave = false;

  @override
  Future<PickedFile?> pickFile(List<String> extensions) async => pick;

  @override
  Future<String> readText(String path) async =>
      texts[path] ?? (throw const FileSystemException('unreadable'));

  @override
  Future<String?> saveText(String fileName, String content) async {
    if (cancelSave) return null;
    savedTexts[fileName] = content;
    return '/out/$fileName';
  }

  @override
  Future<String?> saveFile(
      String fileName, Future<void> Function(String path) write) async {
    if (cancelSave) return null;
    await write('/out/$fileName');
    savedFiles.add('/out/$fileName');
    return '/out/$fileName';
  }

  /// True to act like a phone: project files go to the share sheet.
  bool phone = false;

  /// Set to true to act like a user who closes the share sheet.
  bool dismissShare = false;
  final List<String> sharedFiles = [];

  @override
  bool get sharesFiles => phone;

  @override
  Future<bool> shareFile(
      String fileName, Future<void> Function(String path) write) async {
    await write('/cache/$fileName');
    if (dismissShare) return false;
    sharedFiles.add(fileName);
    return true;
  }

  @override
  Future<String> mediaDir() async => '/app/media';
}

/// Processed sound files in memory: every clip that needs one has a key,
/// and [files] holds the keys that are "on disk".
class FakeSoundCache implements ProcessedSoundCache {
  final Set<String> files = {};
  final List<String> touched = [];
  int evictions = 0;

  @override
  String? keyFor(Clip clip) => clipNeedsProcessedSound(clip)
      ? processedSoundKey(clip, size: 1, modifiedMs: 0)
      : null;

  @override
  String pathFor(String key) => '/app/media/processed/$key.flac';

  @override
  Future<void> ready() async {}

  @override
  bool has(String key) => files.contains(key);

  @override
  void touch(String key) => touched.add(key);

  @override
  Future<int> evict({required int maxBytes, Set<String> keep = const {}}) async {
    evictions++;
    return 0;
  }

  @override
  Future<void> remove(String key) async => files.remove(key);
}

class FakeProjectBundles implements ProjectBundles {
  final List<String> exported = [];
  final Map<String, Project> bundles = {};

  /// When set, [exportBundle] reports half way and waits for it.
  Completer<void>? exportGate;

  /// Media that [exportBundle] reports as left out.
  List<String> skipped = const [];

  @override
  Future<List<String>> exportBundle(Project project, String zipPath,
      {void Function(double fraction)? onProgress}) async {
    onProgress?.call(0.5);
    await exportGate?.future;
    onProgress?.call(1);
    exported.add(zipPath);
    bundles[zipPath] = project;
    return skipped;
  }

  @override
  Future<Project> importBundle(String zipPath,
      {required ProjectStore store, required String mediaDir}) async {
    final source =
        bundles[zipPath] ?? (throw const FormatException('Not a project file'));
    final project = Project.fromJson({
      ...source.toJson(),
      'id': 'imported${bundles.length}',
    });
    await store.save(project);
    return project;
  }
}

class Fakes {
  Fakes({List<Project> projects = const [], Set<String> missing = const {}})
      : missing = {...missing},
        store = FakeProjectStore(projects);

  final FakeProjectStore store;
  final FakeMediaEngine engine = FakeMediaEngine();
  final FakeFileService files = FakeFileService();
  final FakeDocumentService documents = FakeDocumentService();
  final FakeProjectBundles bundles = FakeProjectBundles();
  final FakeBackend backend = FakeBackend();
  final FakeFileDropService drops = FakeFileDropService();
  final FakeSoundCache soundCache = FakeSoundCache();

  /// Finishes every processed sound render that is still running: the
  /// file is "written" and the job completes.
  void finishSoundRenders() {
    for (final r in engine.soundRenders) {
      if (r.job.cancelled) continue;
      final name = r.path.split('/').last;
      soundCache.files.add(name.substring(0, name.lastIndexOf('.')));
      try {
        r.job.finish(r.path);
      } on StateError {
        // Finished before.
      }
    }
  }

  /// Files that are not there. Add or remove paths during a test to move
  /// files around.
  final Set<String> missing;
  final GlobalKey shotKey = GlobalKey();

  /// How often the app tidied its media folder.
  int cleanups = 0;

  /// "Find free music" (off unless a test turns it on).
  final FakeMusicSearch music = FakeMusicSearch();

  /// "Find file…" > "Search the gallery" (off unless a test turns it on).
  final FakeGallerySearch gallery = FakeGallerySearch();

  /// Speech-to-text. Null (the default) is what a phone has; tests of the
  /// 1.11 speech features put a [FakeSpeech] here.
  SpeechService? speech;

  /// When set, the editor's "open in the app" lock is written in
  /// `<lockRoot>/<project id>` (real files); otherwise there is none.
  String? lockRoot;

  /// What open editors tell the media clean-up they still use.
  final LiveMedia liveMedia = LiveMedia();

  /// Project folders the home screen is told cannot be read.
  List<DamagedProject> damaged = const [];

  /// App settings. The tour question counts as answered, so that it does
  /// not pop up in tests about other things.
  final MemoryAppPrefs prefs = MemoryAppPrefs(answered: true);

  /// The build the app says it is (About, version line).
  BuildInfo buildInfo = BuildInfo.current;

  /// The device "Copy version info" reports.
  DeviceDetails device = const DeviceDetails(system: 'TestOS 1.0, test_x64');

  /// Updates (1.12): what the system does, what latest.json says (null =
  /// offline), and the download a test can steer.
  final FakeUpdatePlatform updatePlatform = FakeUpdatePlatform();
  UpdateInfo? latest;
  int updateChecks = 0;
  UpdateDownload Function(UpdateAsset asset, String dir, int build)? downloader;

  /// "Connect to Claude" (a phone by default: nothing is installed).
  ClaudeHelperService? claude;

  /// How many tour sample projects were made.
  int samplesMade = 0;

  /// The tour's sample project, with made-up paths (nothing is written).
  Future<Project> makeTourSample(
      ProjectStore store, DocumentService documents) async {
    samplesMade++;
    final created = await store.create(kTourSampleName);
    final project = buildTourSample(created,
        video: '/app/media/tour_video.mp4',
        photo1: '/app/media/tour_photo1.png',
        photo2: '/app/media/tour_photo2.png');
    await store.save(project);
    return project;
  }

  /// [home] inside the app theme with every service replaced by a fake.
  /// [menuBar]: with the app's menu bar around it, as in the real app
  /// (shown on macOS, Windows and Linux only).
  Widget app(Widget home, {bool menuBar = false, HelpMenuActions? help}) =>
      ProviderScope(
        overrides: [
          projectStoreProvider.overrideWith((ref) => store),
          mediaEngineProvider.overrideWithValue(engine),
          playerBackendProvider.overrideWithValue(backend),
          fileServiceProvider.overrideWithValue(files),
          documentServiceProvider.overrideWithValue(documents),
          projectBundlesProvider.overrideWithValue(bundles),
          fileDropServiceProvider.overrideWithValue(drops),
          processedSoundCacheProvider.overrideWithValue(soundCache),
          musicSearchProvider.overrideWithValue(music),
          gallerySearchProvider.overrideWithValue(gallery),
          liveMediaProvider.overrideWithValue(liveMedia),
          projectLockProvider.overrideWithValue((store, id) => lockRoot == null
              ? null
              : AppProjectLock('$lockRoot/$id', app: 'test')),
          fileExistsProvider
              .overrideWithValue((path) => !missing.contains(path)),
          missingMediaProvider.overrideWithValue((project) async {
            final paths = <String>{
              for (final c in project.clips) c.path,
              for (final a in project.audio) a.path,
              for (final o in project.overlays) o.path,
            };
            return [
              for (final p in paths)
                if (missing.contains(p)) p,
            ];
          }),
          mediaCleanupProvider.overrideWithValue((store) async {
            cleanups++;
            return 0;
          }),
          damagedProjectsProvider
              .overrideWithValue((store, readable) async => damaged),
          // Null = a phone: nothing about speech-to-text exists.
          speechServiceProvider.overrideWithValue(speech),
          appPrefsProvider.overrideWithValue(prefs),
          tourSampleProvider.overrideWithValue(makeTourSample),
          buildInfoProvider.overrideWithValue(buildInfo),
          deviceDetailsProvider.overrideWithValue(() async => device),
          updatePlatformProvider.overrideWithValue(updatePlatform),
          updateFetcherProvider.overrideWithValue(() async {
            updateChecks++;
            final info = latest;
            if (info == null) {
              throw UpdateException(
                  'ClipForge could not reach the update server. Check the '
                  'internet connection and try again.',
                  kind: 'offline');
            }
            return info;
          }),
          updateDownloaderProvider.overrideWithValue((asset, dir, build) =>
              (downloader ?? (a, d, b) => downloadUpdate(a, d, build: b))(
                  asset, dir, build)),
          claudeHelperProvider.overrideWithValue(claude ??
              ClaudeHelperService(
                  build: buildInfo,
                  os: 'android',
                  loadBundle: () async => null)),
        ],
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: home,
            builder: (context, child) => menuBar
                ? AppMenuBar(
                    help: help, child: TourOverlayHost(child: child!))
                : TourOverlayHost(child: child!),
          ),
        ),
      );

  /// Writes what is on screen to docs/screenshots/[name].png when the tests
  /// run with `--dart-define=SCREENSHOTS=true`.
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final boundary = shotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}

/// What the app would ask the system for an update; records it instead.
class FakeUpdatePlatform implements UpdatePlatform {
  @override
  String os = 'linux';
  String? key;
  final List<String> opened = [];
  final List<String> installed = [];
  final List<String> revealed = [];
  int quits = 0;
  String dir = '/nonexistent/clipforge-test-updates';
  @override
  String? installDir;

  @override
  Future<String?> platformKey() async => key;
  @override
  Future<void> openUrl(String url) async => opened.add(url);
  @override
  Future<String> downloadDir() async => '$dir/downloads';
  @override
  Future<String> stateDir() async => '$dir/state';
  @override
  Future<String> swapScript() async => '#!/bin/sh\nexit 0\n';
  @override
  Future<void> installApk(String path) async => installed.add(path);
  @override
  Future<void> reveal(String path) async => revealed.add(path);
  @override
  Future<void> quit() async => quits++;
}

void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const phone = Size(390, 844);
const desktop = Size(1280, 800);

/// Loads the real Roboto and Material icon fonts so screenshots have text.
Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, List<String> names) async {
    final loader = FontLoader(family);
    for (final name in names) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) continue;
      loader.addFont(file
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  // The engine announces every loaded font with a message. Let them all
  // arrive before the first test, or one schedules a frame in the middle
  // of that test ("an animation is still running").
  var announced = 0;
  void onFonts() => announced++;
  PaintingBinding.instance.systemFonts.addListener(onFonts);
  await load('Roboto',
      ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // The preview registers the title fonts the first time an editor opens;
  // do that here so it does not happen inside the first test.
  await loadTitleFonts();
  for (var waited = 0, seen = -1; waited < 40 && seen != announced; waited++) {
    seen = announced;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  PaintingBinding.instance.systemFonts.removeListener(onFonts);
}

Clip videoClip(String id, String path, int inMs, int outMs,
        {int width = 1920, int height = 1080, bool muted = false}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: 20000,
      inMs: inMs,
      outMs: outMs,
      width: width,
      height: height,
      muted: muted,
    );

Clip photoClip(String id, String path, {int ms = 3000}) => Clip(
      id: id,
      type: ClipType.photo,
      path: path,
      sourceDurationMs: 0,
      inMs: 0,
      outMs: ms,
      width: 1200,
      height: 1600,
      hasAudio: false,
      fit: FitMode.blur,
    );

Project sampleProject({String id = 'p1', String name = 'Summer trip'}) => Project(
      id: id,
      name: name,
      createdAt: DateTime(2026, 11, 1, 9),
      updatedAt: DateTime(2026, 11, 14, 18, 30),
      aspect: CanvasAspect.landscape16x9,
      clips: [
        videoClip('a', '/media/beach.mp4', 0, 6000),
        photoClip('b', '/media/sunset.jpg'),
        videoClip('c', '/media/gone.mp4', 2000, 7000),
        videoClip('d', '/media/hike.mp4', 1000, 5000, muted: true),
      ],
      audio: const [
        AudioClip(
          id: 'm1',
          path: '/media/song.mp3',
          sourceDurationMs: 180000,
          startMs: 1000,
          inMs: 0,
          outMs: 12000,
          volume: 0.8,
          fadeInMs: 500,
          fadeOutMs: 1500,
        ),
      ],
      titles: const [
        TitleOverlay(
          id: 't1',
          text: 'Summer 2026',
          startMs: 0,
          endMs: 4000,
          y: 0.8,
          fontSize: 0.09,
          background: true,
        ),
      ],
    );

const missing = {'/media/gone.mp4'};

Finder clipBlocks() => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('clip-');
    });

Finder block(String key) => find.byKey(ValueKey(key));

Future<Fakes> openEditor(WidgetTester tester, Size size,
    {Project? project, Set<String> missingFiles = missing}) async {
  useScreen(tester, size);
  final fakes =
      Fakes(projects: [project ?? sampleProject()], missing: missingFiles);
  await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  return fakes;
}

/// Top left of the scrolled part of the timeline (right of the row
/// headers).
Offset timelineOrigin(WidgetTester tester) {
  final t = find.byType(TimelineView);
  return tester.getTopLeft(t) +
      Offset(TimelineView.headerWidthFor(tester.getSize(t).width), 0);
}

/// Taps the time ruler at [ms] (timeline not scrolled, default zoom).
Future<void> seekTo(WidgetTester tester, int ms, {double zoom = 60}) async {
  final origin = timelineOrigin(tester);
  await tester.tapAt(origin + Offset(28 + ms * zoom / 1000, 10));
  await tester.pump();
}

Project saved(Fakes fakes) => fakes.store.projects['p1']!;


/// Opens one group of clip settings for the selected clip: a bottom sheet
/// on the phone, a section of the side panel on the desktop.
Future<void> openClipTool(WidgetTester tester, Size size, String label) async {
  if (size == phone) {
    if (label.startsWith('Transition')) {
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(label).first);
  } else {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
  }
  await tester.pumpAndSettle();
}

/// Closes a bottom sheet (phone); nothing to close on the desktop.
Future<void> closeSheet(WidgetTester tester, Size size) async {
  if (size != phone) return;
  await tester.tapAt(const Offset(10, 60));
  await tester.pumpAndSettle();
}

List<String> clipIds(Project p) => [for (final c in p.clips) c.id];

bool undoEnabled(WidgetTester tester) =>
    tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
        .onPressed !=
    null;

/// Zooms the timeline out twice (to 26.67 px per second) so that the whole
/// sample project fits on a phone.
Future<void> zoomOutTwice(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Zoom out timeline'));
  await tester.tap(find.byTooltip('Zoom out timeline'));
  await tester.pumpAndSettle();
}

/// Lets a message at the bottom of the screen go away.
Future<void> waitForMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}


/// Files dragged onto the window, driven by the test: [hover], [leave],
/// [drop]. Like the plugin, every enabled drop area hears the drag and
/// reacts only when the point is inside it.
class FakeFileDropService implements FileDropService {
  @override
  bool supported = true;

  final List<_FakeDropTargetState> _targets = [];

  /// Drop areas that are on screen and enabled.
  int get activeTargets => _targets.where((t) => t.widget.enabled).length;

  @override
  Widget target({
    required bool enabled,
    required ValueChanged<Offset?> onHover,
    required ValueChanged<FileDrop> onDrop,
    required Widget child,
  }) =>
      _FakeDropTarget(
          service: this,
          enabled: enabled,
          onHover: onHover,
          onDrop: onDrop,
          child: child);

  Iterable<_FakeDropTargetState> get _active =>
      _targets.where((t) => t.widget.enabled).toList();

  void hover(Offset at) {
    for (final t in _active) {
      t.widget.onHover(t.contains(at) ? at : null);
    }
  }

  void leave() {
    for (final t in _active) {
      t.widget.onHover(null);
    }
  }

  /// Drops [paths] (files, in this order) at [at].
  void drop(List<String> paths,
      {Offset at = const Offset(400, 300),
      List<DroppedFile>? files,
      List<String> folders = const []}) {
    final drop = FileDrop(
        files: files ?? [for (final p in paths) DroppedFile(p)],
        folders: folders,
        globalPosition: at);
    for (final t in _active) {
      t.widget.onHover(null);
      if (t.contains(at)) t.widget.onDrop(drop);
    }
  }
}

class _FakeDropTarget extends StatefulWidget {
  const _FakeDropTarget({
    required this.service,
    required this.enabled,
    required this.onHover,
    required this.onDrop,
    required this.child,
  });
  final FakeFileDropService service;
  final bool enabled;
  final ValueChanged<Offset?> onHover;
  final ValueChanged<FileDrop> onDrop;
  final Widget child;

  @override
  State<_FakeDropTarget> createState() => _FakeDropTargetState();
}

class _FakeDropTargetState extends State<_FakeDropTarget> {
  @override
  void initState() {
    super.initState();
    widget.service._targets.add(this);
  }

  @override
  void dispose() {
    widget.service._targets.remove(this);
    super.dispose();
  }

  bool contains(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


/// Recorded music search: [pages] answers by query, [error] instead.
class FakeMusicSearch extends MusicSearch {
  bool on = false;
  final Map<String, MusicSearchPage> pages = {};
  MusicSearchException? error;
  final List<String> queries = [];
  final List<String> downloads = [];

  @override
  bool get available => on;

  @override
  Future<MusicSearchPage> search(String query,
      {bool includeRestricted = false, int page = 1}) async {
    queries.add('$query|$includeRestricted|$page');
    final e = error;
    if (e != null) throw e;
    return pages[query] ?? const MusicSearchPage(results: []);
  }

  @override
  Future<String> download(MusicResult result, String mediaDir,
      {void Function(double fraction)? onProgress}) async {
    final e = error;
    if (e != null) throw e;
    final path = musicDownloadPath(result, mediaDir);
    downloads.add(path);
    onProgress?.call(1);
    return path;
  }
}

class FakeGallerySearch extends GallerySearch {
  bool on = false;
  List<GalleryItem> found = const [];
  bool denied = false;

  /// Where [fetch] says it put a file (by uri).
  final Map<String, String> fetched = {};

  @override
  bool get supported => on;

  @override
  Future<List<GalleryItem>> findByName(String name) async {
    if (denied) throw const GallerySearchDenied();
    return [
      for (final f in found)
        if (f.name.toLowerCase() == name.toLowerCase()) f,
    ];
  }

  @override
  Future<String> fetch(GalleryItem item) async =>
      fetched[item.uri] ?? '/gallery/${item.name}';
}

/// Speech-to-text without any program or file: what is "installed" and
/// what a transcription "hears" are set by the test.
class FakeSpeech implements SpeechService {
  FakeSpeech({this.backend = ffmpegFilter, Set<String>? packs})
      : installedIds = {...?packs};

  static const ffmpegFilter = BackendInfo(
      id: 'ffmpeg-whisper',
      label: 'FFmpeg on this computer (its "whisper" filter)',
      program: '/usr/bin/ffmpeg',
      measuresWords: false,
      usesPacks: true);
  static const whisperCpp = BackendInfo(
      id: 'whisper-cpp',
      label: 'whisper.cpp on this computer (whisper-cli)',
      program: '/usr/local/bin/whisper-cli',
      measuresWords: true,
      usesPacks: true);

  /// The speech program found; null = none on this computer.
  BackendInfo? backend;
  final Set<String> installedIds;

  /// What transcribing a file gives, by path (others fail).
  final Map<String, Transcript> hears = {};

  /// Transcripts already in the project folder, by SpeechSource.key.
  final Map<String, Transcript> stored = {};
  final List<String> downloadsStarted = [];
  final List<String> transcribed = [];
  final List<String> removed = [];
  StreamController<SpeechProgress>? _downloadProgress;
  Completer<void>? _download;
  String? _downloadId;

  /// When false, transcriptions wait for [finishTranscribe].
  bool instant = true;
  final List<void Function()> _pending = [];

  @override
  String? modelFile;

  InstalledModel? _installed(String id) => installedIds.contains(id)
      ? InstalledModel(
          kSpeechModels.firstWhere((m) => m.id == id), '/models/$id', 148 * 1024 * 1024)
      : null;

  @override
  Future<SpeechPlan> plan(
      {String language = 'auto',
      SpeechQuality quality = SpeechQuality.auto}) async {
    final b = backend;
    if (b == null) {
      return SpeechPlan(problem: noBackendExplanation('windows'), language: language);
    }
    final ids = modelIdsFor(language == 'auto' ? '' : language, quality);
    for (final id in ids) {
      final m = _installed(id);
      if (m != null) {
        return SpeechPlan(backend: b, model: m, modelName: id, language: language);
      }
    }
    if (quality == SpeechQuality.auto) {
      return SpeechPlan(backend: b, needsChoice: true, language: language);
    }
    return SpeechPlan(
        backend: b,
        download: kSpeechModels.firstWhere((m) => m.id == ids.first),
        language: language);
  }

  @override
  List<PackRow> packs(String language) {
    final lang = language == 'auto' ? '' : language;
    return [
      for (final size in const [
        SpeechQuality.small,
        SpeechQuality.medium,
        SpeechQuality.large
      ])
        () {
          InstalledModel? found;
          for (final id in modelIdsFor(lang, size)) {
            found ??= _installed(id);
          }
          return (
            size: size,
            model: found?.model ??
                kSpeechModels
                    .firstWhere((m) => m.id == modelIdsFor(lang, size).first),
            installed: found,
          );
        }(),
    ];
  }

  @override
  int get packsBytes => installedIds.length * 148 * 1024 * 1024;

  @override
  SpeechTask<void> downloadPack(SpeechModel model) {
    downloadsStarted.add(model.id);
    final progress = _downloadProgress = StreamController<SpeechProgress>.broadcast();
    final done = _download = Completer<void>();
    done.future.ignore();
    _downloadId = model.id;
    return SpeechTask(progress.stream, done.future, () async {
      if (!done.isCompleted) {
        done.completeError(SpeechException('Stopped.', cancelled: true));
      }
    });
  }

  /// The running download gets to [fraction].
  void downloadProgress(double fraction) => _downloadProgress!.add(SpeechProgress(
      SpeechPhase.downloading, fraction, '${(fraction * 142).round()} MB of 142 MB'));

  /// The running download is complete (or fails with [error]).
  void finishDownload({String? error}) {
    if (error != null) {
      _download!.completeError(SpeechException(error, kind: 'failed'));
    } else {
      installedIds.add(_downloadId!);
      _download!.complete();
    }
  }

  @override
  Future<void> removePack(SpeechModel model) async {
    removed.add(model.id);
    installedIds.remove(model.id);
    checkFailedIds.remove(model.id);
  }

  /// Packs that were downloaded but failed their check.
  final Set<String> checkFailedIds = {};

  @override
  bool packCheckFailed(SpeechModel model) => checkFailedIds.contains(model.id);

  @override
  Future<bool> usePackAnyway(SpeechModel model) async {
    if (!checkFailedIds.remove(model.id)) return false;
    installedIds.add(model.id);
    return true;
  }

  @override
  Future<void> useModelFile(String? path) async => modelFile = path;

  @override
  SpeechTask<Transcript> transcribe(String projectId, SpeechSource source,
      {String language = 'auto', SpeechQuality quality = SpeechQuality.auto}) {
    transcribed.add('${source.path}|$language|${quality.name}');
    final progress = StreamController<SpeechProgress>.broadcast();
    final done = Completer<Transcript>();
    done.future.ignore();
    void finish() {
      if (done.isCompleted) return;
      final t = hears[source.path];
      if (t == null) {
        done.completeError(SpeechException(
            'The speech program stopped with an error.',
            kind: 'failed'));
      } else {
        stored[source.key] = t;
        done.complete(t);
      }
    }

    if (instant) {
      scheduleMicrotask(finish);
    } else {
      scheduleMicrotask(() => progress.add(const SpeechProgress(
          SpeechPhase.transcribing, 0.4, 'Listening to the speech… 40%')));
      _pending.add(finish);
    }
    return SpeechTask(progress.stream, done.future, () async {
      if (!done.isCompleted) {
        done.completeError(SpeechException('Stopped.', cancelled: true));
      }
    });
  }

  void finishTranscribe() {
    for (final f in _pending) {
      f();
    }
    _pending.clear();
  }

  @override
  Future<Map<String, Transcript>> transcriptsOf(
          String projectId, List<SpeechSource> sources) async =>
      {
        for (final s in sources)
          if (stored[s.key] != null) s.key: stored[s.key]!,
      };
}

/// A transcript of [path]: [text] spoken from [startMs], 300 ms a word
/// with 100 ms between words.
Transcript spokenTranscript(String path, String text,
    {int startMs = 0,
    String language = 'en',
    String backend = 'whisper-cpp',
    WordTiming timing = WordTiming.measured}) {
  final words = <TranscriptWord>[];
  var t = startMs;
  for (final w in text.split(' ')) {
    words.add(TranscriptWord(w, t, t + 300));
    t += 400;
  }
  return Transcript(
    sourcePath: path,
    audioTrack: 0,
    language: language,
    requestedLanguage: language,
    model: 'base',
    backend: backend,
    wordTiming: timing,
    durationMs: t,
    createdAt: DateTime.utc(2026),
    segments: segmentsFromWords(words),
  );
}
