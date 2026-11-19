import 'package:material_ui/material_ui.dart';

// Every action the editor offers, by name (1.15). The menu bar, the side
// panel, the phone's bars and sheets and the timeline's context menu all
// show actions from this one list, with the same words and the same icon;
// whether one can be done now, and why not, comes from one place too
// (EditorActions in editor_actions.dart).

/// One action as a list shows it.
@immutable
class ActionEntry {
  const ActionEntry({
    required this.act,
    required this.label,
    required this.icon,
    this.reason,
    this.checked,
    this.mixed = false,
    this.onTap,
    this.danger = false,
  });
  final Act act;
  final String label;
  final IconData icon;

  /// Why it cannot be done now (short, lower case, no full stop); null
  /// when it can.
  final String? reason;

  /// Null for a plain action; the state of a switch otherwise.
  final bool? checked;

  /// A switch that is on for some and off for others ("Lower music under
  /// speech" set per track).
  final bool mixed;
  final VoidCallback? onTap;
  final bool danger;

  bool get enabled => reason == null;

  /// "Fit music to video (select a music clip)" while it cannot be done.
  String get labelWithReason => reason == null ? label : '$label ($reason)';
}

enum Act {
  // File
  renameProject,
  publishingNotes,
  backToProjects,
  export,
  exportSeveral,
  exportSubtitles,
  settings,
  // Edit
  undo,
  redo,
  history,
  duplicate,
  copySettings,
  pasteSettings,
  delete,
  findInText,
  // Add
  addMedia,
  addMusic,
  addVoice,
  addTitle,
  addCaption,
  importSubtitles,
  addOverlay,
  markMoment,
  // Clip
  split,
  startAtPlayhead,
  endAtPlayhead,
  freezeFrame,
  removeSilences,
  crop,
  rotateRight,
  moveEarlier,
  moveLater,
  shortFromHere,
  shortsFromMarkers,
  goodMoments,
  // Sound
  fitMusic,
  lineUpVoice,
  separateSound,
  putSoundBack,
  addSoundTrack,
  lowerMusic,
  copyCredits,
  // Text and speech
  textWindow,
  transcribe,
  captionsFromSpeech,
  removeFillers,
  autoCuts,
  // View
  zoomIn,
  zoomOut,
  snapping,
  soundWaves,
  // Playback
  playPause,
  playBackwards,
  pause,
  playForwards,
  goToStart,
  goToEnd,
  previousFrame,
  nextFrame,
  previousSpeech,
  nextSpeech,
  // Help (in the editor)
  shortcuts,
  // Phones: the project menu
  shapeAndSize,
  fades,
  // The settings of the selection (phones: a sheet; computers: the panel)
  editItem,
}

/// The words for [a], the same everywhere.
String actLabel(Act a) => switch (a) {
      Act.renameProject => 'Rename project…',
      Act.publishingNotes => 'Publishing notes…',
      Act.backToProjects => 'Back to projects',
      Act.export => 'Export…',
      Act.exportSeveral => 'Export several…',
      Act.exportSubtitles => 'Export subtitles (.srt)…',
      Act.settings => 'Settings…',
      Act.undo => 'Undo',
      Act.redo => 'Redo',
      Act.history => 'History',
      Act.duplicate => 'Duplicate',
      Act.copySettings => 'Copy settings',
      Act.pasteSettings => 'Paste settings',
      Act.delete => 'Delete',
      Act.findInText => 'Find in the text…',
      Act.addMedia => 'Videos or photos…',
      Act.addMusic => 'Music or sound…',
      Act.addVoice => 'Voice recording…',
      Act.addTitle => 'Title',
      Act.addCaption => 'Caption…',
      Act.importSubtitles => 'Subtitle file (.srt)…',
      Act.addOverlay => 'Overlay video or photo…',
      Act.markMoment => 'Good moment marker',
      Act.split => 'Split',
      Act.startAtPlayhead => 'Start at playhead',
      Act.endAtPlayhead => 'End at playhead',
      Act.freezeFrame => 'Freeze frame',
      Act.removeSilences => 'Remove silences…',
      Act.crop => 'Crop and position…',
      Act.rotateRight => 'Rotate right',
      Act.moveEarlier => 'Move earlier',
      Act.moveLater => 'Move later',
      Act.shortFromHere => 'Make a short from here…',
      Act.shortsFromMarkers => 'Make shorts from markers…',
      Act.goodMoments => 'Good moments…',
      Act.fitMusic => 'Fit music to video',
      Act.lineUpVoice => 'Line up voice with video',
      Act.separateSound => 'Separate sound…',
      Act.putSoundBack => 'Put sound back',
      Act.addSoundTrack => 'Add sound track',
      Act.lowerMusic => 'Lower music under speech',
      Act.copyCredits => 'Copy music credits',
      Act.textWindow => 'Text window',
      Act.transcribe => 'Transcribe speech…',
      Act.captionsFromSpeech => 'Captions from speech…',
      Act.removeFillers => 'Remove filler words…',
      Act.autoCuts => 'Automatic cuts…',
      Act.zoomIn => 'Zoom in',
      Act.zoomOut => 'Zoom out',
      Act.snapping => 'Snap to playhead and edges',
      Act.soundWaves => 'Show sound waves',
      Act.playPause => 'Play/Pause',
      Act.playBackwards => 'Play backwards',
      Act.pause => 'Pause',
      Act.playForwards => 'Play forwards',
      Act.goToStart => 'Go to start',
      Act.goToEnd => 'Go to end',
      Act.previousFrame => 'Previous frame',
      Act.nextFrame => 'Next frame',
      Act.previousSpeech => 'Previous speech start',
      Act.nextSpeech => 'Next speech start',
      Act.shortcuts => 'Keyboard shortcuts',
      Act.shapeAndSize => 'Shape and size',
      Act.fades => 'Fade in and out',
      Act.editItem => 'Edit',
    };

