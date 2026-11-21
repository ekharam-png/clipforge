import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/model/project.dart';
import 'editor/acts.dart';
import 'theme.dart';

// The app's menus (1.15): ONE tree ([buildMenuTree]) that both menu bars
// draw - the macOS menu bar ([buildAppMenus]) and the bar inside the window
// on Windows and Linux ([WindowMenuBar]) - so they cannot drift apart.
//
//   File · Edit · Add · Clip · Part · Sound · Text and speech · View ·
//   Playback · Help
//
// An item that cannot be used now stays in its place, greyed out, and its
// label says why: "Fit music to video (select a music clip)". The reason
// comes from EditorActions (editor/editor_actions.dart), the same source
// the side panel and the phone use.

/// What the menu bar can do in the open editor: every action with whether
/// it can be done now ([ActionEntry.reason]) and its tick.
@immutable
class EditorMenuActions {
  const EditorMenuActions({
    required this.entries,
    this.playing = false,
    this.shape,
    this.currentShape,
    this.videoSize,
    this.currentVideoSize,
    this.speech = false,
  });

  final Map<Act, ActionEntry> entries;
  final bool playing;

  /// Speech-to-text exists here (computers): the speech items are shown.
  final bool speech;
  final ValueChanged<CanvasAspect>? shape;
  final CanvasAspect? currentShape;
  final ValueChanged<VideoSize>? videoSize;
  final VideoSize? currentVideoSize;

  /// The action of [a], null while it cannot be done.
  VoidCallback? run(Act a) => entries[a]?.onTap;

  /// What the menus show (which items are on, their reasons and ticks),
  /// to tell whether they need building again.
  List<Object?> get state => [
        for (final a in Act.values) ...[
          entries[a]?.label,
          entries[a]?.reason,
          entries[a]?.checked,
          entries[a]?.onTap != null,
        ],
        playing,
        speech,
        currentShape,
        currentVideoSize,
        shape != null,
        videoSize != null,
      ];
}

/// "Original (as the first clip)", "9:16 upright", ...
String menuShapeLabel(CanvasAspect a) => switch (a) {
      CanvasAspect.original => 'Original (as the first clip)',
      CanvasAspect.portrait9x16 => '9:16 upright',
      CanvasAspect.landscape16x9 => '16:9 wide',
      CanvasAspect.square1x1 => '1:1 square',
      CanvasAspect.portrait4x5 => '4:5 upright',
    };

/// "Same as the first clip", "720p", ...
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

/// Connects the open editor to the app's menu bar.
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
        listEquals(before.state, actions.state);
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

/// What the Help menu (and File > Settings…) does.
@immutable
class HelpMenuActions {
  const HelpMenuActions({
    required this.openHelp,
    required this.showTour,
    this.showAbout,
    this.copyVersionInfo,
    this.checkForUpdates,
    this.connectClaude,
    this.sendFeedback,
    this.showWhatsNew,
    this.showShortcuts,
    this.openSettings,
  });
  final VoidCallback openHelp;
  final VoidCallback showTour;

  /// Opens About ClipForge (version, build, date; lib/ui/about.dart).
  final VoidCallback? showAbout;

  /// Copies the version and device details for a bug report.
  final VoidCallback? copyVersionInfo;

  /// Asks now whether a newer version exists (lib/ui/update).
  final VoidCallback? checkForUpdates;

  /// Opens "Connect to Claude" (computers only; null on phones).
  final VoidCallback? connectClaude;

  /// Opens "Send feedback" (lib/ui/feedback).
  final VoidCallback? sendFeedback;

  /// Opens "What's new" (the release notes inside the app).
  final VoidCallback? showWhatsNew;

  /// Opens the "Keyboard shortcuts" help article.
  final VoidCallback? showShortcuts;

  /// Opens the Settings page (File > Settings…, Ctrl/Cmd+,).
  final VoidCallback? openSettings;
}

