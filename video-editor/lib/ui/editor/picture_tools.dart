import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/model/picture_layout.dart';
import '../../core/model/project.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'clip_panels.dart';
import 'part_actions.dart';
import 'session.dart';

// Crop and position (main-track clips and overlay items) and the settings
// of an overlay item. The preview draws the crop frame ([CropFrame]) while
// a [CropPanel] is on screen (EditorSession.cropTarget).

const _dim = TextStyle(color: AppColors.textDim, fontSize: 12);

/// The clip (main track) or the overlay item's clip with id [id].
Clip? pictureOf(Project p, String id) {
  for (final c in p.clips) {
    if (c.id == id) return c;
  }
  for (final o in p.overlays) {
    if (o.id == id) return o.clip;
  }
  return null;
}

/// A few words about a picture's crop and position, for a section heading.
String framingSummary(Framing f) {
  if (f.isDefault) return '';
  final parts = <String>[
    if (!f.crop.isFull) 'Cropped',
    if (f.rotation != 0) 'Turned',
    if (f.flipH || f.flipV) 'Flipped',
    if (f.onlyPan) 'Moved',
  ];
  return parts.join(', ');
}

/// The shapes the crop frame can be held to.
enum CropShape { free, original, wide, tall, square, portrait }

String cropShapeLabel(CropShape s) => switch (s) {
      CropShape.free => 'Free',
      CropShape.original => 'Original',
      CropShape.wide => '16:9',
      CropShape.tall => '9:16',
      CropShape.square => '1:1',
      CropShape.portrait => '4:5',
    };

/// Width / height of [s] in picture pixels; null for free. [original] is
/// the shape of the whole (turned) picture.
double? cropShapeRatio(CropShape s, double original) => switch (s) {
      CropShape.free => null,
      CropShape.original => original,
      CropShape.wide => 16 / 9,
      CropShape.tall => 9 / 16,
      CropShape.square => 1,
      CropShape.portrait => 4 / 5,
    };

/// Crop, rotation, mirroring and position of [itemId] (a main-track clip
/// or an overlay item). While it is on screen the preview shows the whole
/// picture with the crop frame, whose corners and edges can be dragged.
class CropPanel extends StatefulWidget {
  const CropPanel({super.key, required this.session, required this.itemId});
  final EditorSession session;
  final String itemId;

  @override
  State<CropPanel> createState() => _CropPanelState();
}

class _CropPanelState extends State<CropPanel> {
  @override
  void initState() {
    super.initState();
    _claim();
  }

