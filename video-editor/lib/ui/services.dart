import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/model/project.dart';
import '../core/perf_log.dart';
import '../core/storage/media_check.dart' as media_check;
import '../core/storage/media_cleanup.dart' as media_cleanup;
import '../core/storage/media_import.dart';
import '../media/processed_sound_cache.dart';
import 'format.dart' show savePathFor;
import '../core/storage/project_bundle.dart' as bundle;
import '../core/storage/project_lock.dart';
import '../core/build_info.dart';
import '../core/storage/project_store.dart';
import '../media/media_api.dart';
import '../media/media_engine_factory.dart';
import '../media/media_jobs.dart';
import 'long_jobs.dart';
import 'playback/media_kit_backend.dart';
import 'playback/timeline_player.dart';

/// Everything the UI needs from the platform, behind providers so that
/// tests can replace each piece.
final projectStoreProvider =
    FutureProvider<ProjectStore>((ref) => ProjectStore.open());
final mediaEngineProvider =
    Provider<MediaEngine>((ref) => createMediaEngine());
final playerBackendProvider =
    Provider<PlayerBackend>((ref) => const MediaKitBackend());
final fileServiceProvider =
    Provider<FileService>((ref) => PlatformFileService());
final documentServiceProvider =
    Provider<DocumentService>((ref) => PlatformDocumentService());
final projectBundlesProvider =
    Provider<ProjectBundles>((ref) => const ProjectBundles());
final fileDropServiceProvider =
    Provider<FileDropService>((ref) => PlatformFileDropService());
final thumbnailsProvider = Provider<ThumbnailCache>(
    (ref) => ThumbnailCache(ref.watch(mediaEngineProvider)));

/// The processed clip sound files (`<app media>/processed/`, see
/// media/processed_sound.dart).
final processedSoundCacheProvider = Provider<ProcessedSoundCache>((ref) {
  final documents = ref.watch(documentServiceProvider);
  return FileProcessedSoundCache(documents.mediaDir);
});

/// Whether a media file is still where the project says it is.
final fileExistsProvider = Provider<bool Function(String path)>(
    (ref) => (path) => File(path).existsSync());

/// The media files of a project that are not where it says they are
/// (checked on disk, before an export).
final missingMediaProvider =
    Provider<Future<List<String>> Function(Project project)>(
        (ref) => media_check.findMissingMedia);

/// The "open in the app" lock of a project (core/storage/project_lock.dart):
/// the editor holds it while the project is open, so that Claude's tools
/// (clipforge-mcp) refuse to edit it at the same time. Null when projects
/// are not files on disk (tests).
final projectLockProvider =
    Provider<AppProjectLock? Function(ProjectStore store, String projectId)>(
        (ref) => (store, id) => store is FileProjectStore
            ? AppProjectLock(p.join(store.rootPath, id),
                app: BuildInfo.current.describe())
            : null);

/// Deletes the files in the app's own media folder that no saved project
/// uses any more and returns how many went. See [cleanAppMedia].
final mediaCleanupProvider =
    Provider<Future<int> Function(ProjectStore store)>((ref) {
  final documents = ref.watch(documentServiceProvider);
  final damaged = ref.watch(damagedProjectsProvider);
  final live = ref.watch(liveMediaProvider);
  return (store) =>
      cleanAppMedia(store, documents, damaged, keep: live.paths());
});

/// Media that open editors still use (their project and its undo / redo
/// states), which the clean-up must never delete even when no SAVED
/// project refers to it any more.
class LiveMedia {
  final Set<Iterable<String> Function()> _sources = {};

  void add(Iterable<String> Function() source) => _sources.add(source);
  void remove(Iterable<String> Function() source) => _sources.remove(source);

  Set<String> paths() => {
        for (final s in _sources) ...s(),
      };
}

final liveMediaProvider = Provider<LiveMedia>((ref) => LiveMedia());

