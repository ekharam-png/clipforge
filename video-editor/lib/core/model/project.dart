// Project data model. This file is the shared contract between the editor
// core, the export engine and the UI. All times are integer milliseconds.
// A project serialises to plain JSON so that it can later be synced between
// devices and edited by external tools (e.g. an MCP server).

const int kSchemaVersion = 2;

enum ClipType { video, photo }

/// How a clip is placed when its shape differs from the canvas.
enum FitMode { fit, fill, blur }

/// How the picture changes from the previous clip into a clip.
enum TransitionType { none, crossfade, fadeBlack, slideLeft, slideUp }

/// Look of a text overlay. [caption] is a subtitle: it is laid out by the
/// app (bottom centre, boxed) and is what SRT import creates.
enum TitleKind { title, caption }

/// A one-tap colour look ("filter") of a clip, applied after brightness,
/// contrast and saturation. See core/model/look_filter.dart for what each
/// does; the export and the preview use the same colour matrix.
enum LookFilter { none, warm, cool, blackWhite, vintage, vivid }

/// The font of a title or caption. Each is a bundled font file that covers
/// Latin, Cyrillic and Hebrew letters (see titleFontFileName in
/// title_layout.dart): [classic] DejaVu Sans, [modern] Rubik, [elegant]
/// Bona Nova, [handwritten] Amatic SC.
enum TitleFont { classic, modern, elegant, handwritten }

/// How the lines of a title line up with each other.
enum TitleAlign { center, left, right }

/// How a title appears or goes away (see titleAnimationAt in
/// title_layout.dart).
enum TitleAnimation { none, fade, slideUp, pop }

/// Which side of a two-channel (stereo) sound a clip uses. [left] and
/// [right] put that one channel on both sides: for recordings that keep a
/// microphone per channel (an interview mic on the left, a camera mic on
/// the right). See [Clip.audioChannel].
enum AudioChannel { both, left, right }

/// Output shape. [original] follows the size captured from the first clip
/// that was ever added (see [Project.originalWidth]).
enum CanvasAspect {
  original,
  portrait9x16,
  landscape16x9,
  square1x1,
  portrait4x5;

  /// Width / height, or null for [original].
  double? get ratio => switch (this) {
        CanvasAspect.original => null,
        CanvasAspect.portrait9x16 => 9 / 16,
        CanvasAspect.landscape16x9 => 16 / 9,
        CanvasAspect.square1x1 => 1,
        CanvasAspect.portrait4x5 => 4 / 5,
      };
}

/// Size of the exported video, by its SHORT side (the height of a
/// landscape video, the width of a portrait one). [matchFirstClip] keeps
/// the size of the clip the canvas was captured from (see
/// [Project.originalWidth]); the others scale the canvas to that short
/// side, up or down, keeping its shape.
enum VideoSize {
  matchFirstClip,
  p720,
  p1080,
  p2160;

  /// The short side in pixels, or null for [matchFirstClip].
  int? get shortSide => switch (this) {
        VideoSize.matchFirstClip => null,
        VideoSize.p720 => 720,
        VideoSize.p1080 => 1080,
        VideoSize.p2160 => 2160,
      };
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

/// Part of a picture to keep, as fractions (0..1) of the picture after its
/// rotation and flips ([Framing]): left edge [x], top edge [y], [width] and
/// [height]. [full] keeps everything.
class CropRect {
  const CropRect(this.x, this.y, this.width, this.height);

  static const CropRect full = CropRect(0, 0, 1, 1);

  /// Smallest width / height a crop may have (5 % of the picture).
  static const double minSize = 0.05;

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool get isFull =>
      x.abs() < 1e-6 &&
      y.abs() < 1e-6 &&
      (width - 1).abs() < 1e-6 &&
      (height - 1).abs() < 1e-6;

  /// Kept inside the picture and at least [minSize] in each direction;
  /// unusable numbers fall back to [full].
  CropRect clamped() {
    if ([x, y, width, height].any((v) => v.isNaN || v.isInfinite)) return full;
    double c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
    final w = c(width, minSize, 1);
    final h = c(height, minSize, 1);
    return CropRect(c(x, 0, 1 - w), c(y, 0, 1 - h), w, h);
  }

  /// The same part of the picture once the picture is turned a quarter
  /// turn clockwise.
  CropRect turnedClockwise() => CropRect(1 - bottom, x, height, width);

  /// The same part of the picture once it is mirrored left to right
  /// ([horizontal]) or top to bottom.
  CropRect flipped({required bool horizontal}) => horizontal
      ? CropRect(1 - right, y, width, height)
      : CropRect(x, 1 - bottom, width, height);

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};

  static CropRect fromJson(Object? j) {
    if (j is! Map) return full;
    double v(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    return CropRect(v('x', 0), v('y', 0), v('width', 1), v('height', 1))
        .clamped();
  }

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CropRect($x, $y, $width x $height)';
}

/// How a picture is turned, mirrored, cropped and positioned ("Crop and
/// position"), for a main-track clip and an overlay alike.
///
/// Order, in the export (lib/media/ffmpeg_command.dart) and the preview
/// (lib/core/model/picture_layout.dart) alike: the picture as the file
/// shows it (its own rotation metadata applied) is turned [rotation]
/// degrees clockwise, then mirrored ([flipH], [flipV]), then cut to
/// [crop]. What is left is fitted / filled into the frame (or the overlay
/// box) as before; [panX] / [panY] then choose which part stays in shot
/// where the picture is bigger than the frame (Fill, Zoom, an overlay
/// filling its box): -1 = the left / top edge, 0 = centred, 1 = the right
/// / bottom edge.
///
/// Defaults change nothing, so projects from before 1.6 load unchanged.
class Framing {
  const Framing({
    this.crop = CropRect.full,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.panX = 0,
    this.panY = 0,
  });

  static const Framing none = Framing();

  final CropRect crop;

  /// Clockwise, in degrees: 0, 90, 180 or 270.
  final int rotation;
  final bool flipH;
  final bool flipV;
  final double panX;
  final double panY;

  /// True when the picture is turned on its side (width and height swap).
  bool get sideways => rotation % 180 != 0;

  bool get isDefault =>
      crop.isFull &&
      rotation % 360 == 0 &&
      !flipH &&
      !flipV &&
      panX.abs() < 1e-6 &&
      panY.abs() < 1e-6;

  /// Only the position differs from [none].
  bool get onlyPan =>
      crop.isFull && rotation % 360 == 0 && !flipH && !flipV;

  /// Rotation as 0, 90, 180 or 270.
  static int normalizeRotation(int degrees) {
    final quarter = ((degrees / 90).round()) % 4;
    return (quarter < 0 ? quarter + 4 : quarter) * 90;
  }

  /// Values kept to their ranges.
  Framing normalized() {
    double pan(double v) => v.isNaN ? 0 : (v < -1 ? -1 : (v > 1 ? 1 : v));
    return Framing(
      crop: crop.clamped(),
      rotation: normalizeRotation(rotation),
      flipH: flipH,
      flipV: flipV,
      panX: pan(panX),
      panY: pan(panY),
    );
  }

  /// Turned by [quarterTurns] quarter turns clockwise (negative: the other
  /// way). The crop and the position turn with the picture, so the same
  /// part of it stays in shot.
  Framing turned(int quarterTurns) {
    var f = this;
    final n = ((quarterTurns % 4) + 4) % 4;
    for (var i = 0; i < n; i++) {
      // A mirrored picture turns the other way under its mirror: the crop
      // and the position are kept in the picture as shown.
      f = Framing(
        crop: f.crop.turnedClockwise(),
        rotation: normalizeRotation(f.rotation + (f.flipH != f.flipV ? -90 : 90)),
        flipH: f.flipH,
        flipV: f.flipV,
        panX: -f.panY,
        panY: f.panX,
      );
    }
    return f;
  }

  /// Mirrored left to right ([horizontal]) or top to bottom; the crop and
  /// the position are mirrored with the picture.
  Framing flipped({required bool horizontal}) => Framing(
        crop: crop.flipped(horizontal: horizontal),
        rotation: rotation,
        flipH: horizontal ? !flipH : flipH,
        flipV: horizontal ? flipV : !flipV,
        panX: horizontal ? -panX : panX,
        panY: horizontal ? panY : -panY,
      );

  Framing copyWith({
    CropRect? crop,
    int? rotation,
    bool? flipH,
    bool? flipV,
    double? panX,
    double? panY,
  }) =>
      Framing(
        crop: crop ?? this.crop,
        rotation: rotation ?? this.rotation,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        panX: panX ?? this.panX,
        panY: panY ?? this.panY,
      );

