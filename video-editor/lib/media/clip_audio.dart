// Pure Dart: the processing of a clip's OWN sound (not the music track),
// for the export (ffmpeg filters) and for the preview (mpv `af` / `aid`).
//
// Stages, in this order (see also the comment at [Clip.voiceFocus]):
//
//   1. source       which audio stream of the file ([Clip.audioTrackInUse]),
//                   then which side of it ([Clip.audioChannelInUse]);
//   2. clean-up     [kDenoiseChain] (export only, see below);
//   3. voice focus  [voiceFocusFilters];
//   4. speed and volume (in ffmpeg_command.dart / the player).
//
// EXTENSION POINT for AI voice / music separation (not built): a separated
// voice file and background file per clip, with a level each, replace
// stage 1 - the export mixes the two files at their levels where it now
// reads `[N:a:T]` plus [audioSourceFilters]; the preview plays the mixed
// stems instead of the clip's file. Stages 2..4 stay as they are, so clean-up,
// voice focus, speed and volume keep working on the separated sound.
//
// Everything here exists with the same spelling in FFmpeg 6.1 and 8.x.

import 'dart:math' as math;

import '../core/model/project.dart';
import 'sound_filters.dart' show SoundStage;

// ---- export ----------------------------------------------------------------

/// "Clean audio" ([Clip.denoise]) chain, applied to a clip's own sound
/// after the source stage and before voice focus, speed and volume:
///
///  * `highpass=f=80` — removes rumble / handling noise below speech.
///  * `afftdn=nr=12:nf=-35` — spectral noise reduction: steady noise below
///    about -35 dBFS is lowered by 12 dB, louder sound passes.
///  * `dynaudnorm=f=250:g=7:p=0.8:m=2:b=1` — evens out loudness slowly
///    (250 ms frames, Gaussian window of 7 frames = 1.75 s), aiming at a
///    peak of 0.8 with at most 2x (+6 dB) gain. The gain is kept that low
///    on purpose: a leveller also raises long pauses, and +6 dB still
///    leaves half of the 12 dB noise reduction there. `b=1` makes the
///    first and last second use their own gain instead of fading in from
///    1.0, which matters for short clips.
///
/// None of the filters needs a model file and none changes the duration or
/// timing. dynaudnorm was preferred over loudnorm (single pass is slow and
/// inexact) and speechnorm (it raises pauses as much as speech). Measured
/// with FFmpeg 6.1 on a tone with white noise at -51 dBFS: noise in a long
/// pause -8 dB, tone +2.6 dB.
///
/// Export only: the players the apps ship (media_kit's libmpv builds for
/// Android, Windows and macOS, FFmpeg 6.0) contain no audio filter but
/// `equalizer`, so neither afftdn nor dynaudnorm can run in the preview.
const String kDenoiseChain = 'highpass=f=80,'
    'afftdn=nr=12:nf=-35,'
    'dynaudnorm=f=250:g=7:p=0.8:m=2:b=1';

/// Below this strength voice focus counts as off.
const double kVoiceFocusOff = 0.005;

/// Voice focus strength of [clip], 0..1 (NaN and out-of-range values
/// clamped); 0 when it is off.
double voiceFocusOf(Clip clip) {
  final s = clip.voiceFocus;
  if (s.isNaN || s < kVoiceFocusOff) return 0;
  return s > 1 ? 1 : s;
}

/// Samples [voiceFocusCentreFilters]'s `dialoguenhance` delays its output at
/// 48 kHz: its FFT is 2048 samples long with an overlap of 512, so the
/// output starts 2048 - 512 samples late (measured: 1536, FFmpeg 6.1).
/// The chain pads that much at the end and cuts it off at the start, so
/// that the sound stays in sync with the picture and keeps its length.
const int kDialogueEnhanceLatency = 1536;

/// What `dialoguenhance` (default options) puts on its centre channel for a
/// sound that is the same on both sides, relative to that sound (measured
/// 2.63..2.72 with FFmpeg 6.1 on tones, noise and speech-like signals).
const double kDialogueEnhanceCentreGain = 2.67;

