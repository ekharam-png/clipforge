// The ClipForge tools offered over MCP. Every editing tool loads the
// project from disk, applies the change through ProjectEditor (so the
// app's clamping rules apply), saves it atomically and answers with a
// summary of the timeline. Pure Dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/build_info.dart';
import '../core/editor/edit_labels.dart' show describeEdit;
import '../core/editor/project_editor.dart';
import '../core/model/picture_layout.dart';
import '../core/model/project.dart';
import '../core/model/title_layout.dart';
import '../core/storage/project_lock.dart';
import '../core/storage/project_store.dart';
import '../core/subtitles/srt.dart';
import '../core/transcript/captions.dart';
import '../core/transcript/cut_plan.dart';
import '../core/transcript/fillers.dart';
import '../core/transcript/speech_edits.dart';
import '../core/transcript/transcript_store.dart';
import '../core/transcript/transcript_timeline.dart';
import '../core/editor/sound_tracks.dart' show VoiceProblem;
import '../media/clip_silences.dart';
import '../media/jump_check.dart';
import '../media/media_api.dart';
import '../media/sound_align.dart';
import '../media/transcribe/transcription_service.dart';
import '../media/video_encoder.dart' show kSmallMaxRateKbps;
import 'delegate.dart';
import 'environment.dart';
import 'export_jobs.dart';
import 'guide_content.dart';
import 'mcp_protocol.dart';
import 'report.dart';
import 'summary.dart';
import 'transcribe_jobs.dart';

part 'tools_selftest.dart';
part 'tools_speech.dart';

const String kServerName = 'clipforge';
const String kServerTitle = 'ClipForge video editor';
/// The version of ClipForge this server was built from (pubspec.yaml,
/// passed in by bin/build_mcp.dart): the same as the app's.
String get kServerVersion => BuildInfo.current.version;

/// Defaults taken from the app (lib/ui/editor/import_actions.dart).
const int kDefaultPhotoMs = 3000;
const int kDefaultTitleMs = 3000;
const int kDefaultCaptionMs = 2500;

/// Quiet kept at each side of a removed silence, as in the app
/// (kSilenceKeepMs in lib/ui/editor/clip_actions.dart).
const int kSilenceKeepMs = 150;

/// Titles listed with detail "full" after an edit.
const int kSummaryTitles = 12;

/// How long export_video waits for the job by default, and the longest
/// wait of any call (MCP clients give up on a call after about a minute).
const int kDefaultExportWait = 20;
const int kMaxStatusWait = 45;

/// Clips / titles per get_project answer by default, and at most.
const int kDefaultClipPage = 30;
const int kDefaultTitlePage = 30;
const int kMaxClipPage = 300;

const Set<String> _imageExtensions = {
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif', //
};

/// Photos are recognised by file extension, like in the app.
bool isImagePath(String path) =>
    _imageExtensions.contains(p.extension(path).toLowerCase());

const String kCloseProjectRule =
    'IMPORTANT: a project must be CLOSED in the ClipForge app while it is '
    'edited here (in the app, go back to the home screen). The app keeps its '
    'own copy of the project it has open and autosaves it after every change '
    'made there, which would overwrite these edits. ClipForge 1.9 and later '
    'mark an open project, and the editing tools then refuse with a message; '
    'reading and exporting still work. Reopen the project in the app '
    'afterwards to see the result.';

const String kServerInstructions =
    'Tools for editing ClipForge video projects: the same project files the '
    'ClipForge desktop app opens.\n'
    'FIRST, once per conversation, call get_guide (no arguments) and follow '
    'its "start" section: who the user is, the workflow, the safety rules. '
    'It has more sections (recipes, tools, troubleshooting) for when they '
    'are needed. self_test checks the whole installation with its own '
    'sample files in a temporary folder.\n'
    '$kCloseProjectRule\n'
    'Workflow: list_projects (or create_project) -> get_project -> edit '
    'tools -> export_video. Edit tools answer with a SHORT summary (clip '
    'count, length, output size and why, the ids that were added / removed '
    '/ changed, warnings); pass detail "full" for the whole timeline. '
    'get_project shows the timeline with the ids (clip_id, audio_id, '
    'title_id, overlay_id) the other tools need, page by page for long '
    'projects (clip_offset / clip_limit, from_ms / to_ms).\n'
    'Exports run as background jobs: export_video waits about 20 s and then '
    'answers with a job_id; poll get_export_status (wait_seconds 45) until '
    'it says finished. Never start the same export again while one runs.\n'
    'remove_silences, set_clip_properties "all", apply_to_all, '
    'copy_clip_settings and separate_sound "all" take dry_run to see the '
    'result first.\n'
    'All times are whole MILLISECONDS. "Timeline" times are positions in the '
    'finished video; "source" times are positions inside the original media '
    'file (they differ once a clip is trimmed, cut or sped up).\n'
    'File paths must be full paths on this computer. Media files are used '
    'where they are (not copied), so they must stay in place.\n'
    'A voice that was recorded on its own file while the video was filmed '
    '(separate microphone, Zoom audio file per speaker) is added with '
    'add_voice, not add_music: it is lined up with the video by sound and '
    'then follows its clip through every cut. Check its confidence.\n'
    'Titles and captions follow the picture they were placed on: when clips '
    'are trimmed, cut, moved or sped up they move along, and one whose '
    'footage is removed completely is removed too. Music does NOT move; '
    'check it with get_project after cutting.\n'
    'SPEECH: transcribe turns what is said into text with word times '
    '(a background job like exports: poll get_transcribe_status). Then '
    'get_transcript reads it (compact; page long talks), find_in_transcript '
    'finds a phrase, captions_from_transcript makes captions, '
    'remove_fillers cuts "um" / "uh" (dry_run is true by default) and '
    'make_short turns a part of the timeline into a new upright project. '
    'transcribe never downloads anything by itself: when a language pack '
    'is missing it says which and how big; ask the user, then pass '
    'download_pack true. You can read what is SAID; you still cannot see '
    'the picture.\n'
    'If a tool says FFmpeg is missing, pass the install instruction on to '
    'the user; call get_status to see what was found.';

/// The parts of [silences] (source times of the clip's file) that are cut
/// out of [clip]: limited to its trimmed range, with [kSilenceKeepMs] of
/// quiet left on each side that touches sound, and only when at least
/// 2 x [kSilenceKeepMs] (300 ms) remains to cut. Mirrors `silencesToCut`
/// in lib/ui/editor/clip_actions.dart.
List<({int startMs, int endMs})> silencesToCut(
    Clip clip, List<({int startMs, int endMs})> silences) {
  final result = <({int startMs, int endMs})>[];
  for (final r in silences) {
    var start = r.startMs < clip.inMs ? clip.inMs : r.startMs;
    var end = r.endMs > clip.outMs ? clip.outMs : r.endMs;
    if (start > clip.inMs) start += kSilenceKeepMs;
    if (end < clip.outMs) end -= kSilenceKeepMs;
    if (end - start >= 2 * kSilenceKeepMs) {
      result.add((startMs: start, endMs: end));
    }
  }
  return result;
}

/// Moves captions whose times refer to the media file [sourcePath] onto the
/// timeline of [project]: every part of a cue that is still used by a clip
/// of that file is placed where that clip plays it (trim, cuts and speed
/// applied). Parts that end up next to each other are joined; cues whose
/// source time was cut away are dropped. Returns the placed captions and
/// the number of cues dropped.
({List<TitleOverlay> titles, int dropped}) captionsFromSourceTimes(
  Project project,
  String sourcePath,
  List<TitleOverlay> cues, {
  required String Function() newId,
}) {
  final titles = <TitleOverlay>[];
  var dropped = 0;
  for (final cue in cues) {
    final spans = <({int start, int end})>[];
    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      if (c.type != ClipType.video || !p.equals(c.path, sourcePath)) continue;
      final a = cue.startMs < c.inMs ? c.inMs : cue.startMs;
      final b = cue.endMs > c.outMs ? c.outMs : cue.endMs;
      if (b <= a) continue;
      final base = project.clipStartMs(i);
      spans.add((
        start: base + ((a - c.inMs) / c.speed).round(),
        end: base + ((b - c.inMs) / c.speed).round(),
      ));
    }
    spans.sort((x, y) => x.start.compareTo(y.start));
    final merged = <({int start, int end})>[];
    for (final s in spans) {
      if (merged.isNotEmpty && s.start <= merged.last.end + 1) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: s.end > last.end ? s.end : last.end));
      } else {
        merged.add(s);
      }
    }
    final usable = [
      for (final s in merged)
        if (s.end - s.start >= ProjectEditor.minDurationMs) s,
    ];
    if (usable.isEmpty) {
      dropped++;
      continue;
    }
    for (var i = 0; i < usable.length; i++) {
      titles.add(TitleOverlay(
        id: i == 0 ? cue.id : newId(),
        text: cue.text,
        startMs: usable[i].start,
        endMs: usable[i].end,
        x: cue.x,
        y: cue.y,
        fontSize: cue.fontSize,
        colorArgb: cue.colorArgb,
        bold: cue.bold,
        background: cue.background,
        kind: cue.kind,
      ));
    }
  }
  return (titles: titles, dropped: dropped);
}

/// The opposite of [captionsFromSourceTimes]: the captions of [project]
/// with times in the media file [sourcePath] (what the moment on the
/// timeline shows of that file; trims, cuts and speed undone). A caption
/// over a cut becomes one cue across the removed part when that part is
/// at most [joinGapMs] long, else one cue per piece. Captions over other
/// files only are left out (counted in `skipped`).
({List<TitleOverlay> titles, int skipped}) captionsToSourceTimes(
    Project project, String sourcePath, List<TitleOverlay> captions,
    {int joinGapMs = 2000}) {
  final out = <TitleOverlay>[];
  var skipped = 0;
  for (final cue in captions) {
    final pieces = <({int start, int end})>[];
    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      if (c.type != ClipType.video || !p.equals(c.path, sourcePath)) continue;
      final cs = project.clipStartMs(i), ce = project.clipEndMs(i);
      final a = cue.startMs > cs ? cue.startMs : cs;
      final b = cue.endMs < ce ? cue.endMs : ce;
      if (b <= a) continue;
      pieces.add((
        start: c.inMs + ((a - cs) * c.speed).round(),
        end: c.inMs + ((b - cs) * c.speed).round(),
      ));
    }
    if (pieces.isEmpty) {
      skipped++;
      continue;
    }
    pieces.sort((x, y) => x.start.compareTo(y.start));
    final merged = <({int start, int end})>[];
    for (final s in pieces) {
      if (merged.isNotEmpty && s.start <= merged.last.end + joinGapMs) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: s.end > last.end ? s.end : last.end));
      } else {
        merged.add(s);
      }
    }
    for (final m in merged) {
      out.add(cue.copyWith(startMs: m.start, endMs: m.end));
    }
  }
  return (titles: out, skipped: skipped);
}

/// The warning for an edit that moved the picture ([before] -> [after])
/// while sound that is NOT linked to a clip sits on a speech track: such
/// sound stays at its timeline time (like music), so it is now out of sync
/// with the picture. Null when the cut did not change or nothing is
/// unlinked.
String? unlinkedSpeechWarning(Project before, Project after) {
  if (timelineKey(before) == timelineKey(after)) return null;
  final loose = [
    for (final a in after.audio)
      if (after.trackById(a.trackId)?.speech == true &&
          !(a.belongsToClip && a.linked))
        a,
  ];
  if (loose.isEmpty) return null;
  final tracks = {
    for (final a in loose) after.trackById(a.trackId)?.name ?? a.trackId,
  };
  return '${loose.length} sound item(s) on the speech track(s) '
      '${tracks.map((t) => '"$t"').join(', ')} are NOT linked to a clip '
      '(${loose.take(3).map((a) => '"${p.basename(a.path)}"').join(', ')}'
      '${loose.length > 3 ? ', …' : ''}), so they did not move with this cut '
      'and are now OUT OF SYNC with the picture. A voice recorded '
      'separately must be linked to follow cuts: undo, then add it with '
      'add_voice (a new file) or link the existing sound with align_audio '
      '(audio_id, clip_id); after that every cut and remove_silences takes '
      'picture and voice together.';
}

/// A key for the cut of [project]: which parts of which files play, in
/// which order, at which speed. Subtitles exported with timeline times only
/// fit a project with the same key.
String timelineKey(Project project) => textHash(jsonEncode([
      for (var i = 0; i < project.clips.length; i++)
        [
          project.clips[i].path,
          project.clips[i].inMs,
          project.clips[i].outMs,
          project.clips[i].speed,
          project.transitionOverlapMs(i),
        ],
    ]));

String _srtKey(String srt) =>
    textHash(srt.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim());

/// An edit this server saved: the project before and after it.
class _Step {
  _Step(this.before, this.after, this.label);
  final Project before;
  final Project after;
  final String label;
}

class _Loaded {
  _Loaded(this.project, this.file, this.raw);
  final Project project;
  final File file;
  String get dir => file.parent.path;

  /// Exact text of project.json when it was read.
  final String raw;
}

/// What an edit reports besides the timeline.
class _Done {
  _Done(this.message, [this.extra = const {}, this.removesTitles = false]);
  final String message;
  final Map<String, dynamic> extra;

  /// True for the tools whose job is to remove titles (no extra note).
  final bool removesTitles;
}

// Schema helpers -------------------------------------------------------------
Map<String, dynamic> _str(String description, {List<String>? values}) => {
      'type': 'string',
      'description': description,
      'enum': ?values,
    };

Map<String, dynamic> _int(String description, {int? min, int? max}) => {
      'type': 'integer',
      'description': description,
      'minimum': ?min,
      'maximum': ?max,
    };

Map<String, dynamic> _num(String description, {num? min, num? max}) => {
      'type': 'number',
      'description': description,
      'minimum': ?min,
      'maximum': ?max,
    };

Map<String, dynamic> _bool(String description) =>
    {'type': 'boolean', 'description': description};

final Map<String, dynamic> _projectId = _str(
    'The project to work on: its project_id from list_projects (the exact '
    'project name also works when only one project has that name).');

const String _editNote =
    ' The project must be closed in the ClipForge app (see get_status).';

/// The "crop and position" arguments shared by set_clip_properties,
/// add_overlay and update_overlay.
final Map<String, Map<String, dynamic>> _framingProps = {
  'crop_shape': _str(
      'Crop to the largest part of the picture with this shape, around the '
      'middle of the current crop ("16:9", "9:16", "1:1", "4:5"); "none" '
      'removes the crop. Use crop_x/y/width/height for any other part.',
      values: const ['none', '16:9', '9:16', '1:1', '4:5']),
  'crop_x': _num(
      'Crop: left edge as a fraction of the picture width (0..1), measured '
      'on the picture after rotation and flips.',
      min: 0,
      max: 1),
  'crop_y': _num('Crop: top edge as a fraction of the picture height (0..1).',
      min: 0, max: 1),
  'crop_width': _num(
      'Crop: width as a fraction of the picture width (0.05..1).',
      min: 0.05,
      max: 1),
  'crop_height': _num(
      'Crop: height as a fraction of the picture height (0.05..1).',
      min: 0.05,
      max: 1),
  'rotation': _int(
      'Turn the picture clockwise: 0, 90, 180 or 270 degrees (absolute, '
      'not added to the current value). The crop and position turn with it.',
      min: 0,
      max: 270),
  'flip_horizontal': _bool('true: mirrored left to right.'),
  'flip_vertical': _bool('true: mirrored top to bottom (upside down).'),
  'position_x': _num(
      'Which part stays in the frame when the picture is bigger than it '
      '(fit "fill", zoom, an overlay filling its box): -1 = keep the left '
      'edge, 0 = the middle (default), 1 = the right edge.',
      min: -1,
      max: 1),
  'position_y': _num(
      'The same up and down: -1 = keep the top, 0 = middle, 1 = the bottom.',
      min: -1,
      max: 1),
};

/// Settings of an overlay item (add_overlay, update_overlay).
final Map<String, Map<String, dynamic>> _overlayProps = {
  'start_ms': _int('Timeline position where it starts, in ms. Default 0.',
      min: 0),
  'in_ms': _int('Video: start inside the file (source ms). Default 0.', min: 0),
  'out_ms': _int('Video: end inside the file (source ms). Default: its end.',
      min: 0),
  'duration_ms': _int('Photo: how long it shows, in ms. Default 3000.',
      min: 100, max: 60000),
  'layout': _str('Where it goes (default "pip").',
      values: const ['pip', 'side_by_side', 'top_bottom', 'full', 'free']),
  'corner': _str('Corner of a "pip" (default "bottom_right").',
      values: const ['top_left', 'top_right', 'bottom_left', 'bottom_right']),
  'size_percent': _num(
      '"pip" / "free": it is as big as fits into this percentage of the '
      'frame\'s width and height, 10..100 (default 33).',
      min: 10,
      max: 100),
  'x': _num('"free": centre, as a fraction of the frame width (0..1). Makes '
      'the layout "free".', min: 0, max: 1),
  'y': _num('"free": centre, as a fraction of the frame height (0..1).',
      min: 0, max: 1),
  'overlay_side': _str(
      '"side_by_side": the overlay on the "left" or "right" (default) half; '
      '"top_bottom": on the "top" or "bottom" (default) half.',
      values: const ['left', 'right', 'top', 'bottom']),
  'border': _bool('"pip" / "free": a thin white frame around it.'),
  'volume': _num('Loudness of its sound, 0..2 (1 = unchanged).', min: 0, max: 2),
  'muted': _bool('true: its sound is not heard.'),
  'speed': _num('Video speed, 0.25..4 (1 = normal; pitch kept).',
      min: 0.25, max: 4),
  'fade_in_ms': _int('Picture and sound fade in over this many ms.', min: 0),
  'fade_out_ms': _int('Picture and sound fade out over this many ms.', min: 0),
  ..._framingProps,
};

/// The title style arguments shared by add_title and update_title.
final Map<String, Map<String, dynamic>> _titleStyleProps = {
  'style': _str(
      'A ready-made look, applied first (font, colour, outline, box, '
      'shadow); other arguments given in the same call win over it: '
      '${kTitleStylePresets.map((p) => '"${p.key}" (${p.label})').join(', ')}.',
      values: [for (final p in kTitleStylePresets) p.key]),
  'font': _str(
      'Font: "classic" (DejaVu Sans), "modern" (Rubik, rounded), "elegant" '
      '(Bona Nova, serif) or "handwritten" (Amatic SC). All have Latin, '
      'Cyrillic and Hebrew letters.',
      values: [for (final f in TitleFont.values) f.name]),
  'outline': _bool('A line around every letter (colour: outline_color).'),
  'outline_color': _str('Colour of the outline as #RRGGBB. Default #000000.'),
  'shadow': _bool('A soft drop shadow (not drawn with background). Default true.'),
  'align': _str(
      'How the lines line up: "center", "left" or "right". Also moves the '
      'text against that side of the picture (unless x is given).',
      values: [for (final a in TitleAlign.values) a.name]),
  'position': _str(
      'Quick vertical place: "top", "middle", "lower_third" or "bottom" '
      '(sets y; the text is kept inside the picture).',
      values: kTitlePositionNames.keys.toList()),
  'animation_in': _str(
      'How it appears: "none", "fade", "slide_up" or "pop" (about 0.4 s).',
      values: kTitleAnimationNames.keys.toList()),
  'animation_out': _str(
      'How it goes away: "none", "fade", "slide_up" or "pop".',
      values: kTitleAnimationNames.keys.toList()),
};

const List<String> _titleStyleKeys = [
  'style', 'font', 'outline', 'outline_color', 'shadow', 'align', //
  'position', 'animation_in', 'animation_out',
];

/// Names Claude uses for the colour filters, positions and animations.
const Map<String, LookFilter> kLookFilterNames = {
  'none': LookFilter.none,
  'warm': LookFilter.warm,
  'cool': LookFilter.cool,
  'black_and_white': LookFilter.blackWhite,
  'vintage': LookFilter.vintage,
  'vivid': LookFilter.vivid,
};
const Map<String, TitlePosition> kTitlePositionNames = {
  'top': TitlePosition.top,
  'middle': TitlePosition.middle,
  'lower_third': TitlePosition.lowerThird,
  'bottom': TitlePosition.bottom,
};
const Map<String, TitleAnimation> kTitleAnimationNames = {
  'none': TitleAnimation.none,
  'fade': TitleAnimation.fade,
  'slide_up': TitleAnimation.slideUp,
  'pop': TitleAnimation.pop,
};

const List<String> _framingKeys = [
  'crop_shape', 'crop_x', 'crop_y', 'crop_width', 'crop_height', //
  'rotation', 'flip_horizontal', 'flip_vertical', 'position_x', 'position_y',
];

const Map<String, double> _cropShapes = {
  '16:9': 16 / 9,
  '9:16': 9 / 16,
  '1:1': 1,
  '4:5': 4 / 5,
};

class ClipForgeTools {
  /// [exportLauncher] decides where exports run (default: inside this
  /// server; the shipped server passes [separateProcessLauncher]).
  /// [stateDir] holds export jobs and other notes of the server (default:
  /// `claude-jobs` next to the projects folder). [isAlive] / [hostName]
  /// replace the process check of the app's project lock (tests).
  ClipForgeTools({
    required this.projectsDir,
    required this.media,
    this.fontsChecked = const [],
    String Function()? newId,
    ExportLauncher? exportLauncher,
    String? stateDir,
    this.isAlive,
    this.hostName,
    TranscriptionService? speech,
    TranscribeLauncher? transcribeLauncher,
  })  : store = FileProjectStore(projectsDir.path),
        speechRoot = p.dirname(p.normalize(p.absolute(projectsDir.path))),
        _newId = newId ?? const Uuid().v4,
        jobs = ExportJobStore(stateDir ??
            p.join(p.dirname(p.normalize(p.absolute(projectsDir.path))), 'claude-jobs')) {
    this.exportLauncher = exportLauncher ??
        inProcessLauncher(() async => await media.requireEngine());
    this.speech = speech ??
        TranscriptionService(
            rootDir: speechRoot, appVersion: BuildInfo.current.version);
    transcribeJobs = TranscribeJobStore(p.join(jobs.dir, 'transcribe'));
    this.transcribeLauncher = transcribeLauncher ??
        inProcessTranscribeLauncher((_) => this.speech);
  }

  /// The ClipForge folder (`<Documents>/ClipForge`): language packs are in
  /// its `models` folder, shared with the app.
  final String speechRoot;

  /// Speech-to-text on this computer.
  late final TranscriptionService speech;

  /// The transcribe jobs, and where they run.
  late final TranscribeJobStore transcribeJobs;
  late final TranscribeLauncher transcribeLauncher;

  final ProjectsDir projectsDir;
  final MediaTools media;

  /// Where exports run.
  late final ExportLauncher exportLauncher;

  /// The export jobs (and other state of the server).
  final ExportJobStore jobs;
  final Future<bool> Function(int pid)? isAlive;
  final String? hostName;

  /// Folders searched for the fonts (shown by get_status when none had them).
  final List<String> fontsChecked;
  final FileProjectStore store;
  final String Function() _newId;

