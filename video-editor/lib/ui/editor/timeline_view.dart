import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/background_work.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/editor/snapping.dart';
import '../../core/model/project.dart';
import '../../core/text/text_document.dart';
import '../../media/speech_map.dart' show speechEdges;
import '../../media/media_jobs.dart' show ThumbnailStrip;
import '../format.dart';
import '../services.dart' show ThumbnailCache;
import '../speaker_colors.dart';
import '../theme.dart';
import '../widgets.dart';
import 'action_sheets.dart';
import 'clip_panels.dart';
import 'long_project_note.dart';
import 'session.dart';
import 'sound_status.dart';
import 'sound_tracks_ui.dart';
import 'sound_wave.dart';

/// Horizontally scrolling timeline: a time ruler, the overlay row (when the
/// project has overlay items), the main track, one row per sound track and
/// a titles row, with the playhead on top. A narrow
/// column on the left (it does not scroll) names the rows and holds the
/// sound controls: mute / solo of the video's own sound and of each track,
/// the track menu, and "Add sound track".
/// Where files dropped at a point of the window would go on the main track:
/// the index to insert them at, and the place (global coordinates) to draw
/// the insertion line. Null when the point is not over the timeline.
typedef TimelineDropLocator = ({int index, Rect line})? Function(
    Offset global);

/// The [TimelineDropLocator] of the timeline showing a session (set while
/// one is on screen). Used by the editor's file drop.
final Expando<TimelineDropLocator> timelineDropLocators =
    Expando('timeline drop locator');

class TimelineView extends StatefulWidget {
  const TimelineView({super.key, required this.session, this.onTransitionTap});
  final EditorSession session;

  /// Called after a tap on a transition badge has selected its clip. Phones
  /// open the Transition sheet here; wide windows show it in the side panel
  /// anyway.
  final VoidCallback? onTransitionTap;

  /// Width of the row header column: phones, wider windows.
  static const double headerWidthCompact = 44;
  static const double headerWidthWide = 112;

  /// Below this width the timeline uses the narrow header.
  static const double compactBelow = 600;

  /// Where the scrolled timeline starts for a timeline [width] wide.
  static double headerWidthFor(double width) =>
      width < compactBelow ? headerWidthCompact : headerWidthWide;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

enum _Edge { start, end, body }

class _TimelineViewState extends State<TimelineView> {
  static const double _padLeft = 28;
  static const double _padRight = 160;
  static const double _rulerHeight = 26;
  /// Top of the main track: right under the ruler, or under the overlay
  /// row when the project has overlay items ([_overlayRow]).
  double get _firstRowTop => 32 + _partStrip;

  /// The strip right under the ruler where dragging selects a part of the
  /// timeline (1.17). Computers only: a finger scrolls the timeline, so
  /// phones select a part with "Select part" and its two handles.
  static const double partStripHeight = 16;
  bool _compact = false;
  double get _partStrip => _compact ? 0 : partStripHeight;
  double get _clipTop =>
      _overlayRow ? _firstRowTop + _laneHeight + _laneGap + 4 : _firstRowTop;

  /// The overlay row is shown (the project has overlay items), as last
  /// built.
  bool _overlayRow = false;
  static const double _clipHeight = 56;
  static const double _laneHeight = 30;
  static const double _laneGap = 4;
  static const int _maxLanes = 2;

  static const double _handleWidth = 22;
  static const double _transitionBadge = 22;

  final _scroll = ScrollController();
  final Map<int, Offset> _pointers = {};
  double? _pinchDistance;
  double _pinchZoom = 0;
  late double _lastZoom;

  // Drag of a handle or a selected block.
  LiveEdit? _edit;
  Object? _base;
  double _dragDx = 0;

  /// Where the sound track rows start, and their ids top to bottom, as
  /// last built (dragging a sound clip onto another row).
  double _audioTop = 0;
  List<String> _trackIds = const [];

  // Dragging a clip of the main track to a new place.
  final _contentKey = GlobalKey();
  String? _reorderId;
  double _reorderX = 0; // pointer, in timeline coordinates
  double _reorderGrab = 0; // pointer distance from the block's left edge

  // Only what is near the view is built and painted: a 40-minute video is
  // over a million pixels wide at the largest zoom. The built stretch (the
  // "window") moves in steps of [_chunk] as the timeline scrolls.
  double _viewWidth = 0;
  double _builtBase = double.nan;

  /// Where the view scrolls to right after a zoom (the jump happens after
  /// the frame; this frame is already built for it).
  double? _zoomOffset;

  double get _chunk => math.max(256.0, _viewWidth / 2);
  double _windowBase(double offset) =>
      (offset / _chunk).floorToDouble() * _chunk;

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) return;
    if (_windowBase(_scroll.offset) == _builtBase) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Scrolled during layout: build the new window right after.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  EditorSession get _s => widget.session;
  EditorController get _editor => _s.editor;
  double get _pxPerMs => _s.zoom.value / 1000;
  double _x(int ms) => _padLeft + ms * _pxPerMs;
  int _ms(double x) => ((x - _padLeft) / _pxPerMs).round();

  @override
  void initState() {
    super.initState();
    _lastZoom = _s.zoom.value;
    _s.zoom.addListener(_onZoom);
    _s.playback.position.addListener(_followPlayhead);
    _scroll.addListener(_onScroll);
    timelineDropLocators[_s] = _dropAt;
    _longNote = LongProjectNote(_s, context);
  }

  late final LongProjectNote _longNote;

  /// A caption block narrower than this cannot be read.
  static const double _readableCaption = 110;

  /// Title and caption blocks narrower than this are drawn as slim marks.
  static const double _slimBelow = 12;
  static const double _stripHeight = 20;

  Project? _captionsFor;
  TextDocument _captions = TextDocument.empty;

  /// The captions in time order (worked out again when the project
  /// changes).
  TextDocument _captionDoc(Project project) {
    if (!identical(project, _captionsFor)) {
      _captionsFor = project;
      _captions = identical(project.titles, _captionsTitles)
          ? _captions
          : buildTextDocument(TextSource.captions, captionLines(project));
      _captionsTitles = project.titles;
    }
    return _captions;
  }

  List<TitleOverlay>? _captionsTitles;

