import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../file_drop.dart';
import '../services.dart';
import '../theme.dart';
import 'import_actions.dart';
import 'session.dart';

// "Add from a folder path…" (1.17, computers): a way to add media WITHOUT
// the system's file window - type or paste the path of a file or a
// folder, tick what to add. For keyboard users, and for helpers that
// drive the app and cannot see the system's file window. What is added
// goes through the same pipeline as files dropped on the window
// (addDroppedFiles): videos and photos to the main track, sound with the
// "What is this sound?" question, .srt files as captions.

/// The most files of one folder the list shows.
const int kPathListLimit = 300;

/// What a typed path gives: the media files, a note, or why nothing.
class PathLook {
  const PathLook(this.files, {this.folder, this.problem, this.left = 0});
  final List<String> files;

  /// The folder that was opened (null: the path was one file).
  final String? folder;

  /// Why there is nothing to add (one sentence); null when there is.
  final String? problem;

  /// Files in the folder that are not media.
  final int left;
}

/// A path as people paste it: without the quotes Windows' "Copy as path"
/// puts around it, without `file://`.
String cleanTypedPath(String raw) {
  var t = raw.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'")))) {
    t = t.substring(1, t.length - 1).trim();
  }
  if (t.startsWith('file://')) {
    try {
      t = Uri.parse(t).toFilePath();
    } catch (_) {}
  }
  return t;
}

/// Looks at [raw]: one media file, or the media files directly inside a
/// folder (sorted by name; folders inside are not opened).
PathLook lookAtPath(String raw) {
  final path = cleanTypedPath(raw);
  if (path.isEmpty) {
    return const PathLook([], problem: 'Type or paste the path of a file or a folder.');
  }
  try {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      final kind = dropKindOf(path);
      if (kind == DropKind.unsupported || kind == DropKind.project) {
        return PathLook(const [],
            problem: kind == DropKind.project
                ? 'That is a project file: open it from the project list.'
                : '${p.basename(path)} is not a video, photo, sound or '
                    'subtitle (.srt) file.');
      }
      return PathLook([path]);
    }
    if (type == FileSystemEntityType.directory) {
      final found = <String>[];
      var left = 0;
      for (final e in Directory(path).listSync(followLinks: true)) {
        if (e is! File) continue;
        final kind = dropKindOf(e.path);
        if (kind == DropKind.unsupported || kind == DropKind.project) {
          left++;
        } else {
          found.add(e.path);
        }
      }
      found.sort((a, b) =>
          p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
      if (found.isEmpty) {
        return PathLook(const [],
            folder: path,
            left: left,
            problem: 'There are no videos, photos or sounds directly in '
                'that folder.');
      }
      return PathLook(found.take(kPathListLimit).toList(),
          folder: path, left: left + (found.length > kPathListLimit ? found.length - kPathListLimit : 0));
    }
    return const PathLook([], problem: 'There is no file or folder at that path.');
  } on FileSystemException catch (e) {
    return PathLook(const [],
        problem: 'That path cannot be read (${e.osError?.message ?? e.message}).');
  }
}

/// "Add from a folder path…". [initial]: a path to start with (pasted
/// with Ctrl+V on the timeline); it is looked at right away.
Future<void> showAddFromPath(BuildContext context, EditorSession s,
    {String? initial}) async {
  s.playback.pause();
  final chosen = await showDialog<List<String>>(
    context: context,
    builder: (_) => _AddFromPathDialog(initial: initial),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted || s.isDisposed) {
    return;
  }
  await addDroppedFiles(
      context,
      s,
      FileDrop(
          files: [for (final f in chosen) DroppedFile(f)],
          globalPosition: Offset.zero));
}

/// Ctrl+V on the timeline: when the clipboard holds the path of a file or
/// a folder, "Add from a folder path…" opens with it. True when it did.
Future<bool> pastePathToAdd(BuildContext context, EditorSession s) async {
  String? text;
  try {
    text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } catch (_) {
    return false;
  }
  if (text == null || !context.mounted || s.isDisposed) return false;
  // Several lines (several files copied as paths): the first that is one.
  for (final line in text.split(RegExp(r'[\r\n]+')).take(20)) {
    final path = cleanTypedPath(line);
    if (path.length < 2 || path.length > 1024) continue;
    try {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
        continue;
      }
    } catch (_) {
      continue;
    }
    await showAddFromPath(context, s, initial: path);
    return true;
  }
  return false;
}

class _AddFromPathDialog extends StatefulWidget {
  const _AddFromPathDialog({this.initial});
  final String? initial;

  @override
  State<_AddFromPathDialog> createState() => _AddFromPathDialogState();
}

class _AddFromPathDialogState extends State<_AddFromPathDialog> {
  late final TextEditingController _path =
      TextEditingController(text: widget.initial ?? '');
  PathLook? _look;
  final Set<String> _ticked = {};

  @override
  void initState() {
    super.initState();
    if ((widget.initial ?? '').trim().isNotEmpty) _doLook();
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _doLook() {
    final look = lookAtPath(_path.text);
    _look = look;
    _ticked
      ..clear()
      ..addAll(look.files);
    if (mounted) setState(() {});
  }

  static IconData _icon(String path) => switch (dropKindOf(path)) {
        DropKind.music => Icons.music_note,
        DropKind.subtitles => Icons.subtitles_outlined,
        _ => isImageFile(path) ? Icons.image_outlined : Icons.movie_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final look = _look;
    return AlertDialog(
      key: const ValueKey('add-path-dialog'),
      title: const Text('Add from a folder path'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Type or paste the path of a file, or of a folder to choose '
                'from (in Explorer: Shift+right-click > Copy as path; in '
                'Finder: Option+right-click > Copy as Pathname).',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('add-path-field'),
                    controller: _path,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Path', isDense: true),
                    onSubmitted: (_) => _doLook(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('add-path-look'),
                  onPressed: _doLook,
                  child: const Text('Show files'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (look?.problem != null)
              Text(look!.problem!, key: const ValueKey('add-path-problem')),
            if (look != null && look.files.isNotEmpty) ...[
              if (look.folder != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${look.files.length} media '
                          '${look.files.length == 1 ? 'file' : 'files'} in '
                          'this folder'
                          '${look.left > 0 ? ' (${look.left} other left out)' : ''}',
                          key: const ValueKey('add-path-count'),
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 12.5)),
                    ),
                    TextButton(
                      key: const ValueKey('add-path-all'),
                      onPressed: () => setState(() =>
                          _ticked.length == look.files.length
                              ? _ticked.clear()
                              : _ticked.addAll(look.files)),
                      child: Text(_ticked.length == look.files.length
                          ? 'Untick all'
                          : 'Tick all'),
                    ),
                  ],
                ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < look.files.length; i++)
                        CheckboxListTile(
                          key: ValueKey('add-path-item-$i'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          secondary: Icon(_icon(look.files[i]), size: 18),
                          title: Text(p.basename(look.files[i])),
                          value: _ticked.contains(look.files[i]),
                          onChanged: (v) => setState(() => v == true
                              ? _ticked.add(look.files[i])
                              : _ticked.remove(look.files[i])),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('add-path-go'),
          onPressed: look == null || _ticked.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                    for (final f in look.files)
                      if (_ticked.contains(f)) f,
                  ]),
          child: Text(_ticked.length <= 1
              ? 'Add'
              : 'Add ${_ticked.length} files'),
        ),
      ],
    );
  }
}

/// True for a photo, by its name.
bool isImageFile(String path) => const {
      '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.gif', '.bmp', //
    }.contains(p.extension(path).toLowerCase());
