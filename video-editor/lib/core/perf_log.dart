// The performance log (1.17): a small ring buffer of what the app did and
// when, for the case that it stalls on someone's computer and nobody can
// attach a debugger there. Pure Dart; works in release builds; costs a
// string and a list slot per event (a few events per second at most).
//
// What is in it: opening a project, each probe, save start / end, each
// sound picture and thumbnail run (start / end / stopped / put back in
// the queue), and every time the app's own (UI) isolate could not run for
// a while ("gap"), measured by a 100 ms timer.
//
// What is NEVER in it: file names, paths, project names, text. A file is
// "video 1539 s" or "sound 92 s" (kind and length only), so the log can
// be copied into a feedback message.
//
// A second, tiny isolate (the watchdog) gets a copy of every line and a
// heartbeat ten times a second. When the heartbeat stays away for
// [kUnresponsiveMs] it WRITES the log to `<app support>/perf-log.txt`
// itself: a stalled app cannot write anything, the watchdog can. After the
// app was closed by force, the next start finds that file and offers its
// end as "the previous run".

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// The file the log is written to, inside the app support folder.
const String kPerfLogFileName = 'perf-log.txt';

/// How many lines the buffer keeps.
const int kPerfLogLines = 400;

/// How many lines go into "Copy version info" and into feedback.
const int kPerfLogShared = 60;

/// The timer that measures gaps ticks this often.
const int kGapTickMs = 100;

/// A gap at least this long is written to the log.
const int kGapNotedMs = 300;

/// A gap this long counts as "not responding" (the safety valve of the
/// sound pictures, and the watchdog's own report).
const int kUnresponsiveMs = 2000;

/// The marker of the watchdog's line; the next start looks for it.
const String kNotRespondingMark = 'NOT RESPONDING';

class PerfLog {
  PerfLog({DateTime Function()? now, this.capacity = kPerfLogLines})
      : _now = now ?? DateTime.now {
    _start = _now();
  }

  /// The app's one log. Tests may make their own.
  static final PerfLog instance = PerfLog();

  final DateTime Function() _now;
  final int capacity;
  late final DateTime _start;
  final List<String> _lines = [];
  SendPort? _dog;
  Timer? _tick;
  final Stopwatch _watch = Stopwatch();
  int _lastTickUs = 0;

  /// The longest time the isolate could not run since the start (or since
  /// [takeLongestGap]), in ms.
  int get longestGapMs => _longestGapMs;
  int _longestGapMs = 0;

  /// Told about every gap of [kGapNotedMs] or more (ms).
  final List<void Function(int gapMs)> _gapListeners = [];

  void addGapListener(void Function(int gapMs) f) => _gapListeners.add(f);
  void removeGapListener(void Function(int gapMs) f) =>
      _gapListeners.remove(f);

  /// The end of the previous run's file when that run ended while the app
  /// was not responding; empty otherwise. Set by [start].
  List<String> previousRun = const [];

  String? _path;

  /// Where [write] puts the file; null before [start].
  String? get filePath => _path;

  static String _two(int n) => n < 10 ? '0$n' : '$n';
  static String _three(int n) => n < 10 ? '00$n' : (n < 100 ? '0$n' : '$n');

