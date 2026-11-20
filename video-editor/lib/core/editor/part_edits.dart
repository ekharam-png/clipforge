part of 'project_editor.dart';

// The edits on a selected part of the timeline (1.17); see part.dart for
// the part, the rows and "why not". Each is ONE undo step with a History
// name, works across clip boundaries (the main track is split at the
// part's edges where needed) and leaves titles, captions, markers and
// linked sound to the editor's own follow rules.

/// What an action on a part did.
class PartResult {
  const PartResult({this.changed = 0, this.problem, this.part, this.removedMs = 0});

  /// How many items were changed (clips, sounds, titles...); 0: nothing.
  final int changed;

  /// Why nothing was done (a short lower-case reason); null when done.
  final String? problem;

  /// Where the part is afterwards, when the action moved or resized it
  /// (speed, duplicate); null: unchanged, or gone (cut out).
  final TimelinePart? part;

  /// Time that left the video (cut out).
  final int removedMs;

  bool get ok => problem == null && changed > 0;
}

/// Short fades put on the two halves of a sound that a cut joins, so the
/// join does not click.
const int kJoinFadeMs = 20;

extension PartEdits on ProjectEditor {
  String _rowNames(Project p, TimelinePart part, PartAction a, Set<String>? rows) {
    final names = [for (final r in partRowsFor(p, part, a, rows)) r.name];
    if (names.isEmpty) return '';
    if (allRowsTicked(p, rows) && names.length > 2) return ' on every row';
    return ' on ${names.join(', ')}';
  }

  /// "Silence" ([level] 0) / "Lower volume" ([level] a linear factor under
  /// 1) for [part] on the ticked [rows] (null: every row): a [QuietRange]
  /// on each sound that plays there - the video's own sound, sounds on
  /// the sound tracks (linked voices included), overlay items. No time
  /// moves; nothing is split.
  PartResult silencePart(TimelinePart part,
      {Set<String>? rows, double level = 0}) {
    final p = _project;
    final lv = level.isNaN ? 0.0 : level.clamp(0.0, 1.0).toDouble();
    final action = lv <= 0.0005 ? PartAction.silence : PartAction.lower;
    final problem = partActionProblem(p, part, action, rows);
    if (problem != null) return PartResult(problem: problem);
    if (lv >= 1) return const PartResult(problem: 'that level changes nothing');
    var changed = 0;
    final okRows = {for (final r in partRowsFor(p, part, action, rows)) r.id};
    final clips = [...p.clips];
    if (okRows.contains(kRowVideo)) {
      for (final x in clipsInPart(p, part)) {
        final c = x.clip;
        if (c.type != ClipType.video || !c.hasAudio || c.muted) continue;
        if (x.srcTo <= x.srcFrom) continue;
        final q = addQuietRange(
            c.quiet,
            _quietOver(x.srcFrom, x.srcTo, lv,
                fromEdge: part.startMs <= p.clipStartMs(x.index),
                toEdge: part.endMs >= p.clipEndMs(x.index)));
        if (_sameQuiet(q, c.quiet)) continue;
        clips[x.index] = c.copyWith(quiet: q);
        changed++;
      }
    }
    final audio = [...p.audio];
    for (var i = 0; i < audio.length; i++) {
      final a = audio[i];
      if (!okRows.contains(a.trackId)) continue;
      final r = soundSourceRange(a, part);
      if (r == null) continue;
      final q = addQuietRange(
          a.quiet,
          _quietOver(r.from, r.to, lv,
              fromEdge: !a.looped && part.startMs <= a.startMs,
              toEdge: !a.looped && part.endMs >= a.endMs));
      if (_sameQuiet(q, a.quiet)) continue;
      audio[i] = a.copyWith(quiet: q);
      changed++;
    }
    final overlays = [...p.overlays];
    if (okRows.contains(kRowOverlay)) {
      for (var i = 0; i < overlays.length; i++) {
        final o = overlays[i];
        if (!o.audible) continue;
        final r = overlaySourceRange(o, part);
        if (r == null) continue;
        final q = addQuietRange(
            o.clip.quiet,
            _quietOver(r.from, r.to, lv,
                fromEdge: part.startMs <= o.startMs,
                toEdge: part.endMs >= o.endMs));
        if (_sameQuiet(q, o.clip.quiet)) continue;
        overlays[i] = o.copyWith(clip: o.clip.copyWith(quiet: q));
        changed++;
      }
    }
    if (changed == 0) {
      return const PartResult(problem: 'it is already like that');
    }
    final len = partLengthLabel(part.lengthMs);
    _edit(
        (p) => p.copyWith(
            tracks: p.soundTracks, clips: clips, audio: audio, overlays: overlays),
        hint: action == PartAction.silence
            ? 'Silenced a part ($len)${_rowNames(p, part, action, rows)}'
            : 'Lowered a part ($len) to ${levelLabel(lv)}'
                '${_rowNames(p, part, action, rows)}');
    return PartResult(changed: changed);
  }

