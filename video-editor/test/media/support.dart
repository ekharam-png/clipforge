// Shared by the integration tests: fixtures made with the system ffmpeg,
// probing, frame and loudness measurements.

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
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
final t0 = DateTime.utc(2026);

late Directory tmp;
late ProcessMediaEngine engine;
late FontPaths fonts;
var seq = 0;

String f(String name) => p.join(tmp.path, name);
String outPath() => p.join(tmp.path, 'out', 'export_${seq++}.mp4');

void ff(List<String> args) {
  final r = Process.runSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
  if (r.exitCode != 0) fail('fixture ffmpeg failed: ${r.stderr}');
}

class Probe {
  Probe(this.json);
  final Map json;
  List get streams => json['streams'] as List;
  Map? stream(String type) {
    for (final s in streams) {
      if ((s as Map)['codec_type'] == type) return s;
    }
    return null;
  }

  int get width => stream('video')!['width'] as int;
  int get height => stream('video')!['height'] as int;
  int get durationMs => (double.parse((json['format'] as Map)['duration'] as String) * 1000).round();
  int streamMs(String type) => (double.parse(stream(type)!['duration'] as String) * 1000).round();
}

Probe ffprobe(String path) {
  final r = Process.runSync('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path],
      stdoutEncoding: utf8);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return Probe(jsonDecode(r.stdout as String) as Map);
}

/// Decodes one frame as RGB24.
class Frame {
  Frame(this.w, this.h, this.rgb);
  final int w, h;
  final List<int> rgb;
  (int, int, int) at(int x, int y) {
    final i = (y * w + x) * 3;
    return (rgb[i], rgb[i + 1], rgb[i + 2]);
  }

  bool isBlack(int x, int y) {
    final (r, g, b) = at(x, y);
    return r < 24 && g < 24 && b < 24;
  }

  int countBright() {
    var n = 0;
    for (var i = 0; i < rgb.length; i += 3) {
      if (rgb[i] > 200 && rgb[i + 1] > 200 && rgb[i + 2] > 200) n++;
    }
    return n;
  }
}

/// Mean of the three channels over the whole frame, 0..255 each.
extension FrameStats on Frame {
  (double, double, double) mean({int x0 = 0, int y0 = 0, int? x1, int? y1}) {
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = y0; y < (y1 ?? h); y++) {
      for (var x = x0; x < (x1 ?? w); x++) {
        final i = (y * w + x) * 3;
        r += rgb[i];
        g += rgb[i + 1];
        b += rgb[i + 2];
        n++;
      }
    }
    return (r / n, g / n, b / n);
  }

  /// Mean brightness (Rec. 601 luma of the mean colour), 0..255.
  double luma({int x0 = 0, int y0 = 0, int? x1, int? y1}) {
    final (r, g, b) = mean(x0: x0, y0: y0, x1: x1, y1: y1);
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  /// Mean colourfulness: average of max(R,G,B) - min(R,G,B) per pixel.
  double chroma() {
    var s = 0;
    for (var i = 0; i < rgb.length; i += 3) {
      final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      s += mx - mn;
    }
    return s / (rgb.length / 3);
  }
}

