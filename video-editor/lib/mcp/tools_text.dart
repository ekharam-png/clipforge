// The text and "who speaks" tools (1.13): get_captions (the captions as
// compact text, paged), replace_in_captions (find and replace over all
// captions, dry run by default) and get_speech_map (who talks when, from
// the sound itself - no transcript needed). Part of tools.dart.
part of 'tools.dart';

const int kDefaultCaptionLines = 400;
const int kMaxCaptionLines = 2000;
const int kDefaultSpeechRows = 300;
const int kMaxSpeechRows = 2000;

extension _TextTools on ClipForgeTools {
  List<ToolDef> get _textToolDefs => [
        ToolDef(
          name: 'get_captions',
          title: 'Read the captions',
          description:
              'The captions on the timeline as compact text, whatever made '
              'them (import_srt, captions_from_transcript, typed in the '
              'app): one line per caption, "start-end [m:ss] Speaker: '
              'text" with times in ms on the timeline. A caption that '
              'starts with "Name:" is that speaker\'s; captions without a '
              'name belong to whoever spoke last. 500 captions are about '
              '35 KB. Use this to READ long captioned projects (get_project '
              'lists captions with their whole look, 30 at a time); use '
              'get_transcript for what was transcribed from the sound. '
              'ids true adds each caption\'s title_id (for update_title / '
              'remove_title; replace_in_captions needs none). format '
              '"paragraphs" joins the lines of one speaker into paragraphs '
              '(as the app\'s Text window shows them). kind "titles" lists '
              'the plain titles instead, "all" both.',
          properties: {
            'project_id': _projectId,
            'from_ms': _int('Only what starts at or after this time, in ms.', min: 0),
            'to_ms': _int('Only what starts before this time, in ms.', min: 0),
            'kind': _str('"captions" (default), "titles" or "all".',
                values: const ['captions', 'titles', 'all']),
            'format': _str('"text" (default: one line per caption) or '
                '"paragraphs".', values: const ['text', 'paragraphs']),
            'ids': _bool('true: put the title_id in front of every line. '
                'Default false.'),
            'offset': _int('Skip this many lines (or paragraphs).', min: 0),
            'limit': _int(
                'At most this many (default $kDefaultCaptionLines, at most '
                '$kMaxCaptionLines).',
                min: 1,
                max: kMaxCaptionLines),
          },
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _getCaptions,
        ),
        ToolDef(
          name: 'replace_in_captions',
          title: 'Find and replace in captions',
          description:
              'Replaces a word or phrase in EVERY caption at once (a '
              'misspelt name in 500 captions). DRY RUN BY DEFAULT: the '
              'answer says how many places in how many captions would '
              'change and shows examples; call again with dry_run false '
              'to do it (one undo step). Case does not matter unless '
              'case_sensitive is true; whole_word true leaves longer '
              'words alone ("Sam" not in "Samuel"). The replacement is '
              'put in exactly as given. Captions that would become empty '
              'are left alone (use remove_title). Times and look do not '
              'change.$_editNote',
          properties: {
            'project_id': _projectId,
            'find': _str('The text to look for.'),
            'replace': _str('What to put in its place ("" removes it).'),
            'case_sensitive': _bool('Default false.'),
            'whole_word': _bool('Only where it is not part of a longer '
                'word. Default false.'),
            'from_ms': _int('Only captions that start at or after this '
                'time, in ms.', min: 0),
            'to_ms': _int('Only captions that start before this time, in ms.', min: 0),
            'include_titles': _bool('Also change plain titles. Default '
                'false: captions only.'),
            'dry_run': _bool('true (DEFAULT): report only, save nothing. '
                'false: replace.'),
          },
          required: const ['project_id', 'find', 'replace'],
          handler: _replaceInCaptions,
        ),
        ToolDef(
          name: 'get_speech_map',
          title: 'Who speaks when',
          description:
              'Who is talking when, worked out from the SOUND (no '
              'transcript needed): for every speaker - a speech track, '
              'i.e. a voice recorded on its own file (add_voice) or a '
              'voice-over; without speech tracks the video\'s own sound '
              'is the one speaker - the stretches of talk on the timeline '
              'as it is cut now, the total and the share of the talking. '
              'Microphones recorded together are compared, so one '
              'speaker\'s voice heard faintly in the other\'s microphone '
              'does not count. view "turns" (default) merges the talk '
              'into speaker turns in time order ("start-end [m:ss] Name"), '
              'which is what to cut by: a turn\'s start and end are good '
              'cut points. view "stretches" lists every stretch per '
              'speaker (pauses of 0.3 s and more separate them). The '
              'first call for a long file listens to it once (a few '
              'seconds for 40 minutes); after that it is instant. It '
              'tells loud from quiet - not speech from music or noise, '
              'and not WHAT is said.',
          properties: {
            'project_id': _projectId,
            'view': _str('"turns" (default) or "stretches".',
                values: const ['turns', 'stretches']),
            'from_ms': _int('Only what ends after this time, in ms.', min: 0),
            'to_ms': _int('Only what starts before this time, in ms.', min: 0),
            'speaker': _str('Only this speaker (a track name or track_id).'),
            'min_ms': _int('Leave out turns / stretches shorter than this many ms. '
                'Default 0.', min: 0),
            'offset': _int('Skip this many rows.', min: 0),
            'limit': _int(
                'At most this many rows (default $kDefaultSpeechRows, at '
                'most $kMaxSpeechRows).',
                min: 1,
                max: kMaxSpeechRows),
          },
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          openWorld: true,
          handler: _getSpeechMap,
        ),
      ];

