import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/model/project.dart' show ClipType, Project, VideoSize;
import '../../media/export_estimate.dart';
import '../../media/media_api.dart';
import '../../media/video_encoder.dart' show encoderDescription, encoderLabel;
import '../format.dart';
import '../help/help_screen.dart';
import '../long_jobs.dart';
import '../services.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'clip_panels.dart' show ChoiceRow;
import 'long_project_note.dart' show kLongProjectMs;
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
        documents: documents),
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
  });
  final Project project;

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
  ExportQuality _quality = ExportQuality.full;
  double _progress = 0;
  ExportJob? _job;
  StreamSubscription<ExportProgress>? _progressSub;
  bool _cancelling = false;
  String? _outputPath;
  String? _error;
  String? _errorLog;
  List<String> _errorMissing = const [];

  /// Video, or the sound only (M4A / MP3).
  ExportFormat _format = ExportFormat.video;

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
    if (_format.audioOnly) {
      return '${safeFileName(_project.name)} (sound).${_format.extension}';
    }
    final suffix = _quality == ExportQuality.small ? ' (small)' : '';
    return '${safeFileName(_project.name)}$suffix.mp4';
  }

  @override
  void initState() {
    super.initState();
    _lookForFastVideo();
    _lookForGraphicsCard();
  }

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
    if (_phase == _Phase.running) _job?.cancel().catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
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
    final options = ExportOptions(
        quality: _quality,
        fps: _exportFps,
        useHardwareEncoder: useGpu,
        format: _format,
        processedSound: widget.processedSound?.call() ?? const {});
    if (!await _roomFor(path, options) || !mounted) return;

    RunningJob? tracked;
    var keptAwake = false;
    final clock = Stopwatch()..start();
    _wantedGpu = useGpu && _gpuAvailable != false;
    try {
      final job = widget.engine.export(
        _project,
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
          _Phase.options => _format.audioOnly ? 'Export sound' : 'Export video',
          _Phase.running => _cancelling ? 'Stopping…' : 'Exporting…',
          _Phase.done => _format.audioOnly ? 'Sound saved' : 'Video saved',
          _Phase.failed => 'Export failed',
        }),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: switch (_phase) {
                _Phase.options => _options(context),
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
              FilledButton(onPressed: _start, child: const Text('Export')),
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
            onTap: () => setState(() => _quality = q),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          onSelected: (f) => setState(() => _format = f),
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
            onChanged: (v) => setState(() => _useGpu = v),
          ),
        if (!audio) _encoderPlan(text),
        _sizeLine(text),
        const SizedBox(height: 4),
        Text(
          widget.files.canChooseSaveLocation
              ? 'Length ${formatLength(_project.durationMs)}. '
                  'You choose where to save it next.'
              : audio
                  ? 'Length ${formatLength(_project.durationMs)}. '
                      'When it is ready you can send it to another app.'
                  : 'Length ${formatLength(_project.durationMs)}. '
                      'The finished video goes to your gallery.',
          style: text.bodySmall?.copyWith(color: AppColors.textDim),
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
        Text('${(_progress * 100).round()}%'),
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
      ],
    );
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

/// "As first clip", "720p", "1080p", "4K".
String videoSizeLabel(VideoSize s) => switch (s) {
      VideoSize.matchFirstClip => 'As first clip',
      VideoSize.p720 => '720p',
      VideoSize.p1080 => '1080p',
      VideoSize.p2160 => '4K',
    };
