import '../core/model/project.dart';
import 'video_encoder.dart';

export 'video_encoder.dart' show VideoEncoder;

/// CONTRACT between the media/export layer and the UI.
///
/// Pure Dart (no Flutter, no plugins): command-line tools can import this
/// file, `ffmpeg_command.dart` and `process_media_engine.dart`. The engine
/// for the running platform is picked by `createMediaEngine()` in
/// `media_engine_factory.dart`, which is the Flutter-only part.

class MediaInfo {
  const MediaInfo({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasVideo,
    required this.hasAudio,
    this.fps = 0,
    this.audioStreams = const [],
  });
  final int durationMs; // 0 for still images
  final int width; // display size, rotation applied; 0 for audio-only
  final int height;
  final bool hasVideo;
  final bool hasAudio;

  /// Frame rate of the video (average frames per second); 0 when unknown,
  /// for photos and for audio files.
  final double fps;

  /// Channel count of each audio stream, in file order (0 where the probe
  /// did not say). Empty when the file has no sound or the engine does not
  /// report it. Stored as [Clip.audioStreams].
  final List<int> audioStreams;
}

enum ExportQuality { full, small }

/// What an export makes: a video (MP4, H.264 + AAC), or the sound only as
/// an M4A (AAC) or MP3 file.
enum ExportFormat {
  video,
  m4a,
  mp3;

  bool get audioOnly => this != ExportFormat.video;

  /// File name extension, without the dot.
  String get extension => switch (this) {
        ExportFormat.video => 'mp4',
        ExportFormat.m4a => 'm4a',
        ExportFormat.mp3 => 'mp3',
      };
}

class ExportOptions {
  const ExportOptions({
    this.quality = ExportQuality.full,
    this.fps = 30,
    this.useHardwareEncoder = true,
    this.processedSound = const {},
    this.format = ExportFormat.video,
  });

  /// Video, or sound only ([ExportFormat]). Sound only ignores [quality]
  /// for the picture (there is none), [fps] and [useHardwareEncoder].
  final ExportFormat format;

  /// The frame rates offered in the Export window besides "Same as the
  /// clips" (every one divides the 48 kHz sound into whole samples).
  static const List<int> frameRateChoices = [24, 25, 30, 60];

  /// The export frame rate for "Same as the clips": the highest frame rate
  /// among [sourceFps] (0 = unknown is ignored), rounded to a whole number
  /// (29.97 -> 30, 23.976 -> 24, 59.94 -> 60) and kept to 1..60; [fallback]
  /// when none is known.
  static int sameAsSourceFps(Iterable<double> sourceFps, {int fallback = 30}) {
    var best = 0.0;
    for (final v in sourceFps) {
      if (v.isFinite && v > best) best = v;
    }
    if (best <= 0) return fallback;
    final r = best.round();
    return r < 1 ? 1 : (r > 60 ? 60 : r);
  }

  /// [full] keeps the canvas resolution; [small] scales the short side to
  /// 720 and uses a lower bitrate for messaging apps.
  final ExportQuality quality;

  /// Frames per second of the output (1..120; 30 by default).
  final int fps;

  /// Encode the picture on the graphics card when this computer/phone has
  /// an encoder for it ("Use graphics card (faster)"). The engine falls
  /// back to the processor (libx264) when there is none, or when it fails;
  /// see hardware_encoding.dart. False: always the processor.
  final bool useHardwareEncoder;

  /// Ready processed sound files (see media/processed_sound.dart) by clip
  /// id: such a clip's sound is read from the file (whole source file,
  /// source timing, stages 1..3 already applied) instead of running the
  /// clean-up / voice focus chain again. Only up-to-date files belong here
  /// (the app passes those whose key matches the clip now). Clips not
  /// listed use the normal chain.
  final Map<String, String> processedSound;

  /// Source frame rates from which a 60 fps export is worth offering.
  static const double highFrameRateFrom = 50;

