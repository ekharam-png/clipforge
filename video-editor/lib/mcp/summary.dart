// The description of a project that every tool returns: a compact text for
// the model to read and the same facts as JSON. Pure Dart.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/project.dart';

/// Names used for [CanvasAspect] in tool arguments and results.
const Map<String, CanvasAspect> kAspectNames = {
  'original': CanvasAspect.original,
  '9:16': CanvasAspect.portrait9x16,
  '16:9': CanvasAspect.landscape16x9,
  '1:1': CanvasAspect.square1x1,
  '4:5': CanvasAspect.portrait4x5,
};

String aspectName(CanvasAspect aspect) =>
    kAspectNames.entries.firstWhere((e) => e.value == aspect).key;

String _aspectLabel(CanvasAspect aspect) => switch (aspect) {
      CanvasAspect.original => 'original (shape of the first clip)',
      CanvasAspect.portrait9x16 => '9:16 (vertical)',
      CanvasAspect.landscape16x9 => '16:9 (horizontal)',
      CanvasAspect.square1x1 => '1:1 (square)',
      CanvasAspect.portrait4x5 => '4:5 (portrait)',
    };

/// `1:02.345` (minutes:seconds.milliseconds).
String clock(int ms) {
  final t = ms < 0 ? 0 : ms;
  final minutes = t ~/ 60000;
  final seconds = (t ~/ 1000 % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds.${(t % 1000).toString().padLeft(3, '0')}';
}

/// `#RRGGBB`, or `#AARRGGBB` when not fully opaque.
String colorText(int argb) {
  final hex = (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
  return hex.startsWith('FF') ? '#${hex.substring(2)}' : '#$hex';
}

/// Parses `#RRGGBB`, `#AARRGGBB`, the same without `#`, or a few colour
/// names. Null when [text] is none of those.
int? parseColor(String text) {
  const names = {
    'white': 0xFFFFFFFF,
    'black': 0xFF000000,
    'red': 0xFFFF0000,
    'green': 0xFF00C000,
    'blue': 0xFF0000FF,
    'yellow': 0xFFFFFF00,
    'orange': 0xFFFF8800,
    'pink': 0xFFFF66AA,
    'purple': 0xFF8000FF,
    'cyan': 0xFF00FFFF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
  };
  final t = text.trim().toLowerCase();
  if (names.containsKey(t)) return names[t];
  final hex = t.startsWith('#') ? t.substring(1) : t;
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
  if (hex.length == 6) return 0xFF000000 | int.parse(hex, radix: 16);
  if (hex.length == 8) return int.parse(hex, radix: 16);
  return null;
}

String _num(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _signed(double v) => '${v > 0 ? '+' : ''}${_num(v)}';

bool _missing(String path) {
  try {
    return !File(path).existsSync();
  } catch (_) {
    return true;
  }
}

String _oneLine(String text, [int max = 70]) {
  final flat = text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' / ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
}

/// Short keys ("m1", "m2", ...) for the media files of [project], in the
/// order they are first used (clips, then sound, then overlays): get_project
/// lists every path ONCE in a `media` table and the items name the key.
Map<String, String> mediaKeys(Project project) {
  final keys = <String, String>{};
  void add(String path) => keys.putIfAbsent(path, () => 'm${keys.length + 1}');
  for (final c in project.clips) {
    add(c.path);
  }
  for (final a in project.audio) {
    add(a.path);
  }
  for (final o in project.overlays) {
    add(o.clip.path);
  }
  return keys;
}

/// The `media` table: key -> full path, file name, whether it is missing
/// and how many items use it.
Map<String, dynamic> mediaTableJson(Project project) {
  final keys = mediaKeys(project);
  int uses(String path) =>
      project.clips.where((c) => c.path == path).length +
      project.audio.where((a) => a.path == path).length +
      project.overlays.where((o) => o.clip.path == path).length;
  return {
    for (final e in keys.entries)
      e.value: {
        'file': p.basename(e.key),
        'path': e.key,
        'fileMissing': _missing(e.key),
        'uses': uses(e.key),
      },
  };
}

/// [json] of an item with its file named by the key from [keys] instead
/// of `file` / `path` / `fileMissing`.
Map<String, dynamic> _withMediaKey(
    Map<String, dynamic> json, Map<String, String> keys) {
  final path = json['path'];
  if (path is! String || !keys.containsKey(path)) return json;
  return {
    for (final e in json.entries)
      if (e.key == 'file')
        'media': keys[path]
      else if (e.key != 'path' && e.key != 'fileMissing')
        e.key: e.value,
  };
}

Map<String, dynamic> clipJson(Project project, int index) {
  final c = project.clips[index];
  final overlap = project.transitionOverlapMs(index);
  return {
    'index': index,
    'id': c.id,
    'type': c.type.name,
    'file': p.basename(c.path),
    'path': c.path,
    'fileMissing': _missing(c.path),
    'timelineStartMs': project.clipStartMs(index),
    'timelineEndMs': project.clipEndMs(index),
    'durationMs': c.durationMs,
    if (c.type == ClipType.video) ...{
      'sourceInMs': c.inMs,
      'sourceOutMs': c.outMs,
      'sourceDurationMs': c.sourceDurationMs,
      'speed': c.speed,
      'hasAudio': c.hasAudio,
      'volume': c.volume,
      'muted': c.muted,
      'denoise': c.denoise,
      'voiceFocusPercent': (c.voiceFocus * 100).round(),
      // 1-based like the app's "Track 1"; how many the file has (0 = not
      // known for clips added by older versions).
      'audioTrack': c.audioTrackInUse + 1,
      'audioTracks': c.audioStreams.length,
      'audioChannel': c.audioChannelInUse.name,
      'audioChannels': c.audioChannelsInUse,
    },
    'width': c.width,
    'height': c.height,
    'fit': c.fit.name,
    'brightness': c.brightness,
    'contrast': c.contrast,
    'saturation': c.saturation,
    'zoom': c.zoom,
    'filter': _filterKey(c.filter),
    'warmth': c.warmth,
    'fadeInMs': c.fadeInMs,
    'fadeOutMs': c.fadeOutMs,
    if (c.frameRate > 0) 'frameRate': c.frameRate,
    'transition': c.transition.name,
    'transitionMs': c.transitionMs,
    'transitionOverlapMs': overlap,
    ...framingJson(c.framing),
  };
}

/// Names of [OverlayLayout] for the tools.
const Map<String, OverlayLayout> kOverlayLayoutNames = {
  'pip': OverlayLayout.pip,
  'side_by_side': OverlayLayout.sideBySide,
  'top_bottom': OverlayLayout.topBottom,
  'full': OverlayLayout.full,
  'free': OverlayLayout.free,
};

String overlayLayoutKey(OverlayLayout l) =>
    kOverlayLayoutNames.entries.firstWhere((e) => e.value == l).key;

/// Names of [OverlayCorner] for the tools.
const Map<String, OverlayCorner> kOverlayCornerNames = {
  'top_left': OverlayCorner.topLeft,
  'top_right': OverlayCorner.topRight,
  'bottom_left': OverlayCorner.bottomLeft,
  'bottom_right': OverlayCorner.bottomRight,
};

String overlayCornerKey(OverlayCorner c) =>
    kOverlayCornerNames.entries.firstWhere((e) => e.value == c).key;

/// Crop and position of a picture, as the tools name them (only what is
/// not the default).
Map<String, dynamic> framingJson(Framing f) => {
      if (!f.crop.isFull)
        'crop': {
          'x': f.crop.x,
          'y': f.crop.y,
          'width': f.crop.width,
          'height': f.crop.height,
        },
      if (f.rotation != 0) 'rotation': f.rotation,
      if (f.flipH) 'flipHorizontal': true,
      if (f.flipV) 'flipVertical': true,
      if (f.panX != 0) 'positionX': f.panX,
      if (f.panY != 0) 'positionY': f.panY,
    };

String _framingText(Framing f) {
  final parts = [
    if (!f.crop.isFull)
      'crop x ${_num(f.crop.x)} y ${_num(f.crop.y)} '
          'w ${_num(f.crop.width)} h ${_num(f.crop.height)}',
    if (f.rotation != 0) 'rotated ${f.rotation}°',
    if (f.flipH) 'flipped sideways',
    if (f.flipV) 'flipped upside down',
    if (f.panX != 0 || f.panY != 0)
      'position x ${_signed(f.panX)} y ${_signed(f.panY)}',
  ];
  return parts.isEmpty ? '' : ', ${parts.join(', ')}';
}

Map<String, dynamic> overlayJson(Project project, OverlayClip o) {
  final c = o.clip;
  return {
    'id': o.id,
    'type': c.type.name,
    'file': p.basename(c.path),
    'path': c.path,
    'fileMissing': _missing(c.path),
    'timelineStartMs': o.startMs,
    'timelineEndMs': o.endMs,
    'durationMs': o.durationMs,
    if (c.type == ClipType.video) ...{
      'sourceInMs': c.inMs,
      'sourceOutMs': c.outMs,
      'sourceDurationMs': c.sourceDurationMs,
      'speed': c.speed,
      'hasAudio': c.hasAudio,
      'volume': c.volume,
      'muted': c.muted,
    },
    'width': c.width,
    'height': c.height,
    'layout': overlayLayoutKey(o.layout),
    if (o.layout == OverlayLayout.pip) 'corner': overlayCornerKey(o.corner),
    if (o.layout == OverlayLayout.pip || o.layout == OverlayLayout.free)
      'sizePercent': (o.size * 100).round(),
    if (o.layout == OverlayLayout.free) ...{'x': o.x, 'y': o.y},
    if (o.layout == OverlayLayout.sideBySide ||
        o.layout == OverlayLayout.topBottom)
      'overlaySide': o.layout == OverlayLayout.sideBySide
          ? (o.overlayFirst ? 'left' : 'right')
          : (o.overlayFirst ? 'top' : 'bottom'),
    'border': o.border,
    'fadeInMs': o.fadeInMs,
    'fadeOutMs': o.fadeOutMs,
    ...framingJson(c.framing),
  };
}

/// Names of [VideoSize] for the tools.
const Map<String, VideoSize> kVideoSizeNames = {
  'match_first_clip': VideoSize.matchFirstClip,
  '720p': VideoSize.p720,
  '1080p': VideoSize.p1080,
  '4k': VideoSize.p2160,
};

String videoSizeKey(VideoSize s) =>
    kVideoSizeNames.entries.firstWhere((e) => e.value == s).key;

Map<String, dynamic> trackJson(Project project, SoundTrack t) => {
      'id': t.id,
      'name': t.name,
      'volume': t.volume,
      'muted': t.muted,
      'solo': t.solo,
      if (t.id != SoundTrack.videoId) ...{
        'duckUnderSpeech': t.duck,
        'speech': t.speech,
        'audioIds': [
          for (final a in project.clipsOnTrack(t.id)) a.id,
        ],
      },
      'heard': project.trackGain(t) > 0,
    };

Map<String, dynamic> audioJson(AudioClip a, [Project? project]) => {
      'id': a.id,
      'trackId': a.trackId,
      // voice / music / effect; a voice lined up with a video clip also has
      // linked_clip (while it follows that clip) and offset_ms (time in
      // this file = time in the clip's file + offset_ms).
      if (project != null) 'role': project.soundRoleOf(a),
      if (a.isVoice && a.linked) 'linked_clip': a.sourceClipId,
      if (a.isVoice) 'offset_ms': a.syncOffsetMs,
      'file': p.basename(a.path),
      'path': a.path,
      'fileMissing': _missing(a.path),
      'timelineStartMs': a.startMs,
      'timelineEndMs': a.endMs,
      'sourceInMs': a.inMs,
      'sourceOutMs': a.outMs,
      'sourceDurationMs': a.sourceDurationMs,
      'volume': a.volume,
      'fadeInMs': a.fadeInMs,
      'fadeOutMs': a.fadeOutMs,
      if (a.speed != 1) 'speed': a.speed,
      if (a.denoise) 'denoise': true,
      if (a.voiceFocus >= 0.005) 'voiceFocus': a.voiceFocus,
      if (a.isSeparated) 'separatedFromClipId': a.sourceClipId,
      if (a.sourceClipId != null) 'followsClip': a.linked,
      if (a.looped) 'loopMs': a.loopMs,
      if (a.credit != null) 'credit': a.credit!.fullLine,
    };

Map<String, dynamic> titleJson(TitleOverlay t) => {
      'id': t.id,
      'kind': t.kind.name,
      'text': t.text,
      'startMs': t.startMs,
      'endMs': t.endMs,
      'x': t.x,
      'y': t.y,
      'fontSize': t.fontSize,
      'color': colorText(t.colorArgb),
      'bold': t.bold,
      'background': t.background,
      'font': t.font.name,
      'outline': t.outline,
      if (t.outline) 'outlineColor': colorText(t.outlineColorArgb),
      'shadow': t.shadow,
      'align': t.align.name,
      'animationIn': _animKey(t.animIn),
      'animationOut': _animKey(t.animOut),
    };

String _animKey(TitleAnimation a) =>
    a == TitleAnimation.slideUp ? 'slide_up' : a.name;

String _filterKey(LookFilter f) =>
    f == LookFilter.blackWhite ? 'black_and_white' : f.name;

List<TitleOverlay> _sortedTitles(Project project) {
  final list = [...project.titles];
  final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final byStart = a.startMs.compareTo(b.startMs);
    return byStart != 0 ? byStart : order[a.id]!.compareTo(order[b.id]!);
  });
  return list;
}

/// Titles shown for a limit of [maxTitles] (null = all): the plain titles
/// first (there are few), then captions in time order.
List<TitleOverlay> _shownTitles(Project project, int? maxTitles) {
  final sorted = _sortedTitles(project);
  if (maxTitles == null || sorted.length <= maxTitles) return sorted;
  final keep = <TitleOverlay>[
    ...sorted.where((t) => t.kind == TitleKind.title),
    ...sorted.where((t) => t.kind == TitleKind.caption),
  ].take(maxTitles).toSet();
  return [
    for (final t in sorted)
      if (keep.contains(t)) t,
  ];
}

/// Part of a project to show (get_project): a time range of the timeline
/// and / or a page of clips, at most [titleLimit] titles.
class ProjectPage {
  const ProjectPage({
    this.fromMs,
    this.toMs,
    this.clipOffset = 0,
    this.clipLimit,
    this.titleOffset = 0,
    this.titleLimit,
  });
  final int? fromMs;
  final int? toMs;
  final int clipOffset;
  final int? clipLimit;
  final int titleOffset;
  final int? titleLimit;

  bool overlaps(int start, int end) =>
      (fromMs == null || end > fromMs!) && (toMs == null || start < toMs!);

  bool get hasRange => fromMs != null || toMs != null;
}

/// Indexes of the clips [page] shows, and how many match its range.
({List<int> shown, int matching}) pageClips(Project project, ProjectPage? page) {
  final all = [
    for (var i = 0; i < project.clips.length; i++)
      if (page == null ||
          page.overlaps(project.clipStartMs(i), project.clipEndMs(i)))
        i,
  ];
  if (page == null) return (shown: all, matching: all.length);
  final from = page.clipOffset.clamp(0, all.length);
  final to = page.clipLimit == null
      ? all.length
      : (from + page.clipLimit!).clamp(from, all.length);
  return (shown: all.sublist(from, to), matching: all.length);
}

/// Titles [page] shows (time order), and how many match its range.
({List<TitleOverlay> shown, int matching}) pageTitles(
    Project project, ProjectPage page) {
  final all = [
    for (final t in _sortedTitles(project))
      if (page.overlaps(t.startMs, t.endMs)) t,
  ];
  final from = page.titleOffset.clamp(0, all.length);
  final to = page.titleLimit == null
      ? all.length
      : (from + page.titleLimit!).clamp(from, all.length);
  return (shown: all.sublist(from, to), matching: all.length);
}

/// The project as JSON for `structuredContent`. At most [maxTitles] titles
/// are listed (null = all); `titlesOmitted` says how many were left out.
Map<String, dynamic> projectJson(Project project,
    {int? maxTitles, ProjectPage? page}) {
  final canvas = project.canvasSize;
  final clipPage = pageClips(project, page);
  final titlePage = page == null ? null : pageTitles(project, page);
  final shown = titlePage?.shown ?? _shownTitles(project, maxTitles);
  // get_project (a page): every path once, items name its key.
  final keys = page == null ? const <String, String>{} : mediaKeys(project);
  Map<String, dynamic> item(Map<String, dynamic> json) =>
      page == null ? json : _withMediaKey(json, keys);
  return {
    'id': project.id,
    'name': project.name,
    'aspect': aspectName(project.aspect),
    'canvasWidth': canvas.width,
    'canvasHeight': canvas.height,
    'durationMs': project.durationMs,
    'duckMusic': project.duckMusic,
    'videoSize': videoSizeKey(project.videoSize),
    'fadeInMs': project.fadeInMs,
    'fadeOutMs': project.fadeOutMs,
    'videoSound': trackJson(project, project.videoSound),
    'soundTracks': [for (final t in project.soundTracks) trackJson(project, t)],
    'updatedAt': project.updatedAt.toUtc().toIso8601String(),
    'clipCount': project.clips.length,
    if (page != null) 'media': mediaTableJson(project),
    'clips': [for (final i in clipPage.shown) item(clipJson(project, i))],
    'audio': [
      for (final a in project.audio)
        if (page == null || page.overlaps(a.startMs, a.endMs))
          item(audioJson(a, project)),
    ],
    'overlays': [
      for (final o in project.overlays)
        if (page == null || page.overlaps(o.startMs, o.endMs))
          item(overlayJson(project, o)),
    ],
    'titles': [for (final t in shown) titleJson(t)],
    'titleCount':
        project.titles.where((t) => t.kind == TitleKind.title).length,
    'captionCount':
        project.titles.where((t) => t.kind == TitleKind.caption).length,
    'titlesOmitted': project.titles.length - shown.length,
    if (page != null)
      'page': {
        'fromMs': page.fromMs,
        'toMs': page.toMs,
        'clipsMatching': clipPage.matching,
        'clipOffset': page.clipOffset,
        'clipsShown': clipPage.shown.length,
        if (clipPage.shown.isNotEmpty) 'firstClipIndex': clipPage.shown.first,
        if (clipPage.shown.isNotEmpty) 'lastClipIndex': clipPage.shown.last,
        if (page.clipOffset + clipPage.shown.length < clipPage.matching)
          'nextClipOffset': page.clipOffset + clipPage.shown.length,
        'titlesMatching': titlePage!.matching,
        'titleOffset': page.titleOffset,
        'titlesShown': titlePage.shown.length,
        if (page.titleOffset + titlePage.shown.length < titlePage.matching)
          'nextTitleOffset': page.titleOffset + titlePage.shown.length,
      },
  };
}

/// The project as text: one line per clip, audio item and title, with the
/// ids needed for further tool calls. All times are milliseconds.
String projectText(Project project, {int? maxTitles, ProjectPage? page}) {
  final clipPage = pageClips(project, page);
  final titlePage = page == null ? null : pageTitles(project, page);
  final canvas = project.canvasSize;
  // get_project (a page): files are named by a short key, every full path
  // is listed once in "Media files".
  final keys = page == null ? const <String, String>{} : mediaKeys(project);
  String fileRef(String path) =>
      keys[path] ?? '"${p.basename(path)}"';
  String missingNote(String path) => !_missing(path)
      ? ''
      : keys.containsKey(path)
          ? '  [FILE MISSING]'
          : '  [FILE MISSING: $path]';
  final out = StringBuffer()
    ..writeln('Project "${project.name}" (project_id ${project.id})')
    ..writeln('Shape: ${_aspectLabel(project.aspect)}, '
        '${canvas.width}x${canvas.height} px. '
        'Length: ${project.durationMs} ms (${clock(project.durationMs)}). '
        'Video size: ${videoSizeKey(project.videoSize)}.'
        '${project.fadeInMs > 0 ? ' Fades in from black: ${project.fadeInMs} ms.' : ''}'
        '${project.fadeOutMs > 0 ? ' Fades out to black: ${project.fadeOutMs} ms.' : ''}');
  out.writeln(_videoSoundLine(project));
  if (project.soundTracks.isEmpty) {
    out.writeln('Sound tracks: none yet (add_music or separate_sound makes one; '
        'add_sound_track adds an empty one).');
  } else {
    out.writeln('Sound tracks (top to bottom):');
    for (final t in project.soundTracks) {
      out.writeln('  track_id=${t.id} "${t.name}"${_trackState(project, t)}'
          '${t.duck ? ', lowered under speech' : ''}'
          '${t.speech ? ', counts as speech' : ''}, '
          '${project.clipsOnTrack(t.id).length} item(s)');
    }
  }

  if (keys.isNotEmpty) {
    final table = mediaTableJson(project);
    out.writeln('Media files (each listed once; clips, sound and overlays '
        'name them by key):');
    for (final e in table.entries) {
      final m = e.value as Map;
      out.writeln('  ${e.key} = "${m['file']}"  ${m['path']}  '
          '(used ${m['uses']}x)${m['fileMissing'] == true ? '  [FILE MISSING]' : ''}');
    }
  }

  if (project.clips.isEmpty) {
    out.writeln('Clips: none yet (add some with add_media).');
  } else {
    final range = page == null || !page.hasRange
        ? ''
        : ' between ${page.fromMs ?? 0} and ${page.toMs ?? project.durationMs} ms';
    if (page != null &&
        (clipPage.shown.length < project.clips.length || page.hasRange)) {
      final next = page.clipOffset + clipPage.shown.length;
      out.writeln('Clips, in playing order (times in ms): '
          '${clipPage.shown.isEmpty ? 'none' : '#${clipPage.shown.first}–#${clipPage.shown.last}'} '
          'shown, ${clipPage.matching} of ${project.clips.length} clips$range'
          '${next < clipPage.matching ? ' (next page: clip_offset $next)' : ''}:');
    } else {
      out.writeln('Clips, in playing order (times in ms):');
    }
    for (final i in clipPage.shown) {
      final c = project.clips[i];
      final line = StringBuffer(
          '  #$i clip_id=${c.id} ${c.type.name} ${fileRef(c.path)} '
          'timeline ${project.clipStartMs(i)}–${project.clipEndMs(i)}');
      if (c.type == ClipType.video) {
        line.write(', source ${c.inMs}–${c.outMs} of ${c.sourceDurationMs}'
            ', speed ${_num(c.speed)}x');
        if (!c.hasAudio) {
          line.write(', no sound');
        } else if (c.muted) {
          line.write(', muted');
        } else if (c.volume != 1.0) {
          line.write(', volume ${_num(c.volume)}');
        }
        if (c.hasAudio && c.audioStreams.length > 1) {
          line.write(', sound track ${c.audioTrackInUse + 1} of '
              '${c.audioStreams.length}');
        }
        if (c.hasAudio && c.audioChannelInUse != AudioChannel.both) {
          line.write(', ${c.audioChannelInUse.name} channel only');
        }
        if (c.denoise) line.write(', clean audio');
        if (c.voiceFocus >= 0.005) {
          line.write(', voice focus ${(c.voiceFocus * 100).round()}%');
        }
      }
      if (c.fit != FitMode.fit) line.write(', fit ${c.fit.name}');
      if (c.zoom != 1.0) line.write(', zoom ${_num(c.zoom)}x');
      if (c.brightness != 0) line.write(', brightness ${_signed(c.brightness)}');
      if (c.contrast != 0) line.write(', contrast ${_signed(c.contrast)}');
      if (c.saturation != 0) line.write(', saturation ${_signed(c.saturation)}');
      if (c.filter != LookFilter.none) line.write(', filter ${_filterKey(c.filter)}');
      if (c.warmth != 0) line.write(', warmth ${_signed(c.warmth)}');
      if (c.fadeInMs > 0) line.write(', fade in ${c.fadeInMs} ms');
      if (c.fadeOutMs > 0) line.write(', fade out ${c.fadeOutMs} ms');
      line.write(_framingText(c.framing));
      if (i > 0 && c.transition != TransitionType.none) {
        line.write(', transition ${c.transition.name} '
            '${project.transitionOverlapMs(i)} ms (overlaps the previous clip)');
      }
      line.write(missingNote(c.path));
      out.writeln(line);
    }
  }

  if (project.audio.isEmpty) {
    out.writeln('Music / sound: none.');
  } else {
    out.writeln('Music / sound:');
    for (final a in project.audio) {
      if (page != null && !page.overlaps(a.startMs, a.endMs)) continue;
      final line = StringBuffer(
          '  audio_id=${a.id} ${fileRef(a.path)} '
          'timeline ${a.startMs}–${a.endMs}, '
          'source ${a.inMs}–${a.outMs} of ${a.sourceDurationMs}, '
          'volume ${_num(a.volume)}');
      if (a.speed != 1) line.write(', speed ${_num(a.speed)}x');
      if (a.denoise) line.write(', clean audio');
      if (a.voiceFocus >= 0.005) {
        line.write(', voice focus ${(a.voiceFocus * 100).round()}%');
      }
      if (a.isVoice) {
        line.write(a.linked
            ? ', voice recorded separately, linked_clip=${a.sourceClipId} '
                'offset_ms=${a.syncOffsetMs} (follows that clip)'
            : ', voice recorded separately, not linked '
                '(offset_ms=${a.syncOffsetMs}, stays where it is)');
      } else if (a.sourceClipId != null) {
        line.write(', sound separated from clip_id=${a.sourceClipId}'
            '${a.linked ? ' (follows that clip)' : ' (stays where it is)'}');
      }
      if (a.fadeInMs > 0) line.write(', fade in ${a.fadeInMs}');
      if (a.fadeOutMs > 0) line.write(', fade out ${a.fadeOutMs}');
      if (a.looped) line.write(', loops its source part to fill ${a.loopMs} ms');
      if (a.credit != null) line.write(', credit: ${a.credit!.shortLine}');
      line.write(', role ${project.soundRoleOf(a)}');
      line.write(', track "${project.trackById(a.trackId)?.name ?? a.trackId}"');
      if (a.endMs > project.durationMs) {
        line.write(' (runs past the end of the video; the export stops at '
            '${project.durationMs})');
      }
      line.write(missingNote(a.path));
      out.writeln(line);
    }
  }

  if (project.overlays.isEmpty) {
    out.writeln('Overlay track: empty (add_overlay puts a video or photo over '
        'the picture).');
  } else {
    out.writeln('Overlay track (over the main picture, under the titles):');
    for (final o in project.overlays) {
      if (page != null && !page.overlaps(o.startMs, o.endMs)) continue;
      final c = o.clip;
      final line = StringBuffer(
          '  overlay_id=${o.id} ${c.type.name} ${fileRef(c.path)} '
          'timeline ${o.startMs}–${o.endMs}');
      if (c.type == ClipType.video) {
        line.write(', source ${c.inMs}–${c.outMs} of ${c.sourceDurationMs}'
            ', speed ${_num(c.speed)}x');
        if (!c.hasAudio) {
          line.write(', no sound');
        } else if (c.muted) {
          line.write(', muted');
        } else if (c.volume != 1.0) {
          line.write(', volume ${_num(c.volume)}');
        }
      }
      line.write(', layout ${overlayLayoutKey(o.layout)}');
      if (o.layout == OverlayLayout.pip) {
        line.write(' ${overlayCornerKey(o.corner)}');
      }
      if (o.layout == OverlayLayout.pip || o.layout == OverlayLayout.free) {
        line.write(', size ${(o.size * 100).round()}%');
      }
      if (o.layout == OverlayLayout.free) {
        line.write(' centred at x ${_num(o.x)} y ${_num(o.y)}');
      }
      if (o.layout == OverlayLayout.sideBySide) {
        line.write(', overlay on the ${o.overlayFirst ? 'left' : 'right'}');
      }
      if (o.layout == OverlayLayout.topBottom) {
        line.write(', overlay on the ${o.overlayFirst ? 'top' : 'bottom'}');
      }
      if (o.border) line.write(', white frame');
      if (o.fadeInMs > 0) line.write(', fade in ${o.fadeInMs}');
      if (o.fadeOutMs > 0) line.write(', fade out ${o.fadeOutMs}');
      line.write(_framingText(c.framing));
      if (o.endMs > project.durationMs) {
        line.write(' (runs past the end of the video; the export stops at '
            '${project.durationMs})');
      }
      line.write(missingNote(c.path));
      out.writeln(line);
    }
  }

  if (project.titles.isEmpty) {
    out.writeln('Titles and captions: none.');
  } else {
    final shown = titlePage?.shown ?? _shownTitles(project, maxTitles);
    final captions =
        project.titles.where((t) => t.kind == TitleKind.caption).length;
    out.writeln('Titles and captions (${project.titles.length - captions} '
        'title(s), $captions caption(s)):');
    for (final t in shown) {
      final line = StringBuffer(
          '  title_id=${t.id} ${t.kind.name} ${t.startMs}–${t.endMs} '
          '"${_oneLine(t.text)}"');
      if (t.kind == TitleKind.title) {
        line.write(' at x ${_num(t.x)} y ${_num(t.y)}, size ${_num(t.fontSize)}'
            ', ${colorText(t.colorArgb)}'
            '${t.bold ? ', bold' : ''}${t.background ? ', boxed' : ''}'
            '${t.font != TitleFont.classic ? ', font ${t.font.name}' : ''}'
            '${t.outline ? ', outline' : ''}'
            '${t.align != TitleAlign.center ? ', aligned ${t.align.name}' : ''}'
            '${t.animIn != TitleAnimation.none ? ', in: ${_animKey(t.animIn)}' : ''}'
            '${t.animOut != TitleAnimation.none ? ', out: ${_animKey(t.animOut)}' : ''}');
      }
      out.writeln(line);
    }
    final omitted = project.titles.length - shown.length;
    if (titlePage != null) {
      final next = page!.titleOffset + shown.length;
      if (omitted > 0) {
        out.writeln('  ($omitted not shown: ${titlePage.matching} match'
            '${page.hasRange ? ' the time range' : ''}'
            '${next < titlePage.matching ? '; next page: title_offset $next' : ''}.)');
      }
    } else if (omitted > 0) {
      out.writeln('  … and $omitted more (get_project lists all of them).');
    }
  }
  return out.toString().trimRight();
}

String _trackState(Project project, SoundTrack t) {
  final parts = [
    if (t.volume != 1.0) 'volume ${_num(t.volume)}',
    if (t.muted) 'muted',
    if (t.solo) 'solo',
    if (!t.muted && project.anySolo && !t.solo) 'not heard (another track is solo)',
  ];
  return parts.isEmpty ? '' : ', ${parts.join(', ')}';
}

String _videoSoundLine(Project project) {
  final v = project.videoSound;
  final state = _trackState(project, v);
  return 'Video sound (track_id=${SoundTrack.videoId}): '
      '${state.isEmpty ? 'normal' : state.substring(2)}.';
}