  @override
  void didUpdateWidget(CropPanel old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId) _claim();
  }

  /// Tells the preview to show the crop frame of this item (after the
  /// frame: the preview may be building right now).
  void _claim() {
    final s = widget.session;
    final id = widget.itemId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || s.isDisposed) return;
      s.cropRatio.value = null;
      s.cropTarget.value = id;
      if (s.project.clips.any((c) => c.id == id)) {
        s.showClip(id);
      } else {
        s.showOverlay(id);
      }
    });
  }

  @override
  void dispose() {
    final s = widget.session;
    final id = widget.itemId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s.isDisposed) return;
      if (s.cropTarget.value == id) s.cropTarget.value = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return ListenableBuilder(
      listenable: Listenable.merge([s.editor, s.cropRatio]),
      builder: (context, _) {
        final clip = pictureOf(s.project, widget.itemId);
        if (clip == null) return const SizedBox(height: 8);
        return _content(context, clip);
      },
    );
  }

  Widget _content(BuildContext context, Clip clip) {
    final s = widget.session;
    final editor = s.editor;
    final id = widget.itemId;
    final f = clip.framing;
    final turned = turnedSize(clip);
    final original = turned.width / turned.height;
    final ratio = s.cropRatio.value;
    CropShape? shape = ratio == null ? CropShape.free : null;
    if (ratio != null) {
      for (final c in CropShape.values) {
        final r = cropShapeRatio(c, original);
        if (r != null && (r - ratio).abs() < 1e-3) {
          shape = c;
          if (c != CropShape.original) break;
        }
      }
    }
    final room = _panRoom(s.project, id);
    String side(double v, String low, String high) {
      if (v.abs() < 0.005) return 'Middle';
      if (v <= -0.995) return '$low edge';
      if (v >= 0.995) return '$high edge';
      return '${v < 0 ? low : high} ${(v.abs() * 100).round()}%';
    }

    Widget action(IconData icon, String label, VoidCallback onTap, Key key) =>
        OutlinedButton.icon(
          key: key,
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 40),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabelWithHint('Crop',
            articleId: 'crop-position',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in CropShape.values)
              ChoicePill(
                key: ValueKey('crop-shape-${c.name}'),
                label: cropShapeLabel(c),
                selected: c == shape,
                onTap: () {
                  final r = cropShapeRatio(c, original);
                  s.cropRatio.value = r;
                  if (r != null) {
                    editor.setPictureCrop(
                        id,
                        c == CropShape.original
                            ? CropRect.full
                            : cropForRatio(clip, r, f.crop));
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
            'Drag the corners or sides of the frame on the picture; drag '
            'inside it to move it.',
            style: _dim),
        const SizedBox(height: 12),
        const PanelLabel('Turn and flip'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            action(Icons.rotate_left, 'Rotate left',
                () => editor.rotatePicture(id, clockwise: false),
                const ValueKey('rotate-left')),
            action(Icons.rotate_right, 'Rotate right',
                () => editor.rotatePicture(id),
                const ValueKey('rotate-right')),
            action(Icons.flip, 'Flip sideways',
                () => editor.flipPicture(id, horizontal: true),
                const ValueKey('flip-sideways')),
            action(Icons.swap_vert, 'Flip upside down',
                () => editor.flipPicture(id, horizontal: false),
                const ValueKey('flip-upside-down')),
          ],
        ),
        const SizedBox(height: 12),
        const PanelLabel('Position'),
        LiveSlider(
          key: const ValueKey('pan-x'),
          editor: editor,
          label: 'Left – right',
          value: f.panX,
          min: -1,
          max: 1,
          display: (v) => side(v, 'Left', 'Right'),
          onChanged: (v) =>
              editor.setPicturePan(id, x: (v * 20).round() / 20),
        ),
        LiveSlider(
          key: const ValueKey('pan-y'),
          editor: editor,
          label: 'Up – down',
          value: f.panY,
          min: -1,
          max: 1,
          display: (v) => side(v, 'Top', 'Bottom'),
          onChanged: (v) =>
              editor.setPicturePan(id, y: (v * 20).round() / 20),
        ),
        Text(
          !room.x && !room.y
              ? 'The whole picture is in the frame, so there is nothing to '
                  'move. Choose Fill (in Look) or zoom in, then move it to '
                  'keep the part you want.'
              : 'Chooses which part of the picture stays in the frame.',
          style: _dim,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('reset-crop'),
            onPressed: f.isDefault
                ? null
                : () {
                    s.cropRatio.value = null;
                    editor.resetFraming(id);
                  },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset crop and position'),
          ),
        ),
      ],
    );
  }

  /// Whether the pan moves anything, sideways / up and down.
  static ({bool x, bool y}) _panRoom(Project p, String id) {
    final canvas = p.canvasSize;
    final W = canvas.width.toDouble(), H = canvas.height.toDouble();
    PicBox at(double px, double py) {
      for (final c in p.clips) {
        if (c.id != id) continue;
        final moved = c.copyWith(
            framing: c.framing.copyWith(panX: px, panY: py));
        return placeClip(moved, W, H).picture;
      }
      for (final o in p.overlays) {
        if (o.id != id) continue;
        final box = overlayFrame(o, W, H).box;
        final size = o.clip.framedSize;
        return placeCover(o.clip.framing.copyWith(panX: px, panY: py),
                size.width, size.height, box)
            .picture;
      }
      return const PicBox(0, 0, 0, 0);
    }

    final a = at(-1, -1), b = at(1, 1);
    return (x: (a.left - b.left).abs() > 0.5, y: (a.top - b.top).abs() > 0.5);
  }
}

