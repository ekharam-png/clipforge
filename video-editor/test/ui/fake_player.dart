import 'dart:async';

import 'package:clipforge/ui/playback/timeline_player.dart';
import 'package:flutter/widgets.dart';

/// Records every command and lets a test push position / completed events.
class FakePlayer implements TimelinePlayer {
  FakePlayer({this.name = 'player', this.events});

  /// How the shared [events] log names this player.
  final String name;

  /// Lifecycle events shared with the backend (surfaces, disposal), to
  /// check their order.
  final List<String>? events;
  final List<String> log = [];
  final _position = StreamController<int>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  String? path;
  int positionMs = 0;
  bool playing = false;
  double volume = 1;
  double rate = 1;
  int audioTrack = 0;
  String audioFilter = '';
  bool disposed = false;

  void emitPosition(int ms) {
    positionMs = ms;
    _position.add(ms);
  }

  void emitCompleted() => _completed.add(null);

  @override
  Future<void> open(String path,
      {required int positionMs, required bool play}) async {
    log.add('open $path@$positionMs ${play ? 'play' : 'paused'}');
    this.path = path;
    this.positionMs = positionMs;
    playing = play;
  }

  @override
  Future<void> play() async {
    log.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(int positionMs) async {
    log.add('seek $positionMs');
    this.positionMs = positionMs;
  }

  @override
  Future<void> setVolume(double volume) async {
    log.add('volume ${volume.toStringAsFixed(2)}');
    this.volume = volume;
  }

  @override
  Future<void> setRate(double rate) async {
    log.add('rate ${rate.toStringAsFixed(2)}');
    this.rate = rate;
  }

  @override
  Future<void> setAudioTrack(int index) async {
    log.add('track $index');
    audioTrack = index;
  }

  @override
  Future<void> setAudioFilter(String filter) async {
    log.add('af $filter');
    audioFilter = filter;
  }

  @override
  Stream<int> get positionStream => _position.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Future<void> dispose() async {
    log.add('dispose');
    events?.add('$name disposed');
    disposed = true;
  }
}

class FakeBackend implements PlayerBackend {
  /// Surfaces mounted and unmounted, players disposed, in order.
  final List<String> events = [];

  /// The first video player; the editor makes a second one when it needs
  /// it, see [videoPlayers].
  late final FakePlayer video = FakePlayer(name: 'video 0', events: events);
  late final List<FakePlayer> videoPlayers = [video];
  int _videoMade = 0;
  final List<FakePlayer> audio = [];

  @override
  TimelinePlayer createVideoPlayer() {
    if (_videoMade++ == 0) return video;
    final p = FakePlayer(name: 'video ${_videoMade - 1}', events: events);
    videoPlayers.add(p);
    return p;
  }

  @override
  TimelinePlayer createAudioPlayer() {
    final p = FakePlayer(name: 'music ${audio.length}', events: events);
    audio.add(p);
    return p;
  }

  @override
  Widget buildVideoSurface(TimelinePlayer videoPlayer) =>
      _FakeSurface(name: (videoPlayer as FakePlayer).name, events: events);
}

/// Stands in for a video texture; says when it comes and goes.
class _FakeSurface extends StatefulWidget {
  const _FakeSurface({required this.name, required this.events});
  final String name;
  final List<String> events;

  @override
  State<_FakeSurface> createState() => _FakeSurfaceState();
}

class _FakeSurfaceState extends State<_FakeSurface> {
  @override
  void initState() {
    super.initState();
    widget.events.add('${widget.name} surface mounted');
  }

  @override
  void dispose() {
    widget.events.add('${widget.name} surface gone');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF2E5E8C));
}
