// Pure Dart: the rules of sound tracks, used by ProjectEditor (which
// documents them, see "Sound tracks" in its class comment).
//
//  * Sound clips on ONE track never overlap. Different tracks overlap
//    freely and are mixed.
//  * Placing a clip ([placeOnTracks]): on the wanted track when it is free
//    there; otherwise on the first other track that is free there;
//    otherwise on a new track while there are fewer than the maximum;
//    otherwise on the wanted track right after what is in the way.
//  * Moving a clip by hand along or onto a track ([nearestFreeStart]): the
//    free place nearest to where it was dropped (so a drag stops at a
//    neighbour, and jumps past it once the other side is nearer).
//  * Trimming by hand: the edges stop at the neighbours ([trimLimits]).
//  * A separated sound that is still linked follows its video clip
//    ([syncLinkedSound]); so does a voice recorded separately
//    ([AudioClip.syncOffsetMs]), whose part of ITS file is the clip's part
//    shifted by the offset.

import '../model/project.dart';

/// Start and end (timeline ms) of the sound clips on [trackId] other than
/// [ignoreId], in timeline order.
List<({int start, int end})> busyRanges(Project p, String trackId,
    {String? ignoreId}) {
  final out = <({int start, int end})>[
    for (final a in p.audio)
      if (a.trackId == trackId && a.id != ignoreId && a.durationMs > 0)
        (start: a.startMs, end: a.endMs),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// True when [start]..[end] is free on [trackId] (touching is fine).
bool isFree(Project p, String trackId, int start, int end,
    {String? ignoreId}) {
  for (final r in busyRanges(p, trackId, ignoreId: ignoreId)) {
    if (r.start < end && start < r.end) return false;
  }
  return true;
}

/// The free starts for a clip of [duration] on [trackId], nearest to
/// [desired] (never below 0). With [onlyLater], the first one at or after
/// [desired].
int nearestFreeStart(Project p, String trackId, int desired, int duration,
    {String? ignoreId, bool onlyLater = false}) {
  if (desired < 0) desired = 0;
  final busy = busyRanges(p, trackId, ignoreId: ignoreId);
  // Gaps between the busy ranges: [from, to), the last one open-ended.
  int? best;
  var bestDistance = 1 << 62;
  void consider(int from, int? to) {
    if (to != null && to - from < duration) return;
    final latest = to == null ? null : to - duration;
    var s = desired < from ? from : desired;
    if (latest != null && s > latest) s = latest;
    if (onlyLater && s < desired) return;
    final d = (s - desired).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = s;
    }
  }

  var from = 0;
  for (final r in busy) {
    if (r.start > from) consider(from, r.start);
    if (r.end > from) from = r.end;
  }
  consider(from, null);
  return best ?? from;
}

/// How far the edges of the sound clip [a] may go on its track: the end
/// of the clip before it and the start of the clip after it (null: no
/// limit).
({int lowest, int? highest}) trimLimits(Project p, AudioClip a) {
  var lowest = 0;
  int? highest;
  for (final r in busyRanges(p, a.trackId, ignoreId: a.id)) {
    if (r.end <= a.startMs && r.end > lowest) lowest = r.end;
    if (r.start >= a.endMs && (highest == null || r.start < highest)) {
      highest = r.start;
    }
  }
  return (lowest: lowest, highest: highest);
}

/// The default name for a new track of [p]: the first of
/// [kSoundTrackNames] not in use, else "Sound n".
String nextTrackName(Project p) {
  final used = {for (final t in p.soundTracks) t.name.toLowerCase()};
  for (final n in kSoundTrackNames) {
    if (!used.contains(n.toLowerCase())) return n;
  }
  var n = p.soundTracks.length + 1;
  while (used.contains('sound $n')) {
    n++;
  }
  return 'Sound $n';
}

/// A new track named [name], "Lower under speech" on for a "Music" track
/// when the project's default [Project.duckMusic] is, "speech" on for a
/// "Voice" track.
SoundTrack newTrack(Project p, String id, String name) {
  final lower = name.trim().toLowerCase();
  return SoundTrack(
    id: id,
    name: name,
    speech: lower == 'voice',
    duck: lower.startsWith('music') && p.duckMusic,
  );
}

/// [p] with [clip] put on a track by the placement rule (see the top of
/// this file), [p.tracks] materialised from [Project.soundTracks]. A new
/// track is made with [newId] when needed and allowed ([maxTracks]).
/// The clip is replaced when its id is already in [p.audio], else added.
Project placeOnTracks(Project p, AudioClip clip,
    {required int maxTracks, required String Function() newId}) {
  var tracks = [...p.soundTracks];
  var trackId = clip.trackId;
  // "The Music track" is the one named Music when it has another id.
  if (trackId == kMusicTrackId && !tracks.any((t) => t.id == trackId)) {
    for (final t in tracks) {
      if (t.name.trim().toLowerCase() == 'music') {
        trackId = t.id;
        break;
      }
    }
  }
  if (!tracks.any((t) => t.id == trackId)) {
    if (tracks.length < maxTracks || tracks.isEmpty) {
      final name = trackId == kMusicTrackId ? 'Music' : nextTrackName(p);
      tracks.add(newTrack(p, trackId, name));
    } else {
      trackId = tracks.first.id;
    }
  }
  var base = p.copyWith(tracks: tracks);
  final d = clip.durationMs;
  final start = clip.startMs < 0 ? 0 : clip.startMs;
  var placed = clip.copyWith(trackId: trackId, startMs: start);
  if (!isFree(base, trackId, start, start + d, ignoreId: clip.id)) {
    final other = tracks.where((t) =>
        t.id != trackId &&
        isFree(base, t.id, start, start + d, ignoreId: clip.id));
    if (other.isNotEmpty) {
      placed = placed.copyWith(trackId: other.first.id);
    } else if (tracks.length < maxTracks) {
      final t = newTrack(base, newId(), _similarName(base, trackId));
      tracks = [...tracks, t];
      base = base.copyWith(tracks: tracks);
      placed = placed.copyWith(trackId: t.id);
    } else {
      placed = placed.copyWith(
          startMs: nearestFreeStart(base, trackId, start, d,
              ignoreId: clip.id, onlyLater: true));
    }
  }
  final i = base.audio.indexWhere((a) => a.id == clip.id);
  return base.copyWith(
    audio: i < 0 ? [...base.audio, placed] : ([...base.audio]..[i] = placed),
  );
}

/// A name for a second track of the same kind as [trackId]: "Voice 2".
String _similarName(Project p, String trackId) {
  final of = p.trackById(trackId)?.name ?? 'Sound';
  final stem = of.replaceFirst(RegExp(r'\s+\d+$'), '');
  final used = {for (final t in p.soundTracks) t.name.toLowerCase()};
  var n = 2;
  while (used.contains('${stem.toLowerCase()} $n')) {
    n++;
  }
  return '$stem $n';
}

/// Shortest piece of a separately recorded voice worth an item (timeline
/// ms): a clip the voice file covers for less than this gets none.
const int kMinVoicePieceMs = 100;

/// Where a linked sound of the clip at [index] of [p] goes: the clip's
/// place, part of the file and speed. When the clip starts with a
/// transition and the clip before it has a linked sound on the same track
/// ([prevOnTrack]), the sound starts where the transition ends instead, so
/// that the two do not overlap on the track.
///
/// A voice recorded separately ([AudioClip.syncOffsetMs]) keeps its own
/// file: its part is the clip's part shifted by the offset. Where the voice
/// file has nothing (the clip's part starts before the file does, or runs
/// past its end) the sound starts later / ends earlier, so the result may
/// be shorter than the clip, or empty ([voiceCovers] is then false).
AudioClip mirrorClip(Project p, int index, AudioClip a, {bool prevOnTrack = false}) {
  final c = p.clips[index];
  var start = p.clipStartMs(index);
  var inMs = c.inMs;
  if (prevOnTrack) {
    final o = p.transitionOverlapMs(index);
    if (o > 0) {
      final src = (o * c.speed).round();
      if (c.outMs - (inMs + src) >= 1) {
        start += o;
        inMs += src;
      }
    }
  }
  final offset = a.syncOffsetMs;
  if (offset != null) {
    var vin = inMs + offset;
    var vout = c.outMs + offset;
    if (vin < 0) {
      start += c.speed > 0 ? (-vin / c.speed).round() : -vin;
      vin = 0;
    }
    if (a.sourceDurationMs > 0 && vout > a.sourceDurationMs) {
      vout = a.sourceDurationMs;
    }
    if (vout < vin) vout = vin;
    return a.copyWith(startMs: start, inMs: vin, outMs: vout, speed: c.speed);
  }
  return a.copyWith(
    path: c.path,
    startMs: start,
    inMs: inMs,
    outMs: c.outMs,
    speed: c.speed,
  );
}

/// False for a mirrored voice ([mirrorClip]) with (next to) nothing in it:
/// its file has no sound for that clip.
bool voiceCovers(AudioClip mirrored) =>
    mirrored.syncOffsetMs == null ||
    mirrored.durationMs >= kMinVoicePieceMs &&
        mirrored.sourceSpanMs >= kMinVoicePieceMs;

/// The linked sounds of [p] that are the same voice recording as [a]: the
/// same file with the same offset on the same track, lined up with clips
/// of the same video file as [a]'s clip. [a] itself is always included.
/// Just [a] for anything that is not a voice recorded separately.
List<AudioClip> voiceGroup(Project p, AudioClip a) {
  if (!a.isVoice) return [a];
  final clipPath = {for (final c in p.clips) c.id: c.path};
  final mine = clipPath[a.sourceClipId];
  return [
    for (final x in p.audio)
      if (x.id == a.id ||
          (x.isVoice &&
              x.path == a.path &&
              x.trackId == a.trackId &&
              mine != null &&
              clipPath[x.sourceClipId] == mine))
        x,
  ];
}

/// The linked voice recordings ([AudioClip.isVoice]) of clip [clipId].
List<AudioClip> linkedVoicesOf(Project p, String clipId) => [
      for (final a in p.audio)
        if (a.isVoice && a.linked && a.sourceClipId == clipId) a,
    ];

/// [after] with every linked sound following its video clip:
///
///  * a sound whose clip is still there takes the clip's place, part of
///    the file and speed ([mirrorClip]);
///  * a sound whose clip was deleted is deleted with it;
///  * pieces the edit cut from a clip with a linked sound (a split, Remove
///    silences: new clips of the same file inside the clip's old part of
///    the file, muted like it) get a linked sound of their own, with the
///    same settings, on the same track;
///  * a voice recorded separately belongs to the video FILE: any new clip
///    of that file (a piece, a copy, the file added again) gets its part
///    of every voice lined up with it; a clip the voice file has no sound
///    for gets none, and loses the one it had;
///  * a sound that now overlaps another clip on its track is placed by the
///    placement rule ([placeOnTracks]).
///
/// Returns [after] itself when there is nothing linked.
Project syncLinkedSound(Project before, Project after,
    {required int maxTracks, required String Function() newId}) {
  if (!after.audio.any((a) => a.linked)) return after;
  final index = <String, int>{
    for (var i = 0; i < after.clips.length; i++) after.clips[i].id: i,
  };
  final oldClips = {for (final c in before.clips) c.id: c};

  // The linked sounds of each clip (one separated sound, and one per voice
  // recording).
  final linkedOf = <String, List<AudioClip>>{};
  for (final a in after.audio) {
    if (a.linked && a.sourceClipId != null) {
      (linkedOf[a.sourceClipId!] ??= []).add(a);
    }
  }
  // New pieces of a clip with a linked sound.
  final adds = <AudioClip>[];
  final muteToo = <String>{};
  if (!identical(before.clips, after.clips) && linkedOf.isNotEmpty) {
    for (final c in after.clips) {
      if (oldClips.containsKey(c.id) || c.type != ClipType.video) continue;
      // The clip it was cut from, else any clip of the same file.
      Clip? inside;
      Clip? sameFile;
      for (final parent in before.clips) {
        if (parent.path != c.path ||
            !index.containsKey(parent.id) ||
            linkedOf[parent.id] == null) {
          continue;
        }
        sameFile ??= parent;
        if (parent.inMs <= c.inMs && c.outMs <= parent.outMs) {
          inside = parent;
          break;
        }
      }
      final parent = inside ?? sameFile;
      if (parent == null) continue;
      for (final sound in linkedOf[parent.id]!) {
        if (sound.isVoice) {
          adds.add(sound.copyWith(id: newId(), sourceClipId: c.id));
          // The camera's sound stays off for the whole file.
          if (parent.muted && !c.muted) muteToo.add(c.id);
        } else if (identical(parent, inside) && c.muted) {
          adds.add(sound.copyWith(id: newId(), sourceClipId: c.id));
        }
      }
    }
  }

  // Which tracks each clip's linked sounds are on (for transitions).
  final onTrack = <String>{
    for (final a in [...after.audio, ...adds])
      if (a.linked && a.sourceClipId != null) '${a.sourceClipId}|${a.trackId}',
  };

  var changed = adds.isNotEmpty;
  final audio = <AudioClip>[];
  final moved = <AudioClip>[];
  for (final a in [...after.audio, ...adds]) {
    if (!a.linked || a.sourceClipId == null) {
      audio.add(a);
      continue;
    }
    final i = index[a.sourceClipId];
    if (i == null) {
      changed = true;
      continue;
    }
    final prev = i > 0 ? after.clips[i - 1].id : null;
    final m = mirrorClip(after, i, a,
        prevOnTrack: prev != null && onTrack.contains('$prev|${a.trackId}'));
    if (!voiceCovers(m)) {
      changed = true;
      continue;
    }
    if (m.startMs != a.startMs ||
        m.inMs != a.inMs ||
        m.outMs != a.outMs ||
        m.speed != a.speed ||
        m.path != a.path) {
      changed = true;
    }
    audio.add(m);
    moved.add(m);
  }
  if (!changed) return after;
  var out = after.copyWith(
    audio: audio,
    clips: muteToo.isEmpty
        ? after.clips
        : [
            for (final c in after.clips)
              muteToo.contains(c.id) ? c.copyWith(muted: true) : c,
          ],
  );
  // Overlaps with other clips on the same track.
  for (final m in moved) {
    final cur = out.audio.firstWhere((a) => a.id == m.id);
    if (!isFree(out, cur.trackId, cur.startMs, cur.endMs, ignoreId: cur.id)) {
      out = placeOnTracks(out, cur, maxTracks: maxTracks, newId: newId);
    }
  }
  return out;
}

/// A voice recording that could not be added ([buildVoice]).
class VoiceProblem implements Exception {
  const VoiceProblem(this.message);

  /// One or two sentences for the user.
  final String message;
  @override
  String toString() => message;
}

/// [p] with the voice recording [voice] (its file, length and sound
/// settings; id, place and trim are ignored) lined up with clip [clipId]
/// at [offsetMs] ([AudioClip.syncOffsetMs]) - and with every other clip of
/// the same video file, since the offset belongs to the two files. One
/// linked item per clip, all on one track:
///
///  * [trackId] when given and it exists;
///  * else a speech track nothing is on yet;
///  * else a NEW speech track ([trackName], default "Voice", "Voice 2"...)
///    while there are fewer than [maxTracks];
///  * else a speech track on which every piece is free;
///  * else it cannot be added ([VoiceProblem]): several voices of one
///    conversation overlap all the way, so they cannot share a track.
///
/// [muteClips] mutes those clips (the camera's own sound). Throws
/// [VoiceProblem] also for an unknown clip, a photo, and an offset that
/// leaves the voice file no sound for any clip.
({Project project, List<String> ids, String trackId}) buildVoice(
  Project p,
  AudioClip voice, {
  required String clipId,
  required int offsetMs,
  String? trackId,
  String? trackName,
  bool muteClips = true,
  required int maxTracks,
  required String Function() newId,
}) {
  final first = p.clips.where((c) => c.id == clipId).firstOrNull;
  if (first == null) throw const VoiceProblem('That clip is not in the project.');
  if (first.type != ClipType.video) {
    throw const VoiceProblem('A voice can only be lined up with a video clip.');
  }
  final template = voice.copyWith(
    sourceClipId: clipId,
    linked: true,
    syncOffsetMs: offsetMs,
    loopMs: 0,
    fadeInMs: 0,
    fadeOutMs: 0,
  );
  // The pieces, track undecided.
  AudioClip onTrack(AudioClip a, String t) => a.copyWith(trackId: t);
  List<AudioClip> pieces(String track) {
    final out = <AudioClip>[];
    String? prevWith;
    final used = {for (final a in p.audio) a.id};
    for (var i = 0; i < p.clips.length; i++) {
      final c = p.clips[i];
      if (c.type != ClipType.video || c.path != first.path) continue;
      var id = newId();
      while (!used.add(id)) {
        id = newId();
      }
      final m = mirrorClip(
          p, i, onTrack(template.copyWith(id: id, sourceClipId: c.id), track),
          prevOnTrack: i > 0 && prevWith == p.clips[i - 1].id);
      if (!voiceCovers(m)) continue;
      out.add(m);
      prevWith = c.id;
    }
    return out;
  }

  var tracks = [...p.soundTracks];
  bool fits(String track, List<AudioClip> list) =>
      list.every((m) => isFree(p, track, m.startMs, m.endMs));

  String? track;
  if (trackId != null &&
      trackId != SoundTrack.videoId &&
      tracks.any((t) => t.id == trackId)) {
    track = trackId;
  }
  var probe = pieces(track ?? '');
  if (probe.isEmpty) {
    throw const VoiceProblem(
        'With this offset the voice file has no sound for the clip.');
  }
  if (track != null && !fits(track, probe)) {
    throw VoiceProblem('Other sounds are in the way on the track '
        '"${p.trackById(track)?.name ?? track}".');
  }
  if (track == null) {
    final busy = {for (final a in p.audio) a.trackId};
    final empty =
        tracks.where((t) => t.speech && !busy.contains(t.id)).firstOrNull;
    if (empty != null) {
      track = empty.id;
      final name = _cleanTrackName(trackName);
      if (name != null &&
          empty.name.toLowerCase().startsWith('voice') &&
          !tracks.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
        tracks[tracks.indexOf(empty)] = empty.copyWith(name: name);
      }
    } else if (tracks.length < maxTracks) {
      final ids = {
        for (final t in tracks) t.id,
        SoundTrack.videoId,
        kMusicTrackId,
      };
      var id = newId();
      while (!ids.add(id)) {
        id = newId();
      }
      track = id;
      tracks.add(SoundTrack(
          id: id,
          name: _freeTrackName(tracks, _cleanTrackName(trackName) ?? 'Voice'),
          speech: true));
    } else {
      final shared =
          tracks.where((t) => t.speech && fits(t.id, probe)).firstOrNull;
      if (shared == null) {
        throw VoiceProblem('There is no free sound track for this voice: a '
            'project has at most $maxTracks sound tracks, and voices that '
            'talk at the same time cannot share one. Delete a sound track '
            'you do not need, then add the voice again.');
      }
      track = shared.id;
    }
  }
  final placed = [for (final m in probe) onTrack(m, track)];
  final mutedPath = muteClips ? first.path : null;
  return (
    project: p.copyWith(
      tracks: tracks,
      clips: mutedPath == null
          ? p.clips
          : [
              for (final c in p.clips)
                c.type == ClipType.video && c.path == mutedPath && !c.muted
                    ? c.copyWith(muted: true)
                    : c,
            ],
      audio: [...p.audio, ...placed],
    ),
    ids: [for (final m in placed) m.id],
    trackId: track,
  );
}

String? _cleanTrackName(String? name) {
  final n = name?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (n.isEmpty) return null;
  return n.length > 40 ? n.substring(0, 40).trim() : n;
}

/// [name], or "[name] 2"... when a track is called that already.
String _freeTrackName(List<SoundTrack> tracks, String name) {
  final used = {for (final t in tracks) t.name.toLowerCase()};
  if (!used.contains(name.toLowerCase())) return name;
  var n = 2;
  while (used.contains('${name.toLowerCase()} $n')) {
    n++;
  }
  return '$name $n';
}
