// Pure Dart: where a picture goes in the frame. Shared by the preview
// (lib/ui/editor/preview_view.dart) and the export
// (lib/media/ffmpeg_command.dart), so that crop, rotation, position, fit,
// zoom and the overlay layouts come out the same in both.
//
// All sizes are in pixels of a frame of [frameW] x [frameH] (the project
// canvas for the preview, the output size for the export).

import 'project.dart';

/// A rectangle (no dependency on dart:ui).
class PicBox {
  const PicBox(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  PicBox scaled(double k) => PicBox(left * k, top * k, width * k, height * k);
  PicBox shifted(double dx, double dy) =>
      PicBox(left + dx, top + dy, width, height);

  @override
  bool operator ==(Object other) =>
      other is PicBox &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'PicBox(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)} x ${height.toStringAsFixed(1)})';
}

/// Where a framed picture is drawn.
class PicturePlacement {
  const PicturePlacement({required this.picture, required this.visible});

  /// Where the picture AFTER rotation and crop ([Clip.framedSize]) is
  /// drawn. May reach beyond the frame (fill, zoom).
  final PicBox picture;

  /// The part of the frame it may show in; the rest is cut off. The whole
  /// frame, except for the zoomed picture of [FitMode.blur].
  final PicBox visible;

  /// Where the WHOLE turned picture (before cropping) would be drawn, so
  /// that its [crop] part lands on [picture].
  PicBox fullPicture(CropRect crop) {
    final w = picture.width / crop.width;
    final h = picture.height / crop.height;
    return PicBox(
        picture.left - crop.x * w, picture.top - crop.y * h, w, h);
  }
}

/// Clips whose shape is within this relative distance of the frame are
/// simply stretched to it (avoids 1px bars from odd source sizes); the
/// export uses the same tolerance.
const double kSameShapeTolerance = 0.01;

double _pan(double v) => v.isNaN ? 0 : (v < -1 ? -1 : (v > 1 ? 1 : v));

/// Zoom as the export uses it: 1..4.
double clipZoom(Clip c) =>
    c.zoom.isNaN ? 1.0 : (c.zoom < 1 ? 1.0 : (c.zoom > 4 ? 4.0 : c.zoom));

/// True when [c]'s framed picture has (almost) the frame's shape.
bool sameShapeAsFrame(Clip c, double frameW, double frameH) {
  final s = c.framedSize;
  if (s.width <= 0 || s.height <= 0 || frameW <= 0 || frameH <= 0) {
    return false;
  }
  return ((s.width / s.height) / (frameW / frameH) - 1).abs() <
      kSameShapeTolerance;
}

/// Where a main-track clip's picture goes in a frame of [frameW] x
/// [frameH]: rotation and crop ([Clip.framing]) first, then fit / fill /
/// blur ([Clip.fit]), zoom ([Clip.zoom]) and position (pan).
///
/// Zoom cuts a window of 1/zoom of the frame out of the fitted frame and
/// enlarges it; the pan says where that window sits (-1 left/top edge, 1
/// right/bottom edge). With [FitMode.fill] the window moves over the whole
/// filled picture, so the pan also chooses which part of a picture that is
/// wider (or taller) than the frame stays in shot. With [FitMode.blur]
/// only the sharp picture is zoomed, centred over the background.
PicturePlacement placeClip(Clip c, double frameW, double frameH) {
  final frame = PicBox(0, 0, frameW, frameH);
  var pw = c.framedSize.width;
  var ph = c.framedSize.height;
  if (pw <= 0 || ph <= 0) {
    pw = frameW;
    ph = frameH;
  }
  final z = clipZoom(c);
  final px = (1 + _pan(c.framing.panX)) / 2;
  final py = (1 + _pan(c.framing.panY)) / 2;
  final W = frameW, H = frameH;

  PicturePlacement zoomedOver(double pw, double ph) {
    // A picture of pw x ph covering the frame (its left / top edge at the
    // frame's); the zoom window of W/z x H/z moves over all of it.
    final ox = (pw - W / z) * px;
    final oy = (ph - H / z) * py;
    return PicturePlacement(
      picture: PicBox(-ox * z, -oy * z, pw * z, ph * z),
      visible: frame,
    );
  }

  if (sameShapeAsFrame(c, W, H)) {
    return zoomedOver(W, H);
  }
  switch (c.fit) {
    case FitMode.fill:
      final s = (W / pw > H / ph) ? W / pw : H / ph;
      return zoomedOver(pw * s, ph * s);
    case FitMode.fit:
      final s = (W / pw < H / ph) ? W / pw : H / ph;
      final fw = pw * s, fh = ph * s;
      // The fitted picture sits centred in the frame; the zoom window moves
      // over the frame (bars included).
      final ox = (W - W / z) * px;
      final oy = (H - H / z) * py;
      return PicturePlacement(
        picture: PicBox(((W - fw) / 2 - ox) * z, ((H - fh) / 2 - oy) * z,
            fw * z, fh * z),
        visible: frame,
      );
    case FitMode.blur:
      final s = (W / pw < H / ph) ? W / pw : H / ph;
      final fw = pw * s, fh = ph * s;
      final cw = fw < W / z ? fw : W / z;
      final ch = fh < H / z ? fh : H / z;
      final ox = (fw - cw) * px;
      final oy = (fh - ch) * py;
      final vis = PicBox((W - cw * z) / 2, (H - ch * z) / 2, cw * z, ch * z);
      return PicturePlacement(
        picture: PicBox(vis.left - ox * z, vis.top - oy * z, fw * z, fh * z),
        visible: vis,
      );
  }
}

/// A picture of [pw] x [ph] (already turned and cropped) filling [box]
/// (cut to its shape), placed by [framing]'s pan: how overlays fill
/// their box.
PicturePlacement placeCover(Framing framing, double pw, double ph, PicBox box) {
  if (pw <= 0 || ph <= 0) {
    return PicturePlacement(picture: box, visible: box);
  }
  final s = (box.width / pw > box.height / ph) ? box.width / pw : box.height / ph;
  final w = pw * s, h = ph * s;
  final ox = (w - box.width) * (1 + _pan(framing.panX)) / 2;
  final oy = (h - box.height) * (1 + _pan(framing.panY)) / 2;
  return PicturePlacement(
      picture: PicBox(box.left - ox, box.top - oy, w, h), visible: box);
}

/// Size of [c]'s picture after turning, before the crop (never 0).
({double width, double height}) turnedSize(Clip c) {
  final w = (c.framing.sideways ? c.height : c.width).toDouble();
  final h = (c.framing.sideways ? c.width : c.height).toDouble();
  return (width: w > 0 ? w : 16, height: h > 0 ? h : 9);
}

/// The largest crop of shape [ratio] (picture pixels) around the middle of
/// [around], inside the picture of [c].
CropRect cropForRatio(Clip c, double ratio, CropRect around) {
  final s = turnedSize(c);
  // As fractions: width w and height h with w*W / (h*H) = ratio.
  var w = 1.0;
  var h = s.width / (ratio * s.height);
  if (h > 1) {
    h = 1;
    w = ratio * s.height / s.width;
  }
  final cx = around.x + around.width / 2;
  final cy = around.y + around.height / 2;
  return CropRect(
    (cx - w / 2).clamp(0.0, 1 - w).toDouble(),
    (cy - h / 2).clamp(0.0, 1 - h).toDouble(),
    w,
    h,
  ).clamped();
}

/// The whole turned picture of [c] (no crop, zoom or position), fitted into
/// the frame: what the preview shows while the crop is being changed.
/// [margin] keeps it that far from the frame's edges (room for the crop
/// frame's handles).
PicBox cropEditorPicture(Clip c, double frameW, double frameH,
    {double margin = 0}) {
  final f = c.framing;
  var w = (f.sideways ? c.height : c.width).toDouble();
  var h = (f.sideways ? c.width : c.height).toDouble();
  if (w <= 0 || h <= 0) {
    w = frameW;
    h = frameH;
  }
  final m = margin * 2 < frameW && margin * 2 < frameH ? margin : 0.0;
  final aw = frameW - 2 * m, ah = frameH - 2 * m;
  final s = (aw / w < ah / h) ? aw / w : ah / h;
  return PicBox((frameW - w * s) / 2, (frameH - h * s) / 2, w * s, h * s);
}

/// Where an overlay item and the main picture go while it shows.
class OverlayFrame {
  const OverlayFrame({
    required this.box,
    this.border = 0,
    this.mainSource,
    this.mainDest,
  });

