// Pure Dart: who speaks when ON THE TIMELINE (1.13), from the sound
// pictures of the project's files ([SoundPeaks]) - no transcript needed.
//
// A "speaker" is a speech track (the Voice rows: one linked voice file per
// person, or a voice-over); when the project has none, the video's own
// sound is the one speaker. Stretches are found per FILE
// ([speechStretches]; microphones recorded together are compared so that
// one does not show the other's voice: [groupSpeechStretches]) and then
// mapped through each sound's trim, speed and place - so cuts, speed
// changes and the linked-voice offset need no bookkeeping.

import '../core/model/project.dart';
import 'sound_peaks.dart';

export 'sound_peaks.dart' show TimeRange;

/// The sound picture of a file and audio stream, or null when it is not
/// there (yet).
typedef PeaksLookup = SoundPeaks? Function(String path, int audioTrack);

/// Remembers the stretches of files and of groups of microphones, so that
/// an edit of the project (every step of a drag) does not work them out
/// again. Keyed by the peaks objects themselves.
class SpeechCache {
  final Map<String, ({List<SoundPeaks> of, List<List<TimeRange>> result})>
      _groups = {};
  final Expando<List<TimeRange>> _single = Expando();

  List<TimeRange> single(SoundPeaks p) => _single[p] ??= speechStretches(p);

  List<List<TimeRange>> group(
      String key, List<({SoundPeaks peaks, int offsetMs})> mics) {
    final known = _groups[key];
    if (known != null && known.of.length == mics.length) {
      var same = true;
      for (var i = 0; i < mics.length && same; i++) {
        same = identical(known.of[i], mics[i].peaks);
      }
      if (same) return known.result;
    }
    final result = groupSpeechStretches(mics);
    _groups[key] = (of: [for (final m in mics) m.peaks], result: result);
    if (_groups.length > 32) _groups.remove(_groups.keys.first);
    return result;
  }
}

int _trackOf(AudioClip a) => a.soundClip.audioTrackInUse;

/// Works out, for the sounds of one project, where speech is.
class SpeechResolver {
  SpeechResolver(this.project, this.lookup, this.cache);
  final Project project;
  final PeaksLookup lookup;
  final SpeechCache cache;

  late final Map<String, String> _clipPath = {
    for (final c in project.clips) c.id: c.path,
  };
  late final Set<String> _speechTracks = {
    for (final t in project.soundTracks)
      if (t.speech) t.id,
  };

  /// Voices lined up with the same video file: recorded together.
  late final Map<String, List<AudioClip>> _voicesOfVideo = () {
    final out = <String, List<AudioClip>>{};
    for (final a in project.audio) {
      if (!a.isVoice) continue;
      final video = _clipPath[a.sourceClipId];
      if (video == null) continue;
      final list = out[video] ??= [];
      final id = _micId(a);
      if (!list.any((x) => _micId(x) == id)) list.add(a);
    }
    return out;
  }();

  static String _micId(AudioClip a) =>
      '${a.path}|${_trackOf(a)}|${a.syncOffsetMs}';

  /// True when [a] is drawn as speech (talk bright, pauses dim).
  bool isSpeech(AudioClip a) =>
      !a.looped && (a.isVoice || _speechTracks.contains(a.trackId));

  /// The stretches where someone talks in [a]'s FILE (its own time), or
  /// null when [a] is not speech or its sound picture is not there yet.
  List<TimeRange>? fileStretches(AudioClip a) {
    if (!isSpeech(a)) return null;
    final peaks = lookup(a.path, _trackOf(a));
    if (peaks == null) return null;
    final video = a.isVoice ? _clipPath[a.sourceClipId] : null;
    final mates = video == null ? null : _voicesOfVideo[video];
    if (mates == null || mates.length < 2) return cache.single(peaks);
    final mics = <({SoundPeaks peaks, int offsetMs})>[];
    final ids = <String>[];
    for (final m in mates) {
      final p = lookup(m.path, _trackOf(m));
      if (p == null) continue;
      mics.add((peaks: p, offsetMs: m.syncOffsetMs!));
      ids.add(_micId(m));
    }
    final at = ids.indexOf(_micId(a));
    if (at < 0) return cache.single(peaks);
    return cache.group('$video>${ids.join('>')}', mics)[at];
  }
}

/// [file] (stretches in a sound file's own time, sorted) as they play on
/// the timeline for something that starts at [startMs] and plays
/// [inMs]..[outMs] of the file at [speed].
List<TimeRange> stretchesOnTimeline(List<TimeRange> file,
    {required int startMs,
    required int inMs,
    required int outMs,
    double speed = 1}) {
  if (file.isEmpty || outMs <= inMs) return const [];
  final s = speed <= 0 || speed.isNaN ? 1.0 : speed;
  // First stretch that ends after inMs.
  var lo = 0, hi = file.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (file[mid].endMs <= inMs) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final out = <TimeRange>[];
  for (var i = lo; i < file.length; i++) {
    final r = file[i];
    if (r.startMs >= outMs) break;
    final a = r.startMs < inMs ? inMs : r.startMs;
    final b = r.endMs > outMs ? outMs : r.endMs;
    if (b <= a) continue;
    out.add((
      startMs: startMs + ((a - inMs) / s).round(),
      endMs: startMs + ((b - inMs) / s).round(),
    ));
  }
  return out;
}

/// One speaker on the timeline.
class SpeakerTrack {
  SpeakerTrack(this.id, this.name, this.stretches, {this.pending = false});

  /// The sound track's id ([SoundTrack.videoId] for the video's own
  /// sound).
  final String id;
  final String name;