  ({int? from, int? to}) _range(Map<String, dynamic> a) {
    final from = ClipForgeTools._i(a, 'from_ms'), to = ClipForgeTools._i(a, 'to_ms');
    if (from != null && to != null && to <= from) {
      throw ToolError('to_ms ($to) must be after from_ms ($from).');
    }
    return (from: from, to: to);
  }

  Future<ToolResult> _getCaptions(Map<String, dynamic> a, ToolCall call) async {
    final project = (await _load(a['project_id'])).project;
    final r = _range(a);
    final kind = (a['kind'] as String?) ?? 'captions';
    final paragraphs = a['format'] == 'paragraphs';
    final ids = a['ids'] == true;
    final offset = ClipForgeTools._i(a, 'offset') ?? 0;
    final limit = (ClipForgeTools._i(a, 'limit') ?? kDefaultCaptionLines)
        .clamp(1, kMaxCaptionLines);
    var lines = [
      if (kind != 'titles') ...captionLines(project),
      if (kind != 'captions') ...titleLines(project),
    ];
    if (kind == 'all') {
      lines.sort((x, y) => x.startMs.compareTo(y.startMs));
    }
    final total = lines.length;
    lines = [
      for (final l in lines)
        if ((r.from == null || l.startMs >= r.from!) &&
            (r.to == null || l.startMs < r.to!))
          l,
    ];
    final what = switch (kind) {
      'titles' => 'title(s)',
      'all' => 'caption(s) and title(s)',
      _ => 'caption(s)',
    };
    final doc = buildTextDocument(
        kind == 'titles' ? TextSource.titles : TextSource.captions, lines);
    final rows = paragraphs ? doc.paragraphs.length : lines.length;
    final from = offset.clamp(0, rows);
    final to = (from + limit).clamp(from, rows);
    final next = to < rows ? to : null;
    final text = StringBuffer()
      ..writeln('"${project.name}" (${_mss(project.durationMs)} long) has '
          '$total $what'
          '${lines.length == total ? '' : ', ${lines.length} in this part'}'
          '${doc.speakers.isEmpty ? '' : '; speakers: ${doc.speakers.join(', ')}'}. '
          '${rows == 0 ? '' : '${paragraphs ? 'Paragraphs' : 'Lines'} ${from + 1}-$to of $rows. '}'
          'Times are ms on the timeline (start-end), then [m:ss].');
    if (paragraphs) {
      for (final p in doc.paragraphs.sublist(from, to)) {
        text.writeln('${p.startMs}-${p.endMs} [${_mss(p.startMs)}] '
            '${p.speaker.isEmpty ? '' : '${p.speaker}: '}${p.text}');
      }
    } else {
      for (final l in lines.sublist(from, to)) {
        text.writeln('${ids ? '${l.id} ' : ''}${l.startMs}-${l.endMs} '
            '[${_mss(l.startMs)}] '
            '${l.speaker.isEmpty ? '' : '${l.speaker}: '}${l.text}');
      }
    }
    if (total == 0) {
      text.writeln(kind == 'titles'
          ? 'No titles. add_title adds one.'
          : 'No captions yet. import_srt adds them from a subtitle file, '
              'captions_from_transcript from the speech (after '
              'transcribe), add_caption one by one.');
    }
    if (next != null) text.writeln('More: call again with offset $next.');
    return ToolResult(text.toString().trimRight(), structured: {
      'projectId': project.id,
      'kind': kind,
      'format': paragraphs ? 'paragraphs' : 'text',
      'total': total,
      'matching': rows,
      'offset': from,
      'count': to - from,
      'nextOffset': ?next,
      'speakers': doc.speakers,
    });
  }