/// The crop frame over the whole picture in the preview: dims what is cut
/// away; corners and sides change the crop (holding the shape chosen in
/// the Crop panel, [EditorSession.cropRatio]), dragging inside moves it.
class CropFrame extends StatefulWidget {
  const CropFrame({
    super.key,
    required this.session,
    required this.itemId,
    required this.clip,
    required this.full,
  });
  final EditorSession session;
  final String itemId;

  /// The picture's clip (its framing and size).
  final Clip clip;

  /// Where the whole turned picture is drawn, in preview pixels.
  final PicBox full;

  /// Size of the handles' touch area.
  static const double grip = 30;

  @override
  State<CropFrame> createState() => _CropFrameState();
}

enum _Grip { move, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

class _CropFrameState extends State<CropFrame> {
  LiveEdit? _edit;
  CropRect _base = CropRect.full;
  Offset _moved = Offset.zero;

  void _start(_Grip g) {
    widget.session.playback.pause();
    _edit = LiveEdit(widget.session.editor);
    _base = widget.clip.framing.crop;
    _moved = Offset.zero;
  }

  void _update(_Grip g, Offset delta) {
    final edit = _edit;
    if (edit == null) return;
    _moved += delta;
    final full = widget.full;
    if (full.width <= 0 || full.height <= 0) return;
    final dx = _moved.dx / full.width;
    final dy = _moved.dy / full.height;
    final next = _dragged(g, dx, dy);
    edit.apply(() => widget.session.editor.setPictureCrop(widget.itemId, next));
  }

  void _end() => _edit = null;

