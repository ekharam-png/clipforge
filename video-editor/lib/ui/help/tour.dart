import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// The guided tour: a few steps that point at real buttons of the app with
/// a spotlight and a short caption.
///
/// How it fits together:
/// - Widgets the tour points at are wrapped in a [TourAnchor] with one of
///   the [TourIds]. The tour finds them by that id while it runs.
/// - [TourController] (one per app, [tourControllerProvider]) knows the
///   steps and the current one. The home screen and the editor attach
///   [TourHomeHooks] / [TourEditorHooks] so the tour can open the sample
///   project, select a clip, and close it again at the end.
/// - [TourOverlayHost] sits above the app's navigator (MaterialApp.builder)
///   and draws the spotlight and the caption over whatever screen is open.
///
/// The steps depend on the layout: phones have a tool bar at the bottom,
/// wide windows a side panel ([buildTourSteps]). The tests check that every
/// step finds its widgets at both sizes, so renaming or removing one of the
/// wrapped widgets makes them fail.

/// The ids of the widgets the tour points at.
abstract final class TourIds {
  static const newProject = 'new-project';
  static const openProjectFile = 'open-project-file';
  static const addMedia = 'add-media';
  static const timeline = 'timeline';
  static const split = 'split';
  static const toolSpeed = 'tool-speed';
  static const toolLook = 'tool-look';
  static const toolSound = 'tool-sound';
  static const inspector = 'inspector';
  static const shape = 'shape';
  static const saveStatus = 'save-status';
  static const export = 'export';
}

// Anchors ---------------------------------------------------------------------

