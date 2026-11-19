// Keeps "good moment" markers on the picture they were dropped on when an
// edit changes the main track (a cut, Remove silences, a trim, a move, a
// speed change). Pure Dart; used by ProjectEditor after every edit.
//
// Lighter than the titles' anchors (title_anchors.dart), and stateless: a
// marker is found again by the clip it sat on and its place in that clip's
// file; pieces a cut made from the clip (same file) are looked at too. A
// marker whose footage is gone stays at its time, kept inside the video.

import '../model/project.dart';

bool _sameTrack(Project a, Project b) {
  if (identical(a.clips, b.clips)) return true;
  if (a.clips.length != b.clips.length) return false;
  for (var i = 0; i < a.clips.length; i++) {
    final x = a.clips[i], y = b.clips[i];
    if (x.id != y.id ||
        x.inMs != y.inMs ||
        x.outMs != y.outMs ||
        x.speed != y.speed ||
        x.transition != y.transition ||
        x.transitionMs != y.transitionMs) {
      return false;
    }
  }
  return true;
}

/// The markers of [after] moved to where their picture now is, in time
/// order; `after.markers` itself when nothing has to move.
List<Marker> retimeMarkers(Project before, Project after) {
  final markers = after.markers;
  if (markers.isEmpty || before.clips.isEmpty) return markers;
  if (_sameTrack(before, after)) return markers;
  final was = {for (final m in before.markers) m.id: m};
  final total = after.durationMs;
  var changed = false;
  final out = <Marker>[];
  for (final m in markers) {
    final old = was[m.id];
    // New in this edit, or moved by it: it is where it was put.
    if (old == null || old.ms != m.ms) {
      out.add(m);
      continue;
    }
    var ms = _follow(before, after, m.ms);
    if (ms > total) ms = total;
    if (ms < 0) ms = 0;
    if (ms != m.ms) changed = true;
    out.add(m.copyWith(ms: ms));
  }
  if (!changed) return markers;
  out.sort((a, b) => a.ms.compareTo(b.ms));
  return List.unmodifiable(out);
}

int _follow(Project before, Project after, int ms) {
  if (ms >= before.durationMs) {
    // At the very end: stays at the end.
    return ms == before.durationMs ? after.durationMs : ms;
  }
  final i = before.clipIndexAt(ms);
  if (i < 0) return ms;
  final c = before.clips[i];
  final offset = ms - before.clipStartMs(i);
  final photo = c.type == ClipType.photo;
  final speed = c.speed <= 0 || c.speed.isNaN ? 1.0 : c.speed;
  final source = photo ? offset.toDouble() : c.inMs + offset * speed;

  int place(int j, Clip n) {
    final start = after.clipStartMs(j);
    if (photo) return start + offset.clamp(0, n.durationMs);
    final s = n.speed <= 0 || n.speed.isNaN ? 1.0 : n.speed;
    return start + ((source - n.inMs) / s).round().clamp(0, n.durationMs);
  }

  int? sameClip;
  for (var j = 0; j < after.clips.length; j++) {
    final n = after.clips[j];
    if (n.id == c.id) {
      if (photo || (source >= n.inMs && source <= n.outMs)) return place(j, n);
      sameClip = j;
    }
  }
  if (!photo) {
    // A piece of the same file that now holds this moment (after a cut).
    for (var j = 0; j < after.clips.length; j++) {
      final n = after.clips[j];
      if (n.type == ClipType.video &&
          n.path == c.path &&
          source >= n.inMs &&
          source <= n.outMs) {
        return place(j, n);
      }
    }
  }
  // The moment itself was cut away: the nearest edge of its clip, when the
  // clip is still there.
  if (sameClip != null) return place(sameClip, after.clips[sameClip]);
  return ms;
}
