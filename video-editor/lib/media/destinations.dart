// "Where is it going?" (1.14): the export presets as DATA. One table,
// [kDestinations]; the Export window, "Export several…" and Claude's
// export_kit all read it. To add a destination, add a row.
//
// ClipForge never uploads and never logs in anywhere: a destination only
// decides the shape, size and kind of file, names the file, warns about a
// length or size the site may refuse, and knows the address of the site's
// own upload page (opened in the user's browser).
//
// THE LIMITS ARE CONSERVATIVE AND THE SITES CHANGE THEM. They are values
// that were safe on every site of a row when this was written (November
// 2026 knowledge, not checked live); every warning says "check the site".
// Change them here and nowhere else.
// Pure Dart.

import '../core/editor/edit_labels.dart' show aspectName;
import '../core/editor/project_editor.dart';
import '../core/model/project.dart';
import '../core/publish/shorts.dart' show kShortMaxSeconds;
import 'export_estimate.dart';
import 'media_api.dart';

/// A page of a site where the user uploads the file themselves.
class UploadLink {
  const UploadLink(this.label, this.url);

  /// "YouTube", "Instagram", "TikTok".
  final String label;

  /// Plain https address, opened in the user's own browser.
  final String url;
}

class ExportDestination {
  const ExportDestination({
    required this.id,
    required this.label,
    required this.detail,
    required this.fileTag,
    this.shapes = const [],
    this.videoSize,
    this.quality = ExportQuality.full,
    this.formats = const [ExportFormat.video],
    this.maxSeconds,
    this.maxMegabytes,
    this.limitNote = '',
    this.uploads = const [],
    this.shortForm = false,
    this.custom = false,
  });

  /// Never changes (settings, Claude's export_kit, tests).
  final String id;

  /// As the Export window shows it.
  final String label;

  /// One plain sentence under the choice.
  final String detail;

  /// What the file is called after the project's name: "YouTube" gives
  /// "(Project) - YouTube.mp4". A destination with several [shapes] adds
  /// the shape ("Instagram 4x5").
  final String fileTag;

  /// The shapes this destination takes, the usual one first. Empty: the
  /// project's own shape.
  final List<CanvasAspect> shapes;

  /// The video size it gets (null: the project's).
  final VideoSize? videoSize;
  final ExportQuality quality;

  /// The kinds of file it can be, the usual one first.
  final List<ExportFormat> formats;

  /// Longest video the sites of this row are sure to take; null: no limit
  /// worth warning about.
  final int? maxSeconds;

  /// Biggest file they are sure to take.
  final int? maxMegabytes;

  /// Said with the warning: whose limit it is and that it changes.
  final String limitNote;

  /// The sites' own upload pages.
  final List<UploadLink> uploads;

  /// Uses the short title and description of the publishing notes.
  final bool shortForm;

  /// "Custom": the Export window's own controls, no preset.
  final bool custom;

  bool get audioOnly => formats.first.audioOnly;
}

/// THE TABLE. Order = order in the Export window.
const List<ExportDestination> kDestinations = [
  ExportDestination(
    id: 'youtube',
    label: 'YouTube',
    detail: 'Wide 16:9, 1080p, full quality.',
    fileTag: 'YouTube',
    shapes: [CanvasAspect.landscape16x9],
    videoSize: VideoSize.p1080,
    uploads: [UploadLink('YouTube', 'https://www.youtube.com/upload')],
  ),
  ExportDestination(
    id: 'shorts',
    label: 'Shorts / Reels / TikTok',
    detail: 'Upright 9:16, 1080p. For YouTube Shorts, Instagram Reels '
        'and TikTok.',
    fileTag: 'Short',
    shapes: [CanvasAspect.portrait9x16],
    videoSize: VideoSize.p1080,
    maxSeconds: kShortMaxSeconds,
    limitNote: 'YouTube Shorts, Instagram Reels and TikTok each have their '
        'own longest length and change it from time to time; '
        '$kShortMaxSeconds seconds is safe on all three. Check the site.',
    uploads: [
      UploadLink('YouTube', 'https://www.youtube.com/upload'),
      UploadLink('Instagram', 'https://www.instagram.com/'),
      UploadLink('TikTok', 'https://www.tiktok.com/upload'),
    ],
    shortForm: true,
  ),
  ExportDestination(
    id: 'instagram',
    label: 'Instagram post',
    detail: 'Tall 4:5 (fills more of the screen) or square 1:1, 1080p.',
    fileTag: 'Instagram',
    shapes: [CanvasAspect.portrait4x5, CanvasAspect.square1x1],
    videoSize: VideoSize.p1080,
    maxSeconds: 60,
    limitNote: 'Instagram treats longer videos differently from posts and '
        'changes its limits; 60 seconds is safe for a post. Check the site.',
    uploads: [UploadLink('Instagram', 'https://www.instagram.com/')],
    shortForm: true,
  ),
  ExportDestination(
    id: 'whatsapp',
    label: 'WhatsApp / Telegram',
    detail: 'A small file (720p) that is quick to send.',
    fileTag: 'WhatsApp',
    quality: ExportQuality.small,
    maxMegabytes: 16,
    limitNote: 'WhatsApp has long made videos over about 16 MB smaller '
        'itself, or refused them (send it as a document to keep the '
        'quality); Telegram takes much bigger files. The limits change: '
        'check the app.',
  ),
  ExportDestination(
    id: 'podcast',
    label: 'Podcast audio',
    detail: 'The sound only, as an MP3 (plays everywhere) or M4A file.',
    fileTag: 'audio',
    formats: [ExportFormat.mp3, ExportFormat.m4a],
  ),
  ExportDestination(
    id: 'custom',
    label: 'Custom',
    detail: 'Choose the size, quality and kind of file yourself.',
    fileTag: '',
    custom: true,
  ),
];

