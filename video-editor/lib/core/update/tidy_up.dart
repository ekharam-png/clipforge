// "Tidy up" (1.14.1, Windows): for people whose ClipForge runs from a
// folder the updater unpacked a download into.
//
// What happened on real PCs with 1.12 - 1.14: the step that swaps the old
// version for the new one never ran, the new version stayed in
// "<folder>.update-new", and it was then started by hand from there. The
// next update unpacked into "<folder>.update-new.update-new", and so on.
//
// This file works out, without changing anything, what a tidy-up would do:
//   - where this version should live: a folder called "ClipForge" next to
//     the one it runs from (default), or the original folder name without
//     the suffixes;
//   - which folders next to it are OLDER ClipForge installs that can go.
//     A folder is only ever listed when it is PROVEN to be one: its name
//     is the original name, or that name with ".update-new" endings, AND
//     it holds clipforge.exe with a lower version than the running one.
// The move itself is done by the update script in "move" mode after the
// app has closed (update_install.dart, startSwap).
//
// Pure Dart (dart:io).

import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_install.dart';

/// [name] without its ".update-new" endings, and how many there were.
({String base, int depth}) stagedName(String name) {
  var base = name;
  var depth = 0;
  while (base.toLowerCase().endsWith(kUpdateNewSuffix) &&
      base.length > kUpdateNewSuffix.length) {
    base = base.substring(0, base.length - kUpdateNewSuffix.length);
    depth++;
  }
  return (base: base, depth: depth);
}

/// The name people should end up with.
const String kTidyDefaultName = 'ClipForge';

/// A folder next to the running one that holds an older ClipForge.
class OlderInstall {
  const OlderInstall(this.path, this.version);
  final String path;
  final AppVersion version;
  String get name => p.basename(path);
}

/// What stands where the app could move to.
enum TidyTargetState {
  /// Nothing has that name: the folder is made.
  free,

  /// An older ClipForge is there: it is brought up to date in place.
  olderClipForge,

  /// Something else (or a ClipForge that is not older): never touched.
  taken,
}

/// A place the app could move to.
class TidyTarget {
  const TidyTarget(this.path, this.state, [this.version]);
  final String path;
  final TidyTargetState state;

  /// With [TidyTargetState.olderClipForge]: what is there now.
  final AppVersion? version;
  String get name => p.basename(path);
  bool get usable => state != TidyTargetState.taken;
}

/// What a tidy-up would do. Nothing in here has been changed on disk.
class TidyPlan {
  const TidyPlan({
    required this.runningDir,
    required this.current,
    required this.targets,
    required this.older,
  });

  /// The folder the app runs from (its name ends in ".update-new").
  final String runningDir;
  final AppVersion current;

  /// Where it could live: "ClipForge" first, then the original name when
  /// that is another one.
  final List<TidyTarget> targets;

  /// Proven older ClipForge folders next to it (a folder that is chosen
  /// as the target is not removed: see [removable]).
  final List<OlderInstall> older;

  String get runningName => p.basename(runningDir);

  /// The first place that can be used; null when none can.
  TidyTarget? get defaultTarget {
    for (final t in targets) {
      if (t.usable) return t;
    }
    return null;
  }

  /// The older folders that can go when the app moves to [target].
  List<OlderInstall> removable(TidyTarget target) => [
        for (final o in older)
          if (!p.equals(o.path, target.path)) o,
      ];
}

/// The plan for an app of version [current] that runs from [installDir];
/// null when that folder is not one the updater unpacked into (its name
/// does not end in ".update-new"). [versionOf] reads which ClipForge a
/// folder holds (tests replace it).
TidyPlan? planTidyUp({
  required String installDir,
  required AppVersion current,
  String exeName = 'clipforge.exe',
  AppVersion? Function(String dir)? versionOf,
}) {
  final read = versionOf ?? (String d) => readInstalledVersion(d, exeName: exeName);
  final name = p.basename(installDir);
  final staged = stagedName(name);
  if (staged.depth == 0) return null;
  final parent = p.dirname(installDir);

  TidyTarget target(String targetName) {
    final path = p.join(parent, targetName);
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return TidyTarget(path, TidyTargetState.free);
    }
    final v = Directory(path).existsSync() ? read(path) : null;
    if (v != null && v.isOlderThan(current)) {
      return TidyTarget(path, TidyTargetState.olderClipForge, v);
    }
    return TidyTarget(path, TidyTargetState.taken, v);
  }

  final targets = [
    target(kTidyDefaultName),
    if (staged.base.toLowerCase() != kTidyDefaultName.toLowerCase())
      target(staged.base),
  ];

  // Older installs: "<base>" and "<base>.update-new…" with a lower version.
  final older = <OlderInstall>[];
  try {
    final dirs = Directory(parent).listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final d in dirs) {
      if (p.equals(d.path, installDir)) continue;
      final other = stagedName(p.basename(d.path));
      if (other.base.toLowerCase() != staged.base.toLowerCase()) continue;
      final v = read(d.path);
      if (v == null || !v.isOlderThan(current)) continue;
      older.add(OlderInstall(d.path, v));
    }
  } catch (_) {}
  return TidyPlan(
      runningDir: installDir, current: current, targets: targets, older: older);
}
