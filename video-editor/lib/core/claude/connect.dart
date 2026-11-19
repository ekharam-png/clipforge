// "Connect to Claude" done by the app itself (1.14): find Claude Code and
// Claude Desktop on this computer, say whether each is connected to
// ClipForge's helper, connect / disconnect them, and say whether the
// helper is in use right now.
//
// SAFETY RULES of this file:
//  * only ever the entry called `clipforge` is touched - in Claude Code
//    through its own `claude mcp` commands, in Claude Desktop inside
//    `mcpServers` of its config file; every other key stays as it is;
//  * a config file that cannot be read as plain JSON is never rewritten
//    (the user is told, and nothing changes);
//  * a backup with the date in its name is written next to the config
//    file before every change;
//  * nothing secret is read or written; everything here happens only when
//    the user presses a button on the Connect page.
//
// Pure Dart. Everything that touches the computer goes through
// [ConnectHost], so that tests run on pretend computers.
//
// NOT VERIFIED AGAINST A REAL CLAUDE INSTALL (none in the build
// container): the exact wording of `claude mcp get` / `list`, where the
// Microsoft Store build of Claude Desktop keeps its folder, and the name
// of the folder of an installed extension. The parsing is defensive and
// the fixtures in test/core/fixtures/claude are written from memory.

import 'dart:convert';

import 'package:path/path.dart' as p;

/// The one entry this file ever touches.
const String kClaudeEntryName = 'clipforge';

/// What a program run gave back.
class RunResult {
  const RunResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get output => [stdout.trim(), stderr.trim()].where((s) => s.isNotEmpty).join('\n');
}

/// The computer, as far as connecting Claude needs it.
abstract class ConnectHost {
  /// "windows", "macos" or "linux".
  String get os;
  Map<String, String> get environment;
  bool fileExists(String path);
  bool dirExists(String path);

  /// Names of the folders directly inside [path] (empty when unreadable).
  List<String> listDirs(String path);

  /// Null when the file cannot be read.
  String? readText(String path);
  void writeText(String path, String text);
  void deleteFile(String path);
  DateTime now();

  /// Runs [exe] and waits (at most [timeout]). Throws when it cannot start.
  Future<RunResult> run(String exe, List<String> args,
      {String? workingDirectory, Duration timeout});
  Future<bool> processAlive(int pid);
}

p.Context _ctx(String os) => os == 'windows' ? p.windows : p.posix;

String? _home(ConnectHost h) {
  final e = h.environment;
  final v = h.os == 'windows' ? (e['USERPROFILE'] ?? e['HOME']) : e['HOME'];
  return v == null || v.trim().isEmpty ? null : v;
}

/// True when [a] and [b] name the same file (Windows: whatever the case
/// and the slashes).
bool samePath(String a, String b, String os) {
  final c = _ctx(os);
  var x = c.normalize(a.trim()), y = c.normalize(b.trim());
  if (os == 'windows') {
    x = x.toLowerCase();
    y = y.toLowerCase();
  }
  return x == y;
}

/// Whether [command] looks like a ClipForge helper (an older copy
/// somewhere else): its file is called clipforge-mcp.
bool looksLikeClipForgeHelper(String command) {
  final name = command.replaceAll('\\', '/').split('/').last.toLowerCase();
  return name == 'clipforge-mcp' || name == 'clipforge-mcp.exe';
}

// Claude Code ---------------------------------------------------------------

/// The `claude` program of Claude Code, or null: on the PATH, then in the
/// places its installers use.
String? findClaudeCode(ConnectHost h) {
  final c = _ctx(h.os);
  final names = h.os == 'windows'
      ? const ['claude.exe', 'claude.cmd', 'claude.bat', 'claude.ps1']
      : const ['claude'];
  final dirs = <String>[
    ...(h.environment['PATH'] ?? h.environment['Path'] ?? '')
        .split(h.os == 'windows' ? ';' : ':')
        .where((d) => d.trim().isNotEmpty),
  ];
  final home = _home(h);
  if (home != null) {
    dirs.addAll([
      c.join(home, '.local', 'bin'),
      c.join(home, '.claude', 'local'),
      c.join(home, '.claude', 'bin'),
    ]);
    if (h.os == 'windows') {
      final roaming = h.environment['APPDATA'];
      final local = h.environment['LOCALAPPDATA'];
      if (roaming != null) dirs.add(c.join(roaming, 'npm'));
      if (local != null) {
        dirs.add(c.join(local, 'Programs', 'claude'));
        dirs.add(c.join(local, 'Microsoft', 'WinGet', 'Links'));
      }
    } else {
      dirs.addAll([
        '/usr/local/bin', '/opt/homebrew/bin', //
        c.join(home, '.npm-global', 'bin'),
      ]);
    }
  }
  for (final d in dirs) {
    for (final n in names) {
      // A .ps1 alone cannot be started as a program.
      if (n.endsWith('.ps1')) continue;
      final path = c.join(d.trim(), n);
      if (h.fileExists(path)) return path;
    }
  }
  return null;
}

