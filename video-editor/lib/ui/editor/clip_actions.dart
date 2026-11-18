import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../../media/media_api.dart';
import '../../media/clip_silences.dart';
import '../../media/media_jobs.dart';
import '../../core/storage/media_import.dart' show formatBytes;
import '../format.dart';
import '../gallery_search.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'clip_panels.dart' show ChoiceRow;
import '../../core/transcript/speech_edits.dart';
import 'session.dart';

const _uuid = Uuid();

/// How long a freeze frame stays on screen when it is first inserted.
const int kFreezeFrameMs = 2000;

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Cuts the clip under the playhead in two. A selected clip follows the
/// playhead (see [EditorSession.selectionFollowsPlayhead]), before the cut
/// and after it, so the highlighted clip is the one the next action is for.
void splitAtPlayhead(BuildContext context, EditorSession s) {
  s.playback.pause();
  s.selectionFollowsPlayhead();
  final t = s.playback.positionMs;
  if (!s.editor.splitAt(t)) {
    _say(
        context,
        t >= s.project.durationMs
            ? 'The playhead is at the end of the video. Move the playhead '
                'inside a clip to split it there.'
            : 'Too close to the start or end of a clip. Move the playhead '
                'inside a clip to split it there.');
    return;
  }
  s.selectionFollowsPlayhead();
}

// Missing files ---------------------------------------------------------------

/// Lets the user point at the file that should stand in for [oldPath], a
/// video, photo or (with [audio]) sound whose file is gone. Every clip that
/// used the old file uses the new one afterwards; one undo step.
Future<void> findMissingFile(
    BuildContext context, EditorSession s, String oldPath,
    {required bool audio}) async {
  s.playback.pause();
  PickedFile? fromGallery;
  if (s.gallery.supported) {
    final how = await _askHowToFind(context, missingFileName(oldPath));
    if (how == null || !context.mounted) return;
    if (how == _FindHow.gallery) {
      fromGallery = await _searchGallery(context, s, oldPath);
      if (!context.mounted) return;
    }
  }
  final List<PickedFile> picked;
  if (fromGallery != null) {
    picked = [fromGallery];
  } else {
    try {
      picked = audio ? await s.files.pickAudio() : await s.files.pickMedia();
    } catch (e) {
      if (context.mounted) _say(context, 'Could not open the file picker ($e)');
      return;
    }
  }
  if (picked.isEmpty || !context.mounted) return;
  final file = picked.first;
  final project = s.project;
  // The new file has to cover the part of the old one that is used.
  var neededMs = 0;
  if (audio) {
    for (final a in project.audio) {
      if (a.path == oldPath && a.outMs > neededMs) neededMs = a.outMs;
    }
  } else {
    for (final c in project.clips) {
      if (c.path == oldPath && c.type == ClipType.video && c.outMs > neededMs) {
        neededMs = c.outMs;
      }
    }
  }
  String? problem;
  await whileBusy(context, 'Checking ${file.name}…', () async {
    try {
      final info = await s.engine.probe(file.path);
      if (audio) {
        if (!info.hasAudio || info.durationMs <= 0) {
          problem = '${file.name} has no sound in it.';
        }
      } else if (info.width <= 0 || info.height <= 0) {
        problem = '${file.name} is not a video or photo.';
      } else if (neededMs > 0 &&
          (isImagePath(file.path) || !info.hasVideo)) {
        problem = '${file.name} is not a video.';
      }
      // A little slack: players and ffprobe disagree by a frame or two.
      if (problem == null && neededMs > info.durationMs + 200) {
        problem = '${file.name} is shorter (${formatLength(info.durationMs)}) '
            'than the part of ${fileName(oldPath)} this project uses '
            '(${formatLength(neededMs)}).';
      }
    } catch (_) {
      problem = '${file.name} could not be read.';
    }
  });
  if (!context.mounted) return;
  if (problem != null) {
    _say(context, problem!);
    return;
  }
  s.editor.relinkMedia(oldPath, file.path);
  s.playback.recheckFiles();
  _say(context, 'Now using ${file.name}.');
}

/// The name a missing file had when it was added: the app's own copies
/// before 1.8 were called `<16-digit time>_<name>`; the ones since 1.8 keep
/// the name in a folder of their own.
String missingFileName(String path) {
  final base = p.basename(path.replaceAll(r'\', '/'));
  final m = RegExp(r'^\d{13,17}_(.+)$').firstMatch(base);
  return m == null ? base : m.group(1)!;
}

enum _FindHow { gallery, files }

Future<_FindHow?> _askHowToFind(BuildContext context, String name) =>
    showDialog<_FindHow>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Find file'),
        content: Text('Where is $name now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(_FindHow.files),
            child: const Text('Choose it myself…'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(_FindHow.gallery),
            child: const Text('Search the gallery'),
          ),
        ],
      ),
    );