/// The voice focus stages for strength [s] (0..1; empty when off), on a
/// 48 kHz stereo stream. Designed and measured on synthetic fixtures (a
/// formant "voice" in the centre, f0 around 130 Hz, and a wide-stereo
/// "music" bed with bass, chords, guitar notes at 1.5 / 2.3 kHz and
/// hi-hats; see docs/HANDOVER.md, Sound):
///
///  * `highpass` 60 Hz (s -> 0) .. 150 Hz (s = 1), 2 poles: bass and rumble
///    under the voice. Costs the voice about 0.9 dB (50 %) / 1.5 dB (100 %),
///    mostly its fundamental; the 300..4000 Hz band is untouched.
///  * `lowpass` about 17 kHz (s -> 0) .. 7.5 kHz (s = 1): hiss and cymbals.
///  * `equalizer` +3 dB x s around 3 kHz (1.5 octaves): consonants. On the
///    fixture it raised the music's guitar notes as much as the voice, so
///    it is kept small.
///  * centre emphasis ([voiceFocusCentreFilters]): `dialoguenhance` finds what is
///    the same on both sides (a voice in the middle) and the mix keeps that
///    at its level while everything else is lowered by up to 1 / (1 + 2 s):
///    -3.5 dB at 50 %, -9.5 dB at 100 % for sound spread wide. A mono
///    recording, or a stereo one that is the same on both sides, passes it
///    unchanged (measured +0.1 dB), so this is safe for phone recordings
///    and only acts on stereo mixes. After silence it needs about 0.2 s to
///    settle: the first words come out up to 2 dB softer. A voice off to
///    one side counts as "spread" and gets quieter (-4 dB at 50 %, -6.5 dB
///    at 100 % for a 75 / 25 pan).
///
/// Left out after measuring: a 300 Hz "mud" cut (-6 dB lowered the voice
/// 1.5 dB more than the music: speech has its first formant there) and a
/// compressor (it raised the music between phrases by 3.5 dB relative to
/// the voice - the opposite of the aim).
List<String> voiceFocusFilters(double s) {
  if (s.isNaN || s < kVoiceFocusOff) return const [];
  if (s > 1) s = 1;
  final hp = 60 + 90 * s;
  final lp = 7500 * math.pow(2, 1.2 * (1 - s)).toDouble();
  return [
    'highpass=f=${_num(hp, 0)}',
    'lowpass=f=${_num(lp, 0)}',
    'equalizer=f=3000:t=o:w=1.5:g=${_num(3 * s, 2)}',
    ...voiceFocusCentreFilters(s),
  ];
}

/// The centre emphasis stage of voice focus at strength [s] (0..1).
///
/// `dialoguenhance` (FFmpeg 5.1+) takes stereo and gives three channels:
/// the two sides as they came in plus a centre channel holding what the
/// two sides share, raised. `pan` mixes that back to stereo as
/// `g * (side + k * centre)`, with `k * 2.67 = 2 s` so that a sound that is
/// the same on both sides comes out at its own level while what differs
/// between the sides is lowered to `g = 1 / (1 + 2 s)`. The three output
/// channels are addressed by number, so the stage does not depend on the
/// name of the layout.
List<String> voiceFocusCentreFilters(double s) {
  final ka = 2 * s;
  final g = 1 / (1 + ka);
  final k = g * ka / kDialogueEnhanceCentreGain;
  final gs = _num(g, 4), ks = _num(k, 4);
  return [
    'apad=pad_len=$kDialogueEnhanceLatency',
    'dialoguenhance',
    'pan=stereo|c0=$gs*c0+$ks*c2|c1=$gs*c1+$ks*c2',
    'atrim=start_sample=$kDialogueEnhanceLatency',
    'asetpts=N/SR/TB',
  ];
}

/// The channel stage of the source on a stereo stream: [AudioChannel.left]
/// / [AudioChannel.right] copy that side to both. Empty for both sides.
List<String> audioSourceFilters(Clip clip) => switch (clip.audioChannelInUse) {
      AudioChannel.both => const [],
      AudioChannel.left => const ['pan=stereo|c0=c0|c1=c0'],
      AudioChannel.right => const ['pan=stereo|c0=c1|c1=c1'],
    };

