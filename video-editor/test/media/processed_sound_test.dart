// Processed clip sound: cache keys and when they change, the render
// command, the cache folder (LRU size limit) and the clean-up of unused
// media keeping processed files that saved projects lead to.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/storage/media_cleanup.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/media/clip_audio.dart' show kDenoiseChain;
import 'package:clipforge/media/processed_sound.dart';
import 'package:clipforge/media/processed_sound_cache.dart';
import 'package:clipforge/media/sound_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Clip talk({
  String path = '/v/a.mp4',
  int inMs = 0,
  int outMs = 4000,
  bool denoise = true,
  double focus = 0,
  int track = 0,
  AudioChannel channel = AudioChannel.both,
  List<int> streams = const [2, 2],
}) =>
    Clip(
      id: 'a',
      type: ClipType.video,
      path: path,
      sourceDurationMs: 60000,
      inMs: inMs,
      outMs: outMs,
      width: 640,
      height: 360,
      denoise: denoise,
      voiceFocus: focus,
      audioTrack: track,
      audioChannel: channel,
      audioStreams: streams,
    );

String key(Clip c, {int size = 1000, int mtime = 5}) =>
    processedSoundKey(c, size: size, modifiedMs: mtime);

void main() {
  group('which clips need processed sound', () {
    test('clean-up or voice focus on a video with sound', () {
      expect(clipNeedsProcessedSound(talk()), isTrue);
      expect(clipNeedsProcessedSound(talk(denoise: false, focus: 0.5)), isTrue);
      expect(clipNeedsProcessedSound(talk(denoise: false)), isFalse);
      // Track and side alone play exactly live.
      expect(
          clipNeedsProcessedSound(
              talk(denoise: false, channel: AudioChannel.left)),
          isFalse);
      expect(clipNeedsProcessedSound(talk().copyWith(muted: true)), isFalse);
      expect(clipNeedsProcessedSound(talk().copyWith(volume: 0)), isFalse);
    });
  });

  group('cache keys', () {
    test('the same for every piece and trim of one file', () {
      expect(key(talk(inMs: 0, outMs: 2000)), key(talk(inMs: 5000, outMs: 9000)));
      // Speed, volume, picture: applied after the processed file.
      expect(key(talk().copyWith(speed: 2, volume: 0.3, brightness: 0.5)),
          key(talk()));
    });

    test('change with the file, its size or time, and every sound setting',
        () {
      final base = key(talk());
      expect(key(talk(path: '/v/b.mp4')), isNot(base));
      expect(key(talk(), size: 1001), isNot(base));
      expect(key(talk(), mtime: 6), isNot(base));
      expect(key(talk(denoise: false, focus: 0.5)), isNot(base));
      expect(key(talk(focus: 0.5)), isNot(key(talk(focus: 0.55))));
      expect(key(talk(track: 1)), isNot(base));
      expect(key(talk(channel: AudioChannel.right)), isNot(base));
      expect(
          processedSoundKey(talk(),
              size: 1000, modifiedMs: 5, leaveOut: {SoundStage.cleanUp}),
          isNot(base));
    });

    test('settings the file does not have do not count', () {
      // Track 3 of a file with two tracks plays track 1, like the export.
      expect(key(talk(track: 3)), key(talk()));
      // A side of a mono stream: both.
      expect(key(talk(channel: AudioChannel.left, streams: const [1])),
          key(talk(streams: const [1])));
    });

    test('carry the chain version and look like processed files', () {
      final k = key(talk());
      expect(k, matches(RegExp(r'^snd_[0-9a-f]{32}$')));
      expect(isProcessedSoundFileName(processedSoundFileName(k)), isTrue);
      expect(isProcessedSoundFileName('clip.mp4'), isFalse);
      expect(processedSoundSignature(talk(focus: 0.85)), 't0|both|d1|vf0.8500');
      expect(kSoundChainVersion, greaterThanOrEqualTo(1));
    });

    test('stable hash is stable', () {
      expect(stableHash('abc'), stableHash('abc'));
      expect(stableHash('abc'), isNot(stableHash('abd')));
      expect(stableHash(''), hasLength(32));
    });
  });

  group('render command', () {
    test('whole file, chosen track, export chain, 48 kHz FLAC', () {
      final c = talk(track: 1, focus: 0.5);
      final args = buildProcessedSoundCommand(c, '/out/x.flac.part');
      expect(args.sublist(args.indexOf('-i'), args.indexOf('-i') + 2),
          ['-i', '/v/a.mp4']);
      expect(args, isNot(contains('-ss')), reason: 'the whole file');
      expect(args[args.indexOf('-map') + 1], '0:a:1');
      final af = args[args.indexOf('-af') + 1];
      expect(af, startsWith('aresample=48000:async=1:first_pts=0,'));
      expect(af, contains(kDenoiseChain));
      expect(af, contains('dialoguenhance'));
      expect(af, isNot(contains('atempo')));
      expect(af, isNot(contains('volume')));
      expect(args.sublist(args.length - 3), ['-f', 'flac', '/out/x.flac.part']);
      expect(args, containsAllInOrder(['-c:a', 'flac', '-sample_fmt', 's16']));
    });

    test('progress lines', () {
      expect(parseProgressTimeMs('out_time_us=1500000'), 1500);
      expect(parseProgressTimeMs('out_time_ms=2000000'), 2000);
      expect(parseProgressTimeMs('progress=continue'), isNull);
    });
  });

  group('cache folder', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_snd_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('keys from the source file on disk; none when it is missing',
        () async {
      final src = File(p.join(tmp.path, 'a.mp4'))..writeAsStringSync('x');
      final cache = FileProcessedSoundCache(() async => tmp.path);
      await cache.ready();
      expect(Directory(p.join(tmp.path, 'processed')).existsSync(), isTrue);
      final c = talk(path: src.path);
      final k = cache.keyFor(c)!;
      expect(cache.has(k), isFalse);
      File(cache.pathFor(k)).writeAsStringSync('flac');
      expect(cache.has(k), isTrue);
      expect(cache.keyFor(talk(path: p.join(tmp.path, 'gone.mp4'))), isNull);
      expect(cache.keyFor(talk(path: src.path, denoise: false)), isNull);
    });

    test('a changed source gets a new key', () async {
      var now = DateTime(2026, 11, 16, 12);
      final src = File(p.join(tmp.path, 'a.mp4'))..writeAsStringSync('x');
      final cache = FileProcessedSoundCache(() async => tmp.path, now: () => now);
      await cache.ready();
      final before = cache.keyFor(talk(path: src.path));
      src.writeAsStringSync('longer');
      now = now.add(const Duration(seconds: 3)); // facts are re-read
      expect(cache.keyFor(talk(path: src.path)), isNot(before));
    });

    test('least recently used files go first, wanted ones never', () async {
      final dir = Directory(p.join(tmp.path, 'processed'))..createSync();
      final t = DateTime(2026, 11, 1);
      File write(String name, int bytes, int age) {
        final f = File(p.join(dir.path, name))..writeAsBytesSync(List.filled(bytes, 0));
        f.setLastModifiedSync(t.subtract(Duration(hours: age)));
        return f;
      }

      final oldest = write('snd_1.flac', 400, 30);
      final old = write('snd_2.flac', 400, 20);
      final wanted = write('snd_3.flac', 400, 40);
      final recent = write('snd_4.flac', 400, 1);
      final part = write('snd_5.flac.part', 100, 5);
      final other = write('notes.txt', 100, 50);
      final freed = await evictProcessedSounds(dir.path,
          maxBytes: 900, keep: {'snd_3.flac'}, now: () => t);
      expect(oldest.existsSync(), isFalse);
      expect(old.existsSync(), isFalse);
      expect(wanted.existsSync(), isTrue);
      expect(recent.existsSync(), isTrue);
      expect(part.existsSync(), isFalse, reason: 'a left-over partial render');
      expect(other.existsSync(), isTrue, reason: 'not ours');
      expect(freed, 900);
    });
  });

  group('clean-up of unused media', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_snd_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('keeps processed files a saved project leads to', () async {
      final media = Directory(p.join(tmp.path, 'media'))..createSync();
      final old = DateTime.now().subtract(const Duration(days: 1));
      final src = File(p.join(media.path, 'a.mp4'))
        ..writeAsStringSync('video')
        ..setLastModifiedSync(old);
      final c = talk(path: src.path);
      final project = Project(
        id: 'p1',
        name: 'P',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        clips: [c],
      );
      final used = processedSoundPathsOf(project, media.path);
      expect(used, hasLength(1));
      final keep = File(used.single)
        ..createSync(recursive: true)
        ..writeAsStringSync('flac');
      final stale = File(p.join(media.path, 'processed', 'snd_old.flac'))
        ..writeAsStringSync('flac');
      for (final f in [keep, stale]) {
        f.setLastModifiedSync(old);
      }
      final store = _Store([project]);
      await removeUnreferencedMedia(media.path, store,
          alsoUses: (pr) => processedSoundPathsOf(pr, media.path));
      expect(keep.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
      expect(src.existsSync(), isTrue);
    });
  });
}

class _Store implements ProjectStore {
  _Store(this.projects);
  final List<Project> projects;
  @override
  Future<List<ProjectInfo>> list() async => [
        for (final p in projects)
          ProjectInfo(id: p.id, name: p.name, updatedAt: p.updatedAt, durationMs: 0),
      ];
  @override
  Future<Project> load(String id) async => projects.firstWhere((p) => p.id == id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
