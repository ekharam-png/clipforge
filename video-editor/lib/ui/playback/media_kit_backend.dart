import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'timeline_player.dart';

/// The value of mpv's `volume` property that plays a sound at [amplitude]
/// times its own level (1.0 = unchanged, 0.5 = half the sample values,
/// which is what the export's `volume=0.5` and its fades do).
///
/// mpv's volume is not linear: it multiplies the samples by
/// `(volume / 100)³` (player/audio.c, `gain = pow(volume / 100, 3)`;
/// measured with mpv 0.37 and `--ao=pcm`: volume 50 gives -18.06 dB, i.e.
/// 0.125, not 0.5). So the cube root goes in. 2.0, the loudest the editor
/// allows, needs 126, inside mpv's default `volume-max` of 130.
double mpvVolumeFor(double amplitude) {
  if (amplitude.isNaN || amplitude <= 0) return 0;
  final a = amplitude > 2 ? 2.0 : amplitude;
  return 100 * math.pow(a, 1 / 3).toDouble();
}

/// Whether mpv dropped the sound of a loaded file because it could not
/// build the audio [filter]s (measured with mpv 0.37: "Audio filter
/// initialized failed!", then `aid` reads "no" while the file has an audio
/// track and the `aid` option is still "auto" or a number; the picture
/// plays on, silent, and so do the files opened after it).
///
/// [aid] is mpv's `aid` property, [aidOption] its `options/aid`,
/// [trackTypes] the `type` of each entry of `track-list`. An `aid` option
/// of "no" means the track choice, not the filter, silenced it.
bool filterSilencedSound({
  required String filter,
  required String aid,
  required String aidOption,
  required List<String> trackTypes,
}) =>
    filter.isNotEmpty &&
    (aid == 'no' || aid == 'false') &&
    aidOption != 'no' &&
    aidOption != 'false' &&
    trackTypes.contains('audio');

/// [TimelinePlayer] backed by a media_kit (libmpv) [Player].
///
/// A video player borrows its [Player] and [VideoController] from
/// [VideoPlayerPool] and gives them back on [dispose] instead of destroying
/// them; see there for why. A music player owns its [Player].
class MediaKitTimelinePlayer implements TimelinePlayer {
  MediaKitTimelinePlayer({required bool withVideo})
      : this._(withVideo ? VideoPlayerPool.instance.take() : null);

  MediaKitTimelinePlayer._(this._pooled)
      : player = _pooled?.player ?? Player(),
        controller = _pooled?.controller;

  final PooledVideoPlayer? _pooled;
  final Player player;
  final VideoController? controller;

  /// How long a file may take to become playable.
  static const Duration loadTimeout = Duration(seconds: 4);

  bool _disposed = false;

  /// Completes when the file is really loaded, so that a [seek] right after
  /// it is not lost: `Player.open` itself returns while mpv is still opening
  /// the file, and mpv refuses to seek until then. Throws when the file does
  /// not load.
  @override
  Future<void> open(String path,
      {required int positionMs, required bool play}) async {
    final media = Media(path, start: Duration(milliseconds: positionMs));
    var reopened = false;
    for (var attempt = 0;; attempt++) {
      // A player given back mid-load must not touch the core again: the
      // pool may already have lent it to the next editor.
      if (_disposed) throw StateError('The player was closed');
      await player.open(media, play: play);
      if (await _waitUntilLoaded()) {
        // mpv could not build the sound filters for this file: it then
        // plays the picture WITHOUT sound (and keeps doing so for the
        // files after it). Drop the filters for good and load it again.
        if (!reopened && await _filterSilencedSound()) {
          reopened = true;
          rejectedAudioFilters.add(_audioFilter);
          debugPrint('ClipForge: the preview player refused the sound '
              'filter "$_audioFilter"; playing without it.');
          await _setAf('');
          continue;
        }
        // Players that never had a track chosen (music, plain clips) are
        // left as they are.
        if (_audioTrackChosen) await _applyAudioTrack();
        return;
      }
      // Opening files in quick succession can leave mpv with nothing
      // loaded; a second try gets it going.
      if (attempt > 0 || _disposed) {
        throw StateError('The player could not load $path');
      }
    }
  }

  /// Waits for mpv to report a playback time, which it has from the moment
  /// the file can be played and seeked. Call right after `Player.open`:
  /// everything the old file still had to say has been delivered by then.
  Future<bool> _waitUntilLoaded() async {
    try {
      await player.stream.position.first.timeout(loadTimeout);
      return !_disposed;
    } on TimeoutException {
      // No news is not always bad news: ask.
      final native = player.platform;
      if (_disposed || native is! NativePlayer) return !_disposed;
      return (await native.getProperty('time-pos')).isNotEmpty;
    } on StateError {
      return false; // the player was disposed while waiting
    }
  }

  // Commands after [dispose] (still queued by the playback controller) do
  // nothing: a video player's core may belong to the next editor by then.
  static final Future<void> _nothing = Future.value();

  @override
  Future<void> play() => _disposed ? _nothing : player.play();

