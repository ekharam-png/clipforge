// Speech-to-text in the editor (1.11, computers only): "Transcribe
// speech…" with its language packs, "Captions from speech" and "Remove
// filler words". Everything here is reached only when
// `EditorSession.speech` is there; on phones it is null and none of it is
// built.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/model/project.dart';
import '../../core/transcript/captions.dart';
import '../../core/transcript/cut_plan.dart';
import '../../core/transcript/fillers.dart';
import '../../core/transcript/speech_edits.dart';
import '../../media/jump_check.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../speech/speech_service.dart';
import '../theme.dart';
import 'session.dart';

const _uuid = Uuid();
const _dim = TextStyle(fontSize: 12, color: AppColors.textDim);

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// True when the project has something speech-to-text could listen to.
bool canTranscribe(Project p) => speechSourcesOfProject(p).isNotEmpty;

/// How much of the project's speech has a transcript now.
TranscriptCoverage coverageOf(EditorSession s, {String? clipId}) =>
    transcriptCoverage(s.project, s.transcriptOf, clipId: clipId);

/// The language most of the transcribed speech is in ('' unknown).
String speechLanguageOf(EditorSession s) {
  final count = <String, int>{};
  for (final t in s.transcripts.value.values) {
    if (t.language.isEmpty) continue;
    count[t.language] = (count[t.language] ?? 0) + t.wordCount + 1;
  }
  if (count.isEmpty) return '';
  return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .first
      .key;
}

/// "Transcribe speech…": for [clip]'s sound, or for the whole project.
/// Returns true when a transcript was made.
Future<bool> showTranscribeDialog(BuildContext context, EditorSession s,
    {Clip? clip}) async {
  if (s.speech == null) return false;
  s.playback.pause();
  final made = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TranscribeDialog(session: s, clipId: clip?.id),
  );
  if (made == true && context.mounted) {
    final words =
        s.transcripts.value.values.fold<int>(0, (n, t) => n + t.wordCount);
    _say(context, 'Speech transcribed: $words words. Read it in the Text window.');
  }
  return made == true;
}

const _languages = ['auto', 'en', 'ru', 'he', 'other'];

/// How much plays before and after a filler in its preview (ms).
const int kFillerPreviewLeadMs = 1500;

class _TranscribeDialog extends StatefulWidget {
  const _TranscribeDialog({required this.session, this.clipId});
  final EditorSession session;
  final String? clipId;

  @override
  State<_TranscribeDialog> createState() => _TranscribeDialogState();
}

class _TranscribeDialogState extends State<_TranscribeDialog> {
  String _choice = 'auto';
  final _code = TextEditingController();
  SpeechQuality _size = SpeechQuality.auto;
  SpeechPlan? _plan;
  bool _checking = true;
  String? _error;

  /// A pack being downloaded.
  SpeechModel? _downloading;
  SpeechTask<void>? _download;
  SpeechProgress? _downloadProgress;

  /// Speech being transcribed.
  SpeechTask<Transcript>? _task;
  SpeechProgress? _progress;
  int _fileIndex = 0;
  int _fileCount = 0;
  bool _made = false;
  bool _stopping = false;

  SpeechService get _speech => widget.session.speech!;

  String get _language {
    if (_choice != 'other') return _choice;
    final c = _code.text.trim().toLowerCase();
    return RegExp(r'^[a-z]{2,3}$').hasMatch(c) ? c : 'auto';
  }

  List<SpeechSource> get _sources =>
      speechSourcesOfProject(widget.session.project, clipId: widget.clipId);

