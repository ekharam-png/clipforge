// 1.8 tool: fit_music_to_video (and loops in get_project).

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  setUp(() {
    b = Bench();
    c = b.client;
  });
  tearDown(() => b.dispose());

  AudioClip song(int source) => AudioClip(
      id: 'm', path: '/music/song.mp3', sourceDurationMs: source,
      startMs: 0, inMs: 0, outMs: source);

  test('fit_music_to_video cuts long music, loops short music on request',
      () async {
    await b.seed('p1', clips: [b.video('a', source: 10000)], audio: [song(60000)]);
    final r = await c.ok('fit_music_to_video', {'project_id': 'p1', 'audio_id': 'm'});
    expect(r.text, contains('ends with the video'));
    final a = (await b.store.load('p1')).audio.single;
    expect([a.endMs, a.fadeOutMs, a.looped], [10000, 2000, false]);

    await b.seed('p2', clips: [b.video('a', source: 10000)], audio: [song(4000)]);
    expect(await c.fails('fit_music_to_video', {'project_id': 'p2', 'audio_id': 'm'}),
        contains('loop: true'));
    final l = await c.ok('fit_music_to_video',
        {'project_id': 'p2', 'audio_id': 'm', 'loop': true});
    expect(l.text, contains('loops'));
    final m = (await b.store.load('p2')).audio.single;
    expect([m.loopMs, m.endMs], [10000, 10000]);
    final g = await c.ok('get_project', {'project_id': 'p2'});
    expect(g.text, contains('loops its source part to fill 10000 ms'));
    // Claude's undo takes it back.
    await c.ok('undo', {'project_id': 'p2'});
    expect((await b.store.load('p2')).audio.single.looped, isFalse);
  });
}
