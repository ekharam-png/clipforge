// 1.11 speech-to-text backends, against FAKE programs and recorded-style
// outputs (test/media/fixtures/speech/): parsing every program's result,
// finding the programs, the commands they are given, progress, cancel,
// failures, and the rule that nothing is downloaded without consent.
import 'dart:io';

import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:clipforge/media/transcribe/whisper_output.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'speech_support.dart';

void main() {
  group('reading results', () {
    test('whisper.cpp, one word per entry (Russian): words measured, '
        'split pieces joined, markers dropped, phrases rebuilt', () {
      final r = parseWhisperCppJson(fixture('whispercpp_words_ru.json'),
          wordPerEntry: true);
      expect(r.language, 'ru');
      expect(r.wordsMeasured, isTrue);
      final tidy = tidySegments(r.segments, regroup: r.regroup);
      expect(tidy.estimated, isFalse);
      expect(tidy.segments.map((s) => s.text), [
        'Привет, друзья!',
        'Сегодня мы говорим о хлебе.',
        'Э-э, ну, сначала нужна мука, вода и как бы соль.',
        'Потом вы ждёте.',
      ]);
      final friends = tidy.segments.first.words[1];
      expect([friends.text, friends.startMs, friends.endMs], ['друзья!', 800, 1300]);
    });

    test('whisper.cpp full JSON with tokens (English)', () {
      final r = parseWhisperCppJson(fixture('whispercpp_full_en.json'));
      final tidy = tidySegments(r.segments);
      expect(r.language, 'en');
      expect(tidy.segments.map((s) => s.text), [
        'Welcome back to the show, everybody.',
        "Um, today we're baking bread.",
      ]);
      final w = tidy.segments.first.words;
      expect([w[4].text, w[4].startMs, w[4].endMs], ['show,', 1060, 1560]);
      expect([w.last.text, w.last.startMs, w.last.endMs], ['everybody.', 1700, 2500]);
    });

    test('faster-whisper / OpenAI JSON with word times (Hebrew)', () {
      final r = parseOpenAiJson(fixture('faster_whisper_he.json'));
      expect(r.language, 'he');
      expect(r.wordsMeasured, isTrue);
      final tidy = tidySegments(r.segments);
      expect(tidy.segments.length, 3);
      expect(tidy.segments[1].text, 'אה, היום נדבר על לחם.');
      expect(tidy.segments[1].words.first.startMs, 3100);
      expect(tidy.segments.last.words.last.endMs, 10360);
    });

    test('OpenAI JSON without word times: words estimated', () {
      final r = parseOpenAiJson(fixture('openai_segments_en.json'));
      expect(r.wordsMeasured, isFalse);
      final tidy = tidySegments(r.segments);
      expect(tidy.estimated, isTrue);
      expect(tidy.segments.first.words.length, 5);
      expect(tidy.segments.first.words.last.endMs, 2600);
    });

    test('FFmpeg filter lines: quotes inside the text, blank audio', () {
      final r = parseFfmpegWhisperJson(fixture('ffmpeg_whisper_ru.json'));
      expect(r.wordsMeasured, isFalse);
      final tidy = tidySegments(r.segments);
      expect(tidy.segments.map((s) => s.text), [
        'Привет, друзья! Сегодня мы говорим о хлебе.',
        'Он сказал: "сначала нужна мука", вода и соль.',
        'Потом вы ждёте.',
      ]);
      expect(tidy.segments.last.startMs, 20000);
      expect(parseFfmpegWhisperJson('').segments, isEmpty);
    });

    test('SubRip, and telling the formats apart', () {
      expect(parseSrtTranscript(fixture('whisper_he.srt')).segments.length, 2);
      expect(parseAnyTranscript(fixture('whisper_he.srt')).segments.first.endMs, 2480);
      expect(parseAnyTranscript(fixture('ffmpeg_whisper_ru.json')).segments.length, 4);
      expect(parseAnyTranscript(fixture('faster_whisper_he.json')).language, 'he');
      expect(parseAnyTranscript(fixture('whispercpp_full_en.json')).language, 'en');
      expect(() => parseOpenAiJson('{not json'), throwsA(isA<SpeechException>()));
    });

    test('progress lines the programs print', () {
      expect(printedSegmentEndMs('[00:00:04.200 --> 00:00:04.650]   Э-э,'), 4650);
      expect(printedSegmentEndMs('[01:02.000 --> 01:05.500]  hello'), 65500);
      expect(printedSegmentEndMs('[1:00:00.000 --> 1:00:02.000] x'), 3602000);
      expect(printedSegmentEndMs('loading model'), isNull);
    });
  });

  group('finding programs', () {
    test('FFmpeg with and without the whisper filter', () async {
      final host = FakeHost()..addFfmpeg();
      final info = await FfmpegWhisperBackend(host).detect();
      expect(info!.id, 'ffmpeg-whisper');
      expect(info.program, '/usr/bin/ffmpeg');
      expect(info.measuresWords, isFalse);
      expect(info.usesPacks, isTrue);
      expect(info.detail, 'FFmpeg 8.0');
      final old = FakeHost()..addFfmpeg(whisper: false, version: '6.1.1');
      expect(await FfmpegWhisperBackend(old).detect(), isNull);
      expect(await FfmpegWhisperBackend(FakeHost()).detect(), isNull);
      expect(FfmpegWhisperBackend.filtersListWhisper(' .. whisper A->A x'), isTrue);
      expect(FfmpegWhisperBackend.filtersListWhisper(' .. whisperx A->A'), isFalse);
    });

    test('whisper programs by name, kind read from --help', () async {
      final cpp = FakeHost()..addWhisperCpp();
      expect((await WhisperCliBackend(cpp).detect())!.id, 'whisper-cpp');
      final faster = FakeHost()..addPythonWhisper();
      final f = await WhisperCliBackend(faster).detect();
      expect([f!.id, f.usesPacks, f.measuresWords], ['faster-whisper', false, true]);
      final openai = FakeHost()
        ..addPythonWhisper(path: '/usr/bin/whisper', faster: false);
      expect((await WhisperCliBackend(openai).detect())!.id, 'openai-whisper');
      // A program called "whisper" that is something else is not used.
      final other = FakeHost()
        ..files.add('/usr/bin/whisper')
        ..answers['/usr/bin/whisper'] = {'--help': 'usage: whisper <message>'};
      expect(await WhisperCliBackend(other).detect(), isNull);
    });

    test('Windows: PATH with .exe, WinGet links and pip Scripts folders',
        () async {
      final host = FakeHost(os: 'windows', environment: {
        'Path': r'C:\Windows;C:\Tools',
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        'USERPROFILE': r'C:\Users\me',
      });
      host.dirs[r'C:\Users\me\AppData\Local\Programs\Python'] = ['Python312'];
      const ffmpeg = r'C:\Users\me\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe';
      const whisper =
          r'C:\Users\me\AppData\Local\Programs\Python\Python312\Scripts\whisper.exe';
      host.addFfmpeg(path: ffmpeg);
      host.addPythonWhisper(path: whisper, faster: false);
      expect(findProgram(host, ['ffmpeg']), ffmpeg);
      expect((await WhisperCliBackend(host).detect())!.program, whisper);
    });

    test('a program the user pointed at wins', () async {
      final host = FakeHost()
        ..addWhisperCpp()
        ..addPythonWhisper(path: '/opt/my/whisper-thing');
      final b = WhisperCliBackend(host, programPath: '/opt/my/whisper-thing');
      expect((await b.detect())!.program, '/opt/my/whisper-thing');
    });
  });

  group('commands', () {
    test('FFmpeg filter: model path escaped, language, queue, json, vad', () {
      final b = FfmpegWhisperBackend(FakeHost());
      final args = b.arguments(const BackendRequest(
          inputPath: r'C:\Videos\talk.mp4',
          workDir: '/tmp/w',
          language: 'ru',
          durationMs: 60000,
          audioTrack: 1,
          modelPath: r'C:\Users\me\Documents\ClipForge\models\ggml-base.bin',
          vadModelPath: '/m/ggml-silero-v5.1.2.bin'));
      expect(args.sublist(args.indexOf('-map'), args.indexOf('-map') + 2),
          ['-map', '0:a:1']);
      final af = args[args.indexOf('-af') + 1];
      expect(
          af,
          r'whisper=model=C\\:/Users/me/Documents/ClipForge/models/ggml-base.bin'
          ':language=ru:queue=20:use_gpu=true:destination=transcript.json'
          ':format=json:vad_model=/m/ggml-silero-v5.1.2.bin');
      expect(args.sublist(args.length - 3), ['-f', 'null', '-']);
      expect(args, containsAllInOrder(['-progress', 'pipe:1']));
    });

    test('whisper.cpp: word mode, json, progress, filler prompt', () {
      final args = WhisperCliBackend.argumentsFor(
          WhisperProgramKind.whisperCpp,
          const BackendRequest(
              inputPath: '/v/talk.mp4',
              wavPath: '/tmp/w/sound.wav',
              workDir: '/tmp/w/run',
              language: 'ru',
              durationMs: 1000,
              modelPath: '/m/ggml-base.bin'));
      expect(
          args.take(12),
          ['-m', '/m/ggml-base.bin', '-f', '/tmp/w/sound.wav', '-l', 'ru', //
            '-ml', '1', '-sow', '-oj', '-of', '/tmp/w/run/out']);
      expect(args, contains('-pp'));
      expect(args[args.indexOf('--prompt') + 1], contains('Э-э'));
    });

    test('Python programs: model name, json, word times; auto language', () {
      final args = WhisperCliBackend.argumentsFor(
          WhisperProgramKind.fasterWhisper,
          const BackendRequest(
              inputPath: '/v/talk.mp4',
              wavPath: '/tmp/w/sound.wav',
              workDir: '/tmp/w/run',
              language: 'auto',
              durationMs: 1000,
              modelName: 'small'));
      expect(args, [
        '/tmp/w/sound.wav', '--model', 'small', '--output_dir', '/tmp/w/run', //
        '--output_format', 'json', '--word_timestamps', 'True',
      ]);
      final he = WhisperCliBackend.argumentsFor(
          WhisperProgramKind.openAi,
          const BackendRequest(
              inputPath: '/v/a.mp4',
              workDir: '/w',
              language: 'he',
              durationMs: 1,
              modelName: 'base',
              keepFillers: false));
      expect(he.first, '/v/a.mp4');
      expect(he, containsAllInOrder(['--language', 'he']));
      expect(he, isNot(contains('--initial_prompt')));
    });
  });

  group('the service', () {
    late Directory dir;
    late String root;
    late String media;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('cf_speech_');
      root = p.join(dir.path, 'ClipForge');
      media = mediaFile(dir, 'talk.mp4');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('nothing on the computer: a plain explanation, per system', () async {
      final s = TranscriptionService(rootDir: root, host: FakeHost());
      final plan = await s.plan(language: 'ru');
      expect(plan.backend, isNull);
      expect(plan.problem, contains('none was found'));
      expect(noBackendExplanation('windows'), contains('winget install ffmpeg'));
      expect(noBackendExplanation('macos'), contains('brew install'));
      await expectLater(
          s.transcribe(media).done,
          throwsA(isA<SpeechException>()
              .having((e) => e.kind, 'kind', 'no-backend')));
    });

    test('program but no pack: nothing downloads without consent', () async {
      final host = FakeHost()..addFfmpeg();
      final s = TranscriptionService(rootDir: root, host: host);
      // No size chosen: the user must pick.
      final auto = await s.plan(language: 'ru');
      expect(auto.needsChoice, isTrue);
      expect(auto.download, isNull);
      await expectLater(
          s.transcribe(media, language: 'ru').done,
          throwsA(isA<SpeechException>()
              .having((e) => e.kind, 'kind', 'needs-pack')
              .having((e) => e.message, 'message',
                  allOf(contains('Small (about 140 MB'), contains('Large (about 1.6 GB')))));
      // A size chosen, still no consent.
      final small = await s.plan(language: 'ru', quality: SpeechQuality.small);
      expect(small.download!.id, 'base');
      await expectLater(
          s.transcribe(media, language: 'ru', quality: SpeechQuality.small).done,
          throwsA(isA<SpeechException>()
              .having((e) => e.kind, 'kind', 'needs-pack')
              .having((e) => e.message, 'message', contains('about 140 MB'))));
      expect(host.started, isEmpty);
      expect(Directory(p.join(root, 'models')).existsSync(), isFalse);
    });

    test('packs per language: sizes, sharing, largest installed wins', () {
      final s = TranscriptionService(rootDir: root, host: FakeHost());
      final m = s.models;
      expect(m.packsFor('en').map((x) => x.model.id),
          ['base.en', 'small.en', 'large-v3-turbo']);
      expect(m.packsFor('ru').map((x) => x.model.id),
          ['base', 'small', 'large-v3-turbo']);
      expect(m.packsFor('he').map((x) => x.model.sizeLabel),
          ['about 140 MB', 'about 470 MB', 'about 1.6 GB']);
      expect(m.choose('ru', SpeechQuality.auto).ready, isFalse);
      // The all-languages Small pack, fetched for Russian, also serves
      // Hebrew and English: no second download.
      installPack(root, 'base');
      expect(m.choose('he', SpeechQuality.auto).installed!.model.id, 'base');
      expect(m.choose('en', SpeechQuality.small).installed!.model.id, 'base');
      expect(m.packsFor('en').first.installed!.model.id, 'base');
      expect(m.choose('en', SpeechQuality.medium).download!.id, 'small.en');
      // English-only packs never serve Russian.
      installPack(root, 'small.en');
      expect(m.choose('ru', SpeechQuality.auto).installed!.model.id, 'base');
      expect(m.choose('en', SpeechQuality.auto).installed!.model.id, 'small.en');
      installPack(root, 'large-v3-turbo');
      expect(m.choose('en', SpeechQuality.auto).installed!.model.id, 'large-v3-turbo');
      expect(m.choose('ru', SpeechQuality.small).installed!.model.id, 'base');
      expect(m.usedBytes, 3 * 2048);
      expect(m.remove(m.byId('large-v3-turbo')!), 2048);
      expect(m.installed.map((x) => x.model.id), ['base.en', 'small.en', 'base']
          .where((id) => id != 'base.en'));
      expect(s.packOffer('ru'), contains('Small (about 140 MB, already on this computer'));
    });

    test('FFmpeg filter end to end: estimated words, the ggml pack used',
        () async {
      final host = FakeHost()..addFfmpeg();
      installPack(root, 'base');
      final s = TranscriptionService(rootDir: root, host: host, appVersion: '1.11.0');
      final job = s.transcribe(media, language: 'ru', durationMs: 20000);
      final seen = <SpeechProgress>[];
      job.progress.listen(seen.add);
      final t = await job.done;
      expect(t.backend, 'ffmpeg-whisper');
      expect(t.model, 'base');
      expect(t.language, 'ru');
      expect(t.wordTiming, WordTiming.estimated);
      expect(t.segments.length, 3);
      expect(t.words.first.text, 'Привет,');
      expect(t.durationMs, 20000);
      expect(seen.any((x) => x.phase == SpeechPhase.transcribing && x.fraction > 0.2),
          isTrue);
      final run = host.started.single;
      expect(run.first, '/usr/bin/ffmpeg');
      expect(run[run.indexOf('-i') + 1], media);
      expect(run[run.indexOf('-af') + 1], contains('ggml-base.bin'));
      // The work folder is gone.
      expect(
          Directory.systemTemp
              .listSync()
              .where((e) => p.basename(e.path).startsWith('clipforge_speech_')),
          isEmpty);
    });

    test('whisper.cpp end to end: WAV first, measured words, preferred over '
        'the FFmpeg filter', () async {
      final host = FakeHost()
        ..addFfmpeg()
        ..addWhisperCpp();
      installPack(root, 'base');
      final s = TranscriptionService(rootDir: root, host: host);
      expect((await s.available()).map((b) => b.id), ['whisper-cpp', 'ffmpeg-whisper']);
      final t = await s.transcribe(media, language: 'ru', durationMs: 12000).done;
      expect(t.backend, 'whisper-cpp');
      expect(t.wordTiming, WordTiming.measured);
      expect(t.words.length, 20);
      expect(host.started.map((c) => p.basename(c.first)), ['ffmpeg', 'whisper-cli']);
      final wav = host.started.first;
      expect(wav, containsAllInOrder(['-ac', '1', '-ar', '16000']));
      expect(wav, containsAllInOrder(['-map', '0:a:0']));
      // Asking for the filter by name works too.
      final viaFilter =
          await s.transcribe(media, language: 'ru', backendId: 'ffmpeg-whisper').done;
      expect(viaFilter.backend, 'ffmpeg-whisper');
      final none = await s.plan(backendId: 'faster-whisper');
      expect(none.problem, contains('was not found'));
    });

    test('a Python program with its model in its own cache needs no pack; '
        'without it, consent first', () async {
      final host = FakeHost()..addPythonWhisper();
      final s = TranscriptionService(rootDir: root, host: host);
      var plan = await s.plan(language: 'he', quality: SpeechQuality.medium);
      expect(plan.programFetchesModel, isTrue);
      expect(plan.ready, isFalse);
      await expectLater(
          s.transcribe(media, language: 'he', quality: SpeechQuality.medium).done,
          throwsA(isA<SpeechException>().having((e) => e.kind, 'kind', 'needs-pack')));
      host.dirs['/home/me/.cache/huggingface/hub'] = [
        'models--Systran--faster-whisper-small'
      ];
      plan = await s.plan(language: 'he');
      expect(plan.ready, isTrue);
      expect(plan.modelName, 'small');
      final t = await s.transcribe(media, language: 'he', durationMs: 11000).done;
      expect(t.backend, 'faster-whisper');
      expect(t.language, 'he');
      expect(t.wordTiming, WordTiming.measured);
      expect(t.model, 'small');
      // No FFmpeg here: the program reads the file itself.
      expect(host.started.single[1], media);
    });

    test('zero download wins: the filter with a pack beats a Python program '
        'that would fetch its model', () async {
      final host = FakeHost()
        ..addFfmpeg()
        ..addPythonWhisper();
      installPack(root, 'base');
      final s = TranscriptionService(rootDir: root, host: host);
      final plan = await s.plan(language: 'ru');
      expect(plan.backend!.id, 'ffmpeg-whisper');
      expect(plan.ready, isTrue);
    });

    test('the user\'s own model file and program', () async {
      final host = FakeHost()..addFfmpeg();
      final own = mediaFile(dir, 'mine/ggml-medium.bin');
      final s = TranscriptionService(rootDir: root, host: host);
      s.models.saveSettings(SpeechSettings(modelPath: own));
      final plan = await s.plan(language: 'he');
      expect(plan.ready, isTrue);
      expect(plan.model!.path, own);
      expect(plan.model!.own, isFalse);
      final t = await s.transcribe(media, language: 'he').done;
      expect(t.model, 'medium');
      // An English-only file is not used for Russian.
      final en = mediaFile(dir, 'mine/ggml-base.en.bin');
      s.models.saveSettings(SpeechSettings(modelPath: en));
      expect((await s.plan(language: 'ru')).needsChoice, isTrue);
      expect((await s.plan(language: 'en')).ready, isTrue);
      expect(s.models.settings.modelPath, en);
    });

    test('a failing program gives its last line; cancel stops it', () async {
      final bad = FakeHost()..addFfmpeg(code: 1);
      installPack(root, 'base');
      final s = TranscriptionService(rootDir: root, host: bad);
      await expectLater(
          s.transcribe(media, language: 'ru').done,
          throwsA(isA<SpeechException>().having(
              (e) => e.message, 'message', contains('Failed to load model'))));
      final slow = FakeHost()..addFfmpeg(runFor: const Duration(seconds: 20));
      final s2 = TranscriptionService(rootDir: root, host: slow);
      final job = s2.transcribe(media, language: 'ru', durationMs: 20000);
      await job.progress.firstWhere((x) => x.phase == SpeechPhase.transcribing);
      final watch = Stopwatch()..start();
      await job.cancel();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      await expectLater(
          job.done,
          throwsA(isA<SpeechException>()
              .having((e) => e.cancelled, 'cancelled', isTrue)));
    });

    test('graphics card: tried, the processor quietly instead, and reported',
        () async {
      installPack(root, 'base');
      // The owner's laptop: whisper.cpp says the card is unsupported and
      // carries on.
      final laptop = FakeHost()
        ..addFfmpeg(gpuLog: const [
          '[whisper @ 0x55] Unsupported GPU: NVIDIA GeForce RTX 4070 Laptop GPU',
        ]);
      var t = await TranscriptionService(rootDir: root, host: laptop)
          .transcribe(media, language: 'ru')
          .done;
      expect(t.device, 'processor');
      expect(laptop.started.length, 1);
      // A card that makes FFmpeg fail outright: one more run without it.
      final broken = FakeHost()..addFfmpeg(gpuFails: true);
      t = await TranscriptionService(rootDir: root, host: broken)
          .transcribe(media, language: 'ru')
          .done;
      expect(t.device, 'processor');
      expect(t.words, isNotEmpty);
      expect(broken.started.length, 2);
      expect(broken.started.last[broken.started.last.indexOf('-af') + 1],
          contains('use_gpu=false'));
      // A card that works.
      final good = FakeHost()
        ..addFfmpeg(gpuLog: const ['whisper_backend_init_gpu: using CUDA0 backend']);
      t = await TranscriptionService(rootDir: root, host: good)
          .transcribe(media, language: 'ru')
          .done;
      expect(t.device, 'graphics card');
      expect(deviceFromLog('nothing telling'), '');
    });

    test('a missing file is said plainly', () async {
      final s = TranscriptionService(rootDir: root, host: FakeHost()..addFfmpeg());
      await expectLater(
          s.transcribe(p.join(dir.path, 'gone.mp4')).done,
          throwsA(isA<SpeechException>()
              .having((e) => e.message, 'message', contains('gone.mp4'))));
    });
  });
}
