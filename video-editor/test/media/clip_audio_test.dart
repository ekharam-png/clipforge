// Unit tests of the clip sound stages (lib/media/clip_audio.dart) in the
// export graph and in the preview filters. No ffmpeg needed; the real
// exports are in voice_focus_integration_test.dart.

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:flutter_test/flutter_test.dart';

const fonts = FontPaths(regular: '/f/Regular.ttf', bold: '/f/Bold.ttf');
final t0 = DateTime.utc(2026);
const fmt = 'aformat=sample_fmts=fltp:channel_layouts=stereo';

Clip piece(int inMs, int outMs, {String file = 'talk'}) => Clip(
    id: '$file-$inMs',
    type: ClipType.video,
    path: '/media/$file.mp4',
    sourceDurationMs: 600000,
    inMs: inMs,
    outMs: outMs,
    width: 1280,
    height: 720,
    audioStreams: const [2, 2]);

Project proj(List<Clip> clips) =>
    Project(id: 'p', name: 'n', createdAt: t0, updatedAt: t0, clips: clips);

FfmpegCommand build(Project p) => buildExportCommand(
    project: p, outputPath: '/out/o.mp4', fonts: fonts, workDir: '/tmp/w');

int inputs(FfmpegCommand c) => c.args.where((a) => a == '-i').length;

