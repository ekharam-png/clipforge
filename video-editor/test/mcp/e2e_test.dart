// End to end: the server as a real process, spoken to over stdio the way
// Claude Desktop does. The single-file executable is built with
// bin/build_mcp.dart and used when that works (it is what ships);
// otherwise the server runs from source with `dart run`.
//
// The editing session needs ffmpeg / ffprobe and is skipped without them.

// Building the executable in setUpAll takes a while on a cold machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/mcp/mcp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// A running server process and a minimal MCP client for it.
class ServerProcess {
  ServerProcess._(this.process);

  final Process process;
  final List<String> stdoutLines = [];
  final StringBuffer stderrText = StringBuffer();
  final List<Map<String, dynamic>> notifications = [];
  final Map<Object, Completer<Map<String, dynamic>>> _waiting = {};
  final Completer<void> _stdoutDone = Completer<void>();
  int _nextId = 1;

  static Future<ServerProcess> start(List<String> command, List<String> args,
      {String? workingDirectory, Map<String, String>? environment}) async {
    final process = await Process.start(command.first, [...command.skip(1), ...args],
        workingDirectory: workingDirectory, environment: environment);
    final s = ServerProcess._(process);
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      s.stdoutLines.add(line);
      final Object? message;
      try {
        message = jsonDecode(line);
      } catch (_) {
        return; // reported by expectOnlyProtocolOnStdout
      }
      if (message is! Map) return;
      if (message.containsKey('method')) {
        s.notifications.add(message.cast<String, dynamic>());
      } else {
        s._waiting.remove(message['id'])?.complete(message.cast<String, dynamic>());
      }
    }, onDone: s._stdoutDone.complete);
    process.stderr.transform(utf8.decoder).listen(s.stderrText.write);
    return s;
  }

  void send(Map<String, dynamic> message) => process.stdin.writeln(jsonEncode(message));

  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic>? params]) {
    final id = _nextId++;
    final done = _waiting[id] = Completer<Map<String, dynamic>>();
    send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return done.future.timeout(const Duration(minutes: 3),
        onTimeout: () => fail('no answer to $method\nstderr:\n$stderrText'));
  }

  /// Tools that answer with a project take `detail`; this session asks for
  /// the whole timeline (the default is a short summary).
  static const _noDetail = {
    'get_status', 'list_projects', 'get_project', 'export_srt', 'export_video', //
    'get_export_status', 'cancel_export', 'list_sound_tracks',
  };

  Future<Reply> call(String tool, [Map<String, dynamic> arguments = const {}, Object? progressToken]) async {
    final response = await request('tools/call', {
      'name': tool,
      'arguments': {
        if (!_noDetail.contains(tool) && !arguments.containsKey('detail')) 'detail': 'full',
        ...arguments,
      },
      if (progressToken != null) '_meta': {'progressToken': progressToken},
    });
    expect(response['error'], isNull, reason: '$tool: ${response['error']}');
    return Reply((response['result'] as Map).cast<String, dynamic>());
  }

  Future<Reply> ok(String tool, [Map<String, dynamic> arguments = const {}]) async {
    final reply = await call(tool, arguments);
    expect(reply.isError, isFalse, reason: '$tool: ${reply.text}');
    return reply;
  }

  Future<Map<String, dynamic>> initialize([String version = '2025-11-25']) async {
    final r = await request('initialize', {
      'protocolVersion': version,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'e2e-test', 'version': '1.0'},
    });
    send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    return (r['result'] as Map).cast<String, dynamic>();
  }

  /// Closes the input, as a client that quits does; returns the exit code.
  Future<int> close() async {
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      fail('the server did not stop when its input was closed\nstderr:\n$stderrText');
    });
    await _stdoutDone.future;
    return code;
  }

  /// Standard output must carry nothing but JSON-RPC messages.
  void expectOnlyProtocolOnStdout() {
    for (final line in stdoutLines) {
      final Object? message;
      try {
        message = jsonDecode(line);
      } catch (_) {
        fail('not JSON on stdout: $line');
      }
      expect(message, isA<Map>().having((m) => m['jsonrpc'], 'jsonrpc', '2.0'), reason: line);
    }
  }
}

