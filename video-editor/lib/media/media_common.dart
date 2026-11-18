// Helpers shared by the engines (dart:io only, no plugins).

import 'dart:io';

import 'package:path/path.dart' as p;

import 'ffmpeg_command.dart';
import '../core/model/project.dart';
import 'media_api.dart';
import 'silence_levels.dart';

/// Outcome of one ffmpeg run: whether it reported success, and its log.
class FfmpegRun {
  const FfmpegRun(this.ok, this.log);
  final bool ok;
  final String log;
}

/// Runs ffmpeg with [args] (no program name) to completion. Each engine
/// provides one; the logic below is shared so that both behave the same.
typedef FfmpegRunner = Future<FfmpegRun> Function(List<String> args);

/// [MediaEngine.extractFrame] on top of [run].
///
/// A time at or after the last frame makes ffmpeg write nothing; the last
/// frame is fetched instead (first from the final 0.4 s, then, for files
/// whose picture ends well before their sound, from the final 4 s).
Future<String> extractFrameWith(
    FfmpegRunner run, String path, int timeMs, String outputPath) async {
  const quiet = ['-loglevel', 'error'];
  final out = File(outputPath);
  await out.parent.create(recursive: true);
  await deleteQuietly(out);
  Future<bool> written() async => await out.exists() && await out.length() > 0;

  var r = await run([
    ...quiet,
    ...buildExtractFrameCommand(
        path: path, outputPath: outputPath, timeMs: timeMs < 0 ? 0 : timeMs),
  ]);
  if (!await written() && timeMs > 0) {
    for (final tailMs in const [400, 4000]) {
      r = await run([
        ...quiet,
        ...buildLastFrameCommand(
            path: path, outputPath: outputPath, tailMs: tailMs),
      ]);
      if (await written()) break;
    }
  }
  if (!await written()) {
    await deleteQuietly(out);
    throw ExportException('Cannot extract a frame of $path', log: r.log);
  }
  return outputPath;
}

/// [MediaEngine.detectSilence] on top of [run] and the engine's [probe].
Future<List<({int startMs, int endMs})>> detectSilenceWith(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  double? thresholdDb,
  int minSilenceMs = 700,
  int audioTrack = 0,
  AudioChannel channel = AudioChannel.both,
}) async {
  final info = await probe(path);
  if (!info.hasAudio) return const [];
  // A track the file does not have (or does not report) falls back to the
  // first, like the export does.
  final track = audioTrack > 0 && audioTrack < info.audioStreams.length
      ? audioTrack
      : 0;
  final side = track < info.audioStreams.length &&
          info.audioStreams[track] == 2
      ? channel
      : AudioChannel.both;
  if (thresholdDb == null) {
    // Automatic threshold: window levels, see silence_levels.dart.
    final r = await run([
      '-nostats', '-loglevel', 'info',
      ...buildLevelScanCommand(path: path, audioTrack: track, channel: side),
    ]);
    if (!r.ok) {
      throw ExportException('Cannot analyse the sound of $path',
          log: (LogTail()..add(r.log)).toString());
    }
    final w = parseLevelLog(r.log);
    final levels = SilenceLevels(
        fromMs: 0, spanMs: info.durationMs, starts: w.starts, levels: w.levels);
    return levels.silences(
        thresholdDb: levels.autoThresholdDb, minSilenceMs: minSilenceMs);
  }
  // silencedetect reports through the log, at level "info".
  final r = await run([
    '-nostats', '-loglevel', 'info',
    ...buildSilenceDetectCommand(
        path: path,
        thresholdDb: thresholdDb,
        minSilenceMs: minSilenceMs,
        audioTrack: track,
        channel: side),
  ]);
  if (!r.ok) {
    throw ExportException('Cannot analyse the sound of $path',
        log: (LogTail()..add(r.log)).toString());
  }
  return parseSilenceLog(r.log,
      durationMs: info.durationMs > 0 ? info.durationMs : null);
}