  CropRect _dragged(_Grip g, double dx, double dy) {
    const min = CropRect.minSize;
    final b = _base;
    var l = b.x, t = b.y, r = b.right, bo = b.bottom;
    if (g == _Grip.move) {
      final x = (l + dx).clamp(0.0, 1 - b.width).toDouble();
      final y = (t + dy).clamp(0.0, 1 - b.height).toDouble();
      return CropRect(x, y, b.width, b.height);
    }
    final left = g == _Grip.left || g == _Grip.topLeft || g == _Grip.bottomLeft;
    final right =
        g == _Grip.right || g == _Grip.topRight || g == _Grip.bottomRight;
    final top = g == _Grip.top || g == _Grip.topLeft || g == _Grip.topRight;
    final bottom =
        g == _Grip.bottom || g == _Grip.bottomLeft || g == _Grip.bottomRight;
    if (left) l = (l + dx).clamp(0.0, r - min).toDouble();
    if (right) r = (r + dx).clamp(l + min, 1.0).toDouble();
    if (top) t = (t + dy).clamp(0.0, bo - min).toDouble();
    if (bottom) bo = (bo + dy).clamp(t + min, 1.0).toDouble();
    final ratio = widget.session.cropRatio.value;
    if (ratio == null) return CropRect(l, t, r - l, bo - t);
    // Keep the shape: h = w * W / (ratio * H) as fractions.
    final size = turnedSize(widget.clip);
    final k = size.width / (ratio * size.height);
    var w = r - l, h = bo - t;
    final horizontal = left || right;
    final vertical = top || bottom;
    if (horizontal && (!vertical || w * k >= h)) {
      h = w * k;
    } else {
      w = h / k;
    }
    // Not beyond the picture: shrink to what fits.
    double roomW, roomH;
    if (horizontal && !vertical) {
      final cy = (b.y + b.bottom) / 2;
      roomH = 2 * math.min(cy, 1 - cy);
      roomW = left ? b.right : 1 - b.x;
    } else if (vertical && !horizontal) {
      final cx = (b.x + b.right) / 2;
      roomW = 2 * math.min(cx, 1 - cx);
      roomH = top ? b.bottom : 1 - b.y;
    } else {
      roomW = left ? b.right : 1 - b.x;
      roomH = top ? b.bottom : 1 - b.y;
    }
    if (w > roomW) {
      w = roomW;
      h = w * k;
    }
    if (h > roomH) {
      h = roomH;
      w = h / k;
    }
    double x, y;
    if (horizontal && !vertical) {
      x = left ? b.right - w : b.x;
      y = (b.y + b.bottom) / 2 - h / 2;
    } else if (vertical && !horizontal) {
      y = top ? b.bottom - h : b.y;
      x = (b.x + b.right) / 2 - w / 2;
    } else {
      x = left ? b.right - w : b.x;
      y = top ? b.bottom - h : b.y;
    }
    return CropRect(x, y, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.full;
    final c = widget.clip.framing.crop;
    final rect = Rect.fromLTWH(full.left + c.x * full.width,
        full.top + c.y * full.height, c.width * full.width, c.height * full.height);
    const g = CropFrame.grip;
    Widget grip(_Grip which, double x, double y,
        {double w = g, double h = g, MouseCursor cursor = SystemMouseCursors.move}) {
      final corner = which.name.length > 6;
      return Positioned(
        key: ValueKey('crop-grip-${which.name}'),
        left: x - w / 2,
        top: y - h / 2,
        width: w,
        height: h,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => _start(which),
            onPanUpdate: (d) => _update(which, d.delta),
            onPanEnd: (_) => _end(),
            onPanCancel: _end,
            child: which == _Grip.move
                ? const SizedBox.expand()
                : Center(
                    child: Container(
                      width: corner ? 14 : (w > h ? 22 : 6),
                      height: corner ? 14 : (h > w ? 22 : 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: ui.Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('crop-frame'),
              painter: _CropShade(rect),
            ),
          ),
        ),
        grip(_Grip.move, rect.center.dx, rect.center.dy,
            w: math.max(0, rect.width - g), h: math.max(0, rect.height - g)),
        grip(_Grip.left, rect.left, rect.center.dy,
            h: math.max(g, rect.height - g),
            cursor: SystemMouseCursors.resizeLeftRight),
        grip(_Grip.right, rect.right, rect.center.dy,
            h: math.max(g, rect.height - g),
            cursor: SystemMouseCursors.resizeLeftRight),
        grip(_Grip.top, rect.center.dx, rect.top,
            w: math.max(g, rect.width - g),
            cursor: SystemMouseCursors.resizeUpDown),
        grip(_Grip.bottom, rect.center.dx, rect.bottom,
            w: math.max(g, rect.width - g),
            cursor: SystemMouseCursors.resizeUpDown),
        grip(_Grip.topLeft, rect.left, rect.top,
            cursor: SystemMouseCursors.resizeUpLeftDownRight),
        grip(_Grip.topRight, rect.right, rect.top,
            cursor: SystemMouseCursors.resizeUpRightDownLeft),
        grip(_Grip.bottomLeft, rect.left, rect.bottom,
            cursor: SystemMouseCursors.resizeUpRightDownLeft),
        grip(_Grip.bottomRight, rect.right, rect.bottom,
            cursor: SystemMouseCursors.resizeUpLeftDownRight),
      ],
    );
  }
}

/// Darkens everything outside the crop and draws its frame and thirds.
class _CropShade extends CustomPainter {
  _CropShade(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, line);
    final thin = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), thin);
    }
  }

  @override
  bool shouldRepaint(_CropShade old) => old.rect != rect;
}

// Overlay item settings --------------------------------------------------------

/// The groups of settings of an overlay item, in display order.
List<ClipTool> overlayToolsFor(OverlayClip o) =>
    const [ClipTool.layout, ClipTool.crop, ClipTool.sound];

String overlayToolLabel(ClipTool tool, OverlayClip o) => switch (tool) {
      ClipTool.layout => 'Layout',
      ClipTool.crop => 'Crop',
      ClipTool.sound =>
        o.clip.type == ClipType.photo ? 'Fades' : 'Sound, speed and fades',
      _ => clipToolLabel(tool),
    };

IconData overlayToolIcon(ClipTool tool) => switch (tool) {
      ClipTool.layout => Icons.picture_in_picture_alt,
      ClipTool.sound => Icons.volume_up,
      _ => clipToolIcon(tool),
    };

String overlayToolSummary(ClipTool tool, OverlayClip o) => switch (tool) {
      ClipTool.layout => overlayLayoutLabel(o.layout),
      ClipTool.crop => framingSummary(o.clip.framing),
      ClipTool.sound => o.clip.type == ClipType.photo
          ? ''
          : (!o.clip.hasAudio
              ? 'No sound'
              : (o.clip.muted ? 'Muted' : '${(o.clip.volume * 100).round()}%')),
      _ => '',
    };