/// Looks for a file with the missing file's name on the phone and lets the
/// user pick one of the matches; it is then copied into ClipForge's media
/// folder. Null when nothing was found or chosen (the file picker opens
/// next, so the user can still look for it).
Future<PickedFile?> _searchGallery(
    BuildContext context, EditorSession s, String oldPath) async {
  final name = missingFileName(oldPath);
  List<GalleryItem> found = const [];
  String? problem;
  await whileBusy(context, 'Searching the gallery for $name…', () async {
    try {
      found = await s.gallery.findByName(name);
    } on GallerySearchDenied {
      problem = 'ClipForge may not look at your photos and videos, so it '
          'cannot search for $name. Choose the file yourself.';
    } catch (e) {
      problem = 'The gallery could not be searched ($e). Choose the file '
          'yourself.';
    }
  });
  if (!context.mounted) return null;
  if (problem != null || found.isEmpty) {
    _say(context, problem ?? 'No file called $name on this phone. Choose '
        'the file yourself (it may have been renamed).');
    return null;
  }
  final item = await showDialog<GalleryItem>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(found.length == 1 ? 'Found $name' : 'Found ${found.length} files'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in found)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_outlined),
                title: Text(f.name),
                subtitle: Text([
                  if (f.folder != null && f.folder!.isNotEmpty) f.folder!,
                  if (f.sizeBytes > 0) formatBytes(f.sizeBytes),
                  if (f.modified != null) formatDate(f.modified!),
                ].join(' · ')),
                onTap: () => Navigator.of(dialog).pop(f),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (item == null || !context.mounted) return null;
  PickedFile? result;
  await whileBusy(context, 'Copying ${item.name} into ClipForge…', () async {
    try {
      final temp = await s.gallery.fetch(item);
      result = await PlatformFileService.keepPickedFile(temp, item.name);
    } catch (e) {
      problem = '${item.name} could not be copied ($e).';
    }
  });
  if (problem != null && context.mounted) _say(context, problem!);
  return result;
}

// Freeze frame --------------------------------------------------------------

/// Holds the picture under the playhead still for [kFreezeFrameMs]: the
/// video clip there is split and a photo of that frame goes in between.
Future<void> freezeFrame(BuildContext context, EditorSession s) async {
  s.playback.pause();
  s.selectionFollowsPlayhead();
  final project = s.project;
  final position = s.playback.positionMs;
  final index = position < project.durationMs
      ? project.clipIndexAt(position)
      : -1;
  final clip = index < 0 ? null : project.clips[index];
  if (clip == null || clip.type != ClipType.video) {
    _say(context, 'Move the playhead onto a video clip to freeze that frame.');
    return;
  }
  final local = position - project.clipStartMs(index);
  const min = EditorController.minDurationMs;
  if (local < min || clip.durationMs - local < min) {
    _say(context,
        'Move the playhead a little further inside the clip to freeze there.');
    return;
  }

  Clip? photo;
  Object? error;
  await whileBusy(context, 'Freezing the frame…', () async {
    try {
      final dir = await s.documents.mediaDir();
      final path = p.join(dir, 'freeze_${_uuid.v4()}.png');
      await s.engine.extractFrame(clip.path, clip.sourceMsAt(local), path);
      MediaInfo? info;
      try {
        info = await s.engine.probe(path);
      } catch (_) {}
      final sized = info != null && info.width > 0 && info.height > 0;
      photo = Clip(
        id: _uuid.v4(),
        type: ClipType.photo,
        path: path,
        sourceDurationMs: 0,
        inMs: 0,
        outMs: kFreezeFrameMs,
        width: sized ? info.width : clip.width,
        height: sized ? info.height : clip.height,
        hasAudio: false,
        // The still should look like the moving picture around it.
        fit: clip.fit,
        brightness: clip.brightness,
        contrast: clip.contrast,
        saturation: clip.saturation,
        zoom: clip.zoom,
      );
    } catch (e) {
      error = e;
    }
  });
  if (!context.mounted) return;
  final still = photo;
  if (still == null) {
    _say(context, 'The frame could not be saved ($error)');
    return;
  }
  if (!s.editor.insertFreezeFrame(position, still)) {
    _say(context, 'This spot cannot be split, so no freeze frame was added.');
    return;
  }
  if (s.project.clips.any((c) => c.id == still.id)) {
    s.select(ItemKind.clip, still.id);
  }
}

