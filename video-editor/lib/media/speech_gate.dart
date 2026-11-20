// Pure Dart: "Only when speaking" (1.17) - a gate per speech track that
// turns a microphone down while its speaker is not talking, so the other
// people's voices, breathing and room noise it picked up are not mixed in.
//
// It is LOUDNESS based: "talking" is what the sound picture of 1.13 found
// (media/sound_peaks.dart: louder than the file's own floor; microphones
// recorded together are compared so that one speaker's voice bleeding
// into another's microphone does not count - `groupSpeechStretches`). It
// does not know words. A quiet speaker, a laugh or a cough near the
// microphone can be judged wrongly; that is what the level is for.
//
// DECISION: nothing is stored per stretch. The quiet stretches are
// computed from the sound picture whenever they are needed (preview,
// export, waveform) by the one function here, and applied with the same
// mechanism as "Silence" on a part ([QuietRange]: media/clip_audio.dart
// `quietFilter` in the export, the players' volume in the preview). Only
// the switch and the level are in the project ([SoundTrack.gate],
// [SoundTrack.gateLevel]).
//
// Timing, so words are not clipped:
//  * pre-roll [kGatePreRollMs] (80 ms): the microphone is fully open that
//    long BEFORE the talk starts - the detector needs a few hops to see a
//    soft first consonant;
//  * hold [kGateHoldMs] (200 ms): it stays open that long after the talk
//    ends (trailing breath, the end of a word that fades);
//  * the level changes over [kQuietFadeMs] (40 ms), inside the quiet
//    stretch, so the attack is finished before the pre-roll starts and
//    the release begins after the hold;
//  * pauses shorter than [kGateMinQuietMs] (400 ms incl. pre-roll and
//    hold) are left open: pumping between words sounds worse than a
//    little noise.

import '../core/model/project.dart';
import 'speech_map.dart';

const int kGatePreRollMs = 80;
const int kGateHoldMs = 200;
const int kGateMinQuietMs = 400;

/// The stretches of a sound FILE ([fileMs] long) where the gate is closed,
/// given where its speaker talks ([talk]: file time, sorted): everything
/// outside the talk, the talk widened by the pre-roll and the hold.
List<QuietRange> gateRangesOf(List<TimeRange> talk,
    {required int fileMs,
    double level = kGateDefaultLevel,
    int preRollMs = kGatePreRollMs,
    int holdMs = kGateHoldMs,
    int minQuietMs = kGateMinQuietMs}) {
  if (fileMs <= 0 || level >= 1) return const [];
  final out = <QuietRange>[];
  var from = 0;
  void close(int to) {
    if (to - from >= minQuietMs) out.add(QuietRange(from, to, level));
  }

  for (final r in talk) {
    final open = r.startMs - preRollMs;
    if (open > from) close(open);
    final end = r.endMs + holdMs;
    if (end > from) from = end;
  }
  if (from < fileMs) close(fileMs);
  return out;
}

/// The gate of every sound of [p] that is on a track with "Only when
/// speaking" on, by sound id (file time). A sound whose picture is not
/// there yet ([lookup] gives null) is left open - it is never guessed.
Map<String, List<QuietRange>> projectGates(Project p, PeaksLookup lookup,
    [SpeechCache? cache]) {
  final gated = {
    for (final t in p.soundTracks)
      if (t.gate && t.speech) t.id: t,
  };
  if (gated.isEmpty) return const {};
  final resolver = SpeechResolver(p, lookup, cache ?? SpeechCache());
  final out = <String, List<QuietRange>>{};
  for (final a in p.audio) {
    final t = gated[a.trackId];
    if (t == null || a.looped) continue;
    final talk = resolver.fileStretches(a);
    if (talk == null) continue;
    final key = '${a.path}|${a.soundClip.audioTrackInUse}|${a.syncOffsetMs}|'
        '${a.sourceClipId == null ? '' : 'v'}|${t.gateLevel}';
    // Pieces of one recording share the list (the stretches are per file).
    final ranges = identical(talk, _lastTalk[key]?.$1)
        ? _lastTalk[key]!.$2
        : gateRangesOf(talk,
            fileMs: a.sourceDurationMs > a.outMs ? a.sourceDurationMs : a.outMs,
            level: t.gateLevel);
    _lastTalk[key] = (talk, ranges);
    if (ranges.isNotEmpty) out[a.id] = ranges;
  }
  if (_lastTalk.length > 64) _lastTalk.clear();
  return out;
}

final Map<String, (List<TimeRange>, List<QuietRange>)> _lastTalk = {};

/// True when [p] has at least two speech tracks with sound and none of
/// them is gated yet (the suggestion's condition).
bool couldUseGate(Project p) {
  final speech = [
    for (final t in p.soundTracks)
      if (t.speech && p.audio.any((a) => a.trackId == t.id)) t,
  ];
  return speech.length >= 2 && !speech.any((t) => t.gate);
}
