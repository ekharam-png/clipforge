// Long videos in the editor: the timeline builds only what is near the
// view, thumbnails come from one strip per file, Remove silences shows
// progress and can be stopped, the export checks the free space and keeps
// the device awake, and long projects get one gentle note.
import 'dart:async';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_jobs.dart';
import 'package:clipforge/ui/editor/editor_screen.dart';
import 'package:clipforge/ui/editor/long_project_note.dart';
import 'package:clipforge/ui/editor/timeline_view.dart';
import 'package:clipforge/ui/long_jobs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// A fake engine that also has the long-video extras.
class LongEngine extends FakeMediaEngine
    implements ThumbnailStripEngine, SilenceJobEngine {
  final List<String> stripRequests = [];
  final List<FakeSilenceJob> silenceJobs = [];

  @override
  Future<ThumbnailStrip> thumbnailStrip(String path,
      {int durationMs = 0, int height = kStripFrameHeight}) async {
    stripRequests.add(path);
    return ThumbnailStrip(
        intervalMs: 10000,
        frames: [for (var i = 0; i < 300; i++) '/thumbs/f$i.jpg']);
  }

  @override
  SilenceJob startSilenceDetection(String path,
      {double? thresholdDb,
      int minSilenceMs = 700,
      int audioTrack = 0,
      AudioChannel channel = AudioChannel.both,
      int fromMs = 0,
      int toMs = 0}) {
    final job = FakeSilenceJob(path, fromMs, toMs);
    silenceJobs.add(job);
    return job;
  }
}

class FakeSilenceJob implements SilenceJob {
  FakeSilenceJob(this.path, this.fromMs, this.toMs) {
    _result.future.ignore();
  }
  final String path;
  final int fromMs;
  final int toMs;
  bool cancelled = false;
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<List<SourceRange>>();

  void report(double f) => _progress.add(f);
  void finish(List<SourceRange> found) => _result.complete(found);

  @override
  SilenceLevels? levels;
  @override
  Stream<double> get progress => _progress.stream;
  @override
  Future<List<SourceRange>> get result => _result.future;
  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(ExportException('Stopped', cancelled: true));
    }
  }
}

class LongFakes extends Fakes {
  LongFakes({super.projects});
  final LongEngine _engine = LongEngine();

  // ignore: overridden_fields
  @override
  LongEngine get engine => _engine;
}

class FakeLongJobs extends LongJobSupport {
  int? free;
  final List<String> calls = [];

  @override
  Future<int?> freeBytes(String directory) async {
    calls.add('free $directory');
    return free;
  }

  @override
  Future<void> exportStarted(
      {required String title, required String text}) async {
    calls.add('started: $text');
  }

  @override
  Future<void> exportEnded() async => calls.add('ended');
}

Clip piece(String id, int inMs, int outMs) => Clip(
      id: id,
      type: ClipType.video,
      path: '/media/long.mp4',
      sourceDurationMs: 2400000,
      inMs: inMs,
      outMs: outMs,
      width: 1280,
      height: 720,
    );

Project longProject({int pieces = 300, int pieceMs = 4000, String id = 'p1'}) =>
    Project(
      id: id,
      name: 'Podcast',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      clips: [
        for (var i = 0; i < pieces; i++)
          piece('c$i', i * (pieceMs + 1000), i * (pieceMs + 1000) + pieceMs),
      ],
      titles: [
        for (var i = 0; i < pieces; i++)
          TitleOverlay(
              id: 't$i',
              text: 'Caption $i',
              startMs: i * pieceMs,
              endMs: i * pieceMs + pieceMs - 500,
              kind: TitleKind.caption),
      ],
    );

Future<LongFakes> openLong(WidgetTester tester, Size size, Project project) async {
  useScreen(tester, size);
  final fakes = LongFakes(projects: [project]);
  await tester.pumpWidget(fakes.app(const EditorScreen(projectId: 'p1')));
  await tester.pumpAndSettle();
  return fakes;
}

ScrollController timelineScroll(WidgetTester tester) => tester
    .widgetList<SingleChildScrollView>(find.descendant(
        of: find.byType(TimelineView),
        matching: find.byType(SingleChildScrollView)))
    .firstWhere((w) => w.scrollDirection == Axis.horizontal)
    .controller!;

