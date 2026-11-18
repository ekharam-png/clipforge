// SubRip (.srt) subtitles <-> caption titles. Pure Dart.

import '../model/project.dart';
import '../model/title_layout.dart';

// One time: [hours:]minutes:seconds[,|.fraction].
const String _time = r'(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?';
final RegExp _timing = RegExp('^\\s*$_time\\s*-+>\\s*$_time');
final RegExp _digits = RegExp(r'^\s*\d+\s*$');
final RegExp _htmlTag =
    RegExp(r'</?(?:i|b|u|s|em|strong|font)(?:\s[^>]*)?>', caseSensitive: false);
final RegExp _assTag = RegExp(r'\{\\[^}]*\}');

int _ms(RegExpMatch m, int g) {
  final h = int.parse(m.group(g) ?? '0');
  final min = int.parse(m.group(g + 1)!);
  final s = int.parse(m.group(g + 2)!);
  // "5" after the separator is half a second, like a decimal fraction.
  final frac = int.parse((m.group(g + 3) ?? '0').padRight(3, '0'));
  return ((h * 60 + min) * 60 + s) * 1000 + frac;
}

/// Reads SubRip text into caption titles (styled by [captionStyle]), in
/// file order. [newId] supplies the id of each title.
///
/// Tolerant of what real files contain: a byte order mark, CRLF or CR line
/// ends, missing index lines, missing blank lines between cues, `.`
/// instead of `,` before the milliseconds, missing hours or milliseconds
/// and position info after the times. Simple formatting tags (`<i>`,
/// `<b>`, `<u>`, `<font ...>`, `{\an8}`) are removed. Cues without a
/// readable time line, without text, or that end at or before their start
/// are skipped. Never throws on bad input; a file with no usable cue
/// gives an empty list.
List<TitleOverlay> parseSrt(String content, {required String Function() newId}) {
  var text = content;
  if (text.startsWith('﻿')) text = text.substring(1);
  final lines =
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final titles = <TitleOverlay>[];
  var i = 0;
  while (i < lines.length) {
    final m = _timing.firstMatch(lines[i]);
    i++;
    if (m == null) continue;
    final start = _ms(m, 1);
    final end = _ms(m, 5);
    final body = <String>[];
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty || _timing.hasMatch(line)) break;
      // An index line directly followed by a time line starts the next cue
      // (the blank line between cues is missing).
      if (_digits.hasMatch(line) &&
          i + 1 < lines.length &&
          _timing.hasMatch(lines[i + 1])) {
        break;
      }
      final clean =
          line.replaceAll(_htmlTag, '').replaceAll(_assTag, '').trim();
      if (clean.isNotEmpty) body.add(clean);
      i++;
    }
    if (body.isEmpty || end <= start) continue;
    titles.add(captionStyle(TitleOverlay(
      id: newId(),
      text: body.join('\n'),
      startMs: start,
      endMs: end,
    )));
  }
  return titles;
}

String _stamp(int ms) {
  final t = ms < 0 ? 0 : ms;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t ~/ 3600000)}:${two(t ~/ 60000 % 60)}:${two(t ~/ 1000 % 60)}'
      ',${(t % 1000).toString().padLeft(3, '0')}';
}

/// Writes the captions among [titles] ([TitleKind.caption] only) as SubRip
/// text, sorted by start time and numbered from 1. Captions without text
/// or without a positive length are left out; blank lines inside a caption
/// are dropped because they would end the cue. Returns '' when there is
/// nothing to write.
String toSrt(List<TitleOverlay> titles) {
  final cues = <({TitleOverlay t, List<String> lines, int order})>[];
  for (var i = 0; i < titles.length; i++) {
    final t = titles[i];
    if (t.kind != TitleKind.caption || t.endMs <= t.startMs) continue;
    final lines = [
      for (final l in t.text.split(RegExp(r'\r\n|\r|\n')))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    if (lines.isEmpty) continue;
    cues.add((t: t, lines: lines, order: i));
  }
  cues.sort((a, b) {
    final byStart = a.t.startMs.compareTo(b.t.startMs);
    if (byStart != 0) return byStart;
    final byEnd = a.t.endMs.compareTo(b.t.endMs);
    return byEnd != 0 ? byEnd : a.order.compareTo(b.order);
  });
  final out = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    out
      ..writeln(i + 1)
      ..writeln('${_stamp(c.t.startMs)} --> ${_stamp(c.t.endMs)}')
      ..writeln(c.lines.join('\n'))
      ..writeln();
  }
  return out.toString();
}
