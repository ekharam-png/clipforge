// What was said in ONE media file: words with their times in that file
// (source time, whole ms), grouped into segments. Pure Dart, no Flutter.
//
// A transcript belongs to a source FILE (a video's sound, or a voice
// recorded separately), not to a project's timeline: where a word plays in
// the finished video is worked out from the clips each time
// (transcript_timeline.dart), so it survives every cut, speed change and
// "Remove silences". It is stored as its own JSON file in the project
// folder (transcript_store.dart), never inside project.json.

/// How the word times were obtained.
enum WordTiming {
  /// The speech program reported a time for every word.
  measured,

  /// Only whole phrases were timed; the words inside were spread over the
  /// phrase by their length. Good for captions and for reading, too rough
  /// to cut single words out safely.
  estimated,
}

class TranscriptWord {
  const TranscriptWord(this.text, this.startMs, this.endMs);

  /// The word as spoken, with its punctuation ("Hello,"), no spaces around.
  final String text;
  final int startMs;
  final int endMs;

  List<Object> toJson() => [text, startMs, endMs];

  static TranscriptWord fromJson(Object? j) {
    final l = j as List;
    return TranscriptWord(
        '${l[0]}', (l[1] as num).round(), (l[2] as num).round());
  }

  @override
  String toString() => '$text@$startMs-$endMs';
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.words,
  });
  final int startMs;
  final int endMs;
  final List<TranscriptWord> words;

  String get text => words.map((w) => w.text).join(' ');

  Map<String, dynamic> toJson() => {
        's': startMs,
        'e': endMs,
        'w': [for (final w in words) w.toJson()],
      };

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) =>
      TranscriptSegment(
        startMs: (j['s'] as num).round(),
        endMs: (j['e'] as num).round(),
        words: [for (final w in (j['w'] as List?) ?? const []) TranscriptWord.fromJson(w)],
      );
}

/// The file format version of a stored transcript.
const int kTranscriptVersion = 1;

class Transcript {
  Transcript({
    required this.sourcePath,
    required this.audioTrack,
    required this.language,
    required this.requestedLanguage,
    required this.model,
    required this.backend,
    required this.wordTiming,
    required this.durationMs,
    required this.createdAt,
    required this.segments,
    this.fingerprint = '',
    this.quality = '',
    this.appVersion = '',
    this.device = '',
  });

  /// "graphics card" / "processor" when the program told; '' unknown.
  final String device;

  /// The media file this is the speech of (as it was when transcribed).
  final String sourcePath;

  /// Which audio stream of the file (0 = first).
  final int audioTrack;

  /// Content fingerprint of the file (see media_import.dart); '' unknown.
  final String fingerprint;

  /// The language of the speech: what the program detected, else what was
  /// asked for ("en", "ru", "he", ...); '' when unknown.
  final String language;

  /// What was asked for: "auto" or a language code.
  final String requestedLanguage;

  /// The model ("large-v3-turbo", or a file name).
  final String model;

  /// The size that was asked for ("auto", "small", "medium", "large").
  final String quality;

  /// Which backend made it (TranscriptionBackend.id).
  final String backend;
  final WordTiming wordTiming;

  /// Length of the sound that was transcribed.
  final int durationMs;
  final DateTime createdAt;
  final String appVersion;
  final List<TranscriptSegment> segments;

  late final List<TranscriptWord> words = List.unmodifiable(
      [for (final s in segments) ...s.words]);

  int get wordCount => words.length;

  String get text => segments.map((s) => s.text).join(' ');

  /// True when this was made with the settings asked for now, so
  /// transcribing again would give the same result: the same language
  /// request, one of [models] (null: any model) and [backend] (null or
  /// "auto": any).
  bool madeWith(
          {required String language, List<String>? models, String? backend}) =>
      requestedLanguage == language &&
      (models == null || models.contains(model)) &&
      (backend == null || backend == 'auto' || backend == this.backend);

