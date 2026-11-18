// Gentle by default: which of the fillers that were found are really cut.
// Pure Dart.
//
// Owner's worry (1.11): removing every "um" makes a video jumpy,
// especially when the speaker moves. So "Remove filler words" has a
// STRENGTH, guard rails at every strength, and a JUMP CHECK:
//
//                         Light (default)   Normal      Strong
//  shortest cut           350 ms            200 ms      80 ms
//  must stand alone       yes: a pause of   no          no
//  between pauses         >= 120 ms on
//                         both sides
//  closest two cuts       2.5 s             1.5 s       0.7 s
//  most cuts in a minute  4                 8           no limit
//  shortest piece left    0.6 s             0.6 s       0.6 s
//  picture would jump     not cut           not cut     cut anyway
//  (score >= 0.5)
//  slight jump            cut with a short dissolve (150 ms), every
//  (score >= 0.2)         strength
//
// "Cut length" is the whole stretch removed: the filler and the pause
// around it that goes with it. When two cuts are too close, or a minute is
// full, the LONGER cut wins (it saves more and is the clearer filler).
// The jump score is 0..1 (media/jump_check.dart): how much the picture
// differs between the frame before the cut and the frame after it; null =
// not measured (then nothing is skipped or smoothed for it).

import '../model/project.dart';
import 'fillers.dart';

enum CutStrength {
  light,
  normal,
  strong;

  static CutStrength parse(Object? raw) => switch ('$raw'.toLowerCase()) {
        'normal' => CutStrength.normal,
        'strong' => CutStrength.strong,
        _ => CutStrength.light,
      };

  String get label => switch (this) {
        CutStrength.light => 'Light',
        CutStrength.normal => 'Normal',
        CutStrength.strong => 'Strong',
      };
}

/// A picture difference from which a cut gets a short dissolve.
const double kJumpSlight = 0.2;

/// A picture difference from which a cut is a visible jump.
const double kJumpy = 0.5;

/// Length of the dissolve put on a slightly jumpy cut (4-5 frames at
/// 30 fps; the shortest the transition mechanism takes is 100 ms).
const int kSmoothMs = 150;

class CutRules {
  const CutRules({
    required this.minCutMs,
    required this.standAloneMs,
    required this.minDistanceMs,
    required this.maxPerMinute,
    this.minPieceMs = 600,
    this.skipJumpy = true,
    this.smooth = true,
  });

  /// The rules of a strength.
  factory CutRules.of(CutStrength s) => switch (s) {
        CutStrength.light => const CutRules(
            minCutMs: 350, standAloneMs: 120, minDistanceMs: 2500, maxPerMinute: 4),
        CutStrength.normal => const CutRules(
            minCutMs: 200, standAloneMs: 0, minDistanceMs: 1500, maxPerMinute: 8),
        CutStrength.strong => const CutRules(
            minCutMs: 80,
            standAloneMs: 0,
            minDistanceMs: 700,
            maxPerMinute: 0,
            skipJumpy: false),
      };

  final int minCutMs;

  /// The pause needed on BOTH sides of the filler (0: none).
  final int standAloneMs;

  /// Closest two cuts may be on the timeline.
  final int minDistanceMs;

  /// Most cuts in any minute of the video (0: no limit).
  final int maxPerMinute;

  /// No piece of a clip shorter than this is left.
  final int minPieceMs;

  /// Cuts whose picture would jump are left in.
  final bool skipJumpy;

  /// Slightly jumpy cuts get a short dissolve.
  final bool smooth;

  CutRules copyWith(
          {int? minCutMs,
          int? minDistanceMs,
          int? maxPerMinute,
          int? minPieceMs,
          bool? skipJumpy}) =>
      CutRules(
        minCutMs: minCutMs ?? this.minCutMs,
        standAloneMs: standAloneMs,
        minDistanceMs: minDistanceMs ?? this.minDistanceMs,
        maxPerMinute: maxPerMinute ?? this.maxPerMinute,
        minPieceMs: minPieceMs ?? this.minPieceMs,
        skipJumpy: skipJumpy ?? this.skipJumpy,
        smooth: smooth,
      );
}

enum CutDecision {
  /// It is cut.
  cut,

  /// Too short for this strength.
  tooShort,

  /// Glued inside fast speech (no pause around it).
  inSpeech,

  /// Another cut is too close.
  tooClose,

  /// That minute already has its number of cuts.
  minuteFull,

  /// The picture would jump.
  jumpy,

  /// It would leave a piece of the clip too short.
  shortPiece,

  /// Someone else is talking over it.
  underSpeech,
}

class PlannedCut {
  PlannedCut(this.hit, this.decision, {this.jump, this.smooth = false});
  final FillerHit hit;
  final CutDecision decision;

  /// 0..1; null when not measured.
  final double? jump;

  /// Gets a short dissolve.
  final bool smooth;
  bool get isCut => decision == CutDecision.cut;

  /// "smooth", "slight", "jumpy" ('' when not measured).
  String get jumpRating => jumpRatingOf(jump);
}

