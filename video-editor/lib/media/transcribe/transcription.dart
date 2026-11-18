// Speech-to-text: the pieces every backend shares. Pure Dart (dart:io).
//
// A BACKEND turns one sound file into phrases (with word times when it
// can). Backends today run a program that is already on the computer:
//  * FfmpegWhisperBackend - the system FFmpeg's `whisper` filter;
//  * WhisperCliBackend    - whisper.cpp, faster-whisper / whisper-
//    ctranslate2 or OpenAI whisper.
//
// THE SEAM FOR A BUILT-IN BACKEND (decision, 1.11): the app ships no
// speech engine of its own - that would add a native library (whisper.cpp
// or sherpa-onnx through FFI) to three desktop builds, which cannot be
// built or tested in the build container and is a large step for a
// feature whose accuracy the owner has not judged yet. When it is wanted,
// it is one more class implementing [TranscriptionBackend] (ggml model in,
// [BackendResult] out), registered first in
// `TranscriptionService.backends`; the model manager, the transcript
// store, the timeline mapping, the UI and Claude's tools do not change.
//
// Everything that starts a program goes through [ProcessHost], so tests
// run the backends against fake programs and recorded-style outputs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/transcript/transcript.dart';

class SpeechException implements Exception {
  SpeechException(this.message, {this.log, this.cancelled = false, this.kind = ''});

  /// One or two plain sentences for the user.
  final String message;
  final String? log;
  final bool cancelled;

  /// "no-backend", "needs-pack", "pack-check", "failed", ...
  final String kind;
  @override
  String toString() => 'SpeechException: $message';
}

class ProcessOutput {
  const ProcessOutput(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get all => '$stdout\n$stderr';
}

/// A program that is running.
abstract class SpeechProcess {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;
  void kill();
}

/// The computer, as far as speech-to-text needs it.
abstract class ProcessHost {
  String get os;
  Map<String, String> get environment;
  bool fileExists(String path);

  /// The names in [dir]; empty when it is not there.
  List<String> listDir(String dir);

  /// Runs to the end; null when the program cannot be started (or takes
  /// longer than [timeout]).
  Future<ProcessOutput?> run(String executable, List<String> arguments,
      {Duration timeout = const Duration(seconds: 15)});

  Future<SpeechProcess> start(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment});
}

class IoProcessHost implements ProcessHost {
  const IoProcessHost();

  @override
  String get os => Platform.operatingSystem;

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  List<String> listDir(String dir) {
    try {
      return [for (final e in Directory(dir).listSync()) p.basename(e.path)];
    } catch (_) {
      return const [];
    }
  }

  static bool _shell(String exe) {
    final l = exe.toLowerCase();
    return Platform.isWindows && (l.endsWith('.cmd') || l.endsWith('.bat'));
  }

