// Sound files and "Voice recorded separately" (1.10):
//
//  * "What is this sound?" - asked whenever sound files are added (dropped,
//    Music > My files, Add media): Voice for the video / Music / Sound
//    effect. A sheet on phones, a dialog on computers.
//  * Voice for the video: lined up with the picture by sound
//    (media/sound_align.dart), linked to its clip so it follows every cut
//    (core/editor/sound_tracks.dart), the camera's own sound muted.
//  * The voice part of a sound clip's panel: nudge buttons, "Line up with
//    the video again", the camera sound switch, "Unlink".
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/editor/project_editor.dart' show ProjectEditor;
import '../../core/editor/sound_tracks.dart' show VoiceProblem, voiceGroup;
import '../../core/model/project.dart';
import '../../media/media_api.dart';
import '../../media/sound_align_job.dart';
import '../file_drop.dart' show showDropProblems;
import '../help/help_screen.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'session.dart';

const _uuid = Uuid();
const _dim = TextStyle(color: AppColors.textDim, fontSize: 12);

/// Fade-out a newly added piece of music gets, so it does not stop dead.
const int kMusicFadeOutMs = 1000;

void _say(BuildContext context, String message, {int seconds = 5}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(message), duration: Duration(seconds: seconds)));
}

bool _phone(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// A sound file that was read and can be added.
class SoundFile {
  const SoundFile(this.file, this.info);
  final PickedFile file;
  final MediaInfo info;
}

/// The answer to "What is this sound?".
class SoundAnswer {
  const SoundAnswer(this.role,
      {this.muteCamera = true, this.trackNames = const []});
  final SoundRole role;

  /// Voice: "Mute the camera's own sound".
  final bool muteCamera;

  /// Voice: the name of each file's track ('' = "Voice").
  final List<String> trackNames;
}

/// The words for [role] in "What is this sound?".
String soundRoleLabel(SoundRole role) => switch (role) {
      SoundRole.voice => 'Voice for the video',
      SoundRole.music => 'Music',
      SoundRole.effect => 'Sound effect',
    };

/// The video clips a voice can be lined up with: one per video file with
/// sound, in timeline order.
List<Clip> _videoFiles(Project p, {bool withSoundOnly = true}) {
  final seen = <String>{};
  return [
    for (final c in p.clips)
      if (c.type == ClipType.video &&
          (c.hasAudio || !withSoundOnly) &&
          seen.add(c.path))
        c,
  ];
}

/// What "What is this sound?" starts with for [files] in project [p]:
/// Voice when every file looks like one (see [guessSoundRole]) and the
/// project has a video clip; else Music.
SoundRole guessBatchRole(Project p, List<SoundFile> files) {
  final videos = _videoFiles(p, withSoundOnly: false);
  if (videos.isEmpty || files.isEmpty) return SoundRole.music;
  final lengths = [for (final c in videos) c.sourceDurationMs];
  for (final f in files) {
    if (guessSoundRole(f.file.name,
            durationMs: f.info.durationMs, videoDurationsMs: lengths) !=
        SoundRole.voice) {
      return SoundRole.music;
    }
  }
  return SoundRole.voice;
}

/// Asks "What is this sound?" for [files] (one question for the batch).
/// Null: cancelled, nothing is added.
Future<SoundAnswer?> askWhatSound(
    BuildContext context, EditorSession s, List<SoundFile> files,
    {SoundRole? preselect}) {
  s.playback.pause();
  final body = _SoundQuestion(
      session: s,
      files: files,
      initial: preselect ?? guessBatchRole(s.project, files));
  if (_phone(context)) {
    return showModalBottomSheet<SoundAnswer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(child: body),
        ),
      ),
    );
  }
  return showDialog<SoundAnswer>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: SingleChildScrollView(child: body),
        ),
      ),
    ),
  );
}

class _SoundQuestion extends StatefulWidget {
  const _SoundQuestion(
      {required this.session, required this.files, required this.initial});
  final EditorSession session;
  final List<SoundFile> files;
  final SoundRole initial;

  @override
  State<_SoundQuestion> createState() => _SoundQuestionState();
}

class _SoundQuestionState extends State<_SoundQuestion> {
  late SoundRole _role;
  bool _mute = true;
  late final List<TextEditingController> _names;

  bool get _hasVideo =>
      _videoFiles(widget.session.project, withSoundOnly: false).isNotEmpty;

