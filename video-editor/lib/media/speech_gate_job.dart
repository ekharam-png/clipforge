// "Only when speaking" for an export that has no sound pictures at hand
// yet (the Export window when the timeline has not drawn them, Claude's
// export job): reads the pictures the gate needs with the engine (they are
// cached on disk) and works the gates out with the same function the
// preview uses (speech_gate.dart).

import '../core/model/project.dart';
import 'sound_peaks_job.dart';
import 'speech_gate.dart';

/// The sounds whose pictures the gates of [p] need: everything on a
/// speech track and every voice recorded separately (microphones recorded
/// together are compared), as (path, audio stream).
List<({String path, int track})> gateSoundsOf(Project p) {
  if (!p.soundTracks.any((t) => t.gate && t.speech)) return const [];
  final speech = {
    for (final t in p.soundTracks)
      if (t.speech) t.id,
  };
  final seen = <String>{};
  return [
    for (final a in p.audio)
      if ((a.isVoice || speech.contains(a.trackId)) &&
          !a.looped &&
          seen.add('${a.path}|${a.soundClip.audioTrackInUse}'))
        (path: a.path, track: a.soundClip.audioTrackInUse),
  ];
}

/// [ExportOptions.gates] for [p]: empty when no track has "Only when
/// speaking" on. [known] gives pictures that are already in memory. A
/// sound that cannot be read is left open (never guessed).
Future<Map<String, List<QuietRange>>> computeProjectGates(
  Project p,
  SoundPeaksEngine engine, {
  String? cacheDir,
  SoundPeaks? Function(String path, int track)? known,
}) async {
  final wanted = gateSoundsOf(p);
  if (wanted.isEmpty) return const {};
  final peaks = <String, SoundPeaks>{};
  for (final w in wanted) {
    final key = '${w.path}|${w.track}';
    var found = known?.call(w.path, w.track);
    if (found == null) {
      try {
        found = await engine.soundPeaks(w.path,
            audioTrack: w.track, cacheDir: cacheDir);
      } catch (_) {
        found = null;
      }
    }
    if (found != null) peaks[key] = found;
  }
  return projectGates(p, (path, track) => peaks['$path|$track']);
}
