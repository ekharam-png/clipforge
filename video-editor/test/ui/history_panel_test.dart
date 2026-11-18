// The History panel (desktop), the History sheet (phone) and the
// "Processing sound" states of instant sound processing, with screenshots.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/sound_renders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// Three edits: speed, voice focus, a title.
Future<void> edit(WidgetTester tester, EditorSession s) async {
  s.editor.setClipSpeed('a', 1.25);
  s.editor.setClipVoiceFocus('d', 0.85);
  s.editor.setClipMuted('d', false);
  s.editor.addTitle(const TitleOverlay(
      id: 't2', text: 'Summer', startMs: 5000, endMs: 7000));
  await tester.pumpAndSettle();
}

Finder row(int step) => find.byKey(ValueKey('history-step-$step'));

void main() {
  setUpAll(loadFonts);

  testWidgets('desktop: History panel, newest first, jump to a step',
      (tester) async {
    final fakes = await openEditor(tester, desktop);
    final s = sessionOf(tester);
    await edit(tester, s);
    expect(find.byKey(const ValueKey('history-panel')), findsNothing);
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-panel')), findsOneWidget);
    expect(find.text("Added title 'Summer'"), findsOneWidget);
    expect(find.text('Unmuted clip 4'), findsOneWidget);
    expect(find.text('Voice focus 85% on clip 4'), findsOneWidget);
    expect(find.text('Speed 1.25× on clip 1'), findsOneWidget);
    expect(find.text('Opened'), findsOneWidget);
    // Newest at the top.
    expect(tester.getTopLeft(row(4)).dy, lessThan(tester.getTopLeft(row(1)).dy));
    expect(tester.getTopLeft(row(1)).dy, lessThan(tester.getTopLeft(row(0)).dy));

    // Back to just after the speed change, in one jump.
    await tester.tap(find.text('Speed 1.25× on clip 1'));
    await tester.pumpAndSettle();
    expect(s.editor.historyPosition, 1);
    expect(s.project.clips.first.speed, 1.25);
    expect(s.project.titles, hasLength(1));
    expect(s.project.clips.last.voiceFocus, 0);
    // The later steps are still listed and can be brought back.
    expect(find.text("Added title 'Summer'"), findsOneWidget);
    expect(s.editor.canRedo, isTrue);
    await fakes.screenshot(tester, 'editor_desktop_history');
    await tester.tap(find.text('Unmuted clip 4'));
    await tester.pumpAndSettle();
    expect(s.editor.historyPosition, 3);
    expect(s.project.clips.last.voiceFocus, 0.85);

    // A new change drops the undone steps.
    s.editor.setAspect(CanvasAspect.square1x1);
    await tester.pumpAndSettle();
    expect(find.text("Added title 'Summer'"), findsNothing);
    expect(find.text('Shape 1:1'), findsOneWidget);

    // Undo with the button moves the highlight.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(s.editor.historyPosition, 3);

    await tester.tap(find.byTooltip('Close history'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-panel')), findsNothing);
  });

  testWidgets('desktop: Edit > History and Ctrl+Shift+H (Windows menu bar)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    useScreen(tester, desktop);
    final fakes = Fakes(projects: [sampleProject()], missing: const {});
    await tester.pumpWidget(
        fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true));
    await tester.pumpAndSettle();
    final s = sessionOf(tester);
    await edit(tester, s);
    await tester.tap(find.widgetWithText(SubmenuButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-history')));
    await tester.pumpAndSettle();
    expect(s.showHistory.value, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(s.showHistory.value, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone: More > History opens a sheet with the same list',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    final s = sessionOf(tester);
    await edit(tester, s);
    expect(find.byTooltip('History'), findsNothing, reason: 'no room up top');
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsOneWidget);
    expect(find.text('Speed 1.25× on clip 1'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_phone_history');
    await tester.tap(find.text('Opened'));
    await tester.pumpAndSettle();
    expect(s.editor.historyPosition, 0);
    expect(s.project.clips.first.speed, 1);
    expect(s.editor.canRedo, isTrue);

    // A selected clip's More sheet has it too.
    await tester.tapAt(const Offset(10, 60));
    await tester.pumpAndSettle();
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-history')), findsOneWidget);
  });

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$label: processing sound, then ready', (tester) async {
      final fakes = await openEditor(tester, size);
      final s = sessionOf(tester);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Sound');
      await tester.tap(find.text('Clean up sound'));
      await tester.pump();
      // Settling: waiting for the switch / slider to stay put.
      expect(find.text('Preparing sound…'), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      expect(fakes.engine.soundRenders, hasLength(1));
      fakes.engine.soundRenders.single.job.report(0.4);
      await tester.pump();
      expect(find.text('Processing sound… 40%'), findsOneWidget);
      expect(find.byKey(const ValueKey('sound-progress-a')), findsOneWidget);
      expect(find.text('Preparing sound… 40%'), findsOneWidget);
      if (size == desktop) {
        expect(find.text('Sound 40%'), findsOneWidget);
      }
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_sound_processing');

      // Stop and start again.
      await tester.ensureVisible(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(s.sounds.statusOf(s.project.clips.first).state, SoundState.stopped);
      expect(find.text('Sound processing stopped'), findsOneWidget);
      await tester.ensureVisible(find.text('Process sound'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Process sound'));
      await tester.pumpAndSettle();
      expect(fakes.engine.soundRenders, hasLength(2));

      fakes.finishSoundRenders();
      await tester.pumpAndSettle();
      expect(find.text('Sound ready: the preview plays it as the export will.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('preparing-sound')), findsNothing);
      expect(s.playback.playingProcessedSound, endsWith('.flac'));
      await fakes.screenshot(tester, 'editor_${label}_sound_ready');

      // The export reads the processed file.
      expect(s.sounds.readyFiles(s.project).keys, ['a']);
    });
  }
}
