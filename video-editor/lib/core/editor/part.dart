// Pure Dart: "a part of the timeline" (1.17) - a stretch of time the user
// selected, the rows it applies to, and the one place that says what an
// action on the part can do on each row, and why not.
//
// The part itself is NOT in the project file and not an undo step: it is
// a selection, kept by the editor session (ui/editor/session.dart) or
// passed by Claude's tools as from_ms / to_ms. The edits are in
// part_edits.dart.

import 'dart:math' as math;

import '../model/project.dart';

/// A stretch of the timeline, [startMs] inclusive to [endMs] exclusive.
class TimelinePart {
  const TimelinePart(this.startMs, this.endMs);

  /// The part between two times, whichever comes first.
  factory TimelinePart.between(int a, int b) =>
      a <= b ? TimelinePart(a, b) : TimelinePart(b, a);

  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;
  bool get isEmpty => endMs <= startMs;

  bool contains(int ms) => ms >= startMs && ms < endMs;

  /// True when [from]..[to] and this part share some time.
  bool overlaps(int from, int to) => from < endMs && to > startMs;

  /// The part kept inside 0..[totalMs].
  TimelinePart clampTo(int totalMs) {
    final a = startMs.clamp(0, math.max(0, totalMs)).toInt();
    final b = endMs.clamp(0, math.max(0, totalMs)).toInt();
    return TimelinePart(a, b < a ? a : b);
  }

  TimelinePart copyWith({int? startMs, int? endMs}) =>
      TimelinePart(startMs ?? this.startMs, endMs ?? this.endMs);

  @override
  bool operator ==(Object other) =>
      other is TimelinePart &&
      other.startMs == startMs &&
      other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'TimelinePart($startMs..$endMs)';
}

/// The shortest part an action works on.
const int kMinPartMs = 100;

/// Row ids: the main track with the video's own sound, the overlay row,
/// the titles and captions row. A sound track's row id is the track's id.
const String kRowVideo = SoundTrack.videoId;
const String kRowOverlay = 'overlay';
const String kRowTitles = 'titles';

enum PartRowKind { video, overlay, sound, titles }

/// One row of the timeline, as the tick boxes list it.
class PartRow {
  const PartRow(this.id, this.name, this.kind);
  final String id;
  final String name;
  final PartRowKind kind;

  @override
  String toString() => 'PartRow($id)';
}

/// The rows of [p], top to bottom as the timeline shows them: the overlay
/// row (when the project has overlay items), the video, every sound track,
/// titles and captions (when there are any).
List<PartRow> partRowsOf(Project p) => [
      if (p.overlays.isNotEmpty)
        const PartRow(kRowOverlay, 'Overlay', PartRowKind.overlay),
      if (p.clips.isNotEmpty)
        const PartRow(kRowVideo, 'Video', PartRowKind.video),
      for (final t in p.soundTracks) PartRow(t.id, t.name, PartRowKind.sound),
      if (p.titles.isNotEmpty)
        const PartRow(kRowTitles, 'Titles and captions', PartRowKind.titles),
    ];

/// True when row [id] is ticked: [rows] null means every row.
bool rowTicked(Set<String>? rows, String id) =>
    rows == null || rows.contains(id);

/// True when every row of [p] is ticked.
bool allRowsTicked(Project p, Set<String>? rows) =>
    rows == null || partRowsOf(p).every((r) => rows.contains(r.id));

/// What can be done with a part.
enum PartAction {
  cutOut,
  deleteGap,
  silence,
  lower,
  speed,
  clean,
  makeShort,
  duplicate,
  addMarker,
  addTitle,
}

/// True for the actions that work on the ticked rows (the others work on
/// the video as a whole).
bool partActionUsesRows(PartAction a) => switch (a) {
      PartAction.cutOut ||
      PartAction.deleteGap ||
      PartAction.silence ||
      PartAction.lower ||
      PartAction.speed ||
      PartAction.clean =>
        true,
      _ => false,
    };

