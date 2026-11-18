// Pure Dart: "instant sound processing". A clip's own sound with its heavy
// stages (clean-up, voice focus; later AI separation) is rendered ahead of
// time, in the background, with the export's own chain (clip_audio.dart),
// into a cached file. The preview then plays that file (the shipped players
// can only run `equalizer`, see clip_audio.dart), and the export reads it
// instead of running the chain again.
//
// What a processed file is:
//
//  * the WHOLE source file (not one clip's trim range), at SOURCE timing
//    (before speed): sample n is source time n / 48000 s, counted from the
//    start of the file as players and ffmpeg count it (`aresample` with
//    `async=1:first_pts=0` fills a late first audio packet). So every
//    piece of one file with the same sound settings - split halves, what
//    "Remove silences" leaves, a re-trimmed clip - shares ONE file, and
//    any position is found by seeking to the source time;
//  * stages 1..3 of the clip's sound (source track and side, clean-up,
//    voice focus) exactly as [clipSoundFilters] builds them for the export;
//    speed and volume (stage 4) stay live in the player / the export graph;
//  * 48 kHz stereo FLAC, 16 bit: lossless, so the export loses nothing by
//    reading it, about 2 MB per minute (a third of WAV), and seeks to the
//    sample (FLAC frames are 4096 samples; ffmpeg and mpv decode from the
//    frame before and drop what precedes the target).
//
// Its name is a hash of everything that decides its content
// ([processedSoundKey]): the source path, size and modification time, the
// settings ([processedSoundSignature]) and [kSoundChainVersion]. A file of
// that name in the cache is therefore always up to date; anything that
// changes the sound gives another name. Old files are removed by the
// cache's size limit (least recently used first) and by the clean-up of
// unused app media (they count as used while a saved project's clip leads
// to them).
//
// EXTENSION POINT for AI voice / music separation (see clip_audio.dart):
// separation replaces stage 1, so it belongs in this file's render, not in
// the preview or the export graph. When a clip gets separation settings,
//  1. add them to [processedSoundSignature] (stem model, voice level,
//     background level) and to [clipNeedsProcessedSound];
//  2. let [buildProcessedSoundCommand] take the two stem files as inputs
//     (`-i voice.flac -i background.flac`), mix them at their levels
//     (`[0:a]volume=v[a];[1:a]volume=b[b];[a][b]amix=normalize=0`) in place
//     of `[0:a:T]` + [audioSourceFilters], then continue with clean-up and
//     voice focus as today;
//  3. key the stems themselves by source + model so that changing a level
//     re-mixes in seconds without separating again.
// The preview, the export reuse, the cache and the queue need no change.

import '../core/model/project.dart';
import 'clip_audio.dart';
import 'sound_filters.dart' show SoundStage;

/// Bumped whenever the processed sound of the same settings would come out
/// differently (a filter value in clip_audio.dart, the file format, the
/// render command), so that old files are not used any more.
const int kSoundChainVersion = 1;

/// Sample rate of processed files (the export's rate).
const int kProcessedSampleRate = 48000;

/// File extension of processed files.
const String kProcessedSoundExtension = 'flac';

/// Folder of the processed files inside the app's media folder.
const String kProcessedSoundFolder = 'processed';

/// True when [clip]'s own sound has a stage the preview players cannot
/// play live (clean-up, voice focus), so that it is worth rendering ahead
/// of time. Track and side alone play exactly live and need no file.
/// A muted (or silent) clip needs none: nothing of it is heard.
bool clipNeedsProcessedSound(Clip clip) =>
    clip.type == ClipType.video &&
    clip.hasAudio &&
    !clip.muted &&
    clip.volume > 0 &&
    (clip.denoise || voiceFocusOf(clip) > 0);

