import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/model/project.dart';
import '../../media/media_api.dart';
import '../playback/timeline_player.dart';
import 'session.dart';

/// Length of a sound sample, in timeline time.
const int kSoundSampleMs = 15000;

/// Of which this much comes before the playhead.
const int kSoundSampleLeadMs = 5000;

/// The source range of [clip] a sample is made of: [kSoundSampleMs] of
/// timeline around [timelineMs] (5 s before, 10 s after), kept inside the
/// clip's trim range; at the clip's start when the playhead is elsewhere.
({int inMs, int outMs}) soundSampleRange(Project project, Clip clip, int timelineMs) {
  final index = project.clips.indexWhere((c) => c.id == clip.id);
  final speed = clip.type == ClipType.photo ? 1.0 : clip.speed;
  final local = index < 0 ? -1 : timelineMs - project.clipStartMs(index);
  final src = local >= 0 && local < clip.durationMs ? clip.sourceMsAt(local) : clip.inMs;
  final span = (kSoundSampleMs * speed).round();
  final lead = (kSoundSampleLeadMs * speed).round();
  final out = math.min(clip.outMs, math.max(src - lead, clip.inMs) + span);
  final inMs = math.max(clip.inMs, out - span);
  return (inMs: inMs, outMs: out);
}

/// The two one-clip projects of a sample: [clip] over [range] with its
/// sound settings, and the same with clean-up and voice focus off and both
/// sides (its track kept). No music and no titles: only the clip's sound.
({Project processed, Project original}) soundSampleProjects(
    Project project, Clip clip, ({int inMs, int outMs}) range) {
  final piece = clip.copyWith(
      inMs: range.inMs, outMs: range.outMs, transition: TransitionType.none);
  Project one(Clip c) => Project(
        id: 'sound-sample',
        name: 'Sound sample',
        createdAt: project.createdAt,
        updatedAt: project.updatedAt,
        clips: [c],
      );
  return (
    processed: one(piece),
    original: one(piece.copyWith(
        denoise: false, voiceFocus: 0, audioChannel: AudioChannel.both)),
  );
}

/// "Hear a 15-second sample": renders 15 s of [clip] around the playhead
/// with the export engine (so clean-up and voice focus are exactly as in
/// the export), once with its sound settings and once without, and plays
/// them for comparison.
Future<void> hearSoundSample(
    BuildContext context, EditorSession s, Clip clip) async {
  s.playback.pause();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SampleDialog(session: s, clip: clip),
  );
}

class _SampleDialog extends StatefulWidget {
  const _SampleDialog({required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  State<_SampleDialog> createState() => _SampleDialogState();
}

class _SampleDialogState extends State<_SampleDialog> {
  Directory? _dir;
  ExportJob? _export;
  RunningJob? _job;
  double _progress = 0;
  String? _error;
  String? _processed;
  String? _original;

  /// Sound settings the export engine could not apply on this device.
  List<String> _warnings = const [];

  TimelinePlayer? _player;
  StreamSubscription<int>? _positionSub;
  StreamSubscription<void>? _endSub;
  bool _withEffect = true;
  bool _playing = false;
  int _positionMs = 0;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    final s = widget.session;
    final job = _job = s.jobs.start(JobKind.export, cancel: _cancel);
    try {
      final range = soundSampleRange(s.project, widget.clip, s.playback.positionMs);
      final projects = soundSampleProjects(s.project, widget.clip, range);
      final dir = _dir = Directory.systemTemp.createTempSync('clipforge_sample_');
      Future<String> render(Project project, String name, double from) async {
        final job = _export = s.engine.export(project, p.join(dir.path, name),
            options: const ExportOptions(quality: ExportQuality.small));
        final sub = job.progress.listen((e) {
          if (mounted) setState(() => _progress = from + e.fraction / 2);
        });
        try {
          return await job.done;
        } finally {
          unawaited(sub.cancel());
        }
      }

      final processed = await render(projects.processed, 'with-effect.mp4', 0);
      final warnings = _export?.warnings ?? const <String>[];
      if (_closed) return;
      final original = await render(projects.original, 'original.mp4', 0.5);
      if (!mounted || _closed) return;
      setState(() {
        _processed = processed;
        _original = original;
        _warnings = warnings;
      });
    } catch (e) {
      if (mounted && !_closed) {
        setState(() => _error = e is ExportException ? e.message : '$e');
      }
    } finally {
      _export = null;
      s.jobs.end(job);
      _job = null;
    }
  }

  Future<void> _cancel() async {
    _closed = true;
    await _export?.cancel();
  }

  Future<void> _load({required bool play}) async {
    final path = _withEffect ? _processed : _original;
    if (path == null) return;
    var player = _player;
    if (player == null) {
      player = _player = widget.session.backend.createAudioPlayer();
      _positionSub = player.positionStream.listen((ms) {
        if (mounted) setState(() => _positionMs = ms);
      });
      _endSub = player.completedStream.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    }
    await player.open(path, positionMs: _positionMs, play: play);
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (_playing) {
      setState(() => _playing = false);
      await player?.pause();
      return;
    }
    setState(() => _playing = true);
    if (player == null) {
      await _load(play: true);
    } else {
      if (_positionMs >= kSoundSampleMs - 100) {
        _positionMs = 0;
        await player.seek(0);
      }
      await player.play();
    }
  }

  Future<void> _choose(bool withEffect) async {
    if (withEffect == _withEffect) return;
    setState(() => _withEffect = withEffect);
    // Same moment of the other version.
    if (_player != null) await _load(play: _playing);
  }

  Future<void> _close() async {
    _closed = true;
    await _export?.cancel();
    final job = _job;
    if (job != null) widget.session.jobs.end(job);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closed = true;
    _positionSub?.cancel();
    _endSub?.cancel();
    unawaited(_cleanUp(_player, _dir));
    super.dispose();
  }

  /// The player first lets go of the file: Windows cannot delete a file
  /// that is still open, which would leave the samples in the temp folder.
  static Future<void> _cleanUp(TimelinePlayer? player, Directory? dir) async {
    try {
      await player?.dispose();
    } catch (_) {}
    if (dir == null) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  String get _effects {
    final c = widget.clip;
    final parts = [
      if (c.denoise) 'clean-up',
      if (c.voiceFocus >= 0.005) 'voice focus ${(c.voiceFocus * 100).round()}%',
      if (c.audioChannelInUse != AudioChannel.both)
        '${c.audioChannelInUse.name} side only',
    ];
    return parts.isEmpty ? 'no sound changes' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final ready = _processed != null && _original != null;
    final Widget body;
    if (_error != null) {
      body = Text('The sample could not be made: $_error');
    } else if (!ready) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress <= 0 ? null : _progress, minHeight: 6),
          const SizedBox(height: 14),
          Text('Making 15 seconds the way the export will sound ($_effects), '
              'and the same without…'),
        ],
      );
    } else {
      final secs = (_positionMs / 1000).clamp(0, 99).toStringAsFixed(1);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Switch while it plays to hear the difference ($_effects).'),
          for (final w in _warnings) ...[
            const SizedBox(height: 8),
            Text(w, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('With changes')),
              ButtonSegment(value: false, label: Text('Original')),
            ],
            selected: {_withEffect},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _choose(v.single),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _togglePlay,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 12),
              Text('$secs s'),
            ],
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Sound sample'),
      content: SizedBox(width: 360, child: body),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text(ready || _error != null ? 'Close' : 'Cancel'),
        ),
      ],
    );
  }
}
