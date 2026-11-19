import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/clip_actions.dart';
import 'package:clipforge/ui/editor/clip_panels.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';
import 'fakes.dart';

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back to projects'));
  await tester.pumpAndSettle();
}

Future<void> undo(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Undo'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('speed changes the length on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      final before = tester.getSize(block('clip-a')).width;

      await openClipTool(tester, size, 'Speed');
      expect(find.text('Length 6.0 s'), findsOneWidget);
      await tester.tap(find.text('2×'));
      await tester.pumpAndSettle();
      expect(find.text('Length 3.0 s (6.0 s at normal speed)'),
          findsOneWidget);
      expect(find.textContaining('/ 0:15.0'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_speed');
      await closeSheet(tester, size);

      // The block is half as wide and carries a speed badge.
      expect(tester.getSize(block('clip-a')).width, closeTo(before / 2, 0.01));
      expect(
          find.descendant(of: block('clip-a'), matching: find.text('2×')),
          findsOneWidget);

      // The slider is one undo step however far it is dragged.
      await openClipTool(tester, size, 'Speed');
      await tester.drag(find.byType(Slider).first, const Offset(-80, 0));
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      await back(tester);
      final slow = saved(fakes).clips.first.speed;
      expect(slow, lessThan(2));
      expect(saved(fakes).clips.first.durationMs, (6000 / slow).round());
    });

    testWidgets('look sliders, reset and fit on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Look');
      expect(
          tester
              .widget<TextButton>(find.ancestor(
                  of: find.text('Reset look'),
                  matching: find.byWidgetPredicate((w) => w is TextButton)))
              .onPressed,
          isNull);

      final sliders = find.byType(Slider);
      // Warmth, brightness, contrast, saturation, zoom.
      expect(sliders, findsNWidgets(5));
      await tester.ensureVisible(sliders.at(1));
      await tester.drag(sliders.at(1), const Offset(60, 0));
      await tester.ensureVisible(sliders.at(3));
      await tester.drag(sliders.at(3), const Offset(-60, 0));
      await tester.ensureVisible(sliders.at(4));
      await tester.drag(sliders.at(4), const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fill'));
      await tester.tap(find.text('Fill'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_look');

      var clip = fakes.store.projects['p1']!.clips.first;
      await closeSheet(tester, size);
      await back(tester);
      clip = saved(fakes).clips.first;
      expect(clip.brightness, greaterThan(0));
      expect(clip.contrast, 0);
      expect(clip.saturation, lessThan(0));
      expect(clip.zoom, greaterThan(1));
      expect(clip.fit, FitMode.fill);
    });

    testWidgets('reset look is one undo step on a $label screen',
        (tester) async {
      final project = sampleProject();
      final fakes = await openEditor(tester, size,
          project: project.copyWith(clips: [
            project.clips.first
                .copyWith(brightness: 0.4, saturation: -0.5, zoom: 2),
            ...project.clips.skip(1),
          ]));
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Look');
      await tester.ensureVisible(find.text('Reset look'));
      await tester.tap(find.text('Reset look'));
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      await undo(tester);
      expect(undoEnabled(tester), isFalse);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await back(tester);
      final clip = saved(fakes).clips.first;
      expect([clip.brightness, clip.saturation, clip.zoom], [0, 0, 1]);
    });

    testWidgets('sound: clean up and remove silences on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      // Two gaps inside the clip, one outside its trimmed range (0..6 s).
      fakes.engine.silences['/media/beach.mp4'] = const [
        (startMs: 1000, endMs: 2500),
        (startMs: 4000, endMs: 5000),
        (startMs: 9000, endMs: 12000),
      ];
      fakes.engine.silenceGate = Completer<void>();
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Sound');
      expect(find.textContaining('processed in the background'), findsOneWidget);
      expect(find.byKey(const ValueKey('sound-badge-a')), findsNothing);
      expect(find.text('Hear a sample'), findsNothing);
      await tester.tap(find.text('Clean up sound'));
      await tester.pump();
      // Visible confirmation: a message and a badge on the clip.
      expect(find.text('Clean up sound is on for this clip.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sound-badge-a')), findsOneWidget);
      // The sound is processed in the background (here: at once).
      expect(fakes.engine.soundRenders, hasLength(1));
      fakes.finishSoundRenders();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sound-progress-a')), findsNothing);
      expect(find.text('Hear a sample'), findsOneWidget);
      expect(find.text('Hear original'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_sound');

      await tester.ensureVisible(find.text('Remove silences'));
      await tester.tap(find.text('Remove silences'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Listening for quiet parts…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(fakes.engine.silenceRequests, ['/media/beach.mp4']);

      fakes.engine.silenceGate!.complete();
      await tester.pumpAndSettle();
      // 1.5 s and 1.0 s of silence, less 0.15 s kept on each side.
      expect(find.text('Found 2 silent gaps (1.9 s in total).'), findsOneWidget);
      expect(find.textContaining('from 6.0 s to 4.1 s'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_silences');
      await tester.tap(find.text('Remove 2 gaps'));
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      expect(clipBlocks(), findsNWidgets(6));
      expect(find.textContaining('/ 0:16.1'), findsOneWidget);

      // Clean up + removal are two steps; the removal alone is one.
      await undo(tester);
      expect(clipBlocks(), findsNWidgets(4));
      expect(find.textContaining('/ 0:18.0'), findsOneWidget);
      expect(undoEnabled(tester), isTrue);
      await undo(tester);
      expect(undoEnabled(tester), isFalse);
      await tester.tap(find.byTooltip('Redo'));
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();

      await back(tester);
      final p = saved(fakes);
      expect(p.clips, hasLength(6));
      expect([for (final c in p.clips.take(3)) (c.inMs, c.outMs)],
          [(0, 1150), (2350, 4150), (4850, 6000)]);
      expect(p.clips.first.denoise, isTrue);
    });

    testWidgets('sound: voice focus and sound source on a $label screen',
        (tester) async {
      final sample = sampleProject();
      final fakes = await openEditor(tester, size,
          project: sample.copyWith(clips: [
            sample.clips.first.copyWith(audioStreams: const [2, 2]),
            ...sample.clips.skip(1),
          ]));
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Sound');
      expect(find.text('Sound from'), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Track 2'), findsOneWidget);
      expect(find.text('Both sides'), findsOneWidget);
      expect(find.textContaining("can't remove music completely"), findsOneWidget);
      await tester.ensureVisible(find.text('Left only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left only'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Track 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track 2'));
      await tester.pumpAndSettle();

      // One drag of the slider is one undo step.
      final slider = find.descendant(
          of: find.byKey(const ValueKey('voice-focus')), matching: find.byType(Slider));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);
      final box = tester.getRect(slider);
      await tester.dragFrom(box.centerLeft + const Offset(12, 0),
          Offset(box.width * 0.55, 0));
      await tester.pumpAndSettle();
      final shown = tester
          .widget<Text>(find.descendant(
              of: find.byKey(const ValueKey('voice-focus')),
              matching: find.textContaining('%')))
          .data!;
      final percent = int.parse(shown.replaceAll('%', ''));
      expect(percent, inInclusiveRange(40, 70));
      expect(percent % 5, 0, reason: 'steps of 5 %');
      // The preview player that shows the clip got the filters and track.
      FakePlayer player() => fakes.backend.videoPlayers
          .lastWhere((p) => p.path == '/media/beach.mp4');
      expect(player().audioFilter, contains('c=FR'));
      expect(player().audioFilter, contains('f=25.5'));
      expect(player().audioTrack, 1);
      await fakes.screenshot(tester, 'editor_${label}_sound_focus');
      await tester.ensureVisible(find.text('Track 1'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_sound_source');
      // Let the "Voice focus is on" message go.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      if (size == phone) {
        // The sheet is tall now; close it like the back button does.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await undo(tester);
      expect(player().audioFilter, isNot(contains('f=25.5')),
          reason: 'focus undone in the preview too');
      expect(player().audioFilter, contains('c=FR'));

      await back(tester);
      final c = saved(fakes).clips.first;
      expect([c.audioTrack, c.audioChannel, c.voiceFocus],
          [1, AudioChannel.left, 0]);
    });

    testWidgets('sound: hear original and a sample on a $label screen',
        (tester) async {
      final sample = sampleProject();
      final fakes = await openEditor(tester, size,
          project: sample.copyWith(clips: [
            sample.clips.first.copyWith(voiceFocus: 0.5, denoise: true),
            ...sample.clips.skip(1),
          ]));
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      FakePlayer player() => fakes.backend.videoPlayers
          .lastWhere((p) => p.path == '/media/beach.mp4');
      expect(player().audioFilter, contains('equalizer'));
      await openClipTool(tester, size, 'Sound');
      await tester.ensureVisible(find.text('Hear original'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hear original'));
      await tester.pumpAndSettle();
      expect(player().audioFilter, '', reason: 'filters off while comparing');
      await tester.tap(find.text('Hear original'));
      await tester.pumpAndSettle();
      expect(player().audioFilter, contains('equalizer'));

      await tester.ensureVisible(find.text('Hear a sample'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hear a sample'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Making 15 seconds'), findsOneWidget);
      // Two small exports of one clip: with the settings, then without.
      expect(fakes.engine.jobs, hasLength(1));
      expect(fakes.engine.lastOptions!.quality, ExportQuality.small);
      fakes.engine.jobs.last.finish(fakes.engine.lastExportPath!);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fakes.engine.jobs, hasLength(2));
      fakes.engine.jobs.last.finish(fakes.engine.lastExportPath!);
      await tester.pumpAndSettle();
      expect(find.text('With changes'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_sound_sample');
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      final listen = fakes.backend.audio.last;
      expect(listen.path, endsWith('with-effect.mp4'));
      expect(listen.playing, isTrue);
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(listen.path, endsWith('original.mp4'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(listen.disposed, isTrue);
      expect(find.text('Sound sample'), findsNothing);
    });

    testWidgets('sound: no source choice for a one-channel clip on a $label screen',
        (tester) async {
      final sample = sampleProject();
      await openEditor(tester, size,
          project: sample.copyWith(clips: [
            sample.clips.first.copyWith(audioStreams: const [1]),
            ...sample.clips.skip(1),
          ]));
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Sound');
      expect(find.text('Sound from'), findsNothing);
      expect(find.text('Left only'), findsNothing);
      expect(find.text('Voice focus'), findsOneWidget);
    });

    testWidgets('transition shows a marker on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await zoomOutTwice(tester);
      const pxPerSecond = 60 / 1.5 / 1.5;

      // Nothing to blend from on the first clip.
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Transition and fades');
      expect(find.textContaining('This is the first clip'), findsOneWidget);
      expect(
          tester
              .widget<ChoicePill>(find.widgetWithText(ChoicePill, 'Crossfade'))
              .onTap,
          isNull);
      await closeSheet(tester, size);

      await tester.tap(block('clip-b'));
      await tester.pumpAndSettle();
      await openClipTool(tester, size, 'Transition and fades');
      await tester.tap(find.text('Crossfade'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_transition');
      await closeSheet(tester, size);

      // The clips overlap for half a second and the marker sits there.
      expect(find.textContaining('/ 0:17.5'), findsOneWidget);
      expect(block('transition-b'), findsOneWidget);
      final a = tester.getRect(block('clip-a'));
      final b = tester.getRect(block('clip-b'));
      expect(a.right - b.left, closeTo(pxPerSecond / 2, 0.01)); // 0.5 s
      final marker = tester.getRect(block('transition-b'));
      expect(marker.center.dx, closeTo((b.left + a.right) / 2, 0.01));

      await openClipTool(tester, size, 'Transition and fades');
      await tester.tap(find.text('Slide up'));
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      await back(tester);
      expect(saved(fakes).clips[1].transition, TransitionType.slideUp);
      expect(saved(fakes).clips[1].transitionMs, 500);
      expect(saved(fakes).durationMs, 17500);
    });

    testWidgets('freeze frame at the playhead on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await seekTo(tester, 2000);
      if (size == phone) {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await fakes.screenshot(tester, 'editor_phone_more');
        await tester.tap(find.text('Freeze frame'));
      } else {
        await tester.tap(find.text('Freeze'));
      }
      await tester.pumpAndSettle();
      expect(clipBlocks(), findsNWidgets(6));
      expect(find.textContaining('/ 0:20.0'), findsOneWidget);
      expect(fakes.engine.frames, hasLength(1));
      expect(fakes.engine.frames.single,
          startsWith('/media/beach.mp4@2000 -> /app/media/freeze_'));
      await fakes.screenshot(tester, 'editor_${label}_freeze');

      await undo(tester);
      expect(clipBlocks(), findsNWidgets(4));
      expect(undoEnabled(tester), isFalse);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await back(tester);
      final clips = saved(fakes).clips;
      expect(clips[0].outMs, 2000);
      expect(clips[1].type, ClipType.photo);
      expect(clips[1].durationMs, kFreezeFrameMs);
      expect(clips[1].path, endsWith('.png'));
      expect((clips[1].width, clips[1].height), (1920, 1080));
      expect(clips[2].inMs, 2000);
    });

    testWidgets('captions: add, import and export on a $label screen',
        (tester) async {
      final fakes = await openEditor(tester, size);
      await seekTo(tester, 5000);
      await tapAdd(tester, 'Caption');
      expect(find.text('Export subtitles (.srt)'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Look at  that!');
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_caption_entry');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // It is on the timeline, selected, and editable like a title.
      expect(find.text('Look at that!'), findsWidgets);
      if (size == phone) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      // (On a computer "Caption" is the panel's heading and its Add
      // button.)
      expect(find.text(size == phone ? 'Edit caption' : 'Caption'),
          size == phone ? findsOneWidget : findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'Look at this!');
      await tester.pumpAndSettle();
      await closeSheet(tester, size);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Import a subtitle file: both lines arrive as one undo step.
      fakes.documents
        ..pick = const PickedFile('/in/subs.srt', 'subs.srt')
        ..texts['/in/subs.srt'] = '1\n00:00:01,000 --> 00:00:02,500\nHello\n\n'
            '2\n00:00:08,000 --> 00:00:10,000\nSecond line\n';
      await tapAdd(tester, 'Caption');
      await tester.tap(find.text('Add a subtitle file (.srt)'));
      await tester.pumpAndSettle();
      expect(find.text('Added 2 captions.'), findsOneWidget);
      expect(find.text('Second line'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_captions');
      await waitForMessage(tester);
      await undo(tester);
      expect(find.text('Second line'), findsNothing);
      expect(find.text('Hello'), findsNothing);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();

      await tapAdd(tester, 'Caption');
      await tester.tap(find.text('Export subtitles (.srt)'));
      await tester.pumpAndSettle();
      final srt = fakes.documents.savedTexts['Summer trip.srt']!;
      expect(srt, contains('00:00:05,000 --> 00:00:07,500\nLook at this!'));
      expect(srt, contains('00:00:08,000 --> 00:00:10,000\nSecond line'));
      expect(srt, isNot(contains('Summer 2026'))); // a title, not a caption

      await back(tester);
      final captions = saved(fakes)
          .titles
          .where((t) => t.kind == TitleKind.caption)
          .toList();
      expect(captions, hasLength(3));
      expect(captions.first.text, 'Look at this!');
      expect(captions.first.background, isTrue);
      expect(captions.first.y, greaterThan(0.7));
    });

    testWidgets('lower music under speech on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await zoomOutTwice(tester);
      await tester.tap(block('audio-m1'));
      await tester.pumpAndSettle();
      if (size == phone) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Applied when you export'), findsOneWidget);
      // Per track: "Lower Music under speech" in the music's settings.
      await tester.ensureVisible(find.text('Lower Music under speech'));
      await tester.tap(find.text('Lower Music under speech'));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_music');
      await closeSheet(tester, size);
      await back(tester);
      expect(saved(fakes).soundTracks.single.duck, isTrue);
    });
  }

  testWidgets('an unreadable subtitle file and an empty one explain themselves',
      (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.documents.pick = const PickedFile('/in/none.srt', 'none.srt');
    await tapAdd(tester, 'Caption');
    await tester.tap(find.text('Add a subtitle file (.srt)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be read'), findsOneWidget);
    await waitForMessage(tester);

    fakes.documents.texts['/in/none.srt'] = 'not subtitles';
    await tapAdd(tester, 'Caption');
    await tester.tap(find.text('Add a subtitle file (.srt)'));
    await tester.pumpAndSettle();
    expect(find.text('No captions were found in that file.'), findsOneWidget);
    expect(undoEnabled(tester), isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('no silent gaps: nothing changes', (tester) async {
    await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(find.text('Remove silences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove silences'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No silent gaps were found'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(undoEnabled(tester), isFalse);
  });

  testWidgets('photos have no speed or sound group', (tester) async {
    await openEditor(tester, phone);
    await zoomOutTwice(tester);
    await tester.tap(block('clip-b'));
    await tester.pumpAndSettle();
    expect(find.text('Look'), findsOneWidget);
    expect(find.text('Speed'), findsNothing);
    expect(find.text('Sound'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    // Listed, greyed out, and it says why (1.15).
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Freeze frame'))
            .enabled,
        isFalse);
    expect(find.text('Not now: move the playhead onto a video clip'),
        findsOneWidget);
    expect(find.text('Transition and fades'), findsOneWidget);
  });

  testWidgets('freeze frame needs a video under the playhead', (tester) async {
    final fakes = await openEditor(tester, desktop);
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await seekTo(tester, 7000); // on the photo
    // Greyed out, and its tooltip says why (1.15).
    expect(find.byTooltip('Freeze: move the playhead onto a video clip'),
        findsOneWidget);
    await tester.tap(find.text('Freeze'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fakes.engine.frames, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('a trim handle moves twice the source on a 2× clip',
      (tester) async {
    final project = sampleProject();
    final fakes = await openEditor(tester, desktop,
        project: project.copyWith(clips: [
          project.clips.first.copyWith(speed: 2),
          ...project.clips.skip(1),
        ]));
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    expect(tester.getSize(block('clip-a')).width, closeTo(180, 0.01));
    // 60 px is one second on the timeline, two seconds of the source.
    await tester.drag(find.bySemanticsLabel('Trim end'), const Offset(-60, 0),
        touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(block('clip-a')).width, closeTo(120, 0.01));
    await back(tester);
    expect(saved(fakes).clips.first.outMs, 4000);
  });

  group('reorder', () {
    testWidgets('long-press and drag on a phone', (tester) async {
      final fakes = await openEditor(tester, phone);
      await zoomOutTwice(tester);
      final a = tester.getRect(block('clip-a'));
      final b = tester.getRect(block('clip-b'));
      final c = tester.getRect(block('clip-c'));

      final gesture = await tester.startGesture(a.center);
      await tester.pump(const Duration(milliseconds: 600));
      // Past the middle of the photo, before the middle of the next clip.
      await gesture.moveTo(Offset(b.center.dx + 8, a.center.dy));
      await tester.pump();
      await gesture.moveTo(Offset((b.center.dx + c.center.dx) / 2, a.center.dy));
      await tester.pump();
      expect(block('reorder-target'), findsOneWidget);
      expect(tester.getRect(block('reorder-target')).center.dx,
          closeTo(c.left, 0.01));
      await fakes.screenshot(tester, 'editor_phone_reorder');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(block('reorder-target'), findsNothing);
      expect(clipIds(fakes.store.projects['p1']!), ['a', 'b', 'c', 'd']);

      await back(tester);
      expect(clipIds(saved(fakes)), ['b', 'a', 'c', 'd']);
    });

    testWidgets('a short tap still selects and a swipe still scrolls',
        (tester) async {
      final fakes = await openEditor(tester, phone);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      final before = tester.getRect(block('clip-a')).left;
      await tester.drag(block('clip-a'), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(block('clip-a')).left, lessThan(before - 100));
      await back(tester);
      expect(clipIds(saved(fakes)), ['a', 'b', 'c', 'd']);
    });

    testWidgets('mouse drag on the desktop, one undo step', (tester) async {
      final fakes = await openEditor(tester, desktop);
      final a = tester.getRect(block('clip-a'));
      final d = tester.getRect(block('clip-d'));
      await tester.dragFrom(d.center, Offset(a.left + 40 - d.center.dx, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.getRect(block('clip-d')).left, closeTo(a.left, 0.01));

      await undo(tester);
      expect(undoEnabled(tester), isFalse);
      expect(tester.getRect(block('clip-a')).left, closeTo(a.left, 0.01));
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(clipIds(saved(fakes)), ['d', 'a', 'b', 'c']);
    });

    testWidgets('the buttons do the same without dragging', (tester) async {
      final fakes = await openEditor(tester, phone);
      await tester.tap(block('clip-a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      // The first clip cannot go earlier, and the line says why.
      expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Move earlier'))
              .enabled,
          isFalse);
      expect(find.text('Not now: it is already the first clip'),
          findsOneWidget);
      await closeSheet(tester, phone);
      await tapMore(tester, 'more-moveLater');
      await tapMore(tester, 'more-moveLater');
      await back(tester);
      expect(clipIds(saved(fakes)), ['b', 'c', 'a', 'd']);
    });
  });

  test('silencesToCut keeps to the trimmed range and leaves breathing room',
      () {
    final clip = videoClip('x', '/v.mp4', 2000, 10000);
    expect(
      silencesToCut(clip, const [
        (startMs: 0, endMs: 1500), // before the clip
        (startMs: 1000, endMs: 3000), // reaches into its start
        (startMs: 5000, endMs: 5400), // too short once padded
        (startMs: 6000, endMs: 7000),
        (startMs: 9500, endMs: 12000), // runs past its end
      ]),
      const [
        (startMs: 2000, endMs: 2850),
        (startMs: 6150, endMs: 6850),
        (startMs: 9650, endMs: 10000),
      ],
    );
  });
}
