// Pure Dart: turns a Project into an ffmpeg argument list. No dart:io, no
// Flutter — everything here is unit-testable without ffmpeg installed and
// usable from a plain `dart` program (e.g. a command-line tool).
//
// The produced arguments do NOT include the program name nor runner-specific
// flags (-progress, -nostdin ...); the engines add those.
//
// Everything used here exists with the same spelling in FFmpeg 6.1 and 8.x.

import 'dart:math' as math;

import '../core/model/look_filter.dart';
import '../core/model/picture_layout.dart';
import '../core/model/project.dart';
import '../core/model/title_layout.dart';
import 'clip_audio.dart';
import 'media_api.dart';
import 'sound_filters.dart' show SoundStage;
import 'video_encoder.dart';

export 'clip_audio.dart';

/// Font files used by drawtext. Plain file-system paths.
///
/// [regular] and [bold] are DejaVu Sans ([TitleFont.classic]); [files]
/// holds the other title fonts by file name ([titleFontFileName]). A font
/// that is not there is drawn in DejaVu Sans instead.
class FontPaths {
  const FontPaths(
      {required this.regular, required this.bold, this.files = const {}});
  final String regular;
  final String bold;

  /// Full paths of the other bundled title fonts, by file name
  /// ("Rubik-Bold.ttf" -> "/…/Rubik-Bold.ttf").
  final Map<String, String> files;

  /// The file drawtext uses for [font] (bold cut when [bold]).
  String pathFor(TitleFont font, bool bold) {
    if (font != TitleFont.classic) {
      final p = files[titleFontFileName(font, bold)];
      if (p != null && p.isNotEmpty) return p;
    }
    return bold ? this.bold : regular;
  }
}

/// Supplies the drawtext fonts when an export starts.
typedef FontResolver = Future<FontPaths> Function();

