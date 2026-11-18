import 'dart:ui' show Offset;

import '../../core/model/look_filter.dart';
import '../../core/model/project.dart';

/// Colour adjustments of the export, as the options of ffmpeg's `eq`
/// filter for a clip's settings (each -1..1). Same mapping as `eqValues` in
/// lib/media/ffmpeg_command.dart (kEqBrightnessGain, kEqContrastGain).
double _unit(double v) => v.isNaN ? 0 : v.clamp(-1.0, 1.0).toDouble();
double eqBrightness(double brightness) => 0.2 * _unit(brightness);
double eqContrast(double contrast) => 1 + 0.5 * _unit(contrast);
double eqSaturation(double saturation) => 1 + _unit(saturation);

/// True when [clip] is shown with its colours changed.
bool hasColorAdjustments(Clip clip) =>
    clip.brightness != 0 ||
    clip.contrast != 0 ||
    clip.saturation != 0 ||
    clipLookMatrix(clip) != null;

/// The 5x4 colour matrix (row major, offsets in 0..255, as taken by
/// `ColorFilter.matrix`) that does to full-range RGB what the export's `eq`
/// does to the limited-range Y'CbCr picture. With k = eq contrast, b = eq
/// brightness, s = eq saturation and L the luma of the pixel:
///
///     offset = (1 - k) * 0.511 + 1.164 * b
///     R' = s * R + (k - s) * L + offset          (same for G and B)
///
/// (the formula documented next to kEqBrightnessGain in
/// lib/media/ffmpeg_command.dart). Contrast and brightness act on the luma
/// only, so every channel gets the same shift; saturation scales the
/// distance from the luma. The luma weights are those of Rec. 709, or of
/// Rec. 601 for SD sources.
List<double> clipColorMatrix(Clip clip) {
  final k = eqContrast(clip.contrast);
  final b = eqBrightness(clip.brightness);
  final s = eqSaturation(clip.saturation);
  final sd = clip.type == ClipType.video &&
      clip.width < 1280 &&
      clip.height <= 576;
  final wr = sd ? 0.299 : 0.2126;
  final wg = sd ? 0.587 : 0.7152;
  final wb = sd ? 0.114 : 0.0722;
  final m = k - s;
  final offset = ((1 - k) * 0.511 + 1.164 * b) * 255;
  final eq = <double>[
    s + m * wr, m * wg, m * wb, 0, offset, //
    m * wr, s + m * wg, m * wb, 0, offset,
    m * wr, m * wg, s + m * wb, 0, offset,
    0, 0, 0, 1, 0,
  ];
  // The colour look (filter, warmth) comes after the eq, as in the
  // export (core/model/look_filter.dart).
  final f = clipLookMatrix(clip);
  if (f == null) return eq;
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var j = 0; j < 3; j++) {
        v += f[row * 4 + j] * eq[j * 5 + col];
      }
      if (col == 4) v += f[row * 4 + 3] * 255;
      out[row * 5 + col] = v;
    }
  }
  out[18] = 1;
  return out;
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// How far each side of a transition is along, for drawing. The four kinds
/// follow ffmpeg's `xfade` transitions "fade", "fadeblack", "slideleft" and
/// "slideup", which the export uses (the slides push: the old picture
/// leaves as the new one enters).
///
/// [progress] runs 0..1 over the overlap. [incoming] is the clip the
/// transition leads to. [upper] says whether this layer is drawn above the
/// other one: a crossfade is the lower layer at full strength with the
/// upper one blended over it, whichever of the two that is.
({double opacity, Offset offset}) transitionPose(
  TransitionType type,
  double progress, {
  required bool incoming,
  required bool upper,
}) {
  final p = progress.clamp(0.0, 1.0);
  switch (type) {
    case TransitionType.none:
      return (opacity: 1, offset: Offset.zero);
    case TransitionType.crossfade:
      return (
        opacity: upper ? (incoming ? p : 1 - p) : 1,
        offset: Offset.zero,
      );
    case TransitionType.fadeBlack:
      // The weights of xfade's "fadeblack": the old picture is gone after
      // the first fifth, the new one comes up over the rest.
      final q = 1 - p;
      final o = incoming
          ? p * (1 - _smoothstep(0.2, 1, q))
          : q * _smoothstep(0.8, 1, q);
      return (opacity: o.clamp(0.0, 1.0), offset: Offset.zero);
    case TransitionType.slideLeft:
      return (opacity: 1, offset: Offset(incoming ? 1 - p : -p, 0));
    case TransitionType.slideUp:
      return (opacity: 1, offset: Offset(0, incoming ? 1 - p : -p));
  }
}
