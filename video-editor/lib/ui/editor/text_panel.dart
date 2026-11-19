// The Text window (1.13; it replaces the read-only Transcript column of
// 1.11): everything said or written in the project as a readable
// document. Sources: the captions on the timeline (whatever made them),
// the speech transcript, the titles. Paragraphs by speaker and pauses, the
// line being spoken highlighted and kept in view, search, click to jump,
// and light editing of captions (fix a word, delete). Cutting the video
// from here is one clearly separate, confirmed action; there is no
// edit-by-text editor (owner's decision, see docs/HANDOVER.md).
//
// The list is virtualised with EXACT heights: every paragraph is measured
// once per width with the same text and style it is drawn with, so the
// window can jump to any line of a 40-minute project at once and the
// scroll bar is true.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/model/project.dart';
import '../../core/text/text_document.dart';
import '../../core/transcript/speech_edits.dart';
import '../../core/transcript/transcript_timeline.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../speaker_colors.dart';
import '../speech/speech_service.dart' show Transcript;
import '../theme.dart';
import '../widgets.dart';
import 'import_actions.dart';
import '../../core/publish/shorts.dart' show kShortLengths;
import 'session.dart';
import 'shorts_actions.dart';
import 'speech_actions.dart';

const _uuid = Uuid();

/// Opens the Text window as a full-screen sheet (phones, narrow windows).
Future<void> showTextSheet(BuildContext context, EditorSession s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheet) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height,
        child: TextPanel(
          session: s,
          sheet: true,
          host: context,
          onClose: () => Navigator.of(sheet).pop(),
        ),
      ),
    ),
  );
}

String textSourceLabel(TextSource s) => switch (s) {
      TextSource.captions => 'Captions',
      TextSource.transcript => 'Transcript',
      TextSource.titles => 'Titles',
    };

class TextPanel extends StatefulWidget {
  const TextPanel({
    super.key,
    required this.session,
    this.sheet = false,
    this.onClose,
    this.onDock,
    this.host,
  });
  final EditorSession session;

  /// Shown as a full-screen sheet: a play button, no multi-select, no
  /// place menu.
  final bool sheet;
  final VoidCallback? onClose;

  /// "At the right" / "Under the preview"; null: no such menu.
  final ValueChanged<TextDock>? onDock;

  /// Context of the editor (dialogs opened from the sheet belong there).
  final BuildContext? host;

  /// How many paragraphs were built since the app started (tests: the
  /// list builds only what is near the view).
  static int debugParagraphBuilds = 0;

  @override
  State<TextPanel> createState() => TextPanelState();
}

/// Heights of the pieces of a paragraph row.
const double _padV = 7;
const double _nameHeight = 20;
const double _editHeight = 132;
const double _gutter = 54;
const double _padH = 12;
const double _tail = 88;
const double _maxColumn = 880;

