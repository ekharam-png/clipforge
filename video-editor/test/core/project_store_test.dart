import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  late Directory tmp;
  late String root;
  late ProjectStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipforge_store_test');
    root = p.join(tmp.path, 'nested', 'projects');
    store = ProjectStore.atPath(root);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File fileOf(String id) => File(p.join(root, id, 'project.json'));

  Future<void> writeRaw(String id, String text) async {
    await Directory(p.join(root, id)).create(recursive: true);
    await fileOf(id).writeAsString(text);
  }

  test('atPath gives a file store rooted there', () {
    expect(store, isA<FileProjectStore>());
    expect((store as FileProjectStore).rootPath, root);
  });

  test('list on a missing root is empty and does not create it', () async {
    expect(await store.list(), isEmpty);
    expect(await Directory(root).exists(), isFalse);
  });

  test('create writes <root>/<id>/project.json', () async {
    final before = DateTime.now();
    final created = await store.create('  My film ');
    expect(created.name, 'My film');
    expect(created.id, isNotEmpty);
    expect(created.clips, isEmpty);
    expect(created.createdAt, created.updatedAt);
    expect(created.createdAt.isBefore(before), isFalse);
    expect(await fileOf(created.id).exists(), isTrue);
    final json = jsonDecode(await fileOf(created.id).readAsString()) as Map;
    expect(json['schemaVersion'], kSchemaVersion);
    expect(json['id'], created.id);
    expect(json['name'], 'My film');
  });

  test('create gives unique ids and a default name', () async {
    final a = await store.create('');
    final b = await store.create('   ');
    expect(a.name, 'Untitled');
    // 1.11: no two projects with the same name.
    expect(b.name, 'Untitled (2)');
    expect((await store.create('untitled')).name, 'untitled (3)');
    expect(a.id, isNot(b.id));
    expect(await store.list(), hasLength(3));
    final copy = await store.duplicate(a.id);
    expect(copy.name, 'Untitled copy');
    expect((await store.duplicate(a.id)).name, 'Untitled copy (2)');
    expect((await store.duplicate(a.id, name: 'Untitled')).name, 'Untitled (4)');
  });

  test('save then load round-trips', () async {
    final original = project(
      id: 'abc',
      name: 'Round',
      aspect: CanvasAspect.portrait9x16,
      clips: [video('a', inMs: 100, outMs: 900), photo('b')],
      audio: [audio('m', startMs: 300, fadeInMs: 100)],
      titles: [title('t', text: 'Заголовок')],
      updatedAt: DateTime.utc(2026, 5, 5, 5, 5, 5, 5),
    );
    await store.save(original);
    final loaded = await store.load('abc');
    expect(jsonEncode(loaded.toJson()), jsonEncode(original.toJson()));
    expect(loaded.updatedAt, original.updatedAt);
  });

  test('save overwrites and leaves no temp files', () async {
    await store.save(project(id: 'abc', name: 'One'));
    await store.save(project(id: 'abc', name: 'Two'));
    expect((await store.load('abc')).name, 'Two');
    final names = [
      await for (final e in Directory(p.join(root, 'abc')).list()) p.basename(e.path),
    ];
    expect(names, ['project.json']);
  });

  test('overlapping saves of one project land in call order', () async {
    final saves = [
      for (var i = 0; i < 25; i++) store.save(project(id: 'abc', name: 'v$i')),
    ];
    await Future.wait(saves);
    expect((await store.load('abc')).name, 'v24');
    final names = [
      await for (final e in Directory(p.join(root, 'abc')).list()) p.basename(e.path),
    ];
    expect(names, ['project.json']);
  });

  test('a failed save reports the error and does not block later saves', () async {
    // A plain file where the project folder should be makes the write fail.
    await Directory(root).create(recursive: true);
    await File(p.join(root, 'abc')).writeAsString('in the way');
    await expectLater(store.save(project(id: 'abc')), throwsA(isA<FileSystemException>()));
    await File(p.join(root, 'abc')).delete();
    await store.save(project(id: 'abc', name: 'Fine'));
    expect((await store.load('abc')).name, 'Fine');
  });

  test('load of a missing project throws FileSystemException', () async {
    await expectLater(store.load('nope'), throwsA(isA<FileSystemException>()));
  });

  test('load of corrupt files throws FormatException', () async {
    await writeRaw('bad', '{"id": "bad", "name": ');
    await writeRaw('empty', '');
    await writeRaw('list', '[1, 2, 3]');
    await writeRaw('nofields', '{"schemaVersion": 1}');
    await writeRaw('baddate',
        '{"id": "baddate", "createdAt": "yesterday", "updatedAt": "today"}');
    await writeRaw('badclip', jsonEncode(project(id: 'badclip').toJson()..['clips'] = [42]));
    for (final id in ['bad', 'empty', 'list', 'nofields', 'baddate', 'badclip']) {
      await expectLater(store.load(id), throwsFormatException, reason: id);
    }
  });

  test('load rejects a newer schemaVersion with a clear message', () async {
    final json = project(id: 'future').toJson()..['schemaVersion'] = kSchemaVersion + 1;
    await writeRaw('future', jsonEncode(json));
    await expectLater(
      store.load('future'),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        allOf(contains('newer version'), contains('${kSchemaVersion + 1}')),
      )),
    );
  });

  test('load accepts the current, an older or a missing schemaVersion', () async {
    await writeRaw('same', jsonEncode(project(id: 'same').toJson()));
    await writeRaw('old', jsonEncode(project(id: 'old').toJson()..['schemaVersion'] = 0));
    await writeRaw('none', jsonEncode(project(id: 'none').toJson()..remove('schemaVersion')));
    expect((await store.load('same')).id, 'same');
    expect((await store.load('old')).id, 'old');
    expect((await store.load('none')).id, 'none');
  });

  test('list is newest first with summary fields', () async {
    await store.save(project(id: 'old', name: 'Old', updatedAt: DateTime.utc(2026, 1, 1)));
    await store.save(project(
      id: 'new',
      name: 'New',
      updatedAt: DateTime.utc(2026, 3, 1),
      clips: [video('a', outMs: 4000), photo('b', durationMs: 1000)],
    ));
    await store.save(project(id: 'mid', name: 'Mid', updatedAt: DateTime.utc(2026, 2, 1)));
    final list = await store.list();
    expect([for (final i in list) i.id], ['new', 'mid', 'old']);
    expect([for (final i in list) i.name], ['New', 'Mid', 'Old']);
    expect(list[0].updatedAt, DateTime.utc(2026, 3, 1));
    expect(list[0].durationMs, 5000);
    expect(list[0].thumbnailSourcePath, '/media/a.mp4');
    expect(list[2].durationMs, 0);
    expect(list[2].thumbnailSourcePath, isNull);
  });

  test('list reflects a re-save', () async {
    await store.save(project(id: 'a', updatedAt: DateTime.utc(2026, 1, 1)));
    await store.save(project(id: 'b', updatedAt: DateTime.utc(2026, 1, 2)));
    expect([for (final i in await store.list()) i.id], ['b', 'a']);
    await store.save(project(id: 'a', name: 'Edited', updatedAt: DateTime.utc(2026, 1, 3)));
    final list = await store.list();
    expect([for (final i in list) i.id], ['a', 'b']);
    expect(list.first.name, 'Edited');
  });

  test('list skips corrupt, empty, newer and stray entries', () async {
    await store.save(project(id: 'good', name: 'Good'));
    await writeRaw('corrupt', 'not json at all');
    await writeRaw('truncated', '{"id": "truncated"');
    await writeRaw('wrongshape', '{"id": 5}');
    await writeRaw('future',
        jsonEncode(project(id: 'future').toJson()..['schemaVersion'] = kSchemaVersion + 5));
    await Directory(p.join(root, 'emptydir')).create();
    await Directory(p.join(root, 'dirasfile', 'project.json')).create(recursive: true);
    await File(p.join(root, 'stray.txt')).writeAsString('hello');
    await File(p.join(root, 'project.json')).writeAsString('{}');
    final list = await store.list();
    expect([for (final i in list) i.id], ['good']);
  });

  test('list uses the folder name as the id', () async {
    await writeRaw('folder', jsonEncode(project(id: 'inner', name: 'Copied').toJson()));
    final info = (await store.list()).single;
    expect(info.id, 'folder');
    expect((await store.load(info.id)).name, 'Copied');
  });

  test('delete removes the folder; missing ids are fine', () async {
    await store.save(project(id: 'a'));
    await store.save(project(id: 'b'));
    await File(p.join(root, 'a', 'extra.bin')).writeAsBytes([1, 2, 3]);
    await store.delete('a');
    expect(await Directory(p.join(root, 'a')).exists(), isFalse);
    expect([for (final i in await store.list()) i.id], ['b']);
    await expectLater(store.load('a'), throwsA(isA<FileSystemException>()));
    await store.delete('a');
    await store.delete('never-existed');
  });

  test('delete right after save does not leave the project behind', () async {
    final pending = store.save(project(id: 'a'));
    await store.delete('a');
    await pending;
    expect(await store.list(), isEmpty);
  });

  test('ids that would escape the root are rejected', () async {
    await Directory(root).create(recursive: true);
    for (final id in ['', '.', '..', '../x', 'a/b', r'a\b']) {
      expect(() => store.load(id), throwsArgumentError, reason: '"$id"');
      expect(() => store.delete(id), throwsArgumentError, reason: '"$id"');
      expect(() => store.save(project(id: id)), throwsArgumentError, reason: '"$id"');
    }
    expect(await Directory(root).exists(), isTrue);
  });

  test('two stores on the same root see each other', () async {
    final other = ProjectStore.atPath(root);
    final created = await store.create('Shared');
    expect((await other.load(created.id)).name, 'Shared');
    await other.delete(created.id);
    expect(await store.list(), isEmpty);
  });

  group('duplicate', () {
    test('copies the content under a new id with a default name', () async {
      final original = project(
        id: 'orig',
        name: 'Trip',
        clips: [video('a', speed: 2, transition: TransitionType.crossfade), photo('b')],
        audio: [audio('m')],
        titles: [title('t').copyWith(kind: TitleKind.caption)],
        aspect: CanvasAspect.square1x1,
      ).copyWith(duckMusic: true);
      await store.save(original);
      final before = DateTime.now();

      final copy = await store.duplicate('orig');

      expect(copy.id, isNot('orig'));
      expect(copy.id, isNotEmpty);
      expect(copy.name, 'Trip copy');
      expect(copy.createdAt.isBefore(before), isFalse);
      expect(copy.updatedAt, copy.createdAt);
      Map<String, dynamic> body(Project q) => q.toJson()
        ..remove('id')
        ..remove('name')
        ..remove('createdAt')
        ..remove('updatedAt');
      expect(jsonEncode(body(copy)), jsonEncode(body(original)));
      // Both are on disk and independent.
      expect(content(await store.load(copy.id)), content(copy));
      expect(content(await store.load('orig')), content(original));
      expect((await store.list()).map((i) => i.name).toList(), ['Trip copy', 'Trip']);
      await store.delete('orig');
      expect((await store.load(copy.id)).clips.length, 2);
    });

    test('takes a name; a blank name falls back to the default', () async {
      await store.save(project(id: 'orig', name: 'Trip'));
      expect((await store.duplicate('orig', name: '  Second cut ')).name, 'Second cut');
      expect((await store.duplicate('orig', name: '   ')).name, 'Trip copy');
      final again = await store.duplicate((await store.duplicate('orig')).id);
      // 1.11: the second copy of "Trip" is "Trip copy (2)"; its copy:
      expect(again.name, 'Trip copy (2) copy');
      expect((await store.list()).map((i) => i.id).toSet().length, 5);
    });

    test('fails like load for missing or corrupt projects', () async {
      await expectLater(store.duplicate('nope'), throwsA(isA<FileSystemException>()));
      await writeRaw('bad', '{ nope');
      await expectLater(store.duplicate('bad'), throwsFormatException);
      await expectLater(store.duplicate('../x'), throwsArgumentError);
      expect((await store.list()), isEmpty);
    });
  });
}
