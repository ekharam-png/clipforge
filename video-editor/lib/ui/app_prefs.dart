import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Small app-wide settings that are not part of a project (today only
/// whether the first-launch tour question was answered).
abstract class AppPrefs {
  /// True once the "Would you like a quick tour?" question was answered
  /// (either way). It is never asked again after that.
  Future<bool> tourAnswered();

  Future<void> setTourAnswered();

  /// A remembered yes/no, false until [setFlag] (e.g. that a note was
  /// shown for a project).
  Future<bool> flag(String name);

  Future<void> setFlag(String name);

  /// Sets [flag] back to false.
  Future<void> clearFlag(String name);

  /// A remembered short text (a date, a number), null until [setText].
  Future<String?> text(String name);

  /// Remembers [value] under [name]; null forgets it.
  Future<void> setText(String name, String? value);
}

/// [AppPrefs.flag] that turns the automatic update check off (it is on by
/// default; Help > Check for updates automatically).
const String kUpdateCheckOffFlag = 'updateCheckOff';

/// [AppPrefs.text]: when updates were last checked (ISO 8601, UTC).
const String kUpdateLastCheckText = 'updateLastCheck';

/// [AppPrefs.text]: the build number the user chose to skip.
const String kUpdateSkipBuildText = 'updateSkipBuild';

/// [AppPrefs.flag] that turns timeline snapping off (it is on by default).
const String kSnappingOffFlag = 'snappingOff';

/// [AppPrefs.flag] that turns "Smooth preview" off on phones (on by
/// default there; see MediaKitBackend.smoothPreview).
const String kSmoothPreviewOffFlag = 'smoothPreviewOff';

/// [AppPrefs] in a small JSON file, `settings.json` in the application
/// support folder (next to the app's own `media` folder). A file that is
/// missing or cannot be read counts as "nothing set yet".
class FileAppPrefs implements AppPrefs {
  FileAppPrefs({Future<String> Function()? folder})
      : _folder = folder ??
            (() async => (await getApplicationSupportDirectory()).path);

  final Future<String> Function() _folder;
  Map<String, Object?>? _values;

  static const fileName = 'settings.json';
  static const _tourKey = 'tourAnswered';

  Future<File> _file() async => File(p.join(await _folder(), fileName));

  Future<Map<String, Object?>> _load() async {
    final cached = _values;
    if (cached != null) return cached;
    var values = <String, Object?>{};
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) values = decoded;
      }
    } catch (_) {
      // Unreadable: start from nothing.
    }
    return _values = values;
  }

  Future<void> _set(String key, Object? value) async {
    final values = await _load();
    values[key] = value;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      // Written next to it first, so a full disk cannot leave half a file.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(values), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Remembered for this run; asked again next time at worst.
    }
  }

  @override
  Future<bool> tourAnswered() async => (await _load())[_tourKey] == true;

  @override
  Future<void> setTourAnswered() => _set(_tourKey, true);

  @override
  Future<bool> flag(String name) async => (await _load())[name] == true;

  @override
  Future<void> setFlag(String name) => _set(name, true);

  @override
  Future<void> clearFlag(String name) => _set(name, false);

  @override
  Future<String?> text(String name) async {
    final v = (await _load())[name];
    return v is String ? v : null;
  }

  @override
  Future<void> setText(String name, String? value) => _set(name, value);
}

/// [AppPrefs] kept in memory (tests, and the end-to-end runs).
class MemoryAppPrefs implements AppPrefs {
  MemoryAppPrefs({this.answered = false});
  bool answered;

  @override
  Future<bool> tourAnswered() async => answered;

  @override
  Future<void> setTourAnswered() async => answered = true;

  final Set<String> flags = {};

  @override
  Future<bool> flag(String name) async => flags.contains(name);

  @override
  Future<void> setFlag(String name) async => flags.add(name);

  @override
  Future<void> clearFlag(String name) async => flags.remove(name);

  final Map<String, String> texts = {};

  @override
  Future<String?> text(String name) async => texts[name];

  @override
  Future<void> setText(String name, String? value) async {
    if (value == null) {
      texts.remove(name);
    } else {
      texts[name] = value;
    }
  }
}

final appPrefsProvider = Provider<AppPrefs>((ref) => FileAppPrefs());
