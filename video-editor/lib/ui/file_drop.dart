import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'format.dart';
import 'services.dart';
import 'theme.dart';

/// What a dropped file is to the app, by its name.
enum DropKind { media, music, subtitles, project, unsupported }

const _videoExtensions = {
  '.mp4', '.mov', '.m4v', '.mkv', '.avi', '.webm', '.3gp', '.3g2', //
  '.mts', '.m2ts', '.ts', '.mpg', '.mpeg', '.wmv', '.flv', '.ogv',
};

const _audioExtensions = {
  '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.oga', '.opus', //
  '.wma', '.aif', '.aiff', '.caf', '.alac',
};

/// The ending of a project file made by "Share project file".
const kProjectFileSuffix = '.clipforge.zip';

DropKind dropKindOf(String path) {
  final name = p.basename(path).toLowerCase();
  if (name.endsWith(kProjectFileSuffix)) return DropKind.project;
  final ext = p.extension(name);
  if (isImagePath(name) || _videoExtensions.contains(ext)) {
    return DropKind.media;
  }
  if (_audioExtensions.contains(ext)) return DropKind.music;
  if (ext == '.srt') return DropKind.subtitles;
  return DropKind.unsupported;
}

/// A drop split by kind, each list in drop order.
class SortedDrop {
  SortedDrop(FileDrop drop) : folders = drop.folders {
    for (final f in drop.files) {
      final kind = dropKindOf(f.path);
      // A folder's other files (documents, sidecar files...) are left out
      // quietly; only files dropped by themselves are reported.
      if (kind == DropKind.unsupported && f.folder != null) {
        skippedInFolders++;
        continue;
      }
      _byKind[kind]!.add(f);
    }
  }

  final List<String> folders;
  final Map<DropKind, List<DroppedFile>> _byKind = {
    for (final k in DropKind.values) k: <DroppedFile>[],
  };

  /// Files inside dropped folders that are not media.
  int skippedInFolders = 0;

  List<DroppedFile> get media => _byKind[DropKind.media]!;
  List<DroppedFile> get music => _byKind[DropKind.music]!;
  List<DroppedFile> get subtitles => _byKind[DropKind.subtitles]!;
  List<DroppedFile> get projects => _byKind[DropKind.project]!;
  List<DroppedFile> get unsupported => _byKind[DropKind.unsupported]!;

  /// Something an editor can add (videos, photos, music, subtitles).
  bool get hasEditable =>
      media.isNotEmpty || music.isNotEmpty || subtitles.isNotEmpty;

  /// One line per file that cannot be used, for a problem list.
  List<String> get unsupportedLines => [
    for (final f in unsupported)
      '${f.name} — not a video, photo, music or subtitle (.srt) file',
  ];

  /// What happened to dropped folders, for a short message; null when no
  /// folder was dropped.
  String? get folderNote {
    if (folders.isEmpty) return null;
    final names = folders.map((f) => '"$f"').join(', ');
    final skipped = skippedInFolders == 0
        ? ''
        : ' ($skippedInFolders other '
              '${skippedInFolders == 1 ? 'file was' : 'files were'} left out)';
    return 'Took the media files directly inside '
        '${folders.length == 1 ? 'the folder' : 'the folders'} $names, '
        'sorted by name; folders inside were not opened$skipped.';
  }
}

/// Lets files be dragged onto [child] from the desktop (macOS, Windows,
/// Linux; nothing on phones). While files are dragged over it the area is
/// highlighted with [message] (or [messageAt] for the pointer's place, and
/// a line at [lineAt] when that gives one). Inactive while another screen
/// or a dialog covers it.
class FileDropZone extends ConsumerStatefulWidget {
  const FileDropZone({
    super.key,
    required this.child,
    required this.message,
    required this.onDrop,
    this.messageAt,
    this.lineAt,
    this.enabled = true,
  });

  final Widget child;
  final String message;
  final FutureOr<void> Function(FileDrop drop) onDrop;
  final String? Function(Offset global)? messageAt;
  final Rect? Function(Offset global)? lineAt;
  final bool enabled;

  @override
  ConsumerState<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends ConsumerState<FileDropZone> {
  Offset? _hover;
  final _key = GlobalKey();

  void _onHover(Offset? global) {
    if (!mounted || global == _hover) return;
    setState(() => _hover = global);
  }

  Future<void> _onDrop(FileDrop drop) async {
    if (!mounted) return;
    setState(() => _hover = null);
    if (drop.files.isEmpty && drop.folders.isEmpty) return;
    await widget.onDrop(drop);
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(fileDropServiceProvider);
    if (!service.supported) return widget.child;
    final route = ModalRoute.of(context);
    final enabled = widget.enabled && (route?.isCurrent ?? true);
    final hover = enabled ? _hover : null;
    return service.target(
      enabled: enabled,
      onHover: _onHover,
      onDrop: _onDrop,
      child: Stack(
        key: _key,
        children: [
          widget.child,
          if (hover != null) Positioned.fill(child: _highlight(hover)),
        ],
      ),
    );
  }

  Widget _highlight(Offset global) {
    final box = _key.currentContext?.findRenderObject();
    Rect? line = widget.lineAt?.call(global);
    if (line != null && box is RenderBox && box.attached) {
      final topLeft = box.globalToLocal(line.topLeft);
      line = topLeft & line.size;
    } else {
      line = null;
    }
    final message = widget.messageAt?.call(global) ?? widget.message;
    // Above the Scaffold, so it brings its own Material (text style).
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          liveRegion: true,
          label: message,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.accent, width: 3),
                  ),
                ),
              ),
              if (line != null)
                Positioned.fromRect(
                  rect: line.inflate(1),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              Align(
                alignment: line == null
                    ? Alignment.center
                    : Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.panelHigh,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.file_download_outlined,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells that files could not be used (one line each).
Future<void> showDropProblems(
  BuildContext context,
  String title,
  List<String> lines, {
  String? footer,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(l),
                ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    footer,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