class TextPanelState extends State<TextPanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'text-search');
  final _scroll = ScrollController();
  final _edit = TextEditingController();
  final _editFocus = FocusNode(debugLabel: 'text-edit');

  EditorSession get _s => widget.session;

  TextSource? _chosen;
  TextDocument _doc = TextDocument.empty;
  List<TitleOverlay>? _docTitles;
  Project? _docProject;
  Map<String, Transcript>? _docTranscripts;
  TextSource? _docSource;

  final Set<String> _selected = {};
  String? _anchor;
  String? _editing;
  bool _follow = true;
  bool _programmatic = false;
  bool _pointerDown = false;

  int _active = -1;
  int _activeWord = -1;

  List<TextMatch> _matches = const [];
  int _match = -1;
  String _matchQuery = '';
  TextDocument? _matchDoc;

  // Layout (see the top of this file).
  double _layoutWidth = -1;
  TextScaler _layoutScaler = TextScaler.noScaling;
  TextDocument? _layoutDoc;
  String? _layoutEditing;
  Float64List _tops = Float64List(1);
  final Map<String, double> _heights = {};
  TextStyle _style = const TextStyle();

  String? _lastTapId;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _s.playback.position.addListener(_onPosition);
    _s.selection.addListener(_onSelection);
    _s.findInText.addListener(focusSearch);
    _s.textDeleteHook = _deleteKey;
  }

  /// The Delete key with several captions selected here deletes them all
  /// (with one, the editor deletes the caption selected on the timeline,
  /// which is the same one).
  bool _deleteKey() {
    if (!mounted || !_editable || _selected.length < 2) return false;
    deleteSelected();
    return true;
  }

  @override
  void dispose() {
    _s.playback.position.removeListener(_onPosition);
    _s.selection.removeListener(_onSelection);
    _s.findInText.removeListener(focusSearch);
    if (_s.textDeleteHook == _deleteKey) _s.textDeleteHook = null;
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _edit.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  // Sources ------------------------------------------------------------------

  List<TextSource> get _sources {
    final p = _s.project;
    return [
      if (p.titles.any((t) => t.kind == TitleKind.caption)) TextSource.captions,
      if (_s.speech != null && _s.transcripts.value.isNotEmpty)
        TextSource.transcript,
      if (p.titles.any((t) => t.kind == TitleKind.title)) TextSource.titles,
    ];
  }

  /// The source shown: the one picked while it exists, else captions when
  /// the project has any, else the transcript, else the titles.
  TextSource? get source {
    final all = _sources;
    if (all.isEmpty) return null;
    return all.contains(_chosen) ? _chosen : all.first;
  }

  TextDocument get document => _doc;
  bool get follow => _follow;
  Set<String> get selectedIds => Set.unmodifiable(_selected);

  void _refreshDoc() {
    final src = source;
    final p = _s.project;
    if (src == _docSource &&
        (src == TextSource.transcript
            ? identical(p, _docProject) &&
                identical(_s.transcripts.value, _docTranscripts)
            : identical(p.titles, _docTitles))) {
      return;
    }
    _docSource = src;
    _docTitles = p.titles;
    _docProject = p;
    _docTranscripts = _s.transcripts.value;
    _doc = switch (src) {
      null => TextDocument.empty,
      TextSource.captions =>
        buildTextDocument(TextSource.captions, captionLines(p)),
      TextSource.titles => buildTextDocument(TextSource.titles, titleLines(p)),
      TextSource.transcript => buildTextDocument(
          TextSource.transcript,
          transcriptLines(
              timelineSegments(timelineWords(p, _s.transcriptOf)))),
    };
    _selected.removeWhere((id) => _doc.indexOf(id) < 0);
    if (_anchor != null && _doc.indexOf(_anchor!) < 0) _anchor = null;
    if (_editing != null && _doc.indexOf(_editing!) < 0) _editing = null;
    _updateActive();
  }

  // Playback: the line being spoken ------------------------------------------

  bool _updateActive() {
    final ms = _s.playback.positionMs;
    final active = _doc.activeLineAt(ms);
    var word = -1;
    if (active >= 0) {
      final words = _doc.lines[active].words;
      for (var i = 0; i < words.length; i++) {
        if (words[i].startMs <= ms) word = i;
      }
    }
    if (active == _active && word == _activeWord) return false;
    _active = active;
    _activeWord = word;
    return true;
  }

  void _onPosition() {
    if (!mounted) return;
    final before = _active;
    if (_updateActive()) setState(() {});
    if (_follow && _active >= 0 && _active != before) {
      _showLine(_active, animate: _s.playback.playing);
    }
  }

  void _onSelection() {
    if (!mounted) return;
    final sel = _s.selection.value;
    if (sel == null || sel.kind != ItemKind.title) return;
    final i = _doc.indexOf(sel.id);
    if (i < 0) return;
    if (_selected.length == 1 && _selected.contains(sel.id)) return;
    setState(() {
      _selected
        ..clear()
        ..add(sel.id);
      _anchor = sel.id;
    });
    _showLine(i, animate: false, force: true);
  }

  // Scrolling ----------------------------------------------------------------

  /// Top and bottom of line [index] in the list's content.
  ({double top, double bottom})? _lineBox(int index) {
    if (_layoutDoc != _doc || index < 0 || index >= _doc.lines.length) {
      return null;
    }
    final pi = _doc.paragraphOfLine[index];
    final par = _doc.paragraphs[pi];
    final top = _tops[pi] + _padV + (_showsName(pi) ? _nameHeight : 0);
    final painter = TextPainter(
      text: TextSpan(text: par.text, style: _style),
      textDirection: textDirectionOf(par.text),
      textScaler: _layoutScaler,
    )..layout(maxWidth: _layoutWidth);
    final k = index - par.firstLine;
    final start = par.offsets[k];
    final boxes = painter.getBoxesForSelection(TextSelection(
        baseOffset: start,
        extentOffset: start + math.max(1, par.lines[k].text.length)));
    var a = 0.0, b = painter.preferredLineHeight;
    if (boxes.isNotEmpty) {
      a = boxes.map((r) => r.top).reduce(math.min);
      b = boxes.map((r) => r.bottom).reduce(math.max);
    }
    painter.dispose();
    return (top: top + a, bottom: top + b);
  }

  /// Brings line [index] into view (when it is not): while following
  /// playback, when a caption is picked on the timeline, for a search
  /// match and for "Now".
  void _showLine(int index, {bool animate = false, bool force = false}) {
    void go() {
      if (!mounted || !_scroll.hasClients) return;
      final box = _lineBox(index);
      if (box == null) return;
      final pos = _scroll.position;
      final target = followOffset(
        top: box.top,
        bottom: box.bottom,
        offset: pos.pixels,
        viewport: pos.viewportDimension,
        // The list only estimates its length until it has been to the
        // end; the measured one is exact.
        maxOffset: math.max(0.0, _tops.last + _tail - pos.viewportDimension),
      );
      if (target == null) return;
      _programmatic = true;
      if (animate && (target - pos.pixels).abs() < pos.viewportDimension * 1.5) {
        _scroll
            .animateTo(target,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut)
            .whenComplete(() => _programmatic = false);
      } else {
        _scroll.jumpTo(target);
        _programmatic = false;
      }
    }

    if (_layoutDoc == _doc && _scroll.hasClients) {
      go();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    // By hand: a drag or a fling, the mouse wheel, the scroll bar's
    // thumb (the pointer is down). Not: this window's own scrolling, nor
    // the list correcting its length as it learns it.
    final byHand = (n is ScrollUpdateNotification &&
            (n.dragDetails != null ||
                (_pointerDown && !_programmatic && (n.scrollDelta ?? 0) != 0))) ||
        (n is UserScrollNotification &&
            n.direction != ScrollDirection.idle &&
            !_programmatic);
    if (byHand && _follow) setState(() => _follow = false);
    return false;
  }

  /// "Now": back to the line being spoken, following again.
  void goToNow() {
    setState(() => _follow = true);
    final i = _active >= 0
        ? _active
        : _doc.lineIndexBefore(_s.playback.positionMs);
    if (i >= 0) _showLine(i, force: true);
  }

  // Search -------------------------------------------------------------------

  void focusSearch() {
    if (!mounted) return;
    _searchFocus.requestFocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  void _refreshMatches() {
    final q = _search.text;
    if (q == _matchQuery && identical(_matchDoc, _doc)) return;
    final fresh = q != _matchQuery;
    _matchQuery = q;
    _matchDoc = _doc;
    _matches = findInText(_doc, q);
    if (_matches.isEmpty) {
      _match = -1;
    } else if (fresh || _match < 0 || _match >= _matches.length) {
      // Start at the first match at or after the line in view / playing.
      final from = math.max(0, _doc.lineIndexBefore(_s.playback.positionMs));
      _match = _matches.indexWhere((m) => m.line >= from);
      if (_match < 0) _match = 0;
    }
  }

  void _onSearchChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _match >= 0 && _match < _matches.length) {
        _follow = false;
        _showLine(_matches[_match].line, force: true);
        setState(() {});
      }
    });
  }

  void stepMatch(int by) {
    if (_matches.isEmpty) return;
    setState(() {
      _match = (_match + by) % _matches.length;
      if (_match < 0) _match += _matches.length;
      _follow = false;
    });
    _showLine(_matches[_match].line, force: true);
  }

  // Clicks, selection, editing -----------------------------------------------

  bool get _editable => _doc.source == TextSource.captions;

  void _tapLine(int index) {
    final line = _doc.lines[index];
    final now = DateTime.now();
    final twice = _lastTapId == line.id &&
        now.difference(_lastTap) < const Duration(milliseconds: 400);
    _lastTapId = line.id;
    _lastTap = now;
    if (twice && _editable) {
      startEditing(line.id);
      return;
    }
    final shift = !widget.sheet && HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      final from = _anchor == null ? -1 : _doc.indexOf(_anchor!);
      if (shift && from >= 0) {
        _selected.clear();
        for (var i = math.min(from, index); i <= math.max(from, index); i++) {
          _selected.add(_doc.lines[i].id);
        }
      } else {
        _selected
          ..clear()
          ..add(line.id);
        _anchor = line.id;
      }
    });
    if (shift) return;
    // The playhead goes there, and the caption is selected on the
    // timeline.
    _s.playback.pause();
    _s.playback.seek(line.startMs);
    if (_doc.source != TextSource.transcript) {
      _s.select(ItemKind.title, line.id);
    }
  }

  void clearSelection() => setState(() {
        _selected.clear();
        _anchor = null;
      });

  void startEditing(String id) {
    final i = _doc.indexOf(id);
    if (i < 0 || !_editable) return;
    setState(() {
      _editing = id;
      _selected
        ..clear()
        ..add(id);
      _anchor = id;
      _edit.text = _doc.lines[i].raw;
      _edit.selection =
          TextSelection(baseOffset: 0, extentOffset: _edit.text.length);
    });
    _s.playback.pause();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocus.requestFocus();
      _showLine(i, force: true);
    });
  }

  void cancelEditing() {
    if (_editing == null) return;
    setState(() => _editing = null);
  }

  /// Saves the edited caption text: one undo step ("Edited caption …").
  void saveEditing() {
    final id = _editing;
    if (id == null) return;
    final text = _edit.text.trim();
    final title = _s.project.titles.where((t) => t.id == id).firstOrNull;
    if (title == null) {
      cancelEditing();
      return;
    }
    if (text.isEmpty) {
      _say('A caption cannot be empty. Use "Delete caption" to remove it.');
      return;
    }
    setState(() => _editing = null);
    if (text != title.text) _s.editor.updateTitle(title.copyWith(text: text));
  }

  /// Deletes the selected captions: one undo step.
  void deleteSelected() {
    if (!_editable || _selected.isEmpty) return;
    final ids = [
      for (final l in _doc.lines)
        if (_selected.contains(l.id)) l.id,
    ];
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      _s.editor.removeTitle(ids.single);
    } else {
      _s.editor.transaction(() {
        ids.forEach(_s.editor.removeTitle);
      }, label: 'Deleted ${ids.length} captions');
    }
    setState(() {
      _selected.clear();
      _anchor = null;
      _editing = null;
    });
    _say(
        ids.length == 1
            ? 'Caption deleted.'
            : '${ids.length} captions deleted.',
        undo: true);
  }

  ({int fromMs, int toMs, String text})? get _selectedRange {
    final lines = [
      for (final l in _doc.lines)
        if (_selected.contains(l.id)) l,
    ];
    if (lines.isEmpty) return null;
    return (
      fromMs: lines.map((l) => l.startMs).reduce(math.min),
      toMs: lines.map((l) => l.endMs).reduce(math.max),
      text: lines.map((l) => l.text).join(' '),
    );
  }

  /// "Cut this part out of the video…": shows what would go, asks, then
  /// cuts with the editor's own cut (logged so it can be put back).
  Future<void> cutSelectedOut() async {
    final range = _selectedRange;
    if (range == null) return;
    final plan = planTimelineCut(_s.project, range.fromMs, range.toMs);
    if (plan.isEmpty) {
      _say('This part is not over the video, so there is nothing to cut.');
      return;
    }
    _s.playback.pause();
    final excerpt = range.text.length > 160
        ? '${range.text.substring(0, 159).trimRight()}…'
        : range.text;
    final ok = await showDialog<bool>(
      context: widget.host ?? context,
      builder: (dialog) => AlertDialog(
        key: const ValueKey('text-cut-dialog'),
        title: const Text('Cut this part out of the video?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'From ${formatTime(plan.fromMs)} to ${formatTime(plan.toMs)}: '
                  '${formatLength(plan.removedMs)} of the picture and its '
                  'sound will be removed.',
                  key: const ValueKey('text-cut-what'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text('“$excerpt”',
                  textDirection: textDirectionOf(excerpt),
                  style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 10),
              Text(
                  'Captions and titles on this part go with it.'
                  '${plan.photosLeft > 0 ? ' A photo that is only partly in this part stays as it is.' : ''}'
                  '\nUndo brings everything back. Later, '
                  '${_s.speech != null ? 'Edit > Speech > Automatic cuts… > ' : ''}'
                  'Put back returns the picture and sound (not the captions).',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('text-cut-go'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Cut it out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // The project may have changed while the question was up.
    final fresh = planTimelineCut(_s.project, range.fromMs, range.toMs);
    final word = range.text.length > 40
        ? '${range.text.substring(0, 39).trimRight()}…'
        : range.text;
    final n = applyTimelineCut(_s.editor.editor, fresh,
        word: word, newId: _uuid.v4);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _anchor = null;
    });
    _say(
        n == 0
            ? 'Nothing was cut.'
            : 'Cut ${formatLength(fresh.removedMs)} out of the video.',
        undo: n > 0);
  }

  /// "Make a short from this…": the selected lines as a new upright
  /// project. With one line selected (phones select one at a time) the
  /// dialog offers 30 / 45 / 60 s from there.
  Future<void> makeShortFromSelection() async {
    final range = _selectedRange;
    if (range == null) return;
    final host = widget.host ?? context;
    // Phones: the sheet goes, the question belongs to the editor.
    if (widget.sheet) widget.onClose?.call();
    await showMakeShort(host, _s,
        fromMs: range.fromMs,
        toMs: range.toMs,
        firstText: range.text,
        lengths: kShortLengths,
        offerSelection: true);
  }

  void _say(String message, {bool undo = false}) {
    final host = widget.host ?? context;
    if (!host.mounted) return;
    ScaffoldMessenger.maybeOf(host)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: undo
            ? SnackBarAction(label: 'Undo', onPressed: _s.editor.undo)
            : null,
      ));
  }

  // Copy and save ------------------------------------------------------------

  Future<void> copyAll({required bool detailed}) async {
    final text =
        documentAsText(_doc, times: detailed, speakers: detailed);
    await Clipboard.setData(ClipboardData(text: text));
    _say('Copied the text'
        '${detailed ? ' with times and names' : ''} '
        '(${_doc.paragraphs.length} '
        '${_doc.paragraphs.length == 1 ? 'paragraph' : 'paragraphs'}).');
  }

  Future<void> saveAsText() async {
    try {
      final where = await _s.documents.saveText(
          '${safeFileName(_s.project.name)}.txt',
          documentAsText(_doc, times: true, speakers: true));
      if (where != null) _say('Text saved: $where');
    } catch (e) {
      _say('The text could not be saved ($e)');
    }
  }

  // Layout -------------------------------------------------------------------

  bool _showsName(int paragraph) {
    final p = _doc.paragraphs[paragraph];
    if (p.speaker.isEmpty) return false;
    return paragraph == 0 ||
        _doc.paragraphs[paragraph - 1].speaker != p.speaker;
  }

  void _ensureLayout(double textWidth, TextScaler scaler, TextStyle style) {
    if (_layoutDoc == _doc &&
        _layoutWidth == textWidth &&
        _layoutScaler == scaler &&
        _layoutEditing == _editing) {
      return;
    }
    if (_layoutWidth != textWidth || _layoutScaler != scaler) _heights.clear();
    if (_heights.length > 6000) _heights.clear();
    _style = style;
    _layoutWidth = textWidth;
    _layoutScaler = scaler;
    _layoutDoc = _doc;
    _layoutEditing = _editing;
    final n = _doc.paragraphs.length;
    final tops = Float64List(n + 1);
    final editAt =
        _editing == null ? -1 : _doc.indexOf(_editing!);
    final editPar = editAt < 0 ? -1 : _doc.paragraphOfLine[editAt];
    var y = 0.0;
    for (var i = 0; i < n; i++) {
      tops[i] = y;
      final par = _doc.paragraphs[i];
      var h = _heights[par.text];
      if (h == null) {
        final painter = TextPainter(
          text: TextSpan(text: par.text, style: style),
          textDirection: textDirectionOf(par.text),
          textScaler: scaler,
        )..layout(maxWidth: textWidth);
        h = painter.height;
        painter.dispose();
        _heights[par.text] = h;
      }
      y += 2 * _padV +
          (_showsName(i) ? _nameHeight : 0) +
          h +
          (i == editPar ? _editHeight : 0);
    }
    tops[n] = y;
    _tops = tops;
  }

  /// Top of every paragraph and the end of the last (tests).
  Float64List get debugTops => _tops;

  // Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): focusSearch,
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([_s.editor, _s.transcripts]),
        builder: (context, _) {
          _refreshDoc();
          _refreshMatches();
          return Container(
            key: const ValueKey('text-panel'),
            color: AppColors.panel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                if (_sources.length > 1) _sourceSwitch(),
                if (!_doc.isEmpty) _searchRow(),
                const Divider(height: 1),
                Expanded(
                    child:
                        _doc.isEmpty ? _TextEmpty(panel: this) : _list()),
                if (_selected.isNotEmpty && _editing == null) _selectionBar(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final src = source;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
      child: Row(
        children: [
          const Icon(Icons.subject, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Text',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          if (widget.sheet)
            ListenableBuilder(
              listenable: _s.playback,
              builder: (context, _) => IconButton(
                key: const ValueKey('text-play'),
                tooltip: _s.playback.playing ? 'Pause' : 'Play',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    _s.playback.playing ? Icons.pause : Icons.play_arrow,
                    semanticLabel: _s.playback.playing ? 'Pause' : 'Play'),
                onPressed:
                    _s.playback.durationMs > 0 ? _s.playback.toggle : null,
              ),
            ),
          if (!_doc.isEmpty)
            IconButton(
              key: const ValueKey('text-follow'),
              tooltip: _follow
                  ? 'Following playback (click to stop)'
                  : 'Follow playback',
              visualDensity: VisualDensity.compact,
              isSelected: _follow,
              icon: const Icon(Icons.my_location, size: 18,
                  semanticLabel: 'Follow playback'),
              onPressed: () => _follow
                  ? setState(() => _follow = false)
                  : goToNow(),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('text-menu'),
            tooltip: 'Copy, save, place',
            icon: const Icon(Icons.more_vert, size: 18,
                semanticLabel: 'Copy, save, place'),
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  copyAll(detailed: false);
                case 'copy-detailed':
                  copyAll(detailed: true);
                case 'save-txt':
                  saveAsText();
                case 'save-srt':
                  exportSubtitles(widget.host ?? context, _s);
                case 'right':
                  widget.onDock?.call(TextDock.right);
                case 'below':
                  widget.onDock?.call(TextDock.below);
                case 'help':
                  showHelpArticle(widget.host ?? context, 'text-window');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'copy',
                  enabled: !_doc.isEmpty,
                  child: const Text('Copy all text')),
              PopupMenuItem(
                  value: 'copy-detailed',
                  enabled: !_doc.isEmpty,
                  child: const Text('Copy with times and names')),
              PopupMenuItem(
                  value: 'save-txt',
                  enabled: !_doc.isEmpty,
                  child: const Text('Save as text file…')),
              PopupMenuItem(
                  value: 'save-srt',
                  enabled: hasCaptions(_s.project),
                  child: const Text('Save as subtitle file (.srt)…')),
              if (widget.onDock != null) ...[
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                    value: 'right',
                    checked: _s.textDock.value == TextDock.right,
                    child: const Text('Show at the right')),
                CheckedPopupMenuItem(
                    value: 'below',
                    checked: _s.textDock.value == TextDock.below,
                    child: const Text('Show under the preview')),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'help', child: Text('Help: read and search the text')),
            ],
          ),
          if (widget.onClose != null)
            IconButton(
              key: const ValueKey('text-close'),
              tooltip: 'Close the Text window',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18,
                  semanticLabel: 'Close the Text window'),
              onPressed: widget.onClose,
            ),
          if (src == null) const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _sourceSwitch() {
    final src = source;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<TextSource>(
          key: const ValueKey('text-source'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            for (final s in _sources)
              ButtonSegment(
                  value: s,
                  label: Text(textSourceLabel(s),
                      key: ValueKey('text-source-${s.name}'))),
          ],
          selected: {?src},
          onSelectionChanged: (v) => setState(() {
            _chosen = v.first;
            _selected.clear();
            _anchor = null;
            _editing = null;
          }),
        ),
      ),
    );
  }

  Widget _searchRow() {
    final has = _search.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  stepMatch(
                      HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  setState(_search.clear);
                  _searchFocus.unfocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const ValueKey('text-search'),
                controller: _search,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  stepMatch(1);
                  _searchFocus.requestFocus();
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find in the text…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 34, minHeight: 0),
                  suffixIcon: !has
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
                onChanged: (_) => _onSearchChanged(),
              ),
            ),
          ),
          if (has) ...[
            const SizedBox(width: 8),
            Text(
                _matches.isEmpty
                    ? 'Not found'
                    : '${_match + 1} of ${_matches.length}',
                key: const ValueKey('text-match-count'),
                style: TextStyle(
                    fontSize: 12,
                    color: _matches.isEmpty
                        ? AppColors.danger
                        : AppColors.textDim,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            IconButton(
              key: const ValueKey('text-prev'),
              tooltip: 'Previous match (Shift+Enter)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 20,
                  semanticLabel: 'Previous match'),
              onPressed: _matches.isEmpty ? null : () => stepMatch(-1),
            ),
            IconButton(
              key: const ValueKey('text-next'),
              tooltip: 'Next match (Enter)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20,
                  semanticLabel: 'Next match'),
              onPressed: _matches.isEmpty ? null : () => stepMatch(1),
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _list() {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 15, height: 1.5, color: const Color(0xFFE9EBF0));
    final colors = speakerColors(_s.project, _doc.speakers);
    // Matches per line, for the paragraphs that are built.
    final byLine = <int, List<int>>{};
    for (var i = 0; i < _matches.length; i++) {
      (byLine[_matches[i].line] ??= []).add(i);
    }
    return LayoutBuilder(
      builder: (context, box) {
        // A text column of comfortable width, in steps (so that dragging
        // the window's edge measures the text now and then, not on every
        // pixel).
        final column = (math.min(box.maxWidth, _maxColumn) / 16).floor() * 16.0;
        final textWidth = math.max(80.0, column - 2 * _padH - _gutter - 10);
        _ensureLayout(textWidth, scaler, style);
        final n = _doc.paragraphs.length;
        final rtl = n > 0 &&
            textDirectionOf(_doc.paragraphs.first.text) == TextDirection.rtl;
        return Stack(
          children: [
            Listener(
              onPointerDown: (_) => _pointerDown = true,
              onPointerUp: (_) => _pointerDown = false,
              onPointerCancel: (_) => _pointerDown = false,
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && _follow) {
                  setState(() => _follow = false);
                }
              },
              child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  key: const ValueKey('text-list'),
                  controller: _scroll,
                  itemCount: n + 1,
                  itemExtentBuilder: (i, _) => i < n
                      ? _tops[i + 1] - _tops[i]
                      : (i == n ? _tail : null),
                  itemBuilder: (context, i) {
                    if (i >= n) return const SizedBox(height: _tail);
                    final par = _doc.paragraphs[i];
                    final last = par.firstLine + par.lines.length;
                    return Align(
                      alignment: box.maxWidth > column + 48
                          ? Alignment.topCenter
                          : (rtl ? Alignment.topRight : Alignment.topLeft),
                      child: SizedBox(
                        width: column,
                        child: _ParagraphView(
                          key: ValueKey('text-par-${par.lines.first.id}'),
                          paragraph: par,
                          style: style,
                          scaler: scaler,
                          textWidth: textWidth,
                          showName: _showsName(i),
                          color: colors[par.speaker],
                          active: _active >= par.firstLine && _active < last
                              ? _active - par.firstLine
                              : -1,
                          activeWord: _activeWord,
                          selected: {
                            for (var k = 0; k < par.lines.length; k++)
                              if (_selected.contains(par.lines[k].id)) k,
                          },
                          matches: [
                            for (var l = par.firstLine; l < last; l++)
                              for (final m in byLine[l] ?? const <int>[])
                                (
                                  line: l - par.firstLine,
                                  start: _matches[m].start,
                                  end: _matches[m].end,
                                  current: m == _match,
                                ),
                          ],
                          editing: _editing == null
                              ? -1
                              : par.lines
                                  .indexWhere((l) => l.id == _editing),
                          editor: _editing == null ? null : _editorBox(),
                          onTapLine: (k) => _tapLine(par.firstLine + k),
                          onTapTime: () {
                            _s.playback.pause();
                            _s.playback.seek(par.startMs);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              ),
            ),
            if (!_follow)
              Positioned(
                right: 16,
                bottom: 12,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('text-now'),
                  onPressed: goToNow,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Now'),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The box a caption is edited in, inside its paragraph.
  Widget _editorBox() {
    return SizedBox(
      height: _editHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyUpEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.escape) {
                    cancelEditing();
                    return KeyEventResult.handled;
                  }
                  if ((key == LogicalKeyboardKey.enter ||
                          key == LogicalKeyboardKey.numpadEnter) &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    saveEditing();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const ValueKey('text-edit-field'),
                  controller: _edit,
                  focusNode: _editFocus,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textDirection: textDirectionOf(_edit.text),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Enter saves · Shift+Enter: new line',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textDim)),
                  ),
                  TextButton(
                      key: const ValueKey('text-edit-cancel'),
                      onPressed: cancelEditing,
                      child: const Text('Cancel')),
                  FilledButton(
                      key: const ValueKey('text-edit-save'),
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: saveEditing,
                      child: const Text('Save')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar() {
    final range = _selectedRange;
    final n = _selected.length;
    final what = switch (_doc.source) {
      TextSource.captions => n == 1 ? 'caption' : 'captions',
      TextSource.titles => n == 1 ? 'title' : 'titles',
      TextSource.transcript => n == 1 ? 'phrase' : 'phrases',
    };
    // Computers: low rows, so that the bar hides little of the text (a
    // double click must still find its line). Phones keep finger size.
    final compact = widget.sheet
        ? const ButtonStyle()
        : TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
    return Container(
      key: const ValueKey('text-selection-bar'),
      decoration: const BoxDecoration(
        color: AppColors.panelHigh,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
                '$n $what'
                '${range == null ? '' : ' · ${formatTime(range.fromMs)}–${formatTime(range.toMs)}'}',
                key: const ValueKey('text-selection-count'),
                style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          ),
          if (_editable && n == 1)
            TextButton.icon(
              key: const ValueKey('text-edit'),
              style: compact,
              onPressed: () => startEditing(_selected.single),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
          if (_editable)
            TextButton.icon(
              key: const ValueKey('text-delete'),
              style: compact,
              onPressed: deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(n == 1 ? 'Delete caption' : 'Delete captions'),
            ),
          // Computers only, and apart from the caption actions: this one
          // changes the VIDEO.
          if (!widget.sheet && _doc.source != TextSource.titles) ...[
            TextButton.icon(
              key: const ValueKey('text-cut'),
              style: compact.copyWith(
                  foregroundColor:
                      const WidgetStatePropertyAll(AppColors.danger)),
              onPressed: cutSelectedOut,
              icon: const Icon(Icons.content_cut, size: 16),
              label: const Text('Cut this part out of the video…'),
            ),
          ],
          // A short is a NEW project; this video is not changed.
          if (_doc.source != TextSource.titles && _s.store != null)
            TextButton.icon(
              key: const ValueKey('text-make-short'),
              style: compact,
              onPressed: makeShortFromSelection,
              icon: const Icon(Icons.smartphone, size: 16),
              label: const Text('Make a short from this…'),
            ),
          IconButton(
            key: const ValueKey('text-selection-clear'),
            tooltip: 'Clear the selection',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16,
                semanticLabel: 'Clear the selection'),
            onPressed: clearSelection,
          ),
        ],
      ),
    );
  }
}

typedef _Mark = ({int line, int start, int end, bool current});

/// One paragraph: the time, the speaker's name (once), and the lines as
/// one flowing text in which every line can be clicked.
class _ParagraphView extends StatefulWidget {
  const _ParagraphView({
    super.key,
    required this.paragraph,
    required this.style,
    required this.scaler,
    required this.textWidth,
    required this.showName,
    required this.color,
    required this.active,
    required this.activeWord,
    required this.selected,
    required this.matches,
    required this.editing,
    required this.editor,
    required this.onTapLine,
    required this.onTapTime,
  });
  final TextParagraph paragraph;
  final TextStyle style;
  final TextScaler scaler;
  final double textWidth;
  final bool showName;
  final Color? color;

  /// Index (in the paragraph) of the line being spoken, or -1; and the
  /// word in it (transcripts).
  final int active;
  final int activeWord;
  final Set<int> selected;
  final List<_Mark> matches;

  /// Index of the line being edited, or -1, and its editor.
  final int editing;
  final Widget? editor;
  final ValueChanged<int> onTapLine;
  final VoidCallback onTapTime;

  @override
  State<_ParagraphView> createState() => _ParagraphViewState();
}

class _ParagraphViewState extends State<_ParagraphView> {
  final List<TapGestureRecognizer> _taps = [];

  void _syncTaps() {
    final n = widget.paragraph.lines.length;
    while (_taps.length > n) {
      _taps.removeLast().dispose();
    }
    while (_taps.length < n) {
      final k = _taps.length;
      _taps.add(TapGestureRecognizer()..onTap = () => widget.onTapLine(k));
    }
  }

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  static const _selectedBg = Color(0x597C9BFF);
  static const _activeBg = Color(0x2EFFFFFF);
  static const _wordBg = Color(0x807C9BFF);
  static const _matchBg = Color(0x73E3C44F);
  static const _currentBg = Color(0xFFF0A04B);

  List<InlineSpan> _lineSpans(int k) {
    final w = widget;
    final line = w.paragraph.lines[k];
    final text = line.text;
    final base = w.selected.contains(k)
        ? _selectedBg
        : (k == w.active ? _activeBg : null);
    // Marks inside the line: search matches, then the word being spoken.
    final marks = <({int start, int end, Color bg, Color? fg})>[
      for (final m in w.matches)
        if (m.line == k)
          (
            start: m.start.clamp(0, text.length),
            end: m.end.clamp(0, text.length),
            bg: m.current ? _currentBg : _matchBg,
            fg: m.current ? Colors.black : null,
          ),
    ];
    if (k == w.active && w.activeWord >= 0 && line.words.isNotEmpty &&
        marks.isEmpty) {
      var at = 0;
      for (var i = 0; i < line.words.length && i <= w.activeWord; i++) {
        if (i == w.activeWord) {
          final end = math.min(text.length, at + line.words[i].text.length);
          if (end > at) marks.add((start: at, end: end, bg: _wordBg, fg: null));
        }
        at += line.words[i].text.length + 1;
      }
    }
    marks.sort((a, b) => a.start.compareTo(b.start));
    TextSpan piece(String s, Color? bg, Color? fg) => TextSpan(
          text: s,
          recognizer: _taps[k],
          mouseCursor: SystemMouseCursors.click,
          style: bg == null && fg == null
              ? null
              : TextStyle(backgroundColor: bg, color: fg),
        );
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in marks) {
      if (m.start < at || m.end <= m.start) continue;
      if (m.start > at) out.add(piece(text.substring(at, m.start), base, null));
      out.add(piece(text.substring(m.start, m.end), m.bg, m.fg));
      at = m.end;
    }
    if (at < text.length || out.isEmpty) {
      out.add(piece(text.substring(at), base, null));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    TextPanel.debugParagraphBuilds++;
    _syncTaps();
    final w = widget;
    final par = w.paragraph;
    final dir = textDirectionOf(par.text);
    final spans = <InlineSpan>[];
    for (var k = 0; k < par.lines.length; k++) {
      if (k > 0) {
        // The space between two lines belongs to neither, unless both are
        // selected (then the selection reads as one stretch).
        final both = w.selected.contains(k) && w.selected.contains(k - 1);
        spans.add(TextSpan(
            text: ' ',
            style: both
                ? const TextStyle(backgroundColor: _selectedBg)
                : null));
      }
      spans.addAll(_lineSpans(k));
    }
    final time = InkWell(
      onTap: w.onTapTime,
      child: SizedBox(
        width: _gutter,
        child: Padding(
          padding: EdgeInsets.only(top: w.showName ? 2 : 3),
          child: Text(formatDuration(par.startMs),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ),
    );
    final body = SizedBox(
      width: w.textWidth,
      child: Column(
        crossAxisAlignment: dir == TextDirection.rtl
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (w.showName)
            SizedBox(
              height: _nameHeight,
              child: Text(par.speaker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: w.color ?? AppColors.textDim)),
            ),
          SizedBox(
            width: w.textWidth,
            child: RichText(
              key: ValueKey('text-body-${par.lines.first.id}'),
              text: TextSpan(style: w.style, children: spans),
              textDirection: dir,
              textAlign: TextAlign.start,
              textScaler: w.scaler,
            ),
          ),
          if (w.editing >= 0) ?w.editor,
        ],
      ),
    );
    // The height is the measured one (the list's extent); should a font
    // ever lay out a hair taller, the text is clipped, never an error.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Directionality(
        textDirection: dir,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: _padV),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              time,
              // The speaker's colour runs down the side of what they say.
              Container(
                padding: const EdgeInsetsDirectional.only(start: 7),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(
                        width: 3,
                        color: w.color?.withValues(alpha: 0.85) ??
                            const Color(0x22FFFFFF)),
                  ),
                ),
                child: body,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Nothing to read yet: how to get text, with buttons.
class _TextEmpty extends StatelessWidget {
  const _TextEmpty({required this.panel});
  final TextPanelState panel;

  @override
  Widget build(BuildContext context) {
    final s = panel._s;
    final host = panel.widget.host ?? context;
    final hasVideo = s.project.clips.isNotEmpty;
    final speech = s.speech != null && canTranscribe(s.project);
    void close() {
      if (panel.widget.sheet) panel.widget.onClose?.call();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              !hasVideo
                  ? 'Add a video first. Then everything said or written in '
                      'it can be read here.'
                  : 'No text yet. Everything said or written in the video '
                      'is shown here once there are captions'
                      '${s.speech != null ? ' or a transcript' : ''}: '
                      'read it, search it, click a sentence to go there.',
              key: const ValueKey('text-empty'),
              style: const TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 14),
          if (hasVideo)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (speech)
                  OutlinedButton.icon(
                    key: const ValueKey('text-transcribe'),
                    onPressed: () {
                      close();
                      showTranscribeDialog(host, s);
                    },
                    icon:
                        const Icon(Icons.record_voice_over_outlined, size: 18),
                    label: const Text('Transcribe speech…'),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('text-import'),
                  onPressed: () {
                    close();
                    importSubtitles(host, s);
                  },
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Import subtitles…'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('text-add-caption'),
                  onPressed: () {
                    close();
                    showCaptionsDialog(host, s);
                  },
                  icon: const Icon(Icons.closed_caption_outlined, size: 18),
                  label: const Text('Add caption…'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
