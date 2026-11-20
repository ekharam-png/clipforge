import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/editor/sound_tracks.dart';
import '../../core/model/project.dart';
import '../../core/model/title_layout.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../help/tour.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'action_sheets.dart';
import 'clip_panels.dart';
import 'editor_actions.dart';
import 'import_actions.dart';
import 'music_actions.dart';
import 'picture_tools.dart';
import 'publishing_panel.dart';
import 'shorts_actions.dart';
import 'session.dart';
export 'action_sheets.dart';
import 'sound_tracks_ui.dart';
import 'voice_actions.dart';

class ToolAction {
  const ToolAction(this.icon, this.label, this.onTap,
      {this.danger = false, this.tourId, this.reason, this.key});

  /// Why it is greyed out (its tooltip then says so).
  final String? reason;
  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  /// The [TourIds] id the tour knows this button by.
  final String? tourId;
}

/// The actions that make sense for what is selected right now.
///
/// On phones ([compact]) the bar shows the most-used actions of the
/// selection and "More" (everything else, grouped like the computer's
/// menus); with nothing selected: Add, Text, Split, More. Wide windows
/// show the settings in the side panel and only need the direct actions.
/// Whether an action can be done comes from [EditorActions].
List<ToolAction> buildToolActions(
  BuildContext context,
  EditorSession s, {
  required bool compact,
}) {
  final actions = EditorActions(s);
  final clip = s.selectedClip;
  final audio = s.selectedAudio;
  final title = s.selectedTitle;
  final close = ToolAction(Icons.close, 'Done', s.clearSelection);
  ToolAction of(Act a, {String? label, String? tourId}) {
    final e = actions.entry(context, a);
    return ToolAction(e.icon, label ?? actName(a), e.onTap,
        danger: e.danger, tourId: tourId, reason: e.reason);
  }

  final more = ToolAction(
      Icons.more_horiz, 'More', () => showMoreSheet(context, s),
      key: const ValueKey('tool-more'));
  final delete = of(Act.delete);

  if (clip != null) {
    final isVideo = clip.type == ClipType.video;
    return [
      close,
      if (s.playback.isMissing(clip.path))
        ToolAction(Icons.search, 'Find file',
            () => findMissingFile(context, s, clip.path, audio: false)),
      of(Act.split, tourId: TourIds.split),
      if (compact) ...[
        for (final tool in clipToolsFor(clip))
          // Transition and Crop live under "More" so the bar stays
          // readable.
          if (tool != ClipTool.transition && tool != ClipTool.crop)
            ToolAction(clipToolIcon(tool), clipToolLabel(tool),
                () => showClipToolSheet(context, s, tool),
                tourId: switch (tool) {
                  ClipTool.speed => TourIds.toolSpeed,
                  ClipTool.look => TourIds.toolLook,
                  ClipTool.sound => TourIds.toolSound,
                  _ => null,
                }),
        more,
      ] else ...[
        if (isVideo) of(Act.freezeFrame, label: 'Freeze'),
        of(Act.duplicate),
      ],
      delete,
    ];
  }
  final overlay = s.selectedOverlay;
  if (overlay != null) {
    return [
      close,
      if (s.playback.isMissing(overlay.path))
        ToolAction(Icons.search, 'Find file',
            () => findMissingFile(context, s, overlay.path, audio: false)),
      if (compact)
        for (final tool in overlayToolsFor(overlay))
          ToolAction(
              overlayToolIcon(tool),
              tool == ClipTool.sound
                  ? (overlay.clip.type == ClipType.photo ? 'Fades' : 'Sound')
                  : overlayToolLabel(tool, overlay),
              () => tool == ClipTool.crop
                  ? showCropSheet(context, s, overlay.id)
                  : showOverlayToolSheet(context, s, tool)),
      // 1.17: an overlay has a More too (rotate, select its time, history).
      if (compact) more,
      delete,
    ];
  }
  if (audio != null) {
    return [
      close,
      if (s.playback.isMissing(audio.path))
        ToolAction(Icons.search, 'Find file',
            () => findMissingFile(context, s, audio.path, audio: true)),
      if (compact) ...[
        ToolAction(Icons.edit_outlined, 'Edit',
            () => showPropertiesSheet(context, s)),
        if (!audio.belongsToClip) of(Act.fitMusic, label: 'Fit'),
        more,
      ],
      delete,
    ];
  }
  if (title != null) {
    return [
      close,
      if (compact)
        ToolAction(Icons.edit_outlined, 'Edit',
            () => showPropertiesSheet(context, s)),
      of(Act.duplicate),
      if (compact) more,
      delete,
    ];
  }
  if (compact) {
    // Phones, nothing selected: Add, Text, Split, More.
    return [
      ToolAction(Icons.add_circle_outline, 'Add', () => showAddSheet(context, s),
          tourId: TourIds.addMedia, key: const ValueKey('tool-add')),
      ToolAction(Icons.subject, 'Text', () => toggleTextWindow(context, s),
          key: const ValueKey('tool-text')),
      of(Act.split, tourId: TourIds.split),
      more,
    ];
  }
  return [
    ...buildAddActions(context, s, compact: compact),
    if (s.project.clips.isNotEmpty) of(Act.split, tourId: TourIds.split),
  ];
}

