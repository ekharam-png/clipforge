// 1.14.1: the update log (update-log.txt) - the evidence an update leaves
// behind: lines from the app and from the scripts, kept across updates,
// cut down when it grows, and its last lines for a bug report.

import 'dart:io';

import 'package:clipforge/core/update/update_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_updlog_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('lines carry the time and who wrote them; the folder is made', () {
    final state = p.join(tmp.path, 'not', 'there', 'yet');
    final log = UpdateLog.inDir(state, now: () => DateTime(2026, 11, 19, 9, 5, 7));
    expect(log.path, p.join(state, 'update-log.txt'));
    expect(log.tail(), isEmpty);
    expect(updateLogReport(state), isNull, reason: 'no log, nothing to add');
    log.add('swap: mode=update');
    log.add('two\nlines');
    expect(File(log.path).readAsStringSync(),
        '2026-11-19 09:05:07 app: swap: mode=update\r\n'
        '2026-11-19 09:05:07 app: two lines\r\n');
  });

  test('the scripts write into the same file; "started" is found by its token', () {
    final log = UpdateLog.inDir(tmp.path);
    log.add('swap: token=77-1');
    expect(log.hasStarted('77-1'), isFalse);
    File(log.path).writeAsStringSync(
        '2026-11-19 09:05:08 script(ps): started token=77-1 pid=4242 mode=update\r\n',
        mode: FileMode.append);
    expect(log.hasStarted('77-1'), isTrue);
    expect(log.hasStarted('77-10'), isFalse);
    expect(log.hasStarted('77'), isFalse, reason: 'the whole token');
    // Letters in another encoding (the cmd script) do not break reading.
    File(log.path).writeAsBytesSync(
        [...'x script(cmd): install=[C:\\Vid'.codeUnits, 0xE9, ...'os]\r\n'.codeUnits],
        mode: FileMode.append);
    expect(log.tail().last, startsWith('x script(cmd): install=[C:\\Vid'));
  });

  test('the last 40 lines, with the full path, for a bug report', () {
    final log = UpdateLog.inDir(tmp.path);
    for (var i = 1; i <= 55; i++) {
      log.add('line $i');
    }
    final lines = log.tail();
    expect(lines.length, 40);
    expect(lines.first, endsWith('app: line 16'));
    expect(lines.last, endsWith('app: line 55'));
    final report = updateLogReport(tmp.path)!;
    expect(report, startsWith('Update log: ${log.path}\nIts last 40 lines:\n'));
    expect(report, endsWith('app: line 55'));
    expect(report, isNot(contains('app: line 15\n')));
  });

  test('kept across updates, and cut to its newer half at about 200 KB', () {
    final log = UpdateLog.inDir(tmp.path);
    final line = 'x' * 990;
    for (var i = 0; i < 150; i++) {
      File(log.path).writeAsStringSync('old $i $line\r\n', mode: FileMode.append);
    }
    expect(File(log.path).lengthSync(), lessThan(kUpdateLogMaxBytes));
    log.add('still everything');
    expect(log.read(), contains('old 0 '));
    for (var i = 150; i < 210; i++) {
      File(log.path).writeAsStringSync('old $i $line\r\n', mode: FileMode.append);
    }
    expect(File(log.path).lengthSync(), greaterThan(kUpdateLogMaxBytes));
    log.add('after the cut');
    final text = log.read();
    expect(File(log.path).lengthSync(), lessThan(kUpdateLogMaxBytes * 0.6));
    expect(text, startsWith('(older lines were removed to keep this file small)\r\nold '));
    expect(text, isNot(contains('old 0 ')));
    expect(text, contains('old 209 '));
    expect(text, endsWith('app: after the cut\r\n'));
    expect(text.split('\r\n')[1], matches(RegExp(r'^old \d+ x+$')), reason: 'whole lines');
  });

  test('a log that cannot be written is never in the way', () {
    final file = File(p.join(tmp.path, 'a-file'))..writeAsStringSync('x');
    final log = UpdateLog(p.join(file.path, 'update-log.txt'));
    log.add('nothing happens');
    expect(log.tail(), isEmpty);
    expect(log.hasStarted('t'), isFalse);
  });
}
