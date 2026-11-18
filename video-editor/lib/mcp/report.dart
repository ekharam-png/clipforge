// What the tools say about a project besides the timeline itself: why the
// video has its size, what changed in an edit, warnings (sound past the
// end, captions that became very short), what "small" changes in an
// export, and how much the music is lowered under speech. Pure Dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';
import '../media/ffmpeg_command.dart' show exportSize;
import '../media/media_api.dart';
import '../media/video_encoder.dart' show kSmallMaxRateKbps, kCrfFull, kCrfSmall;
import 'summary.dart';

/// Captions shorter than this after an edit get a warning.
const int kShortCaptionMs = 1200;

/// The output size of [project] and why it is that size, in one sentence.
String canvasReason(Project project) {
  final c = project.canvasSize;
  final size = '${c.width}x${c.height}';
  final short = c.width < c.height ? c.width : c.height;
  final hint = short < 1080
      ? ' Set video_size "1080p" (set_project_settings) for full HD.'
      : '';
  final shape = project.aspect == CanvasAspect.original
      ? ''
      : ' in the ${aspectName(project.aspect)} shape';
  if (project.videoSize != VideoSize.matchFirstClip) {
    return '$size because video_size is "${videoSizeKey(project.videoSize)}" '
        '(short side ${project.videoSize.shortSide} px)$shape.';
  }
  final ow = project.originalWidth, oh = project.originalHeight;
  final first = project.clips.isEmpty ? null : project.clips.first;
  if ((ow == null || oh == null) && first == null) {
    return '$size: the default until the first clip is added.';
  }
  final b = ow != null && oh != null
      ? (width: ow, height: oh)
      : Project.originalSizeOf(first!);
  final basis = '${b.width}x${b.height}';
  final firstMatches = first != null &&
      Project.originalSizeOf(first).width == b.width &&
      Project.originalSizeOf(first).height == b.height;
  final from = firstMatches
      ? 'the first clip ("${p.basename(first.path)}", ${first.width}x${first.height})'
      : 'the first clip that was added';
  final capped = firstMatches && (first.width != b.width || first.height != b.height)
      ? ' (a photo is used at most at 1080 px, a video at most at 2160 px on its short side)'
      : '';
  return '$size because video_size is "match_first_clip": the size comes from '
      '$from, $basis$capped$shape.$hint';
}

/// What `quality: small` does to [project]'s export, or null for full.
String? smallExportNote(Project project, ExportQuality quality, ExportFormat format) {
  if (quality != ExportQuality.small) return null;
  if (format.audioOnly) return 'quality "small" has no effect on a sound-only file.';
  final full = exportSize(project, ExportQuality.full);
  final small = exportSize(project, ExportQuality.small);
  final frame = full.width == small.width && full.height == small.height
      ? 'the frame size stays ${full.width}x${full.height} (its short side is already 720 or less)'
      : 'the frame is scaled down from ${full.width}x${full.height} to '
          '${small.width}x${small.height} (short side 720)';
  return 'quality "small": $frame; the video bitrate is capped at '
      '$kSmallMaxRateKbps kbit/s with a lower quality setting (x264 CRF '
      '$kCrfSmall instead of $kCrfFull) and the sound is 128 kbit/s instead of 192.';
}

// ---- warnings ---------------------------------------------------------------

/// One warning per music / sound item that runs past the end of the video
/// or starts after it.
List<String> soundPastEndWarnings(Project project) {
  final total = project.durationMs;
  final out = <String>[];
  for (final a in project.audio) {
    if (a.linked && a.sourceClipId != null) continue;
    final name = '"${p.basename(a.path)}" (audio_id ${a.id})';
    if (a.startMs >= total && total > 0) {
      out.add('$name starts at ${a.startMs} ms, after the end of the video '
          '($total ms), so it is not heard. Move it (update_audio start_ms) or '
          'remove it.');
    } else if (a.endMs > total && total > 0) {
      final over = a.endMs - total;
      final fade = a.fadeOutMs > 0
          ? 'its ${a.fadeOutMs} ms fade-out is moved so that it finishes there'
          : 'it has no fade-out, so it stops abruptly';
      out.add('$name runs ${clock(over)} past the end of the video (it ends '
          'at ${a.endMs} ms, the video at $total ms). The export stops it at '
          'the end of the video and $fade. fit_music_to_video makes it end '
          'with the video with a 2 s fade-out.');
    }
  }
  return out;
}

