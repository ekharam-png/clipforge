// Builds the ClipForge MCP server as ONE self-contained executable.
//
//   dart run bin/build_mcp.dart [-o <output file>] [--build-name=1.4.0]
//       [--build-number=21] [--dart-define-from-file=<file.json>]
//       [--dart-define=KEY=VALUE ...]
//
// Default output: build/mcp/clipforge-mcp (clipforge-mcp.exe on Windows).
//
// Version: the build name and number default to pubspec.yaml's `version:`
// and are compiled in as FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER, the
// same defines `flutter build` gives the app; the other options take the
// same values as `flutter build`, so CI passes both the same arguments and
// the server's `--version` and get_status match the app's About box
// (lib/core/build_info.dart).
//
// Why a script: `dart compile exe bin/clipforge_mcp.dart` cannot be run
// directly in this package. The Flutter app depends on plugins with build
// hooks (objective_c, through path_provider), and `dart compile` refuses
// such packages; `dart build cli` works but produces a folder (executable
// plus a lib/ directory) instead of a single file. The server itself needs
// none of those plugins, so this script copies the pure-Dart sources
// (lib/core, lib/media, lib/mcp and the entry point) into a throw-away
// package that depends only on `path`, `uuid` and `archive` - pinned to the
// versions in pubspec.lock - and runs `dart compile exe` there. It also
// proves on every build that the server's imports stay free of Flutter.
//
// Uses only dart:io and dart:convert, so it has no dependencies of its own.

import 'dart:convert';
import 'dart:io';

const _packages = ['path', 'uuid', 'archive'];
const _sources = ['lib/core', 'lib/media', 'lib/mcp'];
const _entry = 'bin/clipforge_mcp.dart';

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

String _native(String posixPath) =>
    posixPath.replaceAll('/', Platform.pathSeparator);

Never _fail(String message) {
  stderr.writeln('build_mcp: $message');
  exit(1);
}

/// The package root: the folder above this script, or the current folder.
String _findRoot() {
  final candidates = <String>[];
  try {
    if (Platform.script.isScheme('file')) {
      candidates.add(File(Platform.script.toFilePath()).parent.parent.path);
    }
  } catch (_) {}
  candidates.add(Directory.current.path);
  for (final c in candidates) {
    if (File(_join(c, 'pubspec.yaml')).existsSync() &&
        File(_join(c, _native(_entry))).existsSync()) {
      return c;
    }
  }
  _fail('run this from the video-editor folder (pubspec.yaml and $_entry '
      'were not found)');
}

/// The version of [package] recorded in pubspec.lock.
String _lockedVersion(String lock, String package) {
  final m = RegExp('^  $package:\\r?\\n(?:    .*\\r?\\n)*?    version: "([^"]+)"',
          multiLine: true)
      .firstMatch(lock);
  if (m == null) _fail('package "$package" is not in pubspec.lock');
  return m.group(1)!;
}

void _copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      _copyDir(entity, Directory(_join(to.path, name)));
    } else if (entity is File && name.endsWith('.dart')) {
      entity.copySync(_join(to.path, name));
    }
  }
}

Future<int> _run(String executable, List<String> args, String workDir) async {
  stdout.writeln('> ${executable.split(Platform.pathSeparator).last} ${args.join(' ')}');
  final process = await Process.start(executable, args,
      workingDirectory: workDir, mode: ProcessStartMode.inheritStdio);
  return process.exitCode;
}

/// `KEY=VALUE` lines of a .env file, or the string values of a JSON object
/// (the two formats `flutter build --dart-define-from-file` reads).
Map<String, String> _definesFromFile(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('--dart-define-from-file: $path not found');
  final text = file.readAsStringSync();
  if (path.toLowerCase().endsWith('.json')) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      _fail('--dart-define-from-file: $path is not JSON (${e.message})');
    }
    if (json is! Map) _fail('--dart-define-from-file: $path must hold an object');
    return {for (final e in json.entries) '${e.key}': '${e.value}'};
  }
  return {
    for (final line in const LineSplitter().convert(text))
      if (line.trim().isNotEmpty && !line.trim().startsWith('#') && line.contains('='))
        line.substring(0, line.indexOf('=')).trim():
            line.substring(line.indexOf('=') + 1).trim(),
  };
}

