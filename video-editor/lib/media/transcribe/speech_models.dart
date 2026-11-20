// The speech models ("language packs") ClipForge can fetch, where they are
// kept, and which one a language and quality need. Pure Dart (dart:io).
//
// NOTHING is bundled and nothing is downloaded up front: the app stays the
// same size. A pack is fetched only when the user clicks it (or, for
// Claude, when the owner said yes and `download_pack` is passed), into
// `<ClipForge>/models/`, and can be removed again.
//
// Owner decision (1.11): three sizes per language, the user chooses; no
// pack is preselected and every download starts from an explicit click
// (or `download_pack` from Claude after asking the owner).
//  * English: Small "base.en" (about 140 MB), Medium "small.en" (about
//    470 MB) - both English only - and Large "large-v3-turbo" (about
//    1.6 GB), which does every language and is shared.
//  * Russian, Hebrew, other languages, Automatic: Small "base", Medium
//    "small", Large "large-v3-turbo" - files for all languages, shared
//    between them and never downloaded twice. They also serve English, so
//    someone who has "base" for Russian needs no extra English pack.
//  * "tiny" models are not offered: too many mistakes to be useful.
// When several packs that can do a language are on the computer the
// largest is used unless the user picks another. Small packs make more
// mistakes, especially in Hebrew; the UI says so.
//
// The files are the standard whisper.cpp "ggml" models, used by the
// system FFmpeg's `whisper` filter and by whisper.cpp's `whisper-cli`.
// (Python whisper programs keep their own models.)
//
// The table is data: `<ClipForge>/models/models.json` (a list of entries
// with the fields of [SpeechModel.toJson]) replaces or adds entries by id,
// so a moved file or a wrong hash can be fixed without a new build.
//
// UNVERIFIED: the URLs follow the published layout
// (huggingface.co/ggerganov/whisper.cpp/resolve/main/<file>); the build
// container cannot reach that host, so no real download was made and the
// sizes are approximate. The built-in entries carry NO SHA-256 (values
// could not be checked, and a wrong one would reject a good file): a
// download is accepted when it is complete and starts like a whisper.cpp
// model file (see `looksLikeWhisperModel` in model_download.dart). An entry
// in models.json may give a sha256; a file that does not match it is kept
// as `<file>.unverified` and not used.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum SpeechQuality {
  /// The largest pack on this computer that can do the language.
  auto,
  small,
  medium,
  large;

  static SpeechQuality parse(Object? raw) => switch ('$raw'.toLowerCase()) {
        'small' || 'fast' || 'standard' => SpeechQuality.small,
        'medium' || 'better' || 'balanced' => SpeechQuality.medium,
        'large' || 'best' || 'turbo' => SpeechQuality.large,
        _ => SpeechQuality.auto,
      };

  /// "Small", "Medium", "Large".
  String get label => switch (this) {
        SpeechQuality.auto => 'Largest installed',
        SpeechQuality.small => 'Small',
        SpeechQuality.medium => 'Medium',
        SpeechQuality.large => 'Large',
      };

  /// The one-line accuracy note of a size.
  String get note => switch (this) {
        SpeechQuality.auto => '',
        SpeechQuality.small => 'quick, more mistakes',
        SpeechQuality.medium => 'good',
        SpeechQuality.large => 'best, large download',
      };
}

class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.sizeLabel,
    required this.title,
    required this.size,
    this.englishOnly = false,
  });

  /// Small / Medium / Large.
  final SpeechQuality size;

  /// "base.en", "base", "small", "large-v3-turbo": also the model name
  /// Python whisper programs understand.
  final String id;
  final String fileName;
  final String url;

  /// Lower-case hex; '' = not checked.
  final String sha256;

  /// Approximate size, for progress before the server says.
  final int sizeBytes;

  /// "about 140 MB".
  final String sizeLabel;

  /// Plain name: "English pack", "All-languages pack".
  final String title;
  final bool englishOnly;

  bool serves(String language) => !englishOnly || language == 'en';

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'url': url,
        'sha256': sha256,
        'sizeBytes': sizeBytes,
        'sizeLabel': sizeLabel,
        'title': title,
        'size': size.name,
        'englishOnly': englishOnly,
      };

  factory SpeechModel.fromJson(Map<String, dynamic> j) => SpeechModel(
        id: '${j['id']}',
        fileName: '${j['fileName']}',
        url: '${j['url']}',
        sha256: '${j['sha256'] ?? ''}'.toLowerCase(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        sizeLabel: '${j['sizeLabel'] ?? ''}',
        title: '${j['title'] ?? j['id']}',
        size: SpeechQuality.parse(j['size']),
        englishOnly: j['englishOnly'] == true,
      );
}

