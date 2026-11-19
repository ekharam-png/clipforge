import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/editor/sound_tracks.dart';
import '../../core/model/project.dart';
import '../app_prefs.dart';
import '../app_settings.dart';
import '../help/help_screen.dart';
import '../settings/settings_screen.dart';
import 'acts.dart';
import 'clip_actions.dart';
import 'history_panel.dart';
import 'import_actions.dart';
import 'music_actions.dart';
import 'publishing_panel.dart';
import 'session.dart';
import 'shorts_actions.dart';
import 'sound_tracks_ui.dart' show addSoundTrack, separateSound;
import 'speech_actions.dart';
import 'text_panel.dart';
import 'tools.dart';
import 'voice_actions.dart' show addVoiceRecording, lineUpVoice;

export 'acts.dart';

// THE source of "can this be done now, and if not, why" (1.15). The menu
// bar, the side panel, the phone's bars and sheets and the timeline's
// context menu all ask here, so they never disagree, and a greyed-out item
// can say why everywhere.

/// What can be done in the open editor right now.
class EditorActions {
  EditorActions(this.s);
  final EditorSession s;

  Project get _p => s.project;
  bool get _has => _p.clips.isNotEmpty;

  Clip? get _settingsClip {
    final clip = s.selectedClip;
    if (clip != null) return clip;
    final under = s.clipIndexUnderPlayhead;
    return under >= 0 ? _p.clips[under] : null;
  }

  AudioClip? get _soundToPutBack {
    final p = _p;
    final selected = s.selectedAudio;
    if (selected != null &&
        selected.isSeparated &&
        p.clips.any((c) => c.id == selected.sourceClipId)) {
      return selected;
    }
    final clip = s.selectedClip;
    if (clip == null) return null;
    return p.audio
        .where((a) => a.isSeparated && a.sourceClipId == clip.id)
        .firstOrNull;
  }

  bool get hasSpeechStarts =>
      s.pictures.speakers.any((t) => t.stretches.isNotEmpty);

  /// The selected clip or overlay item: what "Crop and position" and
  /// "Rotate right" work on.
  String? get pictureId => s.selectedClip?.id ?? s.selectedOverlay?.id;

  static const _needVideo = 'add a video first';

