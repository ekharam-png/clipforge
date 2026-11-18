// Project bundles: one .zip holding a project and its media, to move a
// project between devices (phone <-> computer). Pure Dart.
//
// Layout of a bundle:
//   project.json        the project; bundled media paths are `media/<name>`
//   media/<name>        the media files (stored, not compressed)

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../model/project.dart';
import 'project_store.dart';

/// Name of the project file inside a bundle.
const String kBundleProjectFile = 'project.json';

/// Folder of the media files inside a bundle.
const String kBundleMediaDir = 'media';

/// Writes [project] and the media files it uses to a .zip at [zipPath]
/// (replacing an existing file).
///
/// In the bundled `project.json` the path of every clip and audio clip
/// whose file exists is rewritten to a relative `media/<unique name>`
/// entry; a file used by several clips is stored once. Files that are
/// missing are skipped and keep their original path. [project] itself is
/// not changed.
///
/// [onSkipped] is called once, before the zip is written, with the distinct
/// paths of the media that could NOT be bundled because the file is missing
/// (an empty list when everything was found), so that the user can be told
/// the bundle is incomplete. See also [exportBundleReport].
///
/// Media is streamed from disk to the zip, never held in memory, and the
/// work runs on a background isolate, so this is safe to call from the UI
/// for large videos. [onProgress] gets values from 0 to 1 (by bytes; it
/// moves once per finished file) and always ends with 1. The zip is written
/// to a temporary file next to [zipPath] and renamed when complete, so a
/// failed export leaves no half-written bundle.
Future<void> exportBundle(
  Project project,
  String zipPath, {
  void Function(double)? onProgress,
  void Function(List<String> skippedPaths)? onSkipped,
}) async {
  // Give every existing media file a unique entry name.
  final entryOf = <String, String>{}; // source path -> entry name
  final taken = <String>{};
  final skipped = <String>[];
  final sources = <String>[
    for (final c in project.clips) c.path,
    for (final a in project.audio) a.path,
    for (final o in project.overlays) o.path,
  ];
  for (final source in sources) {
    if (entryOf.containsKey(source)) continue;
    if (source.isEmpty || !await File(source).exists()) {
      if (!skipped.contains(source)) skipped.add(source);
      continue;
    }
    entryOf[source] = '$kBundleMediaDir/${_uniqueName(source, taken)}';
  }
  onSkipped?.call(List.unmodifiable(skipped));

  final json = project.toJson();
  for (final key in const ['clips', 'audio', 'overlays']) {
    for (final item in (json[key] as List? ?? const [])) {
      final map = item as Map<String, dynamic>;
      final entry = entryOf[map['path']];
      if (entry != null) map['path'] = entry;
    }
  }
  final jsonText = const JsonEncoder.withIndent('  ').convert(json);

  final tmpPath = '$zipPath.$pid.part';
  await Directory(p.dirname(p.absolute(zipPath))).create(recursive: true);
  final progress = ReceivePort();
  progress.listen((v) {
    if (v is double) onProgress?.call(v);
  });
  try {
    await _runZip((
      tmpPath: tmpPath,
      jsonText: jsonText,
      files: [for (final e in entryOf.entries) (source: e.key, entry: e.value)],
      progress: onProgress == null ? null : progress.sendPort,
    ));
    await File(tmpPath).rename(zipPath);
  } catch (_) {
    try {
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  } finally {
    // Let progress messages that are already on their way arrive first.
    await Future<void>.delayed(Duration.zero);
    progress.close();
  }
  onProgress?.call(1.0);
}

/// Like [exportBundle], but returns the paths of the media that had to be
/// skipped because the file is missing (empty when the bundle is complete).
Future<List<String>> exportBundleReport(
  Project project,
  String zipPath, {
  void Function(double)? onProgress,
}) async {
  var skipped = const <String>[];
  await exportBundle(project, zipPath,
      onProgress: onProgress, onSkipped: (paths) => skipped = paths);
  return skipped;
}

/// Reads the bundle at [zipPath] into [store] as a NEW project.
///
/// The project gets the id returned by [newId]; its media is extracted to
/// `<mediaDir>/<new id>/` and the bundled (`media/...`) paths are rewritten
/// to absolute paths there. Paths that were not bundled (their file was
/// missing on export) stay as they are. The project keeps its creation
/// time; its `updatedAt` becomes the time of the import. It keeps its name
/// unless [store] already has a project with that name: then it becomes
/// `"<name> (imported)"`, or `"<name> (imported 2)"`, `(imported 3)`, ...
/// when that is taken too. It is saved through [store] and returned.
///
/// Throws a [FormatException] when the file is not a readable zip, when
/// `project.json` is missing, corrupt or from a newer version of the app,
/// or when any entry's path would land outside the target folder (absolute
/// paths, `..`). In those cases nothing is saved and nothing is left in
/// [mediaDir]. Extraction is streamed and runs on a background isolate.
Future<Project> importBundle(
  String zipPath, {
  required ProjectStore store,
  required String mediaDir,
  required String Function() newId,
}) async {
  if (!await File(zipPath).exists()) {
    throw FileSystemException('Bundle not found', zipPath);
  }
  final id = newId();
  if (id.isEmpty ||
      id == '.' ||
      id == '..' ||
      id.contains('/') ||
      id.contains(r'\')) {
    throw ArgumentError.value(id, 'newId', 'Not a valid project id');
  }
  final target = p.normalize(p.absolute(mediaDir, id));
  final targetDir = Directory(target);
  final existed = await targetDir.exists();

  Future<void> cleanUp() async {
    try {
      if (!existed && await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  final _Unzipped result;
  try {
    result = await _runUnzip((zipPath: zipPath, target: target));
  } catch (_) {
    await cleanUp();
    rethrow;
  }
  if (result.error != null) {
    await cleanUp();
    throw FormatException(result.error!);
  }

  try {
    final json = Map<String, dynamic>.from(jsonDecode(result.jsonText!) as Map);
    json['id'] = id;
    json['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final name = json['name'] as String? ?? 'Untitled';
    final taken = {for (final info in await store.list()) info.name};
    if (taken.contains(name)) {
      var candidate = '$name (imported)';
      for (var n = 2; taken.contains(candidate); n++) {
        candidate = '$name (imported $n)';
      }
      json['name'] = candidate;
    }
    for (final key in const ['clips', 'audio', 'overlays']) {
      for (final item in (json[key] as List? ?? const [])) {
        final map = item as Map;
        final extracted = result.extracted[map['path']];
        if (extracted != null) map['path'] = extracted;
      }
    }
    final project = Project.fromJson(json);
    await store.save(project);
    return project;
  } catch (_) {
    await cleanUp();
    rethrow;
  }
}

// Naming ---------------------------------------------------------------------

final RegExp _unsafe = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');

/// A file name for [source] inside the bundle that no other entry uses
/// (compared without case, for file systems that ignore it).
String _uniqueName(String source, Set<String> taken) {
  // Accept both separators whatever the platform that wrote the path.
  var name = source.split(RegExp(r'[\\/]')).last.replaceAll(_unsafe, '_');
  name = name.replaceFirst(RegExp(r'^[. ]+'), '').trimRight();
  if (name.isEmpty) name = 'media';
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = name;
  for (var n = 2; !taken.add(candidate.toLowerCase()); n++) {
    candidate = '${stem}_$n$ext';
  }
  return candidate;
}

// Isolate work ---------------------------------------------------------------
// These helpers take and return only plain values, and the closures passed
// to Isolate.run are built here so that they capture nothing else.

typedef _ZipJob = ({
  String tmpPath,
  String jsonText,
  List<({String source, String entry})> files,
  SendPort? progress,
});

Future<void> _runZip(_ZipJob job) => Isolate.run(() => _zip(job));

Future<void> _zip(_ZipJob job) async {
  var total = 0;
  final sizes = <int>[];
  for (final f in job.files) {
    var size = 0;
    try {
      size = File(f.source).lengthSync();
    } on FileSystemException {
      // Vanished since the check: skipped below.
    }
    sizes.add(size);
    total += size;
  }
  final encoder = ZipFileEncoder();
  encoder.create(job.tmpPath);
  var closed = false;
  try {
    encoder.addArchiveFile(ArchiveFile.bytes(
        kBundleProjectFile, utf8.encode(job.jsonText)));
    var done = 0;
    job.progress?.send(0.0);
    for (var i = 0; i < job.files.length; i++) {
      final f = job.files[i];
      // Video and audio are already compressed: store them as they are.
      await encoder.addFile(File(f.source), f.entry, ZipFileEncoder.store);
      done += sizes[i];
      if (total > 0) job.progress?.send(done / total);
    }
    closed = true;
    await encoder.close();
  } finally {
    if (!closed) {
      try {
        await encoder.close();
      } catch (_) {}
    }
  }
}

typedef _UnzipJob = ({String zipPath, String target});

class _Unzipped {
  const _Unzipped.ok(String this.jsonText, this.extracted) : error = null;
  const _Unzipped.bad(String this.error)
      : jsonText = null,
        extracted = const {};

  /// What is wrong with the bundle, or null.
  final String? error;
  final String? jsonText;

  /// Bundle path (`media/...`) -> absolute path of the extracted file.
  final Map<String, String> extracted;
}

Future<_Unzipped> _runUnzip(_UnzipJob job) => Isolate.run(() => _unzip(job));

/// The segments of a zip entry name, or null when the name is absolute or
/// climbs out of its folder.
List<String>? _safeSegments(String name) {
  final unified = name.replaceAll(r'\', '/');
  if (unified.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
    return null;
  }
  final segments = <String>[];
  for (final s in unified.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..' || s.contains('\u0000')) return null;
    segments.add(s);
  }
  return segments;
}

_Unzipped _unzip(_UnzipJob job) {
  final InputFileStream input;
  try {
    input = InputFileStream(job.zipPath);
  } catch (e) {
    return _Unzipped.bad('Cannot open bundle ${job.zipPath}: $e');
  }
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (e) {
      return _Unzipped.bad('${job.zipPath} is not a readable zip file: $e');
    }

    // Check every entry before writing anything.
    ArchiveFile? projectEntry;
    final media = <({ArchiveFile file, List<String> segments})>[];
    for (final file in archive.files) {
      final segments = _safeSegments(file.name);
      if (segments == null) {
        return _Unzipped.bad(
            'Bundle entry "${file.name}" points outside the bundle');
      }
      if (!file.isFile || file.isSymbolicLink) continue;
      if (segments.length == 1 && segments[0] == kBundleProjectFile) {
        projectEntry = file;
      } else if (segments.length > 1 && segments[0] == kBundleMediaDir) {
        final out = p.joinAll([job.target, ...segments.skip(1)]);
        if (!p.isWithin(job.target, out)) {
          return _Unzipped.bad(
              'Bundle entry "${file.name}" points outside the bundle');
        }
        media.add((file: file, segments: segments));
      }
    }
    if (projectEntry == null) {
      return const _Unzipped.bad('The bundle has no $kBundleProjectFile');
    }

    final String jsonText;
    try {
      jsonText = utf8.decode(projectEntry.content);
      final json = jsonDecode(jsonText);
      if (json is! Map) {
        return const _Unzipped.bad(
            'The bundle\'s $kBundleProjectFile is not a JSON object');
      }
      final version = json['schemaVersion'];
      if (version is num && version > kSchemaVersion) {
        return _Unzipped.bad(
            'The bundle was made by a newer version of the app (schema '
            '$version, this app supports up to $kSchemaVersion)');
      }
      Project.fromJson(Map<String, dynamic>.from(json));
    } catch (e) {
      return _Unzipped.bad('The bundle\'s $kBundleProjectFile is corrupt: $e');
    }

    final extracted = <String, String>{};
    for (final m in media) {
      final out = p.joinAll([job.target, ...m.segments.skip(1)]);
      Directory(p.dirname(out)).createSync(recursive: true);
      final output = OutputFileStream(out);
      try {
        m.file.writeContent(output);
      } on FileSystemException {
        rethrow;
      } catch (e) {
        return _Unzipped.bad('Bundle entry "${m.file.name}" is damaged: $e');
      } finally {
        output.closeSync();
      }
      extracted[m.segments.join('/')] = out;
    }
    return _Unzipped.ok(jsonText, extracted);
  } finally {
    input.closeSync();
  }
}