  /// The overlay's picture fills this box (cut to its shape).
  final PicBox box;

  /// Width of the white frame drawn around [box] (outside it); 0 for none.
  final double border;

  /// Side by side / top and bottom: the part of the main picture
  /// ([mainSource], the middle of the frame) that is moved to
  /// [mainDest] (the other half). Same size, so nothing is scaled.
  final PicBox? mainSource;
  final PicBox? mainDest;
}

/// Margin between a picture-in-picture and the edge of the frame, as a
/// fraction of the frame's short side.
const double kOverlayMargin = 0.03;

/// Width of an overlay's white frame, as a fraction of the short side.
const double kOverlayBorder = 0.006;

/// Size of a picture-in-picture / free overlay: the overlay's own shape
/// (after its crop), as big as fits into [OverlayClip.size] of the frame
/// in each direction.
({double width, double height}) overlayPictureSize(
    OverlayClip o, double frameW, double frameH) {
  var pw = o.clip.framedSize.width;
  var ph = o.clip.framedSize.height;
  if (pw <= 0 || ph <= 0) {
    pw = 16;
    ph = 9;
  }
  final size = o.size.isNaN
      ? 0.33
      : o.size.clamp(OverlayClip.minSize, OverlayClip.maxSize).toDouble();
  final maxW = frameW * size, maxH = frameH * size;
  final k = (maxW / pw < maxH / ph) ? maxW / pw : maxH / ph;
  return (width: pw * k, height: ph * k);
}

/// Where overlay item [o] goes in a frame of [frameW] x [frameH].
OverlayFrame overlayFrame(OverlayClip o, double frameW, double frameH) {
  final W = frameW, H = frameH;
  final short = W < H ? W : H;
  switch (o.layout) {
    case OverlayLayout.full:
      return OverlayFrame(box: PicBox(0, 0, W, H));
    case OverlayLayout.sideBySide:
      // Even halves (the export works in whole, even pixels).
      final half = _evenDown(W / 2);
      final other = W - half;
      final overlay = o.overlayFirst
          ? PicBox(0, 0, half, H)
          : PicBox(half, 0, other, H);
      final dest = o.overlayFirst
          ? PicBox(half, 0, other, H)
          : PicBox(0, 0, half, H);
      return OverlayFrame(
        box: overlay,
        mainDest: dest,
        mainSource: PicBox(_evenDown((W - dest.width) / 2), 0, dest.width, H),
      );
    case OverlayLayout.topBottom:
      final half = _evenDown(H / 2);
      final other = H - half;
      final overlay = o.overlayFirst
          ? PicBox(0, 0, W, half)
          : PicBox(0, half, W, other);
      final dest = o.overlayFirst
          ? PicBox(0, half, W, other)
          : PicBox(0, 0, W, half);
      return OverlayFrame(
        box: overlay,
        mainDest: dest,
        mainSource: PicBox(0, _evenDown((H - dest.height) / 2), W, dest.height),
      );
    case OverlayLayout.pip:
    case OverlayLayout.free:
      final s = overlayPictureSize(o, W, H);
      final border = o.border ? _max(2, short * kOverlayBorder) : 0.0;
      double left, top;
      if (o.layout == OverlayLayout.pip) {
        final m = short * kOverlayMargin + border;
        final right = o.corner == OverlayCorner.topRight ||
            o.corner == OverlayCorner.bottomRight;
        final bottom = o.corner == OverlayCorner.bottomLeft ||
            o.corner == OverlayCorner.bottomRight;
        left = right ? W - m - s.width : m;
        top = bottom ? H - m - s.height : m;
      } else {
        final cx = (o.x.isNaN ? 0.5 : o.x) * W;
        final cy = (o.y.isNaN ? 0.5 : o.y) * H;
        left = _clampD(cx - s.width / 2, 0, W - s.width);
        top = _clampD(cy - s.height / 2, 0, H - s.height);
      }
      return OverlayFrame(
          box: PicBox(left, top, s.width, s.height), border: border);
  }
}

/// [OverlayClip.x] / [OverlayClip.y] of a free overlay whose box has its
/// top left corner at ([left], [top]) in a frame of [frameW] x [frameH].
({double x, double y}) overlayCentreFor(OverlayClip o, double left, double top,
    double frameW, double frameH) {
  final s = overlayPictureSize(o, frameW, frameH);
  final l = _clampD(left, 0, frameW - s.width);
  final t = _clampD(top, 0, frameH - s.height);
  return (
    x: frameW <= 0 ? 0.5 : (l + s.width / 2) / frameW,
    y: frameH <= 0 ? 0.5 : (t + s.height / 2) / frameH,
  );
}

double _evenDown(double v) {
  final i = (v / 2).floor() * 2;
  return (i < 2 ? 2 : i).toDouble();
}

double _max(double a, double b) => a > b ? a : b;

double _clampD(double v, double lo, double hi) =>
    hi < lo ? lo : (v < lo ? lo : (v > hi ? hi : v));
