import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/model/project.dart';
import 'theme.dart';

/// What the menu bar can do in the open editor, and whether it can now.
@immutable
class EditorMenuActions {
  const EditorMenuActions({
    required this.canUndo,
    required this.canRedo,
    required this.canDelete,
    required this.canPlay,
    required this.playing,
    required this.undo,
    required this.redo,
    required this.delete,
    required this.togglePlay,
    this.canExport = false,
    this.export,
    this.backToProjects,
    this.showHistory,
    this.canCrop = false,
    this.cropAndPosition,
    this.rotateRight,
    this.canAddOverlay = false,
    this.addOverlay,
    this.extra = const EditorMenuExtra(),
  });

  /// The items added in 1.7.
  final EditorMenuExtra extra;

  final bool canUndo;
  final bool canRedo;

  /// Something is selected on the timeline.
  final bool canDelete;

  /// The project has something to play.
  final bool canPlay;
  final bool playing;
  final VoidCallback undo;
  final VoidCallback redo;
  final VoidCallback delete;
  final VoidCallback togglePlay;

  /// The project has something to export.
  final bool canExport;

  /// Opens the export dialog (File > Export…).
  final VoidCallback? export;

  /// Saves and goes back to the project list (File > Back to projects).
  final VoidCallback? backToProjects;

  /// Shows or hides the list of changes (Edit > History).
  final VoidCallback? showHistory;

  /// A clip or an overlay item is selected: its picture can be cropped and
  /// turned.
  final bool canCrop;

  /// Opens "Crop and position" of the selection (Edit > Crop and
  /// position…).
  final VoidCallback? cropAndPosition;

  /// Turns the selected picture a quarter turn clockwise (Edit > Rotate
  /// right).
  final VoidCallback? rotateRight;

  /// The project has something to put an overlay over.
  final bool canAddOverlay;

  /// Picks videos or photos for the overlay track (Edit > Add overlay
  /// video or photo…).
  final VoidCallback? addOverlay;
}

/// The editor's menu items added in 1.7. Each action is null while it
/// cannot be done now (the item is then greyed out).
@immutable
class EditorMenuExtra {
  const EditorMenuExtra({
    this.addMedia,
    this.addMusic,
    this.addTitle,
    this.addCaption,
    this.importSubtitles,
    this.exportSubtitles,
    this.renameProject,
    this.split,
    this.freezeFrame,
    this.removeSilences,
    this.moveEarlier,
    this.moveLater,
    this.startAtPlayhead,
    this.endAtPlayhead,
    this.duplicate,
    this.copySettings,
    this.pasteSettings,
    this.separateSound,
    this.putSoundBack,
    this.addSoundTrack,
    this.addVoice,
    this.lineUpVoice,
    this.fitMusic,
    this.copyCredits,
    this.lowerMusic,
    this.lowerMusicOn = false,
    this.shape,
    this.currentShape,
    this.videoSize,
    this.currentVideoSize,
    this.goToStart,
    this.goToEnd,
    this.playBackwards,
    this.pause,
    this.playForwards,
    this.previousFrame,
    this.nextFrame,
    this.zoomIn,
    this.zoomOut,
    this.toggleSnapping,
    this.snapping = true,
    this.showShortcuts,
    this.speech,
    this.showText,
    this.textShown = false,
    this.findInText,
    this.toggleWaves,
    this.wavesOn = true,
    this.previousSpeech,
    this.nextSpeech,
    this.publishingNotes,
    this.exportSeveral,
    this.markMoment,
    this.goodMoments,
    this.shortFromHere,
    this.shortsFromMarkers,
  });

  /// 1.14: File > "Publishing notes…" and "Export several…"; Edit >
  /// Shorts: "Mark a good moment" (M), "Good moments…", "Make a short
  /// from here…", "Make shorts from markers…".
  final VoidCallback? publishingNotes;
  final VoidCallback? exportSeveral;
  final VoidCallback? markMoment;
  final VoidCallback? goodMoments;
  final VoidCallback? shortFromHere;
  final VoidCallback? shortsFromMarkers;

  /// Edit > "Text window" (1.13) and "Find in the text…".
  final VoidCallback? showText;
  final bool textShown;
  final VoidCallback? findInText;

  /// Playback > "Show sound waves" and "Previous / Next speech start".
  final VoidCallback? toggleWaves;
  final bool wavesOn;
  final VoidCallback? previousSpeech;
  final VoidCallback? nextSpeech;

  /// Edit > Speech (1.11, computers only): null where speech-to-text does
  /// not exist (phones), and then the menu is not there at all.
  final SpeechMenu? speech;

  final VoidCallback? addMedia;
  final VoidCallback? addMusic;
  final VoidCallback? addTitle;
  final VoidCallback? addCaption;
  final VoidCallback? importSubtitles;
  final VoidCallback? exportSubtitles;
  final VoidCallback? renameProject;
  final VoidCallback? split;
  final VoidCallback? freezeFrame;
  final VoidCallback? removeSilences;
  final VoidCallback? moveEarlier;
  final VoidCallback? moveLater;
  final VoidCallback? startAtPlayhead;
  final VoidCallback? endAtPlayhead;
  final VoidCallback? duplicate;
  final VoidCallback? copySettings;
  final VoidCallback? pasteSettings;
  final VoidCallback? separateSound;
  final VoidCallback? putSoundBack;
  final VoidCallback? addSoundTrack;

