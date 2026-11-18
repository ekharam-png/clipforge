// Pure Dart: short human names for edits ("Speed 1.25× on clip 2", "Moved
// clip", "Added title 'Summer'"), for the History list. Worked out from the
// project before and after the edit, so every way of editing (buttons,
// drags, keyboard, Claude control) gets one without saying anything. Edits
// whose result does not tell what was done (removing silences) carry their
// own name instead; see ProjectEditor.

import '../model/look_filter.dart';
import '../model/project.dart';
import '../model/title_layout.dart';

/// The name of the edit that turned [before] into [after].
String describeEdit(Project before, Project after) {
  final clips = _describeClips(before.clips, after.clips);
  if (clips != null) return clips;
  final overlays = _describeOverlays(before.overlays, after.overlays);
  if (overlays != null) return overlays;
  final audio = _describeAudio(before, after);
  if (audio != null) return audio;
  final tracks = _describeTracks(before, after);
  if (tracks != null) return tracks;
  final titles = _describeTitles(before.titles, after.titles);
  if (titles != null) return titles;
  if (before.aspect != after.aspect) return 'Shape ${aspectName(after.aspect)}';
  if (before.videoSize != after.videoSize) {
    return 'Video size ${videoSizeName(after.videoSize)}';
  }
  if (before.fadeInMs != after.fadeInMs) {
    return after.fadeInMs == 0 ? 'No fade at the start' : 'Fade in from black';
  }
  if (before.fadeOutMs != after.fadeOutMs) {
    return after.fadeOutMs == 0 ? 'No fade at the end' : 'Fade out to black';
  }
  if (before.duckMusic != after.duckMusic) {
    return after.duckMusic
        ? 'Lower music under speech on'
        : 'Lower music under speech off';
  }
  if (before.name != after.name) return 'Renamed project';
  return 'Edit';
}

/// "9:16", "Original", ...
String aspectName(CanvasAspect a) => switch (a) {
      CanvasAspect.original => 'Original',
      CanvasAspect.portrait9x16 => '9:16',
      CanvasAspect.landscape16x9 => '16:9',
      CanvasAspect.square1x1 => '1:1',
      CanvasAspect.portrait4x5 => '4:5',
    };

/// "Match first clip", "720p", "1080p", "4K".
String videoSizeName(VideoSize s) => switch (s) {
      VideoSize.matchFirstClip => 'Match first clip',
      VideoSize.p720 => '720p',
      VideoSize.p1080 => '1080p',
      VideoSize.p2160 => '4K',
    };

/// "Picture-in-picture", "Side by side", ...
String overlayLayoutName(OverlayLayout l) => switch (l) {
      OverlayLayout.pip => 'Picture-in-picture',
      OverlayLayout.sideBySide => 'Side by side',
      OverlayLayout.topBottom => 'Top and bottom',
      OverlayLayout.full => 'Full screen',
      OverlayLayout.free => 'Free position',
    };

/// What changed in a picture's crop and position, or null.
String? framingChange(Framing a, Framing b) {
  if (a == b) return null;
  if (b.isDefault) return 'Crop and position reset';
  if (a.rotation != b.rotation) return 'Rotated';
  if (a.flipH != b.flipH || a.flipV != b.flipV) return 'Flipped';
  if (a.crop != b.crop) return 'Crop';
  return 'Position';
}

/// "1.25×", "0.5×", "2×".
String speedName(double s) {
  var t = s.toStringAsFixed(2);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$t×';
}

String _percent(double v) => '${(v * 100).round()}%';

/// A title's text as it is named in the list: first line, at most 20
/// characters.
String quoteText(String text) {
  var t = text.trim().split('\n').first.trim();
  if (t.length > 20) t = '${t.substring(0, 19).trimRight()}…';
  return "'$t'";
}

String _what(Clip c) => c.type == ClipType.photo ? 'photo' : 'clip';