const String _hf = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

/// The built-in table (see the top of this file: no hashes, sizes are
/// approximate).
const List<SpeechModel> kSpeechModels = [
  SpeechModel(
    id: 'base.en',
    fileName: 'ggml-base.en.bin',
    url: '$_hf/ggml-base.en.bin',
    sha256: '',
    sizeBytes: 147964211,
    sizeLabel: 'about 140 MB',
    title: 'English only, small',
    size: SpeechQuality.small,
    englishOnly: true,
  ),
  SpeechModel(
    id: 'small.en',
    fileName: 'ggml-small.en.bin',
    url: '$_hf/ggml-small.en.bin',
    sha256: '',
    sizeBytes: 487614201,
    sizeLabel: 'about 470 MB',
    title: 'English only, medium',
    size: SpeechQuality.medium,
    englishOnly: true,
  ),
  SpeechModel(
    id: 'base',
    fileName: 'ggml-base.bin',
    url: '$_hf/ggml-base.bin',
    sha256: '',
    sizeBytes: 147951465,
    sizeLabel: 'about 140 MB',
    title: 'All languages, small',
    size: SpeechQuality.small,
  ),
  SpeechModel(
    id: 'small',
    fileName: 'ggml-small.bin',
    url: '$_hf/ggml-small.bin',
    sha256: '',
    sizeBytes: 487601967,
    sizeLabel: 'about 470 MB',
    title: 'All languages, medium',
    size: SpeechQuality.medium,
  ),
  SpeechModel(
    id: 'large-v3-turbo',
    fileName: 'ggml-large-v3-turbo.bin',
    url: '$_hf/ggml-large-v3-turbo.bin',
    sha256: '',
    sizeBytes: 1624555275,
    sizeLabel: 'about 1.6 GB',
    title: 'All languages, large',
    size: SpeechQuality.large,
  ),
];

/// The ids of the models that are [size] for [language] ("auto" / '' =
/// any language), the one offered for download first; another file of the
/// same size that is already on the computer is used instead of
/// downloading (the all-languages file also does English).
List<String> modelIdsFor(String language, SpeechQuality size) => switch (size) {
      SpeechQuality.large => const ['large-v3-turbo'],
      SpeechQuality.medium =>
        language == 'en' ? const ['small.en', 'small'] : const ['small'],
      SpeechQuality.small =>
        language == 'en' ? const ['base.en', 'base'] : const ['base'],
      SpeechQuality.auto => language == 'en'
          ? const ['large-v3-turbo', 'small.en', 'small', 'base.en', 'base']
          : const ['large-v3-turbo', 'small', 'base'],
    };

/// A language as the pack list shows it.
class LanguagePack {
  const LanguagePack(this.language, this.name, this.note);
  final String language;
  final String name;

  /// What to expect from the Small pack, honestly.
  final String note;
}

const List<LanguagePack> kLanguagePacks = [
  LanguagePack('en', 'English',
      'Good for clear speech; names and fast talk can come out wrong.'),
  LanguagePack('ru', 'Russian',
      'Usable, with more mistakes than English: check names and endings.'),
  LanguagePack('he', 'Hebrew',
      'The Small pack makes many mistakes in Hebrew. For captions you will '
          'keep, Medium or Large is worth the bigger download.'),
];

/// What the user chose for speech-to-text, kept in
/// `<ClipForge>/models/speech-settings.json` (shared by the app and by
/// Claude's tools).
class SpeechSettings {
  const SpeechSettings({this.modelPath, this.programPath, this.ffmpegPath});

  /// "A model file I already have" (a ggml .bin).
  final String? modelPath;

  /// A whisper program the user pointed at.
  final String? programPath;