  @override
  void initState() {
    super.initState();
    _role = widget.initial == SoundRole.voice && !_hasVideo
        ? SoundRole.music
        : widget.initial;
    _names = [
      for (final f in widget.files)
        TextEditingController(text: speakerNameFromFile(f.file.name) ?? ''),
    ];
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _choice(SoundRole role, IconData icon, String about,
      {bool enabled = true}) {
    final selected = _role == role;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.accent.withValues(alpha: 0.16) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? AppColors.accent : AppColors.textDim
                  .withValues(alpha: 0.35)),
        ),
        clipBehavior: ui.Clip.antiAlias,
        child: InkWell(
          key: ValueKey('sound-role-${role.name}'),
          onTap: enabled ? () => setState(() => _role = role) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected ? AppColors.accent : AppColors.textDim),
                  const SizedBox(width: 10),
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(soundRoleLabel(role),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(about, style: _dim),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final many = files.length > 1;
    final names = [for (final f in files.take(3)) f.file.name].join(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(many ? 'What are these sounds?' : 'What is this sound?',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const HelpHint('voice-recorded-separately',
                label: 'Voice recorded separately'),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$names${files.length > 3 ? ' and ${files.length - 3} more' : ''}',
          key: const ValueKey('sound-question-files'),
          style: _dim,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        _choice(
          SoundRole.voice,
          Icons.record_voice_over,
          _hasVideo
              ? 'Speech from a separate microphone or a Zoom recording. '
                  'It is lined up with the picture and follows it when you '
                  'cut.'
              : 'Add the video first, then its voice.',
          enabled: _hasVideo,
        ),
        _choice(SoundRole.music, Icons.music_note,
            'Goes on the Music track, at the playhead.'),
        _choice(SoundRole.effect, Icons.graphic_eq,
            'A short sound. Goes on the Effects track, at the playhead.'),
        if (_role == SoundRole.voice) ...[
          const SizedBox(height: 4),
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey('voice-track-name-$i'),
                controller: _names[i],
                maxLength: ProjectEditor.maxTrackNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: const OutlineInputBorder(),
                  labelText: many
                      ? 'Who speaks in ${files[i].file.name}'
                      : 'Who speaks (name of its track)',
                  hintText: 'Voice',
                ),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('voice-mute-camera'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Mute the camera\'s own sound'),
            subtitle: const Text(
                'So you hear only the better recording. You can switch it '
                'back on later.',
                style: _dim),
            value: _mute,
            onChanged: (v) => setState(() => _mute = v),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('sound-role-add'),
              onPressed: () => Navigator.of(context).pop(SoundAnswer(_role,
                  muteCamera: _mute,
                  trackNames: [for (final c in _names) c.text.trim()])),
              child: Text(_role == SoundRole.voice ? 'Add and line up' : 'Add'),
            ),
          ],
        ),
      ],
    );
  }
}

// Adding ----------------------------------------------------------------------

/// Reads the sound files [picked], asks what they are (unless [role] says)
/// and adds them: music and effects at the playhead, voices lined up with
/// the video. Returns one line per file that could not be added.
Future<List<String>> addSoundFiles(
    BuildContext context, EditorSession session, List<PickedFile> picked,
    {SoundRole? role, SoundRole? preselect}) async {
  final files = <SoundFile>[];
  final problems = <String>[];
  await whileBusy(context,
      picked.length == 1 ? 'Reading the sound…' : 'Reading the sounds…',
      () async {
    for (final file in picked) {
      try {
        final info = await session.engine.probe(file.path);
        if (!info.hasAudio || info.durationMs <= 0) {
          problems.add('${file.name} — no sound found in this file');
          continue;
        }
        files.add(SoundFile(file, info));
      } catch (_) {
        problems.add('${file.name} — the file could not be read');
      }
    }
  });
  if (files.isEmpty || !context.mounted) return problems;
  final SoundAnswer? answer = role != null
      ? SoundAnswer(role)
      : await askWhatSound(context, session, files, preselect: preselect);
  if (answer == null || !context.mounted) return problems;
  switch (answer.role) {
    case SoundRole.music:
      placeSounds(session, files);
    case SoundRole.effect:
      final note = placeSounds(session, files, effect: true);
      if (note != null) _say(context, note);
    case SoundRole.voice:
      problems.addAll(await _addVoices(context, session, files, answer));
  }
  return problems;
}