/// The things that can be added to the project, as the side panel shows
/// them: when nothing is selected, and in its "Add" row whatever is
/// selected. (Phones: the Add sheet, [showAddSheet].)
List<ToolAction> buildAddActions(
  BuildContext context,
  EditorSession s, {
  required bool compact,
}) {
  final actions = EditorActions(s);
  return [
    ToolAction(Icons.add_photo_alternate_outlined, 'Add media',
        () => actions.run(context, Act.addMedia),
        tourId: TourIds.addMedia),
    if (s.project.clips.isNotEmpty) ...[
      ToolAction(Icons.library_music_outlined, 'Music',
          () => actions.run(context, Act.addMusic)),
      ToolAction(Icons.picture_in_picture_alt, 'Overlay',
          () => actions.run(context, Act.addOverlay)),
      ToolAction(Icons.title, 'Title', () => actions.run(context, Act.addTitle)),
      ToolAction(Icons.closed_caption_outlined, 'Caption',
          () => actions.run(context, Act.addCaption)),
    ],
  ];
}

// Bottom sheets (phones) ------------------------------------------------------

Future<void> showToolSheet(BuildContext context,
    {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The picture stays visible so changes can be judged while sliding:
    // a long panel (a title's settings) scrolls inside the sheet.
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75),
    barrierColor: Colors.black26,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              builder(context),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Properties of the selected music or text.
Future<void> showPropertiesSheet(BuildContext context, EditorSession s) {
  final title = s.selectedTitle;
  return showToolSheet(
    context,
    title: s.selectedAudio != null
        ? (s.selectedAudio!.isVoice
            ? 'Edit voice'
            : s.selectedAudio!.isSeparated
                ? 'Edit sound'
                : 'Edit music')
        : (title?.kind == TitleKind.caption ? 'Edit caption' : 'Edit title'),
    builder: (_) => PropertiesEditor(session: s),
  );
}

/// One group of settings of the selected clip.
Future<void> showClipToolSheet(
    BuildContext context, EditorSession s, ClipTool tool) {
  return showToolSheet(
    context,
    title: clipToolLabel(tool),
    builder: (_) => ListenableBuilder(
      listenable: Listenable.merge([s.editor, s.selection]),
      builder: (context, _) {
        final clip = s.selectedClip;
        if (clip == null) return const SizedBox(height: 8);
        return ClipToolPanel(session: s, clip: clip, tool: tool);
      },
    ),
  );
}

/// One group of settings of the selected overlay item (phones).
Future<void> showOverlayToolSheet(
    BuildContext context, EditorSession s, ClipTool tool) {
  final o = s.selectedOverlay;
  return showToolSheet(
    context,
    title: o == null ? 'Overlay' : overlayToolLabel(tool, o),
    builder: (_) => ListenableBuilder(
      listenable: Listenable.merge([s.editor, s.selection]),
      builder: (context, _) {
        final overlay = s.selectedOverlay;
        if (overlay == null) return const SizedBox(height: 8);
        return OverlayToolPanel(session: s, overlay: overlay, tool: tool);
      },
    ),
  );
}

/// Phones: "Crop and position" of [itemId] in a sheet that leaves the
/// preview usable, so that the crop frame can be dragged on the picture.
void showCropSheet(BuildContext context, EditorSession s, String itemId,
    {ScaffoldState? scaffold}) {
  s.playback.pause();
  scaffold ??= Scaffold.maybeOf(context);
  if (scaffold == null) return;
  final height = MediaQuery.sizeOf(context).height;
  scaffold.showBottomSheet(
    (sheet) => ConstrainedBox(
      key: const ValueKey('crop-sheet'),
      constraints: BoxConstraints(maxHeight: height * 0.45),
      child: Material(
        color: AppColors.panel,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Crop and position',
                          style: Theme.of(sheet).textTheme.titleMedium),
                    ),
                    TextButton(
                      key: const ValueKey('crop-sheet-done'),
                      onPressed: () => Navigator.of(sheet).maybePop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: CropPanel(session: s, itemId: itemId),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    backgroundColor: AppColors.panel,
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(this.action, {this.width = 72});
  final ToolAction action;
  final double width;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final color = !enabled
        ? AppColors.textDim.withValues(alpha: 0.4)
        : (action.danger ? AppColors.danger : Colors.white);
    final id = action.tourId;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      // excludeSemantics drops the InkWell's own tap action, so the button
      // needs one here, or assistive tools and automation (which press
      // buttons through accessibility) find a button that does nothing.
      onTap: action.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
    final reason = action.reason;
    final keyed = KeyedSubtree(
      key: action.key,
      child: reason == null
          ? button
          : Tooltip(message: '${action.label}: $reason', child: button),
    );
    return id == null ? keyed : TourAnchor(id: id, child: keyed);
  }
}

/// Bottom tool bar for narrow screens. Every button is at least 48 wide
/// and 60 high. The buttons share the width; when there are too many to
/// fit (a clip with a missing file on a small phone) the bar scrolls and
/// its right edge fades out with an arrow, so nothing hides unannounced.
class ToolBar extends StatelessWidget {
  const ToolBar({super.key, required this.session});
  final EditorSession session;

  static const double minButtonWidth = 48;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        session.editor, session.selection, session.copiedSettings, //
        session.playheadClip,
      ]),
      builder: (context, _) {
        final actions = buildToolActions(context, session, compact: true);
        return Container(
          height: 68,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final room = box.maxWidth - 16;
              final each = (room / actions.length)
                  .clamp(minButtonWidth, 96.0)
                  .toDouble();
              final scrolls = each * actions.length > room + 0.5;
              final bar = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: room),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final a in actions) _ToolButton(a, width: each),
                    ],
                  ),
                ),
              );
              if (!scrolls) return bar;
              return Stack(
                children: [
                  bar,
                  Positioned(
                    key: const ValueKey('tool-bar-more-to-the-right'),
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppColors.panel.withValues(alpha: 0),
                            AppColors.panel,
                          ]),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.chevron_right,
                              size: 18, color: AppColors.textDim),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Side panel for wide windows: the actions plus the properties, inline.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        session.editor, session.selection, session.openTool, //
        session.playheadClip, session.copiedSettings,
      ]),
      builder: (context, _) {
        final actions = buildToolActions(context, session, compact: false);
        final selection = session.selection.value;
        final clip = session.selectedClip;
        final heading = switch (selection?.kind) {
          ItemKind.clip => clip?.type == ClipType.photo ? 'Photo' : 'Video clip',
          ItemKind.audio =>
            session.selectedAudio?.isVoice == true
                ? 'Voice'
                : session.selectedAudio?.isSeparated == true
                    ? 'Sound'
                    : 'Music',
          ItemKind.title =>
            session.selectedTitle?.kind == TitleKind.caption
                ? 'Caption'
                : 'Title',
          ItemKind.overlay => session.selectedOverlay?.clip.type ==
                  ClipType.photo
              ? 'Overlay photo'
              : 'Overlay video',
          null => 'Project',
        };
        final overlay = session.selectedOverlay;
        return Material(
          color: AppColors.panel,
          child: SingleChildScrollView(
            // A new selection starts at the top again.
            key: ValueKey(selection),
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(heading, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(children: [for (final a in actions) _ToolButton(a)]),
              if (selection != null) ...[
                // Adding things does not need "Done" first.
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text('Add',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 12)),
                    ),
                    for (final a
                        in buildAddActions(context, session, compact: false))
                      TextButton.icon(
                        onPressed: a.onTap,
                        icon: Icon(a.icon, size: 16),
                        label: Text(a.label,
                            style: const TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (selection == null) ...[
                Text(
                  session.project.clips.isEmpty
                      ? 'Add videos or photos to get started.'
                      : 'Select a clip, an overlay, a sound or a title on '
                          'the timeline to change it.',
                  style: const TextStyle(color: AppColors.textDim),
                ),
                if (session.project.clips.isNotEmpty) ...[
                  const Divider(height: 32),
                  ProjectFadesPanel(session: session),
                ],
                if (session.project.audio.isNotEmpty) ...[
                  const Divider(height: 32),
                  DuckMusicSwitch(session: session),
                ],
                if (session.project.clips.isNotEmpty) ...[
                  const Divider(height: 32),
                  ShortsPanel(session: session, host: context, notes: true),
                ],
              ] else if (clip != null)
                ..._clipSections(clip)
              else if (overlay != null)
                ..._overlaySections(overlay)
              else
                PropertiesEditor(session: session),
            ],
            ),
          ),
        );
      },
    );
  }

  /// The overlay item's groups of settings, one open at a time.
  List<Widget> _overlaySections(OverlayClip overlay) {
    final tools = overlayToolsFor(overlay);
    final wanted = session.openTool.value;
    final open = tools.contains(wanted) ? wanted : tools.first;
    return [
      for (final tool in tools)
        _Section(
          icon: overlayToolIcon(tool),
          title: overlayToolLabel(tool, overlay),
          summary: overlayToolSummary(tool, overlay),
          open: tool == open,
          onToggle: () => session.openTool.value = tool,
          child: OverlayToolPanel(
              session: session, overlay: overlay, tool: tool),
        ),
      const Divider(),
      const SizedBox(height: 12),
      Text(
        'Length ${formatLength(overlay.durationMs)} — drag the ends on the '
        'overlay row to trim, drag it to move it.',
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
    ];
  }

  /// The clip's groups of settings, one open at a time.
  List<Widget> _clipSections(Clip clip) {
    final tools = clipToolsFor(clip);
    final wanted = session.openTool.value;
    final open = tools.contains(wanted) ? wanted : tools.first;
    final project = session.project;
    return [
      for (final tool in tools)
        _Section(
          icon: clipToolIcon(tool),
          title: clipToolLabel(tool),
          summary: clipToolSummary(tool, clip, project),
          open: tool == open,
          onToggle: () => session.openTool.value = tool,
          child: ClipToolPanel(session: session, clip: clip, tool: tool),
        ),
      const Divider(),
      const SizedBox(height: 12),
      Text(
        'Length ${formatLength(clip.durationMs)}'
        '${clip.type == ClipType.video && clip.speed == 1 ? ' of ${formatLength(clip.sourceDurationMs)}' : ''}'
        ' — drag the ends on the timeline to trim, drag the clip to move it.',
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Wrap(
        children: [
          TextButton.icon(
            onPressed: project.clips.indexOf(clip) > 0
                ? () {
                    final i = project.clips.indexOf(clip);
                    session.editor.moveClip(i, i - 1);
                  }
                : null,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Move earlier'),
          ),
          TextButton.icon(
            onPressed: project.clips.indexOf(clip) < project.clips.length - 1
                ? () {
                    final i = project.clips.indexOf(clip);
                    session.editor.moveClip(i, i + 1);
                  }
                : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Move later'),
          ),
        ],
      ),
    ];
  }
}

/// A collapsible group in the side panel.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(),
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.textDim),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (!open)
                    Text(summary,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: AppColors.textDim),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: child,
          ),
      ],
    );
  }
}

