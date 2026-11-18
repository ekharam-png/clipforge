// Music: "Add music" (my files / find free music), "Fit music to video"
// and the music credits (1.8).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/editor/project_editor.dart' show FitMusicResult;
import '../../core/model/project.dart';
import '../../core/music/openverse.dart';
import '../format.dart';
import '../playback/timeline_player.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'import_actions.dart';
import 'session.dart';

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// Fit music to video ----------------------------------------------------------

/// "Fit music to video": the selected music ends with the video, with a
/// 2 s fade-out; music that is too short is offered a loop. One undo step.
Future<void> fitMusic(
    BuildContext context, EditorSession s, String audioId) async {
  s.playback.pause();
  final editor = s.editor.editor;
  var result = editor.fitMusicToVideo(audioId);
  if (result == FitMusicResult.tooShort) {
    final a = s.project.audio.where((a) => a.id == audioId).firstOrNull;
    if (a == null) return;
    final needed = s.project.durationMs - a.startMs;
    final loop = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('The music is shorter than the video'),
        content: Text(
            'The music plays for ${formatLength(a.passMs)} from where it '
            'starts, the video needs ${formatLength(needed)}. Loop it? It '
            'repeats with a short cross-fade at each repeat and fades out '
            'at the end.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Loop'),
          ),
        ],
      ),
    );
    if (loop != true || !context.mounted) return;
    result = editor.fitMusicToVideo(audioId, loop: true);
  }
  if (!context.mounted) return;
  _say(
      context,
      switch (result) {
        FitMusicResult.fitted =>
          'The music now ends with the video, with a 2-second fade-out.',
        FitMusicResult.looped =>
          'The music now repeats until the video ends, then fades out.',
        FitMusicResult.stoppedAtNext =>
          'Another sound comes later on the same track, so the music now '
              'stops just before it.',
        FitMusicResult.alreadyFits => 'The music already ends with the video.',
        FitMusicResult.startsAfterVideo =>
          'This music starts after the video has ended. Drag it earlier first.',
        FitMusicResult.tooShort => 'This music is too short to loop.',
        FitMusicResult.notFound => 'Select a piece of music first.',
      });
}

// Credits ---------------------------------------------------------------------

/// Copies the credits of all downloaded music, for a post's description.
Future<void> copyMusicCredits(BuildContext context, EditorSession s) async {
  final text = creditsText(s.project);
  if (text.isEmpty) {
    _say(context, 'No music from the free music search in this project.');
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    _say(context, 'Music credits copied. Paste them into your post.');
  }
}

/// How long the credits caption stays at the end of the video.
const int kCreditsCaptionMs = 4000;

/// Adds the short music credits as a small boxed title over the last
/// [kCreditsCaptionMs] of the video ("Added music credits").
void addCreditsTitle(BuildContext context, EditorSession s) {
  final text = creditsCaption(s.project);
  final end = s.project.durationMs;
  if (text.isEmpty || end <= 0) {
    _say(context, 'No music from the free music search in this project.');
    return;
  }
  final start = end > kCreditsCaptionMs ? end - kCreditsCaptionMs : 0;
  final id = const Uuid().v4();
  s.editor.editor.nameNextEdit('Added music credits');
  s.editor.addTitle(TitleOverlay(
    id: id,
    text: text,
    startMs: start,
    endMs: end,
    y: 0.88,
    fontSize: 0.035,
    background: true,
  ));
  s.select(ItemKind.title, id);
  _say(context, 'Credits added at the end of the video.');
}

/// The "Credits" part of the music panel: where the music came from, its
/// licence, Copy credits and Add credits at the end.
class MusicCreditPanel extends StatelessWidget {
  const MusicCreditPanel({super.key, required this.session, required this.audio});
  final EditorSession session;
  final AudioClip audio;

