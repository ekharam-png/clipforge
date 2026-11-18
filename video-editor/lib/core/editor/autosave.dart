import 'dart:async';

import '../model/project.dart';
import '../storage/project_store.dart';
import 'editor_controller.dart';

/// Saves the controller's project through a [ProjectStore] a short while
/// after the last edit.
///
/// Saves never overlap: a change that arrives while a save is running is
/// written right after it. Save errors never reach the controller's
/// listeners; the most recent one is kept in [lastError] and the save is
/// retried on the next change or [flush].
class Autosaver {
  Autosaver(
    this.controller,
    this.store, {
    this.debounce = const Duration(milliseconds: 800),
  }) : _saved = controller.project {
    controller.addListener(_onChanged);
  }

  final EditorController controller;
  final ProjectStore store;

  /// Quiet time after the last edit before the project is written.
  final Duration debounce;

  /// Error of the most recent save attempt, or null when it succeeded.
  Object? lastError;

  Project _saved;
  Timer? _timer;
  Future<void>? _running;
  bool _lastRunFailed = false;
  bool _disposed = false;

  /// True when the controller holds a project state that is not on disk yet.
  bool get hasPendingChanges => !identical(controller.project, _saved);

  /// True while a save is being written.
  bool get isSaving => _running != null;

  void _onChanged() {
    _timer?.cancel();
    _timer = null;
    if (!hasPendingChanges) return;
    _timer = Timer(debounce, () {
      _timer = null;
      _drain();
    });
  }

  /// Runs saves until the disk matches the controller (or a save fails).
  /// The returned future never completes with an error.
  Future<void> _drain() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    _lastRunFailed = false;
    while (true) {
      final snapshot = controller.project;
      if (identical(snapshot, _saved)) return;
      try {
        await store.save(snapshot);
        _saved = snapshot;
        lastError = null;
      } catch (e) {
        lastError = e;
        _lastRunFailed = true;
        return;
      }
    }
  }

  /// Writes any pending change now and waits for it. Never throws; check
  /// [lastError] to see whether the save worked.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    do {
      await _drain();
    } while (hasPendingChanges && !_lastRunFailed);
  }

  /// Stops listening. A change still waiting for the debounce is written
  /// in the background (best effort); call [flush] first to wait for it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_onChanged);
    _timer?.cancel();
    _timer = null;
    if (hasPendingChanges) unawaited(_drain());
  }
}