  /// The JSON fields (added to the clip's own map).
  Map<String, dynamic> toJson() => {
        'crop': crop.toJson(),
        'rotation': rotation,
        'flipH': flipH,
        'flipV': flipV,
        'panX': panX,
        'panY': panY,
      };

  factory Framing.fromJson(Map<String, dynamic> j) => Framing(
        crop: CropRect.fromJson(j['crop']),
        rotation: normalizeRotation((j['rotation'] as num?)?.toInt() ?? 0),
        flipH: j['flipH'] as bool? ?? false,
        flipV: j['flipV'] as bool? ?? false,
        panX: (j['panX'] as num?)?.toDouble() ?? 0,
        panY: (j['panY'] as num?)?.toDouble() ?? 0,
      ).normalized();

  @override
  bool operator ==(Object other) =>
      other is Framing &&
      other.crop == crop &&
      other.rotation == rotation &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.panX == panX &&
      other.panY == panY;

  @override
  int get hashCode => Object.hash(crop, rotation, flipH, flipV, panX, panY);

  @override
  String toString() => 'Framing($crop, $rotation°, flip ${flipH ? 'H' : ''}'
      '${flipV ? 'V' : ''}, pan $panX/$panY)';
}

/// One item on the main track. Clips play back to back in list order.
class Clip {
  const Clip({
    required this.id,
    required this.type,
    required this.path,
    required this.sourceDurationMs,
    required this.inMs,
    required this.outMs,
    required this.width,
    required this.height,
    this.hasAudio = true,
    this.volume = 1.0,
    this.muted = false,
    this.fit = FitMode.fit,
    this.speed = 1.0,
    this.denoise = false,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.zoom = 1.0,
    this.transition = TransitionType.none,
    this.transitionMs = 500,
    this.voiceFocus = 0,
    this.audioTrack = 0,
    this.audioChannel = AudioChannel.both,
    this.audioStreams = const [],
    this.framing = Framing.none,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.filter = LookFilter.none,
    this.warmth = 0,
    this.frameRate = 0,
  });

  final String id;
  final ClipType type;
  final String path;

  /// Full length of the source file. 0 for photos.
  final int sourceDurationMs;

  /// Trim range inside the source. For photos inMs is 0 and outMs is the
  /// time the photo stays on screen.
  final int inMs;
  final int outMs;

  /// Display size in pixels, after rotation metadata is applied.
  final int width;
  final int height;
  final bool hasAudio;
  final double volume;
  final bool muted;
  final FitMode fit;

  /// Playback speed of a video clip, 0.25..4 (1 = normal). Audio keeps its
  /// pitch. Ignored for photos.
  final double speed;

  /// Clean up this clip's sound on export: remove steady background noise
  /// and rumble, and even out the loudness of speech.
  final bool denoise;

  /// Colour adjustments, each -1..1 with 0 meaning unchanged.
  final double brightness;
  final double contrast;
  final double saturation;

  /// Centre zoom, 1..4 (1 = whole picture). Applied after [fit].
  final double zoom;

  /// Transition from the PREVIOUS clip into this one. Ignored on the first
  /// clip. During a transition the two clips overlap on the timeline, so it
  /// shortens the project; see [Project.transitionOverlapMs].
  final TransitionType transition;
  final int transitionMs;

  // ---- the clip's own sound ----------------------------------------------
  //
  // The sound of a clip goes through these stages, in this order, on export
  // (lib/media/clip_audio.dart builds them; the preview plays what its
  // player can, see that file):
  //
  //   1. source: [audioTrack] of the file, then [audioChannel];
  //   2. clean-up ([denoise]);
  //   3. [voiceFocus];
  //   4. speed, then [volume] / [muted].
  //
  // Room for AI separation (not built): a separated "voice" and
  // "background" file per clip, each with its own level, would REPLACE
  // stage 1 (the two files mixed at their levels instead of the file's own
  // sound), so that every later stage keeps working unchanged. Such fields
  // belong here, next to [audioTrack], with JSON defaults that mean "no
  // separation".

  /// Strength of "Voice focus", 0..1 (0 = off): makes speech clearer and
  /// tones down low rumble, bass, hiss and sound spread wide in stereo
  /// (typically music) around it. It cannot remove music.
  final double voiceFocus;

  /// Which audio stream of the file is the clip's sound: 0 is the first.
  /// Only used when the file has that many ([audioTrackInUse]).
  final int audioTrack;

  /// Which side of a stereo stream is used ([audioChannelInUse]).
  final AudioChannel audioChannel;

  /// Channel count of each audio stream of the file, in file order, as
  /// probed when the clip was added; empty when not known (clips added by
  /// older versions). Lets the app offer [audioTrack] / [audioChannel]
  /// only where they mean something.
  final List<int> audioStreams;

  /// Rotation, mirroring, crop and position of the picture ("Crop and
  /// position"); see [Framing].
  final Framing framing;

  /// The clip's picture fades in from black over its first [fadeInMs] and
  /// out to black over its last [fadeOutMs] (timeline ms), and its own
  /// sound fades in and out with it. 0 = no fade. Main track only (an
  /// overlay item has its own fades, [OverlayClip.fadeInMs]).
  final int fadeInMs;
  final int fadeOutMs;

  /// One-tap colour look ([LookFilter]) and warmth (-1 cooler .. 1 warmer,
  /// 0 = unchanged), applied after [brightness], [contrast] and
  /// [saturation].
  final LookFilter filter;
  final double warmth;

  /// Frames per second of the source video as probed when it was added
  /// (0 = not known: photos, clips added before 1.7). Used to step one
  /// frame with the arrow keys.
  final double frameRate;

  /// How loud / visible the clip is at [localMs] (0..[durationMs], on the
  /// timeline from the clip's start) because of its fades: 0..1.
  double fadeGainAt(int localMs) => fadeGain(localMs, durationMs, fadeInMs, fadeOutMs);

  /// Size of the picture after [framing]'s rotation and crop, in source
  /// pixels (not rounded). What is fitted into the frame.
  ({double width, double height}) get framedSize {
    final f = framing;
    final w = (f.sideways ? height : width).toDouble();
    final h = (f.sideways ? width : height).toDouble();
    return (width: w * f.crop.width, height: h * f.crop.height);
  }

  /// [audioTrack] when the file is known to have that stream, otherwise 0.
  int get audioTrackInUse =>
      audioTrack > 0 && audioTrack < audioStreams.length ? audioTrack : 0;

  /// Channels of the stream in use; 0 when not known.
  int get audioChannelsInUse {
    final t = audioTrackInUse;
    return t < audioStreams.length ? audioStreams[t] : 0;
  }

  /// [audioChannel] when the stream in use is known to be stereo (exactly
  /// two channels), otherwise [AudioChannel.both].
  AudioChannel get audioChannelInUse =>
      audioChannelsInUse == 2 ? audioChannel : AudioChannel.both;

  /// Length of the trimmed source range, before speed is applied.
  int get sourceSpanMs => outMs - inMs;

  /// Time this clip occupies on the timeline (speed applied), ignoring any
  /// transition overlap.
  int get durationMs => type == ClipType.photo || speed == 1.0
      ? sourceSpanMs
      : (sourceSpanMs / speed).round();

  /// Converts a time inside this clip on the timeline (0..durationMs) to a
  /// position in the source file.
  int sourceMsAt(int localTimelineMs) => type == ClipType.photo
      ? 0
      : inMs + (localTimelineMs * speed).round().clamp(0, sourceSpanMs);

