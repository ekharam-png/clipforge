import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'package:path_provider/path_provider.dart';

import 'core/build_info.dart';
import 'core/perf_log.dart';
import 'ui/app.dart';

void main(List<String> args) {
  // `clipforge --version` (computers, from a terminal): the same line as
  // Help > About ClipForge, then quit.
  if (args.contains('--version')) {
    stdout.writeln(BuildInfo.current.describe());
    exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // The performance log: measures how long the app could not respond and
  // lets a watchdog write `perf-log.txt` when it stops responding.
  () async {
    String? dir;
    try {
      dir = (await getApplicationSupportDirectory()).path;
    } catch (_) {}
    await PerfLog.instance.start(dir: dir);
  }();
  runApp(const ProviderScope(child: ClipForgeApp()));
}
