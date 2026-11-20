import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import '../../core/model/picture_layout.dart';
import '../../core/model/project.dart';
import '../../core/model/title_layout.dart';
import '../format.dart';
import '../playback/look.dart';
import '../playback/playback_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'clip_actions.dart';
import 'picture_tools.dart';
import 'session.dart';
import 'sound_status.dart';

/// Font families of the bundled export fonts (assets/fonts/DejaVuSans*.ttf),
/// registered by [loadTitleFonts]. Regular and bold are separate families
/// because each is its own file, exactly the ones ffmpeg draws with.
const String kTitleFont = 'ClipForgeTitle';
const String kTitleFontBold = 'ClipForgeTitleBold';

/// Colour of the box behind a title, as in the export
/// (lib/media/ffmpeg_command.dart). Sizes and places come from
/// [layoutTitleBlock], which the export uses too.
const Color kTitleBoxColor = Color(0x8C000000);

/// Offset of the drop shadow of a title without a box.
double titleShadowPx(double fontSize) => math.max(1.0, fontSize / 18);

/// While a crop is changed the whole picture is shown this far inside the
/// preview, so that the handles at its edges can be reached.
const double kCropEditorMargin = 14;

/// Turns true when the fonts are in.
final ValueNotifier<bool> titleFontsLoaded = ValueNotifier(false);
Future<void>? _titleFonts;

/// The Flutter font family of the title font [font] (its bold cut when
/// [bold]): each file is a family of its own, the very file ffmpeg draws
/// with.
String titleFontFamily(TitleFont font, bool bold) => switch (font) {
      TitleFont.classic => bold ? kTitleFontBold : kTitleFont,
      _ => 'ClipForgeTitle-${titleFontFileName(font, bold)}',
    };

/// Makes the export fonts usable by Flutter text. Safe to call often; text
/// already on screen is laid out again when the fonts arrive.
Future<void> loadTitleFonts() => _titleFonts ??= () async {
      try {
        await Future.wait([
          for (final font in TitleFont.values)
            for (final bold in const [false, true])
              (FontLoader(titleFontFamily(font, bold))
                    ..addFont(rootBundle
                        .load('assets/fonts/${titleFontFileName(font, bold)}')))
                  .load(),
        ]);
        titleFontsLoaded.value = true;
      } catch (_) {
        // Without the assets (some tests) titles use the default font.
      }
    }();

/// The picture: the clip under the playhead placed on the project canvas,
/// with the titles that are visible at that time on top.
class PreviewView extends StatelessWidget {
  const PreviewView({super.key, required this.session, required this.onAddMedia});

