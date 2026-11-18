// Speech-to-text for one sound file: finds what this computer can use,
// decides (never downloads on its own), and runs it as a job with
// progress and cancel. Pure Dart; shared by the desktop app and by
// Claude's tools (`clipforge-mcp`). Computers only - the app does not
// create this on phones.
//
// Choice of backend ("auto"): one that can start with NO download wins
// (a program with its model, or a program plus a pack that is already
// here); among equals, programs that time every word (whisper.cpp,
// faster-whisper, OpenAI whisper) come before the FFmpeg filter, whose
// word times are estimated.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/transcript/transcript.dart';
import 'backends.dart';
import 'model_download.dart';
import 'speech_models.dart';
import 'transcription.dart';

export '../../core/transcript/transcript.dart';
export 'backends.dart';
export 'model_download.dart';
export 'speech_models.dart';
export 'transcription.dart';

/// What is needed when no speech program is on the computer, in plain
/// words (the app and Claude's tools both show it).
String noBackendExplanation(String os) {
  final ffmpeg = switch (os) {
    'windows' => 'On Windows the simplest is FFmpeg: open PowerShell and '
        'run  winget install ffmpeg  (version 8 or newer; the usual build '
        'includes speech recognition), then restart ClipForge.',
    'macos' => 'On a Mac the simplest is Terminal:  brew install '
        'whisper-cpp  (or an FFmpeg 8 build that includes the whisper '
        'filter), then restart ClipForge.',
    _ => 'Install whisper.cpp (whisper-cli), faster-whisper '
        '(pip install whisper-ctranslate2) or an FFmpeg 8 built with the '
        'whisper filter, then restart ClipForge.',
  };
  return 'Turning speech into text needs a speech program on this '
      'computer, and none was found. ClipForge can use: FFmpeg 8 or newer '
      'with its "whisper" filter, whisper.cpp (whisper-cli), faster-whisper '
      '(whisper-ctranslate2) or OpenAI whisper. $ffmpeg ClipForge then '
      'finds it by itself; a small language pack is downloaded only when '
      'you ask for it.';
}

/// What a request would use.
class SpeechPlan {
  const SpeechPlan({
    this.backend,
    this.model,
    this.download,
    this.modelName = '',
    this.programFetchesModel = false,
    this.problem,
    this.needsChoice = false,
    this.language = 'auto',
  });

  /// The backend that would run; null with [problem].
  final BackendInfo? backend;

  /// The pack (ggml file) it would use, when it is on the computer.
  final InstalledModel? model;

  /// The pack that must be fetched first (only with the user's consent).
  final SpeechModel? download;

  /// The model's name ("base.en"): what a program with its own models is
  /// told, and what the transcript records.
  final String modelName;

  /// A Python whisper program would fetch this model itself (it was not
  /// found in its cache).
  final bool programFetchesModel;

  /// Why nothing can run, in plain words.
  final String? problem;

  /// No pack for this language is on the computer and no size was chosen.
  final bool needsChoice;
  final String language;

  /// It can start now without downloading anything.
  bool get ready =>
      backend != null &&
      problem == null &&
      download == null &&
      !needsChoice &&
      !programFetchesModel;

  bool get needsDownload =>
      backend != null && problem == null && !ready;
}

enum SpeechPhase { preparing, downloading, readingSound, transcribing }

class SpeechProgress {
  const SpeechProgress(this.phase, this.fraction, this.message);
  final SpeechPhase phase;

  /// 0..1 inside the phase.
  final double fraction;

  /// "Downloading the English pack: 52 of 140 MB".
  final String message;
}

/// One file being transcribed.
class TranscribeJob {
  TranscribeJob._();
  final _progress = StreamController<SpeechProgress>.broadcast();
  final _done = Completer<Transcript>();
  bool _cancelled = false;
  Future<void> Function()? _stop;

  Stream<SpeechProgress> get progress => _progress.stream;

  /// The transcript, or a [SpeechException].
  Future<Transcript> get done => _done.future;

  Future<void> cancel() async {
    _cancelled = true;
    await _stop?.call();
    try {
      await _done.future;
    } catch (_) {}
  }
}

/// Writes the sound of [input]'s stream [audioTrack] as 16 kHz mono WAV to
/// [output]; [onProgress] 0..1; stops when [cancelled] completes.
typedef WavExtractor = Future<void> Function(String input, String output,
    {required int audioTrack,
    required int durationMs,
    required void Function(double fraction) onProgress,
    required Future<void> cancelled});