/// Android, opening a project: files of projects made before 1.8 that
/// still sit in the app's cache folder are moved into the media folder
/// (see core/storage/media_import.dart). Returns old path -> new path.
/// Elsewhere: nothing.
final mediaRescueProvider =
    Provider<Future<Map<String, String>> Function(Project project)>((ref) {
  final documents = ref.watch(documentServiceProvider);
  return (project) async {
    if (!Platform.isAndroid) return const {};
    try {
      final cache = (await getTemporaryDirectory()).path;
      return await rescueMediaPaths(
          project, cache, await documents.mediaDir());
    } catch (_) {
      return const {};
    }
  };
});

/// Things the app does once each time it is started (tidying the media
/// folder). One per [ProviderScope], i.e. one per run.
class OncePerRun {
  bool mediaCleaned = false;

  /// The first-launch tour question was looked at.
  bool tourOffered = false;
}

final oncePerRunProvider = Provider<OncePerRun>((ref) => OncePerRun());

/// Finds the project folders of [store] that hold a project file which
/// cannot be read. [readableIds] are the projects the store did list.
final damagedProjectsProvider = Provider<
    Future<List<DamagedProject>> Function(
        ProjectStore store, Set<String> readableIds)>(
    (ref) => findDamagedProjects);

/// A project on disk that cannot be opened.
class DamagedProject {
  const DamagedProject({required this.id, this.modified});

  /// Name of its folder.
  final String id;
  final DateTime? modified;
}

/// The store's interface only lists readable projects. A store on disk
/// says where it keeps them, which is enough to find the folders that have
/// a project file the store could not read. Other stores: nothing.
Future<List<DamagedProject>> findDamagedProjects(
    ProjectStore store, Set<String> readableIds) async {
  if (store is! FileProjectStore) return const [];
  final result = <DamagedProject>[];
  try {
    final root = Directory(store.rootPath);
    if (!await root.exists()) return result;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = p.basename(entry.path);
      if (readableIds.contains(id)) continue;
      final file = File(p.join(entry.path, FileProjectStore.projectFileName));
      if (!await file.exists()) continue;
      try {
        // Listed a moment ago as unreadable; it may have been a project
        // that was only just being written.
        await store.load(id);
        continue;
      } catch (_) {}
      DateTime? modified;
      try {
        modified = await file.lastModified();
      } catch (_) {}
      result.add(DamagedProject(id: id, modified: modified));
    }
  } on FileSystemException {
    // Whatever was found so far.
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return result;
}

/// Removes what no saved project uses any more from the app's OWN media
/// folder ([DocumentService.mediaDir]: `<application support>/media`). That
/// folder only ever holds copies the app made itself: files the Android
/// picker handed over, freeze frames and media unpacked from a project
/// file. Media the user added on a computer stays in the user's folders,
/// is referenced in place and is never looked at here.
///
/// Nothing is removed while a project file cannot be read: its media would
/// look unused, and deleting it would make the damage permanent.
Future<int> cleanAppMedia(
  ProjectStore store,
  DocumentService documents,
  Future<List<DamagedProject>> Function(
          ProjectStore store, Set<String> readableIds)
      damaged, {
  Iterable<String> keep = const [],
}) async {
  // Locks left behind by a crash or a killed app (project_lock.dart).
  if (store is FileProjectStore) await removeStaleLocks(store.rootPath);
  final readable = {for (final info in await store.list()) info.id};
  if ((await damaged(store, readable)).isNotEmpty) return 0;
  final mediaDir = await documents.mediaDir();
  // Processed clip sound counts as used while a saved project's clip leads
  // to it (same source file and sound settings).
  return media_cleanup.removeUnreferencedMedia(mediaDir, store,
      alsoUses: (project) => processedSoundPathsOf(project, mediaDir),
      keep: keep);
}

class PickedFile {
  const PickedFile(this.path, this.name, {this.warning});
  final String path;
  final String name;

  /// Something the user should know about how the file was brought in
  /// (e.g. no room for ClipForge's own copy); shown with the add result.
  final String? warning;
}

/// File dialogs and export locations.
abstract class FileService {
  /// Videos and photos, several at once. Empty when cancelled.
  Future<List<PickedFile>> pickMedia();
  Future<List<PickedFile>> pickAudio();

  /// True where the user picks the export file up front (desktop).
  bool get canChooseSaveLocation;

  /// Shows a save dialog; null when cancelled.
  Future<String?> chooseSavePath(String fileName);

