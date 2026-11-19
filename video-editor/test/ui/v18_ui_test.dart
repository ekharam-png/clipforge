// 1.8 in the editor: Fit music to video (and loop), Add music > Find free
// music (recorded Openverse answers), music credits, Find file > Search the
// gallery, Smooth preview, and fewer rebuilds while playing. Phone and
// desktop sizes; screenshots with --dart-define=SCREENSHOTS=true.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/music/openverse.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/ui/editor/clip_actions.dart' show missingFileName;
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/gallery_search.dart';
import 'package:clipforge/ui/music_search.dart';
import 'package:clipforge/ui/services.dart' show PickedFile;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

Future<void> selectMusic(WidgetTester tester, Size size) async {
  await zoomOutTwice(tester);
  await tester.tap(block('audio-m1'));
  await tester.pumpAndSettle();
  if (size == phone) {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

final _fixture = parseOpenverseAudio(
    File('test/core/fixtures/openverse_audio.json').readAsStringSync());

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('Fit music to video on a $label screen', (tester) async {
      final fakes = await openEditor(tester, size);
      await selectMusic(tester, size);
      await tapText(tester, 'Fit music to video');
      final s = sessionOf(tester);
      final m = s.project.audio.single;
      expect(m.endMs, s.project.durationMs);
      expect(m.fadeOutMs, 2000);
      expect(s.editor.history.last.label, 'Fitted music to the video');
      expect(find.textContaining('ends with the video'), findsWidgets);
      await fakes.screenshot(tester, 'editor_${label}_fit_music');
    });

    testWidgets('short music: Fit music to video offers a loop on a $label '
        'screen', (tester) async {
      final base = sampleProject();
      final fakes = await openEditor(tester, size,
          project: base.copyWith(audio: [
            base.audio.single.copyWith(outMs: 5000),
          ]).copyWithSource(5000));
      await selectMusic(tester, size);
      await tapText(tester, 'Fit music to video');
      expect(find.text('The music is shorter than the video'), findsOneWidget);
      await fakes.screenshot(tester, 'editor_${label}_loop_offer');
      await tester.tap(find.text('Loop'));
      await tester.pumpAndSettle();
      final s = sessionOf(tester);
      final m = s.project.audio.single;
      expect(m.looped, isTrue);
      expect(m.endMs, s.project.durationMs);
      expect(s.editor.history.last.label, 'Looped music to fit the video');
      expect(find.text('Stop looping'), findsOneWidget);
      expect(find.textContaining('· loops'), findsOneWidget); // timeline
      await fakes.screenshot(tester, 'editor_${label}_looped');
      await tapText(tester, 'Stop looping');
      expect(sessionOf(tester).project.audio.single.looped, isFalse);
    });

    testWidgets('Find free music, preview, use it, credits on a $label '
        'screen', (tester) async {
      final fakes = await openEditor(tester, size);
      fakes.music
        ..on = true
        ..pages['happy'] = _fixture;
      final first = _fixture.results.first;
      fakes.engine.infos[musicDownloadPath(first, '/app/media')] =
          const MediaInfo(
              durationMs: 95000, width: 0, height: 0, hasVideo: false,
              hasAudio: true);
      await tester.tap(find.text('Music').first);
      await tester.pumpAndSettle();
      expect(find.text('Find free music'), findsOneWidget);
      expect(find.text('My files'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'happy');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(fakes.music.queries.last, 'happy|false|1');
      expect(find.text('Happy Ukulele Morning'), findsOneWidget);
      expect(find.text('Sunny Strings · 1:35 · CC BY 4.0'), findsOneWidget);
      expect(find.textContaining('CC0 1.0'), findsOneWidget);
      // Listening streams the file in a player of its own.
      final players = fakes.backend.audio.length;
      await tester.tap(find.byTooltip('Listen').first);
      await tester.pumpAndSettle();
      expect(fakes.backend.audio.length, players + 1);
      expect(fakes.backend.audio.last.path, first.url);
      await fakes.screenshot(tester, 'editor_${label}_free_music');
      // Stricter licences on: searched again with them.
      await tester.tap(find.text('Also show music with stricter licences'));
      await tester.pumpAndSettle();
      expect(fakes.music.queries.last, 'happy|true|1');
      await tester.tap(find.text('Use').first);
      await tester.pumpAndSettle();
      final s = sessionOf(tester);
      final added = s.project.audio.last;
      expect(added.credit?.title, 'Happy Ukulele Morning');
      expect(added.credit?.licenceName, 'CC BY 4.0');
      expect(fakes.music.downloads.single, added.path);
      // The new music is selected; its panel shows the credits.
      ScaffoldMessenger.of(tester.element(find.byType(PreviewView)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      if (size == phone) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Copy credits'));
      await tester.pumpAndSettle();
      expect(find.text('Music: "Happy Ukulele Morning" by Sunny Strings '
          '(CC BY 4.0)'), findsWidgets);
      await fakes.screenshot(tester, 'editor_${label}_music_credits');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await tester.tap(find.text('Copy credits'));
      await tester.pumpAndSettle();
      expect(copied, contains('https://www.jamendo.com/track/1'));
      await tapText(tester, 'Add credits at the end');
      final t = sessionOf(tester).project.titles.last;
      expect(t.endMs, sessionOf(tester).project.durationMs);
      expect(t.text, contains('Sunny Strings'));
      expect(sessionOf(tester).editor.history.last.label,
          'Added music credits');
    });
  }

  testWidgets('free music search offline: a clear message', (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.music
      ..on = true
      ..error = offlineError;
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'piano');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('No connection to the internet'), findsOneWidget);
    // My files still works.
    fakes.engine.infos['/in/tune.mp3'] = const MediaInfo(
        durationMs: 9000, width: 0, height: 0, hasVideo: false, hasAudio: true);
    fakes.files.audio = const [PickedFile('/in/tune.mp3', 'tune.mp3')];
    await tester.tap(find.text('My files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a music file…'));
    await tester.pumpAndSettle();
    // 1.10: asked what the sound is; Music is chosen for a song.
    expect(find.text('What is this sound?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    expect(sessionOf(tester).project.audio.last.path, '/in/tune.mp3');
  });

  testWidgets('Find file: search the gallery by name (phone)', (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.gallery
      ..on = true
      ..found = [
        GalleryItem(
            uri: 'content://media/1',
            name: 'gone.mp4',
            sizeBytes: 52000000,
            modified: DateTime(2026, 11, 16, 20, 59),
            folder: 'DCIM/Camera/'),
      ];
    fakes.engine.infos['/gallery/gone.mp4'] = const MediaInfo(
        durationMs: 20000, width: 1920, height: 1080, hasVideo: true,
        hasAudio: true);
    await zoomOutTwice(tester);
    await tester.tap(block('clip-c'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find file').first);
    await tester.pumpAndSettle();
    expect(find.text('Where is gone.mp4 now?'), findsOneWidget);
    await tester.tap(find.text('Search the gallery'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DCIM/Camera/'), findsOneWidget);
    await fakes.screenshot(tester, 'editor_phone_find_in_gallery');
    await tester.tap(find.text('gone.mp4').last);
    await tester.pumpAndSettle();
    final s = sessionOf(tester);
    expect(s.project.clips[2].path, '/gallery/gone.mp4');
    expect(s.editor.history.last.label, 'Found file on clip 3');
  });

  testWidgets('Find file: gallery says no -> the file picker', (tester) async {
    final fakes = await openEditor(tester, phone);
    fakes.gallery
      ..on = true
      ..denied = true;
    fakes.files.media = const [PickedFile('/picked/gone.mp4', 'gone.mp4')];
    fakes.engine.infos['/picked/gone.mp4'] = const MediaInfo(
        durationMs: 20000, width: 1920, height: 1080, hasVideo: true,
        hasAudio: true);
    await zoomOutTwice(tester);
    await tester.tap(block('clip-c'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find file').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search the gallery'));
    await tester.pumpAndSettle();
    expect(sessionOf(tester).project.clips[2].path, '/picked/gone.mp4');
  });

  test('the name a missing file had', () {
    expect(missingFileName('/data/x/media/1700000000000000_20261116_205955.mp4'),
        '20261116_205955.mp4');
    expect(missingFileName(
            '/data/data/a/cache/file_picker/uuid/20261116_205955.mp4'),
        '20261116_205955.mp4');
    expect(missingFileName(r'C:\Videos\a.mp4'), 'a.mp4');
  });

  testWidgets('Smooth preview switch in More (phone)', (tester) async {
    final fakes = await openEditor(tester, phone);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final sw = find.byKey(const ValueKey('more-smooth-preview'));
    expect(sw, findsOneWidget);
    await fakes.screenshot(tester, 'editor_phone_more_smooth');
    final before = tester.widget<SwitchListTile>(sw).value;
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(sw).value, !before);
    expect(await fakes.prefs.flag('smoothPreviewOff'), before);
  });

  testWidgets('playing: the titles and picture layers do not rebuild every '
      'frame', (tester) async {
    await openEditor(tester, phone);
    final s = sessionOf(tester);
    s.playback.seek(4500); // past the title, inside clip b (a photo)
    await tester.pumpAndSettle();
    final titles0 = debugTitleLayerBuilds, scene0 = debugSceneBuilds;
    // 120 frames at 60 fps inside the photo (no transition, no fades).
    for (var i = 0; i < 120; i++) {
      s.playback.seek(4500 + i * 8);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final titles = debugTitleLayerBuilds - titles0;
    final scene = debugSceneBuilds - scene0;
    // ignore: avoid_print
    print('rebuilds over 120 playhead moves: titles $titles, picture $scene '
        '(before 1.8: 120 each)');
    expect(titles, lessThan(3));
    expect(scene, lessThan(3));
  });
}

extension on Project {
  /// The music's file is [ms] long.
  Project copyWithSource(int ms) => copyWith(audio: [
        for (final a in audio)
          AudioClip.fromJson(a.toJson()..['sourceDurationMs'] = ms),
      ]);
}
