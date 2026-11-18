import 'package:material_ui/material_ui.dart';

import '../../core/model/project.dart';
import '../help/help_screen.dart' show HelpHint;
import '../theme.dart';
import 'session.dart';
import 'sound_renders.dart';

/// On a clip's timeline block: a thin bar along its bottom edge while its
/// processed sound is being made, and "Sound 40%" when there is room.
class ClipSoundProgress extends StatelessWidget {
  const ClipSoundProgress(
      {super.key, required this.session, required this.clip, this.roomy = true});
  final EditorSession session;
  final Clip clip;

  /// The block is big enough for a label.
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.sounds,
      builder: (context, _) {
        final status = session.sounds.statusOf(clip);
        if (!status.preparing) return const SizedBox.shrink();
        final processing = status.state == SoundState.processing;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: LinearProgressIndicator(
                key: ValueKey('sound-progress-${clip.id}'),
                value: processing ? status.fraction : null,
                minHeight: 3,
                backgroundColor: const Color(0x55000000),
                color: AppColors.accent,
              ),
            ),
            if (roomy)
              Positioned(
                right: 5,
                top: 4,
                child: Tooltip(
                  message: status.label,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      processing
                          ? 'Sound ${(status.fraction * 100).floor().clamp(0, 99)}%'
                          : 'Sound…',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// In the Sound panel: where the clip's processed sound is, with Stop /
/// Process sound / Try again.
class SoundProcessingRow extends StatelessWidget {
  const SoundProcessingRow({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  static const _dim = TextStyle(color: AppColors.textDim, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final sounds = session.sounds;
    return ListenableBuilder(
      listenable: sounds,
      builder: (context, _) {
        final status = sounds.statusOf(clip);
        if (status.state == SoundState.none) return const SizedBox.shrink();
        final Widget body;
        switch (status.state) {
          case SoundState.none:
            return const SizedBox.shrink();
          case SoundState.waiting:
          case SoundState.processing:
            final processing = status.state == SoundState.processing;
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(status.label,
                          key: const ValueKey('sound-status')),
                    ),
                    TextButton(
                      onPressed: () => sounds.stop(clip),
                      child: const Text('Stop'),
                    ),
                    const HelpHint('preparing-sound', label: 'Preparing sound'),
                  ],
                ),
                LinearProgressIndicator(
                  value: processing ? status.fraction : null,
                  minHeight: 4,
                ),
                const SizedBox(height: 6),
                const Text(
                    'Meanwhile the preview plays a light version.',
                    style: _dim),
              ],
            );
          case SoundState.ready:
            body = const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Sound ready: the preview plays it as the '
                      'export will.',
                      key: ValueKey('sound-status')),
                ),
              ],
            );
          case SoundState.failed:
          case SoundState.stopped:
            final failed = status.state == SoundState.failed;
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(status.label,
                          key: const ValueKey('sound-status')),
                    ),
                    TextButton(
                      onPressed: () => sounds.retry(clip),
                      child: Text(failed ? 'Try again' : 'Process sound'),
                    ),
                  ],
                ),
                Text(
                  failed
                      ? '${status.error ?? ''} The preview plays a light '
                          'version; the export still does it in full.'
                          .trim()
                      : 'The preview plays a light version; the export '
                          'still does it in full.',
                  style: _dim,
                ),
              ],
            );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: body,
        );
      },
    );
  }
}

/// Over the preview: "Preparing sound…" while the clip under the playhead
/// plays its light live version because its processed sound is not ready
/// yet.
class PreparingSoundNote extends StatelessWidget {
  const PreparingSoundNote({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final playback = session.playback;
    return ListenableBuilder(
      listenable:
          Listenable.merge([session.sounds, playback, playback.hearOriginal]),
      builder: (context, _) {
        final clip = playback.currentClip;
        if (clip == null || playback.hearOriginal.value) {
          return const SizedBox.shrink();
        }
        final status = session.sounds.statusOf(clip);
        if (!status.preparing) return const SizedBox.shrink();
        final processing = status.state == SoundState.processing;
        return IgnorePointer(
          child: Container(
            key: const ValueKey('preparing-sound'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: processing ? status.fraction : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  processing
                      ? 'Preparing sound… '
                          '${(status.fraction * 100).floor().clamp(0, 99)}%'
                      : 'Preparing sound…',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