/// Every filter of the clip's own sound between "48 kHz stereo float" and
/// speed: source channel, clean-up, voice focus. Each ends with [format]
/// so that what follows always gets the same kind of stream.
///
/// [leaveOut]: stages the FFmpeg in use cannot run (see sound_filters.dart);
/// they are skipped, the rest still applies.
String clipSoundFilters(Clip clip, String format,
    {Set<SoundStage> leaveOut = const {}}) {
  final out = StringBuffer();
  final source = audioSourceFilters(clip);
  if (source.isNotEmpty) out.write('${source.join(',')},$format,');
  if (clip.denoise && !leaveOut.contains(SoundStage.cleanUp)) {
    out.write('$kDenoiseChain,$format,');
  }
  final s = voiceFocusOf(clip);
  final focus = [
    if (s > 0 && !leaveOut.contains(SoundStage.voiceFocusTone))
      ...voiceFocusFilters(s).take(3),
    if (s > 0 && !leaveOut.contains(SoundStage.voiceFocusCentre))
      ...voiceFocusCentreFilters(s),
  ];
  if (focus.isNotEmpty) out.write('${focus.join(',')},$format,');
  return out.toString();
}

// ---- quiet ranges (1.17) ---------------------------------------------------

/// Samples per frame while a quiet range's level is applied: the `volume`
/// filter works out its factor once per frame, so the sound is cut into
/// 1 ms frames first (48 samples at 48 kHz). A 40 ms fade is then 40 small
/// steps of at most 2.5 % each - no click - and the edges are right to
/// the millisecond.
const int kQuietFrameSamples = 48;

/// The ffmpeg stages that apply [lists] of quiet ranges (the item's own
/// "Silence" / "Lower volume" ranges, and the computed ranges of "Only
/// when speaking"; their factors multiply) to a 48 kHz stream whose time
/// 0 is [originMs] of the SOURCE file. Only ranges that touch
/// [fromMs]..[toMs] of the source are written. Each stage ends with a
/// comma; empty when nothing applies.
///
/// One list becomes ONE expression: a balanced tree of `if(lt(t,S),..)`
/// over its ranges (sorted, not overlapping), so a microphone with
/// hundreds of pauses costs about ten comparisons per millisecond instead
/// of hundreds; a range is `1-K*clip(min(t-A,B-t)/F,0,1)` - 1 outside,
/// the level inside, a straight line over the fade at each edge, exactly
/// [QuietRange.gainAt], which the preview and the waveform use.
String quietFilter(Iterable<List<QuietRange>> lists,
    {required num originMs, num? fromMs, num? toMs}) {
  final stages = <String>[];
  for (final list in lists) {
    final ranges = [
      for (final r in list)
        if (r.level < 1 &&
            r.toMs > r.fromMs &&
            (fromMs == null || r.toMs > fromMs) &&
            (toMs == null || r.fromMs < toMs))
          r,
    ]..sort((a, b) => a.fromMs.compareTo(b.fromMs));
    if (ranges.isEmpty) continue;
    stages.add("volume=volume='${quietExpression(ranges, originMs)}'"
        ':eval=frame');
  }
  if (stages.isEmpty) return '';
  return 'asetnsamples=n=$kQuietFrameSamples:p=0,${stages.join(',')},'
      'asetnsamples=n=1024:p=0,';
}

/// The `volume` expression for [ranges] (sorted by start, not
/// overlapping); `t` = 0 is [originMs] of the source.
String quietExpression(List<QuietRange> ranges, num originMs) {
  String sec(num ms) => _num((ms - originMs) / 1000, 4);
  String minus(num ms) {
    final v = sec(ms);
    return v.startsWith('-') ? '+${v.substring(1)}' : '-$v';
  }

  String leaf(QuietRange r) {
    final k = _num(1 - r.level, 4);
    final f = r.fadeMs;
    if (f <= 0) {
      return 'if(between(t,${sec(r.fromMs)},${sec(r.toMs)}),'
          '${_num(r.level, 4)},1)';
    }
    return '1-$k*clip(min(t${minus(r.fromMs)},${sec(r.toMs)}-t)'
        '/${_num(f / 1000, 4)},0,1)';
  }

  String node(int lo, int hi) {
    if (hi - lo == 1) return leaf(ranges[lo]);
    final mid = (lo + hi) >> 1;
    return 'if(lt(t,${sec(ranges[mid].fromMs)}),'
        '${node(lo, mid)},${node(mid, hi)})';
  }

  return node(0, ranges.length);
}

