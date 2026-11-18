// Canvas size, text layout blocks, apply-to-all, music end, relink, rename.
import 'dart:convert';

import 'package:clipforge/core/editor/editor_controller.dart';
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Clip bigPhoto(String id, {int width = 4032, int height = 3024}) => Clip(
      id: id,
      type: ClipType.photo,
      path: '/media/$id.jpg',
      sourceDurationMs: 0,
      inMs: 0,
      outMs: 3000,
      width: width,
      height: height,
      hasAudio: false,
    );

EditorController controller(Project p) {
  var now = t0;
  var ids = 0;
  return EditorController(p,
      clock: () => now = now.add(const Duration(seconds: 1)),
      newId: () => 'new${++ids}');
}

void main() {
  group('stable canvas', () {
    test('the size is captured from the first clip ever added and stays', () {
      final c = controller(project());
      expect(c.project.originalWidth, isNull);
      c.addClip(video('a', width: 720, height: 1280));
      expect([c.project.originalWidth, c.project.originalHeight], [720, 1280]);
      c.addClip(video('b', width: 3840, height: 2160));
      c.addClip(bigPhoto('p'), index: 0);
      c.moveClip(2, 0);
      expect(c.project.clips.first.id, 'b');
      expect(c.project.canvasSize, (width: 720, height: 1280));
      c.removeClip('a');
      expect(c.project.canvasSize, (width: 720, height: 1280));
      c.setAspect(CanvasAspect.landscape16x9);
      expect(c.project.canvasSize, (width: 1280, height: 720));
      c.setAspect(CanvasAspect.square1x1);
      expect(c.project.canvasSize, (width: 720, height: 720));
    });

    test('it is forgotten when the project is empty again, and undo restores it', () {
      final c = controller(project());
      c.addClip(video('a', width: 720, height: 1280));
      c.removeClip('a');
      expect(c.project.originalWidth, isNull);
      expect(c.project.originalHeight, isNull);
      expect(c.project.canvasSize, (width: 1920, height: 1080));
      c.addClip(video('b', width: 1280, height: 720));
      expect(c.project.canvasSize, (width: 1280, height: 720));
      c.undo();
      c.undo();
      expect(c.project.canvasSize, (width: 720, height: 1280));
      c.undo();
      expect(c.project.originalWidth, isNull);
    });

    test('a photo first does not make a 12 megapixel video', () {
      final c = controller(project());
      c.addClip(bigPhoto('p'));
      expect([c.project.originalWidth, c.project.originalHeight], [1440, 1080]);
      expect(c.project.canvasSize, (width: 1440, height: 1080));
      c.setAspect(CanvasAspect.portrait9x16);
      expect(c.project.canvasSize, (width: 1080, height: 1920));

      // Portrait photo, and one that is small enough already.
      expect(Project.originalSizeOf(bigPhoto('q', width: 3024, height: 4032)),
          (width: 1080, height: 1440));
      expect(Project.originalSizeOf(bigPhoto('q', width: 800, height: 600)),
          (width: 800, height: 600));
    });

    test('the short side is capped at 2160 and sizes are even', () {
      Project of(int w, int h, [CanvasAspect a = CanvasAspect.original]) =>
          project(aspect: a).copyWith(originalWidth: w, originalHeight: h);
      expect(of(3840, 2160).canvasSize, (width: 3840, height: 2160));
      expect(of(7680, 4320).canvasSize, (width: 3840, height: 2160));
      expect(of(4320, 7680).canvasSize, (width: 2160, height: 3840));
      expect(of(7680, 4320, CanvasAspect.square1x1).canvasSize,
          (width: 2160, height: 2160));
      expect(of(1281, 721).canvasSize, (width: 1282, height: 722));
      // An 8K video as first clip is captured capped.
      final c = controller(project());
      c.addClip(video('a', width: 7680, height: 4320));
      expect(c.project.canvasSize, (width: 3840, height: 2160));
    });

    test('without a captured size the first clip is used, photos capped', () {
      expect(project(clips: [video('a', width: 1280, height: 720)]).canvasSize,
          (width: 1280, height: 720));
      expect(project(clips: [bigPhoto('p'), video('a')]).canvasSize,
          (width: 1440, height: 1080));
      expect(
          project(clips: [bigPhoto('p')], aspect: CanvasAspect.landscape16x9)
              .canvasSize,
          (width: 1920, height: 1080));
    });

    test('an older project captures the clip that is first BEFORE its first edit', () {
      final c = controller(project(clips: [
        video('a', width: 720, height: 1280),
        video('b', width: 1920, height: 1080),
      ]));
      expect(c.project.originalWidth, isNull);
      c.moveClip(0, 1);
      expect(c.project.clips.first.id, 'b');
      expect(c.project.canvasSize, (width: 720, height: 1280));

      final d = controller(project(clips: [
        video('a', width: 720, height: 1280),
        video('b', width: 1920, height: 1080),
      ]));
      d.removeClip('a');
      expect(d.project.canvasSize, (width: 720, height: 1280));
    });

    test('JSON round trip; a v2 file without the fields loads fine', () {
      final p = project(clips: [video('a')])
          .copyWith(originalWidth: 1080, originalHeight: 1920);
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      expect(json['schemaVersion'], 2);
      expect(json['originalWidth'], 1080);
      final back = Project.fromJson(json);
      expect([back.originalWidth, back.originalHeight], [1080, 1920]);
      expect(content(back), content(p));

      final old = project(clips: [video('a', width: 1280, height: 720)]).toJson();
      expect(old.containsKey('originalWidth'), isFalse);
      expect(old.containsKey('originalHeight'), isFalse);
      final loaded = Project.fromJson(
          jsonDecode(jsonEncode(old)) as Map<String, dynamic>);
      expect(loaded.originalWidth, isNull);
      expect(loaded.originalHeight, isNull);
      expect(loaded.canvasSize, (width: 1280, height: 720));

      // Half a size is no size.
      final half = Project.fromJson({...old, 'originalWidth': 500});
      expect(half.originalWidth, isNull);
    });

    test('copyWith keeps, replaces or clears the size', () {
      final p = project().copyWith(originalWidth: 100, originalHeight: 200);
      expect(p.copyWith(name: 'x').originalWidth, 100);
      expect(p.copyWith(originalWidth: 300, originalHeight: 400).originalHeight, 400);
      final cleared = p.copyWith(clearOriginalSize: true);
      expect(cleared.originalWidth, isNull);
      expect(cleared.originalHeight, isNull);
    });

    test('a drag that ends where it began still records nothing', () {
      final start = project(clips: [video('a')]);
      final c = controller(start);
      c.transaction(() {
        c.trimClip('a', inMs: 500);
        c.trimClip('a', inMs: 0);
      });
      expect(identical(c.project, start), isTrue);
      expect(c.canUndo, isFalse);
    });
  });

  group('title size and placement', () {
    const caption = TitleOverlay(
      id: 'c',
      text: 'A caption that needs two lines on a phone',
      startMs: 0,
      endMs: 1000,
      x: CaptionDefaults.x,
      y: CaptionDefaults.y,
      fontSize: CaptionDefaults.fontSize,
      background: true,
      kind: TitleKind.caption,
    );

    test('the font follows the short side; landscape is unchanged', () {
      expect(titleFontPx(caption, 1080, 1920), 49);
      expect(titleFontPx(caption, 1080), 49);
      expect(titleFontPx(caption, 1920, 1080), 49);
      expect(titleFontPx(caption, 720, 720), 32);
      // Without a width the old height-only answer is given.
      expect(titleFontPx(caption, 1920), 86);
      final land =
          layoutTitleBlock(caption, canvasWidth: 1920, canvasHeight: 1080);
      final port =
          layoutTitleBlock(caption, canvasWidth: 1080, canvasHeight: 1920);
      expect(land.fontPx, 49);
      expect(port.fontPx, 49);
      expect(land.lines, hasLength(1));
      expect(port.lines.length, inInclusiveRange(2, 3));
      expect(
          port.lines,
          layoutTitleLines(caption, canvasWidth: 1080, canvasHeight: 1920));
    });

    test('block metrics', () {
      final b = layoutTitleBlock(caption, canvasWidth: 1080, canvasHeight: 1920);
      expect(b.lineHeightPx, closeTo(1.2 * 49, 1e-9));
      expect(b.boxPadPx, closeTo(0.3 * 49, 1e-9));
      expect(b.height, closeTo(b.lines.length * 1.2 * 49, 1e-9));
      var widest = 0.0;
      for (final l in b.lines) {
        final w = estimateTextWidth(l, fontPx: 49, bold: true);
        if (w > widest) widest = w;
      }
      expect(b.width, closeTo(widest, 1e-9));
      expect(b.centerX, closeTo(540, 1e-9));
      expect(b.centerY, closeTo(0.86 * 1920, 1e-9));
      expect(b.left, closeTo(540 - widest / 2, 1e-9));
      expect(b.boxWidth, closeTo(widest + 2 * b.boxPadPx, 1e-9));
      expect(() => b.lines.add('x'), throwsUnsupportedError);

      final plain = layoutTitleBlock(caption.copyWith(background: false),
          canvasWidth: 1080, canvasHeight: 1920);
      expect(plain.boxPadPx, 0);
    });

    test('the whole block stays inside the canvas with a 2% margin', () {
      for (final size in [(w: 1080, h: 1920), (w: 1920, h: 1080), (w: 720, h: 720)]) {
        for (final background in [true, false]) {
          for (final x in [0.0, 0.03, 0.5, 0.97, 1.0]) {
            for (final y in [0.0, 0.05, 0.5, 0.86, 0.99, 1.0]) {
              for (final fontSize in [0.03, 0.045, 0.1, 0.2]) {
                final t = caption.copyWith(
                    x: x, y: y, fontSize: fontSize, background: background);
                final b = layoutTitleBlock(t,
                    canvasWidth: size.w, canvasHeight: size.h);
                final why = '$size bg=$background x=$x y=$y f=$fontSize';
                expect(b.boxLeft, greaterThanOrEqualTo(size.w * 0.02 - 1e-6),
                    reason: why);
                expect(b.boxLeft + b.boxWidth,
                    lessThanOrEqualTo(size.w * 0.98 + 1e-6),
                    reason: why);
                if (b.boxHeight <= size.h * 0.96) {
                  expect(b.boxTop, greaterThanOrEqualTo(size.h * 0.02 - 1e-6),
                      reason: why);
                  expect(b.boxTop + b.boxHeight,
                      lessThanOrEqualTo(size.h * 0.98 + 1e-6),
                      reason: why);
                } else {
                  expect(b.centerY, closeTo(size.h / 2, 1e-9), reason: why);
                }
              }
            }
          }
        }
      }
    });

    test('a position that fits is kept; one at the edge is pulled in', () {
      const t = TitleOverlay(id: 't', text: 'Hi', startMs: 0, endMs: 1000, x: 0.3, y: 0.4);
      final b = layoutTitleBlock(t, canvasWidth: 1920, canvasHeight: 1080);
      expect(b.centerX, closeTo(576, 1e-9));
      expect(b.centerY, closeTo(432, 1e-9));
      final corner = layoutTitleBlock(t.copyWith(x: 1, y: 1),
          canvasWidth: 1920, canvasHeight: 1080);
      expect(corner.centerX, closeTo(1920 * 0.98 - corner.width / 2, 1e-9));
      expect(corner.centerY, closeTo(1080 * 0.98 - corner.height / 2, 1e-9));
    });

    test('a two line landscape caption does not become six lines in portrait', () {
      const two = TitleOverlay(
        id: 'c',
        text: 'A caption with enough words in it that on a landscape canvas '
            'it needs to be laid out as two full lines of text, more or less',
        startMs: 0,
        endMs: 1000,
        y: CaptionDefaults.y,
        fontSize: CaptionDefaults.fontSize,
        background: true,
      );
      final land = layoutTitleBlock(two, canvasWidth: 1920, canvasHeight: 1080);
      final port = layoutTitleBlock(two, canvasWidth: 1080, canvasHeight: 1920);
      expect(land.lines, hasLength(2));
      expect(port.lines.length, lessThanOrEqualTo(4));
      expect(port.boxTop + port.boxHeight, lessThanOrEqualTo(1920 * 0.98 + 1e-6));
    });
  });

  group('applyClipSettingsToAll', () {
    Project sample() => project(clips: [
          video('a').copyWith(
            speed: 2.0,
            brightness: 0.2,
            contrast: -0.3,
            saturation: 0.4,
            zoom: 1.5,
            fit: FitMode.blur,
            volume: 0.5,
            muted: true,
            denoise: true,
          ),
          video('b'),
          photo('p'),
          video('c', source: 300),
        ]);

    test('look goes to every clip, as one undo step', () {
      final c = controller(sample());
      final before = content(c.project);
      expect(c.applyClipSettingsToAll('a', look: true), 3);
      for (final clip in c.project.clips) {
        expect(
            [clip.brightness, clip.contrast, clip.saturation, clip.zoom, clip.fit],
            [0.2, -0.3, 0.4, 1.5, FitMode.blur],
            reason: clip.id);
      }
      expect(c.project.clips[1].speed, 1.0);
      expect(c.project.clips[1].muted, isFalse);
      c.undo();
      expect(content(c.project), before);
      expect(c.canUndo, isFalse);
    });

    test('speed goes to videos only and is capped per clip', () {
      final c = controller(sample());
      c.setClipSpeed('a', 4.0);
      expect(c.applyClipSettingsToAll('a', speed: true), 2);
      expect(c.project.clips[1].speed, 4.0);
      expect(c.project.clips[2].speed, 1.0); // photo
      // 300 ms of source must still last 100 ms.
      expect(c.project.clips[3].speed, 3.0);
      expect(c.project.clips[3].durationMs,
          greaterThanOrEqualTo(EditorController.minDurationMs));
    });

    test('sound goes to videos only', () {
      final c = controller(sample());
      expect(c.applyClipSettingsToAll('a', sound: true), 2);
      for (final id in ['b', 'c']) {
        final clip = c.project.clips.firstWhere((e) => e.id == id);
        expect([clip.volume, clip.muted, clip.denoise], [0.5, true, true]);
      }
      final p = c.project.clips[2];
      expect([p.volume, p.muted, p.denoise], [1.0, false, false]);
    });

    test('all groups at once is still one step; returns what changed', () {
      final c = controller(sample());
      expect(c.applyClipSettingsToAll('a', speed: true, look: true, sound: true), 3);
      c.undo();
      expect(c.canUndo, isFalse);
      c.redo();
      // Nothing left to change.
      final same = c.project;
      expect(c.applyClipSettingsToAll('a', speed: true, look: true, sound: true), 0);
      expect(identical(c.project, same), isTrue);
    });

    test('unknown clip, no group, or a photo as source for speed/sound: nothing', () {
      final start = sample();
      final c = controller(start);
      expect(c.applyClipSettingsToAll('nope', look: true), 0);
      expect(c.applyClipSettingsToAll('a'), 0);
      expect(c.applyClipSettingsToAll('p', speed: true, sound: true), 0);
      expect(identical(c.project, start), isTrue);
      expect(c.canUndo, isFalse);
      // A photo's look can be copied.
      expect(c.applyClipSettingsToAll('p', look: true), 1);
      expect(c.project.clips.first.zoom, 1.0);
    });

    test('the pure editor has it too', () {
      final e = ProjectEditor(sample());
      expect(e.applyClipSettingsToAll('a', look: true), 3);
    });
  });

  group('audibleEndMs', () {
    test('is the end of the music or of the video, whichever is first', () {
      final p = project(clips: [video('a')]); // 10 s
      expect(p.audibleEndMs(audio('m', source: 4000, startMs: 1000)), 5000);
      expect(p.audibleEndMs(audio('m', source: 30000, startMs: 2000)), 10000);
      expect(p.audibleEndMs(audio('m', source: 8000, startMs: 2000)), 10000);
      expect(p.audibleEndMs(audio('m', source: 4000, startMs: 10000)), 10000);
      expect(p.audibleEndMs(audio('m', source: 4000, startMs: 12000)), 12000);
      expect(project().audibleEndMs(audio('m', startMs: 0)), 0);
      expect(project().audibleEndMs(audio('m', startMs: 700)), 700);
    });
  });

  group('relinkMedia', () {
    test('replaces the path on clips and audio, undoably', () {
      final shared = video('b').copyWith(id: 'b2');
      final c = controller(project(
        clips: [video('a'), video('b'), shared],
        audio: [audio('m'), audio('b').copyWith(path: '/media/b.mp4')],
      ));
      final before = content(c.project);
      c.relinkMedia('/media/b.mp4', '/new/b.mov');
      expect([for (final e in c.project.clips) e.path],
          ['/media/a.mp4', '/new/b.mov', '/new/b.mov']);
      expect([for (final e in c.project.audio) e.path],
          ['/media/m.mp3', '/new/b.mov']);
      expect(c.project.clips[1].outMs, 10000);
      c.undo();
      expect(content(c.project), before);
      c.redo();
      c.relinkMedia('/media/m.mp3', '/new/m.mp3');
      expect(c.project.audio.first.path, '/new/m.mp3');
    });

    test('is a no-op when nothing matches', () {
      final start = project(clips: [video('a')]);
      final c = controller(start);
      c.relinkMedia('/media/zzz.mp4', '/new/zzz.mp4');
      c.relinkMedia('/media/a.mp4', '/media/a.mp4');
      c.relinkMedia('/media/a.mp4', '');
      expect(identical(c.project, start), isTrue);
      expect(c.canUndo, isFalse);
    });
  });

  group('rename is not an undo step', () {
    test('it notifies and bumps updatedAt but leaves the history alone', () {
      final c = controller(project(clips: [video('a')]));
      var notes = 0;
      c.addListener(() => notes++);
      c.rename('  Holiday ');
      expect(c.project.name, 'Holiday');
      expect(c.project.updatedAt.isAfter(t0), isTrue);
      expect(notes, 1);
      expect(c.canUndo, isFalse);
      c.rename('Holiday');
      c.rename('   ');
      expect(notes, 1);
    });

    test('undo and redo never bring an old name back', () {
      final c = controller(project(clips: [video('a')]));
      c.setClipVolume('a', 0.5);
      c.rename('One');
      c.setClipVolume('a', 0.2);
      c.undo();
      expect(c.project.name, 'One');
      expect(c.project.clips.single.volume, 0.5);
      c.rename('Two');
      expect(c.canRedo, isTrue, reason: 'a rename keeps the redo branch');
      c.undo();
      expect(c.project.name, 'Two');
      expect(c.project.clips.single.volume, 1.0);
      expect(c.canUndo, isFalse);
      c.redo();
      c.redo();
      expect(c.project.name, 'Two');
      expect(c.project.clips.single.volume, 0.2);
    });

    test('aspect changes are still undoable', () {
      final c = controller(project());
      c.setAspect(CanvasAspect.square1x1);
      c.rename('Named');
      c.undo();
      expect(c.project.aspect, CanvasAspect.original);
      expect(c.project.name, 'Named');
    });

    test('inside a transaction', () {
      final c = controller(project(clips: [video('a')]));
      var notes = 0;
      c.addListener(() => notes++);
      c.transaction(() => c.rename('Only'));
      expect(c.project.name, 'Only');
      expect(c.project.updatedAt.isAfter(t0), isTrue);
      expect(c.canUndo, isFalse);
      expect(notes, greaterThanOrEqualTo(1));

      c.transaction(() {
        c.rename('Both');
        c.setClipVolume('a', 0.5);
      });
      c.undo();
      expect(c.project.name, 'Both');
      expect(c.project.clips.single.volume, 1.0);
      expect(c.canUndo, isFalse);
    });
  });
}