  @override
  Future<void> pause() => _disposed ? _nothing : player.pause();

  @override
  Future<void> seek(int positionMs) => _disposed
      ? _nothing
      : player.seek(Duration(milliseconds: positionMs));

  /// [volume] is a linear amplitude factor, like everywhere in the app.
  @override
  Future<void> setVolume(double volume) =>
      _disposed ? _nothing : player.setVolume(mpvVolumeFor(volume));

  /// mpv keeps the pitch of the sound when the speed changes
  /// (audio-pitch-correction is on by default).
  @override
  Future<void> setRate(double rate) =>
      _disposed ? _nothing : player.setRate(rate);

  int _audioTrack = 0;
  bool _audioTrackChosen = false;

  /// mpv numbers the audio tracks of a file from 1 (`aid`). The track is
  /// set again after every [open]: asking mpv for a track the loaded file
  /// does not have turns its `aid` option into "no", which would leave the
  /// next file without sound.
  @override
  Future<void> setAudioTrack(int index) async {
    _audioTrack = index < 0 ? 0 : index;
    _audioTrackChosen = true;
    await _applyAudioTrack();
  }

  /// Only when it differs: switching tracks makes mpv seek to put the new
  /// track in step, which a file that keeps its track does not need.
  Future<void> _applyAudioTrack() async {
    final native = player.platform;
    if (_disposed || native is! NativePlayer) return;
    final want = '${_audioTrack + 1}';
    final now = await native.getProperty('aid');
    if (now == want || (now == 'auto' && _audioTrack == 0)) return;
    await native.setProperty('aid', want);
  }

  /// mpv's `af` property. The libmpv builds media_kit ships for Android,
  /// Windows and macOS have only the `equalizer` audio filter of FFmpeg
  /// (besides mpv's own); the filters of `previewAudioFilter` stay within
  /// that.
  ///
  /// Should mpv still refuse one (a libmpv with fewer filters), the file
  /// would play silently; [open] notices that, plays the file without the
  /// filter, and the filter is not used again in this run of the app
  /// ([rejectedAudioFilters]). A filter refused while a file plays leaves
  /// that file as it was (mpv keeps its previous filters).
  @override
  Future<void> setAudioFilter(String filter) =>
      _setAf(rejectedAudioFilters.contains(filter) ? '' : filter);

  String _audioFilter = '';

  Future<void> _setAf(String filter) async {
    final native = player.platform;
    if (_disposed || native is! NativePlayer) return;
    _audioFilter = filter;
    await native.setProperty('af', filter);
  }

  /// `af` values that made mpv drop the sound on this computer.
  static final Set<String> rejectedAudioFilters = {};

