// Keeps titles and captions on the picture they were placed over when an
// edit changes the timing of the main track. Pure Dart; used only by
// `ProjectEditor`, which documents the rules (see `ProjectEditor` class
// comment, "Titles follow the picture").
//
// How it works: before an edit, the start and the end of every title are
// turned into an ANCHOR - (clip id, position in that clip's source file) for
// video, (clip id, offset inside the clip) for photos. After the edit the
// anchors are mapped back through the new clip layout. Anchors are kept
// between edits (as fractional source positions) for as long as the title is
// still where they put it, so repeated edits do not add up rounding errors.

import '../model/project.dart';

/// Start times of all clips of a project, computed once.
class _Layout {
  _Layout(Project p) : clips = p.clips {
    var t = 0;
    for (var i = 0; i < clips.length; i++) {
      final start = t - p.transitionOverlapMs(i);
      starts.add(start);
      t = start + clips[i].durationMs;
      indexOf[clips[i].id] = i;
    }
    duration = t;
  }

  final List<Clip> clips;
  final List<int> starts = [];
  final Map<String, int> indexOf = {};
  late final int duration;

  int end(int i) => starts[i] + clips[i].durationMs;

  /// Same rule as [Project.clipIndexAt]; the track must not be empty.
  int indexAt(int timeMs) {
    var found = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= timeMs) found = i;
    }
    return found;
  }
}

class _Anchor {
  const _Anchor(this.clipId, this.photo, this.pos, {this.before, this.after});

  final String clipId;
  final bool photo;

  /// Source position in ms (video) or offset inside the clip in ms (photo).
  final double pos;

  /// Set once the clip is gone: the ids of the clips that came before it
  /// (nearest first) and after it when it disappeared.
  final List<String>? before;
  final List<String>? after;
}

class _Resolved {
  const _Resolved(this.time, this.anchor, this.index,
      {this.exact = true, this.gone = false});
  final double time;
  final _Anchor anchor;

  /// Track index of the clip the time lies on; null when [gone].
  final int? index;

  /// The anchored picture is still on the track.
  final bool exact;

  /// The anchor's clip is not on the track at all.
  final bool gone;
}

class _Entry {
  const _Entry({
    this.start,
    this.end,
    this.extraMs = 0,
    this.durationMs = 0,
    this.startLossy = false,
    this.endLossy = false,
    this.absolute = false,
    this.absStartMs = 0,
    this.absEndMs = 0,
  });

  /// Null means: work the anchor out from the title's current time.
  final _Anchor? start;
  final _Anchor? end;

  /// Part of the title that lies past the end of the main track.
  final int extraMs;

  /// On-screen length when the anchors were taken.
  final int durationMs;

  /// The picture under that edge is currently not on the track (the edge is
  /// clamped). Such anchors are only kept until the transaction ends.
  final bool startLossy;
  final bool endLossy;

  /// The title is not attached to a clip (it starts at or after the end of
  /// the track, or there are no clips).
  final bool absolute;
  final int absStartMs;
  final int absEndMs;
}

class _Dropped {
  const _Dropped(this.title, this.index, this.entry);
  final TitleOverlay title;
  final int index;
  final _Entry entry;
}

/// What the editor remembers about its titles between edits. Immutable.
class TitleAnchors {
  const TitleAnchors._(this._entries, this._dropped);

  static const TitleAnchors empty = TitleAnchors._({}, []);

  final Map<String, _Entry> _entries;

  /// Titles removed by an edit of the running transaction; they come back
  /// when a later edit of the same transaction restores their picture.
  final List<_Dropped> _dropped;

