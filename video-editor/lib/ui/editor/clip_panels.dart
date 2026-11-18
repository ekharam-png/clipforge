import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/editor/editor_controller.dart';
import '../../core/model/look_filter.dart';
import '../../core/model/project.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'picture_tools.dart';
import '../speech/speech_service.dart';
import 'session.dart';
import 'speech_actions.dart';
import 'sound_tracks_ui.dart';
import 'sound_status.dart';
import 'sound_sample.dart';

/// The settings of a clip, one widget per group. Phones show one group at a
/// time in a bottom sheet, wide windows show them as sections of the side
/// panel (see tools.dart).

const List<double> kSpeedPresets = [0.25, 0.5, 1, 1.25, 1.5, 2, 4];

String clipToolLabel(ClipTool tool) => switch (tool) {
  ClipTool.speed => 'Speed',
  ClipTool.look => 'Look',
  ClipTool.sound => 'Sound',
  ClipTool.transition => 'Transition and fades',
  ClipTool.crop => 'Crop',
  ClipTool.layout => 'Layout',
};

IconData clipToolIcon(ClipTool tool) => switch (tool) {
  ClipTool.speed => Icons.speed,
  ClipTool.look => Icons.tune,
  ClipTool.sound => Icons.volume_up,
  ClipTool.transition => Icons.compare,
  ClipTool.crop => Icons.crop,
  ClipTool.layout => Icons.picture_in_picture_alt,
};

/// The groups that apply to [clip], in display order.
List<ClipTool> clipToolsFor(Clip clip) => [
  if (clip.type == ClipType.video) ClipTool.speed,
  ClipTool.look,
  ClipTool.crop,
  if (clip.type == ClipType.video) ClipTool.sound,
  ClipTool.transition,
];

String transitionLabel(TransitionType type) => switch (type) {
  TransitionType.none => 'None',
  TransitionType.crossfade => 'Crossfade',
  TransitionType.fadeBlack => 'Fade through black',
  TransitionType.slideLeft => 'Slide left',
  TransitionType.slideUp => 'Slide up',
};

IconData transitionIcon(TransitionType type) => switch (type) {
  TransitionType.none => Icons.block,
  TransitionType.crossfade => Icons.blur_on,
  TransitionType.fadeBlack => Icons.contrast,
  TransitionType.slideLeft => Icons.keyboard_double_arrow_left,
  TransitionType.slideUp => Icons.keyboard_double_arrow_up,
};

bool clipLookChanged(Clip c) =>
    c.brightness != 0 ||
    c.contrast != 0 ||
    c.saturation != 0 ||
    c.zoom != 1 ||
    c.filter != LookFilter.none ||
    c.warmth != 0;

/// A few words about the current setting, shown next to a section heading.
String clipToolSummary(ClipTool tool, Clip clip, Project project) {
  switch (tool) {
    case ClipTool.speed:
      return formatSpeed(clip.speed);
    case ClipTool.look:
      if (clip.filter != LookFilter.none) return lookFilterLabel(clip.filter);
      return clipLookChanged(clip) ? 'Adjusted' : '';
    case ClipTool.sound:
      if (!clip.hasAudio) return 'No sound';
      if (clip.muted) return 'Muted';
      return '${(clip.volume * 100).round()}%';
    case ClipTool.transition:
      final fades = clip.fadeInMs > 0 || clip.fadeOutMs > 0;
      final t =
          project.clips.indexOf(clip) <= 0 ||
              clip.transition == TransitionType.none
          ? (fades ? '' : 'None')
          : transitionLabel(clip.transition);
      return [if (t.isNotEmpty) t, if (fades) 'Fades'].join(', ');
    case ClipTool.crop:
      return framingSummary(clip.framing);
    case ClipTool.layout:
      return '';
  }
}

/// The controls of one [tool] for [clip].
class ClipToolPanel extends StatelessWidget {
  const ClipToolPanel({
    super.key,
    required this.session,
    required this.clip,
    required this.tool,
  });
  final EditorSession session;
  final Clip clip;
  final ClipTool tool;