/// Throws an [ExportException] naming the clip and music files of [project]
/// that do not exist ("These files are missing: a.mp4, b.jpg"; the full
/// paths are in [ExportException.missingPaths]). Both engines call this
/// before they start ffmpeg, whose own message would name only the first.
Future<void> checkSourcesExist(Project project) async {
  final seen = <String>{};
  final missing = <String>[];
  for (final path in [
    for (final c in project.clips) c.path,
    for (final a in project.audio) a.path,
  ]) {
    if (!seen.add(path)) continue;
    var exists = false;
    try {
      exists = await File(path).exists();
    } catch (_) {}
    if (!exists) missing.add(path);
  }
  if (missing.isEmpty) return;
  final names = <String>[];
  for (final m in missing) {
    final name = p.basename(m);
    final shown = name.isEmpty ? m : name;
    if (!names.contains(shown)) names.add(shown);
  }
  throw ExportException(
      '${missing.length == 1 ? 'This file is' : 'These files are'} missing: '
      '${names.join(', ')}',
      missingPaths: List.unmodifiable(missing));
}

/// The exception for an ffmpeg run that failed: [what] ("ffmpeg failed
/// (exit code 1)") followed by the telling line of [log], which is kept
/// whole in [ExportException.log].
ExportException ffmpegFailure(String what, String log) {
  final why = summarizeFfmpegError(log);
  return ExportException(why == null ? what : '$what: $why', log: log);
}

/// Fonts for [project]: from [resolver] when there is one. Without one a
/// project that draws no text still exports; one with titles cannot.
Future<FontPaths> fontsFor(Project project, FontResolver? resolver) async {
  if (resolver != null) return resolver();
  if (!projectNeedsFonts(project)) {
    return const FontPaths(regular: '', bold: '');
  }
  throw ExportException(
      'This project has titles, but the media engine was created without '
      'fonts (pass `fonts:` or `fontResolver:`).');
}

/// Stable cache file name for a thumbnail of [path].
Future<String> thumbnailPathFor(String path, int timeMs, int maxHeight,
    {Directory? cacheDir}) async {
  final dir = cacheDir ??
      Directory(p.join(Directory.systemTemp.path, 'clipforge_thumbs'));
  await dir.create(recursive: true);
  var stamp = '';
  try {
    final st = await File(path).stat();
    stamp = '${st.size}_${st.modified.millisecondsSinceEpoch}';
  } catch (_) {}
  final key = _fnv1a('$path|$stamp|$timeMs|$maxHeight');
  return p.join(dir.path, 'thumb_$key.jpg');
}

String _fnv1a(String s) {
  // Two 32-bit FNV-1a passes (different seeds); enough for cache keys.
  String pass(int seed) {
    var h = seed;
    for (final c in s.codeUnits) {
      h ^= c & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= c >> 8;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return pass(0x811C9DC5) + pass(0x01234567);
}

/// Creates the temp directory + title text files of [build]'s command.
Future<Directory> createWorkDir() =>
    Directory.systemTemp.createTemp('clipforge_export_');

/// The arguments to run [cmd] with. Normally [FfmpegCommand.args]; when the
/// filter graph is too long for an argument it is written to a file in
/// [work] and referred to with the option the engine's ffmpeg understands
/// ([majorVersion] is only asked for in that case).
Future<List<String>> exportArgs(FfmpegCommand cmd, Directory work,
    Future<int?> Function() majorVersion) async {
  if (!cmd.needsGraphFile) return cmd.args;
  final file = File(p.join(work.path, 'graph.txt'));
  await file.writeAsString(cmd.filterGraph, flush: true);
  return cmd.argsWithGraphFile(file.path, graphFileOption(await majorVersion()));
}

Future<void> writeTextFiles(FfmpegCommand cmd) async {
  for (final e in cmd.textFiles.entries) {
    await File(e.key).writeAsString(e.value, flush: true);
  }
}

Future<void> deleteQuietly(FileSystemEntity e) async {
  try {
    if (await e.exists()) await e.delete(recursive: true);
  } catch (_) {}
}

/// Keeps the tail of a log.
class LogTail {
  LogTail([this.maxChars = 16000]);
  final int maxChars;
  final StringBuffer _b = StringBuffer();
  void add(String s) {
    _b.write(s);
    if (_b.length > maxChars * 2) {
      final t = _b.toString();
      _b
        ..clear()
        ..write(t.substring(t.length - maxChars));
    }
  }

  @override
  String toString() {
    final t = _b.toString();
    return t.length > maxChars ? t.substring(t.length - maxChars) : t;
  }
}