/// What `claude mcp get clipforge` (or a line of `claude mcp list`) says.
class McpEntryInfo {
  const McpEntryInfo({this.found = false, this.command, this.scope, this.connected});

  /// An entry called clipforge exists.
  final bool found;

  /// The program it starts (null when the output did not say).
  final String? command;

  /// "user", "local" or "project" (null when the output did not say).
  final String? scope;

  /// What Claude Code says about the connection, when it says.
  final bool? connected;
}

String _unquote(String s) {
  var t = s.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'")))) {
    t = t.substring(1, t.length - 1);
  }
  return t;
}

/// Reads the answer of `claude mcp get clipforge`, defensively: the
/// wording has changed between versions, so only "Command:" / "Scope:" /
/// "Status:" lines are looked for, anywhere, in any letter case; an
/// answer that says the server was not found (or names no command and
/// does not mention clipforge) counts as "no entry".
McpEntryInfo parseMcpGet(String output, {int exitCode = 0}) {
  final text = output.replaceAll('\r', '');
  final lower = text.toLowerCase();
  if (lower.contains('no mcp server') ||
      lower.contains('not found') ||
      lower.contains('does not exist')) {
    return const McpEntryInfo();
  }
  String? command, scope;
  bool? connected;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final m = RegExp(r'^(command|scope|status)\s*:\s*(.*)$', caseSensitive: false)
        .firstMatch(line);
    if (m == null) continue;
    final value = m.group(2)!.trim();
    switch (m.group(1)!.toLowerCase()) {
      case 'command':
        if (value.isNotEmpty) command = _unquote(value);
      case 'scope':
        final v = value.toLowerCase();
        // ("Local config (private to you in this project)" names both.)
        scope = v.startsWith('user')
            ? 'user'
            : v.startsWith('local')
                ? 'local'
                : v.startsWith('project')
                    ? 'project'
                    : v.contains('user')
                        ? 'user'
                        : v.contains('local')
                            ? 'local'
                            : v.contains('project')
                                ? 'project'
                                : null;
      case 'status':
        final v = value.toLowerCase();
        connected = v.contains('fail') || v.contains('error') || v.contains('✗')
            ? false
            : (v.contains('connected') || v.contains('✓') ? true : null);
    }
  }
  final found = command != null ||
      (exitCode == 0 && lower.contains(kClaudeEntryName) && scope != null);
  return McpEntryInfo(
      found: found, command: command, scope: scope, connected: connected);
}

/// The clipforge line of `claude mcp list` ("clipforge: /path/to/helper -
/// ✓ Connected"), or "no entry".
McpEntryInfo parseMcpList(String output) {
  for (final raw in output.replaceAll('\r', '').split('\n')) {
    final m = RegExp(r'^\s*clipforge\s*:\s*(.+)$', caseSensitive: false).firstMatch(raw);
    if (m == null) continue;
    var rest = m.group(1)!.trim();
    bool? connected;
    final dash = rest.lastIndexOf(' - ');
    if (dash > 0) {
      final status = rest.substring(dash + 3).toLowerCase();
      connected = status.contains('fail') || status.contains('✗')
          ? false
          : (status.contains('connected') || status.contains('✓') ? true : null);
      rest = rest.substring(0, dash).trim();
    }
    // "command arg arg": the helper takes no arguments, so a path with
    // spaces is taken whole when it ends like the helper does.
    final command = _unquote(rest);
    return McpEntryInfo(found: true, command: command, connected: connected);
  }
  return const McpEntryInfo();
}

/// A clipforge entry found in Claude Code's own settings file.
class CodeConfigEntry {
  const CodeConfigEntry(this.scope, this.command, [this.projectDir]);

  /// "user" or "local".
  final String scope;
  final String command;

  /// For "local": the project folder it belongs to.
  final String? projectDir;
}

/// Where Claude Code keeps its settings (read only, never written here).
String? claudeCodeConfigPath(ConnectHost h) {
  final home = _home(h);
  return home == null ? null : _ctx(h.os).join(home, '.claude.json');
}

/// The clipforge entries in Claude Code's settings text: the user-wide
/// one (`mcpServers.clipforge`) and those of single project folders
/// (`projects.<folder>.mcpServers.clipforge`). Empty when the text is not
/// JSON.
List<CodeConfigEntry> codeConfigEntries(String? text) {
  if (text == null) return const [];
  Object? json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    return const [];
  }
  if (json is! Map) return const [];
  final out = <CodeConfigEntry>[];
  String? commandOf(Object? servers) {
    if (servers is! Map) return null;
    final e = servers[kClaudeEntryName];
    if (e is! Map) return null;
    final c = e['command'];
    return c is String ? c : '';
  }

  final user = commandOf(json['mcpServers']);
  if (user != null) out.add(CodeConfigEntry('user', user));
  final projects = json['projects'];
  if (projects is Map) {
    for (final e in projects.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final c = commandOf(v['mcpServers']);
      if (c != null) out.add(CodeConfigEntry('local', c, '${e.key}'));
    }
  }
  return out;
}

