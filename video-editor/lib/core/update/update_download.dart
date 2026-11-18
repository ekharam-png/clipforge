// Fetches one update file (the Windows / macOS zip or the Android APK):
// progress, resume after an interruption, and a size + SHA-256 check before
// the file gets its real name. Pure Dart (dart:io).
//
// The bytes go to `<name>.part` in the folder given. A download that
// stopped continues from where it was (HTTP Range) the next time; a server
// that ignores the range starts over. When complete, the length and the
// SHA-256 are compared with what latest.json promised: a match renames the
// file to its real name; anything else DELETES it and reports - a file that
// failed the check is never kept, opened or installed.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'update_info.dart';

class UpdateProgress {
  const UpdateProgress(this.receivedBytes, this.totalBytes, {this.checking = false});
  final int receivedBytes;
  final int totalBytes;

  /// The download is complete and the file is being checked.
  final bool checking;
  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class UpdateDownload {
  UpdateDownload._(this.asset);
  final UpdateAsset asset;
  final _progress = StreamController<UpdateProgress>.broadcast();
  final _done = Completer<String>();
  bool _cancelled = false;
  HttpClient? _client;

  /// A download whose outcome is given (tests, fakes): [result] is the
  /// path of the file or an error.
  factory UpdateDownload.of(UpdateAsset asset, Future<String> result,
      {List<UpdateProgress> steps = const []}) {
    final d = UpdateDownload._(asset);
    d._done.future.ignore();
    result.ignore();
    () async {
      for (final s in steps) {
        d._progress.add(s);
        await Future<void>.delayed(Duration.zero);
      }
      try {
        d._done.complete(await result);
      } catch (e) {
        d._done.completeError(e);
      } finally {
        unawaited(d._progress.close());
      }
    }();
    return d;
  }

  Stream<UpdateProgress> get progress => _progress.stream;

  /// The path of the checked file, or an [UpdateException].
  Future<String> get done => _done.future;

  /// Stops; what was fetched stays for next time.
  Future<void> cancel() async {
    _cancelled = true;
    _client?.close(force: true);
    try {
      await _done.future;
    } catch (_) {}
  }
}

Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Null when [file] is exactly what [asset] describes, else what is wrong.
Future<String?> updateFileProblem(File file, UpdateAsset asset) async {
  if (!file.existsSync()) return 'the file is missing';
  final length = file.lengthSync();
  if (length != asset.size) {
    return 'size $length bytes, expected ${asset.size}';
  }
  final sum = await sha256OfFile(file);
  if (sum != asset.sha256) return 'sha256 $sum, expected ${asset.sha256}';
  return null;
}

/// Removes update files in [dir] that do not belong to build [keepBuild]
/// (older versions, half downloads of another version). Best effort.
void pruneUpdateFiles(String dir, {int? keepBuild}) {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  for (final f in d.listSync(followLinks: false)) {
    if (f is! File) continue;
    if (keepBuild != null && p.basename(f.path).startsWith('b$keepBuild-')) {
      continue;
    }
    try {
      f.deleteSync();
    } catch (_) {}
  }
}

/// Starts fetching [asset] of build [build] into [dir]. The finished file is
/// `<dir>/b<build>-<file name>`.
UpdateDownload downloadUpdate(UpdateAsset asset, String dir,
    {required int build, HttpClient Function()? client}) {
  final d = UpdateDownload._(asset);
  d._done.future.ignore();
  () async {
    final target = File(p.join(dir, 'b$build-${asset.fileName}'));
    final part = File('${target.path}.part');
    IOSink? sink;
    try {
      await Directory(dir).create(recursive: true);
      if (target.existsSync()) {
        // Downloaded earlier: use it only if it still passes the check.
        if (await updateFileProblem(target, asset) == null) {
          d._done.complete(target.path);
          return;
        }
        target.deleteSync();
      }
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > asset.size) {
        // More than the whole file: left over from something else.
        part.deleteSync();
        have = 0;
      }
      var complete = have == asset.size;
      if (d._cancelled) throw UpdateException('Stopped.', kind: 'stopped');
      if (!complete) {
        final http = d._client = (client ?? HttpClient.new)();
        http.userAgent = 'ClipForge (update download)';
        http.connectionTimeout = const Duration(seconds: 20);
        final request = await http.getUrl(Uri.parse(asset.url));
        if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
        final response = await request.close();
        if (response.statusCode == HttpStatus.ok) {
          have = 0; // The server sends everything again.
          sink = part.openWrite();
        } else if (response.statusCode == HttpStatus.partialContent) {
          sink = part.openWrite(mode: FileMode.append);
        } else {
          await response.drain<void>();
          http.close();
          if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
            // The partial file does not belong to this download.
            if (part.existsSync()) part.deleteSync();
          }
          throw UpdateException(
              'The update could not be downloaded (the server answered '
              '${response.statusCode}). Try again later, or use the '
              'download page.',
              detail: 'HTTP ${response.statusCode}');
        }
        var got = have;
        var lastTold = DateTime.fromMillisecondsSinceEpoch(0);
        // A connection that goes quiet for a minute counts as lost.
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastTold).inMilliseconds >= 150) {
            lastTold = now;
            if (!d._progress.isClosed) {
              d._progress.add(UpdateProgress(got, asset.size));
            }
          }
          if (got > asset.size) break; // Not the promised file.
        }
        await sink.flush();
        await sink.close();
        sink = null;
        http.close(force: true);
        if (d._cancelled) throw UpdateException('Stopped.', kind: 'stopped');
        if (got < asset.size) {
          throw UpdateException(
              'The download stopped before the end. Start it again: it '
              'continues from where it was.',
              kind: 'offline',
              detail: '$got of ${asset.size} bytes');
        }
        complete = true;
      }
      if (d._cancelled) throw UpdateException('Stopped.', kind: 'stopped');
      if (!d._progress.isClosed) {
        d._progress.add(UpdateProgress(asset.size, asset.size, checking: true));
      }
      final problem = await updateFileProblem(part, asset);
      if (problem != null) {
        try {
          part.deleteSync();
        } catch (_) {}
        throw UpdateException(
            'The update was downloaded, but it is not the file ClipForge '
            'expected, so it was deleted and nothing was installed. Try '
            'again, or use the download page.',
            kind: 'check',
            detail: problem);
      }
      await part.rename(target.path);
      d._done.complete(target.path);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      d._done.completeError(d._cancelled
          ? UpdateException('Stopped.', kind: 'stopped')
          : e is UpdateException
              ? e
              : UpdateException(
                  'The update could not be downloaded: check the internet '
                  'connection and try again (it continues from where it '
                  'stopped).',
                  kind: 'offline',
                  detail: '$e'));
    } finally {
      unawaited(d._progress.close());
    }
  }();
  return d;
}
