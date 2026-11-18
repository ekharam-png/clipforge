import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/ui/services.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

List<Project> someProjects() => [
      sampleProject(),
      Project(
        id: 'p2',
        name: 'Birthday dinner with a rather long project name to cut off',
        createdAt: DateTime(2026, 10, 2),
        updatedAt: DateTime(2026, 10, 3, 8, 5),
      ),
      sampleProject(id: 'p3', name: 'Garden'),
    ];

void main() {
  setUpAll(loadFonts);

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('lists projects on a $label screen', (tester) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: someProjects());
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Summer trip'), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget);
      expect(find.textContaining('0:18'), findsNWidgets(2));
      expect(find.textContaining('14 Nov 2026, 18:30'), findsNWidgets(2));
      expect(find.text('New project'), findsOneWidget);
      await fakes.screenshot(tester, 'home_$label');
    });
  }

  testWidgets('empty state offers to start a project', (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes();
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No projects yet'), findsOneWidget);
    await fakes.screenshot(tester, 'home_empty_phone');

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(fakes.store.projects, hasLength(1));
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('Add videos or photos'), findsOneWidget);
  });

  testWidgets('delete asks first', (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(projects: someProjects());
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete project?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fakes.store.projects, hasLength(3));

    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fakes.store.projects.keys, isNot(contains('p1')));
    expect(find.text('Summer trip'), findsNothing);
  });

  testWidgets('rename changes the name in the store', (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(projects: someProjects());
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Holiday');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fakes.store.projects['p1']!.name, 'Holiday');
    expect(find.text('Holiday'), findsOneWidget);
  });

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('duplicate and share a project file on a $label screen',
        (tester) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: someProjects());
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Project options').first);
      await tester.pumpAndSettle();
      await fakes.screenshot(tester, 'home_${label}_menu');
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(fakes.store.projects, hasLength(4));
      expect(find.text('Summer trip copy'), findsOneWidget);
      expect(find.text('Summer trip'), findsOneWidget);

      // Sharing packs the project into one file and shows how far it is.
      fakes.bundles.exportGate = Completer<void>();
      await tester.tap(find.byTooltip('Project options').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share project file'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Packing "Summer trip"'), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.5);
      await fakes.screenshot(tester, 'home_${label}_share');
      fakes.bundles.exportGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Packing'), findsNothing);
      expect(fakes.bundles.exported, ['/out/Summer trip.clipforge.zip']);
      expect(
          find.text('Project file saved: /out/Summer trip.clipforge.zip'),
          findsOneWidget);
    });

    testWidgets('open a project file on a $label screen', (tester) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: someProjects());
      fakes.bundles.bundles['/in/trip.clipforge.zip'] =
          sampleProject(id: 'elsewhere', name: 'From my phone');
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();

      // Cancelling the picker changes nothing.
      await tester.tap(find.text('Open project file'));
      await tester.pumpAndSettle();
      expect(fakes.store.projects, hasLength(3));

      fakes.documents.pick =
          const PickedFile('/in/trip.clipforge.zip', 'trip.clipforge.zip');
      await tester.tap(find.text('Open project file'));
      await tester.pumpAndSettle();
      expect(fakes.store.projects, hasLength(4));
      expect(find.text('From my phone'), findsOneWidget);
      expect(find.text('"From my phone" was added to your projects.'),
          findsOneWidget);

      // Something that is not a project file says so.
      fakes.documents.pick = const PickedFile('/in/other.zip', 'other.zip');
      await tester.tap(find.text('Open project file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not open the project file'),
          findsOneWidget);
      expect(fakes.store.projects, hasLength(4));
    });
  }

  testWidgets('a cancelled share shows nothing and packs nothing',
      (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(projects: someProjects());
    fakes.documents.cancelSave = true;
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share project file'));
    await tester.pumpAndSettle();
    expect(fakes.bundles.exported, isEmpty);
    expect(find.textContaining('Project file saved'), findsNothing);
  });

  testWidgets('phone: the project file goes to the share sheet',
      (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(projects: someProjects());
    fakes.documents.phone = true;
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share project file'));
    await tester.pumpAndSettle();
    expect(fakes.bundles.exported, ['/cache/Summer trip.clipforge.zip']);
    expect(fakes.documents.sharedFiles, ['Summer trip.clipforge.zip']);
    expect(fakes.documents.savedFiles, isEmpty);
    // The share sheet is the confirmation; no path in a private folder.
    expect(find.textContaining('Project file saved'), findsNothing);
    expect(find.textContaining('Packing'), findsNothing);

    // Closing the sheet without choosing says that nothing was sent.
    fakes.documents.dismissShare = true;
    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share project file'));
    await tester.pumpAndSettle();
    expect(find.text('The project file was not sent anywhere.'),
        findsOneWidget);
  });

  for (final (label, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('media left out of a project file is listed on a $label screen',
        (tester) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: someProjects());
      fakes.documents.phone = size == phone;
      fakes.bundles.skipped = const ['/media/gone.mp4'];
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Project options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share project file'));
      await tester.pumpAndSettle();
      expect(find.text('One file is not in the project file'), findsOneWidget);
      expect(find.text('/media/gone.mp4'), findsOneWidget);
      await fakes.screenshot(tester, 'home_${label}_share_skipped');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Project file saved'),
          size == phone ? findsNothing : findsOneWidget);
    });

    testWidgets('a damaged project is shown, not hidden, on a $label screen',
        (tester) async {
      useScreen(tester, size);
      final fakes = Fakes(projects: someProjects());
      fakes.damaged = [
        DamagedProject(id: '3f2a-broken', modified: DateTime(2026, 11, 2, 10)),
      ];
      await tester.pumpWidget(fakes.app(const HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text("Can't open (damaged file)"), findsOneWidget);
      expect(find.textContaining('folder 3f2a-broken'), findsOneWidget);
      await fakes.screenshot(tester, 'home_${label}_damaged');
      // It cannot be opened and has no menu.
      await tester.tap(find.text("Can't open (damaged file)"));
      await tester.pumpAndSettle();
      expect(find.byType(EditorScreen), findsNothing);
      expect(find.byTooltip('Project options'), findsNWidgets(3));
    });
  }

  testWidgets('only damaged projects: still a list, not "no projects yet"',
      (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes()..damaged = const [DamagedProject(id: 'broken')];
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No projects yet'), findsNothing);
    expect(find.text("Can't open (damaged file)"), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Open project file'), findsOneWidget);
  });

  testWidgets('the app tidies its own media once at start and after a delete',
      (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes(projects: someProjects());
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(fakes.cleanups, 1);

    // Coming back from the editor is not a new start.
    await tester.tap(find.text('Garden'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to projects'));
    await tester.pumpAndSettle();
    expect(fakes.cleanups, 1);

    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The question says what happens to the copies.
    expect(find.textContaining('Copies the app made for it'), findsOneWidget);
    expect(find.textContaining('your own folders'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fakes.cleanups, 1);

    await tester.tap(find.byTooltip('Project options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fakes.store.projects, hasLength(2));
    expect(fakes.cleanups, 2);
  });

  testWidgets('the empty state can open a project file too', (tester) async {
    useScreen(tester, phone);
    final fakes = Fakes();
    fakes.bundles.bundles['/in/a.zip'] = sampleProject(name: 'Brought over');
    fakes.documents.pick = const PickedFile('/in/a.zip', 'a.zip');
    await tester.pumpWidget(fakes.app(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open project file'));
    await tester.pumpAndSettle();
    expect(find.text('Brought over'), findsOneWidget);
  });
}