enum ConnectState {
  /// The program / app is not on this computer.
  notInstalled,
  notConnected,

  /// Connected to the helper ClipForge keeps up to date.
  connected,

  /// A clipforge entry exists but starts another copy of the helper.
  connectedElsewhere,

  /// Its settings could not be read (said in [detail]).
  unreadable,
}

class ClaudeCodeStatus {
  const ClaudeCodeStatus({
    required this.state,
    this.program,
    this.command,
    this.others = const [],
    this.detail = '',
  });
  final ConnectState state;

  /// The `claude` program; null when it was not found.
  final String? program;

  /// What the user-wide clipforge entry starts.
  final String? command;

  /// Entries of single project folders that start an OLD ClipForge helper
  /// (Connect offers to remove them).
  final List<CodeConfigEntry> others;

  /// The command that was run and what it answered ("Details").
  final String detail;
}

/// How Claude Code is connected: asked from `claude mcp get clipforge`
/// when the program is there, and read from its settings file besides
/// (also when the program was not found).
Future<ClaudeCodeStatus> claudeCodeStatus(ConnectHost h, String launcher) async {
  final program = findClaudeCode(h);
  final configPath = claudeCodeConfigPath(h);
  final entries =
      codeConfigEntries(configPath == null ? null : h.readText(configPath));
  final others = [
    for (final e in entries)
      if (e.scope == 'local' &&
          looksLikeClipForgeHelper(e.command) &&
          !samePath(e.command, launcher, h.os))
        e,
  ];
  String? command;
  var detail = '';
  var asked = false;
  if (program != null) {
    try {
      final r = await h.run(program, ['mcp', 'get', kClaudeEntryName],
          timeout: const Duration(seconds: 20));
      detail = '> claude mcp get $kClaudeEntryName\n${r.output}';
      final info = parseMcpGet(r.output, exitCode: r.exitCode);
      asked = true;
      if (info.found && info.scope != 'local' && info.scope != 'project') {
        command = info.command ?? '';
      }
    } catch (e) {
      detail = '> claude mcp get $kClaudeEntryName\n(could not be run: $e)';
    }
  }
  // The settings file knows the user-wide entry too (and is all there is
  // when the program was not found or did not answer).
  final fromFile = entries.where((e) => e.scope == 'user').firstOrNull?.command;
  if (command == null || command.isEmpty) command = fromFile ?? command;
  if (program == null && fromFile == null) {
    return ClaudeCodeStatus(
        state: ConnectState.notInstalled, others: others, detail: detail);
  }
  if (command == null) {
    return ClaudeCodeStatus(
        state: asked || fromFile == null
            ? ConnectState.notConnected
            : ConnectState.unreadable,
        program: program,
        others: others,
        detail: detail);
  }
  return ClaudeCodeStatus(
      state: command.isNotEmpty && samePath(command, launcher, h.os)
          ? ConnectState.connected
          : ConnectState.connectedElsewhere,
      program: program,
      command: command,
      others: others,
      detail: detail);
}

/// What Connect / Disconnect did, for "Details".
class ConnectOutcome {
  const ConnectOutcome(this.ok, this.message, this.log);
  final bool ok;

  /// One or two plain sentences.
  final String message;

  /// The commands run (or the files written) and their answers.
  final String log;
}

/// Connects Claude Code: removes a clipforge entry that is already there
/// (user-wide, and [removeOthers]: those of single project folders that
/// start an old ClipForge helper), then runs
/// `claude mcp add --scope user clipforge -- <launcher>`.
Future<ConnectOutcome> connectClaudeCode(ConnectHost h, String launcher,
    {List<CodeConfigEntry> removeOthers = const []}) async {
  final program = findClaudeCode(h);
  if (program == null) {
    return const ConnectOutcome(
        false,
        'Claude Code was not found on this computer. Install it, or copy '
            'the line below into a terminal where the "claude" command works.',
        '');
  }
  final log = StringBuffer();
  Future<RunResult?> run(List<String> args, {String? cwd}) async {
    log.writeln('> claude ${args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ')}'
        '${cwd == null ? '' : '   (in $cwd)'}');
    try {
      final r = await h.run(program, args,
          workingDirectory: cwd, timeout: const Duration(seconds: 40));
      if (r.output.isNotEmpty) log.writeln(r.output);
      return r;
    } catch (e) {
      log.writeln('(could not be run: $e)');
      return null;
    }
  }

  // A previous entry would make "add" refuse. Removing one that is not
  // there is harmless (its answer is only logged).
  await run(['mcp', 'remove', kClaudeEntryName, '-s', 'user']);
  for (final e in removeOthers) {
    final dir = e.projectDir;
    if (dir == null || !h.dirExists(dir)) continue;
    await run(['mcp', 'remove', kClaudeEntryName, '-s', 'local'], cwd: dir);
  }
  final added = await run(
      ['mcp', 'add', '--scope', 'user', kClaudeEntryName, '--', launcher]);
  if (added == null || added.exitCode != 0) {
    return ConnectOutcome(
        false,
        'Claude Code did not accept the connection'
            '${added == null ? '' : ' (it answered with code ${added.exitCode})'}. '
            'See Details; the line below does the same by hand.',
        log.toString().trimRight());
  }
  return ConnectOutcome(
      true,
      'Claude Code is connected. Start a new Claude Code session: it reads '
          'its list of tools when it starts ("/mcp" shows the list).',
      log.toString().trimRight());
}

