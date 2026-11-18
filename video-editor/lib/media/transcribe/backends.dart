// The two backends that use a program already on the computer.
// Pure Dart; every program is started through ProcessHost.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffmpeg_command.dart' show escapeFilterPath;
import 'transcription.dart';
import 'whisper_output.dart';

double? _ffmpegProgress(String line, int durationMs) {
  if (durationMs <= 0) return null;
  if (line.startsWith('out_time_us=') || line.startsWith('out_time_ms=')) {
    final us = int.tryParse(line.substring(12));
    if (us != null && us >= 0) return us / 1000 / durationMs;
  }
  return null;
}

/// The system FFmpeg's `whisper` filter (FFmpeg 8.0 and later, built with
/// `--enable-whisper`; found with `ffmpeg -filters`).
///
/// Options used, from the FFmpeg documentation of the filter: `model`
/// (path of a ggml file), `language` ("auto" or a code), `queue` (seconds
/// of sound gathered before each recognition; 20 here - the documentation
/// recommends a large value for accuracy when nothing is waiting live),
/// `use_gpu` (true: FFmpeg falls back to the processor without a card),
/// `destination` + `format=json` (one object per phrase with start / end
/// in ms), and `vad_model` when a voice-activity model file sits next to
/// the packs.
///
/// The filter times PHRASES only, so word times are estimated
/// (WordTiming.estimated): fine for captions and reading, too rough for
/// cutting single words.
class FfmpegWhisperBackend implements TranscriptionBackend {
  FfmpegWhisperBackend(this.host, {this.ffmpegPath, this.queueSeconds = 20});
  final ProcessHost host;

  /// A particular ffmpeg; null: the one on the PATH / in the usual places.
  final String? ffmpegPath;
  final int queueSeconds;

  static const String kId = 'ffmpeg-whisper';

  String? _program;

  /// The ffmpeg this computer has (with or without the filter).
  String? locateFfmpeg() =>
      ffmpegPath != null && host.fileExists(ffmpegPath!)
          ? ffmpegPath
          : findProgram(host, const ['ffmpeg']);

  /// True when `ffmpeg -filters` lists the whisper filter.
  static bool filtersListWhisper(String filtersOutput) =>
      RegExp(r'^\s*[A-Z.|]{2,4}\s+whisper\s', multiLine: true)
          .hasMatch(filtersOutput);

  @override
  Future<BackendInfo?> detect() async {
    final exe = locateFfmpeg();
    if (exe == null) return null;
    final out = await host.run(exe, const ['-hide_banner', '-filters']);
    if (out == null || !filtersListWhisper(out.all)) return null;
    _program = exe;
    final version = await host.run(exe, const ['-hide_banner', '-version']);
    final v = RegExp(r'version\s+(\S+)').firstMatch(version?.stdout ?? '')?.group(1);
    return BackendInfo(
      id: kId,
      label: 'FFmpeg on this computer (its "whisper" filter)',
      program: exe,
      measuresWords: false,
      usesPacks: true,
      detail: v == null ? '' : 'FFmpeg $v',
    );
  }

  @override
  bool get needsWav => false;

  /// The arguments for [r] (public for tests).
  List<String> arguments(BackendRequest r, {bool useGpu = true}) {
    final options = [
      'model=${escapeFilterPath(r.modelPath ?? '')}',
      'language=${r.language.isEmpty ? 'auto' : r.language}',
      'queue=$queueSeconds',
      'use_gpu=$useGpu',
      'destination=transcript.json',
      'format=json',
      if (r.vadModelPath != null) 'vad_model=${escapeFilterPath(r.vadModelPath!)}',
    ];
    return [
      '-hide_banner', '-nostdin', '-nostats', '-loglevel', 'info',
      '-progress', 'pipe:1',
      '-i', r.inputPath,
      '-vn', '-sn', '-dn',
      '-map', '0:a:${r.audioTrack}',
      '-af', 'whisper=${options.join(':')}',
      '-f', 'null', '-',
    ];
  }

