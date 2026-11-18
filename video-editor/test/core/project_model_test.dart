import 'dart:convert';

import 'package:clipforge/core/model/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('JSON round-trip', () {
    test('full project survives encode/decode', () {
      final p = Project(
        id: 'abc',
        name: 'Holiday',
        createdAt: DateTime.utc(2026, 3, 4, 5, 6, 7, 8),
        updatedAt: DateTime.utc(2026, 3, 5, 1, 2, 3, 4),
        aspect: CanvasAspect.portrait4x5,
        clips: [
          const Clip(
            id: 'c1',
            type: ClipType.video,
            path: r'C:\videos\a b.mp4',
            sourceDurationMs: 12345,
            inMs: 100,
            outMs: 9000,
            width: 1080,
            height: 1920,
            hasAudio: false,
            volume: 1.5,
            muted: true,
            fit: FitMode.blur,
          ),
          photo('c2', durationMs: 2500),
        ],
        audio: [
          audio('a1', startMs: 500, inMs: 1000, outMs: 8000, volume: 0.4, fadeInMs: 300, fadeOutMs: 700),
        ],
        titles: const [
          TitleOverlay(
            id: 't1',
            text: 'Привет "мир"\n🙂',
            startMs: 10,
            endMs: 1500,
            x: 0.25,
            y: 0.75,
            fontSize: 0.1,
            colorArgb: 0x80FF0000,
            bold: false,
            background: true,
          ),
        ],
      );
      final text = jsonEncode(p.toJson());
      final back = Project.fromJson(jsonDecode(text) as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), text);
      expect(back.id, 'abc');
      expect(back.name, 'Holiday');
      expect(back.createdAt, p.createdAt);
      expect(back.updatedAt, p.updatedAt);
      expect(back.aspect, CanvasAspect.portrait4x5);
      expect(back.clips, hasLength(2));
      final c = back.clips.first;
      expect(c.type, ClipType.video);
      expect(c.path, r'C:\videos\a b.mp4');
      expect(c.sourceDurationMs, 12345);
      expect(c.inMs, 100);
      expect(c.outMs, 9000);
      expect(c.width, 1080);
      expect(c.height, 1920);
      expect(c.hasAudio, isFalse);
      expect(c.volume, 1.5);
      expect(c.muted, isTrue);
      expect(c.fit, FitMode.blur);
      expect(back.clips[1].type, ClipType.photo);
      expect(back.clips[1].durationMs, 2500);
      final a = back.audio.single;
      expect([a.startMs, a.inMs, a.outMs, a.fadeInMs, a.fadeOutMs], [500, 1000, 8000, 300, 700]);
      expect(a.volume, 0.4);
      expect(a.endMs, 7500);
      final t = back.titles.single;
      expect(t.text, 'Привет "мир"\n🙂');
      expect([t.startMs, t.endMs], [10, 1500]);
      expect([t.x, t.y, t.fontSize], [0.25, 0.75, 0.1]);
      expect(t.colorArgb, 0x80FF0000);
      expect(t.bold, isFalse);
      expect(t.background, isTrue);
    });

    test('toJson writes schemaVersion and UTC timestamps', () {
      final local = DateTime(2026, 6, 1, 12);
      final j = Project(id: 'x', name: 'n', createdAt: local, updatedAt: local).toJson();
      expect(j['schemaVersion'], kSchemaVersion);
      expect(j['createdAt'], endsWith('Z'));
      expect(DateTime.parse(j['updatedAt'] as String).isAtSameMomentAs(local), isTrue);
    });

    test('missing optional fields get defaults', () {
      final p = Project.fromJson({
        'id': 'x',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'clips': [
          {'id': 'c', 'path': '/a.mp4', 'inMs': 0, 'outMs': 1000, 'width': 10, 'height': 20},
        ],
        'audio': [
          {'id': 'a', 'path': '/a.mp3', 'startMs': 0, 'inMs': 0, 'outMs': 1000},
        ],
        'titles': [
          {'id': 't', 'startMs': 0, 'endMs': 1000},
        ],
      });
      expect(p.name, 'Untitled');
      expect(p.aspect, CanvasAspect.original);
      final c = p.clips.single;
      expect(c.type, ClipType.video);
      expect(c.sourceDurationMs, 0);
      expect(c.hasAudio, isTrue);
      expect(c.volume, 1.0);
      expect(c.muted, isFalse);
      expect(c.fit, FitMode.fit);
      expect(p.audio.single.volume, 1.0);
      expect(p.audio.single.fadeInMs, 0);
      final t = p.titles.single;
      expect(t.text, '');
      expect([t.x, t.y, t.fontSize], [0.5, 0.5, 0.06]);
      expect(t.colorArgb, 0xFFFFFFFF);
      expect(t.bold, isTrue);
      expect(t.background, isFalse);
    });

    test('unknown enum names fall back, numbers may be doubles', () {
      final p = Project.fromJson({
        'id': 'x',
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
        'aspect': 'cinema21x9',
        'clips': [
          {
            'id': 'c',
            'type': 'gif',
            'path': '/a',
            'inMs': 0.0,
            'outMs': 1500.0,
            'width': 10.0,
            'height': 20.0,
            'volume': 1,
            'fit': 'stretch',
          },
        ],
      });
      expect(p.aspect, CanvasAspect.original);
      expect(p.clips.single.type, ClipType.video);
      expect(p.clips.single.fit, FitMode.fit);
      expect(p.clips.single.outMs, 1500);
      expect(p.clips.single.volume, 1.0);
      expect(p.audio, isEmpty);
      expect(p.titles, isEmpty);
    });
  });

  group('timeline maths', () {
    final p = project(clips: [
      video('a', outMs: 1000),
      photo('b', durationMs: 500),
      video('c', inMs: 2000, outMs: 4000),
    ]);

    test('durationMs sums clips', () {
      expect(p.durationMs, 3500);
      expect(project().durationMs, 0);
    });

    test('clipStartMs', () {
      expect(p.clipStartMs(0), 0);
      expect(p.clipStartMs(1), 1000);
      expect(p.clipStartMs(2), 1500);
      expect(p.clipStartMs(3), 3500);
      expect(p.clipStartMs(99), 3500);
      expect(p.clipStartMs(-1), 0);
    });

    test('clipIndexAt', () {
      expect(project().clipIndexAt(0), -1);
      expect(project().clipIndexAt(500), -1);
      expect(p.clipIndexAt(-5), 0);
      expect(p.clipIndexAt(0), 0);
      expect(p.clipIndexAt(999), 0);
      expect(p.clipIndexAt(1000), 1, reason: 'a boundary belongs to the next clip');
      expect(p.clipIndexAt(1499), 1);
      expect(p.clipIndexAt(1500), 2);
      expect(p.clipIndexAt(3499), 2);
      expect(p.clipIndexAt(3500), 2, reason: 'the end resolves to the last clip');
      expect(p.clipIndexAt(1 << 40), 2);
    });
  });

  group('canvasSize', () {
    ({int width, int height}) size(CanvasAspect a, [Clip? first]) =>
        project(aspect: a, clips: [?first]).canvasSize;

    test('no clips', () {
      expect(size(CanvasAspect.original), (width: 1920, height: 1080));
      expect(size(CanvasAspect.portrait9x16), (width: 1080, height: 1920));
      expect(size(CanvasAspect.landscape16x9), (width: 1920, height: 1080));
      expect(size(CanvasAspect.square1x1), (width: 1080, height: 1080));
      expect(size(CanvasAspect.portrait4x5), (width: 1080, height: 1350));
    });

    test('original follows the first clip and is made even', () {
      expect(size(CanvasAspect.original, video('a', width: 1280, height: 720)),
          (width: 1280, height: 720));
      final odd = size(CanvasAspect.original, video('a', width: 1279, height: 721));
      expect(odd.width.isEven && odd.height.isEven, isTrue);
      expect((odd.width - 1279).abs() <= 1 && (odd.height - 721).abs() <= 1, isTrue);
    });

    test('original uses only the first clip', () {
      final p = project(clips: [
        video('a', width: 720, height: 1280),
        video('b', width: 3840, height: 2160),
      ]);
      expect(p.canvasSize, (width: 720, height: 1280));
    });

    test('fixed aspects keep the first clip short side', () {
      final land = video('a', width: 1280, height: 720);
      expect(size(CanvasAspect.landscape16x9, land), (width: 1280, height: 720));
      expect(size(CanvasAspect.portrait9x16, land), (width: 720, height: 1280));
      expect(size(CanvasAspect.square1x1, land), (width: 720, height: 720));
      expect(size(CanvasAspect.portrait4x5, land), (width: 720, height: 900));
      final port = video('a', width: 2160, height: 3840);
      expect(size(CanvasAspect.landscape16x9, port), (width: 3840, height: 2160));
      expect(size(CanvasAspect.portrait9x16, port), (width: 2160, height: 3840));
    });

    test('result is always even', () {
      for (final a in CanvasAspect.values) {
        for (final c in [
          video('a', width: 853, height: 481),
          video('a', width: 481, height: 853),
          video('a', width: 1001, height: 1001),
        ]) {
          final s = size(a, c);
          expect(s.width.isEven, isTrue, reason: '$a ${c.width}x${c.height}');
          expect(s.height.isEven, isTrue, reason: '$a ${c.width}x${c.height}');
          expect(s.width > 0 && s.height > 0, isTrue);
        }
      }
    });

    test('aspect ratios', () {
      expect(CanvasAspect.original.ratio, isNull);
      expect(CanvasAspect.portrait9x16.ratio, closeTo(0.5625, 1e-9));
      expect(CanvasAspect.landscape16x9.ratio, closeTo(1.7778, 1e-4));
      expect(CanvasAspect.square1x1.ratio, 1);
      expect(CanvasAspect.portrait4x5.ratio, 0.8);
    });
  });

  group('copyWith', () {
    test('Clip keeps untouched fields', () {
      final c = video('a', inMs: 100, outMs: 900).copyWith(volume: 0.5, fit: FitMode.fill);
      expect([c.id, c.inMs, c.outMs, c.durationMs], ['a', 100, 900, 800]);
      expect(c.volume, 0.5);
      expect(c.fit, FitMode.fill);
      expect(c.copyWith(id: 'b').id, 'b');
    });

    test('Project keeps id and createdAt', () {
      final p = project().copyWith(name: 'New', aspect: CanvasAspect.square1x1);
      expect(p.id, 'p1');
      expect(p.createdAt, t0);
      expect(p.name, 'New');
      expect(p.aspect, CanvasAspect.square1x1);
    });
  });
}
