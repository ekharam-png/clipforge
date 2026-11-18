// Where transcripts are kept: one JSON file per source file (and audio
// stream) in `<project folder>/transcripts/`. Pure Dart (dart:io).
//
// The file name is the IDENTITY of the sound: a content fingerprint of the
// media file plus the audio stream, so a file that was moved or found again
// ("Find file…") keeps its transcript, and a different recording under the
// same name does not get the wrong one. The settings it was made with
// (language, quality, backend, model) are stored inside; asking for the
// same settings again is a cache hit ([Transcript.madeWith]).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/media_import.dart' show mediaFingerprint;
import 'transcript.dart';

const String kTranscriptsFolder = 'transcripts';

class TranscriptStore {
  TranscriptStore(this.dir);

  /// The store of the project in [projectDir].
  factory TranscriptStore.ofProject(String projectDir) =>
      TranscriptStore(p.join(projectDir, kTranscriptsFolder));

  /// `<project folder>/transcripts`.
  final String dir;

  static final Map<String, String> _fingerprints = {};

  /// The identity of the sound of [path]'s stream [audioTrack]; null when
  /// the file cannot be read.
  static Future<String?> keyFor(String path, int audioTrack) async {
    try {
      final st = await File(path).stat();
      if (st.type == FileSystemEntityType.notFound) return null;
      final memo = '$path|${st.size}|${st.modified.millisecondsSinceEpoch}';
      final print = _fingerprints[memo] ??= await mediaFingerprint(path);
      return '${print}_a$audioTrack';
    } on FileSystemException {
      return null;
    }
  }

  File _file(String key) => File(p.join(dir, '$key.json'));

  Future<Transcript?> _read(File f) async {
    try {
      if (!await f.exists()) return null;
      return Transcript.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// The transcript of [path] / [audioTrack]; null when there is none. A
  /// file that is missing now is looked up by the path it had.
  Future<Transcript?> load(String path, int audioTrack) async {
    final key = await keyFor(path, audioTrack);
    if (key != null) {
      final t = await _read(_file(key));
      if (t != null) return t;
      return null;
    }
    for (final t in await list()) {
      if (t.audioTrack == audioTrack && p.equals(t.sourcePath, path)) return t;
    }
    return null;
  }

  /// Saves [t] (atomically) and returns it with its fingerprint filled in.
  Future<Transcript> save(Transcript t) async {
    final key = await keyFor(t.sourcePath, t.audioTrack);
    if (key == null) {
      throw FileSystemException('The file is missing', t.sourcePath);
    }
    final stored = Transcript.fromJson(
        t.toJson()..['fingerprint'] = key.substring(0, key.lastIndexOf('_a')));
    await Directory(dir).create(recursive: true);
    final tmp = File(p.join(dir, '$key.json.$pid.tmp'));
    await tmp.writeAsString(jsonEncode(stored.toJson()), flush: true);
    await tmp.rename(_file(key).path);
    return stored;
  }

  /// Every transcript of the project.
  Future<List<Transcript>> list() async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <Transcript>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final t = await _read(e);
      if (t != null) out.add(t);
    }
    return out;
  }

  /// Copies every transcript into the store of another project (a
  /// duplicate of this one uses the same files).
  Future<void> copyTo(TranscriptStore other) async {
    final d = Directory(dir);
    if (!await d.exists()) return;
    await Directory(other.dir).create(recursive: true);
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json')) {
        await e.copy(p.join(other.dir, p.basename(e.path)));
      }
    }
  }
}
