// 1.17 with sound pictures: quiet ranges and the gate on the waveform,
// "Only when speaking" in the preview's levels and in the track menu,
// the speaker's turn and the pause as quick selections, the suggestion,
// "Drawing sound…" with its count and the cross that stops it, and the
// small wording helpers.

import 'dart:async';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/editor/editor_actions.dart';
import 'package:clipforge/ui/editor/export_dialog.dart' show shapeWords;
import 'package:clipforge/ui/editor/suggestions.dart';
import 'package:clipforge/ui/help/what_moved.dart';
import 'package:clipforge/ui/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sound_waves_test.dart'
    show fakesFor, key, open, session, talk, wave, samFile;

const desk = Size(1280, 800);

void main() {
  setUpAll(loadFonts);

  testWidgets('a silenced part and the gate are drawn on the waveform; the '
      'preview and the export get the same lists', (tester) async {
    final fakes = await open(tester, desk);
    final s = session(tester);
    final e = s.editor.editor;
    expect(wave(tester, 'v1').quiet, isEmpty);
    expect(s.gates, isEmpty, reason: 'off unless switched on');

    // Silence 2 s..4 s on Sam's row only.
    s.setPart(2000, 4000);
    s.partRows.value = {'sam'};
    await tester.pumpAndSettle();
    EditorActions(s).run(tester.element(key('part-bar')), Act.partSilence);
    await tester.pumpAndSettle();
    expect(wave(tester, 'v1').quiet, [const QuietRange(2000, 4000)]);
    expect(wave(tester, 'v2').quiet, isEmpty);
    expect(s.editor.history.last.label, 'Silenced a part (2.0 s) on Sam');

    // Only when speaking for Dana: her microphone is down while Sam talks.
    e.setOnlyWhenSpeaking('dana', on: true);
    await tester.pumpAndSettle();
    final gate = s.gates['v2']!;
    expect(gate.first.fromMs, 0);
    expect(gate.first.toMs, closeTo(6000 - 80, 40), reason: 'opens 80 ms early');
    expect(gate.every((r) => r.level == kGateDefaultLevel), isTrue);
    expect(s.gates.containsKey('v1'), isFalse);
    expect(wave(tester, 'v2').gate, same(gate));
    // The preview's level of Dana's sound: down at 3 s, open at 8 s.
    final dana = s.project.audio.firstWhere((a) => a.id == 'v2');
    expect(PlaybackController.audioGain(dana, 3000, gate: s.playback.gateOf!(dana)),
        closeTo(kGateDefaultLevel, 1e-9));
    expect(PlaybackController.audioGain(dana, 8000, gate: s.playback.gateOf!(dana)), 1);
    // Sam's own quiet part in the preview: silent at 3 s, a ramp at its edge.
    final sam = s.project.audio.firstWhere((a) => a.id == 'v1');
    expect(PlaybackController.audioGain(sam, 3000), 0);
    expect(PlaybackController.audioGain(sam, 2020), closeTo(0.5, 1e-9));
    expect(PlaybackController.audioGain(sam, 1500), 1);
    // The export gets the same lists.
    expect((await s.exportGates()).keys, ['v2']);
    await fakes.screenshot(tester, 'editor_desktop_quiet_wave');

    // The track menu has the switch and the level.
    await tester.tap(key('track-header-dana'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(key('gate-dana')).value, isTrue);
    expect(key('gate-level-dana'), findsOneWidget);
    await tester.tap(key('gate-dana'));
    await tester.pumpAndSettle();
    expect(s.project.trackById('dana')!.gate, isFalse);
    expect(s.gates, isEmpty);
    expect(s.editor.history.last.label, 'Only when speaking off for Dana');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick selections: a double-click on a voice selects that '
      'speaker\'s turn; the pause here; the suggestion for two microphones',
      (tester) async {
    await open(tester, desk);
    final s = session(tester);
    final actions = EditorActions(s);
    final context = tester.element(key('audio-v1'));
    // Sam talks 1 s..5 s: a double-click at about 2 s on his row.
    final block = tester.getTopLeft(key('audio-v1'));
    await tester.tapAt(block + const Offset(2000 * 0.06, 12));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(block + const Offset(2000 * 0.06, 12));
    await tester.pumpAndSettle();
    expect(s.part.value!.startMs, closeTo(1000, 40));
    expect(s.part.value!.endMs, closeTo(5000, 40));
    s.clearPart();

    // The pause of the selected speaker under the playhead (Sam: 5-12 s).
    s.playback.seek(8000);
    await tester.pumpAndSettle();
    actions.run(context, Act.partPause);
    await tester.pumpAndSettle();
    expect(s.part.value!.startMs, closeTo(5000, 40));
    expect(s.part.value!.endMs, closeTo(12000, 40));
    // While he talks there is no pause: it says so and keeps the part.
    s.playback.seek(3000);
    await tester.pumpAndSettle();
    actions.run(context, Act.partPause);
    await tester.pumpAndSettle();
    expect(find.textContaining('not in a pause'), findsOneWidget);
    actions.run(context, Act.partTurn);
    await tester.pumpAndSettle();
    expect(s.part.value!.startMs, closeTo(1000, 40));

    // Two voice tracks, no gate yet: the suggestion applies; with one on,
    // it does not.
    final gate =
        kSuggestions.firstWhere((x) => x.id == 'only-when-speaking');
    expect(gate.when(SuggestionContext(s)), isTrue);
    s.editor.editor.setOnlyWhenSpeaking('sam', on: true);
    expect(gate.when(SuggestionContext(s)), isFalse);
    expect(kSuggestions.firstWhere((x) => x.id == 'clip-shape').repeats, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Drawing sound… 1 of 4" with a cross that stops it',
      (tester) async {
    final fakes = fakesFor(talk());
    fakes.engine.gate = Completer<void>();
    await open(tester, desk, fakes: fakes);
    final s = session(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Drawing sound… 1 of 4'), findsOneWidget);
    expect(key('drawing-sound-stop'), findsOneWidget);
    await tester.tap(key('drawing-sound-stop'));
    fakes.engine.gate!.complete();
    await tester.pumpAndSettle();
    expect(s.pictures.stopped, isTrue);
    expect(s.pictures.busy, isFalse);
    expect(key('drawing-sound'), findsNothing);
    expect(fakes.engine.asked.length, 1, reason: 'the others were not read');
    // Asked for again.
    s.pictures.resume();
    await tester.pumpAndSettle();
    expect(fakes.engine.asked.toSet().length, 4);
    expect(s.pictures.peaksOf(samFile, 0), isNotNull);
    expect(tester.takeException(), isNull);
  });

  test('wording helpers: shapes in words, versions, the keys note', () {
    expect(shapeWords(1920, 1080), '16:9 wide');
    expect(shapeWords(1080, 1920), '9:16 upright');
    expect(shapeWords(1080, 1080), '1:1 square');
    expect(shapeWords(1080, 1350), '4:5 upright');
    expect(shapeWords(1440, 1080), '4:3 wide');
    expect(shapeWords(2000, 1000), 'wide (2.00:1)');
    expect(olderThanMinor('1.16.0', 17), isTrue);
    expect(olderThanMinor('1.17.0', 17), isFalse);
    expect(olderThanMinor('2.0.0', 17), isFalse);
    expect(olderThanMinor(null, 17), isTrue);
    expect(olderThan115('1.14.1'), isTrue);
  });

  testWidgets('"Two keys changed": what I and O do now, and Q and W',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showKeysMoved(context),
                child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Two keys changed'), findsOneWidget);
    expect(find.textContaining('press Q and W'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keys-moved-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Two keys changed'), findsNothing);
  });
}