  Future<ToolResult> _replaceInCaptions(Map<String, dynamic> a, ToolCall call) {
    final find = a['find'] as String? ?? '';
    final replace = a['replace'] as String? ?? '';
    if (find.trim().isEmpty) throw ToolError('find is empty.');
    final r = _range(a);
    final dryRun = a['dry_run'] != false;
    return _edit({...a, 'dry_run': dryRun}, (e) {
      final found = replaceInCaptions(e.project, find, replace,
          caseSensitive: a['case_sensitive'] == true,
          wholeWord: a['whole_word'] == true,
          fromMs: r.from,
          toMs: r.to,
          titlesToo: a['include_titles'] == true);
      final n = found.changes.length;
      if (n == 0) {
        return _Done(
            'No caption contains "$find"'
            '${found.skipped > 0 ? ' in a way that can be replaced (${found.skipped} would become empty)' : ''}'
            '. Check the spelling with get_captions; case_sensitive and '
            'whole_word narrow the search.',
            {'replacements': 0, 'captionsChanged': 0});
      }
      e.transaction(() {
        for (final c in found.changes) {
          e.updateTitle(c.after);
        }
      },
          label: 'Replaced "${_short(find)}" in $n '
              '${n == 1 ? 'caption' : 'captions'}');
      String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
      final examples = [
        for (final c in found.changes.take(8))
          '  [${_mss(c.before.startMs)}] "${flat(c.before.text)}" -> '
              '"${flat(c.after.text)}"',
      ];
      return _Done(
          'Replaced "$find" by "$replace" in ${found.total} place(s) in $n '
          'caption(s)'
          '${found.skipped > 0 ? ' (${found.skipped} left alone: they would become empty)' : ''}'
          '.\n${examples.join('\n')}'
          '${n > examples.length ? '\n  … and ${n - examples.length} more' : ''}'
          '${dryRun ? '\nCall again with dry_run false to do it.' : ''}',
          {
            'replacements': found.total,
            'captionsChanged': n,
            if (found.skipped > 0) 'captionsSkipped': found.skipped,
            'titleIds': [for (final c in found.changes.take(kMaxListedHits)) c.before.id],
          });
    });
  }

  static String _short(String s) =>
      s.length > 24 ? '${s.substring(0, 23)}…' : s;

  /// Where the sound pictures are kept: next to the projects folder.
  String get _peaksDir => p.join(speechRoot, 'sound-pictures');

