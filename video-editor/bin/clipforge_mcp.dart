// ClipForge MCP server: lets Claude Desktop / Claude Code edit the projects
// of the ClipForge app. Plain Dart (no Flutter):
//
//   dart run bin/clipforge_mcp.dart --help
//   dart compile exe bin/clipforge_mcp.dart -o clipforge-mcp
//
// See the "Claude control" section of README.md.

import 'dart:io';

import 'package:clipforge/mcp/server.dart';

Future<void> main(List<String> args) async {
  exit(await runClipForgeMcp(args));
}