/// Number of video frames in [path] (decoded and counted).
int countFrames(String path) {
  final r = Process.runSync('ffprobe', [
    '-v', 'error', '-count_frames', '-select_streams', 'v:0',
    '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', path
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return int.parse((r.stdout as String).trim().split(',').first);
}

Frame frameAt(String path, int ms, int w, int h) {
  final r = Process.runSync(
      'ffmpeg',
      ['-v', 'error', '-ss', ffSeconds(ms), '-i', path, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
      stdoutEncoding: null);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final bytes = r.stdout as List<int>;
  expect(bytes.length, w * h * 3);
  return Frame(w, h, bytes);
}

/// Mean volume in dB of [path] between [fromMs] and [toMs].
///
/// [filter] (e.g. a band-pass, ending with a comma) is applied first.
double meanVolume(String path, {int fromMs = 0, int? toMs, String filter = ''}) {
  final r = Process.runSync(
      'ffmpeg',
      [
        '-hide_banner', '-nostats', '-ss', ffSeconds(fromMs),
        if (toMs != null) ...['-t', ffSeconds(toMs - fromMs)],
        '-i', path, '-vn', '-af', '${filter}volumedetect', '-f', 'null', '-'
      ],
      stderrEncoding: utf8);
  final m = RegExp(r'mean_volume: (-?[\d.]+|-inf) dB').firstMatch(r.stderr as String);
  expect(m, isNotNull, reason: r.stderr as String);
  return m!.group(1) == '-inf' ? -200 : double.parse(m.group(1)!);
}

Clip clip(String file, int w, int h,
        {int inMs = 0,
        int outMs = 1000,
        bool hasAudio = true,
        bool muted = false,
        double volume = 1,
        FitMode fit = FitMode.fit,
        ClipType type = ClipType.video}) =>
    Clip(
        id: '$file-${seq++}',
        type: type,
        path: f(file),
        sourceDurationMs: type == ClipType.photo ? 0 : 2000,
        inMs: inMs,
        outMs: outMs,
        width: w,
        height: h,
        hasAudio: hasAudio,
        muted: muted,
        volume: volume,
        fit: fit);

Clip land({int inMs = 0, int outMs = 1000, FitMode fit = FitMode.fit, bool muted = false, double volume = 1}) =>
    clip('land.mp4', 640, 360, inMs: inMs, outMs: outMs, fit: fit, muted: muted, volume: volume);
Clip port({int inMs = 0, int outMs = 1000, FitMode fit = FitMode.fit}) =>
    clip('port.mp4', 360, 640, inMs: inMs, outMs: outMs, fit: fit, hasAudio: false);
Clip photo({int ms = 800, FitMode fit = FitMode.fit, String file = 'photo.png', int w = 400, int h = 300}) =>
    clip(file, w, h, outMs: ms, fit: fit, hasAudio: false, type: ClipType.photo);
Clip rot({int outMs = 1000, FitMode fit = FitMode.fit}) => clip('rot.mp4', 360, 640, outMs: outMs, fit: fit);

Project proj(List<Clip> clips,
        {CanvasAspect aspect = CanvasAspect.original,
        List<AudioClip> audio = const [],
        List<TitleOverlay> titles = const [],
        bool duckMusic = false}) =>
    Project(
        id: 'p',
        name: 'n',
        createdAt: t0,
        updatedAt: t0,
        aspect: aspect,
        clips: clips,
        audio: audio,
        titles: titles,
        duckMusic: duckMusic);

/// Exports and checks the basics every export must satisfy.
Future<String> exportAndCheck(Project project,
    {ExportOptions options = const ExportOptions(), ProcessMediaEngine? using, int? width, int? height}) async {
  final out = outPath();
  final result = await (using ?? engine).export(project, out, options: options).done;
  expect(result, out);
  expect(File(out).existsSync(), isTrue);
  final pr = ffprobe(out);
  final size = exportSize(project, options.quality);
  expect(pr.width, width ?? size.width);
  expect(pr.height, height ?? size.height);
  expect(pr.stream('video')!['codec_name'], 'h264');
  expect(pr.stream('video')!['pix_fmt'], 'yuv420p');
  // Limited range: 'tv', or absent when x264 writes no colour description
  // (which means limited). A full-range export also shows as yuvj420p above.
  expect(pr.stream('video')!['color_range'], isNot('pc'));
  expect(pr.stream('audio')!['codec_name'], 'aac');
  expect(pr.stream('audio')!['sample_rate'], '48000');
  expect(pr.stream('audio')!['channels'], 2);
  expect(pr.durationMs, closeTo(project.durationMs, 150));
  expect(pr.streamMs('video'), closeTo(project.durationMs, 150));
  expect(pr.streamMs('audio'), closeTo(project.durationMs, 150));
  return out;
}

/// Creates the temp dir, the engine and the basic fixtures. Call from
/// setUpAll; pair with [tearDownMedia].
void setUpMedia() {
    tmp = Directory.systemTemp.createTempSync('clipforge_test_');
    final root = Directory.current.path;
    fonts = FontPaths(
        regular: p.join(root, 'assets', 'fonts', 'DejaVuSans.ttf'),
        bold: p.join(root, 'assets', 'fonts', 'DejaVuSans-Bold.ttf'));
    expect(File(fonts.regular).existsSync(), isTrue);
    expect(File(fonts.bold).existsSync(), isTrue);
    engine = ProcessMediaEngine(
        ffmpegPath: 'ffmpeg',
        ffprobePath: 'ffprobe',
        fontResolver: () async => fonts,
        thumbnailDir: Directory(f('thumbs')),
        preset: 'ultrafast');

    const x264 = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // Landscape clip with a tone.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=2',
      '-f', 'lavfi', '-i', 'sine=f=440:r=44100:d=2',
      ...x264, '-c:a', 'aac', '-shortest', f('land.mp4')
    ]);
    // Portrait clip without audio, 25 fps.
    ff(['-f', 'lavfi', '-i', 'testsrc=s=360x640:r=25:d=2', ...x264, f('port.mp4')]);
    // Photos.
    ff(['-f', 'lavfi', '-i', 'smptebars=s=400x300', '-frames:v', '1', f('photo.png')]);
    ff(['-f', 'lavfi', '-i', 'color=c=black:s=640x360', '-frames:v', '1', f('black.png')]);
    ff(['-f', 'lavfi', '-i', 'testsrc=s=1620x1080', '-frames:v', '1', '-q:v', '3', f('big.jpg')]);
    // Music.
    ff(['-f', 'lavfi', '-i', 'sine=f=880:r=44100:d=4', '-c:a', 'aac', f('music.m4a')]);
    // Coded 640x360 with a 90 degree rotation => displayed as 360x640.
    ff(['-display_rotation', '90', '-i', f('land.mp4'), '-c', 'copy', f('rot.mp4')]);
    // Odd dimensions.
    ff([
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=1', '-vf', 'scale=641:361',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv444p', f('odd.mp4')
    ]);
}

void tearDownMedia() {
  try {
    tmp.deleteSync(recursive: true);
  } catch (_) {}
}