  final EditorSession session;
  final VoidCallback onAddMedia;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [session.editor, session.playback, session.cropTarget]),
      builder: (context, _) {
        final project = session.project;
        if (project.clips.isEmpty) return _EmptyState(onAddMedia: onAddMedia);
        final canvas = project.canvasSize;
        final cropping = session.cropTarget.value != null;
        final picture = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: session.clearSelection,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: AspectRatio(
                aspectRatio: canvas.width / canvas.height,
                child: LayoutBuilder(
                  builder: (context, box) => ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        _MainRegion(
                          session: session,
                          size: box.biggest,
                          child: _ClipLayer(
                              session: session, size: box.biggest),
                        ),
                        _OverlayLayer(session: session, size: box.biggest),
                        // Titles stay out of the way while cropping.
                        Offstage(
                          offstage: cropping,
                          child: _TitlesLayer(
                              session: session, size: box.biggest),
                        ),
                        // The fade of the whole video from / to black.
                        if (!cropping &&
                            (project.fadeInMs > 0 || project.fadeOutMs > 0))
                          _ProjectFadeLayer(session: session),
                        _CropLayer(session: session, size: box.biggest),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            picture,
            // While the clip's processed sound is not ready yet.
            Positioned(
              left: 12,
              top: 12,
              child: PreparingSoundNote(session: session),
            ),
            // Opening the file: never plain black without a word.
            Center(
              child: ListenableBuilder(
                listenable: session.playback,
                builder: (context, _) => session.playback.loadingFirstFrame
                    ? const IgnorePointer(
                        child: Text('Loading the video…',
                            key: ValueKey('preview-loading'),
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: 13)),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddMedia});
  final VoidCallback onAddMedia;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined,
                size: 56, color: AppColors.textDim),
            const SizedBox(height: 16),
            Text('This project is empty', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Pick the clips you want to put together.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddMedia,
              icon: const Icon(Icons.add),
              label: const Text('Add videos or photos'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipLayer extends StatefulWidget {
  const _ClipLayer({required this.session, required this.size});
  final EditorSession session;

  /// Size of the canvas on screen.
  final Size size;

  @override
  State<_ClipLayer> createState() => _ClipLayerState();
}

/// Draws [PlaybackController.scene]: the clip under the playhead and, during
/// a transition, the clip before it.
///
/// Every layer is a whole canvas (black, with the clip placed on it), like
/// the frames the export blends. The surfaces of the video players stay in
/// the tree, in a fixed order, for as long as the editor is open: a player
/// that loads the next clip ahead of time then already has its texture, and
/// a cut is nothing more than a change of which one is visible.
class _ClipLayerState extends State<_ClipLayer> {
  final Map<int, Widget> _surfaces = {};
  final Map<int, Widget> _backdrops = {};

  @override
  void didUpdateWidget(_ClipLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _surfaces.clear();
      _backdrops.clear();
      _precached = null;
    }
  }

  /// The picture of video player [deck]. Always the same widget, so that it
  /// keeps its state wherever it is put.
  Widget _surface(int deck) => _surfaces[deck] ??= KeyedSubtree(
        key: GlobalKey(debugLabel: 'video deck $deck'),
        child: widget.session.backend
            .buildVideoSurface(widget.session.playback.videoPlayers[deck]),
      );

  /// The same picture a second time, for the blurred backdrop.
  Widget _backdrop(int deck) => _backdrops[deck] ??= KeyedSubtree(
        key: GlobalKey(debugLabel: 'video deck $deck backdrop'),
        child: widget.session.backend
            .buildVideoSurface(widget.session.playback.videoPlayers[deck]),
      );

  static Widget _colour(Clip clip, Widget child) => hasColorAdjustments(clip)
      ? ColorFiltered(
          colorFilter: ColorFilter.matrix(clipColorMatrix(clip)),
          child: child,
        )
      : child;

  /// [clip] on a canvas of its own: turned, mirrored and cropped
  /// ([Clip.framing]), fitted, zoomed and positioned, colour-adjusted, over
  /// black or over a blurred copy of itself. [picture] is called once for
  /// the clip and once more for the backdrop. While the clip's crop is
  /// being changed ([EditorSession.cropTarget]) the whole turned picture
  /// is shown instead, fitted into the canvas.
  ///
  /// The geometry is the export's (placeClip in
  /// core/model/picture_layout.dart): colour is applied to the picture,
  /// not to the bars; the backdrop of [FitMode.blur] fills the canvas, is
  /// not zoomed and is blurred by about 1/14 of the canvas's short side.
  Widget _canvas(Clip clip, Widget Function(bool backdrop) picture) {
    final w = widget.size.width, h = widget.size.height;
    final canvas = PicBox(0, 0, w, h);
    final editing = widget.session.cropTarget.value == clip.id;
    final f = clip.framing;
    final PicBox full;
    var visible = canvas;
    if (editing) {
      full = cropEditorPicture(clip, w, h, margin: kCropEditorMargin);
    } else {
      final placed = placeClip(clip, w, h);
      full = placed.fullPicture(f.crop);
      visible = placed.visible;
    }
    final blur = !editing &&
        clip.fit == FitMode.blur &&
        !sameShapeAsFrame(clip, w, h);
    final sigma = math.max(1.0, widget.size.shortestSide / 14);
    final size = clip.framedSize;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (blur)
            _colour(
              clip,
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                    sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
                child: placedPicture(
                  clip,
                  canvas,
                  placeCover(Framing.none, size.width, size.height, canvas)
                      .fullPicture(f.crop),
                  picture(true),
                ),
              ),
            ),
          _colour(clip, placedPicture(clip, visible, full, picture(false))),
        ],
      ),
    );
  }

  String? _precached;

  /// Decodes the photo that comes after clip [index] ahead of time, so the
  /// cut to it does not show a moment of black while the file is read.
  void _precachePhotoAfter(int index) {
    final clips = widget.session.project.clips;
    if (index < 0 || index + 1 >= clips.length) return;
    final next = clips[index + 1];
    if (next.type != ClipType.photo || next.path == _precached) return;
    if (widget.session.playback.isMissing(next.path)) return;
    _precached = next.path;
    precacheImage(FileImage(File(next.path)), context,
        onError: (_, _) {});
  }

  /// Where a layer sits in the stack: the video players first, then the
  /// outgoing photo, the current photo and the "file not found" notice.
  static int _order(PreviewLayer layer, {required bool incoming}) =>
      switch (layer.kind) {
        PreviewLayerKind.video => layer.deck!,
        PreviewLayerKind.photo => incoming ? 11 : 10,
        PreviewLayerKind.missing || PreviewLayerKind.blank => 12,
      };

  @override
  Widget build(BuildContext context) {
    // The transition and the clip fades follow the playhead frame by
    // frame; between them the picture's layout does not change while the
    // player plays, so the scene is built again only when what it shows
    // changes (1.8; before, every frame while playing).
    return SelectBuilder<Object>(
      listenable: Listenable.merge(
          [widget.session.playback.position, widget.session.cropTarget]),
      select: _sceneKey,
      builder: (context, _) {
        debugSceneBuilds++;
        return _buildScene(context);
      },
    );
  }

  Widget _buildScene(BuildContext context) {
    final playback = widget.session.playback;
    final scene = playback.scene;
    final current = scene.current;
    if (current == null) return const SizedBox.shrink();
    final outgoing = scene.outgoing;
    _precachePhotoAfter(playback.clipIndex);

    /// Applies the clip's own fade and the transition to one side of it.
    Widget pose(PreviewLayer layer, Widget child) {
      // Always an Opacity, so that the tree (and the video surface in it)
      // keeps its shape whether the clip fades or not.
      child = Opacity(opacity: _clipFade(layer.clip), child: child);
      if (outgoing == null) return child;
      final incoming = identical(layer, current);
      final other = incoming ? outgoing : current;
      final at = transitionPose(
        scene.transition,
        scene.progress,
        incoming: incoming,
        upper: _order(layer, incoming: incoming) >
            _order(other, incoming: !incoming),
      );
      return FractionalTranslation(
        translation: at.offset,
        child: Opacity(opacity: at.opacity, child: child),
      );
    }

    Widget photo(PreviewLayer layer) => KeyedSubtree(
          key: ValueKey('photo ${layer.clip.id}'),
          child: pose(layer, _canvas(layer.clip, (_) => _photo(layer.clip))),
        );

    final decks = playback.videoPlayers.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var deck = 0; deck < decks; deck++)
          _deckLayer(
            deck,
            current.kind == PreviewLayerKind.video && current.deck == deck
                ? current
                : outgoing != null &&
                        outgoing.kind == PreviewLayerKind.video &&
                        outgoing.deck == deck
                    ? outgoing
                    : null,
            pose,
          ),
        if (outgoing != null && outgoing.kind == PreviewLayerKind.photo)
          photo(outgoing),
        if (current.kind == PreviewLayerKind.photo) photo(current),
        if (current.kind == PreviewLayerKind.missing)
          pose(
            current,
            _MissingNotice(
              name: fileName(current.clip.path),
              onFind: () => findMissingFile(
                  context, widget.session, current.clip.path,
                  audio: false),
            ),
          ),
      ],
    );
  }

  /// The surface of one video player: on screen when a [layer] of the scene
  /// uses it, otherwise kept alive out of sight.
  Widget _deckLayer(int deck, PreviewLayer? layer,
      Widget Function(PreviewLayer layer, Widget child) pose) {
    final Widget child;
    if (layer == null) {
      child = _surface(deck);
    } else {
      child = pose(
        layer,
        _canvas(layer.clip,
            (backdrop) => backdrop ? _backdrop(deck) : _surface(deck)),
      );
    }
    return Visibility(
      key: ValueKey('deck $deck'),
      visible: layer != null,
      maintainState: true,
      child: child,
    );
  }

  /// Everything [_buildScene] reads that changes while playing.
  Object _sceneKey() {
    final scene = widget.session.playback.scene;
    double r(double v) => (v * 1000).roundToDouble();
    final cur = scene.current, out = scene.outgoing;
    return (
      cur,
      out,
      scene.transition,
      r(scene.progress),
      cur == null ? 1.0 : r(_clipFade(cur.clip)),
      out == null ? 1.0 : r(_clipFade(out.clip)),
      widget.session.cropTarget.value,
    );
  }

  /// How visible [clip] is at the playhead because of its own fade in /
  /// out (from / to black; 1 without fades), as the export fades it.
  double _clipFade(Clip clip) {
    if (clip.fadeInMs <= 0 && clip.fadeOutMs <= 0) return 1;
    final project = widget.session.project;
    final i = project.clips.indexWhere((c) => c.id == clip.id);
    if (i < 0) return 1;
    final local = widget.session.playback.positionMs - project.clipStartMs(i);
    return clip.fadeGainAt(local.clamp(0, clip.durationMs)).toDouble();
  }

  Widget _photo(Clip clip) => Image.file(
        File(clip.path),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      );
}

