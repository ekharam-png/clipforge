// Crop and position (set_clip_properties) and the overlay track tools
// (add_overlay, update_overlay, remove_overlay, the summary), with real
// files made by ffmpeg. Skipped when ffmpeg / ffprobe are not installed.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  late String video, photo, music;

  setUpAll(() {
    if (!ffmpegOk) return;
    b = Bench();
    c = b.client;
    video = b.file('clip.mp4');
    photo = b.file('photo.png');
    music = b.file('music.m4a');
    makeVideo(video, seconds: 4);
    makePhoto(photo);
    makeMusic(music);
  });
  tearDownAll(() {
    if (ffmpegOk) b.dispose();
  });

  Future<String> withVideo(String name) async {
    final id = (await c.ok('create_project', {'name': name})).project['id']
        as String;
    await c.ok('add_media', {'project_id': id, 'paths': [video]});
    return id;
  }

  group('crop and position', () {
    test('set_clip_properties: shape crop, rotation, flips, position',
        () async {
      final id = await withVideo('Crop');
      final clipId =
          (await c.ok('get_project', {'project_id': id})).clips.single['id'];
      final r = await c.ok('set_clip_properties', {
        'project_id': id,
        'clip_id': clipId,
        'crop_shape': '9:16',
        'position_x': -1,
        'fit': 'fill',
      });
      final crop = r.clips.single['crop'] as Map;
      // 9:16 out of 640x360: 202.5 / 640 wide, full height, centred.
      expect(crop['width'], closeTo(202.5 / 640, 1e-6));
      expect(crop['height'], 1.0);
      expect(crop['x'], closeTo((1 - 202.5 / 640) / 2, 1e-6));
      expect(r.clips.single['positionX'], -1);
      expect(r.text, contains('crop x'));

      final turned = await c.ok('set_clip_properties', {
        'project_id': id,
        'clip_id': clipId,
        'rotation': 90,
        'flip_horizontal': true,
      });
      expect(turned.clips.single['rotation'], 90);
      expect(turned.clips.single['flipHorizontal'], isTrue);
      // The crop turned with the picture: now a wide strip.
      final t = turned.clips.single['crop'] as Map;
      expect(t['height'], closeTo(202.5 / 640, 1e-6));

      final none = await c.ok('set_clip_properties', {
        'project_id': id,
        'clip_id': clipId,
        'crop_shape': 'none',
        'crop_x': 0.9,
        'crop_width': 0.5,
      });
      final kept = none.clips.single['crop'] as Map;
      expect(kept['x'], closeTo(0.5, 1e-9));
      expect(none.text, contains('kept inside the picture'));
      final saved = (await b.store.load(id)).clips.single.framing;
      expect(saved.crop.width, 0.5);
    }, skip: skipWithoutFfmpeg);

    test('"all" crops every clip', () async {
      final id = await withVideo('Crop all');
      await c.ok('add_media', {'project_id': id, 'paths': [photo]});
      final r = await c.ok('set_clip_properties', {
        'project_id': id,
        'clip_id': 'all',
        'rotation': 180,
      });
      expect(r.clips.map((x) => x['rotation']), [180, 180]);
    }, skip: skipWithoutFfmpeg);
  });

  group('overlay track', () {
    test('add, list, update, remove', () async {
      final id = await withVideo('PiP');
      final added = await c.ok('add_overlay', {
        'project_id': id,
        'path': photo,
        'start_ms': 500,
        'duration_ms': 1500,
        'corner': 'top_left',
        'size_percent': 40,
        'border': true,
      });
      final ovId = added.data['overlayId'] as String;
      final list = (added.project['overlays'] as List).cast<Map>();
      expect(list.single['id'], ovId);
      expect(list.single['layout'], 'pip');
      expect(list.single['corner'], 'top_left');
      expect(list.single['sizePercent'], 40);
      expect(list.single['timelineStartMs'], 500);
      expect(list.single['timelineEndMs'], 2000);
      expect(added.text, contains('overlay_id=$ovId'));
      expect(added.text, contains('Overlay track'));

      // A second item where the first is: goes after it.
      final second = await c.ok('add_overlay', {
        'project_id': id,
        'path': video,
        'start_ms': 1000,
        'out_ms': 1000,
        'layout': 'side_by_side',
        'overlay_side': 'left',
        'muted': true,
      });
      expect(second.text, contains('starts at 2000 ms'));
      final items = (second.project['overlays'] as List).cast<Map>();
      expect(items.map((o) => o['timelineStartMs']), [500, 2000]);
      expect(items[1]['overlaySide'], 'left');
      expect(items[1]['muted'], isTrue);

      final moved = await c.ok('update_overlay', {
        'project_id': id,
        'overlay_id': ovId,
        'layout': 'full',
        'rotation': 90,
        'fade_in_ms': 300,
      });
      final m = (moved.project['overlays'] as List).cast<Map>().first;
      expect(m['layout'], 'full');
      expect(m['rotation'], 90);
      expect(m['fadeInMs'], 300);

      final err = await c.fails('update_overlay',
          {'project_id': id, 'overlay_id': 'nope', 'layout': 'pip'});
      expect(err, contains('no overlay item'));

      final gone =
          await c.ok('remove_overlay', {'project_id': id, 'overlay_id': ovId});
      expect((gone.project['overlays'] as List), hasLength(1));
      final saved = await b.store.load(id);
      expect(saved.overlays.single.layout, OverlayLayout.sideBySide);
    }, skip: skipWithoutFfmpeg);

    test('an overlay needs a picture and a main video', () async {
      final empty = (await c.ok('create_project', {'name': 'Empty'}))
          .project['id'] as String;
      expect(
          await c.fails(
              'add_overlay', {'project_id': empty, 'path': photo}),
          contains('main video first'));
      final id = await withVideo('Sound only');
      expect(await c.fails('add_overlay', {'project_id': id, 'path': music}),
          contains('no picture'));
    }, skip: skipWithoutFfmpeg);

    test('exports with the overlay', () async {
      final id = await withVideo('Export PiP');
      await c.ok('add_overlay', {
        'project_id': id,
        'path': photo,
        'start_ms': 0,
        'duration_ms': 3000,
        'layout': 'full',
      });
      final r = await c.ok('export_video', {'project_id': id, 'quality': 'small'});
      final out = r.data['outputPath'] as String;
      expect(File(out).existsSync(), isTrue);
      final probe = ffprobeJson(out);
      expect(probedDurationMs(probe), closeTo(4000, 150));
    }, skip: skipWithoutFfmpeg);
  });
}