/// Result of [buildExportCommand].
class FfmpegCommand {
  const FfmpegCommand({
    required this.args,
    required this.textFiles,
    required this.filterGraph,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  /// Arguments for ffmpeg (without the executable name).
  final List<String> args;

  /// Files (path -> UTF-8 content) that must exist before ffmpeg starts.
  /// They hold the title texts, referenced via drawtext `textfile=`.
  final Map<String, String> textFiles;

  /// The -filter_complex value (also contained in [args]).
  final String filterGraph;

  /// Output size in pixels.
  final int width;
  final int height;

  /// Expected output duration (main track length, transitions overlapped):
  /// the same number as [Project.durationMs].
  final int durationMs;

  /// True when [filterGraph] is too long to be handed over as an argument
  /// (see [kMaxInlineGraphChars]); use [argsWithGraphFile] then.
  bool get needsGraphFile => filterGraph.length > kMaxInlineGraphChars;

  /// [args] with the filter graph read from the file [graphPath] (which the
  /// caller writes: [filterGraph], UTF-8, no trailing newline) instead of
  /// being an argument. [option] is the spelling the ffmpeg in use
  /// understands, see [graphFileOption].
  List<String> argsWithGraphFile(String graphPath, String option) {
    final i = args.indexOf('-filter_complex');
    return [...args.sublist(0, i), option, graphPath, ...args.sublist(i + 2)];
  }
}

/// Longest filter graph passed as a `-filter_complex` argument. Operating
/// systems limit arguments (Linux: 131072 bytes for one argument, Windows:
/// 32767 characters for the whole command line), and a project of a few
/// hundred clips that cannot share inputs goes beyond that. Longer graphs
/// are passed in a file; projects of ordinary size are not affected.
const int kMaxInlineGraphChars = 30000;

/// Major version from `ffmpeg -version` output ("ffmpeg version 6.1.1-3ubuntu5
/// ...", "ffmpeg version n8.0.1 ...") or from a bare version ("8.1",
/// "n7.1.1"). Null for development builds ("N-118193-g5f38c82536") and
/// anything else without a release number.
int? ffmpegMajorVersion(String versionText) {
  var t = versionText.trimLeft();
  final m = RegExp(r'^ffmpeg\s+version\s+', caseSensitive: false).firstMatch(t);
  if (m != null) t = t.substring(m.end);
  final v = RegExp(r'^[nNvV]?(\d+)\.\d').firstMatch(t);
  return v == null ? null : int.tryParse(v.group(1)!);
}

/// The option that makes ffmpeg read the complex filter graph from a file.
///
/// FFmpeg 7.0 introduced `-/option file` ("take the value of the option
/// from the file") and deprecated `-filter_complex_script file`, which
/// later releases no longer have; FFmpeg up to 6.1 only knows the latter.
/// No spelling works everywhere, so it depends on [major]
/// ([ffmpegMajorVersion]); unknown (a development build) counts as new.
String graphFileOption(int? major) =>
    major != null && major < 7 ? '-filter_complex_script' : '-/filter_complex';

const int kAudioSampleRate = 48000;

// ---- colour adjustments ----------------------------------------------------

/// How [Clip.brightness], [Clip.contrast] and [Clip.saturation] (each
/// -1..1, clamped) become options of ffmpeg's `eq` filter:
///
///     eq brightness = [kEqBrightnessGain] * brightness     (-0.2 .. 0.2)
///     eq contrast   = 1 + [kEqContrastGain] * contrast     ( 0.5 .. 1.5)
///     eq saturation = 1 + saturation                       ( 0 .. 2)
///
/// `eq` works on the 8-bit limited-range Y'CbCr picture (Y' 16..235, chroma
/// centred on 128), plane by plane, results clipped to 0..255:
///
///     Y'  = contrast * (Y - 128) + 128 + 255 * brightness
///     Cb' = saturation * (Cb - 128) + 128        (same for Cr)
///
/// The same look as a colour matrix on full-range R'G'B' values in 0..1
/// (for a preview), with k = eq contrast, b = eq brightness, s = eq
/// saturation and L = luma of the pixel (0.2126 R + 0.7152 G + 0.0722 B;
/// 0.299 / 0.587 / 0.114 for SD sources):
///
///     offset = (1 - k) * 0.511 + 1.164 * b
///     R' = s * R + (k - s) * L + offset          (same for G and B)
///
/// (0.511 = (128 - 16) / 219 is where the contrast pivot sits, and
/// 1.164 = 255 / 219 converts the brightness step to full range.)
/// So saturation -1 is black and white, +1 doubles the colourfulness;
/// brightness +-1 moves the picture by about +-23 % of the full scale.
const double kEqBrightnessGain = 0.2;
const double kEqContrastGain = 0.5;

/// The `eq` options for [clip] following the mapping documented at
/// [kEqBrightnessGain].
({double brightness, double contrast, double saturation}) eqValues(Clip clip) {
  double unit(double v) => v.isNaN ? 0 : (v < -1 ? -1 : (v > 1 ? 1 : v));
  return (
    brightness: kEqBrightnessGain * unit(clip.brightness),
    contrast: 1 + kEqContrastGain * unit(clip.contrast),
    saturation: 1 + unit(clip.saturation),
  );
}

/// The `eq=...` filter for [clip], or null when it has no colour
/// adjustment.
String? eqFilter(Clip clip) {
  final v = eqValues(clip);
  if (v.brightness.abs() < 0.0005 &&
      (v.contrast - 1).abs() < 0.0005 &&
      (v.saturation - 1).abs() < 0.0005) {
    return null;
  }
  return 'eq=brightness=${_num(v.brightness)}'
      ':contrast=${_num(v.contrast)}'
      ':saturation=${_num(v.saturation)}';
}

/// The filters of [clip]'s colour look ([Clip.filter], [Clip.warmth]) as a
/// colour matrix on RGB (see core/model/look_filter.dart), each preceded
/// by a comma; empty when it has none. The picture goes to RGB with alpha
/// (the alpha channel, always opaque, carries the offsets), through
/// `colorchannelmixer`, and back to 8-bit 4:2:0 limited range.
String lookFilterFilters(Clip clip) {
  final m = clipLookMatrix(clip);
  if (m == null) return '';
  String row(String c, int r) =>
      '${c}r=${_num(m[r * 4], 4)}:${c}g=${_num(m[r * 4 + 1], 4)}'
      ':${c}b=${_num(m[r * 4 + 2], 4)}:${c}a=${_num(m[r * 4 + 3], 4)}';
  return ',format=gbrap,colorchannelmixer=${row('r', 0)}:${row('g', 1)}'
      ':${row('b', 2)},scale=out_range=tv,format=yuv420p';
}

// ---- crop and position -----------------------------------------------------

/// The filters that turn, mirror and crop a picture as [f] says (see
/// [Framing]), each followed by a comma; empty for none of that. Turning
/// comes first (`transpose`), then mirroring, then the crop, which is
/// worked out from the size of the frames it gets and kept to even sizes.
String framingFilters(Framing f) {
  final sb = StringBuffer();
  var h = f.flipH;
  var v = f.flipV;
  switch (Framing.normalizeRotation(f.rotation)) {
    case 90:
      sb.write('transpose=clock,');
    case 270:
      sb.write('transpose=cclock,');
    case 180:
      h = !h;
      v = !v;
  }
  if (h) sb.write('hflip,');
  if (v) sb.write('vflip,');
  final c = f.crop.clamped();
  if (!c.isFull) {
    sb.write('crop=w=trunc(iw*${_num(c.width, 6)}/2)*2'
        ':h=trunc(ih*${_num(c.height, 6)}/2)*2'
        ':x=trunc(iw*${_num(c.x, 6)}):y=trunc(ih*${_num(c.y, 6)}),');
  }
  return sb.toString();
}

/// `:x=...:y=...` for a `crop` that keeps the part chosen by [f]'s pan
/// (-1 left / top edge, 0 middle, 1 right / bottom edge); empty when
/// centred (crop's own default).
String _panXY(Framing f) {
  double k(double v) =>
      (1 + (v.isNaN ? 0 : (v < -1 ? -1 : (v > 1 ? 1 : v)))) / 2;
  if (f.panX.abs() < 1e-6 && f.panY.abs() < 1e-6) return '';
  return ':x=(iw-ow)*${_num(k(f.panX), 4)}:y=(ih-oh)*${_num(k(f.panY), 4)}';
}

// ---- speed -----------------------------------------------------------------

/// Speed of [clip] as used by the export: 1 for photos and unusable values.
double effectiveSpeed(Clip clip) {
  final s = clip.speed;
  if (clip.type == ClipType.photo || s.isNaN || s.isInfinite || s <= 0) {
    return 1;
  }
  return (s - 1).abs() < 0.0005 ? 1 : s;
}

/// Tempo factors, each within 0.5..2, whose product is [speed]. `atempo`
/// only keeps its full quality in that range (and older FFmpeg versions
/// accept nothing else), so e.g. 4x is two 2x stages. Empty for speed 1.
List<double> atempoStages(double speed) {
  if (speed.isNaN || speed.isInfinite || speed <= 0) return const [];
  if ((speed - 1).abs() < 0.0005) return const [];
  final out = <double>[];
  var s = speed;
  while (s > 2.0 + 1e-9 && out.length < 8) {
    out.add(2);
    s /= 2;
  }
  while (s < 0.5 - 1e-9 && out.length < 8) {
    out.add(0.5);
    s /= 0.5;
  }
  if ((s - 1).abs() > 1e-9) out.add(s);
  return out;
}

// ---- music ducking ---------------------------------------------------------

/// [Project.duckMusic]: the mixed music is compressed with the main track's
/// sound as side chain.
///
///  * threshold 0.012 (-38 dBFS, RMS detection): room tone does not
///    trigger it, speech does; digital silence (muted clips, photos) never.
///  * ratio 12 with mix 0.78: the music is pulled down firmly but, because
///    22 % of it always passes uncompressed, by no more than about 13 dB
///    (typically 9 dB under normal speech, 3 dB under very quiet speech).
///  * attack 30 ms, release 400 ms: down within the first syllable, back
///    to full level roughly 0.3..0.6 s after the speech stops.
const String kDuckFilter = 'sidechaincompress='
    'threshold=0.012:ratio=12:attack=30:release=400:mix=0.78';

// ---- transitions -----------------------------------------------------------

/// Name of the `xfade` transition for [t], or null for a hard cut.
String? xfadeName(TransitionType t) => switch (t) {
      TransitionType.none => null,
      TransitionType.crossfade => 'fade',
      TransitionType.fadeBlack => 'fadeblack',
      TransitionType.slideLeft => 'slideleft',
      TransitionType.slideUp => 'slideup',
    };

/// Where a clip sits on the output, in whole frames.
class ClipFrames {
  const ClipFrames({
    required this.clipIndex,
    required this.start,
    required this.frames,
    required this.overlapIn,
    required this.overlapOut,
  });

  /// Index into [Project.clips].
  final int clipIndex;

  /// Output frame where the clip starts (start of its transition, if any).
  final int start;

  /// Length of the clip.
  final int frames;

  /// Frames shared with the previous / next clip (transition length).
  final int overlapIn;
  final int overlapOut;

  int get end => start + frames;
}

/// Places the clips of [project] on a grid of [fps] frames per second.
///
/// Clip starts and ends are the model's times ([Project.clipStartMs],
/// [Project.transitionOverlapMs]) rounded to the nearest frame, so rounding
/// never adds up along the timeline and the total is [Project.durationMs]
/// to within half a frame. Clips without a positive duration are left out.
({List<ClipFrames> clips, int totalFrames, int totalMs}) layoutTimeline(
    Project project, int fps) {
  int frameOf(int ms) => (ms * fps / 1000).round();
  final out = <ClipFrames>[];
  var tMs = 0;
  var prevEnd = 0;
  var prevFree = 0; // frames of the previous clip not used by its fade-in
  for (var i = 0; i < project.clips.length; i++) {
    final c = project.clips[i];
    if (c.durationMs <= 0) continue;
    var overlapMs = out.isEmpty ? 0 : project.transitionOverlapMs(i);
    // An overlap is only meaningful with the clip right before this one.
    if (overlapMs < 0 || (out.isNotEmpty && out.last.clipIndex != i - 1)) {
      overlapMs = 0;
    }
    if (xfadeName(c.transition) == null) overlapMs = 0;
    final startMs = tMs - overlapMs;
    final endMs = startMs + c.durationMs;
    tMs = endMs;

    var start = overlapMs > 0 ? frameOf(startMs) : prevEnd;
    var overlap = prevEnd - start;
    if (overlap > prevFree) overlap = prevFree;
    if (overlap < 0) overlap = 0;
    start = prevEnd - overlap;
    var end = frameOf(endMs);
    if (end < start + 1) end = start + 1;
    if (end < start + overlap) end = start + overlap;
    final frames = end - start;
    if (overlap > 0) {
      final p = out.removeLast();
      out.add(ClipFrames(
          clipIndex: p.clipIndex,
          start: p.start,
          frames: p.frames,
          overlapIn: p.overlapIn,
          overlapOut: overlap));
    }
    out.add(ClipFrames(
        clipIndex: i,
        start: start,
        frames: frames,
        overlapIn: overlap,
        overlapOut: 0));
    prevEnd = end;
    prevFree = frames - overlap;
  }
  return (clips: out, totalFrames: prevEnd, totalMs: tMs);
}

// ---- many pieces of one file ----------------------------------------------

/// Most pieces one input may supply (keeps the `select` expression, which
/// is evaluated for every decoded frame, short).
const int kMaxRunPieces = 200;

/// Longest stretch of unused source between two pieces of a run. A longer
/// gap is cheaper to skip by seeking (a new input) than to decode.
const int kMaxRunGapMs = 10000;

/// Consecutive clips that are pieces of ONE source file (what "Remove
/// silences" leaves behind) and can be produced from a single ffmpeg input.
///
/// Why: every input is a demuxer plus a decoder with its frame buffers.
/// 100 pieces as 100 inputs of a 1280x720 file needed 3.6 GB of memory
/// (FFmpeg 6.1); as one input it takes about as much as a single clip.
///
/// The source is decoded once from the first piece's start, put on a frame
/// grid ([gridFps]); `select` keeps the frames of the pieces and the sound
/// is cut at the same frame numbers, counted in samples (one `atrim` per
/// piece; see [buildExportCommand] for why not `aselect`), so picture and
/// sound cannot drift apart.
///
/// At normal speed the grid is the export frame rate and every piece has
/// exactly its [ClipFrames.frames] frames. With a [speed] (the same for all
/// pieces) the selected pieces are sped up ONCE, as one stream (`setpts` +
/// `fps`, `atempo`); the run as a whole is then held or cut to [frames], the
/// total [layoutTimeline] gives its pieces, while a cut inside the run may
/// fall up to a frame away from where the timeline has it.
class ClipRun {
  const ClipRun({
    required this.first,
    required this.last,
    required this.frames,
    required this.sourceFrames,
    required this.ranges,
    this.speed = 1,
    required this.gridFps,
  });

  /// Speed of every piece (see [effectiveSpeed]).
  final double speed;

  /// Frame rate of the grid the pieces are cut on: the export rate, or a
  /// multiple of it for slow motion (2x for 0.5, 4x for 0.25) so that the
  /// in-between pictures of the source are not lost before it is slowed.
  final int gridFps;

  /// First and last member, as indices into the placed clips of
  /// [layoutTimeline].
  final int first;
  final int last;

  /// Output frames of the whole run.
  final int frames;

  /// Frames to decode, counted from the first piece's start at [gridFps].
  final int sourceFrames;

  /// Frame ranges kept (start inclusive, end exclusive), counted like
  /// [sourceFrames]; one per piece, ascending and not overlapping.
  final List<({int start, int end})> ranges;

  /// The `select` expression of the picture.
  String get expression =>
      [for (final r in ranges) 'between(n,${r.start},${r.end - 1})'].join('+');
}

/// Finds the [ClipRun]s of [project]: two or more neighbours on the
/// timeline that
///
///  * are video clips of the same file with the same settings (fit, zoom,
///    colour, volume, mute, sound source, clean audio, voice focus, speed),
///  * are joined by hard cuts (no transition into, inside or out of the run),
///  * follow each other in the source without overlapping, at most
///    [kMaxRunGapMs] apart.
///
/// Everything else keeps one input per clip. Runs need a grid frame rate
/// ([ClipRun.gridFps]) that divides the audio sample rate (24, 25, 30, 50,
/// 60 ... do).
///
/// [processedSound] ([ExportOptions.processedSound]): pieces of a run also
/// share their processed sound file (or all have none); the run then reads
/// its sound from that one file, again as one input.
List<ClipRun> findClipRuns(Project project, List<ClipFrames> placed, int fps,
    {Map<String, String> processedSound = const {}}) {
  final out = <ClipRun>[];
  if (fps <= 0 || kAudioSampleRate % fps != 0) return out;
  bool eligible(int i) {
    final pl = placed[i];
    final c = project.clips[pl.clipIndex];
    return c.type == ClipType.video &&
        pl.overlapIn == 0 &&
        pl.overlapOut == 0 &&
        c.fadeInMs <= 0 &&
        c.fadeOutMs <= 0 &&
        c.inMs >= 0;
  }

  bool sameSettings(Clip a, Clip b) =>
      a.path == b.path &&
      a.width == b.width &&
      a.height == b.height &&
      a.hasAudio == b.hasAudio &&
      a.muted == b.muted &&
      a.volume == b.volume &&
      a.fit == b.fit &&
      a.denoise == b.denoise &&
      voiceFocusOf(a) == voiceFocusOf(b) &&
      a.audioTrackInUse == b.audioTrackInUse &&
      a.audioChannelInUse == b.audioChannelInUse &&
      a.brightness == b.brightness &&
      a.contrast == b.contrast &&
      a.saturation == b.saturation &&
      a.zoom == b.zoom &&
      a.filter == b.filter &&
      a.warmth == b.warmth &&
      a.framing == b.framing &&
      effectiveSpeed(a) == effectiveSpeed(b) &&
      processedSound[a.id] == processedSound[b.id];

  var i = 0;
  while (i < placed.length) {
    if (!eligible(i)) {
      i++;
      continue;
    }
    final base = project.clips[placed[i].clipIndex];
    final speed = effectiveSpeed(base);
    final grid = fps * (speed >= 1 ? 1 : (1 / speed).ceil().clamp(1, 4));
    if (kAudioSampleRate % grid != 0) {
      i++;
      continue;
    }
    // Frames a piece takes on the grid: at normal speed exactly its frames
    // on the timeline, otherwise its source range.
    int length(int k) {
      if (speed == 1) return placed[k].frames;
      final n = (project.clips[placed[k].clipIndex].sourceSpanMs * grid / 1000).round();
      return n < 1 ? 1 : n;
    }

    final ranges = [(start: 0, end: length(i))];
    var frames = placed[i].frames;
    var prev = base;
    var j = i + 1;
    while (j < placed.length && ranges.length < kMaxRunPieces && eligible(j)) {
      final c = project.clips[placed[j].clipIndex];
      if (!sameSettings(base, c)) break;
      if (c.inMs < prev.outMs || c.inMs - prev.outMs > kMaxRunGapMs) break;
      final start = ((c.inMs - base.inMs) * grid / 1000).round();
      if (start < ranges.last.end) break;
      ranges.add((start: start, end: start + length(j)));
      frames += placed[j].frames;
      prev = c;
      j++;
    }
    if (ranges.length > 1) {
      out.add(ClipRun(
        first: i,
        last: j - 1,
        frames: frames,
        sourceFrames: ranges.last.end,
        ranges: ranges,
        speed: speed,
        gridFps: grid,
      ));
    }
    i = j;
  }
  return out;
}

/// Output size for [project] at [quality]. Always even.
({int width, int height}) exportSize(Project project, ExportQuality quality) {
  final c = project.canvasSize;
  var w = c.width < 2 ? 2 : c.width;
  var h = c.height < 2 ? 2 : c.height;
  if (quality == ExportQuality.small) {
    final shortSide = w < h ? w : h;
    if (shortSide > 720) {
      final k = 720 / shortSide;
      // 1278 x 720 becomes 1280 x 720 (Project.snapToWide).
      final snapped = Project.snapToWide(_even(w * k), _even(h * k));
      w = snapped.width;
      h = snapped.height;
    }
  }
  return (width: _even(w), height: _even(h));
}

int _even(num v) {
  final r = (v / 2).round() * 2;
  return r < 2 ? 2 : r;
}

int _evenUp(num v) {
  final r = (v / 2).ceil() * 2;
  return r < 2 ? 2 : r;
}

/// Seconds with millisecond precision, e.g. 1500 -> "1.500".
String ffSeconds(int ms) {
  final neg = ms < 0;
  final a = ms.abs();
  return '${neg ? '-' : ''}${a ~/ 1000}.${(a % 1000).toString().padLeft(3, '0')}';
}

/// [frames] at [fps] as seconds with microsecond precision ("0.500000").
String _frameSeconds(int frames, int fps) {
  final us = (frames * 1000000 / fps).round();
  return '${us ~/ 1000000}.${(us % 1000000).toString().padLeft(6, '0')}';
}

String _num(double v, [int digits = 3]) {
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// Escapes [value] so that it can be used as an option value of a filter
/// inside a -filter_complex graph (`name=opt=<here>:opt2=...`).
///
/// Two parsing levels have to be survived: the filter's own option parser
/// (special: `\`, `'`, `:`) and then the graph parser (special: `\`, `'`,
/// `[`, `]`, `,`, `;`). Whitespace is escaped too because both parsers trim
/// unescaped leading/trailing blanks.
String escapeFilterValue(String value) {
  final l1 = StringBuffer();
  for (final r in value.runes) {
    final ch = String.fromCharCode(r);
    if (ch == r'\' || ch == "'" || ch == ':') l1.write(r'\');
    l1.write(ch);
  }
  final l2 = StringBuffer();
  for (final r in l1.toString().runes) {
    final ch = String.fromCharCode(r);
    if (ch == r'\' ||
        ch == "'" ||
        ch == '[' ||
        ch == ']' ||
        ch == ',' ||
        ch == ';' ||
        ch == ' ' ||
        ch == '\t') {
      l2.write(r'\');
    }
    l2.write(ch);
  }
  return l2.toString();
}

/// File path as a filter option value. Windows backslashes become forward
/// slashes (ffmpeg accepts both) so only the drive colon needs escaping.
String escapeFilterPath(String path) =>
    escapeFilterValue(path.replaceAll(r'\', '/'));

String _joinPath(String dir, String name) {
  if (dir.isEmpty) return name;
  final last = dir[dir.length - 1];
  return (last == '/' || last == r'\') ? '$dir$name' : '$dir/$name';
}

/// drawtext colour from 0xAARRGGBB.
String ffColor(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = ((argb >> 24) & 0xFF) / 255.0;
  return '0x$rgb@${_num(a)}';
}

/// Opacity of the black box behind a title with [TitleOverlay.background].
const String kTitleBoxOpacity = '0.55';

/// True when exporting [project] draws text, i.e. needs [FontPaths].
bool projectNeedsFonts(Project project) => project.titles
    .any((t) => t.text.trim().isNotEmpty && t.endMs > t.startMs && t.fontSize > 0);

/// Builds the complete export command.
///
/// [workDir] is a directory (it does not need to exist yet) where the title
/// text files listed in [FfmpegCommand.textFiles] will be written by the
/// caller.
///
/// Shape of the filter graph:
///
///  * every clip becomes a picture chain (speed, fps, fit, colour, zoom) of
///    an exact number of frames and a sound chain (clean-up, tempo, volume)
///    of exactly the matching number of samples, see [layoutTimeline];
///  * neighbouring pieces of one source file (hard cuts, same settings) share
///    ONE input and one pair of chains, see [ClipRun];
///  * a photo is decoded once and held for its length;
///  * where two clips share a transition, the last frames of the first and
///    the first frames of the second are split off, blended with `xfade`
///    (sound: `acrossfade`) and the result takes their place;
///  * all pieces are joined by one `concat`, so hard cuts stay hard cuts
///    and the length is frame exact;
///  * titles are drawn on the joined picture, music is mixed (optionally
///    ducked) into the joined sound.
FfmpegCommand buildExportCommand({
  required Project project,
  required String outputPath,
  required FontPaths fonts,
  required String workDir,
  ExportOptions options = const ExportOptions(),
  String preset = 'veryfast',
  VideoEncoder encoder = VideoEncoder.libx264,
  EncoderPlatform encoderPlatform = EncoderPlatform.other,
  Set<SoundStage> leaveOut = const {},
}) {
  final fps = options.fps < 1 ? 30 : (options.fps > 120 ? 120 : options.fps);
  // Sound only: the same sound graph, without any picture (no picture
  // inputs, chains, overlays or titles).
  final audioOnly = options.format.audioOnly;
  final timeline = layoutTimeline(project, fps);
  final placed = timeline.clips;
  if (placed.isEmpty) {
    throw ExportException('Nothing to export: the project has no clips.');
  }
  for (final pl in placed) {
    final c = project.clips[pl.clipIndex];
    if (c.inMs < 0) {
      throw ExportException('Clip ${c.id} has a negative start (${c.inMs}).');
    }
  }
  final totalMs = timeline.totalMs;
  final size = exportSize(project, options.quality);
  final w = size.width;
  final h = size.height;
  int samplesAt(int frame) => (frame * kAudioSampleRate / fps).round();

  final inputs = <String>[];
  final chains = <String>[];
  var inputCount = 0;

  // ---- main track -------------------------------------------------------
  final concatPads = StringBuffer();
  var segments = 0;
  final processedSound = options.processedSound;
  final runs = {
    for (final r in findClipRuns(project, placed, fps,
        processedSound: processedSound))
      r.first: r
  };
  for (var i = 0; i < placed.length; i++) {
    final pl = placed[i];
    final c = project.clips[pl.clipIndex];
    // A run of pieces of one file is handled like one clip of all their
    // frames (labels carry the index of its first piece); see [ClipRun].
    final run = runs[i];
    final n = run?.frames ?? pl.frames;
    final speed = effectiveSpeed(c);
    final silent = c.type == ClipType.photo || !c.hasAudio || c.muted || c.volume <= 0;
    // A ready processed sound file (media/processed_sound.dart) holds the
    // whole source file with stages 1..3 done, at source timing: it is
    // read over the same source range as the picture, as its own input,
    // and only speed and volume follow.
    final processed = silent ? null : processedSound[c.id];
    // Sound only: the clip's file is read only for its sound (-vn), and
    // not at all when the clip is silent or its sound comes from a
    // processed file.
    final mainInput = !audioOnly || (!silent && processed == null);
    final idx = mainInput ? inputCount++ : -1;
    final noVideo = audioOnly ? const ['-vn'] : const <String>[];
    if (!mainInput) {
      // Nothing to read.
    } else if (run != null) {
      // Half a second more than needed: the range is cut to the frame in
      // the graph.
      final spanMs = (run.sourceFrames * 1000 / run.gridFps).ceil() + 500;
      inputs.addAll([
        '-ss', ffSeconds(c.inMs), '-t', ffSeconds(spanMs),
        ...noVideo,
        '-i', c.path,
      ]);
    } else if (c.type == ClipType.photo) {
      // ONE decoded picture; the graph holds it for the clip's length
      // (tpad below). Looping the input instead (-loop 1) decodes and
      // scales the file again for every output frame, which for a 12
      // megapixel photo took longer than real time.
      inputs.addAll(['-framerate', '$fps', '-i', c.path]);
    } else {
      // The trimmed SOURCE range; speed is applied in the graph.
      inputs.addAll([
        '-ss', ffSeconds(c.inMs), '-t', ffSeconds(c.sourceSpanMs),
        ...noVideo,
        '-i', c.path,
      ]);
    }

    // Pieces of this clip: frames shared with the previous clip (head),
    // with the next one (tail), and what is shown alone (body).
    final head = pl.overlapIn;
    final tail = pl.overlapOut;
    final body = n - head - tail;
    final pieces = (head > 0 ? 1 : 0) + (body > 0 ? 1 : 0) + (tail > 0 ? 1 : 0);

    // Fades of the clip itself (from / to black, and its sound), counted
    // in its own frames and samples; never longer than the clip.
    int fadeFrames(int ms) {
      final f = (ms * fps / 1000).round();
      return f < 0 ? 0 : (f > n ? n : f);
    }

    final fadeInF = run == null ? fadeFrames(c.fadeInMs) : 0;
    final fadeOutF = run == null ? fadeFrames(c.fadeOutMs) : 0;

    if (!audioOnly) {
      // Video: constant fps, canvas size, square pixels, 8-bit 4:2:0 limited
      // ("TV") range, and exactly n frames (the last frame is held if the
      // source is short).
      //
      // The range must be asked for explicitly ($_tv on the scale that produces
      // the canvas-sized picture): FFmpeg 7+ negotiates colour range between
      // filters separately from the pixel format, so format=yuv420p alone lets
      // a full-range source (every JPEG photo, some phone video) through as
      // full-range H.264 ("yuvj420p"), which many players show with the wrong
      // contrast. FFmpeg 6 and older converted implicitly. -color_range tv on
      // the output asks for the same thing once more at the encoder.
      //
      // Speed: setpts rescales the timestamps and fps then drops or repeats
      // frames, so the output stays at the export frame rate.
      //
      // Run: frame k of the first fps filter is the source picture at
      // k / grid rate after the first piece's start (start_time pins frame 0
      // there even when the first decoded frame is a little later); select
      // keeps the pieces' frames, which are then numbered without gaps -
      // for a run with a speed, numbered that much faster and brought back
      // to the export rate.
      final pre = run != null
          ? '[$idx:v:0]fps=${run.gridFps}:start_time=0,'
              'tpad=stop=-1:stop_mode=clone,trim=end_frame=${run.sourceFrames},'
              "select='${run.expression}',"
              '${speed == 1 ? 'setpts=N/$fps/TB,' : 'setpts=N/${_num(run.gridFps * speed, 6)}/TB,fps=$fps,'}'
          : '[$idx:v:0]'
              '${speed == 1 ? '' : 'setpts=PTS/${_num(speed, 6)},'}'
              'fps=$fps,';
      // Crop and position (Framing): the picture is turned, mirrored and
      // cropped first, so everything after it sees the framed picture.
      final framed = framingFilters(c.framing);
      final pan = _panXY(c.framing);
      // Colour: on the 8-bit limited-range picture, before any bars are
      // added (bars stay black whatever the brightness). The colour look
      // (filter, warmth) follows the eq.
      final eq = eqFilter(c);
      final look = lookFilterFilters(c);
      final adjust = '${eq == null ? '' : ',format=yuv420p,$eq'}$look';
      // Zoom: a window of 1/zoom of the fitted canvas (where the pan says;
      // the centre by default), scaled back up. See placeClip
      // (core/model/picture_layout.dart), which the preview uses.
      final zoom = clipZoom(c);
      final zoomed = zoom > 1.0005;
      final zoomCrop = zoomed
          ? ',crop=${_even(w / zoom)}:${_even(h / zoom)}$pan,scale=$w:$h$_tv'
          : '';
      // The clip's own fade from / to black, frame exact, on its n frames
      // (before the split for a transition, as the preview fades the whole
      // clip layer).
      final fades = '${fadeInF > 0 ? ',fade=t=in:s=0:n=$fadeInF' : ''}'
          '${fadeOutF > 0 ? ',fade=t=out:s=${n - fadeOutF}:n=$fadeOutF' : ''}';
      final post = ',setsar=1,format=yuv420p,'
          'tpad=stop=-1:stop_mode=clone,'
          'trim=end_frame=$n$fades'
          '${pieces == 1 ? ',setpts=PTS-STARTPTS[v$i]' : ',split=$pieces${_pieceLabels('v', i, head, body, tail)}'}';
      final sameShape = sameShapeAsFrame(c, w.toDouble(), h.toDouble());
      if (sameShape) {
        chains.add('$pre${framed}scale=$w:$h$_tv$adjust$zoomCrop$post');
      } else {
        switch (c.fit) {
          case FitMode.fit:
            chains.add('$pre${framed}scale=$w:$h:force_original_aspect_ratio=decrease'
                ':force_divisible_by=2$_tv$adjust,'
                'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black$zoomCrop$post');
          case FitMode.fill:
            // The pan chooses which part of the filled picture stays.
            chains.add('$pre${framed}scale=$w:$h:force_original_aspect_ratio=increase$_tv,'
                'crop=$w:$h$pan$adjust$zoomCrop$post');
          case FitMode.blur:
            // Background is blurred at quarter resolution (fast, and the
            // upscale adds to the softness).
            final bw = _even(w / 4 < 16 ? 16 : w / 4);
            final bh = _even(h / 4 < 16 ? 16 : h / 4);
            final sigma = _num((bh < bw ? bh : bw) / 14.0);
            // Zoom enlarges the fitted picture only; the background stays.
            // The part that will be visible is cut out first, then enlarged
            // (never beyond the canvas).
            final z = _num(zoom, 4);
            final fgZoom = zoomed
                ? ",crop='min(iw,${_evenUp(w / zoom)})':'min(ih,${_evenUp(h / zoom)})'$pan,"
                    "scale='min($w,2*round(iw*$z/2))':'min($h,2*round(ih*$z/2))'"
                : '';
            chains.add('$pre${framed}split=2[bgsrc$i][fgsrc$i]');
            chains.add(
                '[bgsrc$i]scale=$bw:$bh:force_original_aspect_ratio=increase,'
                'crop=$bw:$bh,gblur=sigma=$sigma,scale=$w:$h$_tv,setsar=1[bg$i]');
            chains.add(
                '[fgsrc$i]scale=$w:$h:force_original_aspect_ratio=decrease'
                ':force_divisible_by=2$_tv$fgZoom,setsar=1[fg$i]');
            // overlay produces yuv420p, so eq can follow directly.
            chains.add('[bg$i][fg$i]overlay=(W-w)/2:(H-h)/2'
                '${eq == null ? '' : ',$eq'}$look$post');
        }
      }
      if (pieces > 1) {
        if (head > 0) chains.add('[v${i}p0]trim=end_frame=$head[v${i}h]');
        if (body > 0) {
          chains.add('[v${i}p1]trim=start_frame=$head:end_frame=${head + body},'
              'setpts=PTS-STARTPTS[v$i]');
        }
        if (tail > 0) chains.add('[v${i}p2]trim=start_frame=${head + body}[v${i}t]');
      }
    }

    // Audio: 48 kHz stereo float, exactly the samples of the n frames.
    // Volume is a linear amplitude factor, see the music section below.
    final nS = samplesAt(n);
    final headS = samplesAt(head);
    final tailStartS = samplesAt(head + body);
    // The clip's fades on its sound, sample exact (the same frames as the
    // picture's).
    final fadeInS = samplesAt(fadeInF);
    final fadeOutS = samplesAt(fadeOutF);
    final afades = silent
        ? ''
        : '${fadeInS > 0 ? ',afade=t=in:ss=0:ns=$fadeInS' : ''}'
            '${fadeOutS > 0 ? ',afade=t=out:ss=${nS - fadeOutS}:ns=$fadeOutS' : ''}';
    final aEnd = ',atrim=end_sample=$nS$afades'
        '${pieces == 1 ? ',asetpts=PTS-STARTPTS[a$i]' : ',asplit=$pieces${_pieceLabels('a', i, head, body, tail)}'}';
    if (processed != null) {
      final spanMs = run != null
          ? (run.sourceFrames * 1000 / run.gridFps).ceil() + 500
          : c.sourceSpanMs;
      inputs.addAll([
        '-ss', ffSeconds(c.inMs), '-t', ffSeconds(spanMs),
        '-i', processed,
      ]);
    }
    final audioIdx = processed != null ? inputCount++ : idx;
    if (silent) {
      chains.add('anullsrc=r=$kAudioSampleRate:cl=stereo,'
          'aformat=sample_fmts=fltp$aEnd');
    } else {
      const fmt = 'aformat=sample_fmts=fltp:channel_layouts=stereo';
      // Source stream, then side, clean-up and voice focus (clip_audio.dart).
      final src = processed != null
          ? '[$audioIdx:a:0]'
          : '[$idx:a:${c.audioTrackInUse}]';
      final clean =
          processed != null ? '' : clipSoundFilters(c, fmt, leaveOut: leaveOut);
      final tempo = [
        for (final s in atempoStages(speed)) 'atempo=${_num(s, 6)},',
      ].join();
      final vol = (c.volume - 1.0).abs() < 0.0005 ? '' : 'volume=${_num(c.volume)},';
      // apad makes up for a source that is too short. Its frames carry no
      // usable timestamps when the source had no sound at all in the range
      // (file replaced by a shorter one), hence the renumbering.
      if (run != null) {
        // The sound is put on the same grid as the picture: gaps and a
        // late start are filled so that sample 0 is the first piece's
        // start, then every piece is cut out at its frame numbers times
        // one frame's samples and the pieces are joined. A speed is
        // applied to the joined pieces; whatever atempo makes of the
        // length, the end is padded or cut to the samples of the run's
        // frames.
        //
        // One atrim per piece, NOT one `aselect` like the picture's
        // `select`: in FFmpeg 8.0 and 8.0.1 `aselect` passes every frame
        // through whatever its expression says (it was left without a
        // frame callback when f_select.c moved to activate(); 8.1 has it
        // again), so the source simply played on from the first piece's
        // start, out of step with the picture. atrim counts the samples
        // it is given and does not depend on timestamps.
        final perFrame = kAudioSampleRate ~/ run.gridFps;
        final np = run.ranges.length;
        String pads(String kind) => [for (var k = 0; k < np; k++) '[a$i$kind$k]'].join();
        chains.add('${src}aresample=$kAudioSampleRate:async=1:first_pts=0,$fmt,'
            '$clean${vol}apad,atrim=end_sample=${run.sourceFrames * perFrame},'
            'asplit=$np${pads('s')}');
        for (var k = 0; k < np; k++) {
          final r = run.ranges[k];
          // Each piece's own quiet ranges (1.17), in its own time.
          final piece = project.clips[placed[i + k].clipIndex];
          final pieceIn = c.inMs + r.start * 1000 / run.gridFps;
          final quiet = quietFilter([piece.quiet],
              originMs: pieceIn,
              fromMs: pieceIn,
              toMs: c.inMs + r.end * 1000 / run.gridFps);
          chains.add('[a${i}s$k]atrim=start_sample=${r.start * perFrame}'
              ':end_sample=${r.end * perFrame},asetpts=PTS-STARTPTS'
              '${quiet.isEmpty ? '' : ',${quiet.substring(0, quiet.length - 1)}'}'
              '[a${i}c$k]');
        }
        chains.add('${pads('c')}concat=n=$np:v=0:a=1,asetpts=N/SR/TB'
            '${speed == 1 ? '' : ',${tempo}apad,asetpts=N/SR/TB'}$aEnd');
      } else {
        final quiet = quietFilter([c.quiet],
            originMs: c.inMs, fromMs: c.inMs, toMs: c.outMs);
        chains.add('${src}aresample=$kAudioSampleRate,$fmt,'
            '$clean$quiet$tempo${vol}apad,asetpts=N/SR/TB$aEnd');
      }
    }
    if (pieces > 1) {
      if (head > 0) chains.add('[a${i}p0]atrim=end_sample=$headS[a${i}h]');
      if (body > 0) {
        chains.add('[a${i}p1]atrim=start_sample=$headS:end_sample=$tailStartS,'
            'asetpts=PTS-STARTPTS[a$i]');
      }
      if (tail > 0) chains.add('[a${i}p2]atrim=start_sample=$tailStartS[a${i}t]');
    }

    // Transition from the previous clip: its tail blended with our head.
    if (head > 0) {
      final prev = placed[i - 1];
      final name = xfadeName(c.transition)!;
      // Both inputs are exactly `head` frames long, so the blend runs from
      // "all previous clip" on its first frame to almost "all this clip"
      // on its last one and yields exactly `head` frames.
      if (!audioOnly) {
        chains.add('[v${i - 1}t][v${i}h]xfade=transition=$name'
            ':duration=${_frameSeconds(head, fps)}:offset=0,'
            'setpts=PTS-STARTPTS[x$i]');
      }
      final prevTailS = samplesAt(prev.frames) - samplesAt(prev.frames - head);
      final ns = prevTailS < headS ? prevTailS : headS;
      // Linear curves: the sum never exceeds the louder of the two clips.
      chains.add('[a${i - 1}t][a${i}h]acrossfade=ns=$ns:c1=tri:c2=tri,'
          'asetpts=N/SR/TB[xa$i]');
      concatPads.write(audioOnly ? '[xa$i]' : '[x$i][xa$i]');
      segments++;
    }
    if (body > 0) {
      concatPads.write(audioOnly ? '[a$i]' : '[v$i][a$i]');
      segments++;
    }
    if (run != null) i = run.last;
  }
  chains.add(audioOnly
      ? '${concatPads}concat=n=$segments:v=0:a=1[acat]'
      : '${concatPads}concat=n=$segments:v=1:a=1[vcat][acat]');

  // ---- overlay track ----------------------------------------------------
  // Drawn over the joined main picture, under the titles.
  var videoOut = '[vcat]';
  final textFiles = <String, String>{};
  if (!audioOnly) {
    final ov = buildOverlayChains(
      project: project,
      fps: fps,
      width: w,
      height: h,
      totalMs: totalMs,
      firstInput: inputCount,
      base: '[vcat]',
    );
    inputs.addAll(ov.inputs);
    inputCount += ov.inputCount;
    chains.addAll(ov.chains);

    // ---- titles ---------------------------------------------------------
    final draws = buildTitleDraws(
      project: project,
      fonts: fonts,
      workDir: workDir,
      width: w,
      height: h,
      totalMs: totalMs,
      textFiles: textFiles,
      fps: fps,
    );
    videoOut = ov.output;
    if (draws.isNotEmpty) {
      chains.add('$videoOut${draws.join(',')}[vout]');
      videoOut = '[vout]';
    }
  }

  // ---- sound tracks -----------------------------------------------------
  // Gain law, here and for the clips' own sound: [Clip.volume],
  // [AudioClip.volume] and [SoundTrack.volume] are LINEAR AMPLITUDE factors
  // (`volume=`): 0.5 is half the sample values = -6.02 dB, 0.25 = -12 dB,
  // 2 = +6 dB; in general 20 * log10(volume) dB. Nothing is normalised
  // (`amix normalize=0`), so a sound keeps its level whatever else plays;
  // only the final limiter (0.97 ceiling) touches peaks of the sum. A
  // preview that wants to sound like the export must apply the same factor
  // to the samples; player "volume" controls are often not linear (mpv's
  // is cubic by default: gain = (volume / 100)^3).
  //
  // The mix, see [buildSoundTrackMix]: every sound clip through its own
  // chain (source, clean-up, voice focus, speed, fades, volume) to its
  // place; the clips of a track mixed and given the track's level (mute
  // and solo included); a track that "lowers under speech" pushed down by
  // the video's own sound plus every speech track; all of it with the
  // video's own sound, then the limiter.
  final mix = buildSoundTrackMix(
    project: project,
    totalMs: totalMs,
    firstInput: inputCount,
    processedSound: processedSound,
    leaveOut: leaveOut,
    gates: options.gates,
  );
  inputs.addAll(mix.inputs);
  inputCount += mix.inputCount;
  chains.addAll(mix.chains);
  var audioOut = mix.output;
  final total = ffSeconds(totalMs);

  // ---- fade of the whole video ------------------------------------------
  // From black at the start, to black at the end, on the finished picture
  // (titles and overlays included) and on all the sound; frame / sample
  // exact. Each fade is at most half the video (Project.projectFades).
  final pf = project.projectFades;
  final totalFrames = timeline.totalFrames;
  int framesOf(int ms) {
    final f = (ms * fps / 1000).round();
    return f < 0 ? 0 : (f > totalFrames ? totalFrames : f);
  }

  final pfIn = framesOf(pf.inMs), pfOut = framesOf(pf.outMs);
  if (!audioOnly && (pfIn > 0 || pfOut > 0)) {
    chains.add('$videoOut'
        '${[
          if (pfIn > 0) 'fade=t=in:s=0:n=$pfIn',
          if (pfOut > 0) 'fade=t=out:s=${totalFrames - pfOut}:n=$pfOut',
        ].join(',')}[vfade]');
    videoOut = '[vfade]';
  }
  if (pfIn > 0 || pfOut > 0) {
    final totalS = samplesAt(totalFrames);
    final inS = samplesAt(pfIn), outS = samplesAt(pfOut);
    chains.add('$audioOut'
        '${[
          if (inS > 0) 'afade=t=in:ss=0:ns=$inS',
          if (outS > 0) 'afade=t=out:ss=${totalS - outS}:ns=$outS',
        ].join(',')}[afade]');
    audioOut = '[afade]';
  }

  final graph = chains.join(';');
  final small = options.quality == ExportQuality.small;
  final List<String> args;
  if (audioOnly) {
    final mp3 = options.format == ExportFormat.mp3;
    args = [
      '-y',
      ...inputs,
      '-filter_complex', graph,
      '-map', audioOut,
      if (mp3) ...['-c:a', 'libmp3lame', '-b:a', '192k']
      else ...['-c:a', 'aac', '-b:a', '192k'],
      '-ar', '$kAudioSampleRate',
      '-ac', '2',
      '-t', total,
      '-map_metadata', '-1',
      if (mp3) ...['-f', 'mp3']
      else ...['-movflags', '+faststart', '-f', 'ipod'],
      outputPath,
    ];
  } else {
    args = [
      '-y',
      ...inputs,
      '-filter_complex', graph,
      '-map', videoOut,
      '-map', audioOut,
      ...videoEncoderArgs(encoder,
          platform: encoderPlatform,
          quality: options.quality,
          width: w,
          height: h,
          fps: fps,
          preset: preset),
      '-color_range', 'tv',
      '-r', '$fps',
      '-g', '${fps * 2}',
      '-c:a', 'aac',
      '-b:a', small ? '128k' : '192k',
      '-ar', '$kAudioSampleRate',
      '-ac', '2',
      '-t', total,
      '-map_metadata', '-1',
      '-movflags', '+faststart',
      '-f', 'mp4',
      outputPath,
    ];
  }
  return FfmpegCommand(
    args: args,
    textFiles: textFiles,
    filterGraph: graph,
    width: audioOnly ? 0 : w,
    height: audioOnly ? 0 : h,
    durationMs: totalMs,
  );
}

/// The `drawbox` / `drawtext` filters that draw the titles and captions of
/// [project] on a [width] x [height] picture of a video [totalMs] long.
/// The text of each line goes into a file in [workDir] (added to
/// [textFiles]).
///
/// Lines, font size and position come from the shared layout
/// ([layoutTitleBlock]), worked out on the project canvas exactly like the
/// preview does (so line breaks do not depend on the export quality) and
/// already kept inside the canvas. Canvas pixels become output pixels by
/// k. Font ([TitleOverlay.font], [FontPaths.pathFor]), outline (drawtext
/// border), shadow, alignment and the entry / exit animations
/// ([titleAnimationAt], built here as the same curves in ffmpeg's
/// expression language) follow the title's settings. A title without any
/// of the 1.7 settings produces exactly the filters of 1.6.
List<String> buildTitleDraws({
  required Project project,
  required FontPaths fonts,
  required String workDir,
  required int width,
  required int height,
  required int totalMs,
  required Map<String, String> textFiles,
  int fps = 30,
}) {
  final canvas = project.canvasSize;
  final draws = <String>[];
  var titleNo = 0;
  final h = height;
  for (final t in project.titles) {
    final start = t.startMs < 0 ? 0 : t.startMs;
    final end = t.endMs > totalMs ? totalMs : t.endMs;
    if (end <= start || t.text.trim().isEmpty || t.fontSize <= 0) continue;
    final n = titleNo++;
    final block = layoutTitleBlock(t,
        canvasWidth: canvas.width, canvasHeight: canvas.height);
    final lines = block.lines;
    final k = canvas.height > 0 ? h / canvas.height : 1.0;
    var fs = (block.fontPx * k).round();
    if (fs < 1) fs = 1;
    final font = escapeFilterPath(fonts.pathFor(t.font, t.bold));
    final enable = escapeFilterValue(
        'gte(t,${ffSeconds(start)})*lt(t,${ffSeconds(end)})');
    final cxV = block.centerX * k;
    final cx = _num(cxV);
    final cy = block.centerY * k;
    final pitch = block.lineHeightPx * k;
    final anim = titleAnimationExpr(t, canvasHeightPx: h.toDouble());

    if (t.background && anim == null) {
      // One rectangle behind the whole block, sized by the layout (not by
      // drawtext's own box metrics) so that it is the box of the preview.
      final bw = (block.width + 2 * block.boxPadPx) * k;
      final bh = (block.height + 2 * block.boxPadPx) * k;
      final left = (block.centerX * k - bw / 2).round();
      final top = (cy - bh / 2).round();
      draws.add('drawbox=x=$left:y=$top'
          ':w=${bw.round() < 1 ? 1 : bw.round()}'
          ':h=${bh.round() < 1 ? 1 : bh.round()}'
          ':color=black@$kTitleBoxOpacity:t=fill'
          ':enable=$enable');
    } else if (t.background && anim != null) {
      // An animated box: drawbox cannot fade or move, so the box is a
      // half-transparent black picture of the layout's size laid over the
      // video (`color` source + `fade` on its transparency + `overlay` with
      // the move as an expression of t). Its opacity curves are the
      // preview's: linear over the animation (pop: over its first / last
      // third). It keeps its size while the text pops, as in the preview.
      // (1.7 drew it as the box of an invisible space with drawtext's
      // boxw/boxh + expression alpha; FFmpeg on GitHub CI crashed with
      // exit code -11 on that graph, see HANDOVER 1.8.)
      final bw = math.max(2, ((block.width + 2 * block.boxPadPx) * k).round());
      final bh = math.max(2, ((block.height + 2 * block.boxPadPx) * k).round());
      final left = (block.centerX * k - bw / 2).round();
      final top = (cy - bh / 2).round();
      final lens = titleAnimationLengths(t);
      final fades = <String>[];
      if (lens.inMs > 0 && t.animIn != TitleAnimation.none) {
        final d = t.animIn == TitleAnimation.pop ? lens.inMs / 3 : lens.inMs;
        fades.add('fade=t=in:st=${ffSeconds(start)}'
            ':d=${ffSeconds(d.round() < 1 ? 1 : d.round())}:alpha=1');
      }
      if (lens.outMs > 0 && t.animOut != TitleAnimation.none) {
        final d = t.animOut == TitleAnimation.pop ? lens.outMs / 3 : lens.outMs;
        final dd = d.round() < 1 ? 1 : d.round();
        fades.add('fade=t=out:st=${ffSeconds(t.endMs - dd)}'
            ':d=${ffSeconds(dd)}:alpha=1');
      }
      final rate = fps < 1 ? 30 : fps;
      draws.add('null[tb${n}a];'
          'color=c=black@$kTitleBoxOpacity:s=${bw}x$bh:r=$rate'
          ':d=${ffSeconds(end + 1000)},format=yuva420p'
          '${fades.isEmpty ? '' : ',${fades.join(',')}'}[tb${n}b];'
          '[tb${n}a][tb${n}b]overlay=x=$left'
          ':y=${escapeFilterValue('$top+${anim.dy}')}'
          ':eval=frame:eof_action=pass:enable=$enable');
    }
    final outline = t.outline ? titleOutlinePx(fs.toDouble()) : 0;
    for (var li = 0; li < lines.length; li++) {
      if (lines[li].trim().isEmpty) continue;
      final path = _joinPath(workDir, 'title_${n}_$li.txt');
      // Right-to-left lines get direction marks (see bidiLine).
      textFiles[path] = bidiLine(lines[li]);
      // Each line is centred on the block's centre line. The baseline is
      // placed so that capital letters are vertically centred on the
      // line; "ascent" keeps it independent of the glyphs used.
      final lineOffset = (li - lines.length / 2 + 0.5) * pitch + fs * 0.36;
      final shadow = t.background || !t.shadow
          ? ''
          : ':shadowcolor=black@0.6:shadowx=${_shadow(fs)}:shadowy=${_shadow(fs)}';
      final border = outline > 0
          ? ':borderw=$outline:bordercolor=${ffColor(t.outlineColorArgb)}'
          : '';
      // Alignment: each line against the block's left / right edge (as
      // laid out), or centred. Scaled about the centre while it pops.
      final String x;
      final String y;
      final String size;
      final String alpha;
      if (anim == null) {
        x = switch (t.align) {
          TitleAlign.center => '$cx-text_w/2',
          TitleAlign.left => _num(cxV - block.width * k / 2),
          TitleAlign.right => '${_num(cxV + block.width * k / 2)}-text_w',
        };
        y = '${_num(cy + lineOffset)}-ascent';
        size = '$fs';
        alpha = '';
      } else {
        // Animated. Opacity and move are expressions of t (alpha / y),
        // with the size it has when it does not pop. While it pops, its
        // SIZE changes: instead of a fontsize expression (FFmpeg on GitHub
        // CI crashed on the 1.7 graph, see HANDOVER 1.8) every output
        // frame of the pop gets its own drawtext with a fixed size,
        // opacity and place, computed by the preview's own
        // [titleAnimationAt], enabled for that frame only.
        final lens = titleAnimationLengths(t);
        final popIn = t.animIn == TitleAnimation.pop ? lens.inMs : 0;
        final popOut = t.animOut == TitleAnimation.pop ? lens.outMs : 0;
        final rate = fps < 1 ? 30 : fps;
        String fixedX(double sc) => switch (t.align) {
              TitleAlign.center => '$cx-text_w/2',
              TitleAlign.left => _num(cxV - block.width * k / 2 * sc),
              TitleAlign.right => '${_num(cxV + block.width * k / 2 * sc)}-text_w',
            };
        void frames(int fromMs, int toMs) {
          if (toMs <= fromMs) return;
          final half = 500 / rate;
          for (var fr = (fromMs * rate / 1000).floor();; fr++) {
            final ft = fr * 1000 / rate;
            if (ft >= toMs) break;
            final a = math.max(fromMs.toDouble(), ft - half);
            final b = math.min(toMs.toDouble(), ft + half);
            if (b <= a) continue;
            final v = titleAnimationAt(t, ft.round().clamp(fromMs, toMs));
            final fsz = math.max(1, (fs * v.scale).round());
            final yy = cy + v.dy * h + lineOffset * v.scale;
            draws.add('drawtext=fontfile=$font'
                ':textfile=${escapeFilterPath(path)}'
                ':expansion=none:fontsize=$fsz'
                ':fontcolor=${ffColor(t.colorArgb)}'
                '$shadow$border'
                ':x=${escapeFilterValue(fixedX(v.scale))}'
                ':y=${escapeFilterValue('${_num(yy)}-ascent')}'
                ':alpha=${_num(v.alpha)}'
                ':enable=${escapeFilterValue('gte(t,${_num(a / 1000, 6)})*lt(t,${_num(b / 1000, 6)})')}');
          }
        }

        frames(start, math.min(end, t.startMs + popIn));
        frames(math.max(start, t.endMs - popOut), end);
        final steadyFrom = math.max(start, t.startMs + popIn);
        final steadyTo = math.min(end, t.endMs - popOut);
        if (steadyTo <= steadyFrom) continue;
        x = fixedX(1);
        y = '${_num(cy)}+${anim.dy}+${_num(lineOffset)}-ascent';
        size = '$fs';
        alpha = ':alpha=${escapeFilterValue(anim.alpha)}';
        draws.add('drawtext=fontfile=$font'
            ':textfile=${escapeFilterPath(path)}'
            ':expansion=none:fontsize=$size:fontcolor=${ffColor(t.colorArgb)}'
            '$shadow$border'
            ':x=${escapeFilterValue(x)}'
            ':y=${escapeFilterValue(y)}'
            '$alpha'
            ':enable=${escapeFilterValue('gte(t,${ffSeconds(steadyFrom)})*lt(t,${ffSeconds(steadyTo)})')}');
        continue;
      }
      draws.add('drawtext=fontfile=$font'
          ':textfile=${escapeFilterPath(path)}'
          ':expansion=none:fontsize=$size:fontcolor=${ffColor(t.colorArgb)}'
          '$shadow$border'
          ':x=${escapeFilterValue(x)}'
          ':y=${escapeFilterValue(y)}'
          '$alpha'
          ':enable=$enable');
    }
  }
  return draws;
}

/// [titleAnimationAt] of [t] as ffmpeg expressions of `t` (seconds):
/// opacity, move down in output pixels ([canvasHeightPx] tall) and size
/// factor ('1' when it does not change). Null when the title has no
/// animation.
({String alpha, String dy, String scale})? titleAnimationExpr(TitleOverlay t,
    {required double canvasHeightPx}) {
  final lens = titleAnimationLengths(t);
  if (lens.inMs <= 0 && lens.outMs <= 0) return null;
  final alpha = <String>[];
  final dy = <String>[];
  final scale = <String>[];
  final slide = _num(kTitleSlideFraction * canvasHeightPx, 2);
  final from = _num(kTitlePopFrom);
  final grow = _num(1 - kTitlePopFrom);
  final over = _num(kTitlePopOvershoot);
  if (lens.inMs > 0) {
    final p = 'clip((t-${ffSeconds(t.startMs)})/${ffSeconds(lens.inMs)},0,1)';
    switch (t.animIn) {
      case TitleAnimation.none:
        break;
      case TitleAnimation.fade:
        alpha.add(p);
      case TitleAnimation.slideUp:
        alpha.add(p);
        dy.add('$slide*pow(1-$p,2)');
      case TitleAnimation.pop:
        alpha.add('min(1,3*$p)');
        scale.add('($from+$grow*(1-pow(1-$p,3))+$over*sin(PI*$p))');
    }
  }
  if (lens.outMs > 0) {
    final q = 'clip((${ffSeconds(t.endMs)}-t)/${ffSeconds(lens.outMs)},0,1)';
    switch (t.animOut) {
      case TitleAnimation.none:
        break;
      case TitleAnimation.fade:
        alpha.add(q);
      case TitleAnimation.slideUp:
        alpha.add(q);
        dy.add('-$slide*pow(1-$q,2)');
      case TitleAnimation.pop:
        alpha.add('min(1,3*$q)');
        scale.add('($from+$grow*(1-pow(1-$q,3)))');
    }
  }
  return (
    alpha: alpha.isEmpty ? '1' : alpha.join('*'),
    dy: dy.isEmpty ? '0' : '(${dy.join('+')})',
    scale: scale.isEmpty ? '1' : scale.join('*'),
  );
}

/// The overlay track ([Project.overlays]) as part of the export graph:
/// [inputs] to add ([firstInput] is the index of the first), [chains], and
/// the label of the picture with the overlays on it ([output]; [base] when
/// no overlay shows).
///
/// Every item that shows before the end of the main track becomes:
///  * one input (its trimmed source range; a photo decoded once and held,
///    like on the main track);
///  * a picture chain: speed, frame rate, crop and position
///    ([framingFilters]), scaled to fill its box ([overlayFrame]) and cut
///    to it where the pan says, a white frame if wanted, exactly the frames
///    it shows (its last frame held if the file is short), fades on its
///    transparency, and shifted to its start on the timeline;
///  * for side by side / top and bottom, the middle of the main picture
///    moved to the other half while it shows;
///  * an `overlay` onto the picture so far, switched on only while it
///    shows.
///
/// Its sound is mixed by [buildSoundTrackMix].
({List<String> inputs, int inputCount, List<String> chains, String output})
    buildOverlayChains({
  required Project project,
  required int fps,
  required int width,
  required int height,
  required int totalMs,
  required int firstInput,
  required String base,
}) {
  final inputs = <String>[];
  final chains = <String>[];
  var inputCount = 0;
  var current = base;
  final w = width.toDouble(), h = height.toDouble();
  for (var k = 0; k < project.overlays.length; k++) {
    final o = project.overlays[k];
    final c = o.clip;
    final startMs = o.startMs < 0 ? 0 : o.startMs;
    var endMs = o.endMs;
    if (endMs > totalMs) endMs = totalMs;
    if (startMs >= totalMs || endMs <= startMs || c.inMs < 0) continue;
    final startFrame = (startMs * fps / 1000).round();
    final n = (endMs * fps / 1000).round() - startFrame;
    if (n < 1) continue;
    final idx = firstInput + inputCount++;
    if (c.type == ClipType.photo) {
      inputs.addAll(['-framerate', '$fps', '-i', c.path]);
    } else {
      inputs.addAll([
        '-ss', ffSeconds(c.inMs), '-t', ffSeconds(c.sourceSpanMs),
        '-i', c.path,
      ]);
    }
    final frame = overlayFrame(o, w, h);
    final box = frame.box;
    final bw = _even(box.width);
    final bh = _even(box.height);
    final speed = effectiveSpeed(c);
    final sb = StringBuffer('[$idx:v:0]');
    if (speed != 1) sb.write('setpts=PTS/${_num(speed, 6)},');
    sb.write('fps=$fps,');
    sb.write(framingFilters(c.framing));
    // Fill the box; the pan chooses what stays in it.
    sb.write('scale=$bw:$bh:force_original_aspect_ratio=increase$_tv,'
        'crop=$bw:$bh${_panXY(c.framing)},setsar=1');
    final b = frame.border > 0 ? _even(frame.border) : 0;
    if (b > 0) {
      sb.write(',pad=${bw + 2 * b}:${bh + 2 * b}:$b:$b:color=white');
    }
    sb.write(',format=yuva420p,tpad=stop=-1:stop_mode=clone,'
        'trim=end_frame=$n,setpts=PTS-STARTPTS');
    final shownMs = (n * 1000 / fps).round();
    var fadeIn = o.fadeInMs < 0 ? 0 : o.fadeInMs;
    if (fadeIn > shownMs) fadeIn = shownMs;
    var fadeOut = o.fadeOutMs < 0 ? 0 : o.fadeOutMs;
    if (fadeOut > shownMs) fadeOut = shownMs;
    if (fadeIn > 0) {
      sb.write(',fade=t=in:st=0:d=${ffSeconds(fadeIn)}:alpha=1');
    }
    if (fadeOut > 0) {
      sb.write(',fade=t=out:st=${ffSeconds(shownMs - fadeOut)}'
          ':d=${ffSeconds(fadeOut)}:alpha=1');
    }
    sb.write(',setpts=PTS+${_frameSeconds(startFrame, fps)}/TB[ov$k]');
    chains.add(sb.toString());
    final enable = escapeFilterValue(
        'gte(t,${_frameSeconds(startFrame, fps)})'
        '*lt(t,${_frameSeconds(startFrame + n, fps)})');
    final src = frame.mainSource;
    final dest = frame.mainDest;
    if (src != null && dest != null) {
      // The middle of the main picture goes to the other half.
      chains.add('${current}split=2[ovb$k][ovs$k]');
      chains.add('[ovs$k]crop=${src.width.round()}:${src.height.round()}'
          ':${src.left.round()}:${src.top.round()}[ovm$k]');
      chains.add('[ovb$k][ovm$k]overlay=${dest.left.round()}:${dest.top.round()}'
          ':enable=$enable[ovh$k]');
      current = '[ovh$k]';
    }
    final x = box.left.round() - b;
    final y = box.top.round() - b;
    chains.add('$current[ov$k]overlay=$x:$y:eof_action=pass:repeatlast=0'
        ':enable=$enable[ovo$k]');
    current = '[ovo$k]';
  }
  return (
    inputs: inputs,
    inputCount: inputCount,
    chains: chains,
    output: current,
  );
}

/// Most source the pieces of one sound run may span (see
/// [findSoundRuns]): the decoded sound between the first piece and a later
/// one waits in memory until that piece plays (about 23 MB per minute).
const int kMaxSoundRunSpanMs = 5 * 60 * 1000;

/// Neighbouring sound clips on one track that are pieces of ONE file with
/// the same settings (what a separated sound becomes after "Remove
/// silences"), read from a single input like [ClipRun]s of the main track:
/// one demuxer and decoder instead of one per piece. Each piece still gets
/// its own chain after an `asplit`, so the result is the same as with one
/// input per piece.
List<List<AudioClip>> findSoundRuns(
    List<AudioClip> clips, Map<String, String> processedSound) {
  String key(AudioClip a) => [
        a.path,
        processedSound[a.id] ?? '',
        a.trackId,
        a.speed,
        a.audioTrackInUseKey,
      ].join('|');
  final out = <List<AudioClip>>[];
  for (final a in clips) {
    final run = out.isEmpty ? null : out.last;
    final last = run?.last;
    if (run != null &&
        last != null &&
        run.length < kMaxRunPieces &&
        key(a) == key(last) &&
        a.inMs >= last.outMs &&
        a.inMs - last.outMs <= kMaxRunGapMs &&
        a.outMs - run.first.inMs <= kMaxSoundRunSpanMs &&
        a.startMs >= last.endMs) {
      run.add(a);
    } else {
      out.add([a]);
    }
  }
  return out;
}

extension on AudioClip {
  /// Settings that change what is read from the file before the clip's own
  /// chain (the chain itself runs per piece).
  String get audioTrackInUseKey => '${soundClip.audioTrackInUse}';
}

/// The sound-track part of the export graph: [inputs] to add after the
/// main track's ([firstInput] is the index of the first), [chains], and
/// the [output] label to map ("[acat]" when nothing is mixed in).
///
/// Shape:
///  * every sound clip: its file (or its ready processed sound file,
///    [processedSound] by audio id), the clip sound chain of
///    [clipSoundFilters] (track and side, clean-up, voice focus; not for a
///    processed file), speed (`atempo`), what is heard of it on the
///    timeline (cut at the video's end, [Project.audibleEndMs]), fades,
///    volume, and `adelay` to its start;
///  * pieces of one file next to each other on a track share one input
///    ([findSoundRuns]);
///  * per track: its clips mixed, padded to the length of the video, and
///    the track level ([Project.trackGain]: volume, mute, solo) - a silent
///    track is left out;
///  * the video's own sound ([acat]) gets [Project.videoSound]'s level;
///  * "Lower this track under speech" ([SoundTrack.duck]): the track is
///    compressed ([kDuckFilter]) with, as side chain, the video's own sound
///    plus every other [SoundTrack.speech] track that is heard;
///  * everything mixed (`normalize=0`), then `alimiter`.
({List<String> inputs, int inputCount, List<String> chains, String output})
    buildSoundTrackMix({
  required Project project,
  required int totalMs,
  required int firstInput,
  Map<String, String> processedSound = const {},
  Set<SoundStage> leaveOut = const {},
  Map<String, List<QuietRange>> gates = const {},
}) {
  const fmt = 'aformat=sample_fmts=fltp:channel_layouts=stereo';
  final total = ffSeconds(totalMs);
  final inputs = <String>[];
  final chains = <String>[];
  var inputCount = 0;
  final fades = !leaveOut.contains(SoundStage.musicFades);

  // What of a clip is heard: timeline start, length, source start.
  ({int start, int dur, int srcIn, int srcDur, int fadeIn})? heard(
      AudioClip a) {
    if (a.volume <= 0 || a.inMs < 0) return null;
    final speed = effectiveSpeed(a.soundClip);
    var startMs = a.startMs;
    var inMs = a.inMs;
    var fadeIn = a.fadeInMs < 0 ? 0 : a.fadeInMs;
    if (startMs < 0) {
      // Starts before the timeline: skip the hidden part.
      inMs += (-startMs * speed).round();
      fadeIn = 0;
      startMs = 0;
    }
    if (a.durationMs <= 0 || startMs >= totalMs) return null;
    // Only what is heard is decoded: the sound stops at its own end or at
    // the end of the main track, whichever comes first.
    var endMs = project.audibleEndMs(a);
    if (endMs > totalMs) endMs = totalMs;
    final dur = endMs - startMs;
    if (dur <= 0) return null;
    var srcDur = (dur * speed).ceil();
    if (inMs + srcDur > a.outMs && a.outMs > inMs) srcDur = a.outMs - inMs;
    return (start: startMs, dur: dur, srcIn: inMs, srcDur: srcDur, fadeIn: fadeIn);
  }

  /// The chain of one clip from its decoded source (already resampled and
  /// cut to its source range) to its place on the timeline.
  String clipTail(AudioClip a, ({int start, int dur, int srcIn, int srcDur, int fadeIn}) h,
      {required bool processed}) {
    final sb = StringBuffer();
    if (!processed) {
      sb.write(clipSoundFilters(a.soundClip, fmt, leaveOut: leaveOut));
    }
    // Silenced / lowered stretches (1.17) and "Only when speaking": in
    // the sound's own time, before speed, so they follow trims and speed.
    sb.write(quietFilter(
        [a.quiet, gates[loopBaseId(a.id)] ?? const <QuietRange>[]],
        originMs: h.srcIn, fromMs: h.srcIn, toMs: h.srcIn + h.srcDur));
    for (final s in atempoStages(effectiveSpeed(a.soundClip))) {
      sb.write('atempo=${_num(s, 6)},');
    }
    sb.write('atrim=duration=${ffSeconds(h.dur)},asetpts=PTS-STARTPTS');
    var fadeIn = h.fadeIn;
    if (fadeIn > h.dur) fadeIn = h.dur;
    if (fades && fadeIn > 0) sb.write(',afade=t=in:st=0:d=${ffSeconds(fadeIn)}');
    var fadeOut = a.fadeOutMs < 0 ? 0 : a.fadeOutMs;
    if (fadeOut > h.dur) fadeOut = h.dur;
    // The fade-out FINISHES where the sound stops being heard
    // ([Project.audibleEndMs]): music that is longer than the video fades
    // out at the video's end instead of being cut off.
    if (fades && fadeOut > 0) {
      sb.write(',afade=t=out:st=${ffSeconds(h.dur - fadeOut)}'
          ':d=${ffSeconds(fadeOut)}');
    }
    if ((a.volume - 1.0).abs() >= 0.0005) sb.write(',volume=${_num(a.volume)}');
    if (h.start > 0) sb.write(',adelay=delays=${h.start}:all=1');
    return sb.toString();
  }

  // The sound of overlay items mixes in like one more track, at the level
  // of the video's own sound, and counts as speech for ducking.
  final overlaySounds = [
    for (final o in project.overlays)
      if (o.audible) o.sound,
  ];
  final tracks = [
    ...project.soundTracks,
    if (overlaySounds.isNotEmpty)
      const SoundTrack(id: kOverlayTrackId, name: 'Overlay', speech: true),
  ];
  double gainOf(SoundTrack t) => t.id == kOverlayTrackId
      ? project.trackGain(project.videoSound)
      : project.trackGain(t);
  // A looped sound ([AudioClip.loopMs]) is mixed as its repeats
  // ([AudioClip.loopPieces]): each a plain clip with its own fades, which
  // overlap and so cross-fade in the track's amix. They share the sound's
  // processed file.
  List<AudioClip> clipsOf(String id) => id == kOverlayTrackId
      ? overlaySounds
      : [for (final a in project.clipsOnTrack(id)) ...a.loopPieces];
  processedSound = {
    ...processedSound,
    for (final a in project.audio)
      if (a.looped && processedSound[a.id] != null)
        for (final piece in a.loopPieces) piece.id: processedSound[a.id]!,
  };

  // Pads of the clips, per track.
  final trackPads = <String, List<String>>{};
  var m = 0;
  for (final t in tracks) {
    if (gainOf(t) <= 0) continue;
    final clips = [
      for (final a in clipsOf(t.id))
        if (heard(a) != null) a,
    ];
    if (clips.isEmpty) continue;
    final pads = trackPads[t.id] = [];
    for (final run in findSoundRuns(clips, processedSound)) {
      final idx = firstInput + inputCount++;
      final first = run.first;
      final processed = processedSound[first.id];
      final src = processed != null
          ? '[$idx:a:0]'
          : '[$idx:a:${first.soundClip.audioTrackInUse}]';
      if (run.length == 1) {
        final h = heard(first)!;
        inputs.addAll([
          '-ss', ffSeconds(h.srcIn), '-t', ffSeconds(h.srcDur),
          '-i', processed ?? first.path,
        ]);
        chains.add('${src}aresample=$kAudioSampleRate,$fmt,'
            '${clipTail(first, h, processed: processed != null)}[m$m]');
        pads.add('[m$m]');
        m++;
        continue;
      }
      // One input for the run: from the first piece's start to the last
      // one's end; each piece cut out by its samples.
      final hs = [for (final a in run) heard(a)!];
      final from = hs.first.srcIn;
      var to = from;
      for (final h in hs) {
        if (h.srcIn + h.srcDur > to) to = h.srcIn + h.srcDur;
      }
      inputs.addAll([
        '-ss', ffSeconds(from), '-t', ffSeconds(to - from + 500),
        '-i', processed ?? first.path,
      ]);
      final r = m;
      chains.add('${src}aresample=$kAudioSampleRate:async=1:first_pts=0,$fmt,'
          'asplit=${run.length}'
          '${[for (var k = 0; k < run.length; k++) '[r${r}s$k]'].join()}');
      for (var k = 0; k < run.length; k++) {
        final h = hs[k];
        final s0 = ((h.srcIn - from) * kAudioSampleRate / 1000).round();
        final s1 = s0 + (h.srcDur * kAudioSampleRate / 1000).round();
        chains.add('[r${r}s$k]atrim=start_sample=$s0:end_sample=$s1,'
            'asetpts=PTS-STARTPTS,'
            '${clipTail(run[k], h, processed: processed != null)}[m$m]');
        pads.add('[m$m]');
        m++;
      }
    }
  }

  final videoGain = project.trackGain(project.videoSound);
  if (trackPads.isEmpty) {
    if ((videoGain - 1).abs() < 0.0005) {
      return (inputs: inputs, inputCount: inputCount, chains: chains, output: '[acat]');
    }
    chains.add('[acat]volume=${_num(videoGain)}[aout]');
    return (inputs: inputs, inputCount: inputCount, chains: chains, output: '[aout]');
  }

  // Each track as one stream as long as the video, at its level.
  final trackOut = <String, String>{};
  var n = 0;
  for (final t in tracks) {
    final pads = trackPads[t.id];
    if (pads == null) continue;
    final gain = gainOf(t);
    final sb = StringBuffer(pads.length == 1
        ? pads.single
        : '${pads.join()}amix=inputs=${pads.length}'
            ':duration=longest:dropout_transition=0:normalize=0,');
    sb.write('apad,asetpts=N/SR/TB,atrim=duration=$total,$fmt');
    if ((gain - 1).abs() >= 0.0005) sb.write(',volume=${_num(gain)}');
    final label = '[t$n]';
    sb.write(label);
    chains.add(sb.toString());
    trackOut[t.id] = label;
    n++;
  }

  // The video's own sound.
  final videoHeard = videoGain > 0;
  final unchanged = (videoGain - 1).abs() < 0.0005;
  final mainLabel = unchanged ? '[acat]' : '[amain]';
  if (videoHeard && !unchanged) {
    chains.add('[acat]volume=${_num(videoGain)}$mainLabel');
  } else if (!videoHeard) {
    // Every output of the graph must go somewhere.
    chains.add('[acat]anullsink');
  }

  // Ducking: who pushes whom down.
  final ducking = !leaveOut.contains(SoundStage.duckMusic);
  final ducked = [
    for (final t in tracks)
      if (ducking && t.duck && trackOut.containsKey(t.id)) t.id,
  ];
  final keySources = <String>[
    if (videoHeard) SoundTrack.videoId,
    for (final t in tracks)
      if (t.speech && trackOut.containsKey(t.id)) t.id,
  ];
  final keysOf = <String, List<String>>{
    for (final d in ducked) d: [for (final s in keySources) if (s != d) s],
  };
  // How often each stream is used: once in the final mix, once per key.
  String labelOf(String id) => id == SoundTrack.videoId ? mainLabel : trackOut[id]!;
  final uses = <String, int>{
    if (videoHeard) SoundTrack.videoId: 1,
    for (final id in trackOut.keys) id: 1,
  };
  for (final keys in keysOf.values) {
    for (final s in keys) {
      uses[s] = uses[s]! + 1;
    }
  }
  final handed = <String, List<String>>{};
  uses.forEach((id, count) {
    final label = labelOf(id);
    if (count == 1) {
      handed[id] = [label];
      return;
    }
    final stem = label.substring(1, label.length - 1);
    final outs = [for (var k = 0; k < count; k++) '[${stem}u$k]'];
    chains.add('${label}asplit=$count${outs.join()}');
    handed[id] = outs;
  });
  String take(String id) => handed[id]!.removeAt(0);

  final finals = <String>[];
  if (videoHeard) finals.add(take(SoundTrack.videoId));
  for (final t in tracks) {
    if (!trackOut.containsKey(t.id)) continue;
    final keys = keysOf[t.id];
    if (keys == null || keys.isEmpty) {
      finals.add(take(t.id));
      continue;
    }
    final own = take(t.id);
    final keyPads = [for (final s in keys) take(s)];
    final stem = trackOut[t.id]!.substring(1, trackOut[t.id]!.length - 1);
    final key = keyPads.length == 1
        ? keyPads.single
        : '[${stem}key]';
    if (keyPads.length > 1) {
      chains.add('${keyPads.join()}amix=inputs=${keyPads.length}'
          ':duration=longest:dropout_transition=0:normalize=0$key');
    }
    chains.add('$own$key$kDuckFilter[${stem}d]');
    finals.add('[${stem}d]');
  }
  final finish = leaveOut.contains(SoundStage.limiter)
      ? ''
      : 'alimiter=limit=0.97:level=0,';
  final mixIn = finals.length == 1
      ? '${finals.single}anull,'
      : '${finals.join()}amix=inputs=${finals.length}'
          ':duration=longest:dropout_transition=0:normalize=0,';
  chains.add('$mixIn${finish}apad,atrim=duration=$total,asetpts=PTS-STARTPTS[aout]');
  return (inputs: inputs, inputCount: inputCount, chains: chains, output: '[aout]');
}

/// Output labels of the split that cuts clip [i] into head / body / tail.
String _pieceLabels(String kind, int i, int head, int body, int tail) =>
    '${head > 0 ? '[$kind${i}p0]' : ''}'
    '${body > 0 ? '[$kind${i}p1]' : ''}'
    '${tail > 0 ? '[$kind${i}p2]' : ''}';

/// scale option: convert to limited ("TV") colour range. See the main track
/// comment in [buildExportCommand].
const _tv = ':out_range=tv';

int _shadow(int fontSize) {
  final s = (fontSize / 18).round();
  return s < 1 ? 1 : s;
}

/// Arguments that write the frame of video [path] shown at [timeMs] as a
/// full-resolution PNG (rotation metadata applied, frame-accurate seek).
/// A time at or past the end produces no file: use
/// [buildLastFrameCommand] then.
List<String> buildExtractFrameCommand({
  required String path,
  required String outputPath,
  int timeMs = 0,
}) =>
    [
      '-y',
      if (timeMs > 0) ...['-ss', ffSeconds(timeMs)],
      '-i', path,
      '-map', '0:v:0',
      '-frames:v', '1',
      '-c:v', 'png',
      '-update', '1',
      '-f', 'image2',
      outputPath,
    ];

/// Arguments that write the LAST frame of video [path] as a PNG: the last
/// [tailMs] are decoded and every frame overwrites the file.
List<String> buildLastFrameCommand({
  required String path,
  required String outputPath,
  int tailMs = 1000,
}) =>
    [
      '-y',
      '-sseof', ffSeconds(-(tailMs < 1 ? 1 : tailMs)),
      '-i', path,
      '-map', '0:v:0',
      '-c:v', 'png',
      '-update', '1',
      '-f', 'image2',
      outputPath,
    ];

/// Arguments that run `silencedetect` over audio stream [audioTrack] (0 =
/// first) of [path], only its [channel] side when that is not both; the
/// result is in the log (level info), see [parseSilenceLog].
List<String> buildSilenceDetectCommand({
  required String path,
  double thresholdDb = -35,
  int minSilenceMs = 700,
  int audioTrack = 0,
  AudioChannel channel = AudioChannel.both,
}) {
  final db = thresholdDb.isNaN ? -35.0 : (thresholdDb > 0 ? 0.0 : thresholdDb);
  final ms = minSilenceMs < 1 ? 1 : minSilenceMs;
  return [
    '-i', path,
    '-map', '0:a:${audioTrack < 0 ? 0 : audioTrack}',
    '-af', '${switch (channel) {
      AudioChannel.both => '',
      AudioChannel.left => 'pan=mono|c0=c0,',
      AudioChannel.right => 'pan=mono|c0=c1,',
    }}silencedetect=noise=${_num(db)}dB:d=${ffSeconds(ms)}',
    '-f', 'null',
    '-',
  ];
}

final RegExp _silenceRe = RegExp(
    r'silence_(start|end):\s*(-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)');

/// Reads the silent stretches from an ffmpeg log produced by
/// [buildSilenceDetectCommand].
///
/// A silence that lasts until the end of the file may come without a
/// `silence_end` line; it then ends at [durationMs] (when that is unknown
/// such an open silence is dropped). Times are clamped to 0..[durationMs].
List<({int startMs, int endMs})> parseSilenceLog(String log, {int? durationMs}) {
  final out = <({int startMs, int endMs})>[];
  int clamp(int ms) {
    if (ms < 0) return 0;
    if (durationMs != null && durationMs > 0 && ms > durationMs) {
      return durationMs;
    }
    return ms;
  }

  void add(int start, int end) {
    final s = clamp(start);
    final e = clamp(end);
    if (e > s) out.add((startMs: s, endMs: e));
  }

  int? open;
  for (final m in _silenceRe.allMatches(log)) {
    final v = double.tryParse(m.group(2)!);
    if (v == null || v.isNaN || v.isInfinite) continue;
    final ms = (v * 1000).round();
    if (m.group(1) == 'start') {
      open = ms;
    } else if (open != null) {
      add(open, ms);
      open = null;
    }
  }
  if (open != null && durationMs != null && durationMs > 0) {
    add(open, durationMs);
  }
  return out;
}

/// Arguments that write one JPEG frame of [path] at [timeMs].
List<String> buildThumbnailCommand({
  required String path,
  required String outputPath,
  int timeMs = 0,
  int maxHeight = 160,
}) {
  final mh = maxHeight < 2 ? 2 : maxHeight;
  return [
    '-y',
    if (timeMs > 0) ...['-ss', ffSeconds(timeMs)],
    '-i', path,
    '-map', '0:v:0',
    '-frames:v', '1',
    '-vf', "scale=-2:'min($mh,ih)'",
    '-q:v', '4',
    '-update', '1',
    '-f', 'image2',
    outputPath,
  ];
}

/// Arguments for ffprobe that print streams + format (+ the first frame,
/// which carries the EXIF orientation of photos) as JSON on stdout.
List<String> buildProbeCommand(String path, {bool? firstFrame}) => [
      '-v', 'error',
      '-hide_banner',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      if (firstFrame ?? probeReadsFirstFrame(path)) ...[
        '-show_frames',
        '-read_intervals', '%+#1',
      ],
      '-i', path,
    ];

/// File endings that are certainly a video or a sound recording: their
/// probe reads the file's index only, never a packet (1.18).
const Set<String> kProbeIndexOnly = {
  '.mp4', '.m4v', '.mov', '.mkv', '.webm', '.avi', '.mts', '.m2ts', '.ts',
  '.mpg', '.mpeg', '.wmv', '.flv', '.3gp', '.mxf', '.mp3', '.m4a', '.wav',
  '.aac', '.flac', '.ogg', '.opus', '.wma', '.aiff', '.aif',
};

/// Whether the probe of [path] also decodes the first frame. That is
/// only needed for photos (their EXIF orientation shows on the decoded
/// frame only). For a video it means opening every decoder and reading
/// packets - work that buys nothing (a video's rotation is in its stream
/// description) and one more place where a very large or slowly read file
/// can keep the probe waiting.
bool probeReadsFirstFrame(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return true;
  return !kProbeIndexOnly.contains(path.substring(dot).toLowerCase());
}

/// Interprets the JSON printed by [buildProbeCommand].
///
/// Width/height are the DISPLAY size (rotation metadata applied); still
/// images report a duration of 0; cover art in audio files is not video.
MediaInfo parseProbeJson(Map<dynamic, dynamic> json) {
  final streams = (json['streams'] as List?) ?? const [];
  final format = (json['format'] as Map?) ?? const {};
  Map? video;
  var hasAudio = false;
  final audioStreams = <int>[];
  for (final s in streams) {
    if (s is! Map) continue;
    final type = s['codec_type'];
    if (type == 'audio') {
      hasAudio = true;
      final ch = _toNum(s['channels'])?.toInt() ?? 0;
      audioStreams.add(ch < 0 ? 0 : ch);
    } else if (type == 'video' && video == null) {
      final disp = s['disposition'];
      final attached = disp is Map && _toNum(disp['attached_pic']) == 1;
      if (!attached) video = s;
    }
  }

  var width = 0;
  var height = 0;
  if (video != null) {
    width = _toNum(video['width'])?.toInt() ?? 0;
    height = _toNum(video['height'])?.toInt() ?? 0;
    var rotation = _rotationOf(video);
    if (rotation == 0) {
      // Photos: EXIF orientation only shows up on the decoded frame. ffmpeg
      // auto-rotates by it, so the display size has to follow.
      final frames = json['frames'];
      if (frames is List) {
        for (final fr in frames) {
          if (fr is Map && (fr['media_type'] ?? 'video') == 'video') {
            rotation = _rotationOf(fr);
            break;
          }
        }
      }
    }
    if (rotation.abs() % 180 == 90) {
      final t = width;
      width = height;
      height = t;
    }
  }

  var durationMs = 0;
  final d = _toNum(format['duration']) ??
      (video == null ? null : _toNum(video['duration']));
  if (d != null && d > 0) durationMs = (d * 1000).round();

  final formatName = '${format['format_name'] ?? ''}';
  const stillCodecs = {'png', 'mjpeg', 'bmp', 'webp', 'tiff', 'jpeg2000', 'jpegxl'};
  final isStill = video != null &&
      !hasAudio &&
      (formatName.endsWith('_pipe') ||
          formatName.split(',').contains('image2') ||
          (stillCodecs.contains(video['codec_name']) &&
              (_toNum(video['nb_frames']) ?? 1) <= 1 &&
              durationMs <= 100));
  if (isStill) durationMs = 0;

  return MediaInfo(
    durationMs: durationMs,
    width: width,
    height: height,
    hasVideo: video != null,
    hasAudio: hasAudio,
    fps: video == null || isStill ? 0 : _frameRateOf(video),
    audioStreams: List.unmodifiable(audioStreams),
  );
}

/// Frames per second of a probed video stream, 0 when unknown.
///
/// `avg_frame_rate` (frames / duration) is preferred: for phone video with
/// a variable frame rate `r_frame_rate` is only the smallest step between
/// two frames (it may say 90000/1, or 120 for a 30 fps recording).
double _frameRateOf(Map stream) {
  for (final key in const ['avg_frame_rate', 'r_frame_rate']) {
    final v = parseFrameRate(stream[key]);
    if (v >= 1 && v <= 1000) return v;
  }
  return 0;
}

/// Reads ffprobe's rational notation ("30000/1001", "25/1", "30"); 0 for
/// anything unusable ("0/0", null, ...).
double parseFrameRate(Object? value) {
  if (value is num) return value.isFinite && value > 0 ? value.toDouble() : 0;
  if (value is! String) return 0;
  final parts = value.trim().split('/');
  if (parts.isEmpty || parts.length > 2) return 0;
  final n = double.tryParse(parts[0]);
  final d = parts.length == 2 ? double.tryParse(parts[1]) : 1.0;
  if (n == null || d == null || d <= 0 || n <= 0) return 0;
  final v = n / d;
  return v.isFinite ? v : 0;
}

num? _toNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

int _rotationOf(Map stream) {
  final side = stream['side_data_list'];
  if (side is List) {
    for (final sd in side) {
      if (sd is Map && sd['rotation'] != null) {
        final r = _toNum(sd['rotation']);
        if (r != null) return r.round();
      }
    }
  }
  final tags = stream['tags'];
  if (tags is Map) {
    final r = _toNum(tags['rotate']);
    if (r != null) return r.round();
  }
  return 0;
}

// ---- failures --------------------------------------------------------------

/// What usually explains a failed run, most telling first within a line.
const List<String> _knownErrors = [
  'No space left on device',
  'Invalid data found when processing input',
  'No such file or directory',
  'Permission denied',
  'Cannot allocate memory',
  'moov atom not found',
  'Read-only file system',
  'Input/output error',
  'Too many open files',
  'Operation not permitted',
  'Disk quota exceeded',
  'File too large',
  'does not contain any stream',
  'matches no streams',
  'Unknown encoder',
  'Unknown decoder',
  'No such filter',
  'Encoder not found',
  'Decoder not found',
];

/// Lines ffmpeg prints after any failure; they say nothing about the cause.
final RegExp _genericError = RegExp(
    r'^(Conversion failed!?|'
    r'Error while (filtering|processing|decoding|encoding|opening)\b.*|'
    r'Error (re)?(initializing|configuring) (complex )?filters?\b.*|'
    r'Error (opening|initializing) (input|output)\b.*|'
    r'Error (muxing|submitting|sending|receiving|writing|reading|processing) (a |the )?(packet|frame|trailer|header)\b.*|'
    r'Failed to (configure|inject|set value)\b.*|'
    r'Terminating (thread|demuxer|muxer)\b.*|'
    r'Task finished with error code.*|'
    r'Nothing was written into output file.*|'
    r'Exiting normally.*|'
    r'Error setting option .*|'
    r'frame=.*|size=.*|video:.*audio:.*)$',
    caseSensitive: false);

/// FFmpeg 7+ names the file on a line of its own.
final RegExp _openingFile =
    RegExp(r'^Error opening (?:input|output) file (.+?)\.?$', caseSensitive: false);

/// The line of an ffmpeg [log] that best explains why it failed, e.g.
/// "/a/b.mp4: Invalid data found when processing input" or "Error writing
/// trailer: No space left on device"; null when the log is empty.
///
/// A line with a well-known cause wins (the last such line; the file ffmpeg
/// could not open is put in front when the line does not name it);
/// otherwise the last line that is not one of ffmpeg's generic closing
/// remarks. The `[component @ 0x...]` prefixes are removed. At most
/// [maxChars] long.
String? summarizeFfmpegError(String log, {int maxChars = 300}) {
  final lines = <String>[];
  for (var l in log.split(RegExp(r'[\r\n]+'))) {
    l = l.replaceAll(RegExp(r'\[[^\]]* @ 0x[0-9a-fA-F]+\] *'), '').trim();
    if (l.isNotEmpty) lines.add(l);
  }
  if (lines.isEmpty) return null;
  String cut(String s) =>
      s.length > maxChars ? '${s.substring(0, maxChars - 1)}…' : s;
  String? file;
  for (final l in lines) {
    final m = _openingFile.firstMatch(l);
    if (m != null) file = m.group(1);
  }
  for (final l in lines.reversed) {
    final lower = l.toLowerCase();
    for (final k in _knownErrors) {
      if (!lower.contains(k.toLowerCase())) continue;
      if (_openingFile.hasMatch(l)) continue;
      return cut(file != null && !l.contains(file) ? '$file: $k' : l);
    }
  }
  for (final l in lines.reversed) {
    if (!_genericError.hasMatch(l)) return cut(l);
  }
  return cut(lines.last);
}

/// Parses one line of ffmpeg's `-progress` output. Returns the fraction
/// (0..1) for time lines, 1.0 for `progress=end`, otherwise null.
double? parseProgressLine(String line, int totalMs) {
  final l = line.trim();
  if (l == 'progress=end') return 1.0;
  int? us;
  if (l.startsWith('out_time_us=')) {
    us = int.tryParse(l.substring(12));
  } else if (l.startsWith('out_time_ms=')) {
    // Despite the name this value is in microseconds as well.
    us = int.tryParse(l.substring(12));
  }
  if (us == null || us < 0 || totalMs <= 0) return null;
  final f = us / 1000.0 / totalMs;
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}
