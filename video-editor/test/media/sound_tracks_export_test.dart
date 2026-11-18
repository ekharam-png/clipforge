// The export graph of sound tracks (pure, no ffmpeg): per-track level,
// mute and solo, per-track ducking keyed by the video sound and speech
// tracks, separated sound with its clip chain / processed file and speed,
// and one input for pieces of one file.
import 'package:clipforge/core/editor/project_editor.dart';
import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026);

Clip video(String id, {int outMs = 6000, double speed = 1}) => Clip(
      id: id,
      type: ClipType.video,
      path: '/m/$id.mp4',
      sourceDurationMs: 20000,
      inMs: 0,
      outMs: outMs,
      width: 1280,
      height: 720,
      speed: speed,
    );

AudioClip sound(String id, String track,
        {int start = 0, int inMs = 0, int outMs = 6000, double volume = 1}) =>
    AudioClip(
      id: id,
      path: '/m/$id.m4a',
      sourceDurationMs: 60000,
      startMs: start,
      inMs: inMs,
      outMs: outMs,
      volume: volume,
      trackId: track,
    );

const voice = SoundTrack(id: 'v', name: 'Voice', speech: true);
const music = SoundTrack(id: 'm', name: 'Music', duck: true);
const fx = SoundTrack(id: 'e', name: 'Effects');

Project proj({
  List<SoundTrack> tracks = const [voice, music, fx],
  List<AudioClip>? audio,
  SoundTrack videoSound = SoundTrack.video,
  List<Clip>? clips,
}) =>
    Project(
      id: 'p',
      name: 'p',
      createdAt: t0,
      updatedAt: t0,
      clips: clips ?? [video('a')],
      tracks: tracks,
      videoSound: videoSound,
      audio: audio ??
          [sound('vo', 'v'), sound('mu', 'm'), sound('ef', 'e', start: 1000, outMs: 2000)],
    );

FfmpegCommand build(Project p, {ExportOptions options = const ExportOptions()}) =>
    buildExportCommand(
      project: p,
      outputPath: '/out.mp4',
      fonts: const FontPaths(regular: '/r.ttf', bold: '/b.ttf'),
      workDir: '/work',
      options: options,
    );

