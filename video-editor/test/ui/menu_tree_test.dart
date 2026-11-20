// The menu tree of 1.15 (lib/ui/app_menu.dart, buildMenuTree): ONE tree
// for the macOS menu bar and the bar in the window on Windows and Linux.
//
// test/ui/menu_tree_snapshot.txt holds every item of both bars, in order,
// with its shortcut. A moved, renamed, added or removed item fails here;
// when the change is meant, write the file again with
//   UPDATE_MENU_SNAPSHOT=1 flutter test test/ui/menu_tree_test.dart
// and say where the item went in docs/HANDOVER.md and the "menus" help
// article.

import 'dart:io';

import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/editor/acts.dart';
import 'package:clipforge/ui/help/what_moved.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _platforms = [
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
];

String _snapshot() {
  final out = StringBuffer();
  for (final p in _platforms) {
    out.writeln('## $p');
    for (final l in describeMenuTree(buildMenuTree(null, platform: p))) {
      out.writeln(l);
    }
  }
  return out.toString();
}

/// Every shortcut the menus of 1.14.1 showed (lib/ui/app_menu.dart of that
/// version), as "item: keys". None may go.
const _shortcuts1141 = <TargetPlatform, List<String>>{
  TargetPlatform.macOS: [
    'New project: Cmd+N', 'Open project file…: Cmd+O', 'Export…: Cmd+E', //
    'Undo: Cmd+Z', 'Redo: Cmd+Shift+Z', 'History: Cmd+Shift+H',
    'Mark a good moment: M', 'Text window: Cmd+Shift+T',
    'Find in the text…: Cmd+F', 'Duplicate: Cmd+D',
    'Copy settings: Cmd+Shift+C', 'Paste settings: Cmd+Shift+V',
    'Delete: Backspace', 'Split at playhead: S',
    'Start clip at playhead: I', 'End clip at playhead: O',
    'Play: Space', 'Play backwards: J', 'Stop: K', 'Play forwards: L',
    'Go to start: Home', 'Go to end: End', 'Previous frame: Left',
    'Next frame: Right', 'Zoom in: +', 'Zoom out: -',
    'ClipForge Help: Cmd+Shift+?',
  ],
  TargetPlatform.windows: [
    'New project: Ctrl+N', 'Open project file…: Ctrl+O', 'Export…: Ctrl+E', //
    'Exit: Alt+F4', 'Undo: Ctrl+Z', 'Redo: Ctrl+Shift+Z',
    'History: Ctrl+Shift+H', 'Text window: Ctrl+Shift+T',
    'Find in the text…: Ctrl+F', 'Duplicate: Ctrl+D',
    'Copy settings: Ctrl+Shift+C', 'Paste settings: Ctrl+Shift+V',
    'Delete: Delete', 'Split at playhead: S', 'Start clip at playhead: I',
    'End clip at playhead: O', 'Mark a good moment: M', 'Play: Space',
    'Play backwards: J', 'Stop: K', 'Play forwards: L', 'Go to start: Home',
    'Go to end: End', 'Previous frame: Left', 'Next frame: Right',
    'Zoom in: +', 'Zoom out: -',
    'Previous speech start: Ctrl+Left', 'Next speech start: Ctrl+Right',
    'ClipForge Help: F1',
  ],
};