String? _describeClips(List<Clip> before, List<Clip> after) {
  if (identical(before, after)) return null;
  final oldIds = {for (final c in before) c.id};
  final newIds = {for (final c in after) c.id};
  final added = [for (final c in after) if (!oldIds.contains(c.id)) c];
  final removed = [for (final c in before) if (!newIds.contains(c.id)) c];

  if (added.isNotEmpty || removed.isNotEmpty) {
    if (removed.isEmpty) {
      // A clip that got shorter next to new pieces of its own file: a cut.
      final photo = added.where((c) => c.type == ClipType.photo).toList();
      final cut = _splitClip(before, after);
      if (cut != null) {
        final n = after.indexWhere((c) => c.id == cut.id) + 1;
        if (photo.length == 1 && added.length == 2) {
          return 'Freeze frame on clip $n';
        }
        if (added.length == 1) return 'Split ${_what(cut)} $n';
        return 'Cut clip $n into ${added.length + 1} pieces';
      }
      if (added.length == 1) return 'Added ${_what(added.single)}';
      final photos = photo.length;
      if (photos == 0) return 'Added ${added.length} clips';
      if (photos == added.length) return 'Added ${added.length} photos';
      return 'Added ${added.length} clips and photos';
    }
    if (added.isEmpty) {
      if (removed.length == 1) {
        final n = before.indexOf(removed.single) + 1;
        return 'Deleted ${_what(removed.single)} $n';
      }
      return 'Deleted ${removed.length} clips';
    }
    return 'Changed clips';
  }

  // Same clips: moved?
  var sameOrder = before.length == after.length;
  for (var i = 0; sameOrder && i < before.length; i++) {
    if (before[i].id != after[i].id) sameOrder = false;
  }
  if (!sameOrder) return 'Moved clip';

  // Settings of one or more clips.
  final changed = <int>[];
  for (var i = 0; i < after.length; i++) {
    if (!identical(before[i], after[i]) && _clipDiffers(before[i], after[i])) {
      changed.add(i);
    }
  }
  if (changed.isEmpty) return null;
  final labels = <String>{
    for (final i in changed) _clipChange(before[i], after[i]),
  };
  // "Muted clip 2", but "Speed 2× on clip 2".
  const verbs = {'Muted', 'Unmuted', 'Trimmed', 'Rotated', 'Flipped'};
  if (changed.length == 1) {
    final l = labels.single;
    final which = '${_what(after[changed.single])} ${changed.single + 1}';
    if (l == 'Length') return 'Length of $which';
    return verbs.contains(l) ? '$l $which' : '$l on $which';
  }
  if (labels.length == 1) {
    final l = labels.single;
    return verbs.contains(l)
        ? '$l ${changed.length} clips'
        : '$l on ${changed.length} clips';
  }
  return 'Changed ${changed.length} clips';
}

bool _clipDiffers(Clip a, Clip b) {
  final ja = a.toJson(), jb = b.toJson();
  for (final k in ja.keys) {
    final x = ja[k], y = jb[k];
    if (x is List && y is List) {
      if (x.length != y.length) return true;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return true;
      }
    } else if (x != y) {
      return true;
    }
  }
  return false;
}

/// The clip of [before] that [after] has cut into pieces (same id, shorter,
/// with new clips of the same file next to it), or null.
Clip? _splitClip(List<Clip> before, List<Clip> after) {
  final oldIds = {for (final c in before) c.id};
  for (var i = 0; i < after.length; i++) {
    final c = after[i];
    if (!oldIds.contains(c.id)) continue;
    final old = before.firstWhere((b) => b.id == c.id);
    // A photo's length is its outMs - inMs as well.
    final shorter = (c.outMs - c.inMs) < (old.outMs - old.inMs);
    if (!shorter) continue;
    // New pieces of the same file (or a still) right after it.
    final next = i + 1 < after.length ? after[i + 1] : null;
    if (next != null &&
        !oldIds.contains(next.id) &&
        (next.path == c.path || next.type == ClipType.photo)) {
      return c;
    }
  }
  return null;
}

