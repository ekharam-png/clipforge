// Keeping the app's own copy of media that comes from outside (Android
// picker, gallery search). Pure Dart, so it is tested without a phone.
//
// WHY (1.8.0, owner: "Missing · 20261116_205955.mp4"): on Android the file
// picker copies every picked file into `<cache>/file_picker/<uuid>/<name>`
// and returns that path with symbolic links resolved (`File.canonicalFile`:
// `/data/data/<app>/cache/...`), while `getTemporaryDirectory()` answers
// `/data/user/0/<app>/cache`, a symbolic link to the same folder. The old
// "is it in the cache?" check compared the two strings, never matched, and
// the project kept pointing INTO THE CACHE, which Android (and Samsung's
// "Device care") empties whenever it likes. [isWithinDir] compares real
// paths, and [keepMediaCopy] makes the app's own copy of every outside file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/project.dart';

/// Folder inside the app media folder where kept copies go:
/// `<media>/imported/<fingerprint>/<original name>`.
const String kImportedDir = 'imported';

/// Room that must stay free on the disk after a copy is made.
const int kKeepFreeReserveBytes = 300 * 1024 * 1024;

/// Above this size the user is told that a copy was made (it takes room).
const int kBigCopyBytes = 1024 * 1024 * 1024;

/// How many bytes from the start and from the end of a file go into its
/// [mediaFingerprint].
const int kFingerprintSampleBytes = 256 * 1024;

/// The result of [keepMediaCopy].
class KeptMedia {
  const KeptMedia(this.path,
      {this.reused = false, this.copiedBytes = 0, this.problem});

  /// The path the project should use.
  final String path;

  /// True when an identical copy was already there (nothing was copied).
  final bool reused;

  /// Bytes written by a copy (0 for a move, a reuse or no copy).
  final int copiedBytes;

  /// Why no copy could be made (the file is then used where it is), for
  /// the user. Null when all went well.
  final String? problem;
}

/// True when [path] is inside [dir], comparing the real locations (links
/// resolved where the files exist), so `/data/user/0/x/cache/a` is inside
/// `/data/data/x/cache`.
bool isWithinDir(String dir, String path) {
  String real(String s) {
    final abs = p.normalize(p.absolute(s));
    try {
      return Directory(abs).existsSync() || File(abs).existsSync()
          ? p.normalize(
              FileSystemEntity.isDirectorySync(abs)
                  ? Directory(abs).resolveSymbolicLinksSync()
                  : File(abs).resolveSymbolicLinksSync(),
            )
          : abs;
    } on FileSystemException {
      return abs;
    }
  }

  final d = p.normalize(p.absolute(dir));
  final f = p.normalize(p.absolute(path));
  if (p.isWithin(d, f)) return true;
  return p.isWithin(real(d), real(f));
}