const _usage = 'Usage: dart run bin/build_mcp.dart [-o <output file>] '
    '[--build-name=<x.y.z>] [--build-number=<n>] '
    '[--dart-define-from-file=<file>] [--dart-define=KEY=VALUE]';

Future<void> main(List<String> args) async {
  String? output;
  String? buildName;
  String? buildNumber;
  final defines = <String, String>{};
  // Accepts both "--name value" and "--name=value".
  String? valueOf(String name, int i) {
    final arg = args[i];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
    return null;
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String take(String name) {
      final inline = valueOf(name, i);
      if (inline != null) return inline;
      if (i + 1 >= args.length) _fail('$name needs a value. $_usage');
      return args[++i];
    }

    bool isOption(String name) => arg == name || arg.startsWith('$name=');
    if (arg == '-o' || isOption('--output')) {
      output = arg == '-o' ? take('-o') : take('--output');
    } else if (isOption('--build-name')) {
      buildName = take('--build-name');
    } else if (isOption('--build-number')) {
      buildNumber = take('--build-number');
    } else if (isOption('--dart-define-from-file')) {
      defines.addAll(_definesFromFile(take('--dart-define-from-file')));
    } else if (isOption('--dart-define')) {
      final pair = take('--dart-define');
      final eq = pair.indexOf('=');
      if (eq <= 0) _fail('--dart-define needs KEY=VALUE, got "$pair"');
      defines[pair.substring(0, eq)] = pair.substring(eq + 1);
    } else {
      _fail('unknown argument "$arg". $_usage');
    }
  }

  final root = _findRoot();
  final exeName = Platform.isWindows ? 'clipforge-mcp.exe' : 'clipforge-mcp';
  final out = File(output ?? _join(_join(_join(root, 'build'), 'mcp'), exeName)).absolute;
  // One staging folder per run, so that two builds at once do not collide.
  final stage = Directory(_join(_join(root, 'build'), 'mcp_stage_$pid'));
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  stage.createSync(recursive: true);

  for (final dir in _sources) {
    _copyDir(Directory(_join(root, _native(dir))),
        Directory(_join(stage.path, _native(dir))));
  }
  Directory(_join(stage.path, 'bin')).createSync();
  File(_join(root, _native(_entry))).copySync(_join(stage.path, _native(_entry)));

  final pubspec = File(_join(root, 'pubspec.yaml')).readAsStringSync();
  // The app's version, as `flutter build` reads it.
  final version = RegExp(r'^version:\s*([^\s+#]+)(?:\+(\d+))?', multiLine: true)
      .firstMatch(pubspec);
  if (version == null) _fail('pubspec.yaml has no "version:" line');
  defines['FLUTTER_BUILD_NAME'] = buildName ?? version.group(1)!;
  final number = buildNumber ?? version.group(2);
  if (number != null) defines['FLUTTER_BUILD_NUMBER'] = number;
  final lock = File(_join(root, 'pubspec.lock')).readAsStringSync();
  final sdk = RegExp(r'''^\s+sdk:\s*['"]?([^'"\r\n#]+)''', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1)
          ?.trim() ??
      '^3.0.0';
  File(_join(stage.path, 'pubspec.yaml')).writeAsStringSync([
    '# Generated by bin/build_mcp.dart. Do not edit.',
    'name: clipforge',
    'publish_to: none',
    'environment:',
    "  sdk: '$sdk'",
    'dependencies:',
    for (final package in _packages) '  $package: ${_lockedVersion(lock, package)}',
    '',
  ].join('\n'));

  final dart = Platform.resolvedExecutable;
  // The versions are normally in the local cache already (the app uses
  // them); go online only when they are not.
  if (await _run(dart, ['pub', 'get', '--offline'], stage.path) != 0 &&
      await _run(dart, ['pub', 'get'], stage.path) != 0) {
    _fail('"dart pub get" failed for the staging package in ${stage.path}');
  }

  out.parent.createSync(recursive: true);
  stdout.writeln('Version: ${defines['FLUTTER_BUILD_NAME']}'
      '${number == null ? '' : ' (build $number)'}');
  final code = await _run(dart, [
    'compile', 'exe',
    for (final e in defines.entries) '--define=${e.key}=${e.value}',
    _native(_entry), '-o', out.path,
  ], stage.path);
  if (code != 0 || !out.existsSync()) {
    _fail('"dart compile exe" failed (exit code $code)');
  }
  stage.deleteSync(recursive: true);
  stdout.writeln('Built ${out.path} (${(out.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
}