/// What changed on one clip, most telling first.
String _clipChange(Clip a, Clip b) {
  if (a.path != b.path) return 'Found file';
  if (a.speed != b.speed) return 'Speed ${speedName(b.speed)}';
  if (a.inMs != b.inMs || a.outMs != b.outMs) {
    return b.type == ClipType.photo ? 'Length' : 'Trimmed';
  }
  if (a.muted != b.muted) return b.muted ? 'Muted' : 'Unmuted';
  if (a.volume != b.volume) return 'Volume ${_percent(b.volume)}';
  if (a.denoise != b.denoise) {
    return b.denoise ? 'Clean up sound' : 'Clean up sound off';
  }
  if (a.voiceFocus != b.voiceFocus) {
    return b.voiceFocus < 0.005
        ? 'Voice focus off'
        : 'Voice focus ${_percent(b.voiceFocus)}';
  }
  if (a.audioTrack != b.audioTrack) return 'Sound track ${b.audioTrack + 1}';
  if (a.audioChannel != b.audioChannel) {
    return switch (b.audioChannel) {
      AudioChannel.both => 'Sound from both sides',
      AudioChannel.left => 'Sound from left only',
      AudioChannel.right => 'Sound from right only',
    };
  }
  if (a.transition != b.transition) {
    return switch (b.transition) {
      TransitionType.none => 'No transition',
      TransitionType.crossfade => 'Crossfade',
      TransitionType.fadeBlack => 'Fade through black',
      TransitionType.slideLeft => 'Slide left',
      TransitionType.slideUp => 'Slide up',
    };
  }
  if (a.transitionMs != b.transitionMs) return 'Transition length';
  if (a.fit != b.fit) {
    return switch (b.fit) {
      FitMode.fit => 'Fit',
      FitMode.fill => 'Fill',
      FitMode.blur => 'Blur background',
    };
  }
  if (a.zoom != b.zoom) return 'Zoom ${speedName(b.zoom)}';
  final framing = framingChange(a.framing, b.framing);
  if (framing != null) return framing;
  if (a.fadeInMs != b.fadeInMs) return b.fadeInMs == 0 ? 'No fade in' : 'Fade in';
  if (a.fadeOutMs != b.fadeOutMs) {
    return b.fadeOutMs == 0 ? 'No fade out' : 'Fade out';
  }
  if (a.filter != b.filter) {
    return b.filter == LookFilter.none
        ? 'No filter'
        : 'Filter ${lookFilterLabel(b.filter)}';
  }
  if (a.warmth != b.warmth) return 'Warmth';
  final look = [
    if (a.brightness != b.brightness) 'Brightness',
    if (a.contrast != b.contrast) 'Contrast',
    if (a.saturation != b.saturation) 'Saturation',
  ];
  if (look.length == 1) return look.single;
  if (look.isNotEmpty) return 'Look';
  if (a.audioStreams.length != b.audioStreams.length) {
    return 'Read sound tracks';
  }
  return 'Changed';
}

String? _describeAudio(Project pb, Project pa) {
  final before = pb.audio, after = pa.audio;
  if (identical(before, after)) return null;
  final oldIds = {for (final a in before) a.id};
  final newIds = {for (final a in after) a.id};
  final addedList = after.where((a) => !oldIds.contains(a.id)).toList();
  final removedList = before.where((a) => !newIds.contains(a.id)).toList();
  final added = addedList.length;
  final removed = removedList.length;
  String kind(AudioClip a) =>
      a.isVoice ? 'voice' : (a.isSeparated ? 'sound' : 'music');
  if (added > 0 && removed == 0) {
    if (added == 1) return 'Added ${kind(addedList.single)}';
    return 'Added $added ${kind(addedList.first)}';
  }
  if (removed > 0 && added == 0) return 'Deleted ${kind(removedList.first)}';
  if (added > 0) return 'Replaced music';
  for (final b in after) {
    final a = before.firstWhere((x) => x.id == b.id);
    if (identical(a, b)) continue;
    final what = kind(a);
    final whatUp = '${what[0].toUpperCase()}${what.substring(1)}';
    if (a.path != b.path) return 'Found $what file';
    if (a.trackId != b.trackId) {
      return 'Moved $what to ${_trackName(pa, b.trackId)}';
    }
    if (a.startMs != b.startMs && a.sourceSpanMs == b.sourceSpanMs) {
      return 'Moved $what';
    }
    if (a.looped != b.looped) {
      return b.looped ? 'Looped $what' : '$whatUp no longer loops';
    }
    if (a.inMs != b.inMs || a.outMs != b.outMs || a.loopMs != b.loopMs) {
      return 'Trimmed $what';
    }
    if (a.volume != b.volume) return '$whatUp volume ${_percent(b.volume)}';
    if (a.fadeInMs != b.fadeInMs) return '$whatUp fade in';
    if (a.fadeOutMs != b.fadeOutMs) return '$whatUp fade out';
    if (a.speed != b.speed) return 'Speed ${speedName(b.speed)} on $what';
    if (a.denoise != b.denoise) {
      return b.denoise ? 'Clean up $what' : 'Clean up $what off';
    }
    if (a.voiceFocus != b.voiceFocus) {
      return b.voiceFocus < 0.005
          ? 'Voice focus off on $what'
          : 'Voice focus ${_percent(b.voiceFocus)} on $what';
    }
    if (a.audioTrack != b.audioTrack || a.audioChannel != b.audioChannel) {
      return 'Sound source of $what';
    }
    if (a.linked != b.linked) return b.linked ? 'Linked $what' : 'Unlinked $what';
    if (a.audioStreams.length != b.audioStreams.length ||
        !a.audioStreams.every(b.audioStreams.contains)) {
      return 'Read sound tracks of $what';
    }
  }
  return null;
}

