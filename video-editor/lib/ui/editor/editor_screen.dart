import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/editor/autosave.dart';
import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../../core/storage/media_import.dart' show relinkProject;
import '../../core/storage/project_lock.dart' show AppProjectLock;
import '../app_menu.dart';
import '../app_prefs.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../help/tour.dart';
import '../playback/media_kit_backend.dart' show MediaKitBackend;
import '../playback/playback_controller.dart';
import '../file_drop.dart';
import '../gallery_search.dart';
import '../music_search.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'clip_actions.dart';
import 'export_dialog.dart';
import 'history_panel.dart';
import 'import_actions.dart';
import 'leave_flow.dart';
import 'music_actions.dart';
import 'preview_view.dart';
import 'save_status.dart';
import 'session.dart';
import 'sound_tracks_ui.dart' show addSoundTrack, separateSound;
import 'voice_actions.dart' show addVoiceRecording, lineUpVoice;
import 'timeline_view.dart';
import 'tools.dart';

/// One step of the Left / Right keys: one frame of the clip under the
/// playhead (its source frame rate, speed included), else 33 ms (a frame
/// at 30 fps) when that is not known (photos, clips added before 1.7).
int frameStepFor(EditorSession s) {
  const fallback = 33;
  final p = s.project;
  final t = s.playback.positionMs;
  final i = t < p.durationMs ? p.clipIndexAt(t) : p.clips.length - 1;
  if (i < 0) return fallback;
  final c = p.clips[i];
  if (c.type != ClipType.video || c.frameRate <= 1) return fallback;
  final ms = (1000 / c.frameRate / (c.speed <= 0 ? 1 : c.speed)).round();
  return ms < 1 ? 1 : ms;
}