/// The one [AppMenuController] of the app.
final AppMenuController appMenu = AppMenuController();

/// Whether the app shows its own menu bar: macOS only (Windows and Linux
/// windows have none, phones neither).
bool get usesPlatformMenuBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// One line of a menu: an item, a divider or a submenu.
@immutable
class MenuNode {
  const MenuNode.item(
    this.label, {
    this.id,
    this.shortcut,
    this.onSelected,
    this.checked,
    this.mixed = false,
    this.also,
  })  : children = null,
        divider = false;
  const MenuNode.submenu(this.label, List<MenuNode> this.children, {this.id})
      : shortcut = null,
        also = null,
        onSelected = null,
        checked = null,
        mixed = false,
        divider = false;
  const MenuNode.divider()
      : label = '',
        id = null,
        shortcut = null,
        onSelected = null,
        checked = null,
        mixed = false,
        children = null,
        also = null,
        divider = true;

  /// A second key that does the same ("Ctrl+Y" next to Ctrl+Shift+Z):
  /// shown after the shortcut in the window's menu bar (a Mac's menu bar
  /// shows one key per item).
  final String? also;

  final String label;

  /// The widget key is `menu-<id>`.
  final String? id;
  final SingleActivator? shortcut;

  /// Null: greyed out.
  final VoidCallback? onSelected;

  /// Null: no tick; else the state of a switch.
  final bool? checked;

  /// A switch that is on for some and off for others.
  final bool mixed;
  final List<MenuNode>? children;
  final bool divider;
}

/// The keys as a menu shows them: "Ctrl+Shift+T", "Cmd+,", "Space".
String describeShortcut(SingleActivator a) {
  final key = a.trigger;
  final name = switch (key) {
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.equal => '+',
    LogicalKeyboardKey.minus => '-',
    LogicalKeyboardKey.slash => '?',
    LogicalKeyboardKey.arrowLeft => 'Left',
    LogicalKeyboardKey.arrowRight => 'Right',
    _ => key.keyLabel,
  };
  return [
    if (a.control) 'Ctrl',
    if (a.meta) 'Cmd',
    if (a.alt) 'Alt',
    if (a.shift) 'Shift',
    name,
  ].join('+');
}

