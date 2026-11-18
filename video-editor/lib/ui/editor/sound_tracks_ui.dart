// Sound tracks in the editor: the row headers left of the timeline (mute,
// solo, the track menu, "Add sound track"), the track menu itself, the
// "Separate sound to track…" flow for a video clip, and the sound options
// of a sound clip (track, clean-up, voice focus, sound from, put back).
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'clip_panels.dart';
import 'session.dart';
import 'sound_status.dart';
import 'voice_actions.dart';

const _dim = TextStyle(color: AppColors.textDim, fontSize: 12);

/// The column left of the timeline. Rows line up with the timeline's: the
/// ruler (with "Add sound track"), the video clips (the video's own sound),
/// one per sound track, the titles.
class TrackHeaders extends StatelessWidget {
  const TrackHeaders({
    super.key,
    required this.session,
    required this.compact,
    required this.rulerHeight,
    required this.clipTop,
    this.overlayTop,
    required this.clipHeight,
    required this.audioTop,
    required this.rowHeight,
    required this.rowGap,
    required this.titleTop,
    required this.titleRows,
  });

  final EditorSession session;

  /// Narrow: icons only, settings in the track menu.
  final bool compact;
  final double rulerHeight;
  final double clipTop;

  /// Top of the overlay row; null when it is not shown.
  final double? overlayTop;
  final double clipHeight;
  final double audioTop;
  final double rowHeight;
  final double rowGap;
  final double titleTop;
  final int titleRows;