  /// Why [a] cannot be done now; null when it can.
  String? whyNot(Act a) {
    final p = _p;
    final clip = s.selectedClip;
    final index = clip == null ? -1 : p.clips.indexOf(clip);
    final audio = s.selectedAudio;
    switch (a) {
      case Act.renameProject:
      case Act.publishingNotes:
      case Act.backToProjects:
      case Act.settings:
      case Act.history:
      case Act.findInText:
      case Act.addMedia:
      case Act.textWindow:
      case Act.zoomIn:
      case Act.zoomOut:
      case Act.snapping:
      case Act.soundWaves:
      case Act.shortcuts:
      case Act.shapeAndSize:
        return null;
      case Act.export:
      case Act.exportSeveral:
      case Act.addMusic:
      case Act.addTitle:
      case Act.addCaption:
      case Act.importSubtitles:
      case Act.addOverlay:
      case Act.markMoment:
      case Act.split:
      case Act.startAtPlayhead:
      case Act.endAtPlayhead:
      case Act.shortFromHere:
      case Act.goodMoments:
      case Act.fades:
        return _has ? null : _needVideo;
      case Act.exportSubtitles:
        return hasCaptions(p) ? null : 'no captions yet';
      case Act.undo:
        return s.editor.canUndo ? null : 'nothing to undo';
      case Act.redo:
        return s.editor.canRedo ? null : 'nothing to redo';
      case Act.duplicate:
        return clip != null || s.selectedTitle != null
            ? null
            : 'select a clip or a title';
      case Act.copySettings:
        return _settingsClip != null ? null : 'select a clip';
      case Act.pasteSettings:
        if (s.copiedSettings.value == null) return 'copy settings first';
        return _settingsClip != null ? null : 'select a clip';
      case Act.delete:
        return s.selection.value != null ? null : 'select something first';
      case Act.addVoice:
        return p.clips.any((c) => c.type == ClipType.video)
            ? null
            : _needVideo;
      case Act.freezeFrame:
        final under = s.clipIndexUnderPlayhead;
        return under >= 0 && p.clips[under].type == ClipType.video
            ? null
            : 'move the playhead onto a video clip';
      case Act.removeSilences:
        final c = _settingsClip;
        return c != null && c.type == ClipType.video && c.hasAudio
            ? null
            : 'select a video clip with sound';
      case Act.crop:
      case Act.rotateRight:
        return pictureId != null ? null : 'select a clip or an overlay';
      case Act.moveEarlier:
        if (clip == null) return 'select a clip';
        return index > 0 ? null : 'it is already the first clip';
      case Act.moveLater:
        if (clip == null) return 'select a clip';
        return index < p.clips.length - 1
            ? null
            : 'it is already the last clip';
      case Act.shortsFromMarkers:
        return p.markers.isNotEmpty ? null : 'no good moment markers yet';
      case Act.fitMusic:
        return audio != null && !audio.belongsToClip
            ? null
            : 'select a music clip';
      case Act.lineUpVoice:
        if (audio == null || audio.isSeparated) return 'select a sound';
        return p.clips.any((c) => c.type == ClipType.video)
            ? null
            : _needVideo;
      case Act.separateSound:
        if (clip == null) return 'select a video clip';
        final problem = EditorController.separateSoundProblem(p, clip.id);
        return problem == null ? null : _asReason(problem);
      case Act.putSoundBack:
        return _soundToPutBack != null ? null : 'select a separated sound';
      case Act.addSoundTrack:
        if (!_has) return _needVideo;
        return p.soundTracks.length < EditorController.maxSoundTracks
            ? null
            : 'there are already ${EditorController.maxSoundTracks} tracks';
      case Act.lowerMusic:
        return p.audio.isNotEmpty ? null : 'add music first';
      case Act.copyCredits:
        return p.audio.any((a) => a.credit != null)
            ? null
            : 'no music from the free music search';
      case Act.transcribe:
      case Act.captionsFromSpeech:
      case Act.removeFillers:
        if (s.speech == null) return 'on computers only';
        return canTranscribe(p) ? null : 'no sound with speech yet';
      case Act.autoCuts:
        if (s.speech == null) return 'on computers only';
        return p.autoCuts.isNotEmpty ? null : 'nothing was cut automatically';
      case Act.playPause:
        return s.playback.durationMs > 0 ? null : 'nothing to play yet';
      case Act.playBackwards:
      case Act.pause:
      case Act.playForwards:
      case Act.goToStart:
      case Act.goToEnd:
      case Act.previousFrame:
      case Act.nextFrame:
        return _has ? null : 'nothing to play yet';
      case Act.previousSpeech:
      case Act.nextSpeech:
        return hasSpeechStarts ? null : 'no speech found yet';
      case Act.editItem:
        return s.selection.value != null ? null : 'select something first';
    }
  }

  /// "A photo has no sound to separate." -> "a photo has no sound to
  /// separate".
  static String _asReason(String sentence) {
    var t = sentence.trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    return t.isEmpty ? t : '${t[0].toLowerCase()}${t.substring(1)}';
  }

  /// The state of the actions that are switches; null for the others.
  bool? checked(Act a) => switch (a) {
        Act.lowerMusic => lowerMusicState(_p) == LowerMusic.all,
        Act.textWindow => s.showText.value,
        Act.snapping => s.snapping.value,
        Act.soundWaves => s.showWaves.value,
        Act.history => null,
        _ => null,
      };

  /// "Lower music under speech" is on for some tracks only.
  bool mixed(Act a) =>
      a == Act.lowerMusic && lowerMusicState(_p) == LowerMusic.some;

  /// The label, which says more for a few actions ("Lower music under
  /// speech (some tracks)" is a state, not a reason).
  String label(Act a) => mixed(a)
      ? '${actLabel(a)} — on for some tracks'
      : actLabel(a);

  /// [a] as a list shows it; tapping runs it from [context] (the editor's
  /// own context, not a sheet's).
  ActionEntry entry(BuildContext context, Act a, {String? label}) {
    final reason = whyNot(a);
    return ActionEntry(
      act: a,
      label: label ?? this.label(a),
      icon: actIcon(a),
      reason: reason,
      checked: checked(a),
      mixed: mixed(a),
      danger: a == Act.delete,
      onTap: reason == null ? () => run(context, a) : null,
    );
  }

