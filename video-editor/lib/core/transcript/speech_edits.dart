// The edits speech-to-text leads to, each ONE undo step, on top of the
// editor's existing operations (so titles and linked voices follow as for
// any other edit). Pure Dart; used by the app and by the MCP tools.

import '../editor/project_editor.dart';
import '../model/project.dart';
import 'cut_plan.dart';
import 'fillers.dart';

/// Cuts [hits] out of their clips (`removeSourceRanges`, the same cut as
/// "Remove silences"). Returns how many separate stretches were removed.
int applyFillerCuts(ProjectEditor e, List<FillerHit> hits) {
  if (hits.isEmpty) return 0;
  final cuts = fillerCuts(hits);
  var removed = 0;
  e.transaction(() {
    for (final entry in cuts.entries) {
      removed += e.removeSourceRanges(entry.key, entry.value);
    }
  },
      label: hits.length == 1
          ? 'Removed 1 filler word'
          : 'Removed ${hits.length} filler words');
  return removed;
}

/// Adds [captions] (and first removes the titles [replaceIds]) as one
/// step.
void addSpeechCaptions(ProjectEditor e, List<TitleOverlay> captions,
    {Iterable<String> replaceIds = const []}) {
  if (captions.isEmpty) return;
  e.transaction(() {
    for (final id in replaceIds) {
      e.removeTitle(id);
    }
    e.addTitles(captions);
  },
      label: captions.length == 1
          ? 'Added 1 caption from speech'
          : 'Added ${captions.length} captions from speech');
}

