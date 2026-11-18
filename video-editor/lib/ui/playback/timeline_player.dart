import 'package:flutter/widgets.dart';

/// The small slice of a media player that [PlaybackController] needs.
/// Positions are milliseconds inside the source file.
abstract class TimelinePlayer {
  /// Loads [path], positions it at [positionMs] and plays or stays paused.
  Future<void> open(String path, {required int positionMs, required bool play});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int positionMs);

  /// Linear amplitude: 1.0 is the file's own level, 0.5 half the sample
  /// values (-6 dB), values up to 2.0 boost. Same scale as the export.
  Future<void> setVolume(double volume);

  /// Playback speed, 1.0 = normal. Sound keeps its pitch.
  Future<void> setRate(double rate);

  /// Which audio stream of the file plays: 0 is the first. Applies to the
  /// loaded file and to files opened later.
  Future<void> setAudioTrack(int index);

  /// Audio filters for the sound, in mpv's `af` syntax (see
  /// `previewAudioFilter` in media/clip_audio.dart); empty for none. They
  /// keep the level of the sound, so [setVolume] stays exact. Applies to
  /// the loaded file and to files opened later.
  Future<void> setAudioFilter(String filter);

  /// Position inside the loaded file while it plays.
  Stream<int> get positionStream;

  /// Fires when the loaded file reaches its end.
  Stream<void> get completedStream;
  Future<void> dispose();
}

/// Creates players and the widget that shows a video player's picture.
abstract class PlayerBackend {
  /// Called at most four times per editor: the preview keeps two video
  /// players for the main track (so that the next clip can be loaded
  /// before the current one ends) and up to two for the overlay track.
  TimelinePlayer createVideoPlayer();
  TimelinePlayer createAudioPlayer();

  /// The picture of a player made by [createVideoPlayer]. It is laid out at
  /// the clip's pixel size by the caller, so it should simply fill its box.
  /// May be called more than once for the same player (the blurred backdrop
  /// draws the picture a second time).
  Widget buildVideoSurface(TimelinePlayer videoPlayer);
}