  /// A fresh path inside the app's own storage (phones).
  Future<String> appExportPath(String fileName);

  /// Phones only: puts the finished video at [sourcePath] into the phone's
  /// gallery. Returns a readable description of where it went, or null when
  /// the user did not allow it.
  Future<String?> saveCopy(String sourcePath, String fileName);
}

class PlatformFileService implements FileService {
  bool _prepared = false;

  Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    // The macOS app is not sandboxed (see macos/Runner/*.entitlements), so
    // the picker's sandbox entitlement check does not apply.
    if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
  }

  @override
  Future<List<PickedFile>> pickMedia() => _pick(FileType.media);

  @override
  Future<List<PickedFile>> pickAudio() => _pick(FileType.audio);

  Future<List<PickedFile>> _pick(FileType type) async {
    await _prepare();
    final files = await FilePicker.pickFiles(type: type);
    final result = <PickedFile>[];
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      result.add(await keepPickedFile(path, f.name));
    }
    return result;
  }

  /// Android: the project must never point at a file the app does not own.
  /// The picker hands out a copy in the app's cache folder (emptied by the
  /// system whenever it likes); a real path (`/storage/emulated/0/DCIM/…`)
  /// can become unreadable after a restart or be moved by the gallery. So
  /// every picked file gets ClipForge's own copy in the media folder (see
  /// core/storage/media_import.dart: the cache copy is moved, not copied;
  /// the same recording is stored once). Computers: files stay where the
  /// user keeps them.
  static Future<PickedFile> keepPickedFile(String path, String name) async {
    if (!Platform.isAndroid) return PickedFile(path, name);
    try {
      final cache = (await getTemporaryDirectory()).path;
      final mediaDir = await PlatformDocumentService().mediaDir();
      final move = isWithinDir(cache, path);
      int? free;
      if (!move) free = await LongJobSupport.instance.freeBytes(mediaDir);
      final kept = await keepMediaCopy(path, mediaDir,
          name: name, move: move, freeBytes: free);
      var warning = kept.problem;
      if (warning == null && kept.copiedBytes >= kBigCopyBytes) {
        warning = '$name: ClipForge keeps its own copy '
            '(${formatBytes(kept.copiedBytes)}), so the project keeps '
            'working if the original is moved.';
      }
      return PickedFile(kept.path, name, warning: warning);
    } catch (_) {
      return PickedFile(path, name);
    }
  }

  @override
  bool get canChooseSaveLocation => !Platform.isAndroid && !Platform.isIOS;

  @override
  Future<String?> chooseSavePath(String fileName) async {
    await _prepare();
    // file_picker's save dialog writes the bytes it is given; with none it
    // just returns the chosen path and the exporter writes the file.
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
      mimeType: 'video/mp4',
      dialogTitle: 'Export video',
    );
    if (uri == null || uri.scheme != 'file') return null;
    var path = uri.toFilePath();
    // The kind of file asked for (a video, or the sound only as .m4a /
    // .mp3) keeps its ending whatever was typed.
    final ext = p.extension(fileName).toLowerCase();
    final want = ext.isEmpty ? '.mp4' : ext;
    if (p.extension(path).toLowerCase() != want) path = '$path$want';
    return path;
  }

  @override
  Future<String> appExportPath(String fileName) async {
    Directory? base;
    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'exports'));
    await dir.create(recursive: true);
    await removeOldExports(dir.path);
    return p.join(dir.path, fileName);
  }

  /// Android: the video is copied into the shared Movies folder through the
  /// `gal` plugin, which streams the file (nothing is held in memory) and
  /// makes it show up in the gallery. Android 9 and older ask for the
  /// storage permission first. NOTE: this path only runs on a phone; it is
  /// not covered by the desktop tests. `gal` has no Linux implementation, so
  /// it must not be called there (desktop exports go straight to the path
  /// from the save dialog and never reach this method).
  @override
  Future<String?> saveCopy(String sourcePath, String fileName) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('The gallery is only available on phones');
    }
    if (!await Gal.requestAccess()) return null;
    await Gal.putVideo(sourcePath);
    // The app's own copy stays for now, so that Share (1.14) can hand it
    // to another app; [appExportPath] removes exports older than two days.
    return 'your gallery (Movies)';
  }
}