class _MissingNotice extends StatelessWidget {
  const _MissingNotice({required this.name, required this.onFind});
  final String name;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1B1012),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 8),
              const Text('File not found',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onFind,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Find file…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How often the titles layer was built (tests measure rebuilds).
int debugTitleLayerBuilds = 0;

/// How often the picture (scene) layer was built (tests measure rebuilds).
int debugSceneBuilds = 0;

/// What the titles layer shows at [t]: which titles are on screen and,
/// while one of them animates, the time itself. The layer builds again only
/// when this changes (before 1.8: every frame while playing, wrapping every
/// title's text again each time).
String titleLayerKey(Project project, int t, String extra) {
  final b = StringBuffer('${identityHashCode(project)}|$extra');
  for (final title in project.titles) {
    if (t < title.startMs || t >= title.endMs) continue;
    b.write('|${title.id}');
    final lens = titleAnimationLengths(title);
    if ((lens.inMs > 0 && t < title.startMs + lens.inMs) ||
        (lens.outMs > 0 && t >= title.endMs - lens.outMs)) {
      b.write('@$t');
    }
  }
  return b.toString();
}

class _TitlesLayer extends StatelessWidget {
  const _TitlesLayer({required this.session, required this.size});
  final EditorSession session;
  final Size size;

  @override
  Widget build(BuildContext context) {
    loadTitleFonts();
    return SelectBuilder<String>(
      listenable: Listenable.merge(
          [session.playback.position, session.selection, titleFontsLoaded]),
      select: () => titleLayerKey(session.project, session.playback.positionMs,
          '${session.selection.value?.id}|${titleFontsLoaded.value}'),
      builder: (context, _) {
        debugTitleLayerBuilds++;
        final t = session.playback.positionMs;
        final selected = session.selectedTitle?.id;
        final canvasPx = session.project.canvasSize;
        // Everything is laid out in pixels of the export canvas and scaled
        // to the preview, so both come out the same.
        final scale = size.width / canvasPx.width;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: ui.Clip.none,
          children: [
            for (final title in session.project.titles)
              if (t >= title.startMs && t < title.endMs)
                _TitleItem(
                  key: ValueKey('preview-title-${title.id}'),
                  session: session,
                  title: title,
                  block: layoutTitleBlock(title,
                      canvasWidth: canvasPx.width,
                      canvasHeight: canvasPx.height),
                  scale: scale,
                  selected: title.id == selected,
                ),
          ],
        );
      },
    );
  }
}