  @override
  void dispose() {
    _longNote.dispose();
    if (identical(timelineDropLocators[_s], _dropAt)) {
      timelineDropLocators[_s] = null;
    }
    _s.zoom.removeListener(_onZoom);
    _s.playback.position.removeListener(_followPlayhead);
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the playhead (or the middle of the view) in place while zooming.
  void _onZoom() {
    final old = _lastZoom;
    final now = _s.zoom.value;
    _lastZoom = now;
    if (!_scroll.hasClients || old == now) return;
    final offset = _scroll.offset;
    final view = _scroll.position.viewportDimension;
    final playX = _padLeft + _s.playback.positionMs * old / 1000;
    final anchorX =
        playX >= offset && playX <= offset + view ? playX : offset + view / 2;
    final anchorMs = (anchorX - _padLeft) / old * 1000;
    final target = _padLeft + anchorMs * now / 1000 - (anchorX - offset);
    _zoomOffset = math.max(0.0, target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _zoomOffset = null;
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _followPlayhead() {
    if (!_s.playback.playing || !_scroll.hasClients) return;
    final x = _x(_s.playback.positionMs);
    final offset = _scroll.offset;
    final view = _scroll.position.viewportDimension;
    if (x > offset + view - 24 || x < offset) {
      _scroll.jumpTo(
          (x - 48).clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
    }
  }

  // Zoom gestures ----------------------------------------------------------

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      _s.setZoom(_s.zoom.value * math.exp(-event.scrollDelta.dy / 400));
    } else if (event.scrollDelta.dx == 0 &&
        !keys.isShiftPressed &&
        _scroll.hasClients) {
      // A plain mouse wheel moves along the timeline.
      _scroll.jumpTo((_scroll.offset + event.scrollDelta.dy)
          .clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  void _pointerDown(PointerDownEvent e) {
    final wasPinching = _pointers.length >= 2;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchDistance = _distance();
      _pinchZoom = _s.zoom.value;
    }
    if (wasPinching != (_pointers.length >= 2)) setState(() {});
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final base = _pinchDistance;
    if (_pointers.length == 2 && base != null && base > 0) {
      _s.setZoom(_pinchZoom * _distance() / base);
    }
  }

  void _pointerUp(PointerEvent e) {
    final wasPinching = _pointers.length >= 2;
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchDistance = null;
    if (wasPinching != (_pointers.length >= 2)) setState(() {});
  }

  double _distance() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  // Dragging handles and blocks -------------------------------------------

  void _startDrag(Object base) {
    _s.playback.pause();
    _edit = LiveEdit(_editor);
    _base = base;
    _dragDx = 0;
    final id = switch (base) {
      Clip c => c.id,
      AudioClip a => a.id,
      TitleOverlay t => t.id,
      OverlayClip o => o.id,
      _ => null,
    };
    // Also where speech starts and ends (not the dragged sound's own
    // track: its talk moves with it).
    final ownTrack = base is AudioClip ? base.trackId : null;
    _snapTargets = snapTargets(_s.project,
        playheadMs: _s.playback.positionMs,
        ignoreId: id,
        extra: speechEdges([
          for (final t in _s.pictures.speakers)
            if (t.id != ownTrack) t,
        ]));
    final i = base is Clip ? _s.project.clips.indexWhere((c) => c.id == id) : -1;
    _clipOrigin = i < 0
        ? null
        : (start: _s.project.clipStartMs(i), end: _s.project.clipEndMs(i));
  }

  void _endDrag() {
    _edit = null;
    _base = null;
    _snapTargets = const [];
    _s.snapLine.value = null;
  }

  // Snapping (see core/editor/snapping.dart): to the playhead and the
  // edges of everything else, within a few pixels; off in the settings or
  // while Alt / Option is held down.
  List<int> _snapTargets = const [];
  ({int start, int end})? _clipOrigin;
  bool get _snapOn =>
      _s.snapping.value && !HardwareKeyboard.instance.isAltPressed;
  int get _snapMs => (10 / _pxPerMs).round();

  /// [ms] (an edge on the timeline) snapped, and the snap line set.
  int _snap(int ms) {
    if (!_snapOn) {
      _s.snapLine.value = null;
      return ms;
    }
    final r = snapTime(ms, _snapTargets, _snapMs);
    _s.snapLine.value = r.snapped;
    return r.ms;
  }

  /// The start of something [length] long moved to [start], snapped by
  /// whichever edge is nearer.
  int _snapStart(int start, int length) {
    if (!_snapOn) {
      _s.snapLine.value = null;
      return start;
    }
    final r = snapSpan(start, length, _snapTargets, _snapMs);
    _s.snapLine.value = r.snapped;
    return r.start;
  }

  void _dragClip(_Edge edge, double dx) {
    final base = _base;
    final edit = _edit;
    if (base is! Clip || edit == null) return;
    _dragDx += dx;
    final start = edge == _Edge.start;
    var timelineMs = _dragDx / _pxPerMs;
    final origin = _clipOrigin;
    if (origin != null) {
      final edgeMs = (start ? origin.start : origin.end) + timelineMs.round();
      timelineMs = (_snap(edgeMs) - (start ? origin.start : origin.end))
          .toDouble();
    }
    edit.apply(() {
      if (base.type == ClipType.photo) {
        final d = timelineMs.round();
        _editor.trimClip(base.id, outMs: base.outMs + (start ? -d : d));
      } else {
        // The handle follows the finger on the timeline; a sped-up clip
        // uses up more of its source for the same distance.
        final d = (timelineMs * base.speed).round();
        if (start) {
          _editor.trimClip(base.id, inMs: base.inMs + d);
        } else {
          _editor.trimClip(base.id, outMs: base.outMs + d);
        }
      }
    });
    // Show the frame at the edge that is being moved.
    final project = _editor.project;
    final i = project.clips.indexWhere((c) => c.id == base.id);
    if (i < 0) return;
    final clipStart = project.clipStartMs(i);
    _s.playback.seek(
        start ? clipStart : clipStart + project.clips[i].durationMs - 1);
  }

  // Selecting a part (1.17) -------------------------------------------------

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  /// Where a drag that marks a part started (timeline ms); null otherwise.
  int? _partAnchor;
  int _partEdgeOrigin = 0;

  /// The last tap, to tell a double-click without making every single
  /// click wait for one.
  String? _lastTapKey;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when [key] was tapped twice within a double-click's time.
  bool _secondTap(String key) {
    final now = DateTime.now();
    final second = _lastTapKey == key &&
        now.difference(_lastTapAt) < const Duration(milliseconds: 400);
    _lastTapKey = second ? null : key;
    _lastTapAt = now;
    return second;
  }

  /// What a right-click or long press on an empty place is about: the
  /// selected part when the place is inside it, else that place.
  TimelineTarget _emptyTarget(int ms) =>
      (_s.part.value?.contains(ms) ?? false)
          ? const TimelineTarget.part()
          : TimelineTarget.empty(ms);

  void _partDragStart(double x) {
    _s.playback.pause();
    _snapTargets = _s.partSnapTargets();
    _partAnchor = _snap(math.max(0, _ms(x)));
  }

  void _partDragTo(double x) {
    final anchor = _partAnchor;
    if (anchor == null) return;
    final to = _snap(math.max(0, _ms(x)));
    _s.setPart(anchor, to);
  }

  void _partDragEnd() {
    _partAnchor = null;
    _snapTargets = const [];
    _s.snapLine.value = null;
  }

  void _partEdgeStart(bool start) {
    final part = _s.part.value;
    if (part == null) return;
    _s.playback.pause();
    _snapTargets = _s.partSnapTargets();
    _partEdgeOrigin = start ? part.startMs : part.endMs;
    _dragDx = 0;
  }

  /// Dragging a handle of the part: the edge follows the pointer, snaps,
  /// and stops short of the other edge; the preview shows the frame there.
  void _partEdgeDrag(bool start, double dx) {
    final part = _s.part.value;
    if (part == null) return;
    _dragDx += dx;
    var ms = _snap(_partEdgeOrigin + (_dragDx / _pxPerMs).round());
    const gap = 50;
    if (start) {
      ms = ms.clamp(0, math.max(0, part.endMs - gap)).toInt();
      _s.part.value = part.copyWith(startMs: ms);
    } else {
      ms = ms
          .clamp(part.startMs + gap,
              math.max(part.startMs + gap, _s.timelineEndMs))
          .toInt();
      _s.part.value = part.copyWith(endMs: ms);
    }
    _s.playback.seek(ms);
  }

  // Reordering the main track ---------------------------------------------

  /// [TimelineDropLocator]: files dropped at [global] go between the clips
  /// nearest to it (before every clip whose middle is to the right).
  ({int index, Rect line})? _dropAt(Offset global) {
    if (!mounted) return null;
    final view = context.findRenderObject();
    final content = _contentKey.currentContext?.findRenderObject();
    if (view is! RenderBox || content is! RenderBox || !view.attached) {
      return null;
    }
    if (!(Offset.zero & view.size).contains(view.globalToLocal(global))) {
      return null;
    }
    final x = content.globalToLocal(global).dx;
    final project = _s.project;
    var index = 0;
    for (var i = 0; i < project.clips.length; i++) {
      final middle = _x(project.clipStartMs(i)) +
          project.clips[i].durationMs * _pxPerMs / 2;
      if (middle < x) index++;
    }
    final lineMs = index < project.clips.length
        ? project.clipStartMs(index)
        : project.durationMs;
    final top = content.localToGlobal(Offset(_x(lineMs), _clipTop));
    return (
      index: index,
      line: Rect.fromLTWH(top.dx - 1.5, top.dy, 3, _clipHeight),
    );
  }

  double? _contentX(Offset global) {
    final box = _contentKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global).dx : null;
  }

  /// The context menu of [target]: a small menu at the pointer after a
  /// right-click, a sheet after a long press ([touch]).
  void _openContext(TimelineTarget target, Offset global,
      {required bool touch}) {
    if (!mounted) return;
    if (touch) HapticFeedback.selectionClick();
    // Narrow windows (phones) get a sheet, wide ones a menu at the pointer.
    showTimelineContextMenu(context, _s, target, position: global);
  }

  // A long press on a clip picks it up to move it; a long press that is
  // let go without moving opens the clip's context menu instead.
  Offset? _pressAt;
  bool _pressMoved = false;

  void _pressStart(Clip clip, Offset global) {
    _pressAt = global;
    _pressMoved = false;
    _reorderStart(clip, global);
  }

  void _pressUpdate(Offset global) {
    final at = _pressAt;
    if (at != null && (global - at).distance > 10) _pressMoved = true;
    _reorderUpdate(global);
  }

  void _pressEnd(Clip clip) {
    final at = _pressAt;
    final moved = _pressMoved;
    _pressAt = null;
    if (!moved && at != null) {
      _reorderEnd(cancelled: true);
      _openContext(TimelineTarget.item(ItemKind.clip, clip.id), at,
          touch: true);
      return;
    }
    _reorderEnd();
  }

  void _reorderStart(Clip clip, Offset global) {
    final x = _contentX(global);
    final index = _s.project.clips.indexWhere((c) => c.id == clip.id);
    if (x == null || index < 0 || _s.project.clips.length < 2) return;
    _s.playback.pause();
    _s.select(ItemKind.clip, clip.id);
    HapticFeedback.selectionClick();
    setState(() {
      _reorderId = clip.id;
      _reorderX = x;
      _reorderGrab = x - _x(_s.project.clipStartMs(index));
    });
  }

  void _reorderUpdate(Offset global) {
    if (_reorderId == null) return;
    // Near the edge of the view the timeline moves along.
    final view = context.findRenderObject();
    if (view is RenderBox && _scroll.hasClients) {
      final vx = view.globalToLocal(global).dx;
      final max = _scroll.position.maxScrollExtent;
      if (vx < 36 && _scroll.offset > 0) {
        _scroll.jumpTo(math.max(0, _scroll.offset - 14));
      } else if (vx > view.size.width - 36 && _scroll.offset < max) {
        _scroll.jumpTo(math.min(max, _scroll.offset + 14));
      }
    }
    final x = _contentX(global);
    if (x != null) setState(() => _reorderX = x);
  }

  /// Where the dragged clip would land: its index in the new order.
  int _reorderTarget(Project project, String id) {
    var target = 0;
    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      if (c.id == id) continue;
      final middle = _x(project.clipStartMs(i)) + c.durationMs * _pxPerMs / 2;
      if (middle < _reorderX) target++;
    }
    return target;
  }

  void _reorderEnd({bool cancelled = false}) {
    final id = _reorderId;
    if (id == null) return;
    final project = _s.project;
    final from = project.clips.indexWhere((c) => c.id == id);
    final to = from < 0 ? -1 : _reorderTarget(project, id);
    setState(() => _reorderId = null);
    if (!cancelled && from >= 0 && to != from) _editor.moveClip(from, to);
  }

  void _dragAudio(_Edge edge, double dx, [Offset? global]) {
    final base = _base;
    final edit = _edit;
    if (base is! AudioClip || edit == null) return;
    _dragDx += dx;
    var d = (_dragDx / _pxPerMs).round();
    d = switch (edge) {
      _Edge.start => _snap(base.startMs + d) - base.startMs,
      _Edge.end => _snap(base.endMs + d) - base.endMs,
      _Edge.body => _snapStart(base.startMs + d, base.durationMs) - base.startMs,
    };
    const min = EditorController.minDurationMs;
    // The row under the pointer: dragging onto another sound track.
    var trackId = base.trackId;
    final box = _contentKey.currentContext?.findRenderObject();
    if (edge == _Edge.body && global != null && box is RenderBox &&
        _trackIds.isNotEmpty) {
      final y = box.globalToLocal(global).dy;
      final row = ((y - _audioTop) / (_laneHeight + _laneGap))
          .floor()
          .clamp(0, _trackIds.length - 1);
      trackId = _trackIds[row];
    }
    edit.apply(() {
      switch (edge) {
        case _Edge.start:
          // Trim the beginning; the end stays where it is on the timeline.
          // A sped-up sound uses more of its file for the same distance.
          final speed = base.speed;
          final lowest = math.max(0, base.inMs - (base.startMs * speed).round());
          final newIn = (base.inMs + (d * speed).round())
              .clamp(lowest, math.max(lowest, base.outMs - (min * speed).ceil()))
              .toInt();
          final newStart = base.startMs + ((newIn - base.inMs) / speed).round();
          _editor.updateAudio(base.copyWith(
              inMs: newIn,
              startMs: newStart,
              // A looped sound keeps its end where it is.
              loopMs: base.looped ? base.endMs - newStart : null));
        case _Edge.end:
          // A looped sound repeats for longer or shorter; a plain one
          // uses more or less of its file.
          _editor.updateAudio(base.looped
              ? base.copyWith(loopMs: base.loopMs + d)
              : base.copyWith(outMs: base.outMs + (d * base.speed).round()));
        case _Edge.body:
          _editor.updateAudio(base.copyWith(
              startMs: math.max(0, base.startMs + d), trackId: trackId));
      }
    });
  }

  void _dragTitle(_Edge edge, double dx) {
    final base = _base;
    final edit = _edit;
    if (base is! TitleOverlay || edit == null) return;
    _dragDx += dx;
    var d = (_dragDx / _pxPerMs).round();
    d = switch (edge) {
      _Edge.start => _snap(base.startMs + d) - base.startMs,
      _Edge.end => _snap(base.endMs + d) - base.endMs,
      _Edge.body => _snapStart(base.startMs + d, base.endMs - base.startMs) -
          base.startMs,
    };
    const min = EditorController.minDurationMs;
    edit.apply(() {
      switch (edge) {
        case _Edge.start:
          final s = (base.startMs + d)
              .clamp(0, math.max(0, base.endMs - min))
              .toInt();
          _editor.updateTitle(base.copyWith(startMs: s));
        case _Edge.end:
          _editor.updateTitle(base.copyWith(
              endMs: math.max(base.startMs + min, base.endMs + d)));
        case _Edge.body:
          final s = math.max(0, base.startMs + d);
          _editor.updateTitle(base.copyWith(
              startMs: s, endMs: s + base.endMs - base.startMs));
      }
    });
  }

  void _dragOverlay(_Edge edge, double dx) {
    final base = _base;
    final edit = _edit;
    if (base is! OverlayClip || edit == null) return;
    _dragDx += dx;
    var d = (_dragDx / _pxPerMs).round();
    d = switch (edge) {
      _Edge.start => _snap(base.startMs + d) - base.startMs,
      _Edge.end => _snap(base.endMs + d) - base.endMs,
      _Edge.body => _snapStart(base.startMs + d, base.durationMs) - base.startMs,
    };
    const min = EditorController.minDurationMs;
    final c = base.clip;
    final photo = c.type == ClipType.photo;
    final speed = photo ? 1.0 : c.speed;
    edit.apply(() {
      switch (edge) {
        case _Edge.start:
          // Trim the beginning; the end stays where it is on the timeline.
          if (photo) {
            final cut = d.clamp(-base.startMs, c.outMs - min).toInt();
            _editor.updateOverlay(base.copyWith(
                startMs: base.startMs + cut,
                clip: c.copyWith(outMs: c.outMs - cut)));
          } else {
            final lowest =
                math.max(0, c.inMs - (base.startMs * speed).round());
            final newIn = (c.inMs + (d * speed).round())
                .clamp(lowest, math.max(lowest, c.outMs - (min * speed).ceil()))
                .toInt();
            _editor.updateOverlay(base.copyWith(
                startMs: base.startMs + ((newIn - c.inMs) / speed).round(),
                clip: c.copyWith(inMs: newIn)));
          }
        case _Edge.end:
          _editor.updateOverlay(base.copyWith(
              clip: c.copyWith(outMs: c.outMs + (d * speed).round())));
        case _Edge.body:
          _editor.updateOverlay(
              base.copyWith(startMs: math.max(0, base.startMs + d)));
      }
    });
    // Show the frame at the edge that is being moved.
    final now = _editor.project.overlays
        .where((o) => o.id == base.id)
        .firstOrNull;
    if (now != null) {
      _s.playback.seek(edge == _Edge.end ? now.endMs - 1 : now.startMs);
    }
  }

  // Layout -----------------------------------------------------------------

  /// Puts overlapping items on separate lanes (first free lane wins).
  static Map<String, int> _lanes(
      Iterable<({String id, int start, int end})> items) {
    final sorted = items.toList()..sort((a, b) => a.start.compareTo(b.start));
    final laneEnds = <int>[];
    final result = <String, int>{};
    for (final item in sorted) {
      var lane = laneEnds.indexWhere((end) => end <= item.start);
      if (lane < 0) {
        if (laneEnds.length < _maxLanes) {
          laneEnds.add(item.end);
          lane = laneEnds.length - 1;
        } else {
          lane = _maxLanes - 1;
          laneEnds[lane] = math.max(laneEnds[lane], item.end);
        }
      } else {
        laneEnds[lane] = item.end;
      }
      result[item.id] = lane;
    }
    return result;
  }

  List<Widget> _handles({
    required double left,
    required double right,
    required double top,
    required double height,
    required Color color,
    required Object base,
    required void Function(_Edge edge, double dx) onDrag,
  }) {
    Widget handle(_Edge edge) => Positioned(
          left: edge == _Edge.start ? left - _handleWidth : right,
          top: top,
          width: _handleWidth,
          height: height,
          child: _Handle(
            start: edge == _Edge.start,
            color: color,
            onStart: () => _startDrag(base),
            onUpdate: (dx) => onDrag(edge, dx),
            onEnd: _endDrag,
          ),
        );
    return [handle(_Edge.start), handle(_Edge.end)];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [_s.editor, _s.selection, _s.zoom, _s.playback, _s.pictures, _s.part]),
      builder: (context, _) => LayoutBuilder(builder: _buildTimeline),
    );
  }

