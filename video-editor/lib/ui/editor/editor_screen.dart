import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/editor/autosave.dart';
import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../../core/storage/media_import.dart' show relinkProject;
import '../../core/storage/project_lock.dart' show AppProjectLock;
import '../../core/storage/project_store.dart' show freeProjectName;
import '../app_menu.dart';
import '../app_prefs.dart';
import '../format.dart';
import '../feedback/feedback_screen.dart';
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
import '../app_settings.dart';
import 'clip_actions.dart';
import 'editor_actions.dart';
import 'add_from_path.dart';
import 'part_actions.dart';
import 'suggestions.dart';
import 'export_dialog.dart';
import 'history_panel.dart';
import 'text_panel.dart';
import '../speech/speech_service.dart';
import 'import_actions.dart';
import 'leave_flow.dart';
import 'preview_view.dart';
import 'shorts_actions.dart';
import '../publish_service.dart';
import 'save_status.dart';
import 'session.dart';
export 'session.dart' show kWideLayoutWidth;
export 'editor_actions.dart' show frameStepFor;
import 'timeline_view.dart';
import 'tools.dart';

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
  AppSettings? _settings;
  SuggestionController? _suggestions;

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
    FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onAnyPointer);
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
          speech: ref.read(speechServiceProvider),
          store: store,
          publish: ref.read(publishServiceProvider),
        );
        _autosaver = Autosaver(editor, store);
      });
      _session!
        ..saveNow = (() async => _autosaver?.flush())
        ..openProject = _openOther
        ..hooks = EditorHooks(
          export: ({bool several = false}) {
            final s = _session;
            if (s != null && s.project.clips.isNotEmpty) {
              _export(s, several: several);
            }
          },
          rename: () {
            final s = _session;
            if (s != null) _rename(s);
          },
          backToProjects: _back,
          playBackwards: () {
            final s = _session;
            if (s != null) _playBackwards(s);
          },
          stopReverse: _stopReverse,
          setSnapping: (on) {
            final s = _session;
            if (s != null) _setSnapping(s, on);
          },
          setSoundWaves: (on) {
            final s = _session;
            if (s != null) _setWaves(s, on);
          },
          scaffold: () => _scaffoldKey.currentState,
        );
      _suggestions = SuggestionController(
        session: _session!,
        settings: ref.read(appSettingsProvider),
        host: () => mounted ? context : null,
      );
      _liveMedia = () => editor.editor.mediaPathsInHistory;
      _liveRegistry = ref.read(liveMediaProvider);
      _liveRegistry!.add(_liveMedia!);
      final s = _session!;
      editor.addListener(_onEdited);
      s.selection.addListener(_updateMenu);
      s.snapping.addListener(_updateMenu);
      s.copiedSettings.addListener(_updateMenu);
      s.showText.addListener(_updateMenu);
      s.showWaves.addListener(_updateMenu);
      s.playheadClip.addListener(_updateMenu);
      s.part.addListener(_updateMenu);
      s.partRows.addListener(_updateMenu);
      s.pictures.addListener(_onPictures);
      s.transcripts.addListener(_updateMenu);
      unawaited(s.loadTranscripts());
      // Snapping, sound waves, where the Text window sits and (phones)
      // the lighter preview are app settings: one live object that the
      // Settings page and the View menu write to as well.
      final settings = ref.read(appSettingsProvider);
      _settings = settings;
      settings.addListener(_onSettings);
      settings.load().then((_) => _onSettings());
      final prefs = ref.read(appPrefsProvider);
      prefs.text(kTextWidthText).then((v) {
        final w = double.tryParse(v ?? '');
        if (mounted && !s.isDisposed && w != null && w >= kTextMinWidth) {
          s.textWidth.value = w;
        }
      }).catchError((Object _) {});
      prefs.text(kTextHeightText).then((v) {
        final h = double.tryParse(v ?? '');
        if (mounted && !s.isDisposed && h != null && h >= kTextMinHeight) {
          s.textHeight.value = h;
        }
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

  /// Whether there is speech to jump to changes as the sound pictures
  /// arrive.
  bool _hadSpeakers = false;
  void _onPictures() {
    final has = _session?.pictures.speakers.any((t) => t.stretches.isNotEmpty) ??
        false;
    if (has == _hadSpeakers) return;
    _hadSpeakers = has;
    _updateMenu();
  }

  /// Turns "Show sound waves" on or off and remembers it.
  void _setWaves(EditorSession s, bool on) {
    s.showWaves.value = on;
    s.pictures.enabled = on;
    ref.read(appSettingsProvider).setSoundWaves(on);
  }

  void _setTextDock(EditorSession s, TextDock dock) {
    s.textDock.value = dock;
    ref.read(appSettingsProvider).setTextBelow(dock == TextDock.below);
  }

  void _rememberTextSize(EditorSession s) {
    final prefs = ref.read(appPrefsProvider);
    prefs
        .setText(kTextWidthText, s.textWidth.value.round().toString())
        .catchError((Object _) {});
    prefs
        .setText(kTextHeightText, s.textHeight.value.round().toString())
        .catchError((Object _) {});
  }

  /// Tells the menu bar (macOS; Windows and Linux: the one in the
  /// window) what the editor can do now. What can be done, and why not,
  /// comes from [EditorActions]: the same source the side panel, the
  /// phone's bars and the timeline's context menu use.
  void _updateMenu() {
    final s = _session;
    if (s == null || !mounted) return;
    final actions = EditorActions(s);
    appMenu.attach(
      this,
      EditorMenuActions(
        entries: {
          for (final a in Act.values)
            if (a != Act.editItem && a != Act.shapeAndSize && a != Act.fades)
              a: _menuEntry(actions, a),
        },
        playing: s.playback.playing,
        // Computers only: without a speech service the speech items are
        // not in the menu at all.
        speech: s.speech != null,
        shape: _inFront2<CanvasAspect>(s.editor.setAspect),
        currentShape: s.project.aspect,
        videoSize: _inFront2<VideoSize>(s.editor.setVideoSize),
        currentVideoSize: s.project.videoSize,
      ),
    );
  }

  /// [a] for the menu bar: it only acts while the editor itself is in
  /// front (see [_inFront]).
  ActionEntry _menuEntry(EditorActions actions, Act a) {
    final reason = actions.whyNot(a);
    return ActionEntry(
      act: a,
      label: actions.label(a),
      icon: actIcon(a),
      reason: reason,
      checked: actions.checked(a),
      mixed: actions.mixed(a),
      onTap: reason == null
          ? _inFront(() {
              if (a == Act.backToProjects) {
                // Like the back arrow: during the tour it ends the tour.
                _back();
              } else {
                actions.run(context, a);
              }
            })
          : null,
    );
  }

  void _back() {
    if (widget.tour && _tour.active) {
      _tour.skip();
    } else {
      _close();
    }
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

  /// Turns timeline snapping on or off and remembers it (the setting is
  /// the app's: see [_onSettings]).
  void _setSnapping(EditorSession s, bool on) {
    s.snapping.value = on;
    ref.read(appSettingsProvider).setSnapping(on);
  }

  /// The app's settings changed (the Settings page, the View menu, another
  /// place): the open editor follows at once.
  void _onSettings() {
    final s = _session;
    if (s == null || !mounted || s.isDisposed) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.loaded) return;
    if (s.snapping.value != settings.snapping) {
      s.snapping.value = settings.snapping;
    }
    if (s.showWaves.value != settings.soundWaves) {
      s.showWaves.value = settings.soundWaves;
      s.pictures.enabled = settings.soundWaves;
    }
    final dock = settings.textBelow ? TextDock.below : TextDock.right;
    if (s.textDock.value != dock) s.textDock.value = dock;
    if (Platform.isAndroid || Platform.isIOS) {
      MediaKitBackend.smoothPreview = settings.smoothPreview;
    }
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

  /// Tab was used to move between the controls (and no click since):
  /// plain keys then belong to the control that has the focus (Space
  /// presses a button, the arrows move a slider), as keyboard users
  /// expect. A click anywhere ends it.
  bool _keyboardNav = false;

  void _onAnyPointer(PointerEvent event) {
    if (event is PointerDownEvent) _keyboardNav = false;
  }

  /// True when this editor is what the user is looking at: the top page
  /// (no dialog, sheet or menu over it), no menu of the menu bar open,
  /// and no text being typed.
  bool _shortcutsActive() {
    if (!mounted || _session == null) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (WindowMenuBar.menuOpen) return false;
    return !_typing();
  }

  /// ALL the editor's shortcuts are answered here, before the focus tree
  /// is asked (1.17, a real Windows test: Ctrl+Z, Ctrl+F and Ctrl+Arrow
  /// sometimes did nothing after a click in the Text window, the side
  /// panel or the timeline - the key went to whatever had the focus, or
  /// to nothing). They no longer depend on which panel has the focus:
  /// whenever the editor is the top page and no text field or dialog has
  /// the keyboard. Text fields keep their own Ctrl+Z / Ctrl+F.
  KeyEventResult _onEarlyKey(KeyEvent event) {
    if (!_shortcutsActive()) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (event is KeyDownEvent) _keyboardNav = true;
      return KeyEventResult.ignored;
    }
    final command = keys.isControlPressed || keys.isMetaPressed;
    if (!command && _keyboardNav) return KeyEventResult.ignored;
    return _onKey(_keys, event);
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
      // Ctrl/Cmd+Left / Right: where speech last started / next starts.
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _stopReverse();
        s.goToSpeechStart(forward: key == LogicalKeyboardKey.arrowRight);
        return KeyEventResult.handled;
      }
      if (repeat) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyF && !shift) {
        findInTextWindow(context, s);
        return KeyEventResult.handled;
      }
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
      // Ctrl/Cmd+V with the path of a file or folder on the clipboard:
      // "Add from a folder path…" opens with it (computers).
      if (key == LogicalKeyboardKey.keyV &&
          !shift &&
          s.files.canChooseSaveLocation) {
        pastePathToAdd(context, s);
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
    // I / O: the selected part starts / ends at the playhead (1.17; as in
    // most editors). Also while playing: marking along is the point.
    if (key == LogicalKeyboardKey.keyI || key == LogicalKeyboardKey.keyO) {
      if (s.project.clips.isNotEmpty) {
        key == LogicalKeyboardKey.keyI
            ? s.markPartStart(playback.positionMs)
            : s.markPartEnd(playback.positionMs);
      }
      return KeyEventResult.handled;
    }
    // Q / W: the clip starts / ends at the playhead (I / O until 1.16).
    if ((key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.keyW) &&
        !shift) {
      if (s.project.clips.isNotEmpty) {
        _stopReverse();
        playback.pause();
        trimToPlayhead(context, s, start: key == LogicalKeyboardKey.keyQ);
      }
      return KeyEventResult.handled;
    }
    // Esc: the selected part goes (nothing else uses Esc here).
    if (key == LogicalKeyboardKey.escape && s.part.value != null) {
      s.clearPart();
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
    // M: a "good moment" marker at the playhead, also while playing.
    if (key == LogicalKeyboardKey.keyM && !shift) {
      markGoodMoment(context, s);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS && !shift) {
      if (s.project.clips.isNotEmpty) splitAtPlayhead(context, s);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      return deleteSelection(s)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChanged);
    // First of all, and whatever else goes wrong below: this editor no
    // longer has the project open (Claude's tools look at the mark).
    _lock?.release();
    _exitListener.dispose();
    _tour.removeListener(_onTour);
    _tour.detachEditor(_tourHooks);
    appMenu.detach(this);
    _settings?.removeListener(_onSettings);
    _suggestions?.dispose();
    _session?.hooks = null;
    _stopReverse();
    _session?.editor.removeListener(_onEdited);
    _session?.selection.removeListener(_updateMenu);
    _session?.snapping.removeListener(_updateMenu);
    _session?.copiedSettings.removeListener(_updateMenu);
    _saveWatch?.cancel();
    _lock?.release();
    FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onAnyPointer);
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
      if (ok && mounted) {
        // Saved and leaving: the project is no longer open here.
        _lock?.release();
        Navigator.of(context).pop();
      }
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

  /// Opens another project (a short that was just made) in place of this
  /// one: saves, lets go of this project, and replaces the page.
  Future<void> _openOther(String projectId) async {
    if (_closing || _askingToQuit || !mounted) return;
    _closing = true;
    try {
      final ok = await _readyToLeave(LeaveReason.backToProjects);
      if (!ok || !mounted) return;
      _lock?.release();
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => EditorScreen(projectId: projectId)));
    } finally {
      _closing = false;
    }
  }

  Future<void> _rename(EditorSession s) async {
    final name = await promptText(context,
        title: 'Rename project', initial: s.project.name);
    if (name == null || name.trim() == s.project.name) return;
    // A name another project has gets " (2)" (as on the project list).
    var given = name.trim();
    try {
      given = await freeProjectName(
          await ref.read(projectStoreProvider.future), name,
          exceptId: s.project.id);
    } catch (_) {
      // The list could not be read: keep the name as typed.
    }
    if (!mounted) return;
    s.editor.rename(given);
    if (given != name.trim()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Another project is already called '
                '"${name.trim()}", so this one is now "$given".')));
    }
  }

  Future<void> _export(EditorSession s, {bool several = false}) async {
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
    // "Only when speaking": the export turns the microphones down by the
    // same lists as the preview; pictures the timeline has not drawn yet
    // are read now (they are kept on disk).
    final gates = await s.exportGates();
    if (!mounted) return;
    await showExportDialog(
      context,
      project: s.project,
      engine: s.engine,
      files: s.files,
      jobs: s.jobs,
      gates: gates,
      processedSound: () => s.sounds.readyFiles(s.project),
      onVideoSize: s.editor.setVideoSize,
      documents: s.documents,
      publish: s.publish,
      onNotes: s.editor.setPublishingNotes,
      turns: () => s.speakerTurnsNow,
      several: several,
      settings: ref.read(appSettingsProvider),
      onKeepCopy: s.store == null
          ? null
          : (variant, name) async {
              // A new project in the list, in the destination's shape.
              final store = s.store!;
              final copy = await store.duplicate(s.project.id,
                  name: await freeProjectName(store, name));
              final saved = Project.fromJson({
                ...variant.toJson(),
                'id': copy.id,
                'name': copy.name,
                'createdAt': copy.createdAt.toUtc().toIso8601String(),
                'updatedAt': copy.updatedAt.toUtc().toIso8601String(),
              });
              await store.save(saved);
              return saved;
            },
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
              final suggestions = _suggestions;
              if (wide) {
                // Narrower than this, a Text window at the right would
                // leave no room for the picture: it sits under it.
                final roomAtRight = box.maxWidth >= 340 + kTextMinWidth + 200;
                return Column(
                  children: [
                    notSaved,
                    // Suggestions: one thin line under the top bar.
                    if (suggestions != null)
                      SuggestionBar(controller: suggestions, phone: false),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ListenableBuilder(
                              listenable: Listenable.merge(
                                  [s.showText, s.textDock, s.textHeight]),
                              builder: (context, _) {
                                final below = s.showText.value &&
                                    (s.textDock.value == TextDock.below ||
                                        !roomAtRight);
                                return LayoutBuilder(
                                  builder: (context, column) => Column(
                                    children: [
                                      Expanded(child: preview),
                                      TransportBar(session: s),
                                      if (below) ...[
                                        _SizeHandle(
                                          key: const ValueKey('text-size-handle'),
                                          vertical: true,
                                          onDrag: (d) => s.textHeight.value =
                                              (s.textHeight.value - d)
                                                  .clamp(kTextMinHeight, 2000.0)
                                                  .toDouble(),
                                          onEnd: () => _rememberTextSize(s),
                                        ),
                                        SizedBox(
                                          // The preview keeps at least a
                                          // strip of 120.
                                          height: s.textHeight.value.clamp(
                                              kTextMinHeight,
                                              math.max(
                                                  kTextMinHeight,
                                                  column.maxHeight - 56 - 126)),
                                          child: _textPanel(s),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
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
                          ListenableBuilder(
                            listenable: Listenable.merge([
                              s.showText, s.textDock, s.textWidth, //
                              s.showHistory,
                            ]),
                            builder: (context, _) {
                              if (!s.showText.value ||
                                  s.textDock.value != TextDock.right ||
                                  !roomAtRight) {
                                return const SizedBox.shrink();
                              }
                              // At least 420 wide; the preview keeps
                              // 300 where the window allows.
                              final most = math.max(
                                  kTextMinWidth,
                                  box.maxWidth -
                                      340 -
                                      (s.showHistory.value ? 261 : 0) -
                                      300);
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _SizeHandle(
                                    key: const ValueKey('text-size-handle'),
                                    vertical: false,
                                    onDrag: (d) => s.textWidth.value =
                                        (s.textWidth.value.clamp(
                                                    kTextMinWidth, most) -
                                                d)
                                            .clamp(kTextMinWidth, most)
                                            .toDouble(),
                                    onEnd: () => _rememberTextSize(s),
                                  ),
                                  SizedBox(
                                    width: s.textWidth.value
                                        .clamp(kTextMinWidth, most),
                                    child: _textPanel(s),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    PartBar(session: s, phone: false, entry: _partEntry),
                    timeline,
                  ],
                );
              }
              return Column(
                children: [
                  notSaved,
                  Expanded(child: preview),
                  // While something is selected the tool bar shows that
                  // item's tools; adding stays within reach here.
                  TransportBar(
                      session: s, onAdd: () => showAddSheet(context, s)),
                  timeline,
                  // A selected part: start, end, length, nudge, Actions.
                  PartBar(session: s, phone: true, entry: _partEntry),
                  // Suggestions: one thin line just above the tool bar,
                  // which a swipe sends away.
                  if (suggestions != null)
                    SuggestionBar(controller: suggestions, phone: true),
                  ToolBar(session: s),
                ],
              );
            },
          ),
        ),
    );
  }

  /// An action of the part bar, from the one registry.
  ActionEntry _partEntry(BuildContext context, Act a) =>
      EditorActions(_session!).entry(this.context, a);

  Widget _textPanel(EditorSession s) => TextPanel(
        key: const ValueKey('text-window'),
        session: s,
        onClose: () => s.showText.value = false,
        onDock: (dock) => _setTextDock(s, dock),
      );

  /// Phones: the "⋯" project menu of the top bar.
  Widget _projectMenu(EditorSession s) {
    final actions = EditorActions(s);
    const items = <(Act, String)>[
      (Act.shapeAndSize, 'Shape and size'),
      (Act.fades, 'Fade in and out'),
      (Act.selectPart, 'Select part'),
      (Act.publishingNotes, 'Publishing notes'),
      (Act.textWindow, 'Text'),
      (Act.history, 'History'),
      (Act.goodMoments, 'Markers'),
      (Act.settings, 'Settings'),
    ];
    return PopupMenuButton<Object>(
      key: const ValueKey('project-menu'),
      tooltip: 'Project menu',
      icon: const Icon(Icons.more_horiz, semanticLabel: 'Project menu'),
      onSelected: (v) {
        // The menu closes first, then the sheet or page opens.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (v is Act) {
            actions.run(context, v);
          } else if (v == 'feedback') {
            s.playback.pause();
            openFeedback(context);
          } else {
            s.playback.pause();
            openHelp(context);
          }
        });
      },
      itemBuilder: (context) => [
        for (final (act, label) in items)
          PopupMenuItem<Object>(
            key: ValueKey('project-menu-${act.name}'),
            value: act,
            enabled: actions.whyNot(act) == null,
            height: 48,
            child: Row(
              children: [
                Icon(actIcon(act), size: 20, color: AppColors.textDim),
                const SizedBox(width: 14),
                Text(label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          key: ValueKey('project-menu-help'),
          value: 'help',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.help_outline, size: 20, color: AppColors.textDim),
              SizedBox(width: 14),
              Text('Help'),
            ],
          ),
        ),
        const PopupMenuItem<Object>(
          key: ValueKey('project-menu-feedback'),
          value: 'feedback',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.textDim),
              SizedBox(width: 14),
              Text('Send feedback'),
            ],
          ),
        ),
      ],
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
                icon: const Icon(Icons.undo, semanticLabel: 'Undo'),
                onPressed: s.editor.canUndo ? s.editor.undo : null,
              ),
              IconButton(
                tooltip: 'Redo',
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
                    onPressed: () => toggleHistory(context, s),
                  ),
                ),
              if (!narrow)
                ValueListenableBuilder<bool>(
                  valueListenable: s.showText,
                  builder: (context, shown, _) => IconButton(
                    key: const ValueKey('text-button'),
                    tooltip: shown
                        ? 'Hide the Text window'
                        : 'Text: read and search what is said',
                    isSelected: shown,
                    icon: const Icon(Icons.subject, semanticLabel: 'Text'),
                    onPressed: () => toggleTextWindow(context, s),
                  ),
                ),
              if (!narrow)
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
              if (narrow)
                // Phones: ONE project menu (shape and size, fades, notes,
                // Text, History, markers, Settings, Help).
                TourAnchor(id: TourIds.shape, child: _projectMenu(s))
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: 'Help',
                    visualDensity: VisualDensity.compact,
                    icon:
                        const Icon(Icons.help_outline, semanticLabel: 'Help'),
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

/// The edge of the Text window that is dragged to resize it.
class _SizeHandle extends StatelessWidget {
  const _SizeHandle({
    super.key,
    required this.vertical,
    required this.onDrag,
    required this.onEnd,
  });

  /// True: a bar across, dragged up and down.
  final bool vertical;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: vertical ? (d) => onDrag(d.delta.dy) : null,
        onVerticalDragEnd: vertical ? (_) => onEnd() : null,
        onHorizontalDragUpdate: vertical ? null : (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: vertical ? null : (_) => onEnd(),
        child: SizedBox(
          width: vertical ? double.infinity : 7,
          height: vertical ? 7 : double.infinity,
          child: Center(
            child: Container(
              width: vertical ? double.infinity : 1,
              height: vertical ? 1 : double.infinity,
              color: AppColors.outline,
            ),
          ),
        ),
      ),
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
String aspectMenuLabel(CanvasAspect aspect) => shapeMenuLabel(aspect);

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

  /// Phones: opens the Add sheet. Shown only while something is selected
  /// (with nothing selected the tool bar itself starts with Add).
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
                    tooltip: 'Go to start',
                    icon: const Icon(Icons.skip_previous, semanticLabel: 'Go to start'),
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
            // Where speech starts (when the sound pictures show any, and
            // there is room: phones have these under More).
            if (MediaQuery.sizeOf(context).width >= 520)
              ListenableBuilder(
                listenable: session.pictures,
                builder: (context, _) => session.pictures.speakers
                        .any((t) => t.stretches.isNotEmpty)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const ValueKey('previous-speech'),
                            tooltip: 'Previous speech start (Ctrl+Left)',
                            icon: const Icon(Icons.keyboard_double_arrow_left,
                                semanticLabel: 'Previous speech start'),
                            onPressed: () =>
                                session.goToSpeechStart(forward: false),
                          ),
                          IconButton(
                            key: const ValueKey('next-speech'),
                            tooltip: 'Next speech start (Ctrl+Right)',
                            icon: const Icon(Icons.keyboard_double_arrow_right,
                                semanticLabel: 'Next speech start'),
                            onPressed: () =>
                                session.goToSpeechStart(forward: true),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            if (onAdd != null)
              ValueListenableBuilder<Selection?>(
                valueListenable: session.selection,
                builder: (context, selected, _) => selected == null
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('transport-add'),
                        tooltip: 'Add',
                        icon: const Icon(Icons.add_circle_outline,
                            semanticLabel: 'Add'),
                        onPressed: onAdd,
                      ),
              ),
            ValueListenableBuilder<double>(
              valueListenable: session.zoom,
              builder: (context, zoom, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    icon: const Icon(Icons.zoom_out, semanticLabel: 'Zoom out'),
                    onPressed: zoom > EditorSession.minZoom
                        ? () => session.setZoom(session.zoom.value / 1.5)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    icon: const Icon(Icons.zoom_in, semanticLabel: 'Zoom in'),
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