/// A shortcut written the Windows way ("Ctrl+Left", "Ctrl+Shift+T") in
/// the words of the computer the app runs on: "Cmd+Left" on a Mac. THE
/// one place for shortcut text outside the menus (tooltips, notes), so
/// that a Mac never reads "Ctrl" (1.18).
String shortcutText(String keys, {TargetPlatform? platform}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.macOS
        ? keys.replaceAll('Ctrl', 'Cmd')
        : keys;

/// The whole menu tree as text, one line per item (tests keep a copy, so
/// a moved or renamed item is noticed).
List<String> describeMenuTree(List<MenuNode> menus) {
  final out = <String>[];
  void walk(String path, List<MenuNode> nodes) {
    for (final n in nodes) {
      if (n.divider) {
        out.add('$path > ---');
      } else if (n.children != null) {
        walk('$path > ${n.label}', n.children!);
      } else {
        out.add('$path > ${n.label}'
            '${n.shortcut == null ? '' : '  [${describeShortcut(n.shortcut!)}${n.also == null ? '' : ' / ${n.also}'}]'}');
      }
    }
  }

  for (final m in menus) {
    walk(m.label, m.children!);
  }
  return out;
}

const String _toProjects = 'go back to the projects first';

/// THE menu tree: File, Edit, Add, Clip, Part, Sound, Text and speech,
/// View, Playback, Help. [platform] decides the modifier key (Cmd on macOS, Ctrl
/// elsewhere), Delete / Backspace, the Help key and Quit / Exit.
///
/// Items carry their shortcuts (Undo, Delete, Play = Space, the
/// single-letter editing keys, ...). Most are only SHOWN here: the editor's
/// own key handling does them, so they also work without the menu and never
/// run twice (see [windowMenuShortcuts] for the few the menu bar handles).
List<MenuNode> buildMenuTree(
  EditorMenuActions? editor, {
  HelpMenuActions? help,
  HomeMenuActions? home,
  TargetPlatform? platform,
}) {
  final os = platform ?? defaultTargetPlatform;
  final mac = os == TargetPlatform.macOS;
  final windows = os == TargetPlatform.windows;
  final e = editor;
  final h = e == null ? home : null;
  SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
      SingleActivator(k, meta: mac, control: !mac, shift: shift);
  SingleActivator plain(LogicalKeyboardKey k) => SingleActivator(k);

  MenuNode act(Act a, String id,
      {SingleActivator? shortcut, String? label, String? also}) {
    final entry = e?.entries[a];
    final base = label ?? entry?.label ?? actLabel(a);
    // On the project list every editing item is greyed out for the same
    // reason; it is said on each (1.17: a greyed item without a word
    // looked broken).
    final reason = e == null ? 'open a project first' : entry?.reason;
    return MenuNode.item(
      reason == null ? base : '$base ($reason)',
      id: id,
      shortcut: shortcut,
      also: also,
      onSelected: entry?.onTap,
      checked: entry?.checked,
      mixed: entry?.mixed ?? false,
    );
  }

  const divider = MenuNode.divider();
  final settings = e?.entries[Act.settings]?.onTap ?? help?.openSettings;
  final shortcuts = e?.entries[Act.shortcuts]?.onTap ?? help?.showShortcuts;
  return [
    MenuNode.submenu('File', [
      MenuNode.item(
          e == null ? 'New project' : 'New project ($_toProjects)',
          id: 'new-project',
          shortcut: key(LogicalKeyboardKey.keyN),
          onSelected: h?.newProject),
      MenuNode.item(
          e == null
              ? 'Open project file…'
              : 'Open project file… ($_toProjects)',
          id: 'open-project-file',
          shortcut: key(LogicalKeyboardKey.keyO),
          onSelected: h?.openProjectFile),
      divider,
      act(Act.renameProject, 'rename-project'),
      act(Act.publishingNotes, 'publishing-notes'),
      act(Act.backToProjects, 'back-to-projects'),
      divider,
      act(Act.export, 'export', shortcut: key(LogicalKeyboardKey.keyE)),
      act(Act.exportSeveral, 'export-several'),
      act(Act.exportSubtitles, 'export-subtitles'),
      divider,
      MenuNode.item('Settings…',
          id: 'settings',
          shortcut: key(LogicalKeyboardKey.comma),
          onSelected: settings),
      // macOS has Quit in the app's own menu, as every Mac app does.
      if (!mac) ...[
        divider,
        MenuNode.item(windows ? 'Exit' : 'Quit',
            id: 'quit',
            shortcut: windows
                ? const SingleActivator(LogicalKeyboardKey.f4, alt: true)
                : const SingleActivator(LogicalKeyboardKey.keyQ,
                    control: true),
            onSelected: requestAppQuit),
      ],
    ]),
    MenuNode.submenu('Edit', [
      act(Act.undo, 'undo', shortcut: key(LogicalKeyboardKey.keyZ)),
      // Ctrl+Y works too (Help > Keyboard shortcuts says so); the menu
      // shows the same keys as on a Mac.
      act(Act.redo, 'redo',
          shortcut: key(LogicalKeyboardKey.keyZ, shift: true),
          also: mac ? null : 'Ctrl+Y'),
      act(Act.history, 'history',
          shortcut: key(LogicalKeyboardKey.keyH, shift: true)),
      divider,
      act(Act.duplicate, 'duplicate', shortcut: key(LogicalKeyboardKey.keyD)),
      act(Act.copySettings, 'copy-settings',
          shortcut: key(LogicalKeyboardKey.keyC, shift: true)),
      act(Act.pasteSettings, 'paste-settings',
          shortcut: key(LogicalKeyboardKey.keyV, shift: true)),
      // Delete and Backspace both delete, on every computer.
      act(Act.delete, 'delete',
          shortcut: plain(mac
              ? LogicalKeyboardKey.backspace
              : LogicalKeyboardKey.delete),
          also: mac ? null : 'Backspace'),
      divider,
      act(Act.findInText, 'find-text', shortcut: key(LogicalKeyboardKey.keyF)),
    ]),
    MenuNode.submenu('Add', [
      act(Act.addMedia, 'add-media'),
      act(Act.addMusic, 'add-music'),
      act(Act.addVoice, 'add-voice'),
      act(Act.addTitle, 'add-title'),
      act(Act.addCaption, 'add-caption'),
      act(Act.importSubtitles, 'import-subtitles'),
      act(Act.addOverlay, 'add-overlay'),
      act(Act.addFromPath, 'add-from-path'),
      act(Act.markMoment, 'mark-moment',
          shortcut: plain(LogicalKeyboardKey.keyM)),
    ]),
    MenuNode.submenu('Clip', [
      act(Act.split, 'split', shortcut: plain(LogicalKeyboardKey.keyS)),
      // Q / W since 1.17: I and O mark a part (the Part menu).
      act(Act.startAtPlayhead, 'start-at-playhead',
          shortcut: plain(LogicalKeyboardKey.keyQ)),
      act(Act.endAtPlayhead, 'end-at-playhead',
          shortcut: plain(LogicalKeyboardKey.keyW)),
      act(Act.freezeFrame, 'freeze-frame'),
      act(Act.removeSilences, 'remove-silences'),
      act(Act.crop, 'crop'),
      act(Act.rotateRight, 'rotate'),
      act(Act.moveEarlier, 'move-earlier'),
      act(Act.moveLater, 'move-later'),
      divider,
      act(Act.shortFromHere, 'short-from-here'),
      act(Act.shortsFromMarkers, 'shorts-from-markers'),
      act(Act.goodMoments, 'good-moments'),
    ]),
    // 1.17: select a part of the timeline, then act on it.
    MenuNode.submenu('Part', [
      act(Act.selectPart, 'select-part'),
      act(Act.partStart, 'part-start',
          shortcut: plain(LogicalKeyboardKey.keyI)),
      act(Act.partEnd, 'part-end', shortcut: plain(LogicalKeyboardKey.keyO)),
      act(Act.partOfItem, 'part-of-item'),
      act(Act.partTurn, 'part-turn'),
      act(Act.partPause, 'part-pause'),
      act(Act.partBetweenMarkers, 'part-between-markers'),
      act(Act.partFromStart, 'part-from-start'),
      act(Act.partToEnd, 'part-to-end'),
      // Esc clears it too; not shown as a menu key, so that a Mac's menu
      // bar does not take Esc away from dialogs and text boxes.
      act(Act.clearPart, 'clear-part'),
      divider,
      act(Act.partCutOut, 'part-cut-out'),
      act(Act.partDelete, 'part-delete'),
      act(Act.partSilence, 'part-silence'),
      act(Act.partLower, 'part-lower'),
      act(Act.partSpeed, 'part-speed'),
      act(Act.partClean, 'part-clean'),
      divider,
      act(Act.partShort, 'part-short'),
      act(Act.partDuplicate, 'part-duplicate'),
      act(Act.partTitle, 'part-title'),
      act(Act.partMarker, 'part-marker'),
    ]),
    MenuNode.submenu('Sound', [
      act(Act.fitMusic, 'fit-music'),
      act(Act.lineUpVoice, 'line-up-voice'),
      act(Act.separateSound, 'separate-sound'),
      act(Act.putSoundBack, 'put-sound-back'),
      act(Act.addSoundTrack, 'add-sound-track'),
      act(Act.lowerMusic, 'lower-music'),
      act(Act.onlyWhenSpeaking, 'only-when-speaking'),
      act(Act.copyCredits, 'copy-credits'),
    ]),
    MenuNode.submenu('Text and speech', [
      act(Act.textWindow, 'text',
          shortcut: key(LogicalKeyboardKey.keyT, shift: true)),
      // Speech-to-text: computers only. On the project list the items are
      // listed (greyed out), so the menu looks the same before and after
      // a project is opened.
      if (e == null || e.speech) ...[
        act(Act.transcribe, 'transcribe'),
        act(Act.captionsFromSpeech, 'speech-captions'),
        act(Act.removeFillers, 'fillers'),
        act(Act.autoCuts, 'auto-cuts'),
      ],
    ]),
    MenuNode.submenu('View', [
      act(Act.zoomIn, 'zoom-in', shortcut: plain(LogicalKeyboardKey.equal)),
      act(Act.zoomOut, 'zoom-out', shortcut: plain(LogicalKeyboardKey.minus)),
      act(Act.snapping, 'snapping'),
      act(Act.soundWaves, 'waves'),
      act(Act.sidePanel, 'side-panel',
          shortcut: key(LogicalKeyboardKey.keyP, shift: true)),
      divider,
      MenuNode.submenu('Shape', id: 'shape', [
        for (final a in CanvasAspect.values)
          MenuNode.item(menuShapeLabel(a),
              id: 'shape-${a.name}',
              checked: e?.currentShape == a,
              onSelected: e?.shape == null ? null : () => e!.shape!(a)),
      ]),
      MenuNode.submenu('Video size', id: 'video-size', [
        for (final v in VideoSize.values)
          MenuNode.item(menuVideoSizeLabel(v),
              id: 'video-size-${v.name}',
              checked: e?.currentVideoSize == v,
              onSelected:
                  e?.videoSize == null ? null : () => e!.videoSize!(v)),
      ]),
    ]),
    MenuNode.submenu('Playback', [
      act(Act.playPause, 'play-pause',
          shortcut: plain(LogicalKeyboardKey.space)),
      act(Act.playBackwards, 'play-backwards',
          shortcut: plain(LogicalKeyboardKey.keyJ)),
      act(Act.pause, 'pause', shortcut: plain(LogicalKeyboardKey.keyK)),
      act(Act.playForwards, 'play-forwards',
          shortcut: plain(LogicalKeyboardKey.keyL)),
      divider,
      act(Act.goToStart, 'go-to-start',
          shortcut: plain(LogicalKeyboardKey.home)),
      act(Act.goToEnd, 'go-to-end', shortcut: plain(LogicalKeyboardKey.end)),
      act(Act.previousFrame, 'previous-frame',
          shortcut: plain(LogicalKeyboardKey.arrowLeft)),
      act(Act.nextFrame, 'next-frame',
          shortcut: plain(LogicalKeyboardKey.arrowRight)),
      divider,
      // Ctrl/Cmd+Left / Right: the editor's own key handling does them, so
      // that they keep their meaning in a text box. (macOS shows no key
      // here: its menu bar would take the keys away from text boxes.)
      act(Act.previousSpeech, 'previous-speech',
          shortcut: mac ? null : key(LogicalKeyboardKey.arrowLeft)),
      act(Act.nextSpeech, 'next-speech',
          shortcut: mac ? null : key(LogicalKeyboardKey.arrowRight)),
    ]),
    MenuNode.submenu('Help', [
      MenuNode.item('ClipForge Help',
          id: 'help',
          shortcut: mac
              ? const SingleActivator(LogicalKeyboardKey.slash,
                  meta: true, shift: true)
              : const SingleActivator(LogicalKeyboardKey.f1),
          onSelected: help?.openHelp),
      MenuNode.item('Keyboard shortcuts',
          id: 'shortcuts', onSelected: shortcuts),
      MenuNode.item('Show the tour', id: 'tour', onSelected: help?.showTour),
      MenuNode.item("What's new",
          id: 'whats-new', onSelected: help?.showWhatsNew),
      divider,
      MenuNode.item('Connect to Claude…',
          id: 'connect-claude', onSelected: help?.connectClaude),
      MenuNode.item('Check for updates…',
          id: 'check-updates', onSelected: help?.checkForUpdates),
      divider,
      MenuNode.item('Send feedback…',
          id: 'send-feedback', onSelected: help?.sendFeedback),
      MenuNode.item('Copy version info',
          id: 'copy-version', onSelected: help?.copyVersionInfo),
      MenuNode.item('About ClipForge',
          id: 'about', onSelected: help?.showAbout),
    ]),
  ];
}

/// The menus of the macOS menu bar: the app's own menu, [buildMenuTree]
/// and Window. Disabled items have no [PlatformMenuItem.onSelected].
List<PlatformMenuItem> buildAppMenus(EditorMenuActions? editor,
    {HelpMenuActions? help, HomeMenuActions? home}) {
  final tree = buildMenuTree(editor,
      help: help, home: home, platform: TargetPlatform.macOS);
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
    for (final m in tree)
      if (m.label != 'Help') _convert(m),
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
    _convert(tree.last),
  ];
}