  /// Edit > Sound > "Add voice recording…" and "Line up with the video"
  /// (the selected sound; 1.10).
  final VoidCallback? addVoice;
  final VoidCallback? lineUpVoice;

  /// "Fit music to video" for the selected music.
  final VoidCallback? fitMusic;

  /// "Copy music credits" (music from the free music search).
  final VoidCallback? copyCredits;
  final VoidCallback? lowerMusic;
  final bool lowerMusicOn;
  final ValueChanged<CanvasAspect>? shape;
  final CanvasAspect? currentShape;
  final ValueChanged<VideoSize>? videoSize;
  final VideoSize? currentVideoSize;
  final VoidCallback? goToStart;
  final VoidCallback? goToEnd;
  final VoidCallback? playBackwards;
  final VoidCallback? pause;
  final VoidCallback? playForwards;
  final VoidCallback? previousFrame;
  final VoidCallback? nextFrame;
  final VoidCallback? zoomIn;
  final VoidCallback? zoomOut;
  final VoidCallback? toggleSnapping;
  final bool snapping;
  final VoidCallback? showShortcuts;

  /// What the menus show (which items are on, ticks), to tell whether
  /// they need building again.
  List<Object?> get state => [
        for (final a in [
          addMedia, addMusic, addTitle, addCaption, importSubtitles, //
          exportSubtitles, renameProject, split, freezeFrame,
          removeSilences, moveEarlier, moveLater, startAtPlayhead,
          endAtPlayhead, duplicate, copySettings, pasteSettings,
          separateSound, putSoundBack, addSoundTrack, lowerMusic,
          addVoice, lineUpVoice,
          fitMusic, copyCredits,
          goToStart, goToEnd, playBackwards, pause, playForwards,
          previousFrame, nextFrame, zoomIn, zoomOut, toggleSnapping,
          showShortcuts, shape, videoSize,
          showText, findInText, toggleWaves, previousSpeech, nextSpeech,
          publishingNotes, exportSeveral, markMoment, goodMoments,
          shortFromHere, shortsFromMarkers,
        ])
          a != null,
        lowerMusicOn,
        currentShape,
        currentVideoSize,
        snapping,
        textShown,
        wavesOn,
        speech != null,
        speech?.transcribe != null,
        speech?.captions != null,
        speech?.fillers != null,
        speech?.autoCuts != null,
      ];
}

/// The Edit > Speech items. A null action is greyed out.
@immutable
class SpeechMenu {
  const SpeechMenu({
    this.transcribe,
    this.captions,
    this.fillers,
    this.autoCuts,
  });

  /// "Automatic cuts…": what was cut automatically, with Put back.
  final VoidCallback? autoCuts;
  final VoidCallback? transcribe;
  final VoidCallback? captions;
  final VoidCallback? fillers;
}

/// "Original (as the first clip)", "9:16 upright", ...
String menuShapeLabel(CanvasAspect a) => switch (a) {
      CanvasAspect.original => 'Original (as the first clip)',
      CanvasAspect.portrait9x16 => '9:16 upright',
      CanvasAspect.landscape16x9 => '16:9 wide',
      CanvasAspect.square1x1 => '1:1 square',
      CanvasAspect.portrait4x5 => '4:5 upright',
    };

/// "Match first clip", "720p", ...
String menuVideoSizeLabel(VideoSize v) => switch (v) {
      VideoSize.matchFirstClip => 'Same as the first clip',
      VideoSize.p720 => '720p',
      VideoSize.p1080 => '1080p (Full HD)',
      VideoSize.p2160 => '4K',
    };

/// What the File menu can do on the project list.
@immutable
class HomeMenuActions {
  const HomeMenuActions(
      {required this.newProject, required this.openProjectFile});
  final VoidCallback newProject;
  final VoidCallback openProjectFile;
}

/// Connects the open editor to the app's menu bar (macOS).
class AppMenuController extends ChangeNotifier {
  bool _notifyPending = false;