/// The destination with [id]; null when there is none.
ExportDestination? destinationById(String id) {
  for (final d in kDestinations) {
    if (d.id == id) return d;
  }
  return null;
}

ExportDestination get kCustomDestination =>
    kDestinations.firstWhere((d) => d.custom);

/// One file of a publishing kit: a destination with the shape and the kind
/// of file chosen for it.
class KitChoice {
  const KitChoice(this.destination, {this.shape, this.format});
  final ExportDestination destination;

  /// One of [ExportDestination.shapes] (null: the first, or the project's
  /// own shape when the destination names none).
  final CanvasAspect? shape;

  /// One of [ExportDestination.formats] (null: the first).
  final ExportFormat? format;

  CanvasAspect? get shapeInUse =>
      shape ?? (destination.shapes.isEmpty ? null : destination.shapes.first);
  ExportFormat get formatInUse => format ?? destination.formats.first;

  /// "9x16", "4x5".
  static String shapeTag(CanvasAspect a) => aspectName(a).replaceAll(':', 'x');

  /// "YouTube", "Short 9x16", "Instagram 4x5", "WhatsApp", "audio".
  String get tag {
    final d = destination;
    final s = shapeInUse;
    if (s != null && (d.shapes.length > 1 || d.shortForm)) {
      return '${d.fileTag} ${shapeTag(s)}';
    }
    return d.fileTag;
  }

  /// As a row of "Export several…": "Instagram post (4:5)".
  String get label {
    final d = destination;
    if (d.shapes.length > 1) return '${d.label} (${aspectName(shapeInUse!)})';
    if (d.formats.length > 1 && format != null && format != d.formats.first) {
      return '${d.label} (${formatInUse.extension.toUpperCase()})';
    }
    return d.label;
  }

  /// Stable key ("instagram:1x1", "podcast:m4a", "youtube").
  String get key {
    final d = destination;
    if (d.shapes.length > 1) return '${d.id}:${shapeTag(shapeInUse!)}';
    if (format != null && format != d.formats.first) {
      return '${d.id}:${formatInUse.extension}';
    }
    return d.id;
  }