  @override
  void initState() {
    super.initState();
    // A language already heard in this project is the likely one.
    final known = speechLanguageOf(widget.session);
    if (known.isNotEmpty) {
      _choice = _languages.contains(known) ? known : 'other';
      if (_choice == 'other') _code.text = known;
    }
    _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    _download?.cancel();
    _task?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    try {
      final plan = await _speech.plan(language: _language, quality: _size);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Could not check this computer: $e';
      });
    }
  }

  void _startDownload(SpeechModel m) {
    final task = _speech.downloadPack(m);
    setState(() {
      _error = null;
      _downloading = m;
      _download = task;
      _downloadProgress = null;
    });
    task.progress.listen((pr) {
      if (mounted) setState(() => _downloadProgress = pr);
    });
    task.done.then((_) {
      if (!mounted) return;
      setState(() {
        _downloading = null;
        _download = null;
        _size = m.size;
      });
      _refresh();
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _downloading = null;
        _download = null;
        if (!(e is SpeechException && e.cancelled)) {
          _error = e is SpeechException ? e.message : '$e';
        }
      });
    });
  }

  /// "Use it anyway" for a pack that was downloaded but failed its check.
  Future<void> _useAnyway(SpeechModel m) async {
    final ok = await _speech.usePackAnyway(m);
    if (!mounted) return;
    setState(() {
      _error = ok ? null : 'That download is not there any more.';
      if (ok) _size = m.size;
    });
    await _refresh();
  }

  Future<void> _remove(SpeechModel m) async {
    await _speech.removePack(m);
    if (!mounted) return;
    if (_size == m.size) _size = SpeechQuality.auto;
    await _refresh();
  }

  Future<void> _chooseFile() async {
    final file = await widget.session.documents.pickFile(const ['bin']);
    if (file == null || !mounted) return;
    await _speech.useModelFile(file.path);
    if (mounted) await _refresh();
  }

  Future<void> _transcribe() async {
    final s = widget.session;
    final sources = _sources;
    final language = _language;
    // Sounds that have a transcript in this language are left alone
    // unless every one has (then it is "again").
    bool has(SpeechSource x) {
      final t = s.transcriptOf(x.path, x.audioTrack);
      return t != null && t.requestedLanguage == language;
    }

    final todo = sources.every(has)
        ? sources
        : [
            for (final x in sources)
              if (!has(x)) x,
          ];
    setState(() {
      _error = null;
      _fileCount = todo.length;
      _fileIndex = 0;
      _stopping = false;
    });
    for (final source in todo) {
      final task =
          _speech.transcribe(s.project.id, source, language: language, quality: _size);
      setState(() {
        _task = task;
        _progress = null;
      });
      final sub = task.progress.listen((pr) {
        if (mounted) setState(() => _progress = pr);
      });
      try {
        final t = await task.done;
        if (s.isDisposed) return;
        s.transcripts.value = {...s.transcripts.value, source.key: t};
        _made = true;
      } catch (e) {
        unawaited(sub.cancel());
        if (!mounted) return;
        setState(() {
          _task = null;
          if (!(e is SpeechException && e.cancelled)) {
            _error = e is SpeechException ? e.message : '$e';
          }
        });
        return;
      }
      unawaited(sub.cancel());
      if (!mounted) return;
      setState(() => _fileIndex++);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _packRow(PackRow row) {
    final m = row.model;
    final installed = row.installed != null;
    final busy = _downloading?.id == m.id;
    final pr = _downloadProgress;
    return Padding(
      key: ValueKey('pack-${row.size.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            key: ValueKey('pack-use-${row.size.name}'),
            tooltip: installed ? 'Use this pack' : 'Download it first',
            icon: Icon(
              _effectiveSize == row.size
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: _effectiveSize == row.size ? AppColors.accent : null,
            ),
            onPressed: installed && _task == null
                ? () {
                    setState(() => _size = row.size);
                    _refresh();
                  }
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row.size.label} · ${m.sizeLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '${row.size.note} · '
                    '${m.englishOnly ? 'English only' : 'all languages, shared'}',
                    style: _dim),
                if (busy) ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                      value: pr == null || pr.fraction <= 0 ? null : pr.fraction),
                  Text(pr?.message ?? 'Starting…', style: _dim),
                ],
                if (!busy && !installed && _speech.packCheckFailed(m)) ...[
                  const SizedBox(height: 4),
                  Text(
                      'Downloaded, but it is not the file ClipForge expected '
                      '(the model may have been updated since). It is not '
                      'used unless you say so.',
                      style: _dim),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        key: ValueKey('pack-use-anyway-${row.size.name}'),
                        onPressed: _task == null && _downloading == null
                            ? () => _useAnyway(m)
                            : null,
                        child: const Text('Use it anyway'),
                      ),
                      TextButton(
                        key: ValueKey('pack-discard-${row.size.name}'),
                        onPressed: _task == null && _downloading == null
                            ? () => _remove(m)
                            : null,
                        child: const Text('Remove it'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            TextButton(
              onPressed: () => _download?.cancel(),
              child: const Text('Stop'),
            )
          else if (installed)
            TextButton(
              key: ValueKey('pack-remove-${row.size.name}'),
              onPressed: _task == null && _downloading == null
                  ? () => _remove(m)
                  : null,
              child: const Text('Remove'),
            )
          else
            OutlinedButton(
              key: ValueKey('pack-download-${row.size.name}'),
              onPressed: _task == null && _downloading == null
                  ? () => _startDownload(m)
                  : null,
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  /// The size that will be used: the chosen one, else the largest that is
  /// on the computer.
  SpeechQuality? get _effectiveSize {
    if (_size != SpeechQuality.auto) return _size;
    final rows = _speech.packs(_language);
    for (final r in rows.reversed) {
      if (r.installed != null) return r.size;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final plan = _plan;
    final sources = _sources;
    final running = _task != null;
    final language = _language;
    final done = sources
        .where((x) => s.transcriptOf(x.path, x.audioTrack) != null)
        .length;
    final rows = _speech.packs(language);
    final note = kLanguagePacks.where((l) => l.language == language).firstOrNull;
    final what = sources.length == 1
        ? 'The sound of ${p.basename(sources.single.path)}'
            '${sources.single.speaker.isEmpty ? '' : ' (${sources.single.speaker})'}'
        : '${sources.length} recordings'
            '${sources.any((x) => x.isVoice) ? ' (one per speaker: ${sources.where((x) => x.speaker.isNotEmpty).map((x) => x.speaker).toSet().join(', ')})' : ''}';
    return AlertDialog(
      key: const ValueKey('transcribe-dialog'),
      title: Row(
        children: [
          const Expanded(child: Text('Transcribe speech')),
          const HelpHint('transcribe-speech', label: 'Transcribe speech'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turns what is said into text, on this computer. It is used '
                'for captions, for removing filler words and for the '
                'transcript.',
                style: _dim,
              ),
              const SizedBox(height: 10),
              Text(
                  '$what'
                  '${done == 0 ? '' : done == sources.length ? ' · already transcribed' : ' · $done already transcribed'}',
                  key: const ValueKey('transcribe-what')),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Language'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    key: const ValueKey('transcribe-language'),
                    value: _choice,
                    onChanged: running
                        ? null
                        : (v) {
                            setState(() {
                              _choice = v!;
                              _size = SpeechQuality.auto;
                            });
                            _refresh();
                          },
                    items: [
                      for (final l in _languages)
                        DropdownMenuItem(
                          value: l,
                          child: Text(l == 'other' ? 'Other…' : languageName(l)),
                        ),
                    ],
                  ),
                  if (_choice == 'other') ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        key: const ValueKey('transcribe-code'),
                        controller: _code,
                        enabled: !running,
                        decoration: const InputDecoration(
                            isDense: true, hintText: 'code: es'),
                        onChanged: (_) => _refresh(),
                      ),
                    ),
                  ],
                ],
              ),
              if (_choice == 'auto')
                const Text(
                    'Choosing the language is more reliable than Automatic.',
                    style: _dim),
              const SizedBox(height: 8),
              if (plan == null && _checking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Looking at what this computer has…'),
                )
              else if (plan?.problem != null)
                Container(
                  key: const ValueKey('transcribe-nothing'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.panelHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(plan!.problem!),
                )
              else if (plan != null) ...[
                Text('Uses: ${plan.backend!.label}',
                    key: const ValueKey('transcribe-program')),
                if (!plan.backend!.measuresWords)
                  const Text(
                      'This program times whole phrases, not single words: '
                      'fine for captions and the transcript; filler words '
                      'cannot be cut precisely with it.',
                      style: _dim),
                const SizedBox(height: 10),
                if (plan.backend!.usesPacks) ...[
                  const Text('Language pack',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Text(
                      'Nothing is downloaded until you press Download. A '
                      'pack is fetched once and can be removed again.',
                      style: _dim),
                  for (final row in rows) _packRow(row),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note.note, style: _dim),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            _speech.packsBytes == 0
                                ? 'No packs on this computer yet.'
                                : 'Packs use ${bytesLabel(_speech.packsBytes)} '
                                    'on this computer.',
                            key: const ValueKey('packs-used'),
                            style: _dim),
                      ),
                      TextButton(
                        onPressed: running ? null : _chooseFile,
                        child: const Text('Use a model file I have…'),
                      ),
                    ],
                  ),
                  if (_speech.modelFile != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Your own file: ${p.basename(_speech.modelFile!)}',
                              style: _dim),
                        ),
                        TextButton(
                          onPressed: running
                              ? null
                              : () async {
                                  await _speech.useModelFile(null);
                                  if (mounted) await _refresh();
                                },
                          child: const Text('Forget it'),
                        ),
                      ],
                    ),
                ] else if (plan.programFetchesModel || plan.needsChoice)
                  Text(
                      '${plan.backend!.label} keeps its own models and does '
                      'not have one for this yet. Run it once yourself so '
                      'that it fetches its model, or install FFmpeg 8 or '
                      'whisper.cpp to use ClipForge\'s small language packs.',
                      key: const ValueKey('transcribe-own-models'))
                else
                  Text('It uses its own model "${plan.modelName}", which is '
                      'already on this computer: nothing to download.',
                      style: _dim),
              ],
              if (running) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                    key: const ValueKey('transcribe-progress'),
                    value: _progress == null ||
                            _progress!.phase != SpeechPhase.transcribing ||
                            _progress!.fraction <= 0
                        ? null
                        : _progress!.fraction),
                const SizedBox(height: 4),
                Text(
                    '${_fileCount > 1 ? 'Recording ${_fileIndex + 1} of $_fileCount · ' : ''}'
                    '${_progress?.message ?? 'Getting ready…'}',
                    style: _dim),
                const Text(
                    'A long recording takes a while. You can stop at any '
                    'time.',
                    style: _dim),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    key: const ValueKey('transcribe-error'),
                    style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _stopping
              ? null
              : () async {
                  if (running) {
                    setState(() => _stopping = true);
                    await _task?.cancel();
                    if (context.mounted) Navigator.of(context).pop(_made);
                  } else {
                    Navigator.of(context).pop(_made);
                  }
                },
          child: Text(running ? 'Stop' : 'Close'),
        ),
        FilledButton(
          key: const ValueKey('transcribe-go'),
          onPressed: !running &&
                  _downloading == null &&
                  plan != null &&
                  plan.ready &&
                  sources.isNotEmpty
              ? _transcribe
              : null,
          child: Text(done == sources.length && done > 0
              ? 'Transcribe again'
              : 'Transcribe'),
        ),
      ],
    );
  }
}

