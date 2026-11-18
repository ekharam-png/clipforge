// What happens when the FFmpeg in use lacks a filter the export's sound
// uses (lib/media/sound_filters.dart): the optional stages are left out
// with a message, the rest of the export is unchanged.
//
// The bundled FFmpeg 8.1.2 builds (Windows x86_64, macOS, Android) contain
// every filter (checked in the downloaded libraries); these tests use fake
// filter lists, and one real export through a wrapper that hides
// `afftdn` from a real ffmpeg.

import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/process_media_engine.dart';
import 'package:clipforge/media/sound_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Every filter a stock FFmpeg has that the export uses.
const _all = {
  'aformat', 'anull', 'aresample', 'atrim', 'asetpts', 'apad', 'asplit',
  'amix', 'concat', 'anullsrc', 'volume', 'adelay', 'acrossfade', 'atempo',
  'pan', 'highpass', 'lowpass', 'equalizer', 'afftdn', 'dynaudnorm',
  'dialoguenhance', 'sidechaincompress', 'afade', 'alimiter',
  // picture
  'fps', 'scale', 'setsar', 'format', 'tpad', 'trim', 'split', 'setpts',
  'xfade', 'drawtext', 'drawbox', 'pad', 'crop', 'overlay', 'gblur', 'eq',
  'color', 'loop', 'null',
};

final _t0 = DateTime.utc(2026);

Clip _clip({bool denoise = true, double focus = 0.85, int outMs = 4000,
        TransitionType transition = TransitionType.none}) =>
    Clip(
      id: 'c${outMs}_$transition',
      type: ClipType.video,
      path: '/v/a.mp4',
      sourceDurationMs: 8000,
      inMs: 0,
      outMs: outMs,
      width: 640,
      height: 360,
      denoise: denoise,
      voiceFocus: focus,
      transition: transition,
    );

Project _project({List<Clip>? clips, bool duck = true, bool fades = true}) =>
    Project(
      id: 'p',
      name: 'p',
      createdAt: _t0,
      updatedAt: _t0,
      duckMusic: duck,
      clips: clips ?? [_clip()],
      audio: [
        AudioClip(
          id: 'm',
          path: '/m/song.mp3',
          sourceDurationMs: 20000,
          startMs: 0,
          inMs: 0,
          outMs: 20000,
          fadeInMs: fades ? 1000 : 0,
          fadeOutMs: fades ? 2000 : 0,
        ),
      ],
    );

String _graph(Project project, {Set<SoundStage> leaveOut = const {}}) =>
    buildExportCommand(
      project: project,
      outputPath: '/out/x.mp4',
      fonts: const FontPaths(regular: '/f/r.ttf', bold: '/f/b.ttf'),
      workDir: '/tmp/w',
      leaveOut: leaveOut,
    ).filterGraph;