  Future<ToolResult> _getSpeechMap(Map<String, dynamic> a, ToolCall call) async {
    final project = (await _load(a['project_id'])).project;
    final r = _range(a);
    final stretchView = a['view'] == 'stretches';
    final minMs = ClipForgeTools._i(a, 'min_ms') ?? 0;
    final offset = ClipForgeTools._i(a, 'offset') ?? 0;
    final limit = (ClipForgeTools._i(a, 'limit') ?? kDefaultSpeechRows)
        .clamp(1, kMaxSpeechRows);
    final engine = await media.requireEngine();

    // The files whose sound says who speaks: the speech tracks' sounds,
    // or (without any) the clips' own sound.
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
    if (wanted.isEmpty) {
      throw ToolError('"${project.name}" has no sound that could be speech: '
          'no speech track with sound (add_voice, or add_music on the '
          '"Voice" track) and no video clip whose own sound is on.');
    }
    final peaks = <String, SoundPeaks>{};
    final warnings = <String>[];
    try {
      await evictSoundPeaks(_peaksDir);
    } catch (_) {}
    for (final e in wanted.entries) {
      if (!File(e.value.path).existsSync()) {
        warnings.add('"${p.basename(e.value.path)}" is missing: its talk is '
            'not in the map (relink_media).');
        continue;
      }
      try {
        final found = await engine.soundPeaks(e.value.path,
            audioTrack: e.value.track, cacheDir: _peaksDir);
        if (found != null) peaks[e.key] = found;
      } on ExportException catch (err) {
        warnings.add('${err.message}.');
      }
    }
    var tracks =
        speakerTracks(project, (path, track) => peaks['$path|$track']);
    final who = a['speaker'] as String?;
    if (who != null) {
      final want = who.trim().toLowerCase();
      final some = [
        for (final t in tracks)
          if (t.id == who || t.name.toLowerCase() == want) t,
      ];
      if (some.isEmpty) {
        throw ToolError('No speaker "$who". Speakers: '
            '${tracks.map((t) => '${t.name} (track_id ${t.id})').join(', ')}.');
      }
      tracks = some;
    }
    bool inPart(int s, int e) =>
        (r.from == null || e > r.from!) &&
        (r.to == null || s < r.to!) &&
        e - s >= minMs;
    final allTalk = tracks.fold<int>(0, (n, t) => n + t.talkMs);
    final candidates = stretchView
        ? ([
            for (final t in tracks)
              for (final s in t.stretches)
                (id: t.id, name: t.name, startMs: s.startMs, endMs: s.endMs),
          ]..sort((x, y) => x.startMs.compareTo(y.startMs)))
        : speakerTurns(tracks);
    final rows = [
      for (final row in candidates)
        if (inPart(row.startMs, row.endMs)) row,
    ];
    final from = offset.clamp(0, rows.length);
    final to = (from + limit).clamp(from, rows.length);
    final next = to < rows.length ? to : null;
    final text = StringBuffer()
      ..writeln('Who speaks in "${project.name}" (${_mss(project.durationMs)} '
          'long, as it is cut now), from the sound:');
    for (final t in tracks) {
      text.writeln('- ${t.name} (track_id ${t.id}): talks '
          '${_mss(t.talkMs)} in ${t.stretches.length} stretch(es)'
          '${allTalk > 0 ? ', ${(t.talkMs * 100 / allTalk).round()}% of the talking' : ''}'
          '${project.durationMs > 0 ? ', ${(t.talkMs * 100 / project.durationMs).round()}% of the video' : ''}'
          '${t.pending ? ' (part of its sound could not be read)' : ''}');
    }
    text.writeln('${stretchView ? 'Stretches' : 'Speaker turns'} '
        '${rows.isEmpty ? 0 : from + 1}-$to of ${rows.length}, times in ms '
        'on the timeline (start-end), then [m:ss], the speaker and the '
        'length:');
    for (final row in rows.sublist(from, to)) {
      text.writeln('${row.startMs}-${row.endMs} [${_mss(row.startMs)}] '
          '${row.name} ${((row.endMs - row.startMs) / 1000).toStringAsFixed(1)} s');
    }
    if (rows.isEmpty) text.writeln('Nobody talks in this part.');
    if (next != null) text.writeln('More: call again with offset $next.');
    for (final w in warnings) {
      text.writeln('Note: $w');
    }
    return ToolResult(text.toString().trimRight(), structured: {
      'projectId': project.id,
      'view': stretchView ? 'stretches' : 'turns',
      'durationMs': project.durationMs,
      'speakers': [
        for (final t in tracks)
          {
            'trackId': t.id,
            'name': t.name,
            'talkMs': t.talkMs,
            'stretches': t.stretches.length,
            if (allTalk > 0)
              'talkShare': double.parse((t.talkMs / allTalk).toStringAsFixed(3)),
          },
      ],
      'total': rows.length,
      'offset': from,
      'count': to - from,
      'nextOffset': ?next,
      'rows': [
        for (final row in rows.sublist(from, to))
          [row.startMs, row.endMs, row.name],
      ],
      if (warnings.isNotEmpty) 'warnings': warnings,
    });
  }
}
