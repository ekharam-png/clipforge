import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/editor/edit_labels.dart' show aspectName;
import '../../core/model/project.dart' hide Clip;
import '../../core/music/openverse.dart' show creditsText;
import '../../core/publish/chapters.dart';
import '../../media/destinations.dart';
import '../../media/export_estimate.dart';
import '../../media/export_kit.dart';
import '../../media/media_api.dart';
import '../../media/video_encoder.dart' show encoderDescription, encoderLabel;
import '../../core/publish/shorts.dart' show kShortMaxSeconds;
import '../app_settings.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../long_jobs.dart';
import '../publish_service.dart';
import '../services.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'clip_panels.dart' show ChoiceRow;
import 'long_project_note.dart' show kLongProjectMs;
import 'publishing_panel.dart';
import 'session.dart';

Future<void> showExportDialog(
  BuildContext context, {
  required Project project,
  required MediaEngine engine,
  required FileService files,
  JobTracker? jobs,
  Map<String, String> Function()? processedSound,
  ValueChanged<VideoSize>? onVideoSize,
  DocumentService? documents,
  PublishService? publish,
  ValueChanged<PublishingNotes>? onNotes,
  Future<Project?> Function(Project variant, String name)? onKeepCopy,
  SpeakerTurns Function()? turns,
  bool several = false,
  AppSettings? settings,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExportDialog(
        project: project,
        engine: engine,
        files: files,
        jobs: jobs,
        processedSound: processedSound,
        onVideoSize: onVideoSize,
        documents: documents,
        publish: publish,
        onNotes: onNotes,
        onKeepCopy: onKeepCopy,
        turns: turns,
        several: several,
        settings: settings),
  );
}

/// Shown instead of the export dialog while media files are gone: says
/// which, and lets each be pointed at again. Completes with true once
/// nothing is missing any more and the user wants to go on.
Future<bool> showMissingMediaDialog(
  BuildContext context, {
  required EditorSession session,
  required Future<List<String>> Function(Project project) check,
  required List<String> missing,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _MissingMediaDialog(session: session, check: check, missing: missing),
  );
  return ok ?? false;
}

class _MissingMediaDialog extends StatefulWidget {
  const _MissingMediaDialog({
    required this.session,
    required this.check,
    required this.missing,
  });
  final EditorSession session;
  final Future<List<String>> Function(Project project) check;
  final List<String> missing;

  @override
  State<_MissingMediaDialog> createState() => _MissingMediaDialogState();
}

class _MissingMediaDialogState extends State<_MissingMediaDialog> {
  late List<String> _missing = widget.missing;

  Future<void> _find(String path) async {
    final s = widget.session;
    final isSound = s.project.audio.any((a) => a.path == path) &&
        !s.project.clips.any((c) => c.path == path);
    await findMissingFile(context, s, path, audio: isSound);
    List<String> now;
    try {
      now = await widget.check(s.project);
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _missing = now);
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(missing.isEmpty
          ? 'All files are back'
          : missing.length == 1
              ? 'A file is missing'
              : '${missing.length} files are missing'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(missing.isEmpty
                    ? 'The video can be exported now.'
                    : 'The video cannot be exported without '
                        '${missing.length == 1 ? 'it' : 'them'}. Put '
                        '${missing.length == 1 ? 'the file' : 'the files'} '
                        'back, show where '
                        '${missing.length == 1 ? 'it is' : 'they are'} now, or '
                        'delete what uses '
                        '${missing.length == 1 ? 'it' : 'them'} from the '
                        'timeline.'),
                for (final path in missing)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fileName(path), style: text.titleSmall),
                              Text(
                                path,
                                style: text.bodySmall
                                    ?.copyWith(color: AppColors.textDim),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _find(path),
                          child: const Text('Find file…'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(missing.isEmpty ? 'Cancel' : 'Close'),
        ),
        if (missing.isEmpty)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
      ],
    );
  }
}

enum _Phase { options, running, done, failed }

class ExportDialog extends StatefulWidget {
  const ExportDialog({
    super.key,
    required this.project,
    required this.engine,
    required this.files,
    this.jobs,
    this.processedSound,
    this.onVideoSize,
    this.documents,
    this.publish,
    this.onNotes,
    this.onKeepCopy,
    this.turns,
    this.several = false,
    this.settings,
  });
  final Project project;

  /// The app's settings: "Use graphics card" is remembered there, and the
  /// two notes of this window (first export, long upright video) follow
  /// "Show suggestions". Null (tests): nothing is remembered.
  final AppSettings? settings;

  /// The kit folder, the share sheet, "Show in folder" and the sites'
  /// upload pages (1.14). Null: none of that is offered.
  final PublishService? publish;

  /// Stores changed publishing notes in the project (one undo step); null:
  /// the notes can be read and copied here but not changed.
  final ValueChanged<PublishingNotes>? onNotes;

  /// "Make a copy in this shape": saves [variant] as a new project called
  /// [name] in the project list and returns it. Null: shape copies exist
  /// only for the export.
  final Future<Project?> Function(Project variant, String name)? onKeepCopy;

  /// Who speaks when, for "Chapters from titles / captions…".
  final SpeakerTurns Function()? turns;

  /// Open on "Export several…".
  final bool several;

  /// Phones: hands a finished sound-only file to the share sheet (the
  /// gallery takes videos only). Null: not offered.
  final DocumentService? documents;

  /// Changes the project's video size ([Project.videoSize]); null: the
  /// choice is not offered.
  final ValueChanged<VideoSize>? onVideoSize;
  final MediaEngine engine;
  final FileService files;

  /// Told while an export runs, so that quitting can ask first.
  final JobTracker? jobs;

  /// The clips' ready processed sound files when the export starts
  /// ([ExportOptions.processedSound]); the export reads them instead of
  /// running clean-up and voice focus again.
  final Map<String, String> Function()? processedSound;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late Project _project = widget.project;
  _Phase _phase = _Phase.options;
  ExportQuality _customQuality = ExportQuality.full;
  double _progress = 0;

  /// "Where is it going?": a row of [kDestinations]. Custom = the controls
  /// below, as before 1.14.
  ExportDestination _dest = kCustomDestination;
  CanvasAspect? _destShape;
  ExportFormat? _destFormat;

  /// The destination's shape differs from the project's: export it as it
  /// is instead of making a copy in that shape.
  bool _asIs = false;