/// Captions that this edit made shorter than [kShortCaptionMs].
List<TitleOverlay> shortenedCaptions(Project before, Project after) {
  final old = {for (final t in before.titles) t.id: t};
  return [
    for (final t in after.titles)
      if (t.kind == TitleKind.caption &&
          t.endMs - t.startMs < kShortCaptionMs &&
          old[t.id] != null &&
          t.endMs - t.startMs < old[t.id]!.endMs - old[t.id]!.startMs)
        t,
  ];
}

String shortCaptionWarning(List<TitleOverlay> shortened) =>
    '${shortened.length} caption(s) are now on screen for less than '
    '${kShortCaptionMs / 1000} s (sped up or cut): '
    '${shortened.take(8).map((t) => '${t.id} (${t.endMs - t.startMs} ms)').join(', ')}'
    '${shortened.length > 8 ? ', …' : ''}. Give min_caption_ms (e.g. 1200) '
    'with the edit to keep captions on screen at least that long, or '
    'lengthen them with update_title.';

/// Makes the captions in [ids] at least [minMs] long where there is room:
/// up to the next caption's start and the end of the video. Returns the
/// lengthened titles (to be stored by the caller).
List<TitleOverlay> lengthenCaptions(Project project, Set<String> ids, int minMs) {
  final captions = [
    for (final t in project.titles)
      if (t.kind == TitleKind.caption) t,
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final out = <TitleOverlay>[];
  for (var i = 0; i < captions.length; i++) {
    final t = captions[i];
    if (!ids.contains(t.id) || t.endMs - t.startMs >= minMs) continue;
    var limit = project.durationMs;
    for (var j = i + 1; j < captions.length; j++) {
      if (captions[j].startMs >= t.endMs) {
        if (captions[j].startMs < limit) limit = captions[j].startMs;
        break;
      }
    }
    var end = t.startMs + minMs;
    if (end > limit) end = limit;
    if (end > t.endMs) out.add(t.copyWith(endMs: end));
  }
  return out;
}

// ---- what changed ---------------------------------------------------------

/// Ids added / removed / changed between [before] and [after], per kind.
Map<String, dynamic> projectChanges(Project before, Project after) {
  Map<String, dynamic> diff(Map<String, String> a, Map<String, String> b) {
    final added = [for (final id in b.keys) if (!a.containsKey(id)) id];
    final removed = [for (final id in a.keys) if (!b.containsKey(id)) id];
    final changed = [
      for (final id in b.keys)
        if (a.containsKey(id) && a[id] != b[id]) id,
    ];
    return {'added': added, 'removed': removed, 'changed': changed};
  }

  Map<String, String> keyed<T>(List<T> items, String Function(T) id,
          Map<String, dynamic> Function(T) json) =>
      {for (final x in items) id(x): jsonEncode(json(x))};

  final settingsBefore = before.toJson()
    ..removeWhere((k, _) => const ['clips', 'audio', 'titles', 'overlays', 'updatedAt'].contains(k));
  final settingsAfter = after.toJson()
    ..removeWhere((k, _) => const ['clips', 'audio', 'titles', 'overlays', 'updatedAt'].contains(k));
  return {
    'clips': diff(keyed(before.clips, (c) => c.id, (c) => c.toJson()),
        keyed(after.clips, (c) => c.id, (c) => c.toJson())),
    'titles': diff(keyed(before.titles, (t) => t.id, (t) => t.toJson()),
        keyed(after.titles, (t) => t.id, (t) => t.toJson())),
    'audio': diff(keyed(before.audio, (a) => a.id, (a) => a.toJson()),
        keyed(after.audio, (a) => a.id, (a) => a.toJson())),
    'overlays': diff(keyed(before.overlays, (o) => o.id, (o) => o.toJson()),
        keyed(after.overlays, (o) => o.id, (o) => o.toJson())),
    'settings': [
      for (final k in {...settingsBefore.keys, ...settingsAfter.keys})
        if (jsonEncode(settingsBefore[k]) != jsonEncode(settingsAfter[k])) k,
    ],
    'durationMsBefore': before.durationMs,
    'durationMsAfter': after.durationMs,
  };
}

/// [projectChanges] in a few words.
String changesText(Map<String, dynamic> changes) {
  final parts = <String>[];
  String ids(List list) =>
      '${list.take(12).join(', ')}${list.length > 12 ? ', … (${list.length} in all)' : ''}';
  for (final (key, noun) in const [
    ('clips', 'clip'),
    ('titles', 'title/caption'),
    ('audio', 'sound item'),
    ('overlays', 'overlay item'),
  ]) {
    final d = changes[key] as Map;
    final a = d['added'] as List, r = d['removed'] as List, c = d['changed'] as List;
    if (a.isNotEmpty) parts.add('${a.length} $noun(s) added: ${ids(a)}');
    if (r.isNotEmpty) parts.add('${r.length} $noun(s) removed: ${ids(r)}');
    if (c.isNotEmpty) parts.add('${c.length} $noun(s) changed: ${ids(c)}');
  }
  final settings = changes['settings'] as List;
  if (settings.isNotEmpty) parts.add('project settings: ${settings.join(', ')}');
  final b = changes['durationMsBefore'] as int, a = changes['durationMsAfter'] as int;
  if (a != b) parts.add('length ${clock(b)} -> ${clock(a)}');
  return parts.isEmpty ? 'nothing' : parts.join('; ');
}

// ---- who saved it last ---------------------------------------------------

/// Written next to project.json by the server after each save: what it
/// saved, so it can tell later whether the app changed the file since.
const String kClaudeEditFileName = '.claude-edit';

/// FNV-1a 64 of [text], as hex.
String textHash(String text) {
  var h = 0xcbf29ce484222325;
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16);
}