void main() {
  final dart = findDart();
  final root = Directory.current.path;
  late Directory tmp;
  late List<String> command;
  late String workDir;
  var compiled = false;

  setUpAll(() async {
    if (dart == null) return;
    tmp = Directory.systemTemp.createTempSync('clipforge_mcp_e2e_');
    // The shipped layout: the executable with a fonts folder next to it.
    final exe = p.join(tmp.path, 'app', Platform.isWindows ? 'clipforge-mcp.exe' : 'clipforge-mcp');
    final build = await Process.run(dart, ['run', p.join('bin', 'build_mcp.dart'), '-o', exe], workingDirectory: root);
    if (build.exitCode == 0 && File(exe).existsSync()) {
      compiled = true;
      final fonts = Directory(p.join(tmp.path, 'app', 'fonts'))..createSync();
      for (final name in ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf']) {
        File(p.join(root, 'assets', 'fonts', name)).copySync(p.join(fonts.path, name));
      }
      command = [exe];
      workDir = tmp.path; // not the repository: the fonts must be found next to the exe
    } else {
      printOnFailure('build_mcp.dart failed, running from source instead:\n${build.stdout}\n${build.stderr}');
      // ignore: avoid_print
      print('NOTE: could not build the executable (exit ${build.exitCode}); testing `dart run` instead.');
      command = [dart, 'run', p.join('bin', 'clipforge_mcp.dart')];
      workDir = root;
    }
  });

  tearDownAll(() {
    if (dart == null) return;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ServerProcess> start(String projects, {List<String> extra = const [], Map<String, String>? env}) =>
      ServerProcess.start(command, ['--projects-dir', projects, ...extra], workingDirectory: workDir, environment: env);

  test('the single-file executable was built', () {
    expect(compiled, isTrue, reason: 'bin/build_mcp.dart must produce the executable that is shipped');
  }, skip: dart == null ? 'no dart executable found' : false);

  test('--version, --help and a wrong option', () async {
    final version = await Process.run(command.first, [...command.skip(1), '--version'], workingDirectory: workDir);
    expect(version.exitCode, 0);
    // The same version as the app: pubspec.yaml's (bin/build_mcp.dart
    // compiles it in; `dart run` from source has none and says "dev").
    final pubspec = RegExp(r'^version:\s*([^\s+]+)\+(\d+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(
        version.stdout as String,
        contains(compiled
            ? 'ClipForge ${pubspec[1]} (build ${pubspec[2]}) · local build (clipforge-mcp, MCP ${kProtocolVersions.first})'
            : 'ClipForge dev · local build (clipforge-mcp, MCP ${kProtocolVersions.first})'));
    final help = await Process.run(command.first, [...command.skip(1), '--help'], workingDirectory: workDir);
    expect(help.exitCode, 0);
    expect(help.stdout as String, allOf(contains('--projects-dir'), contains('--ffmpeg'), contains('--fonts-dir')));
    final bad = await Process.run(command.first, [...command.skip(1), '--nope'], workingDirectory: workDir);
    expect(bad.exitCode, 64);
    expect(bad.stdout as String, isEmpty);
    expect(bad.stderr as String, contains('Unknown option: --nope'));
  }, skip: dart == null ? 'no dart executable found' : false, timeout: const Timeout(Duration(minutes: 2)));

  test('handshake, tool list and status; stdout carries only protocol messages', () async {
    final projects = p.join(tmp.path, 'hs', 'ClipForge', 'projects');
    final s = await start(projects);
    final init = await s.initialize();
    expect(init['protocolVersion'], '2025-11-25');
    expect(init['serverInfo'], containsPair('name', 'clipforge'));
    expect((init['capabilities'] as Map).keys, ['tools']);
    expect(init['instructions'], contains('CLOSED in the ClipForge app'));

    expect((await s.request('ping'))['result'], isEmpty);
    final tools = (((await s.request('tools/list'))['result'] as Map)['tools'] as List).cast<Map>();
    expect(tools.length, 57);
    expect(tools.map((t) => t['name']), containsAll(['get_status', 'add_media', 'remove_silences', 'export_video']));

    final status = await s.ok('get_status');
    expect(status.data['projectsDir'], projects);
    expect(status.data['projectsDirSource'], contains('--projects-dir'));
    final pubspecVersion = RegExp(r'^version:\s*([^\s+]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect((status.data['build'] as Map)['version'], compiled ? pubspecVersion : 'dev');
    expect((status.data['build'] as Map)['display'], startsWith('ClipForge '));
    if (compiled) {
      expect(status.data['fontsDir'], p.join(tmp.path, 'app', 'fonts'), reason: 'fonts next to the executable');
    }
    if (ffmpegOk) {
      expect((status.data['ffmpeg'] as Map)['version'], isNotEmpty);
    }
    final unknown = await s.request('tools/call', {'name': 'delete_project', 'arguments': <String, dynamic>{}});
    expect((unknown['error'] as Map)['code'], kInvalidParams);
    final wrong = await s.call('get_project', {'project_id': 'nothing here'});
    expect(wrong.isError, isTrue);

    // Garbage in, error out, and the server keeps running.
    s.process.stdin.writeln('this is not json');
    expect((await s.request('ping'))['result'], isEmpty);

    expect(await s.close(), 0);
    s.expectOnlyProtocolOnStdout();
    expect(s.stdoutLines.map((l) => (jsonDecode(l) as Map)['id']), contains(null), reason: 'the parse error reply');
    final log = s.stderrText.toString();
    expect(log, contains('[clipforge-mcp] projects folder: $projects'));
    expect(log, contains('initialize: client e2e-test 1.0'));
  }, skip: dart == null ? 'no dart executable found' : false, timeout: const Timeout(Duration(minutes: 2)));

  test('options can come from the environment; an older client revision is honoured', () async {
    final projects = p.join(tmp.path, 'env projects');
    final s = await ServerProcess.start(command, const [],
        workingDirectory: workDir,
        environment: {'CLIPFORGE_PROJECTS_DIR': projects, 'CLIPFORGE_FFMPEG': p.join(tmp.path, 'missing-ffmpeg')});
    expect((await s.initialize('2024-11-05'))['protocolVersion'], '2024-11-05');
    final status = await s.ok('get_status');
    expect(status.data['projectsDir'], projects);
    expect(status.data['ffmpeg'], isNull);
    expect(status.text, contains('ffmpeg: NOT FOUND'));
    // Editing works without ffmpeg; media tools explain what to install.
    final id = (await s.ok('create_project', {'name': 'Ünïcödé ✓ проект'})).project['id'] as String;
    expect((await s.ok('get_project', {'project_id': id})).project['name'], 'Ünïcödé ✓ проект');
    expect(File(p.join(projects, id, 'project.json')).readAsStringSync(), contains('Ünïcödé ✓ проект'));
    final clip = File(p.join(tmp.path, 'x.mp4'))..writeAsStringSync('x');
    final media = await s.call('add_media', {'project_id': id, 'paths': [clip.path]});
    expect(media.isError, isTrue);
    expect(media.text, contains('needs the free program FFmpeg'));
    expect(await s.close(), 0);
    s.expectOnlyProtocolOnStdout();
  }, skip: dart == null ? 'no dart executable found' : false, timeout: const Timeout(Duration(minutes: 2)));

  test('a whole editing session: media, cuts, titles, silences, export', () async {
    final media = Directory(p.join(tmp.path, 'media'))..createSync();
    final intro = p.join(media.path, 'intro.mp4');
    final talk = p.join(media.path, 'talk.mp4');
    final photo = p.join(media.path, 'photo.png');
    final music = p.join(media.path, 'music.m4a');
    makeVideo(intro, seconds: 3);
    makeTalk(talk);
    makePhoto(photo);
    makeMusic(music, seconds: 20);

    final projects = p.join(tmp.path, 'session', 'ClipForge', 'projects');
    final s = await start(projects);
    await s.initialize();

    // Create a project and add the media.
    final id = (await s.ok('create_project', {'name': 'My podcast'})).project['id'] as String;
    expect((await s.ok('list_projects')).text, contains('"My podcast"  project_id $id'));
    final added = await s.ok('add_media', {'project_id': id, 'paths': [intro, talk, photo], 'photo_duration_ms': 2000});
    final ids = (added.data['addedClipIds'] as List).cast<String>();
    expect(ids, hasLength(3));
    expect(added.project['durationMs'], closeTo(3000 + 4000 + 2000, 150));

    // Split the intro at 1 s, drop the first half, trim and speed up the rest.
    final split = await s.ok('split_at', {'project_id': id, 'timeline_ms': 1000});
    expect(split.data['firstClipId'], ids[0]);
    final rest = split.data['secondClipId'] as String;
    await s.ok('remove_clip', {'project_id': id, 'clip_id': ids[0]});
    final trimmed = await s.ok('trim_clip', {'project_id': id, 'clip_id': rest, 'out_ms': 2600});
    expect([trimmed.clips[0]['sourceInMs'], trimmed.clips[0]['sourceOutMs']], [1000, 2600]);
    final fast = await s.ok('set_clip_properties', {'project_id': id, 'clip_id': rest, 'speed': 2, 'saturation': -0.5});
    expect(fast.clips[0]['durationMs'], 800);
    // Crossfade into the talk, slide into the photo.
    await s.ok('set_clip_properties', {'project_id': id, 'clip_id': ids[1], 'transition': 'crossfade', 'transition_ms': 300});
    final slid = await s.ok('set_clip_properties', {'project_id': id, 'clip_id': ids[2], 'transition': 'slideLeft'});
    expect(slid.clips.map((c) => c['transitionOverlapMs']), [0, 300, 500]);
    expect(slid.project['durationMs'], closeTo(800 + 4000 - 300 + 2000 - 500, 80));

    // Cut the silence out of the talk (tone, 1.5 s of silence, tone).
    final cut = await s.ok('remove_silences', {'project_id': id, 'clip_id': ids[1]});
    expect(cut.data['gapsRemoved'], 1);
    expect(cut.data['removedMs'], closeTo(1200, 100));
    expect(cut.clips.map((c) => c['file']), ['intro.mp4', 'talk.mp4', 'talk.mp4', 'photo.png']);
    expect(cut.clips[1]['sourceOutMs'], closeTo(1650, 60));
    expect(cut.clips[2]['sourceInMs'], closeTo(2850, 60));

    // A title, a caption, subtitles made for the uncut talk, music, vertical.
    final title = await s.ok('add_title', {'project_id': id, 'text': 'My podcast', 'start_ms': 0, 'duration_ms': 700, 'y': 0.2});
    expect(title.data['titleId'], isNotEmpty);
    await s.ok('add_caption', {'project_id': id, 'text': 'Welcome!', 'start_ms': 100, 'end_ms': 700});
    final srt = File(p.join(media.path, 'talk.srt'))
      ..writeAsStringSync('1\n00:00:00,200 --> 00:00:01,200\nBefore the pause\n\n'
          '2\n00:00:01,900 --> 00:00:02,600\nDuring the pause\n\n'
          '3\n00:00:03,100 --> 00:00:03,900\nAfter the pause\n');
    final subs = await s.ok('import_srt',
        {'project_id': id, 'path': srt.path, 'time_base': 'source', 'source_clip_id': ids[1]});
    expect(subs.data['captionsAdded'], 2);
    expect(subs.data['cuesDropped'], 1);
    final talkStart = subs.clips[1]['timelineStartMs'] as int;
    final after = subs.titles.firstWhere((t) => t['text'] == 'After the pause');
    final secondPiece = subs.clips[2];
    expect(after['startMs'],
        closeTo((secondPiece['timelineStartMs'] as int) + 3100 - (secondPiece['sourceInMs'] as int), 2));
    expect(subs.titles.firstWhere((t) => t['text'] == 'Before the pause')['startMs'], talkStart + 200);
    final musicAdded =
        await s.ok('add_music', {'project_id': id, 'path': music, 'volume': 0.3, 'fade_out_ms': 500});
    expect(musicAdded.audio.single['id'], musicAdded.data['audioId']);
    final settings = await s.ok('set_project_settings', {'project_id': id, 'aspect': '9:16', 'duck_music': true});
    expect([settings.project['canvasWidth'], settings.project['canvasHeight']], [360, 640]);
    expect((await s.ok('export_srt', {'project_id': id})).data['captionCount'], 3);

    // What is on disk is what the last tool reported.
    final onDisk = jsonDecode(File(p.join(projects, id, 'project.json')).readAsStringSync()) as Map;
    expect(onDisk['aspect'], 'portrait9x16');
    expect(onDisk['clips'], hasLength(4));
    expect(onDisk['titles'], hasLength(4));
    final state = await s.ok('get_project', {'project_id': id});
    final projectMs = state.project['durationMs'] as int;
    expect(projectMs, closeTo(800 + 2800 - 300 + 2000 - 500, 150));

    // Export, with progress, then look at the file with ffprobe.
    final out = p.join(tmp.path, 'out', 'podcast vertical.mp4');
    final exported = await s.call('export_video', {'project_id': id, 'output_path': out, 'quality': 'small'}, 'exp');
    expect(exported.isError, isFalse, reason: '${exported.text}\nstderr:\n${s.stderrText}');
    expect(exported.data['outputPath'], out);
    expect(exported.data['sizeBytes'], File(out).lengthSync());
    final probe = ffprobeJson(out);
    expect(probedDurationMs(probe), closeTo(projectMs, 150));
    expect(probedHas(probe, 'video'), isTrue);
    expect(probedHas(probe, 'audio'), isTrue);
    final v = (probe['streams'] as List).cast<Map>().firstWhere((x) => x['codec_type'] == 'video');
    expect([v['width'], v['height'], v['codec_name']], [360, 640, 'h264']);
    final progress = [
      for (final n in s.notifications)
        if (n['method'] == 'notifications/progress' && (n['params'] as Map)['progressToken'] == 'exp')
          (n['params'] as Map)['progress'] as num,
    ];
    expect(progress, isNotEmpty);
    expect(progress.last, 100);

    expect(await s.close(), 0);
    s.expectOnlyProtocolOnStdout();
  },
      skip: dart == null ? 'no dart executable found' : skipWithoutFfmpeg,
      timeout: const Timeout(Duration(minutes: 5)));

  test('an export keeps going when the server stops; a new server reports it', () async {
    final media = Directory(p.join(tmp.path, 'media2'))..createSync();
    final clip = p.join(media.path, 'long.mp4');
    // Long enough that a fast machine is still rendering after the wait.
    makeVideo(clip, seconds: 20);
    final projects = p.join(tmp.path, 'quit', 'ClipForge', 'projects');
    final s = await start(projects);
    await s.initialize();
    final id = (await s.ok('create_project', {'name': 'Quit'})).project['id'] as String;
    await s.ok('add_media', {'project_id': id, 'paths': [clip, clip]});
    await s.ok('set_clip_properties', {'project_id': id, 'clip_id': 'all', 'speed': 0.25});
    final out = p.join(tmp.path, 'quit-out', 'survivor.mp4');
    final started = await s.ok('export_video', {'project_id': id, 'output_path': out, 'wait_seconds': 1});
    expect(started.data['status'], anyOf('starting', 'running'), reason: started.text);
    expect(started.data['runner'], 'a separate process');
    final job = started.data['jobId'] as String;
    final watch = Stopwatch()..start();
    expect(await s.close(), 0);
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    s.expectOnlyProtocolOnStdout();

    // A new server (as after a client restart) follows the same job.
    final again = await start(projects);
    await again.initialize();
    Reply? done;
    for (var i = 0; i < 6; i++) {
      done = await again.ok('get_export_status', {'job_id': job, 'wait_seconds': 30});
      if (done.data['status'] != 'running' && done.data['status'] != 'starting') break;
    }
    expect(done!.data['status'], 'finished', reason: done.text);
    expect(done.data['outputPath'], out);
    expect(File(out).lengthSync(), done.data['sizeBytes']);
    expect(probedDurationMs(ffprobeJson(out)), closeTo(160000, 300));
    expect(Directory(p.dirname(out)).listSync().map((f) => p.basename(f.path)), ['survivor.mp4'],
        reason: 'the .part file was renamed');
    expect(await again.close(), 0);
  },
      skip: dart == null ? 'no dart executable found' : skipWithoutFfmpeg,
      timeout: const Timeout(Duration(minutes: 5)));
}