class _TitleItem extends StatefulWidget {
  const _TitleItem({
    super.key,
    required this.session,
    required this.title,
    required this.block,
    required this.scale,
    required this.selected,
  });
  final EditorSession session;
  final TitleOverlay title;

  /// Where the export draws the title, in canvas pixels.
  final TitleBlock block;

  /// Preview pixels per canvas pixel.
  final double scale;
  final bool selected;

  @override
  State<_TitleItem> createState() => _TitleItemState();
}

class _TitleItemState extends State<_TitleItem> {
  LiveEdit? _drag;
  late TitleOverlay _base;
  late TitleBlock _baseBlock;
  Offset _moved = Offset.zero;

  void _select() =>
      widget.session.select(ItemKind.title, widget.title.id);

  /// Moves the title with the finger. The export keeps the whole block
  /// inside the picture, so the stored place is the clamped one: the text
  /// stops at the edge and comes back as soon as the finger does.
  void _dragTo(Offset moved) {
    final canvas = widget.session.project.canvasSize;
    if (canvas.width <= 0 || canvas.height <= 0 || widget.scale <= 0) return;
    // Start from where the block is drawn, which may already be a clamped
    // version of the stored place.
    final wanted = _base.copyWith(
      x: (_baseBlock.centerX + moved.dx / widget.scale) / canvas.width,
      y: (_baseBlock.centerY + moved.dy / widget.scale) / canvas.height,
    );
    final placed = layoutTitleBlock(wanted,
        canvasWidth: canvas.width, canvasHeight: canvas.height);
    final x = (placed.centerX / canvas.width).clamp(0.0, 1.0);
    final y = (placed.centerY / canvas.height).clamp(0.0, 1.0);
    _drag?.apply(() =>
        widget.session.editor.updateTitle(_base.copyWith(x: x, y: y)));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final block = widget.block;
    final k = widget.scale;
    final fontSize = block.fontPx * k;
    final pad = block.boxPadPx * k;
    final width = block.width * k + 2 * pad;
    final height = block.height * k + 2 * pad;
    // Entry / exit animation at the playhead, as the export draws it
    // (titleAnimationAt): opacity and move for the whole block, size for
    // the text only (a box keeps its size).
    final anim =
        titleAnimationAt(title, widget.session.playback.positionMs);
    final canvas = widget.session.project.canvasSize;
    final dy = anim.dy * canvas.height * k;
    final family = titleFontFamily(title.font, title.bold);
    final loaded = titleFontsLoaded.value;
    final outline = title.outline ? titleOutlinePx(block.fontPx) * k : 0.0;
    TextStyle style({Paint? stroke}) => TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['DejaVu Sans'],
          // The bold cut is its own font file, as in the export.
          fontWeight: loaded || !title.bold ? FontWeight.w400 : FontWeight.w700,
          fontSize: fontSize,
          height: block.fontPx > 0 ? block.lineHeightPx / block.fontPx : 1.2,
          leadingDistribution: TextLeadingDistribution.even,
          color: stroke == null ? Color(title.colorArgb) : null,
          foreground: stroke,
          shadows: stroke != null || title.background || !title.shadow
              ? null
              : [
                  Shadow(
                    color: const Color(0x99000000),
                    offset: Offset(
                        titleShadowPx(fontSize), titleShadowPx(fontSize)),
                  ),
                ],
        );
    final align = switch (title.align) {
      TitleAlign.center => TextAlign.center,
      TitleAlign.left => TextAlign.left,
      TitleAlign.right => TextAlign.right,
    };
    Widget text(TextStyle s) => Text(
          // Right-to-left lines get direction marks, as in the export.
          block.lines.map(bidiLine).join('\n'),
          textAlign: align,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: s,
        );
    Widget lines = outline > 0
        ? Stack(
            children: [
              // drawtext's border goes OUT from the letters by its width; a
              // stroke twice as wide, under the letters, does the same.
              text(style(
                  stroke: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2 * outline
                    ..strokeJoin = StrokeJoin.round
                    ..color = Color(title.outlineColorArgb))),
              text(style()),
            ],
          )
        : text(style());
    if ((anim.scale - 1).abs() > 1e-4) {
      lines = Transform.scale(scale: anim.scale, child: lines);
    }
    final Widget box = GestureDetector(
      onTap: _select,
      onPanStart: (_) {
        _select();
        _drag = LiveEdit(widget.session.editor);
        _base = title;
        _baseBlock = block;
        _moved = Offset.zero;
      },
      onPanUpdate: (d) {
        _moved += d.delta;
        _dragTo(_moved);
      },
      onPanEnd: (_) => _drag = null,
      onPanCancel: () => _drag = null,
      // One box around the whole block, the size the export draws it.
      // The selection frame is painted over it and takes no room.
      child: Container(
        color: title.background ? kTitleBoxColor : null,
        padding: EdgeInsets.symmetric(horizontal: pad),
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: widget.selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        // The lines keep their own width whatever the estimate in
        // [block] says; they are centred on the same point (or lined up
        // with the block's left / right edge).
        child: OverflowBox(
          alignment: switch (title.align) {
            TitleAlign.center => Alignment.center,
            TitleAlign.left => Alignment.centerLeft,
            TitleAlign.right => Alignment.centerRight,
          },
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: lines,
        ),
      ),
    );
    return Positioned(
      left: block.centerX * k - width / 2,
      top: block.centerY * k - height / 2 + dy,
      width: width,
      height: height,
      child: anim.alpha >= 0.999
          ? box
          : Opacity(opacity: anim.alpha.clamp(0.0, 1.0), child: box),
    );
  }
}

