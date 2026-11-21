// Every test here is bounded: a per-test timeout, loops with a fixed
// number of turns, and settle() that gives up after 10 s of fake time. A
// missed tap can then fail a test but never leave it running.
@Timeout(Duration(seconds: 90))
library;

import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/help/tour.dart';
import 'package:clipforge/ui/help/tour_sample.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

TourController tourOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(TourOverlayHost)))
    .read(tourControllerProvider);

/// The home screen, with the first-launch question not yet answered.
Future<Fakes> openFirstTime(WidgetTester tester, Size size,
    {bool withProjects = false}) async {
  useScreen(tester, size);
  final fakes = Fakes(projects: [if (withProjects) sampleProject()]);
  fakes.prefs.answered = false;
  await tester.pumpWidget(fakes.app(const HomeScreen()));
  await settle(tester);
  return fakes;
}

/// Checks the step on screen: its card, every widget it points at (the
/// test fails when one of them is gone, so a change to the screens cannot
/// silently break the tour), the spotlight on screen, and the card with
/// its Skip button fully visible and not under the spotlight.
void expectStepShown(WidgetTester tester, TourStep step, Size size) {
  expect(find.byKey(ValueKey('tour-card-${step.id}')), findsOneWidget,
      reason: step.id);
  final screen = Offset.zero & size;
  for (final id in step.anchors) {
    final rect = TourAnchors.rectOf(id);
    expect(rect, isNotNull,
        reason: 'Tour step "${step.id}" points at "$id", which is not on '
            'screen. Wrap the widget in TourAnchor(id: TourIds...) again.');
    expect(screen.intersect(rect!).width, greaterThan(8), reason: id);
    expect(screen.intersect(rect).height, greaterThan(8), reason: id);
  }
  final skip = find.text('Skip tour');
  expect(skip, findsOneWidget);
  final skipRect = tester.getRect(skip);
  expect(screen.contains(skipRect.topLeft) && screen.contains(skipRect.bottomRight),
      isTrue, reason: 'Skip must be on screen (${step.id})');
  final card = tester.getRect(find.byKey(ValueKey('tour-card-${step.id}')));
  expect(screen.contains(card.bottomRight - const Offset(1, 1)), isTrue,
      reason: 'card on screen (${step.id})');
  final spot = TourAnchors.unionOf(step.anchors)!;
  // The card may only cover the spotlight when nothing else fits.
  if (spot.height < size.height * 0.5 && spot.width < size.width * 0.6) {
    expect(card.overlaps(spot.deflate(4)), isFalse,
        reason: 'card covers the spotlight (${step.id})');
  }
}

/// pumpAndSettle with a limit: at most 100 frames of 100 ms. The tour has
/// no animation that repeats, so anything longer is a bug.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10));