Future<ConnectOutcome> disconnectClaudeCode(ConnectHost h) async {
  final program = findClaudeCode(h);
  if (program == null) {
    return const ConnectOutcome(false, 'Claude Code was not found.', '');
  }
  const args = ['mcp', 'remove', kClaudeEntryName, '-s', 'user'];
  try {
    final r = await h.run(program, args, timeout: const Duration(seconds: 40));
    final log = '> claude ${args.join(' ')}\n${r.output}';
    return ConnectOutcome(
        r.exitCode == 0,
        r.exitCode == 0
            ? 'Claude Code is no longer connected to ClipForge.'
            : 'Claude Code could not remove the connection; see Details.',
        log);
  } catch (e) {
    return ConnectOutcome(false, 'Claude Code could not be run ($e).', '');
  }
}

// Claude Desktop ------------------------------------------------------------

const String kDesktopConfigName = 'claude_desktop_config.json';

/// A place where Claude Desktop keeps its settings on this computer.
class DesktopPlace {
  const DesktopPlace(this.dir, this.kind);

  /// The "Claude" settings folder (it exists).
  final String dir;

  /// "the Claude app" or "Claude from the Microsoft Store".
  final String kind;
}

/// Every Claude Desktop settings folder that exists here. Windows: the
/// normal one (`%APPDATA%\Claude`) and the Microsoft Store build's
/// (`%LOCALAPPDATA%\Packages\<a package with "Claude" in its name>\
/// LocalCache\Roaming\Claude`); macOS: `~/Library/Application
/// Support/Claude`; Linux: `~/.config/Claude`.
List<DesktopPlace> findClaudeDesktop(ConnectHost h) {
  final c = _ctx(h.os);
  final out = <DesktopPlace>[];
  void add(String? dir, String kind) {
    if (dir != null && h.dirExists(dir) && !out.any((x) => x.dir == dir)) {
      out.add(DesktopPlace(dir, kind));
    }
  }

  final home = _home(h);
  switch (h.os) {
    case 'windows':
      final roaming = h.environment['APPDATA'] ??
          (home == null ? null : c.join(home, 'AppData', 'Roaming'));
      final local = h.environment['LOCALAPPDATA'] ??
          (home == null ? null : c.join(home, 'AppData', 'Local'));
      if (roaming != null) add(c.join(roaming, 'Claude'), 'the Claude app');
      if (local != null) {
        final packages = c.join(local, 'Packages');
        for (final name in h.listDirs(packages)) {
          if (!name.toLowerCase().contains('claude')) continue;
          add(c.join(packages, name, 'LocalCache', 'Roaming', 'Claude'),
              'Claude from the Microsoft Store');
        }
      }
    case 'macos':
      if (home != null) {
        add(c.join(home, 'Library', 'Application Support', 'Claude'),
            'the Claude app');
      }
    default:
      final config = h.environment['XDG_CONFIG_HOME'] ??
          (home == null ? null : c.join(home, '.config'));
      if (config != null) add(c.join(config, 'Claude'), 'the Claude app');
  }
  return out;
}

/// The result of changing a Claude Desktop config text.
class DesktopEdit {
  const DesktopEdit({this.text, this.previous, this.problem, this.changed = false});

  /// The new file content; null when nothing may be written ([problem]).
  final String? text;

  /// What the clipforge entry started before (null: there was none).
  final String? previous;

  /// Why the file must not be touched, in plain words.
  final String? problem;
  final bool changed;
}

/// The `command` of the clipforge entry in a config text; null when there
/// is none (or the text is not JSON).
String? desktopEntryCommand(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  try {
    final json = jsonDecode(text);
    if (json is! Map) return null;
    final servers = json['mcpServers'];
    if (servers is! Map) return null;
    final e = servers[kClaudeEntryName];
    if (e is! Map) return null;
    final c = e['command'];
    return c is String ? c : '';
  } catch (_) {
    return null;
  }
}

