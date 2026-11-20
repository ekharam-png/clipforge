// The publishing tools (1.14): suggest_shorts (candidate passages for
// Claude to judge - the helper has no AI and judges nothing),
// set_publishing_notes / get_publishing_notes, make_chapters, export_kit
// (several files for several destinations as ONE background job) and the
// "good moment" markers. Part of tools.dart.
part of 'tools.dart';

const int kDefaultShortCandidates = 20;
const int kMaxShortCandidates = 100;

extension _PublishTools on ClipForgeTools {
  List<ToolDef> get _publishToolDefs => [
        ToolDef(
          name: 'suggest_shorts',
          title: 'Candidate passages for shorts',
          description:
              'Lists CANDIDATE passages a short could be made of, for YOU '
              'to judge: this tool has no AI and does not know what is '
              'interesting. It reads the transcript (or, without one, the '
              'captions) as it is cut now and groups it into self-contained '
              'passages of whole sentences between min_seconds and '
              'max_seconds long, starting after a pause or when another '
              'speaker takes over. Each has from_ms / to_ms (pass them to '
              'make_short), the speaker(s), the text and simple signals: '
              'starts with a question, has a question, figures are said, '
              'stands by itself (pause before / after), and - when the '
              'sound can be read - how much louder than usual the talk '
              'gets (emphasis, laughter). Candidates may overlap. Read '
              'them, pick 3-5 by the rules in get_guide recipes ("From a '
              'long video to a publishing kit": a hook in the first 3 '
              'seconds, one idea, a complete thought, ends on a point, no '
              'references to things said elsewhere), propose them to the '
              'user with one line of reason each, and make them only after '
              'the user chose. Paged: offset / limit.',
          properties: {
            'project_id': _projectId,
            'min_seconds': _int('Shortest passage. Default 15.', min: 5, max: 600),
            'max_seconds': _int('Longest passage. Default $kShortMaxSeconds '
                '(safe for Shorts, Reels and TikTok).', min: 10, max: 900),
            'source': _str('"auto" (default: the transcript when there is '
                'one, else the captions), "transcript" or "captions".',
                values: const ['auto', 'transcript', 'captions']),
            'from_ms': _int('Only passages that start at or after this '
                'time, in ms.', min: 0),
            'to_ms': _int('Only passages that end at or before this time, '
                'in ms.', min: 0),
            'loudness': _bool('Listen to the sound for the emphasis signal '
                '(the first call reads each file once). Default true.'),
            'offset': _int('Skip this many candidates.', min: 0),
            'limit': _int(
                'At most this many (default $kDefaultShortCandidates, at '
                'most $kMaxShortCandidates).',
                min: 1,
                max: kMaxShortCandidates),
          },
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          openWorld: true,
          handler: _suggestShorts,
        ),
        ToolDef(
          name: 'get_publishing_notes',
          title: 'Read the publishing notes',
          description:
              'The text that goes with the video when the user posts it: '
              'title, description, hashtags, chapters, the optional short '
              'title and description for Shorts / Reels / TikTok, and the '
              'credits of free music. Also shows the text file export_kit '
              'writes next to the videos. ClipForge never posts anything: '
              'the user pastes these themselves.',
          properties: {'project_id': _projectId},
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _getPublishingNotes,
        ),
        ToolDef(
          name: 'set_publishing_notes',
          title: 'Write the publishing notes',
          description:
              'Sets the publishing notes of a project (the app shows them '
              'in Publishing notes, each with a Copy button, and writes '
              'them into the kit\'s text file). Only the arguments given '
              'change; "" clears one. Give the user 3 title options and '
              'let them pick before setting the title. hashtags: words '
              'with or without "#", at most $kMaxHashtags. chapters: lines '
              '"0:00 Title" (see make_chapters for a start). One undo '
              'step.$_editNote',
          properties: {
            'project_id': _projectId,
            'title': _str('The title of the post.'),
            'description': _str('The description (plain text, line breaks '
                'allowed).'),
            'hashtags': _str('Hashtags / tags, separated by spaces or '
                'commas ("bread, baking #sourdough").'),
            'chapters': _str('The chapter list, one "m:ss Title" per line; '
                '"" removes it. The answer warns when it breaks the rules '
                '(first at 0:00, at least 3, each at least 10 s).'),
            'short_title': _str('Title for Shorts / Reels / TikTok when it '
                'should differ.'),
            'short_description': _str('Description for short-form posts '
                'when it should differ.'),
          },
          required: const ['project_id'],
          handler: _setPublishingNotes,
        ),
        ToolDef(
          name: 'make_chapters',
          title: 'Chapters from titles or captions',
          description:
              'Builds a YouTube-style chapter list for the project as it '
              'is cut now and stores it in the publishing notes: from its '
              'titles (one chapter where each title appears); without '
              'titles from its captions (where the speaker changes or '
              'talk starts again after a pause, named by the first words); '
              'without captions from who speaks when (the sound). The '
              'rules are kept: first chapter at 0:00, none shorter than '
              '${kChapterRules.minGapMs ~/ 1000} s, at most '
              '${kChapterRules.maxAutomatic} automatic ones. dry_run true '
              'shows the list without saving - do that first, improve the '
              'titles with what you read in the transcript, then save the '
              'final list with set_publishing_notes chapters. Existing '
              'chapters are only replaced with replace true.$_editNote',
          properties: {
            'project_id': _projectId,
            'dry_run': _bool('true: show the list, save nothing. Default '
                'false.'),
            'replace': _bool('Replace chapters the notes already have. '
                'Default false.'),
          },
          required: const ['project_id'],
          openWorld: true,
          handler: _makeChapters,
        ),
        ToolDef(
          name: 'export_kit',
          title: 'Export a publishing kit',
          description:
              'Exports several files for several destinations into ONE '
              'kit folder as one background job (like export_video: it '
              'waits up to wait_seconds, then answers with a job_id; '
              'follow it with get_export_status, stop it with '
              'cancel_export). Destinations: "youtube" (16:9, 1080p), '
              '"shorts" (9:16, 1080p, for Shorts / Reels / TikTok), '
              '"instagram" (4:5) or "instagram:1x1", "whatsapp" (small '
              'file), "podcast" (MP3) or "podcast:m4a". A destination '
              'whose shape differs from the project\'s gets a temporary '
              'copy in that shape with the blurred background (the '
              'project itself is not changed and no project is added); '
              'for a short made with make_short the shape already fits. '
              'Files are named "<Project> - YouTube.mp4", "<Project> - '
              'Short 9x16.mp4", "<Project> - WhatsApp.mp4", "<Project> - '
              'audio.mp3", and "<Project> - text.txt" holds the publishing '
              'notes with what to paste where. projects lets one kit hold '
              'the long video and its shorts. The answer has the folder '
              'and every file with its size; warnings say when a file is '
              'longer or bigger than its destination is sure to take. '
              'Tell the user where the folder is and what to paste where: '
              'ClipForge never uploads anything.',
          properties: {
            'project_id': _projectId,
            'destinations': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Destinations for project_id, e.g. '
                  '["youtube", "podcast"].',
            },
            'projects': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'project_id': {'type': 'string'},
                  'destinations': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'required': ['project_id', 'destinations'],
              },
              'description': 'More projects for the same kit folder, each '
                  'with its destinations (the shorts: [{"project_id": '
                  '"…", "destinations": ["shorts"]}]).',
            },
            'output_dir': _str('Full path of the kit folder. Default: '
                '"<name of the first project> kit" in the "exports" folder '
                'next to the projects folder.'),
            'overwrite': _bool('Replace files of the same name in the '
                'folder. Default false.'),
            'hardware': _bool('Use the graphics card when possible. '
                'Default true.'),
            'wait_seconds': _int(
                'How long to wait before answering with the job, '
                '0..$kMaxStatusWait. Default $kDefaultExportWait.',
                min: 0,
                max: kMaxStatusWait),
          },
          required: const ['project_id'],
          openWorld: false,
          handler: _exportKit,
        ),
        ToolDef(
          name: 'add_marker',
          title: 'Mark a good moment',
          description:
              'Drops a "good moment" marker at a time of the finished '
              'video (the app shows it on the time ruler; the user drops '
              'them with the M key while watching). Markers follow their '
              'picture through cuts. The app\'s "Make shorts from '
              'markers…" uses them; list_markers gives the part a short '
              'around each would take.$_editNote',
          properties: {
            'project_id': _projectId,
            'at_ms': _int('Where, in ms on the timeline.', min: 0),
            'label': _str('A few words about why (optional).'),
          },
          required: const ['project_id', 'at_ms'],
          handler: _addMarker,
        ),
        ToolDef(
          name: 'list_markers',
          title: 'List the good-moment markers',
          description:
              'The "good moment" markers of a project in time order, each '
              'with its marker_id, time, label and - when there is a '
              'transcript or captions - what is said there, plus the part '
              'a short around it would take (snapped to pauses).',
          properties: {'project_id': _projectId},
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _listMarkers,
        ),
        ToolDef(
          name: 'remove_marker',
          title: 'Remove a marker',
          description:
              'Removes one "good moment" marker (marker_id from '
              'list_markers), or all of them with "all". Nothing else '
              'changes.$_editNote',
          properties: {
            'project_id': _projectId,
            'marker_id': _str('The marker\'s id, or "all".'),
          },
          required: const ['project_id', 'marker_id'],
          handler: _removeMarker,
        ),
      ];

  // What is said, and where the pauses are -----------------------------------

  /// What is said on the timeline of [loaded]: the words of the transcript
  /// when the project has one ([source] "auto" / "transcript"), else its
  /// captions.
  Future<({List<Spoken> items, String source})> _spokenOf(_Loaded loaded,
      {String source = 'auto'}) async {
    final project = loaded.project;
    if (source != 'captions') {
      final s = await _speechOf(loaded);
      if (s.cover.sources.isNotEmpty && !s.cover.none) {
        final words = timelineWords(project, s.lookup);
        if (words.isNotEmpty) {
          return (
            items: [
              for (final w in words)
                Spoken(w.startMs, w.endMs, w.text, w.speaker),
            ],
            source: 'transcript',
          );
        }
      }
      if (source == 'transcript') {
        throw ToolError('"${project.name}" has no transcript for the part '
            'that is on the timeline. Call transcribe first, or use source '
            '"captions".');
      }
    }
    return (
      items: [
        for (final l in captionLines(project))
          Spoken(l.startMs, l.endMs, l.text, l.speaker),
      ],
      source: 'captions',
    );
  }

  /// The sound pictures of the files that carry speech (as get_speech_map
  /// reads them); empty when FFmpeg or the files are not there.
  Future<Map<String, SoundPeaks>> _speechPeaks(Project project) async {
    final speechIds = {
      for (final t in project.soundTracks)
        if (t.speech) t.id,
    };
    final wanted = <String, ({String path, int track})>{};
    for (final s in project.audio) {
      if (!speechIds.contains(s.trackId) || s.looped) continue;
      final t = s.soundClip.audioTrackInUse;
      wanted['${s.path}|$t'] = (path: s.path, track: t);
    }
    if (wanted.isEmpty) {
      for (final c in project.clips) {
        if (c.type != ClipType.video || !c.hasAudio || c.muted) continue;
        wanted['${c.path}|${c.audioTrackInUse}'] =
            (path: c.path, track: c.audioTrackInUse);
      }
    }
    final peaks = <String, SoundPeaks>{};
    if (wanted.isEmpty) return peaks;
    try {
      final engine = await media.requireEngine();
      for (final e in wanted.entries) {
        if (!File(e.value.path).existsSync()) continue;
        try {
          final found = await engine.soundPeaks(e.value.path,
              audioTrack: e.value.track, cacheDir: _peaksDir);
          if (found != null) peaks[e.key] = found;
        } on ExportException {
          // That file stays out.
        }
      }
    } catch (_) {
      // No FFmpeg: no sound pictures.
    }
    return peaks;
  }

  /// The pauses of the timeline: between the talk of every speaker when
  /// the sound can be read, else between what is [spoken].
  Future<({List<Span> pauses, bool fromSound})> _pausesOf(
      Project project, List<Spoken> spoken) async {
    final peaks = await _speechPeaks(project);
    if (peaks.isNotEmpty) {
      final tracks =
          speakerTracks(project, (path, track) => peaks['$path|$track']);
      final talk = [
        for (final t in tracks) ...t.stretches,
      ];
      if (talk.isNotEmpty) {
        return (
          pauses: pausesBetween(talk, project.durationMs),
          fromSound: true,
        );
      }
    }
    return (
      pauses: pausesBetween([
        for (final s in spoken) (startMs: s.startMs, endMs: s.endMs),
      ], project.durationMs),
      fromSound: false,
    );
  }

  // suggest_shorts -----------------------------------------------------------

  Future<ToolResult> _suggestShorts(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    final r = _range(a);
    final minS = ClipForgeTools._i(a, 'min_seconds') ?? 15;
    final maxS = ClipForgeTools._i(a, 'max_seconds') ?? kShortMaxSeconds;
    if (maxS < minS) {
      throw ToolError('max_seconds ($maxS) must not be less than '
          'min_seconds ($minS).');
    }
    final offset = ClipForgeTools._i(a, 'offset') ?? 0;
    final limit = (ClipForgeTools._i(a, 'limit') ?? kDefaultShortCandidates)
        .clamp(1, kMaxShortCandidates);
    final spoken =
        await _spokenOf(loaded, source: (a['source'] as String?) ?? 'auto');
    if (spoken.items.isEmpty) {
      throw ToolError('"${project.name}" has no transcript and no captions, '
          'so there is no text to find passages in. Call transcribe (then '
          'this again), or import_srt. Without any text, make shorts from '
          'times the user gives, from list_markers, or from the speaker '
          'turns of get_speech_map.');
    }
    var all = shortCandidates(spoken.items,
        minMs: minS * 1000, maxMs: maxS * 1000);
    all = [
      for (final c in all)
        if ((r.from == null || c.startMs >= r.from!) &&
            (r.to == null || c.endMs <= r.to!))
          c,
    ];
    final from = offset.clamp(0, all.length);
    final to = (from + limit).clamp(from, all.length);
    final page = all.sublist(from, to);
    final next = to < all.length ? to : null;
    Map<String, SoundPeaks> peaks = const {};
    if (a['loudness'] != false && page.isNotEmpty) {
      peaks = await _speechPeaks(project);
    }
    final marked = page.isEmpty || page.first.completeSentences;
    final text = StringBuffer()
      ..writeln('${all.length} candidate passage(s) of $minS-$maxS s in '
          '"${project.name}" (${_mss(project.durationMs)} long), from its '
          '${spoken.source}'
          '${all.isEmpty ? '' : '; ${from + 1}-$to shown'}. '
          'These are CANDIDATES, not recommendations: read them and judge. '
          'Times are ms on the timeline.'
          '${marked ? ' Every one starts at the beginning of a sentence and ends at the end of one.' : ' The text has no sentence marks, so starts and ends are at pauses - read the first and last words before using one.'}');
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < page.length; i++) {
      final c = page[i];
      final loud = peaks.isEmpty
          ? null
          : emphasisDb(project, (path, track) => peaks['$path|$track'],
              c.startMs, c.endMs);
      final signals = <String>[
        if (c.startsWithQuestion)
          'starts with a question'
        else if (c.hasQuestion)
          'has a question',
        if (c.hasNumbers) 'figures',
        if (c.afterPause && c.beforePause)
          'stands by itself'
        else if (c.afterPause)
          'pause before'
        else if (c.beforePause)
          'pause after',
        if (loud != null && loud >= 3) 'louder than usual (+${loud.round()} dB)',
      ];
      final who = c.speakers.where((s) => s.isNotEmpty).join(', ');
      text
        ..writeln()
        ..writeln('${from + i + 1}. ${c.startMs}-${c.endMs} '
            '[${_mss(c.startMs)}-${_mss(c.endMs)}] '
            '${(c.durationMs / 1000).round()} s'
            '${who.isEmpty ? '' : ', $who'}'
            '${signals.isEmpty ? '' : ' | ${signals.join(', ')}'}')
        ..writeln(c.text);
      rows.add({
        'fromMs': c.startMs,
        'toMs': c.endMs,
        'seconds': (c.durationMs / 1000).round(),
        if (who.isNotEmpty) 'speakers': c.speakers,
        'sentences': c.sentences,
        'startsWithQuestion': c.startsWithQuestion,
        'hasNumbers': c.hasNumbers,
        'pauseBefore': c.afterPause,
        'pauseAfter': c.beforePause,
        'completeSentences': c.completeSentences,
        if (loud != null) 'emphasisDb': double.parse(loud.toStringAsFixed(1)),
        'text': c.text,
      });
    }
    if (all.isEmpty) {
      text.writeln('Nothing fits: try a wider min_seconds / max_seconds, '
          'or read get_transcript and choose the times yourself.');
    }
    if (next != null) text.writeln('\nMore: call again with offset $next.');
    text.writeln('\nNext: propose 3-5 to the user with one line of reason '
        'each; after they chose, make_short with from_ms / to_ms, '
        'caption_style "short" and a title.');
    return ToolResult(text.toString().trimRight(), structured: {
      'projectId': project.id,
      'source': spoken.source,
      'total': all.length,
      'offset': from,
      'count': page.length,
      'nextOffset': ?next,
      'candidates': rows,
    });
  }

  // Publishing notes ---------------------------------------------------------

  String _notesText(Project project) {
    final n = project.publishing;
    if (n.isEmpty) {
      return '"${project.name}" has no publishing notes yet. '
          'set_publishing_notes writes them (title, description, hashtags, '
          'chapters); make_chapters proposes chapters.';
    }
    return 'Publishing notes of "${project.name}":\n'
        '${kitText(project).trimRight()}';
  }

  Map<String, dynamic> _notesJson(Project project) {
    final n = project.publishing;
    final credits = creditsText(project);
    return {
      'title': n.title,
      'description': n.description,
      'hashtags': n.hashtags,
      'chapters': [
        for (final c in n.chapters)
          {'ms': c.ms, 'time': chapterTime(c.ms), 'title': c.title},
      ],
      'shortTitle': n.shortTitle,
      'shortDescription': n.shortDescription,
      if (credits.isNotEmpty) 'musicCredits': credits,
    };
  }

  Future<ToolResult> _getPublishingNotes(
      Map<String, dynamic> a, ToolCall call) async {
    final project = (await _load(a['project_id'])).project;
    final problems =
        chapterProblems(project.publishing.chapters, project.durationMs);
    return ToolResult(
        '${_notesText(project)}'
        '${problems.isEmpty ? '' : '\nChapters: ${problems.join(' ')}'}',
        structured: {
          'projectId': project.id,
          'empty': project.publishing.isEmpty,
          'notes': _notesJson(project),
          'textFileName': kitTextFileName(project.name),
          if (problems.isNotEmpty) 'chapterProblems': problems,
        });
  }

  Future<ToolResult> _setPublishingNotes(Map<String, dynamic> a, ToolCall call) {
    const keys = [
      'title', 'description', 'hashtags', 'chapters', //
      'short_title', 'short_description',
    ];
    if (!keys.any(a.containsKey)) {
      throw ToolError('Give at least one of: ${keys.join(', ')}.');
    }
    return _edit(a, (e) {
      final old = e.project.publishing;
      String? s(String k) => a.containsKey(k) ? '${a[k] ?? ''}' : null;
      final chapters = s('chapters');
      final parsed = chapters == null ? null : parseChapters(chapters);
      if (chapters != null && chapters.trim().isNotEmpty && parsed!.isEmpty) {
        throw ToolError('chapters has no line of the form "m:ss Title".');
      }
      final next = old.copyWith(
        title: s('title')?.trim(),
        description: s('description')?.trim(),
        hashtags: s('hashtags') == null ? null : parseHashtags(s('hashtags')!),
        chapters: parsed,
        shortTitle: s('short_title')?.trim(),
        shortDescription: s('short_description')?.trim(),
      );
      e.setPublishingNotes(next);
      final problems = chapterProblems(next.chapters, e.project.durationMs);
      return _Done(
          'Updated the publishing notes '
          '(${publishingChange(old, next) ?? 'nothing differs'}).\n'
          '${_notesText(e.project)}',
          {
            'notes': _notesJson(e.project),
            if (problems.isNotEmpty)
              '_warnings': ['Chapters: ${problems.join(' ')}'],
          });
    });
  }

  Future<ToolResult> _makeChapters(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    // Only when there is nothing written to go by: who speaks when.
    var turns = const <({String name, int startMs, int endMs})>[];
    final hasText = project.titles.any((t) => t.text.trim().isNotEmpty);
    if (!hasText) {
      final peaks = await _speechPeaks(project);
      if (peaks.isNotEmpty) {
        turns = [
          for (final t in speakerTurns(speakerTracks(
              project, (path, track) => peaks['$path|$track'])))
            (name: t.name, startMs: t.startMs, endMs: t.endMs),
        ];
      }
    }
    final built = buildChapters(project, turns: turns);
    final from = switch (built.source) {
      ChapterSource.titles => 'its titles',
      ChapterSource.captions => 'its captions',
      ChapterSource.speakers => 'who speaks when (the sound)',
      ChapterSource.none => 'nothing',
    };
    if (built.chapters.isEmpty) {
      throw ToolError('No chapters could be made for "${project.name}": it '
          'has no titles, no captions and no speech that could be read, or '
          'it is too short (a chapter is at least '
          '${kChapterRules.minGapMs ~/ 1000} s). Write them yourself with '
          'set_publishing_notes chapters.');
    }
    final had = project.publishing.chapters;
    final dryRun = a['dry_run'] == true;
    if (had.isNotEmpty && a['replace'] != true && !dryRun) {
      throw ToolError('The notes already have ${had.length} chapter(s); '
          'nothing was changed. Pass replace true to replace them, or '
          'dry_run true to see the new list.');
    }
    final problems = chapterProblems(built.chapters, project.durationMs);
    return _edit(a, (e) {
      e.setPublishingNotes(
          e.project.publishing.copyWith(chapters: built.chapters));
      return _Done(
          'Made ${built.chapters.length} chapter(s) from $from:\n'
          '${formatChapters(built.chapters)}\n'
          '${built.source == ChapterSource.titles ? '' : 'The titles are only the first words said: rewrite them from what the part is about (set_publishing_notes chapters).'}',
          {
            'source': built.source.name,
            'chapters': [
              for (final c in built.chapters)
                {'ms': c.ms, 'time': chapterTime(c.ms), 'title': c.title},
            ],
            if (problems.isNotEmpty)
              '_warnings': ['Chapters: ${problems.join(' ')}'],
          });
    });
  }

  // Markers ------------------------------------------------------------------

  Future<ToolResult> _addMarker(Map<String, dynamic> a, ToolCall call) {
    final at = ClipForgeTools._i(a, 'at_ms')!;
    return _edit(a, (e) {
      if (at > e.project.durationMs) {
        throw ToolError('at_ms ($at) is after the end of the video '
            '(${e.project.durationMs} ms).');
      }
      final id = e.addMarker(at, label: (a['label'] as String?) ?? '');
      if (id == null) {
        return _Done('No marker was added: there is already one within '
            '0.2 s of ${_mss(at)}, the project has no clips, or it has '
            '${ProjectEditor.maxMarkers} markers.');
      }
      return _Done('Added a good-moment marker at ${_mss(at)} (marker_id $id).',
          {'markerId': id, 'atMs': at});
    });
  }

  Future<ToolResult> _removeMarker(Map<String, dynamic> a, ToolCall call) {
    final id = '${a['marker_id']}'.trim();
    return _edit(a, (e) {
      final markers = e.project.markers;
      if (id == 'all') {
        if (markers.isEmpty) return _Done('There are no markers.');
        e.transaction(() {
          for (final m in markers) {
            e.removeMarker(m.id);
          }
        });
        return _Done('Removed ${markers.length} marker(s).',
            {'removed': markers.length});
      }
      if (!e.removeMarker(id)) {
        throw ToolError('No marker "$id". Markers: '
            '${markers.isEmpty ? 'none' : markers.map((m) => '${m.id} (${_mss(m.ms)})').join(', ')}.');
      }
      return _Done('Removed the marker.', {'removed': 1});
    });
  }

  Future<ToolResult> _listMarkers(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    if (project.markers.isEmpty) {
      return ToolResult(
          '"${project.name}" has no good-moment markers. The user drops '
          'them in the app with the M key (phones: More > Mark a good '
          'moment); add_marker adds one.',
          structured: {'projectId': project.id, 'markers': <Object>[]});
    }
    final spoken = await _spokenOf(loaded);
    final pauses = await _pausesOf(project, spoken.items);
    final words = [
      for (final s in spoken.items) (startMs: s.startMs, endMs: s.endMs),
    ];
    final text = StringBuffer()
      ..writeln('${project.markers.length} good-moment marker(s) in '
          '"${project.name}" (${_mss(project.durationMs)} long). "short" is '
          'the part a short around the marker would take '
          '(${kMarkerBeforeMs ~/ 1000} s before to ${kMarkerAfterMs ~/ 1000} '
          's after - less in a video under a minute - moved outward to '
          'pauses).');
    final rows = <Map<String, dynamic>>[];
    final ranges = <Span>[];
    for (final m in project.markers) {
      final range = markerRange(m.ms, project.durationMs);
      final snapped = snapShortRange(range.startMs, range.endMs,
          pauses: pauses.pauses, words: words, totalMs: project.durationMs);
      final said = [
        for (final s in spoken.items)
          if (s.endMs > m.ms - 2500 && s.startMs < m.ms + 4000) s.text.trim(),
      ].join(' ');
      text.writeln('- marker_id ${m.id} at ${m.ms} [${_mss(m.ms)}]'
          '${m.label.isEmpty ? '' : ' "${m.label}"'}; short '
          '${snapped.fromMs}-${snapped.toMs}'
          '${said.isEmpty ? '' : '; said there: "${said.length > 140 ? '${said.substring(0, 139)}…' : said}"'}');
      rows.add({
        'markerId': m.id,
        'atMs': m.ms,
        if (m.label.isNotEmpty) 'label': m.label,
        'shortFromMs': snapped.fromMs,
        'shortToMs': snapped.toMs,
      });
      ranges.add((startMs: snapped.fromMs, endMs: snapped.toMs));
    }
    // Markers close together: say so, with the one range that covers
    // them, so that as many shorts are made as were announced.
    final together = <Map<String, dynamic>>[];
    for (final g in overlappingGroups(ranges)) {
      if (g.length < 2) continue;
      final from =
          g.map((i) => ranges[i].startMs).reduce((a, b) => a < b ? a : b);
      final to = g.map((i) => ranges[i].endMs).reduce((a, b) => a > b ? a : b);
      text.writeln('Note: the shorts of markers '
          '${g.map((i) => project.markers[i].id).join(', ')} overlap by more '
          'than ${(kMarkerOverlapShare * 100).round()} %: they would show '
          'mostly the same part. Ask the user: one short covering them '
          '($from-$to) or one each. Tell the user how many shorts you '
          'made.');
      together.add({
        'markerIds': [for (final i in g) project.markers[i].id],
        'oneShortFromMs': from,
        'oneShortToMs': to,
      });
    }
    return ToolResult(text.toString().trimRight(), structured: {
      'projectId': project.id,
      'markers': rows,
      if (together.isNotEmpty) 'overlapping': together,
    });
  }

  // export_kit ---------------------------------------------------------------

  List<KitChoice> _choices(Object? raw, String what) {
    final list = raw is List ? raw : const <Object?>[];
    if (list.isEmpty) {
      throw ToolError('$what needs at least one destination: '
          '${kitChoices().map((c) => c.key).join(', ')}.');
    }
    final out = <KitChoice>[];
    for (final k in list) {
      final c = kitChoiceByKey('$k');
      if (c == null) {
        throw ToolError('Unknown destination "$k". Destinations: '
            '${kitChoices().map((c) => c.key).join(', ')}, podcast:m4a.');
      }
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  Future<ToolResult> _exportKit(Map<String, dynamic> a, ToolCall call) async {
    final parts = <KitJobPart>[];
    {
      final loaded = await _load(a['project_id']);
      parts.add(KitJobPart(
          loaded.project, _choices(a['destinations'], 'destinations')));
    }
    for (final x in (a['projects'] as List?) ?? const []) {
      if (x is! Map) continue;
      final loaded = await _load(x['project_id']);
      if (parts.any((p) => p.project.id == loaded.project.id)) {
        throw ToolError('The project "${loaded.project.name}" is named '
            'twice; give each project once with all its destinations.');
      }
      parts.add(KitJobPart(loaded.project,
          _choices(x['destinations'], 'projects[].destinations')));
    }
    final names = <String>{};
    for (final part in parts) {
      final project = part.project;
      if (project.clips.isEmpty) {
        throw ToolError('The project "${project.name}" has no clips, so '
            'there is nothing to export.');
      }
      if (!names.add(kitSafeName(project.name).toLowerCase())) {
        throw ToolError('Two projects of this kit are called '
            '"${project.name}": their files would get the same names. '
            'Rename one (set_project_settings name) first.');
      }
      final missing = <String>{
        for (final c in project.clips)
          if (!File(c.path).existsSync()) c.path,
        for (final x in project.audio)
          if (!File(x.path).existsSync()) x.path,
        for (final o in project.overlays)
          if (!File(o.path).existsSync()) o.path,
      };
      if (missing.isNotEmpty) {
        throw ToolError('Cannot export "${project.name}": '
            '${missing.length} media file(s) are missing: '
            '${missing.join('; ')}');
      }
    }
    final hardware = a['hardware'] != false;
    final plans = [
      for (final part in parts)
        planKit(part.project, part.choices, useHardwareEncoder: hardware),
    ];
    final first = parts.first.project;
    var folder = a['output_dir'] == null
        ? p.join(p.dirname(store.rootPath), 'exports',
            '${kitSafeName(first.name)} kit')
        : ClipForgeTools._path(a['output_dir'], 'output_dir');
    if (FileSystemEntity.typeSync(folder) == FileSystemEntityType.file) {
      throw ToolError('output_dir "$folder" is a file; give a folder.');
    }
    folder = p.normalize(folder);
    final overwrite = a['overwrite'] == true;
    final clashes = <String>[
      for (final plan in plans)
        for (final name in [
          for (final i in plan.items) i.fileName,
          plan.textFileName,
        ])
          if (File(p.join(folder, name)).existsSync()) name,
    ];
    if (clashes.isNotEmpty && !overwrite) {
      throw ToolError('"$folder" already holds ${clashes.take(4).join(', ')}'
          '${clashes.length > 4 ? ', …' : ''}. Pass overwrite true to '
          'replace them, or another output_dir.');
    }
    final all = jobs.list();
    for (final r in all) {
      if (r.isActive && p.equals(r.outputPath, folder)) {
        final v = await viewJob(r);
        if (v.status != kJobLost) {
          throw ToolError('A kit is already being exported into "$folder" '
              '(job_id ${r.id}). Follow it with get_export_status.');
        }
      }
    }
    String? ffmpegPath, ffprobePath;
    if (exportLauncher.needsFfmpeg) {
      final engine = await media.requireEngine();
      ffmpegPath = engine.ffmpegPath;
      ffprobePath = engine.ffprobePath;
    }
    final needsFonts = plans.any((pl) => pl.items.any((i) =>
        !i.options.format.audioOnly &&
        i.project.titles.any((t) => t.text.trim().isNotEmpty)));
    if (needsFonts && media.fonts == null) {
      throw ToolError('A project of this kit has titles or captions, but '
          'the font files were not found (looked in: '
          '${fontsChecked.join('; ')}).');
    }
    final speeds = <String, double>{
      for (final kind in const ['sound', 'video-gpu', 'video-cpu'])
        if (rememberedSpeed(all, kind, host: localHostName()) != null)
          kind: rememberedSpeed(all, kind, host: localHostName())!,
    };
    var estimate = 0, low = 0, high = 0;
    final listed = <String>[];
    final warnings = <String>[];
    for (final plan in plans) {
      for (final i in plan.items) {
        final e = estimateRenderMs(i.project, i.options, speeds: speeds);
        estimate += e.ms;
        low += e.lowMs;
        high += e.highMs;
        final size = i.project.canvasSize;
        listed.add('${i.fileName}'
            '${i.options.format.audioOnly ? '' : ' (${size.width}x${size.height}${i.reshaped ? ', a temporary copy in this shape, blurred background' : ''})'}');
        for (final w in i.warnings) {
          warnings.add('${i.fileName}: $w');
        }
      }
    }
    final id = _newId().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final record = ExportJobRecord(
      id: id,
      projectId: first.id,
      projectName: parts.length == 1
          ? first.name
          : '${first.name} and ${parts.length - 1} more',
      outputPath: folder,
      partPath: folder,
      format: kKitFormat,
      quality: 'full',
      fps: 30,
      hardware: hardware,
      overwrite: overwrite,
      createdAt: DateTime.now(),
      projectDurationMs:
          plans.fold<int>(0, (n, pl) => n + pl.project.durationMs),
      estimateMs: estimate,
      estimateBasis: 'between ${durationText(low)} and ${durationText(high)} '
          'for all ${listed.length} file(s)',
      heartbeatAt: DateTime.now(),
      host: localHostName(),
      runner: exportLauncher.description,
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath,
      fontsDir: media.fonts == null ? null : p.dirname(media.fonts!.regular),
      notes: warnings,
      details: {
        'kit': true,
        'planned': listed,
        'textFiles': [for (final pl in plans) pl.textFileName],
      },
    );
    try {
      Directory(jobs.dir).createSync(recursive: true);
      jobs.kitFileOf(id).writeAsStringSync(
          jsonEncode({
            'parts': [for (final part in parts) part.toJson()],
          }),
          flush: true);
      jobs.write(record);
    } on FileSystemException catch (e) {
      throw ToolError('The kit could not be set up in ${jobs.dir}: ${e.message}');
    }
    try {
      record.workerPid = await exportLauncher.launch(jobs, id);
    } catch (e) {
      final fallback = inProcessLauncher(() async => await media.requireEngine());
      final r = jobs.read(id) ?? record;
      r.runner = '${fallback.description} (a separate process could not be started: $e)';
      jobs.write(r);
      await fallback.launch(jobs, id);
    }
    return _waitForJob(
        id, ClipForgeTools._i(a, 'wait_seconds') ?? kDefaultExportWait, call,
        started: true);
  }

  /// The answer about a kit job (get_export_status covers kits too).
  ToolResult _kitResult(JobView v, {bool started = false}) {
    final r = v.record;
    final res = r.result ?? const <String, dynamic>{};
    final files = [
      for (final f in (res['files'] as List?) ?? const [])
        (f as Map).cast<String, dynamic>(),
    ];
    final texts = [for (final t in (res['textFiles'] as List?) ?? const []) '$t'];
    final planned = [for (final x in (r.details['planned'] as List?) ?? const []) '$x'];
    final percent = (r.progress * 100).floor();
    String fileLine(Map<String, dynamic> f) {
      final size = ((f['sizeBytes'] as int? ?? 0) / (1024 * 1024)).toStringAsFixed(1);
      final len = f['durationMs'] as int?;
      final wide = (f['width'] as int?) ?? 0;
      return '- ${p.basename('${f['path']}')}: $size MB'
          '${len == null ? '' : ', ${clock(len)}'}'
          '${wide > 0 ? ', ${f['width']}x${f['height']}' : ''}'
          ' (${f['label']})';
    }

    final notes = r.notes.isEmpty
        ? ''
        : '\nWarnings:\n${r.notes.map((n) => '- $n').join('\n')}';
    final String text;
    switch (v.status) {
      case kJobFinished:
        text = 'The publishing kit is ready in:\n${r.outputPath}\n'
            '${files.map(fileLine).join('\n')}\n'
            '${texts.map((t) => '- ${p.basename(t)}: the title, description, hashtags and chapters to paste').join('\n')}\n'
            'Took ${durationText(v.elapsedMs)} (job_id ${r.id}).$notes\n'
            'Tell the user where the folder is and what to paste where: '
            'they upload the files themselves (ClipForge does not post).';
      case kJobFailed:
        text = 'The kit export failed (job_id ${r.id}): '
            '${r.error ?? 'unknown error'}.'
            '${files.isEmpty ? '' : '\nFinished before that, and kept:\n${files.map(fileLine).join('\n')}'}'
            '${(r.log ?? '').isEmpty ? '' : '\nLast lines of the FFmpeg log:\n${r.log}'}';
      case kJobCancelled:
        text = 'The kit export was cancelled (job_id ${r.id}).'
            '${files.isEmpty ? ' No file was written.' : ' Finished before that, and kept in ${r.outputPath}:\n${files.map(fileLine).join('\n')}'}';
      case kJobLost:
        text = 'The kit export (job_id ${r.id}) stopped without finishing: '
            'its process is gone (it last reported '
            '${durationText(v.quietForMs)} ago at $percent%). Files that '
            'were complete are in ${r.outputPath}. Start it again with '
            'export_kit and overwrite true.';
      default:
        final eta = v.etaMs == null ? '' : ', about ${durationText(v.etaMs!)} left';
        text = '${started ? 'The kit export has started' : 'The kit export is ${v.status}'} '
            '(job_id ${r.id}): $percent% of ${planned.length} file(s) after '
            '${durationText(v.elapsedMs)}$eta'
            '${started ? ' (first estimate: about ${durationText(r.estimateMs)}, ${r.estimateBasis})' : ''}. '
            'Call get_export_status with job_id ${r.id} and wait_seconds '
            '$kMaxStatusWait until it says finished (do not start it '
            'again); cancel_export stops it. Folder: ${r.outputPath}\n'
            '${planned.map((x) => '- $x').join('\n')}$notes';
    }
    return ToolResult(text,
        isError: v.status == kJobFailed || v.status == kJobLost,
        structured: {
          'jobId': r.id,
          'status': v.status,
          'kit': true,
          'folder': r.outputPath,
          'outputPath': r.outputPath,
          'progressPercent': v.status == kJobFinished ? 100 : percent,
          'elapsedMs': v.elapsedMs,
          'etaMs': ?v.etaMs,
          'estimateMs': r.estimateMs,
          'planned': planned,
          'files': files,
          'textFiles': texts,
          'error': ?r.error,
          'log': ?r.log,
          if (r.notes.isNotEmpty) 'warnings': r.notes,
        });
  }
}
