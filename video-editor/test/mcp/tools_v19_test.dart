// 1.9: exports as background jobs (fake slow engine), short answers and
// paging, the app's "open" lock, dry runs, warnings (sound past the end,
// short captions, output size), export_srt with source times, ducking
// report.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_lock.dart';
import 'package:clipforge/mcp/environment.dart';
import 'package:clipforge/mcp/export_jobs.dart';
import 'package:clipforge/mcp/mcp_protocol.dart';
import 'package:clipforge/mcp/report.dart';
import 'package:clipforge/mcp/tools.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// An export engine that takes [steps] x [stepTime] and writes a small
/// file, or fails when [fail] is set. [gate] holds it before the last step.
class SlowEngine implements MediaEngine {
  SlowEngine({this.steps = 10, this.stepTime = const Duration(milliseconds: 30), this.fail = false});
  final int steps;
  final Duration stepTime;
  bool fail;
  Completer<void>? gate;
  final List<String> exported = [];

  @override
  ExportJob export(Project project, String outputPath, {ExportOptions options = const ExportOptions()}) {
    exported.add(outputPath);
    return _SlowJob(this, outputPath).._run();
  }

  @override
  Future<MediaInfo> probe(String path) async =>
      const MediaInfo(durationMs: 5000, width: 640, height: 360, hasVideo: true, hasAudio: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _SlowJob implements ExportJob {
  _SlowJob(this.engine, this.path);
  final SlowEngine engine;
  final String path;
  final _progress = StreamController<ExportProgress>.broadcast();
  final _done = Completer<String>();
  bool _cancelled = false;

  Future<void> _run() async {
    await Future<void>.delayed(Duration.zero);
    for (var i = 1; i <= engine.steps; i++) {
      if (i == engine.steps && engine.gate != null) await engine.gate!.future;
      await Future<void>.delayed(engine.stepTime);
      if (_cancelled) {
        _done.completeError(ExportException('Export cancelled', cancelled: true));
        return;
      }
      _progress.add(ExportProgress(i / engine.steps * 0.99));
    }
    if (engine.fail) {
      _done.completeError(ExportException('ffmpeg failed (exit code 1): Broken pipe', log: 'line 1\nBroken pipe'));
      return;
    }
    File(path).writeAsStringSync('not really a video, ' * 100);
    _done.complete(path);
  }

  @override
  Stream<ExportProgress> get progress => _progress.stream;
  @override
  Future<String> get done => _done.future;
  @override
  Future<void> cancel() async => _cancelled = true;
  @override
  VideoEncoder? get videoEncoder => _done.isCompleted ? VideoEncoder.libx264 : null;
  @override
  List<String> get warnings => const [];
}

void main() {
  late Bench b;
  late Client c;
  late SlowEngine engine;

  setUp(() {
    engine = SlowEngine();
    b = Bench(
        ffmpeg: false,
        exportLauncher: inProcessLauncher(() async => engine, needsFfmpeg: false));
    c = b.client;
  });
  tearDown(() => b.dispose());

  /// [n] clips of one recording, like the pieces after removing silences.
  List<Clip> pieces(int n) => [
        for (var i = 0; i < n; i++)
          b.video('c$i', file: 'talk.mp4', source: 1540000, inMs: i * 11000, outMs: i * 11000 + 8000),
      ];

  group('export jobs', () {
    test('a short export finishes within the wait and reports the file', () async {
      await b.seed('p1', clips: [b.video('a')]);
      final out = b.file('out.mp4');
      final r = await c.call('export_video', {'project_id': 'p1', 'output_path': out}, 'tok');
      expect(r.isError, isFalse, reason: r.text);
      expect(r.data['status'], 'finished');
      expect(r.data['outputPath'], out);
      expect(r.data['sizeBytes'], File(out).lengthSync());
      expect(r.data['videoEncoder'], 'libx264');
      expect(r.text, contains('Exported "p1" to:\n$out'));
      // Rendered under a .part name, then renamed: nothing else is left.
      expect(engine.exported.single, endsWith('.part.mp4'));
      expect(Directory(b.tmp.path).listSync().whereType<File>().map((f) => p.basename(f.path)),
          isNot(contains(contains('.part'))));
      final progress = [
        for (final n in c.notifications)
          if ((n['params'] as Map)['progressToken'] == 'tok') (n['params'] as Map)['progress'] as num,
      ];
      expect(progress.last, 100);
      // The job is a file the next server can read.
      final job = b.tools.jobs.read(r.data['jobId'] as String)!;
      expect(job.status, kJobFinished);
      expect(job.result!['sizeBytes'], File(out).lengthSync());
    });

    test('a long export answers with the job; status, progress, ETA, then the result', () async {
      engine.gate = Completer<void>();
      await b.seed('p1', clips: [b.video('a')]);
      final out = b.file('long.mp4');
      final started = await c.ok('export_video', {'project_id': 'p1', 'output_path': out, 'wait_seconds': 1});
      expect(started.data['status'], 'running');
      expect(started.data['progressPercent'], greaterThan(50));
      expect(started.data['estimateMs'], greaterThan(0));
      expect(started.text, allOf(contains('job_id'), contains('get_export_status'), contains('do not start the export again')));
      expect(started.data['partPath'], endsWith('.part.mp4'));
      final id = started.data['jobId'] as String;

      // A second export to the same file is refused while it runs.
      expect(await c.fails('export_video', {'project_id': 'p1', 'output_path': out}), contains('already running'));

      final status = await c.ok('get_export_status', {'job_id': id});
      expect(status.data['status'], 'running');
      expect(status.data['etaMs'], isNotNull);
      expect(status.data['elapsedMs'], greaterThan(0));

      // A server started later (client restart) sees the same job.
      final other = ClipForgeTools(
          projectsDir: b.tools.projectsDir, media: MediaTools(ffmpegOption: '/none', ffprobeOption: '/none'));
      final client2 = Client(McpServer(name: 'x', version: '1', tools: other.tools));
      final seen = await client2.ok('get_export_status', {'job_id': id});
      expect(seen.data['status'], 'running');

      engine.gate!.complete();
      final done = await client2.call('get_export_status', {'job_id': id, 'wait_seconds': 20}, 'wait');
      expect(done.data['status'], 'finished', reason: done.text);
      expect(done.data['progressPercent'], 100);
      expect(File(out).existsSync(), isTrue);
      expect(client2.notifications.where((n) => (n['params'] as Map)['progressToken'] == 'wait'), isNotEmpty);

      // Without a job id: the recent ones.
      final list = await c.ok('get_export_status');
      expect((list.data['jobs'] as List).map((j) => (j as Map)['jobId']), contains(id));
      expect(await c.fails('get_export_status', {'job_id': 'nope'}), contains('no export'));
    });

    test('cancel_export stops it and leaves no file', () async {
      engine.gate = Completer<void>();
      await b.seed('p1', clips: [b.video('a')]);
      final out = b.file('stop.mp4');
      final started = await c.ok('export_video', {'project_id': 'p1', 'output_path': out, 'wait_seconds': 0});
      final id = started.data['jobId'] as String;
      final cancelling = c.ok('cancel_export', {'job_id': id});
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      engine.gate!.complete();
      final r = await cancelling;
      expect(r.data['status'], 'cancelled', reason: r.text);
      expect(File(out).existsSync(), isFalse);
      expect(File(started.data['partPath'] as String).existsSync(), isFalse);
      // Cancelling again just reports it.
      expect((await c.ok('cancel_export', {'job_id': id})).data['status'], 'cancelled');
    });

    test('a failed export says why', () async {
      engine.fail = true;
      await b.seed('p1', clips: [b.video('a')]);
      final r = await c.call('export_video', {'project_id': 'p1', 'output_path': b.file('f.mp4')});
      expect(r.isError, isTrue);
      expect(r.data['status'], 'failed');
      expect(r.text, allOf(contains('The export failed'), contains('Broken pipe')));
    });

    test('a job whose process is gone is reported as lost', () async {
      final now = DateTime.now();
      b.tools.jobs.write(ExportJobRecord(
        id: 'old1', projectId: 'p1', projectName: 'Old', outputPath: b.file('x.mp4'),
        partPath: b.file('x.part.mp4'), format: 'video', quality: 'full', fps: 30,
        hardware: true, overwrite: false, createdAt: now.subtract(const Duration(minutes: 5)),
        projectDurationMs: 1000, estimateMs: 1000, status: kJobRunning, progress: 0.4,
        startedAt: now.subtract(const Duration(minutes: 5)),
        heartbeatAt: now.subtract(const Duration(minutes: 2)),
        host: localHostName(), workerPid: 0x7ffffff0,
      ));
      final r = await c.call('get_export_status', {'job_id': 'old1'});
      expect(r.data['status'], 'lost');
      expect(r.text, contains('stopped without finishing'));
    });

    test('the estimate uses the speed of the last export', () {
      final project = Project(
          id: 'x', name: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026),
          clips: [b.video('a', source: 600000)]);
      final guess = estimateRenderMs(project, const ExportOptions());
      expect(guess.basis, contains('rough'));
      final fast = estimateRenderMs(project, const ExportOptions(), measuredRate: 20);
      expect(fast.ms, lessThan(guess.ms));
      expect(fast.basis, contains('last export'));
      final sound = estimateRenderMs(project, const ExportOptions(format: ExportFormat.m4a));
      expect(sound.ms, lessThan(guess.ms));
    });

    test('small exports say what changed', () async {
      await b.seed('big', clips: [b.video('a')]);
      final r = await c.ok('export_video', {'project_id': 'big', 'quality': 'small', 'output_path': b.file('s.mp4')});
      expect(r.text, contains('scaled down from 1920x1080 to 1280x720'));
      expect(r.data['small'], contains('2500 kbit/s'));
      final project = Project(
          id: 'x', name: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026),
          clips: [Clip(id: 'a', type: ClipType.video, path: '/v.mp4', sourceDurationMs: 1000,
              inMs: 0, outMs: 1000, width: 464, height: 824)]);
      expect(smallExportNote(project, ExportQuality.small, ExportFormat.video),
          allOf(contains('stays 464x824'), contains('2500 kbit/s')));
      expect(smallExportNote(project, ExportQuality.full, ExportFormat.video), isNull);
    });
  });

