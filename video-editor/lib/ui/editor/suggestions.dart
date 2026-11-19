import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/editor/sound_tracks.dart';
import '../../core/model/project.dart';
import '../../media/sound_align.dart' show SoundRole, guessSoundRole;
import '../app_settings.dart';
import '../format.dart';
import '../help/help_screen.dart';
import '../theme.dart';
import 'clip_actions.dart';
import 'editor_actions.dart';
import 'import_actions.dart' show hasCaptions;
import 'music_actions.dart';
import 'session.dart';
import 'speech_actions.dart';
import 'voice_actions.dart' show lineUpVoice;

// Suggestions (1.15): ONE quiet line with a button, a ✕ and "Don't show
// again", when ClipForge sees something it can help with.
//
//  * One at a time, the one with the highest priority that applies.
//  * Never while the video plays, and never changed while a dialog or
//    sheet is open.
//  * Computers: a thin bar under the top bar. Phones: a thin line just
//    above the tool bar, which a swipe sends away.
//  * Settings > Suggestions > Show suggestions turns them all off
//    (AppPrefs flag `suggestionsOff`). "Don't show again" turns one off
//    for good (`hint.<id>.off`); ✕ or using the button closes it for this
//    project (`hint.<id>.<projectId>`), or for good when it is a
//    once-ever one (`hint.<id>.ever`).
//
// To add a suggestion: add one [Suggestion] to [kSuggestions] (an id, a
// priority, when it applies, what it says, its button), and a test in
// test/ui/suggestions_test.dart. Nothing else needs to know about it.
// A trigger must be cheap: it looks at the project and at what is already
// worked out (the sound pictures, the transcripts) and never starts an
// analysis.

/// How often a suggestion comes back once it was closed or used.
enum SuggestionScope {
  /// Again in another project.
  oncePerProject,

  /// Never again on this device.
  onceEver,
}

/// What a trigger may look at.
class SuggestionContext {
  SuggestionContext(this.session,
      {this.textOpened = false, List<({int startMs, int endMs})>? speech})
      // ignore: prefer_initializing_formals
      : _speech = speech;
  final EditorSession session;

  /// The Text window was opened at least once (ever).
  final bool textOpened;
  final List<({int startMs, int endMs})>? _speech;

  Project get project => session.project;

  /// Where someone talks on the timeline, as far as the sound pictures
  /// already know (empty until they are worked out, or with sound waves
  /// turned off). Never worked out for a suggestion's sake.
  List<({int startMs, int endMs})> get speech =>
      _speech ??
      [
        for (final t in session.pictures.speakers)
          for (final r in t.stretches) (startMs: r.startMs, endMs: r.endMs),
      ];
}

/// One button of a suggestion.
class SuggestionButton {
  const SuggestionButton(this.label, this.run);
  final String label;
  final void Function(BuildContext context, SuggestionContext c) run;
}

/// One entry of the registry.
class Suggestion {
  const Suggestion({
    required this.id,
    required this.priority,
    required this.when,
    required this.message,
    required this.buttons,
    this.scope = SuggestionScope.oncePerProject,
    this.icon = Icons.lightbulb_outline,
  });

  /// Never changes: the settings remember it.
  final String id;

  /// The highest that applies is shown.
  final int priority;
  final SuggestionScope scope;
  final IconData icon;

  /// True while the suggestion makes sense. Cheap: no analysis.
  final bool Function(SuggestionContext c) when;
  final String Function(SuggestionContext c) message;

  /// One button, or a few small ones.
  final List<SuggestionButton> Function(SuggestionContext c) buttons;
}

// Triggers --------------------------------------------------------------------

/// The music that does not end with the video: plays on for more than 2 s
/// after it, or starts at the beginning and stops more than 3 s before the
/// end. Short sounds (effects) and looped music are left alone.
AudioClip? musicToFit(Project p) {
  final end = p.durationMs;
  if (p.clips.isEmpty || end < 5000) return null;
  for (final a in p.audio) {
    if (a.belongsToClip || a.looped || a.durationMs < 10000) continue;
    if (a.startMs >= end) continue;
    if (a.endMs > end + 2000) return a;
    if (a.startMs <= math.max(2000, end ~/ 10) && a.endMs < end - 3000) {
      return a;
    }
  }
  return null;
}

