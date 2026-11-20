import 'package:material_ui/material_ui.dart';

import '../../core/model/project.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'clip_panels.dart';
import 'editor_actions.dart';
import 'export_dialog.dart' show videoSizeLabel;
import 'part_actions.dart';
import 'session.dart';
import 'tools.dart';

// The lists of actions (1.15): the phone's Add sheet and More sheet, the
// project menu's sheets, and the timeline's context menu - a right-click
// on a computer, a long press on a phone, the SAME list either way. Every
// line comes from EditorActions, so a line that cannot be used says why.

/// One action as a line of a sheet: icon, words, and under them the hint
/// or, while it cannot be done, the reason.
class ActionTile extends StatelessWidget {
  const ActionTile(this.entry,
      {super.key, this.label, this.onDone, this.chevron = false});
  final ActionEntry entry;

  /// Other words than the action's own ("Trim start to here").
  final String? label;

  /// Called before the action runs (closes the sheet).
  final VoidCallback? onDone;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final reason = e.reason;
    final hint = actHint(e.act);
    final checked = e.checked;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      enabled: e.enabled,
      leading: Icon(e.icon, color: e.danger && e.enabled ? AppColors.danger : null),
      title: Text(label ?? _plain(e.label),
          style: e.danger && e.enabled
              ? const TextStyle(color: AppColors.danger)
              : null),
      subtitle: reason != null
          ? Text('Not now: $reason')
          : hint == null
              ? null
              : Text(hint),
      trailing: checked != null
          ? Icon(
              e.mixed
                  ? Icons.indeterminate_check_box_outlined
                  : checked
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
              semanticLabel: e.mixed
                  ? 'On for some'
                  : checked
                      ? 'On'
                      : 'Off')
          : chevron
              ? const Icon(Icons.chevron_right)
              : null,
      onTap: e.onTap == null
          ? null
          : () {
              onDone?.call();
              e.onTap!();
            },
    );
  }

  static String _plain(String label) =>
      label.endsWith('…') ? label.substring(0, label.length - 1) : label;
}

/// A heading inside a sheet ("Clip", "Sound", "Text").
class SheetHeading extends StatelessWidget {
  const SheetHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600)),
      );
}

/// Everything that can be added, in the order of the computer's Add menu.
const List<Act> kAddActs = [
  Act.addMedia,
  Act.addMusic,
  Act.addVoice,
  Act.addTitle,
  Act.addCaption,
  Act.importSubtitles,
  Act.addOverlay,
  Act.markMoment,
];