// Remove silences -----------------------------------------------------------

/// Quiet stays at the edges of each cut so speech does not sound clipped.
const int kSilenceKeepMs = 150;

/// The parts of [silences] (source times of the clip's file) that would be
/// cut out of [clip]: limited to its trimmed range, with [kSilenceKeepMs]
/// left on the sides that touch sound.
List<({int startMs, int endMs})> silencesToCut(
    Clip clip, List<({int startMs, int endMs})> silences) {
  final result = <({int startMs, int endMs})>[];
  for (final r in silences) {
    var start = r.startMs < clip.inMs ? clip.inMs : r.startMs;
    var end = r.endMs > clip.outMs ? clip.outMs : r.endMs;
    if (start > clip.inMs) start += kSilenceKeepMs;
    if (end < clip.outMs) end -= kSilenceKeepMs;
    if (end - start >= 2 * kSilenceKeepMs) {
      result.add((startMs: start, endMs: end));
    }
  }
  return result;
}

/// How many pieces [clip] is cut into when [cuts] (from [silencesToCut])
/// are removed: the stretches between them that are long enough to stay
/// (the same rule as [EditorController.removeSourceRanges]).
int piecesAfterCuts(Clip clip, List<({int startMs, int endMs})> cuts) {
  const min = EditorController.minDurationMs;
  final sorted = [...cuts]..sort((a, b) => a.startMs.compareTo(b.startMs));
  var pieces = 0;
  void keep(int from, int to) {
    if (to <= from) return;
    final piece = clip.copyWith(inMs: from, outMs: to);
    if (piece.sourceSpanMs >= min && piece.durationMs >= min) pieces++;
  }

  var at = clip.inMs;
  for (final c in sorted) {
    final start = c.startMs < clip.inMs ? clip.inMs : c.startMs;
    final end = c.endMs > clip.outMs ? clip.outMs : c.endMs;
    if (end <= start) continue;
    if (start > at) keep(at, start);
    if (end > at) at = end;
  }
  keep(at, clip.outMs);
  return pieces;
}

/// Looks for the quiet gaps in [clip], says what would go and, when the
/// user agrees, cuts them out as one undo step.
Future<void> removeSilences(
    BuildContext context, EditorSession s, Clip clip) async {
  s.playback.pause();
  final removed = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SilenceDialog(session: s, clipId: clip.id),
  );
  if (removed != null && removed > 0 && context.mounted) {
    _say(
        context,
        removed == 1
            ? 'Removed 1 silent gap. Undo brings it back.'
            : 'Removed $removed silent gaps. Undo brings them back.');
  }
}

class _SilenceDialog extends StatefulWidget {
  const _SilenceDialog({required this.session, required this.clipId});
  final EditorSession session;
  final String clipId;

  @override
  State<_SilenceDialog> createState() => _SilenceDialogState();
}

class _SilenceDialogState extends State<_SilenceDialog> {
  List<({int startMs, int endMs})>? _cuts;
  Object? _error;

  /// The finished search with its measured levels (automatic threshold),
  /// to try another sensitivity without listening again; null when the
  /// engine has no levels.
  ClipSilenceSearch? _found;

  /// True when a voice recorded separately was listened to.
  bool _heardVoice = false;
  SilenceSensitivity _sensitivity = SilenceSensitivity.auto;

  void _setSensitivity(SilenceSensitivity v) {
    final f = _found;
    final clip = _clip;
    if (f == null || clip == null) return;
    setState(() {
      _sensitivity = v;
      _cuts = silencesToCut(clip, f.silencesFor(v));
    });
  }

  /// How far the search is (0..1); null when the engine does not say.
  double? _progress;

  Clip? get _clip => widget.session.project.clips
      .where((c) => c.id == widget.clipId)
      .firstOrNull;