/// A main-track clip inside a part: where the part lies on the timeline
/// within the clip ([fromMs]..[toMs]) and in the clip's SOURCE file.
typedef ClipInPart = ({
  int index,
  Clip clip,
  int fromMs,
  int toMs,
  int srcFrom,
  int srcTo,
});

/// The main-track clips [part] touches, in track order.
List<ClipInPart> clipsInPart(Project p, TimelinePart part) {
  final out = <ClipInPart>[];
  for (var i = 0; i < p.clips.length; i++) {
    final c = p.clips[i];
    final s = p.clipStartMs(i), e = p.clipEndMs(i);
    final from = math.max(part.startMs, s), to = math.min(part.endMs, e);
    if (to <= from) continue;
    out.add((
      index: i,
      clip: c,
      fromMs: from,
      toMs: to,
      srcFrom: c.sourceMsAt(from - s),
      srcTo: c.sourceMsAt(to - s),
    ));
  }
  return out;
}

/// The part of [a]'s FILE that plays during [part]; null when none does.
/// For a looped sound: the stretch of the pass that plays when the part
/// starts (a quiet range on it comes back with every repeat).
({int from, int to})? soundSourceRange(AudioClip a, TimelinePart part) {
  final from = math.max(part.startMs, a.startMs);
  final to = math.min(part.endMs, a.endMs);
  if (to <= from) return null;
  final speed = a.speed <= 0 || a.speed.isNaN ? 1.0 : a.speed;
  var rel = from - a.startMs;
  var len = to - from;
  if (a.looped) {
    final step = a.passMs - a.loopCrossfadeMs;
    if (step <= 0) return null;
    rel = rel % step;
    if (len > a.passMs - rel) len = a.passMs - rel;
  }
  final srcFrom = a.inMs + (rel * speed).round();
  var srcTo = a.inMs + ((rel + len) * speed).round();
  if (srcTo > a.outMs) srcTo = a.outMs;
  if (srcTo <= srcFrom) return null;
  return (from: srcFrom, to: srcTo);
}

/// The part of overlay item [o]'s file that plays during [part].
({int from, int to})? overlaySourceRange(OverlayClip o, TimelinePart part) {
  final from = math.max(part.startMs, o.startMs);
  final to = math.min(part.endMs, o.endMs);
  if (to <= from || o.clip.type == ClipType.photo) return null;
  final a = o.clip.sourceMsAt(from - o.startMs);
  final b = o.clip.sourceMsAt(to - o.startMs);
  return b > a ? (from: a, to: b) : null;
}

/// True for a sound that follows a video clip (a separated sound or a
/// voice recorded separately, while linked): it cannot be cut or moved on
/// its own.
bool followsClip(AudioClip a) => a.belongsToClip && a.linked;

