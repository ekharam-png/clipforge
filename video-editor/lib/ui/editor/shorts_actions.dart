// Shorts, the manual way (1.14): "Make a short from this…" (a selection
// in the Text window), "Make a short from here…" (30 / 45 / 60 s from the
// playhead), "good moment" markers (M while watching) and "Make shorts
// from markers…". Each short is a NEW project: only that part, upright
// 9:16, 1080p, blurred background where the picture is wider, the "Short"
// caption look, an optional title at the top. The long project is never
// changed. The same builder as Claude's make_short
// (core/publish/shorts.dart).

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/editor/project_editor.dart';
import '../../core/model/project.dart';
import '../../core/publish/chapters.dart' show chapterTime;
import '../../core/publish/shorts.dart';
import '../../core/storage/project_store.dart';
import '../../core/text/text_document.dart';
import '../../core/transcript/fillers.dart';
import '../../core/transcript/transcript_timeline.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'session.dart';

const _uuid = Uuid();

/// What is said on the timeline of [s]: the transcript's words when the
/// project has transcripts (computers), else its captions.
List<Spoken> spokenIn(EditorSession s) {
  if (s.transcripts.value.isNotEmpty) {
    final words = timelineWords(s.project, s.transcriptOf);
    if (words.isNotEmpty) {
      return [
        for (final w in words) Spoken(w.startMs, w.endMs, w.text, w.speaker),
      ];
    }
  }
  return [
    for (final l in captionLines(s.project))
      Spoken(l.startMs, l.endMs, l.text, l.speaker),
  ];
}

/// The pauses in the talk: from who is speaking (the sound, when its
/// picture is ready), else the gaps in what is [spoken].
List<Span> pausesIn(EditorSession s, List<Spoken> spoken) {
  final talk = [
    for (final t in s.pictures.speakers) ...t.stretches,
  ];
  return pausesBetween(
      talk.isNotEmpty
          ? talk
          : [for (final x in spoken) (startMs: x.startMs, endMs: x.endMs)],
      s.project.durationMs);
}

/// [fromMs]..[toMs] moved outward to pauses, never into a word or caption.
Span snapToPauses(EditorSession s, int fromMs, int toMs) {
  final spoken = spokenIn(s);
  final r = snapShortRange(fromMs, toMs,
      pauses: pausesIn(s, spoken),
      words: [for (final x in spoken) (startMs: x.startMs, endMs: x.endMs)],
      totalMs: s.project.durationMs);
  return (startMs: r.fromMs, endMs: r.toMs);
}

/// What one short is made from.
class ShortRequest {
  const ShortRequest({
    required this.fromMs,
    required this.toMs,
    required this.name,
    this.shortCaptions = true,
    this.title = '',
  });
  final int fromMs;
  final int toMs;
  final String name;
  final bool shortCaptions;
  final String title;
}

/// Makes the short [r] of the project open in [s] as a new project and
/// returns it. Throws when there is no project list to add it to, or the
/// part holds no video.
Future<Project> createShort(EditorSession s, ShortRequest r) async {
  final store = s.store;
  if (store == null) throw StateError('No project list');
  // The copy is made from what is on disk.
  await s.saveNow?.call();
  final name = await freeProjectName(store, r.name);
  final copy = await store.duplicate(s.project.id, name: name);
  final e = ProjectEditor(
      copy.copyWith(publishing: PublishingNotes.empty, markers: const []));
  final transcribed = s.transcripts.value.isNotEmpty;
  final language =
      transcribed ? s.transcripts.value.values.first.language : '';
  final built = buildShort(e,
      fromMs: r.fromMs,
      toMs: r.toMs,
      blur: true,
      shortCaptions: r.shortCaptions,
      title: r.title,
      words: (short) =>
          transcribed ? timelineWords(short, s.transcriptOf) : null,
      skipWord: transcribed ? isFillerSound(fillersFor(language)) : null,
      newId: _uuid.v4);
  if (!built.ok) {
    await store.delete(copy.id);
    throw StateError('This part holds no video');
  }
  await store.save(e.project);
  return e.project;
}

