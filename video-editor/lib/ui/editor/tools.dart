import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/model/project.dart';
import '../../core/model/title_layout.dart';
import '../app_prefs.dart';
import '../format.dart';
import '../playback/media_kit_backend.dart' show MediaKitBackend;
import '../help/help_screen.dart';
import '../help/tour.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'clip_panels.dart';
import 'import_actions.dart';
import 'music_actions.dart';
import 'history_panel.dart';
import 'picture_tools.dart';
import 'session.dart';
import 'sound_tracks_ui.dart';
import 'voice_actions.dart';

class ToolAction {
  const ToolAction(this.icon, this.label, this.onTap,
      {this.danger = false, this.tourId});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  /// The [TourIds] id the tour knows this button by.
  final String? tourId;
}

/// The actions that make sense for what is selected right now.
///
/// On phones ([compact]) the settings of the selection open in bottom
/// sheets, so a clip gets one button per group of settings; wide windows
/// show the settings in the side panel and only need the direct actions.
List<ToolAction> buildToolActions(
  BuildContext context,
  EditorSession s, {
  required bool compact,
}) {
  final editor = s.editor;
  final project = s.project;
  final clip = s.selectedClip;
  final audio = s.selectedAudio;
  final title = s.selectedTitle;
  final close = ToolAction(Icons.close, 'Done', s.clearSelection);

  if (clip != null) {
    final isVideo = clip.type == ClipType.video;
    return [
      close,
      if (s.playback.isMissing(clip.path))
        ToolAction(Icons.search, 'Find file',
            () => findMissingFile(context, s, clip.path, audio: false)),
      ToolAction(Icons.content_cut, 'Split', () => splitAtPlayhead(context, s),
          tourId: TourIds.split),
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
        ToolAction(Icons.more_horiz, 'More', () => showClipMoreSheet(context, s)),
      ] else ...[
        if (isVideo)
          ToolAction(Icons.ac_unit, 'Freeze', () => freezeFrame(context, s)),
        ToolAction(Icons.copy_all_outlined, 'Duplicate',
            () => duplicateSelection(context, s)),
      ],
      ToolAction(Icons.delete_outline, 'Delete',
          () => editor.removeClip(clip.id),
          danger: true),
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
      ToolAction(Icons.delete_outline, 'Delete',
          () => editor.removeOverlay(overlay.id),
          danger: true),
    ];
  }
  if (audio != null) {
    return [
      close,
      if (s.playback.isMissing(audio.path))
        ToolAction(Icons.search, 'Find file',
            () => findMissingFile(context, s, audio.path, audio: true)),
      if (compact)
        ToolAction(Icons.edit_outlined, 'Edit',
            () => showPropertiesSheet(context, s)),
      ToolAction(Icons.delete_outline, 'Delete',
          () => editor.removeAudio(audio.id),
          danger: true),
    ];
  }
  if (title != null) {
    return [
      close,
      if (compact)
        ToolAction(Icons.edit_outlined, 'Edit',
            () => showPropertiesSheet(context, s)),
      ToolAction(Icons.copy_all_outlined, 'Duplicate',
          () => duplicateSelection(context, s)),
      ToolAction(Icons.delete_outline, 'Delete',
          () => editor.removeTitle(title.id),
          danger: true),
    ];
  }
  return [
    ...buildAddActions(context, s, compact: compact),
    if (project.clips.isNotEmpty)
      ToolAction(Icons.content_cut, 'Split', () => splitAtPlayhead(context, s),
          tourId: TourIds.split),
    // Phones: the less common things (History); wide windows have them in
    // the top bar and the menu bar.
    if (compact && project.clips.isNotEmpty)
      ToolAction(Icons.more_horiz, 'More', () => showEditorMoreSheet(context, s)),
  ];
}

/// Phones, nothing selected: the less common editor actions.
Future<void> showEditorMoreSheet(BuildContext context, EditorSession s) {
  return _showSheet(
    context,
    title: 'More',
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('more-fades'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gradient),
          title: const Text('Fade in and out'),
          subtitle: const Text('Start from black, end in black'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(sheet).pop();
            _showSheet(context,
                title: 'Fade in and out',
                builder: (_) => ListenableBuilder(
                    listenable: s.editor,
                    builder: (_, _) => ProjectFadesPanel(session: s)));
          },
        ),
        _historyTile(context, sheet, s),
        const SmoothPreviewSwitch(),
      ],
    ),
  );
}