  /// An FFmpeg with the whisper filter the user pointed at.
  final String? ffmpegPath;

  Map<String, dynamic> toJson() => {
        'modelPath': ?modelPath,
        'programPath': ?programPath,
        'ffmpegPath': ?ffmpegPath,
      };

  static String? _s(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  factory SpeechSettings.fromJson(Map<String, dynamic> j) => SpeechSettings(
        modelPath: _s(j['modelPath']),
        programPath: _s(j['programPath']),
        ffmpegPath: _s(j['ffmpegPath']),
      );
}

/// True when the name of a model file says it understands English only
/// (whisper.cpp's "ggml-base.en.bin").
bool isEnglishOnlyModelFile(String path) => RegExp(r'[.\-_]en([.\-_]|$)')
    .hasMatch(p.basenameWithoutExtension(p.basename(path)));

/// The user's own model file at [path] as an [InstalledModel].
InstalledModel ownModelFile(String path, int sizeBytes) {
  final name = p.basename(path);
  return InstalledModel(
      SpeechModel(
        id: p.basenameWithoutExtension(name).replaceFirst('ggml-', ''),
        fileName: name,
        url: '',
        sha256: '',
        sizeBytes: 0,
        sizeLabel: '',
        title: 'Your own model file',
        size: SpeechQuality.auto,
        englishOnly: isEnglishOnlyModelFile(name),
      ),
      path,
      sizeBytes,
      own: false);
}

/// True when the user's own model file [own] is what a request for
/// [language] ("auto" / '' = any) uses when no size was chosen: a file
/// for all languages always; an English-only file for English and for
/// Automatic (whisper is then told English).
bool ownModelServes(InstalledModel own, String language) {
  final lang = language == 'auto' ? '' : language;
  return own.model.serves(lang) || lang.isEmpty;
}

/// A model file found on this computer.
class InstalledModel {
  const InstalledModel(this.model, this.path, this.sizeBytes, {this.own = true});
  final SpeechModel model;
  final String path;
  final int sizeBytes;

  /// In ClipForge's models folder (can be removed there); false for a file
  /// the user pointed at.
  final bool own;
}

/// What a language and quality resolve to.
class ModelChoice {
  const ModelChoice({this.installed, this.download});

  /// A model that is on the computer and can be used now.
  final InstalledModel? installed;

  /// The pack to fetch when none is.
  final SpeechModel? download;
  bool get ready => installed != null;
}

/// `<ClipForge>/models/`.
class ModelStore {
  ModelStore(this.dir);
  final String dir;

  File get _settingsFile => File(p.join(dir, 'speech-settings.json'));
  File get _tableFile => File(p.join(dir, 'models.json'));

  /// The model table: the built-in one with `models.json` applied.
  List<SpeechModel> get table {
    final out = [...kSpeechModels];
    try {
      final f = _tableFile;
      if (f.existsSync()) {
        for (final e in jsonDecode(f.readAsStringSync()) as List) {
          final m = SpeechModel.fromJson((e as Map).cast<String, dynamic>());
          final i = out.indexWhere((x) => x.id == m.id);
          if (i >= 0) {
            out[i] = m;
          } else {
            out.add(m);
          }
        }
      }
    } catch (_) {
      // A broken override file is ignored.
    }
    return out;
  }

  SpeechModel? byId(String id) {
    for (final m in table) {
      if (m.id == id) return m;
    }
    return null;
  }

