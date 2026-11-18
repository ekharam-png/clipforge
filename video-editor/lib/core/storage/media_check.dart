import 'dart:io';

import '../model/project.dart';

/// The media files [p] uses that do not exist (any more): the distinct
/// paths of its clips and audio clips, in order of first use. Empty paths
/// count as missing. Pure Dart.
///
/// Use `ProjectEditor.relinkMedia` to point the project at a replacement.
Future<List<String>> findMissingMedia(Project p) async {
  final seen = <String>{};
  final missing = <String>[];
  final paths = [
    for (final c in p.clips) c.path,
    for (final a in p.audio) a.path,
    for (final o in p.overlays) o.path,
  ];
  for (final path in paths) {
    if (!seen.add(path)) continue;
    var exists = false;
    if (path.isNotEmpty) {
      try {
        exists = await File(path).exists();
      } on FileSystemException {
        exists = false;
      }
    }
    if (!exists) missing.add(path);
  }
  return missing;
}