class TranscriptionService {
  /// [rootDir]: the ClipForge folder (`<Documents>/ClipForge`); packs and
  /// settings live in `<rootDir>/models`.
  TranscriptionService({
    required String rootDir,
    ProcessHost? host,
    this.extractWav,
    this.httpClient,
    this.appVersion = '',
    List<TranscriptionBackend>? backends,
  })  : host = host ?? const IoProcessHost(),
        models = ModelStore(p.join(rootDir, 'models')),
        _given = backends;

  final ProcessHost host;
  final ModelStore models;
  final WavExtractor? extractWav;
  final HttpClient Function()? httpClient;
  final String appVersion;
  final List<TranscriptionBackend>? _given;

  List<TranscriptionBackend>? _backends;
  List<({TranscriptionBackend backend, BackendInfo info})>? _found;
  String _foundFor = '';

  /// The backends, best word times first. A built-in backend would be
  /// added in front (see transcription.dart).
  List<TranscriptionBackend> get backends {
    final s = models.settings;
    final key = '${s.programPath}|${s.ffmpegPath}';
    if (_backends == null || key != _foundFor) {
      _foundFor = key;
      _found = null;
      _backends = _given ??
          [
            WhisperCliBackend(host, programPath: s.programPath),
            FfmpegWhisperBackend(host, ffmpegPath: s.ffmpegPath),
          ];
    }
    return _backends!;
  }

  /// Looks for the speech programs (once; [refresh] looks again).
  Future<List<BackendInfo>> available({bool refresh = false}) async =>
      [for (final f in await _detect(refresh: refresh)) f.info];

  Future<List<({TranscriptionBackend backend, BackendInfo info})>> _detect(
      {bool refresh = false}) async {
    final list = backends;
    if (_found != null && !refresh) return _found!;
    final out = <({TranscriptionBackend backend, BackendInfo info})>[];
    for (final b in list) {
      try {
        final info = await b.detect();
        if (info != null) out.add((backend: b, info: info));
      } catch (_) {
        // A program that cannot be asked is not there.
      }
    }
    return _found = out;
  }

  static const List<String> _preference = [
    'whisper-cpp',
    'faster-whisper',
    'openai-whisper',
    FfmpegWhisperBackend.kId,
  ];

  /// What transcribing in [language] ("auto" or a code) at [quality] with
  /// [backendId] ("auto" or an id) would use, and what is missing.
  Future<SpeechPlan> plan(
      {String language = 'auto',
      SpeechQuality quality = SpeechQuality.auto,
      String backendId = 'auto'}) async {
    final found = await _detect();
    if (found.isEmpty) {
      return SpeechPlan(problem: noBackendExplanation(host.os), language: language);
    }
    final wanted = [
      for (final f in found)
        if (backendId == 'auto' || backendId.isEmpty || f.info.id == backendId) f,
    ];
    if (wanted.isEmpty) {
      return SpeechPlan(
          language: language,
          problem: 'The speech program "$backendId" was not found on this '
              'computer. Found: ${found.map((f) => f.info.id).join(', ')}.');
    }
    final lang = language == 'auto' ? '' : language;
    final plans = <SpeechPlan>[];
    for (final f in wanted) {
      if (f.info.usesPacks) {
        final c = models.choose(language, quality);
        plans.add(SpeechPlan(
          backend: f.info,
          model: c.installed,
          download: c.download,
          modelName: c.installed?.model.id ?? c.download?.id ?? '',
          needsChoice: !c.ready && c.download == null,
          language: language,
        ));
      } else {
        final kind = f.backend is WhisperCliBackend
            ? (f.backend as WhisperCliBackend).kind
            : null;
        final ids = modelIdsFor(lang, quality);
        String? cached;
        if (kind != null) {
          for (final id in ids) {
            if (WhisperCliBackend.ownModelCached(host, kind, id)) {
              cached = id;
              break;
            }
          }
        }
        plans.add(SpeechPlan(
          backend: f.info,
          modelName: cached ?? (quality == SpeechQuality.auto ? '' : ids.first),
          programFetchesModel: cached == null && quality != SpeechQuality.auto,
          needsChoice: cached == null && quality == SpeechQuality.auto,
          language: language,
        ));
      }
    }
    int rank(SpeechPlan s) {
      final i = _preference.indexOf(s.backend!.id);
      return (s.ready ? 0 : 100) + (i < 0 ? 50 : i);
    }

    plans.sort((a, b) => rank(a).compareTo(rank(b)));
    return plans.first;
  }

