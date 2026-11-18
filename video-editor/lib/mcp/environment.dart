// Where the MCP server finds things on this computer: the projects folder
// the app uses, the ffmpeg / ffprobe executables and the title fonts.
// Pure Dart. Everything that depends on the operating system takes it as a
// parameter so that the rules for Windows and macOS can be tested on Linux.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/title_layout.dart' show allTitleFontFiles;
import '../media/ffmpeg_command.dart' show FontPaths;
import '../media/process_media_engine.dart';
import 'mcp_protocol.dart' show ToolError;

const String kEnvProjectsDir = 'CLIPFORGE_PROJECTS_DIR';
const String kEnvFfmpeg = 'CLIPFORGE_FFMPEG';
const String kEnvFfprobe = 'CLIPFORGE_FFPROBE';
const String kEnvFontsDir = 'CLIPFORGE_FONTS_DIR';

const String kFontRegular = 'DejaVuSans.ttf';
const String kFontBold = 'DejaVuSans-Bold.ttf';

const String kUsage = '''
clipforge-mcp: lets Claude (or another MCP client) edit ClipForge projects.
It speaks the Model Context Protocol on standard input / output and is
normally started by Claude Desktop or Claude Code, not by hand.

Options (each can also be given as an environment variable):
  --projects-dir <path>   Folder with the ClipForge projects
                          ($kEnvProjectsDir). Default: the folder the
                          desktop app uses, <Documents>/ClipForge/projects.
  --ffmpeg <path>         ffmpeg executable ($kEnvFfmpeg). Default: next to
                          this program, then the PATH and the usual install
                          folders.
  --ffprobe <path>        ffprobe executable ($kEnvFfprobe). Default: next
                          to ffmpeg.
  --fonts-dir <path>      Folder with $kFontRegular and $kFontBold
                          (and the other title fonts: Rubik, Bona Nova,
                          Amatic SC) ($kEnvFontsDir). Default: next to
                          this program.
  --export-job <file>     Internal: render one export job (started by the
                          server itself; see export_video).
  --transcribe-job <file> Internal: run one speech-to-text job (see
                          transcribe).
  --version               Print the version and exit.
  --help                  Print this text and exit.
''';

/// Command-line options merged with their environment variables.
class ServerOptions {
  const ServerOptions({
    this.projectsDir,
    this.ffmpeg,
    this.ffprobe,
    this.fontsDir,
    this.exportJob,
    this.transcribeJob,
    this.help = false,
    this.version = false,
  });

  final String? projectsDir;
  final String? ffmpeg;
  final String? ffprobe;
  final String? fontsDir;

  /// `--export-job <file>`: run as the render process of that job.
  final String? exportJob;

  /// `--transcribe-job <file>`: run that speech-to-text job and exit.
  final String? transcribeJob;
  final bool help;
  final bool version;

  /// Parses [args]; an option on the command line wins over its environment
  /// variable. Throws a [FormatException] for unknown options or a missing
  /// value.
  static ServerOptions parse(List<String> args, Map<String, String> env) {
    final values = <String, String>{};
    var help = false;
    var version = false;
    const names = [
      'projects-dir', 'ffmpeg', 'ffprobe', 'fonts-dir', 'export-job', //
      'transcribe-job',
    ];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') {
        help = true;
        continue;
      }
      if (arg == '--version') {
        version = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw FormatException('Unexpected argument: $arg');
      }
      final eq = arg.indexOf('=');
      final name = arg.substring(2, eq < 0 ? arg.length : eq);
      if (!names.contains(name)) {
        throw FormatException('Unknown option: --$name');
      }
      final String value;
      if (eq >= 0) {
        value = arg.substring(eq + 1);
      } else {
        if (i + 1 >= args.length) {
          throw FormatException('Option --$name needs a value');
        }
        value = args[++i];
      }
      if (value.trim().isEmpty) {
        throw FormatException('Option --$name needs a value');
      }
      values[name] = value;
    }
    String? pick(String option, String variable) {
      final v = values[option] ?? env[variable];
      return v == null || v.trim().isEmpty ? null : v;
    }

    return ServerOptions(
      projectsDir: pick('projects-dir', kEnvProjectsDir),
      ffmpeg: pick('ffmpeg', kEnvFfmpeg),
      ffprobe: pick('ffprobe', kEnvFfprobe),
      fontsDir: pick('fonts-dir', kEnvFontsDir),
      exportJob: values['export-job'],
      transcribeJob: values['transcribe-job'],
      help: help,
      version: version,
    );
  }
}

/// Runs a program and returns its standard output, or null when it cannot
/// be started or fails. Replaceable in tests.
typedef OutputRunner = Future<String?> Function(
    String executable, List<String> arguments);

