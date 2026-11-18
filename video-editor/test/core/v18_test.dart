// 1.8.0: keeping media on Android (missing-file root cause), clean-up that
// never deletes what an open editor still uses, music loops and "Fit music
// to video", music credits and the Openverse search format.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/music/openverse.dart';
import 'package:clipforge/core/storage/media_cleanup.dart';
import 'package:clipforge/core/storage/media_import.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cf18_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String rel, List<int> bytes) {
    final f = File(p.join(tmp.path, rel))..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f.path;
  }

  group('missing files on Android: the cause', () {
    test('a path through a linked folder is inside the real folder '
        '(/data/user/0 -> /data/data)', () {
      // The picker returns canonical paths (/data/data/<app>/cache/...),
      // path_provider the linked one (/data/user/0/<app>/cache). 1.7 compared
      // the strings, so the cached copy was never moved and the system later
      // emptied the cache: "Missing · 20261116_205955.mp4".
      final real = Directory(p.join(tmp.path, 'data', 'data', 'app', 'cache'))
        ..createSync(recursive: true);
      Directory(p.join(tmp.path, 'data', 'user')).createSync(recursive: true);
      Link(p.join(tmp.path, 'data', 'user', '0'))
          .createSync(p.join(tmp.path, 'data', 'data'));
      final picked = write(
          'data/data/app/cache/file_picker/1234/20261116_205955.mp4', [1, 2]);
      final linkedCache = p.join(tmp.path, 'data', 'user', '0', 'app', 'cache');
      expect(p.isWithin(linkedCache, picked), isFalse); // the 1.7 check
      expect(isWithinDir(linkedCache, picked), isTrue);
      expect(isWithinDir(real.path, picked), isTrue);
      expect(isWithinDir(p.join(tmp.path, 'media'), picked), isFalse);
    });
  });

  group('keepMediaCopy', () {
    test('the picker\'s cache copy is moved into the media folder, keeping '
        'its name', () async {
      final media = p.join(tmp.path, 'media');
      final cached = write('cache/file_picker/u1/20261116_205955.mp4',
          List.filled(1000, 7));
      final kept = await keepMediaCopy(cached, media, move: true);
      expect(kept.problem, isNull);
      expect(kept.path, startsWith(p.join(media, kImportedDir)));
      expect(p.basename(kept.path), '20261116_205955.mp4');
      expect(File(kept.path).lengthSync(), 1000);
      expect(File(cached).existsSync(), isFalse);
      expect(kept.copiedBytes, 0);
    });

    test('the same recording picked twice is stored once', () async {
      final media = p.join(tmp.path, 'media');
      final bytes = List.generate(600 * 1024, (i) => i % 251);
      final a = await keepMediaCopy(
          write('cache/a/clip.mp4', bytes), media, move: true);
      final b = await keepMediaCopy(
          write('cache/b/clip.mp4', bytes), media, move: true);
      expect(b.path, a.path);
      expect(b.reused, isTrue);
      expect(File(p.join(tmp.path, 'cache/b/clip.mp4')).existsSync(), isFalse);
      // A different recording with the same name is kept apart.
      final other = List.of(bytes)..[bytes.length - 1] = 0;
      final c = await keepMediaCopy(
          write('cache/c/clip.mp4', other), media, move: true);
      expect(c.path, isNot(a.path));
      expect(
          Directory(p.join(media, kImportedDir)).listSync().length, 2);
    });

    test('a file elsewhere is copied (the original stays); no room = used '
        'in place with a warning', () async {
      final media = p.join(tmp.path, 'media');
      final src = write('DCIM/Camera/v.mp4', List.filled(5000, 1));
      final kept = await keepMediaCopy(src, media, freeBytes: 1 << 40);
      expect(kept.path, isNot(src));
      expect(kept.copiedBytes, 5000);
      expect(File(src).existsSync(), isTrue);
      final src2 = write('DCIM/Camera/w.mp4', List.filled(5000, 2));
      final full = await keepMediaCopy(src2, media,
          freeBytes: kKeepFreeReserveBytes + 100);
      expect(full.path, src2);
      expect(full.problem, contains('not enough free space'));
      // A file already in the media folder is left alone.
      expect((await keepMediaCopy(kept.path, media)).path, kept.path);
      // A file that cannot be read stays as it was, with a problem.
      final gone = await keepMediaCopy(p.join(tmp.path, 'nope.mp4'), media);
      expect(gone.path, p.join(tmp.path, 'nope.mp4'));
      expect(gone.problem, isNotNull);
    });

    test('fingerprint: same content, other date = same; other content = '
        'different', () async {
      final a = write('x/a', List.filled(300000, 3));
      final b = write('y/b', List.filled(300000, 3));
      File(b).setLastModifiedSync(DateTime(2020));
      final c = write('z/c', List.filled(300001, 3));
      expect(await mediaFingerprint(a), await mediaFingerprint(b));
      expect(await mediaFingerprint(a), isNot(await mediaFingerprint(c)));
      expect(await mediaFingerprint(a), hasLength(16));
    });

    test('rescue: a pre-1.8 project pointing into the cache is moved out',
        () async {
      final media = p.join(tmp.path, 'media');
      final cache = p.join(tmp.path, 'cache');
      final inCache = write('cache/file_picker/u/a.mp4', [1, 2, 3]);
      final gone = p.join(cache, 'file_picker', 'v', 'b.mp4');
      final outside = write('DCIM/c.mp4', [4]);
      final proj = project(clips: [
        video('a').copyWith(path: inCache),
        video('b').copyWith(path: gone),
        video('c').copyWith(path: outside),
      ]);
      final moved = await rescueMediaPaths(proj, cache, media);
      expect(moved.keys, [inCache]);
      final fixed = relinkProject(proj, moved);
      expect(fixed.clips[0].path, moved[inCache]);
      expect(File(fixed.clips[0].path).existsSync(), isTrue);
      expect(fixed.clips[1].path, gone); // already lost: Find file
      expect(fixed.clips[2].path, outside);
    });
  });

  group('clean-up never deletes what is still used', () {
    test('keep: files an open editor (or its undo history) uses stay',
        () async {
      final media = p.join(tmp.path, 'media');
      final store = ProjectStore.atPath(p.join(tmp.path, 'projects'));
      final used = write('media/p/used.mp4', [1]);
      final undoOnly = write('media/p/deleted-clip.mp4', [2]);
      final unused = write('media/p/unused.mp4', [3]);
      final e = ProjectEditor(project(clips: [
        video('a').copyWith(path: used),
        video('b').copyWith(path: undoOnly),
      ]));
      e.removeClip('b');
      await store.save(e.project);
      expect(e.mediaPathsInHistory, containsAll([used, undoOnly]));
      await removeUnreferencedMedia(media, store,
          now: () => DateTime.now().add(const Duration(hours: 1)),
          keep: e.mediaPathsInHistory);
      expect(File(used).existsSync(), isTrue);
      expect(File(undoOnly).existsSync(), isTrue);
      expect(File(unused).existsSync(), isFalse);
    });

    test('relinkMediaQuietly is not an undo step and fixes the history',
        () {
      final e = ProjectEditor(project(clips: [video('a'), video('b')]));
      e.removeClip('b');
      final steps = e.history.length;
      e.relinkMediaQuietly({'/media/b.mp4': '/kept/b.mp4'});
      expect(e.history.length, steps);
      e.undo();
      expect(e.project.clips.last.path, '/kept/b.mp4');
    });
  });

  group('loop', () {
    AudioClip song({int source = 10000, int loopMs = 0, int start = 0}) =>
        audio('m', source: source, startMs: start).copyWith(loopMs: loopMs);

    test('loopPieces: repeats overlap by the cross-fade, the last is cut', () {
      final a = song(loopMs: 25000, start: 1000);
      expect(a.durationMs, 25000);
      expect(a.endMs, 26000);
      final pieces = a.loopPieces;
      expect(pieces.map((x) => x.startMs), [1000, 10700, 20400]);
      expect(pieces.map((x) => x.id), ['m', 'm~loop1', 'm~loop2']);
      expect(pieces[0].durationMs, 10000);
      expect(pieces.last.endMs, 26000);
      expect(pieces[1].fadeInMs, kLoopCrossfadeMs);
      expect(pieces[0].fadeOutMs, kLoopCrossfadeMs);
      expect(pieces.every((x) => !x.looped), isTrue);
      expect(loopBaseId('m~loop2'), 'm');
      // Not looped: itself.
      expect(song().loopPieces.single.id, 'm');
    });

    test('JSON keeps the loop and the credit; old JSON has none', () {
      const credit = MusicCredit(
          title: 'Sunny', creator: 'Ann', licence: 'by', licenceVersion: '4.0',
          sourceUrl: 'https://example.org/s');
      final a = song(loopMs: 20000).copyWith(credit: credit);
      final back = AudioClip.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.loopMs, 20000);
      expect(back.credit, credit);
      expect(back.credit!.licenceName, 'CC BY 4.0');
      expect(song().toJson().containsKey('loopMs'), isFalse);
      expect(song().toJson().containsKey('credit'), isFalse);
    });

    test('Fit music to video: longer music is cut, with a 2 s fade-out', () {
      final e = ProjectEditor(project(
          clips: [video('v', source: 20000)],
          audio: [song(source: 60000, start: 3000)]));
      expect(e.fitMusicToVideo('m'), FitMusicResult.fitted);
      final a = e.project.audio.single;
      expect(a.endMs, 20000);
      expect(a.fadeOutMs, kFitMusicFadeOutMs);
      expect(a.looped, isFalse);
      expect(e.history.last.label, 'Fitted music to the video');
      expect(e.fitMusicToVideo('m'), FitMusicResult.alreadyFits);
      e.undo();
      expect(e.project.audio.single.endMs, 63000);
    });

    test('Fit music to video: shorter music asks, then loops (one step)', () {
      final e = ProjectEditor(project(
          clips: [video('v', source: 30000)], audio: [song(source: 8000)]));
      final before = e.history.length;
      expect(e.fitMusicToVideo('m'), FitMusicResult.tooShort);
      expect(e.history.length, before);
      expect(e.fitMusicToVideo('m', loop: true), FitMusicResult.looped);
      final a = e.project.audio.single;
      expect(a.loopMs, 30000);
      expect(a.endMs, 30000);
      expect(a.fadeOutMs, kFitMusicFadeOutMs);
      expect(e.history.length, before + 1);
      expect(e.history.last.label, 'Looped music to fit the video');
      e.stopLoop('m');
      expect(e.project.audio.single.looped, isFalse);
      expect(e.history.last.label, 'Music no longer loops');
    });

    test('Fit music to video stops before the next sound on its track', () {
      final e = ProjectEditor(project(
          clips: [video('v', source: 30000)],
          audio: [
            song(source: 60000),
            audio('n', source: 5000, startMs: 20000),
          ]));
      expect(e.fitMusicToVideo('m'), FitMusicResult.stoppedAtNext);
      expect(e.project.audio.firstWhere((a) => a.id == 'm').endMs, 20000);
    });

    test('trimming a looped sound changes the loop, not the pass', () {
      final e = ProjectEditor(project(
          clips: [video('v', source: 30000)],
          audio: [song(source: 8000, loopMs: 30000)]));
      final a = e.project.audio.single;
      e.updateAudio(a.copyWith(loopMs: 20000));
      expect(e.project.audio.single.endMs, 20000);
      expect(e.project.audio.single.outMs, 8000);
      expect(e.history.last.label, 'Trimmed music');
      // A loop shorter than one pass is no loop.
      e.updateAudio(e.project.audio.single.copyWith(loopMs: 5000));
      expect(e.project.audio.single.looped, isFalse);
    });
  });

  group('Openverse (recorded answer)', () {
    final fixture =
        File('test/core/fixtures/openverse_audio.json').readAsStringSync();

    test('the request asks for safe licences, 20 a page, no mature', () {
      final u = openverseSearchUri('happy ukulele');
      expect(u.host, 'api.openverse.org');
      expect(u.path, '/v1/audio/');
      expect(u.queryParameters['q'], 'happy ukulele');
      expect(u.queryParameters['license'], 'cc0,pdm,by,by-sa');
      expect(u.queryParameters['page_size'], '20');
      expect(u.queryParameters['mature'], 'false');
      expect(openverseSearchUri('x', includeRestricted: true)
          .queryParameters['license'], contains('by-nc'));
    });

    test('results: title, artist, length, licence; NC/ND and mature dropped '
        'unless asked for', () async {
      final client = OpenverseClient(get: (uri) async => fixture);
      final page = await client.search('happy');
      expect(page.results.map((r) => r.title),
          ['Happy Ukulele Morning', 'Untitled', 'Old Song']);
      final r = page.results.first;
      expect(r.creator, 'Sunny Strings');
      expect(r.durationMs, 95000);
      expect(r.licenceName, 'CC BY 4.0');
      expect(r.fileName, 'Happy Ukulele Morning - Sunny Strings.mp3');
      expect(r.credit.shortLine,
          'Music: "Happy Ukulele Morning" by Sunny Strings (CC BY 4.0)');
      expect(r.credit.fullLine, contains('https://www.jamendo.com/track/1'));
      expect(r.credit.needsCredit, isTrue);
      expect(page.results[1].licenceName, 'CC0 1.0');
      expect(page.results[1].credit.needsCredit, isFalse);
      expect(page.results[2].licenceName, 'Public domain');
      expect(page.total, 6);
      expect(page.hasMore, isTrue);
      final all = parseOpenverseAudio(fixture, includeRestricted: true);
      expect(all.results.length, 4); // + the NC one; mature never
    });

    test('a broken answer is a readable error', () {
      expect(() => parseOpenverseAudio('<html>'),
          throwsA(isA<MusicSearchException>()));
    });

    test('offline: a refused connection is the offline message', () async {
      // Nothing listens on this port.
      final client = OpenverseClient(get: (uri) async {
        try {
          final c = HttpClient();
          await c.getUrl(Uri.parse('http://127.0.0.1:9/'));
          return '';
        } on SocketException {
          throw offlineError;
        }
      });
      await expectLater(client.search('x'),
          throwsA(isA<MusicSearchException>()
              .having((e) => e.offline, 'offline', isTrue)));
    });

    test('credits of a project, once each', () {
      const c = MusicCredit(title: 'A', creator: 'B', licence: 'by-sa',
          licenceVersion: '4.0');
      final proj = project(audio: [
        audio('x').copyWith(credit: c),
        audio('y', startMs: 40000).copyWith(credit: c),
        audio('z', startMs: 80000),
      ]);
      expect(projectCredits(proj), [c]);
      expect(creditsCaption(proj), 'Music: "A" by B (CC BY-SA 4.0)');
      expect(creditsText(project()), isEmpty);
    });
  });
}