void main() {
  setUpAll(loadFonts);
  tearDown(() => LongJobSupport.instance = LongJobSupport.none);

  testWidgets('a 20-minute timeline builds only the blocks near the view',
      (tester) async {
    final fakes = await openLong(tester, desktop, longProject());
    // 300 clips and 300 captions; a few dozen of each are built.
    final built = clipBlocks().evaluate().length;
    expect(built, inInclusiveRange(5, 60));
    expect(find.byKey(const ValueKey('clip-c0')), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-c299')), findsNothing);
    final captions = find.byWidgetPredicate((w) =>
        w is Positioned && '${w.key}'.contains("'title-"));
    expect(captions.evaluate().length, lessThan(80));

    // Thumbnails: one strip for the file, tiles only near the view.
    expect(fakes.engine.stripRequests, ['/media/long.mp4']);
    expect(find.byType(Image).evaluate().length, lessThan(120));

    // Scrolled to the end, the last clip is there and can be selected.
    final scroll = timelineScroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clip-c0')), findsNothing);
    expect(find.byKey(const ValueKey('clip-c299')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clip-c299')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Trim start'), findsOneWidget);
    expect(fakes.engine.stripRequests, hasLength(1));
  });

  testWidgets('zooming far in keeps the playhead area built',
      (tester) async {
    await openLong(tester, desktop, longProject());
    // Into the middle, then the largest zoom: the view stays there.
    final scroll = timelineScroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Zoom in timeline'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final view = tester.getRect(find.byType(TimelineView));
    final onScreen = clipBlocks().evaluate().where((e) {
      final r = tester.getRect(find.byWidget(e.widget));
      return r.right > view.left && r.left < view.right;
    });
    expect(onScreen, isNotEmpty);
  });

  testWidgets('remove silences: progress, pieces, and Cancel stops it',
      (tester) async {
    final project = Project(
      id: 'p1',
      name: 'Talk',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      clips: [piece('a', 60000, 660000)],
    );
    final fakes = await openLong(tester, desktop, project);
    await tester.tapAt(tester.getTopLeft(block('clip-a')) + const Offset(60, 20));
    await tester.pumpAndSettle();
    await openClipTool(tester, desktop, 'Sound');
    await tester.ensureVisible(find.text('Remove silences'));
    await tester.tap(find.text('Remove silences'));
    await tester.pump();
    final job = fakes.engine.silenceJobs.single;
    // Only the part of the file the clip uses is listened to.
    expect([job.fromMs, job.toMs], [60000, 660000]);
    job.report(0.4);
    await tester.pump();
    expect(find.text('40%'), findsOneWidget);
    expect(find.textContaining('Cancel stops it'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(job.cancelled, isTrue);
    expect(find.text('Remove silences'), findsWidgets);

    // Again, to the end: the number of pieces is said before applying.
    await tester.tap(find.text('Remove silences'));
    await tester.pump();
    final again = fakes.engine.silenceJobs.last;
    again.finish(const [
      (startMs: 100000, endMs: 101000),
      (startMs: 200000, endMs: 201000),
      (startMs: 650000, endMs: 700000),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('This will cut the clip into 3 pieces. One Undo puts '
        'everything back.'), findsOneWidget);
    await tester.tap(find.text('Remove 3 gaps'));
    await tester.pumpAndSettle();
    expect(find.text('Removed 3 silent gaps. Undo brings them back.'),
        findsOneWidget);
    // The last piece is far to the right: not built until scrolled to.
    expect(clipBlocks(), findsNWidgets(2));
  });

  testWidgets('export: size shown, too little space stops it, tight asks',
      (tester) async {
    final jobs = FakeLongJobs()..free = 50 * 1000 * 1000;
    LongJobSupport.instance = jobs;
    final fakes = await openLong(tester, desktop, longProject(pieces: 300));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-size')), findsOneWidget);
    expect(find.textContaining('File size: about'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
    await tester.pumpAndSettle();
    expect(find.text('Not enough free space'), findsOneWidget);
    expect(fakes.engine.jobs, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Export video'), findsOneWidget);

    // Room for the usual size, not for the largest: asks, and goes on.
    jobs.free = 700 * 1000 * 1000;
    await tester.tap(find.widgetWithText(FilledButton, 'Export').last);
    await tester.pumpAndSettle();
    expect(find.text('Space is tight'), findsOneWidget);
    await tester.tap(find.text('Export anyway'));
    await tester.pump();
    await tester.pump();
    expect(fakes.engine.jobs, hasLength(1));
    expect(find.text('Exporting…'), findsOneWidget);
    expect(find.textContaining('Keep ClipForge open while it exports.'),
        findsOneWidget);
    expect(jobs.calls.last, 'started: Keep ClipForge open while it exports.');
    fakes.engine.jobs.single.finish('/out/movie.mp4');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Video saved'), findsOneWidget);
    expect(jobs.calls.last, 'ended');
  });

  testWidgets('a long project gets the note once', (tester) async {
    final fakes = await openLong(tester, phone, longProject(pieces: 300));
    expect(find.text(kLongProjectNote), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text(kLongProjectNote), findsNothing);
    expect(fakes.prefs.flags, contains('longProjectNote.p1'));

    // Opened again (a new run of the app: only the setting remembers).
    await tester.pumpWidget(const SizedBox());
    final again = LongFakes(projects: [longProject(pieces: 300)]);
    again.prefs.flags.addAll(fakes.prefs.flags);
    await tester.pumpWidget(again.app(const EditorScreen(projectId: 'p1')));
    await tester.pumpAndSettle();
    expect(find.text(kLongProjectNote), findsNothing);
  });

  test('free space from df -Pk', () {
    expect(
        parseDfAvailableBytes(
            'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
            '/dev/vda        263174212  36700000 4194304      90% /\n'),
        4194304 * 1024);
    // A long device name puts the numbers on the next line.
    expect(
        parseDfAvailableBytes('Filesystem 1024-blocks Used Available Capacity Mounted on\n'
            '/dev/mapper/very-long-volume-name\n'
            '   1000 400 600 40% /home\n'),
        600 * 1024);
    expect(parseDfAvailableBytes('df: /nope: No such file'), isNull);
  });

  testWidgets('a short project gets no note', (tester) async {
    await openLong(tester, phone, longProject(pieces: 20, id: 'p1'));
    expect(find.text(kLongProjectNote), findsNothing);
  });
}