/// Records that the server saved [raw] (the new project.json) with [tool].
void recordClaudeEdit(String projectDir, String raw, String tool) {
  try {
    File(p.join(projectDir, kClaudeEditFileName)).writeAsStringSync(jsonEncode({
      'hash': textHash(raw),
      'tool': tool,
      'at': DateTime.now().toUtc().toIso8601String(),
    }));
  } catch (_) {}
}

/// Who saved project.json ([raw]) last: Claude's tools or the app.
({String by, String? tool}) lastEditor(String projectDir, String raw) {
  try {
    final f = File(p.join(projectDir, kClaudeEditFileName));
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync()) as Map;
      if (j['hash'] == textHash(raw)) return (by: 'claude', tool: j['tool'] as String?);
    }
  } catch (_) {}
  return (by: 'app', tool: null);
}

String lastEditorText(({String by, String? tool}) e) => e.by == 'claude'
    ? 'Claude\'s tools${e.tool == null ? '' : ' (${e.tool})'}'
    : 'the ClipForge app (or another program)';

// ---- ducking --------------------------------------------------------------

List<({int start, int end})> _merge(List<({int start, int end})> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final out = <({int start, int end})>[];
  for (final s in sorted) {
    if (s.end <= s.start) continue;
    if (out.isNotEmpty && s.start <= out.last.end) {
      final last = out.removeLast();
      out.add((start: last.start, end: s.end > last.end ? s.end : last.end));
    } else {
      out.add(s);
    }
  }
  return out;
}