/// The controls of one [tool] for overlay item [overlay].
class OverlayToolPanel extends StatelessWidget {
  const OverlayToolPanel({
    super.key,
    required this.session,
    required this.overlay,
    required this.tool,
  });
  final EditorSession session;
  final OverlayClip overlay;
  final ClipTool tool;

  @override
  Widget build(BuildContext context) => switch (tool) {
        ClipTool.layout =>
          OverlayLayoutPanel(session: session, overlay: overlay),
        ClipTool.crop => CropPanel(session: session, itemId: overlay.id),
        _ => OverlaySoundPanel(session: session, overlay: overlay),
      };
}

/// Name of a layout on its button (the same words History uses).
String overlayLayoutLabel(OverlayLayout l) => switch (l) {
      OverlayLayout.pip => 'Picture-in-picture',
      OverlayLayout.sideBySide => 'Side by side',
      OverlayLayout.topBottom => 'Top and bottom',
      OverlayLayout.full => 'Full screen',
      OverlayLayout.free => 'Free position',
    };

IconData overlayLayoutIcon(OverlayLayout l) => switch (l) {
      OverlayLayout.pip => Icons.picture_in_picture_alt,
      OverlayLayout.sideBySide => Icons.vertical_split,
      OverlayLayout.topBottom => Icons.horizontal_split,
      OverlayLayout.full => Icons.fullscreen,
      OverlayLayout.free => Icons.open_with,
    };

/// Where the overlay sits: layout, corner, size, side, frame.
class OverlayLayoutPanel extends StatelessWidget {
  const OverlayLayoutPanel(
      {super.key, required this.session, required this.overlay});
  final EditorSession session;
  final OverlayClip overlay;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final o = overlay;
    void set(OverlayClip next) => editor.updateOverlay(next);
    final small = o.layout == OverlayLayout.pip || o.layout == OverlayLayout.free;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabelWithHint('Layout',
            articleId: 'overlay',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in OverlayLayout.values)
              ChoicePill(
                key: ValueKey('overlay-layout-${l.name}'),
                icon: overlayLayoutIcon(l),
                label: overlayLayoutLabel(l),
                selected: o.layout == l,
                onTap: () => set(o.copyWith(layout: l)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (o.layout) {
            OverlayLayout.pip =>
              'A small picture over the video. Drag it on the picture to put '
                  'it anywhere; drag its corner to change its size.',
            OverlayLayout.sideBySide =>
              'The video on one half, the overlay on the other: the middle '
                  'of each is kept.',
            OverlayLayout.topBottom =>
              'The video on one half, the overlay on the other, one above '
                  'the other.',
            OverlayLayout.full =>
              'Covers the whole video while it plays: for a cut-away or '
                  'another camera.',
            OverlayLayout.free =>
              'Drag it on the picture to put it anywhere; drag its corner to '
                  'change its size.',
          },
          style: _dim,
        ),
        if (o.layout == OverlayLayout.pip) ...[
          const SizedBox(height: 12),
          const PanelLabel('Corner'),
          const SizedBox(height: 6),
          ChoiceRow<OverlayCorner>(
            values: const [OverlayCorner.topLeft, OverlayCorner.topRight],
            label: (c) => c == OverlayCorner.topLeft ? 'Top left' : 'Top right',
            selected: o.corner,
            onSelected: (c) => set(o.copyWith(corner: c)),
          ),
          const SizedBox(height: 6),
          ChoiceRow<OverlayCorner>(
            values: const [OverlayCorner.bottomLeft, OverlayCorner.bottomRight],
            label: (c) =>
                c == OverlayCorner.bottomLeft ? 'Bottom left' : 'Bottom right',
            selected: o.corner,
            onSelected: (c) => set(o.copyWith(corner: c)),
          ),
        ],
        if (o.layout == OverlayLayout.sideBySide ||
            o.layout == OverlayLayout.topBottom) ...[
          const SizedBox(height: 12),
          const PanelLabel('Overlay goes'),
          const SizedBox(height: 6),
          ChoiceRow<bool>(
            values: const [true, false],
            label: (first) => o.layout == OverlayLayout.sideBySide
                ? (first ? 'Left' : 'Right')
                : (first ? 'On top' : 'Below'),
            selected: o.overlayFirst,
            onSelected: (v) => set(o.copyWith(overlayFirst: v)),
          ),
        ],
        if (small) ...[
          const SizedBox(height: 8),
          LiveSlider(
            key: const ValueKey('overlay-size'),
            editor: editor,
            label: 'Size',
            value: o.size,
            min: OverlayClip.minSize,
            max: OverlayClip.maxSize,
            display: (v) => '${(v * 100).round()}%',
            onChanged: (v) => set(o.copyWith(size: (v * 100).round() / 100)),
          ),
          SwitchListTile(
            key: const ValueKey('overlay-border'),
            contentPadding: EdgeInsets.zero,
            title: const Text('White frame'),
            value: o.border,
            onChanged: (v) => set(o.copyWith(border: v)),
          ),
        ],
      ],
    );
  }
}

