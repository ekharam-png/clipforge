import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/editor/project_editor.dart';
import '../../core/model/project.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'acts.dart';
import 'import_actions.dart' show kDefaultTitleText;
import 'session.dart';
import 'shorts_actions.dart';
import 'tools.dart' show showToolSheet;

// "Select a part" (1.17): what the editor does with a selected part of the
// timeline - the bar next to the timeline (computers: one line; phones:
// start, end, length and nudge buttons), the sheet of actions on phones,
// the dialogs (Lower volume, Speed, Only when speaking) and the "Quiet
// parts" list of a sound's panel. The rules (which rows an action can
// change, and why not) are in core/editor/part.dart; the edits in
// core/editor/part_edits.dart.

const _uuid = Uuid();

/// The part action behind [a]; null for the other actions.
PartAction? partActionOf(Act a) => switch (a) {
      Act.partCutOut => PartAction.cutOut,
      Act.partDelete => PartAction.deleteGap,
      Act.partSilence => PartAction.silence,
      Act.partLower => PartAction.lower,
      Act.partSpeed => PartAction.speed,
      Act.partClean => PartAction.clean,
      Act.partShort => PartAction.makeShort,
      Act.partDuplicate => PartAction.duplicate,
      Act.partTitle => PartAction.addTitle,
      Act.partMarker => PartAction.addMarker,
      _ => null,
    };

/// The actions on a part, in the order every list shows them (null: a
/// divider).
const List<Act?> kPartActs = [
  Act.partCutOut,
  Act.partDelete,
  Act.partSilence,
  Act.partLower,
  Act.partSpeed,
  Act.partClean,
  null,
  Act.partShort,
  Act.partDuplicate,
  Act.partTitle,
  Act.partMarker,
];

/// The ways to select a part, in the order the menus show them.
const List<Act> kPartSelectActs = [
  Act.selectPart,
  Act.partStart,
  Act.partEnd,
  Act.partOfItem,
  Act.partTurn,
  Act.partPause,
  Act.partBetweenMarkers,
  Act.partFromStart,
  Act.partToEnd,
  Act.clearPart,
];

/// "Select this clip's time" names what is selected.
String partOfItemLabel(EditorSession s) {
  if (s.selectedAudio != null) return "Select this sound's time";
  if (s.selectedTitle != null) {
    return s.selectedTitle!.kind == TitleKind.caption
        ? "Select this caption's time"
        : "Select this title's time";
  }
  if (s.selectedOverlay != null) return "Select this overlay's time";
  return "Select this clip's time";
}

/// Why the part action or selection [a] cannot be done now; null when it
/// can. (Asked by EditorActions.whyNot, the one source.)
String? partWhyNot(EditorSession s, Act a) {
  final p = s.project;
  if (p.clips.isEmpty) return 'add a video first';
  switch (a) {
    case Act.selectPart:
    case Act.partStart:
    case Act.partEnd:
    case Act.partFromStart:
    case Act.partToEnd:
      return null;
    case Act.partOfItem:
      return s.selection.value == null && s.project.clips.isEmpty
          ? 'select a clip first'
          : null;
    // Where the playhead is decides the rest for these two; that is said
    // when they are used (the menus do not follow every frame).
    case Act.partTurn:
    case Act.partPause:
      return s.pictures.speakers.any((t) => t.stretches.isNotEmpty)
          ? null
          : 'no speech found yet';
    case Act.partBetweenMarkers:
      return p.markers.isEmpty ? 'no good moment markers yet' : null;
    case Act.clearPart:
      return s.part.value == null ? 'no part is selected' : null;
    default:
      final action = partActionOf(a);
      if (action == null) return null;
      if (a == Act.partShort && s.store == null) return 'not available here';
      return partActionProblem(p, s.part.value, action, s.partRows.value);
  }
}

void _say(BuildContext context, String message, {VoidCallback? undo}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: undo),
    ));
}

String _sentence(String reason) => reason.isEmpty
    ? reason
    : '${reason[0].toUpperCase()}${reason.substring(1)}.';

