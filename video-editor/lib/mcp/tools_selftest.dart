// get_guide (the guide for Claude, compiled into the helper) and self_test
// (a scripted check of the real tools against a TEMPORARY projects folder).

part of 'tools.dart';

/// The guide sections as MCP resources (`clipforge://guide/<section>`).
List<McpResource> guideResources() => [
      for (final e in kGuideSections.entries)
        McpResource(
          uri: 'clipforge://guide/${e.key}',
          name: 'guide-${e.key}',
          title: 'ClipForge guide: ${e.key}',
          description: kGuideSummaries[e.key],
          text: e.value,
        ),
    ];

/// One line of the self-test table.
class _Check {
  _Check(this.name, this.result, this.ms, [this.note = '']);
  final String name;

  /// PASS, FAIL or SKIPPED.
  final String result;
  final int ms;
  final String note;
}

/// Stops a check with a reason (it becomes FAIL).
class _CheckFailed implements Exception {
  _CheckFailed(this.message);
  final String message;
}

/// Ends a check as SKIPPED with a reason.
class _CheckSkipped implements Exception {
  _CheckSkipped(this.message);
  final String message;
}

extension _SelfTest on ClipForgeTools {
  List<ToolDef> get _selfToolDefs => [
        ToolDef(
          name: 'get_guide',
          title: 'Read the ClipForge guide',
          description:
              'The guide for working with ClipForge, kept inside this helper '
              'so it always matches the installed version. Call it with no '
              'arguments FIRST in every conversation: the "start" section '
              '(who you are helping, the workflow, the safety rules, what '
              'you can and cannot know). Other sections, only when needed: '
              '"recipes" (step-by-step for the usual jobs), "tools" (every '
              'tool with its arguments), "troubleshooting".',
          properties: {
            'section': _str('Which part. Default "start".',
                values: kGuideSections.keys.toList()),
          },
          readOnly: true,
          idempotent: true,
          handler: _getGuide,
        ),
        ToolDef(
          name: 'self_test',
          title: 'Check that everything works',
          description:
              'Checks this installation end to end in about a minute: makes '
              'its own small sample video with FFmpeg in a TEMPORARY folder '
              'and runs the real tools on a temporary projects folder '
              '(create, add media, split, speed, titles in Cyrillic and '
              'Hebrew, sound tracks, separate sound, remove silences, an '
              'export job checked with ffprobe, undo / redo, the '
              'open-in-the-app refusal, speech-to-text when a speech '
              'program and language pack are installed). The user\'s '
              'projects and files are never touched; everything is deleted '
              'afterwards. Returns a PASS / FAIL table with timings. Use it '
              'when the user asks whether ClipForge and Claude work '
              'together, or after an update.',
          properties: {
            'keep_files': _bool('true: leave the temporary folder in place '
                '(its path is in the answer) to look at. Default false.'),
            'quick': _bool('true: leave out the export and speech-to-text '
                'checks (a few seconds; what the app\'s Test button runs). '
                'Default false.'),
          },
          handler: _selfTest,
        ),
      ];

  Future<ToolResult> _getGuide(Map<String, dynamic> a, ToolCall call) async {
    final section = (a['section'] as String?) ?? 'start';
    final text = kGuideSections[section];
    if (text == null) {
      throw ToolError('There is no guide section "$section". Sections: '
          '${kGuideSections.keys.join(', ')}.');
    }
    final others = [
      for (final e in kGuideSummaries.entries)
        if (e.key != section) '"${e.key}": ${e.value}',
    ];
    return ToolResult(
        '$text\n\n---\nClipForge guide, section "$section" '
        '(${BuildInfo.current.versionLabel}). Other sections '
        '(get_guide section …): ${others.join(' ')}',
        structured: {
          'section': section,
          'version': BuildInfo.current.version,
          'sections': kGuideSummaries,
          'text': text,
        });
  }

