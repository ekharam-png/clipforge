// The background render queue of processed clip sound: debounce, one or
// two at a time, playhead first, stop / retry, obsolete renders.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/sound_renders.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Clip talk(String id, String path,
        {int inMs = 0, int outMs = 4000, bool denoise = true, double focus = 0}) =>
    Clip(
      id: id,
      type: ClipType.video,
      path: path,
      sourceDurationMs: 60000,
      inMs: inMs,
      outMs: outMs,
      width: 640,
      height: 360,
      denoise: denoise,
      voiceFocus: focus,
    );

Project project(List<Clip> clips) => Project(
      id: 'p',
      name: 'Test',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: clips,
    );

void main() {
  late FakeMediaEngine engine;
  late FakeSoundCache cache;
  var focus = 0;

  SoundRenders make({int maxBusy = 2}) {
    engine = FakeMediaEngine();
    cache = FakeSoundCache();
    focus = 0;
    final r = SoundRenders(
      engine: engine,
      cache: cache,
      maxBusy: maxBusy,
      debounce: const Duration(milliseconds: 800),
      focusIndex: () => focus,
    );
    addTearDown(r.dispose);
    return r;
  }

  void finish(int i) {
    final job = engine.soundRenders[i];
    final name = job.path.split('/').last;
    cache.files.add(name.substring(0, name.lastIndexOf('.')));
    job.job.finish(job.path);
  }

  testWidgets('waits until the settings settle, then renders once',
      (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4', focus: 0.5);
    r.update(project([a]));
    expect(r.statusOf(a).state, SoundState.waiting);
    // A slider being dragged: a new value every 100 ms.
    for (final v in [0.55, 0.6, 0.65, 0.7]) {
      await tester.pump(const Duration(milliseconds: 100));
      r.update(project([a.copyWith(voiceFocus: v)]));
    }
    await tester.pump(const Duration(milliseconds: 700));
    expect(engine.soundRenders, isEmpty, reason: 'still settling');
    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.soundRenders, hasLength(1));
    expect(engine.soundRenders.single.clip.voiceFocus, 0.7);
    final last = a.copyWith(voiceFocus: 0.7);
    expect(r.statusOf(last).state, SoundState.processing);
    engine.soundRenders.single.job.report(0.4);
    await tester.pump();
    expect(r.statusOf(last).fraction, closeTo(0.4, 0.001));
    expect(r.statusOf(last).label, 'Processing sound… 40%');
    finish(0);
    await tester.pump();
    expect(r.statusOf(last).state, SoundState.ready);
    expect(r.readyPath(last), endsWith('.flac'));
    expect(r.readyFiles(project([last])), {'a': r.readyPath(last)});
    expect(cache.evictions, 1, reason: 'the cache is kept to its size');
  });

  testWidgets('pieces of one file with the same settings share one render',
      (tester) async {
    final r = make();
    await tester.pump();
    final pieces = [
      talk('a', '/a.mp4', inMs: 0, outMs: 2000),
      talk('b', '/a.mp4', inMs: 2500, outMs: 4000),
      talk('c', '/a.mp4', inMs: 4500, outMs: 9000),
      talk('d', '/a.mp4', inMs: 0, outMs: 2000, denoise: false), // nothing
    ];
    r.update(project(pieces));
    await tester.pump(const Duration(seconds: 1));
    expect(engine.soundRenders, hasLength(1));
    finish(0);
    await tester.pump();
    for (final c in pieces.take(3)) {
      expect(r.statusOf(c).state, SoundState.ready);
    }
    expect(r.statusOf(pieces[3]).state, SoundState.none);
  });

  testWidgets('a file already in the cache is ready at once', (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4');
    cache.files.add(cache.keyFor(a)!);
    r.update(project([a]));
    expect(r.statusOf(a).state, SoundState.ready);
    await tester.pump(const Duration(seconds: 2));
    expect(engine.soundRenders, isEmpty);
    expect(cache.touched, [cache.keyFor(a)], reason: 'recently used');
  });

  testWidgets('two at a time, one while playing, playhead clip first',
      (tester) async {
    final r = make();
    await tester.pump();
    final clips = [
      for (final n in ['a', 'b', 'c', 'd']) talk(n, '/$n.mp4'),
    ];
    focus = 2; // the playhead is on c
    r.update(project(clips));
    await tester.pump(const Duration(seconds: 1));
    expect([for (final j in engine.soundRenders) j.clip.id], ['c', 'd']);
    r.playing = true;
    finish(0);
    await tester.pump();
    expect(engine.soundRenders, hasLength(2), reason: 'playing: only one');
    finish(1);
    await tester.pump();
    expect([for (final j in engine.soundRenders) j.clip.id], ['c', 'd', 'a']);
    r.playing = false;
    await tester.pump();
    expect([for (final j in engine.soundRenders) j.clip.id], ['c', 'd', 'a', 'b']);
  });

  testWidgets('stop cancels; retry renders again', (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4');
    r.update(project([a]));
    await tester.pump(const Duration(seconds: 1));
    r.stop(a);
    await tester.pump();
    expect(engine.soundRenders.single.job.cancelled, isTrue);
    expect(r.statusOf(a).state, SoundState.stopped);
    await tester.pump(const Duration(seconds: 2));
    expect(engine.soundRenders, hasLength(1), reason: 'stays stopped');
    r.retry(a);
    await tester.pump();
    expect(engine.soundRenders, hasLength(2));
    expect(r.statusOf(a).state, SoundState.processing);
  });

  testWidgets('a failed render says why and can be tried again',
      (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4');
    r.update(project([a]));
    await tester.pump(const Duration(seconds: 1));
    engine.soundRenders.single.job.fail(ExportException('No afftdn'));
    await tester.pump();
    expect(r.statusOf(a).state, SoundState.failed);
    expect(r.statusOf(a).error, 'No afftdn');
    expect(r.readyPath(a), isNull);
    r.retry(a);
    await tester.pump();
    expect(engine.soundRenders, hasLength(2));
  });

  testWidgets('a render nobody wants any more is stopped', (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4');
    r.update(project([a]));
    await tester.pump(const Duration(seconds: 1));
    final first = engine.soundRenders.single.job;
    // Clean up switched off: nothing needs that file now.
    r.update(project([a.copyWith(denoise: false)]));
    await tester.pump();
    expect(first.cancelled, isTrue);
    expect(r.busyCount, 0);
    expect(r.statusOf(a.copyWith(denoise: false)).state, SoundState.none);
  });

  testWidgets('volume, speed and trim do not need a new render',
      (tester) async {
    final r = make();
    await tester.pump();
    final a = talk('a', '/a.mp4');
    r.update(project([a]));
    await tester.pump(const Duration(seconds: 1));
    finish(0);
    await tester.pump();
    final b = a.copyWith(volume: 0.5, speed: 2, inMs: 1000, outMs: 3000);
    r.update(project([b]));
    await tester.pump(const Duration(seconds: 1));
    expect(r.statusOf(b).state, SoundState.ready);
    expect(engine.soundRenders, hasLength(1));
  });

  testWidgets('dispose stops what runs', (tester) async {
    final r = SoundRenders(engine: engine = FakeMediaEngine(), cache: FakeSoundCache());
    await tester.pump();
    r.update(project([talk('a', '/a.mp4')]));
    await tester.pump(const Duration(seconds: 1));
    r.dispose();
    expect(engine.soundRenders.single.job.cancelled, isTrue);
  });
}