/// Window width from which the editor uses the side-panel layout.
const double kWideLayoutWidth = 900;

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    super.key,
    required this.projectId,
    this.initialDrop,
    this.tour = false,
  });
  final String projectId;

  /// This is the tour's sample project: the tour selects clips and opens
  /// tools here, and closes the editor when it ends.
  final bool tour;

  /// Files dropped on the project list to start this project with; added
  /// as soon as the project is open.
  final FileDrop? initialDrop;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  EditorSession? _session;
  Autosaver? _autosaver;

  /// Tells the unused-media clean-up what this editor still uses.
  Iterable<String> Function()? _liveMedia;
  LiveMedia? _liveRegistry;
  Object? _loadError;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _closing = false;

  /// Receives the keyboard shortcuts while nothing else in the editor has
  /// the focus.
  final FocusNode _keys = FocusNode(debugLabel: 'editor shortcuts');

  /// Looks at the autosaver now and then: it reports nothing by itself.
  Timer? _saveWatch;

  /// Marks the project as open in the app while this editor shows it.
  AppProjectLock? _lock;

  /// Hears the window being closed and Cmd+Q / Alt+F4 (desktop).
  late final AppLifecycleListener _exitListener;

  /// True while the quit questions are on screen.
  bool _askingToQuit = false;

  late final TourController _tour = ref.read(tourControllerProvider);
  late final TourEditorHooks _tourHooks = TourEditorHooks(close: _close);

  /// The tour step whose set-up was last done here.
  String? _tourStepApplied;

  /// "Play backwards" (J): media players cannot play backwards smoothly,
  /// so the playhead steps back in small jumps at about normal speed.
  Timer? _reverse;
  static const int _reverseStepMs = 120;

  void _stopReverse() {
    _reverse?.cancel();
    _reverse = null;
  }

  void _playBackwards(EditorSession s) {
    final playback = s.playback;
    playback.pause();
    if (_reverse != null) return;
    _reverse = Timer.periodic(const Duration(milliseconds: _reverseStepMs), (_) {
      if (!mounted || s.isDisposed) return _stopReverse();
      final t = playback.positionMs - _reverseStepMs;
      playback.seek(t < 0 ? 0 : t);
      if (t <= 0) _stopReverse();
    });
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
    _exitListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    if (widget.tour) _tour.attachEditor(_tourHooks);
    _tour.addListener(_onTour);
    _load();
  }

  /// The tour moved on (sample project), or was asked for from Help or the
  /// menu bar (any other project: it starts on the project list, so this
  /// editor saves and closes).
  void _onTour() {
    if (!mounted) return;
    if (!widget.tour) {
      if (_tour.startRequested) _close();
      return;
    }
    final s = _session;
    final step = _tour.step;
    if (s == null ||
        step == null ||
        !step.inEditor ||
        _tour.phase != TourPhase.running ||
        _tourStepApplied == step.id) {
      return;
    }
    _tourStepApplied = step.id;
    s.playback.pause();
    final first = s.project.clips.firstOrNull;
    switch (step.setup) {
      case TourSetup.none:
        break;
      case TourSetup.nothingSelected:
        s.clearSelection();
      case TourSetup.selectFirstClip:
      case TourSetup.openSoundTools:
        if (first != null && s.selectedClip?.id != first.id) {
          s.selectClipAndShow(first.id);
        }
        if (step.setup == TourSetup.openSoundTools) {
          s.openTool.value = ClipTool.sound;
        }
    }
  }

  Future<void> _load() async {
    try {
      final store = await ref.read(projectStoreProvider.future);
      var project = await store.load(widget.projectId);
      // Android: files a pre-1.8 project still has in the cache folder
      // move into the app's media folder before the cache is emptied.
      final moved = await ref.read(mediaRescueProvider)(project);
      if (moved.isNotEmpty) {
        project = relinkProject(project, moved);
        try {
          await store.save(project);
        } catch (_) {}
      }
      if (!mounted) return;
      // "Open in the app": Claude's tools leave the project alone meanwhile.
      _lock = ref.read(projectLockProvider)(store, widget.projectId)?..acquire();
      final backend = ref.read(playerBackendProvider);
      final editor = EditorController(project);
      final playback = PlaybackController(
        project: project,
        video: backend.createVideoPlayer(),
        createVideoPlayer: backend.createVideoPlayer,
        createAudioPlayer: backend.createAudioPlayer,
        fileExists: ref.read(fileExistsProvider),
      );
      playback.addListener(_onPlaybackChanged);
      setState(() {
        _session = EditorSession(
          editor: editor,
          playback: playback,
          backend: backend,
          engine: ref.read(mediaEngineProvider),
          files: ref.read(fileServiceProvider),
          documents: ref.read(documentServiceProvider),
          thumbnails: ref.read(thumbnailsProvider),
          soundCache: ref.read(processedSoundCacheProvider),
          gallery: ref.read(gallerySearchProvider),
          music: ref.read(musicSearchProvider),
        );
        _autosaver = Autosaver(editor, store);
      });
      _liveMedia = () => editor.editor.mediaPathsInHistory;
      _liveRegistry = ref.read(liveMediaProvider);
      _liveRegistry!.add(_liveMedia!);
      final s = _session!;
      editor.addListener(_onEdited);
      s.selection.addListener(_updateMenu);
      s.snapping.addListener(_updateMenu);
      s.copiedSettings.addListener(_updateMenu);
      // Timeline snapping is an app setting (on unless turned off).
      final prefs = ref.read(appPrefsProvider);
      // Phones: lighter preview decoding unless turned off (More sheet).
      if (Platform.isAndroid || Platform.isIOS) {
        prefs.flag(kSmoothPreviewOffFlag).then((off) {
          MediaKitBackend.smoothPreview = !off;
        }).catchError((Object _) {});
      }
      prefs.flag(kSnappingOffFlag).then((off) {
        if (mounted && !s.isDisposed) s.snapping.value = !off;
      }).catchError((Object _) {});
      _updateMenu();
      _saveWatch = Timer.periodic(
          const Duration(milliseconds: 500), (_) => _checkSaved());
      _onTour();
      final drop = widget.initialDrop;
      if (drop != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) addDroppedFiles(context, s, drop);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _onEdited() {
    _checkSaved();
    _updateMenu();
  }

  /// Tells the menu bar (macOS; Windows and Linux: the one in the
  /// window) what the editor can do now.
  void _updateMenu() {
    final s = _session;
    if (s == null || !mounted) return;
    final playback = s.playback;
    appMenu.attach(
      this,
      EditorMenuActions(
        canUndo: s.editor.canUndo,
        canRedo: s.editor.canRedo,
        canDelete: s.selection.value != null,
        canPlay: playback.durationMs > 0,
        playing: playback.playing,
        undo: _inFront(s.editor.undo),
        redo: _inFront(s.editor.redo),
        showHistory: _inFront(() => _toggleHistory(s)),
        delete: _inFront(() => _deleteSelection(s)),
        togglePlay: _inFront(() {
          _stopReverse();
          if (playback.durationMs > 0) playback.toggle();
        }),
        canExport: s.project.clips.isNotEmpty,
        export: _inFront(() {
          if (s.project.clips.isNotEmpty) _export(s);
        }),
        canCrop: _pictureId(s) != null,
        cropAndPosition: _inFront(() => _openCrop(s)),
        rotateRight: _inFront(() {
          final id = _pictureId(s);
          if (id != null) s.editor.rotatePicture(id);
        }),
        canAddOverlay: s.project.clips.isNotEmpty,
        addOverlay: _inFront(() {
          if (s.project.clips.isNotEmpty) addOverlay(context, s);
        }),
        extra: _extraMenu(s),
        backToProjects: _inFront(() {
          // Like the back arrow: during the tour it ends the tour.
          if (widget.tour && _tour.active) {
            _tour.skip();
          } else {
            _close();
          }
        }),
      ),
    );
  }

  /// The menu items added in 1.7 (see [EditorMenuExtra]); a null action is
  /// shown greyed out.
  EditorMenuExtra _extraMenu(EditorSession s) {
    final p = s.project;
    final has = p.clips.isNotEmpty;
    final clip = s.selectedClip;
    final clipIndex = clip == null ? -1 : p.clips.indexOf(clip);
    final under = s.clipIndexUnderPlayhead;
    final settingsClip = clip ?? (under >= 0 ? p.clips[under] : null);
    final videoUnder = under >= 0 && p.clips[under].type == ClipType.video;
    final separatedOf = clip == null
        ? null
        : p.audio
            .where((a) => a.isSeparated && a.sourceClipId == clip.id)
            .firstOrNull;
    final selectedSound = s.selectedAudio;
    final soundToPutBack = selectedSound != null &&
            selectedSound.isSeparated &&
            p.clips.any((c) => c.id == selectedSound.sourceClipId)
        ? selectedSound
        : separatedOf;
    VoidCallback? f(bool ok, VoidCallback a) => ok ? _inFront(a) : null;
    return EditorMenuExtra(
      addMedia: _inFront(() => addMedia(context, s)),
      addMusic: f(has, () => showAddMusic(context, s)),
      addTitle: f(has, () {
        addTitle(s);
        if (MediaQuery.sizeOf(context).width < kWideLayoutWidth) {
          showPropertiesSheet(context, s);
        }
      }),
      addCaption: f(has, () => showCaptionsDialog(context, s)),
      importSubtitles: f(has, () => importSubtitles(context, s)),
      exportSubtitles: f(hasCaptions(p), () => exportSubtitles(context, s)),
      renameProject: _inFront(() => _rename(s)),
      split: f(has, () => splitAtPlayhead(context, s)),
      freezeFrame: f(videoUnder, () => freezeFrame(context, s)),
      removeSilences: f(
          (clip ?? settingsClip)?.type == ClipType.video &&
              (clip ?? settingsClip)!.hasAudio,
          () => removeSilences(context, s, (clip ?? settingsClip)!)),
      moveEarlier: f(clipIndex > 0, () => s.editor.moveClip(clipIndex, clipIndex - 1)),
      moveLater: f(clipIndex >= 0 && clipIndex < p.clips.length - 1,
          () => s.editor.moveClip(clipIndex, clipIndex + 1)),
      startAtPlayhead: f(has, () => trimToPlayhead(context, s, start: true)),
      endAtPlayhead: f(has, () => trimToPlayhead(context, s, start: false)),
      duplicate: f(clip != null || s.selectedTitle != null,
          () => duplicateSelection(context, s)),
      copySettings: f(settingsClip != null, () => copyClipSettings(context, s)),
      pasteSettings: f(settingsClip != null && s.copiedSettings.value != null,
          () => pasteClipSettings(context, s)),
      separateSound: f(
          clip != null && EditorController.separateSoundProblem(p, clip.id) == null,
          () => separateSound(context, s, clip!)),
      putSoundBack: f(soundToPutBack != null,
          () => s.editor.reattachSound(soundToPutBack!.id)),
      addVoice: f(p.clips.any((c) => c.type == ClipType.video),
          () => addVoiceRecording(context, s)),
      lineUpVoice: f(
          selectedSound != null &&
              !selectedSound.isSeparated &&
              p.clips.any((c) => c.type == ClipType.video),
          () => lineUpVoice(context, s, selectedSound!.id)),
      addSoundTrack: f(
          has && p.soundTracks.length < EditorController.maxSoundTracks,
          () => addSoundTrack(context, s)),
      fitMusic: f(s.selectedAudio != null && !s.selectedAudio!.belongsToClip,
          () => fitMusic(context, s, s.selectedAudio!.id)),
      copyCredits: f(p.audio.any((a) => a.credit != null),
          () => copyMusicCredits(context, s)),
      lowerMusic: f(p.audio.isNotEmpty, () => s.editor.setDuckMusic(!p.duckMusic)),
      lowerMusicOn: p.duckMusic,
      shape: _inFront2<CanvasAspect>(s.editor.setAspect),
      currentShape: p.aspect,
      videoSize: _inFront2<VideoSize>(s.editor.setVideoSize),
      currentVideoSize: p.videoSize,
      goToStart: f(has, () => s.playback.seek(0)),
      goToEnd: f(has, () => s.playback.seek(s.playback.durationMs)),
      playBackwards: f(has, () => _playBackwards(s)),
      pause: f(has, () {
        _stopReverse();
        s.playback.pause();
      }),
      playForwards: f(has, () {
        _stopReverse();
        if (!s.playback.playing) s.playback.toggle();
      }),
      previousFrame: f(has, () => _step(s, -frameStepFor(s))),
      nextFrame: f(has, () => _step(s, frameStepFor(s))),
      zoomIn: _inFront(() => s.setZoom(s.zoom.value * 1.5)),
      zoomOut: _inFront(() => s.setZoom(s.zoom.value / 1.5)),
      toggleSnapping: _inFront(() => _setSnapping(s, !s.snapping.value)),
      snapping: s.snapping.value,
      showShortcuts: _inFront(() => showHelpArticle(context, 'keyboard-shortcuts')),
    );
  }

  ValueChanged<T> _inFront2<T>(ValueChanged<T> action) => (v) {
        if (!mounted) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        action(v);
      };

  void _step(EditorSession s, int by) {
    _stopReverse();
    s.playback.pause();
    s.playback.seek(s.playback.positionMs + by);
  }

  /// Turns timeline snapping on or off and remembers it.
  void _setSnapping(EditorSession s, bool on) {
    s.snapping.value = on;
    final prefs = ref.read(appPrefsProvider);
    (on ? prefs.clearFlag(kSnappingOffFlag) : prefs.setFlag(kSnappingOffFlag))
        .catchError((Object _) {});
  }

  /// [action], run only while the editor itself is in front: the menu bar
  /// sits outside the window's dialogs, so it can be used while one is
  /// open, and must not act behind it.
  VoidCallback _inFront(VoidCallback action) => () {
        if (!mounted) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        action();
      };

  void _onPlaybackChanged() {
    _updateMenu();
    final playing = _session?.playback.playing ?? false;
    if (playing && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMilliseconds;
    if (delta <= 0) return;
    _lastTick += Duration(milliseconds: delta);
    _session?.playback.tick(delta);
  }

  void _checkSaved() {
    final s = _session;
    final saver = _autosaver;
    if (s == null || saver == null || !mounted) return;
    final failed = saver.lastError != null;
    s.saveFailed.value = failed;
    final before = s.saveStatus.value;
    final state = failed
        ? SaveState.failed
        : saver.isSaving || saver.hasPendingChanges
            ? SaveState.saving
            : SaveState.saved;
    if (state == before.state) return;
    s.saveStatus.value = SaveStatus(state,
        savedAt: state == SaveState.saved ? DateTime.now() : before.savedAt);
  }

  /// Tries to write the project again after a failed save.
  Future<void> _retrySave() async {
    await _autosaver?.flush();
    if (!mounted) return;
    _checkSaved();
    final error = _autosaver?.lastError;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(error == null
              ? 'Saved.'
              : 'Still not saved: ${_plainError(error)}')));
  }

  static String _plainError(Object error) {
    final text = '$error';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _session?.playback.pause();
      _autosaver?.flush().then((_) => _checkSaved());
    } else if (state == AppLifecycleState.resumed) {
      // Files may have been moved, deleted or put back meanwhile.
      _session?.playback.recheckFiles();
    }
  }

  // Keyboard -----------------------------------------------------------------

  /// A text field gives up the focus when something else is clicked (on a
  /// computer), but hands it to the page as a whole, where no key handler
  /// listens. Pick it up, so the shortcuts work again.
  void _onFocusChanged() {
    if (!mounted || _keys.context == null) return;
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && identical(focused, _keys.enclosingScope)) {
      _keys.requestFocus();
    }
  }

  static bool _typing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused.widget is EditableText) return true;
    return focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final s = _session;
    if (s == null || event is KeyUpEvent || _typing()) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final command = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    final playback = s.playback;

    if (command) {
      if (keys.isAltPressed) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? s.editor.redo() : s.editor.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY && !shift) {
        s.editor.redo();
        return KeyEventResult.handled;
      }
      if (repeat) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyD && !shift) {
        duplicateSelection(context, s);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC && shift) {
        copyClipSettings(context, s);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV && shift) {
        pasteClipSettings(context, s);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keys.isAltPressed) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // Shift: a second; otherwise one frame of the clip under the playhead.
      final step = shift ? 1000 : frameStepFor(s);
      _step(s, key == LogicalKeyboardKey.arrowLeft ? -step : step);
      return KeyEventResult.handled;
    }
    // Timeline zoom: + (also = on keyboards where + needs Shift) and -.
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      s.setZoom(s.zoom.value * 1.5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      s.setZoom(s.zoom.value / 1.5);
      return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.space) {
      _stopReverse();
      if (playback.durationMs > 0) playback.toggle();
      return KeyEventResult.handled;
    }
    // J / K / L: backwards, stop, forwards.
    if (key == LogicalKeyboardKey.keyJ) {
      if (playback.durationMs > 0) _playBackwards(s);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK) {
      _stopReverse();
      playback.pause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      _stopReverse();
      if (playback.durationMs > 0 && !playback.playing) playback.toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI || key == LogicalKeyboardKey.keyO) {
      if (s.project.clips.isNotEmpty) {
        _stopReverse();
        playback.pause();
        trimToPlayhead(context, s, start: key == LogicalKeyboardKey.keyI);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _stopReverse();
      playback.seek(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _stopReverse();
      playback.seek(playback.durationMs);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS && !shift) {
      if (s.project.clips.isNotEmpty) splitAtPlayhead(context, s);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      return _deleteSelection(s)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// The selected clip or overlay item, whose picture the menu bar's
  /// "Crop and position" works on; null for anything else.
  static String? _pictureId(EditorSession s) =>
      s.selectedClip?.id ?? s.selectedOverlay?.id;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  /// Edit > Crop and position…: the Crop section of the side panel, or the
  /// crop sheet when the window is too narrow for the panel.
  void _openCrop(EditorSession s) {
    final id = _pictureId(s);
    if (id == null) return;
    if (MediaQuery.sizeOf(context).width >= kWideLayoutWidth) {
      s.openTool.value = ClipTool.crop;
    } else {
      showCropSheet(context, s, id, scaffold: _scaffoldKey.currentState);
    }
  }

  /// Deletes what is selected on the timeline (Delete key, menu bar).
  /// False when nothing is.
  static bool _deleteSelection(EditorSession s) {
    final selection = s.selection.value;
    if (selection == null) return false;
    switch (selection.kind) {
      case ItemKind.clip:
        s.editor.removeClip(selection.id);
      case ItemKind.audio:
        s.editor.removeAudio(selection.id);
      case ItemKind.title:
        s.editor.removeTitle(selection.id);
      case ItemKind.overlay:
        s.editor.removeOverlay(selection.id);
    }
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChanged);
    _exitListener.dispose();
    _tour.removeListener(_onTour);
    _tour.detachEditor(_tourHooks);
    appMenu.detach(this);
    _stopReverse();
    _session?.editor.removeListener(_onEdited);
    _session?.selection.removeListener(_updateMenu);
    _session?.snapping.removeListener(_updateMenu);
    _session?.copiedSettings.removeListener(_updateMenu);
    _saveWatch?.cancel();
    _lock?.release();
    _keys.dispose();
    _ticker.dispose();
    _autosaver?.dispose();
    final live = _liveMedia;
    if (live != null) _liveRegistry?.remove(live);
    _session?.playback.removeListener(_onPlaybackChanged);
    _session?.dispose();
    _session?.editor.dispose();
    super.dispose();
  }

  /// Saves and checks that nothing is lost by leaving now (see
  /// [confirmLeave]): asks only when an export or analysis is running or
  /// the save failed. True when the editor may go.
  Future<bool> _readyToLeave(LeaveReason reason) async {
    final s = _session;
    if (s == null) return true;
    s.playback.pause();
    final ok = await confirmLeave(
      flush: () async {
        await _autosaver?.flush();
        _checkSaved();
      },
      saveError: () => _autosaver?.lastError,
      jobs: s.jobs,
      askStopJobs: (running) => mounted
          ? askStopJobs(context, running, reason: reason)
          : Future.value(true),
      askSaveFailed: (error) => mounted
          ? askSaveFailed(context, error, reason: reason)
          : Future.value(SaveFailedChoice.leaveWithoutSaving),
    );
    return ok;
  }

  /// Back to the project list (back arrow, Android back button). Saves
  /// first; when the save fails the user is told and stays, unless they
  /// choose to leave without the latest changes.
  Future<void> _close() async {
    if (_closing || _askingToQuit) return;
    _closing = true;
    try {
      final ok = await _readyToLeave(LeaveReason.backToProjects);
      if (ok && mounted) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  /// The app is asked to quit (window closed, Cmd+Q, Alt+F4) while this
  /// editor is open. Saves, asks only when something would be lost, and
  /// stops playback before saying yes. The players are not destroyed here:
  /// the process ends with them (see [VideoPlayerPool] for why a video
  /// player's core is never destroyed while the app runs).
  Future<AppExitResponse> _onExitRequested() async {
    if (_session == null) return AppExitResponse.exit;
    // A second request while the questions are up (Cmd+Q pressed twice).
    if (_askingToQuit || _closing) return AppExitResponse.cancel;
    _askingToQuit = true;
    try {
      final ok = await _readyToLeave(LeaveReason.quitApp);
      if (!ok) return AppExitResponse.cancel;
      _session?.playback.pause();
      // dispose() may not run when the app quits.
      _lock?.release();
      return AppExitResponse.exit;
    } finally {
      _askingToQuit = false;
    }
  }

  /// Shows or hides the History column (wide windows) or opens the
  /// History sheet (phones).
  void _toggleHistory(EditorSession s) {
    if (MediaQuery.sizeOf(context).width < kWideLayoutWidth) {
      showHistorySheet(context, s);
    } else {
      s.showHistory.value = !s.showHistory.value;
    }
  }

  Future<void> _rename(EditorSession s) async {
    final name = await promptText(context,
        title: 'Rename project', initial: s.project.name);
    if (name != null) s.editor.rename(name);
  }

  Future<void> _export(EditorSession s) async {
    s.playback.pause();
    await _autosaver?.flush();
    if (!mounted) return;
    _checkSaved();
    // An export cannot work without every file; say which ones are gone
    // instead of starting.
    List<String> gone;
    try {
      gone = await ref.read(missingMediaProvider)(s.project);
    } catch (_) {
      gone = const [];
    }
    if (!mounted) return;
    s.playback.recheckFiles();
    if (gone.isNotEmpty) {
      final ready = await showMissingMediaDialog(
        context,
        session: s,
        check: ref.read(missingMediaProvider),
        missing: gone,
      );
      if (!ready || !mounted) return;
    }
    await showExportDialog(
      context,
      project: s.project,
      engine: s.engine,
      files: s.files,
      jobs: s.jobs,
      processedSound: () => s.sounds.readyFiles(s.project),
      onVideoSize: s.editor.setVideoSize,
      documents: s.documents,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.danger),
                      const SizedBox(height: 12),
                      const Text('This project could not be opened.'),
                      const SizedBox(height: 4),
                      Text('$_loadError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 12)),
                    ],
                  ),
                ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back during the tour ends the tour (which closes this editor).
        if (widget.tour && _tour.active) {
          _tour.skip();
        } else {
          _close();
        }
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _onKey,
        child: _dropZone(s, _scaffold(s)),
      ),
    );
  }

  /// Files dragged onto the editor from the desktop are added to the
  /// project; over the timeline they go where they are dropped.
  Widget _dropZone(EditorSession s, Widget child) {
    TimelineDropLocator? locator() => timelineDropLocators[s];
    return FileDropZone(
      message: 'Drop to add to this video',
      messageAt: (global) =>
          locator()?.call(global) == null ? null : 'Drop to add here',
      lineAt: (global) => locator()?.call(global)?.line,
      onDrop: (drop) => addDroppedFiles(context, s, drop,
          atIndex: locator()?.call(drop.globalPosition)?.index),
      child: child,
    );
  }

  Widget _scaffold(EditorSession s) {
    return Scaffold(
        key: _scaffoldKey,
        appBar: _topBar(s),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= kWideLayoutWidth;
              final preview =
                  PreviewView(session: s, onAddMedia: () => addMedia(context, s));
              final timeline = TourAnchor(
                id: TourIds.timeline,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.panel,
                    border: Border(top: BorderSide(color: AppColors.outline)),
                  ),
                  child: TimelineView(
                    session: s,
                    // Phones have no side panel: the settings open as a
                    // sheet.
                    onTransitionTap: wide
                        ? null
                        : () => showClipToolSheet(
                            context, s, ClipTool.transition),
                  ),
                ),
              );
              final notSaved = _NotSavedBar(session: s, onRetry: _retrySave);
              if (wide) {
                return Column(
                  children: [
                    notSaved,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: preview),
                                TransportBar(session: s),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          TourAnchor(
                            id: TourIds.inspector,
                            child: SizedBox(
                                width: 340,
                                child: InspectorPanel(session: s)),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: s.showHistory,
                            builder: (context, shown, _) => shown
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const VerticalDivider(width: 1),
                                      SizedBox(
                                          width: 260,
                                          child: HistoryPanel(session: s)),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    timeline,
                  ],
                );
              }
              return Column(
                children: [
                  notSaved,
                  Expanded(child: preview),
                  TransportBar(
                    session: s,
                    onAdd: () => showAddSheet(context, s),
                  ),
                  timeline,
                  ToolBar(session: s),
                ],
              );
            },
          ),
        ),
    );
  }

  PreferredSizeWidget _topBar(EditorSession s) {
    final narrow = MediaQuery.sizeOf(context).width < kWideLayoutWidth;
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        tooltip: 'Back to projects',
        icon: const Icon(Icons.arrow_back, semanticLabel: 'Back to projects'),
        onPressed: _close,
      ),
      title: ListenableBuilder(
        listenable: s.editor,
        builder: (context, _) => Tooltip(
          message: 'Rename project',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _rename(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Text(
                s.project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TourAnchor(
          id: TourIds.saveStatus,
          child: SaveStatusIndicator(
            status: s.saveStatus,
            onRetry: _retrySave,
            compact: MediaQuery.sizeOf(context).width < kWideLayoutWidth,
          ),
        ),
        ListenableBuilder(
          listenable: s.editor,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Undo',
                // Phones: a little narrower, so the project name keeps
                // some room next to Help.
                visualDensity: narrow ? VisualDensity.compact : null,
                icon: const Icon(Icons.undo, semanticLabel: 'Undo'),
                onPressed: s.editor.canUndo ? s.editor.undo : null,
              ),
              IconButton(
                tooltip: 'Redo',
                visualDensity: narrow ? VisualDensity.compact : null,
                icon: const Icon(Icons.redo, semanticLabel: 'Redo'),
                onPressed: s.editor.canRedo ? s.editor.redo : null,
              ),
              // Phones open the history from the More menu.
              if (!narrow)
                ValueListenableBuilder<bool>(
                  valueListenable: s.showHistory,
                  builder: (context, shown, _) => IconButton(
                    key: const ValueKey('history-button'),
                    tooltip: shown ? 'Hide history' : 'History',
                    isSelected: shown,
                    icon: const Icon(Icons.history, semanticLabel: 'History'),
                    onPressed: () => _toggleHistory(s),
                  ),
                ),
              TourAnchor(
                id: TourIds.shape,
                child: PopupMenuButton<Object>(
                tooltip: 'Shape of the video: upright, wide or square',
                initialValue: s.project.aspect,
                onSelected: (v) {
                  if (v is CanvasAspect) s.editor.setAspect(v);
                  if (v is VideoSize) s.editor.setVideoSize(v);
                },
                itemBuilder: (context) => [
                  for (final a in CanvasAspect.values)
                    PopupMenuItem(value: a, child: Text(aspectMenuLabel(a))),
                  const PopupMenuDivider(),
                  const PopupMenuItem<Object>(
                    enabled: false,
                    height: 28,
                    child: Text('Video size',
                        style: TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ),
                  for (final v in VideoSize.values)
                    PopupMenuItem<Object>(
                      key: ValueKey('video-size-${v.name}'),
                      value: v,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: s.project.videoSize == v
                                ? const Icon(Icons.check, size: 18)
                                : null,
                          ),
                          Text(videoSizeLabel(v)),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem<Object>(
                    key: const ValueKey('help-hint-shape'),
                    // The menu closes first, then the help opens.
                    onTap: () => WidgetsBinding.instance
                        .addPostFrameCallback((_) {
                      if (mounted) showHelpArticle(this.context, 'shape');
                    }),
                    child: const Row(
                      children: [
                        Icon(Icons.help_outline,
                            size: 18, color: AppColors.textDim),
                        SizedBox(width: 10),
                        Text('Which shape should I use?'),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.aspect_ratio, size: 20),
                      const SizedBox(height: 2),
                      Text(
                        MediaQuery.sizeOf(context).width >= kWideLayoutWidth
                            ? 'Shape: ${aspectLabel(s.project.aspect)}'
                            : 'Shape',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TourAnchor(
                  id: TourIds.export,
                  child: FilledButton(
                    onPressed:
                        s.project.clips.isEmpty ? null : () => _export(s),
                    style: FilledButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: narrow ? 12 : 16),
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Text('Export'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: 'Help',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.help_outline, semanticLabel: 'Help'),
                  onPressed: () {
                    s.playback.pause();
                    openHelp(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String aspectLabel(CanvasAspect aspect) => switch (aspect) {
      CanvasAspect.original => 'Original',
      CanvasAspect.portrait9x16 => '9:16',
      CanvasAspect.landscape16x9 => '16:9',
      CanvasAspect.square1x1 => '1:1',
      CanvasAspect.portrait4x5 => '4:5',
    };

/// The shape with a word about what it is for, as the menu shows it.
String aspectMenuLabel(CanvasAspect aspect) => switch (aspect) {
      CanvasAspect.original => 'Original (as the first clip)',
      CanvasAspect.portrait9x16 => '9:16 upright',
      CanvasAspect.landscape16x9 => '16:9 wide',
      CanvasAspect.square1x1 => '1:1 square',
      CanvasAspect.portrait4x5 => '4:5 upright',
    };

/// A thin line at the top of the editor while the project is not on disk.
class _NotSavedBar extends StatelessWidget {
  const _NotSavedBar({required this.session, required this.onRetry});
  final EditorSession session;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: session.saveFailed,
      builder: (context, failed, _) {
        if (!failed) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF3A2A12),
          child: InkWell(
            onTap: onRetry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 16, color: Color(0xFFFFC56B)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Not saved — retry',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Color(0xFFFFC56B)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Play / pause, the current time and the timeline zoom buttons.
class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.session, this.onAdd});
  final EditorSession session;

  /// Phones: opens the list of things that can be added. Wide windows have
  /// those in the side panel.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final playback = session.playback;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: playback,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Back to start',
                    icon: const Icon(Icons.skip_previous, semanticLabel: 'Back to start'),
                    onPressed:
                        playback.durationMs > 0 ? () => playback.seek(0) : null,
                  ),
                  IconButton.filled(
                    tooltip: playback.playing ? 'Pause' : 'Play',
                    iconSize: 28,
                    icon: Icon(
                        playback.playing ? Icons.pause : Icons.play_arrow,
                        semanticLabel: playback.playing ? 'Pause' : 'Play'),
                    onPressed: playback.durationMs > 0 ? playback.toggle : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([playback.position, playback]),
                builder: (context, _) => Text(
                  '${formatTime(playback.positionMs)} / '
                  '${formatTime(playback.durationMs)}',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (onAdd != null)
              IconButton(
                tooltip: 'Add videos, photos, music or text',
                icon: const Icon(Icons.add_circle_outline, semanticLabel: 'Add videos, photos, music or text'),
                onPressed: onAdd,
              ),
            ValueListenableBuilder<double>(
              valueListenable: session.zoom,
              builder: (context, zoom, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Zoom out timeline',
                    icon: const Icon(Icons.zoom_out, semanticLabel: 'Zoom out timeline'),
                    onPressed: zoom > EditorSession.minZoom
                        ? () => session.setZoom(session.zoom.value / 1.5)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Zoom in timeline',
                    icon: const Icon(Icons.zoom_in, semanticLabel: 'Zoom in timeline'),
                    onPressed: zoom < EditorSession.maxZoom
                        ? () => session.setZoom(session.zoom.value * 1.5)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
