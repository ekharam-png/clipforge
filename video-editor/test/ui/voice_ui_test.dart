// 1.10 "Voice recorded separately" in the editor, on a phone and a desktop
// screen: the "What is this sound?" question (sheet / dialog) with its
// guess, a Zoom voice file lined up and linked on its own track named
// after the speaker, music and effects, a voice that cannot be lined up,
// the nudge buttons, unlink, "Line up with the video" for music that is
// really a voice, and Remove silences listening to the voice. Overflow
// errors fail these tests by themselves.
import 'package:clipforge/core/editor/sound_tracks.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/sound_align_job.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// An engine that "lines up" sound: answers per voice file and video file.
class AlignEngine extends FakeMediaEngine implements SoundAlignEngine {
  /// `voice path` -> `video path` -> result; anything else does not match.
  final Map<String, Map<String, AlignResult>> matches = {};
  final List<String> asked = [];

  @override
  Future<AlignResult> alignSound(String videoPath, String voicePath,
      {int videoAudioTrack = 0, int voiceAudioTrack = 0}) async {
    asked.add('$voicePath vs $videoPath');
    return matches[voicePath]?[videoPath] ??
        const AlignResult(
            offsetMs: 777,
            confidence: 0.05,
            score: 0.1,
            peakRatio: 1.02,
            driftMs: 0,
            overlapMs: 5000);
  }
}

class AlignFakes extends Fakes {
  AlignFakes({super.projects, super.missing});
  final AlignEngine _engine = AlignEngine();

  // ignore: overridden_fields
  @override
  AlignEngine get engine => _engine;
}

AlignResult found(int offsetMs, {int driftMs = 0}) => AlignResult(
    offsetMs: offsetMs,
    confidence: 0.95,
    score: 0.7,
    peakRatio: 4,
    driftMs: driftMs,
    overlapMs: 19000);

const zoom = '/in/audioSamTaylor21406335665.m4a';
const zoomName = 'audioSamTaylor21406335665.m4a';
const _voiceInfo = MediaInfo(
    durationMs: 19000, width: 0, height: 0, hasVideo: false, hasAudio: true);
const _songInfo = MediaInfo(
    durationMs: 9000, width: 0, height: 0, hasVideo: false, hasAudio: true);

Future<AlignFakes> open(WidgetTester tester, Size size, {Project? project}) async {
  useScreen(tester, size);
  final fakes =
      AlignFakes(projects: [project ?? sampleProject()], missing: missing);
  await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  return fakes;
}

