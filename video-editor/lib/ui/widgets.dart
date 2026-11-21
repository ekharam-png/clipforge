import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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

/// A way out of a [whileBusy] window (1.18): given to [whileBusy], the
/// window gets a Cancel button, Esc and the back button close it, and
/// [whileBusy] returns at once - the work may still be running and must
/// check [cancelled] before it uses its result.
class BusyCancel {
  bool _cancelled = false;
  final Completer<void> _done = Completer<void>();

  bool get cancelled => _cancelled;

  /// Completes when the user cancelled.
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _done.complete();
  }

  /// The cancellable busy window that is open right now, if any.
  static BusyCancel? _current;

  /// True while a busy window that can be cancelled is open.
  static bool get busy => _current != null;

  /// Cancels the open busy window (File > Back to projects during
  /// "Adding file…"). True when there was one.
  static bool cancelCurrent() {
    final c = _current;
    if (c == null) return false;
    c.cancel();
    return true;
  }
}

/// Shows [message] with a spinner while [work] runs. With [cancel] the
/// window can be left (Cancel, Esc); the result is then false and [work]
/// is no longer waited for. [slowNote] replaces nothing: it is added
/// under the message after [slowAfter], for work that normally takes a
/// moment ("This is taking longer than usual…").
Future<bool> whileBusy(
    BuildContext context, String message, Future<void> Function() work,
    {BusyCancel? cancel,
    String? slowNote,
    Duration slowAfter = const Duration(seconds: 6)}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  final closed = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: cancel != null,
      // Esc cancels (a window that cannot be dismissed by a click outside
      // does not take Esc by itself).
      child: CallbackShortcuts(
        bindings: cancel == null
            ? const {}
            : {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (open) navigator.pop();
                },
              },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 20),
                Expanded(child: Text(message)),
              ],
            ),
            if (slowNote != null) _SlowNote(slowNote, slowAfter),
          ],
        ),
        actions: cancel == null
            ? null
            : [
                TextButton(
                  key: const ValueKey('busy-cancel'),
                  onPressed: () => navigator.pop(),
                  child: const Text('Cancel'),
                ),
              ],
          ),
        ),
      ),
    ),
  ).then((_) {
    // Closed by the user (Cancel, Esc, back) when the work is not over.
    if (open) cancel?.cancel();
    open = false;
  });
  if (cancel != null) BusyCancel._current = cancel;
  try {
    if (cancel == null) {
      await work();
      return true;
    }
    final finished = work().then((_) => true);
    // A failure after the user left must not become an unhandled error.
    unawaited(finished.then((_) {}, onError: (_) {}));
    final done = await Future.any<bool>(
        [finished, cancel.whenCancelled.then((_) => false)]);
    return done && !cancel.cancelled;
  } finally {
    if (identical(BusyCancel._current, cancel)) BusyCancel._current = null;
    if (open) {
      open = false;
      navigator.pop();
    }
    unawaited(closed);
  }
}

/// A line that appears after a while under a busy message.
class _SlowNote extends StatefulWidget {
  const _SlowNote(this.text, this.after);
  final String text;
  final Duration after;

  @override
  State<_SlowNote> createState() => _SlowNoteState();
}

class _SlowNoteState extends State<_SlowNote> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_show
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(widget.text,
              key: const ValueKey('busy-slow-note'),
              style: Theme.of(context).textTheme.bodySmall),
        );
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

/// The reading direction of [text]: right to left when its first strong
/// letter is Hebrew or Arabic.
TextDirection textDirectionOf(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x52F)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}
