// The waveform inside a block of the timeline (1.13). Only the part of the
// block near the view is worked out and painted, one bar every
// [kWaveStep] pixels, whatever the zoom: a bar shows the loudest moment
// of the stretch of sound it stands for.

import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:material_ui/material_ui.dart';

import '../../media/sound_peaks.dart';

/// Distance between two bars, in pixels.
const double kWaveStep = 2;

/// The bars of a block between [fromX] and [toX] (block coordinates):
/// `heights` 0..1, `active` 1 where the bar lies in one of [stretches]
/// (all 1 without stretches), `firstX` the x of the first bar.
///
/// The block shows the sound's file from [inMs] to [outMs], [speed] times
/// faster, at [pxPerMs]; when it is longer than that (a loop of
/// [passMs]), the part repeats.
({Float32List heights, Uint8List active, double firstX}) waveColumns(
  SoundPeaks peaks, {
  required int inMs,
  required int outMs,
  required double speed,
  required double pxPerMs,
  required double fromX,
  required double toX,
  double step = kWaveStep,
  List<TimeRange>? stretches,
  int passMs = 0,
}) {
  final s = speed <= 0 || speed.isNaN ? 1.0 : speed;
  final first = (fromX / step).floorToDouble() * step;
  final count = toX <= first ? 0 : ((toX - first) / step).ceil();
  final heights = Float32List(count);
  final active = Uint8List(count);
  if (count == 0 || pxPerMs <= 0 || outMs <= inMs) {
    return (heights: heights, active: active, firstX: first);
  }
  final span = outMs - inMs;
  final msPerStep = step / pxPerMs * s; // source ms one bar stands for
  var k = 0; // index into stretches
  for (var i = 0; i < count; i++) {
    var t = (first + i * step) / pxPerMs; // timeline ms from the block start
    if (t < 0) t = 0;
    if (passMs > 0) t = t % passMs;
    final a = inMs + (t * s).floor();
    if (a >= outMs) continue;
    var b = a + msPerStep.ceil();
    if (b > outMs) b = outMs;
    heights[i] = peaks.peakBetween(a, b);
    if (stretches == null) {
      active[i] = 1;
    } else if (passMs > 0) {
      active[i] = stretches.any((r) => r.startMs < b && r.endMs > a) ? 1 : 0;
    } else {
      // Bars and stretches both go forward in time.
      while (k < stretches.length && stretches[k].endMs <= a) {
        k++;
      }
      final mid = (a + b) ~/ 2;
      if (k < stretches.length &&
          stretches[k].startMs <= mid &&
          stretches[k].endMs > mid) {
        active[i] = 1;
      }
    }
    if (span <= 0) break;
  }
  return (heights: heights, active: active, firstX: first);
}

/// Paints [waveColumns]: bars around the middle line (or standing on the
/// bottom edge with [fromBottom]); talk in [color] on a band of [band],
/// pauses in [quietColor].
class WavePainter extends CustomPainter {
  WavePainter({
    required this.peaks,
    required this.inMs,
    required this.outMs,
    required this.speed,
    required this.pxPerMs,
    required this.fromX,
    required this.toX,
    required this.color,
    required this.quietColor,
    this.band,
    this.stretches,
    this.passMs = 0,
    this.fromBottom = false,
  });

  // The painted box starts at [fromX] of the block (only the part near
  // the view is in the tree).

  final SoundPeaks peaks;
  final int inMs;
  final int outMs;
  final double speed;
  final double pxPerMs;
  final double fromX;
  final double toX;
  final Color color;
  final Color quietColor;

  /// Background of the stretches where someone talks.
  final Color? band;
  final List<TimeRange>? stretches;
  final int passMs;
  final bool fromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final c = waveColumns(peaks,
        inMs: inMs,
        outMs: outMs,
        speed: speed,
        pxPerMs: pxPerMs,
        fromX: fromX,
        toX: toX < fromX + size.width ? toX : fromX + size.width,
        stretches: stretches,
        passMs: passMs);
    final n = c.heights.length;
    if (n == 0) return;
    final h = size.height;
    canvas.save();
    canvas.translate(-fromX, 0);
    if (band != null && stretches != null) {
      final paint = Paint()..color = band!;
      var start = -1;
      for (var i = 0; i <= n; i++) {
        final on = i < n && c.active[i] == 1;
        if (on && start < 0) start = i;
        if (!on && start >= 0) {
          canvas.drawRect(
              Rect.fromLTRB(c.firstX + start * kWaveStep, 0,
                  c.firstX + i * kWaveStep, h),
              paint);
          start = -1;
        }
      }
    }
    final loud = Float32List(n * 4), quiet = Float32List(n * 4);
    var nl = 0, nq = 0;
    final mid = h / 2;
    final most = fromBottom ? h - 1 : mid - 2;
    for (var i = 0; i < n; i++) {
      final v = c.heights[i];
      if (v <= 0) continue;
      final x = c.firstX + i * kWaveStep + 0.5;
      var len = v * most;
      if (len < 0.5) len = 0.5;
      final y0 = fromBottom ? h : mid - len;
      final y1 = fromBottom ? h - len : mid + len;
      if (c.active[i] == 1) {
        loud[nl++] = x;
        loud[nl++] = y0;
        loud[nl++] = x;
        loud[nl++] = y1;
      } else {
        quiet[nq++] = x;
        quiet[nq++] = y0;
        quiet[nq++] = x;
        quiet[nq++] = y1;
      }
    }
    final paint = Paint()
      ..strokeWidth = 1.2
      ..isAntiAlias = false;
    if (nl > 0) {
      canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(loud, 0, nl),
          paint..color = color);
    }
    if (nq > 0) {
      canvas.drawRawPoints(PointMode.lines,
          Float32List.sublistView(quiet, 0, nq), paint..color = quietColor);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      !identical(old.peaks, peaks) ||
      !identical(old.stretches, stretches) ||
      old.inMs != inMs ||
      old.outMs != outMs ||
      old.speed != speed ||
      old.pxPerMs != pxPerMs ||
      old.fromX != fromX ||
      old.toX != toX ||
      old.color != color ||
      old.quietColor != quietColor ||
      old.band != band ||
      old.passMs != passMs ||
      old.fromBottom != fromBottom;
}
