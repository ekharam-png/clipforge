// Real renders of processed sound (media/processed_sound.dart) and the
// export reading them (ExportOptions.processedSound), against the normal
// export chain. Skipped (with a message) when ffmpeg / ffprobe are not
// installed.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/processed_sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The sound of [path] as interleaved stereo float samples at 48 kHz.
Float32List pcm(String path) {
  final r = Process.runSync(
      'ffmpeg',
      ['-v', 'error', '-i', path, '-vn', '-ac', '2', '-ar', '48000', '-f', 'f32le', '-'],
      stdoutEncoding: null);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final bytes = Uint8List.fromList(r.stdout as List<int>);
  return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
}

double rms(Float32List x, int from, int to) {
  var s = 0.0;
  for (var i = from * 2; i < to * 2 && i < x.length; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / math.max(1, (to - from) * 2));
}

/// Level of (a - b) relative to a, in dB, over sample frames from..to.
double diffDb(Float32List a, Float32List b, int from, int to) {
  var s = 0.0, d = 0.0;
  for (var i = from * 2; i < to * 2 && i < a.length && i < b.length; i++) {
    s += a[i] * a[i];
    final e = a[i] - b[i];
    d += e * e;
  }
  return 10 * math.log(d / s) / math.ln10;
}

/// The shift of b against a (in samples, within +-max) where they match
/// best, over frames from..to.
int bestLag(Float32List a, Float32List b, int from, int to, {int max = 480}) {
  var best = 0;
  var bestScore = -double.infinity;
  for (var lag = -max; lag <= max; lag++) {
    var s = 0.0;
    for (var i = from; i < to; i += 2) {
      final j = i + lag;
      if (j < 0 || j * 2 >= b.length || i * 2 >= a.length) continue;
      s += a[i * 2] * b[j * 2];
    }
    if (s > bestScore) {
      bestScore = s;
      best = lag;
    }
  }
  return best;
}