String _shortName(Project p, int fromMs) =>
    '${p.name} - short ${chapterTime(fromMs)}';

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "Make a short from this…" / "from here…": shows the part, its length
/// and a warning when it is over the short limit; makes the short; then
/// offers to open it or stay.
///
/// [lengths]: seconds offered instead of the fixed part - the part then
/// runs from [fromMs] for that long ("from the playhead"). [selectionToMs]
/// with [lengths]: "The selection" is offered too (Text window).
Future<void> showMakeShort(
  BuildContext context,
  EditorSession s, {
  required int fromMs,
  required int toMs,
  String firstText = '',
  List<int> lengths = const [],
  bool offerSelection = false,
}) async {
  if (s.store == null) {
    _say(context, 'Shorts cannot be made here.');
    return;
  }
  s.playback.pause();
  final made = await showDialog<Project>(
    context: context,
    builder: (_) => _MakeShortDialog(
      session: s,
      fromMs: fromMs,
      toMs: toMs,
      firstText: firstText,
      lengths: lengths,
      offerSelection: offerSelection,
    ),
  );
  if (made == null || !context.mounted) return;
  await _offerToOpen(context, s, [made]);
}

Future<void> _offerToOpen(
    BuildContext context, EditorSession s, List<Project> made) async {
  final one = made.length == 1;
  final open = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      key: const ValueKey('short-made'),
      title: Text(one ? 'The short is ready' : '${made.length} shorts are ready'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(one
            ? '"${made.single.name}" (${formatLength(made.single.durationMs)}) '
                'is a new project in your project list. This video was not '
                'changed.\n\nOpen it to check the picture (Crop and position '
                'keeps the person in shot) and export it for Shorts / Reels '
                '/ TikTok.'
            : 'They are new projects in your project list:\n'
                '${made.map((p) => '• ${p.name} (${formatLength(p.durationMs)})').join('\n')}\n\n'
                'This video was not changed. Open each one to check the '
                'picture and export it.'),
      ),
      actions: [
        TextButton(
            key: const ValueKey('short-stay'),
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(one ? 'Stay here' : 'OK')),
        if (one && s.openProject != null)
          FilledButton(
              key: const ValueKey('short-open'),
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Open it')),
      ],
    ),
  );
  if (open == true && one) await s.openProject?.call(made.single.id);
}

class _MakeShortDialog extends StatefulWidget {
  const _MakeShortDialog({
    required this.session,
    required this.fromMs,
    required this.toMs,
    required this.firstText,
    required this.lengths,
    required this.offerSelection,
  });
  final EditorSession session;
  final int fromMs;
  final int toMs;
  final String firstText;
  final List<int> lengths;
  final bool offerSelection;

  @override
  State<_MakeShortDialog> createState() => _MakeShortDialogState();
}

class _MakeShortDialogState extends State<_MakeShortDialog> {
  EditorSession get _s => widget.session;

  /// Seconds from the start; null = the part as given (the selection).
  late int? _seconds = widget.lengths.isEmpty || widget.offerSelection
      ? null
      : widget.lengths.first;
  bool _snap = true;
  bool _shortCaptions = true;
  late bool _withTitle = widget.firstText.trim().isNotEmpty;
  late final _title =
      TextEditingController(text: firstSentence(widget.firstText));
  late final _name =
      TextEditingController(text: _shortName(_s.project, widget.fromMs));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The part as it would be cut now.
  Span get _range {
    final total = _s.project.durationMs;
    var from = widget.fromMs.clamp(0, total);
    var to = _seconds == null
        ? widget.toMs.clamp(0, total)
        : (from + _seconds! * 1000).clamp(0, total);
    if (_snap) {
      final r = snapToPauses(_s, from, to);
      from = r.startMs;
      to = r.endMs;
    }
    return (startMs: from, endMs: to);
  }