  @override
  BackendRun start(BackendRequest r) {
    final exe = _program ?? locateFfmpeg() ?? 'ffmpeg';
    BackendRun run(bool gpu) => runBackendProgram(
          host,
          exe,
          arguments(r, useGpu: gpu),
          durationMs: r.durationMs,
          workingDirectory: r.workDir,
          what: 'FFmpeg\'s speech recognition',
          progressOf: (line, err) =>
              err ? null : _ffmpegProgress(line, r.durationMs),
          finish: (log) async {
            final f = File(p.join(r.workDir, 'transcript.json'));
            final result = await f.exists()
                ? parseFfmpegWhisperJson(await f.readAsString())
                : const BackendResult([]);
            final device = deviceFromLog(log);
            return result.withDevice(
                !gpu ? 'processor' : device);
          },
        );
    // The graphics card is tried first (whisper.cpp itself carries on with
    // the processor when it cannot use the card); if that run fails
    // outright, once more on the processor.
    return runWithFallback(run(true), () => run(false));
  }
}

enum WhisperProgramKind {
  /// whisper.cpp (`whisper-cli`): ggml packs, WAV input.
  whisperCpp,

  /// faster-whisper (`whisper-ctranslate2`, `faster-whisper-xxl`).
  fasterWhisper,

  /// OpenAI's Python `whisper`.
  openAi,
}

/// A whisper program installed on the computer: whisper.cpp
/// (`whisper-cli`, older `whisper-cpp`), faster-whisper
/// (`whisper-ctranslate2`, `faster-whisper-xxl`, `faster-whisper`) or
/// OpenAI `whisper` - found by name, or the program the user pointed at
/// ([programPath]); which kind it is is read from its `--help`.
class WhisperCliBackend implements TranscriptionBackend {
  WhisperCliBackend(this.host, {this.programPath});
  final ProcessHost host;
  final String? programPath;

  /// Names tried, in this order (programs that time every word well
  /// first).
  static const List<String> kNames = [
    'whisper-ctranslate2',
    'faster-whisper-xxl',
    'faster-whisper',
    'whisper-cli',
    'whisper-cpp',
    'whisper',
  ];

  String? _program;
  WhisperProgramKind? _kind;

  WhisperProgramKind? get kind => _kind;

  /// Which kind of program printed [help] (its `--help`); null: not a
  /// whisper program we know.
  static WhisperProgramKind? kindFromHelp(String help, String programName) {
    if (help.contains('--output-json') || help.contains('-ojf') ||
        help.contains('--split-on-word')) {
      return WhisperProgramKind.whisperCpp;
    }
    if (help.contains('--word_timestamps') || help.contains('--output_format')) {
      final n = programName.toLowerCase();
      return n.contains('faster') || n.contains('ctranslate') ||
              help.contains('ctranslate2') || help.contains('--compute_type')
          ? WhisperProgramKind.fasterWhisper
          : WhisperProgramKind.openAi;
    }
    return null;
  }

  @override
  Future<BackendInfo?> detect() async {
    final candidates = <String>[
      if (programPath != null && host.fileExists(programPath!)) programPath!,
    ];
    if (candidates.isEmpty) {
      for (final name in kNames) {
        final found = findProgram(host, [name]);
        if (found != null) candidates.add(found);
      }
    }
    for (final exe in candidates) {
      final help = await host.run(exe, const ['--help'],
          timeout: const Duration(seconds: 40));
      if (help == null) continue;
      final kind = kindFromHelp(help.all, p.basename(exe));
      if (kind == null) continue;
      _program = exe;
      _kind = kind;
      return switch (kind) {
        WhisperProgramKind.whisperCpp => BackendInfo(
            id: 'whisper-cpp',
            label: 'whisper.cpp on this computer (${p.basename(exe)})',
            program: exe,
            measuresWords: true,
            usesPacks: true),
        WhisperProgramKind.fasterWhisper => BackendInfo(
            id: 'faster-whisper',
            label: 'faster-whisper on this computer (${p.basename(exe)})',
            program: exe,
            measuresWords: true,
            usesPacks: false,
            detail: 'Keeps its own models and fetches them itself.'),
        WhisperProgramKind.openAi => BackendInfo(
            id: 'openai-whisper',
            label: 'OpenAI whisper on this computer (${p.basename(exe)})',
            program: exe,
            measuresWords: true,
            usesPacks: false,
            detail: 'Keeps its own models and fetches them itself.'),
      };
    }
    return null;
  }