  /// The export frame rate that suits sources with the frame rates
  /// [sourceFps] ([MediaInfo.fps]; 0 = unknown is ignored): 60 when any
  /// source has 50 fps or more, otherwise 30.
  static int suggestedFps(Iterable<double> sourceFps) =>
      sourceFps.any((v) => v.isFinite && v >= highFrameRateFrom) ? 60 : 30;
}

class ExportProgress {
  const ExportProgress(this.fraction);
  final double fraction; // 0..1
}

class ExportException implements Exception {
  ExportException(this.message,
      {this.log, this.cancelled = false, this.missingPaths = const []});

  /// One sentence for the user. For a failed ffmpeg run it ends with the
  /// line of the log that explains the failure, when there is one.
  final String message;

  /// Tail of the ffmpeg log, when there is one.
  final String? log;

  /// True when the export stopped because [ExportJob.cancel] was called.
  final bool cancelled;

  /// Source files of the project that do not exist (full paths, in project
  /// order, each once). Empty for every other kind of failure.
  final List<String> missingPaths;
  @override
  String toString() => 'ExportException: $message';
}

/// A running export. Await [done]; call [cancel] to stop it.
abstract class ExportJob {
  Stream<ExportProgress> get progress;

  /// Completes with the output path, or throws [ExportException].
  Future<String> get done;
  Future<void> cancel();

  /// The encoder that made the finished file; null until [done] completed
  /// successfully (and for engines that do not tell).
  VideoEncoder? get videoEncoder;

  /// Sound settings of the project that this export could not apply, one
  /// sentence each (e.g. "Clean up sound was left out: the FFmpeg on this
  /// device has no "afftdn" filter."). Empty when everything applied; final
  /// once [done] completed.
  List<String> get warnings;
}

abstract class MediaEngine {
  /// Reads duration / size / streams of a video, photo or audio file.
  Future<MediaInfo> probe(String path);

  /// Writes a JPEG frame of [path] at [timeMs] (thumbnails). Returns the
  /// output path.
  Future<String> thumbnail(String path, {int timeMs = 0, int maxHeight = 160});

  /// Writes a full-resolution PNG of the frame of video [path] at [timeMs]
  /// to [outputPath] (freeze frame). Returns [outputPath]. The frame is the
  /// one shown at [timeMs] (rotation applied); times at or past the end
  /// give the last frame.
  Future<String> extractFrame(String path, int timeMs, String outputPath);

  /// Finds the silent stretches in the sound of [path]. Returns source time
  /// ranges, in order, each at least [minSilenceMs] long. Empty when the
  /// file has no audio. [audioTrack] (0 = first) and [channel] pick the
  /// sound the clip uses ([Clip.audioTrackInUse], [Clip.audioChannelInUse]).
  /// [thresholdDb] null (the default) adapts the threshold to the
  /// recording's background noise (media/silence_levels.dart); a number
  /// uses `silencedetect` at that level.
  Future<List<({int startMs, int endMs})>> detectSilence(String path,
      {double? thresholdDb,
      int minSilenceMs = 700,
      int audioTrack = 0,
      AudioChannel channel = AudioChannel.both});

  /// True when exports can use a hardware video encoder here (checked once
  /// and remembered; false on machines without one, and after a hardware
  /// export failed during this run of the app).
  Future<bool> hasHardwareEncoder();

  /// The graphics card encoder exports use here now (found as for
  /// [hasHardwareEncoder]); null when there is none and exports use the
  /// processor.
  Future<VideoEncoder?> graphicsCardEncoder();

  /// Renders the processed sound of [clip] (its WHOLE source file, at
  /// source timing, with stages 1..3 of its sound: track and side,
  /// clean-up, voice focus) to [outputPath] as 48 kHz stereo FLAC; see
  /// media/processed_sound.dart. Progress is the fraction of the source
  /// file done. The file appears at [outputPath] only once it is complete.
  ExportJob renderClipSound(Clip clip, String outputPath);

  /// Renders [project] to an MP4 (H.264 + AAC) at [outputPath].
  ExportJob export(Project project, String outputPath,
      {ExportOptions options = const ExportOptions()});
}