/// Phones keep a finished export in the app's own "exports" folder after
/// copying it to the gallery (so that it can still be shared). This
/// removes what is older than [olderThan] there, kit folders included;
/// called before each new export. Returns how many files went.
Future<int> removeOldExports(String dir,
    {Duration olderThan = const Duration(days: 2), DateTime? now}) async {
  final limit = (now ?? DateTime.now()).subtract(olderThan);
  var removed = 0;
  try {
    await for (final e in Directory(dir).list(recursive: true)) {
      if (e is! File) continue;
      try {
        if ((await e.lastModified()).isBefore(limit)) {
          await e.delete();
          removed++;
        }
      } catch (_) {}
    }
    await for (final e in Directory(dir).list()) {
      if (e is Directory && await e.list().isEmpty) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } on FileSystemException {
    // Nothing to tidy.
  }
  return removed;
}

/// Files that are not media: subtitles and project bundles.
abstract class DocumentService {
  /// Lets the user pick one file with one of [extensions] (without the
  /// dot). Null when cancelled.
  Future<PickedFile?> pickFile(List<String> extensions);

  Future<String> readText(String path);

  /// Saves a small text file where the user chooses. Returns a readable
  /// description of where it went, or null when cancelled.
  Future<String?> saveText(String fileName, String content);

  /// True on phones, where a file for another device is handed to the
  /// system's share sheet ([shareFile]) instead of saved to a folder
  /// ([saveFile]).
  bool get sharesFiles;

  /// Desktop: saves a file that [write] produces. The user picks the place
  /// first and [write] writes straight to it. Returns the path, or null
  /// when cancelled before anything was written.
  Future<String?> saveFile(
      String fileName, Future<void> Function(String path) write);

  /// Phones: lets [write] fill a file and opens the share sheet with it
  /// (send it to a computer, a cloud drive, a file manager...). Whatever
  /// its size, the file never has to fit in memory. Returns false when the
  /// user closed the sheet without choosing anything.
  Future<bool> shareFile(
      String fileName, Future<void> Function(String path) write);

  /// Permanent app folder for media that the app itself brings in (freeze
  /// frames, media unpacked from a project file).
  Future<String> mediaDir();
}

class PlatformDocumentService implements DocumentService {
  bool get _desktop => !Platform.isAndroid && !Platform.isIOS;

  Future<void> _prepare() async {
    if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
  }

  @override
  Future<PickedFile?> pickFile(List<String> extensions) async {
    await _prepare();
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: extensions);
    final path = file?.path;
    return file == null || path == null ? null : PickedFile(path, file.name);
  }

  @override
  Future<String> readText(String path) async {
    final bytes = await File(path).readAsBytes();
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text;
  }

  @override
  Future<String?> saveText(String fileName, String content) async {
    await _prepare();
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'text/plain',
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : fileName;
  }

  @override
  Future<String?> saveFile(
      String fileName, Future<void> Function(String path) write) async {
    await _prepare();
    if (_desktop) {
      final uri = await FilePicker.saveFile(
          fileName: fileName, bytes: Uint8List(0));
      if (uri == null || uri.scheme != 'file') return null;
      final chosen = uri.toFilePath();
      // The offered ending, whole (".clipforge.zip", not only ".zip").
      final path = savePathFor(chosen, fileName);
      await write(path);
      if (path != chosen) {
        // The save window left an empty file under the name it made.
        try {
          final placeholder = File(chosen);
          if (await placeholder.exists() && await placeholder.length() == 0) {
            await placeholder.delete();
          }
        } catch (_) {}
      }
      return path;
    }
    return await shareFile(fileName, write) ? fileName : null;
  }

  @override
  bool get sharesFiles => !_desktop;

  /// NOTE: phone-only path, not run by the desktop tests.
  ///
  /// The file is written to the app's cache and given to the `share_plus`
  /// plugin, which copies it to its own cache folder (emptied at the next
  /// share) and grants the receiving app access through a FileProvider. Our
  /// copy is deleted as soon as the plugin has taken its own, so a project
  /// file does not stay behind in a folder nobody can reach.
  @override
  Future<bool> shareFile(
      String fileName, Future<void> Function(String path) write) async {
    final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'project files'));
    if (await dir.exists()) {
      // Left over from a share that was interrupted.
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    try {
      await write(file.path);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: fileName,
      ));
      return result.status != ShareResultStatus.dismissed;
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  @override
  Future<String> mediaDir() async {
    final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'media'));
    await dir.create(recursive: true);
    return dir.path;
  }
}

