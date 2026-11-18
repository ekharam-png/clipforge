// Proof that the export layer works WITHOUT Flutter: this is a plain Dart
// program (no flutter_test, no plugins) that imports the command builder,
// the API types and ProcessMediaEngine, and exports a tiny project with
// the system ffmpeg.
//
//   dart run test/media/plain_dart_export.dart [output.mp4]
//
// Prints "OK <width>x<height> <durationMs>ms <path>" and exits with 0.
// (export_phase2_integration_test.dart runs it as part of the test suite.)

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/process_media_engine.dart';

Future<void> main(List<String> args) async {
  final tmp = await Directory.systemTemp.createTemp('clipforge_plain_');
  try {
    final root = Platform.script.resolve('../../');
    final fonts = FontPaths(
      regular: root.resolve('assets/fonts/DejaVuSans.ttf').toFilePath(),
      bold: root.resolve('assets/fonts/DejaVuSans-Bold.ttf').toFilePath(),
    );
    final photo = '${tmp.path}/photo.png';
    final made = await Process.run('ffmpeg', [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'smptebars=s=320x180', '-frames:v', '1', photo,
    ]);
    if (made.exitCode != 0) {
      stderr.writeln('cannot create the fixture: ${made.stderr}');
      exit(2);
    }

    final MediaEngine engine = ProcessMediaEngine(fonts: fonts, preset: 'ultrafast');
    final info = await engine.probe(photo);
    final now = DateTime.utc(2026);
    Clip clip(String id) => Clip(
        id: id,
        type: ClipType.photo,
        path: photo,
        sourceDurationMs: 0,
        inMs: 0,
        outMs: 600,
        width: info.width,
        height: info.height,
        hasAudio: false);
    final project = Project(
      id: 'plain',
      name: 'Plain Dart',
      createdAt: now,
      updatedAt: now,
      clips: [
        clip('a'),
        clip('b').copyWith(transition: TransitionType.crossfade, transitionMs: 200, saturation: -1),
      ],
      titles: const [
        TitleOverlay(id: 't', text: 'Hello from plain Dart', startMs: 0, endMs: 1000),
      ],
    );

    // The builder alone is usable too (e.g. to show the command).
    final cmd = buildExportCommand(
        project: project, outputPath: 'unused.mp4', fonts: fonts, workDir: tmp.path);
    if (!cmd.filterGraph.contains('xfade')) {
      stderr.writeln('unexpected graph: ${cmd.filterGraph}');
      exit(3);
    }

    final out = args.isNotEmpty ? args.first : '${tmp.path}/out.mp4';
    final job = engine.export(project, out, options: const ExportOptions(fps: 30));
    await job.done;
    final result = await engine.probe(out);
    final frame = await engine.extractFrame(out, 500, '${tmp.path}/frame.png');
    if (!File(frame).existsSync()) exit(4);
    stdout.writeln('OK ${result.width}x${result.height} ${result.durationMs}ms $out');
    if (result.width != 320 ||
        result.height != 180 ||
        (result.durationMs - project.durationMs).abs() > 150) {
      exit(5);
    }
  } on ExportException catch (e) {
    stderr.writeln('$e\n${e.log ?? ''}');
    exitCode = 1;
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}