  Map<String, dynamic> toJson() => {
        'version': kTranscriptVersion,
        'sourcePath': sourcePath,
        'audioTrack': audioTrack,
        'fingerprint': fingerprint,
        'language': language,
        'requestedLanguage': requestedLanguage,
        'model': model,
        'quality': quality,
        'backend': backend,
        'wordTiming': wordTiming.name,
        'durationMs': durationMs,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'device': device,
        'segments': [for (final s in segments) s.toJson()],
      };

  factory Transcript.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] as num?)?.toInt() ?? 1;
    if (version > kTranscriptVersion) {
      throw FormatException('This transcript was saved by a newer version '
          'of ClipForge (format $version).');
    }
    return Transcript(
      sourcePath: '${j['sourcePath'] ?? ''}',
      audioTrack: (j['audioTrack'] as num?)?.toInt() ?? 0,
      fingerprint: '${j['fingerprint'] ?? ''}',
      language: '${j['language'] ?? ''}',
      requestedLanguage: '${j['requestedLanguage'] ?? 'auto'}',
      model: '${j['model'] ?? ''}',
      quality: '${j['quality'] ?? ''}',
      backend: '${j['backend'] ?? ''}',
      wordTiming: j['wordTiming'] == WordTiming.estimated.name
          ? WordTiming.estimated
          : WordTiming.measured,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: '${j['appVersion'] ?? ''}',
      device: '${j['device'] ?? ''}',
      segments: [
        for (final s in (j['segments'] as List?) ?? const [])
          TranscriptSegment.fromJson((s as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// A phrase as a speech program reports it, before it is tidied up: its
/// text and times, and its words when the program timed them.
class RawSegment {
  RawSegment(this.startMs, this.endMs, this.text, [this.words = const []]);
  final int startMs;
  final int endMs;
  final String text;
  final List<TranscriptWord> words;
}

final RegExp _space = RegExp(r'\s+');

/// Spreads the words of [text] over [startMs]..[endMs] by their length
/// (letters and digits count, punctuation does not; every word gets at
/// least a little time).
List<TranscriptWord> estimateWords(String text, int startMs, int endMs) {
  final parts = [
    for (final w in text.trim().split(_space))
      if (w.isNotEmpty) w,
  ];
  if (parts.isEmpty) return const [];
  if (endMs < startMs) endMs = startMs;
  final weights = [for (final w in parts) _weight(w)];
  final total = weights.fold<double>(0, (a, b) => a + b);
  final span = endMs - startMs;
  final out = <TranscriptWord>[];
  var acc = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final a = startMs + (span * acc / total).round();
    acc += weights[i];
    final b = i == parts.length - 1
        ? endMs
        : startMs + (span * acc / total).round();
    out.add(TranscriptWord(parts[i], a, b < a ? a : b));
  }
  return out;
}

double _weight(String word) {
  var n = 0;
  for (final r in word.runes) {
    if (_isLetterOrDigit(r)) n++;
  }
  return n + 1.0;
}

bool _isLetterOrDigit(int r) =>
    (r >= 0x30 && r <= 0x39) ||
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F) ||
    (r >= 0x370 && r <= 0x52F) || // Greek, Cyrillic
    (r >= 0x5D0 && r <= 0x5EA) || // Hebrew letters
    (r >= 0x620 && r <= 0x64A) || // Arabic letters
    r >= 0x3040;

/// True when [word] ends a sentence ("done.", "what?", "да!").
bool endsSentence(String word) {
  var t = word.trimRight();
  while (t.isNotEmpty && '"\'”’»)]'.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  if (t.isEmpty) return false;
  return '.?!…。？！'.contains(t[t.length - 1]);
}

/// True when [word] ends with a comma, semicolon, colon or dash.
bool endsClause(String word) {
  final t = word.trimRight();
  if (t.isEmpty) return false;
  return ',;:،؛–—-'.contains(t[t.length - 1]);
}

/// Groups [words] into phrases for reading: a new one after a sentence
/// end, after a pause of [pauseMs], and when one gets longer than
/// [maxChars] / [maxMs].
List<TranscriptSegment> segmentsFromWords(List<TranscriptWord> words,
    {int pauseMs = 900, int maxChars = 220, int maxMs = 15000}) {
  final out = <TranscriptSegment>[];
  var cur = <TranscriptWord>[];
  var chars = 0;
  void flush() {
    if (cur.isEmpty) return;
    out.add(TranscriptSegment(
        startMs: cur.first.startMs, endMs: cur.last.endMs, words: cur));
    cur = <TranscriptWord>[];
    chars = 0;
  }

  for (final w in words) {
    if (cur.isNotEmpty) {
      final prev = cur.last;
      if (endsSentence(prev.text) ||
          w.startMs - prev.endMs >= pauseMs ||
          chars + w.text.length + 1 > maxChars ||
          w.endMs - cur.first.startMs > maxMs) {
        flush();
      }
    }
    cur.add(w);
    chars += w.text.length + 1;
  }
  flush();
  return out;
}

/// Tidies what a speech program reported into segments that all have
/// words: sorted, times never negative or backwards, empty phrases and the
/// markers programs print for non-speech ("[MUSIC]", "(applause)",
/// "[BLANK_AUDIO]") dropped, words estimated where the program gave none.
/// Returns the segments and whether any word time had to be estimated.
({List<TranscriptSegment> segments, bool estimated}) tidySegments(
    List<RawSegment> raw,
    {bool regroup = false}) {
  final sorted = [...raw]..sort((a, b) => a.startMs.compareTo(b.startMs));
  var estimated = false;
  final all = <TranscriptWord>[];
  final segs = <TranscriptSegment>[];
  for (final r in sorted) {
    final start = r.startMs < 0 ? 0 : r.startMs;
    final end = r.endMs < start ? start : r.endMs;
    var words = <TranscriptWord>[];
    if (r.words.isNotEmpty) {
      for (final w in r.words) {
        final t = w.text.trim();
        if (t.isEmpty || _isMarker(t)) continue;
        final a = w.startMs < 0 ? 0 : w.startMs;
        words.add(TranscriptWord(t, a, w.endMs < a ? a : w.endMs));
      }
    } else {
      final text = r.text.replaceAll(_markers, ' ').trim();
      if (text.isEmpty) continue;
      words = estimateWords(text, start, end);
      estimated = true;
    }
    if (words.isEmpty) continue;
    all.addAll(words);
    segs.add(TranscriptSegment(
        startMs: words.first.startMs, endMs: words.last.endMs, words: words));
  }
  if (regroup) {
    all.sort((a, b) => a.startMs.compareTo(b.startMs));
    return (segments: segmentsFromWords(all), estimated: estimated);
  }
  return (segments: segs, estimated: estimated);
}

final RegExp _markers = RegExp(
    r'\[[^\]\n]{0,40}\]|\((?:music|applause|laughter|laughs|silence|inaudible|blank_audio|музыка|аплодисменты|смех)\)|[♪♫]+',
    caseSensitive: false);

bool _isMarker(String word) =>
    _markers.stringMatch(word) == word || RegExp(r'^\[_[A-Z_0-9]+\]?$').hasMatch(word);

/// The two-letter code of a language name or code as programs print it
/// ("russian" / "Russian" / "ru" -> "ru"); '' for unknown / auto.
String languageCode(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'auto') return '';
  const names = {
    'english': 'en',
    'russian': 'ru',
    'hebrew': 'he',
    'iw': 'he',
    'spanish': 'es',
    'french': 'fr',
    'german': 'de',
    'italian': 'it',
    'portuguese': 'pt',
    'ukrainian': 'uk',
    'arabic': 'ar',
    'chinese': 'zh',
    'japanese': 'ja',
    'korean': 'ko',
    'turkish': 'tr',
    'polish': 'pl',
    'dutch': 'nl',
  };
  return names[v] ?? v;
}

/// A readable name for a language code ("ru" -> "Russian").
String languageName(String code) => switch (code) {
      '' || 'auto' => 'Automatic',
      'en' => 'English',
      'ru' => 'Russian',
      'he' => 'Hebrew',
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      'uk' => 'Ukrainian',
      'ar' => 'Arabic',
      _ => code,
    };
