import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/model/project.dart';
import '../../core/model/title_layout.dart';
import '../../core/subtitles/srt.dart';
import '../file_drop.dart';
import '../format.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../media/media_api.dart';
import '../../media/media_common.dart' show ProbeTimeout, probeWithin;
import 'session.dart';
import 'voice_actions.dart';

const _uuid = Uuid();

/// The line a busy window shows when reading a file takes long.
const String kSlowReadNote =
    'This is taking longer than usual. You can wait, or cancel and try '
    'again with the file copied to this computer.';

/// What is said about [name] when reading it failed with [e].
String readProblem(Object e, String name) =>
    e is ProbeTimeout ? e.message : '$name — the file could not be read';

/// The probe every "add a file" path uses: with a time limit
/// ([kProbeTimeout]), so "Adding file…" always ends.
Future<MediaInfo> readMedia(EditorSession session, String path) =>
    probeWithin(session.engine, path, timeout: session.probeTimeout);

/// How long a newly added photo stays on screen.
const int kDefaultPhotoMs = 3000;

/// How long a newly added title stays on screen.
const int kDefaultTitleMs = 3000;

/// How long a caption typed in by hand stays on screen.
const int kDefaultCaptionMs = 2500;

/// Fade-out a newly added piece of music gets, so it does not stop dead.
const int kDefaultMusicFadeOutMs = kMusicFadeOutMs;

/// Text of a newly added title; typing replaces it.
const String kDefaultTitleText = 'Title';

/// True when a picture of [width] x [height] has another shape than the
/// project's frame, so that it would get bars.
bool _shapeDiffers(Project project, int width, int height) {
  // An empty project with the "Original" shape takes its shape from the
  // first clip.
  if (project.clips.isEmpty && project.aspect.ratio == null) return false;
  if (width <= 0 || height <= 0) return false;
  final canvas = project.canvasSize;
  final a = width / height;
  final b = canvas.width / canvas.height;
  return (a - b).abs() / b > 0.02;
}