  @override
  Widget build(BuildContext context) {
    final p = session.project;
    final tracks = p.soundTracks;
    final canAdd = tracks.length < EditorController.maxSoundTracks;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      child: Stack(
        clipBehavior: ui.Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: rulerHeight,
            child: Tooltip(
              message: canAdd
                  ? 'Add sound track'
                  : 'At most ${EditorController.maxSoundTracks} sound tracks',
              child: TextButton(
                key: const ValueKey('add-sound-track'),
                onPressed: canAdd ? () => addSoundTrack(context, session) : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: compact
                    ? const Icon(Icons.playlist_add, size: 18,
                        semanticLabel: 'Add sound track')
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16),
                          SizedBox(width: 2),
                          Flexible(
                            child: Text('Sound track',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (overlayTop != null)
            Positioned(
              key: const ValueKey('overlay-row-header'),
              left: 0,
              right: 0,
              top: overlayTop,
              height: rowHeight,
              child: Tooltip(
                message: 'Overlay: pictures over the video',
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (!compact) const SizedBox(width: 8),
                    const Icon(Icons.picture_in_picture_alt,
                        size: 16, color: AppColors.textDim),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text('Overlay',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _dim),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: clipTop,
            height: clipHeight,
            child: _Header(
              session: session,
              track: p.videoSound,
              compact: compact,
              icon: Icons.movie_outlined,
              label: 'Video',
            ),
          ),
          for (var i = 0; i < tracks.length; i++)
            Positioned(
              left: 0,
              right: 0,
              top: audioTop + i * (rowHeight + rowGap),
              height: rowHeight,
              child: _Header(
                session: session,
                track: tracks[i],
                compact: compact,
                icon: tracks[i].speech ? Icons.mic_none : Icons.music_note,
                label: tracks[i].name,
              ),
            ),
          if (tracks.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: audioTop,
              height: rowHeight,
              child: const Center(
                child: Icon(Icons.music_note, size: 16, color: AppColors.textDim),
              ),
            ),
          for (var i = 0; i < titleRows; i++)
            Positioned(
              left: 0,
              right: 0,
              top: titleTop + i * (rowHeight + rowGap),
              height: rowHeight,
              child: i > 0
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: compact
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        if (!compact) const SizedBox(width: 8),
                        const Icon(Icons.title, size: 16, color: AppColors.textDim),
                        if (!compact) ...[
                          const SizedBox(width: 6),
                          const Text('Titles', style: _dim),
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// One row header: on phones a button that opens the track menu and shows
/// its state; on wider windows the name (opens the menu), mute and solo.
class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.track,
    required this.compact,
    required this.icon,
    required this.label,
  });
  final EditorSession session;
  final SoundTrack track;
  final bool compact;
  final IconData icon;
  final String label;

  bool get _video => track.id == SoundTrack.videoId;

  @override
  Widget build(BuildContext context) {
    final p = session.project;
    final heard = p.trackGain(track) > 0;
    final editor = session.editor;
    final state = [
      if (track.muted) 'muted',
      if (track.solo) 'solo',
      if (!track.muted && !heard) 'not heard',
    ].join(', ');
    final name = _video ? 'Video sound' : '${track.name} track';
    void open() => showSoundTrackMenu(context, session, track.id);
    if (compact) {
      return Semantics(
        label: '$name${state.isEmpty ? '' : ', $state'}',
        button: true,
        child: InkWell(
          key: ValueKey('track-header-${track.id}'),
          onTap: open,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                track.muted ? Icons.volume_off : icon,
                size: 18,
                color: heard ? Colors.white : AppColors.textDim,
              ),
              if (track.solo)
                const Positioned(
                  right: 4,
                  top: 2,
                  child: Text('S',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent)),
                ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: '$name: volume, mute, solo${_video ? '' : ', rename'}',
            child: InkWell(
              key: ValueKey('track-header-${track.id}'),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Row(
                  children: [
                    Icon(icon, size: 14,
                        color: heard ? AppColors.textDim : const Color(0x669AA0AC)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: heard ? Colors.white : AppColors.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Toggle(
          key: ValueKey('track-mute-${track.id}'),
          on: track.muted,
          label: 'M',
          tip: track.muted ? 'Unmute $name' : 'Mute $name',
          onColor: AppColors.danger,
          onTap: () => editor.setSoundTrack(track.id, muted: !track.muted),
        ),
        _Toggle(
          key: ValueKey('track-solo-${track.id}'),
          on: track.solo,
          label: 'S',
          tip: track.solo ? 'Solo off' : 'Hear only $name',
          onColor: AppColors.accent,
          onTap: () => editor.setSoundTrack(track.id, solo: !track.solo),
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.on,
    required this.label,
    required this.tip,
    required this.onColor,
    required this.onTap,
  });
  final bool on;
  final String label;
  final String tip;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Semantics(
        label: tip,
        button: true,
        toggled: on,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? onColor : AppColors.panelHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: on ? Colors.black : AppColors.textDim)),
          ),
        ),
      ),
    );
  }
}

/// "Add sound track": adds the next of Voice / Music / Effects and opens
/// its menu, so it can be renamed right away.
void addSoundTrack(BuildContext context, EditorSession s) {
  final id = s.editor.addSoundTrack();
  if (id == null) return;
  final t = s.project.trackById(id)!;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text('Added the ${t.name} track. Tap its name for '
            'volume, mute, solo and more.'),
        duration: const Duration(seconds: 3)));
}

bool _phone(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// The track menu: name, volume, mute, solo, "Lower this track under
/// speech", "Counts as speech", delete. A sheet on phones, a dialog on
/// computers. [trackId] [SoundTrack.videoId] is the video's own sound.
Future<void> showSoundTrackMenu(
    BuildContext context, EditorSession s, String trackId) {
  final body = _TrackMenu(session: s, trackId: trackId);
  if (_phone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black26,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(child: body),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SizedBox(width: 380, child: SingleChildScrollView(child: body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _TrackMenu extends StatefulWidget {
  const _TrackMenu({required this.session, required this.trackId});
  final EditorSession session;
  final String trackId;

  @override
  State<_TrackMenu> createState() => _TrackMenuState();
}

class _TrackMenuState extends State<_TrackMenu> {
  late final TextEditingController _name;

  EditorSession get _s => widget.session;
  bool get _video => widget.trackId == SoundTrack.videoId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: _s.project.trackById(widget.trackId)?.name ?? '');
  }

  @override
  void dispose() {
    _rename();
    _name.dispose();
    super.dispose();
  }

  void _rename() {
    if (_video) return;
    final t = _s.project.trackById(widget.trackId);
    if (t != null && _name.text.trim().isNotEmpty && _name.text.trim() != t.name) {
      _s.editor.renameSoundTrack(t.id, _name.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s.editor,
      builder: (context, _) {
        final p = _s.project;
        final t = p.trackById(widget.trackId);
        if (t == null) return const SizedBox(height: 8);
        final editor = _s.editor;
        final items = p.clipsOnTrack(t.id).length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_video ? Icons.movie_outlined : Icons.graphic_eq, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_video ? 'Video sound' : 'Sound track',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const HelpHint('sound-tracks', label: 'Sound tracks'),
              ],
            ),
            const SizedBox(height: 8),
            if (_video)
              const Text(
                  'The sound of all video clips together. Each clip keeps '
                  'its own volume in its Sound settings.',
                  style: _dim)
            else
              TextField(
                key: const ValueKey('track-name'),
                controller: _name,
                maxLength: EditorController.maxTrackNameLength,
                decoration: const InputDecoration(
                    labelText: 'Name', counterText: '', isDense: true),
                onSubmitted: (_) => _rename(),
                onTapOutside: (_) => _rename(),
              ),
            const SizedBox(height: 8),
            LiveSlider(
              key: const ValueKey('track-volume'),
              editor: editor,
              label: 'Volume',
              value: t.volume,
              min: EditorController.minVolume,
              max: EditorController.maxVolume,
              display: (v) => '${(v * 100).round()}%',
              onChanged: (v) => editor.setSoundTrack(t.id, volume: v),
            ),
            SwitchListTile(
              key: const ValueKey('track-menu-mute'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Mute'),
              value: t.muted,
              onChanged: (v) => editor.setSoundTrack(t.id, muted: v),
            ),
            SwitchListTile(
              key: const ValueKey('track-menu-solo'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Solo'),
              subtitle: const Text(
                  'Hear only the solo tracks, also in the export.',
                  style: _dim),
              value: t.solo,
              onChanged: (v) => editor.setSoundTrack(t.id, solo: v),
            ),
            if (!_video) ...[
              SwitchListTile(
                key: const ValueKey('track-menu-duck'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const LabelWithHint('Lower this track under speech',
                    articleId: 'lower-music'),
                subtitle: const Text(
                    'Gets quieter while the video sound or a speech track '
                    'plays. Applied when you export.',
                    style: _dim),
                value: t.duck,
                onChanged: (v) => editor.setSoundTrack(t.id, duck: v),
              ),
              SwitchListTile(
                key: const ValueKey('track-menu-speech'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('This track is speech'),
                subtitle: const Text(
                    'Tracks set to lower under speech get quieter while it '
                    'plays.',
                    style: _dim),
                value: t.speech,
                onChanged: (v) => editor.setSoundTrack(t.id, speech: v),
              ),
              const SizedBox(height: 4),
              Builder(builder: (context) {
                final order = _s.project.soundTracks;
                final at = order.indexWhere((x) => x.id == t.id);
                return Row(
                  children: [
                    TextButton.icon(
                      key: const ValueKey('track-menu-up'),
                      onPressed: at > 0
                          ? () => editor.moveSoundTrack(t.id, -1)
                          : null,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: const Text('Move up'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('track-menu-down'),
                      onPressed: at >= 0 && at < order.length - 1
                          ? () => editor.moveSoundTrack(t.id, 1)
                          : null,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      label: const Text('Move down'),
                    ),
                  ],
                );
              }),
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('track-menu-delete'),
                    onPressed: items == 0
                        ? () {
                            Navigator.of(context).maybePop();
                            editor.removeSoundTrack(t.id);
                          }
                        : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete track'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                  ),
                  if (items > 0)
                    Expanded(
                      child: Text(
                        'Move or delete its ${items == 1 ? 'sound' : '$items sounds'} first.',
                        style: _dim,
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

// Separate sound -------------------------------------------------------------

/// The part of a video clip's Sound panel about separating: "Separate sound
/// to track…", or where its sound went with "Show the sound" and "Put it
/// back".
class SeparateSoundRow extends StatelessWidget {
  const SeparateSoundRow({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final p = session.project;
    final separated = clip.muted
        ? p.audio
            .where((a) => a.isSeparated && a.sourceClipId == clip.id)
            .firstOrNull
        : null;
    if (separated != null) {
      final track = p.trackById(separated.trackId)?.name ?? 'a sound';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split, size: 18, color: AppColors.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'The sound of this clip is on the $track track'
                    '${separated.linked ? ' and follows the clip' : ''}.',
                    style: _dim),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const ValueKey('show-separated-sound'),
                onPressed: () => session.select(ItemKind.audio, separated.id),
                child: const Text('Show the sound'),
              ),
              TextButton(
                key: const ValueKey('reattach-sound'),
                onPressed: () => session.editor.reattachSound(separated.id),
                child: const Text('Put it back on the clip'),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinkedVoiceRow(session: session, clip: clip),
        _separateButton(context),
      ],
    );
  }

  Widget _separateButton(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          key: const ValueKey('separate-sound'),
          onPressed: () => separateSound(context, session, clip),
          icon: const Icon(Icons.call_split, size: 18),
          label: const Text('Separate sound to track…'),
        ),
        const SizedBox(width: 4),
        const HelpHint('separate-sound', label: 'Separate sound'),
      ],
    );
  }
}

/// "Separate sound to track…": asks which track (and whether for all
/// video clips), then separates as one undo step and selects the sound.
Future<void> separateSound(
    BuildContext context, EditorSession s, Clip clip) async {
  s.playback.pause();
  final problem = EditorController.separateSoundProblem(s.project, clip.id);
  if (problem != null) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(problem)));
    return;
  }
  final choice = await showDialog<({String? trackId, bool all})>(
    context: context,
    builder: (_) => _SeparateDialog(session: s, clip: clip),
  );
  if (choice == null || !context.mounted) return;
  final before = {for (final a in s.project.audio) a.id};
  if (choice.all) {
    s.editor.separateAllSound(trackId: choice.trackId);
  } else {
    s.editor.separateSound(clip.id, trackId: choice.trackId);
  }
  final added = [
    for (final a in s.project.audio)
      if (!before.contains(a.id)) a,
  ];
  if (added.isEmpty) return;
  final mine = added.where((a) => a.sourceClipId == clip.id).firstOrNull ??
      added.first;
  final track = s.project.trackById(mine.trackId)?.name ?? 'sound';
  s.select(ItemKind.audio, mine.id);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(added.length == 1
            ? 'The sound is on the $track track now; the clip is muted. '
                'Drag the sound to start it earlier or later.'
            : 'The sound of ${added.length} clips is on the $track track '
                'now; the clips are muted.'),
        duration: const Duration(seconds: 4)));
}

class _SeparateDialog extends StatefulWidget {
  const _SeparateDialog({required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  State<_SeparateDialog> createState() => _SeparateDialogState();
}

class _SeparateDialogState extends State<_SeparateDialog> {
  /// Null: the default (the speech track, or a new Voice track).
  String? _track;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _track = EditorController.defaultVoiceTrack(widget.session.project);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.session.project;
    final tracks = p.soundTracks;
    final room = tracks.length < EditorController.maxSoundTracks;
    final others = p.clips
        .where((c) =>
            c.id != widget.clip.id &&
            !c.muted &&
            EditorController.separateSoundProblem(p, c.id) == null)
        .length;
    return AlertDialog(
      title: const Text('Separate sound'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'The clip\'s sound goes to a sound track, where you can '
                  'move and trim it on its own. The clip is muted.'),
              const SizedBox(height: 12),
              const Text('Put it on', style: _dim),
              RadioGroup<String?>(
                groupValue: _track,
                onChanged: (v) => setState(() => _track = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in tracks)
                      RadioListTile<String?>(
                        key: ValueKey('separate-to-${t.id}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: t.id,
                        title: Text('${t.name} track'),
                      ),
                    if (room && !tracks.any((t) => t.speech))
                      const RadioListTile<String?>(
                        key: ValueKey('separate-to-new'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: null,
                        title: Text('A new Voice track'),
                      ),
                  ],
                ),
              ),
              if (others > 0)
                CheckboxListTile(
                  key: const ValueKey('separate-all'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _all,
                  onChanged: (v) => setState(() => _all = v ?? false),
                  title: Text('Also the other ${others == 1 ? 'clip' : '$others clips'} with sound'),
                ),
              if (widget.clip.speed != 1)
                Text(
                    'The sound keeps the clip\'s speed '
                    '(${widget.clip.speed}×).',
                    style: _dim),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('separate-confirm'),
          onPressed: () =>
              Navigator.of(context).pop((trackId: _track, all: _all)),
          child: const Text('Separate'),
        ),
      ],
    );
  }
}

// Sound clip panel -----------------------------------------------------------

/// Where a sound clip is and the clip-like sound options it has: its track,
/// clean-up, voice focus, sound from, and for a separated sound "Put back
/// on the clip".
class SoundClipOptions extends StatelessWidget {
  const SoundClipOptions({super.key, required this.session, required this.audio});
  final EditorSession session;
  final AudioClip audio;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final p = session.project;
    final tracks = p.soundTracks;
    final a = audio;
    final track = p.trackById(a.trackId);
    final sound = a.soundClip;
    final stereo = sound.audioChannelsInUse == 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabelWithHint('Track',
            articleId: 'sound-tracks',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tracks)
              ChoicePill(
                key: ValueKey('move-to-${t.id}'),
                label: t.name,
                selected: t.id == a.trackId,
                onTap: () => editor.moveAudioToTrack(a.id, t.id),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (track != null)
          SwitchListTile(
            key: const ValueKey('sound-duck'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: LabelWithHint('Lower ${track.name} under speech',
                articleId: 'lower-music'),
            subtitle: const Text('For the whole track. Applied when you export.',
                style: _dim),
            value: track.duck,
            onChanged: (v) => editor.setSoundTrack(track.id, duck: v),
          ),
        if (a.isVoice) ...[
          const Divider(height: 20),
          VoicePanel(session: session, audio: a),
        ],
        if (a.isSeparated) ...[
          const Divider(height: 20),
          Text(
              a.linked
                  ? 'Sound of a video clip. It follows the clip until you '
                      'move or trim it here.'
                  : 'Sound of a video clip. It stays where you put it.',
              style: _dim),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('reattach-from-sound'),
              onPressed: p.clips.any((c) => c.id == a.sourceClipId)
                  ? () => editor.reattachSound(a.id)
                  : null,
              icon: const Icon(Icons.merge_type, size: 18),
              label: const Text('Put back on the clip'),
            ),
          ),
        ],
        const Divider(height: 20),
        SwitchListTile(
          key: const ValueKey('sound-denoise'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const LabelWithHint('Clean up sound', articleId: 'clean-up-sound'),
          value: a.denoise,
          onChanged: (v) => editor.setAudioDenoise(a.id, v),
        ),
        LiveSlider(
          key: const ValueKey('sound-voice-focus'),
          editor: editor,
          label: 'Voice focus',
          helpArticle: 'voice-focus',
          value: a.voiceFocus,
          min: EditorController.minVoiceFocus,
          max: EditorController.maxVoiceFocus,
          display: (v) => v < 0.005 ? 'Off' : '${(v * 100).round()}%',
          onChanged: (v) =>
              editor.setAudioVoiceFocus(a.id, (v * 20).round() / 20),
        ),
        SoundProcessingRow(session: session, clip: sound),
        if (sound.audioStreams.length > 1 || stereo) ...[
          const SizedBox(height: 4),
          LabelWithHint('Sound from',
              articleId: 'sound-from',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (sound.audioStreams.length > 1)
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < sound.audioStreams.length; i++)
                  ChoicePill(
                    label: 'Track ${i + 1}',
                    selected: i == sound.audioTrackInUse,
                    onTap: () => editor.setAudioSource(a.id, track: i),
                  ),
              ],
            ),
          if (stereo) ...[
            const SizedBox(height: 8),
            ChoiceRow<AudioChannel>(
              values: AudioChannel.values,
              label: audioChannelLabel,
              selected: sound.audioChannelInUse,
              onSelected: (v) => editor.setAudioSource(a.id, channel: v),
            ),
          ],
        ],
      ],
    );
  }
}
