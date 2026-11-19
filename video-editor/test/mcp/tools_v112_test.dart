// Claude control in 1.12: answers say what changed as old -> new for a
// single item, a dry run lists which settings would change, get_status
// names the helper, the self-test runs the real handlers in a temporary
// folder, and the worker start command for Windows is what it should be.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/mcp/export_jobs.dart';
import 'package:clipforge/mcp/report.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  setUp(() {
    b = Bench(ffmpeg: false);
    c = b.client;
    c.fullDetail = false;
  });
  tearDown(() => b.dispose());

  Map fieldsOf(Reply r, String kind) =>
      (((r.data['changes'] as Map)[kind] as Map)['fields'] as Map?) ?? const {};

  group('old -> new', () {
    test('one clip: every changed setting with its old and new value', () async {
      await b.seed('p1', clips: [b.video('a'), b.video('b', file: 'b.mp4')]);
      final r = await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'a', 'speed': 2, 'volume': 0.5});
      final fields = (fieldsOf(r, 'clips')['a'] as Map).cast<String, dynamic>();
      expect(fields['speed'], {'from': 1.0, 'to': 2.0});
      expect(fields['volume'], {'from': 1.0, 'to': 0.5});
      expect(fields.keys, unorderedEquals(['speed', 'volume']),
          reason: 'only what changed');
      expect(r.text, contains('clip a: '));
      expect(r.text, contains('speed 1.0 -> 2.0'));
      expect(r.text, contains('volume 1.0 -> 0.5'));
      expect(r.text, contains('What changed: '));
    });

    test('a title and a sound item get the same', () async {
      await b.seed('p1', clips: [
        b.video('a')
      ], titles: [
        TitleOverlay(id: 't', text: 'Old', startMs: 0, endMs: 2000),
      ], audio: [
        AudioClip(id: 'm', path: b.touch('song.mp3'), sourceDurationMs: 30000, startMs: 0, inMs: 0, outMs: 8000),
      ]);
      final t = await c.ok('update_title', {'project_id': 'p1', 'title_id': 't', 'text': 'New'});
      expect((fieldsOf(t, 'titles')['t'] as Map)['text'], {'from': 'Old', 'to': 'New'});
      expect(t.text, contains('title/caption t: text "Old" -> "New"'));
      final m = await c.ok('update_audio', {'project_id': 'p1', 'audio_id': 'm', 'volume': 0.3});
      expect((fieldsOf(m, 'audio')['m'] as Map)['volume'], {'from': 1.0, 'to': 0.3});
    });

    test('project settings say old -> new too', () async {
      await b.seed('p1', clips: [b.video('a')]);
      final r = await c.ok('set_project_settings', {'project_id': 'p1', 'aspect': '9:16'});
      final fromTo = ((r.data['changes'] as Map)['settingsFromTo'] as Map).cast<String, dynamic>();
      expect(fromTo.keys, ['aspect']);
      expect((fromTo['aspect'] as Map)['from'], isNot((fromTo['aspect'] as Map)['to']));
      expect(r.text, contains('project settings: aspect '));
    });

    test('many items: which settings changed on how many, not a wall of values', () async {
      await b.seed('p1', clips: [for (var i = 0; i < 8; i++) b.video('c$i', file: 'f$i.mp4')]);
      final r = await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'all', 'brightness': 0.2});
      final clips = ((r.data['changes'] as Map)['clips'] as Map);
      expect(clips.containsKey('fields'), isFalse);
      expect(clips['fieldsChanged'], {
        'brightness': {'items': 8, 'to': 0.2},
      });
      expect(r.text, contains('settings that change on the clips: brightness -> 0.2 (8)'));
      expect(r.text.length + jsonEncode(r.data).length, lessThan(3000), reason: 'still short');
    });

    test('fieldChanges: the top-level differences of two objects', () {
      expect(fieldChanges({'a': 1, 'b': [1, 2], 'c': 'x'}, {'a': 2, 'b': [1, 2], 'd': true}), {
        'a': {'from': 1, 'to': 2},
        'c': {'from': 'x', 'to': null},
        'd': {'from': null, 'to': true},
      });
      expect(fieldChangesText({
        'c': {'from': 'x', 'to': null},
      }), 'c "x" -> not set');
    });
  });

  group('dry runs list the settings', () {
    test('apply_to_all and copy_clip_settings say which settings would change', () async {
      await b.seed('p1', clips: [
        b.video('a'),
        for (var i = 0; i < 5; i++) b.video('c$i', file: 'f$i.mp4'),
      ]);
      await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'a', 'brightness': 0.3, 'contrast': 1.2, 'volume': 0.6});
      final before = b.projectFile('p1').readAsStringSync();

      final all = await c.ok('apply_to_all', {'project_id': 'p1', 'clip_id': 'a', 'look': true, 'dry_run': true});
      expect(all.text, startsWith('DRY RUN'));
      expect(all.text, contains('What would change: '));
      final changed = (((all.data['changes'] as Map)['clips'] as Map)['fieldsChanged'] as Map)
          .cast<String, dynamic>();
      expect(changed.keys, containsAll(['brightness', 'contrast']));
      expect(changed['brightness'], {'items': 5, 'to': 0.3});
      expect(all.text, contains('brightness -> 0.3 (5)'));

      final one = await c.ok('copy_clip_settings',
          {'project_id': 'p1', 'from_clip_id': 'a', 'to_clip_ids': ['c0'], 'dry_run': true});
      final fields = (fieldsOf(one, 'clips')['c0'] as Map).cast<String, dynamic>();
      expect(fields['brightness'], {'from': 0.0, 'to': 0.3});
      expect(one.text, contains('clip c0: '));
      expect(b.projectFile('p1').readAsStringSync(), before, reason: 'nothing was saved');
    });
  });

  test('get_status names the helper that is running, and where the app puts it', () async {
    final r = await c.ok('get_status');
    final helper = (r.data['helper'] as Map).cast<String, dynamic>();
    expect(helper['program'], Platform.resolvedExecutable);
    expect(helper.containsKey('stableFolder'), isTrue);
    expect(helper.containsKey('installedByApp'), isTrue);
    expect(r.text, contains('Helper: ${Platform.resolvedExecutable}'));
    expect(r.text, contains('Helper folder: '));
    // Said only for the shipped server, whose exports run in their own process.
    expect(r.text.contains('keeps going when Claude or this helper closes'),
        b.tools.exportLauncher.survivesServer);
  });

  group('self_test', () {
    test('without FFmpeg: says so in the table, still checks what it can, cleans up', () async {
      final r = await c.ok('self_test');
      expect(r.text, startsWith('ClipForge self-test: FAIL'));
      final checks = (r.data['checks'] as List).cast<Map>();
      Map row(String name) => checks.firstWhere((x) => x['name'] == name);
      expect(row('Sample media (FFmpeg)')['result'], 'FAIL');
      expect(row('Sample media (FFmpeg)')['note'], contains('FFmpeg was not found'));
      expect(row('Create a project')['result'], 'PASS');
      expect(row('Titles (Latin, Cyrillic, Hebrew)')['result'], 'PASS');
      expect(row('Undo / redo')['result'], 'PASS');
      expect(row('Refuses while open in the app')['result'], 'PASS');
      expect(row('Export as a background job')['result'], 'SKIPPED');
      expect(row('Clean up')['result'], 'PASS');
      expect(r.data['ok'], isFalse);
      expect(await b.store.list(), isEmpty, reason: 'the user\'s projects folder is not used');
    });

    test('with FFmpeg: everything passes, with progress, in a temporary folder', () async {
      final real = Bench();
      addTearDown(real.dispose);
      final before = Directory.systemTemp
          .listSync()
          .where((e) => p.basename(e.path).startsWith('clipforge-selftest-'))
          .length;
      final r = await real.client.call('self_test', const {}, 'tok');
      expect(r.text, startsWith('ClipForge self-test: PASS'), reason: r.text);
      final checks = (r.data['checks'] as List).cast<Map>();
      expect(checks, hasLength(15));
      expect(checks.where((x) => x['result'] == 'FAIL'), isEmpty);
      expect(checks.where((x) => x['result'] == 'SKIPPED').map((x) => x['name']),
          everyElement('Speech to text'));
      expect(r.text, contains(' #  Check'));
      expect(r.text, contains('Result'));
      expect(r.text, contains('were not touched'));
      expect((r.data['seconds'] as num) < 60, isTrue);
      final progress = real.client.notifications
          .where((n) => n['method'] == 'notifications/progress')
          .map((n) => (n['params'] as Map)['message'])
          .toList();
      expect(progress.first, 'Self-test: Sample media (FFmpeg)');
      expect(progress, contains('Self-test: Export as a background job'));
      expect(progress.last, 'Self-test: done');
      expect(await real.store.list(), isEmpty);
      expect(
          Directory.systemTemp
              .listSync()
              .where((e) => p.basename(e.path).startsWith('clipforge-selftest-'))
              .length,
          before,
          reason: 'the temporary folder is gone');
    }, skip: skipWithoutFfmpeg, timeout: const Timeout(Duration(minutes: 3)));
  });

  test('self_test quick (the app\'s Test button, 1.14): the slow checks are '
      'left out and said so', () async {
    final real = Bench();
    addTearDown(real.dispose);
    final r = await real.client.ok('self_test', {'quick': true});
    expect(r.text, startsWith('ClipForge self-test: PASS'), reason: r.text);
    final checks = (r.data['checks'] as List).cast<Map>();
    Map row(String name) => checks.firstWhere((x) => x['name'] == name);
    expect(row('Export as a background job')['result'], 'SKIPPED');
    expect(row('Export as a background job')['note'], 'not part of the quick test');
    expect(row('Speech to text')['result'], 'SKIPPED');
    expect(row('Remove silences')['result'], 'PASS');
    expect(checks.where((x) => x['result'] == 'FAIL'), isEmpty);
  }, skip: skipWithoutFfmpeg, timeout: const Timeout(Duration(minutes: 2)));

  group('Windows: the worker is started outside the helper\'s process tree', () {
    test('the PowerShell command hides the window, reports the pid and needs no quoting', () {
      const s = kWindowsWorkerStartScript;
      expect(s, contains('Start-Process'));
      expect(s, contains('-WindowStyle Hidden'));
      expect(s, contains('-PassThru'));
      expect(s, contains(r'$p.Id'));
      for (final name in ['CF_WORKER_EXE', 'CF_WORKER_DIR', 'CF_WORKER_ARGC', 'CF_WORKER_ARG']) {
        expect(s, contains(name));
      }
      expect(s.contains('"'), isFalse,
          reason: 'no double quotes: the command survives being passed as one argument');
      expect(s.contains('\n'), isFalse);
    });

    test('elsewhere the worker is detached; the server says how it started the last one', () async {
      final tmp = await Directory.systemTemp.createTemp('clipforge_worker_test');
      addTearDown(() => tmp.delete(recursive: true));
      final marker = p.join(tmp.path, 'ran.txt');
      final pid = await startWorkerProcess('/bin/sh', ['-c', 'echo "\$0 \$1" > "$marker"', 'a b', 'c'],
          workingDirectory: tmp.path);
      expect(pid, greaterThan(0));
      for (var i = 0; i < 50 && !File(marker).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(File(marker).readAsStringSync().trim(), 'a b c', reason: 'arguments arrive whole');
      expect(lastWorkerStart, 'detached');
    }, skip: Platform.isWindows ? 'the Windows way is tested by tool/ci/job_survives_test.py' : false);
  });

  test('latest.json as the release job writes it is what the app reads', () async {
    final tmp = await Directory.systemTemp.createTemp('clipforge_latest_test');
    addTearDown(() => tmp.delete(recursive: true));
    final files = {
      'ClipForge-windows.zip': List.filled(1234, 1),
      'ClipForge-macos.zip': List.filled(99, 2),
      'ClipForge-android.apk': List.filled(4321, 3),
      'ClipForge-android-old-32bit-phones.apk': List.filled(7, 4),
    };
    for (final e in files.entries) {
      File(p.join(tmp.path, e.key)).writeAsBytesSync(e.value);
    }
    final run = await Process.run('python3', [
      p.join('tool', 'ci', 'make_latest_json.py'), '--dir', tmp.path, //
      '--version', '1.12.0', '--build', '142', '--tag', 'v1.12.0',
      '--base-url', 'https://github.com/example/clipforge', '--date', '2026-11-18T10:00:00Z',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final text = File(p.join(tmp.path, 'latest.json')).readAsStringSync();
    final json = jsonDecode(text) as Map;
    // The fields older versions of the page and tools read are still there.
    expect([json['version'], json['build'], json['date'], json['notes_url']], [
      '1.12.0', 142, '2026-11-18T10:00:00Z', //
      'https://github.com/example/clipforge/releases/tag/v1.12.0',
    ]);
    final info = UpdateInfo.parse(text);
    expect(info.platforms.keys, ['windows', 'macos', 'android', 'android32']);
    for (final (key, name) in const [
      ('windows', 'ClipForge-windows.zip'),
      ('macos', 'ClipForge-macos.zip'),
      ('android', 'ClipForge-android.apk'),
      ('android32', 'ClipForge-android-old-32bit-phones.apk'),
    ]) {
      final a = info.platforms[key]!;
      expect(a.url, 'https://github.com/example/clipforge/releases/download/v1.12.0/$name');
      expect(a.size, files[name]!.length);
      expect(a.sha256, sha256.convert(files[name]!).toString());
    }
    // A missing file fails the release instead of publishing half a list.
    File(p.join(tmp.path, 'ClipForge-macos.zip')).deleteSync();
    final bad = await Process.run('python3', [
      p.join('tool', 'ci', 'make_latest_json.py'), '--dir', tmp.path, '--version', '1.12.0', //
      '--build', '142', '--tag', 'v1.12.0', '--base-url', 'https://github.com/example/clipforge',
    ]);
    expect(bad.exitCode, isNot(0));
  }, skip: Process.runSync('which', ['python3']).exitCode == 0 ? false : 'python3 is not installed');
}