PlatformMenuItem _convert(MenuNode n) {
  if (n.children != null) {
    return PlatformMenu(label: n.label, menus: groups(n.children!));
  }
  final tick = n.checked == true ? ' ✓' : '';
  return PlatformMenuItem(
      label: '${n.label}$tick', shortcut: n.shortcut, onSelected: n.onSelected);
}

/// [nodes] as the members of a macOS menu: the stretches between dividers
/// become groups (drawn with a line between them).
List<PlatformMenuItem> groups(List<MenuNode> nodes) {
  if (!nodes.any((n) => n.divider)) return [for (final n in nodes) _convert(n)];
  final out = <PlatformMenuItem>[];
  var group = <PlatformMenuItem>[];
  for (final n in nodes) {
    if (n.divider) {
      if (group.isNotEmpty) out.add(PlatformMenuItemGroup(members: group));
      group = [];
    } else {
      group.add(_convert(n));
    }
  }
  if (group.isNotEmpty) out.add(PlatformMenuItemGroup(members: group));
  return out;
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
    return MacAppKeys(
      controller: c,
      help: help,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, child) => PlatformMenuBar(
            menus: buildAppMenus(c.editor, help: help, home: c.home),
            child: child!),
        child: child,
      ),
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
/// Delete, Space, Ctrl+D, Ctrl+Shift+C / V, Ctrl+F, S, I, O, M, J, K, L,
/// + / -, the arrows, Home / End) is only SHOWN in the menu: the editor's
/// own key handling does them (and a text field's own typing and Undo go
/// first), so they never run twice.
Map<ShortcutActivator, VoidCallback> windowMenuShortcuts(
    AppMenuController c, HelpMenuActions? help) {
  final e = c.editor;
  final h = e == null ? c.home : null;
  final export = e?.run(Act.export);
  final history = e?.run(Act.history);
  final text = e?.run(Act.textWindow);
  final panel = e?.run(Act.sidePanel);
  return {
    const SingleActivator(LogicalKeyboardKey.keyP,
        control: true, shift: true): ?panel,
    if (h != null) ...{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          h.newProject,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true):
          h.openProjectFile,
    },
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): ?export,
    const SingleActivator(LogicalKeyboardKey.keyH,
        control: true, shift: true): ?history,
    const SingleActivator(LogicalKeyboardKey.keyT,
        control: true, shift: true): ?text,
    // Ctrl+, is handled for the whole app by [isSettingsShortcut] (see
    // WindowMenuBar): by the key's place on the keyboard too, and
    // wherever the keyboard focus is.
    if (help != null) const SingleActivator(LogicalKeyboardKey.f1): help.openHelp,
    if (defaultTargetPlatform == TargetPlatform.linux)
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
        requestAppQuit();
      },
  };
}