void main() {
  test('every item of both menu bars, in order, with its shortcut', () {
    final file = File('test/ui/menu_tree_snapshot.txt');
    final now = _snapshot();
    if (Platform.environment['UPDATE_MENU_SNAPSHOT'] == '1') {
      file.writeAsStringSync(now);
    }
    expect(now.split('\n'), file.readAsStringSync().split('\n'));
  });

  test('the ten menus, in this order, on every computer', () {
    for (final p in _platforms) {
      expect([
        for (final m in buildMenuTree(null, platform: p)) m.label,
      ], [
        'File', 'Edit', 'Add', 'Clip', 'Part', 'Sound', 'Text and speech', //
        'View', 'Playback', 'Help',
      ]);
    }
    // The macOS bar: the app's own menu first, Window before Help.
    expect([
      for (final m in buildAppMenus(null)) m.label,
    ], [
      'ClipForge', 'File', 'Edit', 'Add', 'Clip', 'Part', 'Sound', //
      'Text and speech', 'View', 'Playback', 'Window', 'Help',
    ]);
  });

  test('the items the owner asked for are where he asked', () {
    final lines = describeMenuTree(
        buildMenuTree(null, platform: TargetPlatform.windows));
    List<String> of(String menu) => [
          for (final l in lines)
            if (l.startsWith('$menu > ') && !l.endsWith('---'))
              // On the project list every editing item says why it is
              // grey (1.17); the names are what is checked here.
              l
                  .substring(menu.length + 3)
                  .split('  [')
                  .first
                  .replaceAll(' (open a project first)', ''),
        ];
    expect(of('File'), [
      'New project', 'Open project file…', 'Rename project…', //
      'Publishing notes…', 'Back to projects', 'Export…', 'Export several…',
      'Export subtitles (.srt)…', 'Settings…', 'Exit',
    ]);
    expect(of('Edit'), [
      'Undo', 'Redo', 'History', 'Duplicate', 'Copy settings', //
      'Paste settings', 'Delete', 'Find in the text…',
    ]);
    expect(of('Add'), [
      'Videos or photos…', 'Music or sound…', 'Voice recording…', 'Title', //
      'Caption…', 'Subtitle file (.srt)…', 'Overlay video or photo…',
      'Add from a folder path…', 'Good moment marker',
    ]);
    expect(of('Clip'), [
      'Split', 'Start at playhead', 'End at playhead', 'Freeze frame', //
      'Remove silences…', 'Crop and position…', 'Rotate right',
      'Move earlier', 'Move later', 'Make a short from here…',
      'Make shorts from markers…', 'Good moments…',
    ]);
    expect(of('Sound'), [
      'Fit music to video', 'Line up voice with video', 'Separate sound…', //
      'Put sound back', 'Add sound track', 'Lower music under speech',
      'Only when speaking…', 'Copy music credits',
    ]);
    // 1.17: selecting a part, then what to do with it.
    expect(of('Part'), [
      'Select a part', 'Part starts at playhead', 'Part ends at playhead', //
      "Select this clip's time", "Select this speaker's turn",
      'Select the pause here', 'Select between the markers here',
      'Select from the start to the playhead',
      'Select from the playhead to the end', 'Clear the selected part',
      'Cut out', 'Delete and leave a gap', 'Silence', 'Lower volume…',
      'Speed…', 'Clean up sound here', 'Make a short from the part…',
      'Duplicate the part', 'Title over the part',
      'Good moment marker at its start',
    ]);
    expect(of('Text and speech'), [
      'Text window', 'Transcribe speech…', 'Captions from speech…', //
      'Remove filler words…', 'Automatic cuts…',
    ]);
    expect(of('View').take(4), [
      'Zoom in', 'Zoom out', 'Snap to playhead and edges', //
      'Show sound waves',
    ]);
    expect(of('Playback'), [
      'Play/Pause', 'Play backwards', 'Pause', 'Play forwards', //
      'Go to start', 'Go to end', 'Previous frame', 'Next frame',
      'Previous speech start', 'Next speech start',
    ]);
    expect(of('Help'), [
      'ClipForge Help', 'Keyboard shortcuts', 'Show the tour', //
      "What's new", 'Connect to Claude…', 'Check for updates…',
      'Send feedback…',
      'Copy version info', 'About ClipForge',
    ]);
  });

  test('every shortcut the menus of 1.14.1 showed is still there', () {
    for (final p in _platforms) {
      final lines = describeMenuTree(buildMenuTree(null, platform: p));
      // "Ctrl+Shift+Z / Ctrl+Y": an item may show a second key (1.17).
      final keys = {
        for (final l in lines)
          if (l.contains('  ['))
            ...l.split('  [').last.replaceAll(']', '').split(' / '),
      };
      final old = [
        ...(_shortcuts1141[p] ?? _shortcuts1141[TargetPlatform.windows]!),
      ];
      if (p == TargetPlatform.linux) {
        old
          ..remove('Exit: Alt+F4')
          ..add('Quit: Ctrl+Q');
      }
      for (final item in old) {
        final wanted = item.split(': ').last;
        expect(keys, contains(wanted), reason: '$p lost "$item"');
      }
      // No key is shown for two different things.
      final shown = [
        for (final l in lines)
          if (l.contains('  [')) l.split('  [').last,
      ];
      expect(shown.toSet().length, shown.length, reason: '$p: a key twice');
    }
    // 1.17, the ONE shortcut that changed its meaning: I and O mark the
    // start and end of a selected part; what they did (the clip starts /
    // ends at the playhead) is Q and W, and "What moved" says so.
    for (final p in _platforms) {
      final lines = describeMenuTree(buildMenuTree(null, platform: p));
      String keyOf(String item) => lines
          .firstWhere((l) => l.contains('> $item'))
          .split('  [')
          .last
          .replaceAll(']', '');
      expect(keyOf('Start at playhead'), 'Q', reason: '$p');
      expect(keyOf('End at playhead'), 'W', reason: '$p');
      expect(keyOf('Part starts at playhead'), 'I', reason: '$p');
      expect(keyOf('Part ends at playhead'), 'O', reason: '$p');
    }
    expect(kKeysMoved117.$1, contains('I and O'));
    expect(kKeysMoved117.$2, allOf(contains('Q and W'), contains('part')));
    expect(kWhatMovedComputer, contains(kKeysMoved117));
    // New in 1.15: Settings.
    expect(
        describeMenuTree(buildMenuTree(null, platform: TargetPlatform.macOS)),
        contains('File > Settings…  [Cmd+,]'));
    expect(
        describeMenuTree(
            buildMenuTree(null, platform: TargetPlatform.windows)),
        contains('File > Settings…  [Ctrl+,]'));
  });

  test('a greyed-out item says why; a switch shows its state', () {
    ActionEntry e(Act a, {String? reason, bool? checked, bool mixed = false}) =>
        ActionEntry(
            act: a,
            label: mixed ? '${actLabel(a)} — on for some tracks' : actLabel(a),
            icon: actIcon(a),
            reason: reason,
            checked: checked,
            mixed: mixed,
            onTap: reason == null ? () {} : null);
    final editor = EditorMenuActions(entries: {
      Act.fitMusic: e(Act.fitMusic, reason: 'select a music clip'),
      Act.pasteSettings: e(Act.pasteSettings, reason: 'copy settings first'),
      Act.split: e(Act.split),
      Act.snapping: e(Act.snapping, checked: true),
      Act.lowerMusic: e(Act.lowerMusic, checked: false, mixed: true),
    });
    final tree = buildMenuTree(editor, platform: TargetPlatform.windows);
    MenuNode find(String label) {
      for (final m in tree) {
        for (final n in m.children!) {
          if (n.label == label) return n;
        }
      }
      throw StateError('no item "$label"');
    }

    expect(find('Fit music to video (select a music clip)').onSelected, isNull);
    expect(find('Paste settings (copy settings first)').onSelected, isNull);
    expect(find('Split').onSelected, isNotNull);
    expect(find('Snap to playhead and edges').checked, isTrue);
    final lower = find('Lower music under speech — on for some tracks');
    expect((lower.checked, lower.mixed), (false, true));

    // macOS: the same labels; a tick is part of the label there.
    final mac = buildAppMenus(editor);
    final labels = <String>[];
    void walk(List<PlatformMenuItem> items) {
      for (final i in items) {
        if (i is PlatformMenu) {
          walk(i.menus);
        } else if (i is PlatformMenuItemGroup) {
          walk(i.members);
        } else {
          labels.add(i.label);
        }
      }
    }

    walk(mac);
    expect(labels, contains('Fit music to video (select a music clip)'));
    expect(labels, contains('Snap to playhead and edges ✓'));
  });

  testWidgets('Ctrl+comma opens Settings from anywhere: by the character, '
      'by the key\'s place (a layout where it types a letter), with nothing '
      'focused', (tester) async {
    final c = AppMenuController();
    var opened = 0;
    final help = HelpMenuActions(
        openHelp: () {}, showTour: () {}, openSettings: () => opened++);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          WindowMenuBar(controller: c, help: help, child: child!),
      home: const Scaffold(body: Center(child: Text('page'))),
    ));
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    expect(opened, 1);
    // Another layout: the comma key types a letter.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB,
        physicalKey: PhysicalKeyboardKey.comma);
    expect(opened, 2);
    // Another key with Ctrl, and the comma without it: nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    expect(opened, 2);
    // No longer one of the shortcuts that need the keyboard focus.
    expect(
        windowMenuShortcuts(c, help).keys.whereType<SingleActivator>().any(
            (k) => k.trigger == LogicalKeyboardKey.comma),
        isFalse);
  });
}