/// Volume, mute, speed and fades of an overlay item, and where it plays.
class OverlaySoundPanel extends StatelessWidget {
  const OverlaySoundPanel(
      {super.key, required this.session, required this.overlay});
  final EditorSession session;
  final OverlayClip overlay;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final o = overlay;
    final c = o.clip;
    void set(OverlayClip next) => editor.updateOverlay(next);
    final video = c.type == ClipType.video;
    final maxFade = (o.durationMs / 2).clamp(100, 10000).toDouble();
    final preset =
        kSpeedPresets.where((p) => (p - c.speed).abs() < 0.005).firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (video && c.hasAudio) ...[
          LiveSlider(
            key: const ValueKey('overlay-volume'),
            editor: editor,
            label: 'Volume',
            value: c.volume,
            min: EditorController.minVolume,
            max: EditorController.maxVolume,
            enabled: !c.muted,
            display: (v) => '${(v * 100).round()}%',
            onChanged: (v) => set(o.copyWith(
                clip: c.copyWith(volume: (v * 100).round() / 100))),
          ),
          SwitchListTile(
            key: const ValueKey('overlay-mute'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Mute overlay sound'),
            value: c.muted,
            onChanged: (v) => set(o.copyWith(clip: c.copyWith(muted: v))),
          ),
          QuietPartsList(
            session: session,
            itemId: o.id,
            quiet: c.quiet,
            startMs: o.startMs,
            inMs: c.inMs,
            outMs: c.outMs,
            speed: c.speed,
          ),
        ] else if (video)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('This video has no sound.', style: _dim),
          ),
        if (video) ...[
          const PanelLabel('Speed'),
          const SizedBox(height: 6),
          ChoiceRow<double>(
            values: kSpeedPresets,
            label: formatSpeed,
            selected: preset,
            onSelected: (v) =>
                set(o.copyWith(clip: c.copyWith(speed: v))),
          ),
          const SizedBox(height: 8),
        ],
        LiveSlider(
          key: const ValueKey('overlay-fade-in'),
          editor: editor,
          label: 'Fade in',
          value: o.fadeInMs.toDouble(),
          min: 0,
          max: maxFade,
          display: (v) => formatLength(v.round()),
          onChanged: (v) => set(o.copyWith(fadeInMs: v.round())),
        ),
        LiveSlider(
          key: const ValueKey('overlay-fade-out'),
          editor: editor,
          label: 'Fade out',
          value: o.fadeOutMs.toDouble(),
          min: 0,
          max: maxFade,
          display: (v) => formatLength(v.round()),
          onChanged: (v) => set(o.copyWith(fadeOutMs: v.round())),
        ),
        const SizedBox(height: 4),
        Text(
          'Starts at ${formatTime(o.startMs)}, shows for '
          '${formatLength(o.durationMs)}. Drag it along the overlay row to '
          'move it, or drag its ends to trim. Its sound plays with the '
          "video's own sound.",
          style: _dim,
        ),
      ],
    );
  }
}
