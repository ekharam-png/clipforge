// 1.18: the pure parts of what a real Mac test of 1.17 asked for - a
// probe that cannot wait for ever, a very large file that is never read
// whole, the performance log naming what was in flight, the generic
// safety valve, asking the preview player without waiting inside it, and
// where the Mac app runs from.

import 'dart:async';
import 'dart:io';

import 'package:clipforge/core/background_work.dart';
import 'package:clipforge/core/install_place.dart';
import 'package:clipforge/core/perf_log.dart';
import 'package:clipforge/core/storage/media_import.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/ffmpeg_lane.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_common.dart';
import 'package:clipforge/ui/playback/mpv_ask.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// An engine whose probe never answers (the Mac, 8.3 GiB).
class _NeverEngine implements MediaEngine {
  int probes = 0;
  @override
  Future<MediaInfo> probe(String path) {
    probes++;
    return Completer<MediaInfo>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A player that answers "slow" only after [waitMs], everything else at
/// once. Runs on the helper isolate.
class _SlowPlayer implements MpvCalls {
  _SlowPlayer(this.waitMs);
  final int waitMs;
  @override
  String? get(int handle, String name) {
    if (name == 'slow') sleep(Duration(milliseconds: waitMs));
    if (name == 'none') return null;
    return '$name of $handle';
  }

  @override
  void set(int handle, String name, String value) {
    if (name == 'slow') sleep(Duration(milliseconds: waitMs));
  }
}

MpvCalls _slow600() => _SlowPlayer(600);

void main() {
  group('probe', () {
    test('a video is asked for its index only, a photo for its first frame',
        () {
      for (final path in ['/v/a.mp4', '/v/A.MOV', 'C:\\v\\b.mkv', '/s/c.m4a']) {
        expect(buildProbeCommand(path), isNot(contains('-show_frames')),
            reason: path);
        expect(buildProbeCommand(path), containsAll(['-show_format', '-show_streams']));
      }
      for (final path in ['/p/a.jpg', '/p/b.HEIC', '/p/c.png', '/p/noext', '/p/d.gif']) {
        expect(buildProbeCommand(path),
            containsAllInOrder(['-show_frames', '-read_intervals', '%+#1']),
            reason: path);
      }
      expect(buildProbeCommand('/v/a.mp4').last, '/v/a.mp4');
    });

    test('a probe that never answers ends with a clear message', () async {
      final log = PerfLog();
      final engine = _NeverEngine();
      final watch = Stopwatch()..start();
      Object? error;
      try {
        await probeWithin(engine, '/videos/Camera 1.mp4',
            timeout: const Duration(milliseconds: 120), log: log);
      } catch (e) {
        error = e;
      }
      expect(error, isA<ProbeTimeout>());
      expect(watch.elapsedMilliseconds, lessThan(1500));
      final message = (error! as ProbeTimeout).message;
      expect(message, contains('Camera 1.mp4'));
      expect(message, contains('could not be read within'));
      expect(message, contains('copy it to this computer'));
      expect(message, isNot(contains('/videos/')), reason: 'the name, not the path');
      expect(log.last().join('\n'), contains('probe gave no answer within 120 ms'));
      expect(log.last().join('\n'), isNot(contains('Camera')),
          reason: 'never a file name in the log');
    });

    test('the default limit is under a minute', () {
      expect(kProbeTimeout.inSeconds, inInclusiveRange(20, 60));
      expect(probeTimeoutMessage('a.mp4', kProbeTimeout),
          contains('${kProbeTimeout.inSeconds} seconds'));
    });

    test('sizes for the log', () {
      expect(formatProbeSize(8912345678), '8.3 GB');
      expect(formatProbeSize(138 * 1024 * 1024), '138 MB');
    });
  });

  group('a file of more than 4 GiB', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cf118_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// A sparse file: [size] bytes long, with only [head] and [tail]
    /// really on the disk.
    File sparse(String name, int size, {int head = 1, int tail = 2}) {
      final f = File(p.join(dir.path, name));
      final raf = f.openSync(mode: FileMode.write);
      raf.writeFromSync(List.filled(4096, head));
      raf.setPositionSync(size - 4096);
      raf.writeFromSync(List.filled(4096, tail));
      raf.closeSync();
      return f;
    }

    test('the fingerprint reads two small pieces, whatever the size', () async {
      const size = 5 * 1024 * 1024 * 1024 + 123; // 5 GiB and a bit.
      final f = sparse('big.mp4', size);
      expect(f.lengthSync(), size);
      expect(size, greaterThan(0xFFFFFFFF), reason: 'past 32 bits');
      final watch = Stopwatch()..start();
      final print = await mediaFingerprint(f.path);
      // ignore: avoid_print
      print0('fingerprint of a 5 GiB file: ${watch.elapsedMilliseconds} ms');
      expect(print, hasLength(16));
      expect(watch.elapsedMilliseconds, lessThan(3000),
          reason: 'reading 5 GiB would take far longer');
      expect(kFingerprintSampleBytes, lessThanOrEqualTo(1024 * 1024));

      // The size is part of it: one byte longer is another file...
      final longer = sparse('longer.mp4', size + 1);
      expect(await mediaFingerprint(longer.path), isNot(print));
      // ...and so is the END, which lies past 4 GiB.
      final otherEnd = sparse('end.mp4', size, tail: 3);
      expect(await mediaFingerprint(otherEnd.path), isNot(print));
      // The same content again: the same fingerprint.
      final same = sparse('same.mp4', size);
      expect(await mediaFingerprint(same.path), print);
    }, skip: Platform.isWindows ? 'needs sparse files' : null);
  });

  group('the performance log names what is in flight', () {
    test('a span is in flight until it ends', () {
      final log = PerfLog();
      expect(log.inFlight, isEmpty);
      final a = log.span('preview player open (video)');
      final b = log.span('thumbnail');
      final c = log.span('thumbnail');
      expect(log.inFlight, ['preview player open (video)', '2 x thumbnail']);
      b();
      expect(log.inFlight, ['preview player open (video)', 'thumbnail']);
      a('failed');
      c();
      c(); // Twice does nothing.
      expect(log.inFlight, isEmpty);
    });

    test('track: end or failed, and the error goes on', () async {
      final log = PerfLog();
      expect(await log.track('open: settings', () async => 7), 7);
      await expectLater(
          log.track<void>('open: transcripts', () async => throw StateError('x')),
          throwsStateError);
      final text = log.last().join('\n');
      expect(text, contains('open: settings start'));
      expect(text, contains('open: settings end after'));
      expect(text, contains('open: transcripts failed after'));
      expect(log.inFlight, isEmpty);
    });

    test('a long gap says what was in flight; a short one does not', () {
      final log = PerfLog();
      log.span('preview player open (video)');
      log.reportGap(400);
      expect(log.last().last, endsWith('gap 400 ms (the app could not respond)'));
      log.reportGap(99868);
      expect(
          log.last().last,
          endsWith('gap 99868 ms (the app could not respond); in flight: '
              'preview player open (video)'));
      final quiet = PerfLog()..reportGap(5000);
      expect(quiet.last().last, contains('in flight: nothing the log knows of'));
    });

    test('the watchdog writes what was in flight when the app stops', () async {
      final dir = Directory.systemTemp.createTempSync('cf118_dog_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = PerfLog();
      await log.start(dir: dir.path);
      addTearDown(log.stop);
      log.span('preview player open (video)');
      log.span('start: update check');
      // Let the watchdog see a heartbeat, then keep this isolate busy.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      sleep(const Duration(milliseconds: 3200));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final text = File(p.join(dir.path, kPerfLogFileName)).readAsStringSync();
      expect(text, contains(kNotRespondingMark));
      expect(
          text,
          contains('In flight when it stopped: preview player open (video); '
              'start: update check'));
      expect(text, contains('responding again after'));
    });
  });

  group('the safety valve pauses all background work', () {
    test('every busy kind is paused once, and turned back on', () {
      final log = PerfLog();
      final work = BackgroundWork(log: log);
      final events = <String>[];
      var picturesBusy = true;
      work.add(BackgroundTask('sound pictures',
          busy: () => picturesBusy,
          pause: () => events.add('pictures off'),
          resume: () => events.add('pictures on')));
      work.add(BackgroundTask('ffmpeg runs in the background',
          busy: () => false,
          pause: () => events.add('lane off'),
          resume: () => events.add('lane on')));
      var told = 0;
      work.addListener(() => told++);

      work.onGap(1500);
      expect(work.paused, isFalse, reason: 'under two seconds');
      work.onGap(2100);
      expect(work.paused, isTrue);
      expect(work.pausedAfterMs, 2100);
      // One kind was busy: ALL of them are paused.
      expect(events, ['pictures off', 'lane off']);
      work.onGap(9000);
      expect(events, hasLength(2), reason: 'already paused');
      expect(log.last().join('\n'),
          contains('background work paused: the app did not respond for '
              '2100 ms (busy: sound pictures)'));

      // Work that starts while paused is paused at once.
      work.add(BackgroundTask('thumbnails',
          busy: () => true,
          pause: () => events.add('thumbs off'),
          resume: () => events.add('thumbs on')));
      expect(events.last, 'thumbs off');

      work.resumeAll();
      expect(work.paused, isFalse);
      expect(events.sublist(3), ['pictures on', 'lane on', 'thumbs on']);
      expect(told, 2);

      // Nothing in the background: a gap is not theirs (the computer
      // slept), nothing is paused and nothing is said.
      picturesBusy = false;
      final idle = BackgroundWork(log: log)
        ..add(BackgroundTask('sound pictures',
            busy: () => false, pause: () => fail('paused'), resume: () {}));
      idle.onGap(60000);
      expect(idle.paused, isFalse);
    });

    test('a task that throws does not stop the others', () {
      final work = BackgroundWork(log: PerfLog());
      var second = false;
      work.add(BackgroundTask('a',
          busy: () => throw StateError('x'),
          pause: () => throw StateError('x'),
          resume: () {}));
      work.add(BackgroundTask('b',
          busy: () => true, pause: () => second = true, resume: () {}));
      work.onGap(3000);
      expect(second, isTrue);
    });

    test('the lane: no background run starts while paused; user runs do',
        () async {
      final lane = FfmpegLane(log: PerfLog());
      final order = <String>[];
      final strip = Completer<void>();
      final first = lane.run(LanePriority.background, 'thumbnail strip',
          (run) async {
        order.add('strip start');
        await Future.any([strip.future, run.preempted]);
        order.add(run.isPreempted ? 'strip stopped' : 'strip done');
      });
      await Future<void>.delayed(Duration.zero);
      expect(lane.backgroundBusy, isTrue);

      lane.pauseBackground();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['strip start', 'strip stopped']);
      expect(lane.backgroundPaused, isTrue);
      expect(lane.backgroundBusy, isTrue, reason: 'it waits for its turn');
      expect(lane.busy, isFalse);

      // What the user waits for is not held.
      await lane.run(LanePriority.user, 'run', (_) async => order.add('frame'));
      expect(order.last, 'frame');
      expect(lane.busy, isFalse, reason: 'the strip still waits');

      lane.resumeBackground();
      await Future<void>.delayed(Duration.zero);
      expect(order.last, 'strip start');
      strip.complete();
      await first;
      expect(order.last, 'strip done');
      expect(lane.backgroundBusy, isFalse);
    });
  });

  group('asking the preview player', () {
    test('answers come from a helper; this isolate never waits', () async {
      final log = PerfLog();
      final ask = MpvAsk(_slow600,
          timeout: const Duration(milliseconds: 150), log: log);
      addTearDown(ask.close);
      expect(await ask.get(7, 'time-pos'), 'time-pos of 7');
      expect(await ask.get(7, 'none'), isNull);
      expect(await ask.set(7, 'af', ''), isTrue);

      // The player is busy for 600 ms. The app waits 150 ms at most, and
      // its own timers keep running meanwhile.
      var ticks = 0;
      final timer =
          Timer.periodic(const Duration(milliseconds: 10), (_) => ticks++);
      final watch = Stopwatch()..start();
      final answer = await ask.get(7, 'slow');
      final waited = watch.elapsedMilliseconds;
      timer.cancel();
      expect(answer, isNull);
      expect(waited, inInclusiveRange(140, 450));
      expect(ticks, greaterThan(5), reason: 'the isolate was free');
      expect(ask.timeouts, 1);
      expect(log.last().last,
          contains('preview player: no answer to "get slow" within 150 ms'));

      // The next ask does not queue behind the one that is stuck.
      watch.reset();
      expect(await ask.get(8, 'aid'), 'aid of 8');
      expect(watch.elapsedMilliseconds, lessThan(400));
      expect(await ask.set(8, 'slow', 'x'), isFalse);
      expect(ask.timeouts, 2);
      // Once the stuck helpers have answered nothing is left waiting.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(ask.unanswered, 0);
    });
  });

  group('where the Mac app runs from', () {
    const home = '/Users/sam';
    InstallAdvice? advice(String exe,
            {Map<String, String> plists = const {}, String version = '1.18.0'}) =>
        macInstallAdvice(
          executable: exe,
          home: home,
          version: version,
          exists: (path) => plists.containsKey('$path/Contents/Info.plist'),
          readText: (path) => plists[path],
        );
    String plist(String v) => '<plist><dict><key>CFBundleShortVersionString</key>\n'
        '\t<string>$v</string></dict></plist>';

    test('in Applications: nothing to say', () {
      expect(advice('/Applications/ClipForge.app/Contents/MacOS/ClipForge'), isNull);
      expect(
          advice('$home/Applications/ClipForge.app/Contents/MacOS/ClipForge'),
          isNull);
      expect(advice('/usr/local/bin/clipforge'), isNull,
          reason: 'not an app bundle: a development run');
    });

    test('opened from the download (App Translocation)', () {
      final a = advice(
          '/private/var/folders/ab/T/AppTranslocation/1F2E/d/ClipForge.app/'
          'Contents/MacOS/ClipForge')!;
      expect(a.translocated, isTrue);
      expect(a.otherPath, isNull);
      expect(a.message,
          'Move ClipForge to the Applications folder so it can update itself.');
    });

    test('an older copy sits in Applications', () {
      final a = advice(
          '/private/var/folders/ab/T/AppTranslocation/1F2E/d/ClipForge.app/'
          'Contents/MacOS/ClipForge',
          plists: {
            '/Applications/ClipForge.app/Contents/Info.plist': plist('1.14.1'),
          })!;
      expect(a.otherPath, '/Applications/ClipForge.app');
      expect(a.otherVersion, '1.14.1');
      expect(a.otherIsOlder, isTrue);
      expect(
          a.message,
          'Move ClipForge to the Applications folder so it can update itself. '
          'An older ClipForge (1.14.1) is in the Applications folder: '
          'replace it with this one.');
    });

    test('run from Downloads, the same version in Applications', () {
      final a = advice('$home/Downloads/ClipForge.app/Contents/MacOS/ClipForge',
          plists: {
            '/Applications/ClipForge.app/Contents/Info.plist': plist('1.18.0'),
          })!;
      expect(a.translocated, isFalse);
      expect(a.otherIsOlder, isFalse);
      expect(a.message, contains('There is already a ClipForge (1.18.0)'));
    });

    test('a plist that cannot be read: said without a version', () {
      final a = advice('$home/Desktop/ClipForge.app/Contents/MacOS/ClipForge',
          plists: {'/Applications/ClipForge.app/Contents/Info.plist': 'bplist00'})!;
      expect(a.otherVersion, isNull);
      expect(a.message, contains('There is already a ClipForge in the'));
    });
  });
}

// ignore: avoid_print
void print0(String s) => print(s);