// ---- preview ---------------------------------------------------------------
//
// The preview player is libmpv as media_kit ships it. Its FFmpeg (6.0 in
// the Android 1.1.7, Windows 2023-09-24 and macOS v0.6.0 builds) was
// configured with `--disable-filters --enable-filter=overlay
// --enable-filter=equalizer`: `equalizer` is the ONLY audio filter it has
// (the Linux build uses the system libmpv, which has them all, so Linux is
// no proof). So the preview is built from `equalizer` stages plus mpv's own
// `format` filter, which exist everywhere:
//
//  * source: `aid` picks the stream; one side is silenced with two
//    `equalizer` stages of -50 dB over the whole band (a peaking filter
//    with Q 0.001 is a flat gain), a flat +6.02 dB is added, and mpv's
//    `format=channels=mono` then `format=channels=stereo` put the remaining
//    side on both (that costs 6.02 dB, so it comes out at its own level);
//  * voice focus: the presence boost exactly as exported, the high-pass as
//    two low peaking cuts fitted to it (within 1 dB from 25 to 1500 Hz); the
//    low-pass and the centre emphasis are export only;
//  * clean-up: only its 80 Hz rumble cut (same fitted low cut); the noise
//    reduction and the levelling are export only - "Hear a sample" in the
//    Sound panel renders 15 s with the export engine for that.
//
// Layout, as measured with mpv 0.37 on Linux:
//  * every `equalizer` is in ONE `lavfi=[...]` graph and comes BEFORE the
//    channel conversions: mpv 0.37 fails ("Layout indicates a different
//    number of channels than actually present", no sound) when two lavfi
//    filters follow an mpv `format=channels=` conversion;
//  * mpv's `format=format=floatp` goes first, so that the graph gets planar
//    float, which `equalizer` takes as it is: libavfilter cannot convert
//    sample formats in the shipped builds (no `aresample`), e.g. for the
//    16-bit PCM sound of camera files.
//
// All stages keep the level of the sound, so the cubic volume mapping of
// the player stays right.

/// The low cut of the preview's clean-up: the fitted high-pass at 80 Hz.
const double kPreviewCleanUpLowCut = 20 / 90;

/// Index of the audio stream the preview plays (0 = first), the `aid` of
/// mpv minus one.
int previewAudioTrack(Clip clip) => clip.audioTrackInUse;

/// The mpv `af` value for [clip]'s own sound in the preview; empty for
/// none.
String previewAudioFilter(Clip clip) {
  final eqs = <String>[];
  String eq(String opts) => 'equalizer=$opts';
  // Two low peaking cuts fitted to a 2-pole high-pass at 60 + 90 x Hz
  // over 25..1500 Hz, closest above 120 Hz (within 0.5 dB there; within
  // 1 dB overall).
  void lowCut(double x) => eqs
    ..add(eq('f=25.5:t=o:w=${_num(0.77 + 0.44 * x, 3)}'
        ':g=${_num(-15.1 - 10.6 * x, 2)}'))
    ..add(eq('f=${_num(38.5 + 6.7 * x, 1)}:t=o:w=${_num(1.0 + 0.61 * x, 3)}'
        ':g=${_num(-6.0 - 5.6 * x, 2)}'));
  // Clean-up: only its 80 Hz rumble cut can play live (x = 20 / 90).
  if (clip.denoise) lowCut(kPreviewCleanUpLowCut);
  final s = voiceFocusOf(clip);
  if (s > 0) {
    lowCut(s);
    eqs.add(eq('f=3000:t=o:w=1.5:g=${_num(3 * s, 2)}'));
  }
  final side = clip.audioChannelInUse;
  if (side != AudioChannel.both) {
    final mute = side == AudioChannel.left ? 'FR' : 'FL';
    // Q 0.001 makes a peaking filter a flat gain far beyond 20 Hz..20 kHz.
    eqs
      ..add(eq('f=300:t=q:w=0.001:g=-50:c=$mute'))
      ..add(eq('f=3000:t=q:w=0.001:g=-50:c=$mute'))
      ..add(eq('f=1000:t=q:w=0.001:g=6.0206'));
  }
  if (eqs.isEmpty) return '';
  return [
    'format=format=floatp',
    'lavfi=[${eqs.join(',')}]',
    if (side != AudioChannel.both) ...[
      'format=channels=mono',
      'format=channels=stereo',
    ],
  ].join(',');
}

// ---- helpers ---------------------------------------------------------------

String _num(double v, [int digits = 3]) {
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}