  /// "Export several…": the ticked rows, by [KitChoice.key].
  late bool _several = widget.several;
  final Set<String> _ticked = {'youtube', 'shorts'};
  bool _keepCopies = false;

  /// A kit being exported, what it is doing, and what it made.
  KitRun? _kit;
  String _kitNow = '';
  List<KitFile> _kitFiles = const [];
  String? _textPath;

  /// What the finished file(s) were made for (upload pages, short-form
  /// text), and shape copies that were added to the project list.
  List<KitChoice> _made = const [];
  final List<Project> _copies = [];
  String? _copyNote;
  String? _copiedWhat;

  KitChoice get _choice =>
      KitChoice(_dest, shape: _destShape, format: _destFormat);
  ExportQuality get _quality => _dest.custom ? _customQuality : _dest.quality;
  ExportFormat get _format =>
      _dest.custom ? _customFormat : _choice.formatInUse;

  /// The destination wants another shape than the project has.
  bool get _shapeDiffers =>
      !_dest.custom &&
      !_format.audioOnly &&
      shapeDiffers(_project, _choice.shapeInUse);
  PublishingNotes get _notes => _project.publishing;
  ExportJob? _job;
  StreamSubscription<ExportProgress>? _progressSub;
  bool _cancelling = false;
  String? _outputPath;
  String? _error;
  String? _errorLog;
  List<String> _errorMissing = const [];

  /// Video, or the sound only (M4A / MP3).
  ExportFormat _customFormat = ExportFormat.video;

  /// Frames per second chosen: one of [ExportOptions.frameRateChoices], or
  /// null for "Same as the clips" ([_sourceFps]).
  int? _fps = 30;

  /// The frame rates of the project's videos, as their files say.
  final List<double> _sourceRates = [];
  bool _fastSource = false;

  int get _sourceFps => ExportOptions.sameAsSourceFps(_sourceRates);
  int get _exportFps => _fps ?? _sourceFps;

  /// Whether this device has a working hardware video encoder (null while
  /// that is being found out), which one, and whether the user wants it.
  bool? _gpuAvailable;
  VideoEncoder? _gpu;
  bool _useGpu = true;

  /// The encoder that made the finished video, whether the graphics card
  /// was asked for, how long it took, and the sound settings the export
  /// could not apply.
  VideoEncoder? _encoderUsed;
  bool _wantedGpu = false;
  Duration? _took;
  List<String> _warnings = const [];
  /// Phones: where the gallery copy went, or why it did not get there.
  String? _galleryPlace;
  String? _galleryProblem;
  bool _copying = false;

  String get _fileName {
    if (!_dest.custom) return kitFileName(_project.name, _choice);
    if (_format.audioOnly) {
      return '${safeFileName(_project.name)} (sound).${_format.extension}';
    }
    final suffix = _quality == ExportQuality.small ? ' (small)' : '';
    return '${safeFileName(_project.name)}$suffix.mp4';
  }

  @override
  void initState() {
    super.initState();
    _useGpu = widget.settings?.graphicsCard ?? true;
    _lookForFastVideo();
    _lookForGraphicsCard();
    _loadNotes();
  }

  /// The first export on this device: one line next to "Use graphics
  /// card" says what it is.
  bool _firstExport = false;

  /// "This upright video is longer than a short" was closed (for this
  /// project) or turned off.
  bool _longNoteClosed = true;

  static const String _longNoteId = 'long-upright';

  Future<void> _loadNotes() async {
    final settings = widget.settings;
    if (settings == null) return;
    try {
      final prefs = settings.prefs;
      final first = !await prefs.flag(kExportedOnceFlag);
      final closed = await prefs.flag(hintOffFlag(_longNoteId)) ||
          await prefs.flag(hintProjectFlag(_longNoteId, widget.project.id));
      if (!mounted) return;
      setState(() {
        _firstExport = first;
        _longNoteClosed = closed;
      });
    } catch (_) {}
  }

  void _noteExportStarted() {
    widget.settings?.prefs
        .setFlag(kExportedOnceFlag)
        .catchError((Object _) {});
  }

  /// A phone-shaped video that is longer than a short: one line, not a
  /// question in the way.
  bool get _showLongNote {
    if (_longNoteClosed || !(widget.settings?.suggestions ?? false)) {
      return false;
    }
    final canvas = _project.canvasSize;
    return canvas.height > canvas.width &&
        _project.durationMs > kShortMaxSeconds * 1000;
  }

