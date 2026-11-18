import 'package:path/path.dart' as p;

import '../model/project.dart';
// Flutter builds ask the platform (path_provider); plain Dart programs, which
// cannot load plugins, work the folder out from the environment.
import 'documents_dir_io.dart'
    if (dart.library.ui) 'documents_dir_flutter.dart';
import 'file_project_store.dart';

export 'file_project_store.dart';

/// Summary shown on the home screen.
class ProjectInfo {
  const ProjectInfo({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.durationMs,
    this.thumbnailSourcePath,
  });
  final String id;
  final String name;
  final DateTime updatedAt;
  final int durationMs;

  /// Path of the first clip's media file, for a thumbnail. May be null.
  final String? thumbnailSourcePath;
}

/// Saves projects as `<root>/<id>/project.json`. CONTRACT for the UI.
///
/// This file can be imported from plain Dart (no Flutter engine).
abstract class ProjectStore {
  /// Store rooted in the app's documents directory
  /// (`<documents>/ClipForge/projects`).
  ///
  /// Outside Flutter the documents directory is a best guess (see
  /// `documents_dir_io.dart`); command-line tools should let the user
  /// override it and use [ProjectStore.atPath].
  static Future<ProjectStore> open() async {
    final docs = await documentsDirectoryPath();
    return FileProjectStore(p.join(docs, 'ClipForge', 'projects'));
  }

  /// Store rooted at an explicit directory (tests, command-line tools).
  factory ProjectStore.atPath(String rootDir) = FileProjectStore;

  /// Summaries of all readable projects, newest first. Folders that cannot
  /// be read or parsed are skipped.
  Future<List<ProjectInfo>> list();

  /// Creates, saves and returns an empty project.
  Future<Project> create(String name);

  /// Throws a [FileSystemException] when the project does not exist and a
  /// [FormatException] when its file is corrupt or written by a newer
  /// version of the app.
  Future<Project> load(String id);
  Future<void> save(Project project); // atomic: write temp file then rename

  /// Saves and returns a copy of project [id] under a new id, with fresh
  /// created/updated times. [name] defaults to `"<name> copy"` (also when it
  /// is blank). The copy refers to the same media files. Throws like [load]
  /// when the project cannot be read.
  Future<Project> duplicate(String id, {String? name});

  /// Deletes the project folder. Deleting a missing project is a no-op.
  Future<void> delete(String id);
}
