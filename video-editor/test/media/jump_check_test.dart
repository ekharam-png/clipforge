// The jump check with real ffmpeg on synthetic video: a subject that stays
// put scores "smooth", one that has moved scores "jumpy", a small move is
// in between. Skipped without ffmpeg.
import 'dart:io';
import 'dart:typed_data';

import 'package:clipforge/core/transcript/cut_plan.dart';
import 'package:clipforge/media/jump_check.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('score of two frames', () {
    final a = Uint8List.fromList(List.filled(576, 100));
    final b = Uint8List.fromList(List.filled(576, 100));
    expect(jumpScoreOf(a, b), 0);
    for (var i = 0; i < 288; i++) {
      b[i] = 125;
    }
    expect(jumpScoreOf(a, b), closeTo(0.5, 0.001));
    expect(jumpScoreOf(a, Uint8List.fromList(List.filled(576, 250))), 1);
    expect(jumpScoreOf(Uint8List(0), Uint8List(0)), 0);
  });

  group('real video', () {
    late Directory dir;
    late String path;
    setUpAll(() {
      if (!ffmpegOk) return;
      dir = Directory.systemTemp.createTempSync('cf_jump_');
      path = '${dir.path}/speaker.mp4';
      // A "speaker" (white box) on a grey wall: still until 4 s, then at
      // once a fifth of the frame to the right (4..8 s), then a small
      // shift of 12 px (8..12 s).
      final r = Process.runSync('ffmpeg', [
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'color=c=0x606060:s=320x180:r=25:d=12',
        '-f', 'lavfi', '-i', 'color=c=white:s=70x90:r=25:d=12',
        '-filter_complex',
        "[0][1]overlay=x='if(lt(t,4),60,if(lt(t,8),150,162))':y=50",
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-g', '25',
        path,
      ]);
      if (r.exitCode != 0) fail('fixture: ${r.stderr}');
    });
    tearDownAll(() {
      if (ffmpegOk) dir.deleteSync(recursive: true);
    });

    test('static = smooth, moved = jumpy, small move = between', () async {
      final engine = ProcessMediaEngine();
      final watch = Stopwatch()..start();
      final scores = await engine.jumpScores(path, [
        (beforeMs: 1000, afterMs: 2000), // nothing moved
        (beforeMs: 3500, afterMs: 4500), // across the big move
        (beforeMs: 7500, afterMs: 8500), // across the small shift
        (beforeMs: 9000, afterMs: 10500), // still again
        // More than one batch.
        for (var i = 0; i < 9; i++) (beforeMs: 500 + i * 100, afterMs: 2500),
      ]);
      expect(scores.length, 13);
      expect(scores.every((s) => s != null), isTrue);
      expect(scores[0]!, lessThan(0.05));
      expect(jumpRatingOf(scores[0]), 'smooth');
      expect(scores[1]!, greaterThanOrEqualTo(kJumpy));
      expect(jumpRatingOf(scores[1]), 'jumpy');
      expect(scores[2]!, greaterThan(scores[0]! + 0.05));
      expect(scores[2]!, lessThan(scores[1]!));
      expect(scores[3]!, lessThan(0.05));
      expect(scores.skip(4).every((s) => s! < 0.05), isTrue);
      // 26 frames in two ffmpeg runs.
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('a file that cannot be read gives no scores, not an error', () async {
      final scores = await ProcessMediaEngine()
          .jumpScores('${dir.path}/missing.mp4', [(beforeMs: 0, afterMs: 500)]);
      expect(scores, [null]);
      expect(await ProcessMediaEngine().jumpScores(path, const []), isEmpty);
    });
  }, skip: ffmpegOk ? false : 'ffmpeg is not installed');
}
