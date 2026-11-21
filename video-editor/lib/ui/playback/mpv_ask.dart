// Asking the preview player (libmpv) for a property, or setting one,
// WITHOUT the app waiting inside libmpv (1.18).
//
// media_kit's `NativePlayer.getProperty` / `setProperty` call
// `mpv_get_property_string` / `mpv_set_property_string` directly, on the
// app's own (UI) isolate. Those calls wait for mpv's core to reach a point
// where it answers; a core that is busy (opening a file, starting the
// hardware decoder or the sound device) keeps the caller - here the whole
// app - waiting for as long as it takes. In the 1.17 test on a Mac the
// editor did not respond for 99.9 s, starting four seconds after a project
// opened: four seconds is `MediaKitTimelinePlayer.loadTimeout`, after
// which the player was ASKED ("time-pos") whether the file had loaded.
//
// Here the call is made on a helper isolate; the app waits for the answer
// with a time limit. An ask that gets no answer in time counts as "no
// answer" (null / false), is written to the performance log, and the
// helper that is stuck inside libmpv is left to finish by itself while a
// new one takes the next asks. libmpv's client functions may be called
// from any thread.

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../core/perf_log.dart';

/// How long the app waits for the player's answer.
const Duration kMpvAskTimeout = Duration(seconds: 2);

/// What [MpvAsk] calls: the real libmpv, or a stand-in in tests.
abstract class MpvCalls {
  /// Runs on the helper isolate. Null: no such property.
  String? get(int handle, String name);
  void set(int handle, String name, String value);
}

typedef _GetNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _SetNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetDart = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// libmpv at [libraryPath] (the one media_kit loaded).
class LibMpvCalls implements MpvCalls {
  LibMpvCalls(String libraryPath) {
    final lib = DynamicLibrary.open(libraryPath);
    _get = lib.lookupFunction<_GetNative, _GetNative>('mpv_get_property_string');
    _set = lib.lookupFunction<_SetNative, _SetDart>('mpv_set_property_string');
    _free = lib.lookupFunction<_FreeNative, _FreeDart>('mpv_free');
  }

  late final _GetNative _get;
  late final _SetDart _set;
  late final _FreeDart _free;

  @override
  String? get(int handle, String name) {
    final n = name.toNativeUtf8();
    try {
      final v = _get(Pointer<Void>.fromAddress(handle), n);
      if (v == nullptr) return null;
      final text = v.toDartString();
      _free(v.cast());
      return text;
    } finally {
      calloc.free(n);
    }
  }

  @override
  void set(int handle, String name, String value) {
    final n = name.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      _set(Pointer<Void>.fromAddress(handle), n, v);
    } finally {
      calloc.free(n);
      calloc.free(v);
    }
  }
}

class _Helper {
  _Helper(this.isolate, this.port, this.inbox);
  final Isolate isolate;
  final SendPort port;
  final ReceivePort inbox;
  bool stuck = false;
  int waiting = 0;
}

class MpvAsk {
  /// [calls] makes the [MpvCalls] ON THE HELPER ISOLATE (so it must be a
  /// top-level or static function, or a closure over plain values).
  MpvAsk(this.calls, {this.timeout = kMpvAskTimeout, PerfLog? log})
      : _log = log ?? PerfLog.instance;

  final MpvCalls Function() calls;
  final Duration timeout;
  final PerfLog _log;

  Future<_Helper>? _helper;
  int _next = 0;
  final Map<int, Completer<Object?>> _pending = {};

  /// How many asks got no answer in time since the start.
  int get timeouts => _timeouts;
  int _timeouts = 0;

  /// Asks still waiting for an answer (also those given up).
  int get unanswered => _unanswered;
  int _unanswered = 0;

  Future<_Helper> _spawn() async {
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    late final _Helper helper;
    inbox.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is List && m.length == 2) {
        _unanswered--;
        helper.waiting--;
        _pending.remove(m[0])?.complete(m[1]);
        // A helper that was given up and has now answered everything is
        // not needed any more.
        if (helper.stuck && helper.waiting <= 0) {
          helper.port.send(null);
          inbox.close();
        }
      }
    });
    final isolate = await Isolate.spawn(_helperMain, [inbox.sendPort, calls],
        debugName: 'mpv asks', errorsAreFatal: false);
    helper = _Helper(isolate, await ready.future, inbox);
    return helper;
  }

  Future<Object?> _ask(String what, int handle, String name, String value) async {
    final _Helper helper;
    try {
      helper = await (_helper ??= _spawn());
    } catch (_) {
      _helper = null;
      rethrow;
    }
    final id = _next++;
    final done = _pending[id] = Completer<Object?>();
    _unanswered++;
    helper.waiting++;
    helper.port.send([id, what, handle, name, value]);
    return done.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      _timeouts++;
      _log.note('preview player: no answer to "$what $name" within '
          '${timeout.inMilliseconds} ms; going on without it');
      // This helper is waiting inside the player: the next asks get a
      // new one.
      if (!helper.stuck) {
        helper.stuck = true;
        _helper = null;
      }
      return const _NoAnswer();
    });
  }

  /// The property [name] of the player at [handle]; null when the player
  /// did not answer within [timeout] (or has no such property).
  Future<String?> get(int handle, String name) async {
    final v = await _ask('get', handle, name, '');
    return v is String ? v : null;
  }

  /// Sets [name]; false when the player did not take it within [timeout]
  /// (it may still do so later).
  Future<bool> set(int handle, String name, String value) async =>
      await _ask('set', handle, name, value) is! _NoAnswer;

  /// Lets go of the helper (tests).
  Future<void> close() async {
    final h = _helper;
    _helper = null;
    if (h == null) return;
    try {
      final helper = await h;
      helper.port.send(null);
      helper.inbox.close();
    } catch (_) {}
  }
}

class _NoAnswer {
  const _NoAnswer();
}

void _helperMain(List<Object?> args) {
  final out = args[0] as SendPort;
  final make = args[1] as MpvCalls Function();
  final inbox = ReceivePort();
  MpvCalls? calls;
  inbox.listen((m) {
    if (m == null) {
      inbox.close();
      return;
    }
    final job = m as List;
    Object? result;
    try {
      calls ??= make();
      if (job[1] == 'get') {
        result = calls!.get(job[2] as int, job[3] as String);
      } else {
        calls!.set(job[2] as int, job[3] as String, job[4] as String);
        result = true;
      }
    } catch (_) {
      result = null;
    }
    out.send([job[0], result]);
  });
  out.send(inbox.sendPort);
}