  /// The sizes on offer for [language], as a sentence: "Small (about
  /// 140 MB): quick, more mistakes; Medium ...".
  String packOffer(String language) => [
        for (final pk in models.packsFor(language))
          '${pk.size.label} (${pk.model.sizeLabel}'
              '${pk.installed != null ? ', already on this computer' : ''}'
              '${pk.model.englishOnly ? '' : ', all languages'}): ${pk.size.note}',
      ].join('; ');

  /// Starts fetching [model] (only ever called after the user said so).
  ModelDownload download(SpeechModel model) =>
      downloadModel(model, models, client: httpClient);

  Future<void> _defaultWav(String input, String output,
      {required int audioTrack,
      required int durationMs,
      required void Function(double fraction) onProgress,
      required Future<void> cancelled}) async {
    final ffmpeg = FfmpegWhisperBackend(host, ffmpegPath: models.settings.ffmpegPath)
        .locateFfmpeg();
    if (ffmpeg == null) {
      throw SpeechException(
          'Reading the sound needs FFmpeg, which was not found on this '
          'computer.',
          kind: 'no-ffmpeg');
    }
    final proc = await host.start(ffmpeg, [
      '-hide_banner', '-nostdin', '-nostats', '-loglevel', 'error',
      '-progress', 'pipe:1', '-y',
      '-i', input,
      '-vn', '-sn', '-dn', '-map', '0:a:$audioTrack',
      '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le',
      output,
    ]);
    var stopped = false;
    unawaited(cancelled.then((_) {
      stopped = true;
      proc.kill();
    }));
    final errors = <String>[];
    final out = proc.stdoutLines.listen((line) {
      if (durationMs > 0 && line.startsWith('out_time_us=')) {
        final us = int.tryParse(line.substring(12));
        if (us != null && us >= 0) onProgress((us / 1000 / durationMs).clamp(0.0, 1.0));
      }
    }).asFuture<void>();
    final err = proc.stderrLines.listen(errors.add).asFuture<void>();
    final code = await proc.exitCode;
    await Future.wait([out, err]).catchError((Object _) => <void>[]);
    if (stopped) throw SpeechException('Stopped.', cancelled: true);
    if (code != 0) {
      throw SpeechException(
          'The sound of ${p.basename(input)} could not be read'
          '${errors.isEmpty ? '.' : ': ${errors.last.trim()}'}',
          log: errors.join('\n'),
          kind: 'failed');
    }
  }