/// "Select a part": the time of what is selected, else five seconds from
/// the playhead - two handles to drag from there.
void selectPartHere(EditorSession s) {
  final item = s.selection.value == null ? null : s.itemTime;
  if (item != null) {
    s.setPart(item.startMs, item.endMs);
    return;
  }
  final end = s.project.durationMs;
  var from = s.playback.positionMs;
  if (from > end - 1000) from = (end - 5000).clamp(0, end).toInt();
  s.setPart(from, (from + 5000).clamp(0, end).toInt());
}

/// Does the part action or selection [a].
void runPartAct(BuildContext context, EditorSession s, Act a) {
  final p = s.project;
  final at = s.playback.positionMs;
  final part = s.part.value;
  final rows = s.partRows.value;
  final e = s.editor.editor;
  void done(PartResult r, String message) {
    if (r.problem != null) {
      _say(context, _sentence(r.problem!));
    } else {
      _say(context, message, undo: s.editor.undo);
    }
  }

  switch (a) {
    case Act.selectPart:
      s.playback.pause();
      selectPartHere(s);
    case Act.partStart:
      s.markPartStart(at);
    case Act.partEnd:
      s.markPartEnd(at);
    case Act.partOfItem:
      final t = s.itemTime;
      if (t != null) {
        s.setPart(t.startMs, t.endMs);
      } else {
        _say(context, 'Move the playhead onto a clip first.');
      }
    case Act.partTurn:
      final speaker = s.partSpeaker;
      final t = speaker == null ? null : s.turnAt(speaker.id, at);
      if (t != null) {
        s.setPart(t.startMs, t.endMs);
      } else {
        _say(
            context,
            s.pictures.speakers.length > 1 && s.selectedAudio == null
                ? 'Nobody is talking at the playhead. Select a voice on '
                    'the timeline to say whose turn you mean.'
                : 'Nobody is talking at the playhead.');
      }
    case Act.partPause:
      final t = s.pauseHere;
      if (t != null) {
        s.setPart(t.startMs, t.endMs);
      } else {
        _say(context, 'The playhead is not in a pause: someone is talking '
            'there.');
      }
    case Act.partBetweenMarkers:
      final t = partBetweenMarkers(p, at);
      if (t != null) s.setPart(t.startMs, t.endMs);
    case Act.partFromStart:
      s.setPart(0, at);
    case Act.partToEnd:
      s.setPart(at, p.durationMs);
    case Act.clearPart:
      s.clearPart();
    case Act.partCutOut:
      if (part == null) return;
      s.playback.pause();
      final r = e.cutPart(part);
      if (r.ok) {
        s.clearPart();
        s.playback.seek(part.startMs);
      }
      done(
          r,
          'Cut ${formatLength(r.removedMs)} out of everything. '
          'To put it back later: Automatic cuts, or Undo now.');
    case Act.partDelete:
      if (part == null) return;
      final names = _names(p, part, PartAction.deleteGap, rows);
      done(e.deletePart(part, rows: rows),
          'Deleted that part on $names. Nothing moved.');
    case Act.partSilence:
      if (part == null) return;
      final names = _names(p, part, PartAction.silence, rows);
      done(e.silencePart(part, rows: rows),
          'Silenced ${formatLength(part.lengthMs)} on $names.');
    case Act.partLower:
      showLowerDialog(context, s);
    case Act.partSpeed:
      showSpeedDialog(context, s);
    case Act.partClean:
      if (part == null) return;
      final names = _names(p, part, PartAction.clean, rows);
      done(
          e.cleanPart(part, rows: rows),
          'Clean up sound is on for this part on $names. You hear all of '
          'it once its sound is prepared, and in the export.');
    case Act.partShort:
      if (part == null) return;
      final cut = part.clampTo(p.durationMs);
      final first = [
        for (final x in spokenIn(s))
          if (x.endMs > cut.startMs && x.startMs < cut.startMs + 8000)
            x.text.trim(),
      ].join(' ');
      showMakeShort(context, s,
          fromMs: cut.startMs, toMs: cut.endMs, firstText: first);
    case Act.partDuplicate:
      if (part == null) return;
      final r = e.duplicatePart(part);
      if (r.part != null) s.part.value = r.part;
      done(r, 'A copy of the part is right after it (now selected).');
    case Act.partTitle:
      if (part == null) return;
      final id = _uuid.v4();
      s.editor.editor.nameNextEdit('Added a title over a part');
      s.editor.addTitle(TitleOverlay(
          id: id,
          text: kDefaultTitleText,
          startMs: part.startMs,
          endMs: part.endMs));
      if (s.project.titles.any((t) => t.id == id)) {
        s.select(ItemKind.title, id);
      }
    case Act.partMarker:
      if (part == null) return;
      final id = s.editor.addMarker(part.startMs);
      _say(
          context,
          id == null
              ? 'There is already a marker there.'
              : 'Marked ${formatTime(part.startMs)} as a good moment.');
    default:
      break;
  }
}