  /// Tells the menu bars. Screens attach in initState and detach in
  /// dispose, i.e. while the widget tree is being built or torn down, when
  /// the menu bar must not rebuild: the news then goes out after the frame.
  void _changed() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyPending) return;
    _notifyPending = true;
    scheduler.addPostFrameCallback((_) {
      _notifyPending = false;
      notifyListeners();
    }, debugLabel: 'AppMenuController');
  }
  Object? _owner;
  EditorMenuActions? _editor;
  Object? _homeOwner;
  HomeMenuActions? _home;

  /// The actions of the open editor; null on the project list.
  EditorMenuActions? get editor => _editor;

  /// The actions of the project list (New project, Open project file);
  /// they are offered only while no editor is open.
  HomeMenuActions? get home => _home;

  /// Called by the project list when it is shown.
  void attachHome(Object owner, HomeMenuActions actions) {
    _homeOwner = owner;
    _home = actions;
    _changed();
  }

  /// Called by the project list when it goes away.
  void detachHome(Object owner) {
    if (!identical(_homeOwner, owner)) return;
    _homeOwner = null;
    _home = null;
    _changed();
  }

  /// Called by the editor whenever what it can do changes.
  void attach(Object owner, EditorMenuActions actions) {
    final before = _editor;
    final same = identical(_owner, owner) &&
        before != null &&
        before.canUndo == actions.canUndo &&
        before.canRedo == actions.canRedo &&
        before.canDelete == actions.canDelete &&
        before.canPlay == actions.canPlay &&
        before.playing == actions.playing &&
        before.canExport == actions.canExport &&
        before.canCrop == actions.canCrop &&
        before.canAddOverlay == actions.canAddOverlay &&
        listEquals(before.extra.state, actions.extra.state);
    _owner = owner;
    _editor = actions;
    // The editor reports after every edit and playback change; the menu
    // bars only need to hear when what they show changes.
    if (!same) _changed();
  }

  /// Called by the editor when it closes. Ignored when another editor has
  /// attached since.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _editor = null;
    _changed();
  }
}

/// What the Help menu does.
@immutable
class HelpMenuActions {
  const HelpMenuActions({
    required this.openHelp,
    required this.showTour,
    this.showAbout,
    this.copyVersionInfo,
    this.checkForUpdates,
    this.autoUpdateCheck = true,
    this.toggleAutoUpdateCheck,
    this.connectClaude,
  });
  final VoidCallback openHelp;
  final VoidCallback showTour;

  /// Opens About ClipForge (version, build, date; lib/ui/about.dart).
  final VoidCallback? showAbout;

  /// Copies the version and device details for a bug report.
  final VoidCallback? copyVersionInfo;

  /// Asks now whether a newer version exists (lib/ui/update).
  final VoidCallback? checkForUpdates;

  /// Whether the app checks for updates by itself (once a day), and the
  /// switch for it.
  final bool autoUpdateCheck;
  final VoidCallback? toggleAutoUpdateCheck;

  /// Opens "Connect to Claude" (computers only; null on phones).
  final VoidCallback? connectClaude;
}

/// The one [AppMenuController] of the app.
final AppMenuController appMenu = AppMenuController();