/// Marks [child] as something the tour can point at.
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.id, required this.child});
  final String id;
  final Widget child;

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchors._add(widget.id, this);
  }

  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      TourAnchors._remove(old.id, this);
      TourAnchors._add(widget.id, this);
    }
  }

  @override
  void dispose() {
    TourAnchors._remove(widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Where the [TourAnchor]s are.
abstract final class TourAnchors {
  static final Map<String, List<_TourAnchorState>> _live = {};

  static void _add(String id, _TourAnchorState s) => (_live[id] ??= []).add(s);

  static void _remove(String id, _TourAnchorState s) {
    _live[id]?.remove(s);
    if (_live[id]?.isEmpty ?? false) _live.remove(id);
  }

  /// The anchor [id] on the screen that is in front (not one on a page
  /// further back), or null.
  static BuildContext? contextOf(String id) {
    final list = _live[id];
    if (list == null) return null;
    for (final s in list.reversed) {
      if (!s.mounted) continue;
      final route = ModalRoute.of(s.context);
      if (route != null && !route.isCurrent) continue;
      final box = s.context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) return s.context;
    }
    return null;
  }

  /// The global rectangle of the anchor [id], or null.
  static Rect? rectOf(String id) {
    final context = contextOf(id);
    if (context == null) return null;
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The rectangle around all [ids] that are on screen, or null when none
  /// is.
  static Rect? unionOf(List<String> ids) {
    Rect? out;
    for (final id in ids) {
      final r = rectOf(id);
      if (r == null) continue;
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }
}

// Steps -------------------------------------------------------------------------

/// What the editor does before a step is shown.
enum TourSetup { none, nothingSelected, selectFirstClip, openSoundTools }

class TourStep {
  const TourStep({
    required this.id,
    required this.anchors,
    required this.title,
    required this.body,
    this.inEditor = false,
    this.setup = TourSetup.none,
  });

  final String id;

  /// The [TourIds] of the widgets to point at; the spotlight covers them
  /// all.
  final List<String> anchors;
  final String title;
  final String body;

  /// Shown in the sample project (the editor) rather than the home screen.
  final bool inEditor;
  final TourSetup setup;
}

/// The tour for a window that is [wide] (side panel) or not (phone tool
/// bar); [canDrop]: files can be dragged onto the window.
List<TourStep> buildTourSteps({required bool wide, required bool canDrop}) => [
  TourStep(
    id: 'new-project',
    anchors: const [TourIds.newProject],
    title: 'Start a new video',
    body:
        'Tap "New project" to start. Inside it you add your videos, '
        'photos and music.'
        '${canDrop ? ' You can also drag them from a folder straight '
                  'onto this window.' : ''}',
  ),
  const TourStep(
    id: 'open-project-file',
    anchors: [TourIds.openProjectFile],
    title: 'Projects from another device',
    body:
        '"Open project file" opens a project you sent from your phone '
        'or computer. Next, we open a sample project to look around the '
        'editor.',
  ),
  TourStep(
    id: 'add-media',
    anchors: const [TourIds.addMedia],
    inEditor: true,
    setup: TourSetup.nothingSelected,
    title: 'Add videos and photos',
    body: wide
        ? '"Add media" puts videos and photos into your video, after the '
            'selected clip or at the end. The Add menu at the top lists '
            'everything else you can add.'
        : '"Add" lists everything you can put into your video: videos '
            'and photos, music, a voice recording, titles and captions.',
  ),
  const TourStep(
    id: 'timeline',
    anchors: [TourIds.timeline],
    inEditor: true,
    setup: TourSetup.nothingSelected,
    title: 'The timeline',
    body:
        'Your clips, in order. Tap a clip to select it. Drag its ends '
        'to trim it. Hold it and drag to move it somewhere else.',
  ),
  const TourStep(
    id: 'split',
    anchors: [TourIds.split],
    inEditor: true,
    setup: TourSetup.selectFirstClip,
    title: 'Split',
    body:
        '"Split" cuts the clip in two at the white line (the '
        'playhead). Then you can move or delete each piece.',
  ),
  TourStep(
    id: 'clip-tools',
    anchors: wide
        ? const [TourIds.inspector]
        : const [TourIds.toolSpeed, TourIds.toolLook, TourIds.toolSound],
    inEditor: true,
    setup: wide ? TourSetup.openSoundTools : TourSetup.selectFirstClip,
    title: 'Change a clip',
    body:
        '"Speed" for slow motion, "Look" for brightness and colour, '
        '"Sound" for volume. In Sound, "Clean up sound" lowers noise, '
        '"Voice focus" makes speech clearer, and "Hear a sample" lets '
        'you listen before you export.',
  ),
  TourStep(
    id: 'shape',
    anchors: const [TourIds.shape],
    inEditor: true,
    setup: TourSetup.nothingSelected,
    title: wide ? 'Shape' : 'Shape, and the project menu',
    body: wide
        ? 'Make the whole video upright for phones (9:16), wide (16:9) '
            'or square. The same choices are in the View menu; '
            'File > Settings… has the app\'s settings.'
        : 'The three dots open the project menu. "Shape and size" makes '
            'the whole video upright for phones (9:16), wide (16:9) or '
            'square. History, Text and Settings are here too.',
  ),
  const TourStep(
    id: 'save-export',
    anchors: [TourIds.saveStatus, TourIds.export],
    inEditor: true,
    setup: TourSetup.nothingSelected,
    title: 'Saved by itself, then Export',
    body:
        'Every change is saved by itself; the cloud sign shows '
        '"Saved". When you are happy, tap "Export" to make the video '
        'file.',
  ),
];

// Controller ------------------------------------------------------------------

enum TourPhase {
  /// No tour.
  idle,

  /// A step is shown.
  running,

  /// The sample project is being made and opened.
  preparing,

  /// The last card: keep the sample project or not.
  ending,

  /// The sample project is being closed.
  closing,
}

/// What the home screen does for the tour.
class TourHomeHooks {
  const TourHomeHooks({
    required this.makeSample,
    required this.openSample,
    required this.closeSample,
  });

  /// Makes the sample project; returns its id (null when it failed, after
  /// telling the user).
  final Future<String?> Function() makeSample;

  /// Opens the editor with the sample project (does not wait for it to
  /// close).
  final void Function(String projectId) openSample;

  /// After the editor closed: deletes the sample unless [keep].
  final Future<void> Function(String projectId, {required bool keep})
  closeSample;
}

/// What the editor showing the sample project does for the tour.
class TourEditorHooks {
  const TourEditorHooks({required this.close});

  /// Saves and goes back to the project list.
  final Future<void> Function() close;
}

class TourController extends ChangeNotifier {
  TourPhase _phase = TourPhase.idle;
  List<TourStep> _steps = const [];
  int _index = 0;
  bool _startRequested = false;
  String? _sampleId;
  TourHomeHooks? _home;
  TourEditorHooks? _editor;

  TourPhase get phase => _phase;
  bool get active => _phase != TourPhase.idle;
  List<TourStep> get steps => _steps;
  int get index => _index;

  /// The step on screen (also while the next one is being prepared).
  TourStep? get step =>
      active && _index < _steps.length ? _steps[_index] : null;

  /// The sample project, once it was made.
  String? get sampleProjectId => _sampleId;

  /// Back goes to the step before, but not from the editor back to the
  /// home screen.
  bool get canGoBack =>
      _phase == TourPhase.running &&
      _index > 0 &&
      _steps[_index - 1].inEditor == _steps[_index].inEditor;

  bool get isLastStep => _index == _steps.length - 1;

  /// Help or the menu bar asked for the tour; the home screen starts it
  /// once it is in front ([takeStartRequest]).
  bool get startRequested => _startRequested;

  void requestStart() {
    if (active) return;
    _startRequested = true;
    notifyListeners();
  }

  /// True (once) when a start was requested.
  bool takeStartRequest() {
    if (!_startRequested) return false;
    _startRequested = false;
    return true;
  }

  void attachHome(TourHomeHooks hooks) => _home = hooks;
  void detachHome(TourHomeHooks hooks) {
    if (identical(_home, hooks)) _home = null;
  }

  void attachEditor(TourEditorHooks hooks) => _editor = hooks;
  void detachEditor(TourEditorHooks hooks) {
    if (identical(_editor, hooks)) _editor = null;
  }

  /// Starts at the first step (on the home screen).
  void start({required bool wide, required bool canDrop}) {
    if (active) return;
    _startRequested = false;
    _steps = buildTourSteps(wide: wide, canDrop: canDrop);
    _index = 0;
    _sampleId = null;
    _phase = TourPhase.running;
    notifyListeners();
  }

  Future<void> next() async {
    if (_phase != TourPhase.running) return;
    if (isLastStep) {
      _phase = TourPhase.ending;
      notifyListeners();
      return;
    }
    final entering = _steps[_index + 1].inEditor && !_steps[_index].inEditor;
    if (entering && _sampleId == null) {
      _phase = TourPhase.preparing;
      notifyListeners();
      String? id;
      try {
        id = await _home?.makeSample();
      } catch (_) {
        id = null;
      }
      if (_phase != TourPhase.preparing) {
        // Skipped meanwhile.
        if (id != null) await _home?.closeSample(id, keep: false);
        return;
      }
      if (id == null) {
        _reset();
        return;
      }
      _sampleId = id;
      _home?.openSample(id);
    }
    _index++;
    _phase = TourPhase.running;
    notifyListeners();
  }

  void back() {
    if (!canGoBack) return;
    _index--;
    notifyListeners();
  }

  /// Ends the tour now (Skip, Esc); the sample project is deleted.
  Future<void> skip() => _close(keep: false);

  /// Ends the tour after the last card.
  Future<void> finish({required bool keep}) => _close(keep: keep);

  Future<void> _close({required bool keep}) async {
    if (_phase == TourPhase.idle || _phase == TourPhase.closing) return;
    final id = _sampleId;
    _phase = TourPhase.closing;
    notifyListeners();
    try {
      if (id != null) {
        await _editor?.close();
        await _home?.closeSample(id, keep: keep);
      }
    } catch (_) {
      // The tour ends anyway.
    } finally {
      _reset();
    }
  }

  void _reset() {
    _phase = TourPhase.idle;
    _steps = const [];
    _index = 0;
    _sampleId = null;
    notifyListeners();
  }
}

final tourControllerProvider = Provider<TourController>((ref) {
  final controller = TourController();
  ref.onDispose(controller.dispose);
  return controller;
});

// Overlay ---------------------------------------------------------------------

/// Draws the tour over [child] (the whole app, above its navigator).
class TourOverlayHost extends ConsumerStatefulWidget {
  const TourOverlayHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<TourOverlayHost> createState() => _TourOverlayHostState();
}

class _TourOverlayHostState extends ConsumerState<TourOverlayHost> {
  late final TourController _tour = ref.read(tourControllerProvider);

  /// Where the current step's widgets are (global coordinates).
  Rect? _target;
  String? _locatedStep;
  int _stableFrames = 0;
  int _frames = 0;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _tour.addListener(_onTour);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _tour.removeListener(_onTour);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The window changed size: look again.
    _locate();
  }

  bool _onKey(KeyEvent event) {
    if (!_tour.active || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (_tour.phase == TourPhase.closing) return true;
    _tour.skip();
    return true;
  }

  void _onTour() {
    if (!mounted) return;
    setState(() {});
    _locate();
  }

  /// Looks for the step's widgets after each frame until they have stayed
  /// in the same place for a few frames (pages slide in; the editor loads).
  void _locate() {
    final step = _tour.step;
    if (step == null || _tour.phase != TourPhase.running) {
      _locatedStep = null;
      return;
    }
    if (_locatedStep != step.id) {
      _locatedStep = step.id;
      _stableFrames = 0;
      _frames = 0;
      _scrolled = false;
    } else {
      _stableFrames = 0;
      _frames = 0;
    }
    if (_locating) return;
    _locating = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  bool _scrolled = false;

  void _onFrame(Duration _) {
    _locating = false;
    if (!mounted) return;
    final step = _tour.step;
    if (step == null || _tour.phase != TourPhase.running) return;
    if (!_scrolled) {
      final first = TourAnchors.contextOf(step.anchors.first);
      if (first != null) {
        _scrolled = true;
        Scrollable.ensureVisible(first);
      }
    }
    final rect = TourAnchors.unionOf(step.anchors);
    final local = rect == null ? null : _toLocal(rect);
    if (local != _target) {
      setState(() => _target = local);
      _stableFrames = 0;
    } else if (local != null) {
      _stableFrames++;
    }
    _frames++;
    final done = local != null ? _stableFrames >= 3 : _frames >= 90;
    if (done) {
      assert(() {
        if (local == null) {
          debugPrint(
            'Tour step "${step.id}": none of ${step.anchors} is on '
            'screen.',
          );
        }
        return true;
      }());
      return;
    }
    _locating = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    SchedulerBinding.instance.scheduleFrame();
  }

  Rect? _toLocal(Rect global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return global;
    final topLeft = box.globalToLocal(global.topLeft);
    return topLeft & global.size;
  }

  @override
  Widget build(BuildContext context) {
    final phase = _tour.phase;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (phase != TourPhase.idle)
          Positioned.fill(
            child: _TourLayer(
              tour: _tour,
              target: phase == TourPhase.running ? _target : null,
            ),
          ),
      ],
    );
  }
}

class _TourLayer extends StatelessWidget {
  const _TourLayer({required this.tour, required this.target});
  final TourController tour;
  final Rect? target;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final phase = tour.phase;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final hole = target?.inflate(6);
        final Widget card = switch (phase) {
          TourPhase.running => _StepCard(tour: tour),
          TourPhase.preparing => _BusyCard(
            tour: tour,
            text: 'Opening a sample project…',
          ),
          TourPhase.ending => _EndCard(tour: tour),
          TourPhase.closing || TourPhase.idle => const SizedBox.shrink(),
        };
        return Stack(
          children: [
            // Taps on the app wait until the tour is over.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: TweenAnimationBuilder<Rect?>(
                  // Without a target it grows from the middle once one shows.
                  tween: RectTween(
                    end:
                        hole ??
                        Rect.fromCenter(
                          center: size.center(Offset.zero),
                          width: 0,
                          height: 0,
                        ),
                  ),
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  builder: (context, rect, _) => CustomPaint(
                    size: size,
                    painter: _SpotlightPainter(
                      hole: hole == null ? null : rect,
                    ),
                  ),
                ),
              ),
            ),
            _placeCard(
              context,
              size,
              hole,
              card: Semantics(
                container: true,
                liveRegion: true,
                explicitChildNodes: true,
                child: card,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Puts the card next to the spotlight where there is room, always
  /// fully on screen (so Skip can be reached).
  Widget _placeCard(
    BuildContext context,
    Size size,
    Rect? hole, {
    required Widget card,
  }) {
    final pad = MediaQuery.paddingOf(context);
    const margin = 12.0;
    const cardHeight = 230.0;
    final width = (size.width - 32).clamp(200.0, 380.0).toDouble();
    final left0 = 16.0 + pad.left;
    final right0 = size.width - 16 - pad.right;
    final top0 = 16.0 + pad.top;
    final bottom0 = size.height - 16 - pad.bottom;
    double clampX(double x) => x
        .clamp(left0, (right0 - width).clamp(left0, double.infinity))
        .toDouble();

    Widget positioned({double? top, double? bottom, required double left}) {
      // Never taller than the room it has, so it stays on screen (it
      // scrolls inside when it must).
      final room = top != null ? bottom0 - top : (size.height - bottom!) - top0;
      return Positioned(
        left: left,
        top: top,
        bottom: bottom,
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: room.clamp(120.0, double.infinity),
          ),
          child: card,
        ),
      );
    }

    if (hole == null) {
      return Positioned.fill(
        child: Center(
          child: SizedBox(width: width, child: card),
        ),
      );
    }
    final below = bottom0 - hole.bottom - margin;
    final above = hole.top - margin - top0;
    final x = clampX(hole.center.dx - width / 2);
    if (below >= cardHeight) {
      return positioned(top: hole.bottom + margin, left: x);
    }
    if (above >= cardHeight) {
      return positioned(bottom: size.height - hole.top + margin, left: x);
    }
    final leftRoom = hole.left - margin - left0;
    final rightRoom = right0 - hole.right - margin;
    final y = (hole.center.dy - cardHeight / 2)
        .clamp(top0, (bottom0 - cardHeight).clamp(top0, double.infinity))
        .toDouble();
    if (leftRoom >= width) {
      return positioned(top: y, left: hole.left - margin - width);
    }
    if (rightRoom >= width) {
      return positioned(top: y, left: hole.right + margin);
    }
    if (below >= 140 && below >= above) {
      return positioned(top: hole.bottom + margin, left: x);
    }
    if (above >= 140) {
      return positioned(bottom: size.height - hole.top + margin, left: x);
    }
    // No room anywhere: over the spotlight, at the bottom of the screen.
    return positioned(bottom: size.height - bottom0, left: x);
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole});
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.66);
    final h = hole;
    if (h == null) {
      canvas.drawRect(screen, shade);
      return;
    }
    final rrect = RRect.fromRectAndRadius(h, const Radius.circular(12));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(screen)
        ..addRRect(rrect),
      shade,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panelHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.tour});
  final TourController tour;

  @override
  Widget build(BuildContext context) {
    final step = tour.step!;
    final text = Theme.of(context).textTheme;
    return _CardFrame(
      child: Column(
        key: ValueKey('tour-card-${step.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Step ${tour.index + 1} of ${tour.steps.length}',
                  style: text.labelMedium?.copyWith(color: AppColors.textDim),
                ),
              ),
              TextButton(onPressed: tour.skip, child: const Text('Skip tour')),
            ],
          ),
          Text(step.title, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(step.body, style: text.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              if (tour.canGoBack)
                TextButton(onPressed: tour.back, child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: tour.next,
                child: Text(tour.isLastStep ? 'Finish' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard({required this.tour, required this.text});
  final TourController tour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
              TextButton(onPressed: tour.skip, child: const Text('Skip tour')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.tour});
  final TourController tour;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sample = tour.sampleProjectId != null;
    return _CardFrame(
      child: Column(
        key: const ValueKey('tour-card-end'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text("That's the tour!", style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Answers to your questions, and this tour, are in Help: the ? '
            'at the top of the screen.'
            '${sample ? ' Would you like to keep the sample project to play '
                      'with?' : ''}',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: sample
                ? [
                    TextButton(
                      onPressed: () => tour.finish(keep: false),
                      child: const Text('Delete the sample'),
                    ),
                    FilledButton(
                      onPressed: () => tour.finish(keep: true),
                      child: const Text('Keep it'),
                    ),
                  ]
                : [
                    FilledButton(
                      onPressed: () => tour.finish(keep: false),
                      child: const Text('Done'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}