  // Loading and saving ------------------------------------------------------
  Future<String> _resolveId(String ref) async {
    final wanted = ref.trim();
    if (wanted.isEmpty) throw ToolError('project_id is empty.');
    final valid = !(wanted == '.' ||
        wanted == '..' ||
        wanted.contains('/') ||
        wanted.contains(r'\') ||
        wanted.contains('\u0000'));
    if (valid &&
        File(p.join(store.rootPath, wanted, FileProjectStore.projectFileName))
            .existsSync()) {
      return wanted;
    }
    final all = await store.list();
    final byName = [
      for (final i in all)
        if (i.name.trim().toLowerCase() == wanted.toLowerCase()) i,
    ];
    if (byName.length == 1) return byName.first.id;
    String listing(List<ProjectInfo> infos) => infos
        .take(20)
        .map((i) => '"${i.name}" (project_id ${i.id})')
        .join(', ');
    if (byName.length > 1) {
      throw ToolError('${byName.length} projects are called "$wanted", so '
          'the name alone does not say which. Use the project_id of the '
          'one you mean: ${byName.take(20).map((i) => 'project_id ${i.id} '
              '(last changed ${i.updatedAt.toLocal().toString().split('.').first}, '
              '${clock(i.durationMs)} long)').join('; ')}. Ask the user '
          'which one if that does not settle it.');
    }
    throw ToolError('There is no project with the id or name "$wanted" in '
        '${store.rootPath}. '
        '${all.isEmpty ? 'That folder has no projects yet (create_project makes one; get_status shows which folder is used).' : 'Projects: ${listing(all)}.'}');
  }

  Future<_Loaded> _load(Object? ref) async {
    final id = await _resolveId(ref as String);
    final file =
        File(p.join(store.rootPath, id, FileProjectStore.projectFileName));
    try {
      final raw = await file.readAsString();
      var project = await store.load(id);
      if (project.id != id) {
        // The folder name is the id the store saves under.
        project = Project.fromJson(project.toJson()..['id'] = id);
      }
      return _Loaded(project, file, raw);
    } on FormatException catch (e) {
      throw ToolError('The project cannot be read: ${e.message}');
    } on FileSystemException catch (e) {
      throw ToolError('The project cannot be read: ${e.message} (${e.path})');
    }
  }

  /// Refuses (a [ToolError]) when the project in [dir] is open in the app.
  Future<void> _requireClosedInApp(String dir, String name) async {
    final lock = await checkProjectLock(dir, isAlive: isAlive, hostName: hostName);
    if (!lock.isHeld) return;
    final info = lock.info!;
    throw ToolError('Nothing was changed: the project "$name" is open in the '
        'ClipForge app${info.host.isEmpty ? '' : ' on ${info.host}'} (since '
        '${info.openedAt.toLocal().toString().split('.').first}, app process '
        '${info.pid}). The app keeps its own copy and autosaves it, which '
        'would overwrite these edits. Ask the user to close the project in '
        'the app (back to the project list), then repeat the edit. Reading '
        '(get_project, export_video, export_srt) works while it is open.');
  }

  /// Saves [next], unless project.json changed on disk since [loaded] was
  /// read (which means the app, or something else, is writing to it).
  Future<void> _save(_Loaded loaded, Project next, {String tool = ''}) async {
    await _requireClosedInApp(loaded.dir, loaded.project.name);
    String? now;
    try {
      now = await loaded.file.readAsString();
    } on FileSystemException {
      now = null;
    }
    if (now != loaded.raw) {
      throw ToolError(
          'Nothing was saved: the project file changed on disk while this '
          'edit was being made (its updatedAt / content is no longer what '
          'was loaded). This happens when the project is open in the '
          'ClipForge app, which autosaves. Ask the user to close the '
          'project in the app (back to the home screen), then call '
          'get_project and repeat the edit.');
    }
    try {
      await store.save(next);
    } on FileSystemException catch (e) {
      throw ToolError('The project could not be saved: ${e.message} (${e.path})');
    }
    try {
      recordClaudeEdit(loaded.dir, await loaded.file.readAsString(), tool);
    } catch (_) {}
  }

  /// The name of the tool being run (calls run one at a time).
  String _currentTool = '';

  /// The answer of a tool that made or changed a project: a short summary
  /// (counts, length, size and why, what changed, warnings, who saved it
  /// last) by default; with [detail] "full" also the whole timeline.
  /// [before] is the project before the edit (for "what changed").
  Future<ToolResult> _projectResult(String message, Project project,
      {Map<String, dynamic> extra = const {},
      int? maxTitles,
      Project? before,
      String? detail,
      List<String> warnings = const []}) async {
    final full = detail == 'full';
    final all = [...warnings, ...soundPastEndWarnings(project)];
    final dir = p.join(store.rootPath, project.id);
    var editor = (by: 'app', tool: null as String?);
    try {
      editor = lastEditor(
          dir, await File(p.join(dir, FileProjectStore.projectFileName)).readAsString());
    } catch (_) {}
    final changes = before == null ? null : projectChanges(before, project);
    final canvas = project.canvasSize;
    final captions = project.titles.where((t) => t.kind == TitleKind.caption).length;
    final summary = <String, dynamic>{
      'id': project.id,
      'name': project.name,
      'clipCount': project.clips.length,
      'titleCount': project.titles.length - captions,
      'captionCount': captions,
      'audioCount': project.audio.length,
      'overlayCount': project.overlays.length,
      'durationMs': project.durationMs,
      'aspect': aspectName(project.aspect),
      'videoSize': videoSizeKey(project.videoSize),
      'canvasWidth': canvas.width,
      'canvasHeight': canvas.height,
      'canvasReason': canvasReason(project),
      'updatedAt': project.updatedAt.toUtc().toIso8601String(),
      'lastEditedBy': editor.by,
      if (editor.tool != null) 'lastEditTool': editor.tool,
    };
    final text = StringBuffer(message)
      ..writeln()
      ..writeln()
      ..writeln('Project "${project.name}" (project_id ${project.id}): '
          '${project.clips.length} clip(s), ${project.titles.length - captions} '
          'title(s), $captions caption(s), ${project.audio.length} sound '
          'item(s), ${project.overlays.length} overlay item(s); length '
          '${clock(project.durationMs)} (${project.durationMs} ms).')
      ..writeln('Size: ${canvasReason(project)}');
    if (changes != null) {
      text.writeln('${extra['dryRun'] == true ? 'What would change' : 'What changed'}: '
          '${changesText(changes)}.');
    }
    if (all.isNotEmpty) {
      text.writeln('Warnings:');
      for (final w in all) {
        text.writeln('- $w');
      }
    }
    text.write('Last saved ${project.updatedAt.toUtc().toIso8601String().split('.').first}Z '
        'by ${lastEditorText(editor)}.');
    if (full) {
      text
        ..writeln()
        ..writeln()
        ..write(projectText(project, maxTitles: maxTitles));
    } else {
      text.write(' (Short answer: get_project shows the timeline, page by '
          'page for long projects; detail "full" returns all of it here.)');
    }
    return ToolResult(text.toString().trimRight(), structured: {
      'message': message,
      ...extra,
      'project': full
          ? {...projectJson(project, maxTitles: maxTitles), ...summary}
          : summary,
      'changes': ?changes,
      if (all.isNotEmpty) 'warnings': all,
    });
  }

  /// Load, edit through [ProjectEditor], check, save, summarise.
  ///
  /// Common arguments: `dry_run` (do everything but save), `min_caption_ms`
  /// (captions this edit made shorter are lengthened to at least that,
  /// where there is room) and `detail`.
  Future<ToolResult> _edit(Map<String, dynamic> args,
      FutureOr<_Done> Function(ProjectEditor editor) body) async {
    final loaded = await _load(args['project_id']);
    final dryRun = args['dry_run'] == true;
    if (!dryRun) {
      await _requireClosedInApp(loaded.dir, loaded.project.name);
    }
    final editor = ProjectEditor(loaded.project, newId: _newId);
    final done = await body(editor);
    final notes = <String>[];
    final minCaption = _i(args, 'min_caption_ms') ?? 0;
    var shortened = shortenedCaptions(loaded.project, editor.project);
    if (minCaption > 0 && shortened.isNotEmpty) {
      final longer = lengthenCaptions(
          editor.project, {for (final t in shortened) t.id}, minCaption);
      for (final t in longer) {
        editor.updateTitle(t);
      }
      if (longer.isNotEmpty) {
        notes.add('${longer.length} caption(s) were kept on screen for at '
            'least $minCaption ms (min_caption_ms) where the next caption '
            'and the end of the video allowed');
      }
      shortened = [
        for (final t in shortenedCaptions(loaded.project, editor.project))
          if (t.endMs - t.startMs < minCaption) t,
      ];
    }
    final after = editor.project;
    final changed = !identical(after, loaded.project) &&
        _contentKey(after) != _contentKey(loaded.project);
    if (changed && !dryRun) {
      await _save(loaded, after, tool: _currentTool);
      (_undoSteps[after.id] ??= []).add(
          _Step(loaded.project, after, describeEdit(loaded.project, after)));
      _redoSteps[after.id]?.clear();
    }
    // The editor keeps titles on their picture; ones whose footage went
    // away are dropped with it. Say so, the model did not ask for that.
    final kept = {for (final t in after.titles) t.id};
    final lost = done.removesTitles
        ? const <TitleOverlay>[]
        : [
            for (final t in loaded.project.titles)
              if (!kept.contains(t.id)) t,
          ];
    var message = done.message;
    if (!changed && !dryRun && !_saysNothingItself.hasMatch(message)) {
      // Not "Updated the settings ... Nothing was changed": only the truth.
      // (What it had to say besides - its notes - is kept.)
      final note = message.indexOf(' Note: ');
      message = 'Nothing was changed: the project already had these values, '
          'or what was asked is outside the allowed range.'
          '${note < 0 ? '' : message.substring(note)}';
    } else if (dryRun) {
      // A dry run did nothing: say what it WOULD do.
      for (final e in _wouldForms.entries) {
        if (message.startsWith('${e.key} ')) {
          message = 'Would ${e.value}${message.substring(e.key.length)}';
          break;
        }
      }
    }
    if (lost.isNotEmpty) {
      message += ' ${lost.length} title(s) / caption(s) were removed along '
          'with the footage they were on: '
          '${lost.take(5).map((t) => '"${t.text.replaceAll(RegExp(r'\s+'), ' ')}"').join(', ')}'
          '${lost.length > 5 ? ', …' : ''}.';
    }
    if (notes.isNotEmpty) message += ' ${notes.join('. ')}.';
    if (!changed && !message.startsWith('Nothing was changed')) {
      message += '\nNothing ${dryRun ? 'would be' : 'was'} changed in the '
          'project (it already has these values, or the request is outside '
          'the allowed range).';
    }
    if (dryRun) {
      message = 'DRY RUN - nothing was saved. $message';
    }
    final extraWarnings = [
      for (final w in (done.extra['_warnings'] as List?) ?? const []) '$w',
    ];
    return _projectResult(
      message,
      dryRun ? after.copyWith(updatedAt: loaded.project.updatedAt) : after,
      before: loaded.project,
      detail: args['detail'] as String?,
      warnings: [
        if (shortened.isNotEmpty) shortCaptionWarning(shortened),
        ?unlinkedSpeechWarning(loaded.project, after),
        ...extraWarnings,
      ],
      extra: {
        'changed': changed && !dryRun,
        if (dryRun) 'dryRun': true,
        if (dryRun) 'wouldChange': changed,
        ...{...done.extra}..remove('_warnings'),
        if (lost.isNotEmpty) 'titlesRemovedWithFootage': [for (final t in lost) t.id],
      },
      maxTitles: kSummaryTitles,
    );
  }

  /// Messages that already say that (and why) nothing happened; any
  /// other message of an edit that changed nothing is replaced.
  static final RegExp _saysNothingItself =
      RegExp(r'^(No |Nothing |There (is|are) no |None )');

  /// Past tense at the start of a message -> what a dry run says.
  static const Map<String, String> _wouldForms = {
    'Separated': 'separate',
    'Removed': 'remove',
    'Updated': 'update',
    'Applied': 'apply',
    'Copied': 'copy',
    'Set': 'set',
    'Trimmed': 'trim',
    'Added': 'add',
    'Imported': 'import',
    'Put': 'put',
    'Cut': 'cut',
    'Moved': 'move',
    'Changed': 'change',
  };

  // Undo / redo of Claude's own edits --------------------------------------
  //
  // The app's undo history lives in the open editor and is not saved, so
  // this server keeps its own: every edit it saves is remembered (per
  // project, for as long as this server runs) and can be taken back or
  // done again - only while the project is still exactly as this server
  // left it (otherwise the app or something else changed it since).
  final Map<String, List<_Step>> _undoSteps = {};
  final Map<String, List<_Step>> _redoSteps = {};

  static String _contentKey(Project p) =>
      jsonEncode(p.toJson()..remove('updatedAt'));

  Future<ToolResult> _undoRedo(Map<String, dynamic> a, {required bool undo}) async {
    final loaded = await _load(a['project_id']);
    final id = loaded.project.id;
    final from = (undo ? _undoSteps : _redoSteps)[id] ?? [];
    if (from.isEmpty) {
      throw ToolError(undo
          ? 'There is nothing to undo: this server has made no edits to '
              'this project since it started (the app\'s own undo history '
              'is only in the app).'
          : 'There is nothing to redo.');
    }
    final step = from.last;
    final expected = undo ? step.after : step.before;
    if (_contentKey(loaded.project) != _contentKey(expected)) {
      from.clear();
      throw ToolError('The project was changed since Claude\'s last edit '
          '(probably in the app), so Claude\'s undo history for it was '
          'cleared. Use get_project and make the change directly.');
    }
    from.removeLast();
    final target = (undo ? step.before : step.after)
        .copyWith(updatedAt: DateTime.now());
    await _save(loaded, target, tool: undo ? 'undo' : 'redo');
    ((undo ? _redoSteps : _undoSteps)[id] ??= []).add(step);
    return _projectResult(
        '${undo ? 'Undid' : 'Redid'} "${step.label}". '
        '${(undo ? _undoSteps : _redoSteps)[id]?.length ?? 0} more step(s) '
        'can be ${undo ? 'undone' : 'redone'}.',
        target,
        before: loaded.project,
        detail: a['detail'] as String?,
        extra: {'changed': true, 'step': step.label},
        maxTitles: kSummaryTitles);
  }

  Future<ToolResult> _freezeFrame(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    await _requireClosedInApp(loaded.dir, project.name);
    final at = _i(a, 'at_ms')!;
    if (at <= 0 || at >= project.durationMs) {
      throw ToolError('at_ms must be inside the video (0..${project.durationMs} ms).');
    }
    final index = project.clipIndexAt(at);
    final clip = project.clips[index];
    if (clip.type != ClipType.video) {
      throw ToolError('At $at ms the video shows a photo; a freeze frame '
          'needs a video clip.');
    }
    final local = at - project.clipStartMs(index);
    final engine = await media.requireEngine();
    final dir = p.join(store.rootPath, project.id, 'media');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, 'freeze_${_newId()}.png');
    try {
      await engine.extractFrame(clip.path, clip.sourceMsAt(local), path);
    } on ExportException catch (e) {
      throw ToolError('The frame could not be saved: ${e.message}');
    }
    var w = clip.width, h = clip.height;
    try {
      final info = await engine.probe(path);
      if (info.width > 0 && info.height > 0) {
        w = info.width;
        h = info.height;
      }
    } on ExportException {
      // Keep the clip's size.
    }
    final duration = _i(a, 'duration_ms') ?? 2000;
    return _edit(a, (e) {
      final ok = e.insertFreezeFrame(
          at,
          Clip(
            id: _newId(),
            type: ClipType.photo,
            path: path,
            sourceDurationMs: 0,
            inMs: 0,
            outMs: duration,
            width: w,
            height: h,
            hasAudio: false,
          ));
      if (!ok) {
        throw ToolError('$at ms is too close to the start or end of a clip '
            'to freeze there (at least 100 ms inside it).');
      }
      return _Done('Held the picture at $at ms for $duration ms (a still '
          'between the two halves of clip #$index; the video got '
          '$duration ms longer). The still is saved in $dir.');
    });
  }

  // Argument helpers --------------------------------------------------------
  static int? _i(Map<String, dynamic> a, String key) =>
      (a[key] as num?)?.round();
  static double? _d(Map<String, dynamic> a, String key) =>
      (a[key] as num?)?.toDouble();

  /// A full path given by the model: quotes and `~` are handled, `file://`
  /// links are accepted, relative paths are refused.
  static String _path(Object? raw, String argument) {
    var text = (raw as String).trim();
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.startsWith('file://')) {
      try {
        text = Uri.parse(text).toFilePath();
      } catch (_) {}
    }
    if (text == '~' || text.startsWith('~/') || text.startsWith('~\\')) {
      final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
      if (home != null) text = p.join(home, text.length > 2 ? text.substring(2) : '');
    }
    if (text.isEmpty) throw ToolError('"$argument" is empty.');
    if (!p.isAbsolute(text)) {
      throw ToolError('"$argument" must be a full path (like '
          '${Platform.isWindows ? r'C:\Users\name\Videos\clip.mp4' : '/Users/name/Movies/clip.mp4'}), '
          'but got "$text". Ask the user where the file is.');
    }
    return p.normalize(text);
  }

  /// [_path] of a file that must exist.
  static String _existingFile(Object? raw, String argument) {
    final path = _path(raw, argument);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      throw ToolError('"$path" is a folder, not a file. Give the path of the '
          'file itself.');
    }
    if (type == FileSystemEntityType.notFound) {
      throw ToolError('The file "$path" does not exist. Check the spelling '
          'and the folder, or ask the user for the exact location.');
    }
    return path;
  }

  static Clip _clip(Project project, Object? id) {
    for (final c in project.clips) {
      if (c.id == id) return c;
    }
    final known = [
      for (var i = 0; i < project.clips.length; i++)
        '#$i ${project.clips[i].id} (${p.basename(project.clips[i].path)})',
    ];
    throw ToolError('There is no clip with clip_id "$id" in this project. '
        '${known.isEmpty ? 'The project has no clips.' : 'Clips: ${known.join(', ')}.'}');
  }

  static TitleOverlay _title(Project project, Object? id) {
    for (final t in project.titles) {
      if (t.id == id) return t;
    }
    throw ToolError('There is no title or caption with title_id "$id" in this '
        'project (${project.titles.length} exist; get_project lists them).');
  }

  static AudioClip _audio(Project project, Object? id) {
    for (final a in project.audio) {
      if (a.id == id) return a;
    }
    final known = [
      for (final a in project.audio) '${a.id} (${p.basename(a.path)})',
    ];
    throw ToolError('There is no music / sound item with audio_id "$id". '
        '${known.isEmpty ? 'The project has none.' : 'Items: ${known.join(', ')}.'}');
  }

  /// A sound track by id or (case-insensitive) name; "video" is the
  /// video's own sound when [video] allows it.
  static SoundTrack _track(Project project, Object? raw, {bool video = false}) {
    final text = '$raw'.trim();
    if (video &&
        (text == SoundTrack.videoId || text.toLowerCase() == 'video sound')) {
      return project.videoSound;
    }
    for (final t in project.soundTracks) {
      if (t.id == text) return t;
    }
    for (final t in project.soundTracks) {
      if (t.name.toLowerCase() == text.toLowerCase()) return t;
    }
    final known = [
      for (final t in project.soundTracks) '${t.id} ("${t.name}")',
    ];
    throw ToolError('There is no sound track "$text". '
        '${known.isEmpty ? 'The project has no sound tracks yet (add_sound_track makes one).' : 'Tracks: ${known.join(', ')}'}'
        '${video ? '; "video" is the video\'s own sound' : ''}.');
  }

  static void _limited(List<String> notes, String what, num asked, num got) {
    if ((asked - got).abs() > 1e-6) {
      notes.add('$what was limited to $got (asked for $asked)');
    }
  }

  static String _withNotes(String message, List<String> notes) =>
      notes.isEmpty ? message : '$message Note: ${notes.join('; ')}.';

  static ({int start, int end}) _titleTimes(
      Map<String, dynamic> a, int defaultMs) {
    final start = _i(a, 'start_ms')!;
    final end = _i(a, 'end_ms');
    final duration = _i(a, 'duration_ms');
    if (end != null && duration != null) {
      throw ToolError('Give either end_ms or duration_ms, not both.');
    }
    if (end != null && end <= start) {
      throw ToolError('end_ms ($end) must be after start_ms ($start).');
    }
    if (duration != null && duration <= 0) {
      throw ToolError('duration_ms must be more than 0.');
    }
    return (start: start, end: end ?? start + (duration ?? defaultMs));
  }

  static int _color(Object? raw) {
    final c = parseColor(raw as String);
    if (c == null) {
      throw ToolError('color must look like #RRGGBB (for example #FFFFFF for '
          'white or #FFD400 for yellow), got "$raw".');
    }
    return c;
  }

  /// Applies the crop and position arguments ([_framingProps]) to the
  /// picture of [id] (a clip or an overlay item).
  static void _applyFraming(ProjectEditor e, String id, Map<String, dynamic> a,
      void Function(String) note) {
    if (!_framingKeys.any((k) => a[k] != null)) return;
    Clip? clip;
    for (final c in e.project.clips) {
      if (c.id == id) clip = c;
    }
    for (final o in e.project.overlays) {
      if (o.id == id) clip = o.clip;
    }
    if (clip == null) return;
    var f = clip.framing;
    final rotation = _i(a, 'rotation');
    if (rotation != null) {
      final r = Framing.normalizeRotation(rotation);
      if (r != rotation % 360) {
        note('rotation goes in quarter turns: $rotation became $r');
      }
      for (var i = 0; i < 4 && f.rotation != r; i++) {
        f = f.turned(1);
      }
    }
    final h = a['flip_horizontal'] as bool?;
    if (h != null && h != f.flipH) f = f.flipped(horizontal: true);
    final v = a['flip_vertical'] as bool?;
    if (v != null && v != f.flipV) f = f.flipped(horizontal: false);
    final shape = a['crop_shape'] as String?;
    if (shape == 'none') {
      f = f.copyWith(crop: CropRect.full);
    } else if (shape != null) {
      final ratio = _cropShapes[shape];
      if (ratio != null) {
        f = f.copyWith(
            crop: cropForRatio(clip.copyWith(framing: f), ratio, f.crop));
      }
    }
    final cx = _d(a, 'crop_x'), cy = _d(a, 'crop_y');
    final cw = _d(a, 'crop_width'), ch = _d(a, 'crop_height');
    if (cx != null || cy != null || cw != null || ch != null) {
      final asked = CropRect(cx ?? f.crop.x, cy ?? f.crop.y,
          cw ?? f.crop.width, ch ?? f.crop.height);
      final kept = asked.clamped();
      if (kept != asked) {
        note('the crop was kept inside the picture: x ${kept.x.toStringAsFixed(3)}, '
            'y ${kept.y.toStringAsFixed(3)}, width ${kept.width.toStringAsFixed(3)}, '
            'height ${kept.height.toStringAsFixed(3)}');
      }
      f = f.copyWith(crop: kept);
    }
    final px = _d(a, 'position_x'), py = _d(a, 'position_y');
    if (px != null || py != null) f = f.copyWith(panX: px, panY: py);
    e.setFraming(id, f);
  }

  /// The style arguments ([_titleStyleProps]) applied to [t]: the "style"
  /// first, then each one given.
  static TitleOverlay _titleStyle(TitleOverlay t, Map<String, dynamic> a) {
    var n = t;
    final style = a['style'] as String?;
    if (style != null) {
      final preset =
          kTitleStylePresets.where((p) => p.key == style).firstOrNull;
      if (preset == null) {
        throw ToolError('Unknown style "$style". Styles: '
            '${kTitleStylePresets.map((p) => p.key).join(', ')}.');
      }
      n = preset.apply(n);
    }
    final font = a['font'] as String?;
    if (font != null) n = n.copyWith(font: TitleFont.values.byName(font));
    if (a['outline'] != null) n = n.copyWith(outline: a['outline'] as bool);
    if (a['outline_color'] != null) {
      n = n.copyWith(outlineColorArgb: _color(a['outline_color']), outline: true);
    }
    if (a['shadow'] != null) n = n.copyWith(shadow: a['shadow'] as bool);
    final align = a['align'] as String?;
    if (align != null) {
      final al = TitleAlign.values.byName(align);
      n = n.copyWith(align: al, x: titleAlignX(al));
    }
    final position = kTitlePositionNames[a['position']];
    if (position != null) n = n.copyWith(y: titlePositionY(position));
    final animIn = kTitleAnimationNames[a['animation_in']];
    if (animIn != null) n = n.copyWith(animIn: animIn);
    final animOut = kTitleAnimationNames[a['animation_out']];
    if (animOut != null) n = n.copyWith(animOut: animOut);
    return n;
  }

  static OverlayClip _overlay(Project project, Object? id) {
    for (final o in project.overlays) {
      if (o.id == id) return o;
    }
    final known = [
      for (final o in project.overlays) '${o.id} (${p.basename(o.path)})',
    ];
    throw ToolError('There is no overlay item with overlay_id "$id". '
        '${known.isEmpty ? 'The overlay track is empty.' : 'Items: ${known.join(', ')}.'}');
  }

  /// The overlay settings of [a] applied to [o] (only what is given).
  static OverlayClip _overlayArgs(OverlayClip o, Map<String, dynamic> a) {
    var next = o;
    var c = o.clip;
    final layout = a['layout'] as String?;
    if (layout != null) next = next.copyWith(layout: kOverlayLayoutNames[layout]);
    final corner = a['corner'] as String?;
    if (corner != null) next = next.copyWith(corner: kOverlayCornerNames[corner]);
    final size = _d(a, 'size_percent');
    if (size != null) next = next.copyWith(size: size / 100);
    final x = _d(a, 'x'), y = _d(a, 'y');
    if (x != null || y != null) {
      next = next.copyWith(x: x, y: y, layout: OverlayLayout.free);
    }
    final side = a['overlay_side'] as String?;
    if (side != null) {
      next = next.copyWith(overlayFirst: side == 'left' || side == 'top');
      if (layout == null) {
        if ((side == 'left' || side == 'right') &&
            next.layout != OverlayLayout.sideBySide) {
          next = next.copyWith(layout: OverlayLayout.sideBySide);
        } else if ((side == 'top' || side == 'bottom') &&
            next.layout != OverlayLayout.topBottom) {
          next = next.copyWith(layout: OverlayLayout.topBottom);
        }
      }
    }
    if (a['border'] != null) next = next.copyWith(border: a['border'] as bool);
    if (_i(a, 'fade_in_ms') != null) next = next.copyWith(fadeInMs: _i(a, 'fade_in_ms'));
    if (_i(a, 'fade_out_ms') != null) {
      next = next.copyWith(fadeOutMs: _i(a, 'fade_out_ms'));
    }
    if (_d(a, 'volume') != null) c = c.copyWith(volume: _d(a, 'volume'));
    if (a['muted'] != null) c = c.copyWith(muted: a['muted'] as bool);
    if (_d(a, 'speed') != null && c.type == ClipType.video) {
      c = c.copyWith(speed: _d(a, 'speed'));
    }
    if (c.type == ClipType.photo) {
      final d = _i(a, 'duration_ms');
      if (d != null) c = c.copyWith(inMs: 0, outMs: d);
    } else {
      if (_i(a, 'in_ms') != null) c = c.copyWith(inMs: _i(a, 'in_ms'));
      if (_i(a, 'out_ms') != null) c = c.copyWith(outMs: _i(a, 'out_ms'));
    }
    return next.copyWith(clip: c);
  }

  Future<ToolResult> _addOverlay(Map<String, dynamic> a, ToolCall call) async {
    final path = _existingFile(a['path'], 'path');
    final engine = await media.requireEngine();
    final MediaInfo info;
    try {
      info = await engine.probe(path);
    } on ExportException catch (e) {
      throw ToolError('"$path" could not be read as media (${e.message}).');
    }
    final photo = isImagePath(path);
    if (info.width <= 0 || info.height <= 0) {
      throw ToolError('"${p.basename(path)}" has no picture: overlays are '
          'videos or photos (add sound with add_music).');
    }
    if (!photo && (!info.hasVideo || info.durationMs <= 0)) {
      throw ToolError('No video found in "${p.basename(path)}".');
    }
    return _edit(a, (e) {
      if (e.project.clips.isEmpty) {
        throw ToolError('Add the main video first (add_media): an overlay goes '
            'over it.');
      }
      final base = OverlayClip(
        startMs: _i(a, 'start_ms') ?? 0,
        clip: Clip(
          id: _newId(),
          type: photo ? ClipType.photo : ClipType.video,
          path: path,
          sourceDurationMs: photo ? 0 : info.durationMs,
          inMs: 0,
          outMs: photo ? kDefaultPhotoMs : info.durationMs,
          width: info.width,
          height: info.height,
          hasAudio: !photo && info.hasAudio,
          audioStreams: photo ? const [] : info.audioStreams,
        ),
      );
      final wanted = base.startMs;
      final id = e.addOverlay(_overlayArgs(base, a));
      final notes = <String>[];
      void note(String t) {
        if (!notes.contains(t)) notes.add(t);
      }
      _applyFraming(e, id, a, note);
      final now = _overlay(e.project, id);
      if (now.startMs != wanted) {
        note('the overlay track was taken at $wanted ms, so it starts at '
            '${now.startMs} ms (overlay items never overlap)');
      }
      if (now.startMs >= e.project.durationMs) {
        note('it starts after the end of the video (${e.project.durationMs} '
            'ms), so it is not seen');
      }
      return _Done(
          _withNotes(
              'Added the overlay "${p.basename(path)}" at ${now.startMs} ms, '
              '${now.durationMs} ms long, layout ${overlayLayoutKey(now.layout)} '
              '(overlay_id ${now.id}).',
              notes),
          {'overlayId': now.id});
    });
  }

  Future<ToolResult> _updateOverlay(Map<String, dynamic> a, ToolCall call) {
    const keys = [
      'start_ms', 'in_ms', 'out_ms', 'duration_ms', 'layout', 'corner',
      'size_percent', 'x', 'y', 'overlay_side', 'border', 'volume', 'muted',
      'speed', 'fade_in_ms', 'fade_out_ms', ..._framingKeys, //
    ];
    if (!keys.any((k) => a[k] != null)) {
      throw ToolError('Give at least one setting to change: ${keys.join(', ')}.');
    }
    return _edit(a, (e) {
      final o = _overlay(e.project, a['overlay_id']);
      final notes = <String>[];
      void note(String t) {
        if (!notes.contains(t)) notes.add(t);
      }
      var next = _overlayArgs(o, a);
      final start = _i(a, 'start_ms');
      final timing = next.clip.inMs != o.clip.inMs ||
          next.clip.outMs != o.clip.outMs ||
          next.clip.speed != o.clip.speed;
      if (start != null && timing) {
        // Trim first, then move.
        e.updateOverlay(next);
        next = _overlay(e.project, o.id).copyWith(startMs: start);
      } else if (start != null) {
        next = next.copyWith(startMs: start);
      }
      e.updateOverlay(next);
      _applyFraming(e, o.id, a, note);
      final now = _overlay(e.project, o.id);
      if (start != null && now.startMs != start) {
        note('$start ms was taken by another overlay item, so it starts at '
            '${now.startMs} ms');
      }
      return _Done(
          _withNotes(
              'Updated the overlay "${p.basename(o.path)}": '
              '${now.startMs}–${now.endMs} ms, layout '
              '${overlayLayoutKey(now.layout)}.',
              notes),
          {'overlayId': now.id});
    });
  }

  // Tools -------------------------------------------------------------------

  /// Tools that answer with a project and so take `detail`.
  static const Set<String> _noDetail = {
    'get_status', 'list_projects', 'get_project', 'export_srt', 'export_video', //
    'get_export_status', 'cancel_export', 'list_sound_tracks',
    'transcribe', 'get_transcribe_status', 'cancel_transcribe',
    'get_transcript', 'find_in_transcript', 'list_auto_cuts',
    'get_guide', 'self_test',
  };

  /// Tools that change many clips at once and so take `dry_run`.
  static const Set<String> _dryRunTools = {
    'remove_silences', 'set_clip_properties', 'apply_to_all', //
    'copy_clip_settings', 'separate_sound',
  };

  /// Tools that can make captions shorter and so take `min_caption_ms`.
  static const Set<String> _captionTimingTools = {
    'remove_silences', 'set_clip_properties', 'apply_to_all', //
    'copy_clip_settings', 'trim_clip',
  };

  /// [t] with the common arguments it takes, and a handler that records
  /// which tool runs.
  ToolDef _extend(ToolDef t) {
    final props = {
      ...t.properties,
      if (_dryRunTools.contains(t.name))
        'dry_run': _bool('true: work out and report what would change (for '
            'remove_silences: every cut and the total time removed) WITHOUT '
            'saving anything. Default false.'),
      if (_captionTimingTools.contains(t.name))
        'min_caption_ms': _int(
            'Captions that this edit makes shorter (speed-up, cuts) are kept '
            'on screen at least this many ms, where the next caption and the '
            'end of the video allow, 0..10000. Default 0 = they shrink with '
            'their picture (as in the app); the answer warns about captions '
            'shorter than ${kShortCaptionMs / 1000} s. 1200 is a good value.',
            min: 0,
            max: 10000),
      if (!t.readOnly && !_noDetail.contains(t.name))
        'detail': _str(
            '"summary" (default): a short answer (counts, length, size, what '
            'changed, warnings). "full": also the whole timeline (can be '
            'very long for big projects; get_project pages it).',
            values: const ['summary', 'full']),
    };
    return ToolDef(
      name: t.name,
      title: t.title,
      description: t.description,
      properties: props,
      required: t.required,
      readOnly: t.readOnly,
      destructive: t.destructive,
      idempotent: t.idempotent,
      openWorld: t.openWorld,
      handler: (a, call) {
        _currentTool = t.name;
        return t.handler(a, call);
      },
    );
  }

  late final List<ToolDef> tools = [for (final t in _baseTools) _extend(t)];

  late final List<ToolDef> _baseTools = [
    ToolDef(
      name: 'get_status',
      title: 'Server status',
      description:
          'Shows how this server is set up: its version, which helper '
          'program is running and from where (and whether it is the one '
          'the ClipForge app installed), the folder the projects are read '
          'from, whether FFmpeg (needed to add media, remove silences and '
          'export) was found, and the rule about closing the project in the '
          'app. Call it first when something does not work.',
      properties: const {},
      readOnly: true,
      idempotent: true,
      handler: _getStatus,
    ),
    ToolDef(
      name: 'list_projects',
      title: 'List projects',
      description:
          'Lists all ClipForge projects (newest first) with their '
          'project_id, name, length and last change.',
      properties: const {},
      readOnly: true,
      idempotent: true,
      handler: _listProjects,
    ),
    ToolDef(
      name: 'get_project',
      title: 'Show a project',
      description:
          'Shows the timeline of a project: clips (index, clip_id, file, '
          'position on the timeline, used part of the source, speed, '
          'transition), music (audio_id), overlays and titles / captions '
          '(title_id), plus why the video has its size and warnings. Every '
          'media file is listed ONCE in a "media" table (m1, m2, ... with '
          'the full path); clips, sound and overlays name the key. Times '
          'are milliseconds. Long projects come in pages: at most clip_limit '
          'clips (default $kDefaultClipPage) and title_limit titles / '
          'captions (default $kDefaultTitlePage) per answer; the answer says '
          'the next clip_offset / title_offset. from_ms / to_ms show only '
          'what plays in that part of the video.',
      properties: {
        'project_id': _projectId,
        'from_ms': _int('Only what plays from this timeline position on (ms).', min: 0),
        'to_ms': _int('Only what plays before this timeline position (ms).', min: 0),
        'clip_offset': _int('Skip this many (matching) clips. Default 0.', min: 0),
        'clip_limit': _int(
            'At most this many clips, 1..$kMaxClipPage. Default $kDefaultClipPage.',
            min: 1,
            max: kMaxClipPage),
        'title_offset': _int('Skip this many (matching) titles / captions. Default 0.', min: 0),
        'title_limit': _int(
            'At most this many titles / captions, 0..$kMaxClipPage. Default $kDefaultTitlePage.',
            min: 0,
            max: kMaxClipPage),
      },
      required: const ['project_id'],
      readOnly: true,
      idempotent: true,
      handler: _getProject,
    ),
    ToolDef(
      name: 'create_project',
      title: 'Create a project',
      description:
          'Creates a new, empty project and returns its project_id. Add '
          'videos and photos with add_media next.',
      properties: {
        'name': _str('Name of the project, as shown in the app.'),
        'aspect': _str(
            'Shape of the video. "original" follows the first clip; 9:16 is '
            'vertical (Reels, Shorts, TikTok), 16:9 horizontal, 1:1 square, '
            '4:5 portrait. Default: original.',
            values: kAspectNames.keys.toList()),
      },
      required: const ['name'],
      handler: _createProject,
    ),
    ToolDef(
      name: 'duplicate_project',
      title: 'Duplicate a project',
      description:
          'Makes a copy of a project under a new project_id (the media files '
          'are shared, not copied). Useful before a big change, or to make a '
          'second version such as a vertical cut.',
      properties: {
        'project_id': _projectId,
        'name': _str('Name of the copy. Default: "<name> copy".'),
      },
      required: const ['project_id'],
      handler: _duplicateProject,
    ),
    ToolDef(
      name: 'rename_project',
      title: 'Rename a project',
      description: 'Changes the name of a project.$_editNote',
      properties: {
        'project_id': _projectId,
        'name': _str('The new name.'),
      },
      required: const ['project_id', 'name'],
      idempotent: true,
      handler: (a, _) => _edit(a, (e) {
        final name = (a['name'] as String).trim();
        if (name.isEmpty) throw ToolError('The new name is empty.');
        e.rename(name);
        return _Done('The project is now called "$name".');
      }),
    ),
    ToolDef(
      name: 'set_project_settings',
      title: 'Change project settings',
      description:
          'Sets the shape of the video (aspect), its size (video_size), a '
          'fade from black at the start / to black at the end (fade_in_ms, '
          'fade_out_ms) and / or automatic lowering of the music while '
          'speech plays (duck_music). Clips that do not match the shape are placed '
          'according to their "fit" (set_clip_properties).$_editNote',
      properties: {
        'project_id': _projectId,
        'aspect': _str(
            '"original" follows the first clip; 9:16 is vertical (Reels, '
            'Shorts, TikTok), 16:9 horizontal, 1:1 square, 4:5 portrait.',
            values: kAspectNames.keys.toList()),
        'duck_music': _bool(
            'true: every sound track that is not a speech track is lowered '
            'automatically while the video\'s own sound or a speech track '
            '(e.g. "Voice") plays; also the default for music tracks made '
            'later. Per track: update_sound_track duck_under_speech. '
            'Applied on export.'),
        'video_size': _str(
            'Size of the exported video by its short side: "match_first_clip" '
            '(default: the size of the first clip; a small phone clip makes a '
            'small video), "720p", "1080p" or "4k". Clips are scaled to it.',
            values: kVideoSizeNames.keys.toList()),
        'fade_in_ms': _int(
            'Fade the whole video in from black at the start (picture, '
            'titles and all sound), in ms, 0..10000 (0 = off). At most '
            'half the video is used.',
            min: 0,
            max: 10000),
        'fade_out_ms': _int(
            'Fade the whole video out to black at the end, in ms, 0..10000.',
            min: 0,
            max: 10000),
      },
      required: const ['project_id'],
      idempotent: true,
      handler: _setProjectSettings,
    ),
    ToolDef(
      name: 'add_media',
      title: 'Add videos or photos',
      description:
          'Adds video and photo files to the main track, in the order given, '
          'at the end or at "index". Each file is checked with FFmpeg '
          '(needs FFmpeg). The files are used where they are, not copied. '
          'Returns the new clip_ids.$_editNote',
      properties: {
        'project_id': _projectId,
        'paths': {
          'type': 'array',
          'minItems': 1,
          'items': {'type': 'string'},
          'description':
              'Full paths of the video / photo files, in playing order.',
        },
        'index': _int(
            'Position on the track for the first new clip (0 = before '
            'everything). Default: at the end.',
            min: 0),
        'photo_duration_ms': _int(
            'How long each photo is shown, in ms (100..60000). Default 3000.',
            min: 100,
            max: 60000),
      },
      required: const ['project_id', 'paths'],
      handler: _addMedia,
    ),
    ToolDef(
      name: 'add_music',
      title: 'Add music or sound',
      description:
          'Adds an audio file (music, voice-over, sound effect) on a sound '
          'track, starting at start_ms on the timeline. Items on one track '
          'never overlap: when the place is taken it goes on the first other '
          'track that is free there, else on a new track (at most 3), else '
          'right after what is in the way. Needs FFmpeg. Returns its audio_id '
          'and the track it went on; change it later with update_audio or '
          'move_audio_to_track. It stays at its timeline time when clips are '
          'cut. For a voice recorded separately that must stay in sync with '
          'the picture, use add_voice instead.$_editNote',
      properties: {
        'project_id': _projectId,
        'path': _str('Full path of the audio file.'),
        'start_ms': _int('Timeline position where it starts, in ms. Default 0.', min: 0),
        'in_ms': _int('Skip this much of the start of the file (source ms). Default 0.', min: 0),
        'out_ms': _int('Stop at this position of the file (source ms). Default: its end.', min: 0),
        'volume': _num('Loudness, 0..2 (1 = unchanged). Default 1.', min: 0, max: 2),
        'fade_in_ms': _int('Fade in over this many ms. Default 0.', min: 0),
        'fade_out_ms': _int('Fade out over this many ms. Default 0.', min: 0),
        'track_id': _str('The sound track (track_id or name, e.g. "Music", '
            '"Voice", "Effects"). Default: the "Music" track (made when '
            'missing).'),
      },
      required: const ['project_id', 'path'],
      handler: _addMusic,
    ),
    ToolDef(
      name: 'trim_clip',
      title: 'Trim a clip',
      description:
          'Chooses which part of a clip\'s source file is used. in_ms / '
          'out_ms are positions in the SOURCE FILE (not on the timeline): to '
          'keep seconds 5 to 20 of the file use in_ms 5000, out_ms 20000. '
          'Give one or both. For a photo, out_ms is the time it is shown. '
          'Values are limited to the file; a clip stays at least 100 ms '
          'long.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip (clip_id from the timeline).'),
        'in_ms': _int('New start inside the source file, in ms.', min: 0),
        'out_ms': _int('New end inside the source file, in ms (photos: display time).', min: 0),
      },
      required: const ['project_id', 'clip_id'],
      idempotent: true,
      handler: _trimClip,
    ),
    ToolDef(
      name: 'split_at',
      title: 'Split a clip',
      description:
          'Cuts the clip that plays at timeline_ms into two clips at that '
          'point (nothing is removed). timeline_ms is a position in the '
          'finished video. Returns the clip_ids of both halves; to cut a '
          'middle part out, split twice and remove_clip the piece in '
          'between.$_editNote',
      properties: {
        'project_id': _projectId,
        'timeline_ms': _int('Where to cut, in ms on the timeline.', min: 0),
      },
      required: const ['project_id', 'timeline_ms'],
      handler: _splitAt,
    ),
    ToolDef(
      name: 'remove_clip',
      title: 'Remove a clip',
      description:
          'Takes a clip off the timeline; later clips move up. The media '
          'file itself is not deleted.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip to remove.'),
      },
      required: const ['project_id', 'clip_id'],
      destructive: true,
      handler: (a, _) => _edit(a, (e) {
        final clip = _clip(e.project, a['clip_id']);
        e.removeClip(clip.id);
        return _Done('Removed the clip "${p.basename(clip.path)}" from the '
            'timeline (the file is untouched).');
      }),
    ),
    ToolDef(
      name: 'move_clip',
      title: 'Move a clip',
      description:
          'Moves a clip to another place in the playing order. to_index is '
          'the index the clip has afterwards (0 = first).$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip to move.'),
        'to_index': _int('Index the clip should end up at (0 = first).', min: 0),
      },
      required: const ['project_id', 'clip_id', 'to_index'],
      idempotent: true,
      handler: (a, _) => _edit(a, (e) {
        final clip = _clip(e.project, a['clip_id']);
        final from = e.project.clips.indexOf(clip);
        e.moveClip(from, _i(a, 'to_index')!);
        final to = e.project.clips.indexWhere((c) => c.id == clip.id);
        return _Done('The clip "${p.basename(clip.path)}" is now at index $to '
            '(was $from).');
      }),
    ),
    ToolDef(
      name: 'set_clip_properties',
      title: 'Change clip settings',
      description:
          'Changes one or more settings of a clip: speed, volume, mute, how '
          'it fills the frame, audio clean-up, voice focus, which sound track '
          'or side of the file is used, colour, colour filter, warmth, zoom, '
          'crop, rotation, flips, position (which part stays in the frame), '
          'fades from / to black and the transition INTO this clip from the '
          'previous one. Only the '
          'arguments given are changed. Use clip_id "all" to apply the same '
          'settings to every clip. Values outside the allowed range are '
          'limited.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip, or "all" for every clip.'),
        'speed': _num(
            'Playback speed of a video, 0.25..4 (1 = normal, 2 = twice as '
            'fast; the sound keeps its pitch). Changes the clip\'s length on '
            'the timeline.',
            min: 0.25,
            max: 4),
        'volume': _num('Loudness of the clip\'s own sound, 0..2 (1 = unchanged).', min: 0, max: 2),
        'muted': _bool('true: silence the clip\'s own sound.'),
        'fit': _str(
            'When the clip\'s shape differs from the video: "fit" shows all '
            'of it with black bars, "fill" crops it to fill the frame, '
            '"blur" shows all of it over a blurred copy.',
            values: [for (final f in FitMode.values) f.name]),
        'denoise': _bool(
            'true: clean up the sound on export (less background noise and '
            'rumble, more even speech).'),
        'voice_focus': _num(
            'Voice focus strength in percent, 0..100 (0 = off): makes speech '
            'clearer and tones down rumble, bass, hiss and sound spread wide '
            'in stereo (typically background music). It can NOT remove '
            'music: speech and music share the same frequencies. Works best '
            'when the speaker is in the middle of a stereo recording; a voice '
            'off to one side gets quieter. Applied after clean-up. Only part '
            'of it (tone) is heard in the app\'s preview; the export has all '
            'of it.',
            min: 0,
            max: 100),
        'audio_track': _int(
            'Which sound track of the file the clip uses, 1 = the first '
            '(default). For files that keep, e.g., each microphone on its own '
            'track. get_project shows audioTracks per clip.',
            min: 1),
        'audio_channel': _str(
            'For a stereo sound track: "both" (default), or use only the '
            '"left" or "right" channel, played on both sides - for '
            'recordings that keep a microphone on each side. Ignored (stays '
            '"both") when the track is not stereo.',
            values: [for (final c in AudioChannel.values) c.name]),
        'brightness': _num('-1..1, 0 = unchanged.', min: -1, max: 1),
        'contrast': _num('-1..1, 0 = unchanged.', min: -1, max: 1),
        'saturation': _num('-1..1, 0 = unchanged, -1 = black and white.', min: -1, max: 1),
        'zoom': _num(
            'Zoom in, 1..4 (1 = whole picture); into the middle, or where '
            'position_x / position_y say.',
            min: 1,
            max: 4),
        'filter': _str(
            'One-tap colour look, applied after brightness / contrast / '
            'saturation: "none", "warm", "cool", "black_and_white", '
            '"vintage" or "vivid".',
            values: kLookFilterNames.keys.toList()),
        'warmth': _num('Colour temperature, -1 (cooler, bluer) .. 1 (warmer, '
            'more orange); 0 = unchanged.', min: -1, max: 1),
        'fade_in_ms': _int(
            'Fade this clip in from black (its picture and its own sound) '
            'over this many ms, 0..10000 (0 = off). On the first clip this '
            'is a fade from black at the start of the video. For the whole '
            'video use set_project_settings fade_in_ms.',
            min: 0,
            max: 10000),
        'fade_out_ms': _int(
            'Fade this clip out to black over its last ms, 0..10000.',
            min: 0,
            max: 10000),
        ..._framingProps,
        'transition': _str(
            'How the picture changes from the PREVIOUS clip into this one. '
            'No effect on the first clip (use fade_in_ms there). A transition makes the two clips '
            'overlap, so the video gets shorter by its length.',
            values: [for (final t in TransitionType.values) t.name]),
        'transition_ms': _int(
            'Length of the transition in ms, 100..2000 (default 500); never '
            'more than half of either clip.',
            min: 100,
            max: 2000),
      },
      required: const ['project_id', 'clip_id'],
      idempotent: true,
      handler: _setClipProperties,
    ),
    ToolDef(
      name: 'remove_silences',
      title: 'Cut out silences',
      description:
          'Finds the silent stretches in the sound of a clip (or of every '
          'video clip when clip_id is left out) and cuts them out, like '
          '"Remove silences" in the app: 150 ms of quiet is kept on each '
          'side of a cut so speech is not clipped, and gaps shorter than '
          '300 ms after that are left alone. Each clip becomes several '
          'shorter clips. Needs FFmpeg and can take a while for long files. '
          'Titles and captions already in the project move with their '
          'picture; music stays where it is. To add an .srt that was made '
          'for the uncut recording afterwards, use import_srt with '
          'time_base "source".$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('Only this clip. Default: every video clip that has sound.'),
        'threshold_db': _num(
            'Sound quieter than this counts as silence, in dB (negative). '
            'Default: automatic - the background noise of each recording is '
            'measured and the threshold set a few dB above it (works for '
            'noisy phone recordings too). Give a number only to override it '
            '(then FFmpeg silencedetect at that level: about -30 for noisy, '
            '-45 for very clean recordings).',
            min: -90,
            max: 0),
        'min_silence_ms': _int(
            'Only silences at least this long are found, in ms. Default 700. '
            'A larger value (1000-1500) cuts fewer, longer pauses: gentler.',
            min: 100),
        'max_cuts_per_minute': _int(
            'Guard rail: at most this many cuts a minute (the longest pauses '
            'are cut first). Default: no limit. The answer always says how '
            'many cuts a minute it makes; above about 6 a talking-head video '
            'starts to look jumpy.',
            min: 1,
            max: 60),
      },
      required: const ['project_id'],
      destructive: true,
      handler: _removeSilences,
    ),
    ToolDef(
      name: 'add_title',
      title: 'Add a title',
      description:
          'Puts text over the picture from start_ms to end_ms (timeline). '
          'Default: centred, white, bold, 3 seconds. Font, outline, shadow, '
          'alignment, a quick position and entry / exit animations can be '
          'set too (or a ready-made "style"). For subtitles use '
          'add_caption or import_srt instead. Returns the title_id.$_editNote',
      properties: {
        'project_id': _projectId,
        'text': _str('The text. Line breaks are kept; long lines wrap.'),
        'start_ms': _int('When it appears, in ms on the timeline.', min: 0),
        'end_ms': _int('When it disappears, in ms on the timeline.', min: 0),
        'duration_ms': _int('Alternative to end_ms: how long it stays. Default 3000.', min: 100),
        'x': _num('Centre of the text across the picture, 0 (left) .. 1 (right). Default 0.5.', min: 0, max: 1),
        'y': _num('Centre of the text down the picture, 0 (top) .. 1 (bottom). Default 0.5.', min: 0, max: 1),
        'font_size': _num('Text height as a share of the picture\'s SHORT side (its height for a horizontal video, its width for a vertical one), 0.01..0.5. Default 0.06.', min: 0.01, max: 0.5),
        'color': _str('Text colour as #RRGGBB. Default #FFFFFF (white).'),
        'bold': _bool('Bold text. Default true.'),
        'background': _bool('Dark box behind the text for readability. Default false.'),
        ..._titleStyleProps,
      },
      required: const ['project_id', 'text', 'start_ms'],
      handler: _addTitle,
    ),
    ToolDef(
      name: 'add_caption',
      title: 'Add a caption',
      description:
          'Adds one subtitle line in the standard caption look (bottom '
          'centre, white bold text in a dark box) from start_ms on the '
          'timeline. For a whole subtitle file use import_srt. Returns the '
          'title_id.$_editNote',
      properties: {
        'project_id': _projectId,
        'text': _str('The caption text.'),
        'start_ms': _int('When it appears, in ms on the timeline.', min: 0),
        'end_ms': _int('When it disappears, in ms on the timeline.', min: 0),
        'duration_ms': _int('Alternative to end_ms: how long it stays. Default 2500.', min: 100),
      },
      required: const ['project_id', 'text', 'start_ms'],
      handler: _addCaption,
    ),
    ToolDef(
      name: 'import_srt',
      title: 'Import subtitles (.srt)',
      description:
          'Adds every cue of a SubRip (.srt) subtitle file as a caption. '
          'Give the file as "path", or its text as "srt_text". '
          'time_base says what the times in the file mean: "timeline" '
          '(default) = positions in the finished video as it is now; '
          '"source" = positions in the ORIGINAL media file (a transcript of '
          'the uncut recording) - each caption is then moved to where that '
          'moment now plays, following trims, removed silences and speed, '
          'and captions for removed parts are left out.$_editNote',
      properties: {
        'project_id': _projectId,
        'path': _str('Full path of the .srt file.'),
        'srt_text': _str('The contents of an .srt file, instead of path.'),
        'time_base': _str(
            '"timeline" or "source" (see the description). Default timeline.',
            values: const ['timeline', 'source']),
        'source_clip_id': _str(
            'With time_base "source": a clip of the media file the subtitles '
            'belong to. Only needed when the project uses more than one '
            'video file.'),
        'offset_ms': _int(
            'Shift every cue by this many ms before placing it (negative = '
            'earlier). Default 0.'),
        'replace_existing_captions': _bool(
            'true: remove the captions the project already has first '
            '(titles are kept). Default false.'),
      },
      required: const ['project_id'],
      handler: _importSrt,
    ),
    ToolDef(
      name: 'export_srt',
      title: 'Export subtitles (.srt)',
      description:
          'Returns the project\'s captions as SubRip (.srt) text and writes '
          'them to "path" when given. time_base "timeline" (default): '
          'positions in the finished video as it is now - they only fit this '
          'cut. time_base "source": positions in the ORIGINAL media file '
          '(trims, removed silences and speed undone), the same as import_srt '
          'time_base "source" reads, so the subtitles survive re-cutting. The '
          'project is not changed.',
      properties: {
        'project_id': _projectId,
        'path': _str('Full path of the .srt file to write. Optional.'),
        'overwrite': _bool('Allow replacing an existing file at path. Default false.'),
        'time_base': _str(
            '"timeline" (default) or "source" (see the description).',
            values: const ['timeline', 'source']),
        'source_clip_id': _str(
            'With time_base "source": a clip of the media file the times are '
            'for. Only needed when the project uses more than one video file.'),
      },
      required: const ['project_id'],
      readOnly: false,
      idempotent: true,
      handler: _exportSrt,
    ),
    ToolDef(
      name: 'update_title',
      title: 'Change a title or caption',
      description:
          'Changes the text, time or look of one title or caption. Only the '
          'arguments given are changed.$_editNote',
      properties: {
        'project_id': _projectId,
        'title_id': _str('The title or caption (title_id from the timeline).'),
        'text': _str('New text.'),
        'start_ms': _int('New start on the timeline, in ms.', min: 0),
        'end_ms': _int('New end on the timeline, in ms.', min: 0),
        'x': _num('Centre across the picture, 0..1.', min: 0, max: 1),
        'y': _num('Centre down the picture, 0..1.', min: 0, max: 1),
        'font_size': _num('Text height as a share of the picture\'s short side, 0.01..0.5.', min: 0.01, max: 0.5),
        'color': _str('Text colour as #RRGGBB.'),
        'bold': _bool('Bold text.'),
        'background': _bool('Dark box behind the text.'),
        ..._titleStyleProps,
      },
      required: const ['project_id', 'title_id'],
      idempotent: true,
      handler: _updateTitle,
    ),
    ToolDef(
      name: 'remove_title',
      title: 'Remove titles or captions',
      description:
          'Removes one title or caption (title_id), or all captions at once '
          '(all_captions true; plain titles are kept).$_editNote',
      properties: {
        'project_id': _projectId,
        'title_id': _str('The title or caption to remove.'),
        'all_captions': _bool('true: remove every caption of the project.'),
      },
      required: const ['project_id'],
      destructive: true,
      handler: _removeTitle,
    ),
    ToolDef(
      name: 'update_audio',
      title: 'Change music or sound',
      description:
          'Changes where a music / sound item starts, which part of its '
          'file is used, its volume, fades, clean-up and voice focus. Only '
          'the arguments given are changed. Items on one track never '
          'overlap: a new start_ms goes to the nearest free place, and trims '
          'stop at the neighbours. Moving or trimming a separated sound '
          'stops it from following its clip.$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The item (audio_id from the timeline).'),
        'start_ms': _int('Timeline position where it starts, in ms.', min: 0),
        'in_ms': _int('Start inside the audio file (source ms).', min: 0),
        'out_ms': _int('End inside the audio file (source ms).', min: 0),
        'volume': _num('Loudness, 0..2 (1 = unchanged).', min: 0, max: 2),
        'fade_in_ms': _int('Fade in over this many ms (0 = none).', min: 0),
        'fade_out_ms': _int('Fade out over this many ms (0 = none).', min: 0),
        'denoise': _bool('true: "Clean up sound" on this item (less steady '
            'background noise, steadier voice), like a clip\'s.'),
        'voice_focus': _num('"Voice focus" of this item, 0..1 (0 = off).',
            min: 0, max: 1),
      },
      required: const ['project_id', 'audio_id'],
      idempotent: true,
      handler: _updateAudio,
    ),
    ToolDef(
      name: 'remove_audio',
      title: 'Remove music or sound',
      description:
          'Takes a music / sound item out of the project. The audio file '
          'itself is not deleted.$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The item to remove.'),
      },
      required: const ['project_id', 'audio_id'],
      destructive: true,
      handler: (a, _) => _edit(a, (e) {
        final audio = _audio(e.project, a['audio_id']);
        e.removeAudio(audio.id);
        return _Done('Removed "${p.basename(audio.path)}" from the project '
            '(the file is untouched).');
      }),
    ),
    ToolDef(
      name: 'list_sound_tracks',
      title: 'List sound tracks',
      description:
          'Lists the sound tracks of a project (top to bottom) with their '
          'track_id, name, volume, mute, solo, "lower under speech", '
          '"counts as speech" and the audio_ids on each, plus the video\'s '
          'own sound (track_id "video"). Sound on one track never overlaps; '
          'the tracks are mixed.',
      properties: {'project_id': _projectId},
      required: const ['project_id'],
      readOnly: true,
      idempotent: true,
      handler: _listSoundTracks,
    ),
    ToolDef(
      name: 'add_sound_track',
      title: 'Add a sound track',
      description:
          'Adds an empty sound track at the bottom (at most 3 besides the '
          'video\'s own sound). Default names: "Voice" (counts as speech, '
          'so it lowers tracks marked duck_under_speech), "Music", '
          '"Effects". Returns its track_id.$_editNote',
      properties: {
        'project_id': _projectId,
        'name': _str('Name of the track. Default: the first of Voice, Music, '
            'Effects not in use.'),
      },
      required: const ['project_id'],
      handler: (a, _) => _edit(a, (e) {
        final id = e.addSoundTrack(name: a['name'] as String?);
        if (id == null) {
          throw ToolError('There are already ${ProjectEditor.maxSoundTracks} '
              'sound tracks; remove an empty one first (remove_sound_track).');
        }
        final t = e.project.trackById(id)!;
        return _Done('Added the sound track "${t.name}" (track_id $id).',
            {'trackId': id});
      }),
    ),
    ToolDef(
      name: 'update_sound_track',
      title: 'Change a sound track',
      description:
          'Renames a sound track or sets its volume, mute, solo, "lower '
          'under speech" (duck_under_speech: the track gets quieter while '
          'the video\'s own sound or a speech track plays, applied on export) '
          'or "counts as speech". track_id "video" is the video\'s own sound '
          '(volume, muted, solo only). While any track is solo, only solo '
          'tracks are heard, also in the export. Only the arguments given '
          'are changed.$_editNote',
      properties: {
        'project_id': _projectId,
        'track_id': _str('The track (track_id or its name), or "video".'),
        'name': _str('New name.'),
        'volume': _num('Level of the whole track, 0..2 (1 = unchanged).',
            min: 0, max: 2),
        'muted': _bool('true: the track is not heard.'),
        'solo': _bool('true: only solo tracks are heard.'),
        'duck_under_speech':
            _bool('true: lower this track while speech plays.'),
        'speech': _bool('true: this track holds speech and lowers the tracks '
            'that duck under speech.'),
      },
      required: const ['project_id', 'track_id'],
      idempotent: true,
      handler: _updateSoundTrack,
    ),
    ToolDef(
      name: 'remove_sound_track',
      title: 'Remove a sound track',
      description:
          'Removes an EMPTY sound track (move or remove its items first).'
          '$_editNote',
      properties: {
        'project_id': _projectId,
        'track_id': _str('The track (track_id or its name).'),
      },
      required: const ['project_id', 'track_id'],
      destructive: true,
      handler: (a, _) => _edit(a, (e) {
        final t = _track(e.project, a['track_id']);
        final n = e.project.clipsOnTrack(t.id).length;
        if (n > 0) {
          throw ToolError('The track "${t.name}" still has $n item(s); move '
              'them (move_audio_to_track) or remove them (remove_audio) first.');
        }
        e.removeSoundTrack(t.id);
        return _Done('Removed the sound track "${t.name}".');
      }),
    ),
    ToolDef(
      name: 'move_audio_to_track',
      title: 'Move sound to another track',
      description:
          'Moves a music / sound item to another sound track, at start_ms '
          '(default: where it is). When that place is taken it goes to the '
          'nearest free place on that track.$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The item.'),
        'track_id': _str('The track to move it to (track_id or name).'),
        'start_ms': _int('New timeline position, in ms.', min: 0),
      },
      required: const ['project_id', 'audio_id', 'track_id'],
      idempotent: true,
      handler: (a, _) => _edit(a, (e) {
        final audio = _audio(e.project, a['audio_id']);
        final t = _track(e.project, a['track_id']);
        e.moveAudioToTrack(audio.id, t.id, startMs: _i(a, 'start_ms'));
        final now = _audio(e.project, audio.id);
        final asked = _i(a, 'start_ms') ?? audio.startMs;
        return _Done(
            'Moved "${p.basename(now.path)}" to the "${t.name}" track, '
            '${now.startMs}–${now.endMs} ms'
            '${now.startMs != asked ? ' (the place asked for was taken)' : ''}.');
      }),
    ),
    ToolDef(
      name: 'separate_sound',
      title: 'Separate sound from video',
      description:
          '"Separate sound": copies a video clip\'s own sound to a sound '
          'track (default: the speech track "Voice", made when missing) at '
          'the same place, with the clip\'s speed, volume, clean-up, voice '
          'focus and sound source, and mutes the clip. The separated sound '
          'follows its clip through trims, moves, splits, remove_silences '
          'and deletes until it is moved or trimmed itself '
          '(update_audio), which allows L-cuts and J-cuts (sound starting '
          'before or after the picture). Typical podcast: separate_sound '
          'with all true, music on the "Music" track with '
          'duck_under_speech. Give clip_id or all.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The video clip.'),
        'all': _bool('true: every video clip with sound that is not '
            'separated yet, as one step.'),
        'track_id': _str('The track for the sound (track_id or name).'),
      },
      required: const ['project_id'],
      handler: _separateSound,
    ),
    ToolDef(
      name: 'reattach_sound',
      title: 'Put sound back on its clip',
      description:
          'Undoes a separation: the separated sound item is removed and its '
          'video clip plays its own sound again, with the item\'s volume, '
          'clean-up and voice focus.$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The separated sound item (audio_id).'),
      },
      required: const ['project_id', 'audio_id'],
      destructive: true,
      handler: (a, _) => _edit(a, (e) {
        final audio = _audio(e.project, a['audio_id']);
        if (audio.isVoice) {
          throw ToolError('That item is a voice recorded separately, not the '
              'clip\'s own sound. To end its link use align_audio with link '
              'false; to hear the camera again use set_clip_properties '
              'muted false.');
        }
        if (audio.sourceClipId == null) {
          throw ToolError('That item is music, not sound separated from a clip.');
        }
        if (!e.reattachSound(audio.id)) {
          throw ToolError('The clip this sound came from is no longer in the '
              'project.');
        }
        return _Done('The sound is back on clip ${audio.sourceClipId}.');
      }),
    ),
    ToolDef(
      name: 'add_voice',
      title: 'Add a voice recorded separately',
      description:
          'For a voice that was recorded on its own file while the video '
          'was filmed (a separate microphone, a recorder, Zoom\'s one audio '
          'file per speaker): adds it, LINES IT UP with the video by sound '
          '(compares it with the camera\'s own sound) and links it to the '
          'clip, so it follows every trim, split, speed change, '
          'remove_silences and delete, like a separated sound. Every clip '
          'of the same video file gets its part. It goes on its own speech '
          'track (music is lowered under it), and the camera\'s own sound '
          'is muted (mute_clip). Call it once per speaker file; each gets '
          'its own track (at most 3 sound tracks in a project). Returns '
          'offset_ms (time in the voice file = time in the video file + '
          'offset), confidence (0..1), drift_ms and warnings. When the '
          'sounds do not match (confidence under 0.5) or the video has no '
          'sound, the voice is put at the start of the clip, the camera '
          'stays on and a warning says so: then set the offset by hand with '
          'align_audio. Needs FFmpeg; a 25-minute pair takes a few '
          'seconds. remove_silences then listens to the voice(s), not to '
          'the muted camera. Use add_music for music and effects.$_editNote',
      properties: {
        'project_id': _projectId,
        'path': _str('Full path of the voice file.'),
        'clip_id': _str('The video clip it belongs to. Default: every video '
            'file in the project is compared and the best match is used.'),
        'track_name': _str('Name of its track, e.g. the speaker\'s name. '
            'Default: taken from a Zoom file name (audioSamTaylor2140… '
            '-> "Sam Taylor"), else "Voice".'),
        'mute_clip': _bool('Mute the camera\'s own sound of those clips. '
            'Default true (false when it could not be lined up).'),
        'align': _bool('Line it up by sound. Default true. false: use '
            'offset_ms, or put the start of the file at the start of the '
            'clip.'),
        'offset_ms': _int('With align false: the offset to use (time in '
            'the voice file = time in the video file + offset_ms; may be '
            'negative).'),
        'volume': _num('Loudness, 0..2. Default 1.', min: 0, max: 2),
      },
      required: const ['project_id', 'path'],
      handler: _addVoice,
    ),
    ToolDef(
      name: 'align_audio',
      title: 'Line up a sound with the video',
      description:
          'Lines up a sound item that is already in the project with the '
          'video: "Line up with the video" in the app. With nothing else '
          'given it compares the sound with the camera\'s own sound and '
          'links it to the best matching clip (music that is really a voice '
          'becomes a linked voice on a speech track; a voice whose link was '
          'broken is linked again). offset_ms sets the offset by hand '
          'instead; nudge_ms moves a linked voice against the picture '
          '(positive = heard later); link false ends the link (the sound '
          'stays where it is). Returns offset_ms, confidence, drift_ms and '
          'warnings. Nothing changes when the sounds do not match.'
          '$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The sound item (audio_id).'),
        'clip_id': _str('Compare with / link to this video clip. Default: '
            'the best match, or the clip it is linked to.'),
        'offset_ms': _int('Set the offset by hand: time in the sound file = '
            'time in the video file + offset_ms.'),
        'nudge_ms': _int('Move a linked voice by this many ms: positive = '
            'later against the picture, negative = earlier.'),
        'mute_clip': _bool('Mute (true) or unmute (false) the camera\'s own '
            'sound of the clips it is linked to.'),
        'link': _bool('false: end the link. The sound stays where it is; '
            'with mute_clip false the camera is heard again.'),
      },
      required: const ['project_id', 'audio_id'],
      handler: _alignAudio,
    ),
    ToolDef(
      name: 'add_overlay',
      title: 'Add an overlay (picture-in-picture)',
      description:
          'Puts a video or photo on the overlay track: a second video row '
          'drawn OVER the main video from start_ms on (titles and captions '
          'still go on top). Layouts: "pip" (picture-in-picture in a corner, '
          'size_percent), "side_by_side" / "top_bottom" (main video on one '
          'half, the overlay on the other: the middle of each is kept), '
          '"full" (covers the main video: cut-aways, another camera), "free" '
          '(x / y). Its sound plays along with the video sound (volume, '
          'muted). Overlay items never overlap: when start_ms is taken it '
          'goes right after the item in the way. Overlays stay at their time '
          'when the main clips are edited (like music). Crop / position '
          'arguments work as in set_clip_properties. Needs FFmpeg. Returns '
          'its overlay_id.$_editNote',
      properties: {
        'project_id': _projectId,
        'path': _str('Full path of the video or photo.'),
        ..._overlayProps,
      },
      required: const ['project_id', 'path'],
      handler: _addOverlay,
    ),
    ToolDef(
      name: 'update_overlay',
      title: 'Change an overlay',
      description:
          'Changes an overlay item: start_ms moves it (to the nearest free '
          'place when taken), in_ms / out_ms trim it (source times; '
          'duration_ms for a photo), layout, corner, size, side, frame, '
          'sound, speed, fades, crop and position. Only the arguments given '
          'are changed.$_editNote',
      properties: {
        'project_id': _projectId,
        'overlay_id': _str('The overlay item (overlay_id from the timeline).'),
        ..._overlayProps,
      },
      required: const ['project_id', 'overlay_id'],
      idempotent: true,
      handler: _updateOverlay,
    ),
    ToolDef(
      name: 'remove_overlay',
      title: 'Remove an overlay',
      description: 'Takes an item off the overlay track. The media file is '
          'not deleted.$_editNote',
      properties: {
        'project_id': _projectId,
        'overlay_id': _str('The overlay item to remove.'),
      },
      required: const ['project_id', 'overlay_id'],
      destructive: true,
      handler: (a, _) => _edit(a, (e) {
        final o = _overlay(e.project, a['overlay_id']);
        e.removeOverlay(o.id);
        return _Done('Removed the overlay "${p.basename(o.path)}" (the file '
            'is untouched).');
      }),
    ),
    ToolDef(
      name: 'duplicate_clip',
      title: 'Duplicate a clip',
      description:
          'Puts a copy of a clip (same part of the file and all its '
          'settings) right after it on the main track, like Ctrl/Cmd+D in '
          'the app. Returns the copy\'s clip_id.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip to copy.'),
      },
      required: const ['project_id', 'clip_id'],
      handler: (a, _) => _edit(a, (e) {
        final c = _clip(e.project, a['clip_id']);
        final id = e.duplicateClip(c.id)!;
        return _Done('Duplicated clip #${e.project.clips.indexWhere((x) => x.id == c.id)} '
            '(new clip_id $id, right after it).', {'clipId': id});
      }),
    ),
    ToolDef(
      name: 'copy_clip_settings',
      title: 'Copy clip settings to other clips',
      description:
          'Copies the settings of one clip onto other clips, like Copy '
          'settings / Paste settings in the app: the look (brightness, '
          'contrast, saturation, filter, warmth), fit and zoom, crop and '
          'position, and - between video clips - speed and sound settings '
          '(volume, mute, clean-up, voice focus, sound track and side). '
          'Never the trim, transition or fades. One step.$_editNote',
      properties: {
        'project_id': _projectId,
        'from_clip_id': _str('The clip whose settings are copied.'),
        'to_clip_ids': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'The clips that get them; ["all"] for every other clip.',
        },
      },
      required: const ['project_id', 'from_clip_id', 'to_clip_ids'],
      idempotent: true,
      handler: (a, _) => _edit(a, (e) {
        final from = _clip(e.project, a['from_clip_id']);
        final raw = [for (final x in a['to_clip_ids'] as List) '$x'];
        final ids = raw.contains('all')
            ? [for (final c in e.project.clips) if (c.id != from.id) c.id]
            : [for (final x in raw) _clip(e.project, x).id];
        final n = e.pasteClipSettings(ids, ClipSettings.of(from));
        return _Done('Copied the settings of clip #${e.project.clips.indexOf(from)} '
            'to ${ids.length} clip(s); $n changed.', {'changedClips': n});
      }),
    ),
    ToolDef(
      name: 'apply_to_all',
      title: 'Apply a clip\'s settings to all clips',
      description:
          'Like "Apply to all clips" in the app: gives every other clip this '
          'clip\'s look (brightness, contrast, saturation, filter, warmth, '
          'zoom, fit), speed (videos only) and / or sound settings (videos '
          'only). One step.$_editNote',
      properties: {
        'project_id': _projectId,
        'clip_id': _str('The clip whose settings are copied.'),
        'look': _bool('Copy the look. Default false.'),
        'speed': _bool('Copy the speed. Default false.'),
        'sound': _bool('Copy the sound settings. Default false.'),
      },
      required: const ['project_id', 'clip_id'],
      idempotent: true,
      handler: (a, _) {
        if (a['look'] != true && a['speed'] != true && a['sound'] != true) {
          throw ToolError('Say what to copy: look, speed and / or sound true.');
        }
        return _edit(a, (e) {
          final c = _clip(e.project, a['clip_id']);
          final n = e.applyClipSettingsToAll(c.id,
              look: a['look'] == true,
              speed: a['speed'] == true,
              sound: a['sound'] == true);
          return _Done('$n clip(s) changed.', {'changedClips': n});
        });
      },
    ),
    ToolDef(
      name: 'freeze_frame',
      title: 'Freeze frame',
      description:
          'Holds the picture of the video at at_ms (timeline) for '
          'duration_ms: the clip is split there and a still of that frame '
          'is put between the halves (silent), with the clip\'s look and '
          'crop. The video gets longer by duration_ms. Needs FFmpeg; the '
          'still is saved in the project\'s folder.$_editNote',
      properties: {
        'project_id': _projectId,
        'at_ms': _int('Timeline position of the frame to hold, in ms.', min: 1),
        'duration_ms': _int('How long it is held, in ms (100..60000). Default 2000.',
            min: 100, max: 60000),
      },
      required: const ['project_id', 'at_ms'],
      handler: _freezeFrame,
    ),
    ToolDef(
      name: 'move_sound_track',
      title: 'Move a sound track up or down',
      description:
          'Changes the order of the sound tracks (as shown under the video, '
          'top to bottom). Only the order changes; the sound is the same.$_editNote',
      properties: {
        'project_id': _projectId,
        'track_id': _str('The track (track_id or name).'),
        'direction': _str('"up" or "down".', values: const ['up', 'down']),
      },
      required: const ['project_id', 'track_id', 'direction'],
      handler: (a, _) => _edit(a, (e) {
        final t = _track(e.project, a['track_id']);
        final ok = e.moveSoundTrack(t.id, a['direction'] == 'up' ? -1 : 1);
        return _Done(ok
            ? 'Moved the track "${t.name}" ${a['direction']}.'
            : 'The track "${t.name}" is already at the ${a['direction'] == 'up' ? 'top' : 'bottom'}.');
      }),
    ),
    ToolDef(
      name: 'fit_music_to_video',
      title: 'Fit music to the video',
      description:
          'Makes a piece of music end exactly where the video ends, with a '
          '2-second fade-out: longer music is cut; shorter music is looped '
          '(its trimmed part repeats with 300 ms cross-fades) when loop is '
          'true, otherwise nothing changes and the answer says it is too '
          'short. Stops before another sound later on the same track. Do it '
          'after cutting the video (music stays at its timeline times).$_editNote',
      properties: {
        'project_id': _projectId,
        'audio_id': _str('The music (id from get_project).'),
        'loop': _bool('true: loop music that is shorter than the video. '
            'Default false.'),
      },
      required: const ['project_id', 'audio_id'],
      handler: (a, _) => _edit(a, (e) {
        final m = _audio(e.project, a['audio_id']);
        final r = e.fitMusicToVideo(m.id, loop: a['loop'] == true);
        return switch (r) {
          FitMusicResult.fitted => _Done('The music now ends with the video '
              '(2 s fade-out).'),
          FitMusicResult.looped =>
            _Done('The music now loops until the video ends (2 s fade-out).'),
          FitMusicResult.stoppedAtNext => _Done('Another sound comes later on '
              'the same track, so the music now stops just before it.'),
          FitMusicResult.alreadyFits =>
            _Done('The music already ends with the video.'),
          FitMusicResult.tooShort => throw ToolError(
              'The music is shorter than the video. Call again with '
              'loop: true to repeat it.'),
          FitMusicResult.startsAfterVideo =>
            throw ToolError('The music starts after the video ends.'),
          FitMusicResult.notFound => throw ToolError('No such music.'),
        };
      }),
    ),
    ToolDef(
      name: 'undo',
      title: 'Undo Claude\'s last edit',
      description:
          'Takes back the last edit THIS server made to the project (one '
          'tool call = one step), for as long as the server runs. It does '
          'not reach the app\'s own undo history, and refuses when the '
          'project was changed since (e.g. in the app).$_editNote',
      properties: {'project_id': _projectId},
      required: const ['project_id'],
      destructive: true,
      handler: (a, _) => _undoRedo(a, undo: true),
    ),
    ToolDef(
      name: 'redo',
      title: 'Redo an undone edit',
      description: 'Does again what undo took back last.$_editNote',
      properties: {'project_id': _projectId},
      required: const ['project_id'],
      handler: (a, _) => _undoRedo(a, undo: false),
    ),
    ToolDef(
      name: 'relink_media',
      title: 'Point to a moved media file',
      description:
          'Fixes clips and music marked [FILE MISSING] after a media file '
          'was moved or renamed: every item that used old_path now uses '
          'new_path. Trim ranges are kept, so new_path must be the same '
          'recording. No file is moved or changed.$_editNote',
      properties: {
        'project_id': _projectId,
        'old_path': _str('The path the project has now (as shown by get_project).'),
        'new_path': _str('Full path where the file is now.'),
      },
      required: const ['project_id', 'old_path', 'new_path'],
      idempotent: true,
      handler: _relinkMedia,
    ),
    ToolDef(
      name: 'export_video',
      title: 'Export the video',
      description:
          'Starts rendering the project to an MP4 file (H.264 + AAC), or its '
          'sound only to an M4A or MP3 file (format), as a background JOB, '
          'and waits up to wait_seconds (default $kDefaultExportWait) for it. '
          'A short video is finished within that and the answer has its '
          'path, size, length and encoder. A longer one answers with its '
          'job_id, progress, an estimated time left and the output path: '
          'then call get_export_status with that job_id (wait_seconds up to '
          '$kMaxStatusWait waits for it) until status is "finished" - do not '
          'start the export again. The render runs in its own process, so '
          'it keeps going if this server is restarted; cancel_export stops '
          'it. Needs FFmpeg. The file is written as "<name>.<id>.part.<ext>" '
          'and renamed when complete. The project is not changed; edits made '
          'while it renders are not in this export. An existing file is only '
          'replaced with overwrite true. The picture is encoded on the '
          'graphics card when the FFmpeg in use has a working hardware H.264 '
          'encoder, else on the processor (libx264); a failed graphics-card '
          'export is redone on the processor automatically. quality "small" '
          'scales the frame down to a short side of 720 (when it is bigger) '
          'and caps the video bitrate at $kSmallMaxRateKbps kbit/s; the '
          'answer says which of the two applied.',
      properties: {
        'project_id': _projectId,
        'output_path': _str(
            'Full path of the .mp4 to write. Default: a new file named '
            'after the project in the "exports" folder next to the projects '
            'folder.'),
        'quality': _str(
            '"full" keeps the full resolution (default); "small" makes a '
            'smaller file for messaging apps: frame scaled down to a short '
            'side of 720 when bigger, video bitrate capped at '
            '$kSmallMaxRateKbps kbit/s, sound 128 kbit/s.',
            values: [for (final q in ExportQuality.values) q.name]),
        'overwrite': _bool('Allow replacing an existing file at output_path. Default false.'),
        'hardware': _bool(
            'Use the graphics card for the picture when possible (faster). '
            'Default true; false always uses the processor (libx264).'),
        'format': _str(
            '"video" (MP4, default), or the sound only: "m4a" (AAC) or "mp3" '
            '(needs an FFmpeg with libmp3lame). output_path must end in '
            '.mp4 / .m4a / .mp3 to match.',
            values: [for (final f in ExportFormat.values) f.name]),
        'fps': _str(
            'Frame rate of the video: "same" (the highest frame rate of the '
            'clips, rounded: 29.97 -> 30), "24", "25", "30" (default) or '
            '"60".',
            values: const ['same', '24', '25', '30', '60']),
        'wait_seconds': _int(
            'How long to wait for the export before answering with the job, '
            '0..$kMaxStatusWait. Default $kDefaultExportWait.',
            min: 0,
            max: kMaxStatusWait),
      },
      required: const ['project_id'],
      openWorld: false,
      handler: _exportVideo,
    ),
    ToolDef(
      name: 'get_export_status',
      title: 'Export progress',
      description:
          'How an export started by export_video is doing: status '
          '("starting", "running", "finished", "failed", "cancelled", or '
          '"lost" when its process stopped without finishing), percent done, '
          'time so far, estimated time left, the output path and, when '
          'finished, the size, length and encoder of the file; when it '
          'failed, why. Works after a server restart too. wait_seconds waits '
          'that long for it to finish first (progress is reported meanwhile). '
          'Without job_id: the recent exports.',
      properties: {
        'job_id': _str('The job_id export_video returned.'),
        'wait_seconds': _int(
            'Wait up to this long for the export to finish, 0..$kMaxStatusWait. '
            'Default 0 (answer at once).',
            min: 0,
            max: kMaxStatusWait),
      },
      readOnly: true,
      handler: _getExportStatus,
    ),
    ToolDef(
      name: 'cancel_export',
      title: 'Cancel an export',
      description:
          'Stops a running export (job_id from export_video). The part '
          'written so far is deleted; nothing is left under the output name.',
      properties: {
        'job_id': _str('The job_id export_video returned.'),
      },
      required: const ['job_id'],
      destructive: true,
      handler: _cancelExport,
    ),
    ..._speechToolDefs,
    ..._selfToolDefs,
  ];

  // Handlers ----------------------------------------------------------------
  Future<ToolResult> _getStatus(Map<String, dynamic> a, ToolCall call) async {
    final mpeg = await media.ffmpeg();
    final probe = await media.ffprobe();
    final dir = Directory(projectsDir.path);
    final exists = dir.existsSync();
    final count = exists ? (await store.list()).length : 0;
    final fonts = media.fonts;
    final os = Platform.operatingSystem;
    final exe = Platform.resolvedExecutable;
    final self = selfCommand();
    final running = [
      for (final r in jobs.list())
        if (r.isActive) r,
    ];
    final speechStatus = await _speechStatus();
    final helper = helperReport();
    final text = StringBuffer()
      ..writeln('$kServerTitle MCP server.')
      ..writeln('Version: ${BuildInfo.current.describe()}')
      ..writeln('Program: ${self.join(' ')}')
      ..writeln('Projects folder: ${projectsDir.path}')
      ..writeln(fonts == null
          ? 'Title fonts: NOT FOUND (see below)'
          : 'Title fonts: ${p.dirname(fonts.regular)}')
      ..writeln(mpeg == null
          ? 'ffmpeg: NOT FOUND. ${ffmpegInstallHint()}'
          : 'ffmpeg: ${mpeg.path} (version ${mpeg.version})')
      ..writeln(probe == null
          ? 'ffprobe: NOT FOUND (it is installed together with ffmpeg).'
          : 'ffprobe: ${probe.path} (version ${probe.version})')
      ..writeln('Export jobs: ${jobs.dir} (exports run in '
          '${exportLauncher.description}'
          '${exportLauncher.survivesServer ? ' that keeps going when Claude or this helper closes' : ''}); '
          '${running.isEmpty ? 'none running' : '${running.length} running: ${running.map((r) => '${r.id} "${r.projectName}" ${(r.progress * 100).floor()}%').join(', ')}'}.')
      ..writeln(helperReportText(helper))
      ..writeln(speechStatus.text)
      ..writeln()
      ..writeln('Running on $os.')
      ..writeln('Projects folder chosen by: ${projectsDir.source}')
      ..writeln(exists
          ? '  $count project(s) found.'
          : '  This folder does not exist yet. If the app already has '
              'projects, they are stored somewhere else: restart the server '
              'with --projects-dir <folder>.');
    if (projectsDir.alsoChecked.isNotEmpty) {
      text.writeln('  other places considered: ${projectsDir.alsoChecked.join('; ')}');
    }
    if (mpeg == null || probe == null) {
      text.writeln('Without FFmpeg, add_media, add_music, remove_silences '
          'and export_video do not work; the other tools do.');
    }
    if (fonts == null) {
      text.writeln('Title fonts were not found, so projects with titles or '
          'captions cannot be exported. Looked in: ${fontsChecked.join('; ')}. '
          'Start the server with --fonts-dir <folder with $kFontRegular '
          'and $kFontBold>.');
    }
    text
      ..writeln()
      ..write(kCloseProjectRule);
    return ToolResult(text.toString(), structured: {
      'server': kServerName,
      'version': kServerVersion,
      // The same version line as the app's Help > About ClipForge.
      'build': BuildInfo.current.toJson(),
      'executable': exe,
      'command': self,
      'helper': helper,
      'platform': os,
      'projectsDir': projectsDir.path,
      'projectsDirSource': projectsDir.source,
      'projectsDirExists': exists,
      'projectsDirAlsoChecked': projectsDir.alsoChecked,
      'projectCount': count,
      'ffmpeg': mpeg == null ? null : {'path': mpeg.path, 'version': mpeg.version},
      'ffprobe': probe == null ? null : {'path': probe.path, 'version': probe.version},
      'ffmpegInstallHint': mpeg == null || probe == null ? ffmpegInstallHint() : null,
      'fontsDir': fonts == null ? null : p.dirname(fonts.regular),
      'jobsDir': jobs.dir,
      'exportsRun': exportLauncher.description,
      'runningExports': [for (final r in running) r.id],
      'transcription': speechStatus.data,
      'note': kCloseProjectRule,
    });
  }

  Future<ToolResult> _getProject(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    final from = _i(a, 'from_ms'), to = _i(a, 'to_ms');
    if (from != null && to != null && to <= from) {
      throw ToolError('to_ms ($to) must be after from_ms ($from).');
    }
    final page = ProjectPage(
      fromMs: from,
      toMs: to,
      clipOffset: _i(a, 'clip_offset') ?? 0,
      clipLimit: _i(a, 'clip_limit') ?? kDefaultClipPage,
      titleOffset: _i(a, 'title_offset') ?? 0,
      titleLimit: _i(a, 'title_limit') ?? kDefaultTitlePage,
    );
    final editor = lastEditor(loaded.dir, loaded.raw);
    final lock = await checkProjectLock(loaded.dir, isAlive: isAlive, hostName: hostName);
    final warnings = [
      if (lock.isHeld)
        'The project is open in the ClipForge app${lock.info!.host.isEmpty ? '' : ' on ${lock.info!.host}'}: '
            'editing tools refuse until it is closed there (reading and exporting work).',
      ...soundPastEndWarnings(project),
    ];
    final text = StringBuffer()
      ..writeln(projectText(project, page: page))
      ..writeln('Size: ${canvasReason(project)}')
      ..write('Last saved ${project.updatedAt.toUtc().toIso8601String().split('.').first}Z by '
          '${lastEditorText(editor)}.');
    if (warnings.isNotEmpty) {
      text
        ..writeln()
        ..writeln('Warnings:')
        ..write(warnings.map((w) => '- $w').join('\n'));
    }
    return ToolResult(text.toString(), structured: {
      'message': 'Current state of the project.',
      'project': {
        ...projectJson(project, page: page),
        'canvasReason': canvasReason(project),
        'lastEditedBy': editor.by,
        if (editor.tool != null) 'lastEditTool': editor.tool,
        'openInApp': lock.isHeld,
      },
      if (warnings.isNotEmpty) 'warnings': warnings,
    });
  }

  Future<ToolResult> _listProjects(Map<String, dynamic> a, ToolCall call) async {
    final infos = await store.list();
    final text = StringBuffer();
    if (infos.isEmpty) {
      text.write('No projects in ${store.rootPath}. Create one with '
          'create_project, or call get_status if the app has projects that '
          'do not show up here.');
    } else {
      text.writeln('${infos.length} project(s) in ${store.rootPath}:');
      for (final i in infos) {
        text.writeln('  "${i.name}"  project_id ${i.id}  '
            'length ${i.durationMs} ms (${clock(i.durationMs)})  '
            'changed ${i.updatedAt.toLocal().toString().split('.').first}');
      }
    }
    return ToolResult(text.toString().trimRight(), structured: {
      'projectsDir': store.rootPath,
      'projects': [
        for (final i in infos)
          {
            'id': i.id,
            'name': i.name,
            'durationMs': i.durationMs,
            'updatedAt': i.updatedAt.toUtc().toIso8601String(),
          },
      ],
    });
  }

  Future<ToolResult> _createProject(Map<String, dynamic> a, ToolCall call) async {
    final name = (a['name'] as String).trim();
    if (name.isEmpty) throw ToolError('The project name is empty.');
    Project project;
    try {
      project = await store.create(name);
      final aspect = kAspectNames[a['aspect']];
      if (aspect != null && aspect != project.aspect) {
        final editor = ProjectEditor(project)..setAspect(aspect);
        project = editor.project;
        await store.save(project);
      }
    } on FileSystemException catch (e) {
      throw ToolError('The project could not be created in ${store.rootPath}: '
          '${e.message}');
    }
    return _projectResult(
        'Created the project "${project.name}".'
        '${project.name == name ? '' : ' (A project called "$name" already exists, so this one got a number.)'}',
        project,
        detail: a['detail'] as String?, extra: {'changed': true});
  }

  /// The note for a new project whose name got " (2)" because [asked]
  /// (or, without one, [fallback]) was taken.
  static String _numbered(String got, String? asked, String fallback) {
    final wanted = (asked ?? '').trim().isEmpty ? fallback : asked!.trim();
    return got == wanted
        ? ''
        : ' (A project called "$wanted" already exists, so this one got a '
            'number.)';
  }

  Future<ToolResult> _duplicateProject(Map<String, dynamic> a, ToolCall call) async {
    final source = await _load(a['project_id']);
    final Project copy;
    try {
      copy = await store.duplicate(source.project.id, name: a['name'] as String?);
    } on FileSystemException catch (e) {
      throw ToolError('The project could not be copied: ${e.message}');
    }
    return _projectResult(
        'Copied "${source.project.name}" to the new project "${copy.name}" '
        '(project_id ${copy.id}). The original is unchanged.'
        '${_numbered(copy.name, a['name'] as String?, '${source.project.name} copy')}',
        copy,
        detail: a['detail'] as String?,
        extra: {'changed': true, 'sourceProjectId': source.project.id},
        maxTitles: kSummaryTitles);
  }

  Future<ToolResult> _setProjectSettings(Map<String, dynamic> a, ToolCall call) {
    if (a['aspect'] == null &&
        a['duck_music'] == null &&
        a['video_size'] == null &&
        a['fade_in_ms'] == null &&
        a['fade_out_ms'] == null) {
      throw ToolError(
          'Give aspect, video_size, fade_in_ms, fade_out_ms and / or duck_music.');
    }
    return _edit(a, (e) {
      final done = <String>[];
      final aspect = kAspectNames[a['aspect']];
      if (aspect != null) {
        e.setAspect(aspect);
        final c = e.project.canvasSize;
        done.add('shape ${a['aspect']} (${c.width}x${c.height} px)');
      }
      final size = kVideoSizeNames[a['video_size']];
      if (size != null) {
        e.setVideoSize(size);
        final c = e.project.canvasSize;
        done.add('video size ${a['video_size']} (${c.width}x${c.height} px)');
      }
      final duck = a['duck_music'] as bool?;
      if (duck != null) {
        e.setDuckMusic(duck);
        done.add('lowering music under speech ${duck ? 'on' : 'off'}');
      }
      if (a['fade_in_ms'] != null || a['fade_out_ms'] != null) {
        e.setProjectFades(
            fadeInMs: _i(a, 'fade_in_ms'), fadeOutMs: _i(a, 'fade_out_ms'));
        final f = e.project.projectFades;
        done.add('fade from black ${e.project.fadeInMs} ms, to black '
            '${e.project.fadeOutMs} ms'
            '${f.inMs != e.project.fadeInMs || f.outMs != e.project.fadeOutMs ? ' (the export uses ${f.inMs} / ${f.outMs} ms: at most half the video each)' : ''}');
      }
      return _Done('Project settings: ${done.join(', ')}.');
    });
  }

  Future<ToolResult> _addMedia(Map<String, dynamic> a, ToolCall call) async {
    final paths = [
      for (final raw in a['paths'] as List) _existingFile(raw, 'paths'),
    ];
    final engine = await media.requireEngine();
    final photoMs = _i(a, 'photo_duration_ms') ?? kDefaultPhotoMs;
    final clips = <Clip>[];
    final problems = <String>[];
    for (final path in paths) {
      final name = p.basename(path);
      final MediaInfo info;
      try {
        info = await engine.probe(path);
      } on ExportException catch (e) {
        problems.add('$name: the file could not be read as media (${e.message})');
        continue;
      }
      if (info.width <= 0 || info.height <= 0) {
        problems.add(info.hasAudio
            ? '$name: this is a sound file without a picture; add it with add_music '
                '(music, effects) or add_voice (a voice recorded separately '
                'for a video)'
            : '$name: not a video or photo');
      } else if (isImagePath(path)) {
        clips.add(Clip(
          id: _newId(),
          type: ClipType.photo,
          path: path,
          sourceDurationMs: 0,
          inMs: 0,
          outMs: photoMs,
          width: info.width,
          height: info.height,
          hasAudio: false,
        ));
      } else if (!info.hasVideo || info.durationMs <= 0) {
        problems.add('$name: no video found in this file');
      } else {
        clips.add(Clip(
          id: _newId(),
          type: ClipType.video,
          path: path,
          sourceDurationMs: info.durationMs,
          inMs: 0,
          outMs: info.durationMs,
          width: info.width,
          height: info.height,
          hasAudio: info.hasAudio,
          audioStreams: info.audioStreams,
          frameRate: info.fps,
        ));
      }
    }
    if (clips.isEmpty) {
      throw ToolError('Nothing was added. ${problems.join('; ')}.');
    }
    return _edit(a, (e) {
      var at = _i(a, 'index');
      final before = {for (final c in e.project.clips) c.id};
      for (final clip in clips) {
        e.addClip(clip, index: at);
        if (at != null) at++;
      }
      final added = [
        for (final c in e.project.clips)
          if (!before.contains(c.id)) c.id,
      ];
      return _Done(
          'Added ${added.length} clip(s) to the timeline.'
          '${problems.isEmpty ? '' : ' NOT added: ${problems.join('; ')}.'}',
          {'addedClipIds': added, 'problems': problems});
    });
  }

  Future<ToolResult> _addMusic(Map<String, dynamic> a, ToolCall call) async {
    final path = _existingFile(a['path'], 'path');
    final engine = await media.requireEngine();
    final MediaInfo info;
    try {
      info = await engine.probe(path);
    } on ExportException catch (e) {
      throw ToolError('"$path" could not be read as media (${e.message}).');
    }
    if (!info.hasAudio || info.durationMs <= 0) {
      throw ToolError('No sound was found in "$path".');
    }
    return _edit(a, (e) {
      final before = {for (final x in e.project.audio) x.id};
      final track = a['track_id'] == null
          ? kMusicTrackId
          : _trackOrNew(e, a['track_id']);
      e.addAudio(AudioClip(
        trackId: track,
        id: _newId(),
        path: path,
        sourceDurationMs: info.durationMs,
        startMs: _i(a, 'start_ms') ?? 0,
        inMs: _i(a, 'in_ms') ?? 0,
        outMs: _i(a, 'out_ms') ?? info.durationMs,
        volume: _d(a, 'volume') ?? 1.0,
        fadeInMs: _i(a, 'fade_in_ms') ?? 0,
        fadeOutMs: _i(a, 'fade_out_ms') ?? 0,
      ));
      final added = e.project.audio.firstWhere((x) => !before.contains(x.id));
      final on = e.project.trackById(added.trackId)!;
      return _Done(
          'Added "${p.basename(path)}" (${info.durationMs} ms long) at '
          '${added.startMs} ms on the timeline, on the "${on.name}" track '
          '(track_id ${on.id}).',
          {'audioId': added.id, 'trackId': on.id});
    });
  }

  Future<ToolResult> _trimClip(Map<String, dynamic> a, ToolCall call) {
    final inMs = _i(a, 'in_ms');
    final outMs = _i(a, 'out_ms');
    if (inMs == null && outMs == null) {
      throw ToolError('Give in_ms and / or out_ms (positions in the source file, in ms).');
    }
    if (inMs != null && outMs != null && outMs <= inMs) {
      throw ToolError('out_ms ($outMs) must be after in_ms ($inMs).');
    }
    return _edit(a, (e) {
      final clip = _clip(e.project, a['clip_id']);
      if (clip.type == ClipType.photo && outMs == null) {
        throw ToolError('This clip is a photo: set how long it is shown with out_ms.');
      }
      e.trimClip(clip.id, inMs: inMs, outMs: outMs);
      final now = _clip(e.project, clip.id);
      final notes = <String>[];
      if (clip.type == ClipType.video) {
        if (inMs != null) _limited(notes, 'in_ms', inMs, now.inMs);
      }
      if (outMs != null) _limited(notes, 'out_ms', outMs, now.outMs);
      return _Done(_withNotes(
          clip.type == ClipType.photo
              ? 'The photo "${p.basename(clip.path)}" is now shown for ${now.outMs} ms.'
              : 'The clip "${p.basename(clip.path)}" now uses ${now.inMs}–${now.outMs} ms '
                  'of its file (${now.durationMs} ms on the timeline).',
          notes));
    });
  }

  Future<ToolResult> _splitAt(Map<String, dynamic> a, ToolCall call) {
    final at = _i(a, 'timeline_ms')!;
    return _edit(a, (e) {
      final project = e.project;
      if (project.clips.isEmpty) throw ToolError('The project has no clips to split.');
      if (at <= 0 || at >= project.durationMs) {
        throw ToolError('timeline_ms $at is outside the video: it must be '
            'between 1 and ${project.durationMs - 1} (the video is '
            '${project.durationMs} ms long).');
      }
      final index = project.clipIndexAt(at);
      final before = {for (final c in project.clips) c.id};
      if (!e.splitAt(at)) {
        throw ToolError('Cannot split at $at ms: that is less than 100 ms '
            'from an edge of clip #$index (it plays '
            '${project.clipStartMs(index)}–${project.clipEndMs(index)} ms), '
            'and a clip must stay at least 100 ms long. If a cut is already '
            'there, no split is needed.');
      }
      final first = e.project.clips[index];
      final second = e.project.clips.firstWhere((c) => !before.contains(c.id));
      return _Done(
          'Split clip #$index at $at ms. First half: clip_id ${first.id}; '
          'second half: clip_id ${second.id} (new).',
          {'firstClipId': first.id, 'secondClipId': second.id});
    });
  }

  Future<ToolResult> _setClipProperties(Map<String, dynamic> a, ToolCall call) async {
    const settings = [
      'speed', 'volume', 'muted', 'fit', 'denoise', 'voice_focus',
      'audio_track', 'audio_channel', 'brightness', 'contrast',
      'saturation', 'zoom', 'transition', 'transition_ms', 'filter',
      'warmth', 'fade_in_ms', 'fade_out_ms', ..._framingKeys,
    ];
    if (!settings.any((s) => a[s] != null)) {
      throw ToolError('Give at least one setting to change: ${settings.join(', ')}.');
    }
    // Choosing a track or side needs to know the file's sound tracks; clips
    // added by older versions do not record them, so they are probed first.
    final probed = <String, List<int>>{};
    if (a['audio_track'] != null || a['audio_channel'] != null) {
      final before = (await _load(a['project_id'])).project;
      final targets = a['clip_id'] == 'all'
          ? before.clips
          : [_clip(before, a['clip_id'])];
      final unknown = {
        for (final c in targets)
          if (c.type == ClipType.video && c.hasAudio && c.audioStreams.isEmpty)
            c.path,
      };
      if (unknown.isNotEmpty) {
        final engine = await media.requireEngine();
        for (final path in unknown) {
          try {
            probed[path] = (await engine.probe(path)).audioStreams;
          } on ExportException {
            // Unreadable now (e.g. missing): the choice stays at its default.
          }
        }
      }
    }
    final focus = _d(a, 'voice_focus');
    final track = _i(a, 'audio_track');
    final channel = a['audio_channel'] == null
        ? null
        : AudioChannel.values.byName(a['audio_channel'] as String);
    return _edit(a, (e) {
      final all = a['clip_id'] == 'all';
      final targets =
          all ? [...e.project.clips] : [_clip(e.project, a['clip_id'])];
      if (targets.isEmpty) throw ToolError('The project has no clips.');
      final notes = <String>[];
      void note(String text) {
        if (!notes.contains(text)) notes.add(text);
      }

      final speed = _d(a, 'speed');
      final volume = _d(a, 'volume');
      final zoom = _d(a, 'zoom');
      final brightness = _d(a, 'brightness');
      final contrast = _d(a, 'contrast');
      final saturation = _d(a, 'saturation');
      final transitionMs = _i(a, 'transition_ms');
      for (final clip in targets) {
        final id = clip.id;
        final label = all ? ' of #${e.project.clips.indexOf(clip)}' : '';
        if (speed != null) {
          if (clip.type == ClipType.photo) {
            note('speed does not apply to photos');
          } else {
            e.setClipSpeed(id, speed);
          }
        }
        if (volume != null) e.setClipVolume(id, volume);
        if (a['muted'] != null) e.setClipMuted(id, a['muted'] as bool);
        if (a['fit'] != null) {
          e.setClipFit(id, FitMode.values.byName(a['fit'] as String));
        }
        if (a['denoise'] != null) e.setClipDenoise(id, a['denoise'] as bool);
        final streams = probed[clip.path];
        if (streams != null && clip.audioStreams.isEmpty) {
          e.setClipAudioStreams(id, streams);
        }
        if (focus != null || track != null || channel != null) {
          if (clip.type == ClipType.photo) {
            note('sound settings do not apply to photos');
          } else if (!clip.hasAudio) {
            note('the clip${all ? '' : ' "${p.basename(clip.path)}"'} has no sound'
                '${all ? ' (#${e.project.clips.indexOf(clip)})' : ''}');
          }
        }
        if (focus != null) e.setClipVoiceFocus(id, focus / 100);
        if (track != null || channel != null) {
          e.setClipAudioSource(id,
              track: track == null ? null : track - 1, channel: channel);
        }
        if (brightness != null || contrast != null || saturation != null) {
          e.setClipAdjustments(id,
              brightness: brightness, contrast: contrast, saturation: saturation);
        }
        if (zoom != null) e.setClipZoom(id, zoom);
        final filter = kLookFilterNames[a['filter']];
        if (filter != null) e.setClipFilter(id, filter);
        final warmth = _d(a, 'warmth');
        if (warmth != null) e.setClipWarmth(id, warmth);
        final fadeIn = _i(a, 'fade_in_ms'), fadeOut = _i(a, 'fade_out_ms');
        if (fadeIn != null || fadeOut != null) {
          e.setClipFades(id, fadeInMs: fadeIn, fadeOutMs: fadeOut);
          final c = _clip(e.project, id);
          if (fadeIn != null) _limited(notes, 'fade_in_ms$label', fadeIn, c.fadeInMs);
          if (fadeOut != null) {
            _limited(notes, 'fade_out_ms$label', fadeOut, c.fadeOutMs);
          }
        }
        _applyFraming(e, id, a, note);
        if (a['transition'] != null || transitionMs != null) {
          final type = a['transition'] == null
              ? clip.transition
              : TransitionType.values.byName(a['transition'] as String);
          e.setClipTransition(id, type, durationMs: transitionMs);
        }
        final now = _clip(e.project, id);
        if (speed != null && clip.type == ClipType.video) {
          _limited(notes, 'speed$label', speed, now.speed);
        }
        if (volume != null) _limited(notes, 'volume$label', volume, now.volume);
        if (focus != null && clip.type == ClipType.video) {
          _limited(notes, 'voice_focus$label', focus,
              (now.voiceFocus * 1e6).round() / 1e4);
        }
        if (clip.type == ClipType.video && clip.hasAudio) {
          if (track != null && now.audioTrackInUse != track - 1) {
            note(now.audioStreams.isEmpty
                ? 'the sound tracks of #${e.project.clips.indexOf(now)} are not '
                    'known (the file could not be read), so it uses track 1'
                : '#${e.project.clips.indexOf(now)} has '
                    '${now.audioStreams.length} sound track(s); it uses track '
                    '${now.audioTrackInUse + 1}');
          }
          if (channel != null && now.audioChannelInUse != channel) {
            note('"${channel.name}" only applies to a stereo sound track; '
                'the track #${e.project.clips.indexOf(now)} uses has '
                '${now.audioChannelsInUse == 0 ? 'an unknown number of' : now.audioChannelsInUse} '
                'channel(s), so it stays "both"');
          }
        }
        if (zoom != null) _limited(notes, 'zoom$label', zoom, now.zoom);
        if (brightness != null) _limited(notes, 'brightness$label', brightness, now.brightness);
        if (contrast != null) _limited(notes, 'contrast$label', contrast, now.contrast);
        if (saturation != null) _limited(notes, 'saturation$label', saturation, now.saturation);
        if (transitionMs != null) {
          _limited(notes, 'transition_ms$label', transitionMs, now.transitionMs);
        }
        final index = e.project.clips.indexWhere((c) => c.id == id);
        if (now.transition != TransitionType.none &&
            (a['transition'] != null || transitionMs != null)) {
          if (index == 0) {
            note('a transition on the first clip has no effect (there is no clip before it)');
          } else if (e.project.transitionOverlapMs(index) < now.transitionMs) {
            note('the transition into #$index lasts '
                '${e.project.transitionOverlapMs(index)} ms because it cannot '
                'be longer than half of either clip');
          }
        }
      }
      return _Done(_withNotes(
          all
              ? 'Updated the settings of all ${targets.length} clips.'
              : 'Updated the settings of the clip "${p.basename(targets.first.path)}".',
          notes));
    });
  }

  Future<ToolResult> _removeSilences(Map<String, dynamic> a, ToolCall call) async {
    // Check the request before the (slow) analysis.
    final loaded = await _load(a['project_id']);
    if (a['dry_run'] != true) {
      await _requireClosedInApp(loaded.dir, loaded.project.name);
    }
    final preview = loaded.project;
    if (a['clip_id'] != null) {
      final c = _clip(preview, a['clip_id']);
      if (c.type == ClipType.photo) throw ToolError('That clip is a photo; it has no sound.');
      if (!canRemoveSilences(preview, c)) {
        throw ToolError('That clip has no sound, so there are no silences to find.');
      }
    } else if (!preview.clips.any((c) => canRemoveSilences(preview, c))) {
      throw ToolError('The project has no video clip with sound.');
    }
    final engine = await media.requireEngine();
    final threshold = _d(a, 'threshold_db');
    final used = <String>[];
    final minSilence = _i(a, 'min_silence_ms') ?? 700;

    return _edit(a, (e) async {
      final before = e.project;
      final targets = [
        for (final c in before.clips)
          if (a['clip_id'] != null
              ? c.id == a['clip_id']
              : canRemoveSilences(before, c))
            c,
      ];
      if (targets.isEmpty) throw ToolError('The clip is no longer in the project.');
      final found = <String, List<({int startMs, int endMs})>>{};
      final perClip = <Map<String, dynamic>>[];
      final allCuts = <Map<String, dynamic>>[];
      var total = 0;
      final maxPerMinute = _i(a, 'max_cuts_per_minute');
      var heldBack = 0;
      var analysed = 0;
      for (final clip in targets) {
        if (call.isCancelled) throw ToolError('Cancelled.');
        // What is listened to: the clip's own sound, or the voice(s)
        // recorded separately that are lined up with it (clip_silences).
        final sources = silenceSourcesOf(before, clip);
        final lists = <List<({int startMs, int endMs})>>[];
        for (final source in sources) {
          if (!File(source.path).existsSync()) {
            throw ToolError('A media file of clip ${clip.id} is missing: ${source.path}');
          }
          final key = '${source.path}|${source.audioTrack}|${source.channel.name}';
          var ofFile = found[key];
          if (ofFile == null) {
            call.progress(analysed.toDouble(),
                total: targets.length.toDouble(),
                message: 'Listening to ${p.basename(source.path)}');
            try {
              if (threshold == null) {
                final job = engine.startSilenceDetection(
                    source.path,
                    minSilenceMs: minSilence,
                    audioTrack: source.audioTrack,
                    channel: source.channel);
                ofFile = await job.result;
                final l = job.levels;
                if (l != null) {
                  used.add('${p.basename(source.path)}'
                      '${source.isVoice ? ' (voice recorded separately)' : ''}: '
                      'background ${l.noiseFloorDb.round()} dB, threshold '
                      '${l.hasQuietParts ? '${l.autoThresholdDb.round()} dB' : 'none (no quiet parts)'}');
                }
              } else {
                ofFile = await engine.detectSilence(source.path,
                    thresholdDb: threshold,
                    minSilenceMs: minSilence,
                    audioTrack: source.audioTrack,
                    channel: source.channel);
              }
            } on ExportException catch (ex) {
              throw ToolError('The sound of "${source.path}" could not be analysed: ${ex.message}');
            }
            found[key] = ofFile;
          }
          lists.add(silencesInClipTime(source, ofFile, clip.inMs, clip.outMs));
        }
        // The clip's own sound alone: exactly as before 1.10.
        final own = sources.length == 1 && !sources.single.isVoice
            ? sources.single
            : null;
        final silences = own != null
            ? found['${own.path}|${own.audioTrack}|${own.channel.name}']!
            : silentInAll(lists, minMs: minSilence);
        analysed++;
        var cuts = silencesToCut(clip, silences);
        if (maxPerMinute != null && cuts.isNotEmpty) {
          // Guard rail: at most this many cuts a minute, the longest
          // pauses first.
          final room = (clip.durationMs / 60000 * maxPerMinute).ceil();
          final keep = room < 1 ? 1 : room;
          if (cuts.length > keep) {
            heldBack += cuts.length - keep;
            final longest = [...cuts]
              ..sort((x, y) => (y.endMs - y.startMs).compareTo(x.endMs - x.startMs));
            cuts = longest.take(keep).toList()
              ..sort((x, y) => x.startMs.compareTo(y.startMs));
          }
        }
        final index = before.clips.indexWhere((c) => c.id == clip.id);
        for (final c in cuts) {
          allCuts.add({
            'clipId': clip.id,
            'clipIndex': index,
            'sourceStartMs': c.startMs,
            'sourceEndMs': c.endMs,
            'timelineStartMs': before.clipStartMs(index) +
                ((c.startMs - clip.inMs) / clip.speed).round(),
            'removedMs': ((c.endMs - c.startMs) / clip.speed).round(),
          });
        }
        final removed = cuts.isEmpty ? 0 : e.removeSourceRanges(clip.id, cuts);
        // Remembered in the project, so each can be listed and put back
        // (list_auto_cuts, restore_cut).
        if (removed > 0) {
          logSilenceCuts(e, clip.path, cuts, by: 'claude', newId: _newId);
        }
        total += removed;
        perClip.add({'clipId': clip.id, 'file': p.basename(clip.path), 'gapsRemoved': removed});
      }
      final saved = before.durationMs - e.project.durationMs;
      final dryRun = a['dry_run'] == true;
      final perMinute = before.durationMs <= 0
          ? 0.0
          : total / (before.durationMs / 60000);
      final extra = {
        'gapsRemoved': total,
        'removedMs': saved,
        'cutsPerMinute': double.parse(perMinute.toStringAsFixed(1)),
        if (heldBack > 0) 'heldBackByMaxPerMinute': heldBack,
        'clips': perClip.length > 40 ? perClip.take(40).toList() : perClip,
        if (perClip.length > 40) 'clipsOmitted': perClip.length - 40,
        'threshold': threshold ?? 'auto',
        // Every cut ONCE, here (the text only shows the first few).
        'cuts': allCuts.take(300).toList(),
        if (allCuts.length > 300) 'cutsOmitted': allCuts.length - 300,
      };
      final listing = !dryRun || allCuts.isEmpty
          ? ''
          : '\nFirst cuts (timeline position now, length; all of them are in '
              'the structured "cuts"): ${[
              for (final c in allCuts.take(8))
                '${clock(c['timelineStartMs'] as int)} -${c['removedMs']} ms',
            ].join(', ')}${allCuts.length > 8 ? ', … ${allCuts.length - 8} more' : ''}.';
      final pace = ' That is ${perMinute.toStringAsFixed(1)} cut(s) a minute'
          '${perMinute > kCutBudgetPerMinute ? ' - a lot for a video where the speaker is seen: it can look jumpy. Consider a longer min_silence_ms or max_cuts_per_minute ${kCutBudgetPerMinute.round()}, and tell the user the number' : ''}.'
          '${heldBack > 0 ? ' $heldBack shorter pause(s) were left in (max_cuts_per_minute).' : ''}';
      final how = threshold != null
          ? 'threshold $threshold dB'
          : 'automatic threshold${used.isEmpty ? '' : ': ${used.join('; ')}'}';
      if (total == 0) {
        return _Done(
            'No silent gaps were found ($how, at least $minSilence ms).',
            extra);
      }
      return _Done(
          '${dryRun ? 'Would remove' : 'Removed'} $total silent gap(s): the video '
          '${dryRun ? 'would be' : 'is'} $saved ms (${clock(saved)}) shorter '
          '(${before.durationMs} -> ${e.project.durationMs} ms) and '
          '${dryRun ? 'would have' : 'has'} ${e.project.clips.length} clips'
          '${dryRun ? '' : ' now'}.'
          '${e.project.titles.isEmpty ? '' : ' Titles and captions moved with their picture.'}'
          '${e.project.audio.any((x) => !x.linked) ? ' Music was NOT moved; check that it still fits.' : ''}'
          '${e.project.audio.any((x) => x.linked) ? ' Separated sound followed its clips.' : ''}'
          '$pace ($how.)$listing',
          extra);
    });
  }

  Future<ToolResult> _addTitle(Map<String, dynamic> a, ToolCall call) {
    final text = a['text'] as String;
    if (text.trim().isEmpty) throw ToolError('The text is empty.');
    final times = _titleTimes(a, kDefaultTitleMs);
    final color = a['color'] == null ? null : _color(a['color']);
    return _edit(a, (e) {
      final before = {for (final t in e.project.titles) t.id};
      var title = _titleStyle(
          TitleOverlay(
              id: _newId(), text: text, startMs: times.start, endMs: times.end),
          a);
      title = title.copyWith(
        x: _d(a, 'x'),
        y: _d(a, 'y'),
        fontSize: _d(a, 'font_size'),
        colorArgb: color,
        bold: a['bold'] as bool?,
        background: a['background'] as bool?,
      );
      e.addTitle(title);
      final added = e.project.titles.firstWhere((t) => !before.contains(t.id));
      return _Done(
          _withNotes('Added the title (title_id ${added.id}), shown '
              '${added.startMs}–${added.endMs} ms.', _pastEnd(e.project, [added])),
          {'titleId': added.id});
    });
  }

  Future<ToolResult> _addCaption(Map<String, dynamic> a, ToolCall call) {
    final text = a['text'] as String;
    if (text.trim().isEmpty) throw ToolError('The text is empty.');
    final times = _titleTimes(a, kDefaultCaptionMs);
    return _edit(a, (e) {
      final before = {for (final t in e.project.titles) t.id};
      e.addTitle(captionStyle(TitleOverlay(
          id: _newId(), text: text, startMs: times.start, endMs: times.end)));
      final added = e.project.titles.firstWhere((t) => !before.contains(t.id));
      return _Done(
          _withNotes('Added the caption (title_id ${added.id}), shown '
              '${added.startMs}–${added.endMs} ms.', _pastEnd(e.project, [added])),
          {'titleId': added.id});
    });
  }

  static List<String> _pastEnd(Project project, List<TitleOverlay> titles) {
    final late = titles.where((t) => t.startMs >= project.durationMs).length;
    if (late == 0) return const [];
    return [
      '${titles.length == 1 ? 'it starts' : '$late of them start'} at or '
          'after the end of the video (${project.durationMs} ms) and will '
          'not be visible',
    ];
  }

  Future<ToolResult> _importSrt(Map<String, dynamic> a, ToolCall call) async {
    final hasPath = a['path'] != null;
    final hasText = a['srt_text'] != null;
    if (hasPath == hasText) {
      throw ToolError('Give either path (an .srt file) or srt_text (its contents).');
    }
    String content;
    if (hasPath) {
      final path = _existingFile(a['path'], 'path');
      try {
        content = await File(path).readAsString();
      } on FileSystemException catch (e) {
        throw ToolError('"$path" could not be read as text (${e.message}). '
            'Subtitle files must be saved as UTF-8.');
      }
    } else {
      content = a['srt_text'] as String;
    }
    final offset = _i(a, 'offset_ms') ?? 0;
    var cues = parseSrt(content, newId: _newId);
    if (cues.isEmpty) {
      throw ToolError('No subtitles were found in that ${hasPath ? 'file' : 'text'}. '
          'It must be in SubRip format, for example:\n1\n00:00:01,000 --> '
          '00:00:03,500\nHello');
    }
    if (offset != 0) {
      cues = [
        for (final c in cues)
          if (c.endMs + offset > 0)
            c.copyWith(
                startMs: c.startMs + offset < 0 ? 0 : c.startMs + offset,
                endMs: c.endMs + offset),
      ];
    }
    final fromSource = a['time_base'] == 'source';
    if (!fromSource && a['source_clip_id'] != null) {
      throw ToolError('source_clip_id only applies with time_base "source".');
    }
    // Subtitles this server exported earlier: do their times fit?
    final origin = _srtOrigin(content);
    String? originNote(Project project) {
      if (origin == null) return null;
      final base = origin['timeBase'];
      final same = origin['projectId'] == project.id;
      final where = same ? 'this project' : 'the project "${origin['projectName']}"';
      if (base == 'source' && !fromSource) {
        return 'WARNING: this file was exported from $where with SOURCE times '
            '(export_srt time_base "source"), but was imported as timeline '
            'times; undo and import it with time_base "source"';
      }
      if (base == 'timeline' && fromSource) {
        return 'WARNING: this file was exported from $where with TIMELINE '
            'times, but was imported as source times; undo and import it '
            'with time_base "timeline"';
      }
      if (base == 'timeline' && origin['timeline'] != timelineKey(project)) {
        return 'WARNING: this file was exported from $where with timeline '
            'times when the video was cut differently (at ${origin['at']}), '
            'so its times may not match the picture any more; next time '
            'export with time_base "source", which survives re-cutting';
      }
      return null;
    }
    return _edit(a, (e) {
      final project = e.project;
      var captions = cues;
      var dropped = 0;
      String? sourceFile;
      if (fromSource) {
        sourceFile = _sourceFile(project, a['source_clip_id']);
        final placed =
            captionsFromSourceTimes(project, sourceFile, cues, newId: _newId);
        captions = placed.titles;
        dropped = placed.dropped;
        if (captions.isEmpty) {
          throw ToolError('None of the ${cues.length} subtitles falls in a '
              'part of "${p.basename(sourceFile)}" that is still on the timeline.');
        }
      }
      var replaced = 0;
      if (a['replace_existing_captions'] == true) {
        for (final t in project.titles) {
          if (t.kind == TitleKind.caption) {
            e.removeTitle(t.id);
            replaced++;
          }
        }
      }
      final before = {for (final t in e.project.titles) t.id};
      e.addTitles(captions);
      final added = [
        for (final t in e.project.titles)
          if (!before.contains(t.id)) t,
      ];
      final notes = [
        ?originNote(e.project),
        if (replaced > 0) '$replaced earlier caption(s) were removed first',
        if (fromSource)
          'times were taken as positions in "${p.basename(sourceFile!)}" and '
              'moved to where those moments play now',
        if (dropped > 0) '$dropped subtitle(s) were left out because their part of the recording is not on the timeline',
        ..._pastEnd(e.project, added),
      ];
      final origin = originNote(e.project);
      return _Done(
          _withNotes('Imported ${added.length} caption(s) from ${cues.length} subtitle(s).', notes),
          {
            // Also where warnings belong, not only in the sentence.
            if (origin != null) '_warnings': [origin],
            'captionsAdded': added.length,
            'cuesInFile': cues.length,
            'cuesDropped': dropped,
            'captionsReplaced': replaced,
          },
          true);
    });
  }

  /// The one video file of [project] (or of [clipId]) that source times
  /// refer to.
  static String _sourceFile(Project project, Object? clipId) {
    if (clipId != null) {
      final clip = _clip(project, clipId);
      if (clip.type != ClipType.video) throw ToolError('source_clip_id is a photo.');
      return clip.path;
    }
    final files = <String>[];
    for (final c in project.clips) {
      if (c.type == ClipType.video && !files.any((f) => p.equals(f, c.path))) {
        files.add(c.path);
      }
    }
    if (files.isEmpty) {
      throw ToolError('time_base "source" needs a video clip in the project.');
    }
    if (files.length > 1) {
      throw ToolError('The project uses ${files.length} video files '
          '(${files.map(p.basename).join(', ')}). Say which one the '
          'subtitles belong to with source_clip_id.');
    }
    return files.single;
  }

  File get _srtRegistry => File(p.join(jobs.dir, 'srt-exports.json'));

  /// Remembers that [srt] was exported from [project] with [timeBase].
  void _rememberSrt(String srt, Project project, String timeBase, String? source) {
    try {
      var list = <dynamic>[];
      if (_srtRegistry.existsSync()) {
        list = jsonDecode(_srtRegistry.readAsStringSync()) as List;
      }
      list.add({
        'hash': _srtKey(srt),
        'projectId': project.id,
        'projectName': project.name,
        'timeBase': timeBase,
        'source': ?source,
        'timeline': timelineKey(project),
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      if (list.length > 100) list = list.sublist(list.length - 100);
      _srtRegistry.parent.createSync(recursive: true);
      _srtRegistry.writeAsStringSync(jsonEncode(list));
    } catch (_) {}
  }

  /// What is known about where [srt] came from (an export_srt of this
  /// server), or null.
  Map<String, dynamic>? _srtOrigin(String srt) {
    try {
      if (!_srtRegistry.existsSync()) return null;
      final key = _srtKey(srt);
      final list = jsonDecode(_srtRegistry.readAsStringSync()) as List;
      for (final e in list.reversed) {
        if (e is Map && e['hash'] == key) return e.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  Future<ToolResult> _exportSrt(Map<String, dynamic> a, ToolCall call) async {
    final project = (await _load(a['project_id'])).project;
    final fromSource = a['time_base'] == 'source';
    if (!fromSource && a['source_clip_id'] != null) {
      throw ToolError('source_clip_id only applies with time_base "source".');
    }
    var captions = [
      for (final t in project.titles)
        if (t.kind == TitleKind.caption) t,
    ];
    String? sourceFile;
    var skipped = 0;
    if (fromSource && captions.isNotEmpty) {
      sourceFile = _sourceFile(project, a['source_clip_id']);
      final r = captionsToSourceTimes(project, sourceFile, captions);
      captions = r.titles;
      skipped = r.skipped;
    }
    final srt = toSrt(captions);
    if (srt.isEmpty) {
      throw ToolError(skipped > 0
          ? 'None of the captions is over a part of "${p.basename(sourceFile!)}".'
          : 'The project "${project.name}" has no captions to export.');
    }
    final count =
        RegExp(r'^\d+\n\d\d:', multiLine: true).allMatches(srt).length;
    String? written;
    if (a['path'] != null) {
      var path = _path(a['path'], 'path');
      if (p.extension(path).isEmpty) path = '$path.srt';
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound &&
          a['overwrite'] != true) {
        throw ToolError('"$path" already exists. Choose another name or pass overwrite true.');
      }
      try {
        await Directory(p.dirname(path)).create(recursive: true);
        await File(path).writeAsString(srt, flush: true);
      } on FileSystemException catch (e) {
        throw ToolError('The subtitles could not be written to "$path": ${e.message}');
      }
      written = path;
    }
    _rememberSrt(srt, project, fromSource ? 'source' : 'timeline', sourceFile);
    final about = fromSource
        ? 'Times are positions in "${p.basename(sourceFile!)}" (import them '
            'again with import_srt time_base "source")'
            '${skipped > 0 ? '; $skipped caption(s) over other files were left out' : ''}.'
        : 'Times are positions in the video as it is cut now; after re-cutting, '
            'export with time_base "source" instead.';
    return ToolResult(
        '${written == null ? '' : 'Saved $count caption(s) to $written.\n\n'}$srt\n$about'.trimRight(),
        structured: {
          'projectId': project.id,
          'captionCount': count,
          'timeBase': fromSource ? 'source' : 'timeline',
          'sourceFile': ?sourceFile,
          if (skipped > 0) 'captionsSkipped': skipped,
          'path': written,
          'srt': srt,
        });
  }

  Future<ToolResult> _updateTitle(Map<String, dynamic> a, ToolCall call) {
    const fields = [
      'text', 'start_ms', 'end_ms', 'x', 'y', 'font_size', 'color', 'bold',
      'background', ..._titleStyleKeys, //
    ];
    if (!fields.any((f) => a[f] != null)) {
      throw ToolError('Give at least one thing to change: ${fields.join(', ')}.');
    }
    final color = a['color'] == null ? null : _color(a['color']);
    return _edit(a, (e) {
      final t = _title(e.project, a['title_id']);
      final start = _i(a, 'start_ms') ?? t.startMs;
      final end = _i(a, 'end_ms') ?? t.endMs;
      if (end <= start) {
        throw ToolError('The end ($end ms) must be after the start ($start ms). '
            'Give both start_ms and end_ms to move a title.');
      }
      final text = a['text'] as String?;
      if (text != null && text.trim().isEmpty) {
        throw ToolError('The text is empty (use remove_title to delete it).');
      }
      e.updateTitle(_titleStyle(t, a).copyWith(
        text: text,
        startMs: start,
        endMs: end,
        x: _d(a, 'x'),
        y: _d(a, 'y'),
        fontSize: _d(a, 'font_size'),
        colorArgb: color,
        bold: a['bold'] as bool?,
        background: a['background'] as bool?,
      ));
      final now = _title(e.project, t.id);
      return _Done(_withNotes(
          'Updated the ${now.kind.name} (title_id ${now.id}), shown '
          '${now.startMs}–${now.endMs} ms.',
          _pastEnd(e.project, [now])));
    });
  }

  Future<ToolResult> _removeTitle(Map<String, dynamic> a, ToolCall call) {
    final all = a['all_captions'] == true;
    if (all == (a['title_id'] != null)) {
      throw ToolError('Give either title_id or all_captions true.');
    }
    return _edit(a, (e) {
      if (all) {
        final captions = [
          for (final t in e.project.titles)
            if (t.kind == TitleKind.caption) t.id,
        ];
        captions.forEach(e.removeTitle);
        return _Done('Removed ${captions.length} caption(s).',
            {'removed': captions.length}, true);
      }
      final t = _title(e.project, a['title_id']);
      e.removeTitle(t.id);
      return _Done('Removed the ${t.kind.name} "${t.text.replaceAll('\n', ' / ')}".',
          {'removed': 1}, true);
    });
  }

  Future<ToolResult> _updateAudio(Map<String, dynamic> a, ToolCall call) {
    const fields = [
      'start_ms', 'in_ms', 'out_ms', 'volume', 'fade_in_ms', 'fade_out_ms', //
      'denoise', 'voice_focus',
    ];
    if (!fields.any((f) => a[f] != null)) {
      throw ToolError('Give at least one thing to change: ${fields.join(', ')}.');
    }
    return _edit(a, (e) {
      final audio = _audio(e.project, a['audio_id']);
      final inMs = _i(a, 'in_ms') ?? audio.inMs;
      final outMs = _i(a, 'out_ms') ?? audio.outMs;
      if (outMs <= inMs) {
        throw ToolError('out_ms ($outMs) must be after in_ms ($inMs).');
      }
      e.transaction(() {
        e.updateAudio(audio.copyWith(
          startMs: _i(a, 'start_ms'),
          inMs: inMs,
          outMs: outMs,
          volume: _d(a, 'volume'),
          fadeInMs: _i(a, 'fade_in_ms'),
          fadeOutMs: _i(a, 'fade_out_ms'),
        ));
        final denoise = a['denoise'] as bool?;
        if (denoise != null) e.setAudioDenoise(audio.id, denoise);
        final focus = _d(a, 'voice_focus');
        if (focus != null) e.setAudioVoiceFocus(audio.id, focus);
      });
      final now = _audio(e.project, audio.id);
      final notes = <String>[];
      if (a['in_ms'] != null) _limited(notes, 'in_ms', inMs, now.inMs);
      if (a['out_ms'] != null) _limited(notes, 'out_ms', outMs, now.outMs);
      if (a['volume'] != null) _limited(notes, 'volume', _d(a, 'volume')!, now.volume);
      if (a['fade_in_ms'] != null) _limited(notes, 'fade_in_ms', _i(a, 'fade_in_ms')!, now.fadeInMs);
      if (a['fade_out_ms'] != null) _limited(notes, 'fade_out_ms', _i(a, 'fade_out_ms')!, now.fadeOutMs);
      return _Done(_withNotes(
          'Updated "${p.basename(now.path)}": plays ${now.startMs}–${now.endMs} ms '
          'on the timeline.',
          notes));
    });
  }

  /// A track for new sound: an existing one by id or name, else a new one
  /// with that name when there is room.
  String _trackOrNew(ProjectEditor e, Object? raw) {
    try {
      return _track(e.project, raw).id;
    } on ToolError {
      final name = '$raw'.trim();
      if (name.isEmpty ||
          e.project.soundTracks.length >= ProjectEditor.maxSoundTracks) {
        rethrow;
      }
      return e.addSoundTrack(name: name)!;
    }
  }

  Future<ToolResult> _listSoundTracks(Map<String, dynamic> a, ToolCall call) async {
    final project = (await _load(a['project_id'])).project;
    final lines = <String>[
      'Video sound (track_id video): volume ${project.videoSound.volume}'
          '${project.videoSound.muted ? ', muted' : ''}'
          '${project.videoSound.solo ? ', solo' : ''}.',
      for (final t in project.soundTracks)
        '"${t.name}" (track_id ${t.id}): volume ${t.volume}'
            '${t.muted ? ', muted' : ''}${t.solo ? ', solo' : ''}'
            '${t.duck ? ', lowered under speech' : ''}'
            '${t.speech ? ', counts as speech' : ''}; '
            '${project.clipsOnTrack(t.id).length} item(s).',
    ];
    return ToolResult(
      project.soundTracks.isEmpty
          ? '${lines.first} No sound tracks yet.'
          : lines.join('\n'),
      structured: {
        'videoSound': trackJson(project, project.videoSound),
        'soundTracks': [
          for (final t in project.soundTracks) trackJson(project, t),
        ],
      },
    );
  }

  Future<ToolResult> _updateSoundTrack(Map<String, dynamic> a, ToolCall call) {
    const fields = ['name', 'volume', 'muted', 'solo', 'duck_under_speech', 'speech'];
    if (!fields.any((f) => a[f] != null)) {
      throw ToolError('Give at least one thing to change: ${fields.join(', ')}.');
    }
    return _edit(a, (e) {
      final t = _track(e.project, a['track_id'], video: true);
      final video = t.id == SoundTrack.videoId;
      if (video && (a['name'] != null || a['duck_under_speech'] != null || a['speech'] != null)) {
        throw ToolError('The video\'s own sound has only volume, muted and solo.');
      }
      e.transaction(() {
        final name = a['name'] as String?;
        if (name != null) {
          if (name.trim().isEmpty) throw ToolError('The new name is empty.');
          e.renameSoundTrack(t.id, name);
        }
        e.setSoundTrack(t.id,
            volume: _d(a, 'volume'),
            muted: a['muted'] as bool?,
            solo: a['solo'] as bool?,
            duck: a['duck_under_speech'] as bool?,
            speech: a['speech'] as bool?);
      });
      final now = e.project.trackById(t.id)!;
      return _Done(
          'The ${video ? 'video sound' : 'sound track "${now.name}"'} now: '
          'volume ${now.volume}${now.muted ? ', muted' : ''}'
          '${now.solo ? ', solo' : ''}'
          '${!video && now.duck ? ', lowered under speech' : ''}'
          '${!video && now.speech ? ', counts as speech' : ''}'
          '${e.project.trackGain(now) == 0 ? ' (not heard)' : ''}.',
          {'track': trackJson(e.project, now)});
    });
  }

  Future<ToolResult> _separateSound(Map<String, dynamic> a, ToolCall call) {
    final all = a['all'] == true;
    if (all == (a['clip_id'] != null)) {
      throw ToolError('Give either clip_id or all true.');
    }
    return _edit(a, (e) {
      final track = a['track_id'] == null ? null : _trackOrNew(e, a['track_id']);
      final before = {for (final x in e.project.audio) x.id};
      if (all) {
        final n = e.separateAllSound(trackId: track);
        if (n == 0) {
          throw ToolError('No clip has sound left to separate (photos and '
              'clips without sound are skipped; separated clips are muted).');
        }
      } else {
        final c = _clip(e.project, a['clip_id']);
        final problem = ProjectEditor.separateSoundProblem(e.project, c.id);
        if (problem != null) throw ToolError(problem);
        e.separateSound(c.id, trackId: track);
      }
      final added = [
        for (final x in e.project.audio)
          if (!before.contains(x.id)) x,
      ];
      final tracks = {
        for (final x in added) e.project.trackById(x.trackId)!.name,
      };
      return _Done(
          'Separated the sound of ${added.length} clip(s) onto the '
          '${tracks.map((t) => '"$t"').join(' and ')} track; the clip(s) are '
          'muted. The sound follows its clip until it is moved or trimmed '
          'itself.',
          {
            'audioIds': [for (final x in added) x.id],
            'trackIds': {for (final x in added) x.trackId}.toList(),
          });
    });
  }

  /// The video clips a voice can be compared with: one per video file
  /// with sound, or just [only].
  List<Clip> _alignCandidates(Project project, Clip? only) {
    if (only != null) return [only];
    final seen = <String>{};
    return [
      for (final c in project.clips)
        if (c.type == ClipType.video && c.hasAudio && seen.add(c.path)) c,
    ];
  }

  /// Compares [voicePath] with the sound of [candidates]; the best match.
  Future<({Clip clip, AlignResult result})?> _bestAlign(
      List<Clip> candidates, String voicePath, int voiceTrack, ToolCall call) async {
    final engine = await media.requireEngine();
    ({Clip clip, AlignResult result})? best;
    var done = 0;
    for (final c in candidates) {
      if (call.isCancelled) throw ToolError('Cancelled.');
      if (!c.hasAudio) continue;
      if (!File(c.path).existsSync()) {
        throw ToolError('The media file of clip ${c.id} is missing: ${c.path}');
      }
      call.progress(done.toDouble(),
          total: candidates.length.toDouble(),
          message: 'Comparing with the sound of ${p.basename(c.path)}');
      AlignResult r;
      try {
        r = await engine.alignSound(c.path, voicePath,
            videoAudioTrack: c.audioTrackInUse, voiceAudioTrack: voiceTrack);
      } on ExportException catch (e) {
        r = AlignResult.none(e.message);
      }
      done++;
      if (best == null || r.confidence > best.result.confidence) {
        best = (clip: c, result: r);
      }
    }
    return best;
  }

  Map<String, dynamic> _alignJson(AlignResult? r, {required bool linedUp}) => {
        'lined_up': linedUp,
        'confidence': r == null ? 0 : double.parse(r.confidence.toStringAsFixed(2)),
        'drift_ms': r == null || !linedUp ? 0 : r.driftMs,
        if (r?.reason != null) 'reason': r!.reason,
      };

  String _driftWarning(AlignResult r) =>
      'The two recordings drift apart by about ${r.driftMs.abs()} ms over '
      'the part they share (their clocks differ). The offset is the best '
      'single one; the voice can be up to ${(r.driftMs.abs() / 2).round()} ms '
      'early at one end and late at the other. ClipForge does not stretch '
      'sound to repair this.';

  Future<ToolResult> _addVoice(Map<String, dynamic> a, ToolCall call) async {
    final path = _existingFile(a['path'], 'path');
    final engine = await media.requireEngine();
    final MediaInfo info;
    try {
      info = await engine.probe(path);
    } on ExportException catch (e) {
      throw ToolError('"$path" could not be read as media (${e.message}).');
    }
    if (!info.hasAudio || info.durationMs <= 0) {
      throw ToolError('No sound was found in "$path".');
    }
    // Check the request and listen before the project is changed.
    final loaded = await _load(a['project_id']);
    if (a['dry_run'] != true) {
      await _requireClosedInApp(loaded.dir, loaded.project.name);
    }
    final project = loaded.project;
    final given = a['clip_id'] == null ? null : _clip(project, a['clip_id']);
    if (given != null && given.type != ClipType.video) {
      throw ToolError('That clip is a photo; a voice is lined up with a video clip.');
    }
    final videos = [
      for (final c in project.clips)
        if (c.type == ClipType.video) c,
    ];
    if (videos.isEmpty) {
      throw ToolError('The project has no video clip yet. Add the video '
          'first (add_media), then its voice.');
    }
    final align = a['align'] != false;
    ({Clip clip, AlignResult result})? best;
    if (align) {
      best = await _bestAlign(_alignCandidates(project, given), path, 0, call);
    }
    final matched = best != null && best.result.matched;
    final warnings = <String>[];
    return _edit(a, (e) {
      final wanted = matched ? best!.clip : (given ?? videos.first);
      final target = e.project.clips.where((c) => c.id == wanted.id).firstOrNull;
      if (target == null) throw ToolError('The clip is no longer in the project.');
      final manual = _i(a, 'offset_ms');
      final offset = matched
          ? best!.result.offsetMs
          : (!align && manual != null ? manual : -target.inMs);
      final placedByHand = !align && manual != null;
      final mute = (matched || placedByHand) && a['mute_clip'] != false;
      final name = (a['track_name'] as String?)?.trim();
      final List<String> ids;
      try {
        ids = e.addVoice(
          AudioClip(
            id: _newId(),
            path: path,
            sourceDurationMs: info.durationMs,
            startMs: 0,
            inMs: 0,
            outMs: info.durationMs,
            volume: _d(a, 'volume') ?? 1.0,
            audioStreams: info.audioStreams,
          ),
          clipId: target.id,
          offsetMs: offset,
          trackName: name == null || name.isEmpty
              ? speakerNameFromFile(path)
              : name,
          muteClips: mute,
          linedUp: matched || placedByHand,
        );
      } on VoiceProblem catch (problem) {
        throw ToolError(problem.message);
      }
      final first = e.project.audio.firstWhere((x) => x.id == ids.first);
      final track = e.project.trackById(first.trackId)!;
      final n = e.project.clips.indexWhere((c) => c.id == target.id);
      if (align && !matched) {
        final why = best?.result.reason ??
            (best == null
                ? 'no video clip has sound to compare with'
                : 'the sounds do not match (confidence '
                    '${best.result.confidence.toStringAsFixed(2)})');
        warnings.add('Could not line it up automatically: $why. The voice '
            'file starts where clip #$n starts and the camera\'s own sound '
            'was left on. Find the offset by ear or from a clap and set it '
            'with align_audio offset_ms (or nudge_ms), then mute the camera '
            'with align_audio mute_clip true.');
      }
      if (matched && best!.result.drifts) warnings.add(_driftWarning(best.result));
      if (matched && given == null && _alignCandidates(project, null).length > 1) {
        warnings.add('Several video files were compared; '
            '"${p.basename(target.path)}" matched best.');
      }
      final covered = ids.length;
      final label = ProjectEditor.offsetLabel(offset).replaceAll('\u2212', '-');
      return _Done(
          _withNotes(
              '${matched ? 'Added and lined up' : 'Added'} '
              '"${p.basename(path)}" as the voice for clip #$n '
              '(clip_id ${target.id}): offset $offset ms ($label)'
              '${matched ? ', confidence ${best!.result.confidence.toStringAsFixed(2)}' : ''}. '
              '$covered linked item(s) on the speech track "${track.name}" '
              '(track_id ${track.id}); they follow their clips through '
              'edits.${mute ? ' The camera\'s own sound of those clips is muted.' : ''}',
              warnings),
          {
            'audioIds': ids,
            'trackId': track.id,
            'clipId': target.id,
            'offset_ms': offset,
            ..._alignJson(best?.result, linedUp: matched),
            'cameraMuted': mute,
            'warnings': warnings,
          });
    });
  }

  Future<ToolResult> _alignAudio(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    if (a['dry_run'] != true) {
      await _requireClosedInApp(loaded.dir, loaded.project.name);
    }
    final project = loaded.project;
    final audio = _audio(project, a['audio_id']);
    if (audio.isSeparated) {
      throw ToolError('That item is a clip\'s own sound (separate_sound); it '
          'is in sync by itself. Use reattach_sound to put it back.');
    }
    final given = a['clip_id'] == null ? null : _clip(project, a['clip_id']);
    if (given != null && given.type != ClipType.video) {
      throw ToolError('That clip is a photo; a voice is lined up with a video clip.');
    }
    final manual = _i(a, 'offset_ms');
    final nudge = _i(a, 'nudge_ms');
    final unlink = a['link'] == false;
    final mute = a['mute_clip'] as bool?;
    if ([manual != null, nudge != null, unlink].where((x) => x).length > 1) {
      throw ToolError('Give only one of offset_ms, nudge_ms and link false.');
    }
    final linkedClip = project.clips
        .where((c) => c.id == audio.sourceClipId)
        .firstOrNull;

    // Things that need no listening.
    if (unlink || nudge != null) {
      return _edit(a, (e) {
        if (!audio.isVoice || !audio.linked) {
          throw ToolError('That item is not a linked voice, so there is '
              'nothing to ${unlink ? 'unlink' : 'nudge'}. Line it up first '
              '(align_audio without nudge_ms).');
        }
        if (unlink) {
          e.unlinkVoice(audio.id, unmuteClips: mute == false);
          return _Done(
              'The voice is no longer linked to the video: it stays where '
              'it is and no longer follows its clips.'
              '${mute == false ? ' The camera\'s own sound is back on.' : ''}',
              {'audioId': audio.id, 'linked': false});
        }
        e.nudgeVoice(audio.id, nudge!);
        if (mute != null) e.setVoiceClipsMuted(audio.id, mute);
        final now = e.project.audio.where((x) => x.id == audio.id).firstOrNull;
        if (now == null) {
          throw ToolError('With that nudge the voice file has no sound left '
              'for the clip.');
        }
        return _Done(
            'Nudged the voice ${nudge.abs()} ms '
            '${nudge > 0 ? 'later' : 'earlier'}: offset ${now.syncOffsetMs} ms.',
            {'audioId': audio.id, 'offset_ms': now.syncOffsetMs});
      });
    }

    ({Clip clip, AlignResult result})? best;
    if (manual == null) {
      if (!File(audio.path).existsSync()) {
        throw ToolError('The sound file is missing: ${audio.path}');
      }
      best = await _bestAlign(_alignCandidates(project, given), audio.path,
          audio.soundClip.audioTrackInUse, call);
      if (best == null || !best.result.matched) {
        final why = best?.result.reason ??
            (best == null
                ? 'no video clip has sound to compare with'
                : 'the sounds do not match (confidence '
                    '${best.result.confidence.toStringAsFixed(2)})');
        // Only the camera switch may still be wanted.
        if (mute != null && audio.isVoice) {
          return _edit(a, (e) {
            e.setVoiceClipsMuted(audio.id, mute);
            return _Done(
                'Could not line it up automatically: $why. The offset was '
                'left as it is; the camera\'s own sound is now '
                '${mute ? 'muted' : 'on'}.',
                {'audioId': audio.id, ..._alignJson(best?.result, linedUp: false)});
          });
        }
        return ToolResult(
            'Could not line it up automatically: $why. Nothing was changed. '
            'Set the offset by hand with offset_ms (time in the sound file = '
            'time in the video file + offset_ms), e.g. from a clap or a '
            'word visible on the lips.',
            structured: {
              'audioId': audio.id,
              ..._alignJson(best?.result, linedUp: false),
              'warnings': ['not lined up: $why'],
            });
      }
    }
    final warnings = <String>[];
    return _edit(a, (e) {
      final wanted = best?.clip ?? given ?? linkedClip ??
          project.clips.where((c) => c.type == ClipType.video).firstOrNull;
      final target = wanted == null
          ? null
          : e.project.clips.where((c) => c.id == wanted.id).firstOrNull;
      if (target == null) {
        throw ToolError('There is no video clip to link it to; give clip_id.');
      }
      final offset = manual ?? best!.result.offsetMs;
      final List<String> ids;
      try {
        ids = e.linkVoice(audio.id,
            clipId: target.id,
            offsetMs: offset,
            trackName: speakerNameFromFile(audio.path),
            muteClips: mute ?? (audio.isVoice ? null : true));
      } on VoiceProblem catch (problem) {
        throw ToolError(problem.message);
      }
      final first = e.project.audio.firstWhere((x) => x.id == ids.first);
      final track = e.project.trackById(first.trackId)!;
      final n = e.project.clips.indexWhere((c) => c.id == target.id);
      if (best != null && best.result.drifts) {
        warnings.add(_driftWarning(best.result));
      }
      final muted = e.project.clips[n].muted;
      return _Done(
          _withNotes(
              '${manual != null ? 'Linked' : 'Lined up'} '
              '"${p.basename(audio.path)}" with clip #$n (clip_id '
              '${target.id}): offset $offset ms'
              '${best != null ? ', confidence ${best.result.confidence.toStringAsFixed(2)}' : ''}. '
              '${ids.length} linked item(s) on the track "${track.name}" '
              '(the audio_id changed: see audioIds). The camera\'s own sound '
              'of those clips is ${muted ? 'muted' : 'on'}.',
              warnings),
          {
            'audioIds': ids,
            'trackId': track.id,
            'clipId': target.id,
            'offset_ms': offset,
            ..._alignJson(best?.result, linedUp: true),
            'cameraMuted': muted,
            'warnings': warnings,
          });
    });
  }

  Future<ToolResult> _relinkMedia(Map<String, dynamic> a, ToolCall call) {
    final newPath = _existingFile(a['new_path'], 'new_path');
    final wanted = (a['old_path'] as String).trim();
    return _edit(a, (e) {
      // Accept the path as stored, or one that differs only in spelling
      // (slashes, upper / lower case on Windows).
      final stored = <String>{
        for (final c in e.project.clips) c.path,
        for (final x in e.project.audio) x.path,
      };
      final matches = [
        for (final s in stored)
          if (s == wanted || p.equals(s, wanted)) s,
      ];
      if (matches.isEmpty) {
        throw ToolError('Nothing in this project uses the file "$wanted". '
            'Files in use: ${stored.isEmpty ? 'none' : stored.join('; ')}.');
      }
      var items = 0;
      for (final old in matches) {
        items += e.project.clips.where((c) => c.path == old).length +
            e.project.audio.where((x) => x.path == old).length;
        e.relinkMedia(old, newPath);
      }
      return _Done('$items item(s) now use "$newPath".', {'itemsRelinked': items});
    });
  }

  /// A file named after the project in [dir] (default: the "exports" folder
  /// next to the projects folder) that does not exist yet.
  String _defaultExportPath(Project project, [String? dir]) {
    var name = project.name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'ClipForge video';
    dir ??= p.join(p.dirname(store.rootPath), 'exports');
    final running = [
      for (final r in jobs.list())
        if (r.isActive) r.outputPath,
    ];
    bool taken(String path) =>
        FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound ||
        running.any((o) => p.equals(o, path));
    var path = p.join(dir, '$name.mp4');
    for (var n = 2; taken(path); n++) {
      path = p.join(dir, '$name ($n).mp4');
    }
    return path;
  }

  Future<ToolResult> _exportVideo(Map<String, dynamic> a, ToolCall call) async {
    final loaded = await _load(a['project_id']);
    final project = loaded.project;
    if (project.clips.isEmpty) {
      throw ToolError('The project "${project.name}" has no clips, so there is nothing to export.');
    }
    final missing = <String>{
      for (final c in project.clips)
        if (!File(c.path).existsSync()) c.path,
      for (final x in project.audio)
        if (!File(x.path).existsSync()) x.path,
      for (final o in project.overlays)
        if (!File(o.path).existsSync()) o.path,
    };
    if (missing.isNotEmpty) {
      throw ToolError('Cannot export: ${missing.length} media file(s) of this '
          'project are missing (moved, renamed or on a drive that is not '
          'connected): ${missing.join('; ')}');
    }

    final format = a['format'] == null
        ? ExportFormat.video
        : ExportFormat.values.byName(a['format'] as String);
    final ext0 = '.${format.extension}';
    String output;
    if (a['output_path'] == null) {
      output = _defaultExportPath(project);
      if (format.audioOnly) output = p.setExtension(output, ext0);
    } else {
      output = _path(a['output_path'], 'output_path');
      if (FileSystemEntity.typeSync(output) == FileSystemEntityType.directory) {
        output = _defaultExportPath(project, output);
      }
      final ext = p.extension(output).toLowerCase();
      if (ext.isEmpty) {
        output = '$output$ext0';
      } else if (ext != ext0) {
        throw ToolError('With format ${format.name} output_path must end in $ext0 (got "$ext").');
      }
      if (FileSystemEntity.typeSync(output) != FileSystemEntityType.notFound) {
        final isMedia = project.clips.any((c) => p.equals(c.path, output)) ||
            project.audio.any((x) => p.equals(x.path, output));
        if (isMedia) {
          throw ToolError('"$output" is one of the project\'s own media files; choose another output_path.');
        }
        if (a['overwrite'] != true) {
          throw ToolError('"$output" already exists. Choose another name or pass overwrite true.');
        }
      }
    }
    final all = jobs.list();
    for (final r in all) {
      if (r.isActive && p.equals(r.outputPath, output)) {
        final v = await viewJob(r);
        if (v.status != kJobLost) {
          throw ToolError('An export to "$output" is already running (job_id '
              '${r.id}, ${(r.progress * 100).floor()}%). Follow it with '
              'get_export_status, or stop it with cancel_export first.');
        }
      }
    }

    String? ffmpegPath, ffprobePath;
    if (exportLauncher.needsFfmpeg) {
      final engine = await media.requireEngine();
      ffmpegPath = engine.ffmpegPath;
      ffprobePath = engine.ffprobePath;
    }
    if (!format.audioOnly &&
        media.fonts == null &&
        project.titles.any((t) => t.text.trim().isNotEmpty)) {
      throw ToolError('This project has titles or captions, but the font '
          'files $kFontRegular and $kFontBold were not found (looked in: '
          '${fontsChecked.join('; ')}). They come with ClipForge in the '
          '"fonts" folder next to clipforge-mcp; put them back, or start the '
          'server with --fonts-dir <folder>.');
    }
    final quality = a['quality'] == null
        ? ExportQuality.full
        : ExportQuality.values.byName(a['quality'] as String);
    final hardware = a['hardware'] != false;
    final fpsArg = a['fps'] as String?;
    final fps = fpsArg == null
        ? 30
        : fpsArg == 'same'
            ? ExportOptions.sameAsSourceFps([
                for (final c in project.clips)
                  if (c.type == ClipType.video) c.frameRate,
              ])
            : int.parse(fpsArg);
    final options = ExportOptions(
        quality: quality, useHardwareEncoder: hardware, fps: fps, format: format);

    // A rough time up front, from the speed of the last export OF THE SAME
    // KIND here (graphics card / processor / sound only).
    final speeds = <String, double>{
      for (final kind in const ['sound', 'video-gpu', 'video-cpu'])
        if (rememberedSpeed(all, kind, host: localHostName()) != null)
          kind: rememberedSpeed(all, kind, host: localHostName())!,
    };
    final estimate = estimateRenderMs(project, options, speeds: speeds);

    final lock = await checkProjectLock(loaded.dir, isAlive: isAlive, hostName: hostName);
    final small = smallExportNote(project, quality, format);
    final ducking = duckingReport(project);
    final notes = <String>[
      if (!format.audioOnly) 'Size: ${canvasReason(project)}',
      ?small,
      if (ducking.isNotEmpty) duckingText(ducking),
      ...soundPastEndWarnings(project),
      if (lock.isHeld)
        'The project is open in the ClipForge app: this export uses the last '
            'saved state (the app saves every change within a second).',
    ];

    final id = _newId().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final short = id.length > 8 ? id.substring(0, 8) : id;
    final part = p.join(p.dirname(output),
        '${p.basenameWithoutExtension(output)}.$short.part$ext0');
    final record = ExportJobRecord(
      id: id,
      projectId: project.id,
      projectName: project.name,
      outputPath: output,
      partPath: part,
      format: format.name,
      quality: quality.name,
      fps: fps,
      hardware: hardware,
      overwrite: a['overwrite'] == true,
      createdAt: DateTime.now(),
      projectDurationMs: project.durationMs,
      estimateMs: estimate.ms,
      estimateBasis: 'between ${durationText(estimate.lowMs)} and '
          '${durationText(estimate.highMs)}; ${estimate.basis}',
      heartbeatAt: DateTime.now(),
      host: localHostName(),
      runner: exportLauncher.description,
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath,
      fontsDir: media.fonts == null ? null : p.dirname(media.fonts!.regular),
      notes: notes,
      details: {
        if (!format.audioOnly) 'canvasReason': canvasReason(project),
        'small': ?small,
        if (ducking.isNotEmpty) 'ducking': ducking,
      },
    );
    try {
      Directory(jobs.dir).createSync(recursive: true);
      jobs.projectFileOf(id).writeAsStringSync(jsonEncode(project.toJson()), flush: true);
      jobs.write(record);
    } on FileSystemException catch (e) {
      throw ToolError('The export could not be set up in ${jobs.dir}: ${e.message}');
    }
    try {
      record.workerPid = await exportLauncher.launch(jobs, id);
    } catch (e) {
      // No separate process: run it here (it then stops with the server).
      final fallback = inProcessLauncher(() async => await media.requireEngine());
      final r = jobs.read(id) ?? record;
      r.runner = '${fallback.description} (a separate process could not be started: $e)';
      jobs.write(r);
      await fallback.launch(jobs, id);
    }
    return _waitForJob(id, _i(a, 'wait_seconds') ?? kDefaultExportWait, call,
        started: true);
  }

  /// Waits up to [seconds] for job [id] to end, reporting progress, then
  /// describes it.
  Future<ToolResult> _waitForJob(String id, int seconds, ToolCall call,
      {bool started = false}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    var lastPercent = -1;
    // A client that goes away or gives up on this call ends the WAIT; the
    // export itself keeps going (cancel_export stops it).
    call.onCancel(() {});
    while (true) {
      final r = jobs.read(id);
      if (r == null) throw ToolError('There is no export with job_id "$id".');
      final view = await viewJob(r);
      final active = view.status == kJobStarting || view.status == kJobRunning;
      if (active) {
        final percent = (r.progress * 100).floor().clamp(0, 99);
        if (percent > lastPercent) {
          lastPercent = percent;
          call.progress(percent.toDouble(),
              total: 100, message: 'Exporting "${r.projectName}": $percent%');
        }
      }
      if (!active || call.isCancelled || !DateTime.now().isBefore(deadline)) {
        if (view.status == kJobFinished) {
          call.progress(100, total: 100, message: 'Export finished');
        }
        return _jobResult(view, started: started);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  ToolResult _jobResult(JobView v, {bool started = false}) {
    final r = v.record;
    final res = r.result ?? const <String, dynamic>{};
    final percent = (r.progress * 100).floor();
    final notes = r.notes.isEmpty ? '' : '\n${r.notes.map((n) => '- $n').join('\n')}';
    final String text;
    switch (v.status) {
      case kJobFinished:
        final size = res['sizeBytes'] as int? ?? 0;
        final mb = (size / (1024 * 1024)).toStringAsFixed(1);
        final len = res['durationMs'] as int?;
        final audioOnly = r.format != 'video';
        text = 'Exported "${r.projectName}" to:\n${r.outputPath}\n'
            'Size: $mb MB ($size bytes). '
            '${len == null ? '' : 'Length: $len ms (${clock(len)}), ${res['width']}x${res['height']} px, ${res['hasAudio'] == true ? 'with sound' : 'no sound'}. '}'
            '${audioOnly ? 'Sound only (${r.format}). ' : 'Quality: ${r.quality}, ${r.fps} frames per second. '}'
            '${audioOnly || res['encoderDescription'] == null ? '' : '${res['encoderDescription']} (${res['videoEncoder']}). '}'
            'Took ${durationText(v.elapsedMs)} (job_id ${r.id}).'
            '${(res['warnings'] as List?)?.isNotEmpty == true ? '\nNot applied: ${(res['warnings'] as List).join(' ')}' : ''}'
            '$notes';
      case kJobFailed:
        text = 'The export failed (project "${r.projectName}", job_id ${r.id}): '
            '${r.error ?? 'unknown error'}.'
            '${(r.log ?? '').isEmpty ? '' : '\nLast lines of the FFmpeg log:\n${r.log}'}';
      case kJobCancelled:
        text = 'The export of "${r.projectName}" was cancelled (job_id ${r.id}); '
            'no file was written.';
      case kJobLost:
        text = 'The export of "${r.projectName}" (job_id ${r.id}) stopped '
            'without finishing: its process is gone and it last reported '
            '${durationText(v.quietForMs)} ago at $percent% (the computer '
            'restarted, or the process was ended). No file was written under '
            'the output name. Start it again with export_video.';
      default:
        final eta = v.etaMs == null ? '' : ', about ${durationText(v.etaMs!)} left';
        text = '${started ? 'The export of "${r.projectName}" has started' : 'The export of "${r.projectName}" is ${v.status}'} '
            '(job_id ${r.id}): $percent% after ${durationText(v.elapsedMs)}$eta'
            '${started ? ' (first estimate for the whole render: about ${durationText(r.estimateMs)}, ${r.estimateBasis}; the time left is corrected from the real progress as it runs)' : ''}. '
            'It runs in ${r.runner}${r.runner.startsWith('a separate') ? ' and keeps going if this server is restarted' : ''}. '
            'Call get_export_status with job_id ${r.id} and wait_seconds '
            '$kMaxStatusWait until it says finished (do not start the export '
            'again); cancel_export stops it. Output: ${r.outputPath} (written '
            'as ${p.basename(r.partPath)} until it is complete).'
            '${v.quietForMs > 10000 ? ' No progress report for ${durationText(v.quietForMs)}.' : ''}'
            '$notes';
    }
    return ToolResult(text, isError: v.status == kJobFailed || v.status == kJobLost, structured: {
      'jobId': r.id,
      'status': v.status,
      'projectId': r.projectId,
      'outputPath': r.outputPath,
      'partPath': r.partPath,
      'progressPercent': v.status == kJobFinished ? 100 : percent,
      'elapsedMs': v.elapsedMs,
      'etaMs': ?v.etaMs,
      'estimateMs': r.estimateMs,
      'quality': r.quality,
      'format': r.format,
      if (r.format == 'video') 'fps': r.fps,
      'projectDurationMs': r.projectDurationMs,
      'runner': r.runner,
      if (v.status == kJobFinished) ...{
        'sizeBytes': res['sizeBytes'],
        if (res['durationMs'] != null) ...{
          'durationMs': res['durationMs'],
          'width': res['width'],
          'height': res['height'],
          'hasVideo': res['hasVideo'],
          'hasAudio': res['hasAudio'],
        },
        if (res['videoEncoder'] != null) ...{
          'videoEncoder': res['videoEncoder'],
          'hardwareEncoder': res['hardwareEncoder'],
        },
        if (res['warnings'] != null) 'exportWarnings': res['warnings'],
      },
      'error': ?r.error,
      'log': ?r.log,
      if (r.notes.isNotEmpty) 'notes': r.notes,
      ...r.details,
    });
  }

  Future<ToolResult> _getExportStatus(Map<String, dynamic> a, ToolCall call) async {
    final id = (a['job_id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      final list = jobs.list().take(10).toList();
      if (list.isEmpty) {
        return const ToolResult('No exports yet.', structured: {'jobs': <Object>[]});
      }
      final views = [for (final r in list) await viewJob(r)];
      return ToolResult(
          'Recent exports (newest first):\n${views.map((v) => '  job_id ${v.record.id} "${v.record.projectName}" ${v.status}'
              '${v.status == kJobRunning ? ' ${(v.record.progress * 100).floor()}%' : ''} -> ${v.record.outputPath}').join('\n')}',
          structured: {
            'jobs': [
              for (final v in views)
                {
                  'jobId': v.record.id,
                  'projectId': v.record.projectId,
                  'status': v.status,
                  'progressPercent': (v.record.progress * 100).floor(),
                  'outputPath': v.record.outputPath,
                  'createdAt': v.record.createdAt.toUtc().toIso8601String(),
                },
            ],
          });
    }
    if (jobs.read(id) == null) {
      throw ToolError('There is no export with job_id "$id" in ${jobs.dir} '
          '(get_export_status without job_id lists the recent ones).');
    }
    return _waitForJob(id, _i(a, 'wait_seconds') ?? 0, call);
  }

  Future<ToolResult> _cancelExport(Map<String, dynamic> a, ToolCall call) async {
    final id = (a['job_id'] as String).trim();
    final r = jobs.read(id);
    if (r == null) throw ToolError('There is no export with job_id "$id".');
    final view = await viewJob(r);
    if (view.status != kJobStarting && view.status != kJobRunning) {
      return _jobResult(view);
    }
    jobs.requestCancel(id);
    // The render looks for the request every second.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final now = jobs.read(id);
      if (now != null && !now.isActive) return _jobResult(await viewJob(now));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return ToolResult('Asked the export (job_id $id) to stop; it has not '
        'confirmed yet. get_export_status shows when it has.',
        structured: {'jobId': id, 'status': 'cancelling'});
  }
}
