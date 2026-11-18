// Pure Dart: the colour of a clip's one-tap look ([LookFilter]) and
// warmth, as ONE colour matrix that the export (ffmpeg `colorchannelmixer`,
// lib/media/ffmpeg_command.dart) and the preview (Flutter's
// `ColorFilter.matrix`, lib/ui/playback/look.dart) both apply, so that they
// match.
//
// The matrix works on gamma-encoded R'G'B' values in 0..1, after the
// brightness / contrast / saturation of the clip (ffmpeg `eq`). Rows are
// R, G and B: `[r, g, b, offset]`, i.e. R' = r*R + g*G + b*B + offset.
//
// Known difference: the export clips each step to 0..1 (eq, then this
// matrix), the preview applies both in one go, so the very brightest and
// darkest parts of a strongly changed picture can differ slightly. The
// export converts the picture to RGB with the BT.601 colour matrix and back
// with the same one; on HD footage (BT.709) colours can shift by a step or
// two of 255 against the preview.

import 'project.dart';

/// 3 rows of [r, g, b, offset].
typedef ColorMatrix3 = List<double>;

const ColorMatrix3 _identity = [
  1, 0, 0, 0, //
  0, 1, 0, 0,
  0, 0, 1, 0,
];

/// Luma weights (Rec. 709) used for "black and white" and saturation.
const double _wr = 0.2126, _wg = 0.7152, _wb = 0.0722;

/// [b] applied after [a].
ColorMatrix3 composeColor(ColorMatrix3 b, ColorMatrix3 a) {
  final out = List<double>.filled(12, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var v = 0.0;
      for (var k = 0; k < 3; k++) {
        v += b[row * 4 + k] * a[k * 4 + col];
      }
      out[row * 4 + col] = v;
    }
    var off = b[row * 4 + 3];
    for (var k = 0; k < 3; k++) {
      off += b[row * 4 + k] * a[k * 4 + 3];
    }
    out[row * 4 + 3] = off;
  }
  return out;
}

ColorMatrix3 _saturation(double s) {
  final m = 1 - s;
  return [
    s + m * _wr, m * _wg, m * _wb, 0, //
    m * _wr, s + m * _wg, m * _wb, 0,
    m * _wr, m * _wg, s + m * _wb, 0,
  ];
}

ColorMatrix3 _contrast(double c) {
  final o = 0.5 * (1 - c);
  return [
    c, 0, 0, o, //
    0, c, 0, o,
    0, 0, c, o,
  ];
}

ColorMatrix3 _gains(double r, double g, double b,
        [double ro = 0, double go = 0, double bo = 0]) =>
    [
      r, 0, 0, ro, //
      0, g, 0, go,
      0, 0, b, bo,
    ];

/// The matrix of [filter] alone.
ColorMatrix3 lookFilterMatrix(LookFilter filter) => switch (filter) {
      LookFilter.none => _identity,
      // A little more red and yellow, a little less blue.
      LookFilter.warm => _gains(1.06, 1.0, 0.86, 0.02, 0.01, 0),
      // The other way round.
      LookFilter.cool => _gains(0.9, 1.0, 1.08, 0, 0.01, 0.03),
      // Grey from the luma, with a touch more contrast.
      LookFilter.blackWhite => composeColor(_contrast(1.1), _saturation(0)),
      // Faded and warm: less colour, softer contrast with lifted blacks,
      // a yellow-brown tint.
      LookFilter.vintage => composeColor(_gains(1.08, 1.0, 0.82, 0.03, 0.02, 0.02),
          composeColor(_contrast(0.82), _saturation(0.55))),
      // More colour and a little more contrast.
      LookFilter.vivid => composeColor(_contrast(1.08), _saturation(1.35)),
    };

/// The matrix of warmth [w] (-1 cooler .. 1 warmer) alone.
ColorMatrix3 warmthMatrix(double w) {
  final v = w.isNaN ? 0.0 : (w < -1 ? -1.0 : (w > 1 ? 1.0 : w));
  return _gains(1 + 0.1 * v, 1 + 0.01 * v, 1 - 0.14 * v);
}

/// The whole colour step of [clip]: its filter, then its warmth. Null when
/// it changes nothing.
ColorMatrix3? clipLookMatrix(Clip clip) {
  final hasFilter = clip.filter != LookFilter.none;
  final hasWarmth = clip.warmth.abs() >= 0.005 && !clip.warmth.isNaN;
  if (!hasFilter && !hasWarmth) return null;
  var m = lookFilterMatrix(clip.filter);
  if (hasWarmth) m = composeColor(warmthMatrix(clip.warmth), m);
  return m;
}

/// "Warm", "Black & white", ...
String lookFilterLabel(LookFilter f) => switch (f) {
      LookFilter.none => 'None',
      LookFilter.warm => 'Warm',
      LookFilter.cool => 'Cool',
      LookFilter.blackWhite => 'Black & white',
      LookFilter.vintage => 'Vintage',
      LookFilter.vivid => 'Vivid',
    };
