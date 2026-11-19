// A pretend computer for "Connect to Claude": files and folders in memory,
// and a `claude` program that answers from a script.
import 'package:clipforge/core/claude/connect.dart';

class FakeConnectHost implements ConnectHost {
  FakeConnectHost({this.os = 'windows', Map<String, String>? environment})
      : environment = environment ??
            (os == 'windows'
                ? {
                    'USERPROFILE': r'C:\Users\sam',
                    'APPDATA': r'C:\Users\sam\AppData\Roaming',
                    'LOCALAPPDATA': r'C:\Users\sam\AppData\Local',
                    'PATH': r'C:\Windows;C:\Users\sam\AppData\Roaming\npm',
                  }
                : {'HOME': '/Users/sam', 'PATH': '/usr/bin:/usr/local/bin'});

  @override
  final String os;
  @override
  final Map<String, String> environment;
  final Map<String, String> files = {};
  final Set<String> dirs = {};
  final Set<int> alive = {};
  DateTime time = DateTime(2026, 11, 19, 14, 30, 5);

  /// Every program run: "exe arg arg" (and where).
  final List<String> runs = [];

  /// Answers `claude <args>`; default: nothing connected.
  RunResult Function(List<String> args, String? cwd) claude =
      (args, cwd) => args.length > 1 && args[1] == 'get'
          ? const RunResult(1, '', 'No MCP server found with name: clipforge')
          : const RunResult(0, '', '');

  String get sep => os == 'windows' ? r'\' : '/';

  /// Makes [path] a folder (with its parents).
  void mkdir(String path) {
    final parts = path.split(sep);
    for (var i = 1; i <= parts.length; i++) {
      dirs.add(parts.sublist(0, i).join(sep));
    }
  }

  void put(String path, String text) {
    mkdir(path.substring(0, path.lastIndexOf(sep)));
    files[path] = text;
  }

  @override
  bool fileExists(String path) => files.containsKey(path);
  @override
  bool dirExists(String path) => dirs.contains(path);

  @override
  List<String> listDirs(String path) => [
        for (final d in dirs)
          if (d.startsWith('$path$sep') && !d.substring(path.length + 1).contains(sep))
            d.substring(path.length + 1),
      ]..sort();

  List<String> listFiles(String path) => [
        for (final f in files.keys)
          if (f.startsWith('$path$sep') && !f.substring(path.length + 1).contains(sep))
            f.substring(path.length + 1),
      ]..sort();

  @override
  String? readText(String path) => files[path];
  @override
  void writeText(String path, String text) => files[path] = text;
  @override
  void deleteFile(String path) => files.remove(path);
  @override
  DateTime now() => time;

  @override
  Future<RunResult> run(String exe, List<String> args,
      {String? workingDirectory,
      Duration timeout = const Duration(seconds: 30)}) async {
    runs.add('$exe ${args.join(' ')}${workingDirectory == null ? '' : ' @ $workingDirectory'}');
    return claude(args, workingDirectory);
  }

  @override
  Future<bool> processAlive(int pid) async => alive.contains(pid);
}
