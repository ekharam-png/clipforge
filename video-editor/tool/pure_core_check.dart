// Proves that the editing core runs without Flutter. Run with plain Dart:
//
//   dart run tool/pure_core_check.dart
//
// It imports everything a command-line tool (the MCP server) needs and
// exercises it end to end in a temporary folder. Exits non-zero on failure.

import 'dart:io';

import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/core/model/title_layout.dart';
// Imported on its own to show that the file-backed store needs no Flutter.
// ignore: unnecessary_import
import 'package:clipforge/core/storage/file_project_store.dart';
import 'package:clipforge/core/storage/media_check.dart';
import 'package:clipforge/core/storage/media_cleanup.dart';
import 'package:clipforge/core/storage/project_bundle.dart';
import 'package:clipforge/core/storage/project_store.dart';
import 'package:clipforge/core/subtitles/srt.dart';
import 'package:path/path.dart' as p;

void check(bool ok, String what) {
  if (!ok) {
    stderr.writeln('FAILED: $what');
    exit(1);
  }
  stdout.writeln('ok  $what');
}

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('clipforge_pure');
  try {
    final store = FileProjectStore(p.join(tmp.path, 'projects'));
    final ProjectStore asStore = ProjectStore.atPath(store.rootPath);
    final created = await store.create('Pure');

    final media = File(p.join(tmp.path, 'clip.mp4'));
    await media.writeAsBytes(List<int>.generate(5000, (i) => i % 251));

    var ids = 0;
    var notifications = 0;
    final editor = ProjectEditor(created, newId: () => 'id${++ids}')
      ..addListener(() => notifications++);
    editor.addClip(Clip(
      id: 'a',
      type: ClipType.video,
      path: media.path,
      sourceDurationMs: 10000,
      inMs: 0,
      outMs: 10000,
      width: 1920,
      height: 1080,
    ));
    editor.setClipSpeed('a', 2);
    check(editor.project.durationMs == 5000, 'speed changes timeline length');
    check(editor.splitAt(1000), 'split through speed');
    check(editor.project.clips[0].outMs == 2000, 'split maps to source time');
    editor.setClipTransition(editor.project.clips[1].id, TransitionType.crossfade);
    check(editor.project.durationMs == 4500, 'transition overlap');
    editor.undo();
    editor.redo();
    check(notifications == 6, 'listeners are called');

    final captions = parseSrt(
      '1\n00:00:01,000 --> 00:00:02,500\nHello <i>there</i>\n',
      newId: () => 'id${++ids}',
    );
    editor.addTitles(captions);
    check(toSrt(editor.project.titles).contains('Hello there'), 'srt round trip');
    final lines = layoutTitleLines(
      captions.first.copyWith(text: 'word ' * 40),
      canvasWidth: 1080,
      canvasHeight: 1920,
    );
    check(lines.length > 1, 'title layout wraps');
    final block = layoutTitleBlock(captions.first,
        canvasWidth: 1080, canvasHeight: 1920);
    check(block.fontPx == (captions.first.fontSize * 1080).round(),
        'title size follows the short side');
    check((await findMissingMedia(editor.project)).isEmpty, 'media check');

    await store.save(editor.project);
    final copy = await asStore.duplicate(created.id);
    check(copy.name == 'Pure copy' && copy.id != created.id, 'duplicate');

    final zip = p.join(tmp.path, 'out', 'pure.zip');
    await exportBundle(editor.project, zip);
    final imported = await importBundle(
      zip,
      store: store,
      mediaDir: p.join(tmp.path, 'imported'),
      newId: () => 'imported',
    );
    final path = imported.clips.first.path;
    check(
      p.isAbsolute(path) &&
          path != media.path &&
          File(path).lengthSync() == 5000 &&
          (await store.load('imported')).clips.length == 2,
      'bundle round trip',
    );
    check(
      await removeUnreferencedMedia(p.join(tmp.path, 'imported'), store,
                  now: () => DateTime.now().add(const Duration(hours: 1))) ==
              0 &&
          File(path).existsSync(),
      'media clean-up keeps what projects use',
    );
    stdout.writeln('Pure Dart core check passed.');
  } finally {
    await tmp.delete(recursive: true);
  }
}
