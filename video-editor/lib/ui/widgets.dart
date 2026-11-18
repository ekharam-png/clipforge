import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'services.dart';

/// A picture for a media file: the photo itself, or a frame of a video from
/// the [ThumbnailCache]. Shows nothing (transparent) until or unless a
/// picture is available, so put it over a fallback colour.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.path,
    required this.thumbnails,
    this.timeMs = 0,
    this.fit = BoxFit.cover,
    this.repeat = ImageRepeat.noRepeat,
  });

  final String path;
  final ThumbnailCache thumbnails;
  final int timeMs;
  final BoxFit fit;
  final ImageRepeat repeat;

  Widget _image(String file) => Image.file(
        File(file),
        fit: fit,
        repeat: repeat,
        alignment: Alignment.centerLeft,
        cacheHeight: 160,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    if (isImagePath(path)) return _image(path);
    // A thumbnail that is already there shows in the first frame (no
    // blank frame when a timeline block is built again).
    final ready = thumbnails.getNow(path, timeMs: timeMs);
    if (ready != null) return _image(ready);
    return FutureBuilder<String?>(
      future: thumbnails.get(path, timeMs: timeMs),
      builder: (context, snapshot) {
        final file = snapshot.data;
        return file == null ? const SizedBox.shrink() : _image(file);
      },
    );
  }
}

/// Asks for a line of text. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initial,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPrompt(
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });
  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Yes/no question for something that cannot be taken back.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Shows [message] with a spinner while [work] runs.
Future<void> whileBusy(
    BuildContext context, String message, Future<void> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await work();
  } finally {
    navigator.pop();
  }
}


/// Like [ListenableBuilder], but [builder] runs again only when [select]
/// gives a different value (`==`) than at the last build, or the parent
/// rebuilt. For layers that listen to the playhead (60 times a second while
/// playing) but only look different now and then: titles, the project fade,
/// the picture (1.8, phone performance). [select] is read when the frame is
/// built, not when [listenable] notifies, so state that changes right after
/// the notification (a seek that also loads a player) is seen. When the key
/// is unchanged the previous widget is returned as it is, which Flutter
/// skips without rebuilding anything below it.
class SelectBuilder<T> extends StatefulWidget {
  const SelectBuilder({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final T Function() select;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<SelectBuilder<T>> createState() => _SelectBuilderState<T>();
}

class _SelectBuilderState<T> extends State<SelectBuilder<T>> {
  Widget? _built;
  T? _key;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(SelectBuilder<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _built = null; // the parent rebuilt: build again
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null; // e.g. the theme or the screen size changed
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final key = widget.select();
    final built = _built;
    if (built != null && key == _key) return built;
    _key = key;
    return _built = widget.builder(context, widget.child);
  }
}
