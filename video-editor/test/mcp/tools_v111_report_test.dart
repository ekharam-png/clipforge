// 1.11, from the owner's "Claude control test 3" report: project names
// stay unique (and an ambiguous name lists ids and dates), answers stay
// small (ids are counted), honest wording when nothing changed and in dry
// runs, the subtitle "different cut" note is a warning, export estimates
// are remembered per kind of export and given as a range, and silences
// are logged with their cuts per minute.
import 'dart:convert';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
import 'package:clipforge/mcp/export_jobs.dart';
import 'package:clipforge/mcp/report.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Bench b;
  late Client c;
  setUp(() {
    b = Bench();
    c = b.client;
  });
  tearDown(() => b.dispose());

  test('names: a taken name gets a number, and the answer says so', () async {
    final first = await c.ok('create_project', {'name': 'T3 Podcast'});
    expect(first.project['name'], 'T3 Podcast');
    expect(first.text, isNot(contains('already exists')));
    final second = await c.ok('create_project', {'name': 'T3 Podcast'});
    expect(second.project['name'], 'T3 Podcast (2)');
    expect(second.text, contains('A project called "T3 Podcast" already exists'));
    final copy = await c.ok('duplicate_project',
        {'project_id': first.project['id'], 'name': 't3 podcast'});
    expect(copy.project['name'], 't3 podcast (3)');
    expect(copy.text, contains('got a number'));
    final plain = await c.ok('duplicate_project', {'project_id': first.project['id']});
    expect(plain.project['name'], 'T3 Podcast copy');
    expect(plain.text, isNot(contains('got a number')));
  });

  test('an ambiguous name lists the matches with ids and dates', () async {
    // Two projects with one name can still exist (made before 1.11).
    await b.seed('one', name: 'T3 Podcast', clips: [b.video('a')]);
    await b.seed('two', name: 'T3 Podcast');
    final text = await c.fails('get_project', {'project_id': 'T3 Podcast'});
    expect(text, contains('2 projects are called "T3 Podcast"'));
    expect(text, contains('project_id one'));
    expect(text, contains('project_id two'));
    expect(text, contains('last changed 2026-01-02'));
    expect(text, contains('Ask the user which one'));
    // The id always works.
    await c.ok('get_project', {'project_id': 'two'});
  });

  test('answers count ids instead of listing hundreds', () async {
    await b.seed('p', clips: [b.video('a', source: 600000)]);
    final srt = StringBuffer();
    String t(int s) =>
        '00:${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')},000';
    for (var i = 0; i < 463; i++) {
      srt.writeln('${i + 1}\n${t(i)} --> ${t(i + 1)}\nLine number ${i + 1}\n');
    }
    c.fullDetail = false;
    final r = await c.ok('import_srt', {'project_id': 'p', 'srt_text': srt.toString()});
    expect(r.data['captionsAdded'], 463);
    final titles = (r.data['changes'] as Map)['titles'] as Map;
    expect(titles['addedCount'], 463);
    expect((titles['added'] as List).length, kChangeIds);
    expect(r.text, contains('463 title/caption(s) added'));
    expect(r.text, contains('463 in all'));
    expect(jsonEncode(r.result).length, lessThan(4000));
  });

  test('nothing changed: only that is said; dry runs say "would"', () async {
    await b.seed('p', clips: [b.video('a'), b.video('b', file: 'b.mp4')]);
    final first = await c.ok('set_project_settings', {'project_id': 'p', 'aspect': '9:16'});
    expect(first.data['changed'], isTrue);
    final same = await c.ok('set_project_settings', {'project_id': 'p', 'aspect': '9:16'});
    expect(same.data['changed'], isFalse);
    expect(same.text, startsWith('Nothing was changed'));
    expect(same.text.split('\n').first, isNot(contains('Updated')));
    expect('Nothing was changed'.allMatches(same.text).length, 1);
    final dry = await c.ok('set_clip_properties',
        {'project_id': 'p', 'clip_id': 'all', 'volume': 0.5, 'dry_run': true});
    expect(dry.text, startsWith('DRY RUN - nothing was saved. Would '));
    expect(dry.text.split('\n').first, isNot(matches(RegExp(r'saved\. (Set|Updated|Changed) '))));
    final sep = await c.ok('separate_sound',
        {'project_id': 'p', 'all': true, 'dry_run': true});
    expect(sep.text, startsWith('DRY RUN - nothing was saved. Would separate'));
  });

  test('History names an align or outline change for what it is', () async {
    await b.seed('p', clips: [
      b.video('a')
    ], titles: [
      const TitleOverlay(id: 't', text: 'Hello', startMs: 0, endMs: 2000),
    ]);
    final before = await b.store.load('p');
    await c.ok('update_title', {'project_id': 'p', 'title_id': 't', 'align': 'right'});
    final aligned = await b.store.load('p');
    // Right-aligned text is anchored at the right edge (x = 1): the layout
    // keeps the whole block inside the frame (title_layout `place`; the
    // pixel test is v17_integration_test "alignment holds").
    expect(aligned.titles.single.x, 1.0);
    final block = layoutTitleBlock(aligned.titles.single,
        canvasWidth: 1920, canvasHeight: 1080);
    expect(block.left + block.width, lessThanOrEqualTo(1920 * 0.98 + 0.01));
    expect(block.left, greaterThan(960));
    // The History label, through the editor (what the app and the tools
    // both use): alignment moves x too, and is still named alignment.
    final e = ProjectEditor(before);
    e.updateTitle(before.titles.single.copyWith(align: TitleAlign.right, x: 1.0));
    expect(e.history.last.label, startsWith('Lined up title'));
    e.updateTitle(e.project.titles.single.copyWith(outline: true, y: 0.1));
    expect(e.history.last.label, startsWith('Outline on title'));
    e.updateTitle(e.project.titles.single.copyWith(y: 0.5));
    expect(e.history.last.label, startsWith('Moved title'));
    final small = smallExportNote(aligned, ExportQuality.small, ExportFormat.video)!;
    expect(small, contains('a graphics card encoder just keeps to the cap'));
  });

  group('export time estimate', () {
    final project = Project(
        id: 'p',
        name: 'p',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        clips: const [
          Clip(
              id: 'a',
              type: ClipType.video,
              path: '/v.mp4',
              sourceDurationMs: 1361000,
              inMs: 0,
              outMs: 1361000,
              width: 1280,
              height: 720),
        ]);

    test('a speed is remembered per kind: graphics card, processor, sound',
        () {
      final guess = estimateRenderMs(project, const ExportOptions());
      expect(guess.rough, isTrue);
      expect(guess.basis, contains('rough'));
      expect(guess.lowMs, lessThan(guess.ms));
      expect(guess.highMs, greaterThan(2 * guess.ms));
      // The owner's laptop: 22:41 in 1:28 on the card = 14 MP-s per second.
      final card = estimateRenderMs(project, const ExportOptions(),
          speeds: {'video-gpu': 14.2, 'video-cpu': 2.9});
      expect(card.rough, isFalse);
      expect(card.ms, inInclusiveRange(80000, 100000));
      expect(card.basis, contains('graphics card'));
      // Graphics card off: the processor's speed, not the card's.
      final cpu = estimateRenderMs(
          project, const ExportOptions(useHardwareEncoder: false),
          speeds: {'video-gpu': 14.2, 'video-cpu': 2.9});
      expect(cpu.ms, greaterThan(4 * card.ms));
      expect(cpu.basis, contains('processor'));
      // Only a processor speed is known, card asked for: said so.
      final unknownCard = estimateRenderMs(project, const ExportOptions(),
          speeds: {'video-cpu': 2.9});
      expect(unknownCard.basis, contains('a graphics card'));
      // Sound only: 22:41 took 1:10 = about 19x.
      final sound = estimateRenderMs(
          project, const ExportOptions(format: ExportFormat.m4a));
      expect(sound.ms, inInclusiveRange(55000, 85000));
      final soundKnown = estimateRenderMs(
          project, const ExportOptions(format: ExportFormat.m4a),
          speeds: {'sound': 40});
      expect(soundKnown.ms, lessThan(sound.ms));
      expect(soundKnown.rough, isFalse);
    });

    test('titles, overlays and sound items make it longer', () {
      final plain = estimateRenderMs(project, const ExportOptions(), speeds: {'video-cpu': 3});
      final busy = estimateRenderMs(
          project.copyWith(titles: [
            for (var i = 0; i < 20; i++)
              TitleOverlay(id: 't$i', text: 'x', startMs: i * 1000, endMs: i * 1000 + 900),
          ], overlays: [
            OverlayClip(clip: project.clips.single.copyWith(id: 'o'), startMs: 0),
          ]),
          const ExportOptions(),
          speeds: {'video-cpu': 3});
      expect(busy.ms, greaterThan((plain.ms * 1.5).round()));
      expect(busy.basis, contains('20 title(s)'));
      expect(busy.basis, contains('1 overlay item(s)'));
    });

    test('the speed of a finished job is filed under what really ran', () {
      ExportJobRecord job(String id, String format, bool hw, Map<String, dynamic> result) =>
          ExportJobRecord(
            id: id,
            projectId: 'p',
            projectName: 'p',
            outputPath: '/o.mp4',
            partPath: '/o.part.mp4',
            format: format,
            quality: 'full',
            fps: 30,
            hardware: true,
            overwrite: false,
            createdAt: DateTime.utc(2026),
            projectDurationMs: 1000,
            estimateMs: 1,
            status: kJobFinished,
            host: 'pc',
            result: {...result, 'hardwareEncoder': hw},
          );
      final jobs = [
        job('3', 'm4a', false, {'timesRealTime': 19.4}),
        // Asked for the card, ran on the processor (no card): processor.
        job('2', 'video', false, {'megapixelSecondsPerSecond': 2.9}),
        job('1', 'video', true, {'megapixelSecondsPerSecond': 14.2}),
      ];
      expect(rememberedSpeed(jobs, 'video-gpu'), 14.2);
      expect(rememberedSpeed(jobs, 'video-cpu'), 2.9);
      expect(rememberedSpeed(jobs, 'sound'), 19.4);
      expect(rememberedSpeed(jobs, 'sound', host: 'another'), isNull);
    });
  });
}
