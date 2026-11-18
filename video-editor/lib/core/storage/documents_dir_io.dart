import 'dart:io';

import 'package:path/path.dart' as p;

/// The user's documents directory for programs that run without Flutter
/// (command-line tools), where the path_provider plugin is not available.
///
/// Best effort, meant to give the folder the desktop app uses:
/// `xdg-user-dir DOCUMENTS` on Linux, otherwise `<home>/Documents`. It can
/// differ from the app's folder when Documents is redirected (e.g. OneDrive
/// on Windows) or the app is sandboxed, so tools should also accept an
/// explicit path.
Future<String> documentsDirectoryPath() async {
  final env = Platform.environment;
  if (Platform.isLinux) {
    try {
      final r = await Process.run('xdg-user-dir', ['DOCUMENTS']);
      final out = (r.stdout as String).trim();
      if (r.exitCode == 0 && out.isNotEmpty && p.isAbsolute(out)) return out;
    } catch (_) {
      // xdg-user-dir is not installed: fall through.
    }
  }
  final home = Platform.isWindows
      ? (env['USERPROFILE'] ?? env['HOME'])
      : env['HOME'];
  if (home == null || home.isEmpty) {
    throw const FileSystemException(
        'Cannot find the home directory to locate the projects folder');
  }
  return p.join(home, 'Documents');
}
