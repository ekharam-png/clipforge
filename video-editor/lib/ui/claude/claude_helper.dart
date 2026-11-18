import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/build_info.dart';
import '../../core/claude/helper_install.dart';
import '../about.dart';

// The Claude helper that travels with the app (1.12): the desktop app
// carries the Claude extension file as an asset, puts the helper from it
// into a fixed per-user folder on every start, and can save the extension
// file for Claude Desktop. See lib/core/claude/helper_install.dart for the
// folder layout and why.

/// The asset the build workflow adds (missing in development builds).
const String kClaudeBundleAsset = 'assets/claude/ClipForge-claude.mcpb';

/// What the "Connect to Claude" page shows.
class ClaudeHelperState {
  const ClaudeHelperState({
    required this.supported,
    this.stableDir,
    this.launcherPath,
    this.installed = false,
    this.current,
    this.hasBundle = false,
    this.problem,
  });

  /// False on phones: Claude control is for computers.
  final bool supported;
  final String? stableDir;

  /// The path to give to Claude Code.
  final String? launcherPath;
  final bool installed;
  final HelperCurrent? current;

  /// The extension file is inside this app (it can be saved).
  final bool hasBundle;

  /// Why the helper could not be installed, in plain words.
  final String? problem;
}

class ClaudeHelperService {
  ClaudeHelperService({
    required this.build,
    Future<Uint8List?> Function()? loadBundle,
    Map<String, String>? environment,
    String? os,
  })  : _loadBundle = loadBundle ?? _assetBundle,
        _env = environment ?? Platform.environment,
        os = os ?? Platform.operatingSystem;

  final BuildInfo build;
  final Future<Uint8List?> Function() _loadBundle;
  final Map<String, String> _env;
  final String os;
  String? _problem;
  Uint8List? _bytes;
  bool _loaded = false;

  static Future<Uint8List?> _assetBundle() async {
    try {
      final data = await rootBundle.load(kClaudeBundleAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null; // Not in this build.
    }
  }

  bool get supported => os == 'windows' || os == 'macos' || os == 'linux';

  String? get stableDir => supported ? claudeStableDir(os, _env) : null;

  /// The extension file's bytes, or null when this build has none.
  Future<Uint8List?> bundle() async {
    if (!_loaded) {
      _bytes = await _loadBundle();
      _loaded = true;
    }
    return _bytes;
  }

  /// Writes the extension file to [path] ("Save the Claude extension
  /// file…"). False when this build has none.
  Future<bool> writeBundle(String path) async {
    final bytes = await bundle();
    if (bytes == null) return false;
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }

  /// Installs or refreshes the helper (every start of the app; quick when
  /// nothing changed). Never throws.
  Future<void> installAtStart() async {
    final dir = stableDir;
    if (dir == null) return;
    try {
      final bytes = await bundle();
      if (bytes == null) return;
      // Hashing and unpacking ~10 MB: off the main thread. A top-level
      // function and plain values, so nothing else travels to the isolate.
      await compute(_installHelper, <String, Object>{
        'dir': dir,
        'bytes': bytes,
        'version': build.version,
        'build': int.tryParse(build.buildNumber ?? '') ?? 0,
        'os': os,
        'display': build.describe(),
      });
      _problem = null;
    } catch (e) {
      _problem = 'The Claude helper could not be put in place ($e).';
      debugPrint('ClipForge: $_problem');
    }
  }

  Future<ClaudeHelperState> state() async {
    final dir = stableDir;
    if (dir == null) return ClaudeHelperState(supported: supported);
    final s = helperStatus(dir, os);
    return ClaudeHelperState(
      supported: true,
      stableDir: dir,
      launcherPath: s.launcherPath,
      installed: s.installed,
      current: s.current,
      hasBundle: await bundle() != null,
      problem: _problem,
    );
  }
}

Future<void> _installHelper(Map<String, Object> job) async {
  await installClaudeHelper(
    stableDir: job['dir']! as String,
    bundleBytes: job['bytes']! as Uint8List,
    version: job['version']! as String,
    build: job['build']! as int,
    os: job['os']! as String,
    display: job['display']! as String,
  );
}

final claudeHelperProvider = Provider<ClaudeHelperService>(
    (ref) => ClaudeHelperService(build: ref.watch(buildInfoProvider)));