/// Phones: "Add" - ONE sheet listing everything that can be added, with
/// icons and a line of explanation each.
Future<void> showAddSheet(BuildContext context, EditorSession s) {
  s.playback.pause();
  final actions = EditorActions(s);
  final selected = s.selectedClip != null;
  return showToolSheet(
    context,
    title: 'Add',
    builder: (sheet) => Column(
      key: const ValueKey('add-sheet'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in kAddActs)
          ActionTile(
            actions.entry(context, a),
            key: ValueKey('add-${a.name}'),
            label: switch (a) {
              Act.addMedia => 'Videos or photos',
              Act.addMusic => 'Music or sound',
              Act.addVoice => 'Voice recording',
              Act.addCaption => 'Caption',
              Act.importSubtitles => 'Subtitle file (.srt)',
              Act.addOverlay => 'Overlay (picture-in-picture)',
              _ => null,
            },
            onDone: () => Navigator.of(sheet).pop(),
          ),
        if (s.project.clips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              selected
                  ? 'Videos and photos go in after the selected clip; '
                      'everything else starts at the playhead.'
                  : 'Videos and photos go in after the clip at the playhead; '
                      'everything else starts at the playhead.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    ),
  );
}

/// What "More" lists for the selection, grouped under the names of the
/// computer's menus.
List<(String heading, List<Act> acts)> moreGroups(EditorSession s) {
  final speech = s.speech != null;
  // 1.17: select a part of the timeline (then its bar has the actions).
  final talk = s.pictures.speakers.any((t) => t.stretches.isNotEmpty);
  final part = (
    'Part',
    [
      Act.selectPart,
      if (s.selection.value != null) Act.partOfItem,
      if (talk) Act.partTurn,
      if (talk) Act.partPause,
      if (s.project.markers.isNotEmpty) Act.partBetweenMarkers,
      if (s.part.value != null) Act.clearPart,
    ]
  );
  if (s.selectedClip != null) {
    return [
      ('Clip', [
        Act.crop,
        Act.startAtPlayhead,
        Act.endAtPlayhead,
        Act.freezeFrame,
        Act.removeSilences,
        Act.moveEarlier,
        Act.moveLater,
        Act.shortFromHere,
      ]),
      part,
      ('Edit', [Act.duplicate, Act.copySettings, Act.pasteSettings, Act.history]),
      ('Sound', [Act.separateSound, Act.putSoundBack, Act.lowerMusic]),
      ('Text', [Act.textWindow, if (speech) Act.captionsFromSpeech]),
    ];
  }
  if (s.selectedAudio != null) {
    return [
      ('Sound', [
        Act.fitMusic,
        Act.lineUpVoice,
        Act.putSoundBack,
        Act.addSoundTrack,
        Act.lowerMusic,
        Act.onlyWhenSpeaking,
        Act.copyCredits,
      ]),
      part,
      ('Text', [Act.textWindow]),
      ('Edit', [Act.history]),
    ];
  }
  if (s.selectedTitle != null) {
    return [
      ('Text', [Act.textWindow, Act.findInText, Act.exportSubtitles]),
      part,
      ('Edit', [Act.duplicate, Act.history]),
    ];
  }
  if (s.selectedOverlay != null) {
    return [
      ('Clip', [Act.crop, Act.rotateRight]),
      part,
      ('Edit', [Act.history]),
    ];
  }
  return [
    ('Clip', [
      Act.startAtPlayhead,
      Act.endAtPlayhead,
      Act.freezeFrame,
      Act.removeSilences,
      Act.markMoment,
      Act.shortFromHere,
      Act.goodMoments,
    ]),
    part,
    ('Sound', [
      Act.addSoundTrack,
      Act.lowerMusic,
      Act.onlyWhenSpeaking,
      Act.copyCredits,
    ]),
    ('Text', [
      Act.textWindow,
      Act.findInText,
      Act.importSubtitles,
      Act.exportSubtitles,
      if (speech) Act.captionsFromSpeech,
    ]),
    ('Edit', [Act.history]),
  ];
}

/// The words a phone uses where they differ from the menu's ("Start at
/// playhead" is "Trim start to here" under a thumb).
String? _phoneLabel(Act a) => switch (a) {
      Act.startAtPlayhead => 'Trim start to here',
      Act.endAtPlayhead => 'Trim end to here',
      Act.crop => 'Crop and position',
      Act.textWindow => 'Text',
      Act.goodMoments => 'Shorts and good moments',
      Act.selectPart => 'Select part',
      Act.clearPart => 'Clear the part',
      _ => null,
    };

Key? _moreKey(Act a) => switch (a) {
      Act.crop => const ValueKey('more-crop'),
      Act.duplicate => const ValueKey('more-duplicate'),
      Act.copySettings => const ValueKey('more-copy-settings'),
      Act.pasteSettings => const ValueKey('more-paste-settings'),
      Act.history => const ValueKey('more-history'),
      Act.textWindow => const ValueKey('more-text'),
      Act.markMoment => const ValueKey('more-mark-moment'),
      Act.goodMoments => const ValueKey('more-shorts'),
      Act.startAtPlayhead => const ValueKey('more-trim-start'),
      Act.endAtPlayhead => const ValueKey('more-trim-end'),
      _ => ValueKey('more-${a.name}'),
    };

/// Phones: "More" - the rest of what can be done with the selection (or
/// with the project when nothing is selected), grouped under headings that
/// match the computer's menus: Clip, Part, Edit, Sound, Text.
Future<void> showMoreSheet(BuildContext context, EditorSession s) {
  return showToolSheet(
    context,
    title: 'More',
    builder: (sheet) => ListenableBuilder(
      listenable: Listenable.merge([
        s.editor, s.selection, s.pictures, s.copiedSettings, //
        s.playheadClip,
      ]),
      builder: (_, _) {
        final actions = EditorActions(s);
        final clip = s.selectedClip;
        void close() => Navigator.of(sheet).pop();
        return Column(
          key: const ValueKey('more-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (heading, acts) in moreGroups(s)) ...[
              SheetHeading(heading),
              for (final a in acts)
                if (a == Act.goodMoments)
                  // Markers, "make a short from here" and "from markers".
                  ListTile(
                    key: _moreKey(a),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 48,
                    enabled: actions.whyNot(a) == null,
                    leading: const Icon(Icons.smartphone),
                    title: const Text('Shorts and good moments'),
                    subtitle: Text(s.project.markers.isEmpty
                        ? 'Make a short from here, or from your markers'
                        : '${s.project.markers.length} '
                            '${s.project.markers.length == 1 ? 'marker' : 'markers'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      close();
                      showToolSheet(context,
                          title: 'Shorts',
                          builder: (_) =>
                              ShortsPanel(session: s, host: context));
                    },
                  )
                else
                  ActionTile(
                    actions.entry(context, a),
                    key: _moreKey(a),
                    label: _phoneLabel(a),
                    onDone: close,
                    chevron: a == Act.crop ||
                        a == Act.history ||
                        a == Act.textWindow,
                  ),
              if (heading == 'Clip' && clip != null)
                ListTile(
                  key: const ValueKey('more-transition'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  leading: Icon(clipToolIcon(ClipTool.transition)),
                  title: const Text('Transition and fades'),
                  subtitle: Text(s.project.clips.indexOf(clip) <= 0
                      ? 'Fade in from black, fade out'
                      : 'From the clip before: '
                          '${clipToolSummary(ClipTool.transition, clip, s.project)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    close();
                    showClipToolSheet(context, s, ClipTool.transition);
                  },
                ),
              if (heading == 'Text' && actions.hasSpeechStarts)
                ListTile(
                  key: const ValueKey('more-speech-starts'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const LabelWithHint('Go to speech start',
                      articleId: 'who-is-speaking'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('more-previous-speech'),
                        tooltip: 'Previous speech start',
                        icon: const Icon(Icons.keyboard_double_arrow_left),
                        onPressed: () => s.goToSpeechStart(forward: false),
                      ),
                      IconButton(
                        key: const ValueKey('more-next-speech'),
                        tooltip: 'Next speech start',
                        icon: const Icon(Icons.keyboard_double_arrow_right),
                        onPressed: () => s.goToSpeechStart(forward: true),
                      ),
                    ],
                  ),
                ),
            ],
            if (clip != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'You can also hold a clip on the timeline and drag it to a '
                  'new place.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Phones: "Fade in and out" of the whole video (the project menu).
Future<void> showFadesSheet(BuildContext context, EditorSession s) {
  return showToolSheet(context,
      title: 'Fade in and out',
      builder: (_) => ListenableBuilder(
          listenable: s.editor,
          builder: (_, _) => ProjectFadesPanel(session: s)));
}

/// Phones: "Shape and size" (the project menu): the shape of the video and
/// its size, as the computer's View menu has them.
Future<void> showShapeAndSizeSheet(BuildContext context, EditorSession s) {
  return showToolSheet(
    context,
    title: 'Shape and size',
    builder: (sheet) => ListenableBuilder(
      listenable: s.editor,
      builder: (_, _) => Column(
        key: const ValueKey('shape-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeading('Shape'),
          for (final a in CanvasAspect.values)
            ListTile(
              key: ValueKey('shape-${a.name}'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: SizedBox(
                width: 24,
                child: s.project.aspect == a ? const Icon(Icons.check) : null,
              ),
              title: Text(shapeMenuLabel(a)),
              onTap: () => s.editor.setAspect(a),
            ),
          const SheetHeading('Video size'),
          for (final v in VideoSize.values)
            ListTile(
              key: ValueKey('video-size-${v.name}'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: SizedBox(
                width: 24,
                child:
                    s.project.videoSize == v ? const Icon(Icons.check) : null,
              ),
              title: Text(videoSizeLabel(v)),
              onTap: () => s.editor.setVideoSize(v),
            ),
          ListTile(
            key: const ValueKey('help-hint-shape'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: const Icon(Icons.help_outline, color: AppColors.textDim),
            title: const Text('Which shape should I use?'),
            onTap: () {
              Navigator.of(sheet).pop();
              showHelpArticle(context, 'shape');
            },
          ),
        ],
      ),
    ),
  );
}

/// The shape with a word about what it is for, as the menus show it.
String shapeMenuLabel(CanvasAspect aspect) => switch (aspect) {
      CanvasAspect.original => 'Original (as the first clip)',
      CanvasAspect.portrait9x16 => '9:16 upright',
      CanvasAspect.landscape16x9 => '16:9 wide',
      CanvasAspect.square1x1 => '1:1 square',
      CanvasAspect.portrait4x5 => '4:5 upright',
    };

// The timeline's context menu ------------------------------------------------

/// What was right-clicked or long-pressed on the timeline.
@immutable
class TimelineTarget {
  const TimelineTarget.item(ItemKind this.kind, String this.id)
      : markerId = null,
        atMs = null,
        part = false;
  const TimelineTarget.marker(String this.markerId, int this.atMs)
      : kind = null,
        id = null,
        part = false;

  /// An empty part of a track (or the ruler) at [atMs].
  const TimelineTarget.empty(int this.atMs)
      : kind = null,
        id = null,
        markerId = null,
        part = false;

  /// The selected part of the timeline (1.17): a right-click or long
  /// press inside its highlight where no item is.
  const TimelineTarget.part()
      : kind = null,
        id = null,
        markerId = null,
        atMs = null,
        part = true;

  /// True for [TimelineTarget.part].
  final bool part;

  final ItemKind? kind;
  final String? id;
  final String? markerId;
  final int? atMs;
}

/// The actions of a timeline item, in the order the context menu lists
/// them (null: a divider). The same list for a right-click and for a long
/// press.
List<Act?> contextActs(TimelineTarget target, EditorSession s) {
  switch (target.kind) {
    case ItemKind.clip:
      return [
        Act.split,
        Act.startAtPlayhead,
        Act.endAtPlayhead,
        null,
        Act.duplicate,
        Act.copySettings,
        Act.pasteSettings,
        null,
        Act.freezeFrame,
        Act.removeSilences,
        Act.crop,
        Act.rotateRight,
        Act.separateSound,
        Act.putSoundBack,
        null,
        Act.moveEarlier,
        Act.moveLater,
        Act.shortFromHere,
        Act.partOfItem,
        null,
        Act.delete,
      ];
    case ItemKind.audio:
      return [
        Act.editItem,
        Act.fitMusic,
        Act.lineUpVoice,
        Act.putSoundBack,
        Act.lowerMusic,
        Act.copyCredits,
        null,
        Act.partOfItem,
        if (s.pictures.isSpeech(s.selectedAudio ?? _noSound)) Act.partTurn,
        null,
        Act.delete,
      ];
    case ItemKind.title:
      return [
        Act.editItem,
        Act.duplicate,
        Act.textWindow,
        Act.partOfItem,
        null,
        Act.delete,
      ];
    case ItemKind.overlay:
      return [
        Act.editItem,
        Act.crop,
        Act.rotateRight,
        Act.partOfItem,
        null,
        Act.delete,
      ];
    case null:
      if (target.part) return [...kPartActs, null, Act.clearPart];
      if (target.markerId != null) {
        return [
          Act.shortFromHere,
          Act.shortsFromMarkers,
          Act.goodMoments,
          Act.partBetweenMarkers,
        ];
      }
      return [
        Act.addMedia,
        Act.addMusic,
        Act.addVoice,
        Act.addTitle,
        Act.addCaption,
        Act.addOverlay,
        Act.markMoment,
        null,
        Act.split,
        Act.shortFromHere,
        Act.selectPart,
      ];
  }
}

const AudioClip _noSound = AudioClip(
    id: '', path: '', sourceDurationMs: 0, startMs: 0, inMs: 0, outMs: 0);

String _contextTitle(TimelineTarget t, EditorSession s) {
  switch (t.kind) {
    case ItemKind.clip:
      return s.selectedClip?.type == ClipType.photo ? 'Photo' : 'Video clip';
    case ItemKind.audio:
      final a = s.selectedAudio;
      return a?.isVoice == true
          ? 'Voice'
          : a?.isSeparated == true
              ? 'Sound'
              : 'Music';
    case ItemKind.title:
      return s.selectedTitle?.kind == TitleKind.caption ? 'Caption' : 'Title';
    case ItemKind.overlay:
      return 'Overlay';
    case null:
      if (t.part) {
        final p = s.part.value;
        return p == null
            ? 'Selected part'
            : 'Selected part · ${formatLength(p.lengthMs)}';
      }
      return t.markerId != null
          ? 'Good moment at ${formatTime(t.atMs ?? 0)}'
          : 'At ${formatTime(t.atMs ?? 0)}';
  }
}

/// The context menu of a timeline item: a right-click on a computer (a
/// small menu at [position]), a long press on a phone (a sheet). The item
/// is selected first (and the playhead goes to an empty place or a marker
/// that was pressed), so the actions are about what was pressed.
Future<void> showTimelineContextMenu(
  BuildContext context,
  EditorSession s,
  TimelineTarget target, {
  Offset? position,
}) async {
  s.playback.pause();
  final kind = target.kind;
  if (kind != null) {
    switch (kind) {
      case ItemKind.clip:
        s.selectClipAndShow(target.id!);
      case ItemKind.overlay:
        s.selectOverlayAndShow(target.id!);
      case ItemKind.audio || ItemKind.title:
        s.select(kind, target.id!);
    }
  } else if (!target.part) {
    s.clearSelection();
    final at = target.atMs;
    if (at != null) s.playback.seek(at);
  }
  final actions = EditorActions(s);
  final acts = contextActs(target, s);
  // Computers have the settings in the side panel: no "Edit" line there.
  final narrow = isNarrow(context);
  final shown = [
    for (final a in acts)
      if (a != Act.editItem || narrow) a,
  ];
  final markerId = target.markerId;

  if (position == null || narrow) {
    return showToolSheet(
      context,
      title: _contextTitle(target, s),
      builder: (sheet) => Column(
        key: const ValueKey('context-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in shown)
            if (a == null)
              const Divider(height: 8)
            else
              ActionTile(
                actions.entry(context, a),
                key: ValueKey('context-${a.name}'),
                label: _phoneLabel(a),
                onDone: () => Navigator.of(sheet).pop(),
              ),
          if (markerId != null)
            ListTile(
              key: const ValueKey('context-remove-marker'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Remove this marker',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.of(sheet).pop();
                s.editor.removeMarker(markerId);
              },
            ),
        ],
      ),
    );
  }

  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final size = overlay?.size ?? MediaQuery.sizeOf(context);
  final chosen = await showMenu<Object>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy,
        size.width - position.dx, size.height - position.dy),
    color: AppColors.panelHigh,
    // Never taller than the window: a long menu near the bottom edge is
    // moved up to fit, and scrolls when even that is not enough.
    constraints: BoxConstraints(
        minWidth: 112, maxWidth: 420, maxHeight: size.height - 16),
    items: [
      for (final a in shown)
        if (a == null)
          const PopupMenuDivider(height: 8)
        else
          _contextItem(actions.entry(context, a)),
      if (markerId != null)
        const PopupMenuItem<Object>(
          key: ValueKey('context-remove-marker'),
          value: 'remove-marker',
          height: 34,
          child: Text('Remove this marker',
              style: TextStyle(fontSize: 13, color: AppColors.danger)),
        ),
    ],
  );
  if (!context.mounted || s.isDisposed) return;
  if (chosen is Act) {
    actions.run(context, chosen);
  } else if (chosen == 'remove-marker' && markerId != null) {
    s.editor.removeMarker(markerId);
  }
}

PopupMenuEntry<Object> _contextItem(ActionEntry e) => PopupMenuItem<Object>(
      key: ValueKey('context-${e.act.name}'),
      value: e.act,
      enabled: e.enabled,
      height: 34,
      child: Row(
        children: [
          Icon(e.icon,
              size: 16,
              color: !e.enabled
                  ? AppColors.textDim.withValues(alpha: 0.5)
                  : e.danger
                      ? AppColors.danger
                      : AppColors.textDim),
          const SizedBox(width: 10),
          Flexible(
            child: Text(e.labelWithReason,
                style: TextStyle(
                    fontSize: 13,
                    color: e.danger && e.enabled ? AppColors.danger : null)),
          ),
          if (e.checked == true || e.mixed) ...[
            const SizedBox(width: 10),
            Icon(e.mixed ? Icons.remove : Icons.check, size: 16),
          ],
        ],
      ),
    );