  @override
  Widget build(BuildContext context) => switch (tool) {
    ClipTool.speed => SpeedPanel(session: session, clip: clip),
    ClipTool.look => LookPanel(session: session, clip: clip),
    ClipTool.sound => SoundPanel(session: session, clip: clip),
    ClipTool.transition => TransitionPanel(session: session, clip: clip),
    ClipTool.crop => CropPanel(session: session, itemId: clip.id),
    ClipTool.layout => const SizedBox.shrink(),
  };
}

const _dim = TextStyle(color: AppColors.textDim, fontSize: 12);

class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

/// A slider whose whole drag is one undo step.
class LiveSlider extends StatefulWidget {
  const LiveSlider({
    super.key,
    required this.editor,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.enabled = true,
    this.helpArticle,
  });
  final EditorController editor;
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) display;
  final ValueChanged<double> onChanged;
  final bool enabled;

  /// A help article explaining this setting ("?" after the label).
  final String? helpArticle;

  @override
  State<LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<LiveSlider> {
  LiveEdit? _edit;

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(widget.min, widget.max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.helpArticle == null
                  ? PanelLabel(widget.label)
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: LabelWithHint(
                        widget.label,
                        articleId: widget.helpArticle!,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
            ),
            Text(
              widget.display(value),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          // One node with the name, the value and the adjust actions: a
          // plain Semantics wrapper made a separate, unadjustable node
          // named after the slider, which assistive tools then could not
          // change.
          child: MergeSemantics(
            child: Semantics(
              label: widget.label,
              child: Slider(
                value: value,
                min: widget.min,
                max: widget.max,
                semanticFormatterCallback: widget.display,
                onChangeStart: widget.enabled
                    ? (_) => _edit = LiveEdit(widget.editor)
                    : null,
                onChanged: !widget.enabled
                    ? null
                    : (v) {
                        final edit = _edit ??= LiveEdit(widget.editor);
                        edit.apply(() => widget.onChanged(v));
                      },
                onChangeEnd: widget.enabled ? (_) => _edit = null : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Apply to all clips": copies one group of settings of [clip] to every
/// other clip it fits, as one undo step, and says how many changed.
class ApplyToAllButton extends StatefulWidget {
  const ApplyToAllButton({
    super.key,
    required this.session,
    required this.clip,
    required this.tool,
  });
  final EditorSession session;
  final Clip clip;

  /// [ClipTool.speed], [ClipTool.look] or [ClipTool.sound].
  final ClipTool tool;

  @override
  State<ApplyToAllButton> createState() => _ApplyToAllButtonState();
}

class _ApplyToAllButtonState extends State<ApplyToAllButton> {
  String? _result;

  /// The project as [_result] left it; any later edit hides the message.
  Project? _resultFor;

  void _apply() {
    final editor = widget.session.editor;
    final tool = widget.tool;
    final changed = editor.applyClipSettingsToAll(
      widget.clip.id,
      speed: tool == ClipTool.speed,
      look: tool == ClipTool.look,
      sound: tool == ClipTool.sound,
    );
    setState(() {
      _result = switch (changed) {
        0 => 'The other clips already match.',
        1 => 'Changed 1 clip. Undo puts it back.',
        _ => 'Changed $changed clips. Undo puts them back.',
      };
      _resultFor = editor.project;
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.session.project;
    if (project.clips.length < 2) return const SizedBox.shrink();
    final result = identical(_resultFor, project) ? _result : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      // Wraps when the button and its note do not fit side by side.
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Apply to all clips'),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              result ??
                  switch (widget.tool) {
                    ClipTool.speed => 'Gives every video this speed.',
                    ClipTool.look => 'Gives every clip this look.',
                    _ => 'Gives every video these sound settings.',
                  },
              style: _dim,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of equally wide choices, one of them selected.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.values,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final List<T> values;
  final String Function(T value) label;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, v) in values.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: v == selected,
              child: Material(
                color: v == selected ? AppColors.accent : AppColors.panelHigh,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: ui.Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(v),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      // A long label shrinks instead of being cut off.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            label(v),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: v == selected
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One choice among a few, sized to its label (see also [ChoiceRow]).
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.textDim.withValues(alpha: 0.5)
        : (selected ? Colors.black : Colors.white);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: selected ? AppColors.accent : AppColors.panelHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: ui.Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Speed ---------------------------------------------------------------------

class SpeedPanel extends StatelessWidget {
  const SpeedPanel({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  static double _log2(double v) => math.log(v) / math.ln2;

  /// Slider position (-2..2) to a speed in steps of 0.05.
  static double _speedAt(double slider) =>
      ((math.pow(2, slider) * 20).round() / 20).clamp(0.25, 4.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final preset = kSpeedPresets
        .where((p) => (p - clip.speed).abs() < 0.005)
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceRow<double>(
          values: kSpeedPresets,
          label: formatSpeed,
          selected: preset,
          onSelected: (v) => editor.setClipSpeed(clip.id, v),
        ),
        const SizedBox(height: 14),
        LiveSlider(
          editor: editor,
          label: 'Any speed',
          value: _log2(clip.speed),
          min: -2,
          max: 2,
          display: (v) => formatSpeed(_speedAt(v)),
          onChanged: (v) => editor.setClipSpeed(clip.id, _speedAt(v)),
        ),
        Text(
          clip.speed == 1
              ? 'Length ${formatLength(clip.durationMs)}'
              : 'Length ${formatLength(clip.durationMs)} '
                    '(${formatLength(clip.sourceSpanMs)} at normal speed)',
          style: const TextStyle(fontSize: 13),
        ),
        if (clip.hasAudio) ...[
          const SizedBox(height: 4),
          const Text('Voices keep their natural pitch.', style: _dim),
        ],
        ApplyToAllButton(session: session, clip: clip, tool: ClipTool.speed),
      ],
    );
  }
}

// Look ----------------------------------------------------------------------

class LookPanel extends StatelessWidget {
  const LookPanel({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  static String _signed(double v) {
    final n = (v * 100).round();
    return n > 0 ? '+$n' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabelWithHint(
          'Filter',
          articleId: 'filters',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey('look-filters'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in LookFilter.values)
              ChoicePill(
                key: ValueKey('filter-${f.name}'),
                label: lookFilterLabel(f),
                selected: clip.filter == f,
                onTap: () => editor.setClipFilter(clip.id, f),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LiveSlider(
          key: const ValueKey('warmth'),
          editor: editor,
          label: 'Warmth',
          value: clip.warmth,
          min: -1,
          max: 1,
          display: (v) => v.abs() < 0.005
              ? '0'
              : '${_signed(v)} ${v < 0 ? 'cooler' : 'warmer'}',
          onChanged: (v) =>
              editor.setClipWarmth(clip.id, (v * 20).round() / 20),
        ),
        LiveSlider(
          editor: editor,
          label: 'Brightness',
          value: clip.brightness,
          min: -1,
          max: 1,
          display: _signed,
          onChanged: (v) => editor.setClipAdjustments(clip.id, brightness: v),
        ),
        LiveSlider(
          editor: editor,
          label: 'Contrast',
          value: clip.contrast,
          min: -1,
          max: 1,
          display: _signed,
          onChanged: (v) => editor.setClipAdjustments(clip.id, contrast: v),
        ),
        LiveSlider(
          editor: editor,
          label: 'Saturation',
          value: clip.saturation,
          min: -1,
          max: 1,
          display: _signed,
          onChanged: (v) => editor.setClipAdjustments(clip.id, saturation: v),
        ),
        LiveSlider(
          editor: editor,
          label: 'Zoom in',
          value: clip.zoom,
          min: 1,
          max: 4,
          display: (v) => '${v.toStringAsFixed(1)}×',
          onChanged: (v) => editor.setClipZoom(clip.id, (v * 20).round() / 20),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: clipLookChanged(clip)
                ? () => editor.resetLook(clip.id)
                : null,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset look'),
          ),
        ),
        LabelWithHint(
          'Fit to frame',
          articleId: 'fit-fill-blur',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        ChoiceRow<FitMode>(
          values: FitMode.values,
          label: (f) => switch (f) {
            FitMode.fit => 'Fit',
            FitMode.fill => 'Fill',
            FitMode.blur => 'Blur',
          },
          selected: clip.fit,
          onSelected: (v) => editor.setClipFit(clip.id, v),
        ),
        const SizedBox(height: 8),
        Text(switch (clip.fit) {
          FitMode.fit => 'Whole picture, with bars where it does not fill.',
          FitMode.fill => 'Fills the frame; the edges are cropped.',
          FitMode.blur => 'Whole picture over a blurred copy of itself.',
        }, style: _dim),
        ApplyToAllButton(session: session, clip: clip, tool: ClipTool.look),
      ],
    );
  }
}

// Sound ---------------------------------------------------------------------

class SoundPanel extends StatelessWidget {
  const SoundPanel({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    if (!clip.hasAudio) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('This clip has no sound.', style: _dim),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiveSlider(
          editor: editor,
          label: 'Volume',
          value: clip.volume,
          min: EditorController.minVolume,
          max: EditorController.maxVolume,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => editor.setClipVolume(clip.id, v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Mute'),
          value: clip.muted,
          onChanged: (v) => editor.setClipMuted(clip.id, v),
        ),
        SeparateSoundRow(session: session, clip: clip),
        const SizedBox(height: 4),
        ..._sourceChoice(context, editor),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const LabelWithHint(
            'Clean up sound',
            articleId: 'clean-up-sound',
          ),
          subtitle: const Text(
            'Less background noise, steadier voices. The sound is processed '
            'in the background; then the preview plays it as the export '
            'will.',
            style: _dim,
          ),
          value: clip.denoise,
          onChanged: (v) {
            editor.setClipDenoise(clip.id, v);
            if (v) _confirm(context, 'Clean up sound is on for this clip.');
          },
        ),
        const SizedBox(height: 4),
        LiveSlider(
          key: const ValueKey('voice-focus'),
          editor: editor,
          label: 'Voice focus',
          helpArticle: 'voice-focus',
          value: clip.voiceFocus,
          min: EditorController.minVoiceFocus,
          max: EditorController.maxVoiceFocus,
          display: (v) => v < 0.005 ? 'Off' : '${(v * 100).round()}%',
          onChanged: (v) {
            final value = (v * 20).round() / 20;
            final wasOff = clip.voiceFocus < 0.005;
            editor.setClipVoiceFocus(clip.id, value);
            if (wasOff && value >= 0.005) {
              _confirm(context, 'Voice focus is on for this clip.');
            }
          },
        ),
        const Text(
          'Makes speech clearer and tones down music and noise behind it. '
          "It can't remove music completely. You hear it in full as soon as "
          'the sound is processed.',
          style: _dim,
        ),
        SoundProcessingRow(session: session, clip: clip),
        if (clip.denoise ||
            clip.voiceFocus >= 0.005 ||
            clip.audioChannelInUse != AudioChannel.both)
          _CompareSound(session: session, clip: clip),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => removeSilences(context, session, clip),
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Remove silences'),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Finds the quiet gaps and cuts them out.',
                style: _dim,
              ),
            ),
            const HelpHint('remove-silences', label: 'Remove silences'),
          ],
        ),
        // Speech-to-text exists on computers only.
        if (session.speech != null) SpeechRow(session: session, clip: clip),
        ApplyToAllButton(session: session, clip: clip, tool: ClipTool.sound),
      ],
    );
  }

  static void _confirm(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// "Sound from": the file's tracks when it has more than one, and the
  /// sides of the track in use when it is stereo. Nothing otherwise.
  List<Widget> _sourceChoice(BuildContext context, EditorController editor) {
    final tracks = clip.audioStreams.length;
    final stereo = clip.audioChannelsInUse == 2;
    if (tracks < 2 && !stereo) return const [];
    return [
      const SizedBox(height: 4),
      LabelWithHint(
        'Sound from',
        articleId: 'sound-from',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      if (tracks > 1) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var t = 0; t < tracks; t++)
              ChoicePill(
                label: 'Track ${t + 1}',
                selected: t == clip.audioTrackInUse,
                onTap: () => editor.setClipAudioSource(clip.id, track: t),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (stereo) ...[
        ChoiceRow<AudioChannel>(
          values: AudioChannel.values,
          label: audioChannelLabel,
          selected: clip.audioChannelInUse,
          onSelected: (v) => editor.setClipAudioSource(clip.id, channel: v),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        tracks > 1
            ? 'For recordings that keep each microphone on its own track '
                  'or side.'
            : 'For recordings that keep a microphone on each side.',
        style: _dim,
      ),
      const SizedBox(height: 4),
    ];
  }
}

/// Ways to hear what the sound settings do: "Hear original" switches the
/// preview's filters off while it is on, "Hear a sample" renders 15 s with
/// the export engine (clean-up and voice focus in full) next to the
/// original.
class _CompareSound extends StatefulWidget {
  const _CompareSound({required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  State<_CompareSound> createState() => _CompareSoundState();
}

class _CompareSoundState extends State<_CompareSound> {
  @override
  void dispose() {
    // Never leave the preview without its sound settings.
    widget.session.playback.hearOriginalSound = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.session.playback;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: playback.hearOriginal,
          builder: (context, original, _) => SwitchListTile(
            key: const ValueKey('hear-original'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Hear original'),
            subtitle: const Text(
              'Turn on and off while it plays to compare.',
              style: _dim,
            ),
            value: original,
            onChanged: (v) => playback.hearOriginalSound = v,
          ),
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  hearSoundSample(context, widget.session, widget.clip),
              icon: const Icon(Icons.headphones, size: 18),
              label: const Text('Hear a sample'),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '15 seconds made like the export, next to the original.',
                style: _dim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

String audioChannelLabel(AudioChannel c) => switch (c) {
  AudioChannel.both => 'Both sides',
  AudioChannel.left => 'Left only',
  AudioChannel.right => 'Right only',
};

// Transition ----------------------------------------------------------------

class TransitionPanel extends StatelessWidget {
  const TransitionPanel({super.key, required this.session, required this.clip});
  final EditorSession session;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final project = session.project;
    final index = project.clips.indexWhere((c) => c.id == clip.id);
    final first = index <= 0;
    final type = first ? TransitionType.none : clip.transition;
    final active = type != TransitionType.none;
    final overlap = first ? 0 : project.transitionOverlapMs(index);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first
              ? 'This is the first clip, so there is nothing before it to '
                    'change from. To start the video from black, use Fade in '
                    'below.'
              : 'How the clip before changes into this one.',
          style: _dim,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in TransitionType.values)
              ChoicePill(
                label: transitionLabel(t),
                icon: t == TransitionType.none ? null : transitionIcon(t),
                selected: t == type,
                onTap: first
                    ? null
                    : () => editor.setClipTransition(clip.id, t),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LiveSlider(
          editor: editor,
          label: 'Length',
          enabled: active,
          value: clip.transitionMs.toDouble(),
          min: 100,
          max: 2000,
          display: (v) => formatLength(v.round()),
          onChanged: (v) => editor.setClipTransition(
            clip.id,
            clip.transition,
            durationMs: (v / 50).round() * 50,
          ),
        ),
        if (active && overlap < clip.transitionMs)
          Text(
            'Plays for ${formatLength(overlap)}: a transition can take up '
            'at most half of either clip.',
            style: _dim,
          )
        else if (active)
          const Text(
            'The two clips overlap while it plays, so the video gets a '
            'little shorter.',
            style: _dim,
          ),
        const Divider(height: 24),
        ClipFadesPanel(session: session, clip: clip, first: first),
      ],
    );
  }
}

/// "Fade in from black" / "Fade out to black" of one clip: its picture and
/// its own sound (one undo step per drag).
class ClipFadesPanel extends StatelessWidget {
  const ClipFadesPanel({
    super.key,
    required this.session,
    required this.clip,
    this.first = false,
  });
  final EditorSession session;
  final Clip clip;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final max = math.max(
      100.0,
      math.min(EditorController.maxClipFadeMs.toDouble(), clip.durationMs / 2),
    );
    String show(double v) => v < 50 ? 'Off' : formatLength(v.round());
    int step(double v) => v < 50 ? 0 : (v / 100).round() * 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiveSlider(
          key: const ValueKey('clip-fade-in'),
          editor: editor,
          label: 'Fade in from black',
          helpArticle: 'fades',
          value: clip.fadeInMs.toDouble(),
          min: 0,
          max: max,
          display: show,
          onChanged: (v) => editor.setClipFades(clip.id, fadeInMs: step(v)),
        ),
        LiveSlider(
          key: const ValueKey('clip-fade-out'),
          editor: editor,
          label: 'Fade out to black',
          value: clip.fadeOutMs.toDouble(),
          min: 0,
          max: max,
          display: show,
          onChanged: (v) => editor.setClipFades(clip.id, fadeOutMs: step(v)),
        ),
        Text(
          clip.type == ClipType.video
              ? 'The picture and this clip\'s sound fade together.'
                    '${first ? ' On the first clip this starts the video from black.' : ''}'
              : 'The photo fades from and to black.',
          style: _dim,
        ),
      ],
    );
  }
}

/// "Fade in from black" at the start and "Fade out to black" at the end of
/// the whole video (titles, overlays and all sound fade too).
class ProjectFadesPanel extends StatelessWidget {
  const ProjectFadesPanel({super.key, required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final editor = session.editor;
    final p = session.project;
    String show(double v) => v < 50 ? 'Off' : formatLength(v.round());
    int step(double v) => v < 50 ? 0 : (v / 100).round() * 100;
    final max = math.max(100.0, math.min(5000.0, p.durationMs / 2));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelLabel('Start and end of the video'),
        LiveSlider(
          key: const ValueKey('project-fade-in'),
          editor: editor,
          label: 'Fade in from black',
          helpArticle: 'fades',
          value: p.fadeInMs.toDouble(),
          min: 0,
          max: max,
          display: show,
          onChanged: (v) => editor.setProjectFades(fadeInMs: step(v)),
        ),
        LiveSlider(
          key: const ValueKey('project-fade-out'),
          editor: editor,
          label: 'Fade out to black',
          value: p.fadeOutMs.toDouble(),
          min: 0,
          max: max,
          display: show,
          onChanged: (v) => editor.setProjectFades(fadeOutMs: step(v)),
        ),
        const Text(
          'The whole video, with its titles and all its sound.',
          style: _dim,
        ),
      ],
    );
  }
}

/// "Transcribe speech…" and what follows from it, in a Sound panel
/// (computers only; the caller leaves it out when there is no speech
/// service).
class SpeechRow extends StatelessWidget {
  const SpeechRow({super.key, required this.session, this.clip});
  final EditorSession session;

  /// The clip whose sound it is about; null: the whole project.
  final Clip? clip;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Transcript>>(
      valueListenable: session.transcripts,
      builder: (context, _, _) {
        final cover = coverageOf(session, clipId: clip?.id);
        if (cover.sources.isEmpty) return const SizedBox.shrink();
        final has = !cover.none;
        return Padding(
          key: const ValueKey('speech-row'),
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('transcribe-button'),
                    onPressed: () =>
                        showTranscribeDialog(context, session, clip: clip),
                    icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                    label: const Text('Transcribe speech…'),
                  ),
                  const SizedBox(width: 4),
                  const HelpHint('transcribe-speech', label: 'Transcribe speech'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  has
                      ? 'Transcribed. Use it for captions or to remove '
                          'filler words.'
                      : 'Turns what is said into text, for captions and '
                          'more.',
                  style: _dim,
                ),
              ),
              if (has)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('speech-captions-button'),
                      onPressed: () => captionsFromSpeech(context, session),
                      child: const Text('Captions from speech…'),
                    ),
                    TextButton(
                      key: const ValueKey('fillers-button'),
                      onPressed: () => removeFillerWords(context, session),
                      child: const Text('Remove filler words…'),
                    ),
                    if (session.project.autoCuts.isNotEmpty)
                      TextButton(
                        key: const ValueKey('auto-cuts-button'),
                        onPressed: () => showAutoCuts(context, session),
                        child: const Text('Automatic cuts…'),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