  Widget _longNote(TextTheme text) => Padding(
        key: const ValueKey('export-long-upright-note'),
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 8),
              child: Icon(Icons.lightbulb_outline,
                  size: 16, color: AppColors.textDim),
            ),
            Expanded(
              child: Text(
                'This upright video is ${formatLength(_project.durationMs)} '
                'long. Shorts and Reels work best under '
                '$kShortMaxSeconds seconds: "Make a short from here…" cuts '
                'one out of it.',
                style: text.bodySmall?.copyWith(color: AppColors.textDim),
              ),
            ),
            IconButton(
              key: const ValueKey('export-long-upright-close'),
              tooltip: 'Close this note',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close,
                  size: 16, semanticLabel: 'Close this note'),
              onPressed: () {
                setState(() => _longNoteClosed = true);
                widget.settings?.prefs
                    .setFlag(hintProjectFlag(_longNoteId, widget.project.id))
                    .catchError((Object _) {});
              },
            ),
          ],
        ),
      );

  Widget _firstExportNote(TextTheme text) => Padding(
        key: const ValueKey('export-first-note'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'Your first export: with a graphics card it is usually several '
          'times quicker. The switch is remembered, and is also in '
          'Settings.',
          style: text.bodySmall?.copyWith(color: AppColors.textDim),
        ),
      );

  /// The first time this takes a second or two (a tiny test encode); the
  /// answer is then remembered for the run of the app.
  Future<void> _lookForGraphicsCard() async {
    VideoEncoder? gpu;
    try {
      gpu = await widget.engine.graphicsCardEncoder();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _gpu = gpu;
        _gpuAvailable = gpu != null;
      });
    }
  }

  /// The project does not keep the frame rate of its videos, so they are
  /// asked for it here (quick: only the file headers are read).
  Future<void> _lookForFastVideo() async {
    final paths = {
      for (final c in _project.clips)
        if (c.type == ClipType.video) c.path,
    };
    for (final path in paths) {
      try {
        final info = await widget.engine.probe(path);
        if (!mounted) return;
        if (info.fps.isFinite && info.fps > 0) {
          setState(() {
            _sourceRates.add(info.fps);
            if (info.fps >= ExportOptions.highFrameRateFrom) {
              _fastSource = true;
            }
          });
        }
      } catch (_) {
        // A file that cannot be read has no say here.
      }
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    // Closing the dialog mid-export stops the export.
    if (_phase == _Phase.running) {
      _job?.cancel().catchError((_) {});
      _kit?.cancel();
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (_several) return _startKit();
    final files = widget.files;
    String? path;
    try {
      if (files.canChooseSaveLocation) {
        path = await files.chooseSavePath(_fileName);
        if (path == null) return; // cancelled, stay on the options
        // The save dialog may leave an empty placeholder behind.
        final placeholder = File(path);
        if (placeholder.existsSync() && placeholder.lengthSync() == 0) {
          placeholder.deleteSync();
        }
      } else {
        final stamp = DateTime.now()
            .toIso8601String()
            .substring(0, 19)
            .replaceAll(RegExp('[:T]'), '-');
        final ext = '.${_format.extension}';
        final name = _fileName.replaceFirst(ext, ' $stamp$ext');
        path = await files.appExportPath(name);
      }
    } catch (e) {
      _fail('Could not prepare the place to save the video.', '$e');
      return;
    }
    if (!mounted) return;

    // Off only when the user turned it off; while the check is still
    // running the engine decides by itself.
    final useGpu = _gpuAvailable == false || _useGpu;
    _noteExportStarted();
    final options = ExportOptions(
        quality: _quality,
        fps: _exportFps,
        useHardwareEncoder: useGpu,
        format: _format,
        processedSound: widget.processedSound?.call() ?? const {});
    if (!await _roomFor(path, options) || !mounted) return;
    // A destination: the project in its shape and size. "Make a copy in
    // this shape" adds that copy to the project list (it can then be
    // opened to keep the person in shot with Crop and position); the
    // project itself is never changed by an export.
    var project = _project;
    final choice = _choice;
    _copies.clear();
    _copyNote = null;
    if (!_dest.custom) {
      if (_shapeDiffers && !_asIs) {
        final variant = destinationVariant(_project, choice);
        project = await _keepCopy(variant, choice) ?? variant;
        if (!mounted) return;
      } else {
        project = destinationVariant(_project, choice, keepShape: true);
      }
    }
    _made = _dest.custom ? const [] : [choice];
    _kitFiles = const [];
    _textPath = null;

    RunningJob? tracked;
    var keptAwake = false;
    final clock = Stopwatch()..start();
    _wantedGpu = useGpu && _gpuAvailable != false;
    try {
      final job = widget.engine.export(
        project,
        path,
        options: options,
      );
      setState(() {
        _phase = _Phase.running;
        _progress = 0;
        _cancelling = false;
        _job = job;
      });
      tracked = widget.jobs?.start(JobKind.export, cancel: () async {
        if (mounted) {
          await _cancel();
        } else {
          await job.cancel();
        }
      });
      // A long export must not stop when the screen goes off (or, on a
      // phone, when another app is opened).
      keptAwake = true;
      unawaited(LongJobSupport.instance.exportStarted(
          title: 'Exporting ${_project.name}',
          text: _keepOpenNote));
      _progressSub = job.progress.listen(
        (p) {
          if (mounted) setState(() => _progress = p.fraction.clamp(0.0, 1.0));
        },
        onError: (_) {},
      );
      final output = await job.done;
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _outputPath = output;
        _encoderUsed = job.videoEncoder;
        _took = clock.elapsed;
        _warnings = job.warnings;
      });
      // The notes go next to the video as a text file (computers).
      if (files.canChooseSaveLocation) unawaited(_writeTextNextTo(output));
      // On a phone the finished video belongs in the gallery (a sound file
      // is offered to the share sheet instead, see _done).
      if (!files.canChooseSaveLocation && !_format.audioOnly) {
        unawaited(_saveToGallery());
      }
    } on ExportException catch (e) {
      if (_cancelling) {
        _backToOptions();
      } else {
        _fail(e.message, e.log, missing: e.missingPaths);
      }
    } catch (e) {
      if (_cancelling) {
        _backToOptions();
      } else {
        _fail('The export stopped unexpectedly.', '$e');
      }
    } finally {
      if (keptAwake) unawaited(LongJobSupport.instance.exportEnded());
      if (tracked != null) widget.jobs?.end(tracked);
      await _progressSub?.cancel();
      _progressSub = null;
      _job = null;
    }
  }

  static const _keepOpenNote = 'Keep ClipForge open while it exports.';

  /// Adds [variant] (the project in a destination's shape) to the project
  /// list, when the app can. Returns the saved copy.
  Future<Project?> _keepCopy(Project variant, KitChoice choice) async {
    final keep = widget.onKeepCopy;
    final shape = choice.shapeInUse;
    if (keep == null || shape == null) return null;
    try {
      final made = await keep(
          variant, '${_project.name} - ${KitChoice.shapeTag(shape)}');
      if (made != null) _copies.add(made);
      return made;
    } catch (e) {
      _copyNote = 'The copy could not be added to your projects ($e); the '
          'video was exported in this shape all the same.';
      return null;
    }
  }

  /// "(Project) - text.txt" next to a single exported file, when there
  /// is something to paste (notes, or credits of free music).
  Future<void> _writeTextNextTo(String output) async {
    if (_notes.isEmpty && creditsText(_project).isEmpty) return;
    try {
      final dir = Directory(p.dirname(output));
      if (!dir.existsSync()) return;
      final file = File(p.join(dir.path, kitTextFileName(_project.name)));
      file.writeAsStringSync(
          kitText(_project,
              sections: [
                (
                  heading: _dest.custom ? 'This video' : _choice.label,
                  shortForm: _dest.shortForm,
                  file: p.basename(output),
                ),
              ],
              lineEnd: Platform.isWindows ? '\r\n' : '\n'),
          flush: true);
      if (mounted) setState(() => _textPath = file.path);
    } catch (_) {
      // The notes are on the finished screen as well.
    }
  }

  List<KitChoice> get _tickedChoices => [
        for (final c in kitChoices())
          if (_ticked.contains(c.key)) c,
      ];

  /// "Export several…": every ticked destination, one after another, as
  /// one job into one folder (computers: chosen once; phones: the app's
  /// own folder, videos copied into a gallery album named after the
  /// project).
  Future<void> _startKit() async {
    final choices = _tickedChoices;
    final publish = widget.publish;
    if (choices.isEmpty || publish == null) return;
    final desktop = widget.files.canChooseSaveLocation;
    final useGpu = _gpuAvailable == false || _useGpu;
    _noteExportStarted();
    final plan = planKit(_project, choices,
        fps: _exportFps,
        useHardwareEncoder: useGpu,
        processedSound: widget.processedSound?.call() ?? const {});
    String? folder;
    try {
      folder = desktop
          ? await publish.chooseFolder()
          : await publish.appKitFolder(plan.folderName);
    } catch (e) {
      _fail('Could not prepare the place to save the files.', '$e');
      return;
    }
    if (folder == null || !mounted) return;
    // Room for all of them.
    final free = await LongJobSupport.instance.freeBytes(folder);
    if (!mounted) return;
    if (free != null) {
      var need = 0;
      for (final i in plan.items) {
        need += estimateExportSize(i.project, i.options).typicalBytes;
      }
      if (!desktop) need *= 2;
      if (free < need) {
        _fail(
            'Not enough free space: these files need about '
            '${formatBytes(need)} and ${formatBytes(free)} is free. Free up '
            'some space or tick fewer.',
            null);
        return;
      }
    }
    _copies.clear();
    _copyNote = null;
    if (_keepCopies) {
      final done = <CanvasAspect>{};
      for (final i in plan.items) {
        final shape = i.choice.shapeInUse;
        if (!i.reshaped || shape == null || !done.add(shape)) continue;
        await _keepCopy(i.project, i.choice);
      }
      if (!mounted) return;
    }
    RunningJob? tracked;
    final clock = Stopwatch()..start();
    _wantedGpu = useGpu && _gpuAvailable != false;
    String? album;
    String? albumProblem;
    final run = runExportKit(widget.engine, plan, folder,
        lineEnd: Platform.isWindows ? '\r\n' : '\n',
        onFile: desktop
            ? null
            : (file) async {
                // Phones: the gallery takes videos; sound and text stay
                // in the app's folder and go out through Share.
                if (file.item.options.format.audioOnly) return;
                try {
                  album = await publish.saveToAlbum(file.path, plan.folderName);
                  albumProblem = album == null
                      ? 'The app was not allowed to add the videos to the '
                          'gallery.'
                      : null;
                } catch (e) {
                  albumProblem =
                      'The videos could not be added to the gallery ($e)';
                }
              });
    setState(() {
      _phase = _Phase.running;
      _progress = 0;
      _cancelling = false;
      _kit = run;
      _kitNow = '1 of ${plan.items.length}: ${plan.items.first.label}';
      _made = choices;
    });
    tracked = widget.jobs?.start(JobKind.export, cancel: () async {
      if (mounted) {
        await _cancel();
      } else {
        await run.cancel();
      }
    });
    unawaited(LongJobSupport.instance.exportStarted(
        title: 'Exporting ${_project.name}', text: _keepOpenNote));
    final sub = run.progress.listen((pr) {
      if (!mounted) return;
      setState(() {
        _progress = pr.overall.clamp(0.0, 1.0);
        _kitNow = '${pr.index + 1} of ${pr.count}: ${pr.label}';
      });
    });
    try {
      final result = await run.done;
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _kitFiles = result.files;
        _textPath = result.textPath;
        _outputPath = result.folder;
        _encoderUsed = result.files
            .map((f) => f.encoder)
            .whereType<VideoEncoder>()
            .firstOrNull;
        _took = clock.elapsed;
        _warnings = {
          for (final f in result.files) ...f.warnings,
        }.toList();
        _galleryPlace = album;
        _galleryProblem = albumProblem;
      });
    } on ExportException catch (e) {
      if (_cancelling || e.cancelled) {
        _backToOptions();
      } else {
        _fail(e.message, e.log, missing: e.missingPaths);
      }
    } catch (e) {
      _fail('The export stopped unexpectedly.', '$e');
    } finally {
      unawaited(LongJobSupport.instance.exportEnded());
      if (tracked != null) widget.jobs?.end(tracked);
      unawaited(sub.cancel());
      _kit = null;
    }
  }

  Future<void> _copy(String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copiedWhat = what);
  }

  /// Opens "Publishing notes" over this window.
  Future<void> _openNotes() async {
    await showPublishingNotes(
      context,
      project: () => _project,
      turns: widget.turns,
      onChanged: (n) {
        widget.onNotes?.call(n);
        if (mounted) setState(() => _project = _project.copyWith(publishing: n));
      },
    );
    if (mounted) setState(() {});
  }

  /// Phones: the share sheet with the finished file(s). The title and
  /// description go along as text; many apps ignore that, which is why
  /// "Copy title and description" stays on screen.
  Future<void> _share() async {
    final publish = widget.publish;
    if (publish == null) return;
    final paths = _kitFiles.isNotEmpty
        ? [
            for (final f in _kitFiles) f.path,
            ?_textPath,
          ]
        : [?_outputPath];
    if (paths.isEmpty) return;
    final short = _made.isNotEmpty && _made.every((c) => c.destination.shortForm);
    try {
      await publish.share(paths,
          text: _notes.isEmpty && creditsText(_project).isEmpty
              ? null
              : titleAndDescription(_project, shortForm: short),
          subject: _notes.title.isEmpty ? _project.name : _notes.title);
    } catch (e) {
      if (mounted) {
        setState(() => _galleryProblem = 'Sharing did not work ($e)');
      }
    }
  }

  /// Space the export needs on the disk it goes to: the video, and on a
  /// phone its copy in the gallery as well.
  ExportSizeEstimate _neededFor(ExportOptions options) {
    final e = estimateExportSize(_project, options);
    final copies = widget.files.canChooseSaveLocation ? 1 : 2;
    return ExportSizeEstimate(
        typicalBytes: e.typicalBytes * copies, maxBytes: e.maxBytes * copies);
  }

  /// Checks the free space where [path] goes. Says so and returns false
  /// when the video clearly will not fit; asks when it may not. True
  /// (go on) when there is room or the free space cannot be told.
  Future<bool> _roomFor(String path, ExportOptions options) async {
    final free = await LongJobSupport.instance.freeBytes(p.dirname(path));
    if (free == null || !mounted) return true;
    final need = _neededFor(options);
    final room = diskRoomFor(need, free);
    if (room == DiskRoom.enough) return true;
    final needs = 'This video needs about ${formatBytes(need.typicalBytes)} '
        '(up to ${formatBytes(need.maxBytes)} with very detailed footage); '
        '${formatBytes(free)} is free there.';
    if (room == DiskRoom.notEnough) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not enough free space'),
          content: Text('$needs Free up some space'
              '${widget.files.canChooseSaveLocation ? ', choose another place' : ''}'
              '${_quality == ExportQuality.full ? ' or choose Small file' : ''}, '
              'then try again.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Space is tight'),
        content: Text('$needs The export may stop when the disk is full.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export anyway'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  void _backToOptions() {
    if (!mounted) return;
    setState(() => _phase = _Phase.options);
  }

  void _fail(String message, String? log, {List<String> missing = const []}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
      _errorLog = log;
      _errorMissing = missing;
    });
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await _job?.cancel();
      await _kit?.cancel();
    } catch (_) {}
  }

  Future<void> _saveToGallery() async {
    final path = _outputPath;
    if (path == null || _copying) return;
    setState(() {
      _copying = true;
      _galleryProblem = null;
    });
    String? place;
    String? problem;
    try {
      place = await widget.files.saveCopy(path, fileName(path));
      if (place == null) {
        problem = 'The app was not allowed to add the video to the gallery.';
      }
    } catch (e) {
      problem = 'The video could not be added to the gallery ($e)';
    }
    if (!mounted) return;
    setState(() {
      _copying = false;
      _galleryPlace = place;
      _galleryProblem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.running,
      child: AlertDialog(
        title: Text(switch (_phase) {
          _Phase.options => _several
              ? 'Export several'
              : _format.audioOnly
                  ? 'Export sound'
                  : 'Export video',
          _Phase.running => _cancelling ? 'Stopping…' : 'Exporting…',
          _Phase.done => _kitFiles.isNotEmpty
              ? 'Files saved'
              : _format.audioOnly
                  ? 'Sound saved'
                  : 'Video saved',
          _Phase.failed => 'Export failed',
        }),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: switch (_phase) {
                _Phase.options =>
                  _several ? _severalOptions(context) : _options(context),
                _Phase.running => _running(context),
                _Phase.done => _done(context),
                _Phase.failed => _failed(context),
              },
            ),
          ),
        ),
        actions: switch (_phase) {
          _Phase.options => [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                  key: const ValueKey('export-go'),
                  onPressed:
                      _several && _tickedChoices.isEmpty ? null : _start,
                  child: Text(_several
                      ? 'Export ${_tickedChoices.length} '
                          '${_tickedChoices.length == 1 ? 'file' : 'files'}'
                      : 'Export')),
            ],
          _Phase.running => [
              TextButton(
                onPressed: _cancelling ? null : _cancel,
                child: const Text('Cancel export'),
              ),
            ],
          _Phase.done => [
              if (_galleryProblem != null)
                TextButton(
                  onPressed: _saveToGallery,
                  child: const Text('Try again'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          _Phase.failed => [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: _backToOptions,
                child: const Text('Try again'),
              ),
            ],
        },
      ),
    );
  }

  Widget _options(BuildContext context) {
    final canvas = _project.canvasSize;
    final text = Theme.of(context).textTheme;
    Widget choice(ExportQuality q, String title, String detail) {
      final selected = _quality == q;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? AppColors.panelHigh : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? AppColors.accent : AppColors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _customQuality = q),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? AppColors.accent : AppColors.textDim,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(detail,
                            style: text.bodySmall
                                ?.copyWith(color: AppColors.textDim)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final onSize = widget.onVideoSize;
    final audio = _format.audioOnly;
    if (!_dest.custom) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._destinationPicker(text),
          ..._presetDetails(text),
          if (!audio && _gpuAvailable != null) _encoderPlan(text),
          if (!audio && _gpuAvailable == true && _firstExport)
            _firstExportNote(text),
          _sizeLine(text),
          const SizedBox(height: 4),
          Text(_lengthLine(audio),
              style: text.bodySmall?.copyWith(color: AppColors.textDim)),
          if (_showLongNote) _longNote(text),
          _notesRow(text),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._destinationPicker(text),
        Text('Make', style: text.labelLarge),
        const SizedBox(height: 6),
        ChoiceRow<ExportFormat>(
          key: const ValueKey('export-format'),
          values: ExportFormat.values,
          label: (f) => switch (f) {
            ExportFormat.video => 'Video',
            ExportFormat.m4a => 'Sound M4A',
            ExportFormat.mp3 => 'Sound MP3',
          },
          selected: _format,
          onSelected: (f) => setState(() => _customFormat = f),
        ),
        const SizedBox(height: 4),
        Text(
          switch (_format) {
            ExportFormat.video => 'A video file (MP4) with picture and sound.',
            ExportFormat.m4a =>
              'Only the sound, as an M4A file: good quality, small, plays '
                  'almost everywhere. For podcasts and voice recordings.',
            ExportFormat.mp3 =>
              'Only the sound, as an MP3 file: plays on any device.',
          },
          style: text.bodySmall?.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 10),
        if (!audio && onSize != null) ...[
          Text('Video size', style: text.labelLarge),
          const SizedBox(height: 6),
          ChoiceRow<VideoSize>(
            values: VideoSize.values,
            label: videoSizeLabel,
            selected: _project.videoSize,
            onSelected: (v) {
              onSize(v);
              setState(() => _project = _project.copyWith(videoSize: v));
            },
          ),
          const SizedBox(height: 4),
          Text(
            _project.videoSize == VideoSize.matchFirstClip
                ? 'The size of the first clip. Choose 1080p if a small '
                    'clip (from a chat app) came first.'
                : 'Every clip is scaled to this size.',
            style: text.bodySmall?.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 10),
        ],
        if (!audio) ...[
          choice(ExportQuality.full, 'Full quality',
              '${canvas.width} × ${canvas.height}, best for keeping'),
          choice(ExportQuality.small, 'Small file',
              '720p, quick to send in messaging apps'),
          LabelWithHint('Frames per second',
              articleId: 'export-options', style: text.labelLarge),
          const SizedBox(height: 6),
          ChoiceRow<int?>(
            key: const ValueKey('export-fps'),
            values: const [null, ...ExportOptions.frameRateChoices],
            label: (v) => v == null ? 'As clips' : '$v',
            selected: _fps,
            onSelected: (v) => setState(() => _fps = v),
          ),
          const SizedBox(height: 4),
          Text(
            _fps == null
                ? (_sourceRates.isEmpty
                    ? 'Like the clips (30 when they do not say).'
                    : 'Like the clips: $_sourceFps frames per second.')
                : _fastSource && _exportFps < 50
                    ? 'Your video was filmed at a high frame rate: choose 60 '
                        'to keep fast movement smooth (bigger file).'
                    : '30 suits most videos; 25 is the European TV rate, '
                        '24 looks like cinema, 60 keeps fast sport smooth.',
            style: text.bodySmall?.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 6),
        ],
        if (!audio && _gpuAvailable == true)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const LabelWithHint('Use graphics card (faster)',
                articleId: 'graphics-card'),
            subtitle: Text(
              'Usually several times quicker. If a video ever looks wrong, '
              'turn this off: the processor is slower but always works.',
              style: text.bodySmall?.copyWith(color: AppColors.textDim),
            ),
            value: _useGpu,
            onChanged: (v) {
              setState(() => _useGpu = v);
              // Remembered between exports (Settings > Export).
              widget.settings?.setGraphicsCard(v);
            },
          ),
        if (!audio && _gpuAvailable == true && _firstExport)
          _firstExportNote(text),
        if (!audio) _encoderPlan(text),
        _sizeLine(text),
        const SizedBox(height: 4),
        Text(_lengthLine(audio),
            style: text.bodySmall?.copyWith(color: AppColors.textDim)),
        if (_showLongNote) _longNote(text),
        _notesRow(text),
      ],
    );
  }

  String _lengthLine(bool audio) => widget.files.canChooseSaveLocation
      ? 'Length ${formatLength(_project.durationMs)}. '
          'You choose where to save it next.'
      : audio
          ? 'Length ${formatLength(_project.durationMs)}. '
              'When it is ready you can send it to another app.'
          : 'Length ${formatLength(_project.durationMs)}. '
              'The finished video goes to your gallery.';

  Widget _warningLine(String w, {Key? key}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: Color(0xFFFFC56B)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(w, key: key, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  /// "Where is it going?": the rows of the destinations table, and
  /// "Export several…".
  List<Widget> _destinationPicker(TextTheme text) => [
        Row(
          children: [
            Expanded(
              child: LabelWithHint('Where is it going?',
                  articleId: 'export-destinations', style: text.labelLarge),
            ),
            if (widget.publish != null)
              TextButton(
                key: const ValueKey('export-several'),
                onPressed: () => setState(() => _several = true),
                child: const Text('Export several…'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final d in kDestinations)
              ChoiceChip(
                key: ValueKey('export-dest-${d.id}'),
                label: Text(d.label, style: const TextStyle(fontSize: 13)),
                selected: _dest.id == d.id,
                showCheckmark: false,
                // Small enough for two in a row on a phone.
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                onSelected: (_) => setState(() {
                  _dest = d;
                  _destShape = null;
                  _destFormat = null;
                  _asIs = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(_dest.detail,
            key: const ValueKey('export-dest-detail'),
            style: text.bodySmall?.copyWith(color: AppColors.textDim)),
        const SizedBox(height: 10),
      ];

  /// What a destination other than Custom adds: its shape or file choice,
  /// the question about a different shape, and its warnings.
  List<Widget> _presetDetails(TextTheme text) {
    final d = _dest;
    final choice = _choice;
    final shape = choice.shapeInUse;
    final canvas = destinationVariant(_project, choice, keepShape: _asIs)
        .canvasSize;
    return [
      if (d.shapes.length > 1) ...[
        ChoiceRow<CanvasAspect>(
          key: const ValueKey('export-dest-shape'),
          values: d.shapes,
          label: (a) => a == CanvasAspect.square1x1
              ? 'Square 1:1'
              : 'Tall ${aspectName(a)}',
          selected: shape,
          onSelected: (a) => setState(() => _destShape = a),
        ),
        const SizedBox(height: 8),
      ],
      if (d.formats.length > 1) ...[
        ChoiceRow<ExportFormat>(
          key: const ValueKey('export-dest-format'),
          values: d.formats,
          label: (f) => f.extension.toUpperCase(),
          selected: choice.formatInUse,
          onSelected: (f) => setState(() => _destFormat = f),
        ),
        const SizedBox(height: 8),
      ],
      if (_shapeDiffers) ...[
        Text(
            'Your video is ${aspectName(_project.aspect) == 'Original' ? '${_project.canvasSize.width} × ${_project.canvasSize.height}' : aspectName(_project.aspect)}; '
            'this needs ${aspectName(shape!)}.',
            key: const ValueKey('export-shape-differs'),
            style: text.bodyMedium),
        RadioGroup<bool>(
          groupValue: _asIs,
          onChanged: (v) => setState(() => _asIs = v ?? false),
          child: Column(
            children: [
              RadioListTile<bool>(
                key: const ValueKey('export-shape-copy'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: false,
                title: const Text('Make a copy in this shape'),
                subtitle: Text(
                    '${widget.onKeepCopy == null ? 'A' : 'A new project next to this one: a'} '
                    'blurred background fills the frame. Open the copy and '
                    'use Crop and position to keep the person in shot. This '
                    'project stays as it is.',
                    style: text.bodySmall?.copyWith(color: AppColors.textDim)),
              ),
              RadioListTile<bool>(
                key: const ValueKey('export-shape-as-is'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: true,
                title: const Text('Export as it is'),
                subtitle: Text('Keep the shape the video has now.',
                    style: text.bodySmall?.copyWith(color: AppColors.textDim)),
              ),
            ],
          ),
        ),
      ],
      if (!_format.audioOnly)
        Text('${canvas.width} × ${canvas.height}'
            '${d.quality == ExportQuality.small ? ', made smaller for sending (720p)' : ''}',
            key: const ValueKey('export-dest-size'),
            style: text.bodySmall?.copyWith(color: AppColors.textDim)),
      for (final w in destinationWarnings(_project, choice))
        _warningLine(w, key: const ValueKey('export-dest-warning')),
      const SizedBox(height: 8),
    ];
  }

  /// "Publishing notes…" in the options, with what they hold now.
  Widget _notesRow(TextTheme text) {
    final n = _notes;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              n.isEmpty
                  ? 'No title or description for posting yet.'
                  : 'Notes: ${n.title.isEmpty ? '(no title)' : n.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textDim),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('export-notes'),
            onPressed: _openNotes,
            icon: const Icon(Icons.notes, size: 18),
            label: const Text('Publishing notes…'),
          ),
        ],
      ),
    );
  }

  /// "Export several…": tick the destinations; one job makes them all.
  Widget _severalOptions(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ticked = _tickedChoices;
    final plan = planKit(_project, ticked);
    final reshaped = plan.items.where((i) => i.reshaped).toList();
    var bytes = 0;
    for (final i in plan.items) {
      bytes += estimateExportSize(i.project, i.options).typicalBytes;
    }
    final desktop = widget.files.canChooseSaveLocation;
    return Column(
      key: const ValueKey('export-several-list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Tick where the video is going. The files are made one after '
            'another and saved together, with a text file to paste from.',
            style: text.bodySmall?.copyWith(color: AppColors.textDim)),
        const SizedBox(height: 4),
        for (final c in kitChoices())
          CheckboxListTile(
            key: ValueKey('export-tick-${c.key}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ticked.contains(c.key),
            onChanged: (v) => setState(() =>
                v == true ? _ticked.add(c.key) : _ticked.remove(c.key)),
            title: Text(c.label),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kitFileName(_project.name, c),
                    style: text.bodySmall?.copyWith(color: AppColors.textDim)),
                if (_ticked.contains(c.key))
                  for (final w in destinationWarnings(_project, c))
                    _warningLine(w,
                        key: ValueKey('export-tick-warning-${c.key}')),
              ],
            ),
          ),
        if (reshaped.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
              '${reshaped.map((i) => aspectName(i.choice.shapeInUse!)).toSet().join(' and ')}: '
              'a copy of the video in that shape is made for the export, '
              'with a blurred background. Your project stays as it is.',
              key: const ValueKey('export-several-shapes'),
              style: text.bodySmall?.copyWith(color: AppColors.textDim)),
          if (widget.onKeepCopy != null)
            CheckboxListTile(
              key: const ValueKey('export-keep-copies'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _keepCopies,
              onChanged: (v) => setState(() => _keepCopies = v ?? false),
              title: const Text('Keep the shape copies as projects'),
              subtitle: Text(
                  'To adjust Crop and position in them later. Otherwise '
                  'nothing is added to your project list.',
                  style: text.bodySmall?.copyWith(color: AppColors.textDim)),
            ),
        ],
        const SizedBox(height: 6),
        Text(
            ticked.isEmpty
                ? 'Tick at least one.'
                : '${ticked.length} ${ticked.length == 1 ? 'file' : 'files'}, '
                    'about ${formatBytes(bytes)} together. '
                    '${desktop ? 'You choose the folder next.' : 'The videos go to your gallery, in an album called "${plan.folderName}".'}',
            key: const ValueKey('export-several-summary'),
            style: text.bodySmall?.copyWith(color: AppColors.textDim)),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('export-one'),
              onPressed: () => setState(() => _several = false),
              child: const Text('Export just one…'),
            ),
            TextButton.icon(
              key: const ValueKey('export-notes'),
              onPressed: _openNotes,
              icon: const Icon(Icons.notes, size: 18),
              label: const Text('Publishing notes…'),
            ),
          ],
        ),
      ],
    );
  }

  /// Before the export: about how big the file will be.
  Widget _sizeLine(TextTheme text) {
    final options =
        ExportOptions(quality: _quality, fps: _exportFps, format: _format);
    final e = estimateExportSize(_project, options);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.sd_storage_outlined,
              size: 16, color: AppColors.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'File size: about ${formatBytes(e.typicalBytes)}',
              key: const ValueKey('export-size'),
              style: text.bodySmall?.copyWith(color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  /// Before the export: which part of the device will make the video, once
  /// the check for a graphics card is done.
  Widget _encoderPlan(TextTheme text) {
    final gpu = _gpu;
    final String line;
    if (_gpuAvailable == null) {
      line = 'Checking for a graphics card encoder…';
    } else if (gpu != null && _useGpu) {
      line = 'Will use: ${encoderLabel(gpu)}';
    } else if (gpu != null) {
      line = 'Will use: Processor (graphics card turned off)';
    } else {
      line = 'Will use: Processor (no graphics card encoder works on this '
          'device)';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: [
          Icon(gpu != null && _useGpu ? Icons.memory : Icons.developer_board,
              size: 16, color: AppColors.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(line,
                key: const ValueKey('export-encoder-plan'),
                style: text.bodySmall?.copyWith(color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }

  /// After the export: which part made it and how long it took. A
  /// graphics card that was asked for but failed is said so.
  String _resultLine() {
    final used = _encoderUsed;
    final took = _took == null ? '' : ' Took ${formatLength(_took!.inMilliseconds)}.';
    if (used == null) return took.trim();
    final fellBack = !used.hardware && _wantedGpu && _gpu != null;
    final what = fellBack
        ? '${encoderDescription(used)} — the graphics card '
            '(${encoderLabel(_gpu!).replaceFirst('Graphics card — ', '')}) '
            'did not work, so the processor made it.'
        : used.hardware
            ? '${encoderDescription(used)}: '
                '${encoderLabel(used).replaceFirst(RegExp(r'^Graphics (card|chip) — '), '')}.'
            : '${encoderDescription(used)}.';
    return '$what$took';
  }

  Widget _running(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),
        Text('${(_progress * 100).round()}%'
            '${_kit == null || _kitNow.isEmpty ? '' : ' · $_kitNow'}',
            key: const ValueKey('export-progress')),
        const SizedBox(height: 4),
        Text(
          _project.durationMs >= kLongProjectMs
              ? '$_keepOpenNote A long video takes a while.'
              : _keepOpenNote,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF4CD08A), size: 40),
        const SizedBox(height: 12),
        if (_copying)
          const Text('Adding it to your gallery…')
        else if (_galleryPlace != null)
          Text('Saved to ${_galleryPlace!}')
        else if (_kitFiles.isNotEmpty && !widget.files.canChooseSaveLocation)
          const Text('Saved inside the app')
        else ...[
          const Text('Saved to'),
          const SizedBox(height: 4),
          SelectableText(
            _outputPath ?? '',
            style: const TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ],
        if (_encoderUsed != null || _took != null) ...[
          const SizedBox(height: 8),
          Text(
            _resultLine(),
            key: const ValueKey('export-encoder-result'),
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
        for (final w in _warnings) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFFFFC56B)),
              const SizedBox(width: 6),
              Expanded(child: Text(w, style: const TextStyle(fontSize: 12))),
            ],
          ),
        ],
        if (_format.audioOnly &&
            !widget.files.canChooseSaveLocation &&
            widget.documents != null &&
            _outputPath != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('export-share-sound'),
            onPressed: () {
              final path = _outputPath!;
              widget.documents!.shareFile(
                  fileName(path), (dest) => File(path).copy(dest));
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Send to another app'),
          ),
        ],
        if (_galleryProblem != null) ...[
          const SizedBox(height: 12),
          Text(_galleryProblem!, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          const Text(
            'It is still safe inside the app, at the place shown above.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
        ..._afterExport(context),
      ],
    );
  }

  /// The finished screen since 1.14: the files of a kit, shape copies,
  /// the notes with Copy buttons, Share (phones), "Show in folder" and the
  /// sites' own upload pages (computers).
  List<Widget> _afterExport(BuildContext context) {
    final publish = widget.publish;
    final desktop = widget.files.canChooseSaveLocation;
    final n = _notes;
    final short = _made.isNotEmpty && _made.every((c) => c.destination.shortForm);
    final credits = creditsText(_project);
    const dim = TextStyle(color: AppColors.textDim, fontSize: 12);
    Widget copyRow(String id, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: dim),
                    Text(value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('export-copy-$id'),
                tooltip: 'Copy ${label.toLowerCase()}',
                visualDensity: VisualDensity.compact,
                icon: Icon(_copiedWhat == id ? Icons.check : Icons.copy,
                    size: 18, semanticLabel: 'Copy ${label.toLowerCase()}'),
                onPressed: () => _copy(id, value),
              ),
            ],
          ),
        );
    final uploads = <UploadLink>[];
    for (final c in _made) {
      for (final u in c.destination.uploads) {
        if (!uploads.any((x) => x.url == u.url)) uploads.add(u);
      }
    }
    return [
      if (_kitFiles.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final f in _kitFiles)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Icon(
                    f.item.options.format.audioOnly
                        ? Icons.audiotrack
                        : Icons.movie_outlined,
                    size: 16,
                    color: AppColors.textDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(p.basename(f.path),
                      key: ValueKey('export-file-${f.item.choice.key}'),
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
      ],
      if (_textPath != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              const Icon(Icons.description_outlined,
                  size: 16, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    '${p.basename(_textPath!)} - the text to paste',
                    key: const ValueKey('export-text-file'),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      for (final c in _copies)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              'The copy "${c.name}" is in your project list: open it to '
              'adjust Crop and position.',
              key: const ValueKey('export-copy-made'),
              style: const TextStyle(fontSize: 12)),
        ),
      if (_copyNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_copyNote!, style: const TextStyle(fontSize: 12)),
        ),
      const Divider(height: 24),
      if (!n.isEmpty) ...[
        if ((short ? n.titleForShort : n.title).isNotEmpty)
          copyRow('title', 'Title', short ? n.titleForShort : n.title),
        if (pasteText(_project, shortForm: short).isNotEmpty)
          copyRow('description', 'Description',
              pasteText(_project, shortForm: short)),
      ] else if (credits.isNotEmpty)
        copyRow('description', 'Music credits', 'Music: $credits')
      else
        const Text('No title or description for posting yet.', style: dim),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (publish != null && publish.canShare && _outputPath != null)
            FilledButton.icon(
              key: const ValueKey('export-share'),
              onPressed: _share,
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
            ),
          if (!n.isEmpty || credits.isNotEmpty)
            OutlinedButton.icon(
              key: const ValueKey('export-copy-notes'),
              onPressed: () => _copy(
                  'all', titleAndDescription(_project, shortForm: short)),
              icon: Icon(_copiedWhat == 'all' ? Icons.check : Icons.copy_all,
                  size: 18),
              label: const Text('Copy title and description'),
            ),
          OutlinedButton.icon(
            key: const ValueKey('export-notes'),
            onPressed: _openNotes,
            icon: const Icon(Icons.notes, size: 18),
            label: Text(n.isEmpty ? 'Write publishing notes…' : 'Publishing notes…'),
          ),
          if (publish != null && desktop && _outputPath != null)
            OutlinedButton.icon(
              key: const ValueKey('export-show-folder'),
              onPressed: () => publish
                  .showInFolder(_kitFiles.isNotEmpty
                      ? _kitFiles.first.path
                      : _outputPath!)
                  .catchError((Object _) {}),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Show in folder'),
            ),
        ],
      ),
      if (publish != null && publish.canShare)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
              'Many apps ignore text that is shared with a video: copy the '
              'title and description, then paste them there.',
              style: dim),
        ),
      if (publish != null && desktop && uploads.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text(
            'Upload it yourself on the site (opens in your browser; '
            'ClipForge does not sign in or post):',
            style: dim),
        Wrap(
          spacing: 4,
          children: [
            for (final u in uploads)
              TextButton.icon(
                key: ValueKey('export-upload-${u.label.toLowerCase()}'),
                onPressed: () =>
                    publish.openUrl(u.url).catchError((Object _) {}),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Open ${u.label} upload page'),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _failed(BuildContext context) {
    final log = _errorLog?.trim() ?? '';
    final tail = log.length > 1200 ? '…${log.substring(log.length - 1200)}' : log;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
        const SizedBox(height: 12),
        Text(_error ?? 'Something went wrong.'),
        if (_errorMissing.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_errorMissing.length == 1 ? 'Missing file:' : 'Missing files:',
              style: Theme.of(context).textTheme.titleSmall),
          for (final path in _errorMissing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(path,
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
        ],
        if (tail.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Technical details',
                  style: TextStyle(fontSize: 13, color: AppColors.textDim)),
              children: [
                SelectableText(
                  tail,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppColors.textDim),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Same as the first clip", "720p", "1080p", "4K".
String videoSizeLabel(VideoSize s) => switch (s) {
      VideoSize.matchFirstClip => 'Same as the first clip',
      VideoSize.p720 => '720p',
      VideoSize.p1080 => '1080p',
      VideoSize.p2160 => '4K',
    };