  @override
  Widget build(BuildContext context) {
    final c = audio.credit;
    if (c == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text('Credits', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(c.shortLine,
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text(
          c.needsCredit
              ? 'This licence asks you to credit the artist where you share '
                  'the video (in the post or at the end of the video).'
              : 'No credit is required for this music, but it is kind to '
                  'give one.',
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy credits'),
              onPressed: () => copyMusicCredits(context, session),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.subtitles_outlined, size: 18),
              label: const Text('Add credits at the end'),
              onPressed: () => addCreditsTitle(context, session),
            ),
          ],
        ),
      ],
    );
  }
}

// Add music -------------------------------------------------------------------

/// "Add music": a window with two tabs, **My files** (the file picker, as
/// before) and **Find free music** (search Openverse). Without a music
/// search (tests that do not set one) it goes straight to the picker.
Future<void> showAddMusic(BuildContext context, EditorSession s) async {
  s.playback.pause();
  if (!s.music.available) return addMusic(context, s);
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final pick = await showDialog<_AddMusicChoice>(
    context: context,
    builder: (dialog) {
      final body = _AddMusicWindow(session: s);
      return wide
          ? Dialog(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 640, maxHeight: 640),
                child: body,
              ),
            )
          : Dialog.fullscreen(child: body);
    },
  );
  if (pick == null || !context.mounted) return;
  if (pick.myFiles) return addMusic(context, s);
  final found = pick.found;
  if (found == null) return;
  await _downloadAndAdd(context, s, found);
}

class _AddMusicChoice {
  const _AddMusicChoice.myFiles()
      : myFiles = true,
        found = null;
  const _AddMusicChoice.found(this.found) : myFiles = false;
  final bool myFiles;
  final MusicResult? found;
}

Future<void> _downloadAndAdd(
    BuildContext context, EditorSession s, MusicResult r) async {
  String? path;
  String? problem;
  final progress = ValueNotifier<double?>(null);
  await whileBusy(context, 'Downloading ${r.title}…', () async {
    try {
      path = await s.music.download(r, await s.documents.mediaDir(),
          onProgress: (f) => progress.value = f);
    } on MusicSearchException catch (e) {
      problem = e.message;
    } catch (e) {
      problem = 'The music could not be downloaded ($e).';
    }
  });
  progress.dispose();
  if (!context.mounted) return;
  if (path == null) {
    _say(context, problem ?? 'The music could not be downloaded.');
    return;
  }
  final problems = await addMusicFiles(
      context, s, [PickedFile(path!, r.fileName)],
      credits: {path!: r.credit});
  if (!context.mounted) return;
  if (problems.isNotEmpty) {
    _say(context, problems.join('\n'));
    return;
  }
  _say(
      context,
      r.credit.needsCredit
          ? 'Added "${r.title}". Its licence (${r.licenceName}) asks for a '
              'credit: see Credits in the music panel.'
          : 'Added "${r.title}" (${r.licenceName}).');
}

class _AddMusicWindow extends StatelessWidget {
  const _AddMusicWindow({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add music'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'My files'),
            Tab(text: 'Find free music'),
          ]),
        ),
        body: TabBarView(children: [
          _MyFilesTab(),
          FreeMusicSearch(
            session: session,
            onUse: (r) =>
                Navigator.of(context).pop(_AddMusicChoice.found(r)),
          ),
        ]),
      ),
    );
  }
}