/// Property controls for the selected music or text.
class PropertiesEditor extends StatelessWidget {
  const PropertiesEditor({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session.editor, session.selection]),
      builder: (context, _) {
        final audio = session.selectedAudio;
        final title = session.selectedTitle;
        if (audio != null) return _audio(context, audio);
        if (title != null) {
          return _TitleProperties(
              key: ValueKey(title.id), session: session, title: title);
        }
        return const SizedBox(height: 8);
      },
    );
  }

  Widget _audio(BuildContext context, AudioClip audio) {
    final editor = session.editor;
    final maxFade = (audio.durationMs / 2).clamp(100, 10000).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiveSlider(
          editor: editor,
          label: 'Volume',
          value: audio.volume,
          min: EditorController.minVolume,
          max: EditorController.maxVolume,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => editor.updateAudio(audio.copyWith(volume: v)),
        ),
        LiveSlider(
          editor: editor,
          label: 'Fade in',
          value: audio.fadeInMs.toDouble(),
          min: 0,
          max: maxFade,
          display: (v) => formatLength(v.round()),
          onChanged: (v) =>
              editor.updateAudio(audio.copyWith(fadeInMs: v.round())),
        ),
        LiveSlider(
          editor: editor,
          label: 'Fade out',
          value: audio.fadeOutMs.toDouble(),
          min: 0,
          max: maxFade,
          display: (v) => formatLength(v.round()),
          onChanged: (v) =>
              editor.updateAudio(audio.copyWith(fadeOutMs: v.round())),
        ),
        const SizedBox(height: 4),
        Text(
          _audioPlacement(audio),
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        if (!audio.belongsToClip) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.fit_screen_outlined, size: 18),
                label: const LabelWithHint('Fit music to video',
                    articleId: 'fit-music'),
                onPressed: () => fitMusic(context, session, audio.id),
              ),
              if (audio.looped)
                TextButton(
                  onPressed: () => editor.editor.stopLoop(audio.id),
                  child: const Text('Stop looping'),
                ),
            ],
          ),
          if (session.project.clips.any((c) => c.type == ClipType.video))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('line-up-as-voice'),
                icon: const Icon(Icons.record_voice_over, size: 18),
                label: const Text('This is a voice: line up with the video'),
                onPressed: () => lineUpVoice(context, session, audio.id),
              ),
            ),
        ],
        MusicCreditPanel(session: session, audio: audio),
        const Divider(height: 28),
        SoundClipOptions(session: session, audio: audio),
      ],
    );
  }

  String _audioPlacement(AudioClip audio) {
    final end = session.project.durationMs;
    final cut = audio.endMs > end && audio.startMs < end
        ? ' The video ends ${formatLength(audio.endMs - end)} before this '
            'does; the rest is not heard and the fade-out is moved up.'
        : audio.startMs >= end
            ? ' It starts after the video has ended, so it is not heard.'
            : '';
    final loop = audio.looped
        ? ' It repeats its ${formatLength(audio.passMs)} with a short '
            'cross-fade.'
        : '';
    return 'Starts at ${formatTime(audio.startMs)}, plays for '
        '${formatLength(audio.durationMs)}.$loop$cut Drag it on the timeline to '
        'move it (also onto another track), or drag its ends to trim.';
  }
}