/// "Voice track", "the Music track".
String _trackName(Project p, String id) {
  final t = p.trackById(id);
  if (t == null) return 'another track';
  return '${t.name} track';
}

String? _describeTracks(Project pb, Project pa) {
  final vb = pb.videoSound, va = pa.videoSound;
  if (vb.muted != va.muted) {
    return va.muted ? 'Muted video sound' : 'Unmuted video sound';
  }
  if (vb.solo != va.solo) return va.solo ? 'Solo video sound' : 'Solo off';
  if (vb.volume != va.volume) return 'Video sound volume ${_percent(va.volume)}';
  final before = pb.soundTracks, after = pa.soundTracks;
  if (identical(before, after)) return null;
  final oldIds = {for (final t in before) t.id};
  final newIds = {for (final t in after) t.id};
  final added = [for (final t in after) if (!oldIds.contains(t.id)) t];
  final removed = [for (final t in before) if (!newIds.contains(t.id)) t];
  if (added.isNotEmpty && removed.isEmpty) {
    return added.length == 1
        ? 'Added sound track ${added.single.name}'
        : 'Added ${added.length} sound tracks';
  }
  if (removed.isNotEmpty && added.isEmpty) {
    return removed.length == 1
        ? 'Deleted sound track ${removed.single.name}'
        : 'Deleted ${removed.length} sound tracks';
  }
  if (added.isNotEmpty) return 'Changed sound tracks';
  for (final b in after) {
    final a = before.firstWhere((x) => x.id == b.id);
    if (a.name != b.name) return 'Renamed track to ${quoteText(b.name)}';
    final name = '${b.name} track';
    if (a.muted != b.muted) return b.muted ? 'Muted $name' : 'Unmuted $name';
    if (a.solo != b.solo) return b.solo ? 'Solo $name' : 'Solo off';
    if (a.volume != b.volume) return '$name volume ${_percent(b.volume)}';
    if (a.duck != b.duck) {
      return b.duck
          ? 'Lower ${b.name} under speech on'
          : 'Lower ${b.name} under speech off';
    }
    if (a.speech != b.speech) {
      return b.speech ? '$name counts as speech' : '$name not speech';
    }
  }
  var sameOrder = before.length == after.length;
  for (var i = 0; sameOrder && i < before.length; i++) {
    if (before[i].id != after[i].id) sameOrder = false;
  }
  if (!sameOrder) return 'Moved sound track';
  return null;
}

