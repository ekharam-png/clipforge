// fake_async ships with flutter_test; pubspec.yaml is owned by another part
// of the project, so it is used without a direct dev dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:clipforge/core/editor/autosave.dart';
import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

class FakeStore implements ProjectStore {
  final List<Project> saved = [];
  int started = 0;
  int running = 0;
  int maxRunning = 0;

  /// How long a save takes.
  Duration delay = Duration.zero;

  /// Thrown (asynchronously) by the next saves while set.
  Object? failWith;

  /// Thrown synchronously from save() while set.
  Object? throwSync;

  @override
  Future<void> save(Project project) {
    started++;
    if (throwSync != null) throw throwSync!;
    return _save(project);
  }

  Future<void> _save(Project project) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      await Future<void>.delayed(delay);
      if (failWith != null) throw failWith!;
      saved.add(project);
    } finally {
      running--;
    }
  }

  @override
  Future<Project> create(String name) => throw UnimplementedError();
  @override
  Future<void> delete(String id) => throw UnimplementedError();
  @override
  Future<Project> duplicate(String id, {String? name}) =>
      throw UnimplementedError();
  @override
  Future<List<ProjectInfo>> list() => throw UnimplementedError();
  @override
  Future<Project> load(String id) => throw UnimplementedError();
}

const ms = Duration(milliseconds: 1);

