// Pure Dart: timeline snapping. While something is dragged on the timeline
// (a trim handle, a title, a sound, an overlay item), an edge that comes
// close to the playhead or to an edge of another item jumps onto it, so that
// things line up exactly. The timeline draws a line where it snapped.

import '../model/project.dart';

/// The times an edge can snap to in [project]: the start and end of the
/// video, the playhead [playheadMs], every clip edge on the main track
/// (where its picture starts and ends), and the start and end of every
/// title / caption, sound clip and overlay item. Edges of the item with id
/// [ignoreId] (the one being dragged) are left out. [extra]: more times
/// (1.13: where speech starts and ends). Sorted, without duplicates.
List<int> snapTargets(Project project,
    {required int playheadMs, String? ignoreId, Iterable<int> extra = const []}) {
  final out = <int>{0, project.durationMs, playheadMs, ...extra};
  for (var i = 0; i < project.clips.length; i++) {
    final c = project.clips[i];
    if (c.id == ignoreId) continue;
    out.add(project.clipStartMs(i));
    out.add(project.clipEndMs(i));
  }
  for (final t in project.titles) {
    if (t.id == ignoreId) continue;
    out
      ..add(t.startMs)
      ..add(t.endMs);
  }
  for (final a in project.audio) {
    if (a.id == ignoreId) continue;
    out
      ..add(a.startMs)
      ..add(a.endMs);
  }
  for (final o in project.overlays) {
    if (o.id == ignoreId) continue;
    out
      ..add(o.startMs)
      ..add(o.endMs);
  }
  return out.where((t) => t >= 0).toList()..sort();
}

/// [ms] moved onto the nearest of [targets] when that is at most
/// [thresholdMs] away; `snapped` is the target, or null when nothing was
/// near enough (then `ms` is unchanged).
({int ms, int? snapped}) snapTime(int ms, List<int> targets, int thresholdMs) {
  int? best;
  for (final t in targets) {
    final d = (t - ms).abs();
    if (d <= thresholdMs && (best == null || d < (best - ms).abs())) best = t;
  }
  return best == null ? (ms: ms, snapped: null) : (ms: best, snapped: best);
}

/// For something [lengthMs] long dragged so that it would start at
/// [startMs]: the start that lines up whichever of its two edges is
/// nearest to a target (within [thresholdMs]); `snapped` is that target.
({int start, int? snapped}) snapSpan(
    int startMs, int lengthMs, List<int> targets, int thresholdMs) {
  final a = snapTime(startMs, targets, thresholdMs);
  final b = snapTime(startMs + lengthMs, targets, thresholdMs);
  if (a.snapped == null && b.snapped == null) {
    return (start: startMs, snapped: null);
  }
  final da = a.snapped == null ? null : (a.snapped! - startMs).abs();
  final db =
      b.snapped == null ? null : (b.snapped! - (startMs + lengthMs)).abs();
  if (db == null || (da != null && da <= db)) {
    return (start: a.ms, snapped: a.snapped);
  }
  return (start: b.ms - lengthMs, snapped: b.snapped);
}