/// True for Ctrl+, (Settings) on Windows and Linux: the comma by what it
/// types OR by its place on the keyboard. With a Russian or Hebrew layout
/// the comma key types another letter, and Flutter only maps letters and
/// digits back to their Latin keys, so matching the typed character alone
/// missed it (1.17; Ctrl+, did nothing in a real Windows test).
///
/// [mac]: Cmd+, instead (1.18). The Mac's own menu bar normally answers
/// it before the app sees the key; this is the second way in for a
/// keyboard layout where it does not.
bool isSettingsShortcut(KeyEvent event, {bool mac = false}) {
  if (event is! KeyDownEvent) return false;
  final keys = HardwareKeyboard.instance;
  if (keys.isAltPressed || keys.isShiftPressed) return false;
  if (mac
      ? (!keys.isMetaPressed || keys.isControlPressed)
      : (!keys.isControlPressed || keys.isMetaPressed)) {
    return false;
  }
  return event.logicalKey == LogicalKeyboardKey.comma ||
      event.physicalKey == PhysicalKeyboardKey.comma;
}

/// True for Cmd+? (Cmd+Shift+/) on a Mac: by what the key types or by its
/// place on the keyboard.
bool isMacHelpShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final keys = HardwareKeyboard.instance;
  if (!keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
    return false;
  }
  if (event.logicalKey == LogicalKeyboardKey.question) return true;
  return keys.isShiftPressed &&
      (event.logicalKey == LogicalKeyboardKey.slash ||
          event.physicalKey == PhysicalKeyboardKey.slash);
}

