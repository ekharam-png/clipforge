// The sound picture of a file ([SoundPeaks]) on top of an engine's ffmpeg
// runner (dart:io only): one low-rate decode per file, kept on disk so
// that it costs a few seconds once and almost nothing afterwards.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/storage/media_import.dart' show mediaFingerprint;
import 'media_api.dart';
import 'media_common.dart';
import 'sound_align.dart' show buildAlignDecodeCommand;
import 'sound_peaks.dart';

export 'sound_peaks.dart';

/// An engine that can read the sound picture of a file.
abstract interface class SoundPeaksEngine {
  /// The peaks of audio stream [audioTrack] of [path]; null when the file
  /// has no sound. With [cacheDir] the result is read from / written to
  /// that folder ([soundPeaksFileName]). Throws [ExportException] when the
  /// file cannot be read.
  Future<SoundPeaks?> soundPeaks(String path,
      {int audioTrack = 0, String? cacheDir});
}

/// Size limit of the peaks folder: about 200 files of 40 minutes.
const int kSoundPeaksCacheBytes = 48 * 1024 * 1024;

bool isSoundPeaksFileName(String name) =>
    name.startsWith('pk_') && name.endsWith('.cfpk');

/// `pk_<fingerprint>_a<track>.cfpk`: the same recording keeps its picture
/// when it is moved or picked again.
Future<String> soundPeaksFileName(String path, int audioTrack) async =>
    'pk_${await mediaFingerprint(path)}_a$audioTrack.cfpk';

/// [SoundPeaksEngine.soundPeaks] on top of [run] and the engine's [probe].
Future<SoundPeaks?> soundPeaksWith(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  int audioTrack = 0,
  String? cacheDir,
}) async {
  File? cached;
  if (cacheDir != null) {
    try {
      cached = File(p.join(cacheDir, await soundPeaksFileName(path, audioTrack)));
      final known = await SoundPeaks.readFile(cached.path);
      if (known != null) {
        // Just used: the least recently used files go first.
        try {
          await cached.setLastModified(DateTime.now());
        } catch (_) {}
        return known;
      }
    } on FileSystemException {
      cached = null;
    }
  }
  final info = await probe(path);
  if (!info.hasAudio) return null;
  final track = audioTrack > 0 && audioTrack < info.audioStreams.length
      ? audioTrack
      : 0;
  final dir = await Directory.systemTemp.createTemp('clipforge_peaks_');
  try {
    final raw = p.join(dir.path, 'sound.raw');
    final r = await run([
      '-nostats', '-loglevel', 'error',
      ...buildAlignDecodeCommand(path: path, outputPath: raw, audioTrack: track),
    ]);
    if (!r.ok || !await File(raw).exists()) {
      throw ExportException('Cannot read the sound of ${p.basename(path)}',
          log: (LogTail()..add(r.log)).toString());
    }
    final peaks = await SoundPeaks.fromRawFile(raw);
    if (cached != null) {
      try {
        await cached.parent.create(recursive: true);
        final part = File('${cached.path}.part');
        await part.writeAsBytes(peaks.toBytes(), flush: true);
        await part.rename(cached.path);
      } on FileSystemException {
        // Not kept: drawn again next time.
      }
    }
    return peaks;
  } finally {
    await deleteQuietly(dir);
  }
}

/// Deletes the least recently used peaks files in [dir] until they add up
/// to at most [maxBytes] (the rule of the processed sound cache).
/// Returns the bytes freed.
Future<int> evictSoundPeaks(String dir,
    {int maxBytes = kSoundPeaksCacheBytes}) async {
  final entries = <(File, int, DateTime)>[];
  var total = 0, freed = 0;
  try {
    await for (final e in Directory(dir).list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!isSoundPeaksFileName(name) && !name.endsWith('.cfpk.part')) continue;
      try {
        final st = await e.stat();
        total += st.size;
        entries.add((e, st.size, st.modified));
      } on FileSystemException {
        // Gone meanwhile.
      }
    }
  } on FileSystemException {
    return 0;
  }
  entries.sort((a, b) => a.$3.compareTo(b.$3));
  for (final (file, size, _) in entries) {
    if (total <= maxBytes) break;
    try {
      await file.delete();
      total -= size;
      freed += size;
    } on FileSystemException {
      // In use or gone.
    }
  }
  return freed;
}
