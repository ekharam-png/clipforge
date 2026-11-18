import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/project.dart';
import 'project_store.dart';

/// Files changed more recently than this are never removed by
/// [removeUnreferencedMedia]: they may belong to an import that is still
/// running and whose project has not been saved yet.
const Duration kMediaCleanupGrace = Duration(minutes: 10);

/// Deletes the files under [mediaDir] (the app's own copies of imported
/// media) that no saved project in [store] uses, then the folders this left
/// empty. Returns the number of bytes freed. Pure Dart.
///
/// Safety rules:
///  * Only files inside [mediaDir] are ever deleted. Links are not
///    followed; a link is removed as a link.
///  * If the projects cannot all be read - listing fails, or any project
///    folder cannot be loaded (corrupt, written by a newer version,
///    temporarily unreadable, half written) - NOTHING is deleted and 0 is
///    returned, because that project's media could not be told apart from
///    unused files.
///  * Files modified within the last [kMediaCleanupGrace] are kept.
///  * A file counts as used when a clip or audio clip of any project has
///    its path, compared as absolute normalised paths, with links resolved,
///    and also when a project refers to the same location under a different
///    folder prefix (`.../<mediaDir name>/<same relative path>`, which is
///    what a moved app container looks like).
///
///  * [keep] are more paths that must stay whatever the saved projects
///    say: the media of the project open in the editor, including every
///    state on its undo / redo stacks (a clip deleted a minute ago comes
///    back with Undo and needs its file).
///
///  * [alsoUses] names more files a project uses besides its clips' and
///    music's own (the app passes the processed sound files its clips lead
///    to, see media/processed_sound.dart).
///
/// [now] exists for tests.
Future<int> removeUnreferencedMedia(
  String mediaDir,
  ProjectStore store, {
  DateTime Function()? now,
  Iterable<String> Function(Project project)? alsoUses,
  Iterable<String> keep = const [],
}) async {
  final root = Directory(p.normalize(p.absolute(mediaDir)));
  try {
    if (!await root.exists()) return 0;
  } on FileSystemException {
    return 0;
  }

  final Set<String> used;
  try {
    used = {...await _referencedPaths(store, alsoUses), ...keep};
  } catch (_) {
    return 0;
  }
  final usedNormal = <String>{};
  final usedTails = <String>{};
  final marker = '/${p.basename(root.path)}/';
  for (final path in used) {
    if (path.isEmpty) continue;
    final normal = p.normalize(p.absolute(path));
    usedNormal.add(normal);
    try {
      usedNormal.add(File(normal).resolveSymbolicLinksSync());
    } on FileSystemException {
      // Missing file: nothing to resolve.
    }
    final unix = normal.replaceAll(r'\', '/');
    final at = unix.lastIndexOf(marker);
    if (at >= 0) usedTails.add(unix.substring(at + marker.length));
  }

  final List<FileSystemEntity> entries;
  try {
    entries = await root.list(recursive: true, followLinks: false).toList();
  } on FileSystemException {
    return 0;
  }
  final cutoff = (now ?? DateTime.now)().subtract(kMediaCleanupGrace);
  // Folders that were touched recently (before this run deletes anything
  // inside them) may belong to an import in progress: they stay.
  final oldDirs = <String>[];
  for (final e in entries) {
    if (e is! Directory) continue;
    try {
      if (!(await e.stat()).modified.isAfter(cutoff)) {
        oldDirs.add(p.normalize(p.absolute(e.path)));
      }
    } on FileSystemException {
      // Gone: nothing to remove.
    }
  }
  var freed = 0;
  for (final entry in entries) {
    if (entry is Directory) continue;
    final path = p.normalize(p.absolute(entry.path));
    if (!p.isWithin(root.path, path)) continue;
    try {
      if (usedNormal.contains(path)) continue;
      final tail = p.relative(path, from: root.path).replaceAll(r'\', '/');
      if (usedTails.contains(tail)) continue;
      if (entry is File) {
        if (usedNormal.contains(entry.resolveSymbolicLinksSync())) continue;
        if ((await entry.lastModified()).isAfter(cutoff)) continue;
        final size = await entry.length();
        await entry.delete();
        freed += size;
      } else if (entry is Link) {
        // A link: remove the link itself, never what it points at.
        if ((await FileStat.stat(path)).modified.isAfter(cutoff)) continue;
        await entry.delete();
      }
    } on FileSystemException {
      // In use or already gone: leave it for the next run.
    }
  }

  // Folders that are empty now, deepest first. The root itself stays.
  final dirs = oldDirs..sort((a, b) => b.length.compareTo(a.length));
  for (final dir in dirs) {
    if (!p.isWithin(root.path, dir)) continue;
    try {
      final d = Directory(dir);
      if (await d.list(followLinks: false).isEmpty) await d.delete();
    } on FileSystemException {
      // Not empty after all, or already gone.
    }
  }
  return freed;
}

/// Paths used by all saved projects. Throws when any project cannot be
/// read.
Future<Set<String>> _referencedPaths(ProjectStore store,
    Iterable<String> Function(Project project)? alsoUses) async {
  final ids = <String>{};
  if (store is FileProjectStore) {
    // list() leaves unreadable projects out; look at the folders directly
    // so that such a project stops the clean-up instead.
    final root = Directory(store.rootPath);
    if (await root.exists()) {
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! Directory) {
          if (entry is Link && await Directory(entry.path).exists()) {
            ids.add(p.basename(entry.path));
          }
          continue;
        }
        final hasProject = await File(
                p.join(entry.path, FileProjectStore.projectFileName))
            .exists();
        if (!hasProject) {
          // An empty folder is nothing; anything else is a project that is
          // being written or is damaged.
          if (await entry.list(followLinks: false).isEmpty) continue;
          throw FileSystemException('Project folder without a project file',
              entry.path);
        }
        ids.add(p.basename(entry.path));
      }
    }
  } else {
    for (final info in await store.list()) {
      ids.add(info.id);
    }
  }
  final used = <String>{};
  for (final id in ids) {
    final project = await store.load(id);
    for (final c in project.clips) {
      used.add(c.path);
    }
    for (final a in project.audio) {
      used.add(a.path);
    }
    for (final o in project.overlays) {
      used.add(o.path);
    }
    if (alsoUses != null) used.addAll(alsoUses(project));
  }
  return used;
}