/// The label without the "…" (buttons, headings).
String actName(Act a) {
  final l = actLabel(a);
  return l.endsWith('…') ? l.substring(0, l.length - 1) : l;
}

IconData actIcon(Act a) => switch (a) {
      Act.renameProject => Icons.drive_file_rename_outline,
      Act.publishingNotes => Icons.notes,
      Act.backToProjects => Icons.arrow_back,
      Act.export || Act.exportSeveral => Icons.ios_share,
      Act.exportSubtitles => Icons.subtitles_outlined,
      Act.settings => Icons.settings_outlined,
      Act.undo => Icons.undo,
      Act.redo => Icons.redo,
      Act.history => Icons.history,
      Act.duplicate => Icons.copy_all_outlined,
      Act.copySettings => Icons.content_copy,
      Act.pasteSettings => Icons.content_paste,
      Act.delete => Icons.delete_outline,
      Act.findInText => Icons.search,
      Act.addMedia => Icons.add_photo_alternate_outlined,
      Act.addMusic => Icons.library_music_outlined,
      Act.addVoice => Icons.record_voice_over_outlined,
      Act.addTitle => Icons.title,
      Act.addCaption => Icons.closed_caption_outlined,
      Act.importSubtitles => Icons.subtitles_outlined,
      Act.addOverlay => Icons.picture_in_picture_alt,
      Act.markMoment => Icons.flag_outlined,
      Act.split => Icons.content_cut,
      Act.startAtPlayhead => Icons.first_page,
      Act.endAtPlayhead => Icons.last_page,
      Act.freezeFrame => Icons.ac_unit,
      Act.removeSilences => Icons.volume_off_outlined,
      Act.crop => Icons.crop,
      Act.rotateRight => Icons.rotate_right,
      Act.moveEarlier => Icons.arrow_back,
      Act.moveLater => Icons.arrow_forward,
      Act.shortFromHere || Act.shortsFromMarkers => Icons.smartphone,
      Act.goodMoments => Icons.flag,
      Act.fitMusic => Icons.fit_screen_outlined,
      Act.lineUpVoice => Icons.record_voice_over,
      Act.separateSound => Icons.call_split,
      Act.putSoundBack => Icons.call_merge,
      Act.addSoundTrack => Icons.playlist_add,
      Act.lowerMusic => Icons.volume_down_outlined,
      Act.copyCredits => Icons.copyright,
      Act.textWindow => Icons.subject,
      Act.transcribe => Icons.hearing,
      Act.captionsFromSpeech => Icons.closed_caption_outlined,
      Act.removeFillers => Icons.cleaning_services_outlined,
      Act.autoCuts => Icons.auto_fix_high,
      Act.zoomIn => Icons.zoom_in,
      Act.zoomOut => Icons.zoom_out,
      Act.snapping => Icons.vertical_align_center,
      Act.soundWaves => Icons.graphic_eq,
      Act.playPause || Act.playForwards => Icons.play_arrow,
      Act.playBackwards => Icons.fast_rewind,
      Act.pause => Icons.pause,
      Act.goToStart => Icons.skip_previous,
      Act.goToEnd => Icons.skip_next,
      Act.previousFrame => Icons.chevron_left,
      Act.nextFrame => Icons.chevron_right,
      Act.previousSpeech => Icons.keyboard_double_arrow_left,
      Act.nextSpeech => Icons.keyboard_double_arrow_right,
      Act.shortcuts => Icons.keyboard_outlined,
      Act.shapeAndSize => Icons.aspect_ratio,
      Act.fades => Icons.gradient,
      Act.editItem => Icons.edit_outlined,
    };

/// A one-line hint for lists that have room for one (phone sheets).
String? actHint(Act a) => switch (a) {
      Act.addMedia => 'On the main track, after the clip you are on',
      Act.addMusic => 'From your files or the free music search',
      Act.addVoice => 'A voice recorded separately, lined up by its sound',
      Act.addTitle => 'Text over the picture, at the playhead',
      Act.addCaption => 'A line of text at the bottom of the picture',
      Act.importSubtitles => 'Captions from a subtitle file',
      Act.addOverlay => 'A video or photo over the picture',
      Act.markMoment => 'A flag here, to make a short around later',
      Act.startAtPlayhead => 'The clip starts where the playhead is',
      Act.endAtPlayhead => 'The clip ends where the playhead is',
      Act.freezeFrame => 'Hold the picture at the playhead',
      Act.removeSilences => 'Cut the pauses out of this clip',
      Act.crop => 'Crop, rotate, flip, choose what stays in the frame',
      Act.duplicate => 'A copy right after this one',
      Act.copySettings => 'Look, speed, sound, crop and fit',
      Act.pasteSettings => 'Give this clip the copied settings',
      Act.history => 'Your changes; go back to any of them',
      Act.textWindow => 'Read and search everything said or written',
      Act.publishingNotes => 'Title, description, hashtags, chapters',
      Act.goodMoments => 'Your markers; make shorts from them',
      Act.shapeAndSize => 'Upright, wide or square; 720p to 4K',
      Act.fades => 'Start from black, end in black',
      Act.settings => 'Snapping, sound waves, suggestions, updates',
      Act.fitMusic => 'Loop or shorten it to the length of the video',
      Act.lineUpVoice => 'Find where it belongs by its sound',
      Act.lowerMusic => 'Music gets quieter while someone talks',
      Act.separateSound => "The clip's sound as its own block",
      _ => null,
    };
