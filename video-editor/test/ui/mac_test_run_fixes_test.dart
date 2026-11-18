// Small issues from the owner's Mac test run.
import 'package:clipforge/ui/editor/preview_view.dart';
import 'package:clipforge/ui/editor/session.dart';
import 'package:clipforge/ui/editor/tools.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

EditorSession sessionOf(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView)).session;

/// The Delete button of the desktop side panel.
Finder inspectorDelete() => find.descendant(
    of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'InspectorPanel'),
    matching: find.text('Delete'));

void main() {
  setUpAll(loadFonts);

  testWidgets('icon-only buttons have names for assistive tools',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openEditor(tester, desktop);
    for (final name in [
      'Back to projects',
      'Undo',
      'Redo',
      'Back to start',
      'Play',
      'Zoom out timeline',
      'Zoom in timeline',
    ]) {
      expect(find.bySemanticsLabel(name), findsWidgets, reason: name);
    }
    semantics.dispose();
  });

  testWidgets('desktop: the Delete button removes a selected photo',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    await tester.tap(block('clip-b'));
    await tester.pumpAndSettle();
    expect(s.selectedClip?.id, 'b');
    expect(find.text('Photo'), findsOneWidget);
    await tester.tap(inspectorDelete());
    await tester.pumpAndSettle();
    expect(s.project.clips.map((c) => c.id), ['a', 'c', 'd']);
  });

  testWidgets('the tool buttons can be pressed through accessibility',
      (tester) async {
    // Assistive tools and test automation press a button through its
    // semantics node; the tool buttons used to drop that action.
    final semantics = tester.ensureSemantics();
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    await tester.tap(block('clip-b'));
    await tester.pumpAndSettle();
    final node = find.semantics.byLabel('Delete').evaluate().single;
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Delete'));
    await tester.pumpAndSettle();
    expect(s.project.clips.map((c) => c.id), ['a', 'c', 'd']);
    semantics.dispose();
  });

  testWidgets('the title size slider changes the size', (tester) async {
    final semantics = tester.ensureSemantics();
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    await tester.tap(block('title-t1'));
    await tester.pumpAndSettle();
    double size() => s.project.titles.single.fontSize;
    expect(size(), 0.09);

    // Dragging.
    final slider = find.descendant(
        of: find.ancestor(
            of: find.text('Text size'), matching: find.byType(Column)).first,
        matching: find.byType(Slider));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();
    final dragged = size();
    expect(dragged, greaterThan(0.09));
    expect(find.textContaining('${(dragged * 100).round()}%'), findsOneWidget);

    // The accessibility "decrease" action (what assistive tools use).
    // The slider is one node with its name, value and actions (it was a
    // nameless slider under an unadjustable node called "Text size").
    final named = find.semantics.byPredicate((n) =>
        n.label == 'Text size' &&
        n.getSemanticsData().hasAction(SemanticsAction.decrease));
    final node = named.evaluate().single;
    expect(node.getSemanticsData().value, titleSizeLabel(dragged));
    expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
    tester.semantics.decrease(named);
    await tester.pumpAndSettle();
    expect(size(), lessThan(dragged));

    // One undo step per change.
    s.editor.undo();
    await tester.pumpAndSettle();
    expect(size(), closeTo(dragged, 1e-9));
    semantics.dispose();
  });

  testWidgets('split at the very end of the video says why nothing happens',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    s.playback.seek(s.project.durationMs);
    await tester.pump();
    await tester.tap(find.text('Split').first);
    await tester.pump();
    expect(find.textContaining('at the end of the video'), findsOneWidget);
    expect(s.project.clips, hasLength(4));
  });

  testWidgets('split right at the end of a clip says why nothing happens',
      (tester) async {
    await openEditor(tester, desktop);
    final s = sessionOf(tester);
    // 20 ms before the first clip ends: the second piece would be too short.
    s.playback.seek(s.project.clipStartMs(1) - 20);
    await tester.pump();
    await tester.tap(find.text('Split').first);
    await tester.pump();
    expect(find.textContaining('Too close to the start or end of a clip'),
        findsOneWidget);
    expect(s.project.clips, hasLength(4));
  });
}