/// [text] (the content of claude_desktop_config.json, or null when the
/// file does not exist) with the `mcpServers.clipforge` entry pointing at
/// [launcher] - or, with [remove], without that entry. Everything else is
/// kept: the other keys and servers, their order, and - where the file is
/// laid out the usual way - every other byte (only the entry itself is
/// put in or taken out). A text that is not plain JSON (comments, a
/// trailing comma, something that is not an object) is refused.
DesktopEdit editDesktopConfig(String? text, String launcher, {bool remove = false}) {
  final entry = <String, dynamic>{'command': launcher, 'args': <String>[]};
  if (text == null || text.trim().isEmpty) {
    if (remove) return const DesktopEdit();
    return DesktopEdit(
        text: '${const JsonEncoder.withIndent('  ').convert({
              'mcpServers': {kClaudeEntryName: entry},
            })}\n',
        changed: true);
  }
  Object? json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    return const DesktopEdit(
        problem: 'Claude\'s settings file is not plain JSON (it may hold a '
            'comment or a stray comma), so ClipForge will not change it. '
            'Nothing was written. Use the extension file below instead, or '
            'repair the file by hand.');
  }
  if (json is! Map) {
    return const DesktopEdit(
        problem: 'Claude\'s settings file does not hold what is expected '
            '(a list of settings), so ClipForge will not change it.');
  }
  final servers = json['mcpServers'];
  if (servers != null && servers is! Map) {
    return const DesktopEdit(
        problem: 'The "mcpServers" part of Claude\'s settings file is not a '
            'list of servers, so ClipForge will not change it.');
  }
  final previous = desktopEntryCommand(text);
  if (remove && previous == null) return DesktopEdit(text: text);
  if (!remove && previous == launcher) {
    final old = (servers as Map)[kClaudeEntryName] as Map;
    final args = old['args'];
    if ((args == null || (args is List && args.isEmpty)) && old['env'] == null) {
      return DesktopEdit(text: text, previous: previous);
    }
  }
  // What the file must mean afterwards.
  final wanted = <String, dynamic>{};
  var placed = false;
  for (final e in json.entries) {
    if (e.key == 'mcpServers') {
      final next = <String, dynamic>{};
      for (final s in (e.value as Map).entries) {
        if (s.key == kClaudeEntryName) {
          if (!remove) next[kClaudeEntryName] = entry;
        } else {
          next['${s.key}'] = s.value;
        }
      }
      if (!remove && !next.containsKey(kClaudeEntryName)) {
        next[kClaudeEntryName] = entry;
      }
      wanted['mcpServers'] = next;
      placed = true;
    } else {
      wanted['${e.key}'] = e.value;
    }
  }
  if (!placed && !remove) {
    wanted['mcpServers'] = {kClaudeEntryName: entry};
  }
  // Try to change only the entry's own bytes; when the result does not
  // mean exactly [wanted], write the whole file freshly laid out instead.
  final indent = _indentOf(text);
  String? edited;
  try {
    edited = _spliceEntry(text, remove ? null : entry, indent);
  } catch (_) {
    edited = null;
  }
  if (edited != null) {
    try {
      if (jsonEncode(jsonDecode(edited)) != jsonEncode(wanted)) edited = null;
    } catch (_) {
      edited = null;
    }
  }
  edited ??= '${JsonEncoder.withIndent(indent).convert(wanted)}\n';
  return DesktopEdit(text: edited, previous: previous, changed: true);
}

String _indentOf(String text) {
  final m = RegExp(r'\n([ \t]+)"').firstMatch(text);
  return m == null ? '  ' : m.group(1)!;
}

/// A little JSON reader that knows WHERE things are in the text.
class _Scan {
  _Scan(this.s);
  final String s;
  int i = 0;

  void ws() {
    while (i < s.length && ' \t\r\n'.contains(s[i])) {
      i++;
    }
  }

