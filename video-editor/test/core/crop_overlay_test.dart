// 1.6: crop and position (Framing) and the overlay track - model, JSON,
// editing rules, History names, the shared geometry and storage.

import 'dart:io';

import 'package:clipforge/core/editor/edit_labels.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/picture_layout.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/media_check.dart';
import 'package:clipforge/core/storage/project_bundle.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

OverlayClip ov(String id,
        {int startMs = 0,
        int source = 4000,
        int inMs = 0,
        int? outMs,
        bool photo = false,
        OverlayLayout layout = OverlayLayout.pip}) =>
    OverlayClip(
      startMs: startMs,
      layout: layout,
      clip: Clip(
        id: id,
        type: photo ? ClipType.photo : ClipType.video,
        path: '/media/$id.${photo ? 'jpg' : 'mp4'}',
        sourceDurationMs: photo ? 0 : source,
        inMs: inMs,
        outMs: outMs ?? (photo ? 2000 : source),
        width: 1280,
        height: 720,
      ),
    );

void main() {
  int n = 0;
  ProjectEditor editorFor(Project p) =>
      ProjectEditor(p, clock: () => t0, newId: () => 'id${n++}');

  group('Framing', () {
    test('defaults change nothing and old projects load unchanged', () {
      final old = video('a').toJson()
        ..remove('crop')
        ..remove('rotation')
        ..remove('flipH')
        ..remove('flipV')
        ..remove('panX')
        ..remove('panY');
      final c = Clip.fromJson(old);
      expect(c.framing, Framing.none);
      expect(c.framing.isDefault, isTrue);
      final json = project(clips: [video('a')]).toJson()..remove('overlays');
      final loaded = Project.fromJson(json);
      expect(loaded.overlays, isEmpty);
      expect(json['schemaVersion'], 2);
    });

    test('JSON round trip of crop, rotation, flips and pan', () {
      const f = Framing(
          crop: CropRect(0.1, 0.2, 0.5, 0.6),
          rotation: 270,
          flipH: true,
          panX: -0.5,
          panY: 1);
      final c = video('a').copyWith(framing: f);
      final back = Clip.fromJson(c.toJson());
      expect(back.framing, f);
    });

    test('bad values are kept to their ranges', () {
      final f = Framing.fromJson({
        'crop': {'x': -1, 'y': 0.99, 'width': 2, 'height': 0.001},
        'rotation': 450,
        'panX': 7,
      });
      expect(f.rotation, 90);
      expect(f.crop.x, 0);
      expect(f.crop.width, 1);
      expect(f.crop.height, CropRect.minSize);
      expect(f.crop.bottom, lessThanOrEqualTo(1));
      expect(f.panX, 1);
    });

    test('turning takes the crop and the pan along', () {
      const f = Framing(crop: CropRect(0, 0, 0.5, 0.25), panX: 1);
      final t = f.turned(1);
      expect(t.rotation, 90);
      // Top-left strip turns to the top right.
      expect(t.crop, const CropRect(0.75, 0, 0.25, 0.5));
      expect(t.panY, 1);
      expect(t.panX, 0);
      expect(f.turned(4), f);
      expect(f.turned(1).turned(-1), f);
    });

    test('mirroring mirrors the crop; a mirrored picture turns the right way',
        () {
      const f = Framing(crop: CropRect(0, 0, 0.5, 1), panX: -1);
      final m = f.flipped(horizontal: true);
      expect(m.flipH, isTrue);
      expect(m.crop.x, 0.5);
      expect(m.panX, 1);
      // Shown: mirrored, then turned right = stored rotation 270.
      expect(m.turned(1).rotation, 270);
      expect(m.flipped(horizontal: true), f);
    });

    test('framed size swaps for a quarter turn and follows the crop', () {
      final c = video('a', width: 1920, height: 1080).copyWith(
          framing: const Framing(rotation: 90, crop: CropRect(0, 0, 1, 0.5)));
      expect(c.framedSize.width, 1080);
      expect(c.framedSize.height, 960);
    });
  });

  group('editing crop and position', () {
    test('rotate, flip, crop, pan, reset: one undo step each, named', () {
      final e = editorFor(project(clips: [video('a'), video('b')]));
      e.rotatePicture('b');
      e.flipPicture('b', horizontal: true);
      e.setPictureCrop('b', const CropRect(0.2, 0.2, 0.5, 0.5));
      e.setPicturePan('b', x: 0.5);
      e.resetFraming('b');
      expect(e.history.map((h) => h.label), [
        'Rotated clip 2',
        'Flipped clip 2',
        'Crop on clip 2',
        'Position on clip 2',
        'Crop and position reset on clip 2',
      ]);
      expect(e.project.clips[1].framing, Framing.none);
      e.undo();
      expect(e.project.clips[1].framing.panX, 0.5);
      expect(e.project.clips[1].framing.rotation, 90);
    });

    test('no-op edits leave no step', () {
      final e = editorFor(project(clips: [video('a')]));
      e.setPicturePan('a', x: 0);
      e.resetFraming('a');
      e.setPictureCrop('zzz', const CropRect(0, 0, 0.5, 0.5));
      expect(e.canUndo, isFalse);
    });

    test('the crop is clamped and the pan kept to -1..1', () {
      final e = editorFor(project(clips: [video('a')]));
      e.setPictureCrop('a', const CropRect(0.9, -0.2, 0.5, 0.01));
      final c = e.project.clips.single.framing.crop;
      expect(c.x, closeTo(0.5, 1e-9));
      expect(c.y, 0);
      expect(c.height, CropRect.minSize);
      e.setPicturePan('a', x: -3, y: 2);
      expect(e.project.clips.single.framing.panX, -1);
      expect(e.project.clips.single.framing.panY, 1);
    });

    test('split pieces and a freeze frame keep the framing', () {
      const f = Framing(rotation: 180, panX: 0.3);
      final e = editorFor(project(clips: [video('a').copyWith(framing: f)]));
      e.splitAt(4000);
      expect(e.project.clips.map((c) => c.framing), [f, f]);
      e.insertFreezeFrame(2000, photo('still'));
      expect(e.project.clips[1].framing, f);
    });

    test('pieces of one file with another framing are not one export run',
        () {
      // (The export graph checks this too; here: framing is a setting.)
      final a = video('a');
      final b = a.copyWith(id: 'b', framing: const Framing(flipV: true));
      expect(a.framing == b.framing, isFalse);
    });
  });

  group('overlay track', () {
    test('items never overlap: added after what is in the way', () {
      final e = editorFor(project(clips: [video('m', source: 20000)]));
      final a = e.addOverlay(ov('o1', startMs: 1000)); // 1000..5000
      final b = e.addOverlay(ov('o2', startMs: 2000)); // goes to 5000
      expect(e.project.overlays.map((o) => o.id), [a, b]);
      expect(e.project.overlays[1].startMs, 5000);
      expect(e.history.map((h) => h.label), ['Added overlay', 'Added overlay']);
    });

    test('a used id gets a fresh one (also one of a main clip)', () {
      final e = editorFor(project(clips: [video('m')]));
      final id = e.addOverlay(ov('m'));
      expect(id, isNot('m'));
    });

    test('moving goes to the nearest free place', () {
      final e = editorFor(project(clips: [video('m', source: 30000)]));
      e.addOverlay(ov('a', startMs: 0, outMs: 2000)); // 0..2000
      e.addOverlay(ov('b', startMs: 6000, outMs: 2000)); // 6000..8000
      final b = e.project.overlays[1];
      // Dropped on top of a, nearer to its end: right after it.
      e.updateOverlay(b.copyWith(startMs: 1500));
      expect(e.project.overlays[1].startMs, 2000);
      expect(e.history.last.label, 'Moved overlay');
      // Dropped into a gap that fits: exactly there.
      e.updateOverlay(e.project.overlays[1].copyWith(startMs: 9000));
      expect(e.project.overlays[1].startMs, 9000);
    });

    test('trimming stops at the neighbours', () {
      final e = editorFor(project(clips: [video('m', source: 30000)]));
      e.addOverlay(ov('a', startMs: 0, outMs: 2000)); // 0..2000
      e.addOverlay(ov('b', startMs: 3000, source: 10000, inMs: 2000, outMs: 4000));
      final b = e.project.overlays[1];
      // Pull its start back 1.5 s: stops at 2000 (end of a).
      e.updateOverlay(b.copyWith(
          startMs: 1500, clip: b.clip.copyWith(inMs: b.clip.inMs - 1500)));
      final now = e.project.overlays[1];
      expect(now.startMs, 2000);
      expect(now.clip.inMs, 1000);
      expect(now.endMs, 5000);
      expect(e.history.last.label, 'Trimmed overlay');
    });

    test('settings, names, remove and undo', () {
      final e = editorFor(project(clips: [video('m')]));
      final id = e.addOverlay(ov('o'));
      OverlayClip o() => e.project.overlays.single;
      e.updateOverlay(o().copyWith(layout: OverlayLayout.sideBySide));
      e.updateOverlay(o().copyWith(size: 0.5));
      e.updateOverlay(o().copyWith(clip: o().clip.copyWith(muted: true)));
      e.updateOverlay(o().copyWith(fadeInMs: 500));
      e.rotatePicture(id);
      e.updateOverlay(o().copyWith(clip: o().clip.copyWith(speed: 2)));
      e.removeOverlay(id);
      expect(e.history.map((h) => h.label).skip(1), [
        'Overlay Side by side',
        'Overlay size 50%',
        'Muted overlay',
        'Overlay fade in',
        'Rotated overlay',
        'Speed 2× on overlay',
        'Deleted overlay',
      ]);
      e.undo();
      expect(o().clip.speed, 2);
      expect(o().durationMs, 2000);
    });

    test('values are clamped', () {
      final e = editorFor(project(clips: [video('m')]));
      e.addOverlay(ov('o').copyWith(size: 5, x: -1, fadeInMs: 99999));
      final o = e.project.overlays.single;
      expect(o.size, OverlayClip.maxSize);
      expect(o.x, 0);
      expect(o.fadeInMs, o.durationMs);
    });

    test('overlays stay where they are when the main track changes', () {
      final e = editorFor(project(clips: [video('m'), video('n')]));
      e.addOverlay(ov('o', startMs: 12000));
      e.removeClip('m');
      expect(e.project.overlays.single.startMs, 12000);
    });

    test('relink also points overlays at the new file', () {
      final e = editorFor(project(clips: [video('m')]));
      e.addOverlay(ov('o'));
      e.relinkMedia('/media/o.mp4', '/new/o.mp4');
      expect(e.project.overlays.single.path, '/new/o.mp4');
    });

    test('JSON round trip, sorted on load, opacity with fades', () {
      final o = ov('o', startMs: 1000).copyWith(
          layout: OverlayLayout.free,
          x: 0.2,
          y: 0.3,
          border: true,
          fadeInMs: 1000,
          overlayFirst: true,
          corner: OverlayCorner.topLeft);
      final p = project(clips: [video('m')]).copyWith(
          overlays: [ov('late', startMs: 8000), o]);
      final back = Project.fromJson(p.toJson());
      expect(back.overlays.map((x) => x.id), ['o', 'late']);
      expect(back.overlays.first.toJson(), o.toJson());
      expect(o.opacityAt(500), 0);
      expect(o.opacityAt(1500), closeTo(0.5, 1e-9));
      expect(o.opacityAt(3000), 1);
      expect(back.overlayAt(1200)?.id, 'o');
      expect(back.overlayAt(6000), isNull);
    });

    test('the sound of an overlay item', () {
      final o = ov('o', startMs: 1000);
      expect(o.sound.trackId, kOverlayTrackId);
      expect(o.sound.startMs, 1000);
      expect(o.audible, isTrue);
      final muted = o.copyWith(clip: o.clip.copyWith(muted: true));
      expect(muted.audible, isFalse);
      expect(muted.sound.volume, 0);
      expect(ov('p', photo: true).audible, isFalse);
    });

    test('describeEdit names overlay changes', () {
      final a = project(clips: [video('m')]).copyWith(overlays: [ov('o')]);
      final b = a.copyWith(overlays: [
        ov('o').copyWith(layout: OverlayLayout.full),
      ]);
      expect(describeEdit(a, b), 'Overlay Full screen');
      expect(overlayLayoutName(OverlayLayout.pip), 'Picture-in-picture');
    });
  });

  group('geometry shared by preview and export', () {
    test('fit, fill and zoom with a pan', () {
      final c = video('a', width: 1920, height: 1080);
      // 16:9 into 9:16 with fit: bars above and below.
      final fit = placeClip(c, 1080, 1920);
      expect(fit.picture.width, closeTo(1080, 1e-9));
      expect(fit.picture.top, closeTo((1920 - 607.5) / 2, 1e-9));
      // Fill, kept to the left edge.
      final left = placeClip(
          c.copyWith(fit: FitMode.fill, framing: const Framing(panX: -1)),
          1080, 1920);
      expect(left.picture.left, 0);
      expect(left.picture.height, 1920);
      final right = placeClip(
          c.copyWith(fit: FitMode.fill, framing: const Framing(panX: 1)),
          1080, 1920);
      expect(right.picture.right, closeTo(1080, 1e-9));
      // Zoom 2 into the bottom right of a same-shape picture.
      final z = placeClip(
          c.copyWith(zoom: 2, framing: const Framing(panX: 1, panY: 1)),
          1920, 1080);
      expect(z.picture.right, closeTo(1920, 1e-9));
      expect(z.picture.bottom, closeTo(1080, 1e-9));
      expect(z.picture.width, 3840);
    });

    test('blur: only the sharp picture zooms, centred', () {
      final c = video('a', width: 1080, height: 1920)
          .copyWith(fit: FitMode.blur, zoom: 2);
      final pl = placeClip(c, 1920, 1080);
      expect(pl.visible.width, closeTo(607.5 * 2, 1e-9));
      expect(pl.visible.centerX, closeTo(960, 1e-9));
      expect(pl.visible.height, closeTo(1080, 1e-9));
    });

    test('fullPicture puts the crop on the placed picture', () {
      const crop = CropRect(0.5, 0.25, 0.5, 0.5);
      const pl = PicturePlacement(
          picture: PicBox(10, 20, 100, 50), visible: PicBox(0, 0, 200, 200));
      final full = pl.fullPicture(crop);
      expect(full, const PicBox(-90, -5, 200, 100));
    });

    test('overlay boxes', () {
      final pip = overlayFrame(ov('o'), 1920, 1080);
      // 1280x720 at 33 % of a 1920x1080 frame, 3 % margin, bottom right.
      expect(pip.box.width, closeTo(1920 * 0.33, 1e-6));
      expect(pip.box.right, closeTo(1920 - 1080 * 0.03, 1e-6));
      expect(pip.box.bottom, closeTo(1080 - 1080 * 0.03, 1e-6));
      final side = overlayFrame(
          ov('o', layout: OverlayLayout.sideBySide), 1920, 1080);
      expect(side.box, const PicBox(960, 0, 960, 1080));
      expect(side.mainDest, const PicBox(0, 0, 960, 1080));
      expect(side.mainSource, const PicBox(480, 0, 960, 1080));
      final tb = overlayFrame(
          ov('o', layout: OverlayLayout.topBottom)
              .copyWith(overlayFirst: true),
          1080, 1920);
      expect(tb.box, const PicBox(0, 0, 1080, 960));
      expect(tb.mainDest, const PicBox(0, 960, 1080, 960));
      final free = overlayFrame(
          ov('o', layout: OverlayLayout.free).copyWith(x: 0, y: 1), 1920, 1080);
      expect(free.box.left, 0);
      expect(free.box.bottom, closeTo(1080, 1e-9));
      final c = overlayCentreFor(ov('o'), -50, 2000, 1920, 1080);
      expect(c.x, closeTo(1920 * 0.33 / 2 / 1920, 1e-9));
    });

    test('cover fills the box; the pan picks the part', () {
      final pl = placeCover(const Framing(panX: 1), 1920, 1080,
          const PicBox(0, 0, 540, 1080));
      expect(pl.picture.height, 1080);
      expect(pl.picture.right, closeTo(540, 1e-9));
    });

    test('crop for a shape keeps the middle of the current crop', () {
      final c = video('a', width: 1920, height: 1080);
      final r = cropForRatio(c, 9 / 16, CropRect.full);
      expect(r.width * 1920 / (r.height * 1080), closeTo(9 / 16, 1e-9));
      expect(r.x + r.width / 2, closeTo(0.5, 1e-9));
      final left = cropForRatio(c, 1, const CropRect(0, 0, 0.2, 1));
      expect(left.x, 0);
    });
  });

  group('storage', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('cf_ov'));
    tearDown(() async => tmp.delete(recursive: true));

    test('missing media and bundles include overlay files', () async {
      final main = File(p.join(tmp.path, 'main.mp4'))..writeAsBytesSync([1, 2]);
      final over = File(p.join(tmp.path, 'over.mp4'))..writeAsBytesSync([3, 4]);
      final o = ov('o');
      final pr = project(clips: [video('m').copyWith(path: main.path)])
          .copyWith(overlays: [
        o.copyWith(clip: o.clip.copyWith(path: p.join(tmp.path, 'gone.mp4'))),
      ]);
      expect(await findMissingMedia(pr), [p.join(tmp.path, 'gone.mp4')]);

      final ok = pr.copyWith(
          overlays: [o.copyWith(clip: o.clip.copyWith(path: over.path))]);
      final zip = p.join(tmp.path, 'b.zip');
      await exportBundle(ok, zip);
      final store = ProjectStore.atPath(p.join(tmp.path, 'projects'));
      final media = p.join(tmp.path, 'media2');
      final imported = await importBundle(zip,
          store: store, mediaDir: media, newId: () => 'imp');
      final path = imported.overlays.single.path;
      expect(path, startsWith(media));
      expect(File(path).readAsBytesSync(), [3, 4]);
    });
  });
}