Future<String?> runForOutput(String executable, List<String> arguments) async {
  try {
    final r = await Process.run(executable, arguments,
            stdoutEncoding: const Utf8Codec(allowMalformed: true),
            stderrEncoding: const Utf8Codec(allowMalformed: true))
        .timeout(const Duration(seconds: 8));
    return r.exitCode == 0 ? r.stdout as String : null;
  } catch (_) {
    return null;
  }
}

/// The projects folder and how it was found.
class ProjectsDir {
  const ProjectsDir(this.path, this.source, {this.alsoChecked = const []});
  final String path;

  /// Short explanation for `get_status` and the start-up log.
  final String source;

  /// Other folders that were considered (default lookup only).
  final List<String> alsoChecked;
}

/// Replaces `%NAME%` by the value of the environment variable NAME
/// (case-insensitive, like Windows). Unknown names are left as they are.
String expandWindowsVariables(String text, Map<String, String> env) {
  final upper = {for (final e in env.entries) e.key.toUpperCase(): e.value};
  return text.replaceAllMapped(RegExp(r'%([^%]+)%'),
      (m) => upper[m.group(1)!.toUpperCase()] ?? m.group(0)!);
}

/// The `Personal` (= Documents) value from the output of
/// `reg query "...\User Shell Folders" /v Personal`, variables expanded.
String? parseRegDocuments(String output, Map<String, String> env) {
  final m = RegExp(r'^\s*Personal\s+REG_(?:EXPAND_)?SZ\s+(.+?)\s*$',
          multiLine: true, caseSensitive: false)
      .firstMatch(output.replaceAll('\r', ''));
  if (m == null) return null;
  final value = expandWindowsVariables(m.group(1)!, env).trim();
  return value.isEmpty || value.contains('%') ? null : value;
}

const String _shellFoldersKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders';

/// Finds the folder with the app's projects.
///
/// [explicit] (the `--projects-dir` option) is used as it is. Otherwise the
/// answer is `<Documents>/ClipForge/projects`, where Documents is found the
/// way the desktop app's `path_provider` plugin finds it:
///
///  * Windows: the "Documents" known folder. It is asked from the Shell
///    through PowerShell (`[Environment]::GetFolderPath('MyDocuments')`),
///    then read from the registry, then assumed to be
///    `%USERPROFILE%\Documents`. This follows a Documents folder that was
///    moved into OneDrive.
///  * macOS: `~/Documents` (the app is not sandboxed).
///  * Linux: `xdg-user-dir DOCUMENTS`, then `~/Documents`.
///
/// When the folder found that way holds no ClipForge projects folder but
/// one of the other candidates does, that one is used.
Future<ProjectsDir> resolveProjectsDir({
  String? explicit,
  Map<String, String>? environment,
  String? operatingSystem,
  OutputRunner run = runForOutput,
  bool Function(String path)? dirExists,
}) async {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final exists = dirExists ?? (path) => Directory(path).existsSync();
  final ctx = os == 'windows' ? p.windows : p.posix;

  if (explicit != null) {
    final path = ctx.normalize(
        ctx.isAbsolute(explicit) ? explicit : p.absolute(explicit));
    return ProjectsDir(path, 'set with --projects-dir / $kEnvProjectsDir');
  }

  // Documents folders, most trustworthy first, each with its origin.
  final documents = <({String path, String how})>[];
  void add(String? path, String how) {
    if (path == null) return;
    final clean = path.trim();
    if (clean.isEmpty || !ctx.isAbsolute(clean)) return;
    final normal = ctx.normalize(clean);
    if (documents.any((d) => ctx.equals(d.path, normal))) return;
    documents.add((path: normal, how: how));
  }

  if (os == 'windows') {
    final shell = await run('powershell', const [
      '-NoProfile', '-NonInteractive', '-Command',
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Environment]::GetFolderPath('MyDocuments')",
    ]);
    add(shell?.split('\n').first, 'Windows Documents folder (asked from the Shell)');
    final reg = await run('reg', const ['query', _shellFoldersKey, '/v', 'Personal']);
    if (reg != null) {
      final fromReg = parseRegDocuments(reg, env);
      // reg.exe prints in the console code page, so a non-ASCII path may be
      // garbled: only believe a folder that exists.
      if (fromReg != null && exists(fromReg)) {
        add(fromReg, 'Windows Documents folder (from the registry)');
      }
    }
    final home = env['USERPROFILE'] ?? env['HOME'];
    for (final name in const ['OneDrive', 'OneDriveConsumer', 'OneDriveCommercial']) {
      final root = env[name];
      if (root != null && root.isNotEmpty) {
        add(ctx.join(root, 'Documents'), '%$name%\\Documents');
      }
    }
    if (home != null && home.isNotEmpty) {
      add(ctx.join(home, 'Documents'), '%USERPROFILE%\\Documents');
    }
  } else {
    if (os == 'linux') {
      final xdg = await run('xdg-user-dir', const ['DOCUMENTS']);
      add(xdg?.split('\n').first, 'xdg-user-dir DOCUMENTS');
    }
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      add(ctx.join(home, 'Documents'), '~/Documents');
    }
  }
  if (documents.isEmpty) {
    throw const FileSystemException(
        'Cannot find the Documents folder. Start the server with '
        '--projects-dir <folder> (the folder that holds the ClipForge projects).');
  }

  String projectsIn(String docs) => ctx.join(docs, 'ClipForge', 'projects');
  var chosen = documents.first;
  var note = '';
  if (!exists(projectsIn(chosen.path))) {
    for (final d in documents.skip(1)) {
      if (exists(projectsIn(d.path))) {
        note = ' (used because ${projectsIn(chosen.path)} does not exist)';
        chosen = d;
        break;
      }
    }
  }
  return ProjectsDir(
    projectsIn(chosen.path),
    'default: ${chosen.how}$note',
    alsoChecked: [
      for (final d in documents)
        if (!identical(d, chosen)) projectsIn(d.path),
    ],
  );
}