void main() {
  if (!ffmpegOk) {
    test('integration tests need ffmpeg + ffprobe', () {},
        skip: 'ffmpeg/ffprobe not found on PATH');
    return;
  }

  setUpAll(() {
    setUpMedia();
    // 12 s: a "voice" (tone bursts, same on both sides) over wide-stereo
    // "music" and steady hiss, 16-bit PCM like a camera file.
    const voice = '(0.10*sin(2*PI*250*t)+0.08*sin(2*PI*500*t)'
        '+0.06*sin(2*PI*1000*t)+0.04*sin(2*PI*2500*t))'
        '*(0.6+0.4*sin(2*PI*3*t))*gt(sin(2*PI*0.4*t),-0.3)';
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=30:d=12',
      '-f', 'lavfi', '-i',
      "aevalsrc='$voice+0.06*sin(2*PI*330*t)|$voice+0.06*sin(2*PI*523*t)'"
          ':s=48000:d=12:c=stereo',
      '-f', 'lavfi', '-i', 'anoisesrc=r=48000:a=0.02:c=pink:d=12:seed=5',
      '-filter_complex', '[1:a][2:a]amix=inputs=2:normalize=0[a]',
      '-map', '0:v', '-map', '[a]',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
      '-c:a', 'pcm_s16le', '-t', '12', f('talk.mov'),
    ]);
  });
  tearDownAll(tearDownMedia);

  Clip talk(String id, int inMs, int outMs,
          {double speed = 1, bool denoise = true, double focus = 0.5}) =>
      Clip(
        id: id,
        type: ClipType.video,
        path: f('talk.mov'),
        sourceDurationMs: 12000,
        inMs: inMs,
        outMs: outMs,
        width: 320,
        height: 180,
        speed: speed,
        denoise: denoise,
        voiceFocus: focus,
        audioStreams: const [2],
      );

  late String processed;
  late Duration renderTime;

  test('renders the whole source file as 48 kHz stereo FLAC', () async {
    final clip = talk('a', 1000, 5000);
    processed = f('processed/${processedSoundFileName('test')}');
    final fractions = <double>[];
    final watch = Stopwatch()..start();
    final job = engine.renderClipSound(clip, processed);
    job.progress.listen((e) => fractions.add(e.fraction));
    expect(await job.done, processed);
    renderTime = watch.elapsed;
    expect(File('$processed.part').existsSync(), isFalse);
    final pr = ffprobe(processed);
    final a = pr.stream('audio')!;
    expect(a['codec_name'], 'flac');
    expect(a['sample_rate'], '48000');
    expect(a['channels'], 2);
    // Whole file, source timing.
    expect(pr.durationMs, closeTo(12000, 30));
    expect(fractions.last, 1);
    // ignore: avoid_print
    print('processed 12 s in ${renderTime.inMilliseconds} ms '
        '(${(renderTime.inMilliseconds / 12 * 60 / 1000).toStringAsFixed(2)} s '
        'per minute of sound)');
  });

  test('a cancelled render leaves no file', () async {
    final out = f('processed/cancelled.flac');
    final job = engine.renderClipSound(talk('c', 0, 12000), out);
    await job.cancel();
    await expectLater(job.done, throwsA(isA<ExportException>()));
    expect(File(out).existsSync(), isFalse);
    expect(File('$out.part').existsSync(), isFalse);
  });

  Future<void> compare(Project project, Map<String, String> files,
      {double? maxDiffDb = -20, int maxLag = 1}) async {
    final normal = await exportAndCheck(project);
    final reused = await exportAndCheck(project,
        options: ExportOptions(processedSound: files));
    final a = pcm(normal), b = pcm(reused);
    expect((b.length - a.length).abs(), lessThan(2 * 48 * 20),
        reason: 'same length within 20 ms');
    final n = math.min(a.length, b.length) ~/ 2;
    final la = 20 * math.log(rms(a, 0, n)) / math.ln10;
    final lb = 20 * math.log(rms(b, 0, n)) / math.ln10;
    // Sync: the two match best without any shift.
    final lag = bestLag(a, b, 48000, math.min(n, 48000 * 3));
    // Away from the first second (where the normal chain's clean-up starts
    // from nothing, while the processed file has the source before it).
    final d = diffDb(a, b, 48000, n);
    // ignore: avoid_print
    print('level normal ${la.toStringAsFixed(2)} dB, reused '
        '${lb.toStringAsFixed(2)} dB, lag $lag samples, '
        'difference ${d.toStringAsFixed(1)} dB');
    expect(lag.abs(), lessThanOrEqualTo(maxLag));
    expect((la - lb).abs(), lessThan(0.5));
    if (maxDiffDb != null) expect(d, lessThan(maxDiffDb));
  }

  test('export reading the processed file sounds like the normal chain',
      () async {
    final c = talk('a', 1000, 5000);
    await compare(proj([c]), {c.id: processed});
  });

  test('a run of pieces of one file shares one processed input', () async {
    final pieces = [
      talk('p1', 500, 3000),
      talk('p2', 3600, 6000),
      talk('p3', 6500, 11000),
    ];
    final files = {for (final c in pieces) c.id: processed};
    final cmd = buildExportCommand(
      project: proj(pieces),
      outputPath: f('x.mp4'),
      fonts: fonts,
      workDir: tmp.path,
      options: ExportOptions(processedSound: files),
    );
    // One input for the picture, one for the processed sound.
    expect(cmd.args.where((a) => a == '-i').length, 2);
    expect(cmd.args.where((a) => a == processed).length, 1);
    expect(cmd.filterGraph, isNot(contains('afftdn')));
    await compare(proj(pieces), files);
  });

  test('speed is applied after the processed file, as in the normal chain',
      () async {
    // atempo picks its overlap points from the blocks it is given, which
    // differ between the two inputs: the waveforms are not sample-identical
    // (so no difference measure), but level and timing are the same to
    // within 1 ms (measured: 30 samples).
    final c = talk('s', 1000, 9000, speed: 1.5);
    await compare(proj([c]), {c.id: processed}, maxDiffDb: null, maxLag: 48);
  });
}
