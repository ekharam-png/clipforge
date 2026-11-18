// The folder of processed sound files (see processed_sound.dart):
// `<app media>/processed/snd_<hash>.flac`. dart:io only, no Flutter.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import 'processed_sound.dart';
import 'sound_filters.dart' show SoundStage;

/// Default size limit of the processed sound cache: about 12 hours of
/// processed sound (FLAC, ~2 MB a minute).
const int kProcessedSoundCacheBytes = 1500 * 1024 * 1024;

/// Where processed files live and which one a clip needs.
abstract class ProcessedSoundCache {
  /// The key ([processedSoundKey]) of the processed file [clip] needs, or
  /// null when it needs none ([clipNeedsProcessedSound]) or its source file
  /// cannot be read (missing: nothing to process).
  String? keyFor(Clip clip);

  /// Full path of the file for [key]. Only valid after [ready] completed.
  String pathFor(String key);

  /// Resolves the folder (creating it). Call once before [pathFor].
  Future<void> ready();

  /// True when the finished file for [key] is there.
  bool has(String key);

  /// Marks [key] as just used (least recently used files go first).
  void touch(String key);

  /// Deletes least recently used files until the folder holds at most
  /// [maxBytes], never one of [keep]. Returns the bytes freed.
  Future<int> evict({required int maxBytes, Set<String> keep = const {}});

  /// Removes the file for [key] (a render that turned out wrong).
  Future<void> remove(String key);
}

/// A cache that never has anything and wants nothing: no processed sound
/// (command-line tools, tests that do not care).
class NoProcessedSoundCache implements ProcessedSoundCache {
  const NoProcessedSoundCache();
  @override
  String? keyFor(Clip clip) => null;
  @override
  String pathFor(String key) => key;
  @override
  Future<void> ready() async {}
  @override
  bool has(String key) => false;
  @override
  void touch(String key) {}
  @override
  Future<int> evict({required int maxBytes, Set<String> keep = const {}}) async => 0;
  @override
  Future<void> remove(String key) async {}
}

/// [ProcessedSoundCache] on the file system.
class FileProcessedSoundCache implements ProcessedSoundCache {
  /// [mediaDir]: the app's media folder (resolved on [ready]).
  /// [leaveOut]: sound stages this device's FFmpeg cannot run.
  FileProcessedSoundCache(this._mediaDir,
      {this.leaveOut = const {}, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Future<String> Function() _mediaDir;
  final Set<SoundStage> leaveOut;
  final DateTime Function() _now;
  String? _dir;

  /// Source facts (size, modification time) remembered for a moment: a
  /// slider drag asks for the key of the same clips on every frame.
  final Map<String, (int, int, DateTime)?> _facts = {};
  static const Duration _factsFor = Duration(seconds: 2);

  /// The folder, once [ready].
  String? get folder => _dir;

  @override
  Future<void> ready() async {
    if (_dir != null) return;
    final dir = p.join(await _mediaDir(), kProcessedSoundFolder);
    await Directory(dir).create(recursive: true);
    _dir = dir;
  }

  @override
  String? keyFor(Clip clip) {
    if (!clipNeedsProcessedSound(clip)) return null;
    final now = _now();
    var facts = _facts[clip.path];
    if (facts == null || now.difference(facts.$3) > _factsFor) {
      facts = _stat(clip.path, now);
      _facts[clip.path] = facts;
    }
    if (facts.$1 < 0) return null;
    return processedSoundKey(clip,
        size: facts.$1, modifiedMs: facts.$2, leaveOut: leaveOut);
  }

  static (int, int, DateTime) _stat(String path, DateTime now) {
    try {
      final st = File(path).statSync();
      if (st.type == FileSystemEntityType.notFound) return (-1, 0, now);
      return (st.size, st.modified.millisecondsSinceEpoch, now);
    } catch (_) {
      return (-1, 0, now);
    }
  }

  @override
  String pathFor(String key) =>
      p.join(_dir ?? (throw StateError('cache not ready')),
          processedSoundFileName(key));

  @override
  bool has(String key) {
    final dir = _dir;
    if (dir == null) return false;
    try {
      final f = File(p.join(dir, processedSoundFileName(key)));
      return f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  void touch(String key) {
    final dir = _dir;
    if (dir == null) return;
    try {
      File(p.join(dir, processedSoundFileName(key))).setLastModifiedSync(_now());
    } catch (_) {}
  }

  @override
  Future<void> remove(String key) async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await File(p.join(dir, processedSoundFileName(key))).delete();
    } catch (_) {}
  }

  @override
  Future<int> evict({required int maxBytes, Set<String> keep = const {}}) async {
    final dir = _dir;
    if (dir == null) return 0;
    return evictProcessedSounds(dir,
        maxBytes: maxBytes,
        keep: {for (final k in keep) processedSoundFileName(k)},
        now: _now);
  }
}

/// Deletes the least recently used (oldest modification time; [touch]
/// moves it) processed files in [dir] until the files there add up to at
/// most [maxBytes]. File names in [keep] stay whatever their age.
/// Left-over partial renders (`*.part`) older than an hour go too.
/// Returns the bytes freed.
Future<int> evictProcessedSounds(String dir,
    {required int maxBytes,
    Set<String> keep = const {},
    DateTime Function()? now}) async {
  final entries = <(File, int, DateTime)>[];
  var total = 0;
  var freed = 0;
  final cutoff = (now ?? DateTime.now)().subtract(const Duration(hours: 1));
  try {
    await for (final e in Directory(dir).list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      try {
        final st = await e.stat();
        if (name.endsWith('.part')) {
          if (st.modified.isBefore(cutoff)) {
            await e.delete();
            freed += st.size;
          }
          continue;
        }
        if (!isProcessedSoundFileName(name)) continue;
        total += st.size;
        if (!keep.contains(name)) entries.add((e, st.size, st.modified));
      } on FileSystemException {
        // Gone meanwhile.
      }
    }
  } on FileSystemException {
    return freed;
  }
  entries.sort((a, b) => a.$3.compareTo(b.$3));
  for (final (file, size, _) in entries) {
    if (total <= maxBytes) break;
    try {
      await file.delete();
      total -= size;
      freed += size;
    } on FileSystemException {
      // In use (Windows) or gone: try the next.
    }
  }
  return freed;
}

/// The processed files the clips of [project] lead to, as full paths in
/// `<mediaDir>/processed/` (for the clean-up of unused media: these are
/// used). Clips whose source cannot be read lead to none.
Set<String> processedSoundPathsOf(Project project, String mediaDir) {
  final out = <String>{};
  for (final c in [...project.clips, for (final a in project.audio) a.soundClip]) {
    if (!clipNeedsProcessedSound(c)) continue;
    try {
      final st = File(c.path).statSync();
      if (st.type == FileSystemEntityType.notFound) continue;
      final key = processedSoundKey(c,
          size: st.size, modifiedMs: st.modified.millisecondsSinceEpoch);
      out.add(p.join(mediaDir, kProcessedSoundFolder, processedSoundFileName(key)));
    } catch (_) {}
  }
  return out;
}