/// Puts [files] at the playhead as music (on the track of the selected
/// sound, else the Music track, with a short fade-out) or as sound
/// effects (on the "Effects" track, made when there is room). One undo
/// step; the last one is selected. Returns something to tell the user, or
/// null.
String? placeSounds(EditorSession session, List<SoundFile> files,
    {bool effect = false, Map<String, MusicCredit> credits = const {}}) {
  if (files.isEmpty) return null;
  // Sound put after the end of the video would never be heard.
  final startMs = session.playback.positionMs < session.project.durationMs
      ? session.playback.positionMs
      : 0;
  String? note;
  final ids = <String>[];
  session.editor.transaction(() {
    // On the track of the selected sound, unless that is a speech track
    // (music does not belong among the voices); else the Music track.
    final selected = session.selectedAudio?.trackId;
    var track = selected != null &&
            !(session.project.trackById(selected)?.speech ?? false)
        ? selected
        : kMusicTrackId;
    if (effect) {
      final p = session.project;
      final effects = p.soundTracks
          .where((t) => t.name.trim().toLowerCase().startsWith('effect'))
          .firstOrNull;
      final made = effects?.id ?? session.editor.addSoundTrack(name: 'Effects');
      if (made != null) {
        track = made;
      } else {
        track = kMusicTrackId;
        note = 'There is no room for an Effects track (at most '
            '${ProjectEditor.maxSoundTracks} sound tracks), so the sound is '
            'with the music.';
      }
    }
    for (final f in files) {
      final d = f.info.durationMs;
      ids.add(session.editor.addAudio(AudioClip(
        id: _uuid.v4(),
        path: f.file.path,
        sourceDurationMs: d,
        startMs: startMs,
        inMs: 0,
        outMs: d,
        trackId: track,
        audioStreams: f.info.audioStreams,
        credit: credits[f.file.path],
        fadeOutMs: effect
            ? 0
            : (d >= 2 * kMusicFadeOutMs ? kMusicFadeOutMs : d ~/ 2),
      )));
    }
  },
      label: !effect
          ? null
          : (files.length == 1
              ? 'Added sound effect'
              : 'Added ${files.length} sound effects'));
  final last = ids.lastOrNull;
  if (last != null && session.project.audio.any((a) => a.id == last)) {
    session.select(ItemKind.audio, last);
  }
  return note;
}

/// The best match of the sound file [voicePath] among the video files of
/// the project: the clip to line it up with and what was found. Null when
/// there is nothing to compare with or the engine cannot.
Future<({Clip clip, AlignResult result})?> _bestMatch(
    EditorSession s, String voicePath, int voiceTrack) async {
  final engine = s.engine;
  if (engine is! SoundAlignEngine) return null;
  ({Clip clip, AlignResult result})? best;
  for (final c in _videoFiles(s.project)) {
    AlignResult r;
    try {
      r = await (engine as SoundAlignEngine).alignSound(c.path, voicePath,
          videoAudioTrack: c.audioTrackInUse, voiceAudioTrack: voiceTrack);
    } on ExportException catch (e) {
      r = AlignResult.none(e.message);
    } catch (e) {
      r = AlignResult.none('$e');
    }
    if (best == null || r.confidence > best.result.confidence) {
      best = (clip: c, result: r);
    }
  }
  return best;
}

/// The clip a voice that could not be lined up is put at: the selected
/// video clip, else the one under the playhead, else the first.
Clip? _fallbackClip(EditorSession s) {
  final p = s.project;
  final selected = s.selectedClip;
  if (selected != null && selected.type == ClipType.video) return selected;
  final under = s.clipIndexUnderPlayhead;
  if (under >= 0 && p.clips[under].type == ClipType.video) return p.clips[under];
  return p.clips.where((c) => c.type == ClipType.video).firstOrNull;
}

String _driftNote(AlignResult r) => r.drifts
    ? ' The two recordings slowly drift apart (about '
        '${(r.driftMs.abs() / 1000).toStringAsFixed(2)} s over the video); '
        'it is lined up for the best average.'
    : '';

