// 1.18: "Only when speaking" on a real recording (a 9-minute video with
// two voice tracks, a Mac) could not be exported: "its FFmpeg has no "if"
// filter". The check for missing filters read the commas inside the
// volume expression as the end of a filter. Here: the check itself, and a
// real export with 320 pauses on each of two voice tracks (FFmpeg on PATH;
// skipped without it).

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/sound_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<QuietRange> pauses(int count, {required int periodMs, required int fromMs}) => [
      for (var k = 0; k < count; k++)
        QuietRange(
            k * periodMs + fromMs, k * periodMs + fromMs + periodMs ~/ 2),
    ];

void main() {
  group('the missing-filter check and expressions', () {
    test('functions inside a quoted expression are not filters', () {
      for (final n in [1, 2, 3, 4, 7, 320]) {
        final stage = quietFilter([pauses(n, periodMs: 400, fromMs: 200)],
            originMs: 0);
        expect(filtersInGraph('[0:a]${stage}anull[a]'),
            ['asetnsamples', 'volume', 'anull'],
            reason: '$n pauses');
      }
    });

    test('three pauses were what it took: nested if after a comma', () {
      final e = quietExpression(pauses(3, periodMs: 400, fromMs: 200), 0);
      expect(e, contains(',if(lt(t,'));
      final check = SoundFilterCheck.of(
          {'aformat', 'anull', 'volume', 'asetnsamples'});
      expect(check.missingIn("[0:a]asetnsamples=n=48:p=0,volume=volume='$e'"
          ':eval=frame,anull[a]'), isEmpty);
    });

    test('expression functions never count, quoted or escaped', () {
      const graph = "[0:a]volume=volume='if(between(t,1,2),0.5,min(1,max(0,t)))'"
          ':eval=frame[a];'
          r"[0:v]drawtext=text=a:enable=between(t\,1\,2),"
          "overlay=enable='between(t,3,4)*gte(t,0)'[v]";
      expect(filtersInGraph(graph), ['volume', 'drawtext', 'overlay']);
    });

    test('a real filter that is missing is still found', () {
      final check = SoundFilterCheck.of({'aformat', 'anull', 'volume'});
      expect(
          check.missingIn("[0:a]volume=volume='if(lt(t,1),1,0)',afftdn=nr=10[a]"),
          ['afftdn']);
    });

    test('an unclosed quote does not loop or throw', () {
      expect(filtersInGraph("[0:a]volume=volume='if(lt(t,1)"), ['volume']);
    });
  });

  if (!ffmpegOk) {
    test('the export needs ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  group('a real export with hundreds of pauses', () {
    const seconds = 132;
    setUpAll(() {
      setUpMedia();
      ff([
        '-f', 'lavfi', '-i', 'testsrc2=s=160x90:r=5:d=$seconds',
        '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=mono',
        '-map', '0:v', '-map', '1:a',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-g', '10', '-c:a', 'aac', '-t', '$seconds', f('long.mp4'),
      ]);
      ff(['-f', 'lavfi', '-i',
          "aevalsrc='0.3*sin(2*PI*1000*t)':s=48000:d=$seconds", f('micA.wav')]);
      ff(['-f', 'lavfi', '-i',
          "aevalsrc='0.3*sin(2*PI*2000*t)':s=48000:d=$seconds", f('micB.wav')]);
    });
    tearDownAll(tearDownMedia);

    test('320 pauses on each of two voice tracks', () async {
      AudioClip voice(String id, String file, String track) => AudioClip(
            id: id,
            path: f(file),
            sourceDurationMs: seconds * 1000,
            startMs: 0,
            inMs: 0,
            outMs: seconds * 1000,
            trackId: track,
          );
      final project = Project(
        id: 'p',
        name: 'p',
        createdAt: t0,
        updatedAt: t0,
        clips: [
          Clip(
            id: 'pic',
            type: ClipType.video,
            path: f('long.mp4'),
            sourceDurationMs: seconds * 1000,
            inMs: 0,
            outMs: seconds * 1000,
            width: 160,
            height: 90,
            frameRate: 5,
            muted: true,
          ),
        ],
        tracks: const [
          SoundTrack(id: 'a', name: 'A', speech: true),
          SoundTrack(id: 'b', name: 'B', speech: true),
        ],
        audio: [voice('va', 'micA.wav', 'a'), voice('vb', 'micB.wav', 'b')],
      );
      // A is closed in the second half of every 400 ms, B in the first.
      final gates = {
        'va': pauses(320, periodMs: 400, fromMs: 200),
        'vb': pauses(320, periodMs: 400, fromMs: 0),
      };
      final cmd = buildExportCommand(
          project: project,
          outputPath: f('x.mp4'),
          fonts: fonts,
          workDir: tmp.path,
          options: ExportOptions(gates: gates));
      // ignore: avoid_print
      print('graph: ${cmd.filterGraph.length} characters, '
          'file: ${cmd.needsGraphFile}');
      expect(cmd.needsGraphFile, isTrue,
          reason: 'too long for an argument on Windows: it goes in a file');
      expect(filtersInGraph(cmd.filterGraph), isNot(contains('if')));

      final watch = Stopwatch()..start();
      final out =
          await exportAndCheck(project, options: ExportOptions(gates: gates));
      // ignore: avoid_print
      print('exported $seconds s with 2 x 320 pauses in '
          '${watch.elapsedMilliseconds} ms');

      double band(int hz, int fromMs, int toMs) => meanVolume(out,
          fromMs: fromMs,
          toMs: toMs,
          filter: 'bandpass=f=$hz:width_type=q:w=8,');
      // Near the start and at pause 300 of 320 (2 minutes in): A (1 kHz)
      // is heard in the first half of the period and silent in the
      // second, B (2 kHz) the other way round.
      for (final k in [2, 300]) {
        final t = k * 400;
        final aOpen = band(1000, t + 60, t + 140);
        final aShut = band(1000, t + 270, t + 330);
        final bShut = band(2000, t + 70, t + 130);
        final bOpen = band(2000, t + 260, t + 340);
        // ignore: avoid_print
        print('pause $k: A open $aOpen dB, shut $aShut dB; '
            'B shut $bShut dB, open $bOpen dB');
        expect(aShut, lessThan(aOpen - 15), reason: 'A at pause $k');
        expect(bShut, lessThan(bOpen - 15), reason: 'B at pause $k');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
