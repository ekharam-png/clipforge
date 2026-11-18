// The job behind MediaEngine.renderClipSound, shared by both engines: one
// ffmpeg run that writes a processed sound file (processed_sound.dart)
// under a temporary name and renames it when it is complete.
//
// dart:io only, no Flutter.

import 'dart:async';
import 'dart:io';

import '../core/model/project.dart';
import 'ffmpeg_command.dart' show summarizeFfmpegError;
import 'media_api.dart';
import 'media_common.dart' show LogTail, deleteQuietly;
import 'processed_sound.dart';
import 'sound_filters.dart' show SoundStage;

/// A started ffmpeg run, as an engine hands it to [SoundRenderJob].
abstract class FfmpegRunHandle {
  /// Completes with true when ffmpeg finished successfully.
  Future<bool> get finished;

  /// Stops the run (it then finishes unsuccessfully).
  Future<void> stop();
}

/// Starts ffmpeg with [args] (no program name, no runner flags). [onTimeMs]
/// gets the output position as it advances, [onLog] the log.
typedef FfmpegLauncher = Future<FfmpegRunHandle> Function(
  List<String> args, {
  required void Function(int outMs) onTimeMs,
  required void Function(String text) onLog,
});

/// [MediaEngine.renderClipSound]: progress, cancel, and the finished file
/// at its name only when complete.
class SoundRenderJob implements ExportJob {
  SoundRenderJob(this.clip, this.outputPath,
      {required FfmpegLauncher launch,
      Future<Set<SoundStage>> Function()? leaveOut}) {
    _done.future.ignore();
    _run(launch, leaveOut);
  }

  final Clip clip;
  final String outputPath;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  FfmpegRunHandle? _handle;
  bool _cancelled = false;
  double _last = 0;

  @override
  Stream<ExportProgress> get progress => _progress.stream;

  @override
  Future<String> get done => _done.future;

  @override
  VideoEncoder? get videoEncoder => null;

  @override
  List<String> get warnings => const [];

  void _emit(double f) {
    if (_progress.isClosed || f < _last) return;
    _last = f;
    _progress.add(ExportProgress(f));
  }

  Future<void> _run(FfmpegLauncher launch,
      Future<Set<SoundStage>> Function()? leaveOut) async {
    final part = '$outputPath.part';
    final log = LogTail();
    try {
      await Future<void>.delayed(Duration.zero);
      if (!await File(clip.path).exists()) {
        throw ExportException('The file is missing: ${clip.path}',
            missingPaths: [clip.path]);
      }
      final without = leaveOut == null ? const <SoundStage>{} : await leaveOut();
      await File(part).parent.create(recursive: true);
      if (_cancelled) throw ExportException('Cancelled', cancelled: true);
      _emit(0);
      final total = clip.sourceDurationMs;
      final handle = _handle = await launch(
        buildProcessedSoundCommand(clip, part, leaveOut: without),
        onTimeMs: (ms) {
          if (total > 0) {
            final f = ms / total;
            _emit(f >= 1 ? 0.99 : f);
          }
        },
        onLog: log.add,
      );
      if (_cancelled) await handle.stop();
      final ok = await handle.finished;
      if (_cancelled) throw ExportException('Cancelled', cancelled: true);
      if (!ok) {
        final why = summarizeFfmpegError(log.toString());
        throw ExportException(
            why == null ? 'The sound could not be processed' : 'The sound could not be processed: $why',
            log: log.toString());
      }
      final f = File(part);
      if (!await f.exists() || await f.length() == 0) {
        throw ExportException('ffmpeg produced no sound', log: log.toString());
      }
      await deleteQuietly(File(outputPath));
      await f.rename(outputPath);
      _emit(1);
      _done.complete(outputPath);
    } catch (e, st) {
      await deleteQuietly(File(part));
      if (!_done.isCompleted) {
        _done.completeError(_cancelled
            ? ExportException('Cancelled', cancelled: true)
            : e is ExportException
                ? e
                : ExportException('Processing the sound failed: $e', log: '$st'));
      }
    } finally {
      await _progress.close();
    }
  }

  @override
  Future<void> cancel() async {
    if (_done.isCompleted) return;
    _cancelled = true;
    try {
      await _handle?.stop();
    } catch (_) {}
    try {
      await _done.future;
    } catch (_) {}
  }
}