  Widget _buildTimeline(BuildContext context, BoxConstraints box) {
    final project = _s.project;
    final selection = _s.selection.value;
    _overlayRow = project.overlays.isNotEmpty;
    final compact = box.maxWidth < TimelineView.compactBelow;
    _compact = compact;
    final overlayTop = _firstRowTop;
    final headerWidth = TimelineView.headerWidthFor(box.maxWidth);
    final tracks = project.soundTracks;
    final trackRow = {
      for (var i = 0; i < tracks.length; i++) tracks[i].id: i,
    };
    final titleLanes = _lanes([
      for (final t in project.titles)
        (id: t.id, start: t.startMs, end: t.endMs),
    ]);
    int rows(Map<String, int> lanes) =>
        lanes.isEmpty ? 1 : lanes.values.reduce(math.max) + 1;
    final audioRows = math.max(1, tracks.length);
    final titleRows = rows(titleLanes);

    final audioTop = _clipTop + _clipHeight + 8;
    _audioTop = audioTop;
    _trackIds = [for (final t in tracks) t.id];
    double rowTop(String trackId) =>
        audioTop + (trackRow[trackId] ?? 0) * (_laneHeight + _laneGap);
    // Many captions, zoomed out: the blocks are too narrow to read, so
    // the caption under the playhead is shown as one line above them.
    final captions = _captionDoc(project);
    var captionMs = 0;
    for (final l in captions.lines) {
      captionMs += l.endMs - l.startMs;
    }
    final stripShown = captions.lines.length >= 3 &&
        captionMs / captions.lines.length * _pxPerMs < _readableCaption;
    final stripTop = audioTop + audioRows * (_laneHeight + _laneGap) + 2;
    final titleTop = stripTop + (stripShown ? _stripHeight + _laneGap : 0);
    final height = titleTop + titleRows * (_laneHeight + _laneGap) + 10;

    var endMs = project.durationMs;
    for (final a in project.audio) {
      endMs = math.max(endMs, a.endMs);
    }
    for (final t in project.titles) {
      endMs = math.max(endMs, t.endMs);
    }
    for (final o in project.overlays) {
      endMs = math.max(endMs, o.endMs);
    }
    final viewWidth = math.max(0.0, box.maxWidth - headerWidth);
    final width = math.max(viewWidth, _x(endMs) + _padRight);

    // The window of the timeline that is built: the view and at least one
    // view's width (1600 px) on each side.
    _viewWidth = viewWidth;
    final offset = (_zoomOffset ?? (_scroll.hasClients ? _scroll.offset : 0.0))
        .clamp(0.0, math.max(0.0, width - viewWidth))
        .toDouble();
    final base = _windowBase(offset);
    _builtBase = base;
    final margin = math.max(1600.0, viewWidth);
    final winStart = math.max(0.0, base - margin);
    final winEnd = math.min(width, base + _chunk + viewWidth + margin);
    final msLo = _ms(winStart);
    final msHi = _ms(winEnd) + 1;
    bool near(double left, double w) => left + w >= winStart && left <= winEnd;

    final children = <Widget>[
      // Tapping empty space moves the playhead there.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            _s.clearSelection();
            // "Tap elsewhere clears it": the selected part too.
            _s.clearPart();
            _s.playback.seek(_ms(d.localPosition.dx));
          },
          // Right-click / long press on an empty place: what can be added
          // there.
          onSecondaryTapUp: (d) => _openContext(
              _emptyTarget(_ms(d.localPosition.dx)), d.globalPosition,
              touch: false),
          onLongPressStart: (d) => _openContext(
              _emptyTarget(_ms(d.localPosition.dx)), d.globalPosition,
              touch: true),
        ),
      ),
      for (var row = 0; row < audioRows; row++)
        _laneBackground(
          top: audioTop + row * (_laneHeight + _laneGap),
          width: width,
          icon: Icons.music_note,
          hint: tracks.isEmpty
              ? 'Music'
              : (project.clipsOnTrack(tracks[row].id).isEmpty
                  ? 'Empty: add music or drag sound here'
                  : null),
        ),
      if (_overlayRow)
        _laneBackground(
            top: overlayTop, width: width, icon: Icons.picture_in_picture_alt),
      for (var row = 0; row < titleRows; row++)
        _laneBackground(
          top: titleTop + row * (_laneHeight + _laneGap),
          width: width,
          icon: Icons.title,
          hint: row == 0 && project.titles.isEmpty ? 'Titles and captions' : null,
        ),
      Positioned(
        left: 0,
        top: 0,
        width: width,
        height: _rulerHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The ruler moves the playhead, as always. With Shift held it
          // selects a part instead: a click extends the part to there, a
          // drag marks a new one (from where the button went down, not
          // from where the drag was recognised).
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (d) {
            if (_shift) return;
            _s.playback.seek(_ms(d.localPosition.dx));
          },
          onTapUp: (d) {
            if (_shift) _s.extendPartTo(_ms(d.localPosition.dx));
          },
          onHorizontalDragStart: (d) => _shift
              ? _partDragStart(d.localPosition.dx)
              : _s.playback.seek(_ms(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) => _partAnchor != null
              ? _partDragTo(d.localPosition.dx)
              : _s.playback.seek(_ms(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => _partDragEnd(),
          onHorizontalDragCancel: _partDragEnd,
        ),
      ),
      // The strip under the ruler: drag along it to select a part.
      if (_partStrip > 0)
        Positioned(
          key: const ValueKey('part-strip'),
          left: 0,
          top: _rulerHeight,
          width: width,
          height: _partStrip,
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) {
                final ms = _ms(d.localPosition.dx);
                if (_shift) {
                  _s.extendPartTo(ms);
                } else if (!(_s.part.value?.contains(ms) ?? false)) {
                  _s.clearPart();
                }
              },
              onSecondaryTapUp: (d) => _openContext(
                  _emptyTarget(_ms(d.localPosition.dx)), d.globalPosition,
                  touch: false),
              onHorizontalDragStart: (d) => _partDragStart(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _partDragTo(d.localPosition.dx),
              onHorizontalDragEnd: (_) => _partDragEnd(),
              onHorizontalDragCancel: _partDragEnd,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x14FFFFFF),
                  border: Border(
                      bottom: BorderSide(color: AppColors.outline)),
                ),
              ),
            ),
          ),
        ),
      // "Good moment" markers: small flags on the ruler (a tap goes there).
      for (final m in project.markers)
        if (_x(m.ms) >= winStart - 20 && _x(m.ms) <= winEnd + 20)
          Positioned(
            key: ValueKey('marker-${m.id}'),
            left: _x(m.ms) - 9,
            top: 0,
            width: 18,
            height: _rulerHeight,
            child: Tooltip(
              message: m.label.isEmpty
                  ? 'Good moment at ${formatTime(m.ms)}'
                  : '${m.label} (${formatTime(m.ms)})',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _s.playback.seek(m.ms),
                onSecondaryTapUp: (d) => _openContext(
                    TimelineTarget.marker(m.id, m.ms), d.globalPosition,
                    touch: false),
                onLongPressStart: (d) => _openContext(
                    TimelineTarget.marker(m.id, m.ms), d.globalPosition,
                    touch: true),
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: Icon(Icons.flag, size: 15, color: Color(0xFFFFC56B)),
                ),
              ),
            ),
          ),
      // The ruler is drawn for the window only.
      Positioned(
        left: winStart,
        top: 0,
        width: math.max(0.0, winEnd - winStart),
        height: _rulerHeight,
        child: IgnorePointer(
          child: CustomPaint(
            painter: _RulerPainter(
              pixelsPerSecond: _s.zoom.value,
              padLeft: _padLeft,
              originX: winStart,
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
            ),
          ),
        ),
      ),
    ];

    // Main track. Blocks sit where they play: a transition makes a clip
    // start before the previous one has ended, so the two overlap and the
    // later block is drawn over the end of the earlier one.
    final reorderId = project.clips.any((c) => c.id == _reorderId)
        ? _reorderId
        : null;
    Widget? lifted;
    // The clips in the window (the one before too: with a transition it
    // reaches into it), and the one being dragged wherever it is.
    final shown = <int>[];
    if (project.clips.isNotEmpty) {
      for (var i = math.max(0, project.clipIndexAt(msLo) - 1);
          i < project.clips.length && project.clipStartMs(i) <= msHi;
          i++) {
        shown.add(i);
      }
      if (reorderId != null) {
        final r = project.clips.indexWhere((c) => c.id == reorderId);
        if (!shown.contains(r)) shown.add(r);
      }
    }
    for (final i in shown) {
      final clip = project.clips[i];
      final left = _x(project.clipStartMs(i));
      final w = math.max(2.0, clip.durationMs * _pxPerMs);
      final selected =
          selection?.kind == ItemKind.clip && selection?.id == clip.id;
      final dragged = clip.id == reorderId;
      final blockWidget = _ClipBlock(
        clip: clip,
        width: w,
        selected: selected,
        missing: _s.playback.isMissing(clip.path),
        session: _s,
        pxPerMs: _pxPerMs,
        visibleFrom: (winStart - left).clamp(0.0, w).toDouble(),
        visibleTo: (winEnd - left).clamp(0.0, w).toDouble(),
        onTap: () {
          // A second click right after the first: this clip's time is
          // selected as the part.
          if (_secondTap('clip-${clip.id}')) {
            _s.select(ItemKind.clip, clip.id);
            _s.setPart(project.clipStartMs(i), project.clipEndMs(i));
          } else {
            _s.selectClipAndShow(clip.id);
          }
        },
        onContext: (global) => _openContext(
            TimelineTarget.item(ItemKind.clip, clip.id), global,
            touch: false),
        onPressStart: (global) => _pressStart(clip, global),
        onPressUpdate: _pressUpdate,
        onPressEnd: () => _pressEnd(clip),
        onReorderStart: (global) => _reorderStart(clip, global),
        onReorderUpdate: _reorderUpdate,
        onReorderEnd: _reorderEnd,
        onReorderCancel: () => _reorderEnd(cancelled: true),
      );
      // The block keeps its place in the tree while it is dragged (so the
      // gesture carries on); a copy of it follows the pointer.
      children.add(Positioned(
        key: ValueKey('clip-${clip.id}'),
        left: left,
        top: _clipTop,
        width: w,
        height: _clipHeight,
        child: Opacity(opacity: dragged ? 0.3 : 1, child: blockWidget),
      ));
      if (dragged) {
        final liftedLeft = _reorderX - _reorderGrab;
        lifted = Positioned(
          left: liftedLeft,
          top: _clipTop - 6,
          width: w,
          height: _clipHeight,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.9,
              child: _ClipBlock(
                clip: clip,
                width: w,
                selected: true,
                missing: _s.playback.isMissing(clip.path),
                session: _s,
                pxPerMs: _pxPerMs,
                visibleFrom: (winStart - liftedLeft).clamp(0.0, w).toDouble(),
                visibleTo: (winEnd - liftedLeft).clamp(0.0, w).toDouble(),
              ),
            ),
          ),
        );
      }
    }

    // Sound clips, one row per track.
    for (final a in project.audio) {
      final selected =
          selection?.kind == ItemKind.audio && selection?.id == a.id;
      final w = math.max(2.0, a.durationMs * _pxPerMs);
      // The selected one stays built: it may be being dragged.
      if (!selected && !near(_x(a.startMs), w)) continue;
      final missing = _s.playback.isMissing(a.path);
      final heard = project.trackGainOf(a.trackId) > 0;
      final left = _x(a.startMs);
      final peaks = missing
          ? null
          : _s.pictures.peaksOf(a.path, a.soundClip.audioTrackInUse);
      final speaker = _s.pictures.isSpeech(a)
          ? speechTrackColor(project, a.trackId)
          : null;
      final talk = speaker == null ? null : _s.pictures.speechOf(a);
      final from = (winStart - left).clamp(0.0, w).toDouble();
      final to = (winEnd - left).clamp(0.0, w).toDouble();
      children.add(Positioned(
        key: ValueKey('audio-${a.id}'),
        left: _x(a.startMs),
        top: rowTop(a.trackId),
        width: w,
        height: _laneHeight,
        child: Opacity(
          opacity: heard ? 1 : 0.45,
          child: _LaneBlock(
            // A speech track has its speaker's colour: dim where nobody
            // talks, full where that speaker does.
            color: missing
                ? AppColors.missing
                : speaker == null
                    ? AppColors.audio
                    : Color.lerp(speaker, AppColors.panel, talk == null ? 0.45 : 0.68)!,
            background: peaks == null || to <= from
                ? null
                : Positioned(
                    left: from,
                    width: to - from,
                    top: 0,
                    bottom: 0,
                    child: CustomPaint(
                      key: ValueKey('wave-${a.id}'),
                      painter: WavePainter(
                        peaks: peaks,
                        inMs: a.inMs,
                        outMs: a.outMs,
                        speed: a.speed,
                        pxPerMs: _pxPerMs,
                        fromX: from,
                        toX: to,
                        passMs: a.looped ? a.passMs - a.loopCrossfadeMs : 0,
                        quiet: a.quiet,
                        gate: _s.gates[a.id],
                        stretches: talk,
                        band: speaker?.withValues(alpha: 0.75),
                        color: const Color(0xD9FFFFFF),
                        quietColor: speaker == null
                            ? const Color(0x8CFFFFFF)
                            : const Color(0x59FFFFFF),
                      ),
                    ),
                  ),
            icon: missing
                ? Icons.error_outline
                : a.looped
                    ? Icons.repeat
                    : (a.belongsToClip
                        ? Icons.record_voice_over
                        : Icons.music_note),
            label: a.isVoice
                ? '${a.linked ? 'Voice' : 'Voice (not linked)'} · '
                    '${fileName(a.path)}'
                : a.isSeparated
                ? 'Sound · ${fileName(a.path)}'
                : '${a.credit?.title ?? fileName(a.path)}'
                    '${a.looped ? ' · loops' : ''}',
            width: w,
            // Where a looped sound starts again.
            marks: a.looped
                ? [
                    for (final piece in a.loopPieces.skip(1))
                      (piece.startMs - a.startMs) * _pxPerMs,
                  ]
                : const [],
            // What plays after the video has ended is not heard.
            dimFrom: a.endMs > project.durationMs
                ? math.max(0.0, (project.durationMs - a.startMs) * _pxPerMs)
                : null,
            selected: selected,
            onTap: () => _s.select(ItemKind.audio, a.id),
            // Double-click: on a voice, this speaker's turn; else the
            // sound's own time.
            onTapAt: (dx) {
              if (!_secondTap('audio-${a.id}')) return;
              final at = a.startMs + (dx / _pxPerMs).round();
              final turn = speaker == null ? null : _s.turnAt(a.trackId, at);
              turn != null
                  ? _s.setPart(turn.startMs, turn.endMs)
                  : _s.setPart(a.startMs, a.endMs);
            },
            onContext: (global, touch) => _openContext(
                TimelineTarget.item(ItemKind.audio, a.id), global,
                touch: touch),
            onDragStart: () => _startDrag(a),
            onDragUpdate: (dx, global) => _dragAudio(_Edge.body, dx, global),
            onDragEnd: _endDrag,
          ),
        ),
      ));
    }

    // Overlay items, on the row above the main track.
    for (final o in project.overlays) {
      final selected =
          selection?.kind == ItemKind.overlay && selection?.id == o.id;
      final w = math.max(2.0, o.durationMs * _pxPerMs);
      if (!selected && !near(_x(o.startMs), w)) continue;
      final missing = _s.playback.isMissing(o.path);
      children.add(Positioned(
        key: ValueKey('overlay-${o.id}'),
        left: _x(o.startMs),
        top: overlayTop,
        width: w,
        height: _laneHeight,
        child: _LaneBlock(
          color: missing ? AppColors.missing : AppColors.overlay,
          icon: missing
              ? Icons.error_outline
              : (o.clip.type == ClipType.photo
                  ? Icons.image_outlined
                  : Icons.picture_in_picture_alt),
          label: 'Overlay · ${fileName(o.path)}',
          width: w,
          dimFrom: o.endMs > project.durationMs
              ? math.max(0.0, (project.durationMs - o.startMs) * _pxPerMs)
              : null,
          selected: selected,
          onTap: () => _s.selectOverlayAndShow(o.id),
          onTapAt: (_) {
            if (_secondTap('overlay-${o.id}')) _s.setPart(o.startMs, o.endMs);
          },
          onContext: (global, touch) => _openContext(
              TimelineTarget.item(ItemKind.overlay, o.id), global,
              touch: touch),
          onDragStart: () => _startDrag(o),
          onDragUpdate: (dx, _) => _dragOverlay(_Edge.body, dx),
          onDragEnd: _endDrag,
        ),
      ));
    }

    // Titles.
    for (final t in project.titles) {
      final selected =
          selection?.kind == ItemKind.title && selection?.id == t.id;
      final w = math.max(2.0, (t.endMs - t.startMs) * _pxPerMs);
      if (!selected && !near(_x(t.startMs), w)) continue;
      children.add(Positioned(
        key: ValueKey('title-${t.id}'),
        left: _x(t.startMs),
        top: titleTop + titleLanes[t.id]! * (_laneHeight + _laneGap),
        width: w,
        height: _laneHeight,
        child: _LaneBlock(
          slim: w < _slimBelow,
          tooltip: w < 44 ? t.text.replaceAll('\n', ' ') : null,
          color: t.kind == TitleKind.caption
              ? AppColors.caption
              : AppColors.title,
          icon: t.kind == TitleKind.caption
              ? Icons.closed_caption_outlined
              : Icons.title,
          label: t.text.replaceAll('\n', ' '),
          width: w,
          selected: selected,
          onTap: () => _s.select(ItemKind.title, t.id),
          onTapAt: (_) {
            if (_secondTap('title-${t.id}')) _s.setPart(t.startMs, t.endMs);
          },
          onContext: (global, touch) => _openContext(
              TimelineTarget.item(ItemKind.title, t.id), global,
              touch: touch),
          onDragStart: () => _startDrag(t),
          onDragUpdate: (dx, _) => _dragTitle(_Edge.body, dx),
          onDragEnd: _endDrag,
        ),
      ));
    }

    // The selected part (1.17): a highlight across every row, its length
    // in the strip, and a handle on each edge. It lives in the scrolled
    // content, so it stays where it is through scrolling and zooming.
    final part = _s.part.value;
    if (part != null) {
      final left = _x(part.startMs);
      final right = _x(part.endMs);
      children.add(Positioned(
        key: const ValueKey('part-band'),
        left: left,
        top: 0,
        width: math.max(1.0, right - left),
        height: height,
        child: const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x2E7C9BFF),
              border: Border.symmetric(
                  vertical: BorderSide(color: AppColors.accent, width: 1.5)),
            ),
          ),
        ),
      ));
      if (_partStrip > 0 && right - left >= 46) {
        children.add(Positioned(
          left: left + 4,
          top: _rulerHeight,
          width: right - left - 8,
          height: _partStrip,
          child: IgnorePointer(
            child: Center(
              child: Text(
                formatLength(part.lengthMs),
                key: const ValueKey('part-band-length'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
        ));
      }
      // Computers: grips in the strip. Phones: tabs a thumb can hold, on
      // the ruler.
      final hw = compact ? 30.0 : 12.0;
      final top = compact ? 0.0 : _rulerHeight - 3;
      final hh = compact ? _firstRowTop : _partStrip + 6;
      for (final start in [true, false]) {
        children.add(Positioned(
          key: ValueKey(start ? 'part-handle-start' : 'part-handle-end'),
          left: start ? left - hw : right,
          top: top,
          width: hw,
          height: hh,
          child: _PartHandle(
            start: start,
            big: compact,
            onStart: () => _partEdgeStart(start),
            onUpdate: (dx) => _partEdgeDrag(start, dx),
            onEnd: _partDragEnd,
          ),
        ));
      }
    }

    // Trim handles of the selected item, drawn over its neighbours.
    final clip = _s.selectedClip;
    final audio = _s.selectedAudio;
    final title = _s.selectedTitle;
    final overlay = _s.selectedOverlay;
    if (reorderId != null) {
      // The place the dragged clip would be dropped.
      final others = [
        for (var i = 0; i < project.clips.length; i++)
          if (project.clips[i].id != reorderId) i,
      ];
      final from = project.clips.indexWhere((c) => c.id == reorderId);
      final to = _reorderTarget(project, reorderId);
      if (to != from && others.isNotEmpty) {
        final x = to < others.length
            ? _x(project.clipStartMs(others[to]))
            : _x(project.clipEndMs(others.last));
        children.add(Positioned(
          key: const ValueKey('reorder-target'),
          left: x - 2,
          top: _clipTop - 5,
          width: 4,
          height: _clipHeight + 10,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ));
      }
      children.add(lifted!);
    } else if (clip != null) {
      final left = _x(project.clipStartMs(project.clips.indexOf(clip)));
      children.addAll(_handles(
        left: left,
        right: left + math.max(2.0, clip.durationMs * _pxPerMs),
        top: _clipTop,
        height: _clipHeight,
        color: AppColors.accent,
        base: clip,
        onDrag: _dragClip,
      ));
    } else if (audio != null) {
      children.addAll(_handles(
        left: _x(audio.startMs),
        right: _x(audio.startMs) + math.max(2.0, audio.durationMs * _pxPerMs),
        top: rowTop(audio.trackId),
        height: _laneHeight,
        color: AppColors.accent,
        base: audio,
        onDrag: (edge, dx) => _dragAudio(edge, dx),
      ));
    } else if (overlay != null) {
      children.addAll(_handles(
        left: _x(overlay.startMs),
        right:
            _x(overlay.startMs) + math.max(2.0, overlay.durationMs * _pxPerMs),
        top: overlayTop,
        height: _laneHeight,
        color: AppColors.accent,
        base: overlay,
        onDrag: _dragOverlay,
      ));
    } else if (title != null) {
      children.addAll(_handles(
        left: _x(title.startMs),
        right: _x(title.startMs) +
            math.max(2.0, (title.endMs - title.startMs) * _pxPerMs),
        top: titleTop + titleLanes[title.id]! * (_laneHeight + _laneGap),
        height: _laneHeight,
        color: AppColors.accent,
        base: title,
        onDrag: _dragTitle,
      ));
    }

    // Transitions: a light band over the stretch where two clips overlap
    // and a badge on its top edge (clear of the trim handles).
    if (reorderId == null) {
      for (final i in shown) {
        if (i < 1) continue;
        final clip = project.clips[i];
        final overlap = project.transitionOverlapMs(i);
        if (overlap <= 0) continue;
        final left = _x(project.clipStartMs(i));
        final w = overlap * _pxPerMs;
        children.add(Positioned(
          left: left,
          top: _clipTop,
          width: w,
          height: _clipHeight,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x40FFFFFF),
                border: Border.symmetric(
                    vertical: BorderSide(color: Colors.white70)),
              ),
            ),
          ),
        ));
        children.add(Positioned(
          key: ValueKey('transition-${clip.id}'),
          left: left + w / 2 - _transitionBadge / 2,
          top: _clipTop - _transitionBadge / 2 + 2,
          width: _transitionBadge,
          height: _transitionBadge,
          child: _TransitionMarker(
            type: clip.transition,
            onTap: () {
              _s.selectClipAndShow(clip.id);
              _s.openTool.value = ClipTool.transition;
              widget.onTransitionTap?.call();
            },
          ),
        ));
      }
    }

    final pinching = _pointers.length >= 2;
    final scrolled = Listener(
        onPointerSignal: _onPointerSignal,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        onPointerPanZoomStart: (_) => _pinchZoom = _s.zoom.value,
        onPointerPanZoomUpdate: (e) {
          if (e.scale != 1) _s.setZoom(_pinchZoom * e.scale);
        },
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: pinching
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            // Scrolling moves the painted content; it is painted again
            // only when the window or the project changes.
            child: RepaintBoundary(
              child: SizedBox(
                key: _contentKey,
                width: width,
                height: height,
                child: Stack(clipBehavior: ui.Clip.none, children: children),
              ),
            ),
          ),
        ),
    );
    // The playhead is drawn over the scrolled content, in a layer of its
    // own: during playback only it is painted again.
    final timeline = Stack(
      children: [
        Positioned.fill(child: scrolled),
        // Where a drag snapped (a thin yellow line), while it does.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('snap-line'),
              painter: _SnapLinePainter(
                line: _s.snapLine,
                scroll: _scroll,
                padLeft: _padLeft,
                pxPerMs: _pxPerMs,
              ),
            ),
          ),
        ),
        if (stripShown)
          Positioned(
            left: 0,
            right: 0,
            top: stripTop,
            height: _stripHeight,
            child: _CaptionStrip(session: _s, captions: captions),
          ),
        if (_partStrip > 0 && part == null && project.clips.isNotEmpty)
          Positioned(
            left: 8,
            top: _rulerHeight,
            height: _partStrip,
            child: const IgnorePointer(
              child: Center(
                child: Text('Drag here to select a part',
                    key: ValueKey('part-strip-hint'),
                    style: TextStyle(
                        fontSize: 10, height: 1.0, color: AppColors.textDim)),
              ),
            ),
          ),
        Positioned(
          right: 8,
          top: 3,
          child: ListenableBuilder(
            listenable: Listenable.merge([_s.pictures, _s.backgroundPaused]),
            builder: (context, _) {
              final pics = _s.pictures;
              if (!pics.pausedForApp && _s.backgroundPaused.value) {
                // The generic safety valve (1.18): something else than
                // the sound waves was (or might have been) in the way.
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'Background work was paused to keep ClipForge '
                        'responsive · ',
                        key: ValueKey('background-paused'),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textDim)),
                    InkWell(
                      key: const ValueKey('background-resume'),
                      onTap: BackgroundWork.instance.resumeAll,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text('Turn back on',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.accent,
                                decoration: TextDecoration.underline)),
                      ),
                    ),
                  ],
                );
              }
              if (pics.pausedForApp) {
                // The safety valve: one line, and the way back.
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'Sound waves were paused to keep ClipForge '
                        'responsive · ',
                        key: ValueKey('sound-waves-paused'),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textDim)),
                    InkWell(
                      key: const ValueKey('sound-waves-resume'),
                      onTap: () {
                        pics.resume();
                        BackgroundWork.instance.resumeAll();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text('Turn back on',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.accent,
                                decoration: TextDecoration.underline)),
                      ),
                    ),
                  ],
                );
              }
              if (!pics.busy) return const SizedBox.shrink();
              final total = pics.totalCount;
              final at = math.min(total, pics.doneCount + 1);
              // "Drawing sound… 1 of 3" with a ✕ that stops it: the sound
              // pictures are a nicety, never something to wait for.
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      total > 1
                          ? 'Drawing sound… $at of $total'
                          : 'Drawing sound…',
                      key: const ValueKey('drawing-sound'),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textDim)),
                  Tooltip(
                    message: 'Stop drawing the sound (the video works '
                        'without it)',
                    child: InkWell(
                      key: const ValueKey('drawing-sound-stop'),
                      onTap: pics.stop,
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.close,
                            size: 13,
                            color: AppColors.textDim,
                            semanticLabel: 'Stop drawing the sound'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PlayheadPainter(
                  position: _s.playback.position,
                  scroll: _scroll,
                  padLeft: _padLeft,
                  pxPerMs: _pxPerMs,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: headerWidth,
            child: TrackHeaders(
              session: _s,
              compact: compact,
              rulerHeight: _rulerHeight,
              clipTop: _clipTop,
              overlayTop: _overlayRow ? overlayTop : null,
              clipHeight: _clipHeight,
              audioTop: audioTop,
              rowHeight: _laneHeight,
              rowGap: _laneGap,
              titleTop: titleTop,
              titleRows: titleRows,
            ),
          ),
          Expanded(child: timeline),
        ],
      ),
    );
  }

  Widget _laneBackground({
    required double top,
    required double width,
    required IconData icon,
    String? hint,
  }) {
    return Positioned(
      left: 0,
      top: top,
      width: width,
      height: _laneHeight,
      child: IgnorePointer(
        child: Container(
          color: const Color(0x0DFFFFFF),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: _padLeft),
          child: hint == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: AppColors.textDim),
                    const SizedBox(width: 6),
                    Text(hint,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A block on the main track.
class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.clip,
    required this.width,
    required this.selected,
    required this.missing,
    required this.session,
    required this.pxPerMs,
    required this.visibleFrom,
    required this.visibleTo,
    this.onTap,
    this.onContext,
    this.onPressStart,
    this.onPressUpdate,
    this.onPressEnd,
    this.onReorderStart,
    this.onReorderUpdate,
    this.onReorderEnd,
    this.onReorderCancel,
  });

  /// Right-click: the clip's context menu.
  final ValueChanged<Offset>? onContext;

  /// A long press (finger or mouse): picks the clip up; let go without
  /// moving, it opens the context menu.
  final ValueChanged<Offset>? onPressStart;
  final ValueChanged<Offset>? onPressUpdate;
  final VoidCallback? onPressEnd;
  final Clip clip;
  final double width;
  final bool selected;
  final bool missing;
  final EditorSession session;
  final VoidCallback? onTap;

  /// Timeline scale, and the part of the block (from its left edge) that
  /// is near the view: only there are thumbnails drawn.
  final double pxPerMs;
  final double visibleFrom;
  final double visibleTo;

  /// Dragging the block to a new place: after a long press with a finger,
  /// straight away with a mouse. Positions are global.
  final ValueChanged<Offset>? onReorderStart;
  final ValueChanged<Offset>? onReorderUpdate;
  final VoidCallback? onReorderEnd;
  final VoidCallback? onReorderCancel;

  @override
  Widget build(BuildContext context) {
    final isPhoto = clip.type == ClipType.photo;
    final color = missing
        ? AppColors.missing
        : (isPhoto ? AppColors.photo : AppColors.clip);
    final roomy = width >= 44;
    final name = fileName(clip.path);
    // The clip's own sound, when it is heard, along the bottom.
    final wave = isPhoto || missing || !clip.hasAudio || clip.muted
        ? null
        : session.pictures.peaksOf(clip.path, clip.audioTrackInUse);
    return Semantics(
      label: '${missing ? 'Missing file' : (isPhoto ? 'Photo' : 'Video')} $name',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp:
            onContext == null ? null : (d) => onContext!(d.globalPosition),
        onLongPressStart: onPressStart == null
            ? null
            : (d) => onPressStart!(d.globalPosition),
        onLongPressMoveUpdate: onPressUpdate == null
            ? null
            : (d) => onPressUpdate!(d.globalPosition),
        onLongPressEnd: onPressEnd == null ? null : (_) => onPressEnd!(),
        onLongPressCancel: onReorderCancel,
        child: GestureDetector(
          // A mouse does not scroll the timeline by dragging, so it can
          // pick a clip up at once.
          supportedDevices: const {PointerDeviceKind.mouse},
          onHorizontalDragStart: onReorderStart == null
              ? null
              : (d) => onReorderStart!(d.globalPosition),
          onHorizontalDragUpdate: onReorderUpdate == null
              ? null
              : (d) => onReorderUpdate!(d.globalPosition),
          onHorizontalDragEnd:
              onReorderEnd == null ? null : (_) => onReorderEnd!(),
          onHorizontalDragCancel: onReorderCancel,
          child: Container(
          margin: const EdgeInsets.only(right: 1),
          clipBehavior: ui.Clip.antiAlias,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.accent : const Color(0x33FFFFFF),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!missing && visibleTo > visibleFrom)
                Positioned(
                  left: visibleFrom,
                  width: visibleTo - visibleFrom,
                  top: 0,
                  bottom: 0,
                  child: !isPhoto && session.thumbnails.hasStrips
                      ? _ClipThumbs(
                          clip: clip,
                          thumbnails: session.thumbnails,
                          pxPerMs: pxPerMs,
                          from: visibleFrom,
                          to: visibleTo,
                        )
                      : Opacity(
                          opacity: 0.85,
                          child: MediaThumb(
                            path: clip.path,
                            thumbnails: session.thumbnails,
                            // One frame per ~5 s of trim is plenty for a
                            // strip.
                            timeMs: clip.inMs - clip.inMs % 5000,
                            fit: BoxFit.fitHeight,
                            repeat: ImageRepeat.repeatX,
                          ),
                        ),
                ),
              if (wave != null && visibleTo > visibleFrom)
                Positioned(
                  left: visibleFrom,
                  width: visibleTo - visibleFrom,
                  bottom: 0,
                  height: 15,
                  child: ColoredBox(
                    color: const Color(0x8C000000),
                    child: CustomPaint(
                      key: ValueKey('wave-${clip.id}'),
                      painter: WavePainter(
                        peaks: wave,
                        inMs: clip.inMs,
                        outMs: clip.outMs,
                        speed: clip.speed,
                        pxPerMs: pxPerMs,
                        fromX: visibleFrom,
                        toX: visibleTo,
                        color: const Color(0xE6FFFFFF),
                        quietColor: const Color(0x8CFFFFFF),
                        fromBottom: true,
                        quiet: clip.quiet,
                      ),
                    ),
                  ),
                ),
              if (roomy)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x00000000), Color(0x99000000)],
                    ),
                  ),
                ),
              if (roomy)
                Positioned(
                  left: 6,
                  top: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatSeconds(clip.durationMs),
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                      if (!isPhoto && clip.speed != 1 && width >= 76) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatSpeed(clip.speed),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                      // Sound settings that are on, so that a switch in
                      // the Sound panel is visible on the timeline.
                      if (!isPhoto &&
                          clip.hasAudio &&
                          !clip.muted &&
                          (clip.denoise || clip.voiceFocus >= 0.005) &&
                          width >= 76) ...[
                        const SizedBox(width: 5),
                        Container(
                          key: ValueKey('sound-badge-${clip.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (clip.denoise)
                                const Tooltip(
                                  message: 'Clean up sound is on',
                                  child: Icon(Icons.auto_fix_high,
                                      size: 11, color: Colors.black),
                                ),
                              if (clip.voiceFocus >= 0.005)
                                const Tooltip(
                                  message: 'Voice focus is on',
                                  child: Icon(Icons.record_voice_over,
                                      size: 11, color: Colors.black),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Instant sound processing: progress of this clip's sound.
              if (!isPhoto && !missing)
                ClipSoundProgress(session: session, clip: clip, roomy: roomy),
              if (roomy && (missing || clip.muted || isPhoto))
                Positioned(
                  right: 5,
                  top: 4,
                  child: Icon(
                    missing
                        ? Icons.error_outline
                        : (clip.muted ? Icons.volume_off : Icons.image_outlined),
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              if (roomy)
                Positioned(
                  left: 6,
                  right: 4,
                  bottom: wave == null ? 4 : 16,
                  child: Text(
                    missing ? 'Missing · $name' : name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// The thumbnails along a video block, from the file's thumbnail strip:
/// one tile per picture width, each showing the frame nearest its place,
/// built only between [from] and [to] (block coordinates).
class _ClipThumbs extends StatelessWidget {
  const _ClipThumbs({
    required this.clip,
    required this.thumbnails,
    required this.pxPerMs,
    required this.from,
    required this.to,
  });
  final Clip clip;
  final ThumbnailCache thumbnails;
  final double pxPerMs;
  final double from;
  final double to;

  static const _opacity = AlwaysStoppedAnimation<double>(0.85);

  @override
  Widget build(BuildContext context) {
    final ready = thumbnails.stripNow(clip.path);
    if (ready != null) return _tiles(ready);
    return FutureBuilder<ThumbnailStrip?>(
      future: thumbnails.strip(clip.path, durationMs: clip.sourceDurationMs),
      builder: (context, snapshot) {
        final strip = snapshot.data;
        return strip == null ? const SizedBox.shrink() : _tiles(strip);
      },
    );
  }

  Widget _tiles(ThumbnailStrip strip) {
    final aspect =
        clip.width > 0 && clip.height > 0 ? clip.width / clip.height : 16 / 9;
    final tile = (_TimelineViewState._clipHeight * aspect)
        .clamp(28.0, 112.0)
        .toDouble();
    final first = (from / tile).floor();
    final last = (to / tile).ceil();
    return Stack(
      clipBehavior: ui.Clip.hardEdge,
      children: [
        for (var k = first; k < last; k++)
          Positioned(
            left: k * tile - from,
            top: 0,
            bottom: 0,
            width: tile,
            child: Image.file(
              File(strip.frameAt(
                  clip.sourceMsAt(((k + 0.5) * tile / pxPerMs).round()))),
              fit: BoxFit.cover,
              opacity: _opacity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

/// Marks the stretch where two clips overlap in a transition.
class _TransitionMarker extends StatelessWidget {
  const _TransitionMarker({required this.type, required this.onTap});
  final TransitionType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Transition: ${transitionLabel(type)}',
      button: true,
      child: Tooltip(
        message: transitionLabel(type),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.panel, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(transitionIcon(type), size: 13, color: Colors.black),
          ),
        ),
      ),
    );
  }
}

/// A music or title block. It can be dragged along the row once selected.
class _LaneBlock extends StatelessWidget {
  const _LaneBlock({
    required this.color,
    required this.icon,
    required this.label,
    required this.width,
    required this.selected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onContext,
    this.onTapAt,
    this.dimFrom,
    this.marks = const [],
    this.background,
    this.slim = false,
    this.tooltip,
  });
  final Color color;

  /// Called after [onTap] with where in the block (x from its left edge)
  /// the tap was (double-click selects a part there).
  final ValueChanged<double>? onTapAt;

  /// Right-click (touch false) or long press (touch true): the item's
  /// context menu.
  final void Function(Offset global, bool touch)? onContext;

  /// Drawn behind the label (the waveform).
  final Widget? background;

  /// Too narrow for anything: a slim mark instead of a box.
  final bool slim;

  /// Shown when the pointer rests on the block (narrow captions).
  final String? tooltip;

  /// Thin lines at these x (a looped sound's repeats).
  final List<double> marks;
  final IconData icon;
  final String label;
  final double width;

  /// From this x on the block is greyed out (music past the video's end).
  final double? dimFrom;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDragStart;

  /// The horizontal move and where the pointer is (global coordinates).
  final void Function(double dx, Offset global) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final roomy = width >= 44;
    final block = _block(roomy);
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: tooltip == null
          ? block
          : Tooltip(
              message: tooltip!,
              waitDuration: const Duration(milliseconds: 350),
              child: block,
            ),
    );
  }

  Widget _block(bool roomy) {
    return GestureDetector(
        onTap: onTap,
        onTapUp: onTapAt == null ? null : (d) => onTapAt!(d.localPosition.dx),
        onSecondaryTapUp: onContext == null
            ? null
            : (d) => onContext!(d.globalPosition, false),
        onLongPressStart: onContext == null
            ? null
            : (d) => onContext!(d.globalPosition, true),
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: selected ? (_) => onDragStart() : null,
        onHorizontalDragUpdate: selected
            ? (d) => onDragUpdate(d.delta.dx, d.globalPosition)
            : null,
        onHorizontalDragEnd: selected ? (_) => onDragEnd() : null,
        onHorizontalDragCancel: selected ? onDragEnd : null,
        child: slim
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              )
            : Container(
          clipBehavior: ui.Clip.antiAlias,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.accent : const Color(0x33FFFFFF),
              width: selected ? 2 : 1,
            ),
          ),
          child: !roomy && dimFrom == null && marks.isEmpty && background == null
              ? null
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ?background,
                    for (final x in marks)
                      Positioned(
                        left: x,
                        top: 0,
                        bottom: 0,
                        width: 1,
                        child: const ColoredBox(color: Color(0x88FFFFFF)),
                      ),
                    if (dimFrom != null)
                      Positioned(
                        key: const ValueKey('past-the-end'),
                        left: dimFrom,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: Color(0xB3101114)),
                      ),
                    // Over a waveform the name sits on a dark tag, so that
                    // both can be read.
                    if (roomy && background != null)
                      Positioned(
                        left: 3,
                        top: 5,
                        bottom: 5,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: math.min(width - 6, 200)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xB3101114),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (roomy && background == null)
                    Positioned(
                      left: 6,
                      top: 0,
                      bottom: 0,
                      child: Icon(icon, size: 14, color: Colors.white),
                    ),
                    if (roomy && background == null)
                    Positioned(
                      left: 24,
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
    );
  }
}

/// The caption under the playhead as one readable line (shown when the
/// caption blocks are too narrow for their text). A click selects it.
class _CaptionStrip extends StatelessWidget {
  const _CaptionStrip({required this.session, required this.captions});
  final EditorSession session;
  final TextDocument captions;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: session.playback.position,
      builder: (context, ms, _) {
        final i = captions.activeLineAt(ms);
        final line = i < 0 ? null : captions.lines[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: line == null
              ? null
              : () => session.select(ItemKind.title, line.id),
          child: Container(
            key: const ValueKey('caption-strip'),
            color: AppColors.panelHigh,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.closed_caption_outlined,
                    size: 14, color: AppColors.textDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line == null ? '' : line.raw.replaceAll('\n', ' '),
                    key: const ValueKey('caption-strip-text'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textDirection: textDirectionOf(line?.raw ?? ''),
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    required this.start,
    required this.color,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });
  final bool start;
  final Color color;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(6);
    return Semantics(
      label: start ? 'Trim start' : 'Trim end',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The handle follows the finger from where it went down, also
          // when the timeline (which scrolls sideways) took a moment to
          // give the drag up.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => onStart(),
          onHorizontalDragUpdate: (d) => onUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          onHorizontalDragCancel: onEnd,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: start
                  ? const BorderRadius.horizontal(left: radius)
                  : const BorderRadius.horizontal(right: radius),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A handle on an edge of the selected part.
class _PartHandle extends StatelessWidget {
  const _PartHandle({
    required this.start,
    required this.big,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });
  final bool start;

  /// Phones: a tab wide enough for a thumb.
  final bool big;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(big ? 8 : 4);
    return Semantics(
      label: start ? 'Start of the selected part' : 'End of the selected part',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => onStart(),
          onHorizontalDragUpdate: (d) => onUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          onHorizontalDragCancel: onEnd,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: start
                  ? BorderRadius.horizontal(left: radius)
                  : BorderRadius.horizontal(right: radius),
            ),
            alignment: Alignment.center,
            child: Icon(
              start ? Icons.chevron_left : Icons.chevron_right,
              size: big ? 20 : 12,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pixelsPerSecond,
    required this.padLeft,
    this.originX = 0,
    this.fontFamily,
  });
  final double pixelsPerSecond;
  final double padLeft;

  /// Timeline x of this painter's left edge: it paints only its own
  /// stretch of the ruler.
  final double originX;
  final String? fontFamily;

  static const _steps = [0.1, 0.2, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600];

  @override
  void paint(Canvas canvas, Size size) {
    final step = _steps.firstWhere((s) => s * pixelsPerSecond >= 64,
        orElse: () => _steps.last);
    final line = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), line);
    final tick = Paint()
      ..color = AppColors.textDim
      ..strokeWidth = 1;
    final stepPx = step * pixelsPerSecond;
    final first = math.max(0, ((originX - padLeft) / stepPx).floor() - 1);
    final last = ((originX + size.width - padLeft) / stepPx).ceil();
    for (var i = first; i <= last; i++) {
      final seconds = i * step;
      final x = padLeft + seconds * pixelsPerSecond - originX;
      canvas.drawLine(
          Offset(x, size.height - 7), Offset(x, size.height - 1), tick);
      final half = x + step * pixelsPerSecond / 2;
      canvas.drawLine(
          Offset(half, size.height - 4), Offset(half, size.height - 1), line);
      final ms = (seconds * 1000).round();
      final label = step < 1 ? formatTime(ms) : formatDuration(ms);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              fontFamily: fontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x + 4, 4));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pixelsPerSecond != pixelsPerSecond ||
      old.padLeft != padLeft ||
      old.originX != originX;
}

/// The playhead, over the visible part of the timeline. Repaints by itself
/// when the position or the scroll offset changes (no rebuild).
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.position,
    required this.scroll,
    required this.padLeft,
    required this.pxPerMs,
  }) : super(repaint: Listenable.merge([position, scroll]));
  final ValueListenable<int> position;
  final ScrollController scroll;
  final double padLeft;
  final double pxPerMs;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final x = padLeft + position.value * pxPerMs - offset;
    if (x < -8 || x > size.width + 8) return;
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = AppColors.playhead;
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 6, 0, 12, 14), const Radius.circular(4)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.pxPerMs != pxPerMs ||
      old.padLeft != padLeft ||
      !identical(old.position, position) ||
      !identical(old.scroll, scroll);
}

/// The snap line ([EditorSession.snapLine]): where the edge being dragged
/// lined up with something.
class _SnapLinePainter extends CustomPainter {
  _SnapLinePainter({
    required this.line,
    required this.scroll,
    required this.padLeft,
    required this.pxPerMs,
  }) : super(repaint: Listenable.merge([line, scroll]));
  final ValueListenable<int?> line;
  final ScrollController scroll;
  final double padLeft;
  final double pxPerMs;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = line.value;
    if (ms == null) return;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final x = padLeft + ms * pxPerMs - offset;
    if (x < 0 || x > size.width) return;
    canvas.drawRect(Rect.fromLTWH(x - 0.75, 0, 1.5, size.height),
        Paint()..color = const Color(0xFFFFD60A));
  }

  @override
  bool shouldRepaint(_SnapLinePainter old) =>
      old.pxPerMs != pxPerMs ||
      old.padLeft != padLeft ||
      !identical(old.line, line) ||
      !identical(old.scroll, scroll);
}