class _MyFilesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined,
                size: 48, color: AppColors.textDim),
            const SizedBox(height: 12),
            const Text('Music or sound files on this device (MP3, M4A, WAV…).',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose a music file…'),
              onPressed: () =>
                  Navigator.of(context).pop(const _AddMusicChoice.myFiles()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Find free music" tab: search box, licence switch, results with
/// title, artist, length and licence, a play button that streams a
/// preview, and **Use** (download and add).
class FreeMusicSearch extends StatefulWidget {
  const FreeMusicSearch({super.key, required this.session, required this.onUse});
  final EditorSession session;
  final void Function(MusicResult result) onUse;

  @override
  State<FreeMusicSearch> createState() => _FreeMusicSearchState();
}

class _FreeMusicSearchState extends State<FreeMusicSearch> {
  final _query = TextEditingController();
  bool _restricted = false;
  bool _busy = false;
  String? _problem;
  MusicSearchPage? _page;
  final List<MusicResult> _results = [];
  String? _playingId;
  TimelinePlayer? _player;
  int _search = 0;

  @override
  void dispose() {
    _query.dispose();
    _stopPreview();
    super.dispose();
  }

  Future<void> _run({bool more = false}) async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final my = ++_search;
    setState(() {
      _busy = true;
      _problem = null;
      if (!more) {
        _results.clear();
        _page = null;
      }
    });
    try {
      final page = await widget.session.music.search(q,
          includeRestricted: _restricted,
          page: more ? (_page?.page ?? 0) + 1 : 1);
      if (!mounted || my != _search) return;
      setState(() {
        _page = page;
        _results.addAll(page.results);
        if (_results.isEmpty) {
          _problem = 'Nothing found for "$q". Try other words, e.g. '
              '"happy ukulele", "piano", "summer".';
        }
      });
    } on MusicSearchException catch (e) {
      if (mounted && my == _search) setState(() => _problem = e.message);
    } catch (e) {
      if (mounted && my == _search) {
        setState(() => _problem = 'The search did not work ($e).');
      }
    } finally {
      if (mounted && my == _search) setState(() => _busy = false);
    }
  }

  Future<void> _togglePreview(MusicResult r) async {
    if (_playingId == r.id) {
      await _stopPreview();
      if (mounted) setState(() {});
      return;
    }
    await _stopPreview();
    final player = widget.session.backend.createAudioPlayer();
    _player = player;
    setState(() => _playingId = r.id);
    try {
      await player.open(r.url, positionMs: 0, play: true);
    } catch (_) {
      if (mounted && _playingId == r.id) {
        setState(() {
          _playingId = null;
          _problem = 'The preview could not be played (no connection?).';
        });
      }
    }
  }

  Future<void> _stopPreview() async {
    final p = _player;
    _player = null;
    _playingId = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _query,
            autofocus: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'Search free music (e.g. happy ukulele)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _run,
              ),
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Also show music with stricter licences'),
          subtitle: const Text(
            'Non-commercial (NC) or no-changes (ND) music may not be '
            'allowed in posts that earn money or under a video.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          value: _restricted,
          onChanged: (v) {
            setState(() => _restricted = v);
            if (_query.text.trim().isNotEmpty) _run();
          },
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_problem!, style: const TextStyle(color: AppColors.textDim)),
          ),
        Expanded(
          child: _results.isEmpty && _problem == null && !_busy
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Music from Openverse (Jamendo, Freesound, Wikimedia and '
                    'more) that you may use in your videos for free. Shown: '
                    'CC0, public domain, CC BY and CC BY-SA. Credit the '
                    'artist when the licence asks for it (ClipForge keeps '
                    'the credit with the music).',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length + (page?.hasMore == true ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _results.length) {
                      return Center(
                        child: TextButton(
                          onPressed: _busy ? null : () => _run(more: true),
                          child: const Text('More results'),
                        ),
                      );
                    }
                    final r = _results[i];
                    final playing = _playingId == r.id;
                    return ListTile(
                      key: ValueKey('music-${r.id}'),
                      leading: IconButton(
                        tooltip: playing ? 'Stop' : 'Listen',
                        icon: Icon(playing
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline),
                        onPressed: () => _togglePreview(r),
                      ),
                      title: Text(r.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (r.creator.isNotEmpty) r.creator,
                          if (r.durationMs > 0) formatDuration(r.durationMs),
                          r.licenceName,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () {
                          _stopPreview();
                          widget.onUse(r);
                        },
                        child: const Text('Use'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