/// A sound added as music that looks like a voice recording (its name, or
/// its length matching a video clip's file).
AudioClip? voiceAddedAsMusic(Project p) {
  final videos = [
    for (final c in p.clips)
      if (c.type == ClipType.video) c.sourceDurationMs,
  ];
  if (videos.isEmpty) return null;
  for (final a in p.audio) {
    if (a.belongsToClip) continue;
    if (guessSoundRole(fileName(a.path),
            durationMs: a.sourceDurationMs, videoDurationsMs: videos) ==
        SoundRole.voice) {
      return a;
    }
  }
  return null;
}

/// The first clip is small (under 720p) while the video takes its size
/// from it.
bool smallFirstClip(Project p) {
  if (p.videoSize != VideoSize.matchFirstClip || p.clips.isEmpty) return false;
  final c = p.clips.first;
  if (c.width <= 0 || c.height <= 0) return false;
  return math.min(c.width, c.height) < 700;
}

/// A clip whose shape is not the video's and which still sits between
/// bars (the selected one first).
Clip? clipOfOtherShape(EditorSession s) {
  final p = s.project;
  if (p.clips.isEmpty) return null;
  final canvas = p.canvasSize;
  final want = canvas.width / canvas.height;
  bool differs(Clip c) {
    if (c.width <= 0 || c.height <= 0) return false;
    if (c.fit != FitMode.fit || !c.framing.isDefault) return false;
    final turned = c.framing.rotation % 180 != 0;
    final a = turned ? c.height / c.width : c.width / c.height;
    return (a - want).abs() / want > 0.02;
  }

  final selected = s.selectedClip;
  if (selected != null && differs(selected)) return selected;
  for (final c in p.clips) {
    if (differs(c)) return c;
  }
  return null;
}

