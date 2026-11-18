// Updates (1.12), the rules and the download, against a LOCAL web server:
// what latest.json says (newer / same / older build, old files without
// "platforms"), the once-a-day rule, "skip this version", and the download
// with its size + SHA-256 check, an interrupted download and its resume.
// Nothing here talks to the internet.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/update/update_download.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A small web server that serves [files] and can cut a download short.
class TestServer {
  TestServer._(this._server);
  final HttpServer _server;
  final Map<String, List<int>> files = {};
  final List<String> requests = [];
  final List<String?> ranges = [];

  /// Stop sending after this many bytes of the next download (once).
  int? cutAfter;

  /// Answer with this status instead (once).
  int? failWith;

  /// Pretend not to understand Range requests.
  bool ignoreRange = false;

  String get base => 'http://127.0.0.1:${_server.port}';

  static Future<TestServer> start() async {
    final s = TestServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s._server.listen(s._handle);
    return s;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add(path);
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    final response = request.response;
    try {
      final fail = failWith;
      if (fail != null) {
        failWith = null;
        response.statusCode = fail;
        await response.close();
        return;
      }
      final bytes = files[path];
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      var from = 0;
      if (range != null && !ignoreRange) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (from >= bytes.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $from-${bytes.length - 1}/${bytes.length}');
      }
      final body = bytes.sublist(from);
      final cut = cutAfter;
      if (cut != null) {
        // The connection drops in the middle: the whole length is
        // promised, only [cut] bytes arrive.
        cutAfter = null;
        final partial = response.statusCode == HttpStatus.partialContent;
        final socket = await response.detachSocket(writeHeaders: false);
        socket.add(ascii.encode(
            'HTTP/1.1 ${partial ? '206 Partial Content' : '200 OK'}\r\n'
            'Content-Type: application/octet-stream\r\n'
            'Content-Length: ${body.length}\r\n\r\n'));
        socket.add(body.sublist(0, cut));
        await socket.flush();
        socket.destroy();
        return;
      }
      response.contentLength = body.length;
      response.add(body);
      await response.close();
    } catch (_) {}
  }

  Future<void> close() => _server.close(force: true);
}

String latestJson(TestServer s,
        {int build = 142, String version = '1.12.0', List<int>? windowsZip, String? sha}) =>
    jsonEncode({
      'version': version,
      'build': build,
      'date': '2026-11-18T10:00:00Z',
      'notes_url': 'https://example.org/releases/tag/v$version',
      if (windowsZip != null)
        'platforms': {
          'windows': {
            'url': '${s.base}/dl/ClipForge-windows.zip',
            'size': windowsZip.length,
            'sha256': sha ?? sha256.convert(windowsZip).toString(),
          },
        },
    });