  /// Does [a]. Nothing happens when it cannot be done now.
  void run(BuildContext context, Act a) {
    if (!context.mounted || s.isDisposed || whyNot(a) != null) return;
    final p = _p;
    final hooks = s.hooks;
    final clip = s.selectedClip;
    final index = clip == null ? -1 : p.clips.indexOf(clip);
    void step(int by) {
      hooks?.stopReverse();
      s.playback.pause();
      s.playback.seek(s.playback.positionMs + by);
    }

    switch (a) {
      case Act.renameProject:
        hooks?.rename();
      case Act.publishingNotes:
        openPublishingNotes(context, s);
      case Act.backToProjects:
        hooks?.backToProjects();
      case Act.export:
        hooks?.export();
      case Act.exportSeveral:
        hooks?.export(several: true);
      case Act.exportSubtitles:
        exportSubtitles(context, s);
      case Act.settings:
        s.playback.pause();
        openSettings(context);
      case Act.undo:
        s.editor.undo();
      case Act.redo:
        s.editor.redo();
      case Act.history:
        toggleHistory(context, s);
      case Act.duplicate:
        duplicateSelection(context, s);
      case Act.copySettings:
        copyClipSettings(context, s);
      case Act.pasteSettings:
        pasteClipSettings(context, s);
      case Act.delete:
        deleteSelection(s);
      case Act.findInText:
        findInTextWindow(context, s);
      case Act.addMedia:
        addMedia(context, s);
      case Act.addMusic:
        showAddMusic(context, s);
      case Act.addVoice:
        addVoiceRecording(context, s);
      case Act.addTitle:
        addTitle(s);
        if (isNarrow(context)) showPropertiesSheet(context, s);
      case Act.addCaption:
        showCaptionsDialog(context, s);
      case Act.importSubtitles:
        importSubtitles(context, s);
      case Act.addOverlay:
        addOverlay(context, s);
      case Act.markMoment:
        markGoodMoment(context, s);
      case Act.split:
        splitAtPlayhead(context, s);
      case Act.startAtPlayhead:
      case Act.endAtPlayhead:
        hooks?.stopReverse();
        s.playback.pause();
        trimToPlayhead(context, s, start: a == Act.startAtPlayhead);
      case Act.freezeFrame:
        freezeFrame(context, s);
      case Act.removeSilences:
        removeSilences(context, s, _settingsClip!);
      case Act.crop:
        openCrop(context, s);
      case Act.rotateRight:
        final id = pictureId;
        if (id != null) s.editor.rotatePicture(id);
      case Act.moveEarlier:
        s.editor.moveClip(index, index - 1);
      case Act.moveLater:
        s.editor.moveClip(index, index + 1);
      case Act.shortFromHere:
        makeShortFromHere(context, s);
      case Act.shortsFromMarkers:
        makeShortsFromMarkers(context, s);
      case Act.goodMoments:
        showGoodMoments(context, s);
      case Act.fitMusic:
        fitMusic(context, s, s.selectedAudio!.id);
      case Act.lineUpVoice:
        lineUpVoice(context, s, s.selectedAudio!.id);
      case Act.separateSound:
        separateSound(context, s, clip!);
      case Act.putSoundBack:
        s.editor.reattachSound(_soundToPutBack!.id);
      case Act.addSoundTrack:
        addSoundTrack(context, s);
      case Act.lowerMusic:
        // All on -> off; none or some -> on for every music track.
        s.editor.setDuckMusic(lowerMusicState(p) != LowerMusic.all);
      case Act.copyCredits:
        copyMusicCredits(context, s);
      case Act.textWindow:
        toggleTextWindow(context, s);
      case Act.transcribe:
        showTranscribeDialog(context, s, clip: clip);
      case Act.captionsFromSpeech:
        captionsFromSpeech(context, s);
      case Act.removeFillers:
        removeFillerWords(context, s);
      case Act.autoCuts:
        showAutoCuts(context, s);
      case Act.zoomIn:
        s.setZoom(s.zoom.value * 1.5);
      case Act.zoomOut:
        s.setZoom(s.zoom.value / 1.5);
      case Act.snapping:
        final on = !s.snapping.value;
        hooks == null ? s.snapping.value = on : hooks.setSnapping(on);
      case Act.soundWaves:
        final on = !s.showWaves.value;
        if (hooks == null) {
          s.showWaves.value = on;
          s.pictures.enabled = on;
        } else {
          hooks.setSoundWaves(on);
        }
      case Act.playPause:
        hooks?.stopReverse();
        s.playback.toggle();
      case Act.playBackwards:
        hooks?.playBackwards();
      case Act.pause:
        hooks?.stopReverse();
        s.playback.pause();
      case Act.playForwards:
        hooks?.stopReverse();
        if (!s.playback.playing) s.playback.toggle();
      case Act.goToStart:
        hooks?.stopReverse();
        s.playback.seek(0);
      case Act.goToEnd:
        hooks?.stopReverse();
        s.playback.seek(s.playback.durationMs);
      case Act.previousFrame:
        step(-frameStepFor(s));
      case Act.nextFrame:
        step(frameStepFor(s));
      case Act.previousSpeech:
        hooks?.stopReverse();
        s.goToSpeechStart(forward: false);
      case Act.nextSpeech:
        hooks?.stopReverse();
        s.goToSpeechStart(forward: true);
      case Act.shortcuts:
        showHelpArticle(context, 'keyboard-shortcuts');
      case Act.shapeAndSize:
        showShapeAndSizeSheet(context, s);
      case Act.fades:
        showFadesSheet(context, s);
      case Act.editItem:
        openItemSettings(context, s);
    }
  }
}

