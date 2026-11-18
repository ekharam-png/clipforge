// A pretend computer for the speech-to-text tests: programs that "exist"
// at given paths, answer `--help` / `-filters`, and when started write the
// recorded-style results in test/media/fixtures/speech/ where the real
// programs would. No real speech program runs anywhere in the tests.
import 'dart:async';
import 'dart:io';

import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:path/path.dart' as p;

String fixture(String name) =>
    File('test/media/fixtures/speech/$name').readAsStringSync();

class FakeProcess implements SpeechProcess {
  FakeProcess(
      {List<String> out = const [],
      List<String> err = const [],
      int code = 0,
      Duration? runFor,
      void Function()? onEnd}) {
    () async {
      Future<void> wait(Duration d) async {
        final end = DateTime.now().add(d);
        while (!_killed && DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      // Lines arrive over time, the way a real program prints.
      final step = runFor == null ? Duration.zero : runFor ~/ (out.length + 1);
      for (final l in err) {
        _err.add(l);
      }
      for (final l in out) {
        if (_killed) break;
        _out.add(l);
        if (step > Duration.zero) await wait(step);
      }
      if (runFor != null && out.isEmpty) await wait(runFor);
      if (!_killed) onEnd?.call();
      await _out.close();
      await _err.close();
      _exit.complete(_killed ? -9 : code);
    }();
  }
  final _out = StreamController<String>();
  final _err = StreamController<String>();
  final _exit = Completer<int>();
  bool _killed = false;

  @override
  Stream<String> get stdoutLines => _out.stream;
  @override
  Stream<String> get stderrLines => _err.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void kill() => _killed = true;
}

typedef Starter = FakeProcess Function(List<String> args, String? workDir);

class FakeHost implements ProcessHost {
  FakeHost({this.os = 'linux', Map<String, String>? environment})
      : environment = environment ??
            {'PATH': '/usr/bin:/usr/local/bin', 'HOME': '/home/me'};

  @override
  final String os;
  @override
  final Map<String, String> environment;

  /// Files that "exist" (programs and anything else asked about).
  final Set<String> files = {};
  final Map<String, List<String>> dirs = {};

  /// What a program prints for the arguments it is asked with (the first
  /// argument that is a key here decides), by full path.
  final Map<String, Map<String, String>> answers = {};
  final Map<String, Starter> starters = {};

  /// Every program started: [path, ...args].
  final List<List<String>> started = [];
  final List<List<String>> asked = [];

  @override
  bool fileExists(String path) =>
      files.contains(path) ||
      (p.isWithin(Directory.systemTemp.path, path) && File(path).existsSync());

  @override
  List<String> listDir(String dir) => dirs[dir] ?? const [];

  @override
  Future<ProcessOutput?> run(String executable, List<String> arguments,
      {Duration timeout = const Duration(seconds: 15)}) async {
    asked.add([executable, ...arguments]);
    final a = answers[executable];
    if (a == null) return null;
    for (final arg in arguments) {
      if (a.containsKey(arg)) return ProcessOutput(0, a[arg]!, '');
    }
    return const ProcessOutput(1, '', 'unknown option');
  }

  @override
  Future<SpeechProcess> start(String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) async {
    started.add([executable, ...arguments]);
    final s = starters[executable];
    if (s == null) {
      throw SpeechException('The program $executable could not be started');
    }
    return s(arguments, workingDirectory);
  }

  // Ready-made programs -----------------------------------------------------

  static const String filtersWithWhisper = '''
Filters:
  T.. = Timeline support
  .S. = Slice threading
  A = Audio input/output
  V = Video input/output
 ... volume            A->A       Change input volume.
 ... whisper           A->A       Transcribe audio using whisper.cpp.
 T.. zoompan           V->V       Apply Zoom & Pan effect.
''';

  static const String filtersWithout = '''
Filters:
 ... volume            A->A       Change input volume.
 T.. zoompan           V->V       Apply Zoom & Pan effect.
''';

  static const String whisperCppHelp = '''
usage: whisper-cli [options] file0 file1 ...
supported audio formats: flac, mp3, ogg, wav

options:
  -h,        --help              [default] show this help message and exit
  -ml N,     --max-len N         [0      ] maximum segment length in characters
  -sow,      --split-on-word     [false  ] split on word rather than on token
  -oj,       --output-json       [false  ] output result in a JSON file
  -ojf,      --output-json-full  [false  ] include more information in the JSON file
  -of FNAME, --output-file FNAME [       ] output file path (without file extension)
  -pp,       --print-progress    [false  ] print progress
  -l LANG,   --language LANG     [en     ] spoken language ('auto' for auto-detect)
             --prompt PROMPT     [       ] initial prompt (max n_text_ctx/2 tokens)
  -m FNAME,  --model FNAME       [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME        [       ] input audio file path
''';

  static const String fasterWhisperHelp = '''
usage: whisper-ctranslate2 [-h] [--model MODEL] [--model_directory MODEL_DIRECTORY]
                           [--output_dir OUTPUT_DIR] [--output_format {txt,vtt,srt,tsv,json,all}]
                           [--language LANGUAGE] [--word_timestamps WORD_TIMESTAMPS]
                           [--initial_prompt INITIAL_PROMPT] [--compute_type COMPUTE_TYPE]
                           audio [audio ...]
''';

  static const String openAiHelp = '''
usage: whisper [-h] [--model MODEL] [--model_dir MODEL_DIR] [--device DEVICE]
               [--output_dir OUTPUT_DIR] [--output_format {txt,vtt,srt,tsv,json,all}]
               [--verbose VERBOSE] [--task {transcribe,translate}] [--language LANGUAGE]
               [--word_timestamps WORD_TIMESTAMPS] [--initial_prompt INITIAL_PROMPT]
               audio [audio ...]
''';

  /// An ffmpeg at [path]. With [whisper] it has the filter and "writes"
  /// [result] (a fixture name) as transcript.json; it also makes WAV files
  /// when asked to convert.
  void addFfmpeg(
      {String path = '/usr/bin/ffmpeg',
      bool whisper = true,
      String result = 'ffmpeg_whisper_ru.json',
      Duration? runFor,
      int code = 0,
      List<String> gpuLog = const [],
      bool gpuFails = false,
      String version = '8.0'}) {
    files.add(path);
    answers[path] = {
      '-filters': whisper ? filtersWithWhisper : filtersWithout,
      '-version': 'ffmpeg version $version Copyright (c) 2000-2025 the FFmpeg developers',
    };
    starters[path] = (args, dir) {
      final af = args.indexOf('-af');
      if (af >= 0 && args[af + 1].startsWith('whisper=')) {
        return FakeProcess(
            out: const [
              'out_time_us=5000000',
              'progress=continue',
              'out_time_us=15000000',
              'progress=end',
            ],
            err: [
              if (args[af + 1].contains('use_gpu=true')) ...gpuLog,
              if (code != 0) '[whisper @ 0x1] Failed to load model',
            ],
            code: args[af + 1].contains('use_gpu=true') && gpuFails ? 1 : code,
            runFor: runFor,
            onEnd: () {
              if (code == 0 &&
                  !(args[af + 1].contains('use_gpu=true') && gpuFails)) {
                File(p.join(dir!, 'transcript.json')).writeAsStringSync(fixture(result));
              }
            });
      }
      // Sound to WAV: the last argument is the output.
      return FakeProcess(
          out: const ['out_time_us=10000000', 'progress=end'],
          onEnd: () => File(args.last).writeAsBytesSync(List.filled(64, 0)));
    };
  }

  /// whisper.cpp's whisper-cli at [path].
  void addWhisperCpp(
      {String path = '/usr/local/bin/whisper-cli',
      String result = 'whispercpp_words_ru.json',
      Duration? runFor}) {
    files.add(path);
    answers[path] = {'--help': whisperCppHelp};
    starters[path] = (args, dir) {
      final base = args[args.indexOf('-of') + 1];
      return FakeProcess(
          out: const [
            '[00:00:00.320 --> 00:00:00.780]   Привет,',
            '[00:00:04.200 --> 00:00:04.650]   Э-э,',
            '[00:00:10.550 --> 00:00:11.200]   ждёте.',
          ],
          err: const [
            'whisper_init_from_file_with_params_no_state: loading model',
            'whisper_print_progress_callback: progress =  45%',
          ],
          runFor: runFor,
          onEnd: () => File('$base.json').writeAsStringSync(fixture(result)));
    };
  }

  /// A Python whisper program at [path] ("whisper-ctranslate2", "whisper").
  void addPythonWhisper(
      {String path = '/usr/local/bin/whisper-ctranslate2',
      String result = 'faster_whisper_he.json',
      bool faster = true}) {
    files.add(path);
    answers[path] = {'--help': faster ? fasterWhisperHelp : openAiHelp};
    starters[path] = (args, dir) {
      final out = args[args.indexOf('--output_dir') + 1];
      return FakeProcess(
          out: const [
            'Detected language \'Hebrew\' with probability 0.98',
            '[00:00.000 --> 00:02.480]  שלום חברים, ברוכים הבאים!',
            '[00:06.900 --> 00:10.360]  קודם צריך קמח, מים ומלח.',
          ],
          onEnd: () => File(p.join(out, 'sound.json')).writeAsStringSync(fixture(result)));
    };
  }
}

/// A real file (the service checks that the media exists).
String mediaFile(Directory dir, String name, {int bytes = 4000, int fill = 1}) {
  final f = File(p.join(dir.path, name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, fill));
  return f.path;
}

/// Puts a (pretend) pack file for model [id] into the models folder of
/// [root].
void installPack(String root, String id) {
  final store = ModelStore(p.join(root, 'models'));
  final m = store.byId(id)!;
  File(p.join(store.dir, m.fileName))
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(2048, 5));
}