String? _describeTitles(List<TitleOverlay> before, List<TitleOverlay> after) {
  if (identical(before, after)) return null;
  final oldIds = {for (final t in before) t.id};
  final newIds = {for (final t in after) t.id};
  final added = [for (final t in after) if (!oldIds.contains(t.id)) t];
  final removed = [for (final t in before) if (!newIds.contains(t.id)) t];
  String kind(TitleOverlay t) => t.kind == TitleKind.caption ? 'caption' : 'title';
  if (added.isNotEmpty && removed.isEmpty) {
    if (added.length == 1) {
      return 'Added ${kind(added.single)} ${quoteText(added.single.text)}';
    }
    final captions = added.every((t) => t.kind == TitleKind.caption);
    return 'Added ${added.length} ${captions ? 'captions' : 'titles'}';
  }
  if (removed.isNotEmpty && added.isEmpty) {
    if (removed.length == 1) {
      return 'Deleted ${kind(removed.single)} ${quoteText(removed.single.text)}';
    }
    return 'Deleted ${removed.length} titles';
  }
  if (added.isNotEmpty) return 'Changed titles';
  for (final b in after) {
    final a = before.firstWhere((x) => x.id == b.id);
    if (identical(a, b)) continue;
    final name = '${kind(b)} ${quoteText(b.text)}';
    if (a.text != b.text) return 'Edited $name';
    // Alignment moves the text too, and outline / shadow are often set
    // together with a place: name the step after what was asked for
    // (1.9 called all of these "Moved title").
    if (a.align != b.align) return 'Lined up $name';
    if (a.outline != b.outline && a.colorArgb == b.colorArgb) {
      return b.outline ? 'Outline on $name' : 'No outline on $name';
    }
    if (a.x != b.x || a.y != b.y) return 'Moved $name';
    if (a.startMs != b.startMs || a.endMs != b.endMs) return 'Timing of $name';
    if (a.fontSize != b.fontSize) return 'Size of $name';
    if (a.kind != b.kind) return 'Changed $name';
    if (a.font != b.font) return 'Font ${titleFontLabel(b.font)} on $name';
    if (a.animIn != b.animIn) {
      return b.animIn == TitleAnimation.none
          ? 'No entry animation on $name'
          : '${titleAnimationLabel(b.animIn)} in on $name';
    }
    if (a.animOut != b.animOut) {
      return b.animOut == TitleAnimation.none
          ? 'No exit animation on $name'
          : '${titleAnimationLabel(b.animOut)} out on $name';
    }
    if (a.align != b.align) return 'Lined up $name';
    if (a.outline != b.outline && a.colorArgb == b.colorArgb) {
      return b.outline ? 'Outline on $name' : 'No outline on $name';
    }
    if (a.shadow != b.shadow && a.colorArgb == b.colorArgb) {
      return b.shadow ? 'Shadow on $name' : 'No shadow on $name';
    }
    return 'Styled $name';
  }
  return null;
}

String? _describeOverlays(List<OverlayClip> before, List<OverlayClip> after) {
  if (identical(before, after)) return null;
  final oldIds = {for (final o in before) o.id};
  final newIds = {for (final o in after) o.id};
  final added = [for (final o in after) if (!oldIds.contains(o.id)) o];
  final removed = [for (final o in before) if (!newIds.contains(o.id)) o];
  if (added.isNotEmpty && removed.isEmpty) {
    return added.length == 1 ? 'Added overlay' : 'Added ${added.length} overlays';
  }
  if (removed.isNotEmpty && added.isEmpty) {
    return removed.length == 1
        ? 'Deleted overlay'
        : 'Deleted ${removed.length} overlays';
  }
  if (added.isNotEmpty) return 'Changed overlays';
  for (final b in after) {
    final a = before.firstWhere((x) => x.id == b.id);
    if (identical(a, b)) continue;
    final ca = a.clip, cb = b.clip;
    if (ca.path != cb.path) return 'Found overlay file';
    if (ca.speed != cb.speed) return 'Speed ${speedName(cb.speed)} on overlay';
    if (a.startMs != b.startMs && ca.sourceSpanMs == cb.sourceSpanMs) {
      return 'Moved overlay';
    }
    if (ca.inMs != cb.inMs || ca.outMs != cb.outMs) {
      return cb.type == ClipType.photo ? 'Length of overlay' : 'Trimmed overlay';
    }
    if (ca.muted != cb.muted) return cb.muted ? 'Muted overlay' : 'Unmuted overlay';
    if (ca.volume != cb.volume) return 'Overlay volume ${_percent(cb.volume)}';
    if (a.fadeInMs != b.fadeInMs) return 'Overlay fade in';
    if (a.fadeOutMs != b.fadeOutMs) return 'Overlay fade out';
    if (a.layout != b.layout) return 'Overlay ${overlayLayoutName(b.layout)}';
    if (a.corner != b.corner) return 'Overlay corner';
    if (a.size != b.size) return 'Overlay size ${_percent(b.size)}';
    if (a.x != b.x || a.y != b.y) return 'Moved overlay on the picture';
    if (a.overlayFirst != b.overlayFirst) return 'Swapped sides of overlay';
    if (a.border != b.border) return b.border ? 'Overlay frame on' : 'Overlay frame off';
    final f = framingChange(ca.framing, cb.framing);
    if (f != null) {
      return switch (f) {
        'Rotated' => 'Rotated overlay',
        'Flipped' => 'Flipped overlay',
        _ => '$f on overlay',
      };
    }
    if (ca.audioTrack != cb.audioTrack || ca.audioChannel != cb.audioChannel) {
      return 'Sound source of overlay';
    }
    return 'Changed overlay';
  }
  return null;
}
