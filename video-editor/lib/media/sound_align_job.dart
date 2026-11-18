// "Line up by sound" on top of an engine's ffmpeg runner (dart:io only):
// decodes the two sounds to small raw files, reads their envelopes and
// compares them (media/sound_align.dart).

import 'dart:io';

import 'package:path/path.dart' as p;

import 'media_api.dart';
import 'media_common.dart';
import 'sound_align.dart';

export 'sound_align.dart';

/// An engine that can line up a voice file with a video's own sound.
abstract interface class SoundAlignEngine {
  /// Finds the offset of the sound file [voicePath] against the sound of
  /// [videoPath] (its audio stream [videoAudioTrack]): time in the voice
  /// file = time in the video file + offset. Never throws for sounds that
  /// do not match or a video without sound: the result then has a low
  /// confidence and a reason. Throws [ExportException] when a file cannot
  /// be read at all.
  Future<AlignResult> alignSound(String videoPath, String voicePath,
      {int videoAudioTrack = 0, int voiceAudioTrack = 0});
}

/// The last few envelopes, so that several voice files (one per speaker)
/// decode the video's sound once. About 2 MB per 40 minutes.
final Map<String, SoundEnvelope> _envelopes = {};
const int _keepEnvelopes = 4;

Future<String> _fileKey(String path, int track) async {
  var stamp = '';
  try {
    final st = await File(path).stat();
    stamp = '${st.size}_${st.modified.millisecondsSinceEpoch}';
  } catch (_) {}
  return '$path|$stamp|$track';
}

/// The envelope of the sound of [path]; null when the file has no sound.
Future<SoundEnvelope?> soundEnvelopeWith(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String path, {
  int audioTrack = 0,
}) async {
  final info = await probe(path);
  if (!info.hasAudio) return null;
  final track = audioTrack > 0 && audioTrack < info.audioStreams.length
      ? audioTrack
      : 0;
  final key = await _fileKey(path, track);
  final known = _envelopes.remove(key);
  if (known != null) {
    _envelopes[key] = known; // most recently used last
    return known;
  }
  final dir = await Directory.systemTemp.createTemp('clipforge_align_');
  try {
    final raw = p.join(dir.path, 'sound.raw');
    final r = await run([
      '-nostats', '-loglevel', 'error',
      ...buildAlignDecodeCommand(
          path: path, outputPath: raw, audioTrack: track),
    ]);
    if (!r.ok || !await File(raw).exists()) {
      throw ExportException('Cannot read the sound of ${p.basename(path)}',
          log: (LogTail()..add(r.log)).toString());
    }
    final env = await SoundEnvelope.fromRawFile(raw);
    _envelopes[key] = env;
    while (_envelopes.length > _keepEnvelopes) {
      _envelopes.remove(_envelopes.keys.first);
    }
    return env;
  } finally {
    await deleteQuietly(dir);
  }
}

/// [SoundAlignEngine.alignSound] on top of [run] and the engine's [probe].
Future<AlignResult> alignSoundWith(
  FfmpegRunner run,
  Future<MediaInfo> Function(String path) probe,
  String videoPath,
  String voicePath, {
  int videoAudioTrack = 0,
  int voiceAudioTrack = 0,
}) async {
  final video =
      await soundEnvelopeWith(run, probe, videoPath, audioTrack: videoAudioTrack);
  if (video == null) return const AlignResult.none('The video has no sound.');
  final voice =
      await soundEnvelopeWith(run, probe, voicePath, audioTrack: voiceAudioTrack);
  if (voice == null) return const AlignResult.none('The file has no sound.');
  return alignEnvelopes(video, voice);
}