  SpeechSettings get settings {
    try {
      final f = _settingsFile;
      if (!f.existsSync()) return const SpeechSettings();
      return SpeechSettings.fromJson(
          (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
    } catch (_) {
      return const SpeechSettings();
    }
  }

  void saveSettings(SpeechSettings s) {
    Directory(dir).createSync(recursive: true);
    _settingsFile.writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(s.toJson()),
        flush: true);
  }

  File fileOf(SpeechModel m) => File(p.join(dir, m.fileName));
  File partOf(SpeechModel m) => File(p.join(dir, '${m.fileName}.part'));
  File unverifiedOf(SpeechModel m) =>
      File(p.join(dir, '${m.fileName}.unverified'));

  /// The packs in the models folder.
  List<InstalledModel> get installed => [
        for (final m in table)
          if (fileOf(m).existsSync())
            InstalledModel(m, fileOf(m).path, fileOf(m).lengthSync()),
      ];

  /// The user's own model file, when it is still there. Its name tells
  /// whether it is English only (whisper.cpp's "*.en.bin").
  InstalledModel? get userModel {
    final path = settings.modelPath;
    if (path == null) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    return ownModelFile(path, f.lengthSync());
  }

  /// Bytes used by packs in the folder (finished, half-fetched and
  /// unchecked ones).
  int get usedBytes {
    final d = Directory(dir);
    if (!d.existsSync()) return 0;
    var n = 0;
    for (final e in d.listSync()) {
      if (e is File &&
          (e.path.endsWith('.bin') ||
              e.path.endsWith('.part') ||
              e.path.endsWith('.unverified'))) {
        n += e.lengthSync();
      }
    }
    return n;
  }

  /// The model for [language] at [quality]. [SpeechQuality.auto]: the
  /// largest pack on the computer that can do the language, else the
  /// user's own file; nothing to download is proposed (the user picks a
  /// size). A given size: an installed file of that size, else the pack
  /// to download.
  ModelChoice choose(String language, SpeechQuality quality) {
    final lang = language == 'auto' ? '' : language;
    final own = userModel;
    final have = installed;
    // The file the user pointed at is what they want used (1.17: it was
    // only looked at after the packs, and an English-only file was never
    // usable with the language on Automatic - whisper is then told
    // English, see TranscriptionService.transcribe).
    if (quality == SpeechQuality.auto &&
        own != null &&
        ownModelServes(own, language)) {
      return ModelChoice(installed: own);
    }
    for (final id in modelIdsFor(lang, quality)) {
      for (final m in have) {
        if (m.model.id == id) return ModelChoice(installed: m);
      }
    }
    if (quality == SpeechQuality.auto) return const ModelChoice();
    return ModelChoice(download: byId(modelIdsFor(lang, quality).first));
  }

  /// The three sizes for [language] as the pack list shows them: the
  /// model each would use and whether it is on the computer.
  List<({SpeechQuality size, SpeechModel model, InstalledModel? installed})>
      packsFor(String language) {
    final lang = language == 'auto' ? '' : language;
    final have = installed;
    final out = <({SpeechQuality size, SpeechModel model, InstalledModel? installed})>[];
    for (final size in const [
      SpeechQuality.small,
      SpeechQuality.medium,
      SpeechQuality.large
    ]) {
      InstalledModel? found;
      for (final id in modelIdsFor(lang, size)) {
        for (final m in have) {
          if (m.model.id == id) found ??= m;
        }
      }
      final model = found?.model ?? byId(modelIdsFor(lang, size).first);
      if (model != null) out.add((size: size, model: model, installed: found));
    }
    return out;
  }

  /// Removes a pack (and anything half-fetched of it) to free its space.
  /// Returns the bytes freed.
  int remove(SpeechModel m) {
    var freed = 0;
    for (final f in [fileOf(m), partOf(m), unverifiedOf(m)]) {
      try {
        if (f.existsSync()) {
          freed += f.lengthSync();
          f.deleteSync();
        }
      } catch (_) {}
    }
    return freed;
  }

  /// "Use it anyway" for a pack whose check failed.
  bool acceptUnverified(SpeechModel m) {
    final f = unverifiedOf(m);
    if (!f.existsSync()) return false;
    f.renameSync(fileOf(m).path);
    return true;
  }

  /// A voice-activity model next to the packs (whisper.cpp's
  /// "ggml-silero-*.bin"), used by the FFmpeg filter when present. Never
  /// downloaded by ClipForge.
  String? get vadModelPath {
    final d = Directory(dir);
    if (!d.existsSync()) return null;
    for (final e in d.listSync()) {
      final n = p.basename(e.path).toLowerCase();
      if (e is File && n.contains('silero') && n.endsWith('.bin')) return e.path;
    }
    return null;
  }
}

/// "142 MB", "1.6 GB".
String bytesLabel(int bytes) {
  if (bytes >= 1000 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).round()} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes bytes';
}
