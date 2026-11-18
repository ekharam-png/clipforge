// A project with hundreds of pieces and captions is encoded on another
// isolate when saved; the file is the same as for any other project.
import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/storage/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  test('saving and loading a project of 480 pieces and 400 captions',
      () async {
    final root = Directory.systemTemp.createTempSync('big_save').path;
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    final store = ProjectStore.atPath(root);
    final created = await store.create('Podcast');
    final big = created.copyWith(
      clips: [
        for (var i = 0; i < 480; i++)
          video('c$i', source: 2400000, inMs: i * 5000, outMs: i * 5000 + 4000),
      ],
      titles: [
        for (var i = 0; i < 400; i++)
          title('t$i', startMs: i * 4000, endMs: i * 4000 + 3000, text: 'Line $i'),
      ],
    );
    expect(big.clips.length + big.titles.length,
        greaterThanOrEqualTo(kEncodeInBackgroundFrom));
    await store.save(big);
    final file = File(p.join(root, big.id, 'project.json'));
    expect(file.readAsStringSync(),
        const JsonEncoder.withIndent('  ').convert(big.toJson()));
    final loaded = await store.load(big.id);
    expect(content(loaded), content(big));
  });
}