String jumpRatingOf(double? jump) => jump == null
    ? ''
    : jump >= kJumpy
        ? 'jumpy'
        : jump >= kJumpSlight
            ? 'slight'
            : 'smooth';

/// Decides for every one of [hits] (timeline order) whether it is cut
/// under [rules]. [jumps] holds the jump score of a hit by its index in
/// [hits] (missing: not measured). The result is in the order of [hits].
List<PlannedCut> planFillerCuts(Project p, List<FillerHit> hits, CutRules rules,
    {Map<int, double> jumps = const {}}) {
  final decision = List<CutDecision?>.filled(hits.length, null);
  final clipById = {for (final c in p.clips) c.id: c};
  final candidates = <int>[];
  for (var i = 0; i < hits.length; i++) {
    final h = hits[i];
    final clip = clipById[h.clipId];
    final jump = jumps[i];
    if (h.overlapsSpeech) {
      decision[i] = CutDecision.underSpeech;
    } else if (h.cutMs < rules.minCutMs) {
      decision[i] = CutDecision.tooShort;
    } else if (rules.standAloneMs > 0 &&
        (h.gapBeforeMs < rules.standAloneMs || h.gapAfterMs < rules.standAloneMs)) {
      decision[i] = CutDecision.inSpeech;
    } else if (clip != null &&
        ((h.cutStartMs > clip.inMs && h.cutStartMs - clip.inMs < rules.minPieceMs) ||
            (h.cutEndMs < clip.outMs && clip.outMs - h.cutEndMs < rules.minPieceMs))) {
      decision[i] = CutDecision.shortPiece;
    } else if (rules.skipJumpy && jump != null && jump >= kJumpy) {
      decision[i] = CutDecision.jumpy;
    } else {
      candidates.add(i);
    }
  }
  // Longest first; a cut is taken when no taken cut is too close and its
  // minute has room.
  candidates.sort((a, b) {
    final d = hits[b].cutMs.compareTo(hits[a].cutMs);
    return d != 0 ? d : a.compareTo(b);
  });
  final taken = <int>[];
  for (final i in candidates) {
    final t = hits[i].startMs;
    var close = false;
    final near = <int>[t];
    for (final k in taken) {
      final d = (hits[k].startMs - t).abs();
      if (d < rules.minDistanceMs) close = true;
      if (d < 60000) near.add(hits[k].startMs);
    }
    // The fullest minute this cut would be part of (it included).
    var inMinute = 0;
    for (final from in near) {
      if (from > t) continue;
      final n = near.where((x) => x >= from && x < from + 60000).length;
      if (n > inMinute) inMinute = n;
    }
    if (close) {
      decision[i] = CutDecision.tooClose;
    } else if (rules.maxPerMinute > 0 && inMinute > rules.maxPerMinute) {
      decision[i] = CutDecision.minuteFull;
    } else {
      decision[i] = CutDecision.cut;
      taken.add(i);
    }
  }
  return [
    for (var i = 0; i < hits.length; i++)
      PlannedCut(hits[i], decision[i]!,
          jump: jumps[i],
          smooth: decision[i] == CutDecision.cut &&
              rules.smooth &&
              jumps[i] != null &&
              jumps[i]! >= kJumpSlight),
  ];
}

/// The numbers of a plan, for the header and for Claude.
class CutSummary {
  CutSummary(List<PlannedCut> plan, int videoMs)
      : found = plan.length,
        cuts = plan.where((c) => c.isCut).length,
        savedMs = plan.where((c) => c.isCut).fold(0, (n, c) => n + c.hit.cutMs),
        skippedTooClose = plan
            .where((c) =>
                c.decision == CutDecision.tooClose ||
                c.decision == CutDecision.minuteFull)
            .length,
        skippedJumpy = plan.where((c) => c.decision == CutDecision.jumpy).length,
        skippedSmall = plan
            .where((c) =>
                c.decision == CutDecision.tooShort ||
                c.decision == CutDecision.inSpeech ||
                c.decision == CutDecision.shortPiece)
            .length,
        skippedUnderSpeech =
            plan.where((c) => c.decision == CutDecision.underSpeech).length,
        smoothed = plan.where((c) => c.isCut && c.smooth).length,
        cutsPerMinute = videoMs <= 0
            ? 0
            : plan.where((c) => c.isCut).length / (videoMs / 60000);
  final int found;
  final int cuts;
  final int savedMs;
  final int skippedTooClose;
  final int skippedJumpy;
  final int skippedSmall;
  final int skippedUnderSpeech;
  final int smoothed;
  final double cutsPerMinute;

  /// "about 3" / "less than 1".
  String get perMinuteText => cuts == 0
      ? '0'
      : cutsPerMinute < 0.75
          ? 'less than 1'
          : 'about ${cutsPerMinute.round()}';
}

/// Cuts per minute at or under this are easy on the eye for a talking
/// head; above it Claude is told to hold back (fillers and silences
/// together).
const double kCutBudgetPerMinute = 6;
