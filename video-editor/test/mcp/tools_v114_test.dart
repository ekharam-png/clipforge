// 1.14 in the Claude tools: suggest_shorts (candidates from a stored
// transcript or from captions: whole sentences only), make_short with the
// Short caption look, a title, snapping and warnings, publishing notes,
// make_chapters, markers, and export_kit as ONE background job (an engine
// that only pretends) that get_export_status and cancel_export cover.
import 'dart:async';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/publish/shorts.dart';
import 'package:clipforge/core/transcript/transcript_store.dart';
import 'package:clipforge/mcp/export_jobs.dart';
import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../media/speech_support.dart';
import 'support.dart';
import 'tools_v19_test.dart' show SlowEngine;

/// A made-up talk: sentences with the pause after each, about three words
/// a second.
const _talk = <(String, int)>[
  ('Why does the first loaf always fail?', 1200),
  ('I baked forty of them before one worked.', 300),
  ('The mistake is always the same.', 300),
  ('You stop kneading too early.', 1800),
  ('So how do you know when to stop?', 400),
  ('You stretch the dough until you can see light through it.', 300),
  ('Bakers call that the window test.', 300),
  ('If it tears, you keep going for another 3 minutes.', 2200),
  ('The oven should be as hot as it goes.', 300),
  ('Put a tray of water on the bottom.', 300),
  ('The steam is what makes the crust.', 2500),
];

Transcript talk(String path) {
  final words = <TranscriptWord>[];
  var at = 500;
  for (final (sentence, pause) in _talk) {
    for (final w in sentence.split(' ')) {
      words.add(TranscriptWord(w, at, at + 280));
      at += 330;
    }
    at += pause;
  }
  return Transcript(
      sourcePath: path,
      audioTrack: 0,
      language: 'en',
      requestedLanguage: 'en',
      model: 'base.en',
      backend: 'whisper-cpp',
      wordTiming: WordTiming.measured,
      durationMs: at,
      createdAt: DateTime.utc(2026),
      segments: segmentsFromWords(words));
}

TitleOverlay cap(String id, String text, int start, int end) => TitleOverlay(
    id: id, text: text, startMs: start, endMs: end, kind: TitleKind.caption);