/// "Lower music under speech" for the whole project. The truth is each
/// track's own switch (its menu on the timeline); this one shows whether
/// all, some or none of the tracks that are not speech are lowered, and
/// sets them all. The Sound menu shows the same state.
class DuckMusicSwitch extends StatelessWidget {
  const DuckMusicSwitch({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final state = lowerMusicState(session.project);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelLabel('All music in this project'),
        SwitchListTile(
          key: const ValueKey('lower-music-all'),
          contentPadding: EdgeInsets.zero,
          title: const LabelWithHint('Lower music under speech',
              articleId: 'lower-music'),
          subtitle: Text(
            switch (state) {
              LowerMusic.some =>
                'On for some tracks only (set in each track\'s menu). Turn '
                    'this on to lower every music track.',
              _ => 'Every music track gets quieter while the video sound or '
                  'the Voice track plays. Applied when you export.',
            },
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          value: state == LowerMusic.all,
          // Some -> all on; all -> off.
          onChanged: (_) =>
              session.editor.setDuckMusic(state != LowerMusic.all),
        ),
      ],
    );
  }
}

/// A title's size in words, with the share of the frame's short side that
/// one line of text takes: `Medium · 6%`.
String titleSizeLabel(double fontSize) {
  final word = fontSize < 0.045
      ? 'Small'
      : fontSize < 0.085
          ? 'Medium'
          : fontSize < 0.14
              ? 'Large'
              : 'Huge';
  return '$word · ${(fontSize * 100).round()}%';
}

