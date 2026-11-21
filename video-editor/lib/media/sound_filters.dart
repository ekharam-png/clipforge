// Which FFmpeg filters the export's sound needs, and what to do when the
// FFmpeg in use lacks one.
//
// Pure Dart. The bundled FFmpeg builds (ffmpeg_kit_flutter_new 4.6.8,
// FFmpeg n8.1.2 full-gpl for Windows x86_64, macOS and Android; checked in
// the downloaded libraries, November 2026) contain every filter listed
// here, and so does a stock system ffmpeg 6.1+. This is a safety net for
// an FFmpeg built with fewer filters (a different plugin version, a
// "min" variant, an old system ffmpeg for Claude control): instead of the
// whole export failing on "No such filter", the optional sound stages
// whose filters are missing are left out and the user is told which.

import '../core/model/project.dart';
import 'clip_audio.dart' show voiceFocusOf;

/// Sound stages of an export that can be left out without breaking it.
enum SoundStage {
  /// "Clean up sound": rumble cut, noise reduction, levelling.
  cleanUp(['highpass', 'afftdn', 'dynaudnorm'], 'Clean up sound'),

  /// Voice focus: low cut, high cut and presence.
  voiceFocusTone(['highpass', 'lowpass', 'equalizer'], 'Voice focus'),

  /// Voice focus: keeping the centre (the voice) and lowering the sides.
  voiceFocusCentre(['apad', 'dialoguenhance', 'pan', 'atrim', 'asetpts'],
      'Voice focus (centre emphasis)'),

  /// "Lower music under speech".
  duckMusic(['sidechaincompress', 'asplit'], 'Lower music under speech'),

  /// Fade in / fade out of music.
  musicFades(['afade'], 'Music fades'),

  /// The final peak limiter of the mix with music.
  limiter(['alimiter'], 'Peak limiter');

  const SoundStage(this.filters, this.label);

  /// The FFmpeg filters the stage uses.
  final List<String> filters;

  /// What the user knows the stage as.
  final String label;
}

/// The filter names in the output of `ffmpeg -filters`. Lines look like
/// ` TSC afftdn            A->A       Denoise audio samples using FFT.`
/// (FFmpeg 6) or ` T.. afade A->A (null)` (FFmpeg built with
/// --enable-small); the flag characters may be letters or dots.
Set<String> parseFilterList(String output) {
  final names = <String>{};
  final line = RegExp(r'^\s*[A-Z.|]{2,3}\s+(\w+)\s+[A-Za-z|]+->[A-Za-z|]+',
      multiLine: true);
  for (final m in line.allMatches(output)) {
    names.add(m.group(1)!);
  }
  return names;
}

