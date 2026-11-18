// 1.11 in the Claude tools: transcribe as a background job (fake speech
// programs, recorded-style results), no download without download_pack,
// get_transcript (compact, paged, both time bases, after edits),
// find_in_transcript, captions_from_transcript, remove_fillers (dry run by
// default), make_short, and what get_status says about speech-to-text.
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/transcript/transcript_store.dart';
import 'package:clipforge/mcp/transcribe_jobs.dart';
import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../media/speech_support.dart';
import 'support.dart';

/// A long talk as a stored transcript: [words] words, one every 430 ms.
Transcript longTalk(String path, int words) {
  final list = <TranscriptWord>[];
  for (var i = 0; i < words; i++) {
    final end = i % 9 == 8 ? '.' : '';
    list.add(TranscriptWord('word$i$end', i * 430, i * 430 + 330));
  }
  return Transcript(
      sourcePath: path,
      audioTrack: 0,
      language: 'en',
      requestedLanguage: 'en',
      model: 'base.en',
      backend: 'whisper-cpp',
      wordTiming: WordTiming.measured,
      durationMs: words * 430,
      createdAt: DateTime.utc(2026),
      segments: segmentsFromWords(list));
}

void main() {
  late Bench b;
  late Client c;
  late FakeHost host;

  Bench bench(void Function(FakeHost h) setUp, {List<String> packs = const ['base']}) {
    host = FakeHost();
    setUp(host);
    final made = Bench(speech: (root) {
      for (final id in packs) {
        installPack(root, id);
      }
      return TranscriptionService(rootDir: root, host: host, appVersion: 'test');
    });
    b = made;
    c = made.client;
    return made;
  }

  tearDown(() => b.dispose());

  String dirOf(String id) => p.join(b.store.rootPath, id);

  Future<void> russianTalk({bool cpp = true}) async {
    bench((h) {
      h.addFfmpeg();
      if (cpp) h.addWhisperCpp();
    });
    await b.seed('talk',
        name: 'Talk', clips: [b.video('a', source: cpp ? 12000 : 22000)]);
  }

  group('get_status', () {
    test('lists the speech programs, packs and what can be downloaded',
        () async {
      await russianTalk();
      final r = await c.ok('get_status');
      expect(r.text, contains('Speech-to-text (transcribe): 2 program(s) found'));
      expect(r.text, contains('whisper-cpp'));
      expect(r.text, contains('word times estimated from phrases'));
      final t = (r.data['transcription'] as Map).cast<String, dynamic>();
      expect([for (final x in t['backends'] as List) (x as Map)['id']],
          ['whisper-cpp', 'ffmpeg-whisper']);
      expect(((t['packs'] as List).single as Map)['id'], 'base');
      expect((t['availablePacks'] as List).length, 5);
      expect(t['modelsDir'], endsWith('models'));
    });

    test('nothing installed: says what is needed', () async {
      bench((h) {}, packs: const []);
      final r = await c.ok('get_status');
      expect(r.text, contains('NO speech program found'));
      expect(r.text, contains('whisper.cpp'));
      expect(r.text, contains('none yet'));
    });
  });

  group('transcribe', () {
    test('no speech program: a plain explanation, no job', () async {
      bench((h) {}, packs: const []);
      await b.seed('talk', clips: [b.video('a')]);
      final text = await c.fails('transcribe', {'project_id': 'talk'});
      expect(text, contains('needs a speech program'));
      expect(b.tools.transcribeJobs.list(), isEmpty);
    });

    test('never downloads by itself: names the pack and its size', () async {
      bench((h) => h.addFfmpeg(), packs: const []);
      await b.seed('talk', clips: [b.video('a')]);
      var text = await c.fails('transcribe', {'project_id': 'talk', 'language': 'ru'});
      expect(text, contains('No language pack for Russian speech'));
      expect(text, contains('Small (about 140 MB'));
      expect(text, contains('Medium (about 470 MB'));
      expect(text, contains('Large (about 1.6 GB'));
      expect(text, contains('download_pack true'));
      expect(text, contains('Ask the user first'));
      text = await c.fails('transcribe',
          {'project_id': 'talk', 'language': 'en', 'quality': 'medium'});
      expect(text, contains('"English only, medium" (about 470 MB'));
      expect(text, contains('ggml-small.en.bin'));
      expect(text, contains('Nothing was downloaded'));
      expect(host.started, isEmpty);
      expect(b.tools.transcribeJobs.list(), isEmpty);
      expect(Directory(p.join(b.tmp.path, 'ClipForge', 'models')).existsSync(), isFalse);
    });

    test('with download_pack the pack is fetched (local test server), '
        'checked and used', () async {
      final data = List.generate(50000, (i) => i % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.contentLength = data.length;
        req.response.add(data);
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      bench((h) => h.addFfmpeg(), packs: const []);
      final models = p.join(b.tmp.path, 'ClipForge', 'models');
      Directory(models).createSync(recursive: true);
      File(p.join(models, 'models.json')).writeAsStringSync(jsonEncode([
        {
          'id': 'base',
          'fileName': 'ggml-base.bin',
          'url': 'http://127.0.0.1:${server.port}/ggml-base.bin',
          'sha256': sha256.convert(data).toString(),
          'sizeBytes': data.length,
          'sizeLabel': 'about 140 MB',
          'title': 'All languages, small',
          'size': 'small',
        }
      ]));
      await b.seed('talk', clips: [b.video('a', source: 21000)]);
      final r = await c.ok('transcribe', {
        'project_id': 'talk',
        'language': 'ru',
        'quality': 'small',
        'download_pack': true,
      });
      expect(r.data['status'], 'finished');
      expect(File(p.join(models, 'ggml-base.bin')).lengthSync(), data.length);
      expect(r.data['words'], greaterThan(10));
    });

    test('runs as a job, stores one transcript per file in the project '
        'folder, and is a cache hit the second time', () async {
      await russianTalk();
      final before = b.projectFile('talk').readAsStringSync();
      final r = await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      expect(r.data['status'], 'finished');
      expect(r.data['backend'], 'whisper-cpp');
      expect(r.data['wordTimes'], 'measured');
      expect(r.data['words'], 20);
      expect(r.text, contains('Transcribed "Talk": 20 words'));
      // Not in project.json; its own file in the project folder.
      expect(b.projectFile('talk').readAsStringSync(), before);
      final files = Directory(p.join(dirOf('talk'), 'transcripts')).listSync();
      expect(files.length, 1);
      final stored = jsonDecode((files.single as File).readAsStringSync()) as Map;
      expect(stored['language'], 'ru');
      expect(stored['backend'], 'whisper-cpp');
      expect(stored['model'], 'base');
      // Again: nothing runs.
      final runs = host.started.length;
      final again = await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      expect(again.data['alreadyTranscribed'], isTrue);
      expect(host.started.length, runs);
      // Other settings, or force: it runs again.
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru', 'force': true});
      expect(host.started.length, greaterThan(runs));
      final status = await c.ok('get_transcribe_status');
      expect((status.data['jobs'] as List).length, 2);
    });

    test('a long file does not block the call: job id at once, progress, '
        'then finished', () async {
      bench((h) {
        h.addFfmpeg();
        h.addWhisperCpp(runFor: const Duration(milliseconds: 1500));
      });
      await b.seed('talk', name: 'Talk', clips: [b.video('a', source: 12000)]);
      final watch = Stopwatch()..start();
      final started = await c.ok('transcribe',
          {'project_id': 'talk', 'language': 'ru', 'wait_seconds': 0});
      expect(watch.elapsedMilliseconds, lessThan(1200));
      expect(started.data['status'], anyOf('starting', 'running'));
      final id = started.data['job_id'] as String;
      expect(started.text, contains('get_transcribe_status'));
      // The project can be read and edited meanwhile.
      await c.ok('get_project', {'project_id': 'talk'});
      final done = await c.call('get_transcribe_status',
          {'job_id': id, 'wait_seconds': 20}, 'tok');
      expect(done.data['status'], 'finished');
      expect(done.data['percent'], 100);
      expect(
          c.notifications.where((n) => n['method'] == 'notifications/progress'),
          isNotEmpty);
      expect(await c.fails('get_transcribe_status', {'job_id': 'nope'}),
          contains('no transcribe job'));
    });

    test('cancel stops it; a job whose process died reads as lost', () async {
      bench((h) {
        h.addFfmpeg();
        h.addWhisperCpp(runFor: const Duration(seconds: 30));
      });
      await b.seed('talk', clips: [b.video('a', source: 12000)]);
      final started = await c.ok('transcribe',
          {'project_id': 'talk', 'language': 'ru', 'wait_seconds': 0});
      final id = started.data['job_id'] as String;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final cancelled = await c.ok('cancel_transcribe', {'job_id': id});
      expect(cancelled.data['status'], 'cancelled');
      expect(Directory(p.join(dirOf('talk'), 'transcripts')).existsSync(), isFalse);
      // Lost.
      final old = DateTime.now().subtract(const Duration(minutes: 5));
      b.tools.transcribeJobs.write(TranscribeJobRecord(
          id: 'lost1',
          projectId: 'talk',
          projectName: 'talk',
          projectDir: dirOf('talk'),
          rootDir: b.tools.speechRoot,
          language: 'ru',
          quality: 'auto',
          backend: 'auto',
          force: false,
          downloadPack: false,
          createdAt: old,
          items: [
            TranscribeItem(path: '/x.mp4', audioTrack: 0, speaker: '', durationMs: 1)
          ],
          status: 'running',
          heartbeatAt: old,
          workerPid: 999999999,
          host: 'another-computer'));
      final lost = await c.call('get_transcribe_status', {'job_id': 'lost1'});
      expect(lost.isError, isTrue);
      expect(lost.data['status'], 'lost');
    });

    test('a photo-only project has nothing to transcribe', () async {
      bench((h) => h.addFfmpeg());
      await b.seed('pics', clips: [b.photo('ph')]);
      expect(await c.fails('transcribe', {'project_id': 'pics'}),
          contains('nothing to transcribe'));
      expect(await c.fails('get_transcript', {'project_id': 'pics'}),
          contains('no speech to read'));
    });
  });

  group('reading', () {
    test('before transcribing: says to transcribe first', () async {
      await russianTalk();
      expect(await c.fails('get_transcript', {'project_id': 'talk'}),
          contains('call transcribe'));
      expect(
          await c.fails('find_in_transcript', {'project_id': 'talk', 'phrase': 'x'}),
          contains('call transcribe'));
    });

    test('text by default; segments; words; a range; source time', () async {
      await russianTalk();
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      final text = await c.ok('get_transcript', {'project_id': 'talk'});
      expect(text.text, contains('TIMELINE time'));
      expect(text.text, contains('language Russian'));
      expect(text.text, contains('320-1300 [0:00] Привет, друзья!'));
      expect(text.text, contains('10000-11200 [0:10] Потом вы ждёте.'));
      expect(text.data['total'], 4);
      expect(text.data.containsKey('segments'), isFalse);
      final segs = await c.ok('get_transcript',
          {'project_id': 'talk', 'format': 'segments', 'limit': 2});
      expect(segs.data['count'], 2);
      expect(segs.data['nextOffset'], 2);
      expect(((segs.data['segments'] as List).first as Map)['text'], 'Привет, друзья!');
      final rest = await c.ok('get_transcript',
          {'project_id': 'talk', 'format': 'segments', 'offset': 2});
      expect(rest.data['count'], 2);
      expect(rest.data.containsKey('nextOffset'), isFalse);
      final words = await c.ok('get_transcript', {
        'project_id': 'talk',
        'format': 'words',
        'from_ms': 4000,
        'to_ms': 5000,
      });
      expect(words.data['words'], [
        ['Э-э,', 4200, 4650],
        ['ну,', 4700, 4900],
        ['сначала', 4950, 5500],
      ]);
      expect(words.text, contains('4200-4650:Э-э,'));
      // Trim the first 4 s away: the timeline moves, the source does not.
      await c.ok('trim_clip', {'project_id': 'talk', 'clip_id': 'a', 'in_ms': 4000});
      final moved = await c.ok('get_transcript', {'project_id': 'talk'});
      expect(moved.text, isNot(contains('Привет')));
      expect(moved.text, contains('200-3900 [0:00] Э-э, ну, сначала'));
      final source = await c.ok('get_transcript',
          {'project_id': 'talk', 'time_base': 'source'});
      expect(source.text, contains('SOURCE time'));
      expect(source.text, contains('320-1300 [0:00] Привет, друзья!'));
      expect(await c.fails('get_transcript',
              {'project_id': 'talk', 'from_ms': 500, 'to_ms': 100}),
          contains('must be after'));
    });

    test('a 25-minute talk is compact and pages', () async {
      bench((h) => h.addFfmpeg());
      final clip = b.video('a', source: 1505000);
      await b.seed('long', clips: [clip]);
      await TranscriptStore.ofProject(dirOf('long')).save(longTalk(clip.path, 3500));
      final r = await c.ok('get_transcript', {'project_id': 'long'});
      // 3500 words in 389 phrases: one answer, far below what a full
      // project listing costs.
      expect(r.data['total'], 389);
      expect(r.data['count'], 389);
      expect(r.text.length, lessThan(45000));
      expect(jsonEncode(r.result).length, lessThan(50000));
      final page = await c.ok('get_transcript', {'project_id': 'long', 'limit': 100});
      expect(page.data['nextOffset'], 100);
      expect(page.text, contains('More: call again with offset 100'));
      final words = await c.ok('get_transcript', {'project_id': 'long', 'format': 'words'});
      expect(words.data['count'], 500);
      expect(words.data['total'], 3500);
      final part = await c.ok('get_transcript',
          {'project_id': 'long', 'from_ms': 600000, 'to_ms': 660000});
      expect(part.data['total'], lessThan(20));
    });

    test('find a phrase: places with times and the words around', () async {
      await russianTalk();
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      final r = await c.ok('find_in_transcript',
          {'project_id': 'talk', 'phrase': 'нужна МУКА'});
      expect(r.data['count'], 1);
      final hit = (r.data['hits'] as List).single as Map;
      expect([hit['startMs'], hit['endMs'], hit['clipId']], [5500, 6350, 'a']);
      expect(hit['context'], contains('сначала нужна мука, вода'));
      final none = await c.ok('find_in_transcript',
          {'project_id': 'talk', 'phrase': 'пицца'});
      expect(none.data['count'], 0);
      expect(none.text, contains('is not said'));
      final prefix = await c.ok('find_in_transcript',
          {'project_id': 'talk', 'phrase': 'хлеб', 'prefix': true});
      expect(prefix.data['count'], 1);
    });
  });

  group('captions_from_transcript', () {
    test('dry run lists them; then one edit; replace_existing', () async {
      await russianTalk();
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      final dry = await c.ok('captions_from_transcript',
          {'project_id': 'talk', 'dry_run': true, 'max_line_chars': 32});
      expect(dry.text, startsWith('DRY RUN'));
      final listed = (dry.data['captions'] as List).cast<Map>();
      expect(listed.first['text'], 'Привет, друзья!');
      // The hesitation sound is left out of the text.
      expect(listed.any((x) => '${x['text']}'.contains('Э-э')), isFalse);
      for (final x in listed) {
        for (final line in '${x['text']}'.split('\n')) {
          expect(line.length, lessThanOrEqualTo(32));
        }
      }
      expect((await b.store.load('talk')).titles, isEmpty);
      final real = await c.ok('captions_from_transcript', {'project_id': 'talk'});
      expect(real.data['captionCount'], listed.length);
      var saved = await b.store.load('talk');
      expect(saved.titles.length, listed.length);
      expect(saved.titles.every((t) => t.kind == TitleKind.caption), isTrue);
      // Again without replacing: warned.
      final twice = await c.ok('captions_from_transcript', {'project_id': 'talk'});
      expect(twice.text, contains('already in that part'));
      final replaced = await c.ok('captions_from_transcript', {
        'project_id': 'talk',
        'replace_existing': true,
        'position': 'top',
        'keep_filler_sounds': true,
      });
      saved = await b.store.load('talk');
      expect(saved.titles.length, replaced.data['captionCount']);
      expect(saved.titles.any((t) => t.text.contains('Э-э')), isTrue);
      expect(saved.titles.first.y, lessThan(0.3));
      await c.ok('undo', {'project_id': 'talk'});
      expect((await b.store.load('talk')).titles.length, 2 * listed.length);
    });

    test('Hebrew captions keep reading order (drawn right to left)', () async {
      bench((h) => h.addPythonWhisper());
      host.dirs['/home/me/.cache/huggingface/hub'] = ['models--Systran--faster-whisper-base'];
      await b.seed('he', clips: [b.video('a', source: 11000)]);
      await c.ok('transcribe', {'project_id': 'he', 'language': 'he'});
      await c.ok('captions_from_transcript', {'project_id': 'he'});
      final titles = (await b.store.load('he')).titles;
      expect(titles.first.text, 'שלום חברים, ברוכים הבאים!');
      expect(titles[1].text, 'היום נדבר על לחם.');
      expect(titles.last.text, 'קודם צריך קמח, מים ומלח.');
    });
  });

  group('remove_fillers', () {
    test('dry run and Light by default; then cuts in one step; the cut is '
        'logged and can be put back', () async {
      await russianTalk();
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      // "Э-э," is followed by the next word after 50 ms: Light leaves a
      // filler that is glued to speech.
      final light = await c.ok('remove_fillers', {'project_id': 'talk'});
      expect(light.text, startsWith('DRY RUN'));
      expect(light.data['strength'], 'light');
      expect([light.data['found'], light.data['fillerCount']], [1, 0]);
      expect(light.data['skippedTooSmall'], 1);
      expect(light.text, contains('Would remove 0 of 1 filler word(s)'));
      expect(light.text, contains('too short or inside fast speech'));

      final dry = await c.ok('remove_fillers',
          {'project_id': 'talk', 'strength': 'normal'});
      expect(dry.text, startsWith('DRY RUN'));
      expect(dry.text, contains('Would remove 1 of 1 filler word(s)'));
      expect(dry.text, contains('cut(s) a minute'));
      expect(dry.text, contains('Tell the user these numbers'));
      expect(dry.data['fillerCount'], 1);
      expect(dry.data['cutsPerMinute'], 5.0);
      expect((dry.data['riskiest'] as List).single['startMs'], 4200);
      expect(((dry.data['groups'] as List).single as Map)['filler'], 'э-э');
      expect((dry.data['rules'] as Map)['minDistanceMs'], 1500);
      expect((await b.store.load('talk')).clips.length, 1);
      final withWords = await c.ok('remove_fillers', {
        'project_id': 'talk',
        'include_word_fillers': true,
        'strength': 'strong',
        'min_distance_ms': 0,
      });
      expect([for (final g in withWords.data['groups'] as List) (g as Map)['filler']],
          containsAll(['э-э', 'ну', 'как бы']));
      // Strong keeps cuts 0.7 s apart: "ну" right after "э-э" is left.
      final strong = await c.ok('remove_fillers', {
        'project_id': 'talk',
        'include_word_fillers': true,
        'strength': 'strong',
      });
      expect(strong.data['skippedTooClose'], greaterThanOrEqualTo(1));

      final real = await c.ok('remove_fillers',
          {'project_id': 'talk', 'strength': 'normal', 'dry_run': false});
      expect(real.text, contains('Removed 1 of 1 filler word(s)'));
      expect(real.text, contains('restore_cut'));
      var saved = await b.store.load('talk');
      expect(saved.clips.length, 2);
      expect(saved.durationMs, 12000 - (real.data['totalMs'] as int));
      final after = await c.ok('get_transcript', {'project_id': 'talk'});
      expect(after.text, isNot(contains('Э-э')));
      expect(after.text, contains('ну, сначала'));

      // The log.
      final cut = saved.autoCuts.single;
      expect([cut.kind, cut.word, cut.by], ['filler', 'э-э', 'claude']);
      expect((real.data['cutIds'] as List).single, cut.id);
      final list = await c.ok('list_auto_cuts', {'project_id': 'talk'});
      expect(list.data['count'], 1);
      expect(list.text, contains('filler "э-э"'));
      final row = (list.data['cuts'] as List).single as Map;
      expect([row['id'], row['sourceStartMs'], row['sourceEndMs']],
          [cut.id, cut.startMs, cut.endMs]);

      // Put it back: one clip again, the whole talk is there.
      final dryBack = await c.ok('restore_cut',
          {'project_id': 'talk', 'cut_id': cut.id, 'dry_run': true});
      expect(dryBack.text, startsWith('DRY RUN'));
      final back = await c.ok('restore_cut', {'project_id': 'talk', 'cut_id': cut.id});
      expect(back.data['how'], 'healed');
      saved = await b.store.load('talk');
      expect([saved.clips.length, saved.durationMs], [1, 12000]);
      expect(saved.autoCuts, isEmpty);
      expect((await c.ok('get_transcript', {'project_id': 'talk'})).text,
          contains('Э-э'));
      expect(await c.fails('restore_cut', {'project_id': 'talk', 'cut_id': 'nope'}),
          contains('no automatic cut'));

      // Own list; "all" puts everything back.
      final own = await c.ok('remove_fillers', {
        'project_id': 'talk',
        'fillers': ['потом', 'сегодня'],
        'strength': 'strong',
        'dry_run': false,
      });
      expect(own.data['fillerCount'], 2);
      expect((await b.store.load('talk')).autoCuts.length, 2);
      final all = await c.ok('restore_cut', {'project_id': 'talk', 'cut_id': 'all'});
      expect(all.data['restored'], 2);
      saved = await b.store.load('talk');
      expect([saved.clips.length, saved.durationMs, saved.autoCuts.length], [1, 12000, 0]);
    });

    test('FFmpeg filter transcripts: estimated times are refused, and the '
        'answer is honest about fillers', () async {
      await russianTalk(cpp: false);
      final t = await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      expect(t.data['wordTimes'], 'estimated');
      expect(t.text, contains('ESTIMATED'));
      final dry = await c.ok('remove_fillers', {'project_id': 'talk'});
      expect(dry.data['fillerCount'], 0);
      expect(dry.text, contains('often leave "um"'));
      expect(dry.text, contains('FFmpeg filter'));
      final own = {
        'project_id': 'talk',
        'fillers': ['потом'],
        'strength': 'strong',
        'dry_run': false,
      };
      expect(await c.fails('remove_fillers', own), contains('only estimated'));
      final forced = await c.ok('remove_fillers', {...own, 'allow_estimated_times': true});
      expect(forced.data['fillerCount'], 1);
      expect((await b.store.load('talk')).clips.length, 2);
    });
  });

  group('make_short', () {
    test('a new upright 1080p project with only that part, captions from '
        'the speech; the original is untouched', () async {
      await russianTalk();
      final music = AudioClip(
          id: 'm',
          path: b.touch('song.mp3'),
          sourceDurationMs: 60000,
          startMs: 0,
          inMs: 0,
          outMs: 12000);
      await b.seed('talk', name: 'Talk', clips: [b.video('a', source: 12000)], audio: [music]);
      await c.ok('transcribe', {'project_id': 'talk', 'language': 'ru'});
      final before = b.projectFile('talk').readAsStringSync();
      final r = await c.ok('make_short', {
        'project_id': 'talk',
        'from_ms': 4000,
        'to_ms': 8200,
        'name': 'Bread tip',
      });
      final id = r.data['newProjectId'] as String;
      expect(id, isNot('talk'));
      expect(b.projectFile('talk').readAsStringSync(), before);
      final short = await b.store.load(id);
      expect(short.name, 'Bread tip');
      expect(short.durationMs, 4200);
      expect(short.aspect, CanvasAspect.portrait9x16);
      expect(short.videoSize, VideoSize.p1080);
      expect([short.canvasSize.width, short.canvasSize.height], [1080, 1920]);
      expect([short.clips.single.inMs, short.clips.single.outMs], [4000, 8200]);
      expect([short.audio.single.startMs, short.audio.single.inMs], [0, 4000]);
      expect(r.data['captionCount'], greaterThan(0));
      final captions = short.titles.map((t) => t.text.replaceAll('\n', ' ')).join(' ');
      expect(captions, 'ну, сначала нужна мука, вода и как бы соль.');
      // The transcripts came along: the short can be read on its own.
      final t = await c.ok('get_transcript', {'project_id': id});
      expect(t.text, contains('сначала нужна мука'));
      expect(t.text, isNot(contains('Привет')));
      expect(r.text, contains('The original is unchanged'));
      // Default name, square, no captions.
      final second = await c.ok('make_short', {
        'project_id': 'talk',
        'from_ms': 0,
        'to_ms': 3600,
        'shape': '1:1',
        'captions': false,
      });
      final sq = await b.store.load(second.data['newProjectId'] as String);
      expect(sq.name, 'Talk - short 0:00');
      expect(sq.aspect, CanvasAspect.square1x1);
      expect(sq.titles, isEmpty);
      expect(await c.fails('make_short', {'project_id': 'talk', 'from_ms': 5000, 'to_ms': 5200}),
          contains('at least 1000 ms'));
    });

    test('without a transcript the short is still made, and says so',
        () async {
      await russianTalk();
      final r = await c.ok('make_short',
          {'project_id': 'talk', 'from_ms': 1000, 'to_ms': 6000});
      expect(r.text, contains('not transcribed'));
      expect(r.data['captionCount'], 0);
    });
  });
}
