// 1.7 tools and arguments: fades, filters, title styles, duplicate_clip,
// copy_clip_settings, apply_to_all, move_sound_track, undo / redo,
// freeze_frame, sound-only export and frame rate.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  setUp(() {
    b = Bench();
    c = b.client;
  });
  tearDown(() => b.dispose());

  test('fades, filter and warmth on clips and the project', () async {
    await b.seed('p1', clips: [b.video('a', source: 4000), b.photo('ph')]);
    final r = await c.ok('set_clip_properties', {
      'project_id': 'p1', 'clip_id': 'a', 'fade_in_ms': 9000, 'fade_out_ms': 500,
      'filter': 'black_and_white', 'warmth': 0.5,
    });
    expect(r.text, contains('fade_in_ms was limited to 4000'));
    var a = (await b.store.load('p1')).clips.first;
    expect([a.fadeInMs, a.fadeOutMs, a.filter, a.warmth], [4000, 0, LookFilter.blackWhite, 0.5]);
    expect(r.clips.first['filter'], 'black_and_white');
    await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'all', 'filter': 'vintage'});
    expect((await b.store.load('p1')).clips.map((c) => c.filter), everyElement(LookFilter.vintage));
    final s = await c.ok('set_project_settings',
        {'project_id': 'p1', 'fade_in_ms': 1000, 'fade_out_ms': 6000});
    expect(s.text, contains('at most half the video'));
    expect(s.project['fadeOutMs'], 6000);
    expect(s.text, contains('Fades in from black: 1000 ms.'));
  });

  test('title styles', () async {
    await b.seed('p1', clips: [b.video('a')]);
    final r = await c.ok('add_title', {
      'project_id': 'p1', 'text': 'Hi', 'start_ms': 0, 'style': 'yellow',
      'font': 'handwritten', 'align': 'left', 'position': 'lower_third',
      'animation_in': 'pop', 'animation_out': 'slide_up',
    });
    final t = (await b.store.load('p1')).titles.single;
    expect([t.font, t.colorArgb, t.outline, t.align, t.x, t.y, t.animIn, t.animOut], [
      TitleFont.handwritten, 0xFFFFD60A, true, TitleAlign.left, 0.0, 0.75,
      TitleAnimation.pop, TitleAnimation.slideUp,
    ]);
    expect(r.titles.single['animationOut'], 'slide_up');
    await c.ok('update_title', {
      'project_id': 'p1', 'title_id': t.id, 'outline_color': '#FF0000', 'shadow': false,
    });
    final u = (await b.store.load('p1')).titles.single;
    expect([u.outlineColorArgb, u.shadow], [0xFFFF0000, false]);
    expect(await c.fails('update_title', {'project_id': 'p1', 'title_id': t.id, 'style': 'shiny'}),
        contains('must be one of'));
  });

  test('duplicate, copy settings, apply to all, track order', () async {
    await b.seed('p1', clips: [
      b.video('a').copyWith(brightness: 0.4, speed: 2, filter: LookFilter.warm),
      b.video('b'),
      b.photo('ph'),
    ]);
    final d = await c.ok('duplicate_clip', {'project_id': 'p1', 'clip_id': 'a'});
    final copy = d.data['clipId'] as String;
    expect((await b.store.load('p1')).clips.map((c) => c.id), ['a', copy, 'b', 'ph']);
    final s = await c.ok('copy_clip_settings',
        {'project_id': 'p1', 'from_clip_id': 'a', 'to_clip_ids': ['all']});
    expect(s.data['changedClips'], 2);
    final p1 = await b.store.load('p1');
    expect(p1.clips[2].speed, 2);
    expect(p1.clips[3].filter, LookFilter.warm);
    expect(p1.clips[3].speed, 1);
    await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'b', 'contrast': 0.5});
    final all = await c.ok('apply_to_all', {'project_id': 'p1', 'clip_id': 'b', 'look': true});
    expect(all.data['changedClips'], 3);
    expect(await c.fails('apply_to_all', {'project_id': 'p1', 'clip_id': 'b'}),
        contains('look, speed and / or sound'));

    await c.ok('add_sound_track', {'project_id': 'p1', 'name': 'Voice'});
    await c.ok('add_sound_track', {'project_id': 'p1', 'name': 'Music'});
    final m = await c.ok('move_sound_track',
        {'project_id': 'p1', 'track_id': 'Music', 'direction': 'up'});
    expect(m.text, contains('Moved the track "Music" up'));
    expect((await b.store.load('p1')).soundTracks.map((t) => t.name), ['Music', 'Voice']);
  });

  test('undo and redo take back Claude\'s own edits only', () async {
    await b.seed('p1', clips: [b.video('a')]);
    expect(await c.fails('undo', {'project_id': 'p1'}), contains('nothing to undo'));
    await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'speed': 2});
    await c.ok('set_clip_properties', {'project_id': 'p1', 'clip_id': 'a', 'volume': 0.5});
    final u = await c.ok('undo', {'project_id': 'p1'});
    expect(u.text, contains('Undid "Volume 50% on clip 1"'));
    expect((await b.store.load('p1')).clips.single.volume, 1);
    await c.ok('redo', {'project_id': 'p1'});
    expect((await b.store.load('p1')).clips.single.volume, 0.5);
    await c.ok('undo', {'project_id': 'p1'});
    await c.ok('undo', {'project_id': 'p1'});
    expect((await b.store.load('p1')).clips.single.speed, 1);
    expect(await c.fails('undo', {'project_id': 'p1'}), contains('nothing to undo'));
    // Changed elsewhere (the app): the history is dropped.
    await c.ok('redo', {'project_id': 'p1'});
    final now = await b.store.load('p1');
    await b.store.save(now.copyWith(name: 'Renamed in the app', updatedAt: DateTime.now()));
    expect(await c.fails('undo', {'project_id': 'p1'}), contains('changed since'));
  });

  test('freeze frame and sound-only export (real ffmpeg)', () async {
    final video = b.file('clip.mp4');
    makeVideo(video, seconds: 3);
    final id = (await c.ok('create_project', {'name': 'f'})).project['id'] as String;
    await c.ok('add_media', {'project_id': id, 'paths': [video]});
    final before = (await b.store.load(id)).durationMs;
    expect((await b.store.load(id)).clips.single.frameRate, greaterThan(0));
    final r = await c.ok('freeze_frame', {'project_id': id, 'at_ms': 1000, 'duration_ms': 1500});
    final after = await b.store.load(id);
    expect(after.clips.map((c) => c.type),
        [ClipType.video, ClipType.photo, ClipType.video]);
    expect(after.durationMs, before + 1500);
    expect(File(after.clips[1].path).existsSync(), isTrue);
    expect(r.text, contains('Held the picture at 1000 ms'));
    expect(await c.fails('freeze_frame', {'project_id': id, 'at_ms': 99999}),
        contains('inside the video'));

    final out = b.file('sound.mp3');
    final e = await c.ok('export_video',
        {'project_id': id, 'output_path': out, 'format': 'mp3'});
    expect(File(out).existsSync(), isTrue);
    expect(e.data['format'], 'mp3');
    expect(e.data['hasVideo'], isFalse);
    expect(await c.fails('export_video',
            {'project_id': id, 'output_path': b.file('x.mp4'), 'format': 'm4a'}),
        contains('must end in .m4a'));
    final v = await c.ok('export_video',
        {'project_id': id, 'output_path': b.file('v.mp4'), 'fps': '25', 'hardware': false});
    expect(v.data['fps'], 25);
    expect(p.extension(v.data['outputPath'] as String), '.mp4');
  }, skip: ffmpegOk ? false : 'ffmpeg not installed');
}
