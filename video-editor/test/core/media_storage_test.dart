// Missing media, clean-up of app-owned media, and the bundle additions.
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/media_check.dart';
import 'package:clipforge/core/storage/media_cleanup.dart';
import 'package:clipforge/core/storage/project_bundle.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

/// A store whose list or load can be made to fail.
class FlakyStore implements ProjectStore {
  FlakyStore(this.inner);
  final ProjectStore inner;
  bool failList = false;
  String? failLoad;

  @override
  Future<List<ProjectInfo>> list() async {
    if (failList) throw const FileSystemException('cannot list');
    return inner.list();
  }

  @override
  Future<Project> load(String id) async {
    if (id == failLoad) throw const FormatException('cannot load');
    return inner.load(id);
  }

  @override
  Future<Project> create(String name) => inner.create(name);
  @override
  Future<void> save(Project project) => inner.save(project);
  @override
  Future<Project> duplicate(String id, {String? name}) =>
      inner.duplicate(id, name: name);
  @override
  Future<void> delete(String id) => inner.delete(id);
}

void main() {
  late Directory tmp;
  late FileProjectStore store;
  late String mediaDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipforge_media_test');
    store = FileProjectStore(p.join(tmp.path, 'projects'));
    mediaDir = p.join(tmp.path, 'media');
    await Directory(mediaDir).create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  final old = DateTime.now().subtract(const Duration(hours: 2));

  /// Writes a file of [size] bytes; old enough to be cleaned unless [fresh].
  Future<String> file(String relative, int size, {bool fresh = false}) async {
    final f = File(p.join(tmp.path, relative));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List<int>.filled(size, 7));
    if (!fresh) await f.setLastModified(old);
    return f.path;
  }

  Clip clipAt(String id, String path) => Clip(
        id: id,
        type: ClipType.video,
        path: path,
        sourceDurationMs: 10000,
        inMs: 0,
        outMs: 10000,
        width: 1920,
        height: 1080,
      );

  AudioClip audioAt(String id, String path) => AudioClip(
      id: id, path: path, sourceDurationMs: 30000, startMs: 0, inMs: 0, outMs: 30000);

  group('findMissingMedia', () {
    test('lists each missing path once, clips before audio', () async {
      final here = await file('media/here.mp4', 10);
      final song = await file('media/song.mp3', 10);
      final project0 = project(clips: [
        clipAt('a', here),
        clipAt('b', '/nowhere/b.mp4'),
        clipAt('c', '/nowhere/b.mp4'),
        clipAt('d', ''),
      ], audio: [
        audioAt('m', song),
        audioAt('n', '/nowhere/n.mp3'),
        audioAt('o', '/nowhere/b.mp4'),
      ]);
      expect(await findMissingMedia(project0),
          ['/nowhere/b.mp4', '', '/nowhere/n.mp3']);
    });

    test('nothing missing, and an empty project', () async {
      final here = await file('media/here.mp4', 10);
      expect(await findMissingMedia(project(clips: [clipAt('a', here)])), isEmpty);
      expect(await findMissingMedia(project()), isEmpty);
    });

    test('a folder is not a media file', () async {
      expect(await findMissingMedia(project(clips: [clipAt('a', mediaDir)])),
          [mediaDir]);
    });
  });

  group('removeUnreferencedMedia', () {
    test('deletes what no project uses, with empty folders, and counts bytes', () async {
      final used = await file('media/p1/used.mp4', 100);
      final music = await file('media/music/song.mp3', 50);
      final unused = await file('media/p1/unused.mp4', 300);
      final orphan = await file('media/gone/deep/orphan.mp4', 4000);
      final outside = await file('elsewhere/keep.mp4', 20);
      await store.save(project(id: 'one', clips: [clipAt('a', used)]));
      await store.save(project(
          id: 'two',
          clips: [clipAt('a', outside)],
          audio: [audioAt('m', music)]));

      // The folders were only just made, and recently changed folders are
      // left alone, so look from a little later.
      expect(
          await removeUnreferencedMedia(mediaDir, store,
              now: () => DateTime.now().add(const Duration(minutes: 11))),
          4300);
      expect(File(used).existsSync(), isTrue);
      expect(File(music).existsSync(), isTrue);
      expect(File(outside).existsSync(), isTrue);
      expect(File(unused).existsSync(), isFalse);
      expect(File(orphan).existsSync(), isFalse);
      expect(Directory(p.join(mediaDir, 'gone')).existsSync(), isFalse);
      expect(Directory(p.join(mediaDir, 'p1')).existsSync(), isTrue);
      expect(Directory(mediaDir).existsSync(), isTrue);
      // A second run has nothing to do.
      expect(await removeUnreferencedMedia(mediaDir, store), 0);
    });

    test('never touches anything outside mediaDir', () async {
      final outside = await file('elsewhere/unused.mp4', 20);
      final sibling = await file('media2/unused.mp4', 20);
      final project0 = await file('projects/stray.bin', 20);
      await file('media/unused.mp4', 5);
      expect(await removeUnreferencedMedia(mediaDir, store), 5);
      expect(File(outside).existsSync(), isTrue);
      expect(File(sibling).existsSync(), isTrue);
      expect(File(project0).existsSync(), isTrue);
      // Also when mediaDir is given with a trailing ".." detour.
      await file('media/again.mp4', 6);
      expect(
          await removeUnreferencedMedia(
              p.join(tmp.path, 'elsewhere', '..', 'media'), store),
          6);
      expect(File(outside).existsSync(), isTrue);
    });

    test('does not follow links out of mediaDir', () async {
      final outside = await file('elsewhere/precious.mp4', 20);
      await file('elsewhere/dir/inner.mp4', 20);
      await Link(p.join(mediaDir, 'file-link.mp4')).create(outside);
      await Link(p.join(mediaDir, 'dir-link'))
          .create(p.join(tmp.path, 'elsewhere', 'dir'));
      await removeUnreferencedMedia(mediaDir, store,
          now: () => DateTime.now().add(const Duration(hours: 1)));
      expect(File(outside).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'elsewhere', 'dir', 'inner.mp4')).existsSync(),
          isTrue);
    }, skip: Platform.isWindows);

    test('files changed in the last 10 minutes are kept', () async {
      final importing = await file('media/new/importing.mp4', 100, fresh: true);
      final stale = await file('media/stale.mp4', 10);
      final edge = File(await file('media/edge.mp4', 1));
      await edge.setLastModified(
          DateTime.now().subtract(const Duration(minutes: 9)));
      expect(await removeUnreferencedMedia(mediaDir, store), 10);
      expect(File(importing).existsSync(), isTrue);
      expect(edge.existsSync(), isTrue);
      expect(File(stale).existsSync(), isFalse);
      // Later they are fair game.
      expect(
          await removeUnreferencedMedia(mediaDir, store,
              now: () => DateTime.now().add(const Duration(minutes: 11))),
          101);
      expect(Directory(p.join(mediaDir, 'new')).existsSync(), isFalse);
    });

    test('an unreadable project stops the whole clean-up', () async {
      final a = await file('media/a.mp4', 100);
      final unused = await file('media/unused.mp4', 100);
      await store.save(project(id: 'good', clips: [clipAt('a', a)]));

      // Corrupt.
      final bad = File(p.join(store.rootPath, 'bad', 'project.json'));
      await bad.parent.create(recursive: true);
      await bad.writeAsString('{ not json');
      expect(await store.list(), hasLength(1), reason: 'list() hides it');
      expect(await removeUnreferencedMedia(mediaDir, store), 0);
      expect(File(unused).existsSync(), isTrue);

      // Written by a newer version of the app.
      await bad.writeAsString('{"schemaVersion": 999}');
      expect(await removeUnreferencedMedia(mediaDir, store), 0);

      // Half written: a folder with only a temp file.
      await bad.delete();
      await File(p.join(bad.parent.path, 'project.json.1_0.tmp')).writeAsString('{');
      expect(await removeUnreferencedMedia(mediaDir, store), 0);
      expect(File(unused).existsSync(), isTrue);

      // Once the project is readable again (here: gone) it works. An empty
      // folder does not count as a project.
      await bad.parent.delete(recursive: true);
      await Directory(p.join(store.rootPath, 'empty')).create();
      expect(await removeUnreferencedMedia(mediaDir, store), 100);
      expect(File(a).existsSync(), isTrue);
    });

    test('a store that fails to list or load stops it too', () async {
      final unused = await file('media/unused.mp4', 100);
      await store.save(project(id: 'good'));
      final flaky = FlakyStore(store)..failList = true;
      expect(await removeUnreferencedMedia(mediaDir, flaky), 0);
      flaky
        ..failList = false
        ..failLoad = 'good';
      expect(await removeUnreferencedMedia(mediaDir, flaky), 0);
      expect(File(unused).existsSync(), isTrue);
      flaky.failLoad = null;
      expect(await removeUnreferencedMedia(mediaDir, flaky), 100);
    });

    test('paths are compared normalised; a moved container still protects', () async {
      final a = await file('media/x/a.mp4', 10);
      final b = await file('media/x/b.mp4', 10);
      final c = await file('media/x/c.mp4', 10);
      await store.save(project(id: 'one', clips: [
        clipAt('a', p.join(tmp.path, 'media', 'x', '..', 'x', 'a.mp4')),
        // The same app folder seen under another container path.
        clipAt('b', '/var/mobile/OLD-CONTAINER/Documents/ClipForge/media/x/b.mp4'),
      ]));
      expect(await removeUnreferencedMedia(mediaDir, store), 10);
      expect(File(a).existsSync(), isTrue);
      expect(File(b).existsSync(), isTrue);
      expect(File(c).existsSync(), isFalse);
    });

    test('no projects at all: everything old goes; a missing mediaDir is 0', () async {
      await file('media/a.mp4', 10);
      expect(await removeUnreferencedMedia(mediaDir, store), 10);
      expect(await removeUnreferencedMedia(p.join(tmp.path, 'no-such'), store), 0);
    });
  });

  group('bundles', () {
    test('exportBundle reports the media it had to skip', () async {
      final here = await file('device/here.mp4', 100);
      final project0 = project(clips: [
        clipAt('a', here),
        clipAt('b', '/nowhere/b.mp4'),
        clipAt('c', '/nowhere/b.mp4'),
      ], audio: [
        audioAt('m', '/nowhere/m.mp3'),
      ]);
      List<String>? skipped;
      await exportBundle(project0, p.join(tmp.path, 'a.zip'),
          onSkipped: (paths) => skipped = paths);
      expect(skipped, ['/nowhere/b.mp4', '/nowhere/m.mp3']);
      expect(await exportBundleReport(project0, p.join(tmp.path, 'b.zip')),
          ['/nowhere/b.mp4', '/nowhere/m.mp3']);
      expect(File(p.join(tmp.path, 'b.zip')).existsSync(), isTrue);

      // Complete bundle: called with an empty list. The old call still works.
      final complete = project(clips: [clipAt('a', here)]);
      skipped = null;
      await exportBundle(complete, p.join(tmp.path, 'c.zip'),
          onSkipped: (paths) => skipped = paths);
      expect(skipped, isEmpty);
      await exportBundle(complete, p.join(tmp.path, 'd.zip'));
      expect(await exportBundleReport(complete, p.join(tmp.path, 'e.zip')), isEmpty);
    });

    test('importBundle renames when the name is taken', () async {
      final here = await file('device/here.mp4', 100);
      final zip = p.join(tmp.path, 'trip.zip');
      await exportBundle(project(name: 'Trip', clips: [clipAt('a', here)]), zip);
      var n = 0;
      Future<Project> import() => importBundle(zip,
          store: store, mediaDir: mediaDir, newId: () => 'imp${++n}');

      expect((await import()).name, 'Trip');
      expect((await import()).name, 'Trip (imported)');
      expect((await import()).name, 'Trip (imported 2)');
      expect((await import()).name, 'Trip (imported 3)');
      expect((await store.load('imp3')).name, 'Trip (imported 2)');
      expect({for (final i in await store.list()) i.name}, hasLength(4));

      // A free name is kept again.
      await store.delete('imp1');
      expect((await import()).name, 'Trip');
    });
  });
}