/// Packing a project and its media into one file and back (see
/// core/storage/project_bundle.dart). Behind a provider so tests can fake it.
class ProjectBundles {
  const ProjectBundles();

  /// Returns the media files that are not in the bundle because they could
  /// not be found (empty when everything is in).
  Future<List<String>> exportBundle(Project project, String zipPath,
      {void Function(double fraction)? onProgress}) async {
    // The project's transcripts travel with it (1.12).
    String? transcripts;
    try {
      transcripts = p.join((await getApplicationDocumentsDirectory()).path, 'ClipForge',
          'projects', project.id, bundle.kBundleTranscriptsDir);
    } catch (_) {}
    return bundle.exportBundleReport(project, zipPath,
        onProgress: onProgress, transcriptsDir: transcripts);
  }

  Future<Project> importBundle(String zipPath,
          {required ProjectStore store, required String mediaDir}) =>
      bundle.importBundle(zipPath,
          store: store, mediaDir: mediaDir, newId: const Uuid().v4);
}

/// Asks the [MediaEngine] for timeline thumbnails, a couple at a time, and
/// remembers the answers. A failed thumbnail resolves to null.
/// Thumbnails of media files for the timeline and the project list,
/// made by the [MediaEngine] at most [maxParallel] at a time, newest
/// request first (what is on screen now was asked for last, so it comes
/// before what has been scrolled away).
///
/// Engines that can ([ThumbnailStripEngine]) make a whole video's strip in
/// one run ([strip]); the timeline then takes every frame from it.
class ThumbnailCache {
  ThumbnailCache(this.engine, {this.maxParallel = 2});

  final MediaEngine engine;
  final int maxParallel;
  final Map<String, Future<String?>> _cache = {};
  final Map<String, String?> _done = {};
  final Map<String, Future<ThumbnailStrip?>> _strips = {};
  final Map<String, ThumbnailStrip?> _stripsDone = {};
  final List<Completer<void>> _waiting = [];
  int _running = 0;

  Future<String?> get(String path, {int timeMs = 0}) {
    final key = '$timeMs|$path';
    return _cache[key] ??= _limited(
        () => PerfLog.instance.track('thumbnail',
            () => engine.thumbnail(path, timeMs: timeMs, maxHeight: 120)),
        (v) => _done[key] = v);
  }

  /// The thumbnail [get] has already made, without waiting (null when it
  /// is not ready, or could not be made).
  String? getNow(String path, {int timeMs = 0}) => _done['$timeMs|$path'];

  /// True when the engine makes thumbnail strips ([strip]).
  bool get hasStrips => engine is ThumbnailStripEngine;

  /// The thumbnail strip of the video [path] ([durationMs]: its length,
  /// when known). Null when it cannot be made, or the engine makes none.
  Future<ThumbnailStrip?> strip(String path, {int durationMs = 0}) {
    final e = engine;
    if (e is! ThumbnailStripEngine) return Future.value(null);
    return _strips[path] ??= _limited(
        () => PerfLog.instance.track(
            'thumbnail strip (${durationMs ~/ 1000} s)',
            () => (e as ThumbnailStripEngine)
                .thumbnailStrip(path, durationMs: durationMs)),
        (v) => _stripsDone[path] = v);
  }

  /// The strip [strip] has already made, without waiting.
  ThumbnailStrip? stripNow(String path) => _stripsDone[path];

  Future<T?> _limited<T>(
      Future<T> Function() make, void Function(T? value) done) async {
    if (_running >= maxParallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    T? value;
    try {
      value = await make();
    } catch (_) {
      value = null;
    } finally {
      _running--;
      // Newest first: the timeline asks for what is on screen last.
      if (_waiting.isNotEmpty) _waiting.removeLast().complete();
    }
    done(value);
    return value;
  }
}


/// A file that was dragged onto the window from the desktop.
class DroppedFile {
  const DroppedFile(this.path, {this.folder});
  final String path;