void main() {
  test('three tracks: each its own stream, music ducked by video + voice', () {
    final g = build(proj()).filterGraph;
    // Clip pads m0 (voice), m1 (music), m2 (effects) become tracks t0..t2.
    expect(g, contains('[m0]apad,asetpts=N/SR/TB,atrim=duration=6.000,aformat=sample_fmts=fltp:channel_layouts=stereo[t0]'));
    expect(g, contains('[t1]'));
    expect(g, contains('adelay=delays=1000:all=1[m2]'));
    // The video sound and the voice track are used twice: in the mix and
    // as the side chain of the music.
    expect(g, contains('[acat]asplit=2[acatu0][acatu1]'));
    expect(g, contains('[t0]asplit=2[t0u0][t0u1]'));
    expect(g, contains('[acatu1][t0u1]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[t1key]'));
    expect(g, contains('[t1][t1key]$kDuckFilter[t1d]'));
    expect(g, contains('[acatu0][t0u0][t1d][t2]amix=inputs=4'));
    expect(g, contains('alimiter=limit=0.97:level=0'));
    expect(RegExp('sidechaincompress').allMatches(g).length, 1);
  });

  test('track volume, mute and solo; video sound level', () {
    var g = build(proj(tracks: [
      voice.copyWith(volume: 0.5),
      music.copyWith(muted: true),
      fx,
    ])).filterGraph;
    expect(g, contains('channel_layouts=stereo,volume=0.5[t0]'));
    expect(g, isNot(contains('/m/mu.m4a')));
    expect(g, isNot(contains('sidechaincompress')));
    final args = build(proj(tracks: [voice, music.copyWith(muted: true), fx])).args;
    expect(args, isNot(contains('/m/mu.m4a')));

    // Solo: only the solo track is heard; the video sound is left out.
    final solo = build(proj(tracks: [voice, music, fx.copyWith(solo: true)]));
    expect(solo.args, isNot(contains('/m/vo.m4a')));
    expect(solo.args, contains('/m/ef.m4a'));
    expect(solo.filterGraph, isNot(contains('[acat]asplit')));
    expect(solo.filterGraph, contains('[acat]anullsink'));
    expect(solo.filterGraph, contains('[t0]anull,alimiter'));

    g = build(proj(videoSound: SoundTrack.video.copyWith(volume: 0.25))).filterGraph;
    expect(g, contains('[acat]volume=0.25[amain]'));
    // Muted video sound: not mixed, not a key; voice alone keys the music.
    g = build(proj(videoSound: SoundTrack.video.copyWith(muted: true))).filterGraph;
    expect(g, isNot(contains('[acat]asplit')));
    expect(g, contains('[acat]anullsink'));
    expect(g, contains('[t1][t0u1]$kDuckFilter[t1d]'));
    // No sound tracks heard, video at 1: the plain main track as before.
    final plain = build(proj(audio: const []));
    expect(plain.args, containsAllInOrder(['-map', '[acat]']));
    final quiet = build(proj(audio: const [], videoSound: SoundTrack.video.copyWith(volume: 0.5)));
    expect(quiet.filterGraph, contains('[acat]volume=0.5[aout]'));
  });

  test('a ducked speech track is keyed by the others only', () {
    final g = build(proj(tracks: [voice.copyWith(duck: true), music.copyWith(duck: false), fx]))
        .filterGraph;
    expect(g, contains('[t0][acatu1]$kDuckFilter[t0d]'));
  });

  group('separated sound', () {
    Project separated({double speed = 1, bool denoise = true}) {
      final e = ProjectEditor(
          Project(
              id: 'p',
              name: 'p',
              createdAt: t0,
              updatedAt: t0,
              clips: [
                video('a', outMs: 6000, speed: speed)
                    .copyWith(denoise: denoise, voiceFocus: 0.5, audioStreams: const [2]),
              ]),
          newId: () => 'id${DateTime.now().microsecondsSinceEpoch}');
      e.separateSound('a');
      return e.project;
    }

    test('runs the clip sound chain on the sound clip; the clip is silent', () {
      final p = separated();
      final a = p.audio.single;
      final c = build(p);
      expect(c.args, containsAllInOrder(['-ss', '0.000', '-t', '6.000', '-i', '/m/a.mp4']));
      // The muted video clip: digital silence on the main track.
      expect(c.filterGraph, contains('anullsrc'));
      expect(c.filterGraph, contains(kDenoiseChain));
      expect(c.filterGraph, contains('dialoguenhance'));
      // With a ready processed file: read from it, no chain.
      final pc = build(p,
          options: ExportOptions(processedSound: {a.id: '/cache/snd_x.flac'}));
      expect(pc.args, containsAllInOrder(['-ss', '0.000', '-t', '6.000', '-i', '/cache/snd_x.flac']));
      expect(pc.filterGraph, isNot(contains('afftdn')));
      expect(pc.filterGraph, contains('[1:a:0]aresample'));
    });

    test('carries the speed: atempo and the source span', () {
      final p = separated(speed: 1.5, denoise: false);
      final c = build(p);
      expect(p.audio.single.durationMs, 4000);
      expect(c.args, containsAllInOrder(['-ss', '0.000', '-t', '6.000', '-i', '/m/a.mp4']));
      expect(c.filterGraph, contains('atempo=1.5,atrim=duration=4.000'));
    });

    test('pieces of one file on a track share one input', () {
      final e = ProjectEditor(
          Project(
              id: 'p',
              name: 'p',
              createdAt: t0,
              updatedAt: t0,
              clips: [video('a', outMs: 10000)]),
          newId: () => 'id${DateTime.now().microsecondsSinceEpoch}');
      e.separateSound('a');
      e.removeSourceRanges('a', [
        (startMs: 2000, endMs: 3000),
        (startMs: 6000, endMs: 7000),
      ]);
      expect(e.project.audio.length, 3);
      final c = build(e.project);
      // Three picture pieces share one input (a run), the three sound
      // pieces another.
      expect(c.args.where((a) => a == '/m/a.mp4').length, 2);
      expect(c.filterGraph, contains('asplit=3'));
      expect(c.filterGraph, contains('atrim=start_sample=0:end_sample=96000'));
      expect(c.filterGraph, contains('atrim=start_sample=144000:end_sample=288000'));
    });
  });

  test('findSoundRuns keeps apart what cannot share an input', () {
    final a = sound('a', 'v', start: 0, inMs: 0, outMs: 1000);
    final b = sound('b', 'v', start: 1000, inMs: 2000, outMs: 3000)
        .copyWith(path: a.path);
    final far = sound('c', 'v', start: 2000, inMs: 3000 + kMaxRunGapMs + 1, outMs: 30000)
        .copyWith(path: a.path);
    final back = sound('d', 'v', start: 3000, inMs: 0, outMs: 500).copyWith(path: a.path);
    final runs = findSoundRuns([a, b, far, back], const {});
    expect([for (final r in runs) r.length], [2, 1, 1]);
  });
}