/// Whether the app shows its own menu bar: macOS only (Windows and Linux
/// windows have none, phones neither).
bool get usesPlatformMenuBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// The menus of the macOS menu bar. Disabled items have no [onSelected].
///
/// Items carry their shortcuts (Undo, Delete = Backspace, Play = Space, the
/// single-letter editing keys, ...). They are not fired twice with the
/// editor's own key handling: the key goes to the app first, and a key the
/// app handles (the editor's shortcuts, or a text field's own typing and
/// Undo) is not passed on to the menu; the editor handles every one of
/// them itself, so they also work the same way without the menu.
List<PlatformMenuItem> buildAppMenus(EditorMenuActions? editor,
    {HelpMenuActions? help, HomeMenuActions? home}) {
  final e = editor;
  final x = e?.extra;
  final h = e == null ? home : null;
  return [
    PlatformMenu(
      label: 'ClipForge',
      menus: [
        // The app's own About box instead of the system's: it shows the
        // build number, build time and commit too (lib/ui/about.dart).
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
              label: 'About ClipForge', onSelected: help?.showAbout),
        ]),
        if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.servicesSubmenu))
          const PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu),
          ]),
        const PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications),
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications),
        ]),
        // Asks the app first, like closing the window: see the editor.
        const PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ]),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'New project',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
            onSelected: h?.newProject,
          ),
          PlatformMenuItem(
            label: 'Open project file…',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
            onSelected: h?.openProjectFile,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(label: 'Add media…', onSelected: x?.addMedia),
          PlatformMenuItem(label: 'Add music…', onSelected: x?.addMusic),
          PlatformMenuItem(
              label: 'Import subtitles (.srt)…',
              onSelected: x?.importSubtitles),
          PlatformMenuItem(
              label: 'Export subtitles (.srt)…',
              onSelected: x?.exportSubtitles),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
              label: 'Rename project…', onSelected: x?.renameProject),
          PlatformMenuItem(
              label: 'Publishing notes…', onSelected: x?.publishingNotes),
          PlatformMenuItem(
            label: 'Back to projects',
            onSelected: e?.backToProjects,
          ),
          PlatformMenuItem(
            label: 'Export…',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
            onSelected: e != null && e.canExport ? e.export : null,
          ),
          PlatformMenuItem(
              label: 'Export several…', onSelected: x?.exportSeveral),
        ]),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: [
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Undo',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
            onSelected: e != null && e.canUndo ? e.undo : null,
          ),
          PlatformMenuItem(
            label: 'Redo',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true, shift: true),
            onSelected: e != null && e.canRedo ? e.redo : null,
          ),
          PlatformMenuItem(
            label: 'History',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyH,
                meta: true, shift: true),
            onSelected: e?.showHistory,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenu(label: 'Shorts', menus: [
            PlatformMenuItem(
                label: 'Mark a good moment',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyM),
                onSelected: x?.markMoment),
            PlatformMenuItem(
                label: 'Good moments…', onSelected: x?.goodMoments),
            PlatformMenuItem(
                label: 'Make a short from here…',
                onSelected: x?.shortFromHere),
            PlatformMenuItem(
                label: 'Make shorts from markers…',
                onSelected: x?.shortsFromMarkers),
          ]),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: x != null && x.textShown ? 'Text window ✓' : 'Text window',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyT,
                meta: true, shift: true),
            onSelected: x?.showText,
          ),
          PlatformMenuItem(
            label: 'Find in the text…',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
            onSelected: x?.findInText,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Duplicate',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
            onSelected: x?.duplicate,
          ),
          PlatformMenuItem(
            label: 'Copy settings',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                meta: true, shift: true),
            onSelected: x?.copySettings,
          ),
          PlatformMenuItem(
            label: 'Paste settings',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyV,
                meta: true, shift: true),
            onSelected: x?.pasteSettings,
          ),
          PlatformMenuItem(
            label: 'Delete',
            shortcut: const SingleActivator(LogicalKeyboardKey.backspace),
            onSelected: e != null && e.canDelete ? e.delete : null,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Split at playhead',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyS),
            onSelected: x?.split,
          ),
          PlatformMenuItem(
            label: 'Start clip at playhead',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyI),
            onSelected: x?.startAtPlayhead,
          ),
          PlatformMenuItem(
            label: 'End clip at playhead',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyO),
            onSelected: x?.endAtPlayhead,
          ),
          PlatformMenuItem(label: 'Freeze frame', onSelected: x?.freezeFrame),
          PlatformMenuItem(
              label: 'Remove silences…', onSelected: x?.removeSilences),
          PlatformMenuItem(label: 'Move clip earlier', onSelected: x?.moveEarlier),
          PlatformMenuItem(label: 'Move clip later', onSelected: x?.moveLater),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Crop and position…',
            onSelected: e != null && e.canCrop ? e.cropAndPosition : null,
          ),
          PlatformMenuItem(
            label: 'Rotate right',
            onSelected: e != null && e.canCrop ? e.rotateRight : null,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(label: 'Add title', onSelected: x?.addTitle),
          PlatformMenuItem(label: 'Add caption…', onSelected: x?.addCaption),
          PlatformMenuItem(
            label: 'Add overlay video or photo…',
            onSelected: e != null && e.canAddOverlay ? e.addOverlay : null,
          ),
        ]),
        PlatformMenu(label: 'Sound', menus: [
          PlatformMenuItem(label: 'Add voice recording…', onSelected: x?.addVoice),
          PlatformMenuItem(label: 'Line up with the video', onSelected: x?.lineUpVoice),
          PlatformMenuItem(label: 'Add sound track', onSelected: x?.addSoundTrack),
          PlatformMenuItem(label: 'Separate sound…', onSelected: x?.separateSound),
          PlatformMenuItem(label: 'Put sound back', onSelected: x?.putSoundBack),
          PlatformMenuItem(label: 'Fit music to video', onSelected: x?.fitMusic),
          PlatformMenuItem(label: 'Copy music credits', onSelected: x?.copyCredits),
          PlatformMenuItem(
              label: x != null && x.lowerMusicOn
                  ? 'Lower music under speech ✓'
                  : 'Lower music under speech',
              onSelected: x?.lowerMusic),
        ]),
        if (x?.speech != null)
          PlatformMenu(label: 'Speech', menus: [
            PlatformMenuItem(
                label: 'Transcribe speech…', onSelected: x!.speech!.transcribe),
            PlatformMenuItem(
                label: 'Captions from speech…', onSelected: x.speech!.captions),
            PlatformMenuItem(
                label: 'Remove filler words…', onSelected: x.speech!.fillers),
            PlatformMenuItem(
                label: 'Automatic cuts…', onSelected: x.speech!.autoCuts),
          ]),
        PlatformMenu(label: 'Shape', menus: [
          for (final a in CanvasAspect.values)
            PlatformMenuItem(
              label: '${menuShapeLabel(a)}${x?.currentShape == a ? ' ✓' : ''}',
              onSelected: x?.shape == null ? null : () => x!.shape!(a),
            ),
        ]),
        PlatformMenu(label: 'Video size', menus: [
          for (final v in VideoSize.values)
            PlatformMenuItem(
              label:
                  '${menuVideoSizeLabel(v)}${x?.currentVideoSize == v ? ' ✓' : ''}',
              onSelected: x?.videoSize == null ? null : () => x!.videoSize!(v),
            ),
        ]),
      ],
    ),
    PlatformMenu(
      label: 'Playback',
      menus: [
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: e != null && e.playing ? 'Pause' : 'Play',
            shortcut: const SingleActivator(LogicalKeyboardKey.space),
            onSelected: e != null && e.canPlay ? e.togglePlay : null,
          ),
          PlatformMenuItem(
            label: 'Play backwards',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyJ),
            onSelected: x?.playBackwards,
          ),
          PlatformMenuItem(
            label: 'Stop',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyK),
            onSelected: x?.pause,
          ),
          PlatformMenuItem(
            label: 'Play forwards',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyL),
            onSelected: x?.playForwards,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Go to start',
            shortcut: const SingleActivator(LogicalKeyboardKey.home),
            onSelected: x?.goToStart,
          ),
          PlatformMenuItem(
            label: 'Go to end',
            shortcut: const SingleActivator(LogicalKeyboardKey.end),
            onSelected: x?.goToEnd,
          ),
          PlatformMenuItem(
            label: 'Previous frame',
            shortcut: const SingleActivator(LogicalKeyboardKey.arrowLeft),
            onSelected: x?.previousFrame,
          ),
          PlatformMenuItem(
            label: 'Next frame',
            shortcut: const SingleActivator(LogicalKeyboardKey.arrowRight),
            onSelected: x?.nextFrame,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
            label: 'Zoom in timeline',
            shortcut: const SingleActivator(LogicalKeyboardKey.equal),
            onSelected: x?.zoomIn,
          ),
          PlatformMenuItem(
            label: 'Zoom out timeline',
            shortcut: const SingleActivator(LogicalKeyboardKey.minus),
            onSelected: x?.zoomOut,
          ),
          PlatformMenuItem(
            label: x == null || x.snapping
                ? 'Snap to playhead and edges ✓'
                : 'Snap to playhead and edges',
            onSelected: x?.toggleSnapping,
          ),
        ]),
        PlatformMenuItemGroup(members: [
          // Cmd+Left / Right (the editor's own key handling does them, so
          // that they keep their meaning in a text box).
          PlatformMenuItem(
            label: 'Previous speech start',
            onSelected: x?.previousSpeech,
          ),
          PlatformMenuItem(
            label: 'Next speech start',
            onSelected: x?.nextSpeech,
          ),
          PlatformMenuItem(
            label: x == null || x.wavesOn
                ? 'Show sound waves ✓'
                : 'Show sound waves',
            onSelected: x?.toggleWaves,
          ),
        ]),
      ],
    ),
    const PlatformMenu(
      label: 'Window',
      menus: [
        PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen),
        ]),
      ],
    ),
    PlatformMenu(
      label: 'Help',
      menus: [
        PlatformMenuItem(
          label: 'ClipForge Help',
          shortcut: const SingleActivator(LogicalKeyboardKey.slash,
              meta: true, shift: true),
          onSelected: help?.openHelp,
        ),
        PlatformMenuItem(
            label: 'Keyboard shortcuts', onSelected: x?.showShortcuts),
        PlatformMenuItem(label: 'Show the tour', onSelected: help?.showTour),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
              label: 'Connect to Claude…', onSelected: help?.connectClaude),
        ]),
        PlatformMenuItemGroup(members: [
          PlatformMenuItem(
              label: 'Check for updates…', onSelected: help?.checkForUpdates),
          PlatformMenuItem(
              label: (help?.autoUpdateCheck ?? true)
                  ? 'Check for updates automatically ✓'
                  : 'Check for updates automatically',
              onSelected: help?.toggleAutoUpdateCheck),
        ]),
        PlatformMenuItem(
            label: 'Copy version info', onSelected: help?.copyVersionInfo),
      ],
    ),
  ];
}