  group('short answers and paging', () {
    test('an edit of a 137-clip project answers briefly; detail full has everything', () async {
      await b.seed('big', clips: pieces(137));
      c.fullDetail = false;
      final r = await c.ok('set_clip_properties', {'project_id': 'big', 'clip_id': 'c5', 'volume': 0.5});
      expect(r.text.length + jsonEncode(r.data).length, lessThan(6000));
      expect(r.data['project'], containsPair('clipCount', 137));
      expect(r.data['project'], isNot(contains('clips')));
      expect(((r.data['changes'] as Map)['clips'] as Map)['changed'], ['c5']);
      expect(r.text, contains('1 clip(s) changed: c5'));
      expect(r.text, contains('Last saved'));
      expect(r.data['project'], containsPair('lastEditedBy', 'claude'));
      final full = await c.ok('set_clip_properties', {'project_id': 'big', 'clip_id': 'c5', 'volume': 0.6, 'detail': 'full'});
      expect(full.clips, hasLength(137));
    });

    test('get_project pages long projects and shows a time range', () async {
      await b.seed('big', clips: pieces(137));
      final first = await c.ok('get_project', {'project_id': 'big'});
      expect(first.clips, hasLength(60));
      final page = first.project['page'] as Map;
      expect([page['clipsMatching'], page['nextClipOffset']], [137, 60]);
      expect(first.text, contains('next page: clip_offset 60'));
      final last = await c.ok('get_project', {'project_id': 'big', 'clip_offset': 120});
      expect(last.clips.map((x) => x['index']), List.generate(17, (i) => 120 + i));
      expect((last.project['page'] as Map).containsKey('nextClipOffset'), isFalse);
      final range = await c.ok('get_project', {'project_id': 'big', 'from_ms': 16000, 'to_ms': 24000});
      expect(range.clips.map((x) => x['index']), [2]);
      expect(await c.fails('get_project', {'project_id': 'big', 'from_ms': 5, 'to_ms': 5}), contains('after'));
    });

    test('who saved last: Claude, or the app after Claude', () async {
      await b.seed('p1', clips: [b.video('a')]);
      expect((await c.ok('get_project', {'project_id': 'p1'})).project['lastEditedBy'], 'app');
      await c.ok('rename_project', {'project_id': 'p1', 'name': 'New'});
      final g = await c.ok('get_project', {'project_id': 'p1'});
      expect(g.project['lastEditedBy'], 'claude');
      expect(g.project['lastEditTool'], 'rename_project');
      expect(g.text, contains("by Claude's tools (rename_project)"));
      // The app saves it.
      final project = await b.store.load('p1');
      await b.store.save(project.copyWith(name: 'From the app'));
      expect((await c.ok('get_project', {'project_id': 'p1'})).project['lastEditedBy'], 'app');
    });
  });

