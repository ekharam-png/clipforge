// 1.6 in the editor: the Crop panel and the crop frame on the preview, the
// overlay track (adding, the timeline row, its panels, moving and resizing
// it on the preview, its player), and the menu bar items. Phone and
// desktop sizes; screenshots with --dart-define=SCREENSHOTS=true.

import 'package:clipforge/core/model/picture_layout.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/app_menu.dart';
import 'package:clipforge/ui/editor/acts.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/timeline_view.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

Project now(WidgetTester tester) => sessionOf(tester).project;

const pip = OverlayClip(
  startMs: 1000,
  clip: Clip(
    id: 'o1',
    type: ClipType.video,
    path: '/media/interview.mp4',
    sourceDurationMs: 20000,
    inMs: 0,
    outMs: 4000,
    width: 1280,
    height: 720,
  ),
);

Project withOverlay() => sampleProject().copyWith(overlays: [pip]);

Finder grip(String name) => find.byKey(ValueKey('crop-grip-$name'));

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    final phoneScreen = size == phone;

    testWidgets('crop and position of a clip on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      final s = sessionOf(tester);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      if (phoneScreen) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('more-crop')));
      } else {
        await tester.ensureVisible(find.text('Crop').first);
        await tester.tap(find.text('Crop').first);
      }
      await tester.pumpAndSettle();
      expect(s.cropTarget.value, 'a');
      expect(find.byKey(const ValueKey('crop-frame')), findsOneWidget);
      if (phoneScreen) {
        expect(find.byKey(const ValueKey('crop-sheet')), findsOneWidget);
      }

      // Turn it, then go back to straight: one step each, named.
      await tester.ensureVisible(find.byKey(const ValueKey('rotate-right')));
      await tester.tap(find.byKey(const ValueKey('rotate-right')));
      await tester.pumpAndSettle();
      expect(now(tester).clips.first.framing.rotation, 90);
      expect(s.editor.history.last.label, 'Rotated clip 1');
      await tester.tap(find.byKey(const ValueKey('rotate-left')));
      await tester.pumpAndSettle();
      expect(now(tester).clips.first.framing.rotation, 0);

      // A shape: 9:16 out of the 16:9 picture, held while dragging.
      await tester.ensureVisible(find.byKey(const ValueKey('crop-shape-tall')));
      await tester.tap(find.byKey(const ValueKey('crop-shape-tall')));
      await tester.pumpAndSettle();
      final tall = now(tester).clips.first.framing.crop;
      expect(tall.width * 1920 / (tall.height * 1080), closeTo(9 / 16, 1e-6));
      expect(s.cropRatio.value, closeTo(9 / 16, 1e-9));
      await fakes.screenshot(tester, 'editor_${label}_crop');

      // Drag the frame to the left on the preview: it moves, one step.
      final steps = s.editor.history.length;
      await tester.drag(grip('move'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      final moved = now(tester).clips.first.framing.crop;
      expect(moved.x, 0);
      expect(moved.width, closeTo(tall.width, 1e-9));
      expect(s.editor.history.length, steps + 1);
      expect(s.editor.history.last.label, 'Crop on clip 1');

      // A corner keeps the shape.
      await tester.drag(grip('bottomRight'), const Offset(-40, -40));
      await tester.pumpAndSettle();
      final smaller = now(tester).clips.first.framing.crop;
      expect(smaller.width, lessThan(moved.width));
      expect(smaller.width * 1920 / (smaller.height * 1080),
          closeTo(9 / 16, 1e-6));

      // Free: a side changes only the width.
      await tester.ensureVisible(find.byKey(const ValueKey('crop-shape-free')));
      await tester.tap(find.byKey(const ValueKey('crop-shape-free')));
      await tester.pumpAndSettle();
      await tester.drag(grip('right'), const Offset(50, 0));
      await tester.pumpAndSettle();
      final wider = now(tester).clips.first.framing.crop;
      expect(wider.width, greaterThan(smaller.width));
      expect(wider.height, closeTo(smaller.height, 1e-9));

      // Position, then reset everything.
      await tester.ensureVisible(find.byKey(const ValueKey('reset-crop')));
      await tester.tap(find.byKey(const ValueKey('reset-crop')));
      await tester.pumpAndSettle();
      expect(now(tester).clips.first.framing, Framing.none);
      expect(s.editor.history.last.label,
          'Crop and position reset on clip 1');

      // Leaving the panel takes the frame away.
      if (phoneScreen) {
        await tester.tap(find.byKey(const ValueKey('crop-sheet-done')));
      } else {
        // 1.18: the groups no longer close each other; Crop is closed
        // on its own heading.
        await tester.ensureVisible(sectionHeading('Crop').first);
        await tester.tap(sectionHeading('Crop').first);
      }
      await tester.pumpAndSettle();
      expect(s.cropTarget.value, isNull);
      expect(find.byKey(const ValueKey('crop-frame')), findsNothing);
    });

    testWidgets('adding an overlay and its row on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      fakes.files.media = [const PickedFile('/media/talk.mp4', 'talk.mp4')];
      fakes.engine.infos['/media/talk.mp4'] = const MediaInfo(
          durationMs: 5000,
          width: 1280,
          height: 720,
          hasVideo: true,
          hasAudio: true);
      final s = sessionOf(tester);
      s.playback.seek(2000);
      await tester.pumpAndSettle();
      double mainInTimeline() =>
          tester.getTopLeft(block('clip-a')).dy -
          tester.getTopLeft(find.byType(TimelineView)).dy;
      final mainTop = mainInTimeline();
      if (phoneScreen) {
        await tester.tap(find.byKey(const ValueKey('tool-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overlay (picture-in-picture)'));
      } else {
        await tester.tap(find.text('Overlay'));
      }
      await tester.pumpAndSettle();
      final o = now(tester).overlays.single;
      expect(o.startMs, 2000);
      expect(o.path, '/media/talk.mp4');
      expect(o.layout, OverlayLayout.pip);
      expect(s.selection.value, Selection(ItemKind.overlay, o.id));
      expect(s.editor.history.last.label, 'Added overlay');
      // The row sits above the main track, which moved down.
      final row = block('overlay-${o.id}');
      expect(row, findsOneWidget);
      expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(block('clip-a')).dy));
      expect(mainInTimeline(), closeTo(mainTop + 38, 0.5));
      expect(find.byKey(const ValueKey('overlay-row-header')), findsOneWidget);
      // On the preview, in the bottom right corner.
      final box = find.byKey(ValueKey('preview-overlay-${o.id}'));
      expect(box, findsOneWidget);
      final picture = tester.getRect(find.byType(PreviewView));
      expect(tester.getCenter(box).dx, greaterThan(picture.center.dx));
      await fakes.screenshot(tester, 'editor_${label}_overlay');

      // Its player: the overlay video at the playhead's place in it.
      final players = fakes.backend.videoPlayers;
      expect(players.any((pl) => pl.log.any((l) => l.startsWith('open /media/talk.mp4@0'))),
          isTrue);

      // Delete it: the row goes away.
      if (!phoneScreen) {
        await tester.tap(find.text('Delete'));
      } else {
        await tester.tap(find.text('Delete').last);
      }
      await tester.pumpAndSettle();
      expect(now(tester).overlays, isEmpty);
      expect(find.byKey(const ValueKey('overlay-row-header')), findsNothing);
    });

    testWidgets('overlay layout, moving and resizing on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size, project: withOverlay());
      final s = sessionOf(tester);
      await tester.tap(block('overlay-o1'));
      await tester.pumpAndSettle();
      expect(s.selection.value, const Selection(ItemKind.overlay, 'o1'));
      expect(s.playback.positionMs, 1000);

      // Drag it on the preview: it becomes a free overlay where it is put.
      final box = find.byKey(const ValueKey('preview-overlay-o1'));
      final before = tester.getRect(box);
      await tester.drag(box, const Offset(-60, -30));
      await tester.pumpAndSettle();
      final moved = now(tester).overlays.single;
      expect(moved.layout, OverlayLayout.free);
      final after = tester.getRect(box);
      expect(after.left, closeTo(before.left - 60, 2));
      expect(after.top, closeTo(before.top - 30, 2));
      expect(s.editor.history.last.label, 'Overlay Free position');

      // Its corner makes it bigger.
      await tester.drag(find.byKey(const ValueKey('preview-overlay-resize-o1')),
          const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(now(tester).overlays.single.size, greaterThan(moved.size));
      expect(tester.getRect(box).left, closeTo(after.left, 2));

      // The Layout panel: side by side.
      if (phoneScreen) {
        await tester.tap(find.text('Layout'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(
          find.byKey(const ValueKey('overlay-layout-sideBySide')));
      await tester.tap(find.byKey(const ValueKey('overlay-layout-sideBySide')));
      await tester.pumpAndSettle();
      expect(now(tester).overlays.single.layout, OverlayLayout.sideBySide);
      // The main picture moved into the left half of the frame.
      final region = tester.getRect(find.byKey(const ValueKey('main-region')));
      final frame = tester.getRect(find.byKey(const ValueKey('preview-overlay-o1')));
      expect(region.right, closeTo(frame.left, 1.5));
      expect(find.text('Right'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_overlay_layout');
      await closeSheet(tester, size);

      // Sound, speed and fades.
      if (phoneScreen) {
        await tester.tap(find.text('Sound'));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.text('Sound, speed and fades'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('overlay-mute')));
      await tester.tap(find.byKey(const ValueKey('overlay-mute')));
      await tester.pumpAndSettle();
      expect(now(tester).overlays.single.clip.muted, isTrue);
      expect(s.editor.history.last.label, 'Muted overlay');
      await tester.ensureVisible(find.text('2×'));
      await tester.tap(find.text('2×'));
      await tester.pumpAndSettle();
      expect(now(tester).overlays.single.durationMs, 2000);
      await fakes.screenshot(tester, 'editor_${label}_overlay_sound');
    });

    testWidgets('cropping an overlay on a $label screen', (tester) async {
      await openEditor(tester, size, project: withOverlay());
      final s = sessionOf(tester);
      await tester.tap(block('overlay-o1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Crop').first);
      await tester.tap(find.text('Crop').first);
      await tester.pumpAndSettle();
      expect(s.cropTarget.value, 'o1');
      expect(find.byKey(const ValueKey('crop-frame')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('crop-shape-square')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crop-shape-square')));
      await tester.pumpAndSettle();
      final crop = now(tester).overlays.single.clip.framing.crop;
      expect(crop.width * 1280 / (crop.height * 720), closeTo(1, 1e-6));
      expect(s.editor.history.last.label, 'Crop on overlay');
      // The box of the picture-in-picture takes the cropped shape.
      expect(s.cropTarget.value, 'o1');
    });
  }

  testWidgets('dragging and trimming an overlay on the timeline',
      (tester) async {
    await openEditor(tester, desktop, project: withOverlay());
    final s = sessionOf(tester);
    await tester.tap(block('overlay-o1'));
    await tester.pumpAndSettle();
    // 60 px per second: one second later.
    await tester.drag(block('overlay-o1'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(now(tester).overlays.single.startMs, 2000);
    expect(s.editor.history.last.label, 'Moved overlay');
    // The end handle trims.
    final handle = find.bySemanticsLabel('Trim end');
    await tester.drag(handle, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(now(tester).overlays.single.durationMs, 3000);
    expect(s.editor.history.last.label, 'Trimmed overlay');
  });

  testWidgets('the preview places the clip with its crop like the export',
      (tester) async {
    final p = sampleProject().copyWith(clips: [
      videoClip('a', '/media/beach.mp4', 0, 6000).copyWith(
          framing: const Framing(crop: CropRect(0.5, 0, 0.5, 1))),
    ]);
    await openEditor(tester, desktop, project: p);
    final clip = sessionOf(tester).project.clips.single;
    final canvas = tester.getRect(find.byKey(const ValueKey('main-region')));
    final expected = placeClip(clip, canvas.width, canvas.height);
    // The surface of the front deck is laid out over the WHOLE picture:
    // twice as wide as the cropped part, whose left edge is its middle.
    final surface = find.byKey(const ValueKey('deck 0'));
    expect(surface, findsOneWidget);
    final fitted = tester.getRect(find.descendant(
        of: surface, matching: find.byType(FittedBox)).first);
    expect(fitted.width, closeTo(expected.picture.width * 2, 1));
    expect(fitted.left + fitted.width / 2,
        closeTo(canvas.left + expected.picture.left, 1));
  });

  testWidgets('Clip and Add menus: crop and position, rotate, add overlay',
      (tester) async {
    useScreen(tester, desktop);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final fakes = Fakes(projects: [sampleProject()], missing: const {});
    await tester.pumpWidget(
        fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true));
    await tester.pumpAndSettle();
    final s = sessionOf(tester);
    Future<void> openMenu(String menu) async {
      await tester.tap(find.widgetWithText(SubmenuButton, menu));
      await tester.pumpAndSettle();
    }

    Future<void> openEdit() => openMenu('Clip');

    MenuItemButton item(String key) =>
        tester.widget<MenuItemButton>(find.byKey(ValueKey(key)));
    await openEdit();
    expect(item('menu-crop').onPressed, isNull);
    // Greyed out, and it says why.
    expect(find.text('Crop and position… (select a clip or an overlay)'),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await openMenu('Add');
    expect(item('menu-add-overlay').onPressed, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openEdit();
    await tester.tap(find.byKey(const ValueKey('menu-rotate')));
    await tester.pumpAndSettle();
    expect(s.project.clips.first.framing.rotation, 90);
    await openEdit();
    await tester.tap(find.byKey(const ValueKey('menu-crop')));
    await tester.pumpAndSettle();
    expect(s.openTool.value, ClipTool.crop);
    expect(s.cropTarget.value, 'a');
    debugDefaultTargetPlatformOverride = null;
  });

  test('macOS menu: the same items, enabled by the editor', () {
    var crops = 0;
    ActionEntry e(Act a, {String? reason, VoidCallback? run}) => ActionEntry(
        act: a,
        label: actLabel(a),
        icon: actIcon(a),
        reason: reason,
        onTap: reason == null ? (run ?? () {}) : null);
    final menus = buildAppMenus(EditorMenuActions(entries: {
      Act.crop: e(Act.crop, run: () => crops++),
      Act.rotateRight: e(Act.rotateRight),
      Act.addOverlay: e(Act.addOverlay, reason: 'add a video first'),
    }));
    List<PlatformMenuItem> itemsOf(String menu) {
      final m =
          menus.whereType<PlatformMenu>().firstWhere((m) => m.label == menu);
      return [
        for (final g in m.menus)
          if (g is PlatformMenuItemGroup)
            ...g.members.whereType<PlatformMenuItem>()
          else
            g,
      ];
    }

    PlatformMenuItem named(String menu, String l) =>
        itemsOf(menu).firstWhere((i) => i.label == l);
    expect(named('Clip', 'Crop and position…').onSelected, isNotNull);
    expect(named('Clip', 'Rotate right').onSelected, isNotNull);
    // Greyed out, and the label says why.
    expect(
        named('Add', 'Overlay video or photo… (add a video first)').onSelected,
        isNull);
    named('Clip', 'Crop and position…').onSelected!();
    expect(crops, 1);
  });

  testWidgets('timeline height grows by one row only with overlays',
      (tester) async {
    await openEditor(tester, desktop);
    final plain = tester.getSize(find.byType(TimelineView)).height;
    await tester.pumpWidget(const SizedBox());
    await openEditor(tester, desktop, project: withOverlay());
    final more = tester.getSize(find.byType(TimelineView)).height;
    expect(more - plain, closeTo(38, 0.5));
  });
}
