// Pure Dart: what "Remove silences" listens to for a clip, and the search
// itself.
//
// A clip normally is judged by its own sound. A clip with a VOICE RECORDED
// SEPARATELY lined up with it (1.10, [AudioClip.syncOffsetMs]) is judged by
// that voice instead - by every such voice when there are several speakers
// - and by its own sound too only while that is not muted. A moment counts
// as silent when ALL the sounds listened to are silent there (which is
// what "the mix is silent" means, without having to mix); where a voice
// file has no sound for the clip it counts as silent.

import 'dart:async';

import '../core/editor/sound_tracks.dart' show linkedVoicesOf;
import '../core/model/project.dart';
import 'media_api.dart';
import 'media_jobs.dart';

/// One sound "Remove silences" listens to for a clip.
class SilenceSource {
  const SilenceSource({
    required this.path,
    this.audioTrack = 0,
    this.channel = AudioChannel.both,
    this.offsetMs = 0,
    this.sourceDurationMs = 0,
    this.isVoice = false,
  });
  final String path;
  final int audioTrack;
  final AudioChannel channel;

  /// time in this file = time in the clip's file + offset (0 for the
  /// clip's own sound).
  final int offsetMs;

  /// Length of the file (0: unknown).
  final int sourceDurationMs;

  /// A voice recorded separately (not the clip's own sound).
  final bool isVoice;
}

/// The sounds "Remove silences" listens to for [clip] of [p] (see the top
/// of this file). Empty when there is nothing to listen to.
List<SilenceSource> silenceSourcesOf(Project p, Clip clip) {
  if (clip.type != ClipType.video) return const [];
  final seen = <String>{};
  final voices = <SilenceSource>[];
  for (final a in linkedVoicesOf(p, clip.id)) {
    final track = p.trackById(a.trackId);
    // A voice nobody hears does not keep a stretch.
    if (track != null && p.trackGain(track) <= 0) continue;
    if (a.volume <= 0) continue;
    final s = a.soundClip;
    if (!seen.add('${a.path}|${a.syncOffsetMs}|${s.audioTrackInUse}')) continue;
    voices.add(SilenceSource(
      path: a.path,
      audioTrack: s.audioTrackInUse,
      channel: s.audioChannelInUse,
      offsetMs: a.syncOffsetMs!,
      sourceDurationMs: a.sourceDurationMs,
      isVoice: true,
    ));
  }
  final own = clip.hasAudio && (voices.isEmpty || !clip.muted);
  return [
    if (own)
      SilenceSource(
        path: clip.path,
        audioTrack: clip.audioTrackInUse,
        channel: clip.audioChannelInUse,
        sourceDurationMs: clip.sourceDurationMs,
      ),
    ...voices,
  ];
}

/// True when "Remove silences" has something to listen to for [clip].
bool canRemoveSilences(Project p, Clip clip) =>
    silenceSourcesOf(p, clip).isNotEmpty;

/// The silences of one source as times of the CLIP's file, limited to
/// [fromMs]..[toMs] (the clip's part): [silences] are times of the source's
/// own file; where that file has no sound for the clip, it is silent.
List<SourceRange> silencesInClipTime(
    SilenceSource s, List<SourceRange> silences, int fromMs, int toMs) {
  final out = <SourceRange>[];
  void add(int a, int b) {
    if (a < fromMs) a = fromMs;
    if (b > toMs) b = toMs;
    if (b <= a) return;
    if (out.isNotEmpty && a <= out.last.endMs) {
      if (b > out.last.endMs) {
        out[out.length - 1] = (startMs: out.last.startMs, endMs: b);
      }
    } else {
      out.add((startMs: a, endMs: b));
    }
  }

  // Before the file starts.
  final fileStart = -s.offsetMs;
  if (fileStart > fromMs) add(fromMs, fileStart);
  final sorted = [...silences]..sort((a, b) => a.startMs.compareTo(b.startMs));
  for (final r in sorted) {
    add(r.startMs - s.offsetMs, r.endMs - s.offsetMs);
  }
  // After it ends.
  if (s.sourceDurationMs > 0) {
    final fileEnd = s.sourceDurationMs - s.offsetMs;
    if (fileEnd < toMs) add(fileEnd < fromMs ? fromMs : fileEnd, toMs);
  }
  return out;
}

/// The stretches that are in every one of [lists] (each sorted, without
/// overlaps), at least [minMs] long.
List<SourceRange> silentInAll(List<List<SourceRange>> lists, {int minMs = 0}) {
  if (lists.isEmpty) return const [];
  var cur = lists.first;
  for (final other in lists.skip(1)) {
    final next = <SourceRange>[];
    var i = 0, j = 0;
    while (i < cur.length && j < other.length) {
      final a = cur[i], b = other[j];
      final s = a.startMs > b.startMs ? a.startMs : b.startMs;
      final e = a.endMs < b.endMs ? a.endMs : b.endMs;
      if (e > s) next.add((startMs: s, endMs: e));
      if (a.endMs < b.endMs) {
        i++;
      } else {
        j++;
      }
    }
    cur = next;
  }
  return [
    for (final r in cur)
      if (r.endMs - r.startMs >= minMs) r,
  ];
}