  @override
  bool get needsWav => true;

  /// The arguments for [r] with a program of [kind] (public for tests).
  static List<String> argumentsFor(WhisperProgramKind kind, BackendRequest r) {
    final input = r.wavPath ?? r.inputPath;
    final auto = r.language.isEmpty || r.language == 'auto';
    final prompt = r.keepFillers && !auto ? fillerPrompt(r.language) : null;
    if (kind == WhisperProgramKind.whisperCpp) {
      return [
        '-m', r.modelPath ?? '',
        '-f', input,
        '-l', auto ? 'auto' : r.language,
        // One word per entry, split at word boundaries: word times.
        '-ml', '1', '-sow',
        '-oj', '-of', p.join(r.workDir, 'out'),
        '-pp',
        if (prompt != null) ...['--prompt', prompt],
      ];
    }
    return [
      input,
      '--model', r.modelName,
      '--output_dir', r.workDir,
      '--output_format', 'json',
      '--word_timestamps', 'True',
      if (!auto) ...['--language', r.language],
      if (prompt != null) ...['--initial_prompt', prompt],
    ];
  }

  static final RegExp _percent = RegExp(r'progress\s*=\s*(\d+)\s*%');

  @override
  BackendRun start(BackendRequest r) {
    final exe = _program ?? programPath ?? 'whisper';
    final kind = _kind ?? WhisperProgramKind.openAi;
    return runBackendProgram(
      host,
      exe,
      argumentsFor(kind, r),
      durationMs: r.durationMs,
      workingDirectory: r.workDir,
      // Python on Windows otherwise fails printing Russian or Hebrew.
      environment: const {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'},
      what: 'The speech program (${p.basename(exe)})',
      progressOf: (line, err) {
        final pc = _percent.firstMatch(line);
        if (pc != null) return int.parse(pc.group(1)!) / 100;
        final end = printedSegmentEndMs(line);
        if (end != null && r.durationMs > 0) return end / r.durationMs;
        return null;
      },
      finish: (log) async {
        File? json;
        final cpp = File(p.join(r.workDir, 'out.json'));
        if (await cpp.exists()) {
          json = cpp;
        } else {
          await for (final e in Directory(r.workDir).list()) {
            if (e is File && e.path.toLowerCase().endsWith('.json')) {
              json = e;
              break;
            }
          }
        }
        if (json == null) {
          throw SpeechException(
              'The speech program finished but wrote no result.',
              kind: 'failed');
        }
        final text = await json.readAsString();
        return (kind == WhisperProgramKind.whisperCpp
                ? parseWhisperCppJson(text, wordPerEntry: true)
                : parseOpenAiJson(text))
            .withDevice(deviceFromLog(log));
      },
    );
  }

  /// Whether a Python whisper program already has its model [name] in its
  /// own cache (best effort: the standard cache folders), so that using it
  /// downloads nothing.
  static bool ownModelCached(ProcessHost h, WhisperProgramKind kind, String name) {
    final env = h.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null) return false;
    final ctx = h.os == 'windows' ? p.windows : p.posix;
    if (kind == WhisperProgramKind.openAi) {
      final dir = ctx.join(env['XDG_CACHE_HOME'] ?? ctx.join(home, '.cache'), 'whisper');
      return h.fileExists(ctx.join(dir, '$name.pt'));
    }
    if (kind == WhisperProgramKind.fasterWhisper) {
      final hub = env['HF_HUB_CACHE'] ??
          ctx.join(env['HF_HOME'] ?? ctx.join(home, '.cache', 'huggingface'), 'hub');
      return h.listDir(hub).any((d) =>
          d.startsWith('models--') && d.endsWith('faster-whisper-$name'));
    }
    return false;
  }
}
