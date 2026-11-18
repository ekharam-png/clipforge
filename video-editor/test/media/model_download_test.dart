// The speech pack downloader against a LOCAL test web server: progress,
// resume with Range, a server that ignores Range, a cut connection, the
// SHA-256 check, removal. The real model host is never contacted.
import 'dart:io';
import 'dart:math';

import 'package:clipforge/media/transcribe/transcription_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late HttpServer server;
  late List<int> data;
  late ModelStore store;
  final requests = <String>[];
  var honourRange = true;
  int? cutAfter;
  var status = 200;

  SpeechModel pack({String? sha}) => SpeechModel(
        id: 'test',
        fileName: 'ggml-test.bin',
        url: 'http://127.0.0.1:${server.port}/ggml-test.bin',
        sha256: sha ?? sha256.convert(data).toString(),
        sizeBytes: data.length,
        sizeLabel: 'about 300 KB',
        title: 'Test pack',
        size: SpeechQuality.small,
      );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cf_packs_');
    store = ModelStore(p.join(dir.path, 'models'));
    final r = Random(7);
    data = List.generate(300 * 1024, (_) => r.nextInt(256));
    requests.clear();
    honourRange = true;
    cutAfter = null;
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      requests.add(range ?? 'whole');
      final res = req.response;
      if (status != 200) {
        res.statusCode = status;
        await res.close();
        return;
      }
      var from = 0;
      if (range != null && honourRange) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (from >= data.length) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $from-${data.length - 1}/${data.length}');
      }
      res.contentLength = data.length - from;
      final cut = cutAfter;
      if (cut != null) {
        // Drop the connection in the middle.
        final socket = await res.detachSocket();
        socket.add(data.sublist(from, from + cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      // In pieces, so that progress is reported on the way.
      for (var i = from; i < data.length; i += 32 * 1024) {
        res.add(data.sublist(i, min(i + 32 * 1024, data.length)));
        await res.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  test('downloads with progress, checks the hash, then has its real name',
      () async {
    final m = pack();
    final d = downloadModel(m, store);
    final seen = <DownloadProgress>[];
    d.progress.listen(seen.add);
    final path = await d.done;
    expect(path, store.fileOf(m).path);
    expect(File(path).readAsBytesSync(), data);
    expect(store.partOf(m).existsSync(), isFalse);
    expect(seen.length, greaterThan(2));
    expect(seen.first.totalBytes, data.length);
    expect(seen.last.checking, isTrue);
    expect(seen.where((x) => !x.checking).last.fraction, greaterThan(0.5));
    expect(requests, ['whole']);
    // There already: no request at all.
    expect(await downloadModel(m, store).done, path);
    expect(requests.length, 1);
  });

  test('resumes a partial file with Range', () async {
    final m = pack();
    Directory(store.dir).createSync(recursive: true);
    store.partOf(m).writeAsBytesSync(data.sublist(0, 100000));
    final path = await downloadModel(m, store).done;
    expect(requests, ['bytes=100000-']);
    expect(File(path).readAsBytesSync(), data);
  });

  test('a cut connection keeps the part; the next try continues', () async {
    final m = pack();
    cutAfter = 120000;
    await expectLater(
        downloadModel(m, store).done, throwsA(isA<SpeechException>()));
    expect(store.fileOf(m).existsSync(), isFalse);
    final have = store.partOf(m).lengthSync();
    expect(have, greaterThan(0));
    expect(have, lessThan(data.length));
    cutAfter = null;
    final path = await downloadModel(m, store).done;
    expect(requests.last, 'bytes=$have-');
    expect(File(path).readAsBytesSync(), data);
  });

  test('cancel keeps what was fetched', () async {
    final m = pack();
    final d = downloadModel(m, store);
    await d.progress.first;
    await d.cancel();
    await expectLater(
        d.done,
        throwsA(isA<SpeechException>()
            .having((e) => e.cancelled, 'cancelled', isTrue)));
    expect(store.fileOf(m).existsSync(), isFalse);
    expect(store.partOf(m).existsSync(), isTrue);
    await downloadModel(m, store).done;
    expect(requests.last, startsWith('bytes='));
    expect(store.fileOf(m).readAsBytesSync(), data);
  });

  test('a server that ignores Range: starts over, still right', () async {
    final m = pack();
    honourRange = false;
    Directory(store.dir).createSync(recursive: true);
    store.partOf(m).writeAsBytesSync(List.filled(5000, 9));
    final path = await downloadModel(m, store).done;
    expect(File(path).readAsBytesSync(), data);
  });

  test('a part that is already complete is checked and used', () async {
    final m = pack();
    Directory(store.dir).createSync(recursive: true);
    store.partOf(m).writeAsBytesSync(data);
    final path = await downloadModel(m, store).done;
    expect(File(path).readAsBytesSync(), data);
  });

  test('wrong hash: not used, kept as unverified, "use anyway" or remove',
      () async {
    final m = pack(sha: 'a' * 64);
    await expectLater(
        downloadModel(m, store).done,
        throwsA(isA<SpeechException>()
            .having((e) => e.kind, 'kind', 'pack-check')
            .having((e) => e.message, 'message', contains('not the file'))));
    expect(store.fileOf(m).existsSync(), isFalse);
    expect(store.unverifiedOf(m).existsSync(), isTrue);
    expect(store.usedBytes, data.length);
    expect(store.acceptUnverified(m), isTrue);
    expect(store.fileOf(m).readAsBytesSync(), data);
    expect(store.remove(m), data.length);
    expect(store.usedBytes, 0);
    expect(store.acceptUnverified(m), isFalse);
  });

  test('server error: plain message, nothing left under the real name',
      () async {
    status = 404;
    final m = pack();
    await expectLater(
        downloadModel(m, store).done,
        throwsA(isA<SpeechException>()
            .having((e) => e.message, 'message', contains('404'))));
    expect(store.fileOf(m).existsSync(), isFalse);
  });

  test('no hash: a file that does not look like a model is not used',
      () async {
    final junk = File(p.join(dir.path, 'junk.bin'))
      ..writeAsBytesSync(List.filled(2 * 1024 * 1024, 60));
    expect(await looksLikeWhisperModel(junk), isFalse);
    final model = File(p.join(dir.path, 'model.bin'))
      ..writeAsBytesSync(
          [...'lmgg'.codeUnits, ...List.filled(2 * 1024 * 1024, 0)]);
    expect(await looksLikeWhisperModel(model), isTrue);
    final tiny = File(p.join(dir.path, 'tiny.bin'))
      ..writeAsBytesSync('lmgg'.codeUnits);
    expect(await looksLikeWhisperModel(tiny), isFalse);
  });

  test('the table is data: models.json replaces and adds entries', () {
    expect(store.table.map((m) => m.id),
        ['base.en', 'small.en', 'base', 'small', 'large-v3-turbo']);
    for (final m in store.table) {
      expect(m.url, startsWith('https://'));
      expect(m.url, endsWith(m.fileName));
      // No built-in hashes: they could not be checked (see speech_models).
      expect(m.sha256, isEmpty);
      expect(m.sizeLabel, startsWith('about '));
    }
    Directory(store.dir).createSync(recursive: true);
    File(p.join(store.dir, 'models.json')).writeAsStringSync('''
[{"id":"base","fileName":"ggml-base.bin","url":"https://example.org/b.bin",
  "sha256":"ABCD","sizeBytes":1,"sizeLabel":"about 140 MB","title":"All","size":"small"},
 {"id":"tiny","fileName":"ggml-tiny.bin","url":"https://example.org/t.bin",
  "sizeBytes":1,"sizeLabel":"about 75 MB","title":"Tiny","size":"small"}]''');
    expect(store.byId('base')!.url, 'https://example.org/b.bin');
    expect(store.byId('base')!.sha256, 'abcd');
    expect(store.byId('tiny')!.sizeLabel, 'about 75 MB');
    expect(store.table.length, 6);
  });

  test('transcribing with consent downloads the pack, then runs', () async {
    // Covered with a fake program in transcribe_test; here only that the
    // service uses this downloader for a pack that is missing.
    final service = TranscriptionService(rootDir: dir.path);
    final m = pack();
    final path = await service.download(m).done;
    expect(p.dirname(path), service.models.dir);
    expect(bytesLabel(File(path).lengthSync()), '300 KB');
  });
}