void main() {
  late EditorController c;
  late FakeStore store;

  setUp(() {
    c = EditorController(project());
    store = FakeStore();
  });

  test('saves once, 800ms after the last edit', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      expect(saver.debounce, const Duration(milliseconds: 800));
      expect(saver.hasPendingChanges, isFalse);
      c.rename('A');
      expect(saver.hasPendingChanges, isTrue);
      async.elapse(ms * 799);
      expect(store.started, 0);
      async.elapse(ms * 1);
      expect(store.saved.single.name, 'A');
      expect(saver.hasPendingChanges, isFalse);
      expect(saver.lastError, isNull);
      async.elapse(const Duration(minutes: 1));
      expect(store.started, 1);
      saver.dispose();
    });
  });

  test('nothing is saved without edits', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      async.elapse(const Duration(seconds: 10));
      async.run((_) => saver.flush());
      async.flushMicrotasks();
      expect(store.started, 0);
      saver.dispose();
      async.flushMicrotasks();
      expect(store.started, 0);
    });
  });

  test('each edit restarts the debounce', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      for (var i = 0; i < 10; i++) {
        c.rename('n$i');
        async.elapse(ms * 500);
      }
      expect(store.started, 0);
      async.elapse(ms * 300);
      expect(store.saved.single.name, 'n9');
      saver.dispose();
    });
  });

  test('custom debounce', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store, debounce: ms * 50);
      c.rename('A');
      async.elapse(ms * 49);
      expect(store.started, 0);
      async.elapse(ms);
      expect(store.started, 1);
      saver.dispose();
    });
  });

  test('saves the state reached through undo/redo and transactions', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.transaction(() {
        c.addClip(video('a'));
        c.trimClip('a', inMs: 500);
        c.trimClip('a', inMs: 900);
      });
      async.elapse(ms * 800);
      // (The added file itself was written at once, see below.)
      expect(store.saved.last.clips.single.inMs, 900);
      final before = store.saved.length;
      c.undo();
      async.elapse(ms * 800);
      expect(store.saved, hasLength(before + 1));
      expect(store.saved.last.clips, isEmpty);
      saver.dispose();
    });
  });

  test('1.17: a file that was added is saved at once, not after the quiet '
      'time', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.addClip(video('a'));
      // No time passes: only the save itself runs.
      async.elapse(Duration.zero);
      expect(store.saved, hasLength(1));
      expect(store.saved.single.clips.single.id, 'a');
      expect(saver.hasPendingChanges, isFalse);
      // An edit of what is already there waits as before.
      c.trimClip('a', inMs: 500);
      async.elapse(Duration.zero);
      expect(store.saved, hasLength(1));
      async.elapse(ms * 800);
      expect(store.saved, hasLength(2));
      // Splitting makes more clips but adds no file: no immediate save.
      expect(c.splitAt(2000), isTrue);
      async.elapse(Duration.zero);
      expect(store.saved, hasLength(2));
      async.elapse(ms * 800);
      expect(store.saved, hasLength(3));
      saver.dispose();
    });
  });

  test('a transaction that changes nothing saves nothing', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.transaction(() {
        c.setDuckMusic(true);
        c.setDuckMusic(false);
      });
      expect(saver.hasPendingChanges, isFalse);
      async.elapse(const Duration(seconds: 5));
      expect(store.started, 0);
      saver.dispose();
    });
  });

  test('flush saves immediately and cancels the timer', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.rename('A');
      var done = false;
      saver.flush().then((_) => done = true);
      async.elapse(Duration.zero);
      expect(done, isTrue);
      expect(store.saved.single.name, 'A');
      async.elapse(const Duration(seconds: 5));
      expect(store.started, 1);
      saver.dispose();
    });
  });

  test('flush waits for a save that is already running', () {
    fakeAsync((async) {
      store.delay = ms * 300;
      final saver = Autosaver(c, store);
      c.rename('A');
      async.elapse(ms * 800);
      expect(saver.isSaving, isTrue);
      var done = false;
      saver.flush().then((_) => done = true);
      async.elapse(ms * 299);
      expect(done, isFalse);
      async.elapse(ms);
      expect(done, isTrue);
      expect(saver.isSaving, isFalse);
      expect(store.started, 1);
      saver.dispose();
    });
  });

  test('saves never overlap; a change during a save is written after it', () {
    fakeAsync((async) {
      store.delay = ms * 2000;
      final saver = Autosaver(c, store);
      c.rename('A');
      async.elapse(ms * 800); // save of A starts
      c.rename('B');
      async.elapse(ms * 800); // debounce fires while A is still being written
      expect(store.started, 1);
      c.rename('C');
      async.elapse(ms * 1200); // A done at 2800ms; latest state follows directly
      expect(store.saved.single.name, 'A');
      expect(store.started, 2);
      async.elapse(ms * 2000);
      expect([for (final s in store.saved) s.name], ['A', 'C']);
      async.elapse(const Duration(seconds: 10));
      expect(store.started, 2);
      expect(store.maxRunning, 1);
      expect(saver.hasPendingChanges, isFalse);
      saver.dispose();
    });
  });

  test('flush during a save also writes the newer state', () {
    fakeAsync((async) {
      store.delay = ms * 1000;
      final saver = Autosaver(c, store);
      c.rename('A');
      async.elapse(ms * 800);
      c.rename('B');
      var done = false;
      saver.flush().then((_) => done = true);
      async.elapse(ms * 1000);
      expect(done, isFalse);
      async.elapse(ms * 1000);
      expect(done, isTrue);
      expect([for (final s in store.saved) s.name], ['A', 'B']);
      expect(store.maxRunning, 1);
      saver.dispose();
    });
  });

  test('save errors stay out of the listener and land in lastError', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      store.failWith = const FileSystemException('disk full');
      c.rename('A'); // must not throw
      async.elapse(ms * 800);
      expect(saver.lastError, isA<FileSystemException>());
      expect(saver.hasPendingChanges, isTrue);
      expect(store.started, 1);
      // No retry loop on its own.
      async.elapse(const Duration(seconds: 30));
      expect(store.started, 1);
      // The next edit retries, and success clears the error.
      store.failWith = null;
      c.rename('B');
      async.elapse(ms * 800);
      expect(saver.lastError, isNull);
      expect(store.saved.single.name, 'B');
      expect(saver.hasPendingChanges, isFalse);
      saver.dispose();
    });
  });

  test('a store that throws synchronously is handled too', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      store.throwSync = StateError('closed');
      c.rename('A');
      async.elapse(ms * 800);
      expect(saver.lastError, isStateError);
      store.throwSync = null;
      async.run((_) => saver.flush());
      async.elapse(Duration.zero);
      expect(saver.lastError, isNull);
      expect(store.saved.single.name, 'A');
      saver.dispose();
    });
  });

  test('flush does not throw on failure and can retry later', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      store.failWith = Exception('nope');
      c.rename('A');
      Object? thrown;
      var done = false;
      saver.flush().then((_) {
        done = true;
      }, onError: (Object e) {
        thrown = e;
      });
      async.elapse(Duration.zero);
      expect(done, isTrue);
      expect(thrown, isNull);
      expect(saver.lastError, isException);
      store.failWith = null;
      saver.flush();
      async.elapse(Duration.zero);
      expect(saver.lastError, isNull);
      expect(store.saved.single.name, 'A');
      saver.dispose();
    });
  });

  test('dispose stops listening', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      saver.dispose();
      saver.dispose(); // twice is fine
      c.rename('A');
      async.elapse(const Duration(seconds: 5));
      expect(store.started, 0);
    });
  });

  test('dispose writes a change that was still waiting', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.rename('A');
      async.elapse(ms * 100);
      saver.dispose();
      async.elapse(Duration.zero);
      expect(store.saved.single.name, 'A');
      async.elapse(const Duration(seconds: 5));
      expect(store.started, 1);
    });
  });

  test('dispose with a failing store does not throw', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      store.failWith = Exception('nope');
      c.rename('A');
      saver.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(saver.lastError, isException);
    });
  });

  test('works after the controller itself is disposed', () {
    fakeAsync((async) {
      final saver = Autosaver(c, store);
      c.rename('A');
      saver.dispose();
      c.dispose();
      async.elapse(Duration.zero);
      expect(store.saved.single.name, 'A');
    });
  });

  test('end to end with the file store', () async {
    final tmp = await Directory.systemTemp.createTemp('clipforge_autosave_test');
    addTearDown(() => tmp.delete(recursive: true));
    final files = ProjectStore.atPath(p.join(tmp.path, 'projects'));
    final created = await files.create('Film');
    final controller = EditorController(created);
    final saver = Autosaver(controller, files, debounce: const Duration(milliseconds: 20));
    controller.addClip(video('a'));
    controller.rename('Film 2');
    await saver.flush();
    expect(saver.lastError, isNull);
    final loaded = await files.load(created.id);
    expect(loaded.name, 'Film 2');
    expect(loaded.clips.single.id, 'a');
    expect(content(loaded), content(controller.project));
    saver.dispose();
  });
}
