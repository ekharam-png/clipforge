import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../model/project.dart';
import '../transcript/transcript_store.dart';
import 'project_store.dart';

/// [ProjectStore] backed by plain files. Pure Dart (no Flutter, no
/// plugins), so command-line tools can use it directly.
class FileProjectStore implements ProjectStore {
  FileProjectStore(this.rootPath);

  static const String projectFileName = 'project.json';

  /// Directory that holds one folder per project.
  final String rootPath;

  /// Tail of the pending writes per project id, so that overlapping saves
  /// of one project land in call order.
  final Map<String, Future<void>> _writes = {};
  int _tmpCounter = 0;

  String _dirOf(String id) {
    if (id.isEmpty ||
        id == '.' ||
        id == '..' ||
        id.contains('/') ||
        id.contains(r'\') ||
        id.contains('\u0000')) {
      throw ArgumentError.value(id, 'id', 'Not a valid project id');
    }
    return p.join(rootPath, id);
  }

  File _fileOf(String id) => File(p.join(_dirOf(id), projectFileName));

  @override
  Future<List<ProjectInfo>> list() async {
    final root = Directory(rootPath);
    final infos = <ProjectInfo>[];
    final List<FileSystemEntity> entries;
    try {
      if (!await root.exists()) return infos;
      entries = await root.list(followLinks: false).toList();
    } on FileSystemException {
      return infos;
    }
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final id = p.basename(entry.path);
      try {
        final project = await load(id);
        infos.add(ProjectInfo(
          // The folder name is what load() needs, so it wins over the id
          // stored inside the file.
          id: id,
          name: project.name,
          updatedAt: project.updatedAt,
          durationMs: project.durationMs,
          thumbnailSourcePath:
              project.clips.isEmpty ? null : project.clips.first.path,
        ));
      } catch (_) {
        // Unreadable or corrupt project: leave it out of the list.
      }
    }
    infos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return infos;
  }

  /// [name] when no project is called that yet, else the first of
  /// "name (2)", "name (3)", ... that is free (1.11: two projects with one
  /// name could not be told apart, in the app or by Claude). Upper and
  /// lower case count as the same name.
  Future<String> freeName(String name) async {
    final taken = {
      for (final i in await list()) i.name.trim().toLowerCase(),
    };
    if (!taken.contains(name.trim().toLowerCase())) return name;
    for (var n = 2;; n++) {
      final candidate = '$name ($n)';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
  }

  @override
  Future<Project> create(String name) async {
    final now = DateTime.now();
    final trimmed = name.trim();
    final project = Project(
      id: const Uuid().v4(),
      name: await freeName(trimmed.isEmpty ? 'Untitled' : trimmed),
      createdAt: now,
      updatedAt: now,
    );
    await save(project);
    return project;
  }

  @override
  Future<Project> duplicate(String id, {String? name}) async {
    final source = await load(id);
    final now = DateTime.now();
    final trimmed = name?.trim() ?? '';
    final copy = Project.fromJson(source.toJson()
      ..['id'] = const Uuid().v4()
      ..['name'] =
          await freeName(trimmed.isEmpty ? '${source.name} copy' : trimmed)
      ..['createdAt'] = now.toUtc().toIso8601String()
      ..['updatedAt'] = now.toUtc().toIso8601String());
    await save(copy);
    // The copy uses the same media files, so their transcripts apply.
    try {
      await TranscriptStore.ofProject(p.join(rootPath, id))
          .copyTo(TranscriptStore.ofProject(p.join(rootPath, copy.id)));
    } catch (_) {}
    return copy;
  }

  @override
  Future<Project> load(String id) async {
    final file = _fileOf(id);
    if (!await file.exists()) {
      throw FileSystemException('Project not found', file.path);
    }
    final text = await file.readAsString();
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException(
          'Project file ${file.path} is not valid JSON: ${e.message}');
    }
    if (json is! Map) {
      throw FormatException(
          'Project file ${file.path} does not contain a JSON object');
    }
    final version = json['schemaVersion'];
    if (version is num && version > kSchemaVersion) {
      throw FormatException(
          'Project file ${file.path} was saved by a newer version of the app '
          '(schema $version, this app supports up to $kSchemaVersion)');
    }
    try {
      return Project.fromJson(Map<String, dynamic>.from(json));
    } on FormatException catch (e) {
      throw FormatException(
          'Project file ${file.path} is malformed: ${e.message}');
    } catch (e) {
      // Missing or wrongly typed fields surface as TypeErrors.
      throw FormatException('Project file ${file.path} is malformed: $e');
    }
  }

  @override
  Future<void> save(Project project) {
    final id = project.id;
    _dirOf(id); // validate before queueing
    final previous = _writes[id] ?? Future<void>.value();
    late final Future<void> current;
    current = previous.catchError((Object _) {}).then((_) => _write(project));
    _writes[id] = current;
    // Drop the queue entry once it is the last one. The cleanup future
    // swallows the error; callers still get it through [current].
    current.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_writes[id], current)) _writes.remove(id);
    });
    return current;
  }

  Future<void> _write(Project project) async {
    final dir = Directory(_dirOf(project.id));
    await dir.create(recursive: true);
    // A big project (hundreds of pieces after Remove silences, hundreds of
    // captions) is turned into text on another isolate, so that the
    // editor does not stall while it is saved.
    final text = project.clips.length + project.titles.length >=
            kEncodeInBackgroundFrom
        ? await _encodeInBackground(project)
        : _encodeProject(project);
    final tmp = File(p.join(
        dir.path, '$projectFileName.${pid}_${_tmpCounter++}.tmp'));
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(p.join(dir.path, projectFileName));
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    final dir = Directory(_dirOf(id));
    // Let a pending save finish first so it cannot recreate the folder.
    await (_writes[id] ?? Future<void>.value()).catchError((Object _) {});
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Projects with this many clips and titles together or more are encoded
/// on another isolate when saved.
const int kEncodeInBackgroundFrom = 150;

String _encodeProject(Project project) =>
    const JsonEncoder.withIndent('  ').convert(project.toJson());

// Top-level, so that the closure sent to the isolate holds only the project.
Future<String> _encodeInBackground(Project project) async {
  try {
    return await Isolate.run(() => _encodeProject(project));
  } catch (_) {
    // No isolates here (or the copy failed): do it on this one.
    return _encodeProject(project);
  }
}