  /// The state to keep once an edit (or a transaction) is complete: titles
  /// that were dropped stay dropped, and clamped edges are from now on
  /// attached to the picture they were clamped to.
  TitleAnchors settled() {
    if (_entries.isEmpty && _dropped.isEmpty) return this;
    final kept = <String, _Entry>{};
    _entries.forEach((id, e) {
      if (e.absolute) return;
      final start = e.startLossy ? null : e.start;
      final end = e.endLossy ? null : e.end;
      if (start == null && end == null) return;
      kept[id] = _Entry(
        start: start,
        end: end,
        extraMs: e.extraMs,
        durationMs: e.durationMs,
      );
    });
    return TitleAnchors._(kept, const []);
  }
}

bool _sameTiming(List<Clip> a, List<Clip> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (identical(x, y)) continue;
    if (x.id != y.id ||
        x.type != y.type ||
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

_Anchor _anchorAt(_Layout l, int i, int timeMs) {
  final c = l.clips[i];
  final local = (timeMs - l.starts[i]).clamp(0, c.durationMs).toDouble();
  if (c.type == ClipType.photo) return _Anchor(c.id, true, local);
  final pos = (c.inMs + local * c.speed)
      .clamp(c.inMs.toDouble(), c.outMs.toDouble())
      .toDouble();
  return _Anchor(c.id, false, pos);
}

/// Where [a] is on the track [nl]. [ol] is the track before the edit and
/// [newIds] the clips the edit created (pieces of a split or cut clip).
_Resolved _resolve(
    _Anchor a, bool endSide, _Layout nl, _Layout ol, Set<String> newIds) {
  final own = nl.indexOf[a.clipId];
  final k = own != null && (nl.clips[own].type == ClipType.photo) == a.photo
      ? own
      : null;
  final oldIndex = ol.indexOf[a.clipId];
  final siblings = <int>[];
  if (oldIndex != null && newIds.isNotEmpty) {
    final old = ol.clips[oldIndex];
    for (var j = 0; j < nl.clips.length; j++) {
      final c = nl.clips[j];
      if (newIds.contains(c.id) && c.path == old.path && c.type == old.type) {
        siblings.add(j);
      }
    }
  }

  if (k == null && siblings.isEmpty) {
    // The clip is gone: fall back to the place it used to be.
    var before = a.before;
    var after = a.after;
    if (before == null || after == null) {
      before = [
        if (oldIndex != null)
          for (var j = oldIndex - 1; j >= 0; j--) ol.clips[j].id,
      ];
      after = [
        if (oldIndex != null)
          for (var j = oldIndex + 1; j < ol.clips.length; j++) ol.clips[j].id,
      ];
    }
    final anchor =
        _Anchor(a.clipId, a.photo, a.pos, before: before, after: after);
    if (endSide) {
      for (final id in before) {
        final j = nl.indexOf[id];
        if (j != null) {
          return _Resolved(nl.end(j).toDouble(), anchor, null,
              exact: false, gone: true);
        }
      }
      return _Resolved(0, anchor, null, exact: false, gone: true);
    }
    for (final id in after) {
      final j = nl.indexOf[id];
      if (j != null) {
        return _Resolved(nl.starts[j].toDouble(), anchor, null,
            exact: false, gone: true);
      }
    }
    return _Resolved(nl.duration.toDouble(), anchor, null,
        exact: false, gone: true);
  }

  if (a.photo) {
    // Pieces of a split photo follow each other; the offset carries over.
    var j = k ?? siblings.first;
    var pos = a.pos;
    while (true) {
      final d = nl.clips[j].durationMs;
      if (pos >= 0 && (endSide ? pos <= d : pos < d)) {
        return _Resolved(
            nl.starts[j] + pos, _Anchor(nl.clips[j].id, true, pos), j);
      }
      final next = j + 1;
      if (pos >= d &&
          next < nl.clips.length &&
          siblings.contains(next) &&
          nl.clips[next].type == ClipType.photo) {
        pos -= d;
        j = next;
        continue;
      }
      return _Resolved(nl.end(j).toDouble(), a, j, exact: false);
    }
  }

  final candidates = [?k, ...siblings];
  double timeIn(int j) {
    final c = nl.clips[j];
    final local = ((a.pos - c.inMs) / c.speed).clamp(0, c.durationMs);
    return nl.starts[j] + local.toDouble();
  }

  // The piece that shows the anchored frame. Ranges are half-open so that a
  // position exactly on a cut goes to the right side of it: an end belongs
  // to the piece before the cut, a start to the piece after it.
  for (final j in candidates) {
    final c = nl.clips[j];
    if (endSide
        ? c.inMs < a.pos && a.pos <= c.outMs
        : c.inMs <= a.pos && a.pos < c.outMs) {
      return _Resolved(timeIn(j), _Anchor(c.id, false, a.pos), j);
    }
  }

  // The frame was trimmed or cut away: clamp to the neighbouring kept piece.
  if (endSide) {
    int? best;
    for (final j in candidates) {
      if (nl.clips[j].outMs <= a.pos &&
          (best == null || nl.clips[j].outMs > nl.clips[best].outMs)) {
        best = j;
      }
    }
    if (best != null) {
      return _Resolved(nl.end(best).toDouble(), a, best, exact: false);
    }
    var first = candidates.first;
    for (final j in candidates) {
      if (nl.clips[j].inMs < nl.clips[first].inMs) first = j;
    }
    return _Resolved(nl.starts[first].toDouble(), a, first, exact: false);
  }
  int? best;
  for (final j in candidates) {
    if (nl.clips[j].inMs >= a.pos &&
        (best == null || nl.clips[j].inMs < nl.clips[best].inMs)) {
      best = j;
    }
  }
  if (best != null) {
    return _Resolved(nl.starts[best].toDouble(), a, best, exact: false);
  }
  var last = candidates.first;
  for (final j in candidates) {
    if (nl.clips[j].outMs > nl.clips[last].outMs) last = j;
  }
  return _Resolved(nl.end(last).toDouble(), a, last, exact: false);
}

/// End time of a title that starts at [startMs], or null when it is gone.
int? _endFor(int startMs, _Resolved rs, _Resolved re, _Entry e, int minMs) {
  if (rs.gone && re.gone && e.extraMs == 0) return null;
  var end = re.time.round() + e.extraMs;
  if (end <= startMs) {
    // The start frame is gone and the edges were clamped onto each other:
    // nothing is left of the title.
    if (!rs.exact) return null;
    // The start frame is still there, so the clip with the end frame now
    // comes before it (a reorder): keep the start and the length.
    end = startMs + e.durationMs;
  }
  if (end - startMs < minMs) end = startMs + minMs;
  return end;
}

/// The anchors of [t] on the track [l] it currently sits on: remembered
/// ones as far as they still describe where the title is, fresh ones
/// otherwise.
_Entry _entryFor(TitleOverlay t, _Entry? cached, _Layout l, int minMs) {
  if (cached != null && cached.absolute) {
    if (cached.absStartMs == t.startMs && cached.absEndMs == t.endMs) {
      return cached;
    }
    cached = null;
  }
  const none = <String>{};
  var start = cached?.start;
  var startLossy = cached?.startLossy ?? false;
  _Resolved? rs;
  if (start != null) {
    rs = _resolve(start, false, l, l, none);
    if (rs.time.round() != t.startMs) start = null;
  }
  if (start == null) {
    if (l.clips.isEmpty || t.startMs >= l.duration) {
      return _Entry(absolute: true, absStartMs: t.startMs, absEndMs: t.endMs);
    }
    start = _anchorAt(l, l.indexAt(t.startMs), t.startMs);
    startLossy = false;
    rs = _resolve(start, false, l, l, none);
  }

  // An end that used to hang past the end of the track is only kept while
  // it still does; once clips follow it, it is attached to them.
  if (cached != null &&
      cached.end != null &&
      (cached.extraMs == 0 || t.endMs > l.duration)) {
    final re = _resolve(cached.end!, true, l, l, none);
    final candidate = _Entry(
      start: start,
      end: cached.end,
      extraMs: cached.extraMs,
      durationMs: cached.durationMs,
      startLossy: startLossy,
      endLossy: cached.endLossy,
    );
    if (_endFor(t.startMs, rs!, re, candidate, minMs) == t.endMs) {
      return candidate;
    }
  }
  final startIndex = l.indexAt(t.startMs);
  final endMs = t.endMs > l.duration ? l.duration : t.endMs;
  final endIndex = endMs <= l.end(startIndex) ? startIndex : l.indexAt(endMs - 1);
  return _Entry(
    start: start,
    end: _anchorAt(l, endIndex, endMs),
    extraMs: t.endMs - endMs,
    durationMs: t.endMs - t.startMs,
    startLossy: startLossy,
  );
}

/// [t] moved to where its anchors are on [nl], and the entry to remember;
/// a null title means it is dropped.
({TitleOverlay? title, _Entry entry}) _place(TitleOverlay t, _Entry e,
    _Layout nl, _Layout ol, Set<String> newIds, int minMs) {
  if (e.absolute) return (title: t, entry: e);
  final rs = _resolve(e.start!, false, nl, ol, newIds);
  final re = _resolve(e.end!, true, nl, ol, newIds);
  final entry = _Entry(
    start: rs.anchor,
    end: re.anchor,
    extraMs: e.extraMs,
    durationMs: e.durationMs,
    startLossy: !rs.exact,
    endLossy: !re.exact,
  );
  final start = rs.time.round();
  final end = _endFor(start, rs, re, e, minMs);
  if (end == null) return (title: null, entry: entry);
  return (
    title: start == t.startMs && end == t.endMs
        ? t
        : t.copyWith(startMs: start, endMs: end),
    entry: entry,
  );
}

/// The titles of [after] moved so that they stay on the picture they were
/// over in [before], and the anchors to remember. Returns null when the
/// timing of the main track did not change (nothing to do).
///
/// [after] must have the titles of [before]. [state] is what the previous
/// call returned (or [TitleAnchors.empty]).
({List<TitleOverlay> titles, TitleAnchors state})? retimeTitles({
  required Project before,
  required Project after,
  required TitleAnchors state,
  required int minDurationMs,
}) {
  if (identical(before.clips, after.clips)) return null;
  if (after.titles.isEmpty && state._dropped.isEmpty) return null;
  if (_sameTiming(before.clips, after.clips)) return null;

  final ol = _Layout(before);
  final nl = _Layout(after);
  final newIds = {
    for (final c in after.clips)
      if (!ol.indexOf.containsKey(c.id)) c.id,
  };

  final titles = <TitleOverlay>[];
  final entries = <String, _Entry>{};
  final dropped = <_Dropped>[];
  final present = <String>{};
  var changed = false;
  for (final t in after.titles) {
    present.add(t.id);
    final entry = _entryFor(t, state._entries[t.id], ol, minDurationMs);
    final placed = _place(t, entry, nl, ol, newIds, minDurationMs);
    if (placed.title == null) {
      dropped.add(_Dropped(t, titles.length, placed.entry));
      changed = true;
      continue;
    }
    if (!identical(placed.title, t)) changed = true;
    titles.add(placed.title!);
    entries[t.id] = placed.entry;
  }
  for (final d in state._dropped) {
    if (present.contains(d.title.id)) continue;
    final placed = _place(d.title, d.entry, nl, ol, newIds, minDurationMs);
    if (placed.title == null) {
      dropped.add(_Dropped(d.title, d.index, placed.entry));
      continue;
    }
    titles.insert(d.index.clamp(0, titles.length), placed.title!);
    entries[d.title.id] = placed.entry;
    changed = true;
  }
  return (
    titles: changed ? titles : after.titles,
    state: TitleAnchors._(entries, dropped),
  );
}
