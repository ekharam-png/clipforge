// 1.14 "Where is it going?": the destinations table, its warnings, a copy
// in the destination's shape against "export as it is", and a kit of
// several files made as one job - with an engine that only pretends
// (order, progress, cancel, a failure) and once for real with FFmpeg
// (three files with the right sizes and the text file).
import 'dart:async';
import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/publish/shorts.dart' show kShortMaxSeconds;
import 'package:clipforge/media/destinations.dart';
import 'package:clipforge/media/export_kit.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

Project wide({int ms = 30000, String name = 'Bread talk', FitMode fit = FitMode.fit}) =>
    Project(
      id: 'p',
      name: name,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      clips: [
        Clip(
            id: 'a',
            type: ClipType.video,
            path: '/media/a.mp4',
            sourceDurationMs: ms,
            inMs: 0,
            outMs: ms,
            width: 1920,
            height: 1080,
            fit: fit),
      ],
    );

/// An engine that renders nothing: each export reports two steps and
/// then finishes (or fails / waits, as told).
class PretendEngine implements MediaEngine {
  final List<({String name, Project project, ExportOptions options})> exports = [];
  String? failOn;
  Completer<void>? gate;
  bool write = true;

  @override
  ExportJob export(Project project, String outputPath,
      {ExportOptions options = const ExportOptions()}) {
    exports.add((name: p.basename(outputPath), project: project, options: options));
    return _PretendJob(this, outputPath).._run();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _PretendJob implements ExportJob {
  _PretendJob(this.engine, this.path);
  final PretendEngine engine;
  final String path;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  bool _cancelled = false;

  Future<void> _run() async {
    await Future<void>.delayed(Duration.zero);
    _progress.add(const ExportProgress(0.5));
    await engine.gate?.future;
    await Future<void>.delayed(Duration.zero);
    if (_cancelled) return;
    if (engine.failOn != null && path.contains(engine.failOn!)) {
      _done.completeError(ExportException('ffmpeg failed', log: 'the log'));
      return;
    }
    if (engine.write) File(path).writeAsStringSync('pretend');
    _progress.add(const ExportProgress(1));
    _done.complete(path);
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (!_done.isCompleted) {
      _done.completeError(ExportException('Export cancelled', cancelled: true));
    }
  }

  @override
  Future<String> get done => _done.future;
  @override
  Stream<ExportProgress> get progress => _progress.stream;
  @override
  VideoEncoder? get videoEncoder => VideoEncoder.libx264;
  @override
  List<String> get warnings => const [];
}

void main() {
  group('the table', () {
    test('is data: unique ids, the rows the owner asked for, https pages', () {
      expect(kDestinations.map((d) => d.id),
          ['youtube', 'shorts', 'instagram', 'whatsapp', 'podcast', 'custom']);
      expect(kDestinations.map((d) => d.id).toSet().length, kDestinations.length);
      for (final d in kDestinations) {
        expect(d.label, isNotEmpty);
        expect(d.detail, isNotEmpty);
        expect(d.formats, isNotEmpty);
        for (final u in d.uploads) {
          expect(Uri.parse(u.url).scheme, 'https', reason: u.url);
          expect(u.url, isNot(contains('@')));
        }
        // A limit always says whose it is, that it changes, and to check.
        if (d.maxSeconds != null || d.maxMegabytes != null) {
          expect(d.limitNote.toLowerCase(), contains('check the'), reason: d.id);
          expect(d.limitNote.toLowerCase(), contains('change'), reason: d.id);
        }
      }
      final shorts = destinationById('shorts')!;
      expect(shorts.shapes, [CanvasAspect.portrait9x16]);
      expect(shorts.videoSize, VideoSize.p1080);
      expect(shorts.maxSeconds, kShortMaxSeconds);
      expect(shorts.uploads.map((u) => u.label), ['YouTube', 'Instagram', 'TikTok']);
      expect(destinationById('youtube')!.shapes, [CanvasAspect.landscape16x9]);
      expect(destinationById('instagram')!.shapes,
          [CanvasAspect.portrait4x5, CanvasAspect.square1x1]);
      expect(destinationById('whatsapp')!.quality, ExportQuality.small);
      expect(destinationById('podcast')!.formats, [ExportFormat.mp3, ExportFormat.m4a]);
      expect(kCustomDestination.custom, isTrue);
      expect(destinationById('nowhere'), isNull);
    });

    test('clear file names', () {
      KitChoice c(String key) => kitChoiceByKey(key)!;
      expect(kitFileName('Bread talk', c('youtube')), 'Bread talk - YouTube.mp4');
      expect(kitFileName('Bread talk', c('shorts')), 'Bread talk - Short 9x16.mp4');
      expect(kitFileName('Bread talk', c('instagram')), 'Bread talk - Instagram 4x5.mp4');
      expect(kitFileName('Bread talk', c('instagram:1x1')), 'Bread talk - Instagram 1x1.mp4');
      expect(kitFileName('Bread talk', c('whatsapp')), 'Bread talk - WhatsApp.mp4');
      expect(kitFileName('Bread talk', c('podcast')), 'Bread talk - audio.mp3');
      expect(kitFileName('Bread talk', c('podcast:m4a')), 'Bread talk - audio.m4a');
      expect(kitTextFileName('Bread talk'), 'Bread talk - text.txt');
      expect(kitFileName('What? A/B: "test".', c('youtube')),
          'What_ A_B_ _test_ - YouTube.mp4');
      expect(kitSafeName(' . '), 'Video');
      expect(kitChoiceByKey('custom'), isNull);
      expect(kitChoiceByKey('instagram:16x9'), isNull);
      expect(kitChoiceByKey('instagram'), kitChoiceByKey('instagram:4x5'));
      expect(kitChoiceByKey(' Podcast:M4A ')!.formatInUse, ExportFormat.m4a);
      expect(kitChoices().map((c) => c.key), [
        'youtube', 'shorts', 'instagram:4x5', 'instagram:1x1', 'whatsapp', 'podcast', //
      ]);
      expect(kitChoices().map((c) => c.label), [
        'YouTube', 'Shorts / Reels / TikTok', 'Instagram post (4:5)',
        'Instagram post (1:1)', 'WhatsApp / Telegram', 'Podcast audio',
      ]);
    });

    test('warnings: longer than the limit, bigger than the app takes', () {
      KitChoice c(String key) => kitChoiceByKey(key)!;
      expect(destinationWarnings(wide(ms: 45000), c('shorts')), isEmpty);
      final long = destinationWarnings(wide(ms: 95000), c('shorts'));
      expect(long.single, startsWith('This video is 1:35 long. '));
      expect(long.single, contains('60 seconds is safe'));
      expect(long.single, contains('Check the site'));
      expect(destinationWarnings(wide(ms: 95000), c('youtube')), isEmpty);
      expect(destinationWarnings(wide(ms: 95000), c('instagram')).single,
          contains('Instagram'));
      // 2500 kbit/s: 16 MB is about 50 seconds.
      expect(destinationWarnings(wide(ms: 20000), c('whatsapp')), isEmpty);
      final big = destinationWarnings(wide(ms: 300000), c('whatsapp'));
      expect(big.single, matches(RegExp(r'^This will be about \d+ MB\. WhatsApp')));
      expect(big.single, contains('check the app'));
      expect(destinationWarnings(wide(ms: 3600000), c('podcast')), isEmpty);
    });
  });

  group('the shape of a destination', () {
    test('a copy in that shape: blurred background, 1080p; the project is '
        'not changed', () {
      final project = wide();
      expect(shapeDiffers(project, CanvasAspect.portrait9x16), isTrue);
      expect(shapeDiffers(project, CanvasAspect.landscape16x9), isFalse,
          reason: '1920x1080 is 16:9');
      expect(shapeDiffers(project, null), isFalse);
      final copy = destinationVariant(project, kitChoiceByKey('shorts')!);
      expect(identical(copy, project), isFalse);
      expect(copy.aspect, CanvasAspect.portrait9x16);
      expect(copy.canvasSize, (width: 1080, height: 1920));
      expect(copy.clips.single.fit, FitMode.blur);
      expect(copy.id, project.id);
      expect(project.aspect, CanvasAspect.original);
      expect(project.clips.single.fit, FitMode.fit);
      // A clip the user set to Fill keeps it.
      expect(
          destinationVariant(wide(fit: FitMode.fill), kitChoiceByKey('shorts')!)
              .clips
              .single
              .fit,
          FitMode.fill);
      final square = destinationVariant(project, kitChoiceByKey('instagram:1x1')!);
      expect(square.canvasSize, (width: 1080, height: 1080));
    });

    test('"Export as it is" keeps the shape; the same shape needs no copy', () {
      final project = wide();
      final asIs = destinationVariant(project, kitChoiceByKey('shorts')!, keepShape: true);
      expect(asIs.aspect, CanvasAspect.original);
      expect(asIs.canvasSize, (width: 1920, height: 1080));
      expect(asIs.clips.single.fit, FitMode.fit);
      final youtube = destinationVariant(
          project.copyWith(videoSize: VideoSize.p720), kitChoiceByKey('youtube')!);
      expect(youtube.aspect, CanvasAspect.original, reason: 'already 16:9');
      expect(youtube.canvasSize, (width: 1920, height: 1080), reason: '1080p');
      expect(identical(destinationVariant(project, kitChoiceByKey('whatsapp')!), project), isTrue);
      expect(identical(destinationVariant(project, kitChoiceByKey('podcast')!), project), isTrue);
    });

    test('in the editor it is one undo step with a name', () {
      final e = ProjectEditor(wide());
      expect(applyDestinationShape(e, CanvasAspect.portrait9x16, videoSize: VideoSize.p1080), 1);
      expect(e.history.single.label, 'Shape 9:16 with blurred background');
      e.undo();
      expect(e.project.aspect, CanvasAspect.original);
      expect(e.project.clips.single.fit, FitMode.fit);
    });
  });

  group('a kit, with an engine that only pretends', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('clipforge_kit_'));
    tearDown(() => dir.deleteSync(recursive: true));

    List<KitChoice> choices(List<String> keys) => [for (final k in keys) kitChoiceByKey(k)!];

    test('the plan: one item per destination, shape copies in memory only', () {
      final plan = planKit(wide(ms: 95000),
          choices(['youtube', 'shorts', 'shorts', 'whatsapp', 'podcast']),
          useHardwareEncoder: false);
      expect(plan.items.map((i) => i.fileName), [
        'Bread talk - YouTube.mp4',
        'Bread talk - Short 9x16.mp4',
        'Bread talk - WhatsApp.mp4',
        'Bread talk - audio.mp3',
      ]);
      expect(plan.items.map((i) => i.reshaped), [false, true, false, false]);
      expect(plan.items[1].project.canvasSize, (width: 1080, height: 1920));
      expect(plan.items[1].warnings.single, contains('1:35'));
      expect(plan.items[2].options.quality, ExportQuality.small);
      expect(plan.items[3].options.format, ExportFormat.mp3);
      expect(plan.items.every((i) => !i.options.useHardwareEncoder), isTrue);
      expect(plan.textFileName, 'Bread talk - text.txt');
      expect(plan.folderName, 'Bread talk');
      expect(plan.text(), contains('SHORTS / REELS / TIKTOK\nFile: Bread talk - Short 9x16.mp4'));
    });

    test('one job: one after another, overall progress, the text file', () async {
      final engine = PretendEngine();
      final project = wide().copyWith(
          publishing: const PublishingNotes(title: 'Why the first loaf fails'));
      final plan = planKit(project, choices(['youtube', 'shorts', 'podcast']));
      final seen = <KitProgress>[];
      final finished = <String>[];
      final run = runExportKit(engine, plan, dir.path,
          onFile: (f) async => finished.add(p.basename(f.path)));
      run.progress.listen(seen.add);
      final result = await run.done;
      expect(engine.exports.map((e) => e.name), [
        'Bread talk - YouTube.part.mp4',
        'Bread talk - Short 9x16.part.mp4',
        'Bread talk - audio.part.mp3',
      ]);
      expect(engine.exports[1].project.aspect, CanvasAspect.portrait9x16);
      expect(finished, [
        'Bread talk - YouTube.mp4', 'Bread talk - Short 9x16.mp4', 'Bread talk - audio.mp3', //
      ]);
      expect(result.files.map((f) => p.basename(f.path)), finished);
      expect(result.folder, dir.path);
      final names = dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(names, [
        'Bread talk - Short 9x16.mp4',
        'Bread talk - YouTube.mp4',
        'Bread talk - audio.mp3',
        'Bread talk - text.txt',
      ]);
      expect(File(result.textPath!).readAsStringSync(),
          startsWith('TITLE\nWhy the first loaf fails\n'));
      // Progress only goes up, counts the files, and ends at 1.
      expect(seen.map((s) => s.index).toSet(), {0, 1, 2});
      expect(seen.every((s) => s.count == 3), isTrue);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].overall, greaterThanOrEqualTo(seen[i - 1].overall));
      }
      expect(seen.last.overall, closeTo(1, 1e-9));
      // The sound is a small share of the work.
      expect(seen.lastWhere((s) => s.index == 1).overall, greaterThan(0.9));
    });

    test('cancel: the file being made is thrown away, finished ones stay',
        () async {
      final engine = PretendEngine();
      final plan = planKit(wide(), choices(['youtube', 'shorts', 'podcast']));
      final run = runExportKit(engine, plan, dir.path);
      // Hold the second file.
      run.progress.listen((pr) {
        if (pr.index == 0 && pr.itemFraction == 1) engine.gate = Completer<void>();
        if (pr.index == 1 && pr.itemFraction == 0.5) run.cancel();
      });
      await expectLater(run.done,
          throwsA(isA<ExportException>().having((e) => e.cancelled, 'cancelled', isTrue)));
      expect(engine.exports.length, 2, reason: 'the third never started');
      final names = dir.listSync().map((e) => p.basename(e.path)).toList();
      expect(names, ['Bread talk - YouTube.mp4']);
      expect(run.isCancelled, isTrue);
    });

    test('a failure names the file; an older file of that name is replaced',
        () async {
      File(p.join(dir.path, 'Bread talk - YouTube.mp4')).writeAsStringSync('old');
      final engine = PretendEngine()..failOn = 'Short';
      final run = runExportKit(
          engine, planKit(wide(), choices(['youtube', 'shorts'])), dir.path);
      await expectLater(
          run.done,
          throwsA(isA<ExportException>()
              .having((e) => e.message, 'message', startsWith('Shorts / Reels / TikTok: '))
              .having((e) => e.log, 'log', 'the log')));
      expect(File(p.join(dir.path, 'Bread talk - YouTube.mp4')).readAsStringSync(), 'pretend');
      expect(dir.listSync().length, 1, reason: 'no part file, no text file');
    });
  });

  group('a kit for real', () {
    if (!ffmpegOk) {
      test('needs ffmpeg', () {}, skip: 'ffmpeg not found');
      return;
    }
    setUpAll(setUpMedia);
    tearDownAll(tearDownMedia);

    test('three files with the right sizes, and the text file', () async {
      final project = Project(
        id: 'k',
        name: 'Kit test',
        createdAt: t0,
        updatedAt: t0,
        clips: [land(outMs: 2000)],
        titles: const [
          TitleOverlay(id: 't', text: 'Hello', startMs: 0, endMs: 1500),
        ],
        publishing: const PublishingNotes(
            title: 'A wide test video',
            description: 'Made by a test.',
            hashtags: ['test']),
      );
      final plan = planKit(project, [
        kitChoiceByKey('youtube')!,
        kitChoiceByKey('shorts')!,
        kitChoiceByKey('podcast')!,
      ], useHardwareEncoder: false);
      final folder = f('kit');
      final run = runExportKit(engine, plan, folder);
      var last = 0.0;
      run.progress.listen((pr) => last = pr.overall);
      final result = await run.done;
      expect(last, closeTo(1, 1e-9));
      expect(result.files.length, 3);
      final youtube = ffprobe(p.join(folder, 'Kit test - YouTube.mp4'));
      expect((youtube.width, youtube.height), (1920, 1080));
      expect(youtube.durationMs, closeTo(2000, 150));
      final short = ffprobe(p.join(folder, 'Kit test - Short 9x16.mp4'));
      expect((short.width, short.height), (1080, 1920));
      expect(short.stream('audio'), isNotNull);
      final sound = ffprobe(p.join(folder, 'Kit test - audio.mp3'));
      expect(sound.stream('video'), isNull);
      expect(sound.stream('audio')!['codec_name'], 'mp3');
      expect(sound.durationMs, closeTo(2000, 200));
      // The upright one has the blurred background, not black bars: the
      // top of the frame is not black.
      final top = frameAt(p.join(folder, 'Kit test - Short 9x16.mp4'), 1000, 1080, 1920);
      expect(top.luma(x0: 300, y0: 100, x1: 780, y1: 300), greaterThan(30));
      final text = File(p.join(folder, 'Kit test - text.txt')).readAsStringSync();
      expect(text, contains('TITLE\nA wide test video'));
      expect(text, contains('HASHTAGS\n#test'));
      expect(text, contains('File: Kit test - Short 9x16.mp4'));
      expect(
          Directory(folder).listSync().where((e) => e.path.contains('.part')), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}