/// Phones: "Smooth preview" (see MediaKitBackend.smoothPreview). Takes
/// effect for the clips loaded after it is changed.
class SmoothPreviewSwitch extends ConsumerStatefulWidget {
  const SmoothPreviewSwitch({super.key});

  @override
  ConsumerState<SmoothPreviewSwitch> createState() =>
      _SmoothPreviewSwitchState();
}

class _SmoothPreviewSwitchState extends ConsumerState<SmoothPreviewSwitch> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('more-smooth-preview'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.speed),
      title: const LabelWithHint('Smooth preview', articleId: 'phone-speed'),
      subtitle: const Text(
          'Lighter video decoding while editing; the preview may look a '
          'little softer. Exports are not affected.'),
      value: MediaKitBackend.smoothPreview,
      onChanged: (on) {
        setState(() => MediaKitBackend.smoothPreview = on);
        final prefs = ref.read(appPrefsProvider);
        (on
                ? prefs.clearFlag(kSmoothPreviewOffFlag)
                : prefs.setFlag(kSmoothPreviewOffFlag))
            .catchError((Object _) {});
      },
    );
  }
}

/// "History" in a More sheet: closes the sheet and opens the history.
Widget _historyTile(BuildContext context, BuildContext sheet, EditorSession s) =>
    ListTile(
      key: const ValueKey('more-history'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: const Text('History'),
      subtitle: const Text('Your changes; go back to any of them'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(sheet).pop();
        showHistorySheet(context, s);
      },
    );

/// The things that can be added to the project. Always within reach: the
/// tool bar and the side panel show them when nothing is selected, the "+"
/// button next to Play (phones) and the "Add" row of the side panel show
/// them whatever is selected.
List<ToolAction> buildAddActions(
  BuildContext context,
  EditorSession s, {
  required bool compact,
}) {
  return [
    ToolAction(Icons.add_photo_alternate_outlined, 'Add media',
        () => addMedia(context, s),
        tourId: TourIds.addMedia),
    if (s.project.clips.isNotEmpty) ...[
      ToolAction(Icons.library_music_outlined, 'Music',
          () => showAddMusic(context, s)),
      ToolAction(Icons.picture_in_picture_alt, 'Overlay',
          () => addOverlay(context, s)),
      ToolAction(Icons.title, 'Title', () {
        addTitle(s);
        if (compact) showPropertiesSheet(context, s);
      }),
      ToolAction(Icons.closed_caption_outlined, 'Captions',
          () => showCaptionsDialog(context, s)),
    ],
  ];
}

/// Phones: the "+" button. Lists what can be added without giving up the
/// selection first.
Future<void> showAddSheet(BuildContext context, EditorSession s) {
  s.playback.pause();
  final selected = s.selectedClip != null;
  return _showSheet(
    context,
    title: 'Add',
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in buildAddActions(context, s, compact: true))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(a.icon),
            title: Text(switch (a.label) {
              'Add media' => 'Videos or photos',
              'Captions' => 'Caption',
              'Overlay' => 'Overlay (picture-in-picture)',
              _ => a.label,
            }),
            subtitle: Text(switch (a.label) {
              'Add media' => s.project.clips.isEmpty
                  ? 'Start the video'
                  : selected
                      ? 'Go in after the selected clip'
                      : 'Go in after the clip at the playhead',
              'Music' => 'Starts at the playhead',
              'Overlay' =>
                'A video or photo over the picture, at the playhead',
              'Title' => 'Text over the picture, at the playhead',
              _ => 'A line of subtitles, or a subtitle file',
            }),
            onTap: () {
              Navigator.of(sheet).pop();
              a.onTap?.call();
            },
          ),
      ],
    ),
  );
}

// Bottom sheets (phones) ------------------------------------------------------