  Clip copyWith({
    String? id,
    String? path,
    int? inMs,
    int? outMs,
    double? volume,
    bool? muted,
    FitMode? fit,
    double? speed,
    bool? denoise,
    double? brightness,
    double? contrast,
    double? saturation,
    double? zoom,
    TransitionType? transition,
    int? transitionMs,
    double? voiceFocus,
    int? audioTrack,
    AudioChannel? audioChannel,
    List<int>? audioStreams,
    Framing? framing,
    int? fadeInMs,
    int? fadeOutMs,
    LookFilter? filter,
    double? warmth,
    double? frameRate,
    bool? hasAudio,
  }) =>
      Clip(
        id: id ?? this.id,
        type: type,
        path: path ?? this.path,
        sourceDurationMs: sourceDurationMs,
        inMs: inMs ?? this.inMs,
        outMs: outMs ?? this.outMs,
        width: width,
        height: height,
        hasAudio: hasAudio ?? this.hasAudio,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        fit: fit ?? this.fit,
        speed: speed ?? this.speed,
        denoise: denoise ?? this.denoise,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        zoom: zoom ?? this.zoom,
        transition: transition ?? this.transition,
        transitionMs: transitionMs ?? this.transitionMs,
        voiceFocus: voiceFocus ?? this.voiceFocus,
        audioTrack: audioTrack ?? this.audioTrack,
        audioChannel: audioChannel ?? this.audioChannel,
        audioStreams: audioStreams ?? this.audioStreams,
        framing: framing ?? this.framing,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        filter: filter ?? this.filter,
        warmth: warmth ?? this.warmth,
        frameRate: frameRate ?? this.frameRate,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'path': path,
        'sourceDurationMs': sourceDurationMs,
        'inMs': inMs,
        'outMs': outMs,
        'width': width,
        'height': height,
        'hasAudio': hasAudio,
        'volume': volume,
        'muted': muted,
        'fit': fit.name,
        'speed': speed,
        'denoise': denoise,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'zoom': zoom,
        'transition': transition.name,
        'transitionMs': transitionMs,
        'voiceFocus': voiceFocus,
        'audioTrack': audioTrack,
        'audioChannel': audioChannel.name,
        'audioStreams': audioStreams,
        ...framing.toJson(),
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'filter': filter.name,
        'warmth': warmth,
        'frameRate': frameRate,
      };

  factory Clip.fromJson(Map<String, dynamic> j) => Clip(
        id: j['id'] as String,
        type: _enum(ClipType.values, j['type'], ClipType.video),
        path: j['path'] as String,
        sourceDurationMs: (j['sourceDurationMs'] as num?)?.toInt() ?? 0,
        inMs: (j['inMs'] as num).toInt(),
        outMs: (j['outMs'] as num).toInt(),
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        hasAudio: j['hasAudio'] as bool? ?? true,
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
        muted: j['muted'] as bool? ?? false,
        fit: _enum(FitMode.values, j['fit'], FitMode.fit),
        speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
        denoise: j['denoise'] as bool? ?? false,
        brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 0,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 1.0,
        transition:
            _enum(TransitionType.values, j['transition'], TransitionType.none),
        transitionMs: (j['transitionMs'] as num?)?.toInt() ?? 500,
        voiceFocus: (j['voiceFocus'] as num?)?.toDouble() ?? 0,
        audioTrack: (j['audioTrack'] as num?)?.toInt() ?? 0,
        audioChannel:
            _enum(AudioChannel.values, j['audioChannel'], AudioChannel.both),
        audioStreams: [
          for (final n in (j['audioStreams'] as List? ?? const []))
            if (n is num) n.toInt(),
        ],
        framing: Framing.fromJson(j),
        fadeInMs: (j['fadeInMs'] as num?)?.toInt() ?? 0,
        fadeOutMs: (j['fadeOutMs'] as num?)?.toInt() ?? 0,
        filter: _enum(LookFilter.values, j['filter'], LookFilter.none),
        warmth: (j['warmth'] as num?)?.toDouble() ?? 0,
        frameRate: (j['frameRate'] as num?)?.toDouble() ?? 0,
      );
}

/// Gain (0..1) at [rel] ms into something [duration] ms long that fades in
/// over [fadeIn] and out over [fadeOut] ms; 0 outside it.
double fadeGain(int rel, int duration, int fadeIn, int fadeOut) {
  if (rel < 0 || rel > duration) return 0;
  var g = 1.0;
  if (fadeIn > 0 && rel < fadeIn) g = rel / fadeIn;
  if (fadeOut > 0 && rel > duration - fadeOut) {
    final o = (duration - rel) / fadeOut;
    if (o < g) g = o;
  }
  return g < 0 ? 0 : (g > 1 ? 1 : g);
}

/// Id of the sound track that music without a track belongs to (projects
/// from versions before sound tracks, and [AudioClip]s made without one).
const String kMusicTrackId = 'music';

/// Default names of new sound tracks, in the order they are offered.
const List<String> kSoundTrackNames = ['Voice', 'Music', 'Effects'];

/// A row of sound clips ([AudioClip.trackId]) with its own level. Sound
/// clips on one track never overlap (the editor keeps them apart); the
/// tracks are mixed. The video's own sound has the same settings in
/// [Project.videoSound] (id [SoundTrack.videoId]).
class SoundTrack {
  const SoundTrack({
    required this.id,
    required this.name,
    this.volume = 1.0,
    this.muted = false,
    this.solo = false,
    this.duck = false,
    this.speech = false,
  });

  /// Id of [Project.videoSound].
  static const String videoId = 'video';

  /// The video's own sound, untouched.
  static const SoundTrack video = SoundTrack(id: videoId, name: 'Video sound');

  final String id;
  final String name;

  /// Linear amplitude factor applied to the whole track, like
  /// [AudioClip.volume].
  final double volume;
  final bool muted;

  /// While any track (or the video sound) is solo, only solo tracks are
  /// heard - in the preview and in the export.
  final bool solo;

  /// "Lower this track under speech": the track is pushed down while the
  /// video's own sound or a [speech] track plays. Export only.
  final bool duck;

  /// The track holds speech (the "Voice" track): it lowers the tracks that
  /// [duck], like the video's own sound does.
  final bool speech;

  SoundTrack copyWith({
    String? name,
    double? volume,
    bool? muted,
    bool? solo,
    bool? duck,
    bool? speech,
  }) =>
      SoundTrack(
        id: id,
        name: name ?? this.name,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        solo: solo ?? this.solo,
        duck: duck ?? this.duck,
        speech: speech ?? this.speech,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'volume': volume,
        'muted': muted,
        'solo': solo,
        'duck': duck,
        'speech': speech,
      };

  factory SoundTrack.fromJson(Map<String, dynamic> j,
          {String fallbackId = kMusicTrackId}) =>
      SoundTrack(
        id: j['id'] as String? ?? fallbackId,
        name: j['name'] as String? ?? 'Sound',
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
        muted: j['muted'] as bool? ?? false,
        solo: j['solo'] as bool? ?? false,
        duck: j['duck'] as bool? ?? false,
        speech: j['speech'] as bool? ?? false,
      );

  SoundTrack _withId(String newId) => SoundTrack(
        id: newId,
        name: name,
        volume: volume,
        muted: muted,
        solo: solo,
        duck: duck,
        speech: speech,
      );

  @override
  String toString() => 'SoundTrack($id, $name)';
}

/// A sound item placed freely on a sound track: music, a voice-over, an
/// effect, or the sound of a video clip that was separated from it
/// ("Separate sound", [sourceClipId]).
///
/// It has the sound options of a clip ([denoise], [voiceFocus],
/// [audioTrack], [audioChannel]) with the same meaning; [soundClip] views
/// it as a [Clip] so that the clip sound chain, instant sound processing
/// and the preview filters apply to it unchanged.
class AudioClip {
  const AudioClip({
    required this.id,
    required this.path,
    required this.sourceDurationMs,
    required this.startMs,
    required this.inMs,
    required this.outMs,
    this.volume = 1.0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.trackId = kMusicTrackId,
    this.speed = 1.0,
    this.denoise = false,
    this.voiceFocus = 0,
    this.audioTrack = 0,
    this.audioChannel = AudioChannel.both,
    this.audioStreams = const [],
    this.sourceClipId,
    this.linked = false,
    this.syncOffsetMs,
    this.loopMs = 0,
    this.credit,
  });

  final String id;
  final String path;
  final int sourceDurationMs;

  /// "Loop" (1.8): when > 0 the trimmed range ([inMs]..[outMs]) plays over
  /// and over for this long on the timeline (its [durationMs]); each
  /// repeat starts [loopCrossfadeMs] before the previous one ends and the
  /// two cross-fade. 0 = plays once. See [loopPieces], which both the
  /// export and the preview use, so they match.
  final int loopMs;

  /// Where the music came from and how to credit it (free music search);
  /// null for the user's own files.
  final MusicCredit? credit;

  /// True when it repeats ([loopMs]).
  bool get looped => loopMs > 0;

  /// Length of one pass of the trimmed range on the timeline.
  int get passMs =>
      speed == 1.0 || speed <= 0 || speed.isNaN
          ? sourceSpanMs
          : (sourceSpanMs / speed).round();

  /// Cross-fade between two repeats of a looped sound: [kLoopCrossfadeMs],
  /// at most a quarter of one pass.
  int get loopCrossfadeMs {
    final q = passMs ~/ 4;
    return q < kLoopCrossfadeMs ? q : kLoopCrossfadeMs;
  }