  /// Name of the dropped folder this file was in (one level is opened);
  /// null for a file dropped by itself.
  final String? folder;

  String get name => p.basename(path);
}

/// Files dropped onto the window.
class FileDrop {
  const FileDrop({
    required this.files,
    required this.globalPosition,
    this.folders = const [],
  });

  /// In the order the system handed them over (macOS: the order of the
  /// dragged selection; Windows: the order Explorer lists them; Linux: the
  /// order of the uri-list). A dropped folder's files take its place,
  /// sorted by name, as a folder has no order of its own.
  final List<DroppedFile> files;

  /// Names of the folders that were dropped (and opened).
  final List<String> folders;

  /// Where the drop happened (global coordinates).
  final Offset globalPosition;
}

/// Drag and drop of files from Finder / Explorer / a file manager onto the
/// window. Desktop only: on phones [supported] is false and [target] adds
/// nothing. Behind a provider so that widget tests can drop files.
abstract class FileDropService {
  bool get supported;

  /// Wraps [child] so that files dragged over it are reported to [onHover]
  /// (the pointer, global coordinates; null once the drag left or ended)
  /// and dropped ones to [onDrop]. Nothing is reported while [enabled] is
  /// false (e.g. while another screen or a dialog covers this one).
  Widget target({
    required bool enabled,
    required ValueChanged<Offset?> onHover,
    required ValueChanged<FileDrop> onDrop,
    required Widget child,
  });
}

/// [FileDropService] on top of the desktop_drop plugin.
class PlatformFileDropService implements FileDropService {
  @override
  bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget target({
    required bool enabled,
    required ValueChanged<Offset?> onHover,
    required ValueChanged<FileDrop> onDrop,
    required Widget child,
  }) {
    if (!supported) return child;
    return DropTarget(
      enable: enabled,
      onDragEntered: (d) => onHover(d.globalPosition),
      onDragUpdated: (d) => onHover(d.globalPosition),
      onDragExited: (_) => onHover(null),
      onDragDone: (d) async {
        onHover(null);
        onDrop(await resolveDrop(d.files, d.globalPosition));
      },
      child: child,
    );
  }

  /// Turns what the plugin delivers into [FileDrop]: folders are opened
  /// one level deep (their files sorted by name, hidden files left out),
  /// and files a macOS app handed over as a "file promise" (Photos, Mail,
  /// browsers; they land in a temporary folder) are copied into the app's
  /// media folder so the project keeps working.
  static Future<FileDrop> resolveDrop(
      List<DropItem> items, Offset globalPosition) async {
    final files = <DroppedFile>[];
    final folders = <String>[];
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;
      var isFolder = item is DropItemDirectory;
      if (!isFolder) {
        try {
          isFolder = FileSystemEntity.isDirectorySync(path);
        } catch (_) {}
      }
      if (isFolder) {
        final name = p.basename(path);
        folders.add(name);
        final inside = <String>[];
        try {
          await for (final e in Directory(path).list(followLinks: true)) {
            if (e is File && !p.basename(e.path).startsWith('.')) {
              inside.add(e.path);
            }
          }
        } on FileSystemException {
          // Unreadable folder: nothing from it.
        }
        inside.sort((a, b) => p
            .basename(a)
            .toLowerCase()
            .compareTo(p.basename(b).toLowerCase()));
        files.addAll([for (final f in inside) DroppedFile(f, folder: name)]);
        continue;
      }
      files.add(DroppedFile(item.fromPromise ? await _keepPromise(path) : path));
    }
    return FileDrop(
        files: files, folders: folders, globalPosition: globalPosition);
  }

  static Future<String> _keepPromise(String path) async {
    try {
      final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, 'media'));
      await dir.create(recursive: true);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final target = p.join(dir.path, '${stamp}_${p.basename(path)}');
      await File(path).copy(target);
      return target;
    } catch (_) {
      return path;
    }
  }
}