void main() {
  group('voice focus filters', () {
    test('off below 0.5 %', () {
      expect(voiceFocusFilters(0), isEmpty);
      expect(voiceFocusFilters(0.004), isEmpty);
      expect(voiceFocusFilters(double.nan), isEmpty);
      expect(voiceFocusOf(piece(0, 1000).copyWith(voiceFocus: 7)), 1);
      expect(voiceFocusOf(piece(0, 1000).copyWith(voiceFocus: -1)), 0);
    });

    test('100 %', () {
      expect(voiceFocusFilters(1), [
        'highpass=f=150',
        'lowpass=f=7500',
        'equalizer=f=3000:t=o:w=1.5:g=3',
        'apad=pad_len=1536',
        'dialoguenhance',
        // g = 1/3 for what differs between the sides; centre gain 2.67.
        'pan=stereo|c0=0.3333*c0+0.2497*c2|c1=0.3333*c1+0.2497*c2',
        'atrim=start_sample=1536',
        'asetpts=N/SR/TB',
      ]);
    });

    test('scales with the strength', () {
      final half = voiceFocusFilters(0.5);
      expect(half.take(3), [
        'highpass=f=105',
        'lowpass=f=11368',
        'equalizer=f=3000:t=o:w=1.5:g=1.5',
      ]);
      expect(half, contains('pan=stereo|c0=0.5*c0+0.1873*c2|c1=0.5*c1+0.1873*c2'));
      // Sound that is the same on both sides keeps its level at any
      // strength: g * (1 + k * 2.67) = 1.
      for (final s in [0.1, 0.5, 0.9, 1.0]) {
        final pan = voiceFocusFilters(s).firstWhere((f) => f.startsWith('pan='));
        final m = RegExp(r'c0=([\d.]+)\*c0\+([\d.]+)\*c2').firstMatch(pan)!;
        final g = double.parse(m.group(1)!), gk = double.parse(m.group(2)!);
        expect(g + gk * kDialogueEnhanceCentreGain, closeTo(1, 0.001), reason: '$s');
      }
    });
  });

  group('in the export graph', () {
    test('order: track, side, clean-up, voice focus, speed, volume', () {
      final c = piece(0, 3000).copyWith(
          audioTrack: 1,
          audioChannel: AudioChannel.left,
          denoise: true,
          voiceFocus: 1,
          speed: 2,
          volume: 0.5);
      final g = build(proj([c])).filterGraph;
      final a = g.split(';').firstWhere((s) => s.startsWith('[0:a:1]'));
      expect(a, startsWith('[0:a:1]aresample=48000,$fmt,pan=stereo|c0=c0|c1=c0,$fmt,'
          '$kDenoiseChain,$fmt,highpass=f=150,'));
      final order = [
        'pan=stereo|c0=c0|c1=c0', 'afftdn', 'dialoguenhance', 'atempo=2', 'volume=0.5', 'apad,'
      ];
      var at = -1;
      for (final o in order) {
        final i = a.indexOf(o);
        expect(i, greaterThan(at), reason: o);
        at = i;
      }
    });

    test('right only, first track; nothing extra when everything is off', () {
      final g = build(proj([piece(0, 1000).copyWith(audioChannel: AudioChannel.right)]))
          .filterGraph;
      expect(g, contains('[0:a:0]aresample=48000,$fmt,pan=stereo|c0=c1|c1=c1,$fmt,apad'));
      final plain = build(proj([piece(0, 1000)])).filterGraph;
      expect(plain, contains('[0:a:0]aresample=48000,$fmt,apad,'));
      expect(plain, isNot(contains('pan=')));
      expect(plain, isNot(contains('dialoguenhance')));
    });

    test('a side or track the file is not known to have is not used', () {
      final c = piece(0, 1000).copyWith(
          audioTrack: 1, audioChannel: AudioChannel.left, audioStreams: const []);
      final g = build(proj([c])).filterGraph;
      expect(g, contains('[0:a:0]'));
      expect(g, isNot(contains('pan=')));
      final mono = piece(0, 1000)
          .copyWith(audioChannel: AudioChannel.left, audioStreams: const [1]);
      expect(build(proj([mono])).filterGraph, isNot(contains('pan=')));
    });

    test('muted clips and photos stay silent', () {
      final g = build(proj([
        piece(0, 1000).copyWith(voiceFocus: 1, muted: true),
      ])).filterGraph;
      expect(g, isNot(contains('dialoguenhance')));
      expect(g, contains('anullsrc'));
    });

    test('runs: identical settings share one input, different ones do not', () {
      Clip p(int i, {double focus = 0.6, AudioChannel side = AudioChannel.left, int track = 1}) =>
          piece(i * 2000, i * 2000 + 1200)
              .copyWith(voiceFocus: focus, audioChannel: side, audioTrack: track, denoise: true);
      var cmd = build(proj([p(0), p(1), p(2)]));
      expect(inputs(cmd), 1);
      expect(cmd.filterGraph, contains('[0:a:1]aresample=48000:async=1:first_pts=0,$fmt,'
          'pan=stereo|c0=c0|c1=c0,$fmt,$kDenoiseChain,$fmt,highpass=f=114,'));
      expect('dialoguenhance'.allMatches(cmd.filterGraph), hasLength(1));
      cmd = build(proj([p(0), p(1, focus: 0.7), p(2)]));
      expect(inputs(cmd), 3);
      cmd = build(proj([p(0), p(1, side: AudioChannel.right), p(2)]));
      expect(inputs(cmd), 3);
      cmd = build(proj([p(0), p(1, track: 0), p(2)]));
      expect(inputs(cmd), 3);
      // Values that come out the same count as the same.
      cmd = build(proj([p(0, focus: 0.001), p(1, focus: 0), p(2, focus: 0.004)]));
      expect(inputs(cmd), 1);
    });
  });

  group('preview filters', () {
    test('nothing for a plain clip', () {
      expect(previewAudioFilter(piece(0, 1000)), '');
      expect(previewAudioTrack(piece(0, 1000)), 0);
    });

    test('only equalizer and mpv format filters (all the shipped players have)', () {
      final c = piece(0, 1000).copyWith(
          voiceFocus: 1, audioChannel: AudioChannel.left, audioTrack: 1, denoise: true);
      final af = previewAudioFilter(c);
      final graph = RegExp(r'lavfi=\[([^\]]*)\]').firstMatch(af)!.group(1)!;
      for (final f in graph.split(',')) {
        expect(f, startsWith('equalizer='));
      }
      // Planar float into the graph (no format conversion inside it), and
      // nothing from lavfi after mpv's channel conversion.
      expect(af, startsWith('format=format=floatp,lavfi=['));
      expect(af, endsWith('],format=channels=mono,format=channels=stereo'));
      expect(af, isNot(contains('afftdn')));
      expect(previewAudioTrack(c), 1);
    });

    test('left only: right side silenced, the left put on both at its level', () {
      expect(previewAudioFilter(piece(0, 1000).copyWith(audioChannel: AudioChannel.left)),
          'format=format=floatp,lavfi=['
          'equalizer=f=300:t=q:w=0.001:g=-50:c=FR,'
          'equalizer=f=3000:t=q:w=0.001:g=-50:c=FR,'
          'equalizer=f=1000:t=q:w=0.001:g=6.0206],'
          'format=channels=mono,format=channels=stereo');
      expect(previewAudioFilter(piece(0, 1000).copyWith(audioChannel: AudioChannel.right)),
          contains(':c=FL,'));
      // Not on a mono stream.
      expect(
          previewAudioFilter(piece(0, 1000)
              .copyWith(audioChannel: AudioChannel.right, audioStreams: const [1])),
          '');
    });

    test('clean-up: only its rumble cut plays live', () {
      final af = previewAudioFilter(piece(0, 1000).copyWith(denoise: true));
      expect(af, 'format=format=floatp,lavfi=['
          'equalizer=f=25.5:t=o:w=0.868:g=-17.46,'
          'equalizer=f=40:t=o:w=1.136:g=-7.24]');
    });

    test('voice focus: the low cut and the presence boost', () {
      expect(previewAudioFilter(piece(0, 1000).copyWith(voiceFocus: 1)),
          'format=format=floatp,lavfi=['
          'equalizer=f=25.5:t=o:w=1.21:g=-25.7,'
          'equalizer=f=45.2:t=o:w=1.61:g=-11.6,'
          'equalizer=f=3000:t=o:w=1.5:g=3]');
    });
  });

  group('probe', () {
    test('channels per audio stream', () {
      final i = parseProbeJson({
        'streams': [
          {'codec_type': 'video', 'width': 640, 'height': 360},
          {'codec_type': 'audio', 'channels': 2},
          {'codec_type': 'audio', 'channels': '1'},
          {'codec_type': 'audio'},
        ],
        'format': {'duration': '3.0', 'format_name': 'mov,mp4'},
      });
      expect(i.audioStreams, [2, 1, 0]);
      expect(i.hasAudio, isTrue);
      expect(const MediaInfo(durationMs: 1, width: 1, height: 1, hasVideo: true, hasAudio: true)
          .audioStreams, isEmpty);
    });
  });

  group('silence detection command', () {
    test('track and side', () {
      final a = buildSilenceDetectCommand(
          path: '/m/a.mp4', audioTrack: 1, channel: AudioChannel.right);
      expect(a.sublist(0, 6), [
        '-i', '/m/a.mp4', '-map', '0:a:1', '-af',
        'pan=mono|c0=c1,silencedetect=noise=-35dB:d=0.700',
      ]);
    });
  });
}