  String string() {
    if (s[i] != '"') throw const FormatException('string');
    final start = i;
    i++;
    while (s[i] != '"') {
      if (s[i] == r'\') i++;
      i++;
    }
    i++;
    return jsonDecode(s.substring(start, i)) as String;
  }

  /// Skips one value.
  void value() {
    ws();
    final c = s[i];
    if (c == '"') {
      string();
    } else if (c == '{' || c == '[') {
      final close = c == '{' ? '}' : ']';
      i++;
      ws();
      if (s[i] == close) {
        i++;
        return;
      }
      while (true) {
        ws();
        if (c == '{') {
          string();
          ws();
          if (s[i] != ':') throw const FormatException('colon');
          i++;
        }
        value();
        ws();
        if (s[i] == ',') {
          i++;
          continue;
        }
        if (s[i] == close) {
          i++;
          return;
        }
        throw const FormatException('list');
      }
    } else {
      while (i < s.length && !',}] \t\r\n'.contains(s[i])) {
        i++;
      }
    }
  }

  /// The members of the object that starts at [i]: for each, where its
  /// key starts and where its value starts and ends. Leaves [i] after the
  /// closing brace; [open] / [close] are the braces' places.
  ({int open, int close, List<({String key, int keyAt, int valueAt, int end})> members})
      object() {
    ws();
    if (s[i] != '{') throw const FormatException('object');
    final open = i;
    i++;
    final members = <({String key, int keyAt, int valueAt, int end})>[];
    ws();
    if (s[i] == '}') {
      i++;
      return (open: open, close: i - 1, members: members);
    }
    while (true) {
      ws();
      final keyAt = i;
      final key = string();
      ws();
      if (s[i] != ':') throw const FormatException('colon');
      i++;
      ws();
      final valueAt = i;
      value();
      members.add((key: key, keyAt: keyAt, valueAt: valueAt, end: i));
      ws();
      if (s[i] == ',') {
        i++;
        continue;
      }
      if (s[i] == '}') {
        i++;
        return (open: open, close: i - 1, members: members);
      }
      throw const FormatException('object end');
    }
  }
}

String _indented(Object value, String indent, int depth) {
  final lines = JsonEncoder.withIndent(indent).convert(value).split('\n');
  final pad = indent * depth;
  return [lines.first, for (final l in lines.skip(1)) '$pad$l'].join('\n');
}

/// [text] with only the clipforge member of mcpServers put in, replaced
/// ([entry]) or taken out (null). Throws when the text is laid out in a
/// way this does not handle.
String _spliceEntry(String text, Map<String, dynamic>? entry, String indent) {
  final nl = text.contains('\r\n') ? '\r\n' : '\n';
  final top = (_Scan(text)..ws()).object();
  final servers = top.members.where((m) => m.key == 'mcpServers').firstOrNull;
  String fix(String s) => nl == '\n' ? s : s.replaceAll('\n', nl);
  if (servers == null) {
    if (entry == null) return text;
    // A new "mcpServers" as the last member of the file.
    final body = fix('"mcpServers": ${_indented({kClaudeEntryName: entry}, indent, 1)}');
    if (top.members.isEmpty) {
      return '${text.substring(0, top.open + 1)}$nl$indent$body$nl'
          '${text.substring(top.close)}';
    }
    final last = top.members.last.end;
    return '${text.substring(0, last)},$nl$indent$body${text.substring(last)}';
  }
  final inner = (_Scan(text)..i = servers.valueAt).object();
  final mine = inner.members.where((m) => m.key == kClaudeEntryName).firstOrNull;
  if (entry != null) {
    final value = fix(_indented(entry, indent, 2));
    if (mine != null) {
      return '${text.substring(0, mine.valueAt)}$value${text.substring(mine.end)}';
    }
    final member = '"$kClaudeEntryName": $value';
    if (inner.members.isEmpty) {
      return '${text.substring(0, inner.open + 1)}$nl${indent * 2}$member$nl$indent'
          '${text.substring(inner.close)}';
    }
    final last = inner.members.last.end;
    return '${text.substring(0, last)},$nl${indent * 2}$member${text.substring(last)}';
  }
  if (mine == null) return text;
  // Take the member out together with one comma: the one after it, or
  // (when it is the last) the one before it.
  final index = inner.members.indexOf(mine);
  if (index < inner.members.length - 1) {
    final next = inner.members[index + 1].keyAt;
    return '${text.substring(0, mine.keyAt)}${text.substring(next)}';
  }
  if (index > 0) {
    final before = inner.members[index - 1].end;
    return '${text.substring(0, before)}${text.substring(mine.end)}';
  }
  return '${text.substring(0, inner.open + 1)}${text.substring(inner.close)}';
}

/// An installed ClipForge extension (.mcpb) in [place]: the name of its
/// folder under "Claude Extensions", or null.
String? installedExtension(ConnectHost h, DesktopPlace place) {
  final c = _ctx(h.os);
  for (final parent in ['Claude Extensions', 'extensions']) {
    for (final name in h.listDirs(c.join(place.dir, parent))) {
      if (name.toLowerCase().contains('clipforge')) return name;
    }
  }
  return null;
}

class ClaudeDesktopStatus {
  const ClaudeDesktopStatus({
    required this.state,
    this.places = const [],
    this.command,
    this.extension,
    this.detail = '',
  });
  final ConnectState state;
  final List<DesktopPlace> places;

  /// What the clipforge entry starts now.
  final String? command;

  /// The folder of an installed ClipForge extension, when there is one.
  final String? extension;
  final String detail;

