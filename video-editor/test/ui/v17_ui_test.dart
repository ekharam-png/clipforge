// 1.7 in the editor: colour filters and warmth, fades (project and clip),
// text styles, sound-only export and frame rate, the keyboard (duplicate,
// copy / paste settings, I / O, J / K / L, zoom), snapping setting and the
// new menu items. Phone and desktop sizes; screenshots with
// --dart-define=SCREENSHOTS=true.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

Future<void> dragSlider(WidgetTester tester, Key key, double dx) async {
  final f = find.descendant(of: find.byKey(key), matching: find.byType(Slider));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.drag(f, Offset(dx, 0));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('filters and warmth on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Look');
      await tapKey(tester, 'filter-vintage');
      await dragSlider(tester, const ValueKey('warmth'), 60);
      await tester.ensureVisible(find.byKey(const ValueKey('look-filters')));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_filters');
      final c = sessionOf(tester).project.clips.first;
      expect(c.filter, LookFilter.vintage);
      expect(c.warmth, greaterThan(0));
      // Reset look takes both back, as one step.
      await tester.ensureVisible(find.text('Reset look'));
      await tester.tap(find.text('Reset look'));
      await tester.pumpAndSettle();
      final r = sessionOf(tester).project.clips.first;
      expect([r.filter, r.warmth], [LookFilter.none, 0]);
      expect(sessionOf(tester).editor.history.last.label, 'Reset look on clip 1');
    });

    testWidgets('fades of the video and of a clip on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      final s = sessionOf(tester);
      if (size == phone) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('more-fades')));
        await tester.pumpAndSettle();
      }
      await dragSlider(tester, const ValueKey('project-fade-in'), 80);
      await dragSlider(tester, const ValueKey('project-fade-out'), 40);
      await fakes.screenshot(tester, 'editor_${label}_fades');
      expect(s.project.fadeInMs, greaterThan(0));
      expect(s.project.fadeOutMs, greaterThan(0));
      // At the very start the preview is black.
      s.playback.seek(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-fade')), findsOneWidget);
      await closeSheet(tester, size);

      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Transition and fades');
      expect(find.textContaining('use Fade in'), findsOneWidget);
      await dragSlider(tester, const ValueKey('clip-fade-in'), 60);
      await fakes.screenshot(tester, 'editor_${label}_clip_fades');
      expect(s.project.clips.first.fadeInMs, greaterThan(0));
      expect(s.editor.history.last.label, 'Fade in on clip 1');
    });

    testWidgets('text styles on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      final s = sessionOf(tester);
      await tester.tap(block('title-t1'));
      await tester.pumpAndSettle();
      if (size == phone) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      await tapKey(tester, 'title-style-outline');
      await tapKey(tester, 'title-font-handwritten');
      await tapKey(tester, 'title-position-top');
      await tester.ensureVisible(find.byKey(const ValueKey('title-align')));
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('title-align')), matching: find.text('Left')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('title-anim-in')));
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('title-anim-in')), matching: find.text('Pop')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('title-anim-out')), matching: find.text('Fade')));
      await tester.pumpAndSettle();
      s.playback.seek(1000);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('title-styles')));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_text_styles');
      final t = s.project.titles.single;
      expect([t.font, t.outline, t.y, t.align, t.x, t.animIn, t.animOut], [
        TitleFont.handwritten, true, 0.1, TitleAlign.left, 0.0,
        TitleAnimation.pop, TitleAnimation.fade,
      ]);
      // The preview shows it in its own font.
      final text = tester.widgetList<Text>(find.text('Summer 2026')).first;
      expect(text.style?.fontFamily, titleFontFamily(TitleFont.handwritten, true));
      // At its very start (pop) it is still invisible.
      s.playback.seek(0);
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<Opacity>(find.ancestor(
                  of: find.text('Summer 2026').first, matching: find.byType(Opacity)))
              .any((o) => o.opacity == 0),
          isTrue);
    });

    testWidgets('sound only and frame rate in the Export window on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size, missingFiles: const {});
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Export video'), findsOneWidget);
      // (The window scrolls: "Where is it going?" is above since 1.14.)
      await tester.ensureVisible(find.text('25'));
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'export_${label}_frame_rate');
      await tester.tap(find.text('Sound MP3'));
      await tester.pumpAndSettle();
      expect(find.text('Export sound'), findsOneWidget);
      expect(find.text('Full quality'), findsNothing);
      await fakes.screenshot(tester, 'export_${label}_sound_only');
      await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
      await tester.pump();
      await tester.pump();
      expect(fakes.engine.lastOptions!.format, ExportFormat.mp3);
      expect(fakes.engine.lastOptions!.fps, 25);
      fakes.engine.jobs.single.finish('/out/movie.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Sound saved'), findsOneWidget);
      if (!fakes.files.canChooseSaveLocation) {
        expect(find.byKey(const ValueKey('export-share-sound')), findsOneWidget);
      }
    });

    testWidgets('duplicate and copy settings from More / the side panel on a $label screen',
        (tester) async {
      await openEditor(tester, size);
      final s = sessionOf(tester);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      if (size == phone) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('more-duplicate')));
      } else {
        await tester.tap(find.text('Duplicate'));
      }
      await tester.pumpAndSettle();
      expect(s.project.clips, hasLength(5));
      expect(s.project.clips[1].path, '/media/beach.mp4');
      expect(s.selectedClip?.id, s.project.clips[1].id);
    });
  }

  testWidgets('keyboard: duplicate, copy / paste settings, I / O, zoom, J / K',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    s.editor.setClipFilter('a', LookFilter.cool);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    Future<void> ctrl(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await ctrl(LogicalKeyboardKey.keyD);
    expect(s.project.clips, hasLength(5));
    expect(s.editor.history.last.label, 'Duplicated clip 1');
    await ctrl(LogicalKeyboardKey.keyC, shift: true);
    expect(s.copiedSettings.value, isNotNull);
    await tester.tap(block('clip-c'));
    await tester.pumpAndSettle();
    await ctrl(LogicalKeyboardKey.keyV, shift: true);
    expect(s.project.clips.firstWhere((c) => c.id == 'c').filter, LookFilter.cool);
    expect(s.editor.history.last.label, startsWith('Pasted settings on clip'));

    // I: the first clip starts at the playhead (1 s in).
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    s.playback.seek(1000);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(s.project.clips.first.inMs, 1000);
    expect(s.editor.history.last.label, 'Start of clip 1 at playhead');
    s.playback.seek(2000);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    expect(s.project.clips.first.outMs, 3000);

    final zoom = s.zoom.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    expect(s.zoom.value, greaterThan(zoom));
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    expect(s.zoom.value, lessThan(zoom));

    // The arrow steps one frame of the clip: 25 fps = 40 ms.
    s.editor.setProbeData('/media/beach.mp4', frameRate: 25);
    s.playback.seek(500);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(s.playback.positionMs, 540);
    expect(frameStepFor(s), 40);

    // J goes backwards in steps until K.
    s.playback.seek(1500);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.playback.positionMs, lessThan(1500));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    final stopped = s.playback.positionMs;
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.playback.positionMs, stopped);
  });

  testWidgets('menus: duplicate, paste settings, snapping (Linux / Windows bar)',
      (tester) async {
    useScreen(tester, desktop);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final fakes = Fakes(projects: [sampleProject()], missing: const {});
    await tester.pumpWidget(
        fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true));
    await tester.pumpAndSettle();
    final s = sessionOf(tester);
    MenuItemButton item(String key) =>
        tester.widget<MenuItemButton>(find.byKey(ValueKey(key)));
    Future<void> open(String menu) async {
      await tester.tap(find.widgetWithText(SubmenuButton, menu));
      await tester.pumpAndSettle();
    }

    await open('Edit');
    expect(item('menu-duplicate').onPressed, isNull);
    expect(item('menu-paste-settings').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await open('Edit');
    await tester.tap(find.byKey(const ValueKey('menu-copy-settings')));
    await tester.pumpAndSettle();
    await open('Edit');
    expect(item('menu-paste-settings').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
    await tester.pumpAndSettle();
    expect(s.project.clips, hasLength(5));

    await open('Playback');
    await tester.tap(find.byKey(const ValueKey('menu-snapping')));
    await tester.pumpAndSettle();
    expect(s.snapping.value, isFalse);
    expect(await fakes.prefs.flag(kSnappingOffFlag), isTrue);
    await open('Help');
    expect(item('menu-shortcuts').onPressed, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