/// "Video, Sam and Music" / "every row".
String _names(Project p, TimelinePart part, PartAction a, Set<String>? rows) {
  final names = [for (final r in partRowsFor(p, part, a, rows)) r.name];
  if (names.isEmpty) return 'no row';
  if (allRowsTicked(p, rows) && names.length > 2) return 'every row';
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// What [action] would change and what it leaves, for a tooltip or a line
/// under a button: "Changes Video, Sam. Not Music: music and other sound
/// keep their speed."
String partActionSummary(EditorSession s, PartAction action) {
  final p = s.project;
  final part = s.part.value;
  if (part == null || !partActionUsesRows(action)) return '';
  final rows = s.partRows.value;
  final yes = <String>[];
  final no = <String>[];
  for (final r in partRowsOf(p)) {
    if (!rowTicked(rows, r.id)) continue;
    final why = partRowProblem(p, part, action, r);
    if (why == null) {
      yes.add(r.name);
    } else {
      no.add('${r.name} ($why)');
    }
  }
  if (action == PartAction.cutOut) return 'Changes every row.';
  return [
    if (yes.isNotEmpty) 'Changes ${yes.join(', ')}.',
    if (no.isNotEmpty) 'Not ${no.join('; ')}.',
  ].join(' ');
}

// Rows ------------------------------------------------------------------

/// Ticks or unticks row [id].
void togglePartRow(EditorSession s, String id) {
  final all = {for (final r in partRowsOf(s.project)) r.id};
  final now = {...(s.partRows.value ?? all)};
  now.contains(id) ? now.remove(id) : now.add(id);
  s.partRows.value = now.containsAll(all) ? null : now;
}

/// "Only this row".
void onlyPartRow(EditorSession s, String id) => s.partRows.value = {id};

/// "Rows: everything" / "Rows: Sam" / "Rows: 2 of 4".
String partRowsLabel(EditorSession s) {
  final p = s.project;
  final rows = s.partRows.value;
  if (allRowsTicked(p, rows)) return 'Everything';
  final ticked = [
    for (final r in partRowsOf(p))
      if (rows!.contains(r.id)) r.name,
  ];
  if (ticked.isEmpty) return 'No row';
  if (ticked.length == 1) return 'Only ${ticked.single}';
  return '${ticked.length} of ${partRowsOf(p).length} rows';
}

// The bar ------------------------------------------------------------------

/// The bar of the selected part, right next to the timeline. Computers: one
/// line - what is selected, the rows, the actions. Phones: start and end
/// with nudge buttons (fingers are imprecise), the length, Rows, Actions.
/// Nothing while no part is selected.
class PartBar extends StatelessWidget {
  const PartBar({
    super.key,
    required this.session,
    required this.phone,
    required this.entry,
  });
  final EditorSession session;
  final bool phone;

  /// The action as the registry gives it (EditorActions.entry).
  final ActionEntry Function(BuildContext context, Act a) entry;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.part, s.partRows, s.editor, s.pictures, s.partNudgeTenths, //
        s.playheadClip,
      ]),
      builder: (context, _) {
        final part = s.part.value;
        if (part == null) return const SizedBox.shrink();
        return Material(
          key: const ValueKey('part-bar'),
          color: AppColors.panelHigh,
          child: phone ? _phoneBar(context, part) : _wideBar(context, part),
        );
      },
    );
  }

  String _range(TimelinePart part) =>
      '${formatTime(part.startMs)} – ${formatTime(part.endMs)}';

  Widget _rowsButton(BuildContext context) {
    final s = session;
    final rows = partRowsOf(s.project);
    return PopupMenuButton<String>(
      key: const ValueKey('part-rows'),
      tooltip: 'Which rows the actions apply to. On the timeline: the '
          'tick boxes; Alt+click one for only that row',
      color: AppColors.panelHigh,
      onSelected: (id) {
        if (id == '*') {
          s.partRows.value = null;
        } else if (id.startsWith('only:')) {
          onlyPartRow(s, id.substring(5));
        } else {
          togglePartRow(s, id);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          key: const ValueKey('part-rows-all'),
          value: '*',
          checked: allRowsTicked(s.project, s.partRows.value),
          child: const Text('Everything'),
        ),
        const PopupMenuDivider(),
        for (final r in rows)
          CheckedPopupMenuItem(
            key: ValueKey('part-rows-${r.id}'),
            value: r.id,
            checked: rowTicked(s.partRows.value, r.id),
            child: Text(r.name),
          ),
        const PopupMenuDivider(),
        for (final r in rows)
          PopupMenuItem(
            key: ValueKey('part-rows-only-${r.id}'),
            value: 'only:${r.id}',
            child: Text('Only ${r.name}'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist, size: 16, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text('Rows: ${partRowsLabel(s)}',
                key: const ValueKey('part-rows-label'),
                style: const TextStyle(fontSize: 12.5)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _wideBar(BuildContext context, TimelinePart part) {
    final s = session;
    Widget button(Act a, {String? label}) {
      final e = entry(context, a);
      final action = partActionOf(a);
      final summary = action == null ? '' : partActionSummary(s, action);
      final hint = actHint(a);
      return MouseRegion(
        // While the pointer is on an action, the row headers show which
        // rows it cannot change, and why.
        onEnter: (_) => s.partPreview.value = action,
        onExit: (_) {
          if (s.partPreview.value == action) s.partPreview.value = null;
        },
        child: Tooltip(
          message: e.reason != null
              ? '${actName(a)}: ${e.reason}'
              : [?hint, if (summary.isNotEmpty) summary].join('\n'),
          child: TextButton.icon(
            key: ValueKey('part-${a.name}'),
            onPressed: e.onTap,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(e.icon, size: 16),
            // The size only: a whole TextStyle here would drop the app's
            // font.
            label: Text(label ?? actName(a),
                style: const TextStyle(fontSize: 12.5)),
          ),
        ),
      );
    }

    final cut = entry(context, Act.partCutOut);
    final rowsNote =
        !allRowsTicked(s.project, s.partRows.value) && cut.reason != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 10),
              const Icon(Icons.select_all, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                '${_range(part)} · ${formatLength(part.lengthMs)}',
                key: const ValueKey('part-length'),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              _rowsButton(context),
              const VerticalDivider(width: 12, indent: 8, endIndent: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      button(Act.partCutOut),
                      button(Act.partDelete, label: 'Delete, leave a gap'),
                      button(Act.partSilence),
                      button(Act.partLower, label: 'Lower'),
                      button(Act.partSpeed),
                      button(Act.partClean, label: 'Clean up'),
                      _more(context),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('part-help'),
                tooltip: 'Help: select a part',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.help_outline, size: 17),
                onPressed: () => showHelpArticle(context, 'select-a-part'),
              ),
              IconButton(
                key: const ValueKey('part-clear'),
                tooltip: 'Clear the selected part (Esc)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: s.clearPart,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (rowsNote)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'Cut out removes time, so it needs every row: with only some, '
              'lips and voice would no longer match afterwards. For the '
              'ticked rows use Silence, or Delete and leave a gap.',
              key: const ValueKey('part-rows-note'),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
            ),
          ),
      ],
    );
  }

  Widget _more(BuildContext context) {
    final entries = [
      for (final a in const [
        Act.partShort,
        Act.partDuplicate,
        Act.partTitle,
        Act.partMarker,
      ])
        entry(context, a),
    ];
    return PopupMenuButton<Act>(
      key: const ValueKey('part-more'),
      tooltip: 'Make a short, duplicate, title, marker',
      color: AppColors.panelHigh,
      onSelected: (a) => entries.firstWhere((e) => e.act == a).onTap?.call(),
      itemBuilder: (_) => [
        for (final e in entries)
          PopupMenuItem(
            key: ValueKey('part-${e.act.name}'),
            value: e.act,
            enabled: e.enabled,
            height: 34,
            child: Row(
              children: [
                Icon(e.icon, size: 16, color: AppColors.textDim),
                const SizedBox(width: 10),
                Flexible(
                    child: Text(e.labelWithReason,
                        style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('More', style: TextStyle(fontSize: 12.5)),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _phoneBar(BuildContext context, TimelinePart part) {
    final s = session;
    final tenths = s.partNudgeTenths.value;
    int step() {
      if (tenths) return 100;
      final p = s.project;
      final i = p.clipIndexAt(part.startMs.clamp(0, p.durationMs));
      final c = i >= 0 && i < p.clips.length ? p.clips[i] : null;
      if (c == null || c.type != ClipType.video || c.frameRate <= 1) return 33;
      return (1000 / c.frameRate).round().clamp(1, 100).toInt();
    }

    Widget edge(String name, int ms, bool start) => Expanded(
          child: Row(
            children: [
              IconButton(
                key: ValueKey('part-$name-earlier'),
                tooltip: '${start ? 'Start' : 'End'} earlier',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => s.nudgePart(start: start, deltaMs: -step()),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(start ? 'Start' : 'End',
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textDim)),
                    FittedBox(
                      child: Text(formatTime(ms),
                          key: ValueKey('part-$name-time'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('part-$name-later'),
                tooltip: '${start ? 'Start' : 'End'} later',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => s.nudgePart(start: start, deltaMs: step()),
              ),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              edge('start', part.startMs, true),
              const SizedBox(width: 4),
              edge('end', part.endMs, false),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
          child: Row(
            children: [
              TextButton(
                key: const ValueKey('part-step'),
                style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => s.partNudgeTenths.value = !tenths,
                child: Text(tenths ? 'Step 0.1 s' : 'Step 1 frame',
                    style: const TextStyle(fontSize: 12.5)),
              ),
              Expanded(
                child: Text(
                  formatLength(part.lengthMs),
                  key: const ValueKey('part-length'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('part-actions'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => showPartSheet(context, s, entry),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Actions'),
              ),
              IconButton(
                key: const ValueKey('part-clear'),
                tooltip: 'Clear the selected part',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close),
                onPressed: s.clearPart,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phones: what can be done with the selected part - the rows first (tick
/// boxes, "Only this row"), then the actions, each saying what it changes
/// or why it cannot be done.
Future<void> showPartSheet(BuildContext context, EditorSession s,
    ActionEntry Function(BuildContext context, Act a) entry) {
  s.playback.pause();
  return showToolSheet(
    context,
    title: 'This part',
    builder: (sheet) => ListenableBuilder(
      listenable: Listenable.merge([s.part, s.partRows, s.editor]),
      builder: (_, _) {
        final part = s.part.value;
        if (part == null) return const SizedBox(height: 8);
        final p = s.project;
        final rows = partRowsOf(p);
        void close() => Navigator.of(sheet).pop();
        return Column(
          key: const ValueKey('part-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                '${formatTime(part.startMs)} – ${formatTime(part.endMs)} · '
                '${formatLength(part.lengthMs)}',
                style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text('ROWS',
                      style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  key: const ValueKey('part-sheet-all'),
                  onPressed: allRowsTicked(p, s.partRows.value)
                      ? null
                      : () => s.partRows.value = null,
                  child: const Text('Everything'),
                ),
              ],
            ),
            for (final r in rows)
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      key: ValueKey('part-sheet-row-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(r.name),
                      value: rowTicked(s.partRows.value, r.id),
                      onChanged: (_) => togglePartRow(s, r.id),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('part-sheet-only-${r.id}'),
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => onlyPartRow(s, r.id),
                    child: const Text('Only this'),
                  ),
                ],
              ),
            const Divider(height: 12),
            for (final a in kPartActs)
              if (a == null)
                const Divider(height: 8)
              else
                Builder(builder: (_) {
                  final e = entry(context, a);
                  final action = partActionOf(a);
                  final summary =
                      action == null ? '' : partActionSummary(s, action);
                  final cutNote = a == Act.partCutOut &&
                      e.reason != null &&
                      !allRowsTicked(p, s.partRows.value);
                  return ListTile(
                    key: ValueKey('part-sheet-${a.name}'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 48,
                    enabled: e.enabled,
                    leading: Icon(e.icon),
                    title: Text(actName(a)),
                    subtitle: Text(cutNote
                        ? 'Needs every row: with only some, lips and voice '
                            'would no longer match. Use Silence, or Delete '
                            'and leave a gap.'
                        : e.reason != null
                            ? 'Not now: ${e.reason}'
                            : summary.isNotEmpty
                                ? summary
                                : (actHint(a) ?? '')),
                    onTap: e.onTap == null
                        ? null
                        : () {
                            close();
                            e.onTap!();
                          },
                  );
                }),
          ],
        );
      },
    ),
  );
}

// Dialogs ----------------------------------------------------------------

/// "Lower volume…": -6 / -12 / -18 dB or a slider, for the ticked rows.
Future<void> showLowerDialog(BuildContext context, EditorSession s) async {
  final part = s.part.value;
  if (part == null) return;
  var db = -12.0;
  final chosen = await showDialog<double>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const ValueKey('part-lower-dialog'),
        title: const Text('Lower volume'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${formatLength(part.lengthMs)} gets quieter on the ticked '
                  'rows. Nothing moves; the level changes over a blink '
                  '(40 ms), so nothing clicks.',
                  style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final v in const [-6.0, -12.0, -18.0])
                    ChoiceChip(
                      key: ValueKey('part-lower-${v.round().abs()}'),
                      label: Text('−${v.round().abs()} dB'),
                      selected: db == v,
                      onSelected: (_) => setState(() => db = v),
                    ),
                ],
              ),
              Slider(
                key: const ValueKey('part-lower-slider'),
                min: -30,
                max: -1,
                divisions: 29,
                value: db,
                label: '${db.round()} dB',
                onChanged: (v) => setState(() => db = v.roundToDouble()),
              ),
              Text(
                  '−${db.round().abs()} dB: '
                  '${db <= -18 ? 'far in the background' : db <= -10 ? 'clearly quieter' : 'a little quieter'}',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Text(partActionSummary(s, PartAction.lower),
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('part-lower-go'),
              onPressed: () => Navigator.of(dialog).pop(db),
              child: const Text('Lower')),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted || s.isDisposed) return;
  final now = s.part.value;
  if (now == null) return;
  final r = s.editor.editor
      .silencePart(now, rows: s.partRows.value, level: levelFromDb(chosen));
  _say(
      context,
      r.problem != null
          ? _sentence(r.problem!)
          : 'Lowered ${formatLength(now.lengthMs)} by ${chosen.round().abs()} dB '
              'on ${_names(s.project, now, PartAction.lower, s.partRows.value)}.',
      undo: r.problem == null ? s.editor.undo : null);
}

/// The speeds "Speed…" offers besides a custom one.
const List<double> kPartSpeeds = [0.25, 0.5, 1.5, 2];

/// "Speed…": slow motion or faster for the part; "Mute this part's own
/// sound" is on by itself for speeds below 0.5x (slowed-down sound is
/// rarely wanted) until the user sets it.
Future<void> showSpeedDialog(BuildContext context, EditorSession s) async {
  final part = s.part.value;
  if (part == null) return;
  var speed = 0.5;
  bool? muteChoice;
  bool mute() => muteChoice ?? speed < 0.5;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const ValueKey('part-speed-dialog'),
        title: const Text('Speed of this part'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final v in kPartSpeeds)
                    ChoiceChip(
                      key: ValueKey('part-speed-$v'),
                      label: Text(formatSpeed(v)),
                      selected: speed == v,
                      onSelected: (_) => setState(() => speed = v),
                    ),
                ],
              ),
              Slider(
                key: const ValueKey('part-speed-slider'),
                min: ProjectEditor.minSpeed,
                max: ProjectEditor.maxSpeed,
                divisions: 75,
                value: speed,
                label: formatSpeed(speed),
                onChanged: (v) =>
                    setState(() => speed = (v * 20).round() / 20),
              ),
              Text(
                  '${formatSpeed(speed)}: this part will take '
                  '${formatLength((part.clampTo(s.project.durationMs).lengthMs / speed).round())} '
                  '(now ${formatLength(part.clampTo(s.project.durationMs).lengthMs)}).',
                  key: const ValueKey('part-speed-result'),
                  style: const TextStyle(fontSize: 12.5)),
              CheckboxListTile(
                key: const ValueKey('part-speed-mute'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text("Mute this part's own sound"),
                value: mute(),
                onChanged: (v) => setState(() => muteChoice = v ?? false),
              ),
              const Text(
                  'The video is cut at both ends of the part. Its own sound '
                  'and voices lined up with it follow by themselves. Music '
                  'and other sound keep their speed and their place, so '
                  'what comes after the part no longer sits where it did '
                  'against the music.',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('part-speed-go'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Set speed')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted || s.isDisposed) return;
  final now = s.part.value;
  if (now == null) return;
  final r = s.editor.editor.speedPart(now, speed,
      muteOwnSound: mute(), rows: s.partRows.value);
  if (r.part != null) s.part.value = r.part;
  _say(
      context,
      r.problem != null
          ? _sentence(r.problem!)
          : 'This part now plays at ${formatSpeed(speed)}'
              '${mute() ? ', without its own sound' : ''}. '
              'Music and other sound stayed as they were.',
      undo: r.problem == null ? s.editor.undo : null);
}

/// The levels "Only when speaking" offers between a speaker's turns.
const List<(String label, double level)> kGateLevels = [
  ('A little room sound (−18 dB)', kGateDefaultLevel),
  ('More room sound (−12 dB)', 0.251),
  ('Hardly any (−30 dB)', 0.0316),
  ('Silence', 0),
];

/// The switch and the level of "Only when speaking" for one speech track
/// (the track menu and the dialog use it).
class OnlyWhenSpeakingTile extends StatelessWidget {
  const OnlyWhenSpeakingTile(
      {super.key, required this.session, required this.trackId, this.named = false});
  final EditorSession session;
  final String trackId;

  /// Show the track's name as the title (the dialog lists several).
  final bool named;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final t = s.project.trackById(trackId);
    if (t == null) return const SizedBox.shrink();
    final e = s.editor.editor;
    // The nearest of the offered levels.
    var at = 0;
    for (var i = 1; i < kGateLevels.length; i++) {
      if ((kGateLevels[i].$2 - t.gateLevel).abs() <
          (kGateLevels[at].$2 - t.gateLevel).abs()) {
        at = i;
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: ValueKey('gate-$trackId'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: named
              ? Text(t.name)
              : const LabelWithHint('Only when speaking',
                  articleId: 'only-when-speaking'),
          subtitle: Text(
              named
                  ? (t.gate
                      ? 'Turned down while this speaker is silent'
                      : 'Always open')
                  : 'This microphone is turned down while its speaker is '
                      'not talking. In the preview and the export.',
              style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          value: t.gate,
          onChanged: (v) => e.setOnlyWhenSpeaking(trackId, on: v),
        ),
        if (t.gate)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DropdownButtonFormField<int>(
              key: ValueKey('gate-level-$trackId'),
              initialValue: at,
              isDense: true,
              decoration: const InputDecoration(
                  labelText: 'Between the turns', isDense: true),
              items: [
                for (var i = 0; i < kGateLevels.length; i++)
                  DropdownMenuItem(value: i, child: Text(kGateLevels[i].$1)),
              ],
              onChanged: (i) {
                if (i != null) {
                  e.setOnlyWhenSpeaking(trackId, level: kGateLevels[i].$2);
                }
              },
            ),
          ),
      ],
    );
  }
}

/// "Only when speaking…" (Sound menu, the suggestion): every speech track
/// with its switch and level, and what the gate is.
Future<void> showOnlyWhenSpeaking(BuildContext context, EditorSession s) {
  s.playback.pause();
  Widget body(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([s.editor, s.pictures]),
        builder: (context, _) {
          final tracks = [
            for (final t in s.project.soundTracks)
              if (t.speech) t,
          ];
          return Column(
            key: const ValueKey('only-when-speaking'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'Each microphone also hears the other people, breathing '
                  'and the room. Switched on, a microphone is turned down '
                  'while its own speaker is not talking, and opens just '
                  'before they start. It goes by loudness, not by words: '
                  'listen to a stretch before you export.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 6),
              if (tracks.isEmpty)
                const Text('There is no speech track yet. Add a voice '
                    'recording first (Add > Voice recording).')
              else
                for (final t in tracks)
                  OnlyWhenSpeakingTile(session: s, trackId: t.id, named: true),
              if (s.pictures.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Listening to the sound… the quiet stretches '
                      'appear on the timeline when that is done.',
                      style:
                          TextStyle(color: AppColors.textDim, fontSize: 12)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      showHelpArticle(context, 'only-when-speaking'),
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('How it works, and its limits'),
                ),
              ),
            ],
          );
        },
      );
  if (MediaQuery.sizeOf(context).width < 600) {
    return showToolSheet(context, title: 'Only when speaking', builder: body);
  }
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Only when speaking'),
      content: SizedBox(
          width: 420, child: SingleChildScrollView(child: body(dialog))),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Done')),
      ],
    ),
  );
}

/// "Quiet parts" of a clip's or sound's panel: the silenced and lowered
/// stretches the item plays, with their times on the timeline; a tap
/// selects the stretch as the part, Remove gives it its sound back.
class QuietPartsList extends StatelessWidget {
  const QuietPartsList({
    super.key,
    required this.session,
    required this.itemId,
    required this.quiet,
    required this.startMs,
    required this.inMs,
    required this.outMs,
    required this.speed,
  });
  final EditorSession session;
  final String itemId;
  final List<QuietRange> quiet;

  /// Where the item starts on the timeline, and the part of its file it
  /// plays at [speed].
  final int startMs;
  final int inMs;
  final int outMs;
  final double speed;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final sp = speed <= 0 ? 1.0 : speed;
    final used = [
      for (final r in quiet)
        if (r.toMs > inMs && r.fromMs < outMs) r,
    ];
    if (used.isEmpty) return const SizedBox.shrink();
    int onTimeline(int src) =>
        startMs + ((src.clamp(inMs, outMs) - inMs) / sp).round();
    return Column(
      key: ValueKey('quiet-parts-$itemId'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 2),
          child: LabelWithHint('Quiet parts', articleId: 'silence-a-part'),
        ),
        for (final r in used)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: ValueKey('quiet-part-${r.fromMs}'),
                  onTap: () {
                    final a = onTimeline(r.fromMs), b = onTimeline(r.toMs);
                    s.setPart(a, b);
                    s.playback.seek(a);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                            r.level <= 0.0005
                                ? Icons.volume_off_outlined
                                : Icons.volume_down_outlined,
                            size: 16,
                            color: AppColors.textDim),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${formatTime(onTimeline(r.fromMs))} – '
                            '${formatTime(onTimeline(r.toMs))} · '
                            '${r.level <= 0.0005 ? 'silent' : levelLabel(r.level)}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(
                key: ValueKey('quiet-remove-${r.fromMs}'),
                onPressed: () =>
                    s.editor.editor.removeQuiet(itemId, r.fromMs, r.toMs),
                child: const Text('Remove'),
              ),
            ],
          ),
      ],
    );
  }
}
