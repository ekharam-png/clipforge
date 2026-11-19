// The update log (1.14.1): a plain text file, `update-log.txt`, in the
// update state folder, that the app AND the swap scripts append to - one
// line per step, with the time. It is the evidence when an update did not
// go through on somebody's computer: what was started, with which values,
// what each copy step returned, and where it stopped. It is kept across
// updates and cut down to its newer half when it passes about 200 KB.
//
// Pure Dart (dart:io).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const String kUpdateLogFile = 'update-log.txt';

/// The log is cut down when it is bigger than this.
const int kUpdateLogMaxBytes = 200 * 1024;

class UpdateLog {
  UpdateLog(this.path, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The log in the state folder [stateDir].
  factory UpdateLog.inDir(String stateDir, {DateTime Function()? now}) =>
      UpdateLog(p.join(stateDir, kUpdateLogFile), now: now);

  /// The full path of the file.
  final String path;
  final DateTime Function() _now;

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "2026-11-19 14:03:07" in this computer's time, as the scripts write it.
  static String stamp(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  /// Appends "<time> app: [text]". Never throws: the log is never in the
  /// way of the update.
  void add(String text) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      rotate();
      file.writeAsStringSync(
          '${stamp(_now())} app: ${text.replaceAll('\n', ' ')}\r\n',
          mode: FileMode.append,
          flush: true);
    } catch (_) {}
  }

  /// Keeps the newer half (whole lines) once the file passes [maxBytes].
  void rotate({int maxBytes = kUpdateLogMaxBytes}) {
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() <= maxBytes) return;
      final bytes = file.readAsBytesSync();
      var from = bytes.length - maxBytes ~/ 2;
      while (from < bytes.length && bytes[from - 1] != 0x0A) {
        from++;
      }
      file.writeAsBytesSync([
        ...utf8.encode('(older lines were removed to keep this file small)\r\n'),
        ...bytes.sublist(from),
      ], flush: true);
    } catch (_) {}
  }

  /// Everything in the file ("" when there is none). The cmd script may
  /// write letters in another encoding: they are shown as they come.
  String read() {
    try {
      final file = File(path);
      if (!file.existsSync()) return '';
      return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// The last [count] lines.
  List<String> tail([int count = 40]) {
    final lines = [
      for (final line in read().split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
    return lines.length <= count ? lines : lines.sublist(lines.length - count);
  }

  /// True once a script has written its first line for [token].
  bool hasStarted(String token) => read().contains('started token=$token ');
}

/// The text of "Copy details" / the part "Copy version info" adds: where
/// the log is and its last [count] lines; null when there is no log yet.
String? updateLogReport(String stateDir, {int count = 40}) {
  final log = UpdateLog.inDir(stateDir);
  final lines = log.tail(count);
  if (lines.isEmpty) return null;
  return 'Update log: ${log.path}\n'
      'Its last ${lines.length} lines:\n'
      '${lines.join('\n')}';
}
