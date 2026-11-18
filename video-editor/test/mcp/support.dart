// Shared by the MCP tests: an in-process client for McpServer, a tools
// instance on a temporary projects folder, and ffmpeg fixtures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/file_project_store.dart';
import 'package:clipforge/mcp/environment.dart';
import 'package:clipforge/mcp/export_jobs.dart';
import 'package:clipforge/mcp/mcp_protocol.dart';
import 'package:clipforge/mcp/tools.dart';
import 'package:clipforge/mcp/transcribe_jobs.dart';
import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:clipforge/media/ffmpeg_command.dart' show FontPaths;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _has(String exe) {
  try {
    return Process.runSync(exe, const ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

final bool ffmpegOk = _has('ffmpeg') && _has('ffprobe');
final Object skipWithoutFfmpeg =
    ffmpegOk ? false : 'ffmpeg / ffprobe are not installed';

/// The result of one `tools/call`.
class Reply {
  Reply(this.result);
  final Map<String, dynamic> result;
  bool get isError => result['isError'] == true;
  String get text => ((result['content'] as List).single as Map)['text'] as String;
  Map<String, dynamic> get data =>
      (result['structuredContent'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get project =>
      (data['project'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get clips =>
      (project['clips'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get titles =>
      (project['titles'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get audio =>
      (project['audio'] as List).cast<Map<String, dynamic>>();
  @override
  String toString() => 'Reply(isError: $isError)\n$text';
}

/// Talks to an [McpServer] the way a client would, without a process.
class Client {
  Client(this.server);
  final McpServer server;
  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> notifications = [];
  final Map<Object, Completer<Map<String, dynamic>>> _waiting = {};
  int _nextId = 1;
  int get lastId => _nextId - 1;

  void _onLine(String line) {
    expect(line.contains('\n'), isFalse, reason: 'one message per line');
    final message = (jsonDecode(line) as Map).cast<String, dynamic>();
    sent.add(message);
    if (message.containsKey('method')) {
      notifications.add(message);
    } else if (message['id'] != null) {
      _waiting.remove(message['id'])?.complete(message);
    }
  }

  /// Sends raw text and returns everything the server wrote in reply.
  List<Map<String, dynamic>> raw(String line) {
    final before = sent.length;
    server.handleLine(line, write: _onLine);
    return sent.sublist(before);
  }

  void notify(String method, [Map<String, dynamic>? params]) => server.handleLine(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': ?params}),
      write: _onLine);

  /// Sends a request and completes with the whole response message.
  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic>? params]) {
    final id = _nextId++;
    final done = _waiting[id] = Completer<Map<String, dynamic>>();
    server.handleLine(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params}),
        write: _onLine);
    return done.future;
  }

  /// Edit tools answer with a short summary by default; most tests look at
  /// the timeline in the answer, so they ask for all of it unless they say
  /// otherwise (or [fullDetail] is false).
  bool fullDetail = true;

  Future<Reply> call(String tool, [Map<String, dynamic> arguments = const {}, Object? progressToken]) async {
    final takesDetail = server.tools[tool]?.properties.containsKey('detail') ?? false;
    final response = await request('tools/call', {
      'name': tool,
      'arguments': {
        if (fullDetail && takesDetail && !arguments.containsKey('detail')) 'detail': 'full',
        ...arguments,
      },
      if (progressToken != null) '_meta': {'progressToken': progressToken},
    });
    expect(response['error'], isNull, reason: 'protocol error: ${response['error']}');
    return Reply((response['result'] as Map).cast<String, dynamic>());
  }

  /// A call that must succeed.
  Future<Reply> ok(String tool, [Map<String, dynamic> arguments = const {}]) async {
    final reply = await call(tool, arguments);
    expect(reply.isError, isFalse, reason: reply.text);
    return reply;
  }

  /// A call that must fail as a tool error; returns the message.
  Future<String> fails(String tool, [Map<String, dynamic> arguments = const {}]) async {
    final reply = await call(tool, arguments);
    expect(reply.isError, isTrue, reason: 'expected an error, got: ${reply.text}');
    return reply.text;
  }
}

/// A temporary projects folder with the tools and a client on top.
class Bench {
  Bench._(this.tmp, this.tools, this.client);

  /// [ffmpeg] false simulates a computer without FFmpeg.
  factory Bench(
      {bool ffmpeg = true,
      bool fonts = true,
      String Function()? newId,
      ExportLauncher? exportLauncher,
      Future<bool> Function(int pid)? isAlive,
      TranscriptionService Function(String root)? speech,
      Duration speechHeartbeat = const Duration(milliseconds: 40)}) {
    final tmp = Directory.systemTemp.createTempSync('clipforge_mcp_test_');
    final root = Directory.current.path;
    final service = speech?.call(p.join(tmp.path, 'ClipForge'));
    final tools = ClipForgeTools(
      projectsDir: ProjectsDir(p.join(tmp.path, 'ClipForge', 'projects'), 'test'),
      media: MediaTools(
        ffmpegOption: ffmpeg ? 'ffmpeg' : p.join(tmp.path, 'no-such-ffmpeg'),
        ffprobeOption: ffmpeg ? 'ffprobe' : p.join(tmp.path, 'no-such-ffprobe'),
        fonts: fonts
            ? FontPaths(
                regular: p.join(root, 'assets', 'fonts', 'DejaVuSans.ttf'),
                bold: p.join(root, 'assets', 'fonts', 'DejaVuSans-Bold.ttf'))
            : null,
      ),
      fontsChecked: const ['nowhere'],
      newId: newId,
      exportLauncher: exportLauncher,
      isAlive: isAlive,
      speech: service,
      transcribeLauncher: service == null
          ? null
          : inProcessTranscribeLauncher((_) => service,
              heartbeat: speechHeartbeat),
    );
    final server = McpServer(name: kServerName, version: kServerVersion, tools: tools.tools);
    return Bench._(tmp, tools, Client(server));
  }

  final Directory tmp;
  final ClipForgeTools tools;
  final Client client;
  FileProjectStore get store => tools.store;

  String file(String name) => p.join(tmp.path, name);

  /// An existing (fake) media file.
  String touch(String name) {
    final f = File(file(name))..writeAsBytesSync(const [1, 2, 3]);
    return f.path;
  }

  File projectFile(String id) =>
      File(p.join(store.rootPath, id, FileProjectStore.projectFileName));

  /// Saves a project made of [clips] directly (no ffmpeg needed).
  Future<Project> seed(String id,
      {String? name,
      List<Clip> clips = const [],
      List<AudioClip> audio = const [],
      List<TitleOverlay> titles = const []}) async {
    final t = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final project = Project(
        id: id, name: name ?? id, createdAt: t, updatedAt: t, clips: clips, audio: audio, titles: titles);
    await store.save(project);
    return project;
  }

  /// A 10 s 1920x1080 video clip on a fake file.
  Clip video(String id, {String file = 'talk.mp4', int source = 10000, int inMs = 0, int? outMs, double speed = 1}) =>
      Clip(
          id: id,
          type: ClipType.video,
          path: touch(file),
          sourceDurationMs: source,
          inMs: inMs,
          outMs: outMs ?? source,
          width: 1920,
          height: 1080,
          speed: speed);

  Clip photo(String id, {int ms = 3000}) => Clip(
      id: id,
      type: ClipType.photo,
      path: touch('photo.png'),
      sourceDurationMs: 0,
      inMs: 0,
      outMs: ms,
      width: 800,
      height: 600,
      hasAudio: false);

  void dispose() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void ff(List<String> args) {
  final r = Process.runSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) fail('fixture ffmpeg failed: ${r.stderr}');
}

const _x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];

/// 640x360 video of [seconds] with a steady tone.
void makeVideo(String path, {int seconds = 2}) => ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=$seconds',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=$seconds',
      ..._x264, '-c:a', 'aac', '-shortest', path,
    ]);

/// 4 s video: tone, silence from 1.5 s to 3.0 s, tone.
void makeTalk(String path) => ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=4',
      '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=4',
      '-af', "volume='if(between(t,1.5,3),0,1)':eval=frame",
      ..._x264, '-c:a', 'aac', '-shortest', path,
    ]);

void makePhoto(String path) =>
    ff(['-f', 'lavfi', '-i', 'smptebars=s=400x300', '-frames:v', '1', path]);

void makeMusic(String path, {int seconds = 5}) =>
    ff(['-f', 'lavfi', '-i', 'sine=f=880:r=44100:d=$seconds', '-c:a', 'aac', path]);

/// ffprobe's JSON for [path].
Map<String, dynamic> ffprobeJson(String path) {
  final r = Process.runSync(
      'ffprobe', ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path],
      stdoutEncoding: utf8);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return (jsonDecode(r.stdout as String) as Map).cast<String, dynamic>();
}

int probedDurationMs(Map<String, dynamic> probe) =>
    (double.parse((probe['format'] as Map)['duration'] as String) * 1000).round();

bool probedHas(Map<String, dynamic> probe, String type) =>
    (probe['streams'] as List).any((s) => (s as Map)['codec_type'] == type);

/// The `dart` executable of the SDK that runs the tests.
String? findDart() {
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', exe),
  ];
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<os>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    candidates.add(p.join(dir.path, 'dart-sdk', 'bin', exe));
    dir = dir.parent;
  }
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  try {
    if (Process.runSync(exe, const ['--version']).exitCode == 0) return exe;
  } catch (_) {}
  return null;
}