Future<List<String>> _addVoices(BuildContext context, EditorSession s,
    List<SoundFile> files, SoundAnswer answer) async {
  final problems = <String>[];
  final matches = <({Clip clip, AlignResult result})?>[];
  await whileBusy(context, 'Lining up the voice with the video…', () async {
    for (final f in files) {
      matches.add(await _bestMatch(s, f.file.path, 0));
    }
  });
  if (!context.mounted) return problems;
  final fallback = _fallbackClip(s);
  if (fallback == null) {
    return [
      for (final f in files) '${f.file.name} — add the video first, then its voice',
    ];
  }
  final added = <String>[];
  var linedUp = 0;
  var notLinedUp = 0;
  AlignResult? only;
  int? clipNumber;
  s.editor.transaction(() {
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final m = matches[i];
      final ok = m != null && m.result.matched;
      // The clip may have changed while the sound was compared.
      final target = s.project.clips
              .where((c) => c.id == (ok ? m.clip.id : fallback.id))
              .firstOrNull ??
          _fallbackClip(s);
      if (target == null) continue;
      final name = i < answer.trackNames.length ? answer.trackNames[i] : '';
      try {
        final ids = s.editor.addVoice(
          AudioClip(
            id: _uuid.v4(),
            path: f.file.path,
            sourceDurationMs: f.info.durationMs,
            startMs: 0,
            inMs: 0,
            outMs: f.info.durationMs,
            audioStreams: f.info.audioStreams,
          ),
          clipId: target.id,
          // Not lined up: the voice file starts where the clip starts.
          offsetMs: ok ? m.result.offsetMs : -target.inMs,
          trackName: name.isEmpty ? null : name,
          // Not lined up: the camera stays on, to compare by ear.
          muteClips: ok && answer.muteCamera,
          linedUp: ok,
        );
        added.addAll(ids);
        if (ok) {
          linedUp++;
          only = m.result;
        } else {
          notLinedUp++;
        }
        clipNumber = s.project.clips.indexWhere((c) => c.id == target.id) + 1;
      } on VoiceProblem catch (e) {
        problems.add('${f.file.name} — ${e.message}');
      }
    }
  },
      label: linedUp + notLinedUp > 1
          ? 'Added ${linedUp + notLinedUp} voices'
              '${notLinedUp == 0 ? ', lined up' : ''}'
          : null);
  final first = added.firstOrNull;
  if (first == null || !context.mounted) return problems;
  if (s.project.audio.any((a) => a.id == first)) {
    s.select(ItemKind.audio, first);
  }
  if (notLinedUp > 0) {
    _say(
        context,
        'Could not line it up automatically — nudge it by hand. '
        '${notLinedUp == 1 && linedUp == 0 ? 'The voice starts' : '$notLinedUp of the voices start'} '
        'where clip $clipNumber starts; the camera\'s own sound is still '
        'on so you can compare.',
        seconds: 9);
  } else if (linedUp == 1) {
    final r = only!;
    _say(
        context,
        'Lined up with clip $clipNumber '
        '(${ProjectEditor.offsetLabel(r.offsetMs)}). It follows the picture '
        'when you cut.'
        '${answer.muteCamera ? ' The camera\'s own sound is muted.' : ''}'
        '${_driftNote(r)}',
        seconds: r.drifts ? 10 : 6);
  } else {
    _say(
        context,
        '$linedUp voices lined up with the video, each on its own track. '
        'They follow the picture when you cut.'
        '${answer.muteCamera ? ' The camera\'s own sound is muted.' : ''}',
        seconds: 6);
  }
  return problems;
}