/// One step of the Left / Right keys: one frame of the clip under the
/// playhead (its source frame rate, speed included), else 33 ms (a frame
/// at 30 fps) when that is not known (photos, clips added before 1.7).
int frameStepFor(EditorSession s) {
  const fallback = 33;
  final p = s.project;
  final t = s.playback.positionMs;
  final i = t < p.durationMs ? p.clipIndexAt(t) : p.clips.length - 1;
  if (i < 0) return fallback;
  final c = p.clips[i];
  if (c.type != ClipType.video || c.frameRate <= 1) return fallback;
  final ms = (1000 / c.frameRate / (c.speed <= 0 ? 1 : c.speed)).round();
  return ms < 1 ? 1 : ms;
}

/// The window is too narrow for the side panel (phones): settings open as
/// sheets.
bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kWideLayoutWidth;

/// Deletes what is selected on the timeline (Delete key, menus). False
/// when nothing is.
bool deleteSelection(EditorSession s) {
  // Several captions selected in the Text window go together.
  if (s.textDeleteHook?.call() ?? false) return true;
  final selection = s.selection.value;
  if (selection == null) return false;
  switch (selection.kind) {
    case ItemKind.clip:
      s.editor.removeClip(selection.id);
    case ItemKind.audio:
      s.editor.removeAudio(selection.id);
    case ItemKind.title:
      s.editor.removeTitle(selection.id);
    case ItemKind.overlay:
      s.editor.removeOverlay(selection.id);
  }
  return true;
}

AppPrefs? _prefsOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(context, listen: false)
        .read(appPrefsProvider);
  } catch (_) {
    return null;
  }
}

void _noteTextOpened(BuildContext context) {
  _prefsOf(context)?.setFlag(kTextOpenedFlag).catchError((Object _) {});
}

/// Shows or hides the Text window; in a narrow window (and on phones) it
/// opens as a full-screen sheet instead.
void toggleTextWindow(BuildContext context, EditorSession s) {
  _noteTextOpened(context);
  if (isNarrow(context)) {
    showTextSheet(context, s);
  } else {
    s.showText.value = !s.showText.value;
  }
}

/// Ctrl/Cmd+F: the Text window's search box (opening the window first).
void findInTextWindow(BuildContext context, EditorSession s) {
  _noteTextOpened(context);
  if (isNarrow(context)) {
    showTextSheet(context, s);
  } else {
    s.showText.value = true;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!s.isDisposed) s.findInText.value++;
  });
}

/// Shows or hides the History column (wide windows) or opens the History
/// sheet (phones).
void toggleHistory(BuildContext context, EditorSession s) {
  if (isNarrow(context)) {
    showHistorySheet(context, s);
  } else {
    s.showHistory.value = !s.showHistory.value;
  }
}

/// "Crop and position…": the Crop section of the side panel, or the crop
/// sheet when the window is too narrow for the panel.
void openCrop(BuildContext context, EditorSession s) {
  final id = s.selectedClip?.id ?? s.selectedOverlay?.id;
  if (id == null) return;
  if (!isNarrow(context)) {
    s.openTool.value = ClipTool.crop;
  } else {
    final scaffold = s.hooks?.scaffold?.call();
    showCropSheet(context, s, id,
        scaffold: scaffold is ScaffoldState ? scaffold : null);
  }
}

/// "Publishing notes" (File menu, the project menu on phones, the Project
/// panel).
void openPublishingNotes(BuildContext context, EditorSession s) {
  s.playback.pause();
  showPublishingNotes(context,
      project: () => s.project,
      onChanged: s.editor.setPublishingNotes,
      turns: () => s.speakerTurnsNow);
}

/// The settings of what is selected: a sheet on phones; on computers they
/// are already in the side panel.
void openItemSettings(BuildContext context, EditorSession s) {
  if (!isNarrow(context)) return;
  if (s.selectedClip != null) {
    showClipToolSheet(context, s, ClipTool.look);
  } else if (s.selectedOverlay != null) {
    showOverlayToolSheet(context, s, ClipTool.layout);
  } else if (s.selection.value != null) {
    showPropertiesSheet(context, s);
  }
}