List<({int start, int end})> _intersect(
    List<({int start, int end})> a, List<({int start, int end})> b) {
  final out = <({int start, int end})>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final s = a[i].start > b[j].start ? a[i].start : b[j].start;
    final e = a[i].end < b[j].end ? a[i].end : b[j].end;
    if (e > s) out.add((start: s, end: e));
    if (a[i].end < b[j].end) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

int _total(List<({int start, int end})> spans) =>
    spans.fold(0, (sum, s) => sum + s.end - s.start);

/// Where each "lower under speech" track is lowered: the times it is heard
/// while the video's own sound, a speech track or an overlay's sound can
/// play. Worked out from the timeline and the ducking settings, NOT from
/// measured loudness: pauses inside a clip let the music come back up.
List<Map<String, dynamic>> duckingReport(Project project) {
  final total = project.durationMs;
  final out = <Map<String, dynamic>>[];
  if (total <= 0) return out;
  List<({int start, int end})> heardOf(Iterable<AudioClip> clips) => _merge([
        for (final a in clips)
          if (a.volume > 0)
            for (final piece in a.loopPieces)
              (
                start: piece.startMs < 0 ? 0 : piece.startMs,
                end: project.audibleEndMs(piece) > total ? total : project.audibleEndMs(piece),
              ),
      ]);
  final videoHeard = project.trackGain(project.videoSound) > 0;
  final videoSpeech = videoHeard
      ? _merge([
          for (var i = 0; i < project.clips.length; i++)
            if (project.clips[i].type == ClipType.video &&
                project.clips[i].hasAudio &&
                !project.clips[i].muted &&
                project.clips[i].volume > 0)
              (start: project.clipStartMs(i), end: project.clipEndMs(i)),
          for (final o in project.overlays)
            if (o.audible) (start: o.startMs, end: o.endMs > total ? total : o.endMs),
        ])
      : const <({int start, int end})>[];
  for (final t in project.soundTracks) {
    if (!t.duck || project.trackGain(t) <= 0) continue;
    final heard = heardOf(project.clipsOnTrack(t.id));
    if (heard.isEmpty) continue;
    final speechTracks = [
      for (final s in project.soundTracks)
        if (s.id != t.id && s.speech && project.trackGain(s) > 0) s,
    ];
    final speech = _merge([
      ...videoSpeech,
      for (final s in speechTracks) ...heardOf(project.clipsOnTrack(s.id)),
    ]);
    final lowered = _intersect(heard, speech);
    final heardMs = _total(heard), loweredMs = _total(lowered);
    out.add({
      'trackId': t.id,
      'track': t.name,
      'heardMs': heardMs,
      'loweredMs': loweredMs,
      'stretches': lowered.length,
      'firstStretches': [
        for (final s in lowered.take(10)) {'startMs': s.start, 'endMs': s.end},
      ],
      'under': [
        if (videoSpeech.isNotEmpty) 'the video\'s own sound',
        for (final s in speechTracks) 'the "${s.name}" track',
      ],
      'typicalDb': -9,
      'rangeDb': '-3 (very quiet speech) to about -13',
    });
  }
  return out;
}

String duckingText(List<Map<String, dynamic>> report) {
  if (report.isEmpty) return '';
  final lines = <String>[];
  for (final r in report) {
    final heard = r['heardMs'] as int, lowered = r['loweredMs'] as int;
    final under = (r['under'] as List).cast<String>();
    if (lowered == 0 || under.isEmpty) {
      lines.add('"${r['track']}" is set to be lowered under speech, but no '
          'speech plays while it is heard, so it stays at its level.');
      continue;
    }
    final pct = heard == 0 ? 0 : (lowered * 100 / heard).round();
    final first = (r['firstStretches'] as List)
        .take(4)
        .map((s) => '${clock((s as Map)['startMs'] as int)}–${clock(s['endMs'] as int)}')
        .join(', ');
    lines.add('"${r['track']}" is lowered under ${under.join(' and ')} for '
        '${clock(lowered)} of the ${clock(heard)} it is heard ($pct %), in '
        '${r['stretches']} stretch(es) (from $first${(r['stretches'] as int) > 4 ? ', …' : ''}): '
        'typically about 9 dB down under normal speech (3 dB under very quiet '
        'speech, at most about 13 dB), back up 0.3–0.6 s after the speech stops.');
  }
  return 'Music under speech (worked out from where sound plays and the '
      'ducking settings, not measured; it comes back up in pauses inside a '
      'clip): ${lines.join(' ')}';
}