/// Puts the app's menus in the macOS menu bar (in place of the default
/// ones, whose Edit menu could not reach the app), or, on Windows and
/// Linux, in a menu bar along the top of the window ([WindowMenuBar]).
/// Phones: just [child].
class AppMenuBar extends StatelessWidget {
  const AppMenuBar(
      {super.key, required this.child, this.controller, this.help});
  final Widget child;

  /// What the Help menu does.
  final HelpMenuActions? help;

  /// Defaults to [appMenu].
  final AppMenuController? controller;

  @override
  Widget build(BuildContext context) {
    final c = controller ?? appMenu;
    if (usesWindowMenuBar) {
      return WindowMenuBar(controller: c, help: help, child: child);
    }
    if (!usesPlatformMenuBar) return child;
    return ListenableBuilder(
      listenable: c,
      builder: (context, child) => PlatformMenuBar(
          menus: buildAppMenus(c.editor, help: help, home: c.home),
          child: child!),
      child: child,
    );
  }
}

/// Whether the app draws its own menu bar inside the window: Windows and
/// Linux (their windows have no menu bar of their own).
bool get usesWindowMenuBar =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Asks the app to quit, like closing the window: the open editor saves
/// and asks first when something would be lost (see the editor's exit
/// handling).
Future<void> requestAppQuit() async {
  await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
}