  String _stamp(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:'
      '${_two(t.second)}.${_three(t.millisecond)}';

  /// Adds one line. Never throws; never put a file name in [what].
  void note(String what) {
    final t = _now();
    final line = '${_stamp(t)} +${t.difference(_start).inMilliseconds} $what';
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    try {
      _dog?.send(line);
    } catch (_) {}
  }

  /// Notes the start of something and returns a function that notes its
  /// end with the time it took (and [result], e.g. "stopped").
  ///
  /// Until the returned function is called, [what] counts as IN FLIGHT:
  /// the watchdog's "NOT RESPONDING" line and every long gap name what
  /// was in flight (1.18: a Mac did not respond for 100 s after a project
  /// opened, and the log showed nothing running).
  void Function([String result]) span(String what) {
    note('$what start');
    final w = Stopwatch()..start();
    final id = _nextSpan++;
    _open[id] = what;
    _tellFlight();
    var ended = false;
    return ([String result = 'end']) {
      if (ended) return;
      ended = true;
      _open.remove(id);
      note('$what $result after ${w.elapsedMilliseconds} ms');
      _tellFlight();
    };
  }

  /// [span] around [work]: "end", or "failed" when it throws.
  Future<T> track<T>(String what, Future<T> Function() work) async {
    final end = span(what);
    try {
      final v = await work();
      end();
      return v;
    } catch (_) {
      end('failed');
      rethrow;
    }
  }

  int _nextSpan = 0;
  final Map<int, String> _open = {};

  /// What was started and has not ended, oldest first (the same thing
  /// running three times is "3 x thing").
  List<String> get inFlight => flightSummary(_open.values);

  void _tellFlight() {
    try {
      _dog?.send(<Object>['flight', inFlight.join('; ')]);
    } catch (_) {}
  }

  /// The last [count] lines, oldest first.
  List<String> last([int count = kPerfLogShared]) =>
      _lines.length <= count ? [..._lines] : _lines.sublist(_lines.length - count);

  /// A gap was measured (the timer calls this; tests may).
  void reportGap(int gapMs) {
    if (gapMs > _longestGapMs) _longestGapMs = gapMs;
    if (gapMs < kGapNotedMs) return;
    final flight = inFlight;
    note('gap $gapMs ms (the app could not respond)'
        '${gapMs >= kUnresponsiveMs ? '; in flight: ${flight.isEmpty ? 'nothing the log knows of' : flight.join('; ')}' : ''}');
    for (final f in [..._gapListeners]) {
      try {
        f(gapMs);
      } catch (_) {}
    }
  }

  /// Starts measuring gaps, and (with [dir], the app support folder) the
  /// watchdog that writes the file when the app stops responding. Called
  /// once by the app; NOT in tests (a periodic timer would never end).
  Future<void> start({String? dir, bool watchdog = true}) async {
    if (_tick != null) return;
    _watch.start();
    _lastTickUs = _watch.elapsedMicroseconds;
    _tick = Timer.periodic(const Duration(milliseconds: kGapTickMs), (_) {
      final now = _watch.elapsedMicroseconds;
      final gap = (now - _lastTickUs) ~/ 1000 - kGapTickMs;
      _lastTickUs = now;
      try {
        _dog?.send(0);
      } catch (_) {}
      if (gap > 0) reportGap(gap);
    });
    if (dir == null) return;
    final path = _path = '$dir${Platform.pathSeparator}$kPerfLogFileName';
    try {
      previousRun = await readStalledRun(path);
    } catch (_) {}
    note('start');
    if (!watchdog) return;
    try {
      final ready = ReceivePort();
      await Isolate.spawn(_watchdogMain, [ready.sendPort, path, capacity],
          debugName: 'perf-log watchdog', errorsAreFatal: false);
      final port = await ready.first.timeout(const Duration(seconds: 5));
      if (port is SendPort) {
        for (final l in _lines) {
          port.send(l);
        }
        _dog = port;
        _tellFlight();
      }
    } catch (_) {
      // No watchdog: the log still works, only a stalled app cannot
      // write it.
    }
  }

  /// Stops the timer and the watchdog (tests).
  void stop() {
    _tick?.cancel();
    _tick = null;
    try {
      _dog?.send(null);
    } catch (_) {}
    _dog = null;
  }

  /// The text of the file: a header and every line.
  String text({String header = ''}) => [
        if (header.isNotEmpty) header,
        'longest gap $_longestGapMs ms',
        ..._lines,
        '',
      ].join('\n');

  /// Writes the log to its file (on demand). Returns the path, or null
  /// when there is no folder or it cannot be written.
  Future<String?> write({String header = ''}) async {
    final path = _path;
    if (path == null) return null;
    try {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(text(header: header), flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// What "Copy version info" and feedback include: the last
  /// [kPerfLogShared] lines, and the end of the previous run when that
  /// one stopped responding.
  String shared() {
    final out = StringBuffer();
    if (previousRun.isNotEmpty) {
      out.writeln('Previous run (ended while not responding):');
      for (final l in previousRun) {
        out.writeln('  $l');
      }
    }
    out.writeln('Performance log (longest gap $_longestGapMs ms):');
    for (final l in last()) {
      out.writeln('  $l');
    }
    return out.toString().trimRight();
  }
}

/// [names] with repeats counted: `[a, b, a]` gives `[2 x a, b]`.
List<String> flightSummary(Iterable<String> names) {
  final count = <String, int>{};
  for (final n in names) {
    count[n] = (count[n] ?? 0) + 1;
  }
  return [
    for (final e in count.entries) e.value == 1 ? e.key : '${e.value} x ${e.key}',
  ];
}

/// The last lines of the file at [path] when its run ended while the app
/// was not responding (the watchdog's mark with no "responding again"
/// after it); empty otherwise or when there is no file.
Future<List<String>> readStalledRun(String path,
    {int lines = kPerfLogShared ~/ 2}) async {
  final f = File(path);
  if (!await f.exists()) return const [];
  // Never more than the last 64 KB of a file someone may have replaced.
  final size = await f.length();
  final from = size > 65536 ? size - 65536 : 0;
  final bytes = <int>[];
  await for (final chunk in f.openRead(from)) {
    bytes.addAll(chunk);
  }
  final all = String.fromCharCodes(bytes)
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final mark = all.lastIndexWhere((l) => l.contains(kNotRespondingMark));
  if (mark < 0) return const [];
  if (all.skip(mark + 1).any((l) => l.contains('responding again'))) {
    return const [];
  }
  final end = all.sublist(0, mark + 1);
  return end.length <= lines ? end : end.sublist(end.length - lines);
}

/// The watchdog isolate: keeps a copy of the lines; a heartbeat (0) says
/// the app is alive; when it stays away, the file is written from here.
void _watchdogMain(List<Object?> args) {
  final ready = args[0] as SendPort;
  final path = args[1] as String;
  final capacity = args[2] as int;
  final inbox = ReceivePort();
  final lines = <String>[];
  final watch = Stopwatch()..start();
  var lastBeat = watch.elapsedMilliseconds;
  var beats = 0;
  var stalledSince = -1;
  var flight = '';
  Timer? timer;

  void write() {
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('${lines.join('\n')}\n', flush: true);
    } catch (_) {}
  }

  void add(String line) {
    lines.add(line);
    if (lines.length > capacity) lines.removeRange(0, lines.length - capacity);
  }

  String clock() {
    final t = DateTime.now();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  inbox.listen((m) {
    if (m == null) {
      timer?.cancel();
      inbox.close();
    } else if (m is String) {
      add(m);
    } else if (m is List) {
      // What is in flight right now (see PerfLog.span).
      if (m.length == 2 && m[0] == 'flight') flight = '${m[1]}';
    } else {
      beats++;
      final now = watch.elapsedMilliseconds;
      if (stalledSince >= 0) {
        add('${clock()} responding again after ${now - stalledSince} ms');
        stalledSince = -1;
        write();
      }
      lastBeat = now;
    }
  });
  timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    // Before the first heartbeat the app is still starting.
    if (beats == 0 || stalledSince >= 0) return;
    final quiet = watch.elapsedMilliseconds - lastBeat;
    if (quiet < kUnresponsiveMs) return;
    stalledSince = lastBeat;
    add('${clock()} $kNotRespondingMark for $quiet ms and counting '
        '(written by the watchdog; the lines above are what the app did '
        'last). In flight when it stopped: '
        '${flight.isEmpty ? 'nothing the log knows of' : flight}');
    write();
  });
  ready.send(inbox.sendPort);
}