  /// Transcribes the sound of [path] (stream [audioTrack], [durationMs]
  /// long). Nothing is downloaded unless [allowDownload] is true: a
  /// missing pack fails with kind "needs-pack" and a message that names
  /// the pack and its size.
  TranscribeJob transcribe(
    String path, {
    int audioTrack = 0,
    int durationMs = 0,
    String language = 'auto',
    SpeechQuality quality = SpeechQuality.auto,
    String backendId = 'auto',
    bool allowDownload = false,
    bool keepFillers = true,
  }) {
    final job = TranscribeJob._();
    job._done.future.ignore();
    void tell(SpeechPhase phase, double f, String message) {
      if (!job._progress.isClosed) job._progress.add(SpeechProgress(phase, f, message));
    }

    () async {
      Directory? work;
      try {
        tell(SpeechPhase.preparing, 0, 'Getting ready…');
        if (!File(path).existsSync()) {
          throw SpeechException('The file is missing: ${p.basename(path)}',
              kind: 'failed');
        }
        final plan = await this.plan(
            language: language, quality: quality, backendId: backendId);
        if (plan.problem != null) {
          throw SpeechException(plan.problem!, kind: 'no-backend');
        }
        if (plan.needsChoice) {
          throw SpeechException(
              'No language pack for ${languageName(language == 'auto' ? '' : language)} '
              'speech is on this computer yet. Choose a size to download: '
              '${packOffer(language)}.',
              kind: 'needs-pack');
        }
        var modelPath = plan.model?.path;
        var modelName = plan.modelName;
        if (plan.download != null) {
          final m = plan.download!;
          if (!allowDownload) {
            throw SpeechException(
                'This needs the "${m.title}" pack (${m.sizeLabel}), which is '
                'not on this computer yet.',
                kind: 'needs-pack');
          }
          final d = download(m);
          job._stop = d.cancel;
          final sub = d.progress.listen((pr) => tell(
              SpeechPhase.downloading,
              pr.fraction,
              pr.checking
                  ? 'Checking the downloaded pack…'
                  : 'Downloading the pack "${m.title}": '
                      '${bytesLabel(pr.receivedBytes)} of ${bytesLabel(pr.totalBytes)}'));
          try {
            modelPath = await d.done;
          } finally {
            unawaited(sub.cancel());
          }
          modelName = m.id;
        }
        if (plan.programFetchesModel && !allowDownload) {
          final m = models.byId(plan.modelName);
          throw SpeechException(
              '${plan.backend!.label} keeps its own models and does not have '
              '"${plan.modelName}" yet: it would download it itself '
              '(${m?.sizeLabel ?? 'size unknown'}).',
              kind: 'needs-pack');
        }
        if (job._cancelled) throw SpeechException('Stopped.', cancelled: true);

        final found = await _detect();
        final backend =
            found.firstWhere((f) => f.info.id == plan.backend!.id).backend;
        work = await Directory.systemTemp.createTemp('clipforge_speech_');
        String? wav;
        // A Python whisper program reads media files itself; without an
        // FFmpeg to prepare the sound it gets the file as it is.
        final canPrepare = extractWav != null ||
            FfmpegWhisperBackend(host, ffmpegPath: models.settings.ffmpegPath)
                    .locateFfmpeg() !=
                null;
        final readsMedia = backend is WhisperCliBackend &&
            backend.kind != WhisperProgramKind.whisperCpp;
        if (backend.needsWav && (canPrepare || !readsMedia)) {
          final stop = Completer<void>();
          job._stop = () async {
            if (!stop.isCompleted) stop.complete();
          };
          tell(SpeechPhase.readingSound, 0, 'Reading the sound…');
          wav = p.join(work.path, 'sound.wav');
          await (extractWav ?? _defaultWav)(path, wav,
              audioTrack: audioTrack,
              durationMs: durationMs,
              onProgress: (f) =>
                  tell(SpeechPhase.readingSound, f, 'Reading the sound…'),
              cancelled: stop.future);
          if (job._cancelled) throw SpeechException('Stopped.', cancelled: true);
        }
        final runDir = Directory(p.join(work.path, 'run'))..createSync();
        tell(SpeechPhase.transcribing, 0, 'Listening to the speech…');
        final run = backend.start(BackendRequest(
          inputPath: path,
          wavPath: wav,
          audioTrack: audioTrack,
          workDir: runDir.path,
          language: language,
          durationMs: durationMs,
          modelPath: modelPath,
          modelName: modelName,
          vadModelPath: models.vadModelPath,
          keepFillers: keepFillers,
        ));
        job._stop = run.cancel;
        if (job._cancelled) unawaited(run.cancel());
        final sub = run.progress.listen((f) => tell(SpeechPhase.transcribing, f,
            'Listening to the speech… ${(f * 100).floor()}%'));
        final BackendResult result;
        try {
          result = await run.done;
        } finally {
          unawaited(sub.cancel());
        }
        final tidy = tidySegments(result.segments, regroup: result.regroup);
        var length = durationMs;
        if (length <= 0 && tidy.segments.isNotEmpty) length = tidy.segments.last.endMs;
        job._done.complete(Transcript(
          sourcePath: path,
          audioTrack: audioTrack,
          language: result.language.isNotEmpty
              ? result.language
              : (language == 'auto' ? '' : language),
          requestedLanguage: language,
          model: modelName.isNotEmpty
              ? modelName
              : (modelPath == null ? '' : p.basename(modelPath)),
          quality: quality.name,
          backend: plan.backend!.id,
          wordTiming: result.wordsMeasured && !tidy.estimated
              ? WordTiming.measured
              : WordTiming.estimated,
          durationMs: length,
          createdAt: DateTime.now(),
          appVersion: appVersion,
          device: result.device,
          segments: tidy.segments,
        ));
      } catch (e) {
        job._done.completeError(job._cancelled
            ? SpeechException('Stopped.', cancelled: true)
            : e is SpeechException
                ? e
                : SpeechException('Speech-to-text failed: $e', kind: 'failed'));
      } finally {
        try {
          if (work != null && work.existsSync()) work.deleteSync(recursive: true);
        } catch (_) {}
        unawaited(job._progress.close());
      }
    }();
    return job;
  }
}