  /// Whether the loaded file plays without sound because of [_audioFilter]
  /// (see [filterSilencedSound]).
  Future<bool> _filterSilencedSound() async {
    final native = player.platform;
    if (_disposed || _audioFilter.isEmpty || native is! NativePlayer) {
      return false;
    }
    try {
      final aid = await native.getProperty('aid');
      if (aid != 'no' && aid != 'false') return false;
      final count = int.tryParse(await native.getProperty('track-list/count')) ?? 0;
      return filterSilencedSound(
        filter: _audioFilter,
        aid: aid,
        aidOption: await native.getProperty('options/aid'),
        trackTypes: [
          for (var i = 0; i < count && i < 32; i++)
            await native.getProperty('track-list/$i/type'),
        ],
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<int> get positionStream =>
      player.stream.position.map((d) => d.inMilliseconds);

  @override
  Stream<void> get completedStream =>
      player.stream.completed.where((done) => done);

  Future<void>? _disposal;

  /// Stops the player for good, as far as its owner is concerned. Safe to
  /// call more than once.
  ///
  /// A video player goes back to [VideoPlayerPool] (stopped, its settings
  /// reset) and its core is never destroyed. A music player has no video
  /// output, so its core can be destroyed safely.
  @override
  Future<void> dispose() => _disposal ??= () async {
        _disposed = true;
        final pooled = _pooled;
        if (pooled != null) {
          await VideoPlayerPool.instance.giveBack(pooled);
          return;
        }
        try {
          await player.dispose();
        } catch (_) {
          // Already disposed.
        }
      }();
}

/// How the preview's [VideoController] decodes.
///
/// media_kit already asks mpv for hardware decoding by default (`hwdec`
/// `auto` on desktop, `auto-safe` on Android except in emulators, where it
/// is `no`). On desktop it is pinned here to `auto-safe`: only the decoders
/// mpv lists as giving correct output (VideoToolbox on macOS, D3D11VA /
/// DXVA2 / NVDEC on Windows, VAAPI / NVDEC on Linux), with software
/// decoding whenever a file or the card is not supported, so nothing stops
/// playing. Android keeps the plugin's own choice, which knows about
/// emulators. Only decoding changes: the texture / render context (and the
/// order in which players are given back and disposed) is untouched, and
/// both A/B players of an editor get the same setting.
VideoControllerConfiguration previewVideoConfiguration() => Platform.isAndroid
    ? const VideoControllerConfiguration()
    : const VideoControllerConfiguration(hwdec: 'auto-safe');

/// A media_kit [Player] with its [VideoController], owned by
/// [VideoPlayerPool].
class PooledVideoPlayer {
  PooledVideoPlayer._() : player = Player() {
    controller =
        VideoController(player, configuration: previewVideoConfiguration());
  }

  final Player player;
  late final VideoController controller;

  /// True while an editor uses it.
  bool lent = false;
}

/// Keeps the video players of the app alive for as long as the app runs and
/// lends them to one editor after another.
///
/// Why they are never destroyed: libmpv aborts the whole process
/// ("Broken API use: mpv_render_context_free() not called", player/client.c
/// `mp_clients_destroy`) when a core is destroyed while a render context
/// made for it still exists. `Player.dispose` (media_kit 1.2.6,
/// native/player/real.dart) asks media_kit_video to drop the video output
/// and destroys the core on a fixed 5 s timer. On Linux the output frees its
/// render context at once (media_kit_video linux/video_output.cc). On macOS
/// it only drops a reference (macos/.../VideoOutputManager.swift `destroy`);
/// the render context is freed later, in `TextureHW.deinit`, once the
/// output's worker thread has drained its jobs (each waits for the main
/// thread) and the Flutter texture registry has let go of the texture (on
/// a later turn of the main queue). Nothing tells Dart when that has
/// happened, so whenever it takes longer than the 5 s, the app is killed.
/// A player whose core is never destroyed cannot hit that. Music players
/// have no video output and are still disposed.
///
/// An editor uses at most four video players (two for the main track, two
/// for the overlay track, made only when a project has overlay videos), so
/// the pool stays at two to four in normal use (a few more only if editors overlap, e.g. a project opened
/// while the previous editor is still closing).
class VideoPlayerPool {
  VideoPlayerPool._();

  static final VideoPlayerPool instance = VideoPlayerPool._();

  final List<PooledVideoPlayer> _all = [];

  /// Players that are back, reset and ready to lend.
  final List<PooledVideoPlayer> _idle = [];

  /// How many players the pool has made.
  int get created => _all.length;

  /// How many are lent out right now.
  int get lent => _all.where((p) => p.lent).length;

  /// A reset, idle player, or a new one.
  PooledVideoPlayer take() {
    final p = _idle.isNotEmpty ? _idle.removeLast() : _make();
    p.lent = true;
    return p;
  }

  PooledVideoPlayer _make() {
    final p = PooledVideoPlayer._();
    _all.add(p);
    return p;
  }

  /// Stops [p] and puts back what a fresh player has, then makes it
  /// available again. Commands still queued in media_kit for the previous
  /// editor run before the stop (they share one lock). A player that does
  /// not reset cleanly is kept out of use (but still not destroyed).
  Future<void> giveBack(PooledVideoPlayer p) async {
    if (!p.lent) return;
    p.lent = false;
    try {
      await p.player.stop();
      await p.player.setVolume(100);
      await p.player.setRate(1);
      final native = p.player.platform;
      if (native is NativePlayer) {
        await native.setProperty('af', '');
        await native.setProperty('aid', 'auto');
      }
    } catch (_) {
      return;
    }
    if (!p.lent && !_idle.contains(p)) _idle.add(p);
  }
}

class MediaKitBackend implements PlayerBackend {
  const MediaKitBackend();

  /// "Smooth preview" (phones, 1.8; app setting, on by default on Android):
  /// the preview's video decoders skip the H.264/HEVC deblocking filter and
  /// use libavcodec's fast, slightly less exact paths (mpv
  /// `vd-lavc-skiploopfilter=all`, `vd-lavc-fast=yes`). This lightens
  /// SOFTWARE decoding (files the phone's hardware decoder refuses, e.g.
  /// some 10-bit HDR or 4K clips, and while two or four players run at
  /// once); the picture may look a little softer or blockier. Hardware
  /// decoding and the export are not affected. Applies to files opened
  /// after it is set.
  static bool smoothPreview = false;

  static Future<void> applySmoothPreview(Player player) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty(
          'vd-lavc-skiploopfilter', smoothPreview ? 'all' : 'default');
      await native.setProperty('vd-lavc-fast', smoothPreview ? 'yes' : 'no');
    } catch (_) {
      // An mpv without these options: the preview just stays as it is.
    }
  }

  @override
  TimelinePlayer createVideoPlayer() {
    final p = MediaKitTimelinePlayer(withVideo: true);
    unawaited(applySmoothPreview(p.player));
    return p;
  }

  @override
  TimelinePlayer createAudioPlayer() =>
      MediaKitTimelinePlayer(withVideo: false);

  @override
  Widget buildVideoSurface(TimelinePlayer videoPlayer) {
    final controller = (videoPlayer as MediaKitTimelinePlayer).controller!;
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: BoxFit.fill,
      fill: const Color(0x00000000),
      // The editor pauses playback itself when the app goes to background.
      pauseUponEnteringBackgroundMode: false,
    );
  }
}
