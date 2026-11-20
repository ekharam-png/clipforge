import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_prefs.dart';

// The app's settings as one live object (1.15): the Settings page, the
// View menu, the editor and the Export window all read and write here, so
// a switch changed in one place shows in every other at once. Everything
// is stored through [AppPrefs] (settings.json).

/// [AppPrefs.flag] that turns "Use graphics card" off (on by default; the
/// Export window and Settings > Export).
const String kGraphicsCardOffFlag = 'graphicsCardOff';

/// [AppPrefs.flag] that turns the suggestions off (Settings > Suggestions).
const String kSuggestionsOffFlag = 'suggestionsOff';

/// [AppPrefs.text]: the names of the suggestions that were turned off with
/// "Don't show again" (comma separated), so that Settings can turn them
/// back on. Each one also has its own flag, `hint.<id>.off`.
const String kHintsOffListText = 'hintsOff';

/// [AppPrefs.flag]: the Text window was opened at least once.
const String kTextOpenedFlag = 'textOpened';

/// [AppPrefs.flag]: the "What moved in 1.15" note was shown (or is not
/// needed: a first install).
const String kWhatMovedSeenFlag = 'whatMoved115Seen';

/// The 1.17 note "Two keys changed" (I / O) was shown, or not needed.
const String kKeysMovedSeenFlag = 'keysMoved117Seen';

/// [AppPrefs.flag]: an export was started at least once.
const String kExportedOnceFlag = 'exportedOnce';

/// [AppPrefs.text]: the version whose "Updated to X" line was dismissed.
const String kUpdatedLineSeenText = 'updatedLineSeen';

/// [AppPrefs.text]: the version that ran last (to notice an update that
/// was installed by hand).
const String kLastRunVersionText = 'lastRunVersion';

/// `hint.<id>.off`: the suggestion [id] is never shown again.
String hintOffFlag(String id) => 'hint.$id.off';

/// `hint.<id>.<projectId>`: the suggestion [id] was shown or closed for
/// this project.
String hintProjectFlag(String id, String projectId) => 'hint.$id.$projectId';

/// The settings that are switches or choices. Reading is synchronous once
/// [load] has finished (before that: the defaults).
class AppSettings extends ChangeNotifier {
  AppSettings(this.prefs);

  final AppPrefs prefs;
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;

  bool _snapping = true;
  bool _soundWaves = true;
  bool _smoothPreview = true;
  bool _textBelow = false;
  bool _graphicsCard = true;
  bool _suggestions = true;

  /// Timeline snapping (View > Snap to playhead and edges).
  bool get snapping => _snapping;

  /// View > Show sound waves.
  bool get soundWaves => _soundWaves;

  /// Phones: lighter preview decoding.
  bool get smoothPreview => _smoothPreview;

  /// The Text window sits under the preview instead of at the right.
  bool get textBelow => _textBelow;

  /// Export: use the graphics card when one works.
  bool get graphicsCard => _graphicsCard;

  /// Suggestions are shown.
  bool get suggestions => _suggestions;

  /// Reads everything once; later calls return the same future.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _snapping = !await prefs.flag(kSnappingOffFlag);
      _soundWaves = !await prefs.flag(kSoundWavesOffFlag);
      _smoothPreview = !await prefs.flag(kSmoothPreviewOffFlag);
      _textBelow = await prefs.text(kTextDockText) == 'below';
      _graphicsCard = !await prefs.flag(kGraphicsCardOffFlag);
      _suggestions = !await prefs.flag(kSuggestionsOffFlag);
    } catch (_) {
      // Unreadable settings: the defaults.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _store(String offFlag, bool on) async {
    try {
      await (on ? prefs.clearFlag(offFlag) : prefs.setFlag(offFlag));
    } catch (_) {
      // Kept for this run at least.
    }
  }

  Future<void> setSnapping(bool on) async {
    if (_snapping == on) return;
    _snapping = on;
    notifyListeners();
    await _store(kSnappingOffFlag, on);
  }

  Future<void> setSoundWaves(bool on) async {
    if (_soundWaves == on) return;
    _soundWaves = on;
    notifyListeners();
    await _store(kSoundWavesOffFlag, on);
  }

  Future<void> setSmoothPreview(bool on) async {
    if (_smoothPreview == on) return;
    _smoothPreview = on;
    notifyListeners();
    await _store(kSmoothPreviewOffFlag, on);
  }

  Future<void> setTextBelow(bool below) async {
    if (_textBelow == below) return;
    _textBelow = below;
    notifyListeners();
    try {
      await prefs.setText(kTextDockText, below ? 'below' : 'right');
    } catch (_) {}
  }

  Future<void> setGraphicsCard(bool on) async {
    if (_graphicsCard == on) return;
    _graphicsCard = on;
    notifyListeners();
    await _store(kGraphicsCardOffFlag, on);
  }

  Future<void> setSuggestions(bool on) async {
    if (_suggestions == on) return;
    _suggestions = on;
    notifyListeners();
    await _store(kSuggestionsOffFlag, on);
  }

  /// The suggestions turned off with "Don't show again".
  Future<List<String>> hiddenHints() async {
    try {
      final list = await prefs.text(kHintsOffListText) ?? '';
      return [
        for (final id in list.split(','))
          if (id.isNotEmpty) id,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// "Don't show again" for the suggestion [id].
  Future<void> hideHint(String id) async {
    try {
      await prefs.setFlag(hintOffFlag(id));
      final hidden = await hiddenHints();
      if (!hidden.contains(id)) {
        await prefs.setText(kHintsOffListText, [...hidden, id].join(','));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// "Show hidden suggestions again": every "Don't show again" is undone.
  /// (What was closed for one project stays closed for that project.)
  Future<int> showHiddenHintsAgain() async {
    final hidden = await hiddenHints();
    try {
      for (final id in hidden) {
        await prefs.clearFlag(hintOffFlag(id));
      }
      await prefs.setText(kHintsOffListText, null);
    } catch (_) {}
    notifyListeners();
    return hidden.length;
  }
}

/// The one [AppSettings] of the app (over [appPrefsProvider]).
final appSettingsProvider = Provider<AppSettings>((ref) {
  final settings = AppSettings(ref.watch(appPrefsProvider))..load();
  ref.onDispose(settings.dispose);
  return settings;
});
