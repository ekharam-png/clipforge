import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'core/build_info.dart';
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
  runApp(const ProviderScope(child: ClipForgeApp()));
}