/// A running "Remove silences" search for one clip: every sound it listens
/// to, one after the other.
class ClipSilenceSearch {
  ClipSilenceSearch._(this.sources, this._clip, this._minSilenceMs);

  final List<SilenceSource> sources;
  final Clip _clip;
  final int _minSilenceMs;
  final StreamController<double> _progress = StreamController.broadcast();
  final Completer<List<SourceRange>> _result = Completer();
  final List<SilenceLevels?> _levels = [];
  final List<List<SourceRange>> _found = [];
  SilenceJob? _running;
  bool _cancelled = false;

  /// 0..1 over all the sounds.
  Stream<double> get progress => _progress.stream;

  /// The silences, as times of the clip's file, or [ExportException].
  Future<List<SourceRange>> get result => _result.future;

  /// True when a voice recorded separately is listened to.
  bool get listensToVoice => sources.any((s) => s.isVoice);

  /// True once [result] is there and [silencesFor] can answer.
  bool get canAdjust =>
      _levels.length == sources.length && _levels.every((l) => l != null);

  /// The measured levels of each sound (automatic threshold), in the order
  /// of [sources].
  List<SilenceLevels?> get levels => List.unmodifiable(_levels);

  /// The silences at another sensitivity, without listening again. Only
  /// when [canAdjust].
  List<SourceRange> silencesFor(SilenceSensitivity sensitivity) {
    final lists = <List<SourceRange>>[];
    for (var i = 0; i < sources.length; i++) {
      final l = _levels[i]!;
      lists.add(silencesInClipTime(
          sources[i],
          l.silences(
              thresholdDb: l.thresholdFor(sensitivity),
              minSilenceMs: _minSilenceMs),
          _clip.inMs,
          _clip.outMs));
    }
    return silentInAll(lists, minMs: _minSilenceMs);
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _running?.cancel();
  }

  Future<void> _run(MediaEngine engine, double? thresholdDb) async {
    try {
      for (var i = 0; i < sources.length; i++) {
        if (_cancelled) {
          throw ExportException('Stopped.', cancelled: true);
        }
        final s = sources[i];
        var from = _clip.inMs + s.offsetMs;
        var to = _clip.outMs + s.offsetMs;
        if (from < 0) from = 0;
        if (s.sourceDurationMs > 0 && to > s.sourceDurationMs) {
          to = s.sourceDurationMs;
        }
        List<SourceRange> silences;
        SilenceLevels? levels;
        if (to - from < 40) {
          // The file has no sound for this clip at all.
          silences = const [];
          levels = SilenceLevels(fromMs: from, starts: const [], levels: const []);
        } else if (engine is SilenceJobEngine) {
          final job = _running = (engine as SilenceJobEngine)
              .startSilenceDetection(s.path,
                  thresholdDb: thresholdDb,
                  minSilenceMs: _minSilenceMs,
                  audioTrack: s.audioTrack,
                  channel: s.channel,
                  fromMs: from,
                  toMs: to);
          final sub = job.progress.listen((f) {
            if (!_progress.isClosed) _progress.add((i + f) / sources.length);
          });
          try {
            silences = await job.result;
            levels = job.levels;
          } finally {
            // Not awaited: nothing depends on it (and a cancel future of
            // an already finished stream never completes in widget tests).
            unawaited(sub.cancel());
            _running = null;
          }
        } else {
          silences = await engine.detectSilence(s.path,
              thresholdDb: thresholdDb,
              minSilenceMs: _minSilenceMs,
              audioTrack: s.audioTrack,
              channel: s.channel);
        }
        _levels.add(levels);
        _found.add(
            silencesInClipTime(s, silences, _clip.inMs, _clip.outMs));
      }
      _result.complete(silentInAll(_found, minMs: _minSilenceMs));
    } catch (e, st) {
      _result.completeError(e, st);
    } finally {
      unawaited(_progress.close());
    }
  }
}

/// Starts looking for the silences of [clip] of [p] in everything
/// "Remove silences" listens to for it ([silenceSourcesOf]). [thresholdDb]
/// null: automatic (see media/silence_levels.dart).
ClipSilenceSearch startClipSilenceSearch(
    MediaEngine engine, Project p, Clip clip,
    {double? thresholdDb, int minSilenceMs = 700}) {
  final search =
      ClipSilenceSearch._(silenceSourcesOf(p, clip), clip, minSilenceMs);
  // Errors reach the caller through [result].
  search._result.future.ignore();
  unawaited(search._run(engine, thresholdDb));
  return search;
}