  /// Connected through the settings file AND an extension: one is enough.
  bool get twice => extension != null && command != null;
}

ClaudeDesktopStatus claudeDesktopStatus(ConnectHost h, String launcher) {
  final places = findClaudeDesktop(h);
  if (places.isEmpty) {
    return const ClaudeDesktopStatus(state: ConnectState.notInstalled);
  }
  final c = _ctx(h.os);
  String? command, extension;
  var unreadable = false;
  final detail = StringBuffer();
  for (final place in places) {
    final file = c.join(place.dir, kDesktopConfigName);
    final text = h.fileExists(file) ? h.readText(file) : null;
    detail.writeln('${place.kind}: $file'
        '${h.fileExists(file) ? '' : ' (no settings file yet)'}');
    if (text != null && text.trim().isNotEmpty) {
      try {
        jsonDecode(text);
      } catch (_) {
        unreadable = true;
        detail.writeln('  this file is not plain JSON');
      }
    }
    final found = desktopEntryCommand(text);
    if (found != null) {
      detail.writeln('  clipforge -> $found');
      // The one that points at our helper wins.
      if (command == null || samePath(found, launcher, h.os)) command = found;
    }
    extension ??= installedExtension(h, place);
  }
  if (extension != null) detail.writeln('ClipForge extension installed: $extension');
  final state = command == null
      ? (unreadable ? ConnectState.unreadable : ConnectState.notConnected)
      : (command.isNotEmpty && samePath(command, launcher, h.os)
          ? ConnectState.connected
          : ConnectState.connectedElsewhere);
  return ClaudeDesktopStatus(
      state: state,
      places: places,
      command: command,
      extension: extension,
      detail: detail.toString().trimRight());
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// Connects ([remove] false) or disconnects Claude Desktop in every
/// settings folder found: a backup first
/// (`claude_desktop_config.backup-<date>-<time>.json`), then only the
/// clipforge entry changes. A file that is not plain JSON stops it
/// before anything is written.
ConnectOutcome changeClaudeDesktop(ConnectHost h, String launcher, {bool remove = false}) {
  final places = findClaudeDesktop(h);
  if (places.isEmpty) {
    return const ConnectOutcome(
        false,
        'Claude Desktop was not found on this computer (its settings '
            'folder is not there). Install and open it once, then try again.',
        '');
  }
  final c = _ctx(h.os);
  final log = StringBuffer();
  final edits = <({String file, String? before, DesktopEdit edit})>[];
  for (final place in places) {
    final file = c.join(place.dir, kDesktopConfigName);
    final before = h.fileExists(file) ? h.readText(file) : null;
    if (h.fileExists(file) && before == null) {
      return ConnectOutcome(false,
          'Claude\'s settings file could not be read. Nothing was written.', file);
    }
    final edit = editDesktopConfig(before, launcher, remove: remove);
    if (edit.problem != null) {
      return ConnectOutcome(false, edit.problem!, file);
    }
    edits.add((file: file, before: before, edit: edit));
  }
  var replaced = <String>[];
  var wrote = 0;
  for (final e in edits) {
    if (!e.edit.changed || e.edit.text == null) {
      log.writeln('${e.file}: already as wanted, not written');
      continue;
    }
    try {
      if (e.before != null) {
        final backup = c.join(c.dirname(e.file),
            'claude_desktop_config.backup-${_stamp(h.now())}.json');
        h.writeText(backup, e.before!);
        log.writeln('backup: $backup');
      }
      h.writeText(e.file, e.edit.text!);
      wrote++;
      log.writeln('${remove ? 'removed the clipforge entry from' : 'wrote the clipforge entry to'}: ${e.file}');
      final prev = e.edit.previous;
      if (!remove && prev != null && prev.isNotEmpty && !samePath(prev, launcher, h.os)) {
        replaced.add(prev);
        log.writeln('  it replaced an entry that started: $prev');
      }
    } catch (err) {
      return ConnectOutcome(false,
          'Claude\'s settings file could not be written ($err).', log.toString().trimRight());
    }
  }
  if (remove) {
    return ConnectOutcome(
        true,
        wrote == 0
            ? 'Claude Desktop had no ClipForge entry in its settings file.'
            : 'Claude Desktop is no longer connected through its settings '
                'file (a backup of the file was kept). Close Claude '
                'completely and open it again.',
        log.toString().trimRight());
  }
  return ConnectOutcome(
      true,
      'Claude Desktop is connected'
      '${replaced.isEmpty ? '' : ' (an older ClipForge entry pointing at ${replaced.first} was replaced)'}. '
      'Close Claude completely - also from the icon next to the clock - and '
      'open it again: it reads its list of tools when it starts.',
      log.toString().trimRight());
}

// Is the helper in use? ------------------------------------------------------

/// The folder (inside the helper's per-user folder) where every running
/// helper keeps one small file while a Claude session has it open.
const String kInUseFolder = 'in-use';

/// One running helper.
class HelperSession {
  const HelperSession({
    required this.pid,
    required this.version,
    required this.client,
    required this.startedAt,
    required this.lastCallAt,
  });
  final int pid;
  final String version;

  /// What the Claude program called itself in the handshake ("claude-ai",
  /// "claude-code", …); '' when it did not say.
  final String client;
  final DateTime startedAt;

  /// When a tool was last used (the start, when none was yet).
  final DateTime lastCallAt;

  /// "Claude Desktop", "Claude Code", or the name as it is.
  String get clientName {
    final c = client.toLowerCase();
    if (c.contains('code')) return 'Claude Code';
    if (c.contains('claude')) return 'Claude Desktop';
    return client.isEmpty ? 'Claude' : client;
  }

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'version': version,
        'client': client,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastCallAt': lastCallAt.toUtc().toIso8601String(),
      };

  static HelperSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'];
    final started = DateTime.tryParse('${j['startedAt']}');
    if (pid is! int || started == null) return null;
    return HelperSession(
      pid: pid,
      version: '${j['version'] ?? ''}',
      client: '${j['client'] ?? ''}',
      startedAt: started,
      lastCallAt: DateTime.tryParse('${j['lastCallAt']}') ?? started,
    );
  }
}

