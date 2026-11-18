import 'dart:convert';

import 'package:clipforge/core/model/project.dart';

Clip video(
  String id, {
  int source = 10000,
  int inMs = 0,
  int? outMs,
  int width = 1920,
  int height = 1080,
  double volume = 1.0,
  double speed = 1.0,
  TransitionType transition = TransitionType.none,
  int transitionMs = 500,
}) =>
    Clip(
      id: id,
      type: ClipType.video,
      speed: speed,
      transition: transition,
      transitionMs: transitionMs,
      path: '/media/$id.mp4',
      sourceDurationMs: source,
      inMs: inMs,
      outMs: outMs ?? source,
      width: width,
      height: height,
      volume: volume,
    );

Clip photo(
  String id, {
  int durationMs = 3000,
  int inMs = 0,
  TransitionType transition = TransitionType.none,
  int transitionMs = 500,
}) =>
    Clip(
      id: id,
      transition: transition,
      transitionMs: transitionMs,
      type: ClipType.photo,
      path: '/media/$id.jpg',
      sourceDurationMs: 0,
      inMs: inMs,
      outMs: inMs + durationMs,
      width: 4000,
      height: 3000,
      hasAudio: false,
    );

AudioClip audio(
  String id, {
  int source = 30000,
  int startMs = 0,
  int inMs = 0,
  int? outMs,
  double volume = 1.0,
  int fadeInMs = 0,
  int fadeOutMs = 0,
}) =>
    AudioClip(
      id: id,
      path: '/media/$id.mp3',
      sourceDurationMs: source,
      startMs: startMs,
      inMs: inMs,
      outMs: outMs ?? source,
      volume: volume,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
    );

TitleOverlay title(String id, {int startMs = 0, int endMs = 2000, String text = 'Hi'}) =>
    TitleOverlay(id: id, text: text, startMs: startMs, endMs: endMs);

final DateTime t0 = DateTime.utc(2026, 1, 1);

Project project({
  String id = 'p1',
  String name = 'Test',
  List<Clip> clips = const [],
  List<AudioClip> audio = const [],
  List<TitleOverlay> titles = const [],
  CanvasAspect aspect = CanvasAspect.original,
  DateTime? updatedAt,
}) =>
    Project(
      id: id,
      name: name,
      createdAt: t0,
      updatedAt: updatedAt ?? t0,
      aspect: aspect,
      clips: clips,
      audio: audio,
      titles: titles,
    );

/// Project content without the modification time, for comparisons.
String content(Project p) => jsonEncode(p.toJson()..remove('updatedAt'));
