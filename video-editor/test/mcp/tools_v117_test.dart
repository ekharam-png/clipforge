// 1.17 in the Claude tools: edit_part (cut out, silence, lower, delete,
// speed, clean, duplicate a part of the timeline, with the rows),
// list_quiet_parts / remove_quiet_part, set_only_when_speaking; dry runs,
// the reasons for rows that cannot be changed, and put back through
// restore_cut.

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Bench b;
  late Client c;

  Future<Project> load() async => await b.store.load('pod');

  setUp(() async {
    b = Bench(ffmpeg: false);
    c = b.client;
    await b.seed('pod', name: 'Podcast', clips: [
      b.video('a', file: 'a.mp4'),
      b.video('b', file: 'b.mp4'),
    ], audio: [
      AudioClip(
          id: 'mu',
          path: b.touch('song.mp3'),
          sourceDurationMs: 60000,
          startMs: 0,
          inMs: 0,
          outMs: 20000),
    ], titles: [
      const TitleOverlay(id: 't', text: 'Hello', startMs: 12000, endMs: 14000),
    ]);
  });
  tearDown(() => b.dispose());

  test('the four tools are there, with an action and rows', () {
    final names = {for (final t in b.tools.tools) t.name};
    expect(
        names,
        containsAll([
          'edit_part',
          'list_quiet_parts',
          'remove_quiet_part',
          'set_only_when_speaking',
        ]));
    final edit = b.tools.tools.firstWhere((t) => t.name == 'edit_part');
    expect((edit.properties['action'] as Map)['enum'],
        ['cut_out', 'delete', 'silence', 'lower', 'speed', 'clean', 'duplicate']);
    expect(edit.properties.keys,
        containsAll(['from_ms', 'to_ms', 'rows', 'level_db', 'speed', 'dry_run']));
  });

  test('silence one row: a dry run saves nothing, then it does', () async {
    var r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'silence',
      'from_ms': 8000,
      'to_ms': 12000,
      'rows': ['Music'],
      'dry_run': true,
    });
    expect(r.text, startsWith('DRY RUN - nothing was saved. Would set'));
    expect(r.text, contains('Rows: Music.'));
    expect((await load()).audio.single.quiet, isEmpty);

    r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'silence',
      'from_ms': 8000,
      'to_ms': 12000,
      'rows': ['Music'],
    });
    expect(r.text, contains('to silence; nothing moved.'));
    expect(r.data['changed'], isTrue);
    expect(r.data['itemsChanged'], 1);
    final p = await load();
    expect(p.audio.single.quiet, [const QuietRange(8000, 12000)]);
    expect(p.clips.every((x) => x.quiet.isEmpty), isTrue);
    expect(p.durationMs, 20000);
  });

  test('every row; the answer says which rows were left alone and why',
      () async {
    final r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'lower',
      'from_ms': 11000,
      'to_ms': 15000,
      'level_db': -6,
    });
    expect(r.text, contains('to -6 dB'));
    expect(r.text, contains('Rows: Video, Music.'));
    expect(r.text,
        contains('Left alone: Titles and captions (titles have no sound).'));
    final p = await load();
    expect(p.clips[1].quiet.single.level, closeTo(0.501, 0.001));
    expect(p.audio.single.quiet.single.level, closeTo(0.501, 0.001));
  });

  test('list_quiet_parts and remove_quiet_part', () async {
    await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'silence',
      'from_ms': 2000,
      'to_ms': 3000,
      'rows': ['video'],
    });
    var r = await c.ok('list_quiet_parts', {'project_id': 'pod'});
    expect(r.text, contains('1 quiet part(s)'));
    expect(r.text, contains('silent: clip 1 (a.mp4) [video] item_id a'));
    final row = (r.data['quietParts'] as List).single as Map;
    expect([row['fromMs'], row['toMs'], row['sourceFromMs'], row['level']],
        [2000, 3000, 2000, 'silent']);
    expect(r.data.containsKey('project'), isFalse, reason: 'a read');

    r = await c.ok('remove_quiet_part', {'project_id': 'pod', 'item_id': 'a'});
    expect(r.text, contains('plays at its own level there again'));
    expect((await load()).clips.first.quiet, isEmpty);
    r = await c.ok('list_quiet_parts', {'project_id': 'pod'});
    expect(r.text, contains('No part of "Podcast" is silenced or lowered.'));
    expect(
        await c.fails('remove_quiet_part', {'project_id': 'pod', 'item_id': 'a'}),
        contains('has no quiet part'));
  });

  test('cut_out: everything, logged, put back with restore_cut', () async {
    expect(
        await c.fails('edit_part', {
          'project_id': 'pod',
          'action': 'cut_out',
          'from_ms': 8000,
          'to_ms': 12000,
          'rows': ['video'],
        }),
        allOf(contains('every row'), contains('"silence"')));
    final r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'cut_out',
      'from_ms': 8000,
      'to_ms': 12000,
    });
    expect(r.text, contains('out of everything and closed the gap'));
    expect(r.data['removedMs'], 4000);
    final ids = (r.data['cutIds'] as List).cast<String>();
    expect(ids, hasLength(2));
    var p = await load();
    expect(p.durationMs, 16000);
    expect(p.audio.map((a) => a.durationMs).fold<int>(0, (n, x) => n + x), 16000);
    expect(p.autoCuts.map((x) => [x.kind, x.by]), everyElement(['part', 'claude']));

    final list = await c.ok('list_auto_cuts', {'project_id': 'pod'});
    expect(list.text, contains('part'));
    for (final id in ids) {
      await c.ok('restore_cut', {'project_id': 'pod', 'cut_id': id});
    }
    p = await load();
    expect(p.durationMs, 20000);
    expect(p.clips.map((x) => [x.inMs, x.outMs]), [
      [0, 10000],
      [0, 10000],
    ]);
    expect(p.audio.single.outMs, 20000, reason: 'the music is one piece again');
    expect(p.autoCuts, isEmpty);
  });

  test('delete leaves a gap; the video row says why not', () async {
    expect(
        await c.fails('edit_part', {
          'project_id': 'pod',
          'action': 'delete',
          'from_ms': 5000,
          'to_ms': 7000,
          'rows': ['video'],
        }),
        contains('The video row cannot have a gap: use Cut out.'));
    final r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'delete',
      'from_ms': 5000,
      'to_ms': 7000,
    });
    expect(r.text, contains('left a gap; nothing moved'));
    expect(r.text, contains('Left alone: Video (the video row cannot have a gap'));
    final p = await load();
    expect(p.audio.map((a) => [a.startMs, a.endMs]).toList()..sort((x, y) => x[0] - y[0]), [
      [0, 5000],
      [7000, 20000],
    ]);
    expect(p.durationMs, 20000);
  });

  test('speed: the part, where it is now, mute below 0.5 by default',
      () async {
    expect(
        await c.fails('edit_part', {
          'project_id': 'pod',
          'action': 'speed',
          'from_ms': 2000,
          'to_ms': 4000,
        }),
        contains('needs `speed`'));
    final r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'speed',
      'from_ms': 2000,
      'to_ms': 4000,
      'speed': 0.25,
    });
    expect(r.text, contains('its own sound off'));
    expect(r.data['partNow'], {'fromMs': 2000, 'toMs': 10000});
    final p = await load();
    expect(p.clips.map((x) => [x.speed, x.muted]), [
      [1.0, false],
      [0.25, true],
      [1.0, false],
      [1.0, false],
    ]);
    expect(p.durationMs, 26000);
  });

  test('clean and duplicate; an unknown row lists the rows', () async {
    var r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'clean',
      'from_ms': 2000,
      'to_ms': 4000,
      'rows': ['video'],
    });
    expect(r.text, contains('"Clean up sound" on'));
    expect((await load()).clips.map((x) => x.denoise), [false, true, false, false]);
    r = await c.ok('edit_part', {
      'project_id': 'pod',
      'action': 'duplicate',
      'from_ms': 12000,
      'to_ms': 14000,
    });
    expect(r.data['copy'], {'fromMs': 14000, 'toMs': 16000});
    expect((await load()).durationMs, 22000);
    expect(
        await c.fails('edit_part', {
          'project_id': 'pod',
          'action': 'silence',
          'from_ms': 1,
          'to_ms': 900,
          'rows': ['drums'],
        }),
        allOf(contains('no row "drums"'), contains('"video"'), contains('"Music"')));
    expect(
        await c.fails('edit_part',
            {'project_id': 'pod', 'action': 'silence', 'from_ms': 9, 'to_ms': 3}),
        contains('must be after'));
  });

  test('set_only_when_speaking: a speech track, the level, all, off',
      () async {
    expect(
        await c.fails('set_only_when_speaking',
            {'project_id': 'pod', 'track_id': 'Music'}),
        contains('is not a speech track'));
    await c.ok('add_sound_track', {'project_id': 'pod', 'name': 'Voice'});
    var r = await c.ok('set_only_when_speaking',
        {'project_id': 'pod', 'track_id': 'Voice', 'dry_run': true});
    expect(r.text, startsWith('DRY RUN'));
    expect((await load()).soundTracks.any((t) => t.gate), isFalse);
    r = await c.ok('set_only_when_speaking',
        {'project_id': 'pod', 'track_id': 'Voice', 'room_db': -100});
    expect(r.text, contains('on for "Voice": silent between the turns'));
    expect(r.text, contains('loudness'));
    var t = (await load()).soundTracks.firstWhere((t) => t.name == 'Voice');
    expect([t.gate, t.gateLevel], [true, 0.0]);
    final list = await c.ok('list_quiet_parts', {'project_id': 'pod'});
    expect(list.text, contains('"Only when speaking" is on for Voice'));
    r = await c.ok('set_only_when_speaking',
        {'project_id': 'pod', 'track_id': 'all', 'on': false});
    expect(r.text, contains('off for "Voice"'));
    t = (await load()).soundTracks.firstWhere((t) => t.name == 'Voice');
    expect(t.gate, isFalse);
  });

  // Second pass (same version) -------------------------------------------

  test('list_markers in a short video (35.3 s, markers at 0:11.6 and '
      '0:23.7): two different parts, not the whole video twice', () async {
    await b.seed('clip', clips: [b.video('v', file: 'clip.mp4', source: 35300)]);
    for (final at in [11600, 23700]) {
      await c.ok('add_marker', {'project_id': 'clip', 'at_ms': at});
    }
    final r = await c.ok('list_markers', {'project_id': 'clip'});
    final rows = [for (final m in r.data['markers'] as List) m as Map];
    expect(rows, hasLength(2));
    final ranges = [
      for (final m in rows) (m['shortFromMs'] as int, m['shortToMs'] as int),
    ];
    expect(ranges[0], isNot(ranges[1]));
    for (final (i, (from, to)) in ranges.indexed) {
      expect(to - from, lessThan(35300 * 0.6), reason: 'not the whole video');
      expect(from, lessThan(rows[i]['atMs'] as int));
      expect(to, greaterThan(rows[i]['atMs'] as int));
      expect(to, lessThanOrEqualTo(35300));
    }
    expect(r.data.containsKey('overlapping'), isFalse);
    expect(r.text, isNot(contains('overlap by more than')));
  });

  test('list_markers says when two shorts would show the same part, with '
      'the one range that covers both', () async {
    await b.seed('clip', clips: [b.video('v', file: 'clip.mp4', source: 35300)]);
    final ids = <String>[];
    for (final at in [15000, 17000]) {
      final r = await c.ok('add_marker', {'project_id': 'clip', 'at_ms': at});
      ids.add(r.data['markerId'] as String);
    }
    final r = await c.ok('list_markers', {'project_id': 'clip'});
    final together = (r.data['overlapping'] as List).single as Map;
    expect(together['markerIds'], ids);
    final rows = [for (final m in r.data['markers'] as List) m as Map];
    expect(together['oneShortFromMs'], rows.first['shortFromMs']);
    expect(together['oneShortToMs'], rows.last['shortToMs']);
    expect(r.text, contains('overlap by more than 70 %'));
    expect(r.text, contains('Tell the user how many shorts you made'));
  });

  test('restore_cut brings the captions of a cut part back', () async {
    await b.seed('caps', clips: [
      b.video('v', file: 'caps.mp4', source: 60000),
    ], titles: [
      for (var i = 0; i < 30; i++)
        TitleOverlay(
            id: 'c$i',
            text: 'said $i',
            startMs: i * 2000,
            endMs: i * 2000 + 1800,
            kind: TitleKind.caption),
    ]);
    await c.ok('edit_part', {
      'project_id': 'caps',
      'action': 'cut_out',
      'from_ms': 20000,
      'to_ms': 30000,
    });
    var p = await b.store.load('caps');
    expect(p.durationMs, 50000);
    expect(p.titles.any((t) => t.text == 'said 12'), isFalse);
    expect(p.autoCuts.single.titles, isNotEmpty);
    await c.ok('restore_cut',
        {'project_id': 'caps', 'cut_id': p.autoCuts.single.id});
    p = await b.store.load('caps');
    expect(p.durationMs, 60000);
    final back = p.titles.singleWhere((t) => t.text == 'said 12');
    expect(back.startMs, closeTo(24000, 2));
    expect(back.kind, TitleKind.caption);
    expect(p.titles.length, 30);
  });
}
