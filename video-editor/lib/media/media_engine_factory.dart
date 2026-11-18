// Picks the MediaEngine for the platform the app runs on. This is the only
// file of the media layer's public surface that needs Flutter (through the
// ffmpeg_kit plugin and the bundled font assets); command-line programs
// construct a ProcessMediaEngine themselves instead.

import 'dart:io' show Platform;

import 'ffmpeg_kit_media_engine.dart';
import 'media_api.dart';
import 'media_fonts.dart';
import 'process_media_engine.dart';

/// Android, iOS, macOS and Windows use FFmpeg linked into the app
/// (ffmpeg_kit_flutter_new); Linux runs an ffmpeg executable. Both draw
/// titles with the fonts bundled as assets.
MediaEngine createMediaEngine() {
  if (Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows) {
    return FfmpegKitMediaEngine();
  }
  return ProcessMediaEngine(fontResolver: bundledFonts);
}