void main() {
  late TestServer server;
  late Directory tmp;
  final payload = List<int>.generate(300 * 1024, (i) => (i * 31 + i ~/ 7) % 251);

  setUp(() async {
    server = await TestServer.start();
    tmp = await Directory.systemTemp.createTemp('clipforge_update_test');
    server.files['/dl/ClipForge-windows.zip'] = payload;
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  Future<UpdateInfo> fetch() =>
      fetchUpdateInfo(Uri.parse('${server.base}/latest.json'), allowHttp: true);

  group('latest.json', () {
    test('newer, same and older builds', () async {
      server.files['/latest.json'] = utf8.encode(latestJson(server, build: 142, windowsZip: payload));
      final info = await fetch();
      expect([info.version, info.build], ['1.12.0', 142]);
      expect(info.notesUrl, 'https://example.org/releases/tag/v1.12.0');
      expect(info.date, DateTime.utc(2026, 11, 18, 10));
      expect(info.isNewerThan(141), isTrue, reason: 'a higher build is newer');
      expect(info.isNewerThan(142), isFalse, reason: 'the same build is not');
      expect(info.isNewerThan(150), isFalse, reason: 'an older release is not offered');
      expect(info.isNewerThan(null), isFalse, reason: 'unknown build: never nag');
      expect(offerUpdate(info, currentBuild: 141), isTrue);
      expect(offerUpdate(info, currentBuild: 142), isFalse);
      expect(offerUpdate(info, currentBuild: 150), isFalse);
      final asset = info.platforms['windows']!;
      expect(asset.fileName, 'ClipForge-windows.zip');
      expect(asset.size, payload.length);
      expect(server.requests, ['/latest.json'], reason: 'the check is ONE request');
    });

    test('a file from before 1.12 (no platforms) still says the version', () async {
      server.files['/latest.json'] = utf8.encode(
          '{"version":"1.11.0","build":139,"date":"2026-11-18T08:00:00Z","notes_url":"https://example.org/n"}');
      final info = await fetch();
      expect(info.build, 139);
      expect(info.platforms, isEmpty);
    });

    test('a byte order mark, a number as text and unknown fields are fine', () {
      final info = UpdateInfo.parse('﻿{"version":"2.0.0","build":"200","extra":[1,2]}');
      expect([info.version, info.build, info.notesUrl], ['2.0.0', 200, null]);
    });

    test('downloads only over https; a bad hash or size entry is ignored', () {
      final info = UpdateInfo.parse(jsonEncode({
        'version': '1.12.0',
        'build': 142,
        'notes_url': 'javascript:alert(1)',
        'platforms': {
          'windows': {'url': 'http://example.org/a.zip', 'size': 5, 'sha256': 'a' * 64},
          'macos': {'url': 'https://example.org/b.zip', 'size': 5, 'sha256': 'zz'},
          'android': {'url': 'https://example.org/c.apk', 'size': 0, 'sha256': 'b' * 64},
          'android32': {'url': 'https://example.org/d.apk', 'size': 7, 'sha256': 'C' * 64},
        },
      }));
      expect(info.platforms.keys, ['android32']);
      expect(info.platforms['android32']!.sha256, 'c' * 64);
      expect(info.notesUrl, isNull);
    });

    test('offline, a server error and nonsense are UpdateExceptions', () async {
      await expectLater(fetch(), throwsA(isA<UpdateException>()), reason: '404');
      server.files['/latest.json'] = utf8.encode('<html>Not here</html>');
      await expectLater(
          fetch(),
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'message', contains('not what ClipForge expected'))));
      server.files['/latest.json'] = utf8.encode('{"version":"1.0.0"}');
      await expectLater(fetch(), throwsA(isA<UpdateException>()));
      final url = Uri.parse('${server.base}/latest.json');
      await server.close();
      await expectLater(
          fetchUpdateInfo(url, allowHttp: true),
          throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', 'offline')));
    });
  });

  group('when to check and when to offer', () {
    final now = DateTime.utc(2026, 11, 18, 12);
    test('at most once a day, and not when switched off', () {
      expect(autoCheckDue(switchedOff: false, lastCheck: null, now: now), isTrue);
      expect(
          autoCheckDue(
              switchedOff: false,
              lastCheck: now.subtract(const Duration(hours: 23, minutes: 59)),
              now: now),
          isFalse);
      expect(
          autoCheckDue(
              switchedOff: false,
              lastCheck: now.subtract(const Duration(hours: 24)),
              now: now),
          isTrue);
      expect(autoCheckDue(switchedOff: true, lastCheck: null, now: now), isFalse);
      // A clock that was set back: check rather than wait for ever.
      expect(
          autoCheckDue(
              switchedOff: false, lastCheck: now.add(const Duration(days: 3)), now: now),
          isTrue);
    });

    test('skip this version: hidden until a newer one, shown by a manual check', () {
      const v142 = UpdateInfo(version: '1.12.0', build: 142);
      const v150 = UpdateInfo(version: '1.13.0', build: 150);
      expect(offerUpdate(v142, currentBuild: 139, skippedBuild: 142), isFalse);
      expect(offerUpdate(v142, currentBuild: 139, skippedBuild: 142, manual: true), isTrue);
      expect(offerUpdate(v150, currentBuild: 139, skippedBuild: 142), isTrue);
    });

    test('which file belongs to which device', () {
      expect(updatePlatformKey('windows'), 'windows');
      expect(updatePlatformKey('macos'), 'macos');
      expect(updatePlatformKey('android'), 'android');
      expect(updatePlatformKey('android', android32: true), 'android32');
      expect(updatePlatformKey('linux'), isNull, reason: 'download page only');
    });
  });

  group('download', () {
    UpdateAsset asset({String? sha, int? size}) => UpdateAsset(
        url: '${server.base}/dl/ClipForge-windows.zip',
        size: size ?? payload.length,
        sha256: sha ?? sha256.convert(payload).toString());

    test('downloads with progress, checks, and gives the file its name', () async {
      final d = downloadUpdate(asset(), tmp.path, build: 142);
      final seen = <UpdateProgress>[];
      d.progress.listen(seen.add);
      final path = await d.done;
      expect(p.basename(path), 'b142-ClipForge-windows.zip');
      expect(File(path).readAsBytesSync(), payload);
      expect(seen.last.checking, isTrue);
      expect(File('$path.part').existsSync(), isFalse);
      // Asked again: the checked file is reused, nothing is fetched.
      final before = server.requests.length;
      expect(await downloadUpdate(asset(), tmp.path, build: 142).done, path);
      expect(server.requests.length, before);
    });

    test('a wrong fingerprint: deleted, never kept under any name', () async {
      final d = downloadUpdate(asset(sha: 'f' * 64), tmp.path, build: 142);
      await expectLater(
          d.done,
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'check')
              .having((e) => e.message, 'message', contains('nothing was installed'))));
      expect(tmp.listSync(), isEmpty, reason: 'no file is left behind');
    });

    test('a wrong size: refused the same way', () async {
      final d = downloadUpdate(asset(size: payload.length - 10), tmp.path, build: 142);
      await expectLater(d.done,
          throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', 'check')));
      expect(tmp.listSync(), isEmpty);
    });

    test('an interrupted download continues from where it stopped', () async {
      server.cutAfter = 100 * 1024;
      final first = downloadUpdate(asset(), tmp.path, build: 142);
      await expectLater(
          first.done,
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'offline')
              .having((e) => e.message, 'message', contains('continues from where it'))));
      final part = File(p.join(tmp.path, 'b142-ClipForge-windows.zip.part'));
      final have = part.lengthSync();
      expect(have, inInclusiveRange(1, 100 * 1024));

      final second = downloadUpdate(asset(), tmp.path, build: 142);
      final path = await second.done;
      expect(server.ranges.last, 'bytes=$have-', reason: 'only the rest is asked for');
      expect(File(path).readAsBytesSync(), payload, reason: 'the pieces fit together');
    });

    test('a server that ignores the resume starts over, and it still fits', () async {
      File(p.join(tmp.path, 'b142-ClipForge-windows.zip.part'))
          .writeAsBytesSync(payload.sublist(0, 5000));
      server.ignoreRange = true;
      final path = await downloadUpdate(asset(), tmp.path, build: 142).done;
      expect(File(path).readAsBytesSync(), payload);
    });

    test('a half file of something else fails the check and is removed', () async {
      File(p.join(tmp.path, 'b142-ClipForge-windows.zip.part'))
          .writeAsBytesSync(List.filled(5000, 7));
      await expectLater(downloadUpdate(asset(), tmp.path, build: 142).done,
          throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', 'check')));
      expect(tmp.listSync(), isEmpty);
      // The next try starts clean and works.
      expect(File(await downloadUpdate(asset(), tmp.path, build: 142).done).readAsBytesSync(),
          payload);
    });

    test('stopping keeps what was fetched', () async {
      server.files['/dl/ClipForge-windows.zip'] = payload;
      server.cutAfter = 50 * 1024;
      final d = downloadUpdate(asset(), tmp.path, build: 142);
      await d.cancel();
      await expectLater(d.done, throwsA(isA<UpdateException>()));
    });

    test('a server error is reported; old files of other versions are tidied', () async {
      server.failWith = 500;
      await expectLater(
          downloadUpdate(asset(), tmp.path, build: 142).done,
          throwsA(isA<UpdateException>()
              .having((e) => e.message, 'message', contains('500'))));
      File(p.join(tmp.path, 'b139-ClipForge-windows.zip')).writeAsStringSync('old');
      File(p.join(tmp.path, 'b142-ClipForge-windows.zip.part')).writeAsStringSync('new');
      pruneUpdateFiles(tmp.path, keepBuild: 142);
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['b142-ClipForge-windows.zip.part']);
    });
  });
}