/// The helpers that are running now, newest use first. Files of helpers
/// whose process is gone (a crash, a killed Claude) are stale: they are
/// deleted on the way and not counted.
Future<List<HelperSession>> helperSessions(ConnectHost h, String stableDir,
    {List<String> Function(String dir)? listFiles}) async {
  final c = _ctx(h.os);
  final dir = c.join(stableDir, kInUseFolder);
  final out = <HelperSession>[];
  for (final name in (listFiles ?? (_) => const <String>[])(dir)) {
    if (!name.endsWith('.json')) continue;
    final file = c.join(dir, name);
    HelperSession? s;
    try {
      s = HelperSession.fromJson(jsonDecode(h.readText(file) ?? ''));
    } catch (_) {
      s = null;
    }
    if (s == null || !await h.processAlive(s.pid)) {
      try {
        h.deleteFile(file);
      } catch (_) {}
      continue;
    }
    out.add(s);
  }
  out.sort((a, b) => b.lastCallAt.compareTo(a.lastCallAt));
  return out;
}

/// "2 min ago", "just now", "3 h ago".
String agoText(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inSeconds < 50) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

/// The line under "Is it running?".
String inUseLine(List<HelperSession> sessions, DateTime now) {
  if (sessions.isEmpty) {
    return 'Not in use right now (that is normal: Claude starts it when '
        'needed).';
  }
  final s = sessions.first;
  return 'In use by ${s.clientName} now · last action '
      '${agoText(s.lastCallAt, now)}'
      '${sessions.length > 1 ? ' (${sessions.length} Claude sessions have it open)' : ''}';
}

// The Test button -------------------------------------------------------------

/// The three messages the Test button sends to the helper: the handshake
/// and the quick self-test.
List<String> helperTestMessages() => [
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'clipforge-app-test', 'version': '1'},
        },
      }),
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'self_test',
          'arguments': {'quick': true},
        },
      }),
    ];

/// What the Test button found.
class HelperTestResult {
  const HelperTestResult(this.pass, this.summary, this.report);
  final bool pass;

  /// One line: "PASS: the helper answered as ClipForge 1.14.0 and …".
  final String summary;

  /// The self-test table (or what went wrong), for "Details".
  final String report;
}

/// Reads what the helper wrote back (one JSON message per line).
HelperTestResult readHelperTest(String stdout, {String stderr = '', int? exitCode}) {
  String? version;
  String? report;
  var isError = false;
  for (final line in stdout.replaceAll('\r', '').split('\n')) {
    if (line.trim().isEmpty) continue;
    Object? m;
    try {
      m = jsonDecode(line);
    } catch (_) {
      continue;
    }
    if (m is! Map) continue;
    final result = m['result'];
    if (m['id'] == 1 && result is Map) {
      final info = result['serverInfo'];
      if (info is Map) version = '${info['version']}';
    }
    if (m['id'] == 2) {
      if (result is Map) {
        isError = result['isError'] == true;
        final content = result['content'];
        if (content is List && content.isNotEmpty && content.first is Map) {
          report = '${(content.first as Map)['text']}';
        }
      } else if (m['error'] is Map) {
        isError = true;
        report = '${(m['error'] as Map)['message']}';
      }
    }
  }
  if (version == null) {
    return HelperTestResult(
        false,
        'FAIL: the helper did not answer'
            '${exitCode == null ? '' : ' (it ended with code $exitCode)'}.',
        stderr.trim().isEmpty ? 'Nothing came back from the helper.' : stderr.trim());
  }
  if (report == null) {
    return HelperTestResult(false,
        'FAIL: the helper started (ClipForge $version) but the test did not finish.',
        stderr.trim());
  }
  final pass = !isError && report.contains('ClipForge self-test: PASS');
  return HelperTestResult(
      pass,
      pass
          ? 'PASS: the helper works by itself (ClipForge $version).'
          : 'FAIL: the helper answered (ClipForge $version), but a check '
              'did not pass. See Details.',
      report);
}
