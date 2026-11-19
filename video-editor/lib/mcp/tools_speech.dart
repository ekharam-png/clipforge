// The speech-to-text tools (1.11): transcribe (a background job),
// get_transcribe_status, cancel_transcribe, get_transcript,
// find_in_transcript, captions_from_transcript, remove_fillers and
// make_short. Part of tools.dart (they use its loading / saving helpers).
part of 'tools.dart';

/// Phrases per get_transcript answer by default, and words.
const int kDefaultTranscriptSegments = 400;
const int kDefaultTranscriptWords = 500;
const int kMaxTranscriptPage = 2000;

/// Hits listed by find_in_transcript / remove_fillers.
const int kMaxListedHits = 100;

/// "2:05" / "1:02:05": a time for reading (the exact ms are next to it).
String _mss(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = s ~/ 60 % 60, sec = s % 60;
  final two = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$two' : '$m:$two';
}

extension _SpeechTools on ClipForgeTools {
  static const String _languageHelp =
      '"auto" (default: the program detects it), "en" English, "ru" '
      'Russian, "he" Hebrew, or another two-letter code. Giving the '
      'language is more reliable than "auto", above all for short clips.';

  List<ToolDef> get _speechToolDefs => [
        ToolDef(
          name: 'transcribe',
          title: 'Turn speech into text',
          description:
              'Turns what is SAID in a project into text with a time for '
              'every word, so that get_transcript, find_in_transcript, '
              'captions_from_transcript, remove_fillers and make_short work. '
              'It runs on this computer with a speech program that is '
              'already installed (the system FFmpeg\'s whisper filter, '
              'whisper.cpp, faster-whisper or OpenAI whisper; get_status '
              'shows which). It is a background JOB: this call waits a '
              'little and returns a job_id; poll get_transcribe_status '
              'until it says finished (about as long as the video for a '
              'small pack without a graphics card, much faster with one). '
              'One transcript is kept per media file (per speaker for '
              'voices recorded separately: those files are transcribed '
              'instead of the muted camera sound) in the project folder; it '
              'stays valid through every cut, so transcribe ONCE, before or '
              'after editing. Files already transcribed with the same '
              'settings are skipped. NOTHING IS EVER DOWNLOADED unless '
              'download_pack is true: when a language pack is missing the '
              'answer names it and its size - ask the user, then call again '
              'with download_pack true. The project may stay open in the '
              'app (nothing in the project itself changes).',
          properties: {
            'project_id': _projectId,
            'clip_id': _str('Only the sound of this clip (and its linked '
                'voices). Default: every clip ("all").'),
            'language': _str(_languageHelp),
            'quality': _str(
                'Which size of language pack: "auto" (default: the largest '
                'one already on this computer), "small" (about 140 MB: '
                'quick, more mistakes, weak in Hebrew), "medium" (about '
                '470 MB: good), "large" (about 1.6 GB: best, all '
                'languages). A size that is not on the computer needs '
                'download_pack.',
                values: const ['auto', 'small', 'medium', 'large']),
            'backend': _str(
                'Which speech program: "auto" (default) or an id from '
                'get_status ("ffmpeg-whisper", "whisper-cpp", '
                '"faster-whisper", "openai-whisper").'),
            'download_pack': _bool(
                'true: the user agreed to download the language pack this '
                'needs (the answer without it says which and how big). '
                'Default false: never download.'),
            'force': _bool('true: transcribe again even when a transcript '
                'made with these settings is there. Default false.'),
            'wait_seconds': _int(
                'Wait up to this long for the job before answering, '
                '0..$kMaxStatusWait. Default $kDefaultExportWait.',
                min: 0,
                max: kMaxStatusWait),
          },
          required: const ['project_id'],
          openWorld: true,
          handler: _transcribe,
        ),
        ToolDef(
          name: 'get_transcribe_status',
          title: 'Speech-to-text progress',
          description:
              'How a transcribe job is doing: status ("starting", '
              '"running", "finished", "failed", "cancelled", "lost"), '
              'percent, what it is doing now (downloading a pack, reading '
              'the sound, listening), and per file the words found, the '
              'language and whether word times are measured or estimated. '
              'wait_seconds waits that long for it to finish first. '
              'Without job_id: the recent jobs.',
          properties: {
            'job_id': _str('The job_id transcribe returned.'),
            'wait_seconds': _int(
                'Wait up to this long, 0..$kMaxStatusWait. Default 0.',
                min: 0,
                max: kMaxStatusWait),
          },
          readOnly: true,
          handler: _getTranscribeStatus,
        ),
        ToolDef(
          name: 'cancel_transcribe',
          title: 'Stop speech-to-text',
          description:
              'Stops a running transcribe job. Files it had finished keep '
              'their transcripts; a pack that was downloading continues '
              'from where it stopped next time.',
          properties: {'job_id': _str('The job_id transcribe returned.')},
          required: const ['job_id'],
          handler: _cancelTranscribe,
        ),
        ToolDef(
          name: 'get_transcript',
          title: 'Read what is said',
          description:
              'What is said in the project (after transcribe), with times. '
              'Default: time_base "timeline" (positions in the video as it '
              'is cut NOW - worked out from the clips, so it is right after '
              'every edit) and format "text": one line per phrase, '
              '"start-end [m:ss] Speaker: text" with times in ms - compact, '
              'a 25-minute talk fits in one or two answers. format '
              '"segments" gives the phrases as data, "words" every word '
              'with its times (for exact cut points; page it). from_ms / '
              'to_ms limit the part; offset / limit page through long '
              'answers (nextOffset says where to go on). time_base '
              '"source" gives the transcript of one media file in that '
              'file\'s own time. Claude now KNOWS WHAT IS SAID, but still '
              'cannot see the picture.',
          properties: {
            'project_id': _projectId,
            'time_base': _str('"timeline" (default) or "source".',
                values: const ['timeline', 'source']),
            'format': _str('"text" (default), "segments" or "words".',
                values: const ['text', 'segments', 'words']),
            'from_ms': _int('Only what starts at or after this time, in ms.', min: 0),
            'to_ms': _int('Only what starts before this time, in ms.', min: 0),
            'clip_id': _str('Only this clip (timeline), or the media file '
                'of this clip (source).'),
            'offset': _int('Skip this many phrases (or words).', min: 0),
            'limit': _int(
                'At most this many phrases (default '
                '$kDefaultTranscriptSegments) or words (default '
                '$kDefaultTranscriptWords); at most $kMaxTranscriptPage.',
                min: 1,
                max: kMaxTranscriptPage),
          },
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _getTranscript,
        ),
        ToolDef(
          name: 'find_in_transcript',
          title: 'Find where something is said',
          description:
              'Finds where a word or phrase is said (after transcribe): '
              'timeline start / end in ms, the clip, the speaker and the '
              'words around it. Whole words in order; case and punctuation '
              'do not matter. prefix true also finds longer forms of the '
              'last word ("edit" finds "editing").',
          properties: {
            'project_id': _projectId,
            'phrase': _str('The word or words to look for.'),
            'prefix': _bool('The last word may be the beginning of a '
                'longer word. Default false.'),
            'limit': _int('At most this many places (default 50).',
                min: 1, max: kMaxListedHits),
          },
          required: const ['project_id', 'phrase'],
          readOnly: true,
          idempotent: true,
          handler: _findInTranscript,
        ),
        ToolDef(
          name: 'captions_from_transcript',
          title: 'Captions from speech',
          description:
              'Makes captions from the transcript (after transcribe): one '
              'or two lines of about 32-42 characters, a new caption at '
              'sentence ends, pauses and speaker changes, each on screen '
              'for at least min_duration_ms and at most max_duration_ms, '
              'never overlapping. They get the look of the project\'s '
              'captions (or the standard caption look) and follow their '
              'picture like any caption. Hebrew / Arabic lines are drawn '
              'right to left. "um" / "uh" are left out of the text. One '
              'undo step. dry_run true lists them without saving. Check '
              'the text: speech recognition makes mistakes, more so with a '
              'small pack.$_editNote',
          properties: {
            'project_id': _projectId,
            'from_ms': _int('Only speech from this timeline time, in ms.', min: 0),
            'to_ms': _int('Only speech before this timeline time, in ms.', min: 0),
            'max_line_chars': _int(
                'Longest line in characters, 12..60. Default 37. Lines are '
                'also kept inside the picture (shorter on upright video).',
                min: 12,
                max: 60),
            'max_lines': _int('1 or 2 lines. Default 2.', min: 1, max: 2),
            'min_duration_ms': _int('Shortest time on screen, in ms. Default 1000.',
                min: 300, max: 5000),
            'max_duration_ms': _int('Longest time on screen, in ms. Default 6000.',
                min: 1500, max: 15000),
            'replace_existing': _bool(
                'true: captions already in that part are removed first. '
                'Default false (the answer warns when some are there).'),
            'keep_filler_sounds': _bool('true: keep "um", "uh" in the '
                'text. Default false.'),
            'dry_run': _bool('true: list the captions without saving.'),
            ..._titleStyleProps,
          },
          required: const ['project_id'],
          handler: _captionsFromTranscript,
        ),
        ToolDef(
          name: 'remove_fillers',
          title: 'Remove filler words',
          description:
              'Finds hesitation sounds in the transcript ("um", "uh", "er"; '
              'Russian "э-э", "эм"; Hebrew "אה", "אממ") and cuts them out '
              'GENTLY, one undo step. dry_run is TRUE BY DEFAULT: always '
              'look first, tell the user the numbers in plain words ("I '
              'would remove 23 of 61 fillers, about 3 cuts a minute, saving '
              '19 seconds; 9 were left because the picture would jump"), '
              'then call again with dry_run false. strength: "light" '
              '(default: only clear fillers of 350 ms or more that stand '
              'alone between pauses; no two cuts closer than 2.5 s; at most '
              '4 a minute), "normal" (from 200 ms; 1.5 s apart; 8 a minute) '
              'or "strong" (everything found; 0.7 s apart) - use strong '
              'ONLY when the user asks for it or the result is sound only. '
              'Every strength leaves no piece shorter than 0.6 s. JUMP '
              'CHECK: the picture before and after each cut is compared; '
              'on light / normal a cut where the person moved is left in '
              '("jumpy"), a slight change gets a short dissolve. The answer '
              'gives found / cut / left-because-too-close / '
              'left-because-jumpy, time saved, cuts per minute and the 5 '
              'riskiest cuts with their times - give those to the user to '
              'watch. Every cut is remembered (list_auto_cuts) and can be '
              'put back (restore_cut): if the user says it feels jumpy, '
              'restore the riskiest ones or all. Do not also run '
              'remove_silences hard on the same video without checking the '
              'cuts per minute: about 6 a minute in total is the most a '
              'talking-head video takes. Filler WORDS that are also real '
              'words ("like"; "ну", "как бы", "типа"; "כאילו") are only cut '
              'with include_word_fillers or when named in fillers. Needs '
              'MEASURED word times (transcripts made by the FFmpeg filter '
              'only estimate them: refused unless allow_estimated_times). '
              'Speech programs often leave "um" out of the text, so fewer '
              'are found than are said.$_editNote',
          properties: {
            'project_id': _projectId,
            'strength': _str('"light" (default), "normal" or "strong".',
                values: const ['light', 'normal', 'strong']),
            'clip_id': _str('Only this clip. Default: all.'),
            'from_ms': _int('Only from this timeline time, in ms.', min: 0),
            'to_ms': _int('Only before this timeline time, in ms.', min: 0),
            'language': _str('Whose filler list: "en", "ru", "he". Default: '
                'the language of the transcript.'),
            'fillers': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Your own list instead of the built-in one '
                  '(words or short phrases, e.g. ["um", "you know"]).',
            },
            'include_word_fillers': _bool('Also cut the filler WORDS of '
                'the language. Default false.'),
            'dry_run': _bool('Default TRUE: only report. false: cut.'),
            'allow_estimated_times': _bool('Cut even when word times are '
                'only estimated. Default false.'),
            'jump_check': _bool('Compare the picture before and after each '
                'cut (needs FFmpeg). Default true.'),
            'min_cut_ms': _int('Advanced: shortest cut in ms (overrides the '
                'strength).', min: 40, max: 5000),
            'min_distance_ms': _int('Advanced: closest two cuts may be, in ms.',
                min: 0, max: 60000),
            'max_cuts_per_minute': _int('Advanced: most cuts in a minute; 0 '
                '= no limit.', min: 0, max: 120),
            'min_piece_ms': _int('Advanced: shortest piece of clip left, in ms.',
                min: 100, max: 5000),
            'pad_ms': _int('Advanced: air left next to the neighbouring '
                'words, in ms. Default 40.', min: 0, max: 300),
          },
          required: const ['project_id'],
          destructive: true,
          handler: _removeFillers,
        ),
        ToolDef(
          name: 'list_auto_cuts',
          title: 'List automatic cuts',
          description:
              'The cuts remove_fillers and remove_silences made (by Claude '
              'or in the app), as the project remembers them: id, kind '
              '(filler / silence), the word, the file and the part of it '
              'that was removed, when and by whom, the jump score (0 = the '
              'picture does not change, 1 = a clear jump) and whether a '
              'short dissolve was put on it; plus count, time saved and '
              'cuts per minute. Riskiest first with sort "risk". Paged.',
          properties: {
            'project_id': _projectId,
            'kind': _str('Only "filler", "silence" or "text" (a part cut '
                'out from the app\'s Text window).',
                values: const ['filler', 'silence', 'text']),
            'sort': _str('"time" (default: in file order) or "risk" '
                '(highest jump score first).', values: const ['time', 'risk']),
            'offset': _int('Skip this many.', min: 0),
            'limit': _int('At most this many (default 50).', min: 1, max: 300),
          },
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _listAutoCuts,
        ),
        ToolDef(
          name: 'restore_cut',
          title: 'Put an automatic cut back',
          description:
              'Puts back what an automatic cut removed (cut_id from '
              'list_auto_cuts or from remove_fillers), or "all" of them '
              '(optionally only kind "filler" / "silence"). The two pieces '
              'around the cut become one clip again when nothing changed '
              'between them; otherwise the removed part comes back as a '
              'clip of its own. Titles and linked voices follow. One undo '
              'step. Use it when the user finds the result jumpy.$_editNote',
          properties: {
            'project_id': _projectId,
            'cut_id': _str('The id of the cut, or "all".'),
            'kind': _str('With "all": only these.',
                values: const ['filler', 'silence', 'text']),
            'dry_run': _bool('true: report what would come back, save '
                'nothing.'),
          },
          required: const ['project_id', 'cut_id'],
          handler: _restoreCut,
        ),
        ToolDef(
          name: 'make_short',
          title: 'Make a short from one part',
          description:
              'Makes a NEW project holding only from_ms..to_ms of this '
              'one\'s timeline (the original is not changed): the project '
              'is copied, everything outside the range is cut away with the '
              'normal split / remove (titles and captions on the kept part '
              'stay on their picture, linked voices follow, music is moved '
              'and trimmed), the shape is set (default 9:16 upright) and '
              'the video size to 1080p, and with captions true (default) '
              'captions are made from the transcript when the part has '
              'none. Returns the new project_id - export it with '
              'export_video. Use get_transcript / find_in_transcript to '
              'choose from_ms and to_ms at sentence starts and ends '
              '(suggest_shorts lists candidates). The answer WARNS when '
              'the short is longer than is safe for Shorts / Reels / '
              'TikTok or starts or ends in the middle of a sentence.',
          properties: {
            'project_id': _projectId,
            'from_ms': _int('Start on the timeline, in ms.', min: 0),
            'to_ms': _int('End on the timeline, in ms.', min: 0),
            'name': _str('Name of the new project. Default: "<name> - '
                'short <m:ss>".'),
            'shape': _str('Shape of the short. Default "9:16".',
                values: kAspectNames.keys.toList()),
            'captions': _bool('Add captions from the transcript. Default '
                'true.'),
            'caption_style': _str('"short": the look made for shorts '
                '(bigger, centred in the lower middle, outlined, at most '
                'two lines; captions the part already has get it too). '
                'Default "standard".', values: const ['standard', 'short']),
            'title': _str('A title shown at the top for the whole short '
                '(a few words: the hook).'),
            'snap_to_speech': _bool('true: move from_ms and to_ms outward '
                'to the nearest pause in the talk (never into a word), so '
                'the short does not start or end mid-word. Default false.'),
          },
          required: const ['project_id', 'from_ms', 'to_ms'],
          handler: _makeShort,
        ),
      ];

  // Shared ------------------------------------------------------------------

  /// Every stored transcript the project's clips use.
  Future<({TranscriptLookup lookup, TranscriptCoverage cover})> _speechOf(
      _Loaded loaded,
      {String? clipId}) async {
    final store = TranscriptStore.ofProject(loaded.dir);
    final found = <String, Transcript?>{};
    for (final s in speechSourcesOfProject(loaded.project)) {
      found[s.key] = await store.load(s.path, s.audioTrack);
    }
    Transcript? lookup(String path, int track) => found['$path|$track'];
    return (
      lookup: lookup,
      cover: transcriptCoverage(loaded.project, lookup, clipId: clipId),
    );
  }

  String _sourceName(SpeechSource s) =>
      '${p.basename(s.path)}${s.speaker.isEmpty ? '' : ' (${s.speaker})'}';

  /// Refuses when nothing is transcribed; else the warning about what is
  /// not (null when everything is).
  String? _coverageNote(TranscriptCoverage cover) {
    if (cover.sources.isEmpty) {
      throw ToolError('This project has no video clip with sound (and no '
          'voice recording), so there is no speech to read.');
    }
    if (cover.none) {
      throw ToolError('Nothing is transcribed yet: call transcribe for this '
          'project first (then get_transcribe_status until it is '
          'finished).');
    }
    if (cover.missing.isEmpty) return null;
    return 'Not transcribed yet, so missing here: '
        '${cover.missing.take(6).map(_sourceName).join(', ')}'
        '${cover.missing.length > 6 ? ', …' : ''}. Call transcribe to add '
        'them.';
  }

  // transcribe --------------------------------------------------------------
  Future<ToolResult> _transcribe(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    final clipArg = a['clip_id'] as String?;
    final clipId = clipArg == null || clipArg == 'all'
        ? null
        : ClipForgeTools._clip(project, clipArg).id;
    final sources = speechSourcesOfProject(project, clipId: clipId);
    if (sources.isEmpty) {
      throw ToolError(clipId == null
          ? 'This project has no video clip with sound (and no voice '
              'recording), so there is nothing to transcribe.'
          : 'That clip has no sound to transcribe (a photo or a silent '
              'video).');
    }
    final language = languageCode(a['language'] as String?);
    final lang = language.isEmpty ? 'auto' : language;
    final quality = SpeechQuality.parse(a['quality']);
    final backend = (a['backend'] as String?)?.trim() ?? 'auto';
    final force = a['force'] == true;
    final download = a['download_pack'] == true;

    final store = TranscriptStore.ofProject(loaded.dir);
    final items = <TranscribeItem>[];
    var cached = 0;
    for (final s in sources) {
      if (!File(s.path).existsSync()) {
        throw ToolError('The file is missing: ${s.path}. Use relink_media '
            'first.');
      }
      final item = TranscribeItem(
          path: s.path,
          audioTrack: s.audioTrack,
          speaker: s.speaker,
          durationMs: s.sourceDurationMs);
      if (!force) {
        final have = await store.load(s.path, s.audioTrack);
        if (have != null &&
            have.madeWith(
                language: lang,
                models: quality == SpeechQuality.auto
                    ? null
                    : modelIdsFor(language, quality),
                backend: backend)) {
          item
            ..state = 'cached'
            ..words = have.wordCount
            ..language = have.language
            ..wordTiming = have.wordTiming.name;
          cached++;
        }
      }
      items.add(item);
    }
    if (cached == items.length) {
      final words = items.fold<int>(0, (n, i) => n + i.words);
      return ToolResult(
          'Already transcribed with these settings: ${items.length} file(s), '
          '$words words. Nothing to do (force true transcribes again). Read '
          'it with get_transcript.',
          structured: {
            'status': kJobFinished,
            'alreadyTranscribed': true,
            'files': [for (final i in items) i.toJson()],
            'words': words,
          });
    }

    final plan =
        await speech.plan(language: lang, quality: quality, backendId: backend);
    Never ask(String message, Map<String, dynamic> data) => throw ToolError(
        '$message Nothing was downloaded and nothing was started. Ask the '
        'user first; when they agree, call transcribe again with the same '
        'arguments plus ${data['callWith']}.');
    if (plan.problem != null) throw ToolError(plan.problem!);
    if (plan.needsChoice) {
      ask(
          'No language pack for ${language.isEmpty ? '' : '${languageName(language)} '}speech is on this '
          'computer yet. The sizes to choose from: '
          '${speech.packOffer(lang)}.',
          {'callWith': 'quality "small", "medium" or "large" and download_pack true'});
    }
    if (plan.download != null && !download) {
      final m = plan.download!;
      ask(
          'This needs the language pack "${m.title}" (${m.sizeLabel}, '
          '${m.size.note}; file ${m.fileName}), which is not on this '
          'computer. It would be downloaded once into '
          '${speech.models.dir}.',
          {'callWith': 'download_pack true'});
    }
    if (plan.programFetchesModel && !download) {
      final m = speech.models.byId(plan.modelName);
      ask(
          '${plan.backend!.label} keeps its own models and does not seem to '
          'have "${plan.modelName}" yet; it would download it itself '
          '(${m?.sizeLabel ?? 'size unknown'}).',
          {'callWith': 'download_pack true'});
    }

    final id = _newId();
    final record = TranscribeJobRecord(
      id: id,
      projectId: project.id,
      projectName: project.name,
      projectDir: loaded.dir,
      rootDir: speechRoot,
      language: lang,
      quality: quality.name,
      backend: backend,
      force: force,
      downloadPack: download,
      createdAt: DateTime.now(),
      items: items,
      backendUsed: plan.backend!.id,
    );
    transcribeJobs.write(record);
    try {
      record.workerPid = await transcribeLauncher.launch(transcribeJobs, id);
    } catch (e) {
      // Fall back to running it inside the server.
      await inProcessTranscribeLauncher((_) => speech).launch(transcribeJobs, id);
    }
    return _waitForTranscribe(
        id, ClipForgeTools._i(a, 'wait_seconds') ?? kDefaultExportWait, call,
        started: true, plan: plan);
  }

  Future<ToolResult> _waitForTranscribe(String id, int seconds, ToolCall call,
      {bool started = false, SpeechPlan? plan}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    var lastPercent = -1;
    call.onCancel(() {});
    while (true) {
      final r = transcribeJobs.read(id);
      if (r == null) {
        throw ToolError('There is no transcribe job with job_id "$id".');
      }
      final status = await transcribeJobStatus(r, isAlive: isAlive);
      final active = status == kJobStarting || status == kJobRunning;
      if (active) {
        final percent = (r.progress * 100).floor().clamp(0, 99);
        if (percent > lastPercent) {
          lastPercent = percent;
          call.progress(percent.toDouble(),
              total: 100,
              message: r.message.isEmpty
                  ? 'Transcribing "${r.projectName}": $percent%'
                  : r.message);
        }
      }
      if (!active || call.isCancelled || !DateTime.now().isBefore(deadline)) {
        return _transcribeResult(r, status, started: started, plan: plan);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  ToolResult _transcribeResult(TranscribeJobRecord r, String status,
      {bool started = false, SpeechPlan? plan}) {
    final percent = (r.progress * 100).floor();
    final words = r.items.fold<int>(0, (n, i) => n + i.words);
    final estimated = r.items.any((i) => i.wordTiming == WordTiming.estimated.name);
    final files = r.items
        .map((i) => '- ${p.basename(i.path)}'
            '${i.speaker.isEmpty ? '' : ' (${i.speaker})'}: ${switch (i.state) {
              'done' => '${i.words} words, ${languageName(i.language)}',
              'cached' => 'already transcribed (${i.words} words)',
              'failed' => 'FAILED: ${i.error}',
              'running' => 'working…',
              _ => 'waiting',
            }}')
        .join('\n');
    final String text;
    switch (status) {
      case kJobFinished:
        text = 'Transcribed "${r.projectName}": $words words in '
            '${r.items.length} file(s), with ${r.backendUsed}.\n$files\n'
            '${estimated ? 'Word times are ESTIMATED (this program times whole phrases only): fine for reading, captions and choosing clips; remove_fillers needs allow_estimated_times.\n' : ''}'
            'Read it with get_transcript. Speech recognition makes '
            'mistakes (names, numbers; more with a small pack): do not '
            'quote it as fact.';
      case kJobFailed:
        text = 'Speech-to-text failed: ${r.error}\n$files';
      case kJobCancelled:
        text = 'The transcribe job was stopped.\n$files';
      case kJobLost:
        text = 'The transcribe job stopped without finishing (its process '
            'is gone). Files that were finished kept their transcripts; '
            'call transcribe again for the rest.\n$files';
      default:
        text = '${started ? 'Started' : 'Still working on'} speech-to-text '
            'for "${r.projectName}" (job_id ${r.id}): $percent% done'
            '${r.message.isEmpty ? '' : ' - ${r.message}'}.\n$files\n'
            'It runs in the background. Call get_transcribe_status with '
            'this job_id and wait_seconds $kMaxStatusWait until it says '
            'finished; do not start it again meanwhile.';
    }
    return ToolResult(text,
        isError: status == kJobFailed || status == kJobLost,
        structured: {
          'job_id': r.id,
          'status': status,
          'percent': percent,
          'project_id': r.projectId,
          if (r.message.isNotEmpty) 'doing': r.message,
          'backend': r.backendUsed,
          'language': r.language,
          'quality': r.quality,
          'words': words,
          'wordTimes': estimated ? 'estimated' : 'measured',
          'files': [for (final i in r.items) i.toJson()],
          if (r.error != null) 'error': r.error,
          if (r.errorKind != null) 'errorKind': r.errorKind,
          'runs': r.runner,
        });
  }

  Future<ToolResult> _getTranscribeStatus(
      Map<String, dynamic> a, ToolCall call) async {
    final id = (a['job_id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      final all = transcribeJobs.list().take(10).toList();
      if (all.isEmpty) {
        return const ToolResult('No transcribe jobs yet.',
            structured: {'jobs': <Object>[]});
      }
      final lines = <String>[];
      final data = <Map<String, dynamic>>[];
      for (final r in all) {
        final status = await transcribeJobStatus(r, isAlive: isAlive);
        lines.add('- ${r.id}: "${r.projectName}" $status '
            '${(r.progress * 100).floor()}%');
        data.add({
          'job_id': r.id,
          'project_id': r.projectId,
          'status': status,
          'percent': (r.progress * 100).floor(),
        });
      }
      return ToolResult('Recent transcribe jobs:\n${lines.join('\n')}',
          structured: {'jobs': data});
    }
    return _waitForTranscribe(
        id, ClipForgeTools._i(a, 'wait_seconds') ?? 0, call);
  }

  Future<ToolResult> _cancelTranscribe(
      Map<String, dynamic> a, ToolCall call) async {
    final id = (a['job_id'] as String).trim();
    final r = transcribeJobs.read(id);
    if (r == null) {
      throw ToolError('There is no transcribe job with job_id "$id".');
    }
    if (!r.isActive) {
      return _transcribeResult(r, await transcribeJobStatus(r, isAlive: isAlive));
    }
    transcribeJobs.requestCancel(id);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final now = transcribeJobs.read(id);
      if (now == null || !now.isActive) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final now = transcribeJobs.read(id) ?? r;
    return _transcribeResult(now, await transcribeJobStatus(now, isAlive: isAlive));
  }

  // Reading -----------------------------------------------------------------
  Future<ToolResult> _getTranscript(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    final clipArg = a['clip_id'] as String?;
    final clip = clipArg == null ? null : ClipForgeTools._clip(project, clipArg);
    final speechOf = await _speechOf(loaded, clipId: clip?.id);
    final note = _coverageNote(speechOf.cover);
    final from = ClipForgeTools._i(a, 'from_ms'), to = ClipForgeTools._i(a, 'to_ms');
    if (from != null && to != null && to <= from) {
      throw ToolError('to_ms ($to) must be after from_ms ($from).');
    }
    final format = (a['format'] as String?) ?? 'text';
    final source = a['time_base'] == 'source';
    final offset = ClipForgeTools._i(a, 'offset') ?? 0;
    final limit = (ClipForgeTools._i(a, 'limit') ??
            (format == 'words' ? kDefaultTranscriptWords : kDefaultTranscriptSegments))
        .clamp(1, kMaxTranscriptPage);

    // Rows: (start, end, speaker, text, clip).
    final phrases = <({int s, int e, String who, String text, String clip})>[];
    final words = <({int s, int e, String who, String text, String clip})>[];
    final languages = <String>{};
    var estimated = false;
    String head;
    if (source) {
      final candidates = speechOf.cover.sources
          .where((s) => speechOf.lookup(s.path, s.audioTrack) != null)
          .toList();
      if (candidates.length > 1 && clip == null) {
        throw ToolError('This project has several transcribed files: pass '
            'clip_id to say whose. Files: '
            '${candidates.map(_sourceName).join(', ')}.');
      }
      for (final s in candidates) {
        final t = speechOf.lookup(s.path, s.audioTrack)!;
        languages.add(t.language);
        estimated = estimated || t.wordTiming == WordTiming.estimated;
        for (final seg in t.segments) {
          if (from != null && seg.startMs < from) continue;
          if (to != null && seg.startMs >= to) continue;
          phrases.add((s: seg.startMs, e: seg.endMs, who: s.speaker, text: seg.text, clip: ''));
        }
        for (final w in t.words) {
          if (from != null && w.startMs < from) continue;
          if (to != null && w.startMs >= to) continue;
          words.add((s: w.startMs, e: w.endMs, who: s.speaker, text: w.text, clip: ''));
        }
      }
      head = 'Transcript of ${candidates.map(_sourceName).join(', ')} in '
          'SOURCE time (positions inside the media file)';
    } else {
      final tw = timelineWords(project, speechOf.lookup,
          fromMs: from, toMs: to, clipId: clip?.id);
      for (final s in speechOf.cover.sources) {
        final t = speechOf.lookup(s.path, s.audioTrack);
        if (t != null) languages.add(t.language);
      }
      estimated = tw.any((w) => w.estimated);
      for (final w in tw) {
        words.add((s: w.startMs, e: w.endMs, who: w.speaker, text: w.text, clip: w.clipId));
      }
      for (final seg in timelineSegments(tw)) {
        phrases.add((
          s: seg.startMs,
          e: seg.endMs,
          who: seg.speaker,
          text: seg.text,
          clip: seg.clipId
        ));
      }
      head = 'Transcript of "${project.name}" in TIMELINE time (the video '
          'as it is cut now, ${_mss(project.durationMs)} long)';
    }
    final rows = format == 'words' ? words : phrases;
    final page = rows.skip(offset).take(limit).toList();
    final next = offset + page.length < rows.length ? offset + page.length : null;
    languages.remove('');
    final text = StringBuffer()
      ..writeln('$head: ${format == 'words' ? 'words' : 'phrases'} '
          '${page.isEmpty ? 0 : offset + 1}-${offset + page.length} of '
          '${rows.length}'
          '${languages.isEmpty ? '' : ', language ${languages.map(languageName).join(' / ')}'}'
          '. Times are ms${format == 'text' ? ' (start-end), then [m:ss]' : ''}.');
    if (format == 'text') {
      for (final r in page) {
        text.writeln('${r.s}-${r.e} [${_mss(r.s)}] '
            '${r.who.isEmpty ? '' : '${r.who}: '}${r.text}');
      }
    } else if (format == 'words') {
      // Compact: start:word, a few per line.
      for (var i = 0; i < page.length; i += 10) {
        text.writeln(page
            .skip(i)
            .take(10)
            .map((r) => '${r.s}-${r.e}:${r.text}')
            .join('  '));
      }
    } else {
      text.writeln('(phrases are in the structured result)');
    }
    if (rows.isEmpty) {
      text.writeln('No speech in this part.');
    }
    if (next != null) {
      text.writeln('More: call again with offset $next.');
    }
    final warnings = [
      ?note,
      if (estimated)
        'Word times are estimated from whole phrases (the FFmpeg filter '
            'does not time single words): good to about half a second.',
    ];
    for (final w in warnings) {
      text.writeln('Note: $w');
    }
    return ToolResult(text.toString().trimRight(), structured: {
      'timeBase': source ? 'source' : 'timeline',
      'format': format,
      'total': rows.length,
      'offset': offset,
      'count': page.length,
      'nextOffset': ?next,
      'languages': languages.toList(),
      'wordTimes': estimated ? 'estimated' : 'measured',
      if (format == 'segments')
        'segments': [
          for (final r in page)
            {
              'startMs': r.s,
              'endMs': r.e,
              if (r.who.isNotEmpty) 'speaker': r.who,
              'text': r.text,
              if (r.clip.isNotEmpty) 'clipId': r.clip,
            },
        ],
      if (format == 'words')
        'words': [
          for (final r in page) [r.text, r.s, r.e],
        ],
      if (warnings.isNotEmpty) 'warnings': warnings,
    });
  }

  Future<ToolResult> _findInTranscript(
      Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final speechOf = await _speechOf(loaded);
    final note = _coverageNote(speechOf.cover);
    final phrase = (a['phrase'] as String).trim();
    if (phrase.isEmpty) throw ToolError('phrase is empty.');
    final limit = (ClipForgeTools._i(a, 'limit') ?? 50).clamp(1, kMaxListedHits);
    final words = timelineWords(loaded.project, speechOf.lookup);
    final hits = findPhrase(words, phrase,
        prefix: a['prefix'] == true, limit: kMaxListedHits * 5);
    final shown = hits.take(limit).toList();
    String around(PhraseHit h) {
      final from = (h.first - 6).clamp(0, words.length);
      final to = (h.last + 7).clamp(0, words.length);
      return [
        for (var i = from; i < to; i++)
          if (words[i].speaker == h.words.first.speaker) words[i].text,
      ].join(' ');
    }

    final text = StringBuffer()
      ..writeln(hits.isEmpty
          ? '"$phrase" is not said anywhere in the transcript of '
              '"${loaded.project.name}" (speech recognition may have '
              'written it differently: try one distinctive word, or prefix '
              'true).'
          : '"$phrase" is said ${hits.length} time(s)'
              '${hits.length > shown.length ? ' (first ${shown.length} shown)' : ''}; '
              'timeline times in ms:');
    for (final h in shown) {
      text.writeln('- ${h.startMs}-${h.endMs} [${_mss(h.startMs)}] '
          '${h.words.first.speaker.isEmpty ? '' : '${h.words.first.speaker}: '}'
          '…${around(h)}…');
    }
    if (note != null) text.writeln('Note: $note');
    return ToolResult(text.toString().trimRight(), structured: {
      'phrase': phrase,
      'count': hits.length,
      'hits': [
        for (final h in shown)
          {
            'startMs': h.startMs,
            'endMs': h.endMs,
            'clipId': h.words.first.clipId,
            if (h.words.first.speaker.isNotEmpty) 'speaker': h.words.first.speaker,
            'context': around(h),
          },
      ],
      if (note != null) 'warnings': [note],
    });
  }

  // Editing -----------------------------------------------------------------
  Future<ToolResult> _captionsFromTranscript(
      Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final speechOf = await _speechOf(loaded);
    final note = _coverageNote(speechOf.cover);
    final from = ClipForgeTools._i(a, 'from_ms'), to = ClipForgeTools._i(a, 'to_ms');
    if (from != null && to != null && to <= from) {
      throw ToolError('to_ms ($to) must be after from_ms ($from).');
    }
    final options = CaptionOptions(
      maxLineChars: ClipForgeTools._i(a, 'max_line_chars') ?? 37,
      maxLines: ClipForgeTools._i(a, 'max_lines') ?? 2,
      minMs: ClipForgeTools._i(a, 'min_duration_ms') ?? 1000,
      maxMs: ClipForgeTools._i(a, 'max_duration_ms') ?? 6000,
    );
    final language = _languageOf(speechOf);
    return _edit(a, (e) {
      final project = e.project;
      final template = ClipForgeTools._titleStyle(captionTemplate(project), a);
      final words =
          timelineWords(project, speechOf.lookup, fromMs: from, toMs: to);
      final cues = buildCaptions(words,
          options: options,
          skip: a['keep_filler_sounds'] == true
              ? null
              : isFillerSound(fillersFor(language)),
          lineFits: captionLineFits(project, template));
      if (cues.isEmpty) {
        throw ToolError('No speech was found in that part of the video, so '
            'there are no captions to make.');
      }
      final existing = captionsInRange(project, fromMs: from, toMs: to);
      final replace = a['replace_existing'] == true;
      final titles = captionTitles(cues, template, newId: _newId);
      addSpeechCaptions(e, titles,
          replaceIds: replace ? [for (final t in existing) t.id] : const []);
      final notes = [
        ?note,
        if (existing.isNotEmpty && !replace)
          '${existing.length} caption(s) were already in that part and '
              'are still there, so some may now overlap: undo and pass '
              'replace_existing true to swap them.',
        if (existing.isNotEmpty && replace)
          '${existing.length} earlier caption(s) in that part were replaced.',
      ];
      return _Done(
          'Added ${cues.length} caption(s) from the speech '
          '(${languageName(language)}), ${_mss(cues.first.startMs)} to '
          '${_mss(cues.last.endMs)}. First ones: '
          '${cues.take(3).map((c) => '"${c.text.replaceAll('\n', ' / ')}"').join(', ')}.'
          '${notes.isEmpty ? '' : ' ${notes.join(' ')}'}',
          {
            'captionCount': cues.length,
            'language': language,
            'captions': [
              for (final c in cues.take(kMaxListedHits))
                {'startMs': c.startMs, 'endMs': c.endMs, 'text': c.text},
            ],
            if (cues.length > kMaxListedHits) 'captionsListed': kMaxListedHits,
          },
          replace);
    });
  }

  /// The language most of the project's transcripts are in ('' unknown).
  String _languageOf(({TranscriptLookup lookup, TranscriptCoverage cover}) s) {
    final count = <String, int>{};
    for (final src in s.cover.sources) {
      final t = s.lookup(src.path, src.audioTrack);
      if (t != null && t.language.isNotEmpty) {
        count[t.language] = (count[t.language] ?? 0) + t.wordCount + 1;
      }
    }
    if (count.isEmpty) return '';
    return (count.entries.toList()..sort((x, y) => y.value.compareTo(x.value)))
        .first
        .key;
  }

  /// The jump scores of [hits] (by index); empty when they cannot be
  /// measured. A cut under a full-frame overlay shows no jump: 0.
  Future<Map<int, double>> _jumpScores(Project project, List<FillerHit> hits) async {
    final out = <int, double>{};
    final byPath = <String, List<int>>{};
    final clipOf = {for (final c in project.clips) c.id: c};
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final clip = clipOf[h.clipId];
      if (clip == null) continue;
      final over = project.overlayAt(h.startMs);
      if (over != null && over.layout == OverlayLayout.full) {
        out[i] = 0;
        continue;
      }
      (byPath[clip.path] ??= []).add(i);
    }
    if (byPath.isEmpty) return out;
    final MediaEngine engine;
    try {
      engine = await media.requireEngine();
    } on ToolError {
      return out;
    }
    if (engine is! JumpCheckEngine) return out;
    for (final e in byPath.entries) {
      try {
        final scores = await (engine as JumpCheckEngine).jumpScores(e.key, [
          for (final i in e.value)
            (beforeMs: hits[i].cutStartMs - 40, afterMs: hits[i].cutEndMs + 10),
        ]);
        for (var k = 0; k < e.value.length; k++) {
          final v = scores[k];
          if (v != null) out[e.value[k]] = v;
        }
      } catch (_) {
        // Not measured: those cuts are treated as unknown.
      }
    }
    return out;
  }

  Future<ToolResult> _removeFillers(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final speechOf = await _speechOf(loaded);
    final note = _coverageNote(speechOf.cover);
    final project = loaded.project;
    final clipArg = a['clip_id'] as String?;
    final clip = clipArg == null || clipArg == 'all'
        ? null
        : ClipForgeTools._clip(project, clipArg);
    final language = languageCode(a['language'] as String?).isNotEmpty
        ? languageCode(a['language'] as String?)
        : _languageOf(speechOf);
    final custom = [
      for (final f in (a['fillers'] as List?) ?? const [])
        if ('$f'.trim().isNotEmpty) '$f'.trim(),
    ];
    final base = fillersFor(language);
    final list = custom.isNotEmpty
        ? FillerList(language: language, sounds: custom)
        : (a['include_word_fillers'] == true
            ? FillerList(
                language: language, sounds: [...base.sounds, ...base.words])
            : FillerList(language: language, sounds: base.sounds));
    final strength = CutStrength.parse(a['strength']);
    final rules = CutRules.of(strength).copyWith(
      minCutMs: ClipForgeTools._i(a, 'min_cut_ms'),
      minDistanceMs: ClipForgeTools._i(a, 'min_distance_ms'),
      maxPerMinute: ClipForgeTools._i(a, 'max_cuts_per_minute'),
      minPieceMs: ClipForgeTools._i(a, 'min_piece_ms'),
    );
    final words = timelineWords(project, speechOf.lookup,
        fromMs: ClipForgeTools._i(a, 'from_ms'),
        toMs: ClipForgeTools._i(a, 'to_ms'),
        clipId: clip?.id);
    final hits = findFillers(words, list,
        padMs: ClipForgeTools._i(a, 'pad_ms') ?? 40);
    final estimated = hits.any((h) => h.estimated);
    final dryRun = a['dry_run'] != false;
    if (!dryRun && estimated && a['allow_estimated_times'] != true) {
      throw ToolError('Nothing was cut: the word times of this transcript '
          'are only estimated (it was made by a program that times whole '
          'phrases), so cuts could clip the words next to a filler. '
          'Transcribe again with a program that times words (whisper.cpp, '
          'faster-whisper: see get_status), or pass allow_estimated_times '
          'true and check the result by ear.');
    }
    final jumps = a['jump_check'] == false || hits.isEmpty
        ? const <int, double>{}
        : await _jumpScores(project, hits);
    final plan = planFillerCuts(project, hits, rules, jumps: jumps);
    final sum = CutSummary(plan, project.durationMs);
    final cut = [
      for (final c in plan)
        if (c.isCut) c,
    ];
    final groups = groupFillers([for (final c in cut) c.hit]);
    // The cuts most worth watching: highest jump, then shortest.
    final risky = [...cut]..sort((x, y) {
        final d = (y.jump ?? 0).compareTo(x.jump ?? 0);
        return d != 0 ? d : x.hit.cutMs.compareTo(y.hit.cutMs);
      });
    final viaFilter = speechOf.cover.sources.any((src) =>
        speechOf.lookup(src.path, src.audioTrack)?.backend ==
        FfmpegWhisperBackend.kId);
    Map<String, dynamic> row(PlannedCut c) => {
          'text': c.hit.text,
          'startMs': c.hit.startMs,
          'endMs': c.hit.endMs,
          'cutMs': c.hit.cutMs,
          'clipId': c.hit.clipId,
          if (c.hit.speaker.isNotEmpty) 'speaker': c.hit.speaker,
          if (c.jump != null) 'jump': double.parse(c.jump!.toStringAsFixed(2)),
          if (c.jump != null) 'jumpRating': c.jumpRating,
          if (c.smooth) 'smoothed': true,
        };
    final data = <String, dynamic>{
      'strength': strength.name,
      'found': sum.found,
      'fillerCount': sum.cuts,
      'totalMs': sum.savedMs,
      'cutsPerMinute': double.parse(sum.cutsPerMinute.toStringAsFixed(1)),
      'skippedTooClose': sum.skippedTooClose,
      'skippedJumpy': sum.skippedJumpy,
      'skippedTooSmall': sum.skippedSmall,
      if (sum.skippedUnderSpeech > 0)
        'skippedUnderOtherSpeaker': sum.skippedUnderSpeech,
      'smoothedWithDissolve': sum.smoothed,
      'jumpChecked': jumps.isNotEmpty,
      'language': language,
      'wordTimes': estimated ? 'estimated' : 'measured',
      'groups': [
        for (final g in groups)
          {'filler': g.entry, 'count': g.count, 'totalMs': g.totalMs},
      ],
      'riskiest': [for (final c in risky.take(5)) row(c)],
      'fillers': [for (final c in cut.take(kMaxListedHits)) row(c)],
      if (cut.length > kMaxListedHits) 'fillersListed': kMaxListedHits,
      'rules': {
        'minCutMs': rules.minCutMs,
        'minDistanceMs': rules.minDistanceMs,
        'maxCutsPerMinute': rules.maxPerMinute,
        'minPieceMs': rules.minPieceMs,
      },
    };
    final notes = [
      ?note,
      if (jumps.isEmpty && hits.isNotEmpty && a['jump_check'] != false)
        'The picture could not be checked for jumps (FFmpeg not found or '
            'the frames could not be read), so no cut was left out or '
            'smoothed for that: watch the result.',
      if (sum.cutsPerMinute > kCutBudgetPerMinute)
        'That is more than ${kCutBudgetPerMinute.round()} cuts a minute, '
            'which looks jumpy when the speaker is seen: tell the user, or '
            'use a lighter strength.',
      if (estimated)
        'Word times are ESTIMATED: cutting needs allow_estimated_times '
            'true and may clip neighbouring words.',
      if (viaFilter)
        'This transcript was made by the FFmpeg filter, which cannot be '
            'told to keep hesitation sounds and usually leaves them out, so '
            'few or none are found, and it does not time single words. '
            'whisper.cpp (whisper-cli) or faster-whisper (pip install '
            'whisper-ctranslate2) keep more of them and time every word: '
            'once one is installed, transcribe again with force true.',
      if (hits.isEmpty)
        'None found. Speech programs often leave "um" and "uh" out of the '
            'text, so there may still be some in the sound; '
            'remove_silences shortens the pauses around them.',
    ];
    return _edit({...a, 'dry_run': dryRun}, (e) {
      if (hits.isEmpty) {
        return _Done('No filler words found in the transcript '
            '(${languageName(language)} list). ${notes.join(' ')}', data);
      }
      final ids = <String>[];
      if (cut.isNotEmpty) {
        final before = {for (final c in e.project.autoCuts) c.id};
        applyPlannedCuts(e, plan, by: 'claude', newId: _newId);
        ids.addAll([
          for (final c in e.project.autoCuts)
            if (!before.contains(c.id)) c.id,
        ]);
      }
      final summary = groups
          .map((g) => '"${g.entry}" x${g.count}')
          .join(', ');
      final left = [
        if (sum.skippedTooClose > 0)
          '${sum.skippedTooClose} because another cut is too close',
        if (sum.skippedJumpy > 0)
          '${sum.skippedJumpy} because the picture would jump',
        if (sum.skippedSmall > 0)
          '${sum.skippedSmall} too short or inside fast speech',
        if (sum.skippedUnderSpeech > 0)
          '${sum.skippedUnderSpeech} under another speaker',
      ];
      return _Done(
          '${dryRun ? 'Would remove' : 'Removed'} ${sum.cuts} of ${sum.found} '
          'filler word(s) (strength ${strength.name}): '
          '${sum.perMinuteText} cut(s) a minute, saving '
          '${(sum.savedMs / 1000).toStringAsFixed(1)} s'
          '${summary.isEmpty ? '' : ' ($summary)'}.'
          '${left.isEmpty ? '' : ' Left in: ${left.join('; ')}.'}'
          '${sum.smoothed > 0 ? ' ${sum.smoothed} got a short dissolve (slight picture change).' : ''}'
          '${risky.isEmpty ? '' : ' Riskiest to watch (timeline): ${risky.take(5).map((c) => '${_mss(c.hit.startMs)}${c.jump == null ? '' : ' (${c.jumpRating})'}').join(', ')}.'}'
          '${dryRun ? ' Tell the user these numbers; to cut, call again with dry_run false.' : ' Each cut can be put back with restore_cut (list_auto_cuts).'}'
          '${notes.isEmpty ? '' : ' ${notes.join(' ')}'}',
          {...data, 'cuts': sum.cuts, if (!dryRun) 'cutIds': ids.take(kMaxListedHits).toList()});
    });
  }

  Future<ToolResult> _listAutoCuts(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    final kind = a['kind'] as String?;
    final all = [
      for (final c in project.autoCuts)
        if (kind == null || c.kind == kind) c,
    ];
    if (a['sort'] == 'risk') {
      all.sort((x, y) => (y.jump ?? -1).compareTo(x.jump ?? -1));
    } else {
      all.sort((x, y) {
        final d = x.path.compareTo(y.path);
        return d != 0 ? d : x.startMs.compareTo(y.startMs);
      });
    }
    final offset = ClipForgeTools._i(a, 'offset') ?? 0;
    final limit = (ClipForgeTools._i(a, 'limit') ?? 50).clamp(1, 300);
    final page = all.skip(offset).take(limit).toList();
    final next = offset + page.length < all.length ? offset + page.length : null;
    final totals = autoCutTotals(project);
    final text = StringBuffer()
      ..writeln(project.autoCuts.isEmpty
          ? 'No automatic cuts are recorded in "${project.name}".'
          : '"${project.name}" has ${totals.count} automatic cut(s): '
              '${project.autoCuts.where((c) => c.kind == 'filler').length} filler(s), '
              '${project.autoCuts.where((c) => c.kind == 'silence').length} silence(s), '
              '${project.autoCuts.where((c) => c.kind == 'text').length} cut(s) from the text; '
              '${(totals.savedMs / 1000).toStringAsFixed(1)} s removed, '
              '${totals.perMinute.toStringAsFixed(1)} cut(s) a minute.');
    for (final c in page) {
      text.writeln('- ${c.id}: ${c.kind}'
          '${c.word.isEmpty ? '' : ' "${c.word}"'}, ${p.basename(c.path)} '
          '${c.startMs}-${c.endMs} ms (${c.lengthMs} ms), by ${c.by}'
          '${c.jump == null ? '' : ', jump ${c.jump!.toStringAsFixed(2)} (${jumpRatingOf(c.jump)})'}'
          '${c.smoothed ? ', dissolve' : ''}');
    }
    if (next != null) text.writeln('More: call again with offset $next.');
    return ToolResult(text.toString().trimRight(), structured: {
      'count': totals.count,
      'savedMs': totals.savedMs,
      'cutsPerMinute': double.parse(totals.perMinute.toStringAsFixed(1)),
      'total': all.length,
      'offset': offset,
      'nextOffset': ?next,
      'cuts': [
        for (final c in page)
          {
            'id': c.id,
            'kind': c.kind,
            if (c.word.isNotEmpty) 'word': c.word,
            'file': p.basename(c.path),
            'sourceStartMs': c.startMs,
            'sourceEndMs': c.endMs,
            'by': c.by,
            'at': c.at.toUtc().toIso8601String(),
            if (c.jump != null) 'jump': double.parse(c.jump!.toStringAsFixed(2)),
            if (c.jump != null) 'jumpRating': jumpRatingOf(c.jump),
            'smoothed': c.smoothed,
          },
      ],
    });
  }

  Future<ToolResult> _restoreCut(Map<String, dynamic> a, ToolCall call) {
    final id = (a['cut_id'] as String).trim();
    return _edit(a, (e) {
      if (id == 'all') {
        final kind = a['kind'] as String?;
        final n = restoreAllAutoCuts(e, kind: kind, newId: _newId);
        final left = e.project.autoCuts
            .where((c) => kind == null || c.kind == kind)
            .length;
        return _Done(
            n == 0
                ? 'There are no automatic cuts to put back.'
                : 'Put back $n automatic cut(s); the video is '
                    '${_mss(e.project.durationMs)} long again.'
                    '${left > 0 ? ' $left could not be put back (no clip of that file is left).' : ''}',
            {'restored': n, 'left': left});
      }
      final result = restoreAutoCut(e, id, newId: _newId);
      switch (result) {
        case RestoreResult.unknown:
          throw ToolError('There is no automatic cut with the id "$id" '
              '(list_auto_cuts shows them).');
        case RestoreResult.failed:
          throw ToolError('That cut cannot be put back: no clip of its file '
              'is left in the project.');
        case RestoreResult.healed:
          return _Done('Put the cut back: the two pieces around it are one '
              'clip again.', {'restored': 1, 'how': 'healed'});
        case RestoreResult.asClip:
          return _Done(
              'Put the removed part back as a clip of its own (the pieces '
              'around it had changed since the cut).',
              {'restored': 1, 'how': 'clip'});
      }
    });
  }

  Future<ToolResult> _makeShort(Map<String, dynamic> a, ToolCall call) async {
    final source = await _load(a['project_id']);
    var from = ClipForgeTools._i(a, 'from_ms')!, to = ClipForgeTools._i(a, 'to_ms')!;
    final total = source.project.durationMs;
    if (from < 0 || to > total + 50 || to - from < 1000) {
      throw ToolError('from_ms..to_ms must be a part of the video of at '
          'least 1000 ms (the video is $total ms long).');
    }
    final shape = kAspectNames[a['shape'] ?? '9:16'];
    if (shape == null) {
      throw ToolError('Unknown shape "${a['shape']}". Shapes: '
          '${kAspectNames.keys.join(', ')}.');
    }
    final shortStyle = a['caption_style'] == 'short';
    final warnings = <String>[];
    final notes = <String>[];
    // What is said in the long video: for snapping and the warnings.
    final spoken = await _spokenOf(source);
    if (a['snap_to_speech'] == true) {
      final pauses = await _pausesOf(source.project, spoken.items);
      final snapped = snapShortRange(from, to,
          pauses: pauses.pauses,
          words: [
            for (final s in spoken.items) (startMs: s.startMs, endMs: s.endMs),
          ],
          totalMs: total);
      if (snapped.movedStart || snapped.movedEnd) {
        notes.add('Moved outward to the pauses '
            '(${pauses.fromSound ? 'from the sound' : 'between the ${spoken.source == 'transcript' ? 'words' : 'captions'}'}): '
            '$from-$to became ${snapped.fromMs}-${snapped.toMs}.');
        from = snapped.fromMs;
        to = snapped.toMs;
      } else {
        notes.add('The start and end already were in pauses.');
      }
    }
    if (spoken.items.any((s) => endsSentence(s.text))) {
      if (startsMidSentence(spoken.items, from)) {
        warnings.add('The short starts in the middle of a sentence '
            '(${_mss(from)}): move from_ms to where the sentence begins '
            '(get_transcript / suggest_shorts give the times).');
      }
      if (endsMidSentence(spoken.items, to)) {
        warnings.add('The short ends before its last sentence is finished '
            '(${_mss(to)}): move to_ms to the end of the sentence.');
      }
    }
    final given = (a['name'] as String?)?.trim() ?? '';
    final name = given.isNotEmpty
        ? given
        : '${source.project.name} - short ${_mss(from)}';
    final Project copy;
    try {
      copy = await store.duplicate(source.project.id, name: name);
    } on FileSystemException catch (e) {
      throw ToolError('The project could not be copied: ${e.message}');
    }
    final copyDir = p.join(store.rootPath, copy.id);
    // A short starts without the long video's notes and markers.
    final e = ProjectEditor(
        copy.copyWith(publishing: PublishingNotes.empty, markers: const []),
        newId: _newId);
    final speechOf = await _speechOf(_Loaded(
        copy, File(p.join(copyDir, FileProjectStore.projectFileName)), ''));
    final transcribed = speechOf.cover.sources.isNotEmpty && !speechOf.cover.none;
    final language = transcribed ? _languageOf(speechOf) : '';
    final built = buildShort(e,
        fromMs: from,
        toMs: to,
        shape: shape,
        captions: a['captions'] != false,
        shortCaptions: shortStyle,
        title: (a['title'] as String?) ?? '',
        words: (short) =>
            transcribed ? timelineWords(short, speechOf.lookup) : null,
        skipWord: transcribed ? isFillerSound(fillersFor(language)) : null,
        newId: _newId);
    if (!built.ok) {
      throw ToolError('That part holds no video; nothing was kept. (An '
          'empty project "$name" was left: project_id ${copy.id}.)');
    }
    if (built.captionsKept > 0) {
      notes.add('The part already had ${built.captionsKept} caption(s); '
          'they were kept and no new ones were made.');
    } else if (built.notTranscribed) {
      notes.add('No captions were added: this part is not transcribed '
          '(call transcribe on the original first, then '
          'captions_from_transcript on the short).');
    } else if (built.nothingSaid) {
      notes.add('No captions were added: nothing is said in this part.');
    }
    if (shortStyle && built.captionsAfter > 0) {
      notes.add('The captions have the "Short" look (bigger, lower middle, '
          'outlined, at most two lines'
          '${built.captionsAfter != built.captionsKept + built.captionsFromSpeech ? '; long ones were divided: ${built.captionsAfter} now' : ''}).');
    }
    if (built.titleAdded) notes.add('The title is at the top for the whole short.');
    final result = e.project;
    if (result.durationMs > kShortMaxSeconds * 1000 + 500) {
      warnings.add('The short is ${_mss(result.durationMs)} long: more than '
          'the $kShortMaxSeconds s that is safe on Shorts, Reels and TikTok '
          '(each site has its own limit and changes it; check the site, or '
          'make it shorter).');
    }
    try {
      await store.save(result);
      recordClaudeEdit(
          copyDir,
          await File(p.join(copyDir, FileProjectStore.projectFileName))
              .readAsString(),
          'make_short');
    } on FileSystemException catch (err) {
      throw ToolError('The short could not be saved: ${err.message}');
    }
    final size = result.canvasSize;
    final captionCount = built.captionsFromSpeech;
    return _projectResult(
        'Made the short "${result.name}" (project_id ${result.id}) from '
        '${_mss(from)}-${_mss(to)} of "${source.project.name}": '
        '${_mss(result.durationMs)} long, ${aspectName(result.aspect)}, '
        '${size.width}x${size.height}'
        '${captionCount > 0 ? ', $captionCount captions from the speech' : ''}. '
        'The original is unchanged. Export it with export_video or '
        'export_kit ("shorts").'
        '${ClipForgeTools._numbered(result.name, name, name)}'
        '${notes.isEmpty ? '' : ' ${notes.join(' ')}'}',
        result,
        detail: a['detail'] as String?,
        warnings: warnings,
        extra: {
          'changed': true,
          'newProjectId': result.id,
          'sourceProjectId': source.project.id,
          'fromMs': from,
          'toMs': to,
          'captionCount': captionCount,
          if (shortStyle) 'captionStyle': 'short',
          if (built.titleAdded) 'title': (a['title'] as String).trim(),
        },
        maxTitles: kSummaryTitles);
  }

  // get_status ---------------------------------------------------------------

  /// What speech-to-text can use on this computer (text and data).
  Future<({String text, Map<String, dynamic> data})> _speechStatus() async {
    final backends = await speech.available();
    final packs = speech.models.installed;
    final own = speech.models.userModel;
    final running = [
      for (final r in transcribeJobs.list())
        if (r.isActive) r,
    ];
    final text = StringBuffer('Speech-to-text (transcribe): ');
    if (backends.isEmpty) {
      text.writeln('NO speech program found. ${noBackendExplanation(Platform.operatingSystem)}');
    } else {
      text.writeln('${backends.length} program(s) found:');
      for (final b in backends) {
        text.writeln('  - ${b.id}: ${b.label}, ${b.program}; word times '
            '${b.measuresWords ? 'measured' : 'estimated from phrases'}; '
            '${b.usesPacks ? 'uses ClipForge\'s language packs' : 'has its own models'}.');
      }
    }
    text.writeln('  Language packs in ${speech.models.dir}: '
        '${packs.isEmpty && own == null ? 'none yet (transcribe says which is needed and asks before any download)' : [
            for (final m in packs)
              '${m.model.id} (${m.model.size.label}, ${bytesLabel(m.sizeBytes)}, ${m.model.englishOnly ? 'English only' : 'all languages'})',
            if (own != null) 'the user\'s own file ${own.path}',
          ].join(', ')}'
        '${packs.isEmpty ? '' : '; ${bytesLabel(speech.models.usedBytes)} used'}.');
    if (running.isNotEmpty) {
      text.writeln('  Running: ${running.map((r) => '${r.id} "${r.projectName}" ${(r.progress * 100).floor()}%').join(', ')}.');
    }
    return (
      text: text.toString().trimRight(),
      data: {
        'backends': [for (final b in backends) b.toJson()],
        'modelsDir': speech.models.dir,
        'packs': [
          for (final m in packs)
            {
              'id': m.model.id,
              'size': m.model.size.name,
              'bytes': m.sizeBytes,
              'path': m.path,
              'languages': m.model.englishOnly ? 'en' : 'all',
            },
        ],
        'ownModelFile': ?own?.path,
        'packsBytes': speech.models.usedBytes,
        'availablePacks': [
          for (final m in speech.models.table)
            {
              'id': m.id,
              'size': m.size.name,
              'download': m.sizeLabel,
              'languages': m.englishOnly ? 'en' : 'all',
              'installed': packs.any((x) => x.model.id == m.id),
            },
        ],
        'runningJobs': [for (final r in running) r.id],
        if (backends.isEmpty)
          'needed': noBackendExplanation(Platform.operatingSystem),
      },
    );
  }
}