  @override
  bool operator ==(Object other) => other is KitChoice && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Every row "Export several…" offers: each destination once per shape
/// (Custom is not one of them).
List<KitChoice> kitChoices() => [
      for (final d in kDestinations)
        if (!d.custom)
          if (d.shapes.length > 1)
            for (final s in d.shapes) KitChoice(d, shape: s)
          else
            KitChoice(d),
    ];

/// The choice with [key] ("shorts", "instagram:1x1", "podcast:m4a"; a bare
/// destination id gives its usual shape and file kind). Null when unknown.
KitChoice? kitChoiceByKey(String key) {
  final parts = key.trim().toLowerCase().split(':');
  final d = destinationById(parts.first);
  if (d == null || d.custom) return null;
  if (parts.length < 2) return KitChoice(d);
  final extra = parts[1];
  for (final s in d.shapes) {
    if (KitChoice.shapeTag(s) == extra) return KitChoice(d, shape: s);
  }
  for (final f in d.formats) {
    if (f.extension == extra) return KitChoice(d, format: f);
  }
  return null;
}

/// Characters no file name may hold are replaced; never empty.
String kitSafeName(String name) {
  final cleaned =
      name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  final t = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
  return t.isEmpty ? 'Video' : t;
}

/// "(Project) - YouTube.mp4", "(Project) - Short 9x16.mp4",
/// "(Project) - WhatsApp.mp4", "(Project) - audio.mp3".
String kitFileName(String projectName, KitChoice choice) =>
    '${kitSafeName(projectName)} - ${choice.tag}.'
    '${choice.formatInUse.extension}';

/// "(Project) - text.txt": the publishing notes that go with the files.
String kitTextFileName(String projectName) =>
    '${kitSafeName(projectName)} - text.txt';

/// Whether the picture of [project] has another shape than [shape] (more
/// than 2 % apart, so 1920x1080 counts as 16:9).
bool shapeDiffers(Project project, CanvasAspect? shape) {
  final r = shape?.ratio;
  if (r == null) return false;
  final c = project.canvasSize;
  final now = c.width / c.height;
  return (now / r - 1).abs() > 0.02;
}

/// Gives [e]'s project the [shape] (and [videoSize]) of a destination, as
/// ONE undo step: clips whose own picture has another shape and that are
/// set to "Fit" get the blurred background, so a wide video in an upright
/// frame is not left with black bars. ("Crop and position" can then keep
/// the person in shot; nothing is cropped here.) Returns how many clips
/// got the blurred background.
int applyDestinationShape(ProjectEditor e, CanvasAspect shape,
    {VideoSize? videoSize}) {
  var blurred = 0;
  e.transaction(() {
    e.setAspect(shape);
    if (videoSize != null) e.setVideoSize(videoSize);
    final canvas = e.project.canvasSize;
    final want = canvas.width / canvas.height;
    for (final c in [...e.project.clips]) {
      if (c.fit != FitMode.fit) continue;
      final size = c.framedSize;
      if (size.width <= 0 || size.height <= 0) continue;
      if ((size.width / size.height / want - 1).abs() <= 0.02) continue;
      e.setClipFit(c.id, FitMode.blur);
      blurred++;
    }
  }, label: 'Shape ${aspectName(shape)} with blurred background');
  return blurred;
}

/// [project] as [choice] needs it: the same project when the destination
/// keeps its shape, else a copy in memory in the destination's shape (see
/// [applyDestinationShape]). With [keepShape] ("Export as it is") only the
/// video size is taken over.
Project destinationVariant(Project project, KitChoice choice,
    {bool keepShape = false}) {
  final d = choice.destination;
  if (choice.formatInUse.audioOnly || d.custom) return project;
  final shape = choice.shapeInUse;
  final e = ProjectEditor(project);
  if (shape != null && !keepShape && shapeDiffers(project, shape)) {
    applyDestinationShape(e, shape, videoSize: d.videoSize);
  } else if (d.videoSize != null && d.quality == ExportQuality.full) {
    e.setVideoSize(d.videoSize!);
  }
  return e.project;
}

/// The export settings of [choice].
ExportOptions destinationOptions(KitChoice choice,
        {int fps = 30,
        bool useHardwareEncoder = true,
        Map<String, String> processedSound = const {}}) =>
    ExportOptions(
      quality: choice.destination.quality,
      format: choice.formatInUse,
      fps: fps,
      useHardwareEncoder: useHardwareEncoder,
      processedSound: processedSound,
    );

String _length(int ms) {
  final s = (ms / 1000).round();
  return s < 60
      ? '$s seconds'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Plain warnings about [project] going to [choice]: longer than the
/// destination's limit, or (about) bigger than it takes. Never blocks.
List<String> destinationWarnings(Project project, KitChoice choice) {
  final d = choice.destination;
  final out = <String>[];
  final max = d.maxSeconds;
  if (max != null && project.durationMs > max * 1000 + 500) {
    out.add('This video is ${_length(project.durationMs)} long. ${d.limitNote}');
  }
  final mb = d.maxMegabytes;
  if (mb != null) {
    final bytes = estimateExportSize(
            destinationVariant(project, choice), destinationOptions(choice))
        .typicalBytes;
    if (bytes > mb * 1024 * 1024) {
      out.add('This will be about ${(bytes / (1024 * 1024)).round()} MB. '
          '${d.limitNote}');
    }
  }
  return out;
}