/// An executable that was found and could be started.
class FoundTool {
  const FoundTool(this.path, this.version);
  final String path;
  final String version;
}

/// One-line instruction for installing ffmpeg on [operatingSystem].
String ffmpegInstallHint([String? operatingSystem]) {
  switch (operatingSystem ?? Platform.operatingSystem) {
    case 'windows':
      return 'Install it by opening PowerShell (or Terminal) and running: '
          'winget install ffmpeg   — then close and reopen Claude so it '
          'sees the new program.';
    case 'macos':
      return 'Install it by opening Terminal and running: brew install ffmpeg '
          '  (this needs Homebrew from https://brew.sh) — then quit and '
          'reopen Claude.';
    default:
      return 'Install it with your package manager, for example: '
          'sudo apt install ffmpeg';
  }
}

/// Folders where ffmpeg usually lands but which are often missing from the
/// PATH of a program started by a desktop app.
List<String> usualToolDirs(String os, Map<String, String> env) {
  if (os == 'windows') {
    final local = env['LOCALAPPDATA'];
    final home = env['USERPROFILE'];
    final data = env['ProgramData'] ?? r'C:\ProgramData';
    final programs = env['ProgramFiles'] ?? r'C:\Program Files';
    return [
      if (local != null) p.windows.join(local, 'Microsoft', 'WinGet', 'Links'),
      p.windows.join(programs, 'WinGet', 'Links'),
      p.windows.join(data, 'chocolatey', 'bin'),
      if (home != null) p.windows.join(home, 'scoop', 'shims'),
      p.windows.join(programs, 'ffmpeg', 'bin'),
      r'C:\ffmpeg\bin',
    ];
  }
  final home = env['HOME'];
  return [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/opt/local/bin',
    '/usr/bin',
    if (home != null) p.posix.join(home, '.local', 'bin'),
    if (home != null) p.posix.join(home, 'bin'),
  ];
}

/// Finds and remembers ffmpeg / ffprobe and builds the media engine.
///
/// A program that was not found is looked for again on the next request,
/// so installing ffmpeg does not always need a restart of the server.
class MediaTools {
  MediaTools({
    this.ffmpegOption,
    this.ffprobeOption,
    this.fonts,
    Map<String, String>? environment,
    String? operatingSystem,
    String? executableDir,
  })  : _env = environment ?? Platform.environment,
        _os = operatingSystem ?? Platform.operatingSystem,
        _exeDir = executableDir ?? p.dirname(Platform.resolvedExecutable);

  /// Explicit paths (options / environment variables); null = search.
  final String? ffmpegOption;
  final String? ffprobeOption;

  /// Title fonts, when they were found.
  final FontPaths? fonts;
  final Map<String, String> _env;
  final String _os;
  final String _exeDir;

  FoundTool? _ffmpeg;
  FoundTool? _ffprobe;
  ProcessMediaEngine? _engine;

  Future<FoundTool?> ffmpeg() async =>
      _ffmpeg ??= await _find('ffmpeg', ffmpegOption, null);

  Future<FoundTool?> ffprobe() async {
    if (_ffprobe != null) return _ffprobe;
    final near = (await ffmpeg())?.path;
    return _ffprobe = await _find(
        'ffprobe', ffprobeOption, near == null ? null : p.dirname(near));
  }

