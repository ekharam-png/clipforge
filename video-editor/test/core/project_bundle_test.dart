import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_bundle.dart';
import 'package:clipforge/core/transcript/transcript_store.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

Uint8List bytes(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + seed) % 256));

void main() {
  late Directory tmp;
  late ProjectStore store;
  late String mediaDir;
  var ids = 0;
  String newId() => 'imported${++ids}';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipforge_bundle_test');
    store = ProjectStore.atPath(p.join(tmp.path, 'projects'));
    mediaDir = p.join(tmp.path, 'device2', 'media');
    ids = 0;
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> write(String relative, Uint8List data) async {
    final f = File(p.join(tmp.path, 'device1', relative));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data);
    return f.path;
  }

  Clip clipAt(String id, String path, {ClipType type = ClipType.video}) => Clip(
        id: id,
        type: type,
        path: path,
        sourceDurationMs: type == ClipType.photo ? 0 : 10000,
        inMs: 0,
        outMs: type == ClipType.photo ? 3000 : 10000,
        width: 1920,
        height: 1080,
      );

  AudioClip audioAt(String id, String path) => AudioClip(
      id: id, path: path, sourceDurationMs: 30000, startMs: 0, inMs: 0, outMs: 30000);

  /// The entries of a zip: name -> content.
  Map<String, Uint8List> readZip(String path) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    return {
      for (final f in archive.files)
        if (f.isFile) f.name: f.content,
    };
  }

  /// Writes a zip with exactly these entries.
  Future<String> makeZip(Map<String, List<int>> entries, {String name = 'made.zip'}) async {
    final archive = Archive();
    for (final e in entries.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, e.value));
    }
    final path = p.join(tmp.path, name);
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    return path;
  }

  List<int> projectJson({Object? schemaVersion, String path = 'media/a.mp4'}) {
    final json = project(clips: [clipAt('a', path)]).toJson();
    if (schemaVersion != null) json['schemaVersion'] = schemaVersion;
    return utf8.encode(jsonEncode(json));
  }

  Future<List<String>> filesUnder(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return [];
    return [
      await for (final e in d.list(recursive: true))
        if (e is File) p.relative(e.path, from: dir),
    ]..sort();
  }

  group('exportBundle', () {
    test('writes project.json with relative media paths plus the media', () async {
      final video1 = await write('camera/clip.mp4', bytes(70000, 1));
      final video2 = await write('downloads/clip.mp4', bytes(50000, 2));
      final picture = await write('camera/Фото 1.jpg', bytes(3000, 3));
      final song = await write('music/song.mp3', bytes(20000, 4));
      final missing = p.join(tmp.path, 'device1', 'gone', 'lost.mp4');
      final source = project(
        name: 'Trip',
        clips: [
          clipAt('a', video1).copyWith(speed: 2, zoom: 1.5),
          clipAt('b', video2),
          clipAt('c', video1), // the same file again (a split)
          clipAt('d', picture, type: ClipType.photo),
          clipAt('e', missing),
        ],
        audio: [audioAt('m', song), audioAt('n', video2)],
        titles: [title('t')],
      );
      final before = content(source);
      final zip = p.join(tmp.path, 'out', 'nested', 'trip.zip');
      final progress = <double>[];

      await exportBundle(source, zip, onProgress: progress.add);

      expect(content(source), before, reason: 'the project is not touched');
      final entries = readZip(zip);
      expect(entries.keys.toSet(), {
        'project.json',
        'media/clip.mp4',
        'media/clip_2.mp4',
        'media/Фото 1.jpg',
        'media/song.mp3',
      });
      expect(entries['media/clip.mp4'], bytes(70000, 1));
      expect(entries['media/clip_2.mp4'], bytes(50000, 2));
      expect(entries['media/Фото 1.jpg'], bytes(3000, 3));
      expect(entries['media/song.mp3'], bytes(20000, 4));

      final json = jsonDecode(utf8.decode(entries['project.json']!)) as Map<String, dynamic>;
      expect(json['schemaVersion'], kSchemaVersion);
      expect(json['id'], 'p1');
      expect([for (final c in json['clips'] as List) (c as Map)['path']], [
        'media/clip.mp4',
        'media/clip_2.mp4',
        'media/clip.mp4',
        'media/Фото 1.jpg',
        missing,
      ]);
      expect([for (final a in json['audio'] as List) (a as Map)['path']],
          ['media/song.mp3', 'media/clip_2.mp4']);
      // Apart from the paths the bundled project is the same.
      final bundled = Project.fromJson(json);
      expect(bundled.clips[0].speed, 2);
      expect(bundled.clips[0].zoom, 1.5);
      expect(bundled.titles.single.id, 't');

      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      for (var i = 0; i < progress.length; i++) {
        expect(progress[i], inInclusiveRange(0.0, 1.0));
        if (i > 0) expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      // Nothing but the bundle is left next to it.
      expect(await filesUnder(p.dirname(zip)), ['trip.zip']);
    });

    test('transcripts travel with the project (1.12) and still fit after unpacking', () async {
      final video = await write('videos/talk.mp4', Uint8List.fromList(List.generate(4000, (i) => i % 200)));
      final project = (await store.create('Podcast')).copyWith(clips: [clipAt('c1', video)]);
      await store.save(project);
      // What transcribing leaves in the project folder: one file per media
      // file, named after a fingerprint of the media's content.
      final key = (await TranscriptStore.keyFor(video, 0))!;
      final dir = Directory(p.join(tmp.path, 'projects', project.id, 'transcripts'))
        ..createSync(recursive: true);
      File(p.join(dir.path, '$key.json')).writeAsStringSync('{"words":"hello world"}');
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('not a transcript');

      final zip = p.join(tmp.path, 'out', 'podcast.clipforge.zip');
      await exportBundle(project, zip, transcriptsDir: dir.path);
      final entries = readZip(zip);
      expect(entries.keys, containsAll(['project.json', 'media/talk.mp4', 'transcripts/$key.json']));
      expect(entries.keys.where((k) => k.contains('notes')), isEmpty);

      final imported = await importBundle(zip, store: store, mediaDir: mediaDir, newId: newId);
      final arrived = File(p.join(tmp.path, 'projects', imported.id, 'transcripts', '$key.json'));
      expect(arrived.readAsStringSync(), '{"words":"hello world"}');
      // The unpacked media has the same content, so the same name fits it.
      expect(await TranscriptStore.keyFor(imported.clips.single.path, 0), key);

      // Without transcripts nothing changes, and odd entries are ignored.
      final plain = p.join(tmp.path, 'out', 'plain.clipforge.zip');
      await exportBundle(project, plain);
      expect(readZip(plain).keys.where((k) => k.startsWith('transcripts/')), isEmpty);
    });

    test('freeProjectName: a taken name gets (2), (3); the project itself does not count', () async {
      final a = await store.create('Holiday');
      await store.create('holiday (2)');
      expect(await freeProjectName(store, 'Garden'), 'Garden');
      expect(await freeProjectName(store, ' Holiday '), 'Holiday (3)');
      expect(await freeProjectName(store, 'HOLIDAY', exceptId: a.id), 'HOLIDAY',
          reason: 'renaming a project to its own name (other case) is fine');
    });

    test('media is stored without compression', () async {
      final path = await write('zeros.mp4', Uint8List(200000));
      final zip = p.join(tmp.path, 'z.zip');
      await exportBundle(project(clips: [clipAt('a', path)]), zip);
      expect(File(zip).lengthSync(), greaterThan(200000));
      final archive = ZipDecoder().decodeBytes(File(zip).readAsBytesSync());
      expect(archive.find('media/zeros.mp4')!.compression, CompressionType.none);
    });

    test('a project without media, and replacing an existing bundle', () async {
      final zip = p.join(tmp.path, 'empty.zip');
      await File(zip).writeAsString('old content');
      final progress = <double>[];
      await exportBundle(project(name: 'Empty'), zip, onProgress: progress.add);
      final entries = readZip(zip);
      expect(entries.keys, ['project.json']);
      expect((jsonDecode(utf8.decode(entries['project.json']!)) as Map)['name'], 'Empty');
      expect(progress.last, 1.0);
    });

    test('names differing only by case, and odd names, stay distinct', () async {
      final a = await write('one/Clip.MP4', bytes(100, 1));
      final b = await write('two/clip.mp4', bytes(100, 2));
      final c = await write('three/.hidden', bytes(100, 3));
      final d = await write('four/noext', bytes(100, 4));
      final e = await write('five/noext', bytes(100, 5));
      final zip = p.join(tmp.path, 'case.zip');
      await exportBundle(
          project(clips: [for (final x in [a, b, c, d, e]) clipAt(p.basename(p.dirname(x)), x)]),
          zip);
      final entries = readZip(zip);
      expect(entries.keys.toSet(), {
        'project.json',
        'media/Clip.MP4',
        'media/clip_2.mp4',
        'media/hidden',
        'media/noext',
        'media/noext_2',
      });
      expect(entries['media/noext_2'], bytes(100, 5));
    });

    test('a failed export leaves no file behind', () async {
      final path = await write('a.mp4', bytes(100, 1));
      // The target "folder" is a file, so the bundle cannot be created.
      final blocker = File(p.join(tmp.path, 'blocker'));
      await blocker.writeAsString('x');
      final zip = p.join(blocker.path, 'x.zip');
      await expectLater(exportBundle(project(clips: [clipAt('a', path)]), zip),
          throwsA(isA<FileSystemException>()));
      expect(await filesUnder(tmp.path), contains('blocker'));
      expect((await filesUnder(tmp.path)).where((f) => f.contains('.part')), isEmpty);
    });
  });

  group('importBundle', () {
    test('round trip to another device', () async {
      final video1 = await write('camera/clip.mp4', bytes(300000, 1));
      final video2 = await write('downloads/clip.mp4', bytes(50000, 2));
      final song = await write('music/song.mp3', bytes(20000, 4));
      final missing = p.join(tmp.path, 'device1', 'gone', 'lost.mp4');
      final source = project(
        id: 'original',
        name: 'Trip',
        aspect: CanvasAspect.portrait9x16,
        clips: [
          clipAt('a', video1).copyWith(
              speed: 2, transition: TransitionType.crossfade, brightness: 0.2),
          clipAt('b', video2),
          clipAt('c', video1),
          clipAt('e', missing),
        ],
        audio: [audioAt('m', song)],
        titles: [title('t').copyWith(kind: TitleKind.caption)],
      ).copyWith(duckMusic: true);
      final zip = p.join(tmp.path, 'trip.zip');
      await exportBundle(source, zip);

      // The other device has none of the original files.
      await Directory(p.join(tmp.path, 'device1')).delete(recursive: true);
      final before = DateTime.now();
      final imported = await importBundle(zip,
          store: store, mediaDir: mediaDir, newId: newId);

      expect(imported.id, 'imported1');
      expect(imported.name, 'Trip');
      expect(imported.createdAt, source.createdAt);
      expect(imported.updatedAt.isBefore(before), isFalse);
      final dir = p.join(mediaDir, 'imported1');
      expect([for (final c in imported.clips) c.path], [
        p.join(dir, 'clip.mp4'),
        p.join(dir, 'clip_2.mp4'),
        p.join(dir, 'clip.mp4'),
        missing,
      ]);
      expect(imported.audio.single.path, p.join(dir, 'song.mp3'));
      for (final c in imported.clips) {
        expect(p.isAbsolute(c.path), isTrue);
      }
      expect(await File(p.join(dir, 'clip.mp4')).readAsBytes(), bytes(300000, 1));
      expect(await File(p.join(dir, 'clip_2.mp4')).readAsBytes(), bytes(50000, 2));
      expect(await File(p.join(dir, 'song.mp3')).readAsBytes(), bytes(20000, 4));
      expect(await filesUnder(dir), ['clip.mp4', 'clip_2.mp4', 'song.mp3']);

      // Everything but id, paths and updatedAt is the same.
      Map<String, dynamic> stripped(Project q) {
        final j = q.toJson()
          ..remove('id')
          ..remove('updatedAt');
        for (final k in ['clips', 'audio']) {
          for (final item in j[k] as List) {
            (item as Map).remove('path');
          }
        }
        return j;
      }

      expect(jsonEncode(stripped(imported)), jsonEncode(stripped(source)));

      // It was saved through the store.
      final loaded = await store.load('imported1');
      expect(content(loaded), content(imported));
      expect((await store.list()).single.id, 'imported1');
    });

    test('importing twice gives two independent projects', () async {
      final video1 = await write('clip.mp4', bytes(1000, 1));
      final zip = p.join(tmp.path, 'trip.zip');
      await exportBundle(project(clips: [clipAt('a', video1)]), zip);
      final one = await importBundle(zip, store: store, mediaDir: mediaDir, newId: newId);
      final two = await importBundle(zip, store: store, mediaDir: mediaDir, newId: newId);
      expect(one.id, isNot(two.id));
      expect(one.clips.single.path, isNot(two.clips.single.path));
      expect(File(one.clips.single.path).existsSync(), isTrue);
      expect(File(two.clips.single.path).existsSync(), isTrue);
      expect((await store.list()).length, 2);
    });

    test('a relative mediaDir still gives absolute paths', () async {
      final video1 = await write('clip.mp4', bytes(1000, 1));
      final zip = p.join(tmp.path, 'trip.zip');
      await exportBundle(project(clips: [clipAt('a', video1)]), zip);
      final relative = p.relative(mediaDir);
      final imported =
          await importBundle(zip, store: store, mediaDir: relative, newId: newId);
      expect(p.isAbsolute(imported.clips.single.path), isTrue);
      expect(p.equals(imported.clips.single.path, p.join(mediaDir, 'imported1', 'clip.mp4')),
          isTrue);
    });

    test('folders inside media/ are kept; media paths not in the zip stay', () async {
      final json = project(clips: [
        clipAt('a', 'media/sub/a.mp4'),
        clipAt('b', 'media/not-there.mp4'),
        clipAt('c', '/somewhere/else.mp4'),
      ]).toJson();
      final zip = await makeZip({
        'project.json': utf8.encode(jsonEncode(json)),
        'media/sub/a.mp4': bytes(10, 1),
        'notes.txt': utf8.encode('not media'),
      });
      final imported =
          await importBundle(zip, store: store, mediaDir: mediaDir, newId: newId);
      final dir = p.join(mediaDir, 'imported1');
      expect([for (final c in imported.clips) c.path],
          [p.join(dir, 'sub', 'a.mp4'), 'media/not-there.mp4', '/somewhere/else.mp4']);
      expect(await filesUnder(dir), [p.join('sub', 'a.mp4')]);
    });

    test('a version 1 bundle imports with defaults', () async {
      final json = project(clips: [clipAt('a', 'media/a.mp4')]).toJson()
        ..['schemaVersion'] = 1
        ..remove('duckMusic');
      final clip = (json['clips'] as List).first as Map;
      for (final k in ['speed', 'denoise', 'brightness', 'contrast', 'saturation', 'zoom', 'transition', 'transitionMs']) {
        clip.remove(k);
      }
      final zip = await makeZip({
        'project.json': utf8.encode(jsonEncode(json)),
        'media/a.mp4': bytes(10, 1),
      });
      final imported =
          await importBundle(zip, store: store, mediaDir: mediaDir, newId: newId);
      expect(imported.clips.single.speed, 1.0);
      expect(imported.clips.single.transition, TransitionType.none);
    });

    Future<void> expectRejected(Future<String> zip, {String? message}) async {
      final path = await zip;
      await expectLater(
          importBundle(path, store: store, mediaDir: mediaDir, newId: newId),
          throwsA(isA<FormatException>().having((e) => e.message, 'message',
              message == null ? anything : contains(message))));
      // Nothing was saved and nothing was written anywhere.
      expect(await store.list(), isEmpty);
      expect(await filesUnder(mediaDir), isEmpty);
      expect(await Directory(p.join(mediaDir, 'imported1')).exists(), isFalse);
    }

    test('entries that would escape the target folder are rejected (zip slip)', () async {
      final outside = [
        '../evil.txt',
        'media/../../evil.txt',
        'media/../../../evil.txt',
        '/abs/evil.txt',
        r'media\..\..\evil.txt',
        r'C:\evil.txt',
        'media/sub/../../../evil.txt',
      ];
      for (final name in outside) {
        ids = 0;
        await expectRejected(
            makeZip({
              'project.json': projectJson(),
              'media/a.mp4': bytes(10, 1),
              name: utf8.encode('evil'),
            }),
            message: 'outside');
      }
      // No "evil.txt" anywhere under the test folder or its parent.
      expect((await filesUnder(tmp.path)).where((f) => f.contains('evil')), isEmpty);
      expect(File(p.join(tmp.parent.path, 'evil.txt')).existsSync(), isFalse);
      expect(File(p.join(mediaDir, 'evil.txt')).existsSync(), isFalse);
    });

    test('missing project.json', () async {
      await expectRejected(makeZip({'media/a.mp4': bytes(10, 1)}),
          message: 'project.json');
      await expectRejected(
          makeZip({'sub/project.json': projectJson(), 'media/a.mp4': bytes(10, 1)}),
          message: 'project.json');
    });

    test('corrupt project.json', () async {
      for (final bad in [
        '{ not json',
        '[1, 2, 3]',
        '"text"',
        '{"id": "x"}',
        '{"id": 5, "createdAt": "2026-01-01", "updatedAt": "2026-01-01"}',
        '{"id": "x", "createdAt": "yesterday", "updatedAt": "today"}',
        '',
      ]) {
        ids = 0;
        await expectRejected(
            makeZip({'project.json': utf8.encode(bad), 'media/a.mp4': bytes(10, 1)}),
            message: 'project.json');
      }
      ids = 0;
      await expectRejected(
          makeZip({'project.json': [0xFF, 0xFE, 0x00, 0xC3], 'media/a.mp4': bytes(10, 1)}));
    });

    test('a bundle from a newer version of the app', () async {
      await expectRejected(
          makeZip({'project.json': projectJson(schemaVersion: kSchemaVersion + 1)}),
          message: 'newer version');
    });

    test('not a zip file at all', () async {
      Future<String> raw(List<int> data) async {
        final f = File(p.join(tmp.path, 'raw.zip'));
        await f.writeAsBytes(data);
        return f.path;
      }

      await expectRejected(raw(utf8.encode('this is not a zip file, just text ' * 20)));
      ids = 0;
      await expectRejected(raw(const []));
      ids = 0;
      // A real bundle cut in half.
      final good = await makeZip(
          {'project.json': projectJson(), 'media/a.mp4': bytes(5000, 1)},
          name: 'good.zip');
      final data = await File(good).readAsBytes();
      await expectRejected(raw(data.sublist(0, data.length ~/ 2)));
    });

    test('a bundle that does not exist', () async {
      await expectLater(
          importBundle(p.join(tmp.path, 'nope.zip'),
              store: store, mediaDir: mediaDir, newId: newId),
          throwsA(isA<FileSystemException>()));
      expect(ids, 0);
    });

    test('a failing store leaves no media behind', () async {
      final zip = await makeZip(
          {'project.json': projectJson(), 'media/a.mp4': bytes(10, 1)});
      // The store root is a file, so saving fails.
      final blocker = File(p.join(tmp.path, 'blocked'));
      await blocker.writeAsString('x');
      await expectLater(
          importBundle(zip,
              store: ProjectStore.atPath(blocker.path),
              mediaDir: mediaDir,
              newId: newId),
          throwsA(isA<FileSystemException>()));
      expect(await filesUnder(mediaDir), isEmpty);
    });

    test('an id that is not a folder name is refused', () async {
      final zip = await makeZip({'project.json': projectJson()});
      for (final bad in ['', '..', 'a/b', r'a\b']) {
        await expectLater(
            importBundle(zip, store: store, mediaDir: mediaDir, newId: () => bad),
            throwsArgumentError);
      }
    });
  });
}