/// Black over the whole picture (titles included) while the video fades in
/// from black at its start or out to black at its end
/// ([Project.fadeInMs], [Project.fadeOutMs]), as the export does it.
class _ProjectFadeLayer extends StatelessWidget {
  const _ProjectFadeLayer({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SelectBuilder<int>(
        listenable: session.playback.position,
        // In steps of 1/1000: frames outside the fades do not build.
        select: () => (session.project
                    .fadeGainAt(session.playback.positionMs) *
                1000)
            .round(),
        builder: (context, _) {
          final gain =
              session.project.fadeGainAt(session.playback.positionMs);
          if (gain >= 0.999) return const SizedBox.shrink();
          return ColoredBox(
              key: const ValueKey('project-fade'),
              color: Colors.black.withValues(alpha: 1 - gain));
        },
      ),
    );
  }
}

/// [child] (the picture of [clip] as the file shows it) turned and mirrored
/// by [Clip.framing], laid out at the clip's pixel size and scaled to
/// [full]; only what falls inside [visible] shows. Both rectangles are in
/// the coordinates of the parent (a [Stack] that fills it).
///
/// The black box under the picture is there for the colour filter: on
/// Linux a `ColorFiltered` whose only content is a video texture draws
/// nothing at all, while a texture on top of something painted is filtered
/// as it should be (found by trying, with the real player).
Widget placedPicture(Clip clip, PicBox visible, PicBox full, Widget child) {
  final f = clip.framing;
  final native = SizedBox(
    width: clip.width > 0 ? clip.width.toDouble() : 16,
    height: clip.height > 0 ? clip.height.toDouble() : 9,
    child: Stack(
      fit: StackFit.expand,
      children: [const ColoredBox(color: Colors.black), child],
    ),
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      Positioned(
        left: visible.left,
        top: visible.top,
        width: math.max(0.0, visible.width),
        height: math.max(0.0, visible.height),
        child: ClipRect(
          child: Stack(
            clipBehavior: ui.Clip.none,
            children: [
              Positioned(
                left: full.left - visible.left,
                top: full.top - visible.top,
                width: math.max(0.0, full.width),
                height: math.max(0.0, full.height),
                child: Transform.flip(
                  flipX: f.flipH,
                  flipY: f.flipV,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: RotatedBox(
                      quarterTurns: f.rotation ~/ 90,
                      child: native,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Where the main track's picture goes: the whole canvas, except while a
/// side by side / top and bottom overlay shows, when the middle of it is
/// moved to the other half (as the export does, see overlayFrame). The
/// tree is the same either way, so the video surfaces inside never move.
class _MainRegion extends StatelessWidget {
  const _MainRegion(
      {required this.session, required this.size, required this.child});
  final EditorSession session;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [session.playback.position, session.cropTarget]),
      child: child,
      builder: (context, child) {
        final w = size.width, h = size.height;
        var src = PicBox(0, 0, w, h);
        var dest = src;
        final o = session.playback.overlayItem;
        final target = session.cropTarget.value;
        final croppingMain =
            target != null && session.project.clips.any((c) => c.id == target);
        if (o != null && !croppingMain) {
          final canvas = session.project.canvasSize;
          final k = canvas.width > 0 ? w / canvas.width : 1.0;
          final frame = overlayFrame(
              o, canvas.width.toDouble(), canvas.height.toDouble());
          if (frame.mainSource != null && frame.mainDest != null) {
            src = frame.mainSource!.scaled(k);
            dest = frame.mainDest!.scaled(k);
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              key: const ValueKey('main-region'),
              left: dest.left,
              top: dest.top,
              width: dest.width,
              height: dest.height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: w,
                  maxWidth: w,
                  minHeight: h,
                  maxHeight: h,
                  child: Transform.translate(
                    offset: Offset(-src.left, -src.top),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The overlay track: the item under the playhead, in its box, with its
/// fades. Selected (picture-in-picture / free), it can be dragged to
/// another place and resized by its corner. The surfaces of the overlay
/// players stay in the tree, like those of the main track.
class _OverlayLayer extends StatefulWidget {
  const _OverlayLayer({required this.session, required this.size});
  final EditorSession session;
  final Size size;

  @override
  State<_OverlayLayer> createState() => _OverlayLayerState();
}

class _OverlayLayerState extends State<_OverlayLayer> {
  final Map<int, Widget> _surfaces = {};
  LiveEdit? _drag;
  OverlayClip? _base;
  PicBox _baseBox = const PicBox(0, 0, 0, 0);
  Offset _moved = Offset.zero;

  EditorSession get _s => widget.session;

  @override
  void didUpdateWidget(_OverlayLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) _surfaces.clear();
  }

  Widget _surface(int deck) => _surfaces[deck] ??= KeyedSubtree(
        key: GlobalKey(debugLabel: 'overlay deck $deck'),
        child: _s.backend.buildVideoSurface(_s.playback.overlayPlayers[deck]),
      );

  void _start(OverlayClip o, PicBox box) {
    _s.playback.pause();
    _drag = LiveEdit(_s.editor);
    _base = o;
    _baseBox = box;
    _moved = Offset.zero;
  }

  void _end() {
    _drag = null;
    _base = null;
  }

  /// Moves the overlay: it becomes a free one at the new place.
  void _move(Offset delta, double k) {
    final base = _base, drag = _drag;
    if (base == null || drag == null || k <= 0) return;
    _moved += delta;
    final canvas = _s.project.canvasSize;
    final c = overlayCentreFor(
        base,
        _baseBox.left + _moved.dx / k,
        _baseBox.top + _moved.dy / k,
        canvas.width.toDouble(),
        canvas.height.toDouble());
    drag.apply(() => _s.editor.updateOverlay(base.copyWith(
        layout: OverlayLayout.free,
        x: (c.x * 1000).round() / 1000,
        y: (c.y * 1000).round() / 1000)));
  }

  /// Resizes by the bottom right corner; the top left corner stays.
  void _resize(Offset delta, double k) {
    final base = _base, drag = _drag;
    if (base == null || drag == null || k <= 0 || _baseBox.width <= 0) return;
    _moved += delta;
    final canvas = _s.project.canvasSize;
    final grow = math.max(_moved.dx / k / _baseBox.width,
        _moved.dy / k / _baseBox.height);
    final size = (base.size * (1 + grow))
        .clamp(OverlayClip.minSize, OverlayClip.maxSize)
        .toDouble();
    final sized = base.copyWith(size: (size * 100).round() / 100);
    final c = overlayCentreFor(sized, _baseBox.left, _baseBox.top,
        canvas.width.toDouble(), canvas.height.toDouble());
    drag.apply(() => _s.editor.updateOverlay(sized.copyWith(
        layout: OverlayLayout.free,
        x: (c.x * 1000).round() / 1000,
        y: (c.y * 1000).round() / 1000)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _s.playback.position,
        _s.cropTarget,
        _s.selection,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final playback = _s.playback;
    final view = playback.overlay;
    final target = _s.cropTarget.value;
    // Cropping a main-track clip: the overlay is out of the way.
    final croppingMain =
        target != null && _s.project.clips.any((c) => c.id == target);
    final shown = croppingMain ? null : view;
    final decks = playback.overlayPlayers.length;
    final children = <Widget>[];
    Widget? item;
    if (shown != null) item = _item(context, shown, target == shown.item.id);
    for (var deck = 0; deck < decks; deck++) {
      final mine = shown != null &&
          shown.kind == PreviewLayerKind.video &&
          shown.deck == deck;
      children.add(Visibility(
        key: ValueKey('overlay deck $deck'),
        visible: mine,
        maintainState: true,
        child: mine ? item! : _surface(deck),
      ));
    }
    if (shown != null && shown.kind != PreviewLayerKind.video) {
      children.add(KeyedSubtree(
          key: ValueKey('overlay ${shown.item.id}'), child: item!));
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  /// The picture of overlay [view] in its box, with its selection frame
  /// and handles; the whole picture when [editing] its crop.
  Widget _item(BuildContext context, OverlayView view, bool editing) {
    final o = view.item;
    final w = widget.size.width, h = widget.size.height;
    final canvas = _s.project.canvasSize;
    final k = canvas.width > 0 ? w / canvas.width : 1.0;
    final frame =
        overlayFrame(o, canvas.width.toDouble(), canvas.height.toDouble());
    final box = frame.box.scaled(k);
    final border = frame.border * k;
    final c = o.clip;
    final Widget content = switch (view.kind) {
      PreviewLayerKind.video => _surface(view.deck!),
      PreviewLayerKind.photo => Image.file(
          File(o.path),
          fit: BoxFit.fill,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        ),
      _ => const SizedBox.shrink(),
    };
    final selected = _s.selection.value?.kind == ItemKind.overlay &&
        _s.selection.value?.id == o.id;
    final movable = selected &&
        !editing &&
        (o.layout == OverlayLayout.pip || o.layout == OverlayLayout.free);

    if (editing) {
      final full = cropEditorPicture(c, w, h, margin: kCropEditorMargin);
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xE6000000)),
          if (view.kind == PreviewLayerKind.video ||
              view.kind == PreviewLayerKind.photo)
            placedPicture(c, PicBox(0, 0, w, h), full, content),
        ],
      );
    }
    final size = c.framedSize;
    final placed = placeCover(c.framing, size.width * k, size.height * k, box);
    final Widget picture = switch (view.kind) {
      PreviewLayerKind.missing => Positioned(
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          child: const ColoredBox(
            color: Color(0xFF1B1012),
            child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppColors.danger, size: 28),
            ),
          ),
        ),
      PreviewLayerKind.blank => const SizedBox.shrink(),
      _ => placedPicture(
          c, placed.visible, placed.fullPicture(c.framing.crop), content),
    };
    final opacity = o.opacityAt(_s.playback.positionMs).clamp(0.0, 1.0);
    const grip = 26.0;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: ui.Clip.none,
      children: [
        Opacity(
          opacity: opacity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (border > 0)
                Positioned(
                  left: box.left - border,
                  top: box.top - border,
                  width: box.width + 2 * border,
                  height: box.height + 2 * border,
                  child: const ColoredBox(color: Colors.white),
                ),
              if (border > 0)
                Positioned(
                  left: box.left,
                  top: box.top,
                  width: box.width,
                  height: box.height,
                  child: const ColoredBox(color: Colors.black),
                ),
              picture,
            ],
          ),
        ),
        // Tapping the overlay selects it; selected, it can be moved.
        Positioned(
          key: ValueKey('preview-overlay-${o.id}'),
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          child: MouseRegion(
            cursor: movable ? SystemMouseCursors.move : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => _s.selectOverlayAndShow(o.id),
              onPanStart: movable ? (_) => _start(o, frame.box) : null,
              onPanUpdate: movable ? (d) => _move(d.delta, k) : null,
              onPanEnd: movable ? (_) => _end() : null,
              onPanCancel: movable ? _end : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (movable)
          Positioned(
            key: ValueKey('preview-overlay-resize-${o.id}'),
            left: box.right - grip / 2,
            top: box.bottom - grip / 2,
            width: grip,
            height: grip,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (_) => _start(o, frame.box),
                onPanUpdate: (d) => _resize(d.delta, k),
                onPanEnd: (_) => _end(),
                onPanCancel: _end,
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The crop frame of [EditorSession.cropTarget] when that picture shows at
/// the playhead (see [CropFrame]).
class _CropLayer extends StatelessWidget {
  const _CropLayer({required this.session, required this.size});
  final EditorSession session;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        session.cropTarget,
        session.editor,
        session.playback.position,
      ]),
      builder: (context, _) {
        final id = session.cropTarget.value;
        if (id == null) return const SizedBox.shrink();
        final playback = session.playback;
        Clip? clip;
        if (playback.positionMs < playback.durationMs) {
          final current = playback.currentClip;
          if (current?.id == id) clip = current;
          final o = playback.overlayItem;
          if (o?.id == id) clip = o!.clip;
        }
        if (clip == null) return const SizedBox.shrink();
        return CropFrame(
          key: ValueKey('crop-frame-$id'),
          session: session,
          itemId: id,
          clip: clip,
          full: cropEditorPicture(clip, size.width, size.height,
              margin: kCropEditorMargin),
        );
      },
    );
  }
}
