// Readers for what whisper programs write. Pure Dart, no I/O.
//
//  * whisper.cpp `-oj` / `-ojf`: {"result":{"language":"ru"},
//    "transcription":[{"offsets":{"from":0,"to":3200},"text":" ...",
//    "tokens":[{"text":" Hello","offsets":{"from":0,"to":320}}]}]}.
//    With `-ml 1 -sow` every entry is one word.
//  * OpenAI whisper / faster-whisper / whisper-ctranslate2
//    `--output_format json`: {"text":..., "language":"en", "segments":
//    [{"start":0.0,"end":3.2,"text":" ...","words":[{"word":" Hello",
//    "start":0.0,"end":0.32}]}]} (seconds).
//  * FFmpeg's whisper filter `format=json`: one object per line,
//    {"start":0,"end":3200,"text":"..."} (ms), the text NOT escaped.
//  * SubRip (.srt), which all of them can write.

import 'dart:convert';

import '../../core/subtitles/srt.dart';
import '../../core/transcript/transcript.dart';
import 'transcription.dart';

int _ms(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
int _secMs(Object? v) => v is num ? (v * 1000).round() : 0;

Map<String, dynamic> _object(String content, String what) {
  final Object? j;
  try {
    j = jsonDecode(content);
  } on FormatException catch (e) {
    throw SpeechException('$what wrote a result that cannot be read '
        '(${e.message}).', kind: 'failed');
  }
  if (j is! Map) {
    throw SpeechException('$what wrote a result that cannot be read.',
        kind: 'failed');
  }
  return j.cast<String, dynamic>();
}

/// whisper.cpp JSON. [wordPerEntry]: it ran with `-ml 1 -sow`, so every
/// entry is a word (pieces without a leading space continue the word
/// before them).
BackendResult parseWhisperCppJson(String content, {bool wordPerEntry = false}) {
  final j = _object(content, 'whisper.cpp');
  final list = (j['transcription'] as List?) ?? const [];
  final language = languageCode(((j['result'] as Map?)?['language']) as String?);
  final segments = <RawSegment>[];
  var measured = false;
  for (final e in list) {
    if (e is! Map) continue;
    final off = (e['offsets'] as Map?) ?? const {};
    final from = _ms(off['from']), to = _ms(off['to']);
    final text = '${e['text'] ?? ''}';
    final tokens = e['tokens'];
    if (wordPerEntry) {
      final t = text.trim();
      if (t.isEmpty) continue;
      measured = true;
      final continues = !text.startsWith(' ') &&
          segments.isNotEmpty &&
          from - segments.last.endMs < 80;
      if (continues) {
        final prev = segments.removeLast();
        final word = TranscriptWord(prev.text + t, prev.startMs, to);
        segments.add(RawSegment(word.startMs, word.endMs, word.text, [word]));
      } else {
        segments.add(RawSegment(from, to, t, [TranscriptWord(t, from, to)]));
      }
      continue;
    }
    final words = <TranscriptWord>[];
    if (tokens is List) {
      for (final tk in tokens) {
        if (tk is! Map) continue;
        final raw = '${tk['text'] ?? ''}';
        if (raw.trim().isEmpty || raw.startsWith('[_')) continue;
        final o = (tk['offsets'] as Map?) ?? const {};
        final a = _ms(o['from']), b = _ms(o['to']);
        if (words.isNotEmpty && !raw.startsWith(' ')) {
          final prev = words.removeLast();
          words.add(TranscriptWord(prev.text + raw.trim(), prev.startMs, b));
        } else {
          words.add(TranscriptWord(raw.trim(), a, b));
        }
      }
    }
    if (words.isNotEmpty) measured = true;
    segments.add(RawSegment(from, to, text.trim(), words));
  }
  return BackendResult(segments,
      language: language, wordsMeasured: measured, regroup: wordPerEntry);
}

/// The JSON of OpenAI whisper, faster-whisper and whisper-ctranslate2.
BackendResult parseOpenAiJson(String content) {
  final j = _object(content, 'The whisper program');
  final segments = <RawSegment>[];
  var measured = false;
  for (final s in (j['segments'] as List?) ?? const []) {
    if (s is! Map) continue;
    final words = <TranscriptWord>[];
    for (final w in (s['words'] as List?) ?? const []) {
      if (w is! Map) continue;
      final text = '${w['word'] ?? w['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      words.add(TranscriptWord(text, _secMs(w['start']), _secMs(w['end'])));
    }
    if (words.isNotEmpty) measured = true;
    segments.add(RawSegment(
        _secMs(s['start']), _secMs(s['end']), '${s['text'] ?? ''}'.trim(), words));
  }
  return BackendResult(segments,
      language: languageCode(j['language'] as String?), wordsMeasured: measured);
}

final RegExp _ffmpegLine = RegExp(
    r'\{"start":(-?\d+),"end":(-?\d+),"text":"(.*?)"\}\s*(?=\{"start":|$)',
    dotAll: true);

/// What the FFmpeg whisper filter wrote with `format=json`. The text is
/// taken as it is between the first quote and the closing `"}` (FFmpeg
/// does not escape quotes inside it).
BackendResult parseFfmpegWhisperJson(String content) {
  final segments = <RawSegment>[];
  for (final m in _ffmpegLine.allMatches(content.replaceAll('\r\n', '\n').trim())) {
    final text = m
        .group(3)!
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', ' ')
        .replaceAll('\n', ' ')
        .trim();
    if (text.isEmpty) continue;
    segments.add(RawSegment(int.parse(m.group(1)!), int.parse(m.group(2)!), text));
  }
  return BackendResult(segments);
}

/// A SubRip file as phrases.
BackendResult parseSrtTranscript(String content) {
  var n = 0;
  final cues = parseSrt(content, newId: () => 's${n++}');
  return BackendResult([
    for (final c in cues)
      RawSegment(c.startMs, c.endMs, c.text.replaceAll('\n', ' ').trim()),
  ]);
}

/// Reads [content] in whichever of the formats above it is.
BackendResult parseAnyTranscript(String content) {
  final t = content.trimLeft();
  if (t.startsWith('{"start":')) return parseFfmpegWhisperJson(content);
  if (t.startsWith('{')) {
    final j = _object(content, 'The whisper program');
    if (j.containsKey('transcription')) return parseWhisperCppJson(content);
    return parseOpenAiJson(content);
  }
  return parseSrtTranscript(content);
}
