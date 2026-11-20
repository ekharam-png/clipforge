// The menu bar inside the window on Windows and Linux (lib/ui/app_menu.dart,
// WindowMenuBar): same menus and actions as the macOS one, enabled from the
// open editor, keys that never run twice.

import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/editor/acts.dart';
import 'package:clipforge/ui/editor/export_dialog.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// Counts what the menu asked for.
class _Calls {
  final Map<String, int> n = {};
  VoidCallback call(String what) =>
      () => n[what] = (n[what] ?? 0) + 1;
  int operator [](String what) => n[what] ?? 0;
}

EditorMenuActions _editor(
  _Calls calls, {
  bool canUndo = true,
  bool canExport = true,
  bool playing = false,
}) {
  ActionEntry e(Act a, String name, {String? reason}) => ActionEntry(
    act: a,
    label: actLabel(a),
    icon: actIcon(a),
    reason: reason,
    onTap: reason == null ? calls(name) : null,
  );
  return EditorMenuActions(
    entries: {
      Act.undo: e(Act.undo, 'undo', reason: canUndo ? null : 'nothing to undo'),
      Act.redo: e(Act.redo, 'redo', reason: 'nothing to redo'),
      Act.delete: e(Act.delete, 'delete'),
      Act.playPause: e(Act.playPause, 'play'),
      Act.export: e(
        Act.export,
        'export',
        reason: canExport ? null : 'add a video first',
      ),
      Act.backToProjects: e(Act.backToProjects, 'back'),
    },
    playing: playing,
  );
}

Widget _app(AppMenuController c, _Calls calls) => MaterialApp(
  theme: ThemeData.dark(),
  builder: (context, child) => AppMenuBar(
    controller: c,
    help: HelpMenuActions(openHelp: calls('help'), showTour: calls('tour')),
    child: child!,
  ),
  home: const Scaffold(body: Center(child: Text('page'))),
);

Future<void> _open(WidgetTester tester, String menu) async {
  await tester.tap(find.widgetWithText(SubmenuButton, menu));
  await tester.pumpAndSettle();
}