/// The keys of the in-window menu bar that nothing else handles: they are
/// handled here, once. Every other shortcut the menus show (Undo, Redo,
/// Delete, Space, Ctrl+D, Ctrl+Shift+C / V, S, I, O, J, K, L, + / -, the
/// arrows, Home / End) is only SHOWN in the menu: the editor's own key
/// handling does them (and a text field's own typing and Undo go first),
/// so they never run twice.
Map<ShortcutActivator, VoidCallback> windowMenuShortcuts(
    AppMenuController c, HelpMenuActions? help) {
  final e = c.editor;
  final h = e == null ? c.home : null;
  return {
    if (h != null) ...{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          h.newProject,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true):
          h.openProjectFile,
    },
    if (e != null && e.canExport && e.export != null)
      const SingleActivator(LogicalKeyboardKey.keyE, control: true): e.export!,
    if (e != null && e.showHistory != null)
      const SingleActivator(LogicalKeyboardKey.keyH,
          control: true, shift: true): e.showHistory!,
    if (e != null && e.extra.showText != null)
      const SingleActivator(LogicalKeyboardKey.keyT,
          control: true, shift: true): e.extra.showText!,
    if (help != null) const SingleActivator(LogicalKeyboardKey.f1): help.openHelp,
    if (defaultTargetPlatform == TargetPlatform.linux)
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
        requestAppQuit();
      },
  };
}

/// The menu bar along the top of the window on Windows and Linux: the same
/// menus and actions as the macOS menu bar (File, Edit, Playback, Help),
/// compact and in the app's dark colours. Sits above the app's navigator,
/// so it needs its own [Overlay] for the menus that drop down.
class WindowMenuBar extends StatefulWidget {
  const WindowMenuBar(
      {super.key, required this.controller, required this.child, this.help});
  final AppMenuController controller;
  final HelpMenuActions? help;
  final Widget child;

  /// Height of the bar.
  static const double height = 30;

  @override
  State<WindowMenuBar> createState() => _WindowMenuBarState();
}

class _WindowMenuBarState extends State<WindowMenuBar> {
  /// Menus open now, and what had the keyboard before the first opened.
  int _open = 0;
  FocusNode? _focusBefore;

  void _opened() {
    if (_open++ == 0) _focusBefore = FocusManager.instance.primaryFocus;
  }