/// Why [action] can do nothing on [row] for [part]: a short lower-case
/// reason without a full stop (shown next to the row's greyed tick box);
/// null when it can.
String? partRowProblem(
    Project p, TimelinePart part, PartAction action, PartRow row) {
  if (!partActionUsesRows(action)) return null;
  final inPart = clipsInPart(p, part);
  final sounds = row.kind != PartRowKind.sound
      ? const <AudioClip>[]
      : [
          for (final a in p.audio)
            if (a.trackId == row.id && part.overlaps(a.startMs, a.endMs)) a,
        ];
  final overlays = row.kind != PartRowKind.overlay
      ? const <OverlayClip>[]
      : [
          for (final o in p.overlays)
            if (part.overlaps(o.startMs, o.endMs)) o,
        ];
  final titles = row.kind != PartRowKind.titles
      ? 0
      : p.titles.where((t) => part.overlaps(t.startMs, t.endMs)).length;
  const nothing = 'nothing on this row here';
  switch (action) {
    case PartAction.cutOut:
      return null;
    case PartAction.deleteGap:
      switch (row.kind) {
        case PartRowKind.video:
          return 'the video row cannot have a gap: use Cut out';
        case PartRowKind.sound:
          if (sounds.isEmpty) return nothing;
          return sounds.every(followsClip)
              ? 'this sound follows its video clip: use Silence'
              : null;
        case PartRowKind.overlay:
          return overlays.isEmpty ? nothing : null;
        case PartRowKind.titles:
          return titles == 0 ? nothing : null;
      }
    case PartAction.silence:
    case PartAction.lower:
      switch (row.kind) {
        case PartRowKind.video:
          final videos = inPart.where(
              (x) => x.clip.type == ClipType.video && x.clip.hasAudio);
          if (videos.isEmpty) return 'no video with sound here';
          return videos.every((x) => x.clip.muted)
              ? "the video's own sound is switched off here"
              : null;
        case PartRowKind.sound:
          return sounds.isEmpty ? nothing : null;
        case PartRowKind.overlay:
          return overlays.any((o) => o.audible)
              ? null
              : 'no overlay with sound here';
        case PartRowKind.titles:
          return 'titles have no sound';
      }
    case PartAction.speed:
      switch (row.kind) {
        case PartRowKind.video:
          return inPart.any((x) => x.clip.type == ClipType.video)
              ? null
              : 'no video clip here (photos have no speed)';
        case PartRowKind.sound:
          return sounds.isNotEmpty && sounds.every(followsClip)
              ? 'follows the video by itself'
              : 'music and other sound keep their speed';
        case PartRowKind.overlay:
          return 'overlays keep their speed';
        case PartRowKind.titles:
          return 'titles stay on their picture';
      }
    case PartAction.clean:
      switch (row.kind) {
        case PartRowKind.video:
          final videos = inPart.where(
              (x) => x.clip.type == ClipType.video && x.clip.hasAudio);
          if (videos.isEmpty) return 'no video with sound here';
          return videos.every((x) => x.clip.muted)
              ? "the video's own sound is switched off here"
              : null;
        case PartRowKind.sound:
          if (sounds.isEmpty) return nothing;
          return sounds.every((a) => a.looped)
              ? 'a looped sound cannot be cleaned in part'
              : null;
        case PartRowKind.overlay:
          return 'not for overlays';
        case PartRowKind.titles:
          return 'titles have no sound';
      }
    case PartAction.makeShort:
    case PartAction.duplicate:
    case PartAction.addMarker:
    case PartAction.addTitle:
      return null;
  }
}

/// The rows [action] would change: ticked in [rows] and without a
/// [partRowProblem].
List<PartRow> partRowsFor(
        Project p, TimelinePart part, PartAction action, Set<String>? rows) =>
    [
      for (final r in partRowsOf(p))
        if (rowTicked(rows, r.id) &&
            partRowProblem(p, part, action, r) == null)
          r,
    ];