  @override
  Future<ProcessOutput?> run(String executable, List<String> arguments,
      {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      final r = await Process.run(executable, arguments,
              runInShell: _shell(executable),
              stdoutEncoding: const Utf8Codec(allowMalformed: true),
              stderrEncoding: const Utf8Codec(allowMalformed: true))
          .timeout(timeout);
      return ProcessOutput(r.exitCode, r.stdout as String, r.stderr as String);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SpeechProcess> start(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) async {
    try {
      final proc = await Process.start(executable, arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          runInShell: _shell(executable));
      proc.stdin.close().ignore();
      return _IoProcess(proc);
    } on ProcessException catch (e) {
      throw SpeechException('The program $executable could not be started: '
          '${e.message}');
    }
  }
}

class _IoProcess implements SpeechProcess {
  _IoProcess(this._proc);
  final Process _proc;

  static Stream<String> _lines(Stream<List<int>> s) => s
      .transform(const Utf8Decoder(allowMalformed: true))
      // Programs redraw progress with carriage returns.
      .map((t) => t.replaceAll('\r', '\n'))
      .transform(const LineSplitter());

  @override
  late final Stream<String> stdoutLines = _lines(_proc.stdout);
  @override
  late final Stream<String> stderrLines = _lines(_proc.stderr);
  @override
  Future<int> get exitCode => _proc.exitCode;
  @override
  void kill() => _proc.kill(ProcessSignal.sigkill);
}

/// Where programs usually are besides the PATH.
List<String> usualProgramDirs(ProcessHost h) {
  final env = h.environment;
  if (h.os == 'windows') {
    final local = env['LOCALAPPDATA'];
    final roaming = env['APPDATA'];
    final home = env['USERPROFILE'];
    final programs = env['ProgramFiles'] ?? r'C:\Program Files';
    final data = env['ProgramData'] ?? r'C:\ProgramData';
    final dirs = <String>[
      if (local != null) p.windows.join(local, 'Microsoft', 'WinGet', 'Links'),
      p.windows.join(programs, 'WinGet', 'Links'),
      p.windows.join(data, 'chocolatey', 'bin'),
      if (home != null) p.windows.join(home, 'scoop', 'shims'),
      if (home != null) p.windows.join(home, '.local', 'bin'),
      p.windows.join(programs, 'ffmpeg', 'bin'),
      r'C:\ffmpeg\bin',
    ];
    // pip puts programs in ...\PythonNNN\Scripts, often not on the PATH.
    for (final parent in [
      if (local != null) p.windows.join(local, 'Programs', 'Python'),
      if (roaming != null) p.windows.join(roaming, 'Python'),
    ]) {
      for (final name in h.listDir(parent)) {
        dirs.add(p.windows.join(parent, name, 'Scripts'));
      }
    }
    return dirs;
  }
  final home = env['HOME'];
  return [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/opt/local/bin',
    '/usr/bin',
    if (home != null) p.posix.join(home, '.local', 'bin'),
    if (home != null) p.posix.join(home, 'bin'),
  ];
}

/// The first of [names] found on the PATH or in the usual folders, as a
/// full path; null when none is there.
String? findProgram(ProcessHost h, List<String> names) {
  final windows = h.os == 'windows';
  final ctx = windows ? p.windows : p.posix;
  final pathVar = h.environment['PATH'] ?? h.environment['Path'] ?? '';
  final dirs = [
    ...pathVar.split(windows ? ';' : ':').where((d) => d.trim().isNotEmpty),
    ...usualProgramDirs(h),
  ];
  final endings = windows ? const ['.exe', '.cmd', '.bat'] : const [''];
  for (final name in names) {
    for (final dir in dirs) {
      for (final ending in endings) {
        final candidate = ctx.join(dir.trim(), '$name$ending');
        if (h.fileExists(candidate)) return candidate;
      }
    }
  }
  return null;
}

/// What a backend is, for the user and for get_status.
class BackendInfo {
  const BackendInfo({
    required this.id,
    required this.label,
    required this.program,
    required this.measuresWords,
    required this.usesPacks,
    this.detail = '',
  });

  /// "ffmpeg-whisper", "whisper-cpp", "faster-whisper", "openai-whisper".
  final String id;

  /// Plain words: "FFmpeg on this computer (whisper filter)".
  final String label;

  /// Full path of the program.
  final String program;

  /// It times every word (else word times are estimated from phrases).
  final bool measuresWords;

  /// It reads ClipForge's packs (ggml files). False: the program keeps
  /// (and fetches) its own models.
  final bool usesPacks;
  final String detail;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'program': program,
        'wordTimes': measuresWords ? 'measured' : 'estimated',
        'usesClipForgePacks': usesPacks,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

class BackendRequest {
  const BackendRequest({
    required this.inputPath,
    required this.workDir,
    required this.language,
    required this.durationMs,
    this.wavPath,
    this.audioTrack = 0,
    this.modelPath,
    this.modelName = '',
    this.vadModelPath,
    this.keepFillers = true,
  });

  /// The media file as it is.
  final String inputPath;

  /// Its sound as 16 kHz mono WAV, when one was prepared.
  final String? wavPath;
  final int audioTrack;

  /// An empty folder for the run's files.
  final String workDir;

  /// "auto" or a code ("en", "ru", "he").
  final String language;
  final int durationMs;

  /// The ggml file (backends that use packs).
  final String? modelPath;

  /// The model's name for programs with their own models ("base.en").
  final String modelName;
  final String? vadModelPath;

  /// Ask the program to keep "um" and "uh" (a hint; see [fillerPrompt]).
  final bool keepFillers;
}

class BackendResult {
  const BackendResult(this.segments,
      {this.language = '',
      this.wordsMeasured = false,
      this.regroup = false,
      this.device = ''});

  /// "graphics card" / "processor" when the program's log told; '' else.
  final String device;

  BackendResult withDevice(String device) => BackendResult(segments,
      language: language,
      wordsMeasured: wordsMeasured,
      regroup: regroup,
      device: device);
  final List<RawSegment> segments;

  /// Detected language (code), '' when the program did not say.
  final String language;
  final bool wordsMeasured;

  /// The segments are single words: group them into phrases.
  final bool regroup;
}

/// A backend at work.
class BackendRun {
  BackendRun(this.progress, this.done, this._cancel);

  /// 0..1.
  final Stream<double> progress;
  final Future<BackendResult> done;
  final Future<void> Function() _cancel;
  Future<void> cancel() => _cancel();
}

abstract class TranscriptionBackend {
  /// What this backend is on this computer; null when it is not here.
  Future<BackendInfo?> detect();

  /// It needs the sound as a WAV file ([BackendRequest.wavPath]).
  bool get needsWav;

  BackendRun start(BackendRequest request);
}

/// A sentence in the language's own filler style, given to programs that
/// take a "prompt": whisper tends to tidy "um" and "uh" away, and a prompt
/// written with them makes it keep them (a well-known trick; how well it
/// works was not measured here). Null for other languages.
String? fillerPrompt(String language) => switch (language) {
      'en' => 'Um, uh, like, you know... Umm, let me think, hmm. Okay, here\'s what I\'m, uh, thinking.',
      'ru' => 'Э-э, ну, как бы, эм... Так, вот что я, типа, думаю.',
      'he' => 'אה, אממ, כאילו... אוקיי, אז מה שאני, אה, חושב.',
      _ => null,
    };

final RegExp _stamp = RegExp(
    r'\[\s*(?:(\d+):)?(\d+):(\d+)[.,](\d+)\s*-->\s*(?:(\d+):)?(\d+):(\d+)[.,](\d+)\s*\]');

/// The END time (ms) of a "[00:01.000 --> 00:04.200]" line as whisper
/// programs print while they work; null for other lines.
int? printedSegmentEndMs(String line) {
  final m = _stamp.firstMatch(line);
  if (m == null) return null;
  final h = int.parse(m.group(5) ?? '0');
  final min = int.parse(m.group(6)!);
  final s = int.parse(m.group(7)!);
  final frac = m.group(8)!.padRight(3, '0').substring(0, 3);
  return ((h * 60 + min) * 60 + s) * 1000 + int.parse(frac);
}

/// Shared plumbing of the backends: runs [executable], turns its output
/// lines into progress with [progressOf] (ms done, or a 0..1 fraction as a
/// negative number is not used: return null for lines that say nothing),
/// keeps the tail of the log, and calls [finish] when it ended well.
BackendRun runBackendProgram(
  ProcessHost host,
  String executable,
  List<String> args, {
  required int durationMs,
  required double? Function(String line, bool isStderr) progressOf,
  required Future<BackendResult> Function(String log) finish,
  required String what,
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final progress = StreamController<double>.broadcast();
  final done = Completer<BackendResult>();
  done.future.ignore();
  SpeechProcess? proc;
  var cancelled = false;
  final log = <String>[];
  final errors = <String>[];
  void keep(String line, bool err) {
    if (line.trim().isEmpty) return;
    log.add(line);
    if (log.length > 400) log.removeAt(0);
    if (err) {
      errors.add(line);
      if (errors.length > 40) errors.removeAt(0);
    }
  }

  var last = 0.0;
  void onLine(String line, bool err) {
    final f = progressOf(line, err);
    if (f != null && f > last && !progress.isClosed) {
      last = f > 0.99 ? 0.99 : f;
      progress.add(last);
    }
    if (f == null || err) keep(line, err);
  }

  () async {
    try {
      proc = await host.start(executable, args,
          workingDirectory: workingDirectory, environment: environment);
      if (cancelled) proc!.kill();
      final out = proc!.stdoutLines.listen((l) => onLine(l, false)).asFuture<void>();
      final err = proc!.stderrLines.listen((l) => onLine(l, true)).asFuture<void>();
      final code = await proc!.exitCode;
      await Future.wait([out, err]).catchError((Object _) => <void>[]);
      if (cancelled) throw SpeechException('Stopped.', cancelled: true);
      if (code != 0) {
        final tail = errors.isNotEmpty ? errors : log;
        throw SpeechException(
            '$what stopped with an error (code $code)'
            '${tail.isEmpty ? '.' : ': ${tail.last.trim()}'}',
            log: log.join('\n'),
            kind: 'failed');
      }
      final result = await finish(log.join('\n'));
      if (!progress.isClosed) progress.add(1);
      done.complete(result);
    } catch (e) {
      done.completeError(cancelled
          ? SpeechException('Stopped.', cancelled: true)
          : e is SpeechException
              ? e
              : SpeechException('$what failed: $e',
                  log: log.join('\n'), kind: 'failed'));
    } finally {
      unawaited(progress.close());
    }
  }();
  return BackendRun(progress.stream, done.future, () async {
    cancelled = true;
    proc?.kill();
    try {
      await done.future;
    } catch (_) {}
  });
}

/// Whether a whisper program's log says it ran on the graphics card or on
/// the processor ('' when it does not say). whisper.cpp tries the card
/// and carries on with the processor by itself when it cannot use it
/// ("Unsupported GPU: ...", "no GPU found").
String deviceFromLog(String log) {
  final l = log.toLowerCase();
  if (l.contains('unsupported gpu') ||
      l.contains('no gpu found') ||
      l.contains('use gpu    = 0') ||
      l.contains('use gpu = 0') ||
      l.contains('failed to initialize') && l.contains('gpu') ||
      l.contains('falling back to cpu')) {
    return 'processor';
  }
  if (l.contains('using cuda') ||
      l.contains('using vulkan') ||
      l.contains('using metal') ||
      l.contains('using opencl') ||
      l.contains('ggml_vulkan:') ||
      l.contains('ggml_metal_init') ||
      l.contains('cuda0') ||
      l.contains("device 'cuda'") ||
      l.contains('device: cuda')) {
    return 'graphics card';
  }
  return '';
}

/// [first], and when it fails (not cancelled) [second] once: "try the
/// graphics card, fall back to the processor quietly".
BackendRun runWithFallback(BackendRun first, BackendRun Function() second) {
  final progress = StreamController<double>.broadcast();
  final done = Completer<BackendResult>();
  done.future.ignore();
  var current = first;
  var cancelled = false;
  () async {
    var sub = first.progress.listen((f) {
      if (!progress.isClosed) progress.add(f);
    });
    try {
      done.complete(await first.done);
    } catch (e) {
      unawaited(sub.cancel());
      if (cancelled || (e is SpeechException && e.cancelled)) {
        done.completeError(e);
      } else {
        current = second();
        sub = current.progress.listen((f) {
          if (!progress.isClosed) progress.add(f);
        });
        try {
          done.complete(await current.done);
        } catch (e2) {
          done.completeError(e2);
        }
      }
    } finally {
      unawaited(sub.cancel());
      unawaited(progress.close());
    }
  }();
  return BackendRun(progress.stream, done.future, () async {
    cancelled = true;
    await current.cancel();
  });
}