Project now(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session.project;

/// Lets a message go away (the longest stays 10 s).
Future<void> afterMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

/// Music button > the picker's files.
Future<void> pickSound(WidgetTester tester) async {
  await tapAdd(tester, 'Music');
}

bool selectedRole(WidgetTester tester, String role) {
  final tile = find.byKey(ValueKey('sound-role-$role'));
  return find
      .descendant(of: tile, matching: find.byIcon(Icons.radio_button_checked))
      .evaluate()
      .isNotEmpty;
}

/// The sample project with a linked voice for clip a on its own track.
Project withVoice({bool linked = true}) {
  final p = sampleProject();
  final clips = [
    p.clips.first.copyWith(muted: true, frameRate: 25),
    ...p.clips.skip(1),
  ];
  return p.copyWith(
    tracks: const [
      SoundTrack(id: 'dg', name: 'Sam Taylor', speech: true),
      SoundTrack(id: kMusicTrackId, name: 'Music', duck: true),
    ],
    clips: clips,
    audio: [
      ...p.audio,
      AudioClip(
        id: 'v1',
        path: zoom,
        sourceDurationMs: 19000,
        startMs: 0,
        inMs: 420,
        outMs: 6420,
        trackId: 'dg',
        sourceClipId: 'a',
        linked: linked,
        syncOffsetMs: 420,
      ),
    ],
  );
}

Future<void> openSoundPanel(WidgetTester tester, Size size, String id) async {
  // Its left end: a long sound's middle can be off the screen.
  await tester.tapAt(tester.getTopLeft(block('audio-$id')) + const Offset(16, 10));
  await tester.pumpAndSettle();
  if (size == phone) {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('a Zoom voice file: asked, lined up, linked on a $label screen',
        (tester) async {
      final fakes = await open(tester, size);
      fakes.engine.infos[zoom] = _voiceInfo;
      fakes.engine.matches[zoom] = {'/media/beach.mp4': found(420)};
      fakes.files.audio = const [PickedFile(zoom, zoomName)];
      await pickSound(tester);

      // The question, with Voice chosen and the speaker's name filled in.
      expect(find.text('What is this sound?'), findsOneWidget);
      expect(find.text(zoomName), findsOneWidget);
      expect(selectedRole(tester, 'voice'), isTrue);
      expect(selectedRole(tester, 'music'), isFalse);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('voice-track-name-0')))
              .controller!
              .text,
          'Sam Taylor');
      expect(
          tester
              .widget<SwitchListTile>(
                  find.byKey(const ValueKey('voice-mute-camera')))
              .value,
          isTrue);
      // A sheet on the phone, a dialog on the computer.
      expect(find.byType(BottomSheet).evaluate().isNotEmpty, size == phone);
      await fakes.screenshot(tester, 'editor_${label}_sound_question');

      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lined up with clip 1 (+0.42 s)'),
          findsOneWidget);
      expect(find.textContaining('camera\'s own sound is muted'), findsOneWidget);

      final p = now(tester);
      final v = p.audio.singleWhere((a) => a.isVoice);
      expect([v.startMs, v.inMs, v.outMs], [0, 420, 6420]);
      expect(v.linked, isTrue);
      expect(v.sourceClipId, 'a');
      final track = p.trackById(v.trackId)!;
      expect(track.name, 'Sam Taylor');
      expect(track.speech, isTrue);
      expect(p.clips.first.muted, isTrue);
      // Every video file with sound was compared (not the photo).
      expect(fakes.engine.asked.length, 3);
      // On the timeline, in its own row, selected.
      expect(block('audio-${v.id}'), findsOneWidget);
      expect(find.textContaining('Voice · $zoomName'), findsWidgets);
      await afterMessage(tester);
      await fakes.screenshot(tester, 'editor_${label}_voice_linked');

      // One undo step takes all of it back.
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(now(tester).audio.any((a) => a.isVoice), isFalse);
      expect(now(tester).clips.first.muted, isFalse);
      expect(now(tester).soundTracks.any((t) => t.name == 'Sam Taylor'),
          isFalse);
    });

    testWidgets('music and a sound effect are asked about too on a $label screen',
        (tester) async {
      final fakes = await open(tester, size);
      fakes.engine.infos['/in/tune.mp3'] = _songInfo;
      fakes.files.audio = const [PickedFile('/in/tune.mp3', 'tune.mp3')];
      await pickSound(tester);
      expect(find.text('What is this sound?'), findsOneWidget);
      expect(selectedRole(tester, 'music'), isTrue);
      // No voice fields for music.
      expect(find.byKey(const ValueKey('voice-track-name-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      var p = now(tester);
      expect(p.audio.last.path, '/in/tune.mp3');
      expect(p.soundRoleOf(p.audio.last), 'music');
      expect(p.audio.last.fadeOutMs, 1000);
      expect(fakes.engine.asked, isEmpty);

      // The same file as a sound effect: an Effects track.
      await pickSound(tester);
      await tester.tap(find.byKey(const ValueKey('sound-role-effect')));
      await tester.pumpAndSettle();
      expect(selectedRole(tester, 'effect'), isTrue);
      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      p = now(tester);
      expect(p.soundRoleOf(p.audio.last), 'effect');
      expect(p.trackById(p.audio.last.trackId)!.name, 'Effects');
      expect(p.audio.last.fadeOutMs, 0);

      // Cancel adds nothing.
      final count = p.audio.length;
      await pickSound(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(now(tester).audio.length, count);
    });

    testWidgets('a voice that cannot be lined up, then nudged by hand on a '
        '$label screen', (tester) async {
      final fakes = await open(tester, size);
      fakes.engine.infos['/in/mic.wav'] = _voiceInfo;
      fakes.files.audio = const [PickedFile('/in/mic.wav', 'mic.wav')];
      await pickSound(tester);
      expect(selectedRole(tester, 'voice'), isTrue, reason: 'named "mic"');
      await tester.enterText(
          find.byKey(const ValueKey('voice-track-name-0')), 'Anna');
      await tester.tap(find.byKey(const ValueKey('sound-role-add')));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(
              'Could not line it up automatically — nudge it by hand'),
          findsOneWidget);
      var p = now(tester);
      var v = p.audio.singleWhere((a) => a.isVoice);
      // At the start of the first video clip, linked, the camera still on.
      expect([v.startMs, v.inMs, v.syncOffsetMs], [0, 0, 0]);
      expect(v.linked, isTrue);
      expect(p.clips.first.muted, isFalse);
      expect(p.trackById(v.trackId)!.name, 'Anna');
      await afterMessage(tester);

      // Its panel has the nudge buttons.
      if (size == phone) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Edit voice').evaluate().isNotEmpty ||
          find.text('Voice').evaluate().isNotEmpty, isTrue);
      final earlier = find.byKey(const ValueKey('nudge-earlier-100'));
      await tester.ensureVisible(earlier);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-status')), findsOneWidget);
      await tester.tap(earlier);
      await tester.pumpAndSettle();
      v = now(tester).audio.singleWhere((a) => a.isVoice);
      // Earlier: the picture gets a later part of the voice file.
      expect([v.syncOffsetMs, v.inMs, v.startMs], [100, 100, 0]);
      await tester.tap(find.byKey(const ValueKey('nudge-later-10')));
      await tester.pumpAndSettle();
      expect(now(tester).audio.singleWhere((a) => a.isVoice).syncOffsetMs, 90);
      // One frame (unknown frame rate: 33 ms).
      await tester.tap(find.byKey(const ValueKey('nudge-earlier-frame')));
      await tester.pumpAndSettle();
      expect(now(tester).audio.singleWhere((a) => a.isVoice).syncOffsetMs, 123);
      expect(find.textContaining('lined up at +0.12 s'), findsOneWidget);

      // The camera switch.
      final cam = find.byKey(const ValueKey('voice-camera-muted'));
      await tester.ensureVisible(cam);
      await tester.pumpAndSettle();
      await tester.tap(cam);
      await tester.pumpAndSettle();
      expect(now(tester).clips.first.muted, isTrue);
    });

    testWidgets('the voice panel: nudge, unlink, line up again on a $label screen',
        (tester) async {
      final fakes = await open(tester, size, project: withVoice());
      await openSoundPanel(tester, size, 'v1');
      expect(find.textContaining('Voice for clip 1, lined up at +0.42 s'),
          findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('nudge-later-frame')));
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'editor_${label}_voice_panel');
      // Later by one frame of a 25 fps clip: 40 ms.
      await tester.tap(find.byKey(const ValueKey('nudge-later-frame')));
      await tester.pumpAndSettle();
      var v = now(tester).audio.firstWhere((a) => a.id == 'v1');
      expect([v.syncOffsetMs, v.inMs], [380, 380]);
      expect(v.linked, isTrue);
      await tester.tap(find.byKey(const ValueKey('nudge-later-100')));
      await tester.pumpAndSettle();
      expect(now(tester).audio.firstWhere((a) => a.id == 'v1').syncOffsetMs, 280);

      // Line up again: the engine finds +0.50 s.
      fakes.engine.matches[zoom] = {'/media/beach.mp4': found(500)};
      final again = find.byKey(const ValueKey('voice-realign'));
      await tester.ensureVisible(again);
      await tester.pumpAndSettle();
      expect(find.text('Line up with the video again'), findsOneWidget);
      await tester.tap(again);
      await tester.pumpAndSettle();
      var p = now(tester);
      v = p.audio.singleWhere((a) => a.isVoice);
      expect([v.syncOffsetMs, v.linked, v.trackId], [500, true, 'dg']);
      expect(p.clips.first.muted, isTrue, reason: 'the camera stays muted');
      await afterMessage(tester);

      // Unlink: asked; the sound stays, the camera comes back on.
      final unlink = find.byKey(const ValueKey('voice-unlink'));
      await tester.ensureVisible(unlink);
      await tester.pumpAndSettle();
      await tester.tap(unlink);
      await tester.pumpAndSettle();
      expect(find.text('Unlink the voice from the video?'), findsOneWidget);
      expect(find.byKey(const ValueKey('unlink-unmute')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('unlink-confirm')));
      await tester.pumpAndSettle();
      p = now(tester);
      final after = p.audio.singleWhere((a) => a.isVoice);
      expect(after.linked, isFalse);
      expect([after.startMs, after.inMs, after.outMs],
          [v.startMs, v.inMs, v.outMs]);
      expect(p.clips.first.muted, isFalse);
      expect(find.textContaining('not linked to the video'), findsOneWidget);
      expect(find.byKey(const ValueKey('nudge-later-10')), findsNothing);
      expect(find.text('Line up with the video'), findsOneWidget);
    });

    testWidgets('music that is really a voice: line up with the video on a '
        '$label screen', (tester) async {
      // What happened to the owner: the Zoom file landed on the Music track.
      final base = sampleProject();
      final project = base.copyWith(audio: [
        const AudioClip(
          id: 'm1',
          path: zoom,
          sourceDurationMs: 19000,
          startMs: 1000,
          inMs: 0,
          outMs: 12000,
        ),
      ]);
      final fakes = await open(tester, size, project: project);
      fakes.engine.matches[zoom] = {'/media/beach.mp4': found(-300)};
      await openSoundPanel(tester, size, 'm1');
      final button = find.byKey(const ValueKey('line-up-as-voice'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      // Asked (default yes): mute the camera's own sound?
      expect(find.text('Mute the camera\'s own sound?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mute-camera-yes')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lined up with clip 1 (−0.30 s)'),
          findsOneWidget);
      final p = now(tester);
      final v = p.audio.single;
      expect(v.isVoice && v.linked, isTrue);
      expect([v.startMs, v.inMs, v.outMs], [300, 0, 5700]);
      expect(p.trackById(v.trackId)!.name, 'Sam Taylor');
      expect(p.trackById(v.trackId)!.speech, isTrue);
      expect(p.clips.first.muted, isTrue);
      expect(linkedVoicesOf(p, 'a').length, 1);
      await afterMessage(tester);
    });
  }

  testWidgets('a video and its voice picked together in Add media',
      (tester) async {
    final fakes = await open(tester, desktop);
    fakes.engine.infos
      ..['/in/video1406335665.mp4'] = const MediaInfo(
          durationMs: 20000,
          width: 1920,
          height: 1080,
          hasVideo: true,
          hasAudio: true)
      ..[zoom] = _voiceInfo;
    fakes.engine.matches[zoom] = {'/in/video1406335665.mp4': found(250)};
    // The sound file first: the video still goes in before it is asked about.
    fakes.files.media = const [
      PickedFile(zoom, zoomName),
      PickedFile('/in/video1406335665.mp4', 'video1406335665.mp4'),
    ];
    await tester.tap(find.text('Add media').first);
    await tester.pumpAndSettle();
    expect(find.text('What is this sound?'), findsOneWidget);
    expect(selectedRole(tester, 'voice'), isTrue);
    expect(now(tester).clips.last.path, '/in/video1406335665.mp4');
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    final p = now(tester);
    final v = p.audio.singleWhere((a) => a.isVoice);
    expect(v.sourceClipId, p.clips.last.id);
    expect(v.syncOffsetMs, 250);
    expect(p.clips.last.muted, isTrue);
    expect(find.text('A file could not be added'), findsNothing);
    await afterMessage(tester);
  });

  testWidgets('music is not put among the voices', (tester) async {
    final fakes = await open(tester, desktop, project: withVoice());
    await openSoundPanel(tester, desktop, 'v1');
    fakes.engine.infos['/in/tune.mp3'] = _songInfo;
    fakes.files.audio = const [PickedFile('/in/tune.mp3', 'tune.mp3')];
    await pickSound(tester);
    expect(selectedRole(tester, 'music'), isTrue);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    final p = now(tester);
    final tune = p.audio.firstWhere((a) => a.path == '/in/tune.mp3');
    expect(p.trackById(tune.trackId)!.speech, isFalse);
    expect(p.soundRoleOf(tune), 'music');
  });

  testWidgets('two speakers at once: each on its own track', (tester) async {
    final fakes = await open(tester, desktop);
    const two = '/in/audioAlexK11406335665.m4a';
    fakes.engine.infos
      ..[zoom] = _voiceInfo
      ..[two] = _voiceInfo;
    fakes.engine.matches
      ..[zoom] = {'/media/beach.mp4': found(420)}
      ..[two] = {'/media/beach.mp4': found(400, driftMs: 0)};
    fakes.files.audio = const [
      PickedFile(zoom, zoomName),
      PickedFile(two, 'audioAlexK11406335665.m4a'),
    ];
    await pickSound(tester);
    expect(find.text('What are these sounds?'), findsOneWidget);
    expect(selectedRole(tester, 'voice'), isTrue);
    expect(find.byKey(const ValueKey('voice-track-name-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 voices lined up with the video'),
        findsOneWidget);
    final p = now(tester);
    final voices = [for (final a in p.audio) if (a.isVoice) a];
    expect(voices.length, 2);
    expect({for (final v in voices) p.trackById(v.trackId)!.name},
        {'Sam Taylor', 'Alex K'});
    expect(p.soundTracks.length, 3);
    await afterMessage(tester);
    // One undo step for the batch.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(now(tester).audio.any((a) => a.isVoice), isFalse);

    // A third speaker does not fit (Music + 2 voices = 3 tracks): said so.
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    const three = '/in/audioThird31406335665.m4a';
    fakes.engine.infos[three] = _voiceInfo;
    fakes.engine.matches[three] = {'/media/beach.mp4': found(410)};
    fakes.files.audio = const [PickedFile(three, 'audioThird31406335665.m4a')];
    await pickSound(tester);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    expect(find.text('A file could not be added'), findsOneWidget);
    expect(find.textContaining('at most 3 sound tracks'), findsOneWidget);
    expect(now(tester).audio.where((a) => a.isVoice).length, 2);
  });

  testWidgets('a drifting recording is said so', (tester) async {
    final fakes = await open(tester, desktop);
    fakes.engine.infos[zoom] = _voiceInfo;
    fakes.engine.matches[zoom] = {
      '/media/beach.mp4': found(420, driftMs: 240),
    };
    fakes.files.audio = const [PickedFile(zoom, zoomName)];
    await pickSound(tester);
    await tester.tap(find.byKey(const ValueKey('sound-role-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('slowly drift apart (about 0.24 s'),
        findsOneWidget);
    await afterMessage(tester);
  });

  testWidgets('Add and Sound have the voice items (Windows menu bar)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
    useScreen(tester, desktop);
    final fakes =
        AlignFakes(projects: [withVoice(linked: false)], missing: missing);
    await tester.pumpWidget(
        fakes.app(const EditorScreen(projectId: 'p1'), menuBar: true));
    await tester.pumpAndSettle();
    MenuItemButton item(String key) =>
        tester.widget<MenuItemButton>(find.byKey(ValueKey(key)));
    Future<void> openMenu(String menu) async {
      await tester.tap(find.widgetWithText(SubmenuButton, menu));
      await tester.pumpAndSettle();
    }

    Future<void> openSound() => openMenu('Sound');

    await openSound();
    // Greyed out, and it says why.
    expect(find.text('Line up voice with video (select a sound)'),
        findsOneWidget);
    expect(item('menu-line-up-voice').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await openMenu('Add');
    expect(find.text('Voice recording…'), findsOneWidget);
    expect(item('menu-add-voice').onPressed, isNotNull);
    // The picker has nothing: no question.
    await tester.tap(find.byKey(const ValueKey('menu-add-voice')));
    await tester.pumpAndSettle();
    expect(find.text('What is this sound?'), findsNothing);

    // With the voice selected, "Line up with the video" links it again.
    fakes.engine.matches[zoom] = {'/media/beach.mp4': found(450)};
    await tester.tapAt(
        tester.getTopLeft(block('audio-v1')) + const Offset(16, 10));
    await tester.pumpAndSettle();
    await openSound();
    expect(item('menu-line-up-voice').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('menu-line-up-voice')));
    await tester.pumpAndSettle();
    final v = now(tester).audio.singleWhere((a) => a.isVoice);
    expect([v.linked, v.syncOffsetMs], [true, 450]);
    await afterMessage(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a clip with a linked voice says so in its Sound panel',
      (tester) async {
    await open(tester, desktop, project: withVoice());
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Sound');
    expect(find.byKey(const ValueKey('linked-voice-note')), findsOneWidget);
    expect(find.textContaining('Voice from a separate recording (Sam Taylor)'),
        findsOneWidget);
    // "Put it back" is for the clip's own separated sound only.
    expect(find.byKey(const ValueKey('reattach-sound')), findsNothing);
    expect(find.byKey(const ValueKey('separate-sound')), findsOneWidget);
  });

  testWidgets('remove silences listens to the linked voice', (tester) async {
    final fakes = await open(tester, desktop, project: withVoice());
    // The camera file is "silent" all through, the voice has one pause at
    // 2.42..4.42 s of ITS file = 2..4 s of the clip's.
    fakes.engine.silences['/media/beach.mp4'] = [(startMs: 0, endMs: 6000)];
    fakes.engine.silences[zoom] = [(startMs: 2420, endMs: 4420)];
    await tester.tap(block('clip-a'));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Sound');
    final button = find.text('Remove silences');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fakes.engine.silenceRequests, [zoom]);
    expect(find.text('Found 1 silent gap (1.7 s).'), findsOneWidget);
    expect(find.byKey(const ValueKey('silence-voice-note')), findsOneWidget);
    await tester.tap(find.text('Remove 1 gap'));
    await tester.pumpAndSettle();
    final p = now(tester);
    // Two pieces, each with its part of the voice, still in sync.
    expect(p.clips.where((c) => c.path == '/media/beach.mp4').length, 2);
    final voices = [for (final a in p.audio) if (a.isVoice) a]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    expect(voices.length, 2);
    expect([voices[0].inMs, voices[0].outMs], [420, 2570]);
    expect([voices[1].inMs, voices[1].outMs], [4270, 6420]);
    expect(voices[1].startMs, voices[0].endMs);
  });
}