/// Why [action] cannot be done for [part] with the ticked [rows]: a short
/// lower-case reason without a full stop; null when it can.
String? partActionProblem(
    Project p, TimelinePart? part, PartAction action, Set<String>? rows) {
  if (p.clips.isEmpty) return 'add a video first';
  if (part == null || part.isEmpty) return 'select a part first';
  if (part.lengthMs < kMinPartMs) return 'the part is too short';
  final total = p.durationMs;
  final inVideo = part.clampTo(total);
  switch (action) {
    case PartAction.cutOut:
      if (inVideo.lengthMs < kMinPartMs) return 'the part is after the video';
      if (inVideo.startMs < kMinPartMs && total - inVideo.endMs < kMinPartMs) {
        return 'that would remove the whole video';
      }
      if (!allRowsTicked(p, rows)) {
        return 'tick every row: lips and voice would no longer match '
            'afterwards';
      }
      return null;
    case PartAction.deleteGap:
    case PartAction.silence:
    case PartAction.lower:
    case PartAction.clean:
      final ticked = [
        for (final r in partRowsOf(p))
          if (rowTicked(rows, r.id)) r,
      ];
      if (ticked.isEmpty) return 'tick a row first';
      if (partRowsFor(p, part, action, rows).isNotEmpty) return null;
      if (ticked.length == 1) {
        return partRowProblem(p, part, action, ticked.single);
      }
      return switch (action) {
        PartAction.deleteGap => 'nothing on the ticked rows can leave a gap',
        PartAction.clean => 'no sound to clean on the ticked rows here',
        _ => 'no sound on the ticked rows here',
      };
    case PartAction.speed:
      if (!rowTicked(rows, kRowVideo)) return 'tick the video row';
      return partRowProblem(p, part, action,
          const PartRow(kRowVideo, 'Video', PartRowKind.video));
    case PartAction.duplicate:
    case PartAction.makeShort:
      return inVideo.lengthMs < kMinPartMs ? 'the part is after the video' : null;
    case PartAction.addMarker:
      return part.startMs > total ? 'the part is after the video' : null;
    case PartAction.addTitle:
      return null;
  }
}

/// "2.3 s", "1:05.2": the length of a part for History and messages.
String partLengthLabel(int ms) {
  if (ms < 0) ms = 0;
  final tenths = (ms / 100).round();
  if (tenths < 600) return '${tenths ~/ 10}.${tenths % 10} s';
  final s = tenths ~/ 10;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}.${tenths % 10}';
}

/// "-12 dB" for a linear [level]; "silence" for 0.
String levelLabel(double level) {
  if (level <= 0.0005) return 'silence';
  final db = 20 * math.log(level) / math.ln10;
  final r = db.round();
  return '${r > 0 ? '+' : (r < 0 ? '−' : '')}${r.abs()} dB';
}

/// The linear factor for [db] decibels (-6 -> 0.501).
double levelFromDb(num db) => math.pow(10, db / 20).toDouble();

// Quick selections -----------------------------------------------------------

/// The time main-track clip [clipId] takes on the timeline.
TimelinePart? partOfClip(Project p, String clipId) {
  final i = p.clips.indexWhere((c) => c.id == clipId);
  if (i < 0) return null;
  return TimelinePart(p.clipStartMs(i), p.clipEndMs(i));
}

/// From the marker before [atMs] (or the start) to the marker after it
/// (or the end of the video); null without markers.
TimelinePart? partBetweenMarkers(Project p, int atMs) {
  if (p.markers.isEmpty) return null;
  var from = 0;
  var to = p.durationMs;
  for (final m in p.markers) {
    if (m.ms <= atMs && m.ms > from) from = m.ms;
  }
  for (final m in p.markers) {
    if (m.ms > atMs && m.ms < to) to = m.ms;
  }
  return to > from ? TimelinePart(from, to) : null;
}

/// The stretch of [stretches] (sorted, timeline time) that [atMs] is in;
/// null when it is in none.
TimelinePart? stretchAt(List<({int startMs, int endMs})> stretches, int atMs) {
  for (final r in stretches) {
    if (atMs >= r.startMs && atMs < r.endMs) {
      return TimelinePart(r.startMs, r.endMs);
    }
  }
  return null;
}

/// "The pause here": the quiet stretch around [atMs] between two of
/// [stretches] (a speaker's talk, sorted, timeline time), kept inside
/// 0..[totalMs]; null when [atMs] is inside talk.
TimelinePart? pauseAt(
    List<({int startMs, int endMs})> stretches, int atMs, int totalMs) {
  var from = 0;
  var to = totalMs;
  for (final r in stretches) {
    if (atMs >= r.startMs && atMs < r.endMs) return null;
    if (r.endMs <= atMs && r.endMs > from) from = r.endMs;
    if (r.startMs > atMs && r.startMs < to) to = r.startMs;
  }
  return to - from >= kMinPartMs ? TimelinePart(from, to) : null;
}
