// Speech-to-text as the app's widgets see it. COMPUTERS ONLY: on phones
// the provider gives null and nothing about speech is built at all (no
// menu, no button, nothing greyed out).
//
// The work itself is the pure-Dart TranscriptionService (shared with
// Claude's tools); this is the thin layer that keeps transcripts in the
// project folder and that tests replace with a fake.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/build_info.dart';
import '../../core/storage/documents_dir_io.dart'
    if (dart.library.ui) '../../core/storage/documents_dir_flutter.dart';
import '../../core/transcript/transcript_store.dart';
import '../../core/transcript/transcript_timeline.dart';
import '../../media/transcribe/transcription_service.dart';

export '../../core/transcript/transcript_timeline.dart';
export '../../media/transcribe/transcription_service.dart';

/// Something long that reports progress and can be stopped.
class SpeechTask<T> {
  SpeechTask(this.progress, this.done, this._cancel);
  final Stream<SpeechProgress> progress;
  final Future<T> done;
  final Future<void> Function() _cancel;
  Future<void> cancel() => _cancel();
}

/// One size of pack for a language, as the list shows it.
typedef PackRow = ({
  SpeechQuality size,
  SpeechModel model,
  InstalledModel? installed
});

abstract class SpeechService {
  /// What transcribing [language] with [quality] would use, and what is
  /// missing. Never downloads.
  Future<SpeechPlan> plan({String language, SpeechQuality quality});

  /// The three sizes for [language].
  List<PackRow> packs(String language);

  /// Bytes the downloaded packs use.
  int get packsBytes;

  /// Fetches a pack. Only ever called from the user's click.
  SpeechTask<void> downloadPack(SpeechModel model);

  /// Frees a pack's space.
  Future<void> removePack(SpeechModel model);

  /// "A model file I already have" (null: forget it).
  Future<void> useModelFile(String? path);

  /// The file set with [useModelFile], when it is still there.
  String? get modelFile;

  /// Transcribes [source] for project [projectId] and saves the result in
  /// the project folder. Never downloads.
  SpeechTask<Transcript> transcribe(String projectId, SpeechSource source,
      {String language, SpeechQuality quality});

  /// The stored transcripts of [sources], by [SpeechSource.key].
  Future<Map<String, Transcript>> transcriptsOf(
      String projectId, List<SpeechSource> sources);
}

/// True on the systems that have speech-to-text.
bool speechSupportedOn(String operatingSystem) =>
    operatingSystem == 'windows' ||
    operatingSystem == 'macos' ||
    operatingSystem == 'linux';

/// Null on phones: the UI then shows nothing about speech.
final speechServiceProvider = Provider<SpeechService?>((ref) =>
    speechSupportedOn(Platform.operatingSystem) ? DesktopSpeechService() : null);

class DesktopSpeechService implements SpeechService {
  /// [rootDir]: the ClipForge folder (default `<Documents>/ClipForge`);
  /// [projectsDir]: where the projects are (default `<rootDir>/projects`).
  DesktopSpeechService({String? rootDir, String? projectsDir})
      : _rootGiven = rootDir,
        _projectsGiven = projectsDir;
  final String? _rootGiven;
  final String? _projectsGiven;
  TranscriptionService? _service;
  String? _root;

  Future<TranscriptionService> _ready() async {
    final have = _service;
    if (have != null) return have;
    final root = _root =
        _rootGiven ?? p.join(await documentsDirectoryPath(), 'ClipForge');
    return _service = TranscriptionService(
        rootDir: root, appVersion: BuildInfo.current.version);
  }

  TranscriptStore _store(String projectId) =>
      TranscriptStore.ofProject(
          p.join(_projectsGiven ?? p.join(_root!, 'projects'), projectId));

  @override
  Future<SpeechPlan> plan(
          {String language = 'auto',
          SpeechQuality quality = SpeechQuality.auto}) async =>
      (await _ready()).plan(language: language, quality: quality);

  @override
  List<PackRow> packs(String language) =>
      _service?.models.packsFor(language) ?? const [];

  @override
  int get packsBytes => _service?.models.usedBytes ?? 0;

  @override
  String? get modelFile => _service?.models.userModel?.path;

  @override
  Future<void> useModelFile(String? path) async {
    final s = await _ready();
    final now = s.models.settings;
    s.models.saveSettings(SpeechSettings(
        modelPath: path, programPath: now.programPath, ffmpegPath: now.ffmpegPath));
  }

  @override
  SpeechTask<void> downloadPack(SpeechModel model) {
    final progress = StreamController<SpeechProgress>.broadcast();
    final done = Completer<void>();
    done.future.ignore();
    ModelDownload? download;
    var cancelled = false;
    () async {
      try {
        final s = await _ready();
        final d = download = s.download(model);
        if (cancelled) unawaited(d.cancel());
        final sub = d.progress.listen((pr) => progress.add(SpeechProgress(
            SpeechPhase.downloading,
            pr.fraction,
            pr.checking
                ? 'Checking the download…'
                : '${bytesLabel(pr.receivedBytes)} of ${bytesLabel(pr.totalBytes)}')));
        try {
          await d.done;
        } finally {
          unawaited(sub.cancel());
        }
        done.complete();
      } catch (e) {
        done.completeError(e);
      } finally {
        unawaited(progress.close());
      }
    }();
    return SpeechTask(progress.stream, done.future, () async {
      cancelled = true;
      await download?.cancel();
    });
  }

  @override
  Future<void> removePack(SpeechModel model) async {
    (await _ready()).models.remove(model);
  }

  @override
  SpeechTask<Transcript> transcribe(String projectId, SpeechSource source,
      {String language = 'auto', SpeechQuality quality = SpeechQuality.auto}) {
    final progress = StreamController<SpeechProgress>.broadcast();
    final done = Completer<Transcript>();
    done.future.ignore();
    TranscribeJob? job;
    var cancelled = false;
    () async {
      try {
        final s = await _ready();
        final j = job = s.transcribe(source.path,
            audioTrack: source.audioTrack,
            durationMs: source.sourceDurationMs,
            language: language,
            quality: quality);
        if (cancelled) unawaited(j.cancel());
        final sub = j.progress.listen(progress.add);
        final Transcript t;
        try {
          t = await j.done;
        } finally {
          unawaited(sub.cancel());
        }
        done.complete(await _store(projectId).save(t));
      } catch (e) {
        done.completeError(e);
      } finally {
        unawaited(progress.close());
      }
    }();
    return SpeechTask(progress.stream, done.future, () async {
      cancelled = true;
      await job?.cancel();
    });
  }

  @override
  Future<Map<String, Transcript>> transcriptsOf(
      String projectId, List<SpeechSource> sources) async {
    await _ready();
    final store = _store(projectId);
    final out = <String, Transcript>{};
    for (final s in sources) {
      final t = await store.load(s.path, s.audioTrack);
      if (t != null) out[s.key] = t;
    }
    return out;
  }
}