/// A dialog that says the speech has to be transcribed first, with the
/// button to do it. Returns true when a transcript is there afterwards.
Future<bool> _needTranscript(BuildContext context, EditorSession s, String what) async {
  if (!coverageOf(s).none) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const ValueKey('speech-needed'),
      title: Text(what),
      content: const SizedBox(
        width: 380,
        child: Text('This works from the words that are said, so the speech '
            'has to be transcribed first.'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Transcribe speech…')),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await showTranscribeDialog(context, s);
  return !coverageOf(s).none;
}

/// "Captions from speech": caption items from the transcript, in the
/// current caption style, as one undo step.
Future<void> captionsFromSpeech(BuildContext context, EditorSession s) async {
  if (s.speech == null) return;
  s.playback.pause();
  if (!await _needTranscript(context, s, 'Captions from speech')) return;
  if (!context.mounted) return;
  final added = await showDialog<int>(
    context: context,
    builder: (_) => _CaptionsDialog(session: s),
  );
  if (added != null && added > 0 && context.mounted) {
    _say(context,
        'Added $added ${added == 1 ? 'caption' : 'captions'} from the speech. Undo takes them away.');
  }
}

class _CaptionsDialog extends StatefulWidget {
  const _CaptionsDialog({required this.session});
  final EditorSession session;

  @override
  State<_CaptionsDialog> createState() => _CaptionsDialogState();
}

class _CaptionsDialogState extends State<_CaptionsDialog> {
  int _lines = 2;
  double _chars = 37;
  bool _replace = true;

  List<CaptionCue> _cues(Project project, TitleOverlay template) {
    final s = widget.session;
    return buildCaptions(
      timelineWords(project, s.transcriptOf),
      options: CaptionOptions(maxLineChars: _chars.round(), maxLines: _lines),
      skip: isFillerSound(fillersFor(speechLanguageOf(s))),
      lineFits: captionLineFits(project, template),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final project = s.project;
    final template = captionTemplate(project);
    final cues = _cues(project, template);
    final existing = captionsInRange(project);
    final cover = coverageOf(s);
    return AlertDialog(
      key: const ValueKey('speech-captions-dialog'),
      title: Row(
        children: [
          const Expanded(child: Text('Captions from speech')),
          const HelpHint('captions-from-speech', label: 'Captions from speech'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  cues.isEmpty
                      ? 'No speech was found in the video as it is cut now.'
                      : 'This adds ${cues.length} '
                          '${cues.length == 1 ? 'caption' : 'captions'}, in '
                          'the look your captions have. Each follows its '
                          'picture when you cut.',
                  key: const ValueKey('speech-captions-count')),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Lines'),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                    ],
                    selected: {_lines},
                    onSelectionChanged: (v) => setState(() => _lines = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Longest line: ${_chars.round()} letters'),
              Slider(
                value: _chars,
                min: 32,
                max: 42,
                divisions: 10,
                onChanged: (v) => setState(() => _chars = v),
              ),
              if (cues.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.panelHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cues.take(3).map((c) => c.text).join('\n—\n'),
                    key: const ValueKey('speech-captions-preview'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              if (existing.isNotEmpty)
                CheckboxListTile(
                  key: const ValueKey('speech-captions-replace'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _replace,
                  onChanged: (v) => setState(() => _replace = v ?? true),
                  title: Text('Replace the ${existing.length} '
                      '${existing.length == 1 ? 'caption' : 'captions'} that '
                      '${existing.length == 1 ? 'is' : 'are'} already there'),
                ),
              if (!cover.complete && cover.missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '${cover.missing.length} of ${cover.sources.length} '
                      'recordings are not transcribed yet and get no '
                      'captions.',
                      style: _dim),
                ),
              const SizedBox(height: 6),
              const Text(
                  'Read them through afterwards: speech recognition makes '
                  'mistakes, especially with names.',
                  style: _dim),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('speech-captions-add'),
          onPressed: cues.isEmpty
              ? null
              : () {
                  addSpeechCaptions(
                      s.editor.editor,
                      captionTitles(cues, template, newId: _uuid.v4),
                      replaceIds: _replace
                          ? [for (final t in existing) t.id]
                          : const []);
                  Navigator.of(context).pop(cues.length);
                },
          child: const Text('Add captions'),
        ),
      ],
    );
  }
}

/// "Remove filler words": a list to review, then the cuts in one undo
/// step.
Future<void> removeFillerWords(BuildContext context, EditorSession s) async {
  if (s.speech == null) return;
  s.playback.pause();
  if (!await _needTranscript(context, s, 'Remove filler words')) return;
  if (!context.mounted) return;
  final removed = await showDialog<int>(
    context: context,
    builder: (_) => _FillersDialog(session: s),
  );
  if (removed != null && removed > 0 && context.mounted) {
    _say(context,
        'Removed $removed filler ${removed == 1 ? 'word' : 'words'}. Undo brings them back.');
  }
}

class _FillersDialog extends StatefulWidget {
  const _FillersDialog({required this.session});
  final EditorSession session;

  @override
  State<_FillersDialog> createState() => _FillersDialogState();
}

class _FillersDialogState extends State<_FillersDialog> {
  late String _language;
  final _extra = TextEditingController();
  CutStrength _strength = CutStrength.light;

  /// Fillers the user ticked or unticked, by clip and place (the others
  /// follow the strength).
  final Map<String, bool> _picked = {};

  /// Jump scores by the same key; filled in the background.
  final Map<String, double> _jumps = {};
  bool _checkingJumps = false;
  Timer? _stopPlay;

  static String _keyOf(FillerHit h) => '${h.clipId}|${h.cutStartMs}|${h.entry}';

  @override
  void initState() {
    super.initState();
    _language = speechLanguageOf(widget.session);
    _checkJumps();
  }

  @override
  void dispose() {
    _stopPlay?.cancel();
    _extra.dispose();
    super.dispose();
  }

  FillerList get _list {
    final base = fillersFor(_language);
    final extra = [
      for (final e in _extra.text.split(','))
        if (e.trim().isNotEmpty) e.trim(),
    ];
    return base.copyWith(sounds: [...base.sounds, ...extra]);
  }

  List<FillerHit> _hits() {
    final s = widget.session;
    return findFillers(timelineWords(s.project, s.transcriptOf), _list);
  }

  /// Compares the picture before and after every cut (when the engine
  /// can): the "smooth / slight / jumpy" rating.
  Future<void> _checkJumps() async {
    final s = widget.session;
    final engine = s.engine;
    if (engine is! JumpCheckEngine) return;
    final hits = _hits();
    final pathOf = {for (final c in s.project.clips) c.id: c.path};
    final byPath = <String, List<FillerHit>>{};
    for (final h in hits) {
      if (_jumps.containsKey(_keyOf(h))) continue;
      // Under a full-frame overlay nothing of the cut is seen.
      final over = s.project.overlayAt(h.startMs);
      if (over != null && over.layout == OverlayLayout.full) {
        _jumps[_keyOf(h)] = 0;
        continue;
      }
      final path = pathOf[h.clipId];
      if (path != null) (byPath[path] ??= []).add(h);
    }
    if (byPath.isEmpty) return;
    setState(() => _checkingJumps = true);
    for (final e in byPath.entries) {
      try {
        final scores = await (engine as JumpCheckEngine).jumpScores(e.key, [
          for (final h in e.value)
            (beforeMs: h.cutStartMs - 40, afterMs: h.cutEndMs + 10),
        ]);
        for (var i = 0; i < e.value.length; i++) {
          final v = scores[i];
          if (v != null) _jumps[_keyOf(e.value[i])] = v;
        }
      } catch (_) {
        // Not measured: shown without a rating.
      }
    }
    if (mounted) setState(() => _checkingJumps = false);
  }

  /// Previews the cut APPLIED: plays from about 1.5 s before the part
  /// that would be removed, jumps over it, and plays about 1.5 s after it,
  /// so the join can be judged by ear and eye before anything is cut.
  void _play(FillerHit h) {
    final s = widget.session;
    final playback = s.playback;
    _stopPlay?.cancel();
    playback.pause();
    final project = s.project;
    final i = h.clipIndex;
    if (i < 0 || i >= project.clips.length || project.clips[i].id != h.clipId) {
      return;
    }
    final clip = project.clips[i];
    final base = project.clipStartMs(i);
    int onTimeline(int sourceMs) =>
        base + ((sourceMs - clip.inMs) / clip.speed).round();
    final cutFrom = onTimeline(h.cutStartMs), cutTo = onTimeline(h.cutEndMs);
    final from = cutFrom - kFillerPreviewLeadMs < 0 ? 0 : cutFrom - kFillerPreviewLeadMs;
    final until = cutTo + kFillerPreviewLeadMs > project.durationMs
        ? project.durationMs
        : cutTo + kFillerPreviewLeadMs;
    playback.seek(from);
    playback.play();
    var jumped = false;
    // Never longer than the stretch itself plus a few seconds (a player
    // that is still loading).
    final limitMs = (until - from) + 6000;
    _stopPlay = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      final at = playback.positionMs;
      if (!jumped && at >= cutFrom - 20 && at < cutTo) {
        jumped = true;
        playback.seek(cutTo);
        playback.play();
      } else if ((jumped && at >= until - 20) || timer.tick * 30 > limitMs) {
        timer.cancel();
        playback.pause();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final all = _hits();
    final estimated = all.any((h) => h.estimated);
    final viaFilter =
        s.transcripts.value.values.any((t) => t.backend == FfmpegWhisperBackend.kId);
    // The strength decides among the hesitation sounds; filler WORDS are
    // listed but never ticked for the user.
    final sounds = [
      for (final h in all)
        if (h.isSound) h,
    ];
    final plan = planFillerCuts(s.project, sounds, CutRules.of(_strength), jumps: {
      for (var i = 0; i < sounds.length; i++)
        if (_jumps[_keyOf(sounds[i])] != null) i: _jumps[_keyOf(sounds[i])]!,
    });
    final planned = {for (final c in plan) _keyOf(c.hit): c};
    bool on(FillerHit h) =>
        _picked[_keyOf(h)] ??
        (!estimated && !h.overlapsSpeech && (planned[_keyOf(h)]?.isCut ?? false));
    final chosen = [
      for (final h in all)
        if (on(h) && !h.overlapsSpeech) h,
    ];
    final total = chosen.fold<int>(0, (n, h) => n + h.cutMs);
    final perMinute = s.project.durationMs <= 0
        ? 0.0
        : chosen.length / (s.project.durationMs / 60000);
    final jumpyLeft =
        plan.where((c) => c.decision == CutDecision.jumpy).length;

    Widget rating(FillerHit h) {
      final r = jumpRatingOf(_jumps[_keyOf(h)]);
      if (r.isEmpty) return const SizedBox(width: 52);
      final color = switch (r) {
        'jumpy' => AppColors.danger,
        'slight' => const Color(0xFFE0B050),
        _ => AppColors.textDim,
      };
      return SizedBox(
        width: 52,
        child: Text(r, style: TextStyle(fontSize: 12, color: color)),
      );
    }

    return AlertDialog(
      key: const ValueKey('fillers-dialog'),
      title: Row(
        children: [
          const Expanded(child: Text('Remove filler words')),
          const HelpHint('remove-filler-words', label: 'Remove filler words'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Fillers of'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    key: const ValueKey('fillers-language'),
                    value: kDefaultFillers.containsKey(_language) ? _language : '',
                    onChanged: (v) {
                      setState(() {
                        _language = v!;
                        _picked.clear();
                      });
                      _checkJumps();
                    },
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Any language')),
                      for (final l in kDefaultFillers.keys)
                        DropdownMenuItem(value: l, child: Text(languageName(l))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Select'),
                  const SizedBox(width: 12),
                  SegmentedButton<CutStrength>(
                    key: const ValueKey('fillers-strength'),
                    showSelectedIcon: false,
                    segments: [
                      for (final v in CutStrength.values)
                        ButtonSegment(value: v, label: Text(v.label)),
                    ],
                    selected: {_strength},
                    onSelectionChanged: (v) => setState(() {
                      _strength = v.first;
                      _picked.clear();
                    }),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                    switch (_strength) {
                      CutStrength.light =>
                        'Light: only clear fillers that stand alone between '
                            'pauses, well apart. The video stays calm.',
                      CutStrength.normal =>
                        'Normal: shorter ones too, still kept apart.',
                      CutStrength.strong =>
                        'Strong: every one that was found. Can look jumpy '
                            'when the speaker is seen; fine for sound only.',
                    },
                    style: _dim),
              ),
              Text(
                  all.isEmpty
                      ? 'No filler words were found in the transcript.'
                      : '${chosen.length} of ${all.length} selected · saves '
                          '${formatDuration(total)}'
                          '${total < 1000 && total > 0 ? ' (${formatLength(total)})' : ''} · '
                          '${chosen.isEmpty ? 'no cuts' : perMinute < 0.75 ? 'less than 1 cut per minute' : 'about ${perMinute.round()} ${perMinute.round() == 1 ? 'cut' : 'cuts'} per minute'}',
                  key: ValueKey(all.isEmpty ? 'fillers-none' : 'fillers-total'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_checkingJumps)
                const Text('Checking the picture around each cut…', style: _dim)
              else if (jumpyLeft > 0)
                Text(
                    '$jumpyLeft ${jumpyLeft == 1 ? 'is' : 'are'} left in '
                    'because the picture would jump there.',
                    key: const ValueKey('fillers-jumpy-left'),
                    style: _dim),
              if (all.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    key: const ValueKey('fillers-list'),
                    shrinkWrap: true,
                    itemCount: all.length,
                    itemBuilder: (context, i) {
                      final h = all[i];
                      return Row(
                        key: ValueKey('filler-row-$i'),
                        children: [
                          Checkbox(
                            key: ValueKey('filler-$i'),
                            value: on(h),
                            onChanged: h.overlapsSpeech
                                ? null
                                : (v) => setState(
                                    () => _picked[_keyOf(h)] = v ?? false),
                          ),
                          SizedBox(
                            width: 46,
                            child: Text(formatDuration(h.startMs),
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.accent)),
                          ),
                          Expanded(
                            child: Text(
                              '“${h.text}”'
                              '${h.isSound ? '' : ' · also a real word'}'
                              '${h.overlapsSpeech ? ' · someone else is talking' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 46,
                            child: Text(formatLength(h.cutMs),
                                style: const TextStyle(fontSize: 12)),
                          ),
                          rating(h),
                          IconButton(
                            tooltip: 'Play it as it would be after the cut',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            onPressed: () => _play(h),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('fillers-extra'),
                controller: _extra,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Also look for (separate with commas)',
                ),
                onChanged: (_) {
                  setState(() {});
                  _checkJumps();
                },
              ),
              if (estimated)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      'The times of single words are only estimated in this '
                      'transcript, so a cut can clip the word next to it. '
                      'Nothing is ticked for you: tick what you want and '
                      'listen to the result.',
                      key: ValueKey('fillers-estimated'),
                      style: TextStyle(color: AppColors.danger, fontSize: 12)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    viaFilter
                        ? 'This transcript was made by FFmpeg\'s speech '
                            'filter, which usually leaves "um" and "uh" out '
                            'of the text, so few are found. whisper.cpp '
                            '(whisper-cli) or faster-whisper keep more of '
                            'them and time every word; with one installed, '
                            'transcribe again.'
                        : 'Speech programs often leave "um" and "uh" out of '
                            'the text, so there can be more in the sound '
                            'than are listed. Every cut can be put back '
                            'later (Automatic cuts).',
                    key: ValueKey(
                        viaFilter ? 'fillers-filter-note' : 'fillers-note'),
                    style: _dim),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('fillers-remove'),
          onPressed: chosen.isEmpty
              ? null
              : () {
                  _stopPlay?.cancel();
                  s.playback.pause();
                  applyPlannedCuts(
                      s.editor.editor,
                      [
                        for (final h in chosen)
                          PlannedCut(h, CutDecision.cut,
                              jump: _jumps[_keyOf(h)],
                              smooth: (_jumps[_keyOf(h)] ?? 0) >= kJumpSlight),
                      ],
                      newId: _uuid.v4);
                  Navigator.of(context).pop(chosen.length);
                },
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

/// "Automatic cuts": what Remove filler words and Remove silences took
/// out, with "Put back" for each and for all.
Future<void> showAutoCuts(BuildContext context, EditorSession s) {
  s.playback.pause();
  return showDialog<void>(
    context: context,
    builder: (_) => _AutoCutsDialog(session: s),
  );
}

class _AutoCutsDialog extends StatelessWidget {
  const _AutoCutsDialog({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.editor,
      builder: (context, _) {
        final project = session.project;
        final cuts = [...project.autoCuts]..sort((a, b) {
            final d = a.path.compareTo(b.path);
            return d != 0 ? d : a.startMs.compareTo(b.startMs);
          });
        final totals = autoCutTotals(project);
        return AlertDialog(
          key: const ValueKey('auto-cuts-dialog'),
          title: const Text('Automatic cuts'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    cuts.isEmpty
                        ? 'Nothing was cut automatically in this project '
                            '(or everything was put back).'
                        : '${totals.count} ${totals.count == 1 ? 'cut' : 'cuts'} · '
                            '${formatLength(totals.savedMs)} removed · '
                            '${totals.perMinute < 0.75 ? 'less than 1' : 'about ${totals.perMinute.round()}'} '
                            'per minute',
                    key: const ValueKey('auto-cuts-summary'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text(
                    'What Remove filler words, Remove silences and "Cut this '
                    'part out" (Text window) took out. '
                    'Put back returns a piece to the video.',
                    style: _dim),
                if (cuts.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      key: const ValueKey('auto-cuts-list'),
                      shrinkWrap: true,
                      itemCount: cuts.length,
                      itemBuilder: (context, i) {
                        final c = cuts[i];
                        final r = jumpRatingOf(c.jump);
                        return Row(
                          key: ValueKey('auto-cut-$i'),
                          children: [
                            Icon(
                                c.kind == 'filler'
                                    ? Icons.record_voice_over_outlined
                                    : Icons.content_cut,
                                size: 16,
                                color: AppColors.textDim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${c.kind == 'filler' ? '“${c.word}”' : c.kind == 'text' ? 'Cut from the text${c.word.isEmpty ? '' : ' “${c.word}”'}' : 'Silence'} · '
                                '${p.basename(c.path)} at ${formatDuration(c.startMs)} · '
                                '${formatLength(c.lengthMs)}'
                                '${r.isEmpty ? '' : ' · $r'}'
                                '${c.smoothed ? ' · dissolve' : ''}'
                                '${c.by == 'claude' ? ' · by Claude' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            TextButton(
                              key: ValueKey('auto-cut-back-$i'),
                              onPressed: () => restoreAutoCut(
                                  session.editor.editor, c.id,
                                  newId: _uuid.v4),
                              child: const Text('Put back'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (cuts.isNotEmpty)
              TextButton(
                key: const ValueKey('auto-cuts-all'),
                onPressed: () => restoreAllAutoCuts(session.editor.editor,
                    newId: _uuid.v4),
                child: const Text('Put back all'),
              ),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close')),
          ],
        );
      },
    );
  }
}