  Future<FoundTool?> _find(String name, String? explicit, String? near) async {
    if (explicit != null) return _try(explicit);
    final exe = _os == 'windows' ? '$name.exe' : name;
    final separator = _os == 'windows' ? ';' : ':';
    final pathVar = _env['PATH'] ?? _env['Path'] ?? '';
    final dirs = <String>[
      if (near != null && near != '.') near,
      _exeDir,
      ...pathVar.split(separator).where((d) => d.trim().isNotEmpty),
      ...usualToolDirs(_os, _env),
    ];
    final seen = <String>{};
    for (final dir in dirs) {
      final candidate = p.join(dir, exe);
      if (!seen.add(candidate) || !File(candidate).existsSync()) continue;
      final found = await _try(candidate);
      if (found != null) return found;
    }
    return null;
  }

  static Future<FoundTool?> _try(String path) async {
    final out = await runForOutput(path, const ['-hide_banner', '-version']);
    if (out == null) return null;
    final m = RegExp(r'version\s+(\S+)').firstMatch(out);
    return FoundTool(path, m?.group(1) ?? 'unknown');
  }

  /// The engine, or a [ToolError] that says what is missing and how to
  /// install it.
  Future<ProcessMediaEngine> requireEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final mpeg = await ffmpeg();
    final probe = await ffprobe();
    if (mpeg == null || probe == null) {
      final missing = [
        if (mpeg == null) 'ffmpeg',
        if (probe == null) 'ffprobe',
      ].join(' and ');
      final configured = [
        if (mpeg == null && ffmpegOption != null) ffmpegOption,
        if (probe == null && ffprobeOption != null) ffprobeOption,
      ];
      throw ToolError(
          'This needs the free program FFmpeg, and $missing could not be '
          '${configured.isEmpty ? 'found on this computer' : 'started from the configured path (${configured.join(', ')})'}. '
          '${ffmpegInstallHint(_os)} '
          'If it is installed in an unusual place, start the server with '
          '--ffmpeg <path> and --ffprobe <path>. '
          'Editing tools that do not read media files keep working without it.');
    }
    return _engine = ProcessMediaEngine(
        ffmpegPath: mpeg.path, ffprobePath: probe.path, fonts: fonts);
  }
}

/// Result of [locateFonts].
class FontLookup {
  const FontLookup(this.fonts, this.checked);

  /// Null when no folder holds both font files.
  final FontPaths? fonts;

  /// Folders that were looked at, in order.
  final List<String> checked;
}

/// Looks for the two DejaVu fonts that exported titles are drawn with.
///
/// [explicitDir] (`--fonts-dir`) is the only place looked at when given.
/// Otherwise: `fonts/` next to the executable, the Flutter bundle the
/// executable was shipped in (Windows / Linux: `data/flutter_assets/...`;
/// macOS: inside `ClipForge.app` next to or around the executable), and
/// finally the repository's `assets/fonts` (running from source).
FontLookup locateFonts({
  String? explicitDir,
  String? executableDir,
  String? scriptDir,
  String? workingDir,
}) {
  final exe = executableDir ?? p.dirname(Platform.resolvedExecutable);
  String? script = scriptDir;
  if (script == null) {
    try {
      if (Platform.script.isScheme('file')) {
        script = p.dirname(Platform.script.toFilePath());
      }
    } catch (_) {}
  }
  final cwd = workingDir ?? Directory.current.path;
  const assets = ['flutter_assets', 'assets', 'fonts'];
  const inApp = [
    'Contents', 'Frameworks', 'App.framework', 'Resources', ...assets, //
  ];
  final dirs = explicitDir != null
      ? [explicitDir]
      : <String>[
          p.join(exe, 'fonts'),
          exe,
          p.join(exe, 'data', 'flutter_assets', 'assets', 'fonts'),
          // macOS: beside the .app, or inside its Contents/MacOS folder.
          p.joinAll([exe, 'ClipForge.app', ...inApp]),
          p.joinAll([exe, '..', 'ClipForge.app', ...inApp]),
          p.joinAll([exe, '..', 'Frameworks', 'App.framework', 'Resources', ...assets]),
          '/Applications/ClipForge.app/${inApp.join('/')}',
          if (script != null) p.join(script, 'fonts'),
          if (script != null) p.join(script, '..', 'assets', 'fonts'),
          p.join(cwd, 'assets', 'fonts'),
        ];
  final checked = <String>[];
  for (final d in dirs) {
    final dir = p.normalize(p.absolute(d));
    if (checked.contains(dir)) continue;
    checked.add(dir);
    final regular = p.join(dir, kFontRegular);
    final bold = p.join(dir, kFontBold);
    if (File(regular).existsSync() && File(bold).existsSync()) {
      // The other title fonts, when they are in the same folder (a title
      // in a missing font is drawn in DejaVu Sans).
      final files = <String, String>{
        for (final name in allTitleFontFiles)
          if (File(p.join(dir, name)).existsSync()) name: p.join(dir, name),
      };
      return FontLookup(
          FontPaths(regular: regular, bold: bold, files: files), checked);
    }
  }
  return FontLookup(null, checked);
}