  group('open in the app', () {
    Future<void> lock(String id, {Duration age = Duration.zero, int? pid, String? host}) async {
      final at = DateTime.now().subtract(age);
      File(p.join(b.store.rootPath, id, kAppLockFileName)).writeAsStringSync(jsonEncode(ProjectLockInfo(
        pid: pid ?? currentPid, host: host ?? localHostName(), openedAt: at, heartbeatAt: at, app: 'ClipForge test',
      ).toJson()));
    }

    test('edits are refused while the app has the project open; reading works', () async {
      await b.seed('p1', clips: [b.video('a')]);
      await lock('p1');
      final before = b.projectFile('p1').readAsStringSync();
      final message = await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      expect(message, allOf(contains('is open in the ClipForge app'), contains('close the project')));
      expect(b.projectFile('p1').readAsStringSync(), before);
      expect(await c.fails('rename_project', {'project_id': 'p1', 'name': 'x'}), contains('open in the'));
      final g = await c.ok('get_project', {'project_id': 'p1'});
      expect(g.project['openInApp'], isTrue);
      expect(g.text, contains('editing tools refuse'));
      // A dry run changes nothing, so it is allowed.
      final dry = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'all', 'speed': 2, 'dry_run': true});
      expect(dry.data['wouldChange'], isTrue);
    });