  Future<void> _make() async {
    final r = _range;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final made = await createShort(
          _s,
          ShortRequest(
            fromMs: r.startMs,
            toMs: r.endMs,
            name: _name.text.trim().isEmpty
                ? _shortName(_s.project, r.startMs)
                : _name.text.trim(),
            shortCaptions: _shortCaptions,
            title: _withTitle ? _title.text : '',
          ));
      if (mounted) Navigator.of(context).pop(made);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError
              ? '${e.message}.'
              : 'The short could not be made ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = _range;
    final length = r.endMs - r.startMs;
    final tooLong = length > kShortMaxSeconds * 1000 + 500;
    final tooShort = length < 1000;
    final hasCaptions = _s.project.titles.any((t) =>
        t.kind == TitleKind.caption && t.startMs < r.endMs && t.endMs > r.startMs);
    final willCaption = hasCaptions || _s.transcripts.value.isNotEmpty;
    return AlertDialog(
      key: const ValueKey('short-dialog'),
      title: Row(
        children: [
          const Expanded(child: Text('Make a short')),
          IconButton(
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline, semanticLabel: 'Help'),
            onPressed: () => showHelpArticle(context, 'make-a-short'),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.lengths.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    children: [
                      if (widget.offerSelection)
                        ChoiceChip(
                          key: const ValueKey('short-length-selection'),
                          label: const Text('The selection'),
                          showCheckmark: false,
                          selected: _seconds == null,
                          onSelected: (_) => setState(() => _seconds = null),
                        ),
                      for (final n in widget.lengths)
                        ChoiceChip(
                          key: ValueKey('short-length-$n'),
                          label: Text('$n s'),
                          showCheckmark: false,
                          selected: _seconds == n,
                          onSelected: (_) => setState(() => _seconds = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                    'From ${formatTime(r.startMs)} to ${formatTime(r.endMs)} · '
                    '${formatLength(length)}',
                    key: const ValueKey('short-length'),
                    style: text.titleSmall),
                if (tooLong)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 16, color: Color(0xFFFFC56B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'Longer than $kShortMaxSeconds seconds: Shorts, '
                              'Reels and TikTok each have their own limit and '
                              'change it. $kShortMaxSeconds seconds is safe '
                              'everywhere; check the site for more.',
                              key: const ValueKey('short-warning'),
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                    'A new upright (9:16) project with only this part. This '
                    'video is not changed.',
                    style: text.bodySmall?.copyWith(color: AppColors.textDim)),
                CheckboxListTile(
                  key: const ValueKey('short-snap'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _snap,
                  onChanged: (v) => setState(() => _snap = v ?? true),
                  title: const Text('Start and end at a pause'),
                  subtitle: const Text('Never in the middle of a word.'),
                ),
                CheckboxListTile(
                  key: const ValueKey('short-captions'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _shortCaptions,
                  onChanged: (v) => setState(() => _shortCaptions = v ?? true),
                  title: const Text('Short caption look'),
                  subtitle: Text(willCaption
                      ? 'Bigger, in the lower middle, outlined, one or two '
                          'lines.'
                      : 'This part has no captions yet; add them in the '
                          'short.'),
                ),
                CheckboxListTile(
                  key: const ValueKey('short-with-title'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _withTitle,
                  onChanged: (v) => setState(() => _withTitle = v ?? false),
                  title: const Text('Title at the top'),
                ),
                if (_withTitle)
                  TextField(
                    key: const ValueKey('short-title'),
                    controller: _title,
                    maxLength: 80,
                    inputFormatters: [LengthLimitingTextInputFormatter(80)],
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'A few words that make people stop',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('short-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name of the new project',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        key: const ValueKey('short-error'),
                        style: const TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            key: const ValueKey('short-go'),
            onPressed: _busy || tooShort ? null : _make,
            child: Text(_busy ? 'Making…' : 'Make the short')),
      ],
    );
  }
}

/// "Make a short from here…": 30 / 45 / 60 s from the playhead. (The
/// timeline has no range selection: I and O trim the clip.)
Future<void> makeShortFromHere(BuildContext context, EditorSession s) {
  final at = s.playback.positionMs;
  final spoken = spokenIn(s);
  final first = [
    for (final x in spoken)
      if (x.endMs > at && x.startMs < at + 8000) x.text.trim(),
  ].join(' ');
  return showMakeShort(context, s,
      fromMs: at,
      toMs: at + kShortLengths.first * 1000,
      firstText: first,
      lengths: kShortLengths);
}

/// Drops a "good moment" marker at the playhead (M; Add > Good moment
/// marker; phones: the Add sheet).
void markGoodMoment(BuildContext context, EditorSession s) {
  if (s.project.clips.isEmpty) return;
  final at = s.playback.positionMs;
  final id = s.editor.addMarker(at);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      // It has a button, and must still go away by itself: on a phone it
      // lies over the tool bar.
      persist: false,
      content: Text(id == null
          ? 'There is already a marker here.'
          : 'Marked a good moment at ${formatTime(at)}.'),
      action: id == null
          ? null
          : SnackBarAction(
              label: 'Undo', onPressed: () => s.editor.removeMarker(id)),
    ));
}

/// What is said around a marker (for the list).
String _saidAt(List<Spoken> spoken, int ms) {
  final t = [
    for (final x in spoken)
      if (x.endMs > ms - 2000 && x.startMs < ms + 4000) x.text.trim(),
  ].join(' ');
  return t.length > 90 ? '${t.substring(0, 89).trimRight()}…' : t;
}

/// The small list of "good moments": jump to one, remove it, make a short
/// around one or around all.
Future<void> showGoodMoments(BuildContext context, EditorSession s) {
  return showDialog<void>(
    context: context,
    builder: (dialog) => ListenableBuilder(
      listenable: s.editor,
      // (Not called "context": the actions below belong to the editor's
      // context, which outlives this dialog.)
      builder: (_, _) {
        final markers = s.project.markers;
        final spoken = spokenIn(s);
        return AlertDialog(
          key: const ValueKey('markers-dialog'),
          title: const Text('Good moments'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SizedBox(
              width: double.maxFinite,
              child: markers.isEmpty
                  ? const Text(
                      'No markers yet. While you watch, press M (on a phone: Add, '
                      'then Good moment marker) whenever something '
                      'good happens. Then come back here to make a short '
                      'around each one.',
                      key: ValueKey('markers-empty'))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in markers)
                          ListTile(
                            key: ValueKey('marker-row-${m.id}'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.flag,
                                color: Color(0xFFFFC56B)),
                            title: Text(formatTime(m.ms)),
                            subtitle: _saidAt(spoken, m.ms).isEmpty
                                ? null
                                : Text(_saidAt(spoken, m.ms),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () {
                              s.playback.pause();
                              s.playback.seek(m.ms);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: ValueKey('marker-short-${m.id}'),
                                  tooltip: 'Make a short around it',
                                  icon: const Icon(Icons.content_cut,
                                      size: 20,
                                      semanticLabel: 'Make a short around it'),
                                  onPressed: () {
                                    Navigator.of(dialog).pop();
                                    final r = markerRange(
                                        m.ms, s.project.durationMs);
                                    showMakeShort(context, s,
                                        fromMs: r.startMs,
                                        toMs: r.endMs,
                                        firstText: _saidAt(spoken, m.ms));
                                  },
                                ),
                                IconButton(
                                  key: ValueKey('marker-remove-${m.id}'),
                                  tooltip: 'Remove the marker',
                                  icon: const Icon(Icons.close,
                                      size: 20,
                                      semanticLabel: 'Remove the marker'),
                                  onPressed: () => s.editor.removeMarker(m.id),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('Close')),
            if (markers.isNotEmpty)
              FilledButton(
                  key: const ValueKey('markers-make-shorts'),
                  onPressed: () {
                    Navigator.of(dialog).pop();
                    makeShortsFromMarkers(context, s);
                  },
                  child: const Text('Make shorts from markers…')),
          ],
        );
      },
    ),
  );
}

/// The part each marker's short would take: [kMarkerBeforeMs] before to
/// [kMarkerAfterMs] after, moved outward to pauses.
List<({Marker marker, Span range})> markerShorts(EditorSession s) => [
      for (final m in s.project.markers)
        (
          marker: m,
          range: () {
            final r = markerRange(m.ms, s.project.durationMs);
            return snapToPauses(s, r.startMs, r.endMs);
          }(),
        ),
    ];

/// "Make shorts from markers…": one short around each marker.
Future<void> makeShortsFromMarkers(BuildContext context, EditorSession s) async {
  if (s.store == null) return;
  final plan = markerShorts(s);
  if (plan.isEmpty) {
    await showGoodMoments(context, s);
    return;
  }
  s.playback.pause();
  var shortCaptions = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const ValueKey('markers-shorts-dialog'),
        title: Text(plan.length == 1
            ? 'Make a short from the marker?'
            : 'Make ${plan.length} shorts from the markers?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'One new upright project around each marker: about '
                      '20 seconds before it to 25 seconds after, starting '
                      'and ending at a pause in the talk. This video is not '
                      'changed.'),
                  const SizedBox(height: 8),
                  for (final x in plan)
                    Text(
                        '• ${formatTime(x.range.startMs)} – '
                        '${formatTime(x.range.endMs)} '
                        '(${formatLength(x.range.endMs - x.range.startMs)})',
                        key: ValueKey('markers-short-${x.marker.id}')),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: shortCaptions,
                    onChanged: (v) => setState(() => shortCaptions = v ?? true),
                    title: const Text('Short caption look'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('markers-shorts-go'),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(plan.length == 1 ? 'Make it' : 'Make them')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final made = <Project>[];
  String? problem;
  for (final x in plan) {
    try {
      made.add(await createShort(
          s,
          ShortRequest(
            fromMs: x.range.startMs,
            toMs: x.range.endMs,
            name: _shortName(s.project, x.marker.ms),
            shortCaptions: shortCaptions,
          )));
    } catch (e) {
      problem = e is StateError ? e.message : '$e';
    }
  }
  if (!context.mounted) return;
  if (made.isEmpty) {
    _say(context, 'No short could be made${problem == null ? '' : ' ($problem)'}.');
    return;
  }
  await _offerToOpen(context, s, made);
}