  /// Where this speaker talks, timeline time, sorted, not overlapping.
  final List<TimeRange> stretches;

  /// Some of its sound has no picture yet (still being drawn).
  final bool pending;

  late final int talkMs =
      stretches.fold(0, (n, r) => n + r.endMs - r.startMs);
}

List<TimeRange> _merged(List<TimeRange> list, {int joinMs = 1}) {
  if (list.length < 2) return list;
  final sorted = [...list]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <TimeRange>[sorted.first];
  for (final r in sorted.skip(1)) {
    final last = out.last;
    if (r.startMs - last.endMs < joinMs) {
      if (r.endMs > last.endMs) {
        out[out.length - 1] = (startMs: last.startMs, endMs: r.endMs);
      }
    } else {
      out.add(r);
    }
  }
  return out;
}

/// The speakers of [p] with their talk on the timeline: every speech
/// track that has sound; with none, the video's own sound ("Video").
List<SpeakerTrack> speakerTracks(Project p, PeaksLookup lookup,
    [SpeechCache? cache]) {
  final c = cache ?? SpeechCache();
  final resolver = SpeechResolver(p, lookup, c);
  final out = <SpeakerTrack>[];
  for (final t in p.soundTracks) {
    if (!t.speech) continue;
    final clips = p.audio.where((a) => a.trackId == t.id && !a.looped).toList();
    if (clips.isEmpty) continue;
    final all = <TimeRange>[];
    var pending = false;
    for (final a in clips) {
      final file = resolver.fileStretches(a);
      if (file == null) {
        pending = true;
        continue;
      }
      all.addAll(stretchesOnTimeline(file,
          startMs: a.startMs, inMs: a.inMs, outMs: a.outMs, speed: a.speed));
    }
    out.add(SpeakerTrack(t.id, t.name, _merged(all), pending: pending));
  }
  if (out.isNotEmpty) return out;
  // No speech tracks: the video's own sound.
  final all = <TimeRange>[];
  var pending = false, any = false;
  for (var i = 0; i < p.clips.length; i++) {
    final clip = p.clips[i];
    if (clip.type != ClipType.video || !clip.hasAudio || clip.muted) continue;
    any = true;
    final peaks = lookup(clip.path, clip.audioTrackInUse);
    if (peaks == null) {
      pending = true;
      continue;
    }
    all.addAll(stretchesOnTimeline(c.single(peaks),
        startMs: p.clipStartMs(i),
        inMs: clip.inMs,
        outMs: clip.outMs,
        speed: clip.speed));
  }
  if (!any) return const [];
  return [
    SpeakerTrack(SoundTrack.videoId, 'Video', _merged(all), pending: pending),
  ];
}

/// One speaker talking for a while.
typedef SpeakerTurn = ({String id, String name, int startMs, int endMs});

/// A pause from which the same speaker's talk counts as a new turn.
const int kTurnPauseMs = 3000;

/// The talk of all [tracks] as turns, in time order: stretches of one
/// speaker that follow each other (no one else starting in between, no
/// pause of [pauseMs]) are one turn. Where two talk at once the turns
/// overlap.
List<SpeakerTurn> speakerTurns(List<SpeakerTrack> tracks,
    {int pauseMs = kTurnPauseMs}) {
  final all = <({String id, String name, int startMs, int endMs})>[
    for (final t in tracks)
      for (final r in t.stretches)
        (id: t.id, name: t.name, startMs: r.startMs, endMs: r.endMs),
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <SpeakerTurn>[];
  for (final r in all) {
    if (out.isNotEmpty &&
        out.last.id == r.id &&
        r.startMs - out.last.endMs < pauseMs) {
      final last = out.last;
      out[out.length - 1] = (
        id: last.id,
        name: last.name,
        startMs: last.startMs,
        endMs: r.endMs > last.endMs ? r.endMs : last.endMs,
      );
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Pauses shorter than this do not count as a new start for "Go to next
/// / previous speech start".
const int kSpeechStartPauseMs = 700;

/// Where speech starts: on the track [trackId] (after a pause of
/// [kSpeechStartPauseMs]), or, without one, wherever the speaker changes
/// or someone starts again after a long pause ([speakerTurns]). Sorted.
List<int> speechStarts(List<SpeakerTrack> tracks, {String? trackId}) {
  final track = trackId == null
      ? null
      : tracks.where((t) => t.id == trackId).firstOrNull;
  if (track != null) {
    return [
      for (final r in _merged(track.stretches, joinMs: kSpeechStartPauseMs))
        r.startMs,
    ];
  }
  final seen = <int>{};
  return [
    for (final t in speakerTurns(tracks))
      if (seen.add(t.startMs)) t.startMs,
  ]..sort();
}

/// The next ([forward]) or previous of [starts] seen from [positionMs];
/// null when there is none. Going back from just after a start goes to
/// the one before it (so pressing twice steps back twice, also while
/// playing).
int? neighbourStart(List<int> starts, int positionMs, {required bool forward}) {
  if (forward) {
    for (final s in starts) {
      if (s > positionMs + 20) return s;
    }
    return null;
  }
  int? found;
  for (final s in starts) {
    if (s < positionMs - 400) {
      found = s;
    } else {
      break;
    }
  }
  return found;
}

/// Every start and end of talk (for snapping), sorted.
List<int> speechEdges(List<SpeakerTrack> tracks) {
  final out = <int>{};
  for (final t in tracks) {
    for (final r in t.stretches) {
      out
        ..add(r.startMs)
        ..add(r.endMs);
    }
  }
  return out.toList()..sort();
}