/// The Mac: Cmd+? opens ClipForge Help and Cmd+, Settings ALSO when the
/// system's menu bar did not answer the key (1.18). In the 1.17 test
/// Cmd+? did nothing visible: macOS gives that key to the search box of
/// the Help menu before the menu item's own shortcut. A key the menu bar
/// did answer never arrives here, so nothing opens twice (and the pages
/// themselves ignore a second request within a moment).
class MacAppKeys extends StatefulWidget {
  const MacAppKeys(
      {super.key, required this.controller, required this.child, this.help});
  final AppMenuController controller;
  final HelpMenuActions? help;
  final Widget child;

  @override
  State<MacAppKeys> createState() => _MacAppKeysState();
}

class _MacAppKeysState extends State<MacAppKeys> {
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    VoidCallback? open;
    if (isMacHelpShortcut(event)) {
      open = widget.help?.openHelp;
    } else if (isSettingsShortcut(event, mac: true)) {
      open = widget.controller.editor?.run(Act.settings) ??
          widget.help?.openSettings;
    }
    if (open == null) return false;
    // Key repeat, or the menu bar and this both: once.
    final now = DateTime.now();
    final last = _last;
    _last = now;
    if (last != null && now.difference(last).inMilliseconds < 600) return true;
    open();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The menu bar along the top of the window on Windows and Linux: the same
/// menus and actions as the macOS menu bar ([buildMenuTree]),
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