  /// While the search runs, quitting asks first (and stops it).
  RunningJob? _job;
  ClipSilenceSearch? _search;
  StreamSubscription<double>? _progressSub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    // Closing the dialog stops a search that is still running.
    _search?.cancel();
    final job = _job;
    if (job != null) widget.session.jobs.end(job);
    super.dispose();
  }

  Future<void> _listen() async {
    final clip = _clip;
    if (clip == null) return;
    // The clip's own sound, or the voice(s) recorded separately that are
    // lined up with it (media/clip_silences.dart); only the part of each
    // file the clip uses is listened to.
    final search = _search = startClipSilenceSearch(
        widget.session.engine, widget.session.project, clip);
    final job = _job = widget.session.jobs.start(JobKind.analysis,
        cancel: search.cancel);
    _progressSub = search.progress.listen((f) {
      // Whole percents only: no rebuild for every report.
      if (!mounted || (_progress != null &&
          (f * 100).floor() == (_progress! * 100).floor())) {
        return;
      }
      setState(() => _progress = f);
    });
    try {
      final silences = await search.result;
      if (!mounted) return;
      setState(() {
        _found = search.canAdjust ? search : null;
        _heardVoice = search.listensToVoice;
        _cuts = silencesToCut(_clip ?? clip, silences);
      });
    } on ExportException catch (e) {
      if (mounted && !e.cancelled) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _search = null;
      widget.session.jobs.end(job);
    }
  }

  /// "Sensitivity": the automatic threshold, or a few dB either way.
  List<Widget> _sensitivityChoice() {
    final f = _found;
    if (f == null) return const [];
    // The loudest of the sounds listened to tells the story.
    final l = f.levels.whereType<SilenceLevels>().reduce(
        (a, b) => b.loudDb > a.loudDb ? b : a);
    return [
      const SizedBox(height: 14),
      const Text('Sensitivity',
          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      const SizedBox(height: 6),
      ChoiceRow<SilenceSensitivity>(
        key: const ValueKey('silence-sensitivity'),
        values: SilenceSensitivity.values,
        label: (v) => switch (v) {
          SilenceSensitivity.fewerCuts => 'Fewer cuts',
          SilenceSensitivity.auto => 'Automatic',
          SilenceSensitivity.moreCuts => 'More cuts',
        },
        selected: _sensitivity,
        onSelected: _setSensitivity,
      ),
      const SizedBox(height: 6),
      Text(
        l.hasQuietParts
            ? 'Background noise about ${l.noiseFloorDb.round()} dB; quieter '
                'than ${l.thresholdFor(_sensitivity).round()} dB counts as '
                'silence.'
            : 'The sound is about equally loud all through.',
        key: const ValueKey('silence-threshold'),
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
    ];
  }

  void _apply() {
    final cuts = _cuts;
    if (cuts == null) return;
    // One call, one undo step.
    // Remembered in the project (1.11), so each can be put back later.
    final e = widget.session.editor.editor;
    final path = _clip?.path;
    var removed = 0;
    e.transaction(() {
      removed = e.removeSourceRanges(widget.clipId, cuts);
      if (removed > 0 && path != null) {
        logSilenceCuts(e, path, cuts, newId: const Uuid().v4);
      }
    },
        label: cuts.length == 1
            ? 'Removed 1 silence'
            : 'Removed ${cuts.length} silences');
    Navigator.of(context).pop(removed);
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final cuts = _cuts;
    final Widget content;
    var canApply = false;
    if (_error != null) {
      content = Text('The sound of this clip could not be checked ($_error)');
    } else if (cuts == null || clip == null) {
      final progress = _progress;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            minHeight: 6,
            value: progress != null && progress > 0 ? progress : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('Listening for quiet parts…')),
              if (progress != null)
                Text('${(progress * 100).floor()}%',
                    key: const ValueKey('silence-progress')),
            ],
          ),
          if (clip != null && clip.sourceSpanMs >= 5 * 60000) ...[
            const SizedBox(height: 8),
            Text(
              'A long clip takes a while. Cancel stops it.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ],
      );
    } else if (cuts.isEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_sensitivity == SilenceSensitivity.auto
              ? 'No silent gaps were found in this clip, so nothing changes.'
              : 'No silent gaps at this sensitivity.'),
          ..._sensitivityChoice(),
        ],
      );
    } else {
      canApply = true;
      final sourceMs =
          cuts.fold<int>(0, (sum, r) => sum + r.endMs - r.startMs);
      final timelineMs = (sourceMs / clip.speed).round();
      final after = clip.durationMs - timelineMs;
      final pieces = piecesAfterCuts(clip, cuts);
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cuts.length == 1
                ? 'Found 1 silent gap (${formatLength(timelineMs)}).'
                : 'Found ${cuts.length} silent gaps '
                    '(${formatLength(timelineMs)} in total).',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_heardVoice) ...[
            const SizedBox(height: 4),
            const Text(
              'Listened to the voice recorded separately.',
              key: ValueKey('silence-voice-note'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text('Removing them shortens this clip from '
              '${formatLength(clip.durationMs)} to ${formatLength(after)}.'),
          const SizedBox(height: 8),
          Text(
            pieces == 1
                ? 'The clip stays in one piece. One Undo puts everything '
                    'back.'
                : 'This will cut the clip into $pieces pieces. One Undo '
                    'puts everything back.',
            key: const ValueKey('silence-pieces'),
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          ..._sensitivityChoice(),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Remove silences'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SizedBox(width: double.maxFinite, child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(canApply || (cuts == null && _error == null)
              ? 'Cancel'
              : 'Close'),
        ),
        if (canApply)
          FilledButton(
            onPressed: _apply,
            child: Text(cuts!.length == 1 ? 'Remove 1 gap' : 'Remove ${cuts.length} gaps'),
          ),
      ],
    );
  }
}