/// The sound settings that decide a processed file's content, as text
/// ("t0|both|d1|vf0.85"). Volume, mute and speed are left out: they are
/// applied live (preview) or after it (export).
String processedSoundSignature(Clip clip) {
  final vf = voiceFocusOf(clip);
  return [
    't${clip.audioTrackInUse}',
    clip.audioChannelInUse.name,
    'd${clip.denoise ? 1 : 0}',
    'vf${vf.toStringAsFixed(4)}',
  ].join('|');
}

/// Name (without folder and extension) of the processed file for [clip]
/// whose source file has [size] bytes and was last modified at
/// [modifiedMs] (milliseconds since the epoch). [leaveOut]: sound stages
/// the FFmpeg in use cannot run (normally none).
String processedSoundKey(Clip clip,
    {required int size,
    required int modifiedMs,
    Set<SoundStage> leaveOut = const {}}) {
  final stages = [for (final s in leaveOut) s.name]..sort();
  final text = [
    'v$kSoundChainVersion',
    clip.path,
    '$size',
    '$modifiedMs',
    processedSoundSignature(clip),
    if (stages.isNotEmpty) 'without:${stages.join(',')}',
  ].join('\n');
  return 'snd_${stableHash(text)}';
}

/// The file name of [key] ([processedSoundKey]).
String processedSoundFileName(String key) => '$key.$kProcessedSoundExtension';

/// True when [name] (a file name) looks like a processed file.
bool isProcessedSoundFileName(String name) =>
    name.startsWith('snd_') && name.endsWith('.$kProcessedSoundExtension');

/// 128-bit FNV-1a style hash of [s] as 32 hex digits: four 32-bit passes
/// with different seeds. Stable across runs and platforms (cache names),
/// not meant to be secure.
String stableHash(String s) {
  String pass(int seed, int salt) {
    var h = seed;
    for (final c in s.codeUnits) {
      h ^= (c ^ salt) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= c >> 8;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return pass(0x811C9DC5, 0) +
      pass(0x01234567, 0x5A) +
      pass(0x89ABCDEF, 0xA5) +
      pass(0x0F1E2D3C, 0x3C);
}

/// The filter chain of a processed file: the source on the 48 kHz grid
/// from the file's start, then [clipSoundFilters] (track and side,
/// clean-up, voice focus) exactly as the export runs it.
String processedSoundFilter(Clip clip, {Set<SoundStage> leaveOut = const {}}) {
  const fmt = 'aformat=sample_fmts=fltp:channel_layouts=stereo';
  final chain = clipSoundFilters(clip, fmt, leaveOut: leaveOut);
  return 'aresample=$kProcessedSampleRate:async=1:first_pts=0,$fmt,'
      '${chain.isEmpty ? '' : chain}anull';
}

/// ffmpeg arguments (no program name, no runner flags) that write the
/// processed sound of [clip]'s whole source file to [outputPath] as FLAC.
/// The caller writes to a temporary name and renames it when ffmpeg is
/// done, so a cut-off render never looks finished.
List<String> buildProcessedSoundCommand(
  Clip clip,
  String outputPath, {
  Set<SoundStage> leaveOut = const {},
}) =>
    [
      '-y',
      '-i', clip.path,
      '-map', '0:a:${clip.audioTrackInUse}',
      '-vn', '-sn', '-dn',
      '-af', processedSoundFilter(clip, leaveOut: leaveOut),
      '-c:a', 'flac',
      '-sample_fmt', 's16',
      '-ar', '$kProcessedSampleRate',
      '-ac', '2',
      '-map_metadata', '-1',
      '-f', 'flac',
      outputPath,
    ];

/// The output position in milliseconds from one line of ffmpeg's
/// `-progress` output (`out_time_us=`, or `out_time_ms=`, which is in
/// microseconds too); null for other lines.
int? parseProgressTimeMs(String line) {
  final l = line.trim();
  int? us;
  if (l.startsWith('out_time_us=') || l.startsWith('out_time_ms=')) {
    us = int.tryParse(l.substring(12));
  }
  if (us == null || us < 0) return null;
  return us ~/ 1000;
}