  /// The quiet range for [from]..[to] of a file. Where the part runs past
  /// the item's own edge ([fromEdge] / [toEdge]) the range is made a
  /// little longer than what the item plays, so that its fade lies outside
  /// the item: a part that covers a cut must not let 40 ms of sound
  /// through on each side of the cut.
  static QuietRange _quietOver(int from, int to, double level,
          {required bool fromEdge, required bool toEdge}) =>
      QuietRange(fromEdge ? from - 2 * kQuietFadeMs : from,
          toEdge ? to + 2 * kQuietFadeMs : to, level);

  static bool _sameQuiet(List<QuietRange> a, List<QuietRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// "Remove" in an item's "Quiet parts" list: the sound of [itemId] (a
  /// main-track clip, a sound or an overlay item) plays at its own level
  /// again between [fromMs] and [toMs] of its SOURCE file. One undo step.
  /// False when nothing was quiet there.
  bool removeQuiet(String itemId, int fromMs, int toMs) {
    final p = _project;
    List<QuietRange> cleared(List<QuietRange> q) =>
        addQuietRange(q, QuietRange(fromMs, toMs, 1));
    final before = p;
    _edit((p) {
      final ci = p.clips.indexWhere((c) => c.id == itemId);
      if (ci >= 0) {
        final c = p.clips[ci];
        final q = cleared(c.quiet);
        if (_sameQuiet(q, c.quiet)) return null;
        return p.copyWith(clips: [...p.clips]..[ci] = c.copyWith(quiet: q));
      }
      final ai = p.audio.indexWhere((a) => a.id == itemId);
      if (ai >= 0) {
        final a = p.audio[ai];
        final q = cleared(a.quiet);
        if (_sameQuiet(q, a.quiet)) return null;
        return p.copyWith(
            tracks: p.soundTracks,
            audio: [...p.audio]..[ai] = a.copyWith(quiet: q));
      }
      final oi = p.overlays.indexWhere((o) => o.id == itemId);
      if (oi >= 0) {
        final o = p.overlays[oi];
        final q = cleared(o.clip.quiet);
        if (_sameQuiet(q, o.clip.quiet)) return null;
        return p.copyWith(
            overlays: [...p.overlays]
              ..[oi] = o.copyWith(clip: o.clip.copyWith(quiet: q)));
      }
      return null;
    }, hint: 'Removed a quiet part');
    return !identical(before, _project);
  }

  /// "Cut out": removes [part] from EVERYTHING and closes the gap. The
  /// main track is cut with the editor's own operations (so titles,
  /// captions, markers and linked sound follow); music, other free sound
  /// and overlay items, which sit at fixed times, lose the same stretch
  /// and what comes after moves up. Every removed piece of a video file is
  /// written to the automatic-cut log (kind "part") so it can be put back.
  PartResult cutPart(TimelinePart part,
      {String by = 'app', DateTime? now}) {
    final before = _project;
    final problem = partActionProblem(before, part, PartAction.cutOut, null);
    if (problem != null) return PartResult(problem: problem);
    final total = before.durationMs;
    final cut = part.clampTo(total);
    final plan = clipsInPart(before, cut);
    final at = now ?? _clock();
    const min = ProjectEditor.minDurationMs;
    var done = 0;
    var removed = 0;
    transaction(() {
      final log = <AutoCut>[];
      final usedIds = {for (final c in before.autoCuts) c.id};
      // Back to front, so earlier clips keep their place meanwhile.
      for (final x in plan.reversed) {
        final c = x.clip;
        final start = before.clipStartMs(x.index);
        final end = before.clipEndMs(x.index);
        final head = x.fromMs - start, tail = end - x.toMs;
        final whole = head < min && tail < min;
        final was = _project;
        var srcA = c.inMs, srcB = c.outMs;
        if (whole) {
          removeClip(c.id);
        } else if (c.type == ClipType.photo) {
          trimClip(c.id, outMs: c.outMs - (x.toMs - x.fromMs));
        } else {
          // A piece shorter than the minimum would go with the cut:
          // stretch the cut over it so the log says what really went.
          srcA = head < min ? c.inMs : x.srcFrom;
          srcB = tail < min ? c.outMs : x.srcTo;
          if (srcB - srcA < 1) continue;
          removeSourceRanges(c.id, [(startMs: srcA, endMs: srcB)]);
        }
        if (identical(was, _project)) continue;
        done++;
        if (c.type == ClipType.video) {
          log.add(AutoCut(
              id: _freshIdNotIn(usedIds),
              kind: 'part',
              path: c.path,
              startMs: srcA,
              endMs: srcB,
              at: at,
              by: by));
        }
      }
      removed = total - _project.durationMs;
      if (done > 0 && removed > 0) {
        _edit((p) => _rippleFree(p, cut.startMs, cut.startMs + removed));
      }
      if (log.isNotEmpty) {
        setAutoCuts([..._project.autoCuts, ...log.reversed]);
      }
    }, label: 'Cut out a part (${partLengthLabel(cut.lengthMs)})');
    if (done == 0) return const PartResult(problem: 'nothing could be cut there');
    return PartResult(changed: done, removedMs: removed);
  }

  /// [p] with the stretch [a]..[b] taken out of everything that sits at a
  /// fixed time (sound that does not follow a clip, overlay items): what
  /// lies inside goes, what comes after moves up by the length.
  Project _rippleFree(Project p, int a, int b) {
    final len = b - a;
    if (len <= 0) return p;
    const min = ProjectEditor.minDurationMs;
    final usedAudio = {for (final x in p.audio) x.id};
    final audio = <AudioClip>[];
    for (final x in p.audio) {
      if (followsClip(x) || x.endMs <= a) {
        audio.add(x);
      } else if (x.startMs >= b) {
        audio.add(x.copyWith(startMs: x.startMs - len));
      } else {
        audio.addAll(_withoutStretch(x, a, b, usedAudio, closeGap: true)
            .where((y) => y.durationMs >= min));
      }
    }
    final usedOverlay = {
      for (final o in p.overlays) o.id,
      for (final c in p.clips) c.id,
    };
    final overlays = <OverlayClip>[];
    for (final o in p.overlays) {
      if (o.endMs <= a) {
        overlays.add(o);
      } else if (o.startMs >= b) {
        overlays.add(o.copyWith(startMs: o.startMs - len));
      } else {
        overlays.addAll(_overlayWithoutStretch(o, a, b, usedOverlay,
                closeGap: true)
            .where((y) => y.durationMs >= min));
      }
    }
    return p.copyWith(
        tracks: p.soundTracks,
        audio: audio,
        overlays: ProjectEditor._sortedOverlays(overlays));
  }

  /// The pieces of sound [x] that are left when [a]..[b] of the timeline
  /// goes: the part before and the part after (a new id), each with a
  /// short fade at the cut. With [closeGap] the part after starts at [a].
  List<AudioClip> _withoutStretch(AudioClip x, int a, int b, Set<String> used,
      {required bool closeGap}) {
    const min = ProjectEditor.minDurationMs;
    final out = <AudioClip>[];
    final speed = x.speed <= 0 || x.speed.isNaN ? 1.0 : x.speed;
    final headMs = a - x.startMs;
    final tailMs = x.endMs - b;
    final hasHead = headMs >= min, hasTail = tailMs >= min;
    if (x.looped) {
      if (hasHead) out.add(x.copyWith(loopMs: headMs));
      if (hasTail) {
        out.add(x.copyWith(
            id: hasHead ? _freshIdNotIn(used) : null,
            startMs: closeGap ? a : b,
            loopMs: tailMs));
      }
      return out;
    }
    if (hasHead) {
      final cutSrc = x.inMs + (headMs * speed).round();
      out.add(ProjectEditor._normalizeAudio(x.copyWith(
          outMs: cutSrc,
          fadeOutMs: hasTail ? kJoinFadeMs : math.min(x.fadeOutMs, headMs))));
    }
    if (hasTail) {
      final cutSrc = x.inMs + ((b - x.startMs) * speed).round();
      out.add(ProjectEditor._normalizeAudio(x.copyWith(
          id: hasHead ? _freshIdNotIn(used) : null,
          startMs: closeGap ? a : b,
          inMs: math.min(cutSrc, x.outMs - 1),
          fadeInMs: hasHead ? kJoinFadeMs : math.min(x.fadeInMs, tailMs))));
    }
    return out;
  }

  List<OverlayClip> _overlayWithoutStretch(
      OverlayClip o, int a, int b, Set<String> used,
      {required bool closeGap}) {
    const min = ProjectEditor.minDurationMs;
    final out = <OverlayClip>[];
    final c = o.clip;
    final photo = c.type == ClipType.photo;
    final headMs = a - o.startMs;
    final tailMs = o.endMs - b;
    final hasHead = headMs >= min, hasTail = tailMs >= min;
    if (hasHead) {
      out.add(ProjectEditor._normalizeOverlay(o.copyWith(
          fadeOutMs: hasTail ? 0 : o.fadeOutMs,
          clip: photo
              ? c.copyWith(outMs: headMs)
              : c.copyWith(outMs: c.sourceMsAt(headMs)))));
    }
    if (hasTail) {
      final clip = photo
          ? c.copyWith(outMs: tailMs)
          : c.copyWith(inMs: c.sourceMsAt(b - o.startMs));
      out.add(ProjectEditor._normalizeOverlay(o.copyWith(
          startMs: closeGap ? a : b,
          fadeInMs: hasHead ? 0 : o.fadeInMs,
          clip: hasHead ? clip.copyWith(id: _freshIdNotIn(used)) : clip)));
    }
    return out;
  }

  /// After a cut of kind "part" was put back ([restoreAutoCut]): the free
  /// sound and overlay items from [atMs] on move later by [grownMs] again,
  /// and a sound the cut had divided there becomes one piece again.
  void unripplePart(int atMs, int grownMs) {
    if (grownMs <= 0) return;
    _edit((p) {
      var any = false;
      final audio = <AudioClip>[];
      for (final x in p.audio) {
        if (followsClip(x) || x.startMs < atMs - 2) {
          audio.add(x);
          continue;
        }
        any = true;
        // The piece that ends right here and continues in this one: it
        // gets back what returned (a cut over several clips comes back
        // in several steps), and the two are one again once nothing is
        // missing between them.
        final hi = x.looped || x.startMs > atMs + 2
            ? -1
            : audio.indexWhere((h) =>
                !followsClip(h) &&
                !h.looped &&
                h.path == x.path &&
                h.trackId == x.trackId &&
                h.speed == x.speed &&
                (h.endMs - atMs).abs() <= 2 &&
                h.outMs <= x.inMs + 3);
        if (hi < 0) {
          audio.add(x.copyWith(startMs: x.startMs + grownMs));
          continue;
        }
        final h = audio[hi];
        final speed = h.speed <= 0 ? 1.0 : h.speed;
        final missing = x.inMs - h.outMs;
        final give = math.min(missing, (grownMs * speed).round());
        if (missing - give <= 3) {
          audio[hi] = ProjectEditor._normalizeAudio(
              h.copyWith(outMs: x.outMs, fadeOutMs: x.fadeOutMs));
        } else {
          audio[hi] =
              ProjectEditor._normalizeAudio(h.copyWith(outMs: h.outMs + give));
          audio.add(x.copyWith(startMs: x.startMs + grownMs));
        }
      }
      final overlays = [
        for (final o in p.overlays)
          if (o.startMs < atMs - 2)
            o
          else
            o.copyWith(startMs: o.startMs + grownMs),
      ];
      if (!any && !p.overlays.any((o) => o.startMs >= atMs - 2)) return null;
      return p.copyWith(tracks: p.soundTracks, audio: audio, overlays: overlays);
    });
  }

  /// "Delete and leave a gap": [part] goes from the ticked [rows] and
  /// nothing moves - sound that does not follow a clip, overlay items,
  /// titles and captions. The main track cannot have a gap and linked
  /// sound follows its clip, so those are left alone ([partRowProblem]
  /// says so).
  PartResult deletePart(TimelinePart part, {Set<String>? rows}) {
    final p = _project;
    final problem = partActionProblem(p, part, PartAction.deleteGap, rows);
    if (problem != null) return PartResult(problem: problem);
    final okRows = {
      for (final r in partRowsFor(p, part, PartAction.deleteGap, rows)) r.id
    };
    final a = part.startMs, b = part.endMs;
    const min = ProjectEditor.minDurationMs;
    var changed = 0;
    final usedAudio = {for (final x in p.audio) x.id};
    final audio = <AudioClip>[];
    for (final x in p.audio) {
      if (!okRows.contains(x.trackId) ||
          followsClip(x) ||
          !part.overlaps(x.startMs, x.endMs)) {
        audio.add(x);
        continue;
      }
      changed++;
      audio.addAll(_withoutStretch(x, a, b, usedAudio, closeGap: false)
          .where((y) => y.durationMs >= min));
    }
    var overlays = p.overlays;
    if (okRows.contains(kRowOverlay)) {
      final used = {
        for (final o in p.overlays) o.id,
        for (final c in p.clips) c.id,
      };
      final next = <OverlayClip>[];
      for (final o in p.overlays) {
        if (!part.overlaps(o.startMs, o.endMs)) {
          next.add(o);
          continue;
        }
        changed++;
        next.addAll(_overlayWithoutStretch(o, a, b, used, closeGap: false)
            .where((y) => y.durationMs >= min));
      }
      overlays = ProjectEditor._sortedOverlays(next);
    }
    var titles = p.titles;
    if (okRows.contains(kRowTitles)) {
      final used = {for (final t in p.titles) t.id};
      final next = <TitleOverlay>[];
      for (final t in p.titles) {
        if (!part.overlaps(t.startMs, t.endMs)) {
          next.add(t);
          continue;
        }
        changed++;
        final head = a - t.startMs, tail = t.endMs - b;
        if (head >= min) next.add(t.copyWith(endMs: a));
        if (tail >= min) {
          next.add(t.copyWith(
              id: head >= min ? _freshIdNotIn(used) : null, startMs: b));
        }
      }
      titles = next;
    }
    if (changed == 0) return const PartResult(problem: 'nothing to delete there');
    final names = _rowNames(p, part, PartAction.deleteGap, rows);
    _edit(
        (p) => p.copyWith(
            tracks: p.soundTracks, audio: audio, overlays: overlays, titles: titles),
        hint: 'Deleted a part (${partLengthLabel(part.lengthMs)})$names, '
            'leaving a gap');
    return PartResult(changed: changed);
  }

  /// The ids of the main-track clips that lie in [a]..[b] after the track
  /// was split at both ends (their middle is inside).
  List<String> _splitAround(int a, int b) {
    if (b < _project.durationMs) splitAt(b);
    if (a > 0) splitAt(a);
    final p = _project;
    return [
      for (var i = 0; i < p.clips.length; i++)
        if (((p.clipStartMs(i) + p.clipEndMs(i)) ~/ 2) >= a &&
            ((p.clipStartMs(i) + p.clipEndMs(i)) ~/ 2) < b)
          p.clips[i].id,
    ];
  }

  TimelinePart? _extentOf(List<String> clipIds) {
    final p = _project;
    int? from, to;
    for (var i = 0; i < p.clips.length; i++) {
      if (!clipIds.contains(p.clips[i].id)) continue;
      from ??= p.clipStartMs(i);
      to = p.clipEndMs(i);
    }
    return from == null || to == null ? null : TimelinePart(from, to);
  }

  /// "Speed" for [part]: the main track is split at the part's edges and
  /// the video clips in between play at [speed] (slow motion below 1).
  /// The clips' own sound and linked sound follow (the editor's rule);
  /// music and other free sound, overlays and everything later on the
  /// timeline keep their own time - the video after the part moves, they
  /// do not. [muteOwnSound] switches the sound of that part off: the
  /// clips are muted and linked sound is silenced there.
  PartResult speedPart(TimelinePart part, double speed,
      {bool muteOwnSound = false, Set<String>? rows}) {
    final before = _project;
    final problem = partActionProblem(before, part, PartAction.speed, rows);
    if (problem != null) return PartResult(problem: problem);
    if (speed.isNaN) return const PartResult(problem: 'that is not a speed');
    final s = speed
        .clamp(ProjectEditor.minSpeed, ProjectEditor.maxSpeed)
        .toDouble();
    final cut = part.clampTo(before.durationMs);
    // Nothing to do: say so before the track is split for nothing.
    final wouldChange = clipsInPart(before, cut).any((x) =>
        x.clip.type == ClipType.video &&
        (x.clip.speed != s ||
            (muteOwnSound && x.clip.hasAudio && !x.clip.muted)));
    if (!wouldChange) {
      return const PartResult(problem: 'it already plays at that speed');
    }
    var changed = 0;
    TimelinePart? after;
    transaction(() {
      final ids = _splitAround(cut.startMs, cut.endMs);
      final done = <String>[];
      for (final id in ids) {
        final c = _project.clips.where((c) => c.id == id).firstOrNull;
        if (c == null || c.type != ClipType.video) continue;
        final was = _project;
        setClipSpeed(id, s);
        if (muteOwnSound && c.hasAudio && !c.muted) setClipMuted(id, true);
        if (!identical(was, _project)) changed++;
        done.add(id);
      }
      if (muteOwnSound && done.isNotEmpty) {
        _edit((p) {
          var any = false;
          final audio = [
            for (final a in p.audio)
              if (followsClip(a) && done.contains(a.sourceClipId))
                () {
                  final q = addQuietRange(a.quiet, QuietRange(a.inMs, a.outMs));
                  if (_sameQuiet(q, a.quiet)) return a;
                  any = true;
                  return a.copyWith(quiet: q);
                }()
              else
                a,
          ];
          return any ? p.copyWith(tracks: p.soundTracks, audio: audio) : null;
        });
      }
      after = _extentOf(done);
    },
        label: 'Speed ${_speedLabel(s)} on a part '
            '(${partLengthLabel(cut.lengthMs)})'
            '${muteOwnSound ? ', its sound off' : ''}');
    if (changed == 0) {
      return const PartResult(problem: 'it already plays at that speed');
    }
    return PartResult(changed: changed, part: after);
  }

  static String _speedLabel(double s) {
    var t = s.toStringAsFixed(2);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$t×';
  }

  /// "Clean up sound here": clean-up ([Clip.denoise]) for [part] only, on
  /// the ticked [rows]. DECISION: by splitting, not by a per-range sound
  /// cache - the main track is split at the part's edges (linked sound
  /// gets its pieces by the follow rule) and free sound on a ticked track
  /// is divided there too; the pieces in between get clean-up. The
  /// processed-sound cache is keyed by file and settings, so the pieces
  /// share one rendered file with every other cleaned piece of that file.
  PartResult cleanPart(TimelinePart part, {Set<String>? rows}) {
    final before = _project;
    final problem = partActionProblem(before, part, PartAction.clean, rows);
    if (problem != null) return PartResult(problem: problem);
    final okRows = {
      for (final r in partRowsFor(before, part, PartAction.clean, rows)) r.id
    };
    final cut = part.clampTo(math.max(before.durationMs, part.endMs));
    final a = cut.startMs, b = cut.endMs;
    // Nothing to do: say so before anything is split for nothing.
    final wouldChange = (okRows.contains(kRowVideo) &&
            clipsInPart(before, part).any((x) =>
                x.clip.type == ClipType.video &&
                x.clip.hasAudio &&
                !x.clip.muted &&
                !x.clip.denoise)) ||
        before.audio.any((x) =>
            okRows.contains(x.trackId) &&
            !x.looped &&
            !x.denoise &&
            part.overlaps(x.startMs, x.endMs));
    if (!wouldChange) {
      return const PartResult(problem: 'the sound there is already cleaned');
    }
    var changed = 0;
    transaction(() {
      // The main track only has to be split when something that follows
      // it is cleaned: the video's own sound, or linked sound on a row.
      final linkedWanted = before.audio.any((x) =>
          followsClip(x) &&
          okRows.contains(x.trackId) &&
          part.overlaps(x.startMs, x.endMs));
      if (okRows.contains(kRowVideo) || linkedWanted) {
        final ids = _splitAround(math.min(a, before.durationMs),
            math.min(b, before.durationMs));
        for (final id in ids) {
          final c = _project.clips.where((c) => c.id == id).firstOrNull;
          if (c == null || c.type != ClipType.video) continue;
          if (okRows.contains(kRowVideo) && c.hasAudio && !c.muted && !c.denoise) {
            setClipDenoise(id, true);
            changed++;
          }
          for (final x in [..._project.audio]) {
            if (!followsClip(x) || x.sourceClipId != id) continue;
            if (!okRows.contains(x.trackId) || x.denoise) continue;
            setAudioDenoise(x.id, true);
            changed++;
          }
        }
      }
      // Free sound: divided at the edges, the middle cleaned.
      _edit((p) {
        var any = false;
        final used = {for (final x in p.audio) x.id};
        final audio = <AudioClip>[];
        for (final x in p.audio) {
          if (followsClip(x) ||
              x.looped ||
              !okRows.contains(x.trackId) ||
              !part.overlaps(x.startMs, x.endMs)) {
            audio.add(x);
            continue;
          }
          final pieces = _dividedAt(x, a, b, used);
          for (final piece in pieces) {
            final mid = (piece.startMs + piece.endMs) ~/ 2;
            if (mid >= a && mid < b && !piece.denoise) {
              audio.add(piece.copyWith(denoise: true));
              any = true;
              changed++;
            } else {
              audio.add(piece);
            }
          }
        }
        return any ? p.copyWith(tracks: p.soundTracks, audio: audio) : null;
      });
    }, label: 'Cleaned up sound on a part (${partLengthLabel(cut.lengthMs)})');
    if (changed == 0) {
      return const PartResult(problem: 'the sound there is already cleaned');
    }
    return PartResult(changed: changed);
  }

  /// Sound [x] divided at timeline times [a] and [b] where they fall
  /// inside it (no piece shorter than the minimum): one to three pieces
  /// that together play exactly what [x] played; the first keeps the id.
  List<AudioClip> _dividedAt(AudioClip x, int a, int b, Set<String> used) {
    const min = ProjectEditor.minDurationMs;
    final speed = x.speed <= 0 || x.speed.isNaN ? 1.0 : x.speed;
    final cuts = [
      for (final t in [a, b])
        if (t - x.startMs >= min && x.endMs - t >= min) t,
    ];
    if (cuts.length == 2 && cuts[1] - cuts[0] < min) cuts.removeLast();
    if (cuts.isEmpty) return [x];
    final out = <AudioClip>[];
    var start = x.startMs;
    var inMs = x.inMs;
    for (var i = 0; i <= cuts.length; i++) {
      final end = i < cuts.length ? cuts[i] : x.endMs;
      final outMs = i < cuts.length
          ? x.inMs + ((end - x.startMs) * speed).round()
          : x.outMs;
      out.add(x.copyWith(
        id: i == 0 ? null : _freshIdNotIn(used),
        startMs: start,
        inMs: inMs,
        outMs: outMs,
        fadeInMs: i == 0 ? math.min(x.fadeInMs, end - start) : 0,
        fadeOutMs: i == cuts.length ? math.min(x.fadeOutMs, end - start) : 0,
      ));
      start = end;
      inMs = outMs;
    }
    return out;
  }

  /// "Duplicate the part": a copy of the video in [part] right after it
  /// (the main track is split at the edges; linked voices follow by the
  /// rule for clips of the same file).
  PartResult duplicatePart(TimelinePart part) {
    final before = _project;
    final problem = partActionProblem(before, part, PartAction.duplicate, null);
    if (problem != null) return PartResult(problem: problem);
    final cut = part.clampTo(before.durationMs);
    var changed = 0;
    TimelinePart? after;
    transaction(() {
      final ids = _splitAround(cut.startMs, cut.endMs);
      if (ids.isEmpty) return;
      final p = _project;
      var at = p.clips.indexWhere((c) => c.id == ids.last) + 1;
      final copies = <String>[];
      for (final id in ids) {
        final c = p.clips.firstWhere((c) => c.id == id);
        final copy = c.copyWith(
            id: _freshId(_project),
            transition: copies.isEmpty ? TransitionType.none : c.transition);
        addClip(copy, index: at++);
        copies.add(copy.id);
        changed++;
      }
      after = _extentOf(copies);
    }, label: 'Duplicated a part (${partLengthLabel(cut.lengthMs)})');
    if (changed == 0) return const PartResult(problem: 'nothing to copy there');
    return PartResult(changed: changed, part: after);
  }

  /// "Only when speaking" for speech track [trackId] ([SoundTrack.gate],
  /// [SoundTrack.gateLevel]); null leaves a value as it is. One undo step.
  void setOnlyWhenSpeaking(String trackId, {bool? on, double? level}) {
    final t = _project.trackById(trackId);
    if (t == null || trackId == SoundTrack.videoId) return;
    final lv = level == null || level.isNaN
        ? null
        : level.clamp(0.0, 1.0).toDouble();
    final turnsOn = on ?? t.gate;
    _editTrack(trackId, (t) => t.copyWith(gate: on, gateLevel: lv),
        hint: on == null
            ? 'Only when speaking: ${levelLabel(lv ?? t.gateLevel)} between '
                'turns on ${t.name}'
            : 'Only when speaking ${turnsOn ? 'on' : 'off'} for ${t.name}');
  }
}