  /// The sound as plain, non-looped pieces on its track: itself when not
  /// looped; else one piece per repeat (ids `<id>~loop<k>` after the
  /// first), overlapping by [loopCrossfadeMs] with a fade-out / fade-in
  /// there, the first with this sound's fade-in, the last cut where the
  /// loop ends and given this sound's fade-out.
  List<AudioClip> get loopPieces {
    if (!looped) return [this];
    final pass = passMs;
    if (pass <= 0) return [copyWith(loopMs: 0)];
    final xf = loopCrossfadeMs;
    final step = pass - xf;
    final end = endMs;
    final out = <AudioClip>[];
    for (var k = 0; step > 0; k++) {
      final start = startMs + k * step;
      if (start >= end || (k > 0 && end - start <= xf ~/ 2)) break;
      final last = start + pass >= end;
      final len = last ? end - start : pass;
      final srcLen = speed == 1.0 ? len : (len * speed).round();
      out.add(AudioClip(
        id: k == 0 ? id : '$id$kLoopPieceMark$k',
        path: path,
        sourceDurationMs: sourceDurationMs,
        startMs: start,
        inMs: inMs,
        outMs: (inMs + srcLen).clamp(inMs, outMs).toInt(),
        volume: volume,
        fadeInMs: k == 0 ? fadeInMs : xf,
        fadeOutMs: last ? (fadeOutMs < len ? fadeOutMs : len) : xf,
        trackId: trackId,
        speed: speed,
        denoise: denoise,
        voiceFocus: voiceFocus,
        audioTrack: audioTrack,
        audioChannel: audioChannel,
        audioStreams: audioStreams,
        sourceClipId: sourceClipId,
        linked: linked,
        syncOffsetMs: syncOffsetMs,
        credit: credit,
      ));
      if (last) break;
    }
    return out;
  }

  /// Position on the timeline.
  final int startMs;

  /// Trim range inside the source file.
  final int inMs;
  final int outMs;
  final double volume;
  final int fadeInMs;
  final int fadeOutMs;

  /// The [SoundTrack] it is on.
  final String trackId;

  /// Playback speed (pitch kept), as the video clip it was separated from
  /// had; 1 for music.
  final double speed;

  /// Same as [Clip.denoise], [Clip.voiceFocus], [Clip.audioTrack],
  /// [Clip.audioChannel] and [Clip.audioStreams].
  final bool denoise;
  final double voiceFocus;
  final int audioTrack;
  final AudioChannel audioChannel;
  final List<int> audioStreams;

  /// The video clip this sound belongs to: the clip it was separated from
  /// ("Separate sound"), or the clip a separately recorded voice was lined
  /// up with ([syncOffsetMs]); null for music.
  final String? sourceClipId;

  /// Set for a VOICE RECORDED SEPARATELY (1.10, "Voice for the video": a
  /// microphone or Zoom per-speaker file lined up with a video clip): where
  /// this file sits against the clip's file,
  ///
  ///     time in this file = time in the clip's file + syncOffsetMs
  ///
  /// (positive: this recording started earlier than the camera). While
  /// [linked], the sound follows its clip like a separated sound does, the
  /// part of THIS file being the clip's part shifted by the offset, cut
  /// where this file has no sound (before its start: it starts later on the
  /// timeline; after its end: it ends earlier, silence). Null for music and
  /// for a sound separated from the clip itself.
  final int? syncOffsetMs;

  /// While true the sound follows its video clip ([sourceClipId]) through
  /// every edit of the main track (same place, same part of the file, same
  /// speed). Moving or trimming the sound by hand ends that: from then on
  /// it stays where it is put, like music.
  final bool linked;

  /// Length of the trimmed source range, before speed.
  int get sourceSpanMs => outMs - inMs;

  /// Time it takes on the timeline (speed applied; the loop length when
  /// [looped]).
  int get durationMs => looped ? loopMs : passMs;
  int get endMs => startMs + durationMs;

  /// True for a sound separated from a video clip (the clip's own sound).
  bool get isSeparated => sourceClipId != null && syncOffsetMs == null;

  /// True for a voice recorded separately and lined up with a video clip
  /// ([syncOffsetMs]), linked or not.
  bool get isVoice => syncOffsetMs != null;

  /// True when it belongs to a video clip: [isSeparated] or [isVoice].
  bool get belongsToClip => sourceClipId != null || syncOffsetMs != null;

  /// This sound seen as a video clip with only its sound settings (id,
  /// file, trim, speed, volume, clean-up, voice focus, track and side), for
  /// the code that processes a clip's own sound (media/clip_audio.dart,
  /// media/processed_sound.dart, the preview's filters).
  Clip get soundClip => Clip(
        id: id,
        type: ClipType.video,
        path: path,
        sourceDurationMs: sourceDurationMs,
        inMs: inMs,
        outMs: outMs,
        width: 0,
        height: 0,
        volume: volume,
        speed: speed,
        denoise: denoise,
        voiceFocus: voiceFocus,
        audioTrack: audioTrack,
        audioChannel: audioChannel,
        audioStreams: audioStreams,
      );

  AudioClip copyWith({
    String? id,
    String? path,
    int? startMs,
    int? inMs,
    int? outMs,
    double? volume,
    int? fadeInMs,
    int? fadeOutMs,
    String? trackId,
    double? speed,
    bool? denoise,
    double? voiceFocus,
    int? audioTrack,
    AudioChannel? audioChannel,
    List<int>? audioStreams,
    String? sourceClipId,
    bool clearSourceClip = false,
    bool? linked,
    int? syncOffsetMs,
    int? loopMs,
    MusicCredit? credit,
    bool clearCredit = false,
  }) =>
      AudioClip(
        id: id ?? this.id,
        path: path ?? this.path,
        sourceDurationMs: sourceDurationMs,
        startMs: startMs ?? this.startMs,
        inMs: inMs ?? this.inMs,
        outMs: outMs ?? this.outMs,
        volume: volume ?? this.volume,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        trackId: trackId ?? this.trackId,
        speed: speed ?? this.speed,
        denoise: denoise ?? this.denoise,
        voiceFocus: voiceFocus ?? this.voiceFocus,
        audioTrack: audioTrack ?? this.audioTrack,
        audioChannel: audioChannel ?? this.audioChannel,
        audioStreams: audioStreams ?? this.audioStreams,
        sourceClipId:
            clearSourceClip ? null : sourceClipId ?? this.sourceClipId,
        linked: clearSourceClip ? false : linked ?? this.linked,
        syncOffsetMs: clearSourceClip ? null : syncOffsetMs ?? this.syncOffsetMs,
        loopMs: loopMs ?? this.loopMs,
        credit: clearCredit ? null : credit ?? this.credit,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'sourceDurationMs': sourceDurationMs,
        'startMs': startMs,
        'inMs': inMs,
        'outMs': outMs,
        'volume': volume,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'trackId': trackId,
        'speed': speed,
        'denoise': denoise,
        'voiceFocus': voiceFocus,
        'audioTrack': audioTrack,
        'audioChannel': audioChannel.name,
        'audioStreams': audioStreams,
        // A voice recorded separately keeps its clip under other names
        // than a separated sound does: versions before 1.10 would take a
        // 'sourceClipId' for a sound of the clip's own file and replace
        // this file by the clip's. They read it as plain music instead.
        if (sourceClipId != null && syncOffsetMs == null)
          'sourceClipId': sourceClipId,
        if (sourceClipId != null && syncOffsetMs == null) 'linked': linked,
        if (syncOffsetMs != null) 'syncOffsetMs': syncOffsetMs,
        if (syncOffsetMs != null && sourceClipId != null)
          'voiceClipId': sourceClipId,
        if (syncOffsetMs != null && sourceClipId != null) 'voiceLinked': linked,
        if (loopMs > 0) 'loopMs': loopMs,
        if (credit != null) 'credit': credit!.toJson(),
      };