/// Edit > Sound > "Add voice recording…": picks sound files and adds them
/// as the voice for the video (the question opens with Voice chosen).
Future<void> addVoiceRecording(BuildContext context, EditorSession s) async {
  s.playback.pause();
  if (_videoFiles(s.project, withSoundOnly: false).isEmpty) {
    _say(context, 'Add the video first, then its voice recording.');
    return;
  }
  final List<PickedFile> picked;
  try {
    picked = await s.files.pickAudio();
  } catch (e) {
    if (context.mounted) _say(context, 'Could not open the file picker ($e)');
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final problems =
      await addSoundFiles(context, s, picked, preselect: SoundRole.voice);
  if (problems.isNotEmpty && context.mounted) {
    showDropProblems(
        context,
        problems.length == 1
            ? 'A file could not be added'
            : '${problems.length} files could not be added',
        problems);
  }
}

// Line up (again), unlink -------------------------------------------------------

/// "Line up with the video": compares the sound [audioId] with the sound
/// of the video clips and links it to the best match - a voice that is
/// lined up already is lined up again; plain music that is really a voice
/// becomes one (asked: mute the camera?). When nothing matches, a voice
/// keeps its place and plain sound is linked where it is, to be nudged by
/// hand.
Future<void> lineUpVoice(
    BuildContext context, EditorSession s, String audioId) async {
  s.playback.pause();
  final a = s.project.audio.where((a) => a.id == audioId).firstOrNull;
  if (a == null) return;
  if (_videoFiles(s.project, withSoundOnly: false).isEmpty) {
    _say(context, 'There is no video clip to line it up with.');
    return;
  }
  ({Clip clip, AlignResult result})? best;
  await whileBusy(context, 'Lining up the voice with the video…', () async {
    best = await _bestMatch(s, a.path, a.soundClip.audioTrackInUse);
  });
  if (!context.mounted) return;
  final m = best;
  final name = speakerNameFromFile(a.path);
  if (m != null && m.result.matched) {
    bool? mute;
    if (!a.isVoice) {
      mute = await _askMuteCamera(context);
      if (mute == null || !context.mounted) return;
    }
    try {
      final ids = s.editor.linkVoice(audioId,
          clipId: m.clip.id,
          offsetMs: m.result.offsetMs,
          trackName: name,
          muteClips: mute);
      if (ids.isNotEmpty) s.select(ItemKind.audio, ids.first);
      final n = s.project.clips.indexWhere((c) => c.id == m.clip.id) + 1;
      _say(
          context,
          'Lined up with clip $n '
          '(${ProjectEditor.offsetLabel(m.result.offsetMs)}). It follows '
          'the picture when you cut.${_driftNote(m.result)}',
          seconds: m.result.drifts ? 10 : 5);
    } on VoiceProblem catch (e) {
      _say(context, e.message, seconds: 8);
    }
    return;
  }
  const failed = 'Could not line it up automatically — nudge it by hand.';
  if (a.isVoice && a.linked) {
    _say(context, '$failed It stays where it is.', seconds: 7);
    return;
  }
  // Link it where it is now, so that it follows the picture and can be
  // nudged.
  final p = s.project;
  var i = a.startMs < p.durationMs ? p.clipIndexAt(a.startMs) : -1;
  if (i < 0 || p.clips[i].type != ClipType.video) {
    final f = _fallbackClip(s);
    i = f == null ? -1 : p.clips.indexOf(f);
  }
  if (i < 0) {
    _say(context, failed);
    return;
  }
  final c = p.clips[i];
  final shown = c.inMs + ((a.startMs - p.clipStartMs(i)) * c.speed).round();
  try {
    final ids = s.editor.linkVoice(audioId,
        clipId: c.id,
        offsetMs: a.inMs - shown,
        trackName: name,
        muteClips: c.muted);
    if (ids.isNotEmpty) s.select(ItemKind.audio, ids.first);
    _say(
        context,
        '$failed It stays where it is and now follows clip ${i + 1} when '
        'you cut.',
        seconds: 8);
  } on VoiceProblem catch (e) {
    _say(context, '$failed ${e.message}', seconds: 8);
  }
}

Future<bool?> _askMuteCamera(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mute the camera\'s own sound?'),
        content: const Text(
            'The voice is lined up with the picture. Muting the camera '
            'leaves only the better recording. You can switch it back on '
            'later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('mute-camera-no'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep both'),
          ),
          FilledButton(
            key: const ValueKey('mute-camera-yes'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Mute the camera'),
          ),
        ],
      ),
    );

