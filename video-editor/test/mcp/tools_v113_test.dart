// 1.13 in the Claude tools: get_captions (the captions as compact text,
// paged, with speakers), replace_in_captions (find and replace over all
// captions, dry run by default) and get_speech_map (who talks when, from
// the sound: real files made by ffmpeg; skipped without it).

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

TitleOverlay cap(String id, String text, int start, int end) => TitleOverlay(
    id: id, text: text, startMs: start, endMs: end, kind: TitleKind.caption);

void main() {
  group('captions', () {
    late Bench b;
    late Client c;
    setUp(() async {
      b = Bench(ffmpeg: false);
      c = b.client;
      await b.seed('pod', name: 'Podcast', clips: [
        b.video('a', source: 600000),
      ], titles: [
        cap('c1', 'Sem: Welcome back', 0, 2000),
        cap('c2', 'to the\nshow.', 2100, 4000),
        cap('c3', 'Dana: Thanks, Sem.', 5000, 7000),
        cap('c4', 'Semolina is next.', 61000, 63000),
        const TitleOverlay(id: 't1', text: 'The Sem Show', startMs: 0, endMs: 3000),
      ]);
    });
    tearDown(() => b.dispose());

    test('get_captions: one compact line each, speakers carried on', () async {
      final r = await c.ok('get_captions', {'project_id': 'pod'});
      expect(r.text, contains('has 4 caption(s); speakers: Sem, Dana.'));
      expect(r.text, contains('Lines 1-4 of 4.'));
      expect(
          r.text.split('\n').skip(1).toList(),
          [
            '0-2000 [0:00] Sem: Welcome back',
            '2100-4000 [0:02] Sem: to the show.',
            '5000-7000 [0:05] Dana: Thanks, Sem.',
            '61000-63000 [1:01] Dana: Semolina is next.',
          ]);
      expect(r.data['total'], 4);
      expect(r.data['speakers'], ['Sem', 'Dana']);
      expect(r.data.containsKey('nextOffset'), isFalse);
      // It is a read: no project in the answer, nothing saved.
      expect(r.data.containsKey('project'), isFalse);
    });

    test('get_captions: ids, a time range, pages, paragraphs, titles',
        () async {
      var r = await c.ok('get_captions',
          {'project_id': 'pod', 'ids': true, 'from_ms': 2000, 'to_ms': 60000});
      expect(r.text, contains('has 4 caption(s), 2 in this part'));
      expect(r.text, contains('c2 2100-4000 [0:02] Sem: to the show.'));
      expect(r.text, isNot(contains('Welcome')));
      r = await c.ok('get_captions', {'project_id': 'pod', 'limit': 3});
      expect(r.text, contains('Lines 1-3 of 4.'));
      expect(r.text, contains('More: call again with offset 3.'));
      expect(r.data['nextOffset'], 3);
      r = await c.ok('get_captions', {'project_id': 'pod', 'offset': 3});
      expect(r.text.trim().split('\n').last, '61000-63000 [1:01] Dana: Semolina is next.');
      r = await c.ok('get_captions', {'project_id': 'pod', 'format': 'paragraphs'});
      expect(r.text.split('\n').skip(1).toList(), [
        '0-4000 [0:00] Sem: Welcome back to the show.',
        '5000-7000 [0:05] Dana: Thanks, Sem.',
        '61000-63000 [1:01] Dana: Semolina is next.',
      ]);
      r = await c.ok('get_captions', {'project_id': 'pod', 'kind': 'titles'});
      expect(r.text, contains('has 1 title(s)'));
      expect(r.text, contains('0-3000 [0:00] The Sem Show'));
      r = await c.ok('get_captions', {'project_id': 'pod', 'kind': 'all'});
      expect(r.data['total'], 5);
      expect(await c.fails('get_captions', {'project_id': 'pod', 'from_ms': 9, 'to_ms': 3}),
          contains('must be after'));
    });

    test('get_captions on a project without captions says how to get them',
        () async {
      await b.seed('empty', clips: [b.video('a')]);
      final r = await c.ok('get_captions', {'project_id': 'empty'});
      expect(r.text, contains('has 0 caption(s)'));
      expect(r.text, contains('import_srt'));
      expect(r.text, contains('captions_from_transcript'));
    });

    test('1000 captions come in compact pages', () async {
      await b.seed('long', clips: [
        b.video('a', source: 2400000)
      ], titles: [
        for (var i = 0; i < 1000; i++)
          cap('c$i', '${i % 5 == 0 ? (i.isEven ? 'Sam: ' : 'Dana: ') : ''}and that is line $i',
              i * 2400, i * 2400 + 2200),
      ]);
      final r = await c.ok('get_captions', {'project_id': 'long'});
      expect(r.text, contains('Lines 1-400 of 1000.'));
      expect(r.data['nextOffset'], 400);
      expect(r.text.length, lessThan(22000));
      final all = await c.ok('get_captions', {'project_id': 'long', 'limit': 2000});
      expect(all.data['count'], 1000);
      expect(all.text.length, lessThan(55000));
    });

    test('replace_in_captions is a dry run unless told otherwise', () async {
      final before = b.projectFile('pod').readAsStringSync();
      final r = await c.ok('replace_in_captions',
          {'project_id': 'pod', 'find': 'Sem', 'replace': 'Sam', 'whole_word': true});
      expect(r.text, startsWith('DRY RUN - nothing was saved. Would replace "Sem" by "Sam" '
          'in 2 place(s) in 2 caption(s).'));
      expect(r.text, contains('[0:00] "Sem: Welcome back" -> "Sam: Welcome back"'));
      expect(r.text, contains('[0:05] "Dana: Thanks, Sem." -> "Dana: Thanks, Sam."'));
      expect(r.text, contains('Call again with dry_run false to do it.'));
      expect(r.data['replacements'], 2);
      expect(r.data['captionsChanged'], 2);
      expect(r.data['dryRun'], isTrue);
      expect(r.data['changed'], isFalse);
      expect(b.projectFile('pod').readAsStringSync(), before);
    });

    test('replace_in_captions for real: every place, one undo step',
        () async {
      final r = await c.ok('replace_in_captions', {
        'project_id': 'pod', 'find': 'sem', 'replace': 'Sam', 'dry_run': false, //
      });
      expect(r.text, startsWith('Replaced "sem" by "Sam" in 3 place(s) in 3 caption(s).'));
      expect(r.data['changed'], isTrue);
      var saved = await b.store.load('pod');
      expect(saved.titles.map((t) => t.text), [
        'Sam: Welcome back',
        'to the\nshow.',
        'Dana: Thanks, Sam.',
        'Samolina is next.',
        'The Sem Show', // a title: left alone
      ]);
      // Times and look did not change.
      expect(saved.titles[2].startMs, 5000);
      final u = await c.ok('undo', {'project_id': 'pod'});
      expect(u.text, contains('Undid "Edited 3 captions"'));
      saved = await b.store.load('pod');
      expect(saved.titles.first.text, 'Sem: Welcome back');
      // Titles too, case-sensitive, a time range.
      await c.ok('replace_in_captions', {
        'project_id': 'pod', 'find': 'Sem', 'replace': 'Sam', 'dry_run': false,
        'include_titles': true, 'case_sensitive': true, 'to_ms': 5000,
      });
      saved = await b.store.load('pod');
      expect(saved.titles.map((t) => t.text), [
        'Sam: Welcome back',
        'to the\nshow.',
        'Dana: Thanks, Sem.',
        'Semolina is next.',
        'The Sam Show',
      ]);
    });

    test('replace_in_captions: nothing found, empty find, emptied captions',
        () async {
      var r = await c.ok('replace_in_captions',
          {'project_id': 'pod', 'find': 'pizza', 'replace': 'bread', 'dry_run': false});
      expect(r.text, contains('No caption contains "pizza"'));
      expect(r.data['changed'], isFalse);
      expect(
          await c.fails('replace_in_captions',
              {'project_id': 'pod', 'find': ' ', 'replace': 'x'}),
          contains('find is empty'));
      await b.seed('one', clips: [b.video('a')], titles: [cap('x', 'um', 0, 1000)]);
      r = await c.ok('replace_in_captions',
          {'project_id': 'one', 'find': 'um', 'replace': '', 'dry_run': false});
      expect(r.text, contains('1 would become empty'));
      expect((await b.store.load('one')).titles.single.text, 'um');
    });
  });

  group('get_speech_map', () {
    late Bench b;
    late Client c;
    late String sam, dana, camera;

    /// A tone that is loud in [loud] (seconds), faint in [faint] (the
    /// other speaker heard through this microphone), nearly silent else.
    void voiceFile(String path, List<(int, int)> loud, List<(int, int)> faint) {
      String any(List<(int, int)> l) =>
          l.map((r) => 'between(t,${r.$1},${r.$2})').join('+');
      ff([
        '-f', 'lavfi', '-i', 'sine=f=220:r=16000:d=24',
        '-af',
        "volume='if(${any(loud)},0.5,if(${any(faint)},0.03,0.0006))':eval=frame",
        '-c:a', 'aac', path,
      ]);
    }

    setUpAll(() async {
      if (!ffmpegOk) return;
      b = Bench();
      c = b.client;
      sam = b.file('audioSam.m4a');
      dana = b.file('audioDana.m4a');
      camera = b.file('zoom.mp4');
      voiceFile(sam, [(1, 5), (12, 18)], [(6, 11)]);
      voiceFile(dana, [(6, 11), (15, 18)], [(1, 5), (12, 15)]);
      makeVideo(camera, seconds: 24);
      final t = DateTime.utc(2026, 1, 2);
      AudioClip voice(String id, String path, String track) => AudioClip(
          id: id, path: path, sourceDurationMs: 24000, startMs: 0, inMs: 0,
          outMs: 24000, trackId: track, sourceClipId: 'a', linked: true,
          syncOffsetMs: 0);
      await b.store.save(Project(
        id: 'talk',
        name: 'Zoom talk',
        createdAt: t,
        updatedAt: t,
        clips: [
          Clip(
              id: 'a', type: ClipType.video, path: camera, sourceDurationMs: 24000,
              inMs: 0, outMs: 24000, width: 640, height: 360, muted: true),
        ],
        tracks: const [
          SoundTrack(id: 'sam', name: 'Sam', speech: true),
          SoundTrack(id: 'dana', name: 'Dana', speech: true),
        ],
        audio: [voice('v1', sam, 'sam'), voice('v2', dana, 'dana')],
      ));
      await b.store.save(Project(
        id: 'solo',
        name: 'Solo',
        createdAt: t,
        updatedAt: t,
        clips: [
          Clip(
              id: 'a', type: ClipType.video, path: sam, sourceDurationMs: 24000,
              inMs: 0, outMs: 24000, width: 640, height: 360),
        ],
      ));
    });
    tearDownAll(() {
      if (ffmpegOk) b.dispose();
    });

    List<(String, int, int)> rows(Reply r) => [
          for (final row in (r.data['rows'] as List).cast<List>())
            (row[2] as String, ((row[0] as int) / 100).round(), ((row[1] as int) / 100).round()),
        ];

    /// Rows as (speaker, start, end) in tenths of a second, compared with
    /// a tenth of slack (the files are AAC: the decoder's own delay).
    void expectRows(Reply r, List<(String, int, int)> want) {
      final got = rows(r);
      expect(got.map((x) => x.$1), want.map((x) => x.$1), reason: r.text);
      for (var i = 0; i < want.length; i++) {
        expect(got[i].$2, closeTo(want[i].$2, 1), reason: r.text);
        expect(got[i].$3, closeTo(want[i].$3, 1), reason: r.text);
      }
    }

    test('speaker turns from the sound; bleed between microphones ignored',
        () async {
      final r = await c.ok('get_speech_map', {'project_id': 'talk'});
      expect(r.text, contains('Who speaks in "Zoom talk"'));
      // Tenths of a second.
      expectRows(r, [
        ('Sam', 10, 50),
        ('Dana', 60, 110),
        ('Sam', 120, 180),
        ('Dana', 150, 180), // both talk: the turns overlap
      ]);
      final speakers = (r.data['speakers'] as List).cast<Map>();
      expect(speakers.map((s) => (s['trackId'], s['name'], s['stretches'])),
          [('sam', 'Sam', 2), ('dana', 'Dana', 2)]);
      expect(speakers[0]['talkMs'], closeTo(10000, 150));
      expect(speakers[1]['talkMs'], closeTo(8000, 150));
      expect(speakers[0]['talkShare'], closeTo(0.556, 0.01));
      expect(r.text, contains('- Sam (track_id sam): talks 0:10 in 2 stretch(es), 56% of the talking, 42% of the video'));
      expect(RegExp(r'^\d+-\d+ \[0:0[01]\] Sam [34]\.\d s$', multiLine: true).hasMatch(r.text),
          isTrue, reason: r.text);
      // The pictures are kept next to the projects folder.
      final kept = Directory(p.join(b.tmp.path, 'ClipForge', 'sound-pictures'))
          .listSync()
          .map((e) => p.basename(e.path))
          .toList();
      expect(kept.length, 2);
      expect(kept.every((n) => n.startsWith('pk_') && n.endsWith('.cfpk')), isTrue);
    }, skip: skipWithoutFfmpeg);

    test('one speaker, a time range, stretches, pages', () async {
      var r = await c.ok('get_speech_map',
          {'project_id': 'talk', 'speaker': 'dana', 'view': 'stretches'});
      expectRows(r, [('Dana', 60, 110), ('Dana', 150, 180)]);
      r = await c.ok('get_speech_map',
          {'project_id': 'talk', 'from_ms': 5500, 'to_ms': 12500});
      expectRows(r, [('Dana', 60, 110), ('Sam', 120, 180)]);
      r = await c.ok('get_speech_map', {'project_id': 'talk', 'limit': 2});
      expect(r.data['nextOffset'], 2);
      expect(r.text, contains('Speaker turns 1-2 of 4'));
      expect(r.text, contains('More: call again with offset 2.'));
      r = await c.ok('get_speech_map', {'project_id': 'talk', 'min_ms': 4500});
      expect(rows(r).map((x) => x.$1), ['Dana', 'Sam']);
      expect(await c.fails('get_speech_map', {'project_id': 'talk', 'speaker': 'Kim'}),
          contains('No speaker "Kim". Speakers: Sam (track_id sam), Dana (track_id dana)'));
    }, skip: skipWithoutFfmpeg);

    test('the map follows a cut', () async {
      await c.ok('duplicate_project', {'project_id': 'talk', 'name': 'Cut'});
      final id = (await b.store.list()).firstWhere((x) => x.name == 'Cut').id;
      // Take 5.5-11.5 s (Dana's first turn) out.
      await c.ok('split_at', {'project_id': id, 'timeline_ms': 11500});
      await c.ok('split_at', {'project_id': id, 'timeline_ms': 5500});
      final clips = (await b.store.load(id)).clips;
      await c.ok('remove_clip', {'project_id': id, 'clip_id': clips[1].id});
      final r = await c.ok('get_speech_map', {'project_id': id});
      // Sam goes on a second after the cut: one turn.
      expectRows(r, [('Sam', 10, 120), ('Dana', 90, 120)]);
      expect(r.data['durationMs'], 18000);
    }, skip: skipWithoutFfmpeg);

    test('without speech tracks the video\'s own sound is the speaker',
        () async {
      final r = await c.ok('get_speech_map', {'project_id': 'solo'});
      expect((r.data['speakers'] as List).single['name'], 'Video');
      // Alone, the microphone also "hears" the faint part.
      expect(rows(r).first.$1, 'Video');
      expect(rows(r).first.$2, closeTo(10, 1));
    }, skip: skipWithoutFfmpeg);

    test('nothing to listen to; no FFmpeg', () async {
      await b.seed('mute', clips: [b.photo('ph')]);
      expect(await c.fails('get_speech_map', {'project_id': 'mute'}),
          contains('has no sound that could be speech'));
      final bare = Bench(ffmpeg: false);
      addTearDown(bare.dispose);
      await bare.seed('x', clips: [bare.video('a')]);
      expect(await bare.client.fails('get_speech_map', {'project_id': 'x'}),
          contains('FFmpeg'));
    }, skip: skipWithoutFfmpeg);
  });

  test('the new tools are announced like the others', () {
    final b = Bench(ffmpeg: false);
    addTearDown(b.dispose);
    final byName = {for (final t in b.tools.tools) t.name: t};
    expect(byName['get_captions']!.readOnly, isTrue);
    expect(byName['get_speech_map']!.readOnly, isTrue);
    expect(byName['replace_in_captions']!.readOnly, isFalse);
    expect(byName['replace_in_captions']!.properties.keys,
        containsAll(['find', 'replace', 'dry_run', 'whole_word', 'detail']));
    expect(byName['get_captions']!.properties.containsKey('detail'), isFalse);
    expect(b.tools.tools.length, 62);
  });
}