  factory AudioClip.fromJson(Map<String, dynamic> j) => AudioClip(
        id: j['id'] as String,
        path: j['path'] as String,
        sourceDurationMs: (j['sourceDurationMs'] as num?)?.toInt() ?? 0,
        startMs: (j['startMs'] as num).toInt(),
        inMs: (j['inMs'] as num).toInt(),
        outMs: (j['outMs'] as num).toInt(),
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
        fadeInMs: (j['fadeInMs'] as num?)?.toInt() ?? 0,
        fadeOutMs: (j['fadeOutMs'] as num?)?.toInt() ?? 0,
        trackId: j['trackId'] as String? ?? kMusicTrackId,
        speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
        denoise: j['denoise'] as bool? ?? false,
        voiceFocus: (j['voiceFocus'] as num?)?.toDouble() ?? 0,
        audioTrack: (j['audioTrack'] as num?)?.toInt() ?? 0,
        audioChannel:
            _enum(AudioChannel.values, j['audioChannel'], AudioChannel.both),
        audioStreams: [
          for (final n in (j['audioStreams'] as List? ?? const []))
            if (n is num) n.toInt(),
        ],
        sourceClipId: j['syncOffsetMs'] is num
            ? j['voiceClipId'] as String?
            : j['sourceClipId'] as String?,
        linked: j['syncOffsetMs'] is num
            ? j['voiceClipId'] is String && (j['voiceLinked'] as bool? ?? false)
            : j['sourceClipId'] is String && (j['linked'] as bool? ?? false),
        syncOffsetMs: (j['syncOffsetMs'] as num?)?.toInt(),
        loopMs: (j['loopMs'] as num?)?.toInt() ?? 0,
        credit: j['credit'] is Map
            ? MusicCredit.fromJson((j['credit'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// Cross-fade between the repeats of a looped sound ([AudioClip.loopMs]).
const int kLoopCrossfadeMs = 300;

/// Marks the id of a repeat made by [AudioClip.loopPieces]:
/// `<sound id>~loop<k>`.
const String kLoopPieceMark = '~loop';

/// The sound id a repeat made by [AudioClip.loopPieces] belongs to.
String loopBaseId(String id) {
  final i = id.indexOf(kLoopPieceMark);
  return i < 0 ? id : id.substring(0, i);
}

/// Where a piece of music came from and how it must be credited (free
/// music search, 1.8). Kept with the sound in the project.
class MusicCredit {
  const MusicCredit({
    required this.title,
    required this.creator,
    required this.licence,
    this.licenceVersion = '',
    this.licenceUrl = '',
    this.sourceUrl = '',
    this.provider = '',
    this.attribution = '',
  });

  final String title;
  final String creator;

  /// Openverse licence code: `cc0`, `pdm`, `by`, `by-sa`, `by-nc`, ...
  final String licence;
  final String licenceVersion;
  final String licenceUrl;

  /// The page the music is on (to credit and to check the licence).
  final String sourceUrl;

  /// Where Openverse found it (e.g. `jamendo`, `freesound`, `wikimedia_audio`).
  final String provider;

  /// The full attribution text the source gives, when it gives one.
  final String attribution;

  /// "CC BY 4.0", "CC0 1.0", "Public domain".
  String get licenceName => musicLicenceName(licence, licenceVersion);

  /// True when the licence asks for the creator to be credited (not CC0 /
  /// public domain).
  bool get needsCredit => licence != 'cc0' && licence != 'pdm';

  /// Short line for the end of a video: `Music: "Title" by Name (CC BY 4.0)`.
  String get shortLine {
    final by = creator.trim().isEmpty ? '' : ' by ${creator.trim()}';
    return 'Music: "${title.trim().isEmpty ? 'Untitled' : title.trim()}"$by '
        '($licenceName)';
  }

  /// Full credit for a post's description: title, creator, source and
  /// licence with their links (the "TASL" form Creative Commons asks for).
  String get fullLine {
    final b = StringBuffer(shortLine);
    if (sourceUrl.isNotEmpty) b.write(' $sourceUrl');
    if (licenceUrl.isNotEmpty) b.write(' — licence: $licenceUrl');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'creator': creator,
        'licence': licence,
        if (licenceVersion.isNotEmpty) 'licenceVersion': licenceVersion,
        if (licenceUrl.isNotEmpty) 'licenceUrl': licenceUrl,
        if (sourceUrl.isNotEmpty) 'sourceUrl': sourceUrl,
        if (provider.isNotEmpty) 'provider': provider,
        if (attribution.isNotEmpty) 'attribution': attribution,
      };

  factory MusicCredit.fromJson(Map<String, dynamic> j) => MusicCredit(
        title: j['title'] as String? ?? '',
        creator: j['creator'] as String? ?? '',
        licence: j['licence'] as String? ?? '',
        licenceVersion: j['licenceVersion'] as String? ?? '',
        licenceUrl: j['licenceUrl'] as String? ?? '',
        sourceUrl: j['sourceUrl'] as String? ?? '',
        provider: j['provider'] as String? ?? '',
        attribution: j['attribution'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is MusicCredit &&
      other.title == title &&
      other.creator == creator &&
      other.licence == licence &&
      other.licenceVersion == licenceVersion &&
      other.sourceUrl == sourceUrl;

  @override
  int get hashCode =>
      Object.hash(title, creator, licence, licenceVersion, sourceUrl);
}

/// Readable name of an Openverse licence code.
String musicLicenceName(String code, [String version = '']) {
  final v = version.isEmpty ? '' : ' $version';
  return switch (code) {
    'cc0' => 'CC0$v',
    'pdm' => 'Public domain',
    'by' => 'CC BY$v',
    'by-sa' => 'CC BY-SA$v',
    'by-nc' => 'CC BY-NC$v',
    'by-nc-sa' => 'CC BY-NC-SA$v',
    'by-nd' => 'CC BY-ND$v',
    'by-nc-nd' => 'CC BY-NC-ND$v',
    'sampling+' => 'CC Sampling+$v',
    'nc-sampling+' => 'CC NC-Sampling+$v',
    _ => code.toUpperCase(),
  };
}

/// A piece of text shown over the picture for a time range.
class TitleOverlay {
  const TitleOverlay({
    required this.id,
    required this.text,
    required this.startMs,
    required this.endMs,
    this.x = 0.5,
    this.y = 0.5,
    this.fontSize = 0.06,
    this.colorArgb = 0xFFFFFFFF,
    this.bold = true,
    this.background = false,
    this.kind = TitleKind.title,
    this.font = TitleFont.classic,
    this.outline = false,
    this.outlineColorArgb = 0xFF000000,
    this.shadow = true,
    this.align = TitleAlign.center,
    this.animIn = TitleAnimation.none,
    this.animOut = TitleAnimation.none,
  });

  final String id;
  final String text;
  final int startMs;
  final int endMs;

  /// Centre of the text, as a fraction of canvas width / height (0..1).
  final double x;
  final double y;

  /// Text height as a fraction of the canvas SHORT side (the height of a
  /// landscape canvas, the width of a portrait one).
  final double fontSize;
  final int colorArgb;
  final bool bold;

  /// Draw a semi-transparent dark box behind the text.
  final bool background;
  final TitleKind kind;

  /// The font ([TitleFont]); the bold cut when [bold].
  final TitleFont font;

  /// A line of [outlineColorArgb] around every letter.
  final bool outline;
  final int outlineColorArgb;

  /// A soft drop shadow (only without [background]).
  final bool shadow;

  /// How the lines line up inside the block ([TitleAlign]).
  final TitleAlign align;

  /// How the title appears and goes away ([TitleAnimation]).
  final TitleAnimation animIn;
  final TitleAnimation animOut;

  TitleOverlay copyWith({
    String? id,
    String? text,
    int? startMs,
    int? endMs,
    double? x,
    double? y,
    double? fontSize,
    int? colorArgb,
    bool? bold,
    bool? background,
    TitleKind? kind,
    TitleFont? font,
    bool? outline,
    int? outlineColorArgb,
    bool? shadow,
    TitleAlign? align,
    TitleAnimation? animIn,
    TitleAnimation? animOut,
  }) =>
      TitleOverlay(
        id: id ?? this.id,
        text: text ?? this.text,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        x: x ?? this.x,
        y: y ?? this.y,
        fontSize: fontSize ?? this.fontSize,
        colorArgb: colorArgb ?? this.colorArgb,
        bold: bold ?? this.bold,
        background: background ?? this.background,
        kind: kind ?? this.kind,
        font: font ?? this.font,
        outline: outline ?? this.outline,
        outlineColorArgb: outlineColorArgb ?? this.outlineColorArgb,
        shadow: shadow ?? this.shadow,
        align: align ?? this.align,
        animIn: animIn ?? this.animIn,
        animOut: animOut ?? this.animOut,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'colorArgb': colorArgb,
        'bold': bold,
        'background': background,
        'kind': kind.name,
        'font': font.name,
        'outline': outline,
        'outlineColorArgb': outlineColorArgb,
        'shadow': shadow,
        'align': align.name,
        'animIn': animIn.name,
        'animOut': animOut.name,
      };

  factory TitleOverlay.fromJson(Map<String, dynamic> j) => TitleOverlay(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        startMs: (j['startMs'] as num).toInt(),
        endMs: (j['endMs'] as num).toInt(),
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 0.06,
        colorArgb: (j['colorArgb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        bold: j['bold'] as bool? ?? true,
        background: j['background'] as bool? ?? false,
        kind: _enum(TitleKind.values, j['kind'], TitleKind.title),
        font: _enum(TitleFont.values, j['font'], TitleFont.classic),
        outline: j['outline'] as bool? ?? false,
        outlineColorArgb:
            (j['outlineColorArgb'] as num?)?.toInt() ?? 0xFF000000,
        shadow: j['shadow'] as bool? ?? true,
        align: _enum(TitleAlign.values, j['align'], TitleAlign.center),
        animIn: _enum(TitleAnimation.values, j['animIn'], TitleAnimation.none),
        animOut:
            _enum(TitleAnimation.values, j['animOut'], TitleAnimation.none),
      );
}

/// How an overlay item sits on the picture of the main track.
enum OverlayLayout {
  /// A small picture in a corner ([OverlayClip.corner], [OverlayClip.size]).
  pip,

  /// The main video on one half, the overlay on the other, left and right.
  sideBySide,

  /// The same, one above the other.
  topBottom,

  /// The overlay covers the whole picture (a cut-away, another camera).
  full,

  /// Anywhere, at any size ([OverlayClip.x], [OverlayClip.y],
  /// [OverlayClip.size]): what dragging it on the preview makes.
  free,
}

/// Corner of a picture-in-picture.
enum OverlayCorner { topLeft, topRight, bottomLeft, bottomRight }

/// A video or photo on the overlay track (the second video row, above the
/// main track): placed at [startMs] on the timeline with its own trim,
/// speed, volume and fades, drawn over the main track's picture (titles
/// and captions still go on top of it) and heard along with it.
///
/// [clip] holds the media and its settings (file, trim, speed, volume,
/// mute, [Clip.framing]); its transition, fit, look and sound clean-up are
/// not used. Overlay items never overlap each other (the editor keeps them
/// apart). They stay at their timeline time when the main track is edited,
/// like music.
class OverlayClip {
  const OverlayClip({
    required this.clip,
    required this.startMs,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.layout = OverlayLayout.pip,
    this.corner = OverlayCorner.bottomRight,
    this.size = 0.33,
    this.x = 0.75,
    this.y = 0.75,
    this.overlayFirst = false,
    this.border = false,
  });

  /// Smallest and largest [size].
  static const double minSize = 0.1;
  static const double maxSize = 1.0;

  final Clip clip;

  /// Position on the timeline.
  final int startMs;

  /// Fade of picture and sound, in timeline ms.
  final int fadeInMs;
  final int fadeOutMs;
  final OverlayLayout layout;

  /// [OverlayLayout.pip] only.
  final OverlayCorner corner;

  /// [OverlayLayout.pip] and [OverlayLayout.free]: the picture is as big as
  /// fits into this fraction of the frame's width and height (0.33: a
  /// third of the frame each way at most).
  final double size;

  /// [OverlayLayout.free]: centre of the overlay, as a fraction of the
  /// frame's width / height.
  final double x;
  final double y;

  /// [OverlayLayout.sideBySide] / [OverlayLayout.topBottom]: the overlay
  /// takes the left / top half (false: the right / bottom half).
  final bool overlayFirst;

  /// A thin white frame around a picture-in-picture or free overlay.
  final bool border;

  String get id => clip.id;
  String get path => clip.path;
  int get durationMs => clip.durationMs;
  int get endMs => startMs + durationMs;

  /// The overlay's sound, as a sound clip at its place (for the mix).
  AudioClip get sound => AudioClip(
        id: clip.id,
        path: clip.path,
        sourceDurationMs: clip.sourceDurationMs,
        startMs: startMs,
        inMs: clip.inMs,
        outMs: clip.outMs,
        volume: clip.muted ? 0 : clip.volume,
        fadeInMs: fadeInMs,
        fadeOutMs: fadeOutMs,
        trackId: kOverlayTrackId,
        speed: clip.type == ClipType.photo ? 1 : clip.speed,
        audioTrack: clip.audioTrack,
        audioChannel: clip.audioChannel,
        audioStreams: clip.audioStreams,
      );

  /// True when its sound is heard at all.
  bool get audible =>
      clip.type == ClipType.video &&
      clip.hasAudio &&
      !clip.muted &&
      clip.volume > 0;

  /// Opacity of the picture at timeline time [timeMs] (fades included);
  /// 0 outside the item.
  double opacityAt(int timeMs) {
    final rel = timeMs - startMs;
    final d = durationMs;
    if (rel < 0 || rel >= d) return 0;
    var a = 1.0;
    if (fadeInMs > 0 && rel < fadeInMs) a = rel / fadeInMs;
    if (fadeOutMs > 0 && rel > d - fadeOutMs) {
      final o = (d - rel) / fadeOutMs;
      if (o < a) a = o;
    }
    return a < 0 ? 0 : (a > 1 ? 1 : a);
  }

  OverlayClip copyWith({
    Clip? clip,
    int? startMs,
    int? fadeInMs,
    int? fadeOutMs,
    OverlayLayout? layout,
    OverlayCorner? corner,
    double? size,
    double? x,
    double? y,
    bool? overlayFirst,
    bool? border,
  }) =>
      OverlayClip(
        clip: clip ?? this.clip,
        startMs: startMs ?? this.startMs,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
        layout: layout ?? this.layout,
        corner: corner ?? this.corner,
        size: size ?? this.size,
        x: x ?? this.x,
        y: y ?? this.y,
        overlayFirst: overlayFirst ?? this.overlayFirst,
        border: border ?? this.border,
      );

  /// The clip's own fields plus the overlay's.
  Map<String, dynamic> toJson() => {
        ...clip.toJson(),
        'startMs': startMs,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'layout': layout.name,
        'corner': corner.name,
        'size': size,
        'x': x,
        'y': y,
        'overlayFirst': overlayFirst,
        'border': border,
      };

  factory OverlayClip.fromJson(Map<String, dynamic> j) => OverlayClip(
        // The fade keys are the overlay's own (picture and sound); the
        // clip's main-track fades do not apply to an overlay item.
        clip: Clip.fromJson(j).copyWith(fadeInMs: 0, fadeOutMs: 0),
        startMs: (j['startMs'] as num?)?.toInt() ?? 0,
        fadeInMs: (j['fadeInMs'] as num?)?.toInt() ?? 0,
        fadeOutMs: (j['fadeOutMs'] as num?)?.toInt() ?? 0,
        layout: _enum(OverlayLayout.values, j['layout'], OverlayLayout.pip),
        corner:
            _enum(OverlayCorner.values, j['corner'], OverlayCorner.bottomRight),
        size: (j['size'] as num?)?.toDouble() ?? 0.33,
        x: (j['x'] as num?)?.toDouble() ?? 0.75,
        y: (j['y'] as num?)?.toDouble() ?? 0.75,
        overlayFirst: j['overlayFirst'] as bool? ?? false,
        border: j['border'] as bool? ?? false,
      );

  @override
  String toString() => 'OverlayClip(${clip.id}, $startMs+$durationMs, ${layout.name})';
}

/// [AudioClip.trackId] of the sound of overlay items ([OverlayClip.sound]):
/// not a sound track of its own; it plays at the level of the video's own
/// sound ([Project.videoSound]).
const String kOverlayTrackId = 'overlay';

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.aspect = CanvasAspect.original,
    this.clips = const [],
    this.audio = const [],
    this.titles = const [],
    this.duckMusic = false,
    this.originalWidth,
    this.originalHeight,
    this.tracks = const [],
    this.videoSound = SoundTrack.video,
    this.videoSize = VideoSize.matchFirstClip,
    this.overlays = const [],
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
  });

  /// Longest allowed short side of the output canvas.
  static const int maxCanvasShortSide = 2160;

  /// Longest short side when the canvas size comes from a photo (photos
  /// are often 12 megapixels or more, far beyond any video).
  static const int maxPhotoCanvasShortSide = 1080;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CanvasAspect aspect;
  final List<Clip> clips;
  final List<AudioClip> audio;
  final List<TitleOverlay> titles;

  /// "Lower music under speech" for music tracks that do not say it
  /// themselves: the setting of projects from before sound tracks (their
  /// music track takes it over, see [fromJson]) and the default of a new
  /// "Music" track. The export uses [SoundTrack.duck] of each track.
  final bool duckMusic;

  /// The sound tracks, in the order they are shown (top to bottom). See
  /// [soundTracks] for the list everything else should use.
  final List<SoundTrack> tracks;

  /// Volume, mute and solo of the video clips' own sound as a whole (on top
  /// of each clip's own volume and mute). [SoundTrack.duck] and
  /// [SoundTrack.speech] mean nothing here: the video's sound always counts
  /// as speech for ducking.
  final SoundTrack videoSound;

  /// Size of the output video; see [VideoSize] and [canvasSize].
  final VideoSize videoSize;

  /// The overlay track (the second video row): items in timeline order,
  /// never overlapping. Empty in projects from before 1.6.
  final List<OverlayClip> overlays;

  /// The whole video fades in from black over its first [fadeInMs] and out
  /// to black over its last [fadeOutMs]; all sound fades with it. Titles
  /// and overlays fade too (it is applied to the finished picture). 0 = no
  /// fade.
  final int fadeInMs;
  final int fadeOutMs;

  /// Longest fade of the whole video.
  static const int maxFadeMs = 10000;

  /// Picture and sound level (0..1) at [timeMs] because of [fadeInMs] /
  /// [fadeOutMs], as the export applies them (each fade at most half the
  /// video).
  double fadeGainAt(int timeMs) {
    if (fadeInMs <= 0 && fadeOutMs <= 0) return 1;
    final d = durationMs;
    if (d <= 0) return 1;
    final f = projectFades;
    return fadeGain(timeMs.clamp(0, d), d, f.inMs, f.outMs);
  }

  /// [fadeInMs] and [fadeOutMs] as the export uses them: each at most half
  /// the video.
  ({int inMs, int outMs}) get projectFades {
    final half = durationMs ~/ 2;
    int lim(int v) => v < 0 ? 0 : (v > half ? half : v);
    return (inMs: lim(fadeInMs), outMs: lim(fadeOutMs));
  }

  /// The overlay item showing at [timeMs], or null.
  OverlayClip? overlayAt(int timeMs) {
    for (final o in overlays) {
      if (timeMs >= o.startMs && timeMs < o.endMs) return o;
    }
    return null;
  }

  /// [tracks], plus a track for every [AudioClip.trackId] that is not in
  /// [tracks] (a "Music" track for [kMusicTrackId], else "Sound"), which
  /// takes [duckMusic] as its "Lower under speech". So a project built
  /// without tracks (older code, tests) still has every sound on a track.
  List<SoundTrack> get soundTracks {
    final cached = _soundTracks[this];
    if (cached != null) return cached;
    var out = tracks;
    if (audio.isNotEmpty) {
      final known = {for (final t in tracks) t.id};
      List<SoundTrack>? extra;
      for (final a in audio) {
        if (known.add(a.trackId)) {
          (extra ??= []).add(SoundTrack(
            id: a.trackId,
            name: a.trackId == kMusicTrackId ? 'Music' : 'Sound',
            duck: duckMusic,
          ));
        }
      }
      if (extra != null) out = List.unmodifiable([...tracks, ...extra]);
    }
    _soundTracks[this] = out;
    return out;
  }

  static final Expando<List<SoundTrack>> _soundTracks = Expando('tracks');

  /// The track with [id] from [soundTracks] (or [videoSound]), or null.
  SoundTrack? trackById(String id) {
    if (id == SoundTrack.videoId) return videoSound;
    for (final t in soundTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// What the sound [a] is, for lists and for Claude: `voice` (a voice
  /// recorded separately, a separated sound, or anything on a speech
  /// track), `effect` (on a track named "Effects..."), else `music`.
  String soundRoleOf(AudioClip a) {
    if (a.belongsToClip) return 'voice';
    final t = trackById(a.trackId);
    if (t != null && t.speech) return 'voice';
    if (t != null && t.name.trim().toLowerCase().startsWith('effect')) {
      return 'effect';
    }
    return 'music';
  }

  /// True while the video sound or any sound track is solo.
  bool get anySolo => videoSound.solo || soundTracks.any((t) => t.solo);

  /// Level a track is heard at, mute and solo included: its volume, or 0.
  double trackGain(SoundTrack t) {
    if (t.muted) return 0;
    if (anySolo && !t.solo) return 0;
    final v = t.volume;
    return v.isNaN || v < 0 ? 0 : v;
  }

  /// [trackGain] of the track with [trackId] (1 for an unknown id).
  double trackGainOf(String trackId) {
    final t = trackById(trackId);
    return t == null ? 1 : trackGain(t);
  }

  /// The sound clips on track [trackId], in timeline order.
  List<AudioClip> clipsOnTrack(String trackId) =>
      [for (final a in audio) if (a.trackId == trackId) a]
        ..sort((a, b) => a.startMs.compareTo(b.startMs));

  /// Size the canvas is derived from: captured by the editor from the first
  /// clip that was ever added and then fixed (reordering or deleting clips
  /// does not change the shape of the video) until the project has no clips
  /// again. A size captured from a photo is stored already scaled down to a
  /// short side of [maxPhotoCanvasShortSide]. Null means "not captured"
  /// (projects saved by older versions): [canvasSize] then follows the
  /// first clip.
  final int? originalWidth;
  final int? originalHeight;

  /// The size to store in [originalWidth] / [originalHeight] when [clip]
  /// is the clip the canvas is captured from.
  static ({int width, int height}) originalSizeOf(Clip clip) => _capShortSide(
      clip.width,
      clip.height,
      clip.type == ClipType.photo ? maxPhotoCanvasShortSide : maxCanvasShortSide);

  static ({int width, int height}) _capShortSide(int w, int h, int cap) {
    final short = w < h ? w : h;
    if (short <= cap || short <= 0) return (width: w, height: h);
    final k = cap / short;
    return (width: (w * k).round(), height: (h * k).round());
  }

  /// Where the music clip [a] stops being heard: `min(a.endMs, durationMs)`,
  /// or `a.startMs` when it starts at or after the end of the video (it is
  /// then never heard). The fade-out is positioned to FINISH at this time,
  /// i.e. music that runs past the end of the video fades out at the video's
  /// end instead of being cut off.
  int audibleEndMs(AudioClip a) {
    final total = durationMs;
    if (a.startMs >= total) return a.startMs;
    return a.endMs < total ? a.endMs : total;
  }

  /// How long the clip at [index] overlaps the previous clip because of its
  /// transition. 0 for the first clip and for [TransitionType.none]. Never
  /// more than half of either clip, so two transitions cannot collide.
  int transitionOverlapMs(int index) {
    if (index <= 0 || index >= clips.length) return 0;
    final c = clips[index];
    if (c.transition == TransitionType.none || c.transitionMs <= 0) return 0;
    final prevHalf = clips[index - 1].durationMs ~/ 2;
    final thisHalf = c.durationMs ~/ 2;
    var o = c.transitionMs;
    if (o > prevHalf) o = prevHalf;
    if (o > thisHalf) o = thisHalf;
    return o;
  }

  /// Length of the main track (transition overlaps removed).
  int get durationMs => _timing.durationMs;

  /// Timeline position where the clip at [index] starts. With a transition
  /// this is where the transition begins (the previous clip is still
  /// showing until `clipStartMs(index) + transitionOverlapMs(index)`).
  /// Indexes past the end give [durationMs]; negative ones give 0.
  int clipStartMs(int index) {
    final t = _timing;
    if (index < 0) return 0;
    if (index >= t.starts.length) return t.durationMs;
    return t.starts[index];
  }

  /// Timeline position where the clip at [index] ends.
  int clipEndMs(int index) => clipStartMs(index) + clips[index].durationMs;

  /// Index of the clip playing at [timeMs], or -1 when there are no clips.
  /// During a transition this is the incoming (later) clip. Times past the
  /// end resolve to the last clip.
  int clipIndexAt(int timeMs) {
    if (clips.isEmpty) return -1;
    final t = _timing;
    final starts = t.starts;
    if (!t.ordered) {
      // Only for invalid clips (negative lengths): the plain scan.
      var found = 0;
      for (var i = 0; i < starts.length; i++) {
        if (starts[i] <= timeMs) found = i;
      }
      return found;
    }
    // The last clip that starts at or before timeMs (0 when none does).
    var lo = 0, hi = starts.length - 1;
    if (starts[0] > timeMs) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= timeMs) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Clip start times and the total length, worked out once per project
  /// (a project is immutable), so that the lookups above are O(1) /
  /// O(log n) instead of a walk over all clips. Long projects (hundreds of
  /// pieces after "Remove silences") ask for these on every frame.
  _ClipTiming get _timing {
    final cached = _timings[this];
    if (cached != null && cached.count == clips.length) return cached;
    final n = clips.length;
    final starts = List<int>.filled(n, 0);
    var t = 0;
    var ordered = true;
    for (var i = 0; i < n; i++) {
      final overlap = transitionOverlapMs(i);
      starts[i] = t - overlap;
      if (i > 0 && starts[i] < starts[i - 1]) ordered = false;
      t += clips[i].durationMs - overlap;
    }
    final timing = _ClipTiming(n, starts, t, ordered);
    _timings[this] = timing;
    return timing;
  }

  static final Expando<_ClipTiming> _timings = Expando('clip timing');

  /// Output size in pixels (both even).
  ///
  /// The basis is the captured [originalWidth] x [originalHeight]; when that
  /// is null, the first clip (a photo scaled to a short side of at most
  /// [maxPhotoCanvasShortSide]); 1920x1080 when there is neither.
  /// [CanvasAspect.original] uses the basis as it is; the other aspects keep
  /// its short side so that export does not lose resolution. In every case
  /// the short side is at most [maxCanvasShortSide].
  ({int width, int height}) get canvasSize {
    int even(num v) {
      final e = (v / 2).round() * 2;
      return e < 2 ? 2 : e;
    }

    ({int width, int height})? base;
    if (originalWidth != null &&
        originalHeight != null &&
        originalWidth! > 0 &&
        originalHeight! > 0) {
      base = (width: originalWidth!, height: originalHeight!);
    } else if (clips.isNotEmpty &&
        clips.first.width > 0 &&
        clips.first.height > 0) {
      base = originalSizeOf(clips.first);
    }
    if (base != null) {
      base = _capShortSide(base.width, base.height, maxCanvasShortSide);
    }
    // A chosen video size scales the basis to that short side.
    final target = videoSize.shortSide;
    if (target != null && base != null) {
      final short = base.width < base.height ? base.width : base.height;
      if (short > 0 && short != target) {
        final k = target / short;
        base = (width: (base.width * k).round(), height: (base.height * k).round());
      }
    }
    final r = aspect.ratio;
    if (r == null) {
      if (base == null) {
        final s = target ?? 1080;
        return (width: even(s * 16 / 9), height: even(s));
      }
      return (width: even(base.width), height: even(base.height));
    }
    final shortSide = base == null
        ? (target ?? 1080)
        : (base.width < base.height ? base.width : base.height);
    return r >= 1
        ? (width: even(shortSide * r), height: even(shortSide))
        : (width: even(shortSide), height: even(shortSide / r));
  }

  Project copyWith({
    String? name,
    DateTime? updatedAt,
    CanvasAspect? aspect,
    List<Clip>? clips,
    List<AudioClip>? audio,
    List<TitleOverlay>? titles,
    bool? duckMusic,
    int? originalWidth,
    int? originalHeight,
    bool clearOriginalSize = false,
    List<SoundTrack>? tracks,
    SoundTrack? videoSound,
    VideoSize? videoSize,
    List<OverlayClip>? overlays,
    int? fadeInMs,
    int? fadeOutMs,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        aspect: aspect ?? this.aspect,
        clips: clips ?? this.clips,
        audio: audio ?? this.audio,
        titles: titles ?? this.titles,
        duckMusic: duckMusic ?? this.duckMusic,
        originalWidth:
            clearOriginalSize ? null : originalWidth ?? this.originalWidth,
        originalHeight:
            clearOriginalSize ? null : originalHeight ?? this.originalHeight,
        tracks: tracks ?? this.tracks,
        videoSound: videoSound ?? this.videoSound,
        videoSize: videoSize ?? this.videoSize,
        overlays: overlays ?? this.overlays,
        fadeInMs: fadeInMs ?? this.fadeInMs,
        fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': kSchemaVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'aspect': aspect.name,
        'videoSize': videoSize.name,
        'duckMusic': duckMusic,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        if (originalWidth != null && originalHeight != null) ...{
          'originalWidth': originalWidth,
          'originalHeight': originalHeight,
        },
        'videoSound': videoSound.toJson(),
        'tracks': [for (final t in tracks) t.toJson()],
        'clips': [for (final c in clips) c.toJson()],
        'audio': [for (final a in audio) a.toJson()],
        'titles': [for (final t in titles) t.toJson()],
        'overlays': [for (final o in overlays) o.toJson()],
      };

  /// Reads a project. A project saved before sound tracks existed (no
  /// "tracks") gets them here: all its music goes on a "Music" track that
  /// takes the old "Lower music under speech"; music that overlapped other
  /// music (allowed then, not on one track now) goes on "Music 2",
  /// "Music 3", ... - first free track, in timeline order.
  factory Project.fromJson(Map<String, dynamic> j) {
    final duck = j['duckMusic'] as bool? ?? false;
    var audio = [
      for (final a in (j['audio'] as List? ?? const []))
        AudioClip.fromJson(Map<String, dynamic>.from(a as Map)),
    ];
    var tracks = <SoundTrack>[];
    final rawTracks = j['tracks'];
    if (rawTracks is List) {
      final seen = <String>{};
      for (final t in rawTracks) {
        if (t is! Map) continue;
        final track = SoundTrack.fromJson(Map<String, dynamic>.from(t));
        if (track.id == SoundTrack.videoId || !seen.add(track.id)) continue;
        tracks.add(track);
      }
    } else if (audio.isNotEmpty) {
      final migrated = _spreadOverMusicTracks(audio, duck);
      audio = migrated.audio;
      tracks = migrated.tracks;
    }
    final video = j['videoSound'];
    return Project(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Untitled',
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      aspect: _enum(CanvasAspect.values, j['aspect'], CanvasAspect.original),
      videoSize:
          _enum(VideoSize.values, j['videoSize'], VideoSize.matchFirstClip),
      duckMusic: duck,
      fadeInMs: (j['fadeInMs'] as num?)?.toInt() ?? 0,
      fadeOutMs: (j['fadeOutMs'] as num?)?.toInt() ?? 0,
      originalWidth: j['originalHeight'] is num
          ? (j['originalWidth'] as num?)?.toInt()
          : null,
      originalHeight: j['originalWidth'] is num
          ? (j['originalHeight'] as num?)?.toInt()
          : null,
      tracks: tracks,
      videoSound: video is Map
          ? SoundTrack.fromJson(Map<String, dynamic>.from(video))
              .copyWith(name: SoundTrack.video.name)
              ._withId(SoundTrack.videoId)
          : SoundTrack.video,
      clips: [
        for (final c in (j['clips'] as List? ?? const []))
          Clip.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      audio: audio,
      titles: [
        for (final t in (j['titles'] as List? ?? const []))
          TitleOverlay.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      overlays: [
        for (final o in (j['overlays'] as List? ?? const []))
          if (o is Map) OverlayClip.fromJson(Map<String, dynamic>.from(o)),
      ]..sort((a, b) => a.startMs.compareTo(b.startMs)),
    );
  }

  static ({List<AudioClip> audio, List<SoundTrack> tracks})
      _spreadOverMusicTracks(List<AudioClip> audio, bool duck) {
    final order = [for (var i = 0; i < audio.length; i++) i]
      ..sort((a, b) => audio[a].startMs.compareTo(audio[b].startMs));
    final ends = <int>[];
    final lane = List<int>.filled(audio.length, 0);
    for (final i in order) {
      final a = audio[i];
      var l = ends.indexWhere((e) => e <= a.startMs);
      if (l < 0) {
        ends.add(a.endMs);
        l = ends.length - 1;
      } else {
        ends[l] = a.endMs;
      }
      lane[i] = l;
    }
    String idOf(int l) => l == 0 ? kMusicTrackId : '$kMusicTrackId${l + 1}';
    return (
      audio: [
        for (var i = 0; i < audio.length; i++)
          audio[i].copyWith(trackId: idOf(lane[i])),
      ],
      tracks: [
        for (var l = 0; l < ends.length; l++)
          SoundTrack(
              id: idOf(l), name: l == 0 ? 'Music' : 'Music ${l + 1}', duck: duck),
      ],
    );
  }
}

/// See [Project._timing].
class _ClipTiming {
  _ClipTiming(this.count, this.starts, this.durationMs, this.ordered);

  /// Number of clips it was worked out for.
  final int count;
  final List<int> starts;
  final int durationMs;

  /// True when [starts] never goes down (always, for valid clips).
  final bool ordered;
}
