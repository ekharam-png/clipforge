// Every tool that needs no media access, against a temporary projects
// folder, called through the protocol layer (so the schemas are checked
// too). Runs without ffmpeg.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/mcp/summary.dart';
import 'package:clipforge/mcp/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

const srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n\n'
    '2\n00:00:04,000 --> 00:00:06,000\nSecond <i>line</i>\n\n'
    '3\n00:00:08,000 --> 00:00:09,500\nThird\n';

void main() {
  late Bench b;
  late Client c;

  setUp(() {
    b = Bench(ffmpeg: false);
    c = b.client;
  });
  tearDown(() => b.dispose());

  group('tool list', () {
    test('has the expected tools, all described', () async {
      final r = await c.request('tools/list');
      final tools = ((r['result'] as Map)['tools'] as List).cast<Map>();
      expect(tools.map((t) => t['name']), [
        'get_status', 'list_projects', 'get_project', 'create_project', 'duplicate_project',
        'rename_project', 'set_project_settings', 'add_media', 'add_music', 'trim_clip',
        'split_at', 'remove_clip', 'move_clip', 'set_clip_properties', 'remove_silences',
        'add_title', 'add_caption', 'import_srt', 'export_srt', 'update_title', 'remove_title',
        'update_audio', 'remove_audio', 'list_sound_tracks', 'add_sound_track',
        'update_sound_track', 'remove_sound_track', 'move_audio_to_track', 'separate_sound',
        'reattach_sound', 'add_voice', 'align_audio', //
        'add_overlay', 'update_overlay', 'remove_overlay',
        'duplicate_clip', 'copy_clip_settings', 'apply_to_all', 'freeze_frame',
        'move_sound_track', 'fit_music_to_video', 'undo', 'redo', 'relink_media', 'export_video', //
        'get_export_status', 'cancel_export',
        // 1.11: speech.
        'transcribe', 'get_transcribe_status', 'cancel_transcribe',
        'get_transcript', 'find_in_transcript', 'captions_from_transcript',
        'remove_fillers', 'list_auto_cuts', 'restore_cut', 'make_short',
        // 1.13: captions as text, find and replace, who speaks.
        'get_captions', 'replace_in_captions', 'get_speech_map',
        // 1.14: shorts, publishing notes, kits, markers.
        'suggest_shorts', 'get_publishing_notes', 'set_publishing_notes',
        'make_chapters', 'export_kit', 'add_marker', 'list_markers',
        'remove_marker',
        'get_guide', 'self_test',
      ]);
      for (final t in tools) {
        final name = t['name'] as String;
        expect(name, matches(RegExp(r'^[a-z_]+$')));
        expect((t['description'] as String).length, greaterThan(40), reason: name);
        final schema = t['inputSchema'] as Map;
        expect(schema['type'], 'object', reason: name);
        final props = (schema['properties'] as Map).cast<String, Map>();
        for (final e in props.entries) {
          expect(e.value['type'], isNotNull, reason: '$name.${e.key}');
          expect((e.value['description'] as String?)?.isNotEmpty, isTrue, reason: '$name.${e.key}');
          // Every time is in milliseconds and says so.
          if (e.key.endsWith('_ms')) {
            expect(e.value['type'], 'integer', reason: '$name.${e.key}');
            expect(e.value['description'], contains('ms'), reason: '$name.${e.key}');
          }
        }
        for (final req in (schema['required'] as List? ?? const [])) {
          expect(props.containsKey(req), isTrue, reason: '$name requires unknown $req');
        }
        if (!const {
          'get_status', 'list_projects', 'create_project', 'get_export_status', //
          'cancel_export', 'get_transcribe_status', 'cancel_transcribe',
          'get_guide', 'self_test',
        }
            .contains(name)) {
          expect(props.containsKey('project_id'), isTrue, reason: name);
          expect(schema['required'], contains('project_id'), reason: name);
        }
      }
      // Nothing can delete a whole project or a file.
      expect(tools.map((t) => t['name'] as String).where((n) => n.contains('delete')), isEmpty);
      // Editing tools carry the close-the-project reminder.
      final trim = tools.firstWhere((t) => t['name'] == 'trim_clip');
      expect(trim['description'], contains('closed in the ClipForge app'));
      expect(trim['description'], contains('SOURCE FILE'));
    });

    test('the instructions state the coexistence rule and the units', () {
      expect(kServerInstructions, contains('CLOSED in the ClipForge app'));
      expect(kServerInstructions, contains('MILLISECONDS'));
    });
  });

  group('status and projects', () {
    test('get_status without ffmpeg says how to install it and where projects are', () async {
      final r = await c.ok('get_status');
      expect(r.text, contains('Projects folder: ${b.store.rootPath}'));
      expect(r.text, contains('does not exist yet'));
      expect(r.text, contains('ffmpeg: NOT FOUND'));
      expect(r.text, anyOf(contains('apt install ffmpeg'), contains('brew install ffmpeg'), contains('winget')));
      expect(r.text, contains('CLOSED in the ClipForge app'));
      expect(r.data['projectsDir'], b.store.rootPath);
      expect(r.data['projectsDirExists'], isFalse);
      expect(r.data['ffmpeg'], isNull);
      expect(r.data['ffmpegInstallHint'], isNotNull);
      expect(r.data['fontsDir'], endsWith(p.join('assets', 'fonts')));
      expect(r.data['note'], kCloseProjectRule);
    });

    test('get_status reports the same version and build as the app', () async {
      final bench = Bench(ffmpeg: false);
      addTearDown(bench.dispose);
      final r = await bench.client.ok('get_status');
      final pubspec = RegExp(r'^version:\s*([^\s+]+)\+(\d+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!;
      final info = BuildInfo.current;
      // flutter test compiles in pubspec.yaml's version, like flutter build.
      expect(info.version, pubspec[1]);
      expect(r.data['version'], pubspec[1]);
      final build = (r.data['build'] as Map).cast<String, Object?>();
      expect(build, info.toJson());
      expect(build['buildNumber'], pubspec[2]);
      expect(build['display'], 'ClipForge ${pubspec[1]} (build ${pubspec[2]}) · local build');
      expect(r.text, contains('Version: ClipForge ${pubspec[1]} (build ${pubspec[2]})'));
    });

    test('get_status with ffmpeg reports path and version', () async {
      final bench = Bench();
      addTearDown(bench.dispose);
      await bench.seed('one');
      final r = await bench.client.ok('get_status');
      expect(r.text, matches(RegExp(r'ffmpeg: \S+ \(version \S+\)')));
      expect(r.text, contains('1 project(s) found'));
      expect((r.data['ffmpeg'] as Map)['version'], isNotEmpty);
      expect((r.data['ffprobe'] as Map)['path'], isNotEmpty);
      expect(r.data['ffmpegInstallHint'], isNull);
      expect(r.data['projectCount'], 1);
    }, skip: skipWithoutFfmpeg);

    test('get_status says when the fonts are missing', () async {
      final bench = Bench(ffmpeg: false, fonts: false);
      addTearDown(bench.dispose);
      final r = await bench.client.ok('get_status');
      expect(r.text, contains('Title fonts: NOT FOUND'));
      expect(r.text, contains('--fonts-dir'));
      expect(r.data['fontsDir'], isNull);
    });

    test('create, list, get', () async {
      expect((await c.ok('list_projects')).text, contains('No projects'));
      final made = await c.ok('create_project', {'name': '  My podcast  ', 'aspect': '9:16'});
      final id = made.project['id'] as String;
      expect(made.text, contains('Created the project "My podcast"'));
      expect(made.text, contains('project_id $id'));
      expect(made.project['aspect'], '9:16');
      expect(made.project['canvasWidth'], 1080);
      expect(made.project['canvasHeight'], 1920);
      expect(b.projectFile(id).existsSync(), isTrue);
      expect((await b.store.load(id)).aspect, CanvasAspect.portrait9x16);

      final list = await c.ok('list_projects');
      expect(list.text, contains('"My podcast"  project_id $id'));
      expect((list.data['projects'] as List).single, containsPair('id', id));

      final got = await c.ok('get_project', {'project_id': id});
      expect(got.text, contains('Clips: none yet'));
      expect(got.text, contains('9:16 (vertical)'));
      expect(got.project['durationMs'], 0);
    });

    test('a project is found by id or by its exact name, whatever the case', () async {
      await b.seed('p1', name: 'Holiday');
      await b.seed('p2', name: 'Twin');
      await b.seed('p3', name: 'Twin');
      expect((await c.ok('get_project', {'project_id': 'p1'})).project['id'], 'p1');
      expect((await c.ok('get_project', {'project_id': ' holiday '})).project['id'], 'p1');
      final twin = await c.fails('get_project', {'project_id': 'Twin'});
      expect(twin, allOf(contains('2 projects are called "Twin"'), contains('p2'), contains('p3')));
      final none = await c.fails('get_project', {'project_id': 'nope'});
      expect(none, allOf(contains('no project with the id or name "nope"'), contains('"Holiday" (project_id p1)')));
      for (final bad in ['../p1', r'..\p1', '..', 'a/b', '']) {
        expect((await c.call('get_project', {'project_id': bad})).isError, isTrue, reason: bad);
      }
    });

    test('a damaged project file is reported, not thrown', () async {
      await b.seed('p1');
      b.projectFile('p1').writeAsStringSync('{ not json');
      expect(await c.fails('get_project', {'project_id': 'p1'}), contains('cannot be read'));
      b.projectFile('p1').writeAsStringSync(jsonEncode({'schemaVersion': 99, 'id': 'p1'}));
      expect(await c.fails('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 1}), contains('newer version'));
    });

    test('a folder whose name differs from the id inside is edited in place', () async {
      await b.seed('inner', name: 'Copied');
      Directory(p.join(b.store.rootPath, 'inner')).renameSync(p.join(b.store.rootPath, 'folder'));
      final r = await c.ok('rename_project', {'project_id': 'folder', 'name': 'Renamed'});
      expect(r.project['id'], 'folder');
      expect(Directory(p.join(b.store.rootPath, 'inner')).existsSync(), isFalse);
      expect((await b.store.load('folder')).name, 'Renamed');
    });

    test('duplicate_project copies under a new id and leaves the original alone', () async {
      await b.seed('p1', name: 'Film', clips: [b.video('a')]);
      final before = b.projectFile('p1').readAsStringSync();
      final r = await c.ok('duplicate_project', {'project_id': 'p1'});
      final id = r.project['id'] as String;
      expect(id, isNot('p1'));
      expect(r.project['name'], 'Film copy');
      expect(r.clips.single['id'], 'a');
      expect(r.data['sourceProjectId'], 'p1');
      expect(b.projectFile('p1').readAsStringSync(), before);
      final named = await c.ok('duplicate_project', {'project_id': 'Film', 'name': 'Vertical cut'});
      expect(named.project['name'], 'Vertical cut');
      expect((await b.store.list()).length, 3);
    });

    test('rename_project', () async {
      await b.seed('p1', name: 'Old');
      final r = await c.ok('rename_project', {'project_id': 'p1', 'name': ' New name '});
      expect(r.project['name'], 'New name');
      expect((await b.store.load('p1')).name, 'New name');
      expect(await c.fails('rename_project', {'project_id': 'p1', 'name': '   '}), contains('empty'));
      final same = await c.ok('rename_project', {'project_id': 'p1', 'name': 'New name'});
      expect(same.data['changed'], isFalse);
      expect(same.text, contains('Nothing was changed'));
    });

    test('set_project_settings', () async {
      await b.seed('p1', clips: [b.video('a')]);
      final r = await c.ok('set_project_settings', {'project_id': 'p1', 'aspect': '9:16', 'duck_music': true});
      expect(r.project['aspect'], '9:16');
      expect(r.project['canvasWidth'], 1080);
      expect(r.project['canvasHeight'], 1920);
      expect(r.project['duckMusic'], isTrue);
      expect(r.text, contains('1080x1920'));
      final saved = await b.store.load('p1');
      expect(saved.aspect, CanvasAspect.portrait9x16);
      expect(saved.duckMusic, isTrue);
      for (final e in kAspectNames.entries) {
        await c.ok('set_project_settings', {'project_id': 'p1', 'aspect': e.key});
        expect((await b.store.load('p1')).aspect, e.value);
      }
      expect(await c.fails('set_project_settings', {'project_id': 'p1'}), contains('fade_out_ms and / or duck_music'));
      expect(await c.fails('set_project_settings', {'project_id': 'p1', 'aspect': 'vertical'}),
          contains('must be one of: original, 9:16'));
    });
  });

  group('saving', () {
    test('an edit that changes nothing does not touch the file', () async {
      await b.seed('p1', clips: [b.video('a')]);
      final before = b.projectFile('p1').readAsStringSync();
      final r = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 1});
      expect(r.data['changed'], isFalse);
      expect(b.projectFile('p1').readAsStringSync(), before);
    });

    test('a change is saved with a new updatedAt, and no temp files are left', () async {
      final seeded = await b.seed('p1', clips: [b.video('a')]);
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      final saved = await b.store.load('p1');
      expect(saved.clips.single.speed, 2);
      expect(saved.updatedAt.isAfter(seeded.updatedAt), isTrue);
      expect(saved.createdAt, seeded.createdAt);
      // project.json, and the note of what this server saved last.
      expect(Directory(p.join(b.store.rootPath, 'p1')).listSync().map((f) => p.basename(f.path)).toSet(),
          {'project.json', '.claude-edit'});
    });

    test('refuses to save when the file changed between load and save (app autosave)', () async {
      // The id generator runs inside the edit, after the project was loaded:
      // use it to play the app saving the project at that moment.
      late Bench bench;
      var saves = 0;
      bench = Bench(
          ffmpeg: false,
          newId: () {
            final f = bench.projectFile('p1');
            final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
            json['updatedAt'] = DateTime.utc(2030, 1, 1, 0, 0, saves++).toIso8601String();
            json['name'] = 'Saved by the app';
            f.writeAsStringSync(jsonEncode(json));
            return 'new-id';
          });
      addTearDown(bench.dispose);
      await bench.seed('p1', name: 'Mine', clips: [bench.video('a')]);
      final message =
          await bench.client.fails('add_caption', {'project_id': 'p1', 'text': 'Hi', 'start_ms': 0});
      expect(message, allOf(contains('Nothing was saved'), contains('open in the ClipForge app'), contains('close')));
      final onDisk = await bench.store.load('p1');
      expect(onDisk.name, 'Saved by the app');
      expect(onDisk.titles, isEmpty);
      expect(saves, 1);
    });

    test('a failed edit saves nothing, even after part of it was applied', () async {
      await b.seed('p1', clips: [b.video('a')]);
      final before = b.projectFile('p1').readAsStringSync();
      // The id is fine for the first target only.
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'zzz', 'speed': 2}),
          contains('no clip with clip_id "zzz"'));
      expect(b.projectFile('p1').readAsStringSync(), before);
    });
  });

  group('clips', () {
    setUp(() async {
      await b.seed('p1', name: 'Film', clips: [
        b.video('a', file: 'one.mp4'),
        b.video('b', file: 'two.mp4', source: 6000),
        b.photo('c'),
      ]);
    });

    test('the summary lists index, id, file, timeline and source ranges', () async {
      final r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.text, contains('Project "Film" (project_id p1)'));
      expect(r.text, contains('Length: 19000 ms (0:19.000)'));
      // 1.12: every file once in a media table, the clips name its key.
      expect(r.text, contains('m1 = "one.mp4"  ${b.file('one.mp4')}  (used 1x)'));
      expect(r.text, contains('#0 clip_id=a video m1 timeline 0–10000, source 0–10000 of 10000, speed 1x'));
      expect(r.text, contains('#1 clip_id=b video m2 timeline 10000–16000, source 0–6000 of 6000, speed 1x'));
      expect(r.text, contains('#2 clip_id=c photo m3 timeline 16000–19000'));
      expect(b.file('one.mp4').allMatches(r.text).length, 1, reason: 'each path once');
      final media = (r.project['media'] as Map).cast<String, dynamic>();
      expect(media.keys, ['m1', 'm2', 'm3']);
      expect(media['m2'], {'file': 'two.mp4', 'path': b.file('two.mp4'), 'fileMissing': false, 'uses': 1});
      expect(r.text, contains('Music / sound: none.'));
      expect(r.text, contains('Titles and captions: none.'));
      expect(r.clips.map((x) => x['index']), [0, 1, 2]);
      expect(r.clips[1], containsPair('timelineStartMs', 10000));
      expect(r.clips[1], containsPair('timelineEndMs', 16000));
      expect(r.clips[1], containsPair('media', 'm2'));
      expect(r.clips[1].containsKey('path'), isFalse);
      expect(r.clips[2], containsPair('type', 'photo'));
    });

    test('a missing media file is flagged', () async {
      File(b.file('two.mp4')).deleteSync();
      final r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.text, contains('${b.file('two.mp4')}  (used 1x)  [FILE MISSING]'));
      expect(r.text, contains('speed 1x  [FILE MISSING]'));
      expect(((r.project['media'] as Map)['m2'] as Map)['fileMissing'], isTrue);
    });

    test('trim_clip takes source times and reports limits', () async {
      final r = await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 2000, 'out_ms': 5000});
      expect(r.text, contains('now uses 2000–5000 ms of its file (3000 ms on the timeline)'));
      expect(r.clips[0], containsPair('sourceInMs', 2000));
      expect(r.clips[0], containsPair('sourceOutMs', 5000));
      expect(r.clips[1], containsPair('timelineStartMs', 3000));
      final saved = (await b.store.load('p1')).clips.first;
      expect([saved.inMs, saved.outMs], [2000, 5000]);

      final limited = await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'b', 'out_ms': 99999});
      expect(limited.data['changed'], isFalse);
      expect(limited.text, contains('out_ms was limited to 6000 (asked for 99999)'));

      final oneEdge = await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 4990});
      expect(oneEdge.clips[0]['sourceInMs'], 4900, reason: 'a clip keeps 100 ms');
      expect(oneEdge.text, contains('in_ms was limited to 4900'));

      final photo = await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'c', 'out_ms': 1500});
      expect(photo.text, contains('now shown for 1500 ms'));
      expect(photo.clips[2]['durationMs'], 1500);

      expect(await c.fails('trim_clip', {'project_id': 'p1', 'clip_id': 'a'}), contains('in_ms and / or out_ms'));
      expect(await c.fails('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 5, 'out_ms': 5}),
          contains('must be after'));
      expect(await c.fails('trim_clip', {'project_id': 'p1', 'clip_id': 'c', 'in_ms': 5}), contains('photo'));
      expect(await c.fails('trim_clip', {'project_id': 'p1', 'clip_id': 'x', 'in_ms': 5}),
          allOf(contains('no clip with clip_id "x"'), contains('#0 a (one.mp4)')));
    });

    test('split_at takes a timeline time and returns both ids', () async {
      final r = await c.ok('split_at', {'project_id': 'p1', 'timeline_ms': 12000});
      final second = r.data['secondClipId'] as String;
      expect(r.data['firstClipId'], 'b');
      expect(second, isNot(anyOf('a', 'b', 'c')));
      expect(r.text, contains('second half: clip_id $second (new)'));
      expect(r.clips.map((x) => x['id']), ['a', 'b', second, 'c']);
      expect([r.clips[1]['sourceInMs'], r.clips[1]['sourceOutMs']], [0, 2000]);
      expect([r.clips[2]['sourceInMs'], r.clips[2]['sourceOutMs']], [2000, 6000]);
      expect(r.project['durationMs'], 19000);

      expect(await c.fails('split_at', {'project_id': 'p1', 'timeline_ms': 10050}),
          allOf(contains('less than 100 ms'), contains('clip #1')));
      expect(await c.fails('split_at', {'project_id': 'p1', 'timeline_ms': 19000}), contains('between 1 and 18999'));
      expect(await c.fails('split_at', {'project_id': 'p1', 'timeline_ms': 0}), contains('outside the video'));
      await b.seed('empty');
      expect(await c.fails('split_at', {'project_id': 'empty', 'timeline_ms': 5}), contains('no clips'));
    });

    test('split_at goes through the clip speed', () async {
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
      final r = await c.ok('split_at', {'project_id': 'p1', 'timeline_ms': 1000});
      expect(r.clips[0]['sourceOutMs'], 2000);
      expect(r.clips[1]['speed'], 2);
    });

    test('remove_clip and move_clip', () async {
      final moved = await c.ok('move_clip', {'project_id': 'p1', 'clip_id': 'c', 'to_index': 0});
      expect(moved.clips.map((x) => x['id']), ['c', 'a', 'b']);
      expect(moved.text, contains('now at index 0 (was 2)'));
      final far = await c.ok('move_clip', {'project_id': 'p1', 'clip_id': 'c', 'to_index': 99});
      expect(far.clips.map((x) => x['id']), ['a', 'b', 'c']);
      final same = await c.ok('move_clip', {'project_id': 'p1', 'clip_id': 'c', 'to_index': 2});
      expect(same.data['changed'], isFalse);

      final removed = await c.ok('remove_clip', {'project_id': 'p1', 'clip_id': 'b'});
      expect(removed.clips.map((x) => x['id']), ['a', 'c']);
      expect(removed.text, contains('the file is untouched'));
      expect(File(b.file('two.mp4')).existsSync(), isTrue);
      expect(await c.fails('remove_clip', {'project_id': 'p1', 'clip_id': 'b'}), contains('no clip'));
    });

    test('titles follow their picture, and the result says when one went with its footage', () async {
      await c.ok('add_caption', {'project_id': 'p1', 'text': 'On two', 'start_ms': 11000, 'end_ms': 12000});
      await c.ok('add_title', {'project_id': 'p1', 'text': 'On the photo', 'start_ms': 16500, 'end_ms': 18000});
      // Trimming 4 s off the first clip pulls everything after it earlier.
      final trimmed = await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 4000});
      expect(trimmed.titles.map((t) => [t['text'], t['startMs'], t['endMs']]), [
        ['On two', 7000, 8000],
        ['On the photo', 12500, 14000],
      ]);
      expect(trimmed.data.containsKey('titlesRemovedWithFootage'), isFalse);
      final removed = await c.ok('remove_clip', {'project_id': 'p1', 'clip_id': 'b'});
      expect(removed.text, contains('1 title(s) / caption(s) were removed along with the footage they were on: "On two"'));
      expect(removed.data['titlesRemovedWithFootage'], hasLength(1));
      expect(removed.titles.map((t) => [t['text'], t['startMs']]), [
        ['On the photo', 6500],
      ]);
    });

    test('relink_media points clips and music at a moved file', () async {
      final old = b.file('two.mp4');
      final moved = b.touch('moved two.mp4');
      File(old).deleteSync();
      expect((await c.ok('get_project', {'project_id': 'p1'})).text, contains('[FILE MISSING'));
      final r = await c.ok('relink_media', {'project_id': 'p1', 'old_path': old, 'new_path': moved});
      expect(r.text, contains('1 item(s) now use "$moved"'));
      expect(r.text, isNot(contains('[FILE MISSING')));
      final clip = (await b.store.load('p1')).clips[1];
      expect([clip.path, clip.inMs, clip.outMs], [moved, 0, 6000]);
      expect(await c.fails('relink_media', {'project_id': 'p1', 'old_path': old, 'new_path': moved}),
          allOf(contains('Nothing in this project uses'), contains('one.mp4')));
      expect(await c.fails('relink_media', {'project_id': 'p1', 'old_path': moved, 'new_path': b.file('gone.mp4')}),
          contains('does not exist'));
    });

    test('set_clip_properties sets everything through the editor', () async {
      final r = await c.ok('set_clip_properties', {
        'project_id': 'p1', 'clip_id': 'b', 'speed': 2, 'volume': 0.5, 'muted': true, 'fit': 'blur',
        'denoise': true, 'brightness': 0.2, 'contrast': -0.1, 'saturation': -1, 'zoom': 1.5,
        'transition': 'crossfade', 'transition_ms': 400, //
      });
      final clip = (await b.store.load('p1')).clips[1];
      expect(clip.speed, 2);
      expect(clip.volume, 0.5);
      expect(clip.muted, isTrue);
      expect(clip.fit, FitMode.blur);
      expect(clip.denoise, isTrue);
      expect(clip.brightness, 0.2);
      expect(clip.contrast, -0.1);
      expect(clip.saturation, -1);
      expect(clip.zoom, 1.5);
      expect(clip.transition, TransitionType.crossfade);
      expect(clip.transitionMs, 400);
      // 6 s at 2x = 3 s, overlapping the first clip by 400 ms.
      expect(r.clips[1], containsPair('timelineStartMs', 9600));
      expect(r.clips[1], containsPair('timelineEndMs', 12600));
      expect(r.project['durationMs'], 15600);
      expect(
          r.text,
          contains('speed 2x, muted, clean audio, fit blur, zoom 1.5x, brightness +0.2, contrast -0.1, '
              'saturation -1, transition crossfade 400 ms'));
    });

    test('set_clip_properties limits values and says so', () async {
      // The schema range is advisory for clients; the editor does the clamping.
      final r = await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'a', 'speed': 10, 'volume': 5, 'zoom': 9, 'transition_ms': 5000});
      final clip = (await b.store.load('p1')).clips[0];
      expect([clip.speed, clip.volume, clip.zoom, clip.transitionMs], [4.0, 2.0, 4.0, 2000]);
      expect(r.text, contains('speed was limited to 4.0 (asked for 10.0)'));
      expect(r.text, contains('volume was limited to 2.0'));
      expect(r.text, contains('transition_ms was limited to 2000 (asked for 5000)'));
    });

    test('set_clip_properties explains transitions that cannot fully apply', () async {
      final first = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'transition': 'fadeBlack'});
      expect(first.text, contains('first clip has no effect'));
      await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'b', 'out_ms': 600});
      final short = await c.ok('set_clip_properties',
          {'project_id': 'p1', 'clip_id': 'b', 'transition': 'slideLeft', 'transition_ms': 1000});
      expect(short.text, contains('lasts 300 ms because it cannot be longer than half of either clip'));
      expect(short.clips[1], containsPair('transitionOverlapMs', 300));
      // Only the length: the kind is kept.
      await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'b', 'transition_ms': 200});
      final clip = (await b.store.load('p1')).clips[1];
      expect([clip.transition, clip.transitionMs], [TransitionType.slideLeft, 200]);
    });

    test('set_clip_properties "all" applies to every clip', () async {
      final r = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'all', 'speed': 2, 'denoise': true});
      expect(r.text, contains('all 3 clips'));
      expect(r.text, contains('speed does not apply to photos'));
      final clips = (await b.store.load('p1')).clips;
      expect(clips.map((x) => x.speed), [2.0, 2.0, 1.0]);
      expect(clips.map((x) => x.denoise), everyElement(isTrue));
      expect(r.project['durationMs'], 5000 + 3000 + 3000);
    });

    test('set_clip_properties voice_focus in percent, limited, on all clips', () async {
      final r = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'voice_focus': 55});
      expect(r.clips[0], containsPair('voiceFocusPercent', 55));
      expect(r.text, contains('voice focus 55%'));
      expect((await b.store.load('p1')).clips[0].voiceFocus, closeTo(0.55, 1e-9));
      final over = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'voice_focus': 250});
      expect(over.text, contains('voice_focus was limited to 100'));
      final all = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'all', 'voice_focus': 30});
      expect(all.text, contains('sound settings do not apply to photos'));
      final clips = (await b.store.load('p1')).clips;
      expect(clips.map((x) => x.voiceFocus), [0.3, 0.3, 0]);
      final off = await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'b', 'voice_focus': 0});
      expect(off.clips[1], containsPair('voiceFocusPercent', 0));
    });

    test('set_clip_properties audio_channel on a known stereo clip', () async {
      final stereo = b.video('s', file: 'stereo.mp4').copyWith(audioStreams: const [2]);
      await b.seed('st', clips: [stereo]);
      final r = await c.ok('set_clip_properties', {'project_id': 'st', 'clip_id': 's', 'audio_channel': 'right'});
      expect(r.clips.single, containsPair('audioChannel', 'right'));
      expect(r.text, contains('right channel only'));
      expect(await c.fails('set_clip_properties', {'project_id': 'st', 'clip_id': 's', 'audio_channel': 'middle'}),
          contains('both, left, right'));
    });

    test('set_clip_properties needs something to set and valid names', () async {
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a'}), contains('at least one setting'));
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'fit': 'cover'}),
          contains('must be one of: fit, fill, blur'));
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'transition': 'wipe'}),
          contains('none, crossfade, fadeBlack, slideLeft, slideUp'));
      expect(await c.fails('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speeed': 2}),
          contains('Unknown argument "speeed"'));
    });
  });

  group('titles and captions', () {
    setUp(() async {
      await b.seed('p1', clips: [b.video('a')]);
    });

    test('add_title with defaults and with everything set', () async {
      final plain = await c.ok('add_title', {'project_id': 'p1', 'text': 'Hello', 'start_ms': 1000});
      final id = plain.data['titleId'] as String;
      expect(plain.text, contains('title_id $id'));
      expect(plain.titles.single, {
        'id': id, 'kind': 'title', 'text': 'Hello', 'startMs': 1000, 'endMs': 4000, 'x': 0.5, 'y': 0.5,
        'fontSize': 0.06, 'color': '#FFFFFF', 'bold': true, 'background': false, //
        'font': 'classic', 'outline': false, 'shadow': true, 'align': 'center',
        'animationIn': 'none', 'animationOut': 'none',
      });
      final full = await c.ok('add_title', {
        'project_id': 'p1', 'text': 'Big\nnews', 'start_ms': 0, 'end_ms': 2000, 'x': 0.5, 'y': 0.2,
        'font_size': 0.1, 'color': '#ffd400', 'bold': false, 'background': true, //
      });
      final t = (await b.store.load('p1')).titles.last;
      expect([t.text, t.startMs, t.endMs, t.y, t.fontSize, t.colorArgb, t.bold, t.background, t.kind],
          ['Big\nnews', 0, 2000, 0.2, 0.1, 0xFFFFD400, false, true, TitleKind.title]);
      expect(full.text, contains('title 0–2000 "Big / news" at x 0.5 y 0.2, size 0.1, #FFD400, boxed'));
      final byLength = await c.ok('add_title', {'project_id': 'p1', 'text': 'x', 'start_ms': 500, 'duration_ms': 700});
      expect(byLength.titles.firstWhere((x) => x['id'] == byLength.data['titleId'])['endMs'], 1200);
    });

    test('add_title checks its arguments', () async {
      Future<String> bad(Map<String, dynamic> extra) =>
          c.fails('add_title', {'project_id': 'p1', 'text': 'x', 'start_ms': 1000, ...extra});
      expect(await bad({'end_ms': 1000}), contains('must be after start_ms'));
      expect(await bad({'end_ms': 2000, 'duration_ms': 5}), contains('either end_ms or duration_ms'));
      expect(await bad({'color': 'sparkly'}), contains('#RRGGBB'));
      expect(await c.fails('add_title', {'project_id': 'p1', 'text': '  ', 'start_ms': 0}), contains('empty'));
      expect((await b.store.load('p1')).titles, isEmpty);
    });

    test('add_caption uses the caption look and warns past the end', () async {
      final r = await c.ok('add_caption', {'project_id': 'p1', 'text': 'Subtitle', 'start_ms': 2000});
      final t = (await b.store.load('p1')).titles.single;
      expect(t.kind, TitleKind.caption);
      expect([t.startMs, t.endMs], [2000, 4500]);
      expect([t.x, t.y, t.fontSize, t.background, t.bold],
          [CaptionDefaults.x, CaptionDefaults.y, CaptionDefaults.fontSize, true, true]);
      expect(r.text, contains('caption 2000–4500 "Subtitle"'));
      final late = await c.ok('add_caption', {'project_id': 'p1', 'text': 'Late', 'start_ms': 10000});
      expect(late.text, contains('after the end of the video (10000 ms) and will not be visible'));
    });

    test('update_title changes only what is given', () async {
      final id = (await c.ok('add_title', {'project_id': 'p1', 'text': 'Hello', 'start_ms': 1000})).data['titleId'];
      final r = await c.ok('update_title',
          {'project_id': 'p1', 'title_id': id, 'text': 'Bye', 'end_ms': 2500, 'color': 'red', 'y': 0.9});
      expect(r.titles.single, containsPair('text', 'Bye'));
      final t = (await b.store.load('p1')).titles.single;
      expect([t.text, t.startMs, t.endMs, t.colorArgb, t.y, t.x, t.bold], ['Bye', 1000, 2500, 0xFFFF0000, 0.9, 0.5, true]);
      expect(await c.fails('update_title', {'project_id': 'p1', 'title_id': id}), contains('at least one thing'));
      expect(await c.fails('update_title', {'project_id': 'p1', 'title_id': id, 'start_ms': 3000}),
          contains('must be after the start'));
      expect(await c.fails('update_title', {'project_id': 'p1', 'title_id': id, 'text': ' '}), contains('remove_title'));
      expect(await c.fails('update_title', {'project_id': 'p1', 'title_id': 'nope', 'text': 'x'}),
          contains('no title or caption with title_id "nope"'));
    });

    test('remove_title removes one, or all captions but no titles', () async {
      final title = (await c.ok('add_title', {'project_id': 'p1', 'text': 'T', 'start_ms': 0})).data['titleId'];
      await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt});
      final one = (await b.store.load('p1')).titles[1].id;
      final r = await c.ok('remove_title', {'project_id': 'p1', 'title_id': one});
      expect(r.text, contains('Removed the caption "Hello"'));
      expect(r.project['captionCount'], 2);
      final all = await c.ok('remove_title', {'project_id': 'p1', 'all_captions': true});
      expect(all.text, contains('Removed 2 caption(s)'));
      expect((await b.store.load('p1')).titles.map((t) => t.id), [title]);
      expect(await c.fails('remove_title', {'project_id': 'p1'}), contains('either title_id or all_captions'));
      expect(await c.fails('remove_title', {'project_id': 'p1', 'title_id': title, 'all_captions': true}),
          contains('either'));
    });

    test('import_srt from text and from a file, on the timeline', () async {
      final r = await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt});
      expect(r.text, contains('Imported 3 caption(s) from 3 subtitle(s)'));
      expect(r.data['captionsAdded'], 3);
      expect(r.titles.map((t) => [t['kind'], t['text'], t['startMs'], t['endMs']]), [
        ['caption', 'Hello', 1000, 2000],
        ['caption', 'Second line', 4000, 6000],
        ['caption', 'Third', 8000, 9500],
      ]);
      final path = b.file('subs.srt');
      File(path).writeAsStringSync('﻿${srt.replaceAll('\n', '\r\n')}');
      final again = await c.ok('import_srt',
          {'project_id': 'p1', 'path': path, 'offset_ms': -1500, 'replace_existing_captions': true});
      expect(again.text, contains('3 earlier caption(s) were removed first'));
      final titles = (await b.store.load('p1')).titles;
      expect(titles.map((t) => [t.startMs, t.endMs]), [
        [0, 500],
        [2500, 4500],
        [6500, 8000],
      ]);
      expect(titles.map((t) => t.id).toSet().length, 3);
    });

    test('import_srt reports bad input', () async {
      expect(await c.fails('import_srt', {'project_id': 'p1'}), contains('either path'));
      expect(await c.fails('import_srt', {'project_id': 'p1', 'path': b.file('x.srt'), 'srt_text': srt}),
          contains('either path'));
      expect(await c.fails('import_srt', {'project_id': 'p1', 'path': b.file('missing.srt')}),
          allOf(contains('does not exist'), contains('missing.srt')));
      expect(await c.fails('import_srt', {'project_id': 'p1', 'path': 'subs.srt'}), contains('must be a full path'));
      expect(await c.fails('import_srt', {'project_id': 'p1', 'srt_text': 'just some words'}),
          contains('No subtitles were found'));
      expect(await c.fails('import_srt', {'project_id': 'p1', 'srt_text': srt, 'source_clip_id': 'a'}),
          contains('only applies with time_base "source"'));
      expect((await b.store.load('p1')).titles, isEmpty);
    });

    test('import_srt with source times follows cuts and speed', () async {
      // The 10 s recording with 2–4 s cut out, and the rest after it at 2x.
      await b.seed('cut', clips: [
        b.video('a', outMs: 2000),
        b.video('b', inMs: 4000, outMs: 10000, speed: 2),
      ]);
      final r = await c.ok('import_srt', {
        'project_id': 'cut',
        'time_base': 'source',
        'srt_text': '1\n00:00:01,000 --> 00:00:01,800\nKept\n\n'
            '2\n00:00:02,500 --> 00:00:03,500\nCut away\n\n'
            '3\n00:00:01,500 --> 00:00:05,000\nAcross the cut\n\n'
            '4\n00:00:06,000 --> 00:00:08,000\nFast part\n\n'
            '5\n00:00:09,900 --> 00:00:12,000\nTail\n',
      });
      expect(r.titles.map((t) => [t['text'], t['startMs'], t['endMs']]), [
        ['Kept', 1000, 1800],
        ['Across the cut', 1500, 2500],
        ['Fast part', 3000, 4000],
      ]);
      // "Tail" keeps 100 ms of source = 50 ms at 2x: too short to show.
      expect(r.data['cuesDropped'], 2);
      expect(r.text, contains('2 subtitle(s) were left out'));
      expect(r.text, contains('positions in "talk.mp4"'));
    });

    test('import_srt with source times needs to know the file when there are several', () async {
      await b.seed('two', clips: [b.video('a', file: 'one.mp4'), b.video('b', file: 'two.mp4')]);
      expect(await c.fails('import_srt', {'project_id': 'two', 'time_base': 'source', 'srt_text': srt}),
          allOf(contains('uses 2 video files'), contains('source_clip_id')));
      final r = await c.ok('import_srt',
          {'project_id': 'two', 'time_base': 'source', 'source_clip_id': 'b', 'srt_text': srt});
      expect(r.titles.map((t) => t['startMs']), [11000, 14000, 18000]);
      await b.seed('photos', clips: [b.photo('c')]);
      expect(await c.fails('import_srt', {'project_id': 'photos', 'time_base': 'source', 'srt_text': srt}),
          contains('needs a video clip'));
      await b.seed('gone', clips: [b.video('a', inMs: 9600)]);
      expect(await c.fails('import_srt', {'project_id': 'gone', 'time_base': 'source', 'srt_text': srt}),
          contains('None of the 3 subtitles'));
    });

    test('export_srt returns the text and writes a file without overwriting', () async {
      expect(await c.fails('export_srt', {'project_id': 'p1'}), contains('no captions'));
      await c.ok('import_srt', {'project_id': 'p1', 'srt_text': srt});
      final before = b.projectFile('p1').readAsStringSync();
      final r = await c.ok('export_srt', {'project_id': 'p1'});
      expect(r.text, startsWith('1\n00:00:01,000 --> 00:00:02,000\nHello\n\n2\n'));
      expect(r.data['captionCount'], 3);
      expect(r.data['path'], isNull);
      final out = b.file(p.join('out', 'subs'));
      final saved = await c.ok('export_srt', {'project_id': 'p1', 'path': out});
      expect(saved.data['path'], '$out.srt');
      expect(saved.text, startsWith('Saved 3 caption(s) to $out.srt'));
      expect(File('$out.srt').readAsStringSync(), r.data['srt']);
      expect(await c.fails('export_srt', {'project_id': 'p1', 'path': '$out.srt'}), contains('already exists'));
      await c.ok('export_srt', {'project_id': 'p1', 'path': '$out.srt', 'overwrite': true});
      expect(b.projectFile('p1').readAsStringSync(), before, reason: 'the project is not touched');
    });

    test('after an edit the summary lists a few titles; get_project lists all', () async {
      final many = StringBuffer();
      for (var i = 0; i < 40; i++) {
        many.writeln('${i + 1}\n00:00:${(i ~/ 4).toString().padLeft(2, '0')},${(i % 4) * 250} --> '
            '00:00:${(i ~/ 4).toString().padLeft(2, '0')},${(i % 4) * 250 + 200}\nLine $i\n');
      }
      await c.ok('add_title', {'project_id': 'p1', 'text': 'Opening', 'start_ms': 9000});
      final r = await c.ok('import_srt', {'project_id': 'p1', 'srt_text': many.toString()});
      expect(r.data['captionsAdded'], 40);
      expect(r.titles, hasLength(kSummaryTitles));
      expect(r.titles.map((t) => t['text']), contains('Opening'), reason: 'plain titles are always shown');
      expect(r.project['titlesOmitted'], 41 - kSummaryTitles);
      expect(r.project['captionCount'], 40);
      expect(r.text, contains('… and ${41 - kSummaryTitles} more (get_project lists all of them)'));
      final page = await c.ok('get_project', {'project_id': 'p1'});
      expect(page.titles, hasLength(kDefaultTitlePage), reason: 'a small default page');
      final all = await c.ok('get_project', {'project_id': 'p1', 'title_limit': 100});
      expect(all.titles, hasLength(41));
      expect(all.project['titlesOmitted'], 0);
    });
  });

  group('sound tracks', () {
    setUp(() async {
      await b.seed('p1', clips: [
        b.video('a', source: 10000),
        b.video('b', file: 'two.mp4', source: 8000, speed: 1.25),
      ], audio: [
        AudioClip(id: 'm', path: b.touch('song.mp3'), sourceDurationMs: 30000, startMs: 0, inMs: 0, outMs: 30000),
      ]);
    });

    test('list, add (max 3), rename, settings, remove empty only', () async {
      var r = await c.ok('list_sound_tracks', {'project_id': 'p1'});
      expect(r.text, contains('"Music" (track_id music)'));
      expect((r.data['soundTracks'] as List).single['audioIds'], ['m']);
      r = await c.ok('add_sound_track', {'project_id': 'p1'});
      final voice = r.data['trackId'] as String;
      expect(r.text, contains('"Voice"'));
      await c.ok('add_sound_track', {'project_id': 'p1', 'name': 'Crowd'});
      expect(await c.fails('add_sound_track', {'project_id': 'p1'}), contains('already 3'));
      r = await c.ok('update_sound_track', {
        'project_id': 'p1', 'track_id': 'music', 'volume': 0.5, 'duck_under_speech': true, //
      });
      expect(r.text, contains('volume 0.5, lowered under speech'));
      await c.ok('update_sound_track', {'project_id': 'p1', 'track_id': 'crowd', 'name': 'Fans', 'solo': true});
      r = await c.ok('update_sound_track', {'project_id': 'p1', 'track_id': 'video', 'muted': true});
      expect(r.text, contains('video sound'));
      expect(await c.fails('update_sound_track', {'project_id': 'p1', 'track_id': 'video', 'name': 'x'}),
          contains('only volume'));
      expect(await c.fails('update_sound_track', {'project_id': 'p1', 'track_id': 'nope', 'muted': true}),
          contains('no sound track "nope"'));
      final p = await b.store.load('p1');
      expect([for (final t in p.soundTracks) t.name], ['Music', 'Voice', 'Fans']);
      expect(p.trackById('music')!.duck, isTrue);
      expect(p.videoSound.muted, isTrue);
      expect(await c.fails('remove_sound_track', {'project_id': 'p1', 'track_id': 'Music'}),
          contains('still has 1 item'));
      await c.ok('remove_sound_track', {'project_id': 'p1', 'track_id': voice});
      expect((await b.store.load('p1')).soundTracks.length, 2);
      r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.text, contains('Sound tracks (top to bottom):'));
      expect(r.text, contains('Video sound (track_id=video): muted'));
    });

    test('add_music on a named track; busy spots go to a free track', () async {
      var r = await c.ok('move_audio_to_track', {'project_id': 'p1', 'audio_id': 'm', 'track_id': 'music', 'start_ms': 1000});
      expect(r.text, contains('1000–31000'));
      await c.ok('add_sound_track', {'project_id': 'p1', 'name': 'Effects'});
      final song = b.touch('fx.mp3');
      // add_music probes the file: without ffmpeg it fails; place it by hand.
      expect(await c.fails('add_music', {'project_id': 'p1', 'path': song, 'track_id': 'Effects'}),
          isNot(contains('no sound track')));
    });

    test('separate_sound: one clip, all clips, follow, reattach', () async {
      var r = await c.ok('separate_sound', {'project_id': 'p1', 'clip_id': 'a'});
      expect(r.text, contains('"Voice" track'));
      final ids = (r.data['audioIds'] as List).cast<String>();
      var p = await b.store.load('p1');
      final s = p.audio.firstWhere((x) => x.id == ids.single);
      expect([s.startMs, s.inMs, s.outMs, s.linked], [0, 0, 10000, true]);
      expect(p.clips.first.muted, isTrue);
      expect(await c.fails('separate_sound', {'project_id': 'p1', 'clip_id': 'a'}), contains('already separated'));
      r = await c.ok('separate_sound', {'project_id': 'p1', 'all': true});
      p = await b.store.load('p1');
      final two = p.audio.firstWhere((x) => x.sourceClipId == 'b');
      expect(two.speed, 1.25);
      expect(two.trackId, s.trackId);
      r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.text, contains('sound separated from clip_id=a (follows that clip)'));
      // The sound follows its clip.
      await c.ok('trim_clip', {'project_id': 'p1', 'clip_id': 'a', 'in_ms': 2000});
      p = await b.store.load('p1');
      expect(p.audio.firstWhere((x) => x.id == ids.single).inMs, 2000);
      expect(p.audio.firstWhere((x) => x.sourceClipId == 'b').startMs, 8000);
      await c.ok('update_audio', {'project_id': 'p1', 'audio_id': ids.single, 'denoise': true, 'voice_focus': 0.5});
      p = await b.store.load('p1');
      expect(p.audio.firstWhere((x) => x.id == ids.single).voiceFocus, 0.5);
      r = await c.ok('reattach_sound', {'project_id': 'p1', 'audio_id': ids.single});
      p = await b.store.load('p1');
      expect(p.clips.first.muted, isFalse);
      expect(p.clips.first.denoise, isTrue);
      expect(await c.fails('reattach_sound', {'project_id': 'p1', 'audio_id': 'm'}), contains('music'));
      expect(await c.fails('separate_sound', {'project_id': 'p1'}), contains('either clip_id or all'));
    });

    test('video size and duck_music in the project settings', () async {
      final r = await c.ok('set_project_settings', {'project_id': 'p1', 'video_size': '720p', 'duck_music': true});
      expect(r.text, contains('video size 720p (1280x720 px)'));
      final p = await b.store.load('p1');
      expect(p.videoSize, VideoSize.p720);
      expect(p.soundTracks.single.duck, isTrue);
      expect(projectJson(p)['videoSize'], '720p');
    });
  });

  group('music', () {
    setUp(() async {
      await b.seed('p1', clips: [
        b.video('a')
      ], audio: [
        AudioClip(id: 'm', path: b.touch('song.mp3'), sourceDurationMs: 30000, startMs: 0, inMs: 0, outMs: 30000),
      ]);
    });

    test('the summary shows the item and that it runs past the end', () async {
      final r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.text, contains('audio_id=m m2 timeline 0–30000, source 0–30000 of 30000, volume 1'));
      expect(r.text, contains('runs past the end of the video'));
      expect(r.audio.single, containsPair('timelineEndMs', 30000));
    });

    test('update_audio changes only what is given and reports limits', () async {
      final r = await c.ok('update_audio', {
        'project_id': 'p1', 'audio_id': 'm', 'start_ms': 2000, 'in_ms': 5000, 'out_ms': 13000,
        'volume': 0.3, 'fade_in_ms': 500, 'fade_out_ms': 1500, //
      });
      final a = (await b.store.load('p1')).audio.single;
      expect([a.startMs, a.inMs, a.outMs, a.volume, a.fadeInMs, a.fadeOutMs], [2000, 5000, 13000, 0.3, 500, 1500]);
      expect(r.text, contains('plays 2000–10000 ms on the timeline'));
      expect(r.text, contains('volume 0.3, fade in 500, fade out 1500'));
      final limited = await c.ok('update_audio', {'project_id': 'p1', 'audio_id': 'm', 'out_ms': 99000, 'volume': 3});
      expect(limited.text, contains('out_ms was limited to 30000'));
      expect(limited.text, contains('volume was limited to 2.0'));
      expect((await b.store.load('p1')).audio.single.inMs, 5000);
      expect(await c.fails('update_audio', {'project_id': 'p1', 'audio_id': 'm'}), contains('at least one thing'));
      expect(await c.fails('update_audio', {'project_id': 'p1', 'audio_id': 'm', 'out_ms': 100}),
          contains('must be after in_ms'));
      expect(await c.fails('update_audio', {'project_id': 'p1', 'audio_id': 'x', 'volume': 1}),
          allOf(contains('no music / sound item with audio_id "x"'), contains('m (song.mp3)')));
    });

    test('remove_audio leaves the file', () async {
      final r = await c.ok('remove_audio', {'project_id': 'p1', 'audio_id': 'm'});
      expect(r.audio, isEmpty);
      expect(File(b.file('song.mp3')).existsSync(), isTrue);
      expect(await c.fails('remove_audio', {'project_id': 'p1', 'audio_id': 'm'}), contains('The project has none'));
    });
  });

  group('without ffmpeg', () {
    setUp(() async {
      await b.seed('p1', clips: [b.video('a')]);
    });

    Matcher installHelp() => allOf(
        contains('needs the free program FFmpeg'),
        anyOf(contains('apt install ffmpeg'), contains('brew install ffmpeg'), contains('winget install ffmpeg')),
        contains('keep working without it'));

    test('media tools fail with the install instruction, paths are checked first', () async {
      final media = b.touch('clip.mp4');
      expect(await c.fails('add_media', {'project_id': 'p1', 'paths': [media]}), installHelp());
      expect(await c.fails('add_music', {'project_id': 'p1', 'path': media}), installHelp());
      expect(await c.fails('remove_silences', {'project_id': 'p1'}), installHelp());
      expect(await c.fails('export_video', {'project_id': 'p1'}), installHelp());

      final missing = b.file('nope.mp4');
      expect(await c.fails('add_media', {'project_id': 'p1', 'paths': [media, missing]}),
          allOf(contains('The file "$missing" does not exist'), isNot(contains('FFmpeg'))));
      expect(await c.fails('add_music', {'project_id': 'p1', 'path': missing}), contains('does not exist'));
      expect(await c.fails('add_media', {'project_id': 'p1', 'paths': ['clip.mp4']}), contains('must be a full path'));
      expect(await c.fails('add_media', {'project_id': 'p1', 'paths': [b.tmp.path]}), contains('is a folder'));
      expect(await c.fails('add_media', {'project_id': 'p1', 'paths': <String>[]}), contains('at least 1 item'));
      expect((await b.store.load('p1')).clips, hasLength(1));
    });

    test('everything else works', () async {
      await c.ok('split_at', {'project_id': 'p1', 'timeline_ms': 5000});
      await c.ok('add_caption', {'project_id': 'p1', 'text': 'Hi', 'start_ms': 0});
      await c.ok('set_project_settings', {'project_id': 'p1', 'aspect': '1:1'});
      final r = await c.ok('get_project', {'project_id': 'p1'});
      expect(r.clips, hasLength(2));
    });

    test('export_video checks the project before anything else', () async {
      await b.seed('empty');
      expect(await c.fails('export_video', {'project_id': 'empty'}), contains('no clips'));
      File(b.file('talk.mp4')).deleteSync();
      expect(await c.fails('export_video', {'project_id': 'p1'}),
          allOf(contains('media file(s) of this project are missing'), contains('talk.mp4')));
    });

    test('remove_silences checks the clip first', () async {
      await b.seed('p2', clips: [b.photo('c')]);
      expect(await c.fails('remove_silences', {'project_id': 'p2'}), contains('no video clip with sound'));
      expect(await c.fails('remove_silences', {'project_id': 'p2', 'clip_id': 'c'}), contains('photo'));
      expect(await c.fails('remove_silences', {'project_id': 'p1', 'clip_id': 'zz'}), contains('no clip with clip_id'));
    });
  });

  group('pure helpers', () {
    Clip clip({int inMs = 0, int outMs = 10000}) => Clip(
        id: 'x', type: ClipType.video, path: '/v.mp4', sourceDurationMs: 10000,
        inMs: inMs, outMs: outMs, width: 16, height: 9);

    test('silencesToCut keeps 150 ms each side and ignores what is left under 300 ms', () {
      // Same rule as the app (lib/ui/editor/clip_actions.dart).
      expect(silencesToCut(clip(), [(startMs: 2000, endMs: 4000)]), [(startMs: 2150, endMs: 3850)]);
      expect(silencesToCut(clip(), [(startMs: 2000, endMs: 2600)]), [(startMs: 2150, endMs: 2450)]);
      expect(silencesToCut(clip(), [(startMs: 2000, endMs: 2599)]), isEmpty);
      // At the clip's own edges nothing is kept: there is no speech to protect.
      expect(silencesToCut(clip(), [(startMs: 0, endMs: 1000)]), [(startMs: 0, endMs: 850)]);
      expect(silencesToCut(clip(), [(startMs: 9000, endMs: 10000)]), [(startMs: 9150, endMs: 10000)]);
      // Limited to the trimmed part.
      expect(silencesToCut(clip(inMs: 3000, outMs: 6000), [(startMs: 2000, endMs: 4000), (startMs: 5500, endMs: 9000)]),
          [(startMs: 3000, endMs: 3850), (startMs: 5650, endMs: 6000)]);
      expect(silencesToCut(clip(inMs: 5000), [(startMs: 1000, endMs: 4000)]), isEmpty);
    });

    test('colours', () {
      expect(parseColor('#FFD400'), 0xFFFFD400);
      expect(parseColor('ffd400'), 0xFFFFD400);
      expect(parseColor('#80FF0000'), 0x80FF0000);
      expect(parseColor(' White '), 0xFFFFFFFF);
      expect(parseColor('#12'), isNull);
      expect(parseColor('nope'), isNull);
      expect(colorText(0xFFFFD400), '#FFD400');
      expect(colorText(0x80FF0000), '#80FF0000');
    });

    test('clock and photo detection', () {
      expect(clock(0), '0:00.000');
      expect(clock(62345), '1:02.345');
      expect(clock(3723004), '62:03.004');
      expect(isImagePath('/a/B.JPG'), isTrue);
      expect(isImagePath('/a/b.heic'), isTrue);
      expect(isImagePath('/a/b.mp4'), isFalse);
    });
  });
}
