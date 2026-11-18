// Start-up of the ClipForge MCP server: options, where things are on this
// computer, then the protocol loop on standard input / output. Pure Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/build_info.dart';
import 'environment.dart';
import 'export_jobs.dart';
import 'mcp_protocol.dart';
import 'tools.dart';
import 'transcribe_jobs.dart';

/// Builds the server for [options]. [log] receives diagnostics (they must
/// never go to standard output, which carries only protocol messages).
Future<McpServer> createClipForgeServer(
  ServerOptions options, {
  required void Function(String message) log,
}) async {
  final projectsDir = await resolveProjectsDir(explicit: options.projectsDir);
  log('projects folder: ${projectsDir.path} (${projectsDir.source})');
  if (!Directory(projectsDir.path).existsSync()) {
    log('warning: that folder does not exist yet; if the app has projects '
        'elsewhere, pass --projects-dir');
  }

  final fontLookup = locateFonts(explicitDir: options.fontsDir);
  log(fontLookup.fonts == null
      ? 'warning: title fonts not found (looked in ${fontLookup.checked.join(', ')}); '
          'projects with titles cannot be exported'
      : 'title fonts: ${File(fontLookup.fonts!.regular).parent.path}');

  final media = MediaTools(
    ffmpegOption: options.ffmpeg,
    ffprobeOption: options.ffprobe,
    fonts: fontLookup.fonts,
  );
  // Looked up in the background so that the handshake is not held up.
  unawaited(() async {
    final mpeg = await media.ffmpeg();
    final probe = await media.ffprobe();
    log(mpeg == null
        ? 'warning: ffmpeg not found. ${ffmpegInstallHint()}'
        : 'ffmpeg: ${mpeg.path} (${mpeg.version})');
    log(probe == null
        ? 'warning: ffprobe not found'
        : 'ffprobe: ${probe.path} (${probe.version})');
  }());

  final tools = ClipForgeTools(
    projectsDir: projectsDir,
    media: media,
    fontsChecked: fontLookup.checked,
    // Exports run in their own process and outlive the server.
    exportLauncher: separateProcessLauncher(),
    // So does speech-to-text.
    transcribeLauncher: separateTranscribeLauncher(),
  );
  log('export jobs: ${tools.jobs.dir}');
  return McpServer(
    name: kServerName,
    title: kServerTitle,
    version: kServerVersion,
    instructions: kServerInstructions,
    tools: tools.tools,
    log: log,
  );
}

/// Entry point used by `bin/clipforge_mcp.dart`. Returns the exit code.
Future<int> runClipForgeMcp(List<String> args) async {
  void log(String message) => stderr.writeln('[clipforge-mcp] $message');

  final ServerOptions options;
  try {
    options = ServerOptions.parse(args, Platform.environment);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(kUsage);
    return 64;
  }
  if (options.help) {
    stdout.write(kUsage);
    return 0;
  }
  if (options.exportJob != null) {
    // The render process of one export (started by export_video).
    return runExportWorker(options.exportJob!);
  }
  if (options.transcribeJob != null) {
    // The process of one speech-to-text job (started by transcribe).
    return runTranscribeWorker(options.transcribeJob!);
  }
  if (options.version) {
    // The app's own version line (Help > About ClipForge), so the two can
    // be compared at a glance.
    stdout.writeln('${BuildInfo.current.describe()} '
        '(clipforge-mcp, MCP ${kProtocolVersions.first})');
    return 0;
  }

  log('${BuildInfo.current.describe()}, MCP ${kProtocolVersions.first}, '
      '${Platform.operatingSystem}');
  final McpServer server;
  try {
    server = await createClipForgeServer(options, log: log);
  } on FileSystemException catch (e) {
    log('cannot start: ${e.message}');
    return 1;
  }

  // Standard output carries protocol messages only: UTF-8, one per line.
  void write(String line) => stdout.add(utf8.encode('$line\n'));

  // Answer what is under way and end. Exports run in their own process
  // and keep going.
  final signals = <StreamSubscription<ProcessSignal>>[];
  Future<void> stop(ProcessSignal _) async {
    await server.shutdown();
    await stdout.flush();
    exit(0);
  }

  try {
    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
  } catch (_) {
    // Signals are not available everywhere; the server works without them.
  }

  await server.serve(stdin, write);
  for (final s in signals) {
    await s.cancel();
  }
  await stdout.flush();
  log('input closed, stopping');
  return 0;
}