void main() {
  group('parseFilterList', () {
    test('reads stock and --enable-small listings', () {
      const stock = '''
Filters:
  T.. = Timeline support
  .S. = Slice threading
  ..C = Command support
  A = Audio input/output
  | = Source or sink filter
 ... abench            A->A       Benchmark part of a filtergraph.
 TSC afftdn            A->A       Denoise audio samples using FFT.
 ... amovie            |->N       Read audio from a movie source.
 ... acrossfade        AA->A      Cross fade two input audio streams.
 T.C afade             A->A       Fade in/out input audio.
''';
      expect(parseFilterList(stock),
          {'abench', 'afftdn', 'amovie', 'acrossfade', 'afade'});
      // FFmpegKit (--enable-small): no descriptions.
      expect(parseFilterList(' TS. dynaudnorm        A->A       (null)\n'
          ' ... sidechaincompress AA->A      (null)\n'),
          {'dynaudnorm', 'sidechaincompress'});
    });
  });

  group('filtersInGraph', () {
    test('names every filter once, skipping labels and escaped values', () {
      expect(
          filtersInGraph(r'[0:a:0]aresample=48000,aformat=sample_fmts=fltp;'
              r'[vcat]drawtext=fontfile=C\\:/Users/A\ B/f.ttf:text=a\,b'
              r':enable=gte(t\,1)[v];[a][b]amix=inputs=2,aresample=48000[o]'),
          ['aresample', 'aformat', 'drawtext', 'amix']);
    });

    test('the real export graph uses only filters a real ffmpeg has', () {
      final r = Process.runSync('ffmpeg', ['-hide_banner', '-filters']);
      if (r.exitCode != 0) {
        markTestSkipped('ffmpeg not installed');
        return;
      }
      final have = parseFilterList('${r.stdout}');
      final project = _project(clips: [
        _clip(),
        _clip(outMs: 3000, transition: TransitionType.crossfade, focus: 0),
      ]);
      final used = filtersInGraph(_graph(project));
      expect(used, containsAll(['afftdn', 'dialoguenhance', 'afade',
          'sidechaincompress', 'alimiter', 'acrossfade', 'xfade']));
      expect(have, containsAll(used));
    });
  });

  group('SoundFilterCheck', () {
    test('everything there: nothing left out, the graph is unchanged', () {
      final check = SoundFilterCheck.of(_all);
      final project = _project();
      expect(check.unavailable, isEmpty);
      expect(check.messagesFor(project), isEmpty);
      expect(_graph(project, leaveOut: check.unavailable), _graph(project));
      expect(check.missingIn(_graph(project)), isEmpty);
    });

    test('an unreadable list counts as nothing missing', () {
      expect(SoundFilterCheck.of(null).unavailable, isEmpty);
      expect(SoundFilterCheck.of(const {}).unavailable, isEmpty);
      expect(SoundFilterCheck.of(const {'libx264', 'scale'}).missingIn('afftdn'),
          isEmpty);
    });

    test('each missing filter leaves out only its own stage, with a message',
        () {
      final have = {..._all}
        ..remove('afftdn')
        ..remove('dialoguenhance')
        ..remove('sidechaincompress');
      final check = SoundFilterCheck.of(have);
      expect(check.unavailable, {
        SoundStage.cleanUp,
        SoundStage.voiceFocusCentre,
        SoundStage.duckMusic,
      });
      final project = _project();
      final graph = _graph(project, leaveOut: check.unavailable);
      // Gone: clean-up, centre emphasis, ducking.
      expect(graph, isNot(contains('afftdn')));
      expect(graph, isNot(contains('dynaudnorm')));
      expect(graph, isNot(contains('dialoguenhance')));
      expect(graph, isNot(contains('sidechaincompress')));
      // Kept: voice focus tone, music fades, limiter, the mix.
      expect(graph, contains('highpass=f=137,lowpass=f=8497,equalizer=f=3000'));
      expect(graph, contains('afade=t=in:st=0:d=1.000'));
      expect(graph, contains('afade=t=out:'));
      expect(graph, contains('alimiter='));
      expect(graph, contains('amix=inputs=2'));
      // What is left runs on this FFmpeg.
      expect(check.missingIn(graph), isEmpty);
      expect(check.messagesFor(project), [
        'Clean up sound was left out: the FFmpeg on this device has no '
            '"afftdn" filter.',
        'Voice focus (centre emphasis) was left out: the FFmpeg on this '
            'device has no "dialoguenhance" filter.',
        'Lower music under speech was left out: the FFmpeg on this device '
            'has no "sidechaincompress" filter.',
      ]);
    });

    test('only stages the project uses are mentioned', () {
      final check = SoundFilterCheck.of({..._all}
        ..remove('afade')
        ..remove('alimiter'));
      final plain = _project(
          clips: [_clip(denoise: false, focus: 0)], duck: false, fades: false);
      // No fades in the project: only the limiter is worth a word.
      expect(check.leftOutFor(plain), [SoundStage.limiter]);
      final graph = _graph(plain, leaveOut: check.unavailable);
      expect(graph, isNot(contains('alimiter')));
      expect(check.missingIn(graph), isEmpty);
      expect(check.leftOutFor(_project()),
          [SoundStage.musicFades, SoundStage.limiter]);
      expect(_graph(_project(), leaveOut: check.unavailable),
          isNot(contains('afade')));
    });

    test('a missing filter the video cannot do without is named', () {
      final check = SoundFilterCheck.of({..._all}..remove('acrossfade'));
      final project = _project(clips: [
        _clip(),
        _clip(outMs: 3000, transition: TransitionType.crossfade),
      ]);
      final missing = check.missingIn(_graph(project));
      expect(missing, ['acrossfade']);
      expect(missingFiltersMessage(missing),
          'This video cannot be exported on this device: its FFmpeg has no '
          '"acrossfade" filter.');
      expect(missingFiltersMessage(['a', 'b', 'c']), contains('"a", "b" or "c"'));
    });

    test('FilterSupport asks once and survives a failing listing', () async {
      var asked = 0;
      final support = FilterSupport(() async {
        asked++;
        throw const FileSystemException('no ffmpeg');
      });
      expect((await support.check()).unavailable, isEmpty);
      expect((await support.check()).unavailable, isEmpty);
      expect(asked, 1);
    });
  });

  group('a real export with an FFmpeg that lacks afftdn', () {
    final ok = Process.runSync('which', ['ffmpeg']).exitCode == 0 &&
        Process.runSync('which', ['ffprobe']).exitCode == 0;
    late Directory tmp;

    setUpAll(() async {
      if (!ok) return;
      tmp = await Directory.systemTemp.createTemp('cf_filters_');
    });
    tearDownAll(() async {
      if (ok) await tmp.delete(recursive: true);
    });

    test('is made without clean-up and says so', () async {
      if (!ok) {
        markTestSkipped('ffmpeg not installed');
        return;
      }
      // A wrapper that hides afftdn from `-filters` and runs the real
      // ffmpeg for everything else.
      final wrapper = File(p.join(tmp.path, 'ffmpeg'));
      await wrapper.writeAsString('#!/bin/sh\n'
          'for a in "\$@"; do if [ "\$a" = "-filters" ]; then '
          'ffmpeg -hide_banner -filters | grep -v -w afftdn; exit 0; fi; done\n'
          'exec ffmpeg "\$@"\n');
      await Process.run('chmod', ['+x', wrapper.path]);
      final video = p.join(tmp.path, 'a.mp4');
      final r = await Process.run('ffmpeg', [
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc=d=2:s=160x120:r=30',
        '-f', 'lavfi', '-i', 'sine=f=300:d=2',
        '-ac', '2', '-c:v', 'libx264', '-c:a', 'aac', '-shortest', video,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final engine = ProcessMediaEngine(ffmpegPath: wrapper.path,
          ffprobePath: 'ffprobe');
      final project = Project(
        id: 'p', name: 'p', createdAt: _t0, updatedAt: _t0,
        clips: [
          Clip(
            id: 'c', type: ClipType.video, path: video,
            sourceDurationMs: 2000, inMs: 0, outMs: 2000,
            width: 160, height: 120, denoise: true, voiceFocus: 0.5,
          ),
        ],
      );
      final job = engine.export(project, p.join(tmp.path, 'out.mp4'),
          options: const ExportOptions(useHardwareEncoder: false));
      final out = await job.done;
      expect(File(out).lengthSync(), greaterThan(0));
      expect(job.warnings, [
        'Clean up sound was left out: the FFmpeg on this device has no '
            '"afftdn" filter.',
      ]);
    });
  });
}
