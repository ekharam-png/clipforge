// The "part of the timeline" tools (1.17): edit_part (cut out, delete,
// silence, lower, speed, clean, duplicate - ONE tool with an `action`,
// because all of them take the same from_ms / to_ms / rows and follow the
// same rules), list_quiet_parts / remove_quiet_part, and
// set_only_when_speaking. Part of tools.dart.
//
// DECISION on the tool count: one `edit_part` instead of cut_part,
// silence_part, speed_part, clean_part, delete_part. Seven tools with the
// same arguments would add seven schemas to every conversation for no
// more than an enum says; the answer names what was done either way.
part of 'tools.dart';

const List<String> kPartToolActions = [
  'cut_out',
  'delete',
  'silence',
  'lower',
  'speed',
  'clean',
  'duplicate',
];

extension _PartTools on ClipForgeTools {
  List<ToolDef> get _partToolDefs => [
        ToolDef(
          name: 'edit_part',
          title: 'Act on a part of the timeline',
          description:
              'Does something to ONE stretch of the timeline, from_ms..to_ms '
              '(across clip boundaries; clips are split at the edges where '
              'needed; titles, captions, markers and linked voices follow by '
              'the usual rules). One undo step. `action`:\n'
              '- "cut_out": removes that time from EVERYTHING and closes '
              'the gap (video, every sound track, overlays, titles). Needs '
              'every row (do not pass `rows`): cutting only some rows would '
              'leave lips and voice out of step. Logged like an automatic '
              'cut (kind "part" in list_auto_cuts; restore_cut puts it '
              'back).\n'
              '- "silence": no sound there on the given rows; NO time '
              'moves. Short fades (40 ms) so nothing clicks. Use it to take '
              'out a cough or a remark on one microphone while the others '
              'play on.\n'
              '- "lower": the same with a level (level_db, e.g. -12).\n'
              '- "delete": removes the part from the given rows and leaves '
              'a gap (music, effects, overlays, titles and captions). Not '
              'for the video row (the main track has no gaps) and not for '
              'sound that follows a clip (linked voice, separated sound): '
              'use "silence" there.\n'
              '- "speed": slow motion or faster for the part (speed 0.25..4). '
              'The clip\'s own sound and linked voices follow; music and '
              'other sound keep their speed and place. mute_own_sound true '
              'switches that part\'s own sound off (default for speeds '
              'below 0.5).\n'
              '- "clean": "Clean up sound" for the part only, on the given '
              'sound rows (the video is split at the part\'s edges).\n'
              '- "duplicate": a copy of the part right after it.\n'
              '`rows` says which rows it applies to: "video" (the main '
              'track and its own sound), "overlay", "titles", and sound '
              'tracks by track_id or name (list_sound_tracks). Leave it out '
              'for everything. The answer names the rows that were changed '
              'and, for rows that could not be, why. dry_run true reports '
              'without saving.$_editNote',
          properties: {
            'project_id': _projectId,
            'action': _str('What to do with the part.',
                values: kPartToolActions),
            'from_ms': _int('Start of the part on the timeline, in ms.', min: 0),
            'to_ms': _int('End of the part on the timeline, in ms.', min: 0),
            'rows': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'The rows: "video", "overlay", "titles", '
                  'track ids or names. Default: every row.',
            },
            'level_db': _num('For "lower": how much quieter, in dB (-1..-40; '
                'default -12).', min: -40, max: -1),
            'speed': _num('For "speed": 0.25..4 (1 = normal).', min: 0.25, max: 4),
            'mute_own_sound': _bool('For "speed": switch the part\'s own '
                'sound off. Default: true below 0.5, else false.'),
            'dry_run': _bool('true: report what would change, save nothing.'),
          },
          required: const ['project_id', 'action', 'from_ms', 'to_ms'],
          destructive: true,
          handler: _editPart,
        ),
        ToolDef(
          name: 'list_quiet_parts',
          title: 'List silenced and lowered parts',
          description:
              'The stretches that edit_part "silence" / "lower" made quiet, '
              'per item (a video clip\'s own sound, a sound, an overlay): '
              'item_id, what it is, its row, where it lies on the timeline '
              '(from_ms..to_ms) and in its file (source_from_ms..'
              'source_to_ms), and the level ("silent" or dB). Also says '
              'which speech tracks have "Only when speaking" on.',
          properties: {'project_id': _projectId},
          required: const ['project_id'],
          readOnly: true,
          idempotent: true,
          handler: _listQuietParts,
        ),
        ToolDef(
          name: 'remove_quiet_part',
          title: 'Give a quiet part its sound back',
          description:
              'Undoes "silence" / "lower" for one item (item_id from '
              'list_quiet_parts): between source_from_ms and source_to_ms '
              'of its file it plays at its own level again; leave both out '
              'for every quiet part of the item. One undo step.$_editNote',
          properties: {
            'project_id': _projectId,
            'item_id': _str('The clip, sound or overlay (from '
                'list_quiet_parts).'),
            'source_from_ms': _int('Start in the item\'s FILE, in ms.'),
            'source_to_ms': _int('End in the item\'s FILE, in ms.'),
            'dry_run': _bool('true: report only, save nothing.'),
          },
          required: const ['project_id', 'item_id'],
          handler: _removeQuietPart,
        ),
        ToolDef(
          name: 'set_only_when_speaking',
          title: 'Only when speaking (a gate per microphone)',
          description:
              'Switches "Only when speaking" on or off for a speech track: '
              'that microphone is turned down while its own speaker is not '
              'talking, so the other people, breathing and the room are not '
              'mixed in from it. It follows the speech map (get_speech_map: '
              'loudness, with voices that bleed into another microphone '
              'left out), opens 80 ms before the talk and stays open 200 ms '
              'after it; pauses under 0.4 s stay open. room_db is what is '
              'left between the turns (default -18: a little room sound '
              'sounds more natural than dead silence; -100 = silence). It '
              'is applied in the export (and in the app\'s preview); '
              'nothing on the timeline is cut. It goes by loudness, not by '
              'words: tell the user to listen to a stretch. Use it when a '
              'project has two or more voice tracks recorded together.'
              '$_editNote',
          properties: {
            'project_id': _projectId,
            'track_id': _str('The speech track (track_id or its name), or '
                '"all" for every speech track.'),
            'on': _bool('true: on; false: off. Default true.'),
            'room_db': _num('What is left between the turns, in dB '
                '(-100..-3; default -18).', min: -100, max: -3),
            'dry_run': _bool('true: report only, save nothing.'),
          },
          required: const ['project_id', 'track_id'],
          idempotent: true,
          handler: _setOnlyWhenSpeaking,
        ),
      ];

  /// The row ids `rows` names (null: every row); a name that matches no
  /// row is an error that lists the rows.
  Set<String>? _partRows(Project project, Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final rows = partRowsOf(project);
    final out = <String>{};
    for (final r in raw) {
      final text = '$r'.trim();
      final lower = text.toLowerCase();
      final hit = rows.where((x) => x.id == text).firstOrNull ??
          rows.where((x) => x.name.toLowerCase() == lower).firstOrNull ??
          (lower == 'titles' || lower == 'captions'
              ? rows.where((x) => x.id == kRowTitles).firstOrNull
              : null);
      if (hit == null) {
        throw ToolError('There is no row "$text". Rows: '
            '${rows.map((x) => x.kind == PartRowKind.sound ? '"${x.name}" (track_id ${x.id})' : '"${x.id}"').join(', ')}.');
      }
      out.add(hit.id);
    }
    return out;
  }

  static String _sentenceOf(String reason) =>
      '${reason[0].toUpperCase()}${reason.substring(1)}.';

  /// "Changed: Video, Sam. Not: Music (music and other sound keep their
  /// speed)."
  String _rowReport(Project p, TimelinePart part, PartAction action,
      Set<String>? rows) {
    if (action == PartAction.cutOut || action == PartAction.duplicate) return '';
    final yes = <String>[], no = <String>[];
    for (final r in partRowsOf(p)) {
      if (!rowTicked(rows, r.id)) continue;
      final why = partRowProblem(p, part, action, r);
      why == null ? yes.add(r.name) : no.add('${r.name} ($why)');
    }
    return [
      if (yes.isNotEmpty) ' Rows: ${yes.join(', ')}.',
      if (no.isNotEmpty) ' Left alone: ${no.join('; ')}.',
    ].join();
  }

  Future<ToolResult> _editPart(Map<String, dynamic> a, ToolCall call) {
    final from = ClipForgeTools._i(a, 'from_ms')!;
    final to = ClipForgeTools._i(a, 'to_ms')!;
    if (to <= from) throw ToolError('to_ms ($to) must be after from_ms ($from).');
    final action = '${a['action']}';
    return _edit(a, (e) {
      final before = e.project;
      final part = TimelinePart(from, to);
      final rows = _partRows(before, a['rows']);
      final len = _mss(part.lengthMs);
      final at = '${_mss(from)}–${_mss(to)}';
      PartResult r;
      String message;
      PartAction kind;
      final extra = <String, dynamic>{'action': action, 'fromMs': from, 'toMs': to};
      switch (action) {
        case 'cut_out':
          kind = PartAction.cutOut;
          if (rows != null && !allRowsTicked(before, rows)) {
            throw ToolError('cut_out removes time, so it works on every row '
                '(leave `rows` out): with only some rows, lips and voice '
                'would no longer match afterwards. For some rows only, use '
                'action "silence" or "delete".');
          }
          r = e.cutPart(part, by: 'claude');
          message = 'Cut $at out of everything and closed the gap: the video '
              'is ${_mss(e.project.durationMs)} long now '
              '(${_mss(r.removedMs)} shorter). restore_cut can put it back.';
          extra['removedMs'] = r.removedMs;
          extra['cutIds'] = [
            for (final c in e.project.autoCuts)
              if (!before.autoCuts.any((x) => x.id == c.id)) c.id,
          ];
        case 'delete':
          kind = PartAction.deleteGap;
          r = e.deletePart(part, rows: rows);
          message = 'Removed $at ($len) and left a gap; nothing moved.';
        case 'silence':
          kind = PartAction.silence;
          r = e.silencePart(part, rows: rows);
          message = 'Set $at ($len) to silence; nothing moved.';
        case 'lower':
          kind = PartAction.lower;
          final db = (a['level_db'] as num?)?.toDouble() ?? -12.0;
          r = e.silencePart(part, rows: rows, level: levelFromDb(db));
          message = 'Set $at ($len) to ${db.round()} dB; nothing moved.';
          extra['levelDb'] = db;
        case 'speed':
          kind = PartAction.speed;
          final speed = (a['speed'] as num?)?.toDouble();
          if (speed == null) {
            throw ToolError('action "speed" needs `speed` (0.25..4).');
          }
          final mute = a['mute_own_sound'] as bool? ?? speed < 0.5;
          r = e.speedPart(part, speed, muteOwnSound: mute, rows: rows);
          final now = r.part;
          message = 'Set the speed of $at to ${speed}x'
              '${mute ? ', its own sound off' : ''}: that part now runs '
              '${now == null ? '' : '${_mss(now.startMs)}–${_mss(now.endMs)}, '}'
              'the video is ${_mss(e.project.durationMs)} long. Music and '
              'other free sound kept their speed and place.';
          if (now != null) {
            extra['partNow'] = {'fromMs': now.startMs, 'toMs': now.endMs};
          }
        case 'clean':
          kind = PartAction.clean;
          r = e.cleanPart(part, rows: rows);
          message = 'Set "Clean up sound" on for $at ($len) only.';
        case 'duplicate':
          kind = PartAction.duplicate;
          r = e.duplicatePart(part);
          final now = r.part;
          message = 'Added a copy of $at right after it'
              '${now == null ? '' : ' (${_mss(now.startMs)}–${_mss(now.endMs)})'}.';
          if (now != null) {
            extra['copy'] = {'fromMs': now.startMs, 'toMs': now.endMs};
          }
        default:
          throw ToolError('action must be one of '
              '${kPartToolActions.join(', ')}.');
      }
      if (r.problem != null) {
        throw ToolError('${_sentenceOf(r.problem!)}'
            '${_rowReport(before, part, kind, rows)}');
      }
      extra['itemsChanged'] = r.changed;
      return _Done('$message${_rowReport(before, part, kind, rows)}', extra);
    });
  }

  /// Every quiet range in use, as list_quiet_parts shows them.
  List<Map<String, dynamic>> _quietRows(Project project) {
    final out = <Map<String, dynamic>>[];
    void add(String id, String what, String row, List<QuietRange> quiet,
        int startMs, int inMs, int outMs, double speed) {
      final s = speed <= 0 ? 1.0 : speed;
      for (final r in quiet) {
        if (r.toMs <= inMs || r.fromMs >= outMs) continue;
        final a = r.fromMs < inMs ? inMs : r.fromMs;
        final b = r.toMs > outMs ? outMs : r.toMs;
        out.add({
          'itemId': id,
          'what': what,
          'row': row,
          'fromMs': startMs + ((a - inMs) / s).round(),
          'toMs': startMs + ((b - inMs) / s).round(),
          'sourceFromMs': r.fromMs,
          'sourceToMs': r.toMs,
          'level': r.level <= 0.0005 ? 'silent' : levelLabel(r.level),
        });
      }
    }

    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      add(c.id, 'clip ${i + 1} (${p.basename(c.path)})', 'video',
          c.quiet, project.clipStartMs(i), c.inMs, c.outMs, c.speed);
    }
    for (final s in project.audio) {
      if (s.looped) continue;
      add(s.id, 'sound ${p.basename(s.path)}',
          project.trackById(s.trackId)?.name ?? s.trackId, s.quiet, s.startMs,
          s.inMs, s.outMs, s.speed);
    }
    for (final o in project.overlays) {
      add(o.id, 'overlay ${p.basename(o.path)}', 'overlay',
          o.clip.quiet, o.startMs, o.clip.inMs, o.clip.outMs, o.clip.speed);
    }
    out.sort((x, y) => (x['fromMs'] as int).compareTo(y['fromMs'] as int));
    return out;
  }

  Future<ToolResult> _listQuietParts(Map<String, dynamic> a, ToolCall call) async {
    final p = (await _load(a['project_id'])).project;
    final rows = _quietRows(p);
    final gated = [
      for (final t in p.soundTracks)
        if (t.gate)
          {
            'trackId': t.id,
            'name': t.name,
            'room': t.gateLevel <= 0.0005 ? 'silent' : levelLabel(t.gateLevel),
          },
    ];
    final lines = [
      for (final r in rows)
        '${_mss(r['fromMs'] as int)}–${_mss(r['toMs'] as int)} '
            '${r['level']}: ${r['what']} [${r['row']}] item_id ${r['itemId']} '
            'source ${r['sourceFromMs']}..${r['sourceToMs']}',
    ];
    return ToolResult(
        rows.isEmpty
            ? 'No part of "${p.name}" is silenced or lowered.'
                '${gated.isEmpty ? '' : ' "Only when speaking" is on for ${gated.map((g) => g['name']).join(', ')}.'}'
            : '${rows.length} quiet part(s) in "${p.name}":\n${lines.join('\n')}'
                '${gated.isEmpty ? '' : '\n"Only when speaking" is on for ${gated.map((g) => '${g['name']} (${g['room']} between turns)').join(', ')}.'}',
        structured: {'quietParts': rows, 'onlyWhenSpeaking': gated});
  }

  Future<ToolResult> _removeQuietPart(Map<String, dynamic> a, ToolCall call) {
    final id = '${a['item_id']}'.trim();
    return _edit(a, (e) {
      final rows = [
        for (final r in _quietRows(e.project))
          if (r['itemId'] == id) r,
      ];
      if (rows.isEmpty) {
        throw ToolError('The item "$id" has no quiet part (list_quiet_parts '
            'shows them).');
      }
      final from = ClipForgeTools._i(a, 'source_from_ms') ?? -1 << 40;
      final to = ClipForgeTools._i(a, 'source_to_ms') ?? 1 << 40;
      if (to <= from) {
        throw ToolError('source_to_ms must be after source_from_ms.');
      }
      final done = e.removeQuiet(id, from, to);
      return _Done(
          done
              ? 'Removed the quiet part(s) of ${rows.first['what']}: it '
                  'plays at its own level there again.'
              : 'Nothing was quiet between those times on '
                  '${rows.first['what']}.',
          {'itemId': id});
    });
  }

  Future<ToolResult> _setOnlyWhenSpeaking(Map<String, dynamic> a, ToolCall call) {
    final on = a['on'] as bool? ?? true;
    final db = (a['room_db'] as num?)?.toDouble();
    final level = db == null ? null : (db <= -60 ? 0.0 : levelFromDb(db));
    return _edit(a, (e) {
      final p = e.project;
      final all = '${a['track_id']}'.trim().toLowerCase() == 'all';
      final tracks = all
          ? [for (final t in p.soundTracks) if (t.speech) t]
          : [ClipForgeTools._track(p, a['track_id'])];
      if (tracks.isEmpty) {
        throw ToolError('"${p.name}" has no speech track (add_voice makes '
            'one per speaker).');
      }
      for (final t in tracks) {
        if (!t.speech) {
          throw ToolError('"${t.name}" is not a speech track: "Only when '
              'speaking" works on a microphone track (update_sound_track '
              'speech true, when it really holds one speaker).');
        }
      }
      e.transaction(() {
        for (final t in tracks) {
          e.setOnlyWhenSpeaking(t.id, on: on, level: level);
        }
      },
          label: tracks.length == 1
              ? 'Only when speaking ${on ? 'on' : 'off'} for ${tracks.single.name}'
              : 'Only when speaking ${on ? 'on' : 'off'} for '
                  '${tracks.length} tracks');
      final names = tracks.map((t) => '"${t.name}"').join(', ');
      final room = e.project.trackById(tracks.first.id)!.gateLevel;
      return _Done(
          on
              ? 'Set "Only when speaking" on for $names: '
                  '${room <= 0.0005 ? 'silent' : levelLabel(room)} between '
                  'the turns. It is applied when the video is exported (and '
                  'in the app\'s preview); it goes by loudness, so the user '
                  'should listen to a stretch.'
              : 'Set "Only when speaking" off for $names.',
          {
            'tracks': [for (final t in tracks) t.id],
            'on': on,
          });
    });
  }
}