/// Taps Next (or Finish) until the step [id] is shown; fails after the
/// number of steps there are.
Future<void> advanceTo(WidgetTester tester, String id) async {
  final tour = tourOf(tester);
  for (var i = 0; i < 10; i++) {
    if (tour.step?.id == id) return;
    expect(tour.phase, TourPhase.running, reason: 'looking for step $id');
    await next(tester);
  }
  fail('Tour step $id was never shown');
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  group('first launch', () {
    for (final size in [phone, desktop]) {
      final label = size == phone ? 'phone' : 'desktop';

      testWidgets('$label: asked once; "Not now" points to Help',
          (tester) async {
        final fakes = await openFirstTime(tester, size);
        expect(find.text('Welcome to ClipForge!'), findsOneWidget);
        expect(find.textContaining('Would you like a quick tour?'),
            findsOneWidget);
        expect(find.textContaining('in Help'), findsOneWidget);
        await fakes.screenshot(tester, 'first_launch_$label');
        await tester.tap(find.text('Not now'));
        await settle(tester);
        expect(fakes.prefs.answered, isTrue);
        expect(find.textContaining('"Show the tour"'), findsOneWidget);
        expect(tourOf(tester).active, isFalse);

        // The next start of the app does not ask again.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(fakes.app(const HomeScreen()));
        await settle(tester);
        expect(find.text('Welcome to ClipForge!'), findsNothing);
      });
    }

    testWidgets('"Show me around" starts the tour and is remembered',
        (tester) async {
      final fakes = await openFirstTime(tester, phone);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      expect(fakes.prefs.answered, isTrue);
      expect(tourOf(tester).active, isTrue);
      expect(find.byKey(const ValueKey('tour-card-new-project')),
          findsOneWidget);
      await tester.tap(find.text('Skip tour'));
      await settle(tester);
      expect(tourOf(tester).active, isFalse);
    });
  });

  group('the whole tour', () {
    for (final (size, withProjects) in [
      (phone, false),
      (phone, true),
      (desktop, true),
      (desktop, false),
    ]) {
      final label = size == phone ? 'phone' : 'desktop';
      final list = withProjects ? 'with projects' : 'no projects yet';
      testWidgets('$label, $list: every step points at its buttons',
          (tester) async {
        final fakes =
            await openFirstTime(tester, size, withProjects: withProjects);
        await tester.tap(find.text('Show me around'));
        await settle(tester);
        final tour = tourOf(tester);
        final steps = tour.steps;
        expect(steps.length, inInclusiveRange(6, 8));
        expect(steps.where((s) => !s.inEditor).length, 2);
        for (var i = 0; i < steps.length; i++) {
          expect(tour.index, i);
          expectStepShown(tester, steps[i], size);
          expect(find.text('Step ${i + 1} of ${steps.length}'), findsOneWidget);
          if (withProjects) {
            await fakes.screenshot(tester, 'tour_${label}_${i + 1}_${steps[i].id}');
          }
          if (i == 1) {
            // Into the sample project.
            await next(tester);
            expect(find.byType(EditorScreen), findsOneWidget);
            expect(fakes.samplesMade, 1);
            continue;
          }
          if (i == steps.length - 1) {
            expect(find.text('Finish'), findsOneWidget);
            await tester.tap(find.text('Finish'));
            await settle(tester);
            continue;
          }
          await next(tester);
        }
        expect(find.byKey(const ValueKey('tour-card-end')), findsOneWidget);
        if (withProjects) await fakes.screenshot(tester, 'tour_${label}_end');
        final sampleId = tour.sampleProjectId!;
        expect(fakes.store.projects.containsKey(sampleId), isTrue);
        await tester.tap(find.text('Delete the sample'));
        await settle(tester);
        expect(tour.active, isFalse);
        expect(find.byType(EditorScreen), findsNothing);
        expect(fakes.store.projects.containsKey(sampleId), isFalse);
        expect(find.byType(HomeScreen), findsOneWidget);
      });
    }

    testWidgets('phone: the clip tools step shows Speed, Look and Sound',
        (tester) async {
      await openFirstTime(tester, phone);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      await advanceTo(tester, 'clip-tools');
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Look'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);
    });

    testWidgets('desktop: the clip tools step opens the Sound settings',
        (tester) async {
      await openFirstTime(tester, desktop);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      await advanceTo(tester, 'clip-tools');
      expect(find.text('Clean up sound'), findsOneWidget);
      expect(find.text('Voice focus'), findsOneWidget);
    });

    testWidgets('Keep it: the sample project stays', (tester) async {
      final fakes = await openFirstTime(tester, desktop);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      final tour = tourOf(tester);
      await advanceTo(tester, 'save-export');
      await tester.tap(find.text('Finish'));
      await settle(tester);
      expect(tour.phase, TourPhase.ending);
      await tester.tap(find.text('Keep it'));
      await settle(tester);
      expect(tour.active, isFalse);
      expect(find.byType(EditorScreen), findsNothing);
      expect(fakes.store.projects.values.map((p) => p.name),
          contains(kTourSampleName));
      expect(find.text(kTourSampleName), findsOneWidget);
    });
  });

  group('moving around', () {
    for (final size in [phone, desktop]) {
      final label = size == phone ? 'phone' : 'desktop';

      testWidgets('$label: Back, then Skip in the editor', (tester) async {
        final fakes = await openFirstTime(tester, size);
        await tester.tap(find.text('Show me around'));
        await settle(tester);
        final tour = tourOf(tester);
        expect(find.text('Back'), findsNothing, reason: 'first step');
        await next(tester);
        expect(find.text('Back'), findsOneWidget);
        await tester.tap(find.text('Back'));
        await settle(tester);
        expect(tour.index, 0);
        await next(tester);
        await next(tester); // into the editor
        expect(tour.index, 2);
        expect(find.text('Back'), findsNothing,
            reason: 'no way back to the home screen from the editor');
        await next(tester);
        await tester.tap(find.text('Back'));
        await settle(tester);
        expect(tour.index, 2);
        await next(tester);
        await next(tester);
        expect(tour.step!.id, 'split');
        await tester.tap(find.text('Skip tour'));
        await settle(tester);
        expect(tour.active, isFalse);
        expect(find.byType(EditorScreen), findsNothing);
        expect(fakes.store.projects.values.map((p) => p.name),
            isNot(contains(kTourSampleName)));
      });
    }

    testWidgets('desktop: Esc skips the tour', (tester) async {
      final fakes = await openFirstTime(tester, desktop);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      final tour = tourOf(tester);
      await next(tester);
      await next(tester);
      expect(find.byType(EditorScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(tour.active, isFalse);
      expect(find.byType(EditorScreen), findsNothing);
      expect(fakes.store.projects, isEmpty);
    });

    testWidgets('the app underneath cannot be tapped during the tour',
        (tester) async {
      final fakes = await openFirstTime(tester, phone);
      await tester.tap(find.text('Show me around'));
      await settle(tester);
      await tester.tap(find.text('New video'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(EditorScreen), findsNothing);
      expect(fakes.store.projects, isEmpty);
    });

    testWidgets('with reduced motion the spotlight jumps', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openFirstTime(tester, phone);
      await tester.tap(find.text('Show me around'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final builder = tester.widget<TweenAnimationBuilder<Rect?>>(
          find.byType(TweenAnimationBuilder<Rect?>));
      expect(builder.duration, Duration.zero);
      await settle(tester);
      expectStepShown(tester, tourOf(tester).step!, phone);
      await tester.tap(find.text('Skip tour'));
      await settle(tester);
    });
  });

  group('from Help', () {
    testWidgets('an open project is closed and the tour starts on the list',
        (tester) async {
      useScreen(tester, desktop);
      final fakes = Fakes(projects: [sampleProject()]);
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await settle(tester);
      await tester.tap(find.text('Summer trip'));
      await settle(tester);
      expect(find.byType(EditorScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Help'));
      await settle(tester);
      await tester.tap(find.text('Show the tour'));
      await settle(tester);
      expect(find.byType(EditorScreen), findsNothing);
      final tour = tourOf(tester);
      expect(tour.active, isTrue);
      expectStepShown(tester, tour.step!, desktop);
      await tester.tap(find.text('Skip tour'));
      await settle(tester);
      expect(tour.active, isFalse);
      // The project that was open is untouched.
      expect(fakes.store.projects.keys, ['p1']);
    });

    testWidgets('from the project list', (tester) async {
      useScreen(tester, phone);
      final fakes = Fakes(projects: [sampleProject()]);
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await settle(tester);
      await tester.tap(find.byTooltip('Help'));
      await settle(tester);
      await tester.tap(find.text('Show the tour'));
      await settle(tester);
      expect(tourOf(tester).active, isTrue);
      expectStepShown(tester, tourOf(tester).step!, phone);
      await tester.tap(find.text('Skip tour'));
      await settle(tester);
      expect(fakes.store.projects.keys, ['p1']);
    });
  });

  test('the steps for each layout', () {
    final phoneSteps = buildTourSteps(wide: false, canDrop: false);
    final deskSteps = buildTourSteps(wide: true, canDrop: true);
    expect(phoneSteps.map((s) => s.id), deskSteps.map((s) => s.id));
    expect(phoneSteps[5].anchors,
        [TourIds.toolSpeed, TourIds.toolLook, TourIds.toolSound]);
    expect(deskSteps[5].anchors, [TourIds.inspector]);
    expect(deskSteps.first.body, contains('drag'));
    expect(phoneSteps.first.body, isNot(contains('drag')));
    expect(kWideLayoutWidth, lessThan(desktop.width));
  });
}