void main() {
  late Bench b;
  late Client c;
  late SlowEngine engine;

  setUp(() {
    engine = SlowEngine(steps: 3, stepTime: const Duration(milliseconds: 5));
    b = Bench(
        ffmpeg: false,
        exportLauncher: inProcessLauncher(() async => engine, needsFfmpeg: false),
        speech: (root) =>
            TranscriptionService(rootDir: root, host: FakeHost(), appVersion: 'test'));
    c = b.client;
  });
  tearDown(() => b.dispose());

  Future<void> seedTalk() async {
    final clip = b.video('a', source: 60000);
    await b.seed('talk', name: 'Bread talk', clips: [clip]);
    await TranscriptStore.ofProject(p.join(b.store.rootPath, 'talk'))
        .save(talk(clip.path));
  }

  group('suggest_shorts', () {
    test('candidates from the transcript: whole sentences, signals, paging; '
        'it judges nothing', () async {
      await seedTalk();
      final r = await c.ok('suggest_shorts', {
        'project_id': 'talk',
        'min_seconds': 8,
        'max_seconds': 25,
        'loudness': false,
      });
      expect(r.text, contains('from its transcript'));
      expect(r.text, contains('CANDIDATES, not recommendations'));
      expect(r.text, contains('starts at the beginning of a sentence'));
      final rows = (r.data['candidates'] as List).cast<Map>();
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final text = row['text'] as String;
        expect(RegExp(r'[.?!]$').hasMatch(text), isTrue, reason: text);
        expect(text[0], text[0].toUpperCase(), reason: text);
        expect(row['seconds'], inInclusiveRange(8, 25));
        expect(row['completeSentences'], isTrue);
        expect((row['toMs'] as int) > (row['fromMs'] as int), isTrue);
      }
      expect(rows.first['text'], startsWith('Why does the first loaf always fail?'));
      expect(rows.first['text'], endsWith('You stop kneading too early.'));
      expect(rows.first['startsWithQuestion'], isTrue);
      expect(rows.first['hasNumbers'], isTrue);
      expect(rows.first['pauseBefore'], isTrue);
      expect(r.text, contains('starts with a question, figures, stands by itself'));
      // Nothing was saved, and no project is in the answer.
      expect(r.data.containsKey('project'), isFalse);
      // Pages.
      final one = await c.ok('suggest_shorts', {
        'project_id': 'talk', 'min_seconds': 8, 'max_seconds': 25, //
        'limit': 1, 'loudness': false,
      });
      expect(one.data['count'], 1);
      expect(one.data['nextOffset'], 1);
      expect(one.text, contains('More: call again with offset 1.'));
      final none = await c.ok('suggest_shorts', {
        'project_id': 'talk', 'min_seconds': 500, 'max_seconds': 600, 'loudness': false, //
      });
      expect(none.data['total'], 0);
      expect(none.text, contains('Nothing fits'));
      expect(
          await c.fails('suggest_shorts',
              {'project_id': 'talk', 'min_seconds': 30, 'max_seconds': 20}),
          contains('must not be less'));
    });

    test('without a transcript it reads the captions; without any text it '
        'says what to do', () async {
      await b.seed('pod', name: 'Podcast', clips: [
        b.video('a', source: 120000)
      ], titles: [
        cap('c1', 'Sam: Why does the first loaf', 1000, 3000),
        cap('c2', 'always fail?', 3050, 5000),
        cap('c3', 'I baked forty of them before one worked.', 5100, 9000),
        cap('c4', 'Dana: So how do you know when to stop?', 11000, 14000),
        cap('c5', 'Sam: You stretch the dough until', 14100, 17000),
        cap('c6', 'you can see light through it.', 17050, 20000),
      ]);
      final r = await c.ok('suggest_shorts', {
        'project_id': 'pod', 'min_seconds': 5, 'max_seconds': 12, 'loudness': false, //
      });
      expect(r.data['source'], 'captions');
      final rows = (r.data['candidates'] as List).cast<Map>();
      expect(rows.first['text'],
          'Why does the first loaf always fail? I baked forty of them before one worked.');
      expect(rows.first['speakers'], ['Sam']);
      expect((rows.first['fromMs'], rows.first['toMs']), (1000, 9000));
      expect(await c.fails('suggest_shorts', {'project_id': 'pod', 'source': 'transcript'}),
          contains('no transcript'));
      await b.seed('bare', clips: [b.video('x')]);
      expect(await c.fails('suggest_shorts', {'project_id': 'bare'}),
          allOf(contains('no transcript and no captions'), contains('transcribe')));
    });
  });

  group('make_short', () {
    test('caption_style short, a title, snapping to pauses', () async {
      await seedTalk();
      // 6.2 s is inside "worked."; 13 s is inside the second passage.
      final words = talk('x').segments.expand((s) => s.words).toList();
      final first = words.first.startMs;
      final lastOfFirstPassage =
          words.firstWhere((w) => w.text == 'early.').endMs;
      final r = await c.ok('make_short', {
        'project_id': 'talk',
        'from_ms': first + 400,
        'to_ms': lastOfFirstPassage - 500,
        'caption_style': 'short',
        'title': 'Why the first loaf fails',
        'snap_to_speech': true,
        'name': 'Loaf short',
      });
      expect(r.text, contains('Moved outward to the pauses'));
      expect(r.data['fromMs'], lessThanOrEqualTo(first));
      expect(r.data['toMs'], greaterThanOrEqualTo(lastOfFirstPassage));
      expect(r.data['captionStyle'], 'short');
      expect(r.data.containsKey('warnings'), isFalse, reason: r.text);
      final short = await b.store.load(r.data['newProjectId'] as String);
      expect(short.aspect, CanvasAspect.portrait9x16);
      final captions = short.titles.where((t) => t.kind == TitleKind.caption).toList();
      expect(captions, isNotEmpty);
      for (final t in captions) {
        expect(t.fontSize, ShortLook.captionFontSize);
        expect(t.outline, isTrue);
        expect(t.text.split('\n').length, lessThanOrEqualTo(2));
      }
      final top = short.titles.singleWhere((t) => t.kind == TitleKind.title);
      expect(top.text, 'Why the first loaf fails');
      expect((top.startMs, top.endMs), (0, short.durationMs));
      expect(r.text, contains('"Short" look'));
      // The long project keeps its (empty) notes and is untouched.
      expect((await b.store.load('talk')).titles, isEmpty);
    });

    test('warns: starts or ends mid-sentence, longer than is safe', () async {
      await seedTalk();
      final words = talk('x').segments.expand((s) => s.words).toList();
      final mid = words[3].startMs - 20; // "first loaf always fail?"
      var r = await c.ok('make_short', {
        'project_id': 'talk', 'from_ms': mid, 'to_ms': words[10].endMs + 10, //
      });
      final warnings = (r.data['warnings'] as List).join('\n');
      expect(warnings, contains('starts in the middle of a sentence'));
      expect(warnings, contains('ends before its last sentence is finished'));
      // A long one.
      await b.seed('long', name: 'Long', clips: [b.video('l', source: 200000)]);
      r = await c.ok('make_short', {'project_id': 'long', 'from_ms': 0, 'to_ms': 95000});
      expect((r.data['warnings'] as List).single,
          allOf(contains('1:35'), contains('60 s'), contains('check the site')));
    });
  });

  group('publishing notes', () {
    test('set, read, change one field, undo; chapters are checked', () async {
      await b.seed('pod', name: 'Podcast', clips: [b.video('a', source: 600000)]);
      var r = await c.ok('get_publishing_notes', {'project_id': 'pod'});
      expect(r.data['empty'], isTrue);
      expect(r.text, contains('no publishing notes yet'));
      r = await c.ok('set_publishing_notes', {
        'project_id': 'pod',
        'title': 'Why the first loaf fails',
        'description': 'Sam explains the window test.',
        'hashtags': '#bread, baking',
        'chapters': '0:00 Start\n1:02 The window test\n4:30 The oven',
      });
      expect(r.text, contains('Updated the publishing notes'));
      var p0 = await b.store.load('pod');
      expect(p0.publishing.title, 'Why the first loaf fails');
      expect(p0.publishing.hashtags, ['bread', 'baking']);
      expect(p0.publishing.chapters.map((c) => c.ms), [0, 62000, 270000]);
      // Only what is given changes.
      r = await c.ok('set_publishing_notes',
          {'project_id': 'pod', 'short_title': 'The window test', 'hashtags': ''});
      p0 = await b.store.load('pod');
      expect(p0.publishing.title, 'Why the first loaf fails');
      expect(p0.publishing.shortTitle, 'The window test');
      expect(p0.publishing.hashtags, isEmpty);
      r = await c.ok('get_publishing_notes', {'project_id': 'pod'});
      expect(r.text, contains('TITLE\nWhy the first loaf fails'));
      expect(r.text, contains('CHAPTERS\n0:00 Start\n1:02 The window test'));
      expect((r.data['notes'] as Map)['shortTitle'], 'The window test');
      expect(r.data['textFileName'], 'Podcast - text.txt');
      // A list that breaks the rules is saved, with a warning.
      r = await c.ok('set_publishing_notes',
          {'project_id': 'pod', 'chapters': '0:05 Late\n0:09 Too soon'});
      expect((r.data['warnings'] as List).single, contains('must start at 0:00'));
      expect(await c.fails('set_publishing_notes', {'project_id': 'pod', 'chapters': 'no times'}),
          contains('m:ss Title'));
      expect(await c.fails('set_publishing_notes', {'project_id': 'pod'}),
          contains('at least one'));
      // Claude's own undo covers it.
      await c.ok('undo', {'project_id': 'pod'});
      expect((await b.store.load('pod')).publishing.chapters.length, 3);
    });

    test('make_chapters: from titles; dry run; existing ones need replace',
        () async {
      await b.seed('pod', name: 'Podcast', clips: [
        b.video('a', source: 600000)
      ], titles: const [
        TitleOverlay(id: 't1', text: 'Welcome', startMs: 1000, endMs: 4000),
        TitleOverlay(id: 't2', text: 'The dough', startMs: 60000, endMs: 63000),
        TitleOverlay(id: 't3', text: 'The oven', startMs: 185000, endMs: 188000),
      ]);
      var r = await c.ok('make_chapters', {'project_id': 'pod', 'dry_run': true});
      expect(r.text, contains('DRY RUN'));
      expect(r.text, contains('0:00 Welcome\n1:00 The dough\n3:05 The oven'));
      expect(r.data['source'], 'titles');
      expect((await b.store.load('pod')).publishing.chapters, isEmpty);
      r = await c.ok('make_chapters', {'project_id': 'pod'});
      expect((await b.store.load('pod')).publishing.chapters.length, 3);
      expect(await c.fails('make_chapters', {'project_id': 'pod'}),
          contains('already have 3 chapter(s)'));
      await c.ok('make_chapters', {'project_id': 'pod', 'replace': true});
      // Captions when there are no titles.
      await b.seed('caps', clips: [
        b.video('c', source: 120000)
      ], titles: [
        cap('c1', 'Sam: Why does the first loaf fail?', 500, 3000),
        cap('c2', 'Dana: Because of the oven.', 40000, 43000),
        cap('c3', 'Sam: And the salt.', 90000, 93000),
      ]);
      r = await c.ok('make_chapters', {'project_id': 'caps', 'dry_run': true});
      expect(r.data['source'], 'captions');
      expect(r.text, contains('rewrite them'));
      await b.seed('bare', clips: [b.video('x')]);
      expect(await c.fails('make_chapters', {'project_id': 'bare'}),
          contains('No chapters could be made'));
    });
  });

  group('markers', () {
    test('add, list with the part a short would take, remove', () async {
      await seedTalk();
      var r = await c.ok('list_markers', {'project_id': 'talk'});
      expect(r.text, contains('no good-moment markers'));
      r = await c.ok('add_marker', {'project_id': 'talk', 'at_ms': 22000, 'label': 'window test'});
      final id = r.data['markerId'] as String;
      expect((await b.store.load('talk')).markers.single.ms, 22000);
      expect(await c.fails('add_marker', {'project_id': 'talk', 'at_ms': 999000}),
          contains('after the end'));
      r = await c.ok('list_markers', {'project_id': 'talk'});
      final row = ((r.data['markers'] as List).single as Map);
      expect(row['markerId'], id);
      expect(row['label'], 'window test');
      expect(row['shortFromMs'], lessThanOrEqualTo(2000));
      expect(row['shortToMs'], greaterThanOrEqualTo(47000));
      expect(r.text, contains('said there: "'));
      expect(await c.fails('remove_marker', {'project_id': 'talk', 'marker_id': 'nope'}),
          contains('No marker "nope"'));
      await c.ok('add_marker', {'project_id': 'talk', 'at_ms': 5000});
      r = await c.ok('remove_marker', {'project_id': 'talk', 'marker_id': 'all'});
      expect(r.data['removed'], 2);
      expect((await b.store.load('talk')).markers, isEmpty);
    });
  });

  group('export_kit', () {
    test('one job makes every file and the text files; the status tool '
        'covers it', () async {
      await b.seed('long', name: 'Bread talk', clips: [b.video('a', source: 95000)]);
      await b.seed('short', name: 'Bread tip', clips: [
        b.video('s', file: 'tip.mp4', source: 20000)
      ]);
      await c.ok('set_publishing_notes',
          {'project_id': 'long', 'title': 'Why the first loaf fails'});
      final folder = b.file('kit');
      final r = await c.call('export_kit', {
        'project_id': 'long',
        'destinations': ['youtube', 'whatsapp', 'podcast'],
        'projects': [
          {'project_id': 'short', 'destinations': ['shorts']},
        ],
        'output_dir': folder,
      }, 'tok');
      expect(r.isError, isFalse, reason: r.text);
      expect(r.data['status'], 'finished');
      expect(r.data['kit'], isTrue);
      expect(r.data['folder'], folder);
      final names = Directory(folder).listSync().map((e) => p.basename(e.path)).toList()
        ..sort();
      expect(names, [
        'Bread talk - WhatsApp.mp4',
        'Bread talk - YouTube.mp4',
        'Bread talk - audio.mp3',
        'Bread talk - text.txt',
        'Bread tip - Short 9x16.mp4',
        'Bread tip - text.txt',
      ]);
      final files = (r.data['files'] as List).cast<Map>();
      expect(files.map((f) => f['destination']), ['youtube', 'whatsapp', 'podcast', 'shorts']);
      expect(files.every((f) => (f['sizeBytes'] as int) > 0), isTrue);
      expect(r.text, contains('The publishing kit is ready in:\n$folder'));
      expect(r.text, contains('ClipForge does not post'));
      // The short's export was upright, from a copy in memory.
      expect((await b.store.list()).length, 2, reason: 'no project was added');
      expect(File(p.join(folder, 'Bread talk - text.txt')).readAsStringSync(),
          contains('TITLE\nWhy the first loaf fails'));
      // One job; get_export_status knows it.
      final id = r.data['jobId'] as String;
      final status = await c.ok('get_export_status', {'job_id': id});
      expect(status.data['kit'], isTrue);
      expect((status.data['files'] as List).length, 4);
      expect(b.tools.jobs.kitFileOf(id).existsSync(), isFalse);
      final recent = await c.ok('get_export_status');
      expect(recent.text, contains(id));
      // The same folder again needs overwrite.
      expect(
          await c.fails('export_kit', {
            'project_id': 'long', 'destinations': ['youtube'], 'output_dir': folder, //
          }),
          contains('overwrite true'));
    });

    test('warnings up front, unknown destinations, and cancel', () async {
      await b.seed('long', name: 'Bread talk', clips: [b.video('a', source: 95000)]);
      expect(
          await c.fails('export_kit', {'project_id': 'long', 'destinations': ['vimeo']}),
          allOf(contains('Unknown destination "vimeo"'), contains('youtube')));
      expect(await c.fails('export_kit', {'project_id': 'long', 'destinations': []}),
          contains('at least one destination'));
      engine.gate = Completer<void>();
      final r = await c.call('export_kit', {
        'project_id': 'long',
        'destinations': ['shorts', 'youtube'],
        'output_dir': b.file('kit2'),
        'wait_seconds': 0,
      });
      expect(r.data['status'], anyOf('starting', 'running'));
      expect((r.data['warnings'] as List).single,
          allOf(contains('Short 9x16.mp4'), contains('1:35'), contains('Check the site')));
      expect((r.data['planned'] as List).first,
          contains('a temporary copy in this shape'));
      final id = r.data['jobId'] as String;
      final stopping = c.ok('cancel_export', {'job_id': id});
      // The job looks for the request once a second.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      engine.gate!.complete();
      final stopped = await stopping;
      expect(stopped.data['status'], 'cancelled');
      expect(stopped.text, contains('was cancelled'));
    });
  });
}