/// A long clip with talking and pauses, from what the sound pictures
/// already show: at least a minute long, speech in it, and 10 s or more of
/// pauses longer than 1.5 s between the speech.
Clip? clipWithPauses(SuggestionContext c) {
  final speech = c.speech;
  if (speech.isEmpty) return null;
  final p = c.project;
  for (var i = 0; i < p.clips.length; i++) {
    final clip = p.clips[i];
    if (clip.type != ClipType.video || !clip.hasAudio || clip.muted) continue;
    if (clip.durationMs < 60000) continue;
    final from = p.clipStartMs(i);
    final to = from + clip.durationMs;
    final inside = [
      for (final r in speech)
        if (r.endMs > from && r.startMs < to)
          (math.max(r.startMs, from), math.min(r.endMs, to)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (inside.isEmpty) continue;
    var pauses = 0;
    int at = from;
    for (final r in inside) {
      if (r.$1 - at > 1500) pauses += r.$1 - at;
      at = math.max(at, r.$2);
    }
    if (to - at > 1500) pauses += to - at;
    if (pauses >= 10000) return clip;
  }
  return null;
}

/// Music plays while someone talks (3 s or more), and not every music
/// track is lowered under speech.
bool musicOverSpeech(SuggestionContext c) {
  final p = c.project;
  if (lowerMusicState(p) == LowerMusic.all) return false;
  final speech = c.speech;
  if (speech.isEmpty) return false;
  final quiet = {
    for (final t in p.soundTracks)
      if (t.speech || t.duck) t.id,
  };
  var overlap = 0;
  for (final a in p.audio) {
    if (a.belongsToClip || quiet.contains(a.trackId)) continue;
    for (final r in speech) {
      final o = math.min(a.endMs, r.endMs) - math.max(a.startMs, r.startMs);
      if (o > 0) overlap += o.toInt();
      if (overlap >= 3000) return true;
    }
  }
  return false;
}

int _speechMs(SuggestionContext c) =>
    c.speech.fold(0, (n, r) => n + r.endMs - r.startMs);

void _select(EditorSession s, ItemKind kind, String id) {
  if (kind == ItemKind.clip) {
    s.selectClipAndShow(id);
  } else {
    s.select(kind, id);
  }
}

// The registry ----------------------------------------------------------------

/// Every suggestion the bar can show. (Three more "suggestions" are lines
/// in their own place and not in this list: the note about a long upright
/// video and the first-export line in the Export window, and "Updated to
/// X · What's new" on the project list.)
final List<Suggestion> kSuggestions = [
  Suggestion(
    id: 'voice-as-music',
    priority: 90,
    icon: Icons.record_voice_over_outlined,
    when: (c) => voiceAddedAsMusic(c.project) != null,
    message: (c) => 'This sound looks like a voice recorded separately.',
    buttons: (c) => [
      SuggestionButton('Line up with the picture', (context, c) {
        final a = voiceAddedAsMusic(c.project);
        if (a == null) return;
        _select(c.session, ItemKind.audio, a.id);
        lineUpVoice(context, c.session, a.id);
      }),
    ],
  ),
  Suggestion(
    id: 'fit-music',
    priority: 80,
    icon: Icons.library_music_outlined,
    when: (c) => musicToFit(c.project) != null,
    message: (c) {
      final a = musicToFit(c.project);
      return a != null && a.endMs > c.project.durationMs
          ? 'The music is longer than the video.'
          : 'The music stops before the video ends.';
    },
    buttons: (c) => [
      SuggestionButton('Fit to video', (context, c) {
        final a = musicToFit(c.project);
        if (a == null) return;
        _select(c.session, ItemKind.audio, a.id);
        fitMusic(context, c.session, a.id);
      }),
    ],
  ),
  Suggestion(
    id: 'lower-music',
    priority: 70,
    icon: Icons.volume_down_outlined,
    when: musicOverSpeech,
    message: (c) => 'Music plays while someone is talking.',
    buttons: (c) => [
      SuggestionButton('Lower the music',
          (context, c) => c.session.editor.setDuckMusic(true)),
    ],
  ),
  Suggestion(
    id: 'small-first-clip',
    priority: 60,
    icon: Icons.photo_size_select_large,
    when: (c) => smallFirstClip(c.project),
    message: (c) {
      final first = c.project.clips.first;
      return 'The first clip is small (${first.width}×${first.height}), '
          'and the video takes its size from it.';
    },
    buttons: (c) => [
      SuggestionButton('Use 1080p',
          (context, c) => c.session.editor.setVideoSize(VideoSize.p1080)),
    ],
  ),
  Suggestion(
    id: 'clip-shape',
    priority: 50,
    icon: Icons.aspect_ratio,
    when: (c) => clipOfOtherShape(c.session) != null,
    message: (c) => 'A clip has another shape than the video, so it gets '
        'bars.',
    buttons: (c) => [
      for (final (label, fit) in const [
        ('Fill', FitMode.fill),
        ('Blur', FitMode.blur),
      ])
        SuggestionButton(label, (context, c) {
          final clip = clipOfOtherShape(c.session);
          if (clip == null) return;
          _select(c.session, ItemKind.clip, clip.id);
          c.session.editor.setClipFit(clip.id, fit);
        }),
      SuggestionButton('Crop…', (context, c) {
        final clip = clipOfOtherShape(c.session);
        if (clip == null) return;
        _select(c.session, ItemKind.clip, clip.id);
        openCrop(context, c.session);
      }),
    ],
  ),
  Suggestion(
    id: 'remove-silences',
    priority: 40,
    icon: Icons.volume_off_outlined,
    when: (c) => clipWithPauses(c) != null,
    message: (c) => 'A long clip has pauses in the talking.',
    buttons: (c) => [
      SuggestionButton('Remove silences…', (context, c) {
        final clip = clipWithPauses(c);
        if (clip == null) return;
        _select(c.session, ItemKind.clip, clip.id);
        removeSilences(context, c.session, clip);
      }),
    ],
  ),
  Suggestion(
    id: 'captions-from-speech',
    priority: 30,
    icon: Icons.closed_caption_outlined,
    // Computers with speech-to-text only; needs talking and no captions.
    when: (c) =>
        c.session.speech != null &&
        canTranscribe(c.project) &&
        !hasCaptions(c.project) &&
        _speechMs(c) >= 5000,
    message: (c) => 'There is talking in this video and no captions yet.',
    buttons: (c) => [
      SuggestionButton('Captions from speech…',
          (context, c) => captionsFromSpeech(context, c.session)),
    ],
  ),
  Suggestion(
    id: 'open-text',
    priority: 20,
    icon: Icons.subject,
    scope: SuggestionScope.onceEver,
    when: (c) => !c.textOpened && hasCaptions(c.project),
    message: (c) => 'Text shows every caption in one place, to read, search '
        'and fix.',
    buttons: (c) => [
      SuggestionButton(
          'Open Text', (context, c) => toggleTextWindow(context, c.session)),
    ],
  ),
  Suggestion(
    id: 'who-is-speaking',
    priority: 10,
    icon: Icons.record_voice_over_outlined,
    scope: SuggestionScope.onceEver,
    when: (c) => c.project.audio.any((a) => a.isVoice),
    message: (c) => 'With a voice track, the timeline shows who is speaking '
        'when.',
    buttons: (c) => [
      SuggestionButton('See who is speaking',
          (context, c) => showHelpArticle(context, 'who-is-speaking')),
    ],
  ),
];

// Controller ------------------------------------------------------------------

/// Decides which suggestion the open editor shows.
class SuggestionController extends ChangeNotifier {
  SuggestionController({
    required this.session,
    required this.settings,
    required this.host,
    List<Suggestion>? registry,
  }) : registry = [...(registry ?? kSuggestions)]
          ..sort((a, b) => b.priority.compareTo(a.priority)) {
    session.editor.addListener(_schedule);
    session.playback.addListener(_schedule);
    session.pictures.addListener(_schedule);
    session.selection.addListener(_schedule);
    settings.addListener(_onSettings);
    _load();
  }

  final EditorSession session;
  final AppSettings settings;

  /// The editor's context (null once it is gone): the buttons act from it,
  /// and it tells whether a dialog is open.
  final BuildContext? Function() host;
  final List<Suggestion> registry;

  bool _disposed = false;
  bool _loaded = false;
  Timer? _timer;
  bool _textOpened = false;

  /// Closed for this project, closed for good, or turned off.
  final Set<String> _closed = {};

  Suggestion? _current;

  /// What the bar shows; null: nothing.
  Suggestion? get current =>
      session.playback.playing || !settings.suggestions ? null : _current;

  SuggestionContext get context =>
      SuggestionContext(session, textOpened: _textOpened);

  String _closedFlag(Suggestion s) => s.scope == SuggestionScope.onceEver
      ? 'hint.${s.id}.ever'
      : hintProjectFlag(s.id, session.project.id);

  Future<void> _load() async {
    final prefs = settings.prefs;
    try {
      await settings.load();
      _closed.clear();
      for (final s in registry) {
        if (await prefs.flag(hintOffFlag(s.id)) ||
            await prefs.flag(_closedFlag(s))) {
          _closed.add(s.id);
        }
      }
      _textOpened = await prefs.flag(kTextOpenedFlag);
    } catch (_) {
      // No memory: every suggestion may show.
    }
    if (_disposed) return;
    _loaded = true;
    evaluate();
  }

  void _onSettings() {
    // "Show hidden suggestions again" and the main switch.
    if (_disposed) return;
    _load();
    notifyListeners();
  }

  void _schedule() {
    if (_disposed) return;
    // Playback starting or stopping shows / hides the line at once.
    notifyListeners();
    _timer ??= Timer(const Duration(milliseconds: 400), () {
      _timer = null;
      evaluate();
    });
  }

  /// Picks the suggestion to show now. Leaves things as they are while the
  /// video plays or a dialog is open.
  void evaluate() {
    if (_disposed || !_loaded || session.isDisposed) return;
    if (session.playback.playing) return;
    final where = host();
    if (where == null || !where.mounted) return;
    if (!(ModalRoute.of(where)?.isCurrent ?? true)) return;
    Suggestion? next;
    if (settings.suggestions) {
      final c = context;
      for (final s in registry) {
        if (_closed.contains(s.id)) continue;
        bool applies;
        try {
          applies = s.when(c);
        } catch (_) {
          applies = false;
        }
        if (applies) {
          next = s;
          break;
        }
      }
    }
    if (!identical(next, _current)) {
      _current = next;
      notifyListeners();
    }
  }

  void _close(Suggestion s) {
    _closed.add(s.id);
    if (identical(_current, s)) _current = null;
    notifyListeners();
    settings.prefs.setFlag(_closedFlag(s)).catchError((Object _) {});
    // The next one, a moment later (not a line that flips under a finger).
    _schedule();
  }

  /// ✕ or a swipe: not again for this project (or ever, for a once-ever
  /// suggestion).
  void dismiss() {
    final s = _current;
    if (s != null) _close(s);
  }

  /// "Don't show again": this suggestion is off until Settings > "Show
  /// hidden suggestions again".
  Future<void> dontShowAgain() async {
    final s = _current;
    if (s == null) return;
    _closed.add(s.id);
    _current = null;
    notifyListeners();
    await settings.hideHint(s.id);
  }

  /// A button of the current suggestion was pressed.
  void act(SuggestionButton button) {
    final s = _current;
    final where = host();
    if (s == null || where == null || !where.mounted) return;
    final c = context;
    if (s.id == 'open-text') _textOpened = true;
    _close(s);
    button.run(where, c);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    session.editor.removeListener(_schedule);
    session.playback.removeListener(_schedule);
    session.pictures.removeListener(_schedule);
    session.selection.removeListener(_schedule);
    settings.removeListener(_onSettings);
    super.dispose();
  }
}

// The line --------------------------------------------------------------------

/// The suggestion line. Takes no room when there is nothing to suggest.
class SuggestionBar extends StatelessWidget {
  const SuggestionBar(
      {super.key, required this.controller, required this.phone});
  final SuggestionController controller;

  /// Phones: buttons at least 48 high, and a swipe sends the line away.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.current;
        if (s == null) return const SizedBox.shrink();
        final c = controller.context;
        final buttons = s.buttons(c);
        final buttonRow = [
          for (final b in buttons)
            TextButton(
              key: ValueKey('suggestion-${s.id}-${b.label}'),
              onPressed: () => controller.act(b),
              style: TextButton.styleFrom(
                minimumSize: Size(48, phone ? 48 : 32),
                tapTargetSize: phone ? null : MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontSize: 12.5),
              ),
              child: Text(b.label),
            ),
        ];
        // Phones: the words get the whole width, the button(s) a line of
        // their own under them.
        final below = phone;
        final row = Row(
          children: [
            Icon(s.icon, size: 16, color: const Color(0xFF9CC2FF)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  s.message(c),
                  key: const ValueKey('suggestion-text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            if (!below) ...buttonRow,
            if (!phone)
              TextButton(
                key: const ValueKey('suggestion-never'),
                onPressed: controller.dontShowAgain,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textDim,
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontSize: 12),
                ),
                child: const Text("Don't show again"),
              )
            else
              PopupMenuButton<int>(
                key: const ValueKey('suggestion-menu'),
                tooltip: 'More about this suggestion',
                icon: const Icon(Icons.more_vert,
                    size: 18,
                    color: AppColors.textDim,
                    semanticLabel: 'More about this suggestion'),
                onSelected: (_) => controller.dontShowAgain(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      key: ValueKey('suggestion-never'),
                      value: 0,
                      child: Text("Don't show again")),
                ],
              ),
            IconButton(
              key: const ValueKey('suggestion-close'),
              tooltip: 'Close this suggestion',
              constraints: BoxConstraints(
                  minWidth: phone ? 48 : 36, minHeight: phone ? 48 : 32),
              padding: EdgeInsets.zero,
              style: phone
                  ? null
                  : IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              icon: const Icon(Icons.close,
                  size: 16,
                  color: AppColors.textDim,
                  semanticLabel: 'Close this suggestion'),
              onPressed: controller.dismiss,
            ),
          ],
        );
        final line = Material(
          key: const ValueKey('suggestion-bar'),
          color: const Color(0xFF1F2A3A),
          child: Padding(
            padding: EdgeInsets.only(left: 12, right: phone ? 0 : 4),
            child: below
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row,
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(children: buttonRow),
                      ),
                    ],
                  )
                : row,
          ),
        );
        if (!phone) return line;
        return Dismissible(
          key: ValueKey('suggestion-swipe-${s.id}'),
          onDismissed: (_) => controller.dismiss(),
          child: line,
        );
      },
    );
  }
}