  /// True while a menu of the bar is open: the keys then belong to the
  /// menu (arrows, letters), not to the editor's shortcuts.
  static bool get menuOpen => _menusOpen > 0;
  static int _menusOpen = 0;

  @override
  State<WindowMenuBar> createState() => _WindowMenuBarState();
}

class _WindowMenuBarState extends State<WindowMenuBar> {
  /// Menus open now, and what had the keyboard before the first opened.
  int _open = 0;
  FocusNode? _focusBefore;

  void _opened() {
    if (_open++ == 0) _focusBefore = FocusManager.instance.primaryFocus;
    WindowMenuBar._menusOpen = _open;
  }

  /// When the last menu closes, the keyboard goes back to where it was
  /// (the editor), so that Space, the arrows and Ctrl+Z keep working after
  /// a menu was used.
  void _closed() {
    if (_open > 0) _open--;
    WindowMenuBar._menusOpen = _open;
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
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onAppKey);
    FocusManager.instance.addEarlyKeyEventHandler(_onMenuKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onAppKey);
    FocusManager.instance.removeEarlyKeyEventHandler(_onMenuKey);
    WindowMenuBar._menusOpen = 0;
    super.dispose();
  }

  /// The menu bar's own shortcuts (Ctrl+E, Ctrl+Shift+H, Ctrl+Shift+T, F1,
  /// Ctrl+N / O on the project list) are answered BEFORE the focus tree
  /// is asked (1.17): wherever the keyboard focus is - a slider of the
  /// side panel, the Text window, the timeline - and whatever that widget
  /// does with keys itself. The [CallbackShortcuts] below stay as the
  /// second way in.
  KeyEventResult _onMenuKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent || WindowMenuBar.menuOpen) {
      return KeyEventResult.ignored;
    }
    for (final e in windowMenuShortcuts(controller, help).entries) {
      if (e.key.accepts(event, HardwareKeyboard.instance)) {
        e.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Ctrl+, opens Settings from anywhere in the app: also when nothing has
  /// the keyboard focus (the project list right after start), where the
  /// shortcuts of the widget tree are never asked.
  bool _onAppKey(KeyEvent event) {
    if (!mounted || !isSettingsShortcut(event)) return false;
    final open = controller.editor?.run(Act.settings) ?? help?.openSettings;
    if (open == null) return false;
    open();
    return true;
  }

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
    // The app's own font (a bare TextStyle would fall back to the
    // system's default one).
    final itemText = TextStyle(
        fontSize: 13,
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily);
    final itemStyle = MenuItemButton.styleFrom(
      minimumSize: const Size(200, 32),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: itemText,
      visualDensity: VisualDensity.compact,
    );
    const dropStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(AppColors.panelHigh),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: AppColors.outline),
      )),
    );
    // [ticks]: the menu this item is in has items with a tick, so every
    // item keeps the room for one and the words line up.
    Widget build(MenuNode n, {required bool top, bool ticks = false}) {
      final key = n.id == null ? null : ValueKey('menu-${n.id}');
      if (n.divider) return const Divider(height: 9, indent: 8, endIndent: 8);
      final children = n.children;
      if (children != null) {
        return SubmenuButton(
          key: key,
          onOpen: top ? _opened : null,
          onClose: top ? _closed : null,
          style: SubmenuButton.styleFrom(
            minimumSize: top ? const Size(0, height) : const Size(200, 32),
            padding: EdgeInsets.symmetric(horizontal: top ? 10 : 14),
            textStyle: itemText,
            visualDensity: VisualDensity.compact,
          ),
          menuStyle: dropStyle,
          menuChildren: [
            for (final c in children)
              build(c,
                  top: false,
                  ticks: children.any((x) => x.checked != null)),
          ],
          child: Text(n.label),
        );
      }
      final checked = n.checked;
      return MenuItemButton(
        key: key,
        style: itemStyle,
        // The keys in OUR words ([describeShortcut]): "+" for zoom in,
        // not "=" (the key it shares on most keyboards).
        trailingIcon: n.shortcut == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                    '${describeShortcut(n.shortcut!)}'
                    '${n.also == null ? '' : ' / ${n.also}'}',
                    style: itemText.copyWith(
                        color: n.onSelected == null
                            ? AppColors.textDim.withValues(alpha: 0.5)
                            : AppColors.textDim)),
              ),
        onPressed: n.onSelected,
        leadingIcon: checked == null
            ? (ticks ? const SizedBox(width: 18) : null)
            : SizedBox(
                width: 18,
                child: n.mixed
                    ? const Icon(Icons.remove, size: 16)
                    : checked
                        ? const Icon(Icons.check, size: 16)
                        : null,
              ),
        child: Text(n.label),
      );
    }

    final tree = buildMenuTree(controller.editor,
        help: help, home: controller.home);
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
                children: [for (final m in tree) build(m, top: true)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
