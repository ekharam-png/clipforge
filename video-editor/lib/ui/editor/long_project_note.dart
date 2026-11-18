import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app_prefs.dart';
import 'session.dart';

/// From this length on a project counts as long (40-minute videos work,
/// but listening for silences, thumbnails and exporting take a while).
const int kLongProjectMs = 20 * 60 * 1000;

const String kLongProjectNote =
    'Long videos work, but some steps take longer.';

/// Shows [kLongProjectNote] once per project, the first time it is (or
/// becomes) longer than [kLongProjectMs]. Remembered in the app settings,
/// so it does not come back when the project is opened again.
class LongProjectNote {
  LongProjectNote(this.session, this.context) {
    session.editor.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  final EditorSession session;
  final BuildContext context;
  bool _disposed = false;
  bool _asking = false;

  /// Projects noted in this run of the app (also when the settings cannot
  /// be written), per settings store.
  static final Expando<Set<String>> _notedBy = Expando('long notes');
  static final Set<String> _notedWithoutPrefs = {};

  Set<String> get _noted {
    final prefs = _prefs;
    if (prefs == null) return _notedWithoutPrefs;
    return _notedBy[prefs] ??= {};
  }

  AppPrefs? get _prefs {
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(appPrefsProvider);
    } catch (_) {
      return null;
    }
  }

  void _check() {
    if (_disposed || _asking) return;
    final project = session.project;
    if (project.durationMs < kLongProjectMs || _noted.contains(project.id)) {
      return;
    }
    _asking = true;
    _show(project.id).whenComplete(() => _asking = false);
  }

  Future<void> _show(String projectId) async {
    _noted.add(projectId);
    final prefs = _prefs;
    final key = 'longProjectNote.$projectId';
    try {
      if (prefs != null && await prefs.flag(key)) return;
    } catch (_) {}
    if (_disposed || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text(kLongProjectNote),
      duration: Duration(seconds: 6),
    ));
    try {
      await prefs?.setFlag(key);
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    session.editor.removeListener(_check);
  }
}