/// "Unlink": the voice stays where it is and stops following the picture;
/// asks whether the camera's own sound comes back on (when it is muted).
Future<void> unlinkVoice(
    BuildContext context, EditorSession s, String audioId) async {
  final p = s.project;
  final a = p.audio.where((a) => a.id == audioId).firstOrNull;
  if (a == null || !a.isVoice || !a.linked) return;
  final clipIds = {for (final x in voiceGroup(p, a)) x.sourceClipId};
  final muted = p.clips.any((c) => clipIds.contains(c.id) && c.muted);
  var unmute = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Unlink the voice from the video?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'The voice stays exactly where it is, but it no longer '
                'follows the picture when you trim, split or move clips.'),
            if (muted)
              CheckboxListTile(
                key: const ValueKey('unlink-unmute'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: unmute,
                onChanged: (v) => setState(() => unmute = v ?? true),
                title: const Text('Switch the camera\'s own sound back on'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('unlink-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  s.editor.unlinkVoice(audioId, unmuteClips: muted && unmute);
}

// The voice part of a sound clip's panel -----------------------------------------

/// One frame of the clip [c], in ms (33 when its frame rate is unknown).
int voiceFrameMs(Clip? c) =>
    c == null || c.frameRate <= 1 ? 33 : (1000 / c.frameRate).round();

/// For a voice recorded separately: what it is lined up with, the nudge
/// buttons (± 1 frame / 10 ms / 100 ms), "Line up with the video again",
/// the camera sound switch and "Unlink".
class VoicePanel extends StatelessWidget {
  const VoicePanel({super.key, required this.session, required this.audio});
  final EditorSession session;
  final AudioClip audio;

  @override
  Widget build(BuildContext context) {
    final a = audio;
    final p = session.project;
    final editor = session.editor;
    final i = p.clips.indexWhere((c) => c.id == a.sourceClipId);
    final clip = i < 0 ? null : p.clips[i];
    final frame = voiceFrameMs(clip);
    final clipIds = {for (final x in voiceGroup(p, a)) x.sourceClipId};
    final clips = [for (final c in p.clips) if (clipIds.contains(c.id)) c];
    final cameraMuted = clips.isNotEmpty && clips.every((c) => c.muted);

    Widget nudge(String label, int ms, String key) => OutlinedButton(
          key: ValueKey('nudge-$key'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
          ),
          onPressed: () => editor.nudgeVoice(a.id, ms),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.record_voice_over,
                size: 18, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.linked && clip != null
                    ? 'Voice for clip ${i + 1}, lined up at '
                        '${ProjectEditor.offsetLabel(a.syncOffsetMs!)}. It '
                        'follows the clip when you cut.'
                    : 'Voice recorded separately. It is not linked to the '
                        'video: it stays where you put it.',
                key: const ValueKey('voice-status'),
                style: _dim,
              ),
            ),
            const HelpHint('voice-recorded-separately',
                label: 'Voice recorded separately'),
          ],
        ),
        if (a.linked && clip != null) ...[
          const SizedBox(height: 8),
          Text('Nudge the voice', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          // One row each way, so it is clear which buttons do what.
          for (final (label, buttons) in [
            (
              'Earlier',
              [
                nudge('100 ms', -100, 'earlier-100'),
                nudge('10 ms', -10, 'earlier-10'),
                nudge('1 frame', -frame, 'earlier-frame'),
              ]
            ),
            (
              'Later',
              [
                nudge('1 frame', frame, 'later-frame'),
                nudge('10 ms', 10, 'later-10'),
                nudge('100 ms', 100, 'later-100'),
              ]
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 52, child: Text(label, style: _dim)),
                  Expanded(
                    child: Wrap(spacing: 4, runSpacing: 4, children: buttons),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          const Text(
              'Play and watch the lips. Voice too late: nudge earlier.',
              style: _dim),
        ],
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('voice-realign'),
              onPressed: () => lineUpVoice(context, session, a.id),
              icon: const Icon(Icons.graphic_eq, size: 18),
              label: Text(a.linked
                  ? 'Line up with the video again'
                  : 'Line up with the video'),
            ),
            if (a.linked)
              TextButton.icon(
                key: const ValueKey('voice-unlink'),
                onPressed: () => unlinkVoice(context, session, a.id),
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Unlink'),
              ),
          ],
        ),
        if (clips.isNotEmpty)
          SwitchListTile(
            key: const ValueKey('voice-camera-muted'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Mute the camera\'s own sound'),
            value: cameraMuted,
            onChanged: (v) => editor.setVoiceClipsMuted(a.id, v),
          ),
      ],
    );
  }
}

/// In a video clip's Sound panel: says that its voice comes from a
/// separate recording, with "Show the voice".
class LinkedVoiceRow extends StatelessWidget {
  const LinkedVoiceRow({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final p = session.project;
    final voices = [
      for (final a in p.audio)
        if (a.isVoice && a.linked && a.sourceClipId == clip.id) a,
    ];
    if (voices.isEmpty) return const SizedBox.shrink();
    final names = {
      for (final a in voices) p.trackById(a.trackId)?.name ?? 'Voice',
    }.join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.record_voice_over, size: 18, color: AppColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Voice from a separate recording ($names)'
                '${clip.muted ? '; the camera\'s own sound is muted' : ''}.',
                key: const ValueKey('linked-voice-note'),
                style: _dim),
          ),
          TextButton(
            key: const ValueKey('show-linked-voice'),
            onPressed: () => session.select(ItemKind.audio, voices.first.id),
            child: const Text('Show the voice'),
          ),
        ],
      ),
    );
  }
}