  /// When the last menu closes, the keyboard goes back to where it was
  /// (the editor), so that Space, the arrows and Ctrl+Z keep working after
  /// a menu was used.
  void _closed() {
    if (_open > 0) _open--;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_open > 0) return;
      final before = _focusBefore;
      _focusBefore = null;
      if (before != null && before.context != null && before.canRequestFocus) {
        before.requestFocus();
      }
    });
  }

  AppMenuController get controller => widget.controller;
  HelpMenuActions? get help => widget.help;
  static const double height = WindowMenuBar.height;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) => CallbackShortcuts(
          bindings: windowMenuShortcuts(controller, help),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(context),
              Expanded(child: child!),
            ],
          ),
        ),
        child: widget.child,
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final e = controller.editor;
    final x = e?.extra;
    final h = e == null ? controller.home : null;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    const itemText = TextStyle(fontSize: 13);
    final itemStyle = MenuItemButton.styleFrom(
      minimumSize: const Size(200, 32),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: itemText,
      visualDensity: VisualDensity.compact,
    );
    Widget item(String label,
            {VoidCallback? onPressed,
            MenuSerializableShortcut? shortcut,
            Key? key}) =>
        MenuItemButton(
          key: key,
          style: itemStyle,
          shortcut: shortcut,
          onPressed: onPressed,
          child: Text(label),
        );
    Widget menu(String label, List<Widget> items) => SubmenuButton(
          onOpen: _opened,
          onClose: _closed,
          style: SubmenuButton.styleFrom(
            minimumSize: const Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: itemText,
            visualDensity: VisualDensity.compact,
          ),
          menuStyle: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.panelHigh),
            padding:
                WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              side: BorderSide(color: AppColors.outline),
            )),
          ),
          menuChildren: items,
          child: Text(label),
        );
    Widget check(String label,
            {required bool value,
            VoidCallback? onPressed,
            MenuSerializableShortcut? shortcut,
            Key? key}) =>
        MenuItemButton(
          key: key,
          style: itemStyle,
          shortcut: shortcut,
          onPressed: onPressed,
          leadingIcon: SizedBox(
            width: 18,
            child: value ? const Icon(Icons.check, size: 16) : null,
          ),
          child: Text(label),
        );
    Widget submenu(String label, List<Widget> items) => SubmenuButton(
          style: SubmenuButton.styleFrom(
            minimumSize: const Size(200, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: itemText,
            visualDensity: VisualDensity.compact,
          ),
          menuStyle: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.panelHigh),
            padding:
                WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
          ),
          menuChildren: items,
          child: Text(label),
        );
    const divider = Divider(height: 9, indent: 8, endIndent: 8);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: MenuBar(
                style: const MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(AppColors.panel),
                  elevation: WidgetStatePropertyAll(0),
                  padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4)),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
                ),
                children: [
                  menu('File', [
                    item('New project',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyN,
                            control: true),
                        onPressed: h?.newProject),
                    item('Open project file…',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyO,
                            control: true),
                        onPressed: h?.openProjectFile),
                    divider,
                    item('Add media…',
                        key: const ValueKey('menu-add-media'),
                        onPressed: x?.addMedia),
                    item('Add music…', onPressed: x?.addMusic),
                    item('Import subtitles (.srt)…',
                        onPressed: x?.importSubtitles),
                    item('Export subtitles (.srt)…',
                        onPressed: x?.exportSubtitles),
                    divider,
                    item('Rename project…', onPressed: x?.renameProject),
                    item('Publishing notes…',
                        key: const ValueKey('menu-publishing-notes'),
                        onPressed: x?.publishingNotes),
                    item('Back to projects', onPressed: e?.backToProjects),
                    item('Export…',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyE,
                            control: true),
                        onPressed: e != null && e.canExport ? e.export : null),
                    item('Export several…',
                        key: const ValueKey('menu-export-several'),
                        onPressed: x?.exportSeveral),
                    divider,
                    item(windows ? 'Exit' : 'Quit',
                        shortcut: windows
                            ? const SingleActivator(LogicalKeyboardKey.f4,
                                alt: true)
                            : const SingleActivator(LogicalKeyboardKey.keyQ,
                                control: true),
                        onPressed: requestAppQuit),
                  ]),
                  menu('Edit', [
                    item('Undo',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                            control: true),
                        onPressed: e != null && e.canUndo ? e.undo : null),
                    // Ctrl+Y works too (Help > Keyboard shortcuts says so);
                    // the menu shows the same keys as on a Mac.
                    item('Redo',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                            control: true, shift: true),
                        onPressed: e != null && e.canRedo ? e.redo : null),
                    item('History',
                        key: const ValueKey('menu-history'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyH,
                            control: true, shift: true),
                        onPressed: e?.showHistory),
                    divider,
                    check('Text window',
                        key: const ValueKey('menu-text'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyT,
                            control: true, shift: true),
                        value: x?.textShown ?? false,
                        onPressed: x?.showText),
                    item('Find in the text…',
                        key: const ValueKey('menu-find-text'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyF,
                            control: true),
                        onPressed: x?.findInText),
                    divider,
                    item('Duplicate',
                        key: const ValueKey('menu-duplicate'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyD,
                            control: true),
                        onPressed: x?.duplicate),
                    item('Copy settings',
                        key: const ValueKey('menu-copy-settings'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                            control: true, shift: true),
                        onPressed: x?.copySettings),
                    item('Paste settings',
                        key: const ValueKey('menu-paste-settings'),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyV,
                            control: true, shift: true),
                        onPressed: x?.pasteSettings),
                    item('Delete (or Backspace)',
                        shortcut:
                            const SingleActivator(LogicalKeyboardKey.delete),
                        onPressed: e != null && e.canDelete ? e.delete : null),
                    divider,
                    item('Split at playhead',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyS),
                        onPressed: x?.split),
                    item('Start clip at playhead',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyI),
                        onPressed: x?.startAtPlayhead),
                    item('End clip at playhead',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyO),
                        onPressed: x?.endAtPlayhead),
                    item('Freeze frame', onPressed: x?.freezeFrame),
                    item('Remove silences…', onPressed: x?.removeSilences),
                    item('Move clip earlier', onPressed: x?.moveEarlier),
                    item('Move clip later', onPressed: x?.moveLater),
                    divider,
                    item('Crop and position…',
                        key: const ValueKey('menu-crop'),
                        onPressed: e != null && e.canCrop
                            ? e.cropAndPosition
                            : null),
                    item('Rotate right',
                        key: const ValueKey('menu-rotate'),
                        onPressed:
                            e != null && e.canCrop ? e.rotateRight : null),
                    divider,
                    item('Add title', onPressed: x?.addTitle),
                    item('Add caption…', onPressed: x?.addCaption),
                    item('Add overlay video or photo…',
                        key: const ValueKey('menu-add-overlay'),
                        onPressed: e != null && e.canAddOverlay
                            ? e.addOverlay
                            : null),
                    divider,
                    submenu('Shorts', [
                      item('Mark a good moment',
                          key: const ValueKey('menu-mark-moment'),
                          shortcut:
                              const SingleActivator(LogicalKeyboardKey.keyM),
                          onPressed: x?.markMoment),
                      item('Good moments…',
                          key: const ValueKey('menu-good-moments'),
                          onPressed: x?.goodMoments),
                      item('Make a short from here…',
                          key: const ValueKey('menu-short-from-here'),
                          onPressed: x?.shortFromHere),
                      item('Make shorts from markers…',
                          key: const ValueKey('menu-shorts-from-markers'),
                          onPressed: x?.shortsFromMarkers),
                    ]),
                    submenu('Sound', [
                      item('Add voice recording…',
                          key: const ValueKey('menu-add-voice'),
                          onPressed: x?.addVoice),
                      item('Line up with the video',
                          key: const ValueKey('menu-line-up-voice'),
                          onPressed: x?.lineUpVoice),
                      item('Add sound track', onPressed: x?.addSoundTrack),
                      item('Separate sound…', onPressed: x?.separateSound),
                      item('Put sound back', onPressed: x?.putSoundBack),
                      item('Fit music to video', onPressed: x?.fitMusic),
                      item('Copy music credits', onPressed: x?.copyCredits),
                      check('Lower music under speech',
                          value: x?.lowerMusicOn ?? false,
                          onPressed: x?.lowerMusic),
                    ]),
                    if (x?.speech != null)
                      submenu('Speech', [
                        item('Transcribe speech…',
                            key: const ValueKey('menu-transcribe'),
                            onPressed: x!.speech!.transcribe),
                        item('Captions from speech…',
                            key: const ValueKey('menu-speech-captions'),
                            onPressed: x.speech!.captions),
                        item('Remove filler words…',
                            key: const ValueKey('menu-fillers'),
                            onPressed: x.speech!.fillers),
                        item('Automatic cuts…',
                            key: const ValueKey('menu-auto-cuts'),
                            onPressed: x.speech!.autoCuts),
                      ]),
                    submenu('Shape', [
                      for (final a in CanvasAspect.values)
                        check(menuShapeLabel(a),
                            value: x?.currentShape == a,
                            onPressed: x?.shape == null
                                ? null
                                : () => x!.shape!(a)),
                    ]),
                    submenu('Video size', [
                      for (final v in VideoSize.values)
                        check(menuVideoSizeLabel(v),
                            value: x?.currentVideoSize == v,
                            onPressed: x?.videoSize == null
                                ? null
                                : () => x!.videoSize!(v)),
                    ]),
                  ]),
                  menu('Playback', [
                    item(e != null && e.playing ? 'Pause' : 'Play',
                        shortcut:
                            const SingleActivator(LogicalKeyboardKey.space),
                        onPressed: e != null && e.canPlay ? e.togglePlay : null),
                    item('Play backwards',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyJ),
                        onPressed: x?.playBackwards),
                    item('Stop',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyK),
                        onPressed: x?.pause),
                    item('Play forwards',
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyL),
                        onPressed: x?.playForwards),
                    divider,
                    item('Go to start',
                        shortcut: const SingleActivator(LogicalKeyboardKey.home),
                        onPressed: x?.goToStart),
                    item('Go to end',
                        shortcut: const SingleActivator(LogicalKeyboardKey.end),
                        onPressed: x?.goToEnd),
                    item('Previous frame',
                        shortcut:
                            const SingleActivator(LogicalKeyboardKey.arrowLeft),
                        onPressed: x?.previousFrame),
                    item('Next frame',
                        shortcut:
                            const SingleActivator(LogicalKeyboardKey.arrowRight),
                        onPressed: x?.nextFrame),
                    divider,
                    item('Zoom in timeline (+)',
                        shortcut: const SingleActivator(LogicalKeyboardKey.equal),
                        onPressed: x?.zoomIn),
                    item('Zoom out timeline (-)',
                        shortcut: const SingleActivator(LogicalKeyboardKey.minus),
                        onPressed: x?.zoomOut),
                    check('Snap to playhead and edges',
                        key: const ValueKey('menu-snapping'),
                        value: x?.snapping ?? true,
                        onPressed: x?.toggleSnapping),
                    divider,
                    item('Previous speech start',
                        key: const ValueKey('menu-previous-speech'),
                        shortcut: const SingleActivator(
                            LogicalKeyboardKey.arrowLeft,
                            control: true),
                        onPressed: x?.previousSpeech),
                    item('Next speech start',
                        key: const ValueKey('menu-next-speech'),
                        shortcut: const SingleActivator(
                            LogicalKeyboardKey.arrowRight,
                            control: true),
                        onPressed: x?.nextSpeech),
                    check('Show sound waves',
                        key: const ValueKey('menu-waves'),
                        value: x?.wavesOn ?? true,
                        onPressed: x?.toggleWaves),
                  ]),
                  menu('Help', [
                    item('ClipForge Help',
                        shortcut: const SingleActivator(LogicalKeyboardKey.f1),
                        onPressed: help?.openHelp),
                    item('Keyboard shortcuts',
                        key: const ValueKey('menu-shortcuts'),
                        onPressed: x?.showShortcuts),
                    item('Show the tour', onPressed: help?.showTour),
                    divider,
                    item('Connect to Claude…',
                        key: const ValueKey('menu-connect-claude'),
                        onPressed: help?.connectClaude),
                    divider,
                    item('Check for updates…',
                        key: const ValueKey('menu-check-updates'),
                        onPressed: help?.checkForUpdates),
                    check('Check for updates automatically',
                        key: const ValueKey('menu-auto-updates'),
                        value: help?.autoUpdateCheck ?? true,
                        onPressed: help?.toggleAutoUpdateCheck),
                    divider,
                    item('Copy version info',
                        onPressed: help?.copyVersionInfo),
                    item('About ClipForge',
                        key: const ValueKey('menu-about'),
                        onPressed: help?.showAbout),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
