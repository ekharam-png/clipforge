// Thumbnail strips and silence detection with progress (media_jobs.dart),
// plus the export size estimate. The integration part needs the system
// ffmpeg.
import 'dart:async';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/export_estimate.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_jobs.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _has(String exe) {
  try {
    return Process.runSync(exe, const ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

final bool ffmpegOk = _has('ffmpeg') && _has('ffprobe');

void ff(List<String> args) {
  final r = Process.runSync(
      'ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) fail('fixture ffmpeg failed: ${r.stderr}');
}

void main() {
  group('strip maths', () {
    test('interval: 1 s up to 5 minutes, then at most ~300 frames', () {
      expect(thumbnailStripIntervalMs(0), 2000);
      expect(thumbnailStripIntervalMs(5000), 1000);
      expect(thumbnailStripIntervalMs(300000), 1000);
      expect(thumbnailStripIntervalMs(301000), 2000);
      expect(thumbnailStripIntervalMs(2400000), 8000);
      expect(2400000 / thumbnailStripIntervalMs(2400000), lessThanOrEqualTo(300));
      expect(thumbnailStripIntervalMs(3 * 3600000), 36000);
    });

    test('frameAt picks the nearest frame, clamped to the strip', () {
      const s = ThumbnailStrip(intervalMs: 1000, frames: ['a', 'b', 'c']);
      expect(s.frameAt(-500), 'a');
      expect(s.frameAt(0), 'a');
      expect(s.frameAt(499), 'a');
      expect(s.frameAt(500), 'b');
      expect(s.frameAt(1400), 'b');
      expect(s.frameAt(2000), 'c');
      expect(s.frameAt(99000), 'c');
    });

    test('command: one pass, fps filter, keyframes only when asked', () {
      final a = buildThumbnailStripCommand(
          path: '/v.mp4', outputDir: '/o', intervalMs: 8000, height: 96);
      expect(a.contains('-skip_frame'), isFalse);
      expect(a[a.indexOf('-vf') + 1], "fps=fps=1000/8000,scale=-2:'min(96,ih)'");
      expect(a.last, p.join('/o', 'f%05d.jpg'));
      final k = buildThumbnailStripCommand(
          path: '/v.mp4', outputDir: '/o', intervalMs: 8000, keyframesOnly: true);
      expect(k.indexOf('-skip_frame'), lessThan(k.indexOf('-i')));
      expect(k[k.indexOf('-skip_frame') + 1], 'nokey');
      expect(k[k.indexOf('-discard') + 1], 'nokey');
      expect(k.indexOf('-discard'), lessThan(k.indexOf('-i')));
    });

    test('silence command for a stretch: seek before the input, then -t', () {
      final a = buildSilenceDetectRangeCommand(
          path: '/v.mp4', fromMs: 1500, spanMs: 2000);
      expect(a.sublist(0, 4), ['-ss', '1.500', '-i', '/v.mp4']);
      expect(a.sublist(4, 6), ['-t', '2.000']);
      expect(a.last, '-');
      final whole = buildSilenceDetectRangeCommand(path: '/v.mp4');
      expect(whole.contains('-ss'), isFalse);
      expect(whole.contains('-t'), isFalse);
    });
  });

  group('export size estimate', () {
    Project long(int ms, {int w = 1920, int h = 1080}) => Project(
          id: 'p',
          name: 'p',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          clips: [
            Clip(
                id: 'c',
                type: ClipType.video,
                path: '/v.mp4',
                sourceDurationMs: ms,
                inMs: 0,
                outMs: ms,
                width: w,
                height: h),
          ],
        );

    test('40 minutes of 1080p: a few GB full, under 1 GB small', () {
      final full = estimateExportSize(long(2400000), const ExportOptions());
      // 0.12 bit/pixel at 1080p30 is ~7.5 Mbit/s + 192k sound.
      expect(full.typicalBytes, closeTo(2.29e9, 0.05e9));
      expect(full.maxBytes, greaterThan(full.typicalBytes));
      final small = estimateExportSize(
          long(2400000), const ExportOptions(quality: ExportQuality.small));
      expect(small.maxBytes, closeTo((2500 + 128) * 1000 / 8 * 2400, 1e6));
      expect(small.typicalBytes, lessThan(small.maxBytes));
    });

    test('room on the disk', () {
      const e = ExportSizeEstimate(typicalBytes: 1000000000, maxBytes: 2000000000);
      expect(diskRoomFor(e, 100000000), DiskRoom.notEnough);
      expect(diskRoomFor(e, 1000000000), DiskRoom.tight);
      expect(diskRoomFor(e, 2100000000), DiskRoom.tight);
      expect(diskRoomFor(e, 2300000000), DiskRoom.enough);
    });

    test('sizes read like the system shows them', () {
      expect(formatBytes(2290000000), '2.3 GB');
      expect(formatBytes(12600000000), '13 GB');
      expect(formatBytes(45200000), '45 MB');
      expect(formatBytes(1000), '1 MB');
    });
  });

  group('with ffmpeg', skip: ffmpegOk ? null : 'ffmpeg not installed', () {
    late Directory tmp;
    late ProcessMediaEngine engine;
    late String video;
    late String gaps;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('media_jobs_test');
      engine = ProcessMediaEngine(thumbnailDir: Directory(p.join(tmp.path, 'thumbs')));
      video = p.join(tmp.path, 'v.mp4');
      // 6 s: the picture's colour changes every 2 s (red, green, blue).
      ff([
        '-f', 'lavfi', '-i', 'color=c=red:s=160x90:r=25:d=2',
        '-f', 'lavfi', '-i', 'color=c=green:s=160x90:r=25:d=2',
        '-f', 'lavfi', '-i', 'color=c=blue:s=160x90:r=25:d=2',
        '-filter_complex', '[0][1][2]concat=n=3:v=1:a=0',
        '-c:v', 'libx264', '-g', '25', '-pix_fmt', 'yuv420p', video,
      ]);
      // 8 s of tone with silence 2-4 s and 6-8 s.
      gaps = p.join(tmp.path, 'gaps.wav');
      ff([
        '-f', 'lavfi', '-i', 'sine=f=440:r=48000:d=8',
        '-af', "volume='lt(t,2)+between(t,4,6)':eval=frame",
        '-c:a', 'pcm_s16le', gaps,
      ]);
    });
    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('one run makes the whole strip; the second call uses the cache',
        () async {
      final strip = await engine.thumbnailStrip(video);
      expect(strip.intervalMs, 1000);
      expect(strip.frames.length, inInclusiveRange(5, 7));
      for (final f in strip.frames) {
        expect(File(f).lengthSync(), greaterThan(0));
      }
      // Frame at 1 s is red, at 3 s green, at 5 s blue.
      (int, int, int) rgb(String jpg) {
        final r = Process.runSync('ffmpeg', [
          '-v', 'error', '-i', jpg, '-vf', 'scale=1:1', '-f', 'rawvideo',
          '-pix_fmt', 'rgb24', '-',
        ], stdoutEncoding: null);
        final b = r.stdout as List<int>;
        return (b[0], b[1], b[2]);
      }

      expect(rgb(strip.frameAt(1000)).$1, greaterThan(150));
      expect(rgb(strip.frameAt(3000)).$2, greaterThan(90));
      expect(rgb(strip.frameAt(5000)).$3, greaterThan(150));
      final again = await engine.thumbnailStrip(video);
      expect(again.frames, strip.frames);
    });

    test('a file that cannot be read throws', () async {
      await expectLater(engine.thumbnailStrip(p.join(tmp.path, 'nope.mp4')),
          throwsA(isA<ExportException>()));
    });

    test('silence job: same result as detectSilence, progress up to 1',
        () async {
      final job = engine.startSilenceDetection(gaps);
      final seen = <double>[];
      job.progress.listen(seen.add);
      final found = await job.result;
      expect(found, await engine.detectSilence(gaps));
      expect(found.length, 2);
      expect(seen, isNotEmpty);
      expect(seen.last, 1);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
    });

    test('silence job over a stretch reports source times', () async {
      final found = await engine
          .startSilenceDetection(gaps, fromMs: 3000, toMs: 7000)
          .result;
      expect(found.length, 2, reason: '$found');
      expect(found[0].startMs, closeTo(3000, 60));
      expect(found[0].endMs, closeTo(4000, 60));
      expect(found[1].startMs, closeTo(6000, 60));
      expect(found[1].endMs, closeTo(7000, 60));
    });

    test('a cancelled silence job ends with a cancelled exception', () async {
      final job = engine.startSilenceDetection(gaps);
      unawaited(job.cancel());
      await expectLater(
          job.result,
          throwsA(isA<ExportException>()
              .having((e) => e.cancelled, 'cancelled', isTrue)));
    });
  });
}