/// Lets the user pick videos and photos and puts them on the main track as
/// one undo step: after the selected clip, or at the end of the video when
/// none is selected ([EditorSession.insertIndex]). The first new clip is
/// then shown, so it is clear where they went. When they went in after a
/// selected clip, the last new clip becomes the selection, so that adding
/// more keeps them in the order they were added.
Future<void> addMedia(BuildContext context, EditorSession session) async {
  final List<PickedFile> picked;
  try {
    picked = await session.files.pickMedia();
  } catch (e) {
    if (context.mounted) _showProblems(context, ['Could not open the file picker ($e)']);
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final problems = await addMediaFiles(context, session, picked);
  if (problems.isNotEmpty && context.mounted) _showProblems(context, problems);
  if (context.mounted) _sayPickWarnings(context, picked);
}

/// Puts the videos and photos [picked] on the main track like [addMedia]
/// (at [atIndex] when given, e.g. where they were dropped on the timeline).
/// Returns one line per file that could not be added.
Future<List<String>> addMediaFiles(
    BuildContext context, EditorSession session, List<PickedFile> picked,
    {int? atIndex}) async {
  final clips = <Clip>[];
  final problems = <String>[];
  // Sound files picked here (a voice recording next to its video) are
  // asked about once the videos are in.
  final sounds = <PickedFile>[];
  final cancel = BusyCancel();
  final done = await whileBusy(context, 'Adding ${picked.length == 1 ? 'file' : '${picked.length} files'}…', cancel: cancel, slowNote: kSlowReadNote, () async {
    for (final file in picked) {
      if (cancel.cancelled) return;
      try {
        final info = await readMedia(session, file.path);
        if (info.width <= 0 && info.height <= 0 && !info.hasVideo &&
            info.hasAudio && info.durationMs > 0 && !isImagePath(file.path)) {
          sounds.add(file);
          continue;
        }
        if (info.width <= 0 || info.height <= 0) {
          problems.add('${file.name} — not a video or photo');
          continue;
        }
        if (isImagePath(file.path)) {
          clips.add(Clip(
            id: _uuid.v4(),
            type: ClipType.photo,
            path: file.path,
            sourceDurationMs: 0,
            inMs: 0,
            outMs: kDefaultPhotoMs,
            width: info.width,
            height: info.height,
            hasAudio: false,
            // A photo of another shape looks better on a blurred copy of
            // itself than between black bars.
            fit: _shapeDiffers(session.project, info.width, info.height)
                ? FitMode.blur
                : FitMode.fit,
          ));
        } else if (!info.hasVideo || info.durationMs <= 0) {
          problems.add('${file.name} — no video found in this file');
        } else {
          clips.add(Clip(
            id: _uuid.v4(),
            type: ClipType.video,
            path: file.path,
            sourceDurationMs: info.durationMs,
            inMs: 0,
            outMs: info.durationMs,
            width: info.width,
            height: info.height,
            hasAudio: info.hasAudio,
            audioStreams: info.audioStreams,
            frameRate: info.fps,
          ));
        }
      } catch (e) {
        problems.add(readProblem(e, file.name));
      }
    }
  });
  // Cancelled: nothing is added, also not what was read before.
  if (!done || session.isDisposed) return const [];

  if (clips.isNotEmpty) {
    final afterSelection = atIndex == null && session.selectedClip != null;
    var index = atIndex == null
        ? session.insertIndex
        : atIndex.clamp(0, session.project.clips.length);
    session.editor.transaction(() {
      for (final clip in clips) {
        session.editor.addClip(clip, index: index++);
      }
    });
    if (afterSelection &&
        session.project.clips.any((c) => c.id == clips.last.id)) {
      session.select(ItemKind.clip, clips.last.id);
    }
    session.showClip(clips.first.id);
  }
  if (sounds.isNotEmpty && context.mounted) {
    problems.addAll(await addSoundFiles(context, session, sounds));
  }
  return problems;
}

/// Lets the user pick music and places it at the playhead.
Future<void> addMusic(BuildContext context, EditorSession session) async {
  final List<PickedFile> picked;
  try {
    picked = await session.files.pickAudio();
  } catch (e) {
    if (context.mounted) _showProblems(context, ['Could not open the file picker ($e)']);
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final problems = await addMusicFiles(context, session, picked);
  if (problems.isNotEmpty && context.mounted) _showProblems(context, problems);
  if (context.mounted) _sayPickWarnings(context, picked);
}

/// Adds the sound files [picked]. The user's own files are asked about
/// first ("What is this sound?": voice for the video / music / sound
/// effect, see voice_actions.dart); music from the free music search
/// ([credits]) goes straight to the playhead as music. Returns one line per
/// file that could not be added.
Future<List<String>> addMusicFiles(
    BuildContext context, EditorSession session, List<PickedFile> picked,
    {Map<String, MusicCredit> credits = const {}}) async {
  if (credits.isEmpty) return addSoundFiles(context, session, picked);
  final files = <SoundFile>[];
  final problems = <String>[];
  final cancel = BusyCancel();
  final done = await whileBusy(context, 'Adding music…', cancel: cancel, slowNote: kSlowReadNote, () async {
    for (final file in picked) {
      if (cancel.cancelled) return;
      try {
        final info = await readMedia(session, file.path);
        if (!info.hasAudio || info.durationMs <= 0) {
          problems.add('${file.name} — no sound found in this file');
          continue;
        }
        files.add(SoundFile(file, info));
      } catch (e) {
        problems.add(readProblem(e, file.name));
      }
    }
  });
  if (!done || session.isDisposed) return const [];
  placeSounds(session, files, credits: credits);
  return problems;
}

/// Adds files dragged onto the editor from the desktop: videos and photos
/// to the main track (at [atIndex], the place on the timeline they were
/// dropped on, else after the selected clip, else at the end), music at
/// the playhead, `.srt` files as captions. Files that cannot be used are
/// listed in one message, together with files that could not be read.
Future<void> addDroppedFiles(
    BuildContext context, EditorSession session, FileDrop drop,
    {int? atIndex}) async {
  final sorted = SortedDrop(drop);
  final problems = <String>[
    ...sorted.unsupportedLines,
    for (final f in sorted.projects)
      '${f.name} — a project file: open it from the project list '
          '(drop it there)',
  ];
  PickedFile picked(DroppedFile f) => PickedFile(f.path, f.name);
  if (sorted.media.isNotEmpty && context.mounted) {
    problems.addAll(await addMediaFiles(
        context, session, [for (final f in sorted.media) picked(f)],
        atIndex: atIndex));
  }
  if (sorted.music.isNotEmpty && context.mounted) {
    problems.addAll(await addMusicFiles(
        context, session, [for (final f in sorted.music) picked(f)]));
  }
  for (final f in sorted.subtitles) {
    if (!context.mounted) return;
    await _importSubtitlesFrom(context, session, f.path);
  }
  if (!context.mounted) return;
  final note = sorted.folderNote;
  if (problems.isNotEmpty) {
    _showProblems(context, problems,
        footer: problems.length > sorted.projects.length
            ? 'ClipForge takes videos, photos, music and subtitle (.srt) '
                'files.${note == null ? '' : ' $note'}'
            : note);
  } else if (note != null && sorted.subtitles.isEmpty) {
    _say(context, note);
  }
}

/// Where something [lengthMs] long that is added at the playhead starts:
/// at the playhead, or early enough to be seen before the video ends.
int _startAtPlayhead(EditorSession session, int lengthMs) {
  final end = session.project.durationMs;
  var start = session.playback.positionMs;
  if (start + lengthMs > end) start = end - lengthMs;
  return start < 0 ? 0 : start;
}

/// Adds a title at the playhead and selects it.
void addTitle(EditorSession session) {
  final start = _startAtPlayhead(session, kDefaultTitleMs);
  final id = _uuid.v4();
  session.editor.addTitle(TitleOverlay(
    id: id,
    text: kDefaultTitleText,
    startMs: start,
    endMs: start + kDefaultTitleMs,
  ));
  if (session.project.titles.any((t) => t.id == id)) {
    session.select(ItemKind.title, id);
  }
}

/// Adds a one-line caption at the playhead and selects it. Returns false
/// when [text] is empty.
bool addCaption(EditorSession session, String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.isEmpty) return false;
  final start = _startAtPlayhead(session, kDefaultCaptionMs);
  final id = _uuid.v4();
  session.editor.addTitle(captionStyle(TitleOverlay(
    id: id,
    text: line,
    startMs: start,
    endMs: start + kDefaultCaptionMs,
  )));
  if (session.project.titles.any((t) => t.id == id)) {
    session.select(ItemKind.title, id);
  }
  return true;
}

bool hasCaptions(Project project) =>
    project.titles.any((t) => t.kind == TitleKind.caption);

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Reads a SubRip file and adds its lines as captions, as one undo step.
Future<void> importSubtitles(BuildContext context, EditorSession session) async {
  final PickedFile? file;
  try {
    file = await session.documents.pickFile(const ['srt']);
  } catch (e) {
    if (context.mounted) _say(context, 'The subtitle file could not be read ($e)');
    return;
  }
  if (file == null || !context.mounted) return;
  await _importSubtitlesFrom(context, session, file.path);
}

Future<void> _importSubtitlesFrom(
    BuildContext context, EditorSession session, String path) async {
  final List<TitleOverlay> captions;
  try {
    captions =
        parseSrt(await session.documents.readText(path), newId: _uuid.v4);
  } catch (e) {
    if (context.mounted) _say(context, 'The subtitle file could not be read ($e)');
    return;
  }
  if (!context.mounted) return;
  if (captions.isEmpty) {
    _say(context, 'No captions were found in that file.');
    return;
  }
  session.editor.addTitles(captions);
  final end = session.project.durationMs;
  final late = captions.where((c) => c.startMs >= end).length;
  _say(
      context,
      'Added ${captions.length == 1 ? '1 caption' : '${captions.length} captions'}'
      '${late > 0 ? ' ($late after the end of the video)' : ''}.');
}

/// Writes the project's captions to a SubRip file the user chooses.
Future<void> exportSubtitles(BuildContext context, EditorSession session) async {
  final text = toSrt(session.project.titles);
  if (text.isEmpty) {
    _say(context, 'There are no captions to export yet.');
    return;
  }
  try {
    final where = await session.documents
        .saveText('${safeFileName(session.project.name)}.srt', text);
    if (where != null && context.mounted) _say(context, 'Subtitle file saved: $where');
  } catch (e) {
    if (context.mounted) _say(context, 'The subtitle file could not be saved ($e)');
  }
}

/// Quick entry of a caption at the playhead, plus subtitle files.
Future<void> showCaptionsDialog(BuildContext context, EditorSession session) {
  session.playback.pause();
  return showDialog<void>(
    context: context,
    builder: (_) => _CaptionsDialog(session: session, host: context),
  );
}

class _CaptionsDialog extends StatefulWidget {
  const _CaptionsDialog({required this.session, required this.host});
  final EditorSession session;

  /// Context of the editor, for messages after the dialog has closed.
  final BuildContext host;

  @override
  State<_CaptionsDialog> createState() => _CaptionsDialogState();
}

class _CaptionsDialogState extends State<_CaptionsDialog> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    if (addCaption(widget.session, _text.text)) Navigator.of(context).pop();
  }

  void _file(Future<void> Function(BuildContext, EditorSession) action) {
    Navigator.of(context).pop();
    action(widget.host, widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return AlertDialog(
      title: const Text('Add caption'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _text,
                  autofocus: true,
                  maxLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What is being said',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Appears at '
                  '${formatTime(_startAtPlayhead(s, kDefaultCaptionMs))} for '
                  '${formatLength(kDefaultCaptionMs)}, at the bottom of the '
                  'picture. You can move and stretch it on the timeline.',
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                const Divider(height: 28),
                TextButton.icon(
                  onPressed: () => _file(importSubtitles),
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Add a subtitle file (.srt)'),
                ),
                if (hasCaptions(s.project))
                  TextButton.icon(
                    onPressed: () => _file(exportSubtitles),
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Export subtitles (.srt)'),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty ? null : _add,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// What the picker had to say about how files were kept (Android: no room
/// for ClipForge's own copy, or a very big copy was made).
void _sayPickWarnings(BuildContext context, List<PickedFile> picked) {
  final notes = [
    for (final f in picked)
      if (f.warning != null) f.warning!,
  ];
  if (notes.isNotEmpty) _say(context, notes.join('\n'));
}

void _showProblems(BuildContext context, List<String> problems,
    {String? footer}) {
  showDropProblems(
      context,
      problems.length == 1
          ? 'A file could not be added'
          : '${problems.length} files could not be added',
      problems,
      footer: footer);
}

/// Lets the user pick videos or photos and puts them on the overlay track
/// at the playhead, as a picture-in-picture in the bottom right corner
/// (each after the one before when there are several). The first one is
/// selected, so its settings are at hand.
Future<void> addOverlay(BuildContext context, EditorSession session) async {
  final List<PickedFile> picked;
  try {
    picked = await session.files.pickMedia();
  } catch (e) {
    if (context.mounted) _showProblems(context, ['Could not open the file picker ($e)']);
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final problems = await addOverlayFiles(context, session, picked);
  if (problems.isNotEmpty && context.mounted) _showProblems(context, problems);
  if (context.mounted) _sayPickWarnings(context, picked);
}

/// Puts the videos and photos [picked] on the overlay track like
/// [addOverlay]. Returns one line per file that could not be added.
Future<List<String>> addOverlayFiles(
    BuildContext context, EditorSession session, List<PickedFile> picked) async {
  final items = <OverlayClip>[];
  final problems = <String>[];
  // An overlay after the end of the video would never be seen.
  final startMs = session.playback.positionMs < session.project.durationMs
      ? session.playback.positionMs
      : 0;
  final cancel = BusyCancel();
  final done = await whileBusy(context, 'Adding overlay…', cancel: cancel, slowNote: kSlowReadNote, () async {
    for (final file in picked) {
      if (cancel.cancelled) return;
      try {
        final info = await readMedia(session, file.path);
        if (info.width <= 0 || info.height <= 0) {
          problems.add('${file.name} — not a video or photo');
          continue;
        }
        final photo = isImagePath(file.path);
        if (!photo && (!info.hasVideo || info.durationMs <= 0)) {
          problems.add('${file.name} — no video found in this file');
          continue;
        }
        items.add(OverlayClip(
          startMs: startMs,
          clip: Clip(
            id: _uuid.v4(),
            type: photo ? ClipType.photo : ClipType.video,
            path: file.path,
            sourceDurationMs: photo ? 0 : info.durationMs,
            inMs: 0,
            outMs: photo ? kDefaultPhotoMs : info.durationMs,
            width: info.width,
            height: info.height,
            hasAudio: !photo && info.hasAudio,
            audioStreams: photo ? const [] : info.audioStreams,
          ),
        ));
      } catch (e) {
        problems.add(readProblem(e, file.name));
      }
    }
  });
  if (!done || session.isDisposed) return const [];
  if (items.isNotEmpty) {
    final ids = <String>[];
    session.editor.transaction(() {
      for (final o in items) {
        ids.add(session.editor.addOverlay(o));
      }
    });
    if (ids.isNotEmpty &&
        session.project.overlays.any((o) => o.id == ids.first)) {
      session.selectOverlayAndShow(ids.first);
    }
  }
  return problems;
}