Future<void> _showSheet(BuildContext context,
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
  return _showSheet(
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
  return _showSheet(
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
  return _showSheet(
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

/// The less common clip actions.
Future<void> showClipMoreSheet(BuildContext context, EditorSession s) {
  return _showSheet(
    context,
    title: 'More',
    builder: (sheet) => ListenableBuilder(
      listenable: Listenable.merge([s.editor, s.selection]),
      builder: (_, _) {
        final clip = s.selectedClip;
        if (clip == null) return const SizedBox(height: 8);
        final project = s.project;
        final index = project.clips.indexOf(clip);
        void close() => Navigator.of(sheet).pop();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('more-crop'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(clipToolIcon(ClipTool.crop)),
              title: const Text('Crop and position'),
              subtitle: Text(clip.framing.isDefault
                  ? 'Crop, rotate, flip, choose what stays in the frame'
                  : framingSummary(clip.framing)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                close();
                showCropSheet(context, s, clip.id);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(clipToolIcon(ClipTool.transition)),
              title: const Text('Transition and fades'),
              subtitle: Text(index <= 0
                  ? 'Fade in from black, fade out'
                  : 'From the clip before: '
                      '${clipToolSummary(ClipTool.transition, clip, project)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                close();
                showClipToolSheet(context, s, ClipTool.transition);
              },
            ),
            if (clip.type == ClipType.video)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ac_unit),
                title: const Text('Freeze frame'),
                subtitle: Text('Hold the picture at the playhead for '
                    '${formatLength(kFreezeFrameMs)}'),
                onTap: () {
                  close();
                  freezeFrame(context, s);
                },
              ),
            ListTile(
              key: const ValueKey('more-duplicate'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Duplicate'),
              subtitle: const Text('A copy right after this clip'),
              onTap: () {
                close();
                duplicateSelection(context, s);
              },
            ),
            ListTile(
              key: const ValueKey('more-copy-settings'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy settings'),
              subtitle: const Text('Look, speed, sound, crop and fit'),
              onTap: () {
                close();
                copyClipSettings(context, s);
              },
            ),
            if (s.copiedSettings.value != null)
              ListTile(
                key: const ValueKey('more-paste-settings'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_paste),
                title: const Text('Paste settings'),
                subtitle: const Text('Give this clip the copied settings'),
                onTap: () {
                  close();
                  pasteClipSettings(context, s);
                },
              ),
            _historyTile(context, sheet, s),
            const Divider(height: 16),
            _MoveRow(session: s, index: index),
          ],
        );
      },
    ),
  );
}

/// Buttons to change a clip's place; the same as dragging it on the timeline.
class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.session, required this.index});
  final EditorSession session;
  final int index;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final last = session.project.clips.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: index > 0
                    ? () => editor.moveClip(index, index - 1)
                    : null,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Move earlier'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: index >= 0 && index < last
                    ? () => editor.moveClip(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Move later'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'You can also hold a clip on the timeline and drag it to a new '
          'place.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }
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
    return id == null ? button : TourAnchor(id: id, child: button);
  }
}

/// Bottom tool bar for narrow screens.
class ToolBar extends StatelessWidget {
  const ToolBar({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session.editor, session.selection]),
      builder: (context, _) {
        final actions = buildToolActions(context, session, compact: true);
        return Container(
          height: 68,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          // Everything stays reachable without scrolling on a phone: the
          // buttons share the width, and only scroll if they would get too
          // small to hit.
          child: LayoutBuilder(
            builder: (context, box) {
              final each = ((box.maxWidth - 16) / actions.length)
                  .clamp(52.0, 88.0)
                  .toDouble();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth - 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final a in actions) _ToolButton(a, width: each),
                    ],
                  ),
                ),
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
      listenable: Listenable.merge(
          [session.editor, session.selection, session.openTool]),
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

/// "Lower music under speech" for the whole project: every sound track that
/// is not a speech track (each track also has its own switch in its menu).
class DuckMusicSwitch extends StatelessWidget {
  const DuckMusicSwitch({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelLabel('All music in this project'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const LabelWithHint('Lower music under speech',
              articleId: 'lower-music'),
          subtitle: const Text(
            'Every music track gets quieter while the video sound or the '
            'Voice track plays. Applied when you export.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          value: _allLowered(session.project),
          onChanged: session.editor.setDuckMusic,
        ),
      ],
    );
  }
}

bool _allLowered(Project p) {
  final music = [for (final t in p.soundTracks) if (!t.speech) t];
  return music.isEmpty ? p.duckMusic : music.every((t) => t.duck);
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