  Future<ToolResult> _selfTest(Map<String, dynamic> a, ToolCall call) async {
    final total = Stopwatch()..start();
    final keep = a['keep_files'] == true;
    final checks = <_Check>[];
    final tmp = await Directory.systemTemp.createTemp('clipforge-selftest-');
    final root = p.join(tmp.path, 'ClipForge');
    final mediaDir = Directory(p.join(tmp.path, 'media'))..createSync();
    final outDir = Directory(p.join(tmp.path, 'exports'))..createSync();
    // The same tools, pointed at the temporary folder. Exports start the
    // way the real server starts them (a separate process); speech uses
    // the real programs and language packs of this computer.
    final t = ClipForgeTools(
      projectsDir: ProjectsDir(p.join(root, 'projects'), 'self-test (temporary)'),
      media: media,
      fontsChecked: fontsChecked,
      exportLauncher: exportLauncher,
      stateDir: p.join(root, 'claude-jobs'),
      speech: speech,
      transcribeLauncher: inProcessTranscribeLauncher((_) => speech),
    );
    final byName = {for (final d in t.tools) d.name: d};
    Future<ToolResult> run(String name, Map<String, dynamic> args) async {
      final tool = byName[name]!;
      try {
        tool.validate(args);
        return await tool.handler(args, ToolCall.silent());
      } on ToolError catch (e) {
        return ToolResult(e.message, isError: true);
      }
    }

    Future<Map<String, dynamic>> ok(String name, Map<String, dynamic> args) async {
      final r = await run(name, args);
      if (r.isError) throw _CheckFailed('$name: ${_firstLine(r.text)}');
      return r.structured ?? const {};
    }

    void expect(bool condition, String what) {
      if (!condition) throw _CheckFailed(what);
    }

    const names = [
      'Sample media (FFmpeg)', 'Create a project', 'Add media', //
      'Split', 'Speed', 'Titles (Latin, Cyrillic, Hebrew)', 'Sound tracks',
      'Separate sound', 'Remove silences (dry run)', 'Remove silences',
      'Export as a background job', 'Undo / redo', 'Refuses while open in the app',
      'Speech to text', 'Clean up',
    ];
    var step = 0;
    // quick (the app's Test button, 1.14): everything but the two slow
    // checks, which are listed as skipped.
    final quick = a['quick'] == true;
    const slow = {'Export as a background job', 'Speech to text'};
    Future<void> check(String name, Future<String> Function() body) async {
      call.progress(step.toDouble(),
          total: names.length.toDouble(), message: 'Self-test: $name');
      step++;
      final w = Stopwatch()..start();
      try {
        if (quick && slow.contains(name)) {
          throw _CheckSkipped('not part of the quick test');
        }
        final note = await body();
        checks.add(_Check(name, 'PASS', w.elapsedMilliseconds, note));
      } on _CheckSkipped catch (e) {
        checks.add(_Check(name, 'SKIPPED', w.elapsedMilliseconds, e.message));
      } on _CheckFailed catch (e) {
        checks.add(_Check(name, 'FAIL', w.elapsedMilliseconds, e.message));
      } catch (e) {
        checks.add(_Check(name, 'FAIL', w.elapsedMilliseconds, _firstLine('$e')));
      }
    }

    final video = p.join(mediaDir.path, 'sample.mp4');
    final music = p.join(mediaDir.path, 'music.wav');
    var haveMedia = false;
    String? id;
    void needProject() {
      if (id == null) throw _CheckSkipped('no project (an earlier check failed)');
    }

    void needMedia() {
      needProject();
      if (!haveMedia) throw _CheckSkipped('no sample media (FFmpeg)');
    }

    Future<Map<String, dynamic>> project() async =>
        ((await ok('get_project', {'project_id': id}))['project'] as Map)
            .cast<String, dynamic>();
    List<Map<String, dynamic>> clipsOf(Map<String, dynamic> pr) =>
        (pr['clips'] as List).cast<Map<String, dynamic>>();

    try {
      await check(names[0], () async {
        final mpeg = await media.ffmpeg();
        final probe = await media.ffprobe();
        if (mpeg == null || probe == null) {
          throw _CheckFailed('FFmpeg was not found. ${ffmpegInstallHint()}');
        }
        // 6 s: a tone, 1.6 s of silence, a tone (for remove_silences).
        final r1 = await Process.run(mpeg.path, [
          '-hide_banner', '-loglevel', 'error', '-y', //
          '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=25:duration=6',
          '-f', 'lavfi', '-i',
          "aevalsrc='0.4*sin(2*PI*440*t)*(lt(t,2)+gt(t,3.6))':d=6:s=44100",
          '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-shortest', video,
        ]).timeout(const Duration(seconds: 40));
        expect(r1.exitCode == 0 && File(video).existsSync(),
            'FFmpeg could not make the sample video: ${_firstLine('${r1.stderr}')}');
        final r2 = await Process.run(mpeg.path, [
          '-hide_banner', '-loglevel', 'error', '-y', //
          '-f', 'lavfi', '-i', 'sine=frequency=220:duration=8', music,
        ]).timeout(const Duration(seconds: 40));
        expect(r2.exitCode == 0 && File(music).existsSync(),
            'FFmpeg could not make the sample music: ${_firstLine('${r2.stderr}')}');
        haveMedia = true;
        return 'FFmpeg ${mpeg.version}';
      });

      await check(names[1], () async {
        final r = await ok('create_project', {'name': 'Self-test'});
        id = (r['project'] as Map)['id'] as String;
        expect((await t.store.list()).length == 1, 'the project was not saved');
        return '';
      });

      await check(names[2], () async {
        needMedia();
        await ok('add_media', {'project_id': id, 'paths': [video]});
        final pr = await project();
        expect(clipsOf(pr).length == 1, 'expected 1 clip');
        final ms = pr['durationMs'] as int;
        expect((ms - 6000).abs() <= 250, 'length $ms ms, expected about 6000');
        expect((pr['media'] as Map).length == 1, 'media table');
        return '${pr['canvasWidth']}x${pr['canvasHeight']}, ${clock(ms)}';
      });

      await check(names[3], () async {
        needMedia();
        await ok('split_at', {'project_id': id, 'timeline_ms': 1000});
        expect(clipsOf(await project()).length == 2, 'expected 2 clips after the split');
        return '';
      });

      await check(names[4], () async {
        needMedia();
        final first = clipsOf(await project()).first['id'];
        final r = await ok('set_clip_properties',
            {'project_id': id, 'clip_id': first, 'speed': 2.0});
        final pr = await project();
        expect(clipsOf(pr).first['speed'] == 2.0, 'the speed was not set');
        expect((pr['durationMs'] as int) < 5800, 'the video did not get shorter');
        // The answer says old -> new.
        final fields = (((r['changes'] as Map)['clips'] as Map)['fields'] as Map?)
            ?.values
            .first as Map?;
        expect(fields != null && (fields['speed'] as Map?)?['to'] == 2.0,
            'the answer does not report speed old -> new');
        return 'first clip at 2x, ${clock(pr['durationMs'] as int)}';
      });

      await check(names[5], () async {
        needProject();
        for (final (text, at) in const [
          ('Hello', 0),
          ('Привет, мир', 1500),
          ('שלום עולם', 3000),
        ]) {
          await ok('add_title', {
            'project_id': id, 'text': text, 'start_ms': at, 'duration_ms': 1200, //
          });
        }
        final titles = ((await project())['titles'] as List)
            .map((x) => (x as Map)['text'])
            .toSet();
        expect(titles.containsAll(const ['Привет, мир', 'שלום עולם']),
            'the titles did not come back as written');
        expect(media.fonts != null,
            'the titles are saved, but the title fonts were not found, so '
            'exports with titles fail');
        return '3 titles';
      });

      await check(names[6], () async {
        needMedia();
        await ok('add_music',
            {'project_id': id, 'path': music, 'volume': 0.5, 'fade_out_ms': 500});
        await ok('add_sound_track', {'project_id': id, 'name': 'Effects'});
        final pr = await project();
        expect((pr['soundTracks'] as List).length == 2, 'expected 2 sound tracks');
        expect((pr['audio'] as List).length == 1, 'expected 1 sound item');
        return '2 tracks, 1 music item';
      });

      await check(names[7], () async {
        needMedia();
        final last = clipsOf(await project()).last['id'];
        await ok('separate_sound', {'project_id': id, 'clip_id': last});
        final pr = await project();
        expect((pr['audio'] as List).length == 2, 'expected the separated sound');
        expect(clipsOf(pr).last['muted'] == true, 'the clip was not muted');
        return '';
      });

      var cutsFound = 0;
      await check(names[8], () async {
        needMedia();
        final before = clipsOf(await project()).length;
        final r = await ok('remove_silences', {'project_id': id, 'dry_run': true});
        cutsFound = ((r['cuts'] as List?) ?? const []).length;
        expect(r['dryRun'] == true, 'not reported as a dry run');
        expect(cutsFound >= 1, 'the 1.6 s pause was not found');
        expect(clipsOf(await project()).length == before,
            'the dry run changed the project');
        return '$cutsFound cut(s) found, nothing saved';
      });

      await check(names[9], () async {
        needMedia();
        if (cutsFound == 0) throw _CheckSkipped('the dry run found nothing');
        final before = await project();
        await ok('remove_silences', {'project_id': id});
        final after = await project();
        expect((after['durationMs'] as int) < (before['durationMs'] as int) - 800,
            'the video did not get shorter');
        return '${clock(before['durationMs'] as int)} -> '
            '${clock(after['durationMs'] as int)}';
      });

      await check(names[10], () async {
        needMedia();
        final out = p.join(outDir.path, 'self-test.mp4');
        var r = await ok('export_video', {
          'project_id': id, 'output_path': out, 'quality': 'small', //
          'wait_seconds': 5,
        });
        final job = r['jobId'];
        final w = Stopwatch()..start();
        while (r['status'] != kJobFinished) {
          final status = '${r['status']}';
          if (status == kJobFailed || status == kJobCancelled || status == kJobLost) {
            throw _CheckFailed('the export ended as "$status": '
                '${_firstLine('${r['error'] ?? r['message'] ?? ''}')}');
          }
          if (w.elapsed > const Duration(seconds: 50)) {
            await run('cancel_export', {'job_id': job});
            throw _CheckFailed('the export was not finished after 50 s (stopped)');
          }
          r = await ok('get_export_status', {'job_id': job, 'wait_seconds': 5});
        }
        expect(File(out).existsSync(), 'the exported file is not there');
        final probe = (await media.ffprobe())!;
        final pr = await Process.run(probe.path, [
          '-v', 'error', '-show_entries', 'format=duration:stream=codec_type', //
          '-of', 'json', out,
        ]);
        final info = jsonDecode('${pr.stdout}') as Map;
        final kinds = [
          for (final s in (info['streams'] as List? ?? const []))
            (s as Map)['codec_type'],
        ];
        final seconds = double.tryParse('${(info['format'] as Map?)?['duration']}') ?? 0;
        final wanted = ((await project())['durationMs'] as int) / 1000;
        expect(kinds.contains('video') && kinds.contains('audio'),
            'the export has no picture or no sound ($kinds)');
        expect((seconds - wanted).abs() < 0.5,
            'the export is ${seconds.toStringAsFixed(2)} s long, expected '
            '${wanted.toStringAsFixed(2)} s');
        return '${seconds.toStringAsFixed(1)} s, '
            '${(File(out).lengthSync() / 1024).round()} KB, in '
            '${t.exportLauncher.description}'
            '${lastWorkerStart.isEmpty ? '' : ' ($lastWorkerStart)'}';
      });

      await check(names[11], () async {
        needProject();
        final before = await project();
        await ok('add_title',
            {'project_id': id, 'text': 'Undo me', 'start_ms': 0, 'duration_ms': 500});
        await ok('undo', {'project_id': id});
        final undone = await project();
        expect((undone['titles'] as List).length == (before['titles'] as List).length,
            'undo did not take the title away');
        await ok('redo', {'project_id': id});
        expect(
            ((await project())['titles'] as List).length ==
                (before['titles'] as List).length + 1,
            'redo did not bring the title back');
        return '';
      });

      await check(names[12], () async {
        needProject();
        final lock = File(p.join(t.store.rootPath, id!, kAppLockFileName));
        final now = DateTime.now();
        lock.writeAsStringSync(jsonEncode(ProjectLockInfo(
          pid: pid,
          host: localHostName(),
          openedAt: now,
          heartbeatAt: now,
          app: 'self-test (pretend app)',
          token: 'self-test',
        ).toJson()));
        try {
          final refused = await run('add_title',
              {'project_id': id, 'text': 'Blocked', 'start_ms': 0});
          expect(refused.isError && refused.text.contains('open in the'),
              'an edit was NOT refused while the project is marked open');
          expect((await project())['openInApp'] == true,
              'get_project does not show the project as open');
        } finally {
          lock.deleteSync();
        }
        await ok('add_title',
            {'project_id': id, 'text': 'Free again', 'start_ms': 0, 'duration_ms': 500});
        return 'refused, then allowed';
      });

      await check(names[13], () async {
        needMedia();
        final status = (await _speechStatus()).data;
        final backends = [
          for (final b in (status['backends'] as List? ?? const []))
            if ((b as Map)['available'] == true) b,
        ];
        final packs = (status['packs'] as List? ?? const []);
        if (backends.isEmpty) throw _CheckSkipped('no speech engine');
        if (packs.isEmpty && status['ownModelFile'] == null) {
          throw _CheckSkipped('no language pack');
        }
        var r = await run('transcribe', {'project_id': id, 'language': 'en'});
        if (r.isError) throw _CheckFailed(_firstLine(r.text));
        var data = r.structured ?? const {};
        final job = data['job_id'];
        final w = Stopwatch()..start();
        while ('${data['status']}' == kJobRunning || '${data['status']}' == kJobStarting) {
          if (w.elapsed > const Duration(seconds: 40)) {
            await run('cancel_transcribe', {'job_id': job});
            throw _CheckSkipped('still running after 40 s (stopped; a tone '
                'is not speech, so this says little)');
          }
          data = await ok('get_transcribe_status', {'job_id': job, 'wait_seconds': 5});
        }
        expect('${data['status']}' == kJobFinished,
            'transcribing ended as "${data['status']}": '
            '${_firstLine('${data['error'] ?? ''}')}');
        return 'ran with ${(backends.first)['name'] ?? (backends.first)['id']} '
            '(the sample is a tone, not speech)';
      });
    } finally {
      await check(names[14], () async {
        if (keep) return 'kept: ${tmp.path}';
        for (var i = 0; i < 5; i++) {
          try {
            if (tmp.existsSync()) tmp.deleteSync(recursive: true);
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
        expect(!tmp.existsSync(), 'the temporary folder could not be removed: ${tmp.path}');
        return '';
      });
    }
    call.progress(names.length.toDouble(),
        total: names.length.toDouble(), message: 'Self-test: done');

    final passed = checks.where((c) => c.result == 'PASS').length;
    final failed = checks.where((c) => c.result == 'FAIL').length;
    final skipped = checks.where((c) => c.result == 'SKIPPED').length;
    final seconds = total.elapsedMilliseconds / 1000;
    final width = checks.fold<int>(5, (w, c) => c.name.length > w ? c.name.length : w);
    final text = StringBuffer()
      ..writeln('ClipForge self-test: ${failed == 0 ? 'PASS' : 'FAIL'} '
          '($passed passed, $failed failed, $skipped skipped) in '
          '${seconds.toStringAsFixed(1)} s')
      ..writeln(BuildInfo.current.describe())
      ..writeln('Helper: ${Platform.resolvedExecutable}')
      ..writeln()
      ..writeln('${' #'.padRight(4)}${'Check'.padRight(width + 2)}'
          '${'Result'.padRight(9)}${'Time'.padLeft(7)}  Note');
    for (var i = 0; i < checks.length; i++) {
      final c = checks[i];
      text.writeln('${'${i + 1}'.padLeft(2)}  ${c.name.padRight(width + 2)}'
          '${c.result.padRight(9)}'
          '${'${(c.ms / 1000).toStringAsFixed(1)} s'.padLeft(7)}'
          '${c.note.isEmpty ? '' : '  ${c.note}'}');
    }
    text
      ..writeln()
      ..write('Everything ran in a temporary folder'
          '${keep ? ' (kept: ${tmp.path})' : ' that was deleted afterwards'}; '
          'the user\'s projects (${projectsDir.path}) were not touched.');
    return ToolResult(text.toString(), structured: {
      'ok': failed == 0,
      'passed': passed,
      'failed': failed,
      'skipped': skipped,
      'seconds': seconds,
      'version': BuildInfo.current.describe(),
      'helper': Platform.resolvedExecutable,
      'checks': [
        for (final c in checks)
          {
            'name': c.name,
            'result': c.result,
            'ms': c.ms,
            if (c.note.isNotEmpty) 'note': c.note,
          },
      ],
      if (keep) 'folder': tmp.path,
    });
  }
}

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length <= 220 ? line : '${line.substring(0, 219)}…';
}