/// A quick content fingerprint: size plus FNV-1a 64 over the first and last
/// [kFingerprintSampleBytes]. The same recording picked twice gets the same
/// value (also when the picker made a fresh copy with a new date), without
/// reading a 4 GB video. 16 hex digits.
Future<String> mediaFingerprint(String path) async {
  final file = File(path);
  final size = await file.length();
  var h = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  void add(List<int> bytes) {
    for (final b in bytes) {
      h ^= b;
      h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
    }
  }

  add('$size|'.codeUnits);
  final raf = await file.open();
  try {
    final head = await raf.read(kFingerprintSampleBytes);
    add(head);
    if (size > kFingerprintSampleBytes) {
      final tailStart = size - kFingerprintSampleBytes > head.length
          ? size - kFingerprintSampleBytes
          : head.length;
      await raf.setPosition(tailStart);
      add(await raf.read(size - tailStart));
    }
  } finally {
    await raf.close();
  }
  return BigInt.from(h).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Makes sure the app has its OWN copy of the media file [source] inside
/// [mediaDir] and returns the path to use.
///
///  * A file already inside [mediaDir] is used as it is.
///  * The copy goes to `<mediaDir>/imported/<fingerprint>/<name>` ([name]
///    defaults to the file's name), so the same recording added twice (or
///    to two projects) is stored once ([KeptMedia.reused]).
///  * [move]: [source] is a temporary copy nobody else needs (the picker's
///    cache copy): it is renamed (instant, no extra room) or, across disks,
///    copied and then deleted.
///  * Otherwise [source] is copied; when [freeBytes] (free room on the disk
///    of [mediaDir], null = unknown) would drop under
///    [kKeepFreeReserveBytes], nothing is copied and [source] is used where
///    it is, with a [KeptMedia.problem] for the user.
///  * Any failure leaves [source] in use (with a problem); never throws.
///
/// The copy is written to `<name>.part` and renamed when complete.
Future<KeptMedia> keepMediaCopy(
  String source,
  String mediaDir, {
  String? name,
  bool move = false,
  int? freeBytes,
}) async {
  final shown = name ?? p.basename(source);
  try {
    if (isWithinDir(mediaDir, source)) return KeptMedia(source);
    final file = File(source);
    final size = await file.length();
    final fp = await mediaFingerprint(source);
    final safe = _safeName(shown.isEmpty ? p.basename(source) : shown);
    final dir = Directory(p.join(mediaDir, kImportedDir, fp));
    final target = p.join(dir.path, safe);
    final existing = File(target);
    if (await existing.exists() && await existing.length() == size) {
      if (move) {
        try {
          await file.delete();
        } catch (_) {}
      }
      // Touched, so the unused-media clean-up's grace period protects it
      // until the project that now uses it is saved.
      try {
        await existing.setLastModified(DateTime.now());
      } catch (_) {}
      return KeptMedia(target, reused: true);
    }
    await dir.create(recursive: true);
    if (move) {
      try {
        await file.rename(target);
        try {
          await File(target).setLastModified(DateTime.now());
        } catch (_) {}
        return KeptMedia(target);
      } on FileSystemException {
        // Another disk: copied below, then deleted.
      }
    }
    if (!move &&
        freeBytes != null &&
        freeBytes - size < kKeepFreeReserveBytes) {
      return KeptMedia(source,
          problem: '$shown is used from where it is: there is not enough '
              'free space to keep a copy in ClipForge '
              '(${_gb(size)} needed). If it is moved or deleted later, '
              'the project will show it as missing.');
    }
    final part = File('$target.part');
    await file.copy(part.path);
    await part.rename(target);
    if (move) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return KeptMedia(target, copiedBytes: move ? 0 : size);
  } catch (e) {
    return KeptMedia(source,
        problem: '$shown could not be copied into ClipForge ($e); it is '
            'used from where it is.');
  }
}

String _gb(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : '${(bytes / (1024 * 1024)).round()} MB';

/// Human size for messages ("1.2 GB", "350 MB").
String formatBytes(int bytes) => _gb(bytes);

String _safeName(String name) {
  final base = p.basename(name.replaceAll(r'\', '/'));
  final cleaned = base.replaceAll(RegExp(r'[\x00-\x1f/:*?"<>|]'), '_');
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? 'media'
      : cleaned;
}

/// The media paths of [project] that live inside [dir] (resolved like
/// [isWithinDir]) and still exist: what [rescueMediaPaths] moves.
Set<String> mediaPathsWithin(Project project, String dir) => {
      for (final path in projectMediaPaths(project))
        if (path.isNotEmpty && isWithinDir(dir, path) && File(path).existsSync())
          path,
    };

/// Every media path [project] uses (clips, sounds, overlay items).
Set<String> projectMediaPaths(Project project) => {
      for (final c in project.clips) c.path,
      for (final a in project.audio) a.path,
      for (final o in project.overlays) o.path,
    };

/// Projects made before 1.8 on Android may point into the app's cache
/// folder ([cacheDir]); while those files are still there they are moved
/// into [mediaDir]. Returns old path -> new path for the ones that moved
/// (give it to `ProjectEditor.relinkMediaQuietly` or rewrite the project).
Future<Map<String, String>> rescueMediaPaths(
    Project project, String cacheDir, String mediaDir) async {
  final moved = <String, String>{};
  for (final path in mediaPathsWithin(project, cacheDir)) {
    final kept = await keepMediaCopy(path, mediaDir, move: true);
    if (kept.path != path) moved[path] = kept.path;
  }
  return moved;
}

/// [project] with every media path in [moved] replaced.
Project relinkProject(Project project, Map<String, String> moved) {
  if (moved.isEmpty) return project;
  String to(String path) => moved[path] ?? path;
  return project.copyWith(
    clips: [for (final c in project.clips) c.copyWith(path: to(c.path))],
    audio: [for (final a in project.audio) a.copyWith(path: to(a.path))],
    overlays: [
      for (final o in project.overlays)
        o.copyWith(clip: o.clip.copyWith(path: to(o.path))),
    ],
  );
}
