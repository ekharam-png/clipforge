// Fetches one speech pack into the models folder: progress, resume, and a
// SHA-256 check before the file gets its real name. Pure Dart (dart:io).
//
// The bytes go to `<file>.part`. A download that stopped (cancelled,
// connection lost, app closed) continues from where it was next time
// (HTTP Range); a server that ignores the range starts over. When
// complete, the whole file is hashed: a match renames it to its real name;
// a mismatch renames it to `<file>.unverified` and reports - it is never
// used unless the user says "Use it anyway".
//
// Only ever tested against a local test server (test/media/
// model_download_test.dart). The real download from the model host was not
// made in the build container.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'speech_models.dart';
import 'transcription.dart' show SpeechException;

class DownloadProgress {
  const DownloadProgress(this.receivedBytes, this.totalBytes, {this.checking = false});
  final int receivedBytes;

  /// 0 when the server did not say.
  final int totalBytes;

  /// The download is complete and the file is being checked.
  final bool checking;
  double get fraction =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class ModelDownload {
  ModelDownload._(this.model);
  final SpeechModel model;
  final _progress = StreamController<DownloadProgress>.broadcast();
  final _done = Completer<String>();
  bool _cancelled = false;
  HttpClient? _client;

  Stream<DownloadProgress> get progress => _progress.stream;

  /// The path of the finished pack, or a [SpeechException] (kind
  /// "pack-check" when the hash did not match).
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

/// The SHA-256 of [file], lower-case hex.
/// Whether [file] starts like a whisper.cpp model ("ggml" magic, stored
/// little-endian as "lmgg"; newer containers "ggjt"/"gguf" are accepted
/// too) and is not tiny (an error page saved as a file).
Future<bool> looksLikeWhisperModel(File file) async {
  if (!file.existsSync() || file.lengthSync() < 1024 * 1024) return false;
  final raf = await file.open();
  try {
    final head = String.fromCharCodes(await raf.read(4));
    return const {'lmgg', 'ggml', 'tjgg', 'ggjt', 'GGUF'}.contains(head);
  } finally {
    await raf.close();
  }
}

Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Starts fetching [model] into [store].
ModelDownload downloadModel(SpeechModel model, ModelStore store,
    {HttpClient Function()? client}) {
  final d = ModelDownload._(model);
  d._done.future.ignore();
  () async {
    final part = store.partOf(model);
    final target = store.fileOf(model);
    IOSink? sink;
    try {
      if (target.existsSync()) {
        d._done.complete(target.path);
        return;
      }
      await Directory(store.dir).create(recursive: true);
      var have = part.existsSync() ? part.lengthSync() : 0;
      var total = 0;
      var complete = false;
      for (var attempt = 0; attempt < 2 && !complete; attempt++) {
        final http = d._client = (client ?? HttpClient.new)();
        http.userAgent = 'ClipForge (speech pack download)';
        final request = await http.getUrl(Uri.parse(model.url));
        if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
        final response = await request.close();
        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          // Nothing after what we have: it is all there (the check below
          // decides), or the partial file is from something else.
          await response.drain<void>();
          http.close();
          complete = have > 0;
          total = have;
          if (!complete) {
            throw SpeechException('The download server refused the request.',
                kind: 'failed');
          }
          break;
        }
        if (response.statusCode == HttpStatus.ok) {
          have = 0; // The server sends everything again.
          total = response.contentLength > 0 ? response.contentLength : 0;
          sink = part.openWrite();
        } else if (response.statusCode == HttpStatus.partialContent) {
          total = response.contentLength > 0 ? have + response.contentLength : 0;
          sink = part.openWrite(mode: FileMode.append);
        } else {
          await response.drain<void>();
          http.close();
          throw SpeechException(
              'The pack could not be downloaded (the server answered '
              '${response.statusCode}). Check the internet connection and '
              'try again.',
              kind: 'failed');
        }
        var got = have;
        var lastTold = DateTime.fromMillisecondsSinceEpoch(0);
        // A connection that goes quiet for a minute counts as lost.
        await for (final chunk
            in response.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastTold).inMilliseconds >= 200) {
            lastTold = now;
            if (!d._progress.isClosed) {
              d._progress.add(DownloadProgress(
                  got, total > 0 ? total : model.sizeBytes));
            }
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        http.close();
        if (total > 0 && got < total) {
          throw SpeechException(
              'The download stopped before the end. Start it again: it '
              'continues from where it was.',
              kind: 'failed');
        }
        have = got;
        complete = true;
      }
      if (d._cancelled) throw SpeechException('Stopped.', cancelled: true);
      if (!d._progress.isClosed) {
        d._progress.add(DownloadProgress(have, have, checking: true));
      }
      if (model.sha256.isNotEmpty) {
        final sum = await sha256OfFile(part);
        if (sum != model.sha256.toLowerCase()) {
          final kept = store.unverifiedOf(model);
          if (kept.existsSync()) kept.deleteSync();
          await part.rename(kept.path);
          throw SpeechException(
              'The pack was downloaded, but it is not the file ClipForge '
              'expected (its fingerprint is different), so it is not used. '
              'It may be damaged, or the model was updated since this '
              'version of ClipForge was made. You can use it anyway or '
              'remove it.',
              kind: 'pack-check',
              log: 'expected sha256 ${model.sha256}, got $sum');
        }
      }
      if (model.sha256.isEmpty && !await looksLikeWhisperModel(part)) {
        final kept = store.unverifiedOf(model);
        if (kept.existsSync()) kept.deleteSync();
        await part.rename(kept.path);
        throw SpeechException(
            'The pack was downloaded, but it does not look like a speech '
            'model file, so it is not used. The download address may have '
            'changed since this version of ClipForge was made.',
            kind: 'pack-check',
            log: 'no ggml magic at the start of ${model.fileName}');
      }
      await part.rename(target.path);
      d._done.complete(target.path);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      d._done.completeError(d._cancelled
          ? SpeechException('Stopped.', cancelled: true)
          : e is SpeechException
              ? e
              : SpeechException(
                  'The pack could not be downloaded: check the internet '
                  'connection and try again (it continues from where it '
                  'stopped). [$e]',
                  kind: 'failed'));
    } finally {
      unawaited(d._progress.close());
    }
  }();
  return d;
}
