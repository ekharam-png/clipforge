// 1.17 "select a part" in the editor: on a computer the I / O keys, the
// strip under the ruler, Shift on the ruler, the handles, double-click,
// the bar with its actions, the tick boxes of the rows and the reasons;
// on a phone "Select part", the handles, the bar with the nudge arrows
// and the Actions sheet. Also Q / W (trim, which I / O did before), Esc,
// the Quiet parts list, and "Add from a folder path…".

import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/action_sheets.dart';
import 'package:clipforge/ui/editor/add_from_path.dart';
import 'package:clipforge/ui/editor/editor_actions.dart';
import 'package:clipforge/ui/editor/part_actions.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/timeline_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const desk = Size(1280, 800);
const phone = Size(360, 760);

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// A place on the timeline: [ms] at the default zoom, [y] from its top
/// (10 = the ruler, 34 = the strip under it on a computer).
Offset at(WidgetTester tester, int ms, double y) =>
    timelineOrigin(tester) + Offset(28 + ms * 0.06, y);

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> dragFromTo(WidgetTester tester, Offset from, Offset to,
    {int steps = 6}) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  group('computer', () {
    testWidgets('I and O mark the part; the bar, the band and the tick boxes '
        'appear; Esc clears it; Q and W trim the clip', (tester) async {
      final fakes = await openEditor(tester, desk);
      final s = sessionOf(tester);
      expect(key('part-strip'), findsOneWidget);
      expect(find.text('Drag here to select a part'), findsOneWidget);
      expect(key('part-bar'), findsNothing);
      expect(key('part-row-video'), findsNothing);

      await seekTo(tester, 2000);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      // I alone: from the playhead to the end of the video.
      expect(s.part.value, const TimelinePart(2000, 18000));
      await seekTo(tester, 5000);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      expect(s.part.value, const TimelinePart(2000, 5000));
      expect(s.project.clips.first.inMs, 0, reason: 'I and O no longer trim');
      expect(s.editor.canUndo, isFalse, reason: 'a selection is not an edit');

      expect(key('part-band'), findsOneWidget);
      expect(key('part-handle-start'), findsOneWidget);
      expect(key('part-handle-end'), findsOneWidget);
      expect(find.text('Drag here to select a part'), findsNothing);
      expect(tester.widget<Text>(key('part-length')).data,
          contains('0:02.0 – 0:05.0'));
      expect(tester.widget<Text>(key('part-rows-label')).data,
          'Rows: Everything');
      for (final row in ['video', 'music', 'titles']) {
        expect(key('part-row-$row'), findsOneWidget, reason: row);
      }
      for (final a in ['partCutOut', 'partDelete', 'partSilence', 'partLower',
        'partSpeed', 'partClean']) {
        expect(key('part-$a'), findsOneWidget, reason: a);
      }
      await fakes.screenshot(tester, 'editor_desktop_part');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(s.part.value, isNull);
      expect(key('part-bar'), findsNothing);
      expect(key('part-row-video'), findsNothing);

      // Q: the clip under the playhead starts there (what I did until 1.16).
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pumpAndSettle();
      expect(s.project.clips.first.inMs, 5000);
      expect(s.editor.history.last.label, 'Start of clip 1 at playhead');
      s.editor.undo();
      await tester.pumpAndSettle();
      await seekTo(tester, 4000);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      expect(s.project.clips.first.outMs, 4000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drag along the strip (it snaps to a cut); the ruler still '
        'moves the playhead; Shift on the ruler selects', (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      // From 2 s to a little before the cut at 6 s: it snaps onto the cut.
      await dragFromTo(tester, at(tester, 2000, 34), at(tester, 5950, 34));
      expect(s.part.value, const TimelinePart(2000, 6000));
      // The band keeps its place when the timeline is zoomed.
      final before = tester.getTopLeft(key('part-band')).dx;
      s.setZoom(120);
      await tester.pumpAndSettle();
      expect(s.part.value, const TimelinePart(2000, 6000));
      expect(tester.getTopLeft(key('part-band')).dx, greaterThan(before));
      s.setZoom(60);
      await tester.pumpAndSettle();

      // A plain click and drag on the ruler: the playhead, as before.
      await seekTo(tester, 9000);
      expect(s.playback.positionMs, closeTo(9000, 20));
      expect(s.part.value, const TimelinePart(2000, 6000));
      await dragFromTo(tester, at(tester, 3000, 10), at(tester, 4000, 10));
      expect(s.playback.positionMs, closeTo(4000, 40));
      expect(s.part.value, const TimelinePart(2000, 6000));

      // Shift+click stretches the nearer edge to there.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(at(tester, 8000, 10));
      await tester.pumpAndSettle();
      expect(s.part.value!.startMs, 2000);
      expect(s.part.value!.endMs, closeTo(8000, 20));
      // Shift+drag on the ruler marks a new part.
      await dragFromTo(tester, at(tester, 10000, 10), at(tester, 12000, 10));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(s.part.value!.startMs, closeTo(10000, 20));
      expect(s.part.value!.endMs, closeTo(12000, 20));

      // A click on an empty place of the timeline clears it.
      final view = find.byType(TimelineView);
      await tester.tapAt(tester.getBottomRight(view) - const Offset(30, 4));
      await tester.pumpAndSettle();
      expect(s.part.value, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the handles change the part; a double-click selects a '
        'clip\'s time', (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();
      final end = tester.getCenter(key('part-handle-end'));
      await dragFromTo(tester, end, end + const Offset(90, 0));
      expect(s.part.value!.startMs, 2000);
      expect(s.part.value!.endMs, closeTo(6500, 60));
      final start = tester.getCenter(key('part-handle-start'));
      await dragFromTo(tester, start, start + const Offset(-60, 0));
      // It snapped to the music's start at 1 s.
      expect(s.part.value!.startMs, 1000);
      s.clearPart();
      await tester.pumpAndSettle();

      // One click selects the clip; a second right after selects its time.
      await tester.tap(block('clip-d'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(s.part.value, isNull);
      expect(s.selection.value?.id, 'd');
      await tester.tap(block('clip-d'));
      await tester.pumpAndSettle();
      expect(s.part.value, const TimelinePart(14000, 18000));
      expect(tester.takeException(), isNull);
    });

    testWidgets('rows: tick boxes, Alt+click for only one, Cut out says why, '
        'Silence on one row is one named step', (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();
      bool enabled(String a) =>
          tester.widget<TextButton>(key('part-$a')).onPressed != null;
      expect(enabled('partCutOut'), isTrue);
      expect(key('part-rows-note'), findsNothing);

      // Untick the titles: Cut out is off and the bar says why.
      await tester.tap(key('part-row-titles'));
      await tester.pumpAndSettle();
      expect(s.partRows.value, {'video', 'music'});
      expect(tester.widget<Text>(key('part-rows-label')).data,
          'Rows: 2 of 3 rows');
      expect(enabled('partCutOut'), isFalse);
      expect(find.textContaining('lips and voice would no longer match'),
          findsOneWidget);
      expect(enabled('partSilence'), isTrue);

      // Alt+click: only the music.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tap(key('part-row-music'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(s.partRows.value, {'music'});
      expect(tester.widget<Text>(key('part-rows-label')).data,
          'Rows: Only Music');
      // Speed needs the video row: its tooltip says so.
      expect(enabled('partSpeed'), isFalse);
      expect(EditorActions(s).whyNot(Act.partSpeed), 'tick the video row');

      await tester.tap(key('part-partSilence'));
      await tester.pumpAndSettle();
      final p = s.project;
      // The music starts at 1 s: 2 s..5 s of the timeline is 1 s..4 s of it.
      expect(p.audio.single.quiet, [const QuietRange(1000, 4000)]);
      expect(p.clips.every((c) => c.quiet.isEmpty), isTrue);
      expect(s.editor.history.last.label, 'Silenced a part (3.0 s) on Music');
      expect(find.textContaining('Silenced 3.0 s on Music'), findsOneWidget);
      expect(s.part.value, const TimelinePart(2000, 5000),
          reason: 'the part and its rows stay for the next action');
      expect(s.partRows.value, {'music'});
      s.editor.undo();
      await tester.pumpAndSettle();
      expect(s.project.audio.single.quiet, isEmpty);

      // Everything again through the bar's Rows menu.
      await tester.tap(key('part-rows'));
      await tester.pumpAndSettle();
      await tester.tap(key('part-rows-all'));
      await tester.pumpAndSettle();
      expect(s.partRows.value, isNull);
      // Clearing the part forgets the rows.
      s.partRows.value = {'video'};
      s.clearPart();
      await tester.pumpAndSettle();
      expect(s.partRows.value, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pointing at an action shows which rows it cannot change',
        (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(key('part-partSilence')));
      await tester.pumpAndSettle();
      expect(s.partPreview.value, PartAction.silence);
      // Titles have no sound: its box is crossed out.
      final titles = find.descendant(
          of: key('part-row-titles'), matching: find.byType(Icon));
      expect(tester.widget<Icon>(titles).icon,
          Icons.disabled_by_default_outlined);
      final video = find.descendant(
          of: key('part-row-video'), matching: find.byType(Icon));
      expect(tester.widget<Icon>(video).icon, Icons.check_box);
      expect(partActionSummary(s, PartAction.silence),
          'Changes Video, Music. Not Titles and captions (titles have no sound).');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(s.partPreview.value, isNull);
    });

    testWidgets('Cut out, Lower volume and Speed from the bar; the Quiet '
        'parts list', (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      // Lower by 18 dB on every row that has sound.
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();
      await tester.tap(key('part-partLower'));
      await tester.pumpAndSettle();
      expect(key('part-lower-dialog'), findsOneWidget);
      await tester.tap(key('part-lower-18'));
      await tester.pumpAndSettle();
      await tester.tap(key('part-lower-go'));
      await tester.pumpAndSettle();
      var p = s.project;
      expect(p.clips.first.quiet.single.level, closeTo(0.126, 0.001));
      expect(p.audio.single.quiet.single.level, closeTo(0.126, 0.001));
      expect(s.editor.history.last.label,
          'Lowered a part (3.0 s) to −18 dB on Video, Music');

      // The clip's Sound settings list it; Remove gives the sound back.
      s.clearPart();
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      s.openTool.value = ClipTool.sound;
      await tester.pumpAndSettle();
      expect(key('quiet-parts-a'), findsOneWidget);
      expect(find.textContaining('0:02.0 – 0:05.0 · −18 dB'),
          findsOneWidget);
      await tester.ensureVisible(key('quiet-part-2000'));
      await tester.tap(key('quiet-part-2000'));
      await tester.pumpAndSettle();
      expect(s.part.value, const TimelinePart(2000, 5000));
      await tester.tap(key('quiet-remove-2000'));
      await tester.pumpAndSettle();
      expect(s.project.clips.first.quiet, isEmpty);
      expect(key('quiet-parts-a'), findsNothing);

      // Speed: half speed for 2 s..4 s of clip a.
      s.clearSelection();
      s.setPart(2000, 4000);
      await tester.pumpAndSettle();
      await tester.tap(key('part-partSpeed'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('part-speed-result')).data,
          contains('this part will take 4.0'));
      // 0.5x: the sound stays; 0.25x ticks "mute" by itself.
      expect(tester.widget<CheckboxListTile>(key('part-speed-mute')).value,
          isFalse);
      await tester.tap(key('part-speed-0.25'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(key('part-speed-mute')).value,
          isTrue);
      await tester.tap(key('part-speed-0.5'));
      await tester.pumpAndSettle();
      await tester.tap(key('part-speed-go'));
      await tester.pumpAndSettle();
      p = s.project;
      expect(p.clips.take(3).map((c) => c.speed), [1.0, 0.5, 1.0]);
      expect(s.part.value, const TimelinePart(2000, 6000),
          reason: 'the part follows what it became');
      expect(find.textContaining('Music and other sound stayed'),
          findsOneWidget);

      // Cut out: gone from everything, the part with it, and in the log.
      final length = p.durationMs;
      await tester.tap(key('part-partCutOut'));
      await tester.pumpAndSettle();
      p = s.project;
      expect(p.durationMs, length - 4000);
      expect(p.autoCuts.single.kind, 'part');
      expect(s.part.value, isNull);
      expect(s.editor.history.last.label, 'Cut out a part (4.0 s)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a right-click inside the part: its actions; the Part menu '
        'entries say why they cannot be used', (tester) async {
      await openEditor(tester, desk);
      final s = sessionOf(tester);
      final actions = EditorActions(s);
      expect(actions.whyNot(Act.partSilence), 'select a part first');
      expect(actions.whyNot(Act.clearPart), 'no part is selected');
      expect(actions.whyNot(Act.selectPart), isNull);
      expect(actions.whyNot(Act.partBetweenMarkers), 'no good moment markers yet');
      expect(actions.whyNot(Act.onlyWhenSpeaking),
          'add a voice on a speech track first');
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();
      await tester.tapAt(at(tester, 3000, 34), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(key('context-partCutOut'), findsOneWidget);
      expect(key('context-partSilence'), findsOneWidget);
      expect(key('context-clearPart'), findsOneWidget);
      await tester.tap(key('context-clearPart'));
      await tester.pumpAndSettle();
      expect(s.part.value, isNull);
    });
  });

  group('phone', () {
    testWidgets('Select part: two handles, the bar with nudge arrows, the '
        'Actions sheet with the rows', (tester) async {
      final fakes = await openEditor(tester, phone);
      final s = sessionOf(tester);
      // No strip on a phone (a finger scrolls the timeline).
      expect(key('part-strip'), findsNothing);
      await seekTo(tester, 2000);
      await tapMore(tester, 'more-selectPart');
      // Five seconds from the playhead.
      expect(s.part.value, const TimelinePart(2000, 7000));
      expect(key('part-bar'), findsOneWidget);
      expect(key('part-handle-start'), findsOneWidget);
      expect(tester.getSize(key('part-handle-start')).width,
          greaterThanOrEqualTo(28));
      expect(tester.widget<Text>(key('part-start-time')).data, '0:02.0');
      expect(tester.widget<Text>(key('part-end-time')).data, '0:07.0');
      for (final k in ['part-start-earlier', 'part-start-later',
        'part-end-earlier', 'part-end-later', 'part-step', 'part-actions',
        'part-clear']) {
        final size = tester.getSize(key(k));
        expect(size.width, greaterThanOrEqualTo(48), reason: k);
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
      }
      await fakes.screenshot(tester, 'phone_part');

      // One frame (the clip has no known frame rate: 33 ms), then 0.1 s.
      await tester.tap(key('part-start-later'));
      await tester.pumpAndSettle();
      expect(s.part.value!.startMs, 2033);
      await tester.tap(key('part-step'));
      await tester.pumpAndSettle();
      expect(find.text('Step 0.1 s'), findsOneWidget);
      await tester.tap(key('part-end-earlier'));
      await tester.pumpAndSettle();
      expect(s.part.value!.endMs, 6900);
      await tester.tap(key('part-start-earlier'));
      await tester.pumpAndSettle();
      expect(s.part.value!.startMs, 1933);

      // Dragging a handle with a finger moves the edge, not the timeline.
      final handle = tester.getCenter(key('part-handle-start'));
      await tester.dragFrom(handle, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(s.part.value!.startMs, greaterThan(2400));
      expect(s.part.value!.endMs, 6900);
      s.setPart(2000, 5000);
      await tester.pumpAndSettle();

      // Actions: the rows first, then what can be done.
      await tester.tap(key('part-actions'));
      await tester.pumpAndSettle();
      expect(key('part-sheet'), findsOneWidget);
      for (final row in ['video', 'music', 'titles']) {
        expect(key('part-sheet-row-$row'), findsOneWidget, reason: row);
      }
      await fakes.screenshot(tester, 'phone_part_sheet');
      await tester.tap(key('part-sheet-only-music'));
      await tester.pumpAndSettle();
      expect(s.partRows.value, {'music'});
      // Cut out is off, and its line says what to use instead.
      final cut = tester.widget<ListTile>(key('part-sheet-partCutOut'));
      expect(cut.enabled, isFalse);
      expect(find.textContaining('Needs every row'), findsOneWidget);
      await tester.ensureVisible(key('part-sheet-partSilence'));
      await tester.pumpAndSettle();
      await tester.tap(key('part-sheet-partSilence'));
      await tester.pumpAndSettle();
      expect(key('part-sheet'), findsNothing);
      expect(s.project.audio.single.quiet, [const QuietRange(1000, 4000)]);

      await tester.tap(key('part-clear'));
      await tester.pumpAndSettle();
      expect(key('part-bar'), findsNothing);
      expect(key('part-handle-start'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Select part is in the project menu and in the list of a '
        'long press; an overlay has More; the Add list has subtitle files',
        (tester) async {
      await openEditor(tester, phone);
      final s = sessionOf(tester);
      await tapProjectMenu(tester, 'Select part');
      expect(s.part.value, isNotNull);
      s.clearPart();
      await tester.pumpAndSettle();
      expect(contextActs(const TimelineTarget.empty(0), s),
          contains(Act.selectPart));
      expect(
          contextActs(const TimelineTarget.item(ItemKind.clip, 'a'), s),
          contains(Act.partOfItem));
      expect(kAddActs, contains(Act.importSubtitles));
      // With a clip selected: "Select this clip's time".
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await tapMore(tester, 'more-partOfItem');
      expect(s.part.value, const TimelinePart(0, 6000));
      expect(moreGroups(s).map((g) => g.$1), contains('Part'));
    });
  });

  group('add from a folder path', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('clipforge_path_');
      for (final name in ['b.mp4', 'a.MOV', 'song.mp3', 'notes.txt', 'x.srt']) {
        File('${dir.path}/$name').writeAsBytesSync(const [1]);
      }
      Directory('${dir.path}/inner').createSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a folder: its media by name; a file; quotes; what is not there',
        () {
      final look = lookAtPath('"${dir.path}"');
      expect(look.problem, isNull);
      expect(look.folder, dir.path);
      expect(look.files.map((f) => f.split('/').last),
          ['a.MOV', 'b.mp4', 'song.mp3', 'x.srt']);
      expect(look.left, 1);
      expect(lookAtPath('${dir.path}/b.mp4').files, ['${dir.path}/b.mp4']);
      expect(lookAtPath('${dir.path}/notes.txt').problem,
          contains('not a video, photo, sound or subtitle'));
      expect(lookAtPath('${dir.path}/nope').problem,
          'There is no file or folder at that path.');
      expect(lookAtPath('  ').problem, contains('Type or paste'));
      expect(cleanTypedPath("'/a b/c.mp4'"), '/a b/c.mp4');
      expect(cleanTypedPath('file:///a%20b/c.mp4'), '/a b/c.mp4');
    });

    testWidgets('the window: paste a path, tick, Add', (tester) async {
      final fakes = await openEditor(tester, desk);
      final s = sessionOf(tester);
      fakes.engine.infos['${dir.path}/a.MOV'] = const MediaInfo(
          durationMs: 4000, width: 1920, height: 1080, hasVideo: true,
          hasAudio: true);
      expect(EditorActions(s).whyNot(Act.addFromPath), isNull);
      final context = tester.element(find.byType(TimelineView));
      EditorActions(s).run(context, Act.addFromPath);
      await tester.pumpAndSettle();
      expect(key('add-path-dialog'), findsOneWidget);
      expect(tester.widget<FilledButton>(key('add-path-go')).onPressed, isNull);
      await tester.enterText(key('add-path-field'), dir.path);
      await tester.tap(key('add-path-look'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('add-path-count')).data,
          '4 media files in this folder (1 other left out)');
      expect(find.text('a.MOV'), findsOneWidget);
      expect(find.text('Add 4 files'), findsOneWidget);
      // Untick all but the first video.
      for (final i in [1, 2, 3]) {
        await tester.tap(key('add-path-item-$i'));
        await tester.pump();
      }
      expect(find.text('Add'), findsOneWidget);
      await tester.tap(key('add-path-go'));
      await tester.pumpAndSettle();
      expect(key('add-path-dialog'), findsNothing);
      expect(s.project.clips.any((c) => c.path.endsWith('a.MOV')), isTrue);
      // A wrong path says so and adds nothing.
      EditorActions(s).run(context, Act.addFromPath);
      await tester.pumpAndSettle();
      await tester.enterText(key('add-path-field'), '${dir.path}/nope');
      await tester.tap(key('add-path-look'));
      await tester.pumpAndSettle();
      expect(key('add-path-problem'), findsOneWidget);
      expect(tester.widget<FilledButton>(key('add-path-go')).onPressed, isNull);
    });
  });
}