/// The names of the filters a `-filter_complex` [graph] uses, in order of
/// first use. Pad labels (`[a0]`) and option values are skipped; escaped
/// characters inside values (`\,`) do not start a new filter, and nothing
/// inside a quoted value (`volume='if(lt(t,5),if(..),1)'`) is a filter:
/// before 1.18 the commas of such an expression were read as the end of a
/// filter, so an "Only when speaking" export with three or more pauses was
/// refused with `its FFmpeg has no "if" filter`.
List<String> filtersInGraph(String graph) {
  final names = <String>{};
  bool letter(int c) =>
      (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F;
  bool word(int c) => letter(c) || (c >= 0x30 && c <= 0x39);
  final n = graph.length;
  var i = 0;
  var atStart = true;
  while (i < n) {
    final c = graph.codeUnitAt(i);
    if (c == 0x5C) {
      // \x: an escaped character inside a value.
      i += 2;
      continue;
    }
    if (c == 0x27) {
      // '...': a quoted value, taken as it is up to the closing quote
      // (FFmpeg has no escapes inside quotes).
      final close = graph.indexOf("'", i + 1);
      i = close < 0 ? n : close + 1;
      atStart = false;
      continue;
    }
    if (c == 0x5B) {
      // [label]
      final close = graph.indexOf(']', i);
      i = close < 0 ? n : close + 1;
      continue;
    }
    if (c == 0x2C || c == 0x3B) {
      // , ;
      atStart = true;
      i++;
      continue;
    }
    if (atStart && letter(c)) {
      var j = i + 1;
      while (j < n && word(graph.codeUnitAt(j))) {
        j++;
      }
      names.add(graph.substring(i, j));
      i = j;
      atStart = false;
      continue;
    }
    if (c != 0x20 && c != 0x0A) atStart = false;
    i++;
  }
  return names.toList();
}

/// What an FFmpeg's filter list means for the export's sound.
class SoundFilterCheck {
  const SoundFilterCheck._(this.available);

  /// Nothing is known to be missing (also when the list could not be read).
  static const SoundFilterCheck unknown = SoundFilterCheck._(null);

  /// The filter names the FFmpeg has; null when unknown.
  final Set<String>? available;

  /// From the filter names an FFmpeg has ([parseFilterList]). A list
  /// without even `aformat` and `anull` was not captured properly and is
  /// ignored (nothing counts as missing then: FFmpeg's own error is better
  /// than a wrong guess).
  factory SoundFilterCheck.of(Set<String>? available) {
    if (available == null ||
        !available.contains('aformat') ||
        !available.contains('anull')) {
      return unknown;
    }
    return SoundFilterCheck._(Set.unmodifiable(available));
  }

  bool _has(String filter) => available?.contains(filter) ?? true;

  /// Optional stages that cannot run with this FFmpeg.
  Set<SoundStage> get unavailable => {
        for (final s in SoundStage.values)
          if (!s.filters.every(_has)) s,
      };

  /// The filters [graph] uses that this FFmpeg does not have.
  List<String> missingIn(String graph) =>
      [for (final f in filtersInGraph(graph)) if (!_has(f)) f];

  /// The stages [project] uses that cannot run here, in [SoundStage] order.
  List<SoundStage> leftOutFor(Project project) {
    final off = unavailable;
    return [
      for (final s in SoundStage.values)
        if (off.contains(s) && soundStageUsed(project, s)) s,
    ];
  }

  /// One sentence per stage of [project] that is left out, naming the
  /// missing filters, e.g. `Clean up sound was left out: the FFmpeg on
  /// this device has no "afftdn" filter.`
  List<String> messagesFor(Project project) => [
        for (final s in leftOutFor(project))
          '${s.label} was left out: the FFmpeg on this device has no '
              '${_names([for (final f in s.filters) if (!_has(f)) f])} '
              'filter.',
      ];
}

/// The clear message for an export that cannot be made because the
/// FFmpeg lacks [missing] filters that the video needs.
String missingFiltersMessage(List<String> missing) =>
    'This video cannot be exported on this device: its FFmpeg has no '
    '${_names(missing)} filter.';

/// Asks an FFmpeg for its filters once per run of the program and
/// remembers the answer ([shared], one per FFmpeg).
class FilterSupport {
  FilterSupport(this.listFilters);

  factory FilterSupport.shared(String key, FilterSupport Function() create) =>
      _shared[key] ??= create();
  static final Map<String, FilterSupport> _shared = {};

  /// The output of `ffmpeg -filters` (null when it cannot be had).
  final Future<String?> Function() listFilters;

  Future<SoundFilterCheck>? _check;

  /// The check, made on first use. Never fails: an unreadable list counts
  /// as "nothing known to be missing".
  Future<SoundFilterCheck> check() => _check ??= () async {
        try {
          final out = await listFilters();
          return SoundFilterCheck.of(out == null ? null : parseFilterList(out));
        } catch (_) {
          return SoundFilterCheck.unknown;
        }
      }();
}

String _names(List<String> filters) {
  final quoted = [for (final f in filters) '"$f"'];
  if (quoted.length == 1) return quoted.single;
  return '${quoted.sublist(0, quoted.length - 1).join(', ')} or ${quoted.last}';
}

/// Whether exporting [project] would use [stage].
bool soundStageUsed(Project project, SoundStage stage) {
  bool clipSound(Clip c) =>
      c.type != ClipType.photo && c.hasAudio && !c.muted && c.volume > 0;
  final music = project.audio
      .where((a) => a.volume > 0 && project.trackGainOf(a.trackId) > 0)
      .toList();
  final sounds = [
    ...project.clips.where(clipSound),
    for (final a in music) a.soundClip,
  ];
  return switch (stage) {
    SoundStage.cleanUp => sounds.any((c) => c.denoise),
    SoundStage.voiceFocusTone ||
    SoundStage.voiceFocusCentre =>
      sounds.any((c) => voiceFocusOf(c) > 0),
    SoundStage.duckMusic => project.soundTracks.any((t) =>
        t.duck && music.any((a) => a.trackId == t.id)),
    SoundStage.musicFades =>
      music.any((a) => a.fadeInMs > 0 || a.fadeOutMs > 0),
    SoundStage.limiter => music.isNotEmpty,
  };
}