MenuItemButton _item(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton)),
);

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Windows and Linux: the nine menus in the window',
    (tester) async {
      final platform = defaultTargetPlatform;
      // Wide enough for all nine menus (the test font is wide).
      useScreen(tester, desktop);
      final c = AppMenuController();
      final calls = _Calls();
      await tester.pumpWidget(_app(c, calls));
      expect(find.byType(MenuBar), findsOneWidget);
      for (final m in [
        'File', 'Edit', 'Add', 'Clip', 'Sound', 'Text and speech', 'View', //
        'Playback', 'Help',
      ]) {
        expect(find.widgetWithText(SubmenuButton, m), findsOneWidget);
      }
      expect(
        tester.getSize(find.byType(MenuBar)).height,
        lessThanOrEqualTo(WindowMenuBar.height),
      );

      // Project list: New and Open; nothing of the editor.
      c.attachHome(
        c,
        HomeMenuActions(
          newProject: calls('new'),
          openProjectFile: calls('openFile'),
        ),
      );
      await tester.pump();
      await _open(tester, 'File');
      expect(_item(tester, 'New project').onPressed, isNotNull);
      expect(_item(tester, 'Open project file…').onPressed, isNotNull);
      // 1.17: a greyed item says why, on the project list too.
      expect(
          _item(tester, 'Back to projects (open a project first)').onPressed,
          isNull);
      expect(_item(tester, 'Export… (open a project first)').onPressed, isNull);
      expect(
        find.text(platform == TargetPlatform.windows ? 'Exit' : 'Quit'),
        findsOneWidget,
      );
      // Shortcut labels as Windows / Linux write them.
      expect(find.text('Ctrl+N'), findsOneWidget);
      expect(find.text('Ctrl+E'), findsOneWidget);
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();
      expect(calls['new'], 1);
      await _key(tester, LogicalKeyboardKey.keyO, control: true);
      expect(calls['openFile'], 1);

      // An editor opens: its actions, enabled as it says.
      c.attach(c, _editor(calls, canUndo: false));
      await tester.pump();
      await _open(tester, 'File');
      expect(
          _item(tester, 'New project (go back to the projects first)')
              .onPressed,
          isNull);
      expect(_item(tester, 'Export…').onPressed, isNotNull);
      await tester.tap(find.text('Back to projects'));
      await tester.pumpAndSettle();
      expect(calls['back'], 1);
      await _open(tester, 'Edit');
      // Greyed out, and it says why.
      expect(_item(tester, 'Undo (nothing to undo)').onPressed, isNull);
      expect(_item(tester, 'Delete').onPressed, isNotNull);
      expect(find.text('Ctrl+Z'), findsOneWidget);
      // Both keys that redo, both keys that delete (1.17).
      expect(find.text('Ctrl+Shift+Z / Ctrl+Y'), findsOneWidget);
      expect(find.text('Delete / Backspace'), findsOneWidget);
      expect(find.text('Ctrl+D'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(calls['delete'], 1);
      await _open(tester, 'Playback');
      await tester.tap(find.text('Play/Pause'));
      await tester.pumpAndSettle();
      expect(calls['play'], 1);
      await _open(tester, 'Help');
      await tester.tap(find.text('Show the tour'));
      await tester.pumpAndSettle();
      expect(calls['tour'], 1);

      // Keys: Ctrl+E and F1 are the menu's own; Ctrl+N is off in the editor.
      await _key(tester, LogicalKeyboardKey.keyE, control: true);
      await _key(tester, LogicalKeyboardKey.f1);
      await _key(tester, LogicalKeyboardKey.keyN, control: true);
      expect(calls['export'], 1);
      expect(calls['help'], 1);
      expect(calls['new'], 1);
      // Undo / Redo / Delete / Space are only shown: the editor's own keys
      // do them.
      await _key(tester, LogicalKeyboardKey.keyZ, control: true);
      await _key(tester, LogicalKeyboardKey.delete);
      expect(calls['undo'], 0);
      expect(calls['delete'], 1);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('phones and macOS: no menu bar in the window', (tester) async {
    final c = AppMenuController();
    await tester.pumpWidget(_app(c, _Calls()));
    expect(find.byType(MenuBar), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  group('with the real editor (Windows)', () {
    EditorSession sessionOf(WidgetTester tester) =>
        tester.widget<PreviewView>(find.byType(PreviewView)).session;

    testWidgets('Ctrl+Z undoes one step, the menu runs the editor, keys '
        'work again after a menu was used', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()], missing: const {});
      await tester.pumpWidget(
        fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MenuBar), findsOneWidget);
      final s = sessionOf(tester);
      final before = s.project.clips.length;
      s.editor.removeClip(s.project.clips[0].id);
      s.editor.removeClip(s.project.clips[0].id);
      await tester.pumpAndSettle();
      expect(s.project.clips.length, before - 2);

      // Ctrl+Z once: one step back, not two (the menu only shows it).
      await _key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(s.project.clips.length, before - 1);

      // Edit > Undo from the menu.
      await _open(tester, 'Edit');
      expect(_item(tester, 'Undo').onPressed, isNotNull);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(s.project.clips.length, before);

      // The keyboard is back with the editor: Space plays.
      expect(s.playback.playing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(s.playback.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(s.playback.playing, isFalse);

      // File > Export… opens the export dialog; behind it the menu does
      // nothing to the editor.
      await _open(tester, 'File');
      await tester.tap(find.text('Export…'));
      await tester.pumpAndSettle();
      expect(find.byType(ExportDialog), findsOneWidget);
      s.editor.removeClip(s.project.clips[0].id);
      await tester.pumpAndSettle();
      final n = s.project.clips.length;
      await _open(tester, 'Edit');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(s.project.clips.length, n);
      expect(find.byType(ExportDialog), findsOneWidget);
      await _open(tester, 'File');
      await tester.tap(find.text('Back to projects'));
      await tester.pumpAndSettle();
      expect(find.byType(ExportDialog), findsOneWidget);
      expect(find.byType(EditorScreen), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ExportDialog), findsNothing);

      // Ctrl+E is the menu's Export.
      await _key(tester, LogicalKeyboardKey.keyE, control: true);
      expect(find.byType(ExportDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // A font loaded on the way sends its "fonts changed" note late.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