const List<int> kTitlePalette = [
  0xFFFFFFFF, 0xFF000000, 0xFFFFD60A, 0xFFFF453A, //
  0xFFFF4F9A, 0xFF4F8CFF, 0xFF34C759, 0xFFFF9F0A,
];

class _TitleProperties extends StatefulWidget {
  const _TitleProperties({super.key, required this.session, required this.title});
  final EditorSession session;
  final TitleOverlay title;

  @override
  State<_TitleProperties> createState() => _TitlePropertiesState();
}

class _TitlePropertiesState extends State<_TitleProperties> {
  late final _text = TextEditingController(text: widget.title.text);
  final _focus = FocusNode();
  LiveEdit? _typing;

  EditorController get _editor => widget.session.editor;

  /// The title as it is now (the widget's copy may be a frame old).
  TitleOverlay get _current =>
      widget.session.project.titles
          .where((t) => t.id == widget.title.id)
          .firstOrNull ??
      widget.title;

  @override
  void initState() {
    super.initState();
    // Typing replaces the placeholder of a new title.
    if (_text.text == kDefaultTitleText) {
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    }
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _typing = null;
      } else if (_text.text == kDefaultTitleText) {
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(_TitleProperties old) {
    super.didUpdateWidget(old);
    // Follow changes made elsewhere (undo, redo).
    if (widget.title.text != _text.text && !_focus.hasFocus) {
      _text.text = widget.title.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Text',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            final edit = _typing ??= LiveEdit(_editor);
            edit.apply(
                () => _editor.updateTitle(_current.copyWith(text: value)));
          },
        ),
        const SizedBox(height: 16),
        LiveSlider(
          editor: _editor,
          label: 'Text size',
          value: title.fontSize,
          min: 0.02,
          max: 0.25,
          display: titleSizeLabel,
          onChanged: (v) =>
              _editor.updateTitle(_current.copyWith(fontSize: v)),
        ),
        LabelWithHint('Style',
            articleId: 'text-styles',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('title-styles'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in kTitleStylePresets)
              ChoicePill(
                key: ValueKey('title-style-${p.key}'),
                label: p.label,
                selected: false,
                onTap: () => _editor.updateTitle(p.apply(_current)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const PanelLabel('Font'),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('title-fonts'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in TitleFont.values)
              ChoicePill(
                key: ValueKey('title-font-${f.name}'),
                label: titleFontLabel(f),
                selected: title.font == f,
                onTap: () => _editor.updateTitle(_current.copyWith(font: f)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const PanelLabel('Text colour'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final argb in kTitlePalette)
              _Swatch(
                color: Color(argb),
                selected: title.colorArgb == argb,
                onTap: () =>
                    _editor.updateTitle(_current.copyWith(colorArgb: argb)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bold'),
          value: title.bold,
          onChanged: (v) => _editor.updateTitle(_current.copyWith(bold: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark box behind text'),
          value: title.background,
          onChanged: (v) =>
              _editor.updateTitle(_current.copyWith(background: v)),
        ),
        SwitchListTile(
          key: const ValueKey('title-outline'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Outline'),
          subtitle: const Text('A dark line around the letters',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          value: title.outline,
          onChanged: (v) => _editor.updateTitle(_current.copyWith(
              outline: v,
              // Light text gets a dark line, dark text a light one.
              outlineColorArgb: _isDark(title.colorArgb)
                  ? 0xFFFFFFFF
                  : 0xFF000000)),
        ),
        if (!title.background)
          SwitchListTile(
            key: const ValueKey('title-shadow'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Shadow'),
            value: title.shadow,
            onChanged: (v) =>
                _editor.updateTitle(_current.copyWith(shadow: v)),
          ),
        const SizedBox(height: 4),
        const PanelLabel('Position'),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('title-positions'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in TitlePosition.values)
              ChoicePill(
                key: ValueKey('title-position-${p.name}'),
                label: titlePositionLabel(p),
                selected: (title.y - titlePositionY(p)).abs() < 0.005,
                onTap: () => _editor
                    .updateTitle(_current.copyWith(y: titlePositionY(p))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ChoiceRow<TitleAlign>(
          key: const ValueKey('title-align'),
          values: const [TitleAlign.left, TitleAlign.center, TitleAlign.right],
          label: (a) => switch (a) {
            TitleAlign.left => 'Left',
            TitleAlign.center => 'Centre',
            TitleAlign.right => 'Right',
          },
          selected: title.align,
          onSelected: (a) => _editor.updateTitle(
              _current.copyWith(align: a, x: titleAlignX(a))),
        ),
        const SizedBox(height: 12),
        LabelWithHint('Appear',
            articleId: 'text-styles',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        _AnimationRow(
          key: const ValueKey('title-anim-in'),
          value: title.animIn,
          onSelected: (a) =>
              _editor.updateTitle(_current.copyWith(animIn: a)),
        ),
        const SizedBox(height: 10),
        const PanelLabel('Disappear'),
        const SizedBox(height: 6),
        _AnimationRow(
          key: const ValueKey('title-anim-out'),
          value: title.animOut,
          onSelected: (a) =>
              _editor.updateTitle(_current.copyWith(animOut: a)),
        ),
        const SizedBox(height: 12),
        Text(
          'Shown from ${formatTime(title.startMs)} to '
          '${formatTime(title.endMs)}',
          style: const TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: widget.session.playback.position,
          builder: (context, playhead, _) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed:
                    playhead < title.endMs - EditorController.minDurationMs
                        ? () => _editor
                            .updateTitle(_current.copyWith(startMs: playhead))
                        : null,
                child: const Text('Start at playhead'),
              ),
              OutlinedButton(
                onPressed:
                    playhead > title.startMs + EditorController.minDurationMs
                        ? () => _editor
                            .updateTitle(_current.copyWith(endMs: playhead))
                        : null,
                child: const Text('End at playhead'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Drag the text on the picture to place it.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }
}

bool _isDark(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b < 90;
}

/// None / Fade / Slide up / Pop.
class _AnimationRow extends StatelessWidget {
  const _AnimationRow({super.key, required this.value, required this.onSelected});
  final TitleAnimation value;
  final ValueChanged<TitleAnimation> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceRow<TitleAnimation>(
        values: TitleAnimation.values,
        label: titleAnimationLabel,
        selected: value,
        onSelected: onSelected,
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Text colour',
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.outline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}


/// "Shorts and publishing": the buttons for good-moment markers, shorts
/// and (with [notes]) the publishing notes. In the Project panel on
/// computers (nothing selected), in a sheet from More on phones.
class ShortsPanel extends StatelessWidget {
  const ShortsPanel(
      {super.key, required this.session, required this.host, this.notes = false});
  final EditorSession session;

  /// The editor's context (the dialogs belong there, not to a sheet).
  final BuildContext host;
  final bool notes;

  @override
  Widget build(BuildContext context) {
    final s = session;
    void run(VoidCallback action) {
      // In a sheet: close it first.
      if (!notes) Navigator.of(context).maybePop();
      action();
    }

    return ListenableBuilder(
      listenable: s.editor,
      builder: (context, _) {
        final n = s.project.markers.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notes) const PanelLabel('Shorts and publishing'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (notes)
                  OutlinedButton.icon(
                    key: const ValueKey('panel-mark-moment'),
                    onPressed: () => markGoodMoment(host, s),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(MediaQuery.sizeOf(context).width <
                            kWideLayoutWidth
                        ? 'Good moment marker'
                        : 'Good moment marker (M)'),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('panel-good-moments'),
                  onPressed: () => run(() => showGoodMoments(host, s)),
                  icon: const Icon(Icons.flag, size: 18),
                  label: Text(n == 0 ? 'Good moments…' : 'Good moments ($n)…'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('panel-short-from-here'),
                  onPressed: () => run(() => makeShortFromHere(host, s)),
                  icon: const Icon(Icons.smartphone, size: 18),
                  label: const Text('Make a short from here…'),
                ),
                if (n > 0)
                  OutlinedButton.icon(
                    key: const ValueKey('panel-shorts-from-markers'),
                    onPressed: () => run(() => makeShortsFromMarkers(host, s)),
                    icon: const Icon(Icons.content_cut, size: 18),
                    label: const Text('Make shorts from markers…'),
                  ),
                if (notes)
                  OutlinedButton.icon(
                    key: const ValueKey('panel-publishing-notes'),
                    onPressed: () => showPublishingNotes(host,
                        project: () => s.project,
                        onChanged: s.editor.setPublishingNotes,
                        turns: () => s.speakerTurnsNow),
                    icon: const Icon(Icons.notes, size: 18),
                    label: const Text('Publishing notes…'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