/// Keeps only [fromMs]..[toMs] of the timeline (a "short"): the main track
/// is split at both ends and everything outside is removed, with the
/// editor's own split and remove - so titles and captions stay on their
/// picture (those on removed footage go) and linked sound (separated
/// sound, voices recorded separately) follows. Music, effects and overlay
/// items, which sit at fixed timeline times, are moved back by the part
/// that was removed in front and cut to the new length; those entirely
/// outside are removed. One undo step. Returns false, changing nothing,
/// when the range holds no part of the video.
bool keepTimelineRange(ProjectEditor e, int fromMs, int toMs) {
  final before = e.project;
  final total = before.durationMs;
  if (fromMs < 0) fromMs = 0;
  if (toMs > total) toMs = total;
  if (before.clips.isEmpty || toMs - fromMs < ProjectEditor.minDurationMs) {
    return false;
  }
  bool follows(AudioClip a) => a.belongsToClip && a.linked;
  final freeSounds = [
    for (final a in before.audio)
      if (!follows(a)) a,
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final overlays = [...before.overlays]
    ..sort((a, b) => a.startMs.compareTo(b.startMs));
  var ok = true;
  e.transaction(() {
    if (toMs < total) e.splitAt(toMs);
    if (fromMs > 0) e.splitAt(fromMs);
    final p = e.project;
    final drop = <String>[];
    int? keptStart;
    for (var i = 0; i < p.clips.length; i++) {
      final s = p.clipStartMs(i), end = p.clipEndMs(i);
      final mid = (s + end) ~/ 2;
      if (mid < fromMs || mid >= toMs) {
        drop.add(p.clips[i].id);
      } else {
        keptStart ??= s + p.transitionOverlapMs(i);
      }
    }
    if (drop.length == p.clips.length || keptStart == null) {
      ok = false;
      return;
    }
    for (final id in drop) {
      e.removeClip(id);
    }
    final shift = keptStart;
    final length = e.project.durationMs;
    for (final a in freeSounds) {
      if (!e.project.audio.any((x) => x.id == a.id)) continue;
      final start = a.startMs - shift;
      final end = a.endMs - shift;
      if (end <= ProjectEditor.minDurationMs || start >= length) {
        e.removeAudio(a.id);
        continue;
      }
      if (start >= 0) {
        e.updateAudio(a.copyWith(startMs: start));
      } else if (a.looped) {
        e.updateAudio(a.copyWith(startMs: 0, loopMs: a.loopMs + start));
      } else {
        final speed = a.speed <= 0 || a.speed.isNaN ? 1.0 : a.speed;
        e.updateAudio(a.copyWith(
            startMs: 0, inMs: a.inMs + (-start * speed).round(), fadeInMs: 0));
      }
    }
    for (final o in overlays) {
      if (!e.project.overlays.any((x) => x.id == o.id)) continue;
      final start = o.startMs - shift;
      final end = o.endMs - shift;
      if (end <= ProjectEditor.minDurationMs || start >= length) {
        e.removeOverlay(o.id);
        continue;
      }
      if (start >= 0) {
        e.updateOverlay(o.copyWith(startMs: start));
      } else if (o.clip.type == ClipType.photo) {
        e.updateOverlay(o.copyWith(
            startMs: 0, clip: o.clip.copyWith(outMs: o.clip.outMs + start)));
      } else {
        final speed = o.clip.speed <= 0 ? 1.0 : o.clip.speed;
        e.updateOverlay(o.copyWith(
            startMs: 0,
            clip: o.clip.copyWith(inMs: o.clip.inMs + (-start * speed).round())));
      }
    }
  }, label: 'Kept one part of the video');
  if (!ok) {
    // Nothing fitted: take the splits back.
    if (!identical(e.project, before)) e.undo();
    return false;
  }
  return !identical(e.project, before);
}

/// Cuts the planned cuts out (as [applyFillerCuts]), puts a short
/// dissolve on the ones marked smooth, and records every cut in the
/// project's automatic-cut log ([Project.autoCuts]) so it can be listed
/// and put back. One undo step. Returns how many were cut.
int applyPlannedCuts(ProjectEditor e, List<PlannedCut> plan,
    {String by = 'app', required String Function() newId, DateTime? now}) {
  final cuts = [
    for (final c in plan)
      if (c.isCut) c,
  ];
  if (cuts.isEmpty) return 0;
  final at = now ?? DateTime.now();
  final pathOf = {for (final c in e.project.clips) c.id: c.path};
  e.transaction(() {
    final byClip = fillerCuts([for (final c in cuts) c.hit]);
    for (final entry in byClip.entries) {
      e.removeSourceRanges(entry.key, entry.value);
    }
    final log = [...e.project.autoCuts];
    for (final c in cuts) {
      final path = pathOf[c.hit.clipId];
      if (path == null) continue;
      var smoothed = false;
      if (c.smooth) {
        // The piece that now starts where the cut ended.
        final after = e.project.clips
            .where((x) =>
                x.path == path &&
                x.inMs >= c.hit.cutEndMs - 1 &&
                x.inMs <= c.hit.cutEndMs + 1)
            .firstOrNull;
        if (after != null && after.durationMs >= 4 * kSmoothMs) {
          e.setClipTransition(after.id, TransitionType.crossfade,
              durationMs: kSmoothMs);
          smoothed = true;
        }
      }
      log.add(AutoCut(
        id: newId(),
        kind: 'filler',
        path: path,
        startMs: c.hit.cutStartMs,
        endMs: c.hit.cutEndMs,
        word: c.hit.entry,
        at: at,
        by: by,
        jump: c.jump,
        smoothed: smoothed,
      ));
    }
    e.setAutoCuts(log);
  },
      label: cuts.length == 1
          ? 'Removed 1 filler word'
          : 'Removed ${cuts.length} filler words');
  return cuts.length;
}

/// Records silences that were just cut out of [path] in the log (inside
/// the caller's transaction, so it is the same undo step).
void logSilenceCuts(ProjectEditor e, String path,
    List<({int startMs, int endMs})> ranges,
    {String by = 'app', required String Function() newId, DateTime? now}) {
  if (ranges.isEmpty) return;
  final at = now ?? DateTime.now();
  e.setAutoCuts([
    ...e.project.autoCuts,
    for (final r in ranges)
      AutoCut(
          id: newId(),
          kind: 'silence',
          path: path,
          startMs: r.startMs,
          endMs: r.endMs,
          at: at,
          by: by),
  ]);
}

/// How a cut was put back.
enum RestoreResult {
  /// The two pieces around it are one clip again.
  healed,

  /// The removed part is back as a clip of its own (the pieces around it
  /// had changed).
  asClip,

  /// It could not be put back (no clip of that file is left to copy the
  /// settings from); the log entry stays.
  failed,

  /// No such cut.
  unknown,
}

RestoreResult _restore(ProjectEditor e, AutoCut cut, String Function() newId) {
  final p = e.project;
  // The piece that ends where the cut starts and the next clip, when that
  // starts where the cut ends: nothing changed between them.
  for (var i = 0; i + 1 < p.clips.length; i++) {
    final a = p.clips[i], b = p.clips[i + 1];
    if (a.path != cut.path || b.path != cut.path) continue;
    if ((a.outMs - cut.startMs).abs() > 2 || (b.inMs - cut.endMs).abs() > 2) continue;
    if (a.speed != b.speed) continue;
    final speed = a.speed <= 0 ? 1.0 : a.speed;
    // Titles on the later piece would go with it: remember them, and put
    // them back moved by the length that returns.
    final titlesBefore = {for (final t in p.titles) t.id: t};
    final bStart = p.clipStartMs(i + 1);
    final startOfA = p.clipStartMs(i);
    e.trimClip(a.id, outMs: b.outMs);
    e.removeClip(b.id);
    final healed = e.project.clips.where((c) => c.id == a.id).firstOrNull;
    if (healed == null || healed.outMs != b.outMs) return RestoreResult.failed;
    final shift = startOfA + ((b.inMs - a.inMs) / speed).round() - bStart;
    final lost = [
      for (final t in titlesBefore.values)
        if (!e.project.titles.any((x) => x.id == t.id))
          t.copyWith(startMs: t.startMs + shift, endMs: t.endMs + shift),
    ];
    if (lost.isNotEmpty) e.addTitles(lost);
    return RestoreResult.healed;
  }
  // Otherwise: the removed part as its own clip, after the last piece of
  // the file that ends at or before it (else before the first that starts
  // after it).
  Clip? template;
  var index = p.clips.length;
  for (var i = 0; i < p.clips.length; i++) {
    final c = p.clips[i];
    if (c.path != cut.path) continue;
    template ??= c;
    if (c.outMs <= cut.startMs + 2) {
      template = c;
      index = i + 1;
    } else if (c.inMs >= cut.endMs - 2 && index == p.clips.length) {
      index = i;
    }
  }
  if (template == null) return RestoreResult.failed;
  final before = p.clips.length;
  e.addClip(
      template.copyWith(
          id: newId(),
          inMs: cut.startMs,
          outMs: cut.endMs,
          transition: TransitionType.none,
          fadeInMs: 0,
          fadeOutMs: 0),
      index: index);
  return e.project.clips.length > before
      ? RestoreResult.asClip
      : RestoreResult.failed;
}

/// "Put back": undoes the automatic cut [cutId] - the two pieces around it
/// become one clip again when nothing changed between them, otherwise the
/// removed part comes back as a clip of its own - and takes it off the
/// log. One undo step.
RestoreResult restoreAutoCut(ProjectEditor e, String cutId,
    {required String Function() newId}) {
  final cut = e.project.autoCuts.where((c) => c.id == cutId).firstOrNull;
  if (cut == null) return RestoreResult.unknown;
  var result = RestoreResult.failed;
  e.transaction(() {
    result = _restore(e, cut, newId);
    if (result != RestoreResult.failed) {
      e.setAutoCuts([
        for (final c in e.project.autoCuts)
          if (c.id != cutId) c,
      ]);
    }
  }, label: 'Put back 1 automatic cut');
  return result;
}

/// "Put back all automatic cuts" ([kind]: only fillers / only silences).
/// One undo step. Returns how many came back.
int restoreAllAutoCuts(ProjectEditor e,
    {String? kind, required String Function() newId}) {
  final wanted = [
    for (final c in e.project.autoCuts)
      if (kind == null || c.kind == kind) c,
  ]..sort((a, b) => b.startMs.compareTo(a.startMs));
  if (wanted.isEmpty) return 0;
  var restored = 0;
  e.transaction(() {
    final done = <String>{};
    for (final cut in wanted) {
      if (_restore(e, cut, newId) != RestoreResult.failed) {
        restored++;
        done.add(cut.id);
      }
    }
    e.setAutoCuts([
      for (final c in e.project.autoCuts)
        if (!done.contains(c.id)) c,
    ]);
  },
      label: wanted.length == 1
          ? 'Put back 1 automatic cut'
          : 'Put back ${wanted.length} automatic cuts');
  return restored;
}

/// Count, time saved and cuts per minute of the automatic cuts in [p].
({int count, int savedMs, double perMinute}) autoCutTotals(Project p) {
  final saved = p.autoCuts.fold<int>(0, (n, c) => n + c.lengthMs);
  final minutes = (p.durationMs + saved) / 60000;
  return (
    count: p.autoCuts.length,
    savedMs: saved,
    perMinute: minutes <= 0 ? 0 : p.autoCuts.length / minutes,
  );
}

/// What "Cut this part out of the video" (the Text window, 1.13) would
/// remove for a stretch of the timeline.
class TimelineCutPlan {
  const TimelineCutPlan(this.fromMs, this.toMs, this.parts, this.photosLeft);
  final int fromMs;
  final int toMs;

  /// Per clip: the part of its SOURCE file that goes; [whole]: the clip
  /// goes completely.
  final List<({String clipId, String path, int startMs, int endMs, bool whole, int timelineMs})>
      parts;

  /// Photos that are only partly inside the stretch stay as they are.
  final int photosLeft;

  /// Length that leaves the video (timeline time).
  int get removedMs => parts.fold(0, (n, x) => n + x.timelineMs);
  bool get isEmpty => parts.isEmpty;
}

/// Works out [TimelineCutPlan] for [fromMs]..[toMs] of [p]'s timeline.
/// Nothing is changed.
TimelineCutPlan planTimelineCut(Project p, int fromMs, int toMs) {
  if (fromMs < 0) fromMs = 0;
  if (toMs > p.durationMs) toMs = p.durationMs;
  final parts =
      <({String clipId, String path, int startMs, int endMs, bool whole, int timelineMs})>[];
  var photos = 0;
  if (toMs - fromMs < 1) return TimelineCutPlan(fromMs, toMs, parts, 0);
  for (var i = 0; i < p.clips.length; i++) {
    final c = p.clips[i];
    final start = p.clipStartMs(i), end = p.clipEndMs(i);
    final a = fromMs > start ? fromMs : start;
    final b = toMs < end ? toMs : end;
    if (b <= a) continue;
    final min = ProjectEditor.minDurationMs;
    final whole = a - start < min && end - b < min;
    if (c.type == ClipType.photo) {
      if (whole) {
        parts.add((
          clipId: c.id, path: c.path, startMs: c.inMs, endMs: c.outMs, //
          whole: true, timelineMs: end - start,
        ));
      } else {
        photos++;
      }
      continue;
    }
    if (whole) {
      parts.add((
        clipId: c.id, path: c.path, startMs: c.inMs, endMs: c.outMs, //
        whole: true, timelineMs: end - start,
      ));
      continue;
    }
    // Pieces shorter than the minimum would be dropped with the cut:
    // stretch the cut over them so the log says what really went.
    final srcA = a - start < min ? c.inMs : c.sourceMsAt(a - start);
    final srcB = end - b < min ? c.outMs : c.sourceMsAt(b - start);
    if (srcB - srcA < 1) continue;
    parts.add((
      clipId: c.id, path: c.path, startMs: srcA, endMs: srcB, //
      whole: false, timelineMs: b - a,
    ));
  }
  return TimelineCutPlan(fromMs, toMs, parts, photos);
}

/// Cuts [plan] out of the video: one undo step, every removed piece of a
/// video file recorded in the automatic-cut log (kind "text", [word] =
/// what was said there) so that it can be put back. Titles and captions
/// on the removed footage go with it, linked sound follows (the editor's
/// own rules). Returns how many pieces were removed.
int applyTimelineCut(ProjectEditor e, TimelineCutPlan plan,
    {String word = '',
    String by = 'app',
    required String Function() newId,
    DateTime? now}) {
  if (plan.isEmpty) return 0;
  final at = now ?? DateTime.now();
  var done = 0;
  e.transaction(() {
    final log = <AutoCut>[];
    // Back to front, so that earlier clips keep their place meanwhile.
    for (final part in plan.parts.reversed) {
      final clip = e.project.clips.where((c) => c.id == part.clipId).firstOrNull;
      if (clip == null) continue;
      final before = e.project;
      if (part.whole) {
        e.removeClip(part.clipId);
      } else {
        e.removeSourceRanges(
            part.clipId, [(startMs: part.startMs, endMs: part.endMs)]);
      }
      if (identical(before, e.project)) continue;
      done++;
      if (clip.type == ClipType.video) {
        log.add(AutoCut(
          id: newId(),
          kind: 'text',
          path: part.path,
          startMs: part.startMs,
          endMs: part.endMs,
          word: word,
          at: at,
          by: by,
        ));
      }
    }
    if (log.isNotEmpty) e.setAutoCuts([...e.project.autoCuts, ...log.reversed]);
  }, label: 'Cut a part out of the video');
  return done;
}