// Duplicate, copy / paste settings, in / out points (1.7) -------------------

/// Duplicates the selected clip (right after it) or title / caption (right
/// after it on the timeline) and selects the copy (Ctrl/Cmd+D, Edit menu).
/// Says so when nothing that can be duplicated is selected.
void duplicateSelection(BuildContext context, EditorSession s) {
  final clip = s.selectedClip;
  if (clip != null) {
    final id = s.editor.duplicateClip(clip.id);
    if (id != null) s.selectClipAndShow(id);
    return;
  }
  final title = s.selectedTitle;
  if (title != null) {
    final id = s.editor.duplicateTitle(title.id);
    if (id != null) s.select(ItemKind.title, id);
    return;
  }
  _say(context, 'Select a clip or a title to duplicate it.');
}

/// The clip "Copy settings" / "Paste settings" work on: the selected one,
/// else the one under the playhead.
Clip? _settingsClip(EditorSession s) {
  final selected = s.selectedClip;
  if (selected != null) return selected;
  final i = s.clipIndexUnderPlayhead;
  return i < 0 ? null : s.project.clips[i];
}

/// Remembers the look, speed, sound, crop and position, fit and zoom of
/// the selected clip (Ctrl/Cmd+Shift+C, Edit menu).
void copyClipSettings(BuildContext context, EditorSession s) {
  final clip = _settingsClip(s);
  if (clip == null) {
    _say(context, 'Select a clip to copy its settings.');
    return;
  }
  s.copiedSettings.value = ClipSettings.of(clip);
  final n = s.project.clips.indexOf(clip) + 1;
  _say(context,
      'Copied the settings of clip $n: look, speed, sound, crop and fit. '
      'Select another clip and paste them.');
}

/// Puts the copied settings on the selected clip (Ctrl/Cmd+Shift+V, Edit
/// menu). One undo step.
void pasteClipSettings(BuildContext context, EditorSession s) {
  final settings = s.copiedSettings.value;
  final clip = _settingsClip(s);
  if (settings == null) {
    _say(context, 'Copy the settings of a clip first.');
    return;
  }
  if (clip == null) {
    _say(context, 'Select a clip to paste the settings on.');
    return;
  }
  final n = s.editor.pasteClipSettings([clip.id], settings);
  if (n == 0) _say(context, 'This clip already has these settings.');
}

/// I / O keys: the selected clip (else the one under the playhead) starts
/// ([start]) or ends at the playhead, by trimming it. Says why when the
/// playhead is not inside that clip.
void trimToPlayhead(BuildContext context, EditorSession s,
    {required bool start}) {
  final project = s.project;
  final t = s.playback.positionMs;
  var clip = s.selectedClip;
  var i = clip == null ? s.clipIndexUnderPlayhead : project.clips.indexOf(clip);
  if (i < 0) {
    _say(context, 'Move the playhead onto a clip first.');
    return;
  }
  clip = project.clips[i];
  final local = t - project.clipStartMs(i);
  const min = EditorController.minDurationMs;
  if (local < 0 || local > clip.durationMs) {
    _say(context, 'Move the playhead inside the selected clip first.');
    return;
  }
  if ((start && clip.durationMs - local < min) || (!start && local < min)) {
    _say(context, 'Too close to the other end of the clip.');
    return;
  }
  final c = clip;
  s.editor.transaction(() {
    if (c.type == ClipType.photo) {
      s.editor.trimClip(c.id, outMs: start ? c.durationMs - local : local);
    } else if (start) {
      s.editor.trimClip(c.id, inMs: c.sourceMsAt(local));
    } else {
      s.editor.trimClip(c.id, outMs: c.sourceMsAt(local));
    }
  },
      label: start
          ? 'Start of clip ${i + 1} at playhead'
          : 'End of clip ${i + 1} at playhead');
  // After "start here" the clip begins where it began: show its first frame.
  if (start) s.playback.seek(s.project.clipStartMs(i));
}