    test('a lock left by a crash (old heartbeat or gone process) is ignored', () async {
      await b.seed('p1', clips: [b.video('a')]);
      await lock('p1', age: const Duration(minutes: 10));
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      await lock('p1', pid: 0x7ffffff0);
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 1.5});
      // Another computer (shared folder): only the heartbeat counts.
      await lock('p1', pid: 0x7ffffff0, host: 'other-computer');
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 1}),
          contains('on other-computer'));
    });

    test("the app's lock: written, kept fresh, removed; stale ones are swept", () async {
      final dir = Directory(p.join(b.tmp.path, 'projects', 'x'))..createSync(recursive: true);
      final lock = AppProjectLock(dir.path, app: 'ClipForge test')..acquire();
      expect((await checkProjectLock(dir.path)).state, ProjectLockState.held);
      // Another editor's lock is not removed by this one.
      final other = AppProjectLock(dir.path)..acquire();
      lock.release();
      expect((await checkProjectLock(dir.path)).state, ProjectLockState.held);
      other.release();
      expect((await checkProjectLock(dir.path)).state, ProjectLockState.none);
      // A crash leftover.
      File(p.join(dir.path, kAppLockFileName)).writeAsStringSync(jsonEncode(ProjectLockInfo(
        pid: 0x7ffffff0, host: localHostName(), openedAt: DateTime.now(), heartbeatAt: DateTime.now(),
      ).toJson()));
      final check = await checkProjectLock(dir.path);
      expect(check.state, ProjectLockState.stale);
      expect(check.reason, contains('no longer running'));
      expect(await removeStaleLocks(p.dirname(dir.path)), 1);
      expect(File(p.join(dir.path, kAppLockFileName)).existsSync(), isFalse);
      expect(await processAlive(currentPid), isTrue);
      expect(await processAlive(0x7ffffff0), isFalse);
    });
  });

  group('dry runs', () {
    test('set_clip_properties all / apply_to_all report without saving', () async {
      await b.seed('p1', clips: [b.video('a'), b.video('b')]);
      final before = b.projectFile('p1').readAsStringSync();
      final r = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'all', 'speed': 2, 'dry_run': true});
      expect(r.text, startsWith('DRY RUN'));
      expect([r.data['changed'], r.data['wouldChange'], r.data['dryRun']], [false, true, true]);
      expect(r.project['durationMs'], 10000);
      expect(b.projectFile('p1').readAsStringSync(), before);
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      final a = await c.ok('apply_to_all', {'project_id': 'p1', 'clip_id': 'a', 'speed': true, 'dry_run': true});
      expect(a.data['wouldChange'], isTrue);
      expect((await b.store.load('p1')).clips[1].speed, 1);
      // Nothing to undo from a dry run.
      await c.ok('undo', {'project_id': 'p1'});
      expect(await c.fails('undo', {'project_id': 'p1'}), contains('nothing to undo'));
    });
  });

  group('warnings', () {
    test('music past the end is pointed out after a cut, with fit_music_to_video', () async {
      final song = AudioClip(id: 'm', path: '/music/song.mp3', sourceDurationMs: 30000,
          startMs: 0, inMs: 0, outMs: 12000, fadeOutMs: 1500);
      await b.seed('p1', clips: [b.video('a'), b.video('b', file: 'b.mp4')], audio: [song]);
      final ok = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'volume': 0.9});
      expect(ok.data['warnings'], isNull);
      final cut = await c.ok('remove_clip', {'project_id': 'p1', 'clip_id': 'b'});
      final w = (cut.data['warnings'] as List).single as String;
      expect(w, allOf(contains('song.mp3'), contains('past the end'), contains('1500 ms fade-out'),
          contains('fit_music_to_video')));
      expect(soundPastEndWarnings((await b.store.load('p1')).copyWith(
          audio: [song.copyWith(fadeOutMs: 0)])).single, contains('stops abruptly'));
    });

    test('the size and why', () async {
      final phone = Clip(id: 'a', type: ClipType.video, path: b.touch('small.mp4'), sourceDurationMs: 5000,
          inMs: 0, outMs: 5000, width: 464, height: 824);
      await b.seed('p1', clips: [phone]);
      c.fullDetail = false;
      final r = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'volume': 0.5});
      expect(r.text, allOf(contains('464x824 because'), contains('"small.mp4", 464x824'),
          contains('video_size "1080p"')));
      final big = await c.ok('set_project_settings', {'project_id': 'p1', 'video_size': '1080p'});
      expect(big.data['project']['canvasReason'], startsWith('1080x1918 because video_size is "1080p"'));
    });

    test('captions that get very short: warned, or kept on screen with min_caption_ms', () async {
      await b.seed('p1', clips: [b.video('a')], titles: [
        const TitleOverlay(id: 't1', text: 'One', startMs: 0, endMs: 2400, kind: TitleKind.caption),
        const TitleOverlay(id: 't2', text: 'Two', startMs: 3000, endMs: 4000, kind: TitleKind.caption),
      ]);
      final fast = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      expect((fast.data['warnings'] as List).single, allOf(contains('less than 1.2 s'), contains('t2 (500 ms)')));
      await c.ok('undo', {'project_id': 'p1'});
      final kept = await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'a', 'speed': 2, 'min_caption_ms': 1200});
      expect(kept.data['warnings'], isNull);
      expect(kept.text, contains('min_caption_ms'));
      final t2 = (await b.store.load('p1')).titles.firstWhere((t) => t.id == 't2');
      expect([t2.startMs, t2.endMs], [1500, 2700]);
    });
  });

  group('subtitles with source times', () {
    test('export_srt time_base source undoes the cuts; import puts them back', () async {
      // The same recording cut into two pieces (2..4 s removed).
      await b.seed('p1', clips: [
        b.video('a', inMs: 0, outMs: 2000),
        b.video('b', inMs: 4000, outMs: 10000),
      ], titles: [
        const TitleOverlay(id: 't1', text: 'Before', startMs: 500, endMs: 1500, kind: TitleKind.caption),
        const TitleOverlay(id: 't2', text: 'Across', startMs: 1500, endMs: 2500, kind: TitleKind.caption),
        const TitleOverlay(id: 't3', text: 'After', startMs: 3000, endMs: 4000, kind: TitleKind.caption),
      ]);
      final r = await c.ok('export_srt', {'project_id': 'p1', 'time_base': 'source'});
      expect(r.data['timeBase'], 'source');
      final srt = r.data['srt'] as String;
      expect(srt, contains('00:00:00,500 --> 00:00:01,500\nBefore'));
      expect(srt, contains('00:00:01,500 --> 00:00:04,500\nAcross'), reason: 'one cue over the removed part');
      expect(srt, contains('00:00:05,000 --> 00:00:06,000\nAfter'));
      final back = await c.ok('import_srt',
          {'project_id': 'p1', 'srt_text': srt, 'time_base': 'source', 'replace_existing_captions': true});
      expect([for (final t in back.titles) [t['text'], t['startMs'], t['endMs']]],
          [['Before', 500, 1500], ['Across', 1500, 2500], ['After', 3000, 4000]]);
      expect(back.text, isNot(contains('WARNING')));
      // Imported with the wrong time base: said so.
      final wrong = await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt});
      expect(wrong.text, contains('SOURCE times'));
    });

    test('timeline subtitles imported after re-cutting are flagged', () async {
      await b.seed('p1', clips: [b.video('a')], titles: [
        const TitleOverlay(id: 't1', text: 'Hi', startMs: 5000, endMs: 6000, kind: TitleKind.caption),
      ]);
      final srt = (await c.ok('export_srt', {'project_id': 'p1'})).data['srt'] as String;
      final same = await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt, 'replace_existing_captions': true});
      expect(same.text, isNot(contains('WARNING')));
      await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 2000});
      final later = await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt, 'replace_existing_captions': true});
      expect(later.text, contains('cut differently'));
    });
  });

  group('ducking report', () {
    test('where the music is lowered, worked out from the timeline', () async {
      final song = AudioClip(id: 'm', path: b.touch('song.mp3'), sourceDurationMs: 60000,
          startMs: 0, inMs: 0, outMs: 30000);
      final silent = b.video('b', file: 'b.mp4').copyWith(muted: true);
      final project = Project(
        id: 'p', name: 'p', createdAt: DateTime(2026), updatedAt: DateTime(2026),
        clips: [b.video('a'), silent, b.video('c', file: 'c.mp4')],
        audio: [song],
        tracks: const [SoundTrack(id: kMusicTrackId, name: 'Music', duck: true)],
      );
      final report = duckingReport(project);
      expect(report.single['loweredMs'], 20000);
      expect(report.single['heardMs'], 30000);
      expect(report.single['stretches'], 2);
      expect(duckingText(report), allOf(contains('"Music" is lowered'), contains('not measured'), contains('9 dB')));
      await b.seed('p1', clips: project.clips, audio: project.audio);
      final saved = await b.store.load('p1');
      await b.store.save(saved.copyWith(tracks: project.tracks));
      final r = await c.ok('export_video', {'project_id': 'p1', 'output_path': b.file('d.mp4')});
      expect(r.text, contains('Music under speech'));
      expect((r.data['ducking'] as List).single, containsPair('loweredMs', 20000));
    });
  });

  test('get_status starts with the program, folders and tools', () async {
    final r = await c.ok('get_status');
    final lines = r.text.split('\n');
    expect(lines[1], startsWith('Version: ClipForge'));
    expect(lines[2], startsWith('Program: '));
    expect(lines[3], 'Projects folder: ${b.store.rootPath}');
    expect(lines[4], startsWith('Title fonts: '));
    expect(lines[5], startsWith('ffmpeg: '));
    expect(r.text, contains('Export jobs: ${b.tools.jobs.dir}'));
    expect(r.data['executable'], Platform.resolvedExecutable);
    expect(r.data['jobsDir'], b.tools.jobs.dir);
  });
}
