// Makes the bundled DejaVu fonts available as real files, because ffmpeg's
// drawtext needs a file path (Flutter assets live inside the app bundle).
//
// This file needs Flutter. Plain-Dart programs give ProcessMediaEngine the
// paths of the .ttf files instead (its `fonts` / `fontResolver` arguments).

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/model/title_layout.dart' show allTitleFontFiles;
import 'ffmpeg_command.dart';

export 'ffmpeg_command.dart' show FontPaths, FontResolver;

const String kFontAssetRegular = 'assets/fonts/DejaVuSans.ttf';
const String kFontAssetBold = 'assets/fonts/DejaVuSans-Bold.ttf';

Future<FontPaths>? _cached;

/// Copies the bundled fonts to the application support directory (once per
/// run; files are rewritten only when missing or of a different size).
Future<FontPaths> bundledFonts() {
  return _cached ??= _extract().catchError((Object e) {
    _cached = null;
    throw e;
  });
}

Future<FontPaths> _extract() async {
  Directory base;
  try {
    base = await getApplicationSupportDirectory();
  } catch (_) {
    base = Directory.systemTemp;
  }
  final preferred = p.join(base.path, 'clipforge_fonts');
  var dir = Directory(preferred);
  if (Platform.isWindows) {
    for (final candidate in fontDirCandidates(preferred, Platform.environment)) {
      try {
        final d = Directory(candidate);
        await d.create(recursive: true);
        final probe = File(p.join(candidate, '.write_test'));
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        dir = d;
        break;
      } catch (_) {
        // Not writable here; try the next place.
      }
    }
  }
  await dir.create(recursive: true);
  Future<String> copy(String asset) async {
    final data = await rootBundle.load(asset);
    final file = File(p.join(dir.path, p.basename(asset)));
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
    }
    return file.path;
  }

  // The other title fonts (Rubik, Bona Nova, Amatic SC); one that cannot
  // be unpacked is drawn in DejaVu Sans instead.
  final files = <String, String>{};
  for (final name in allTitleFontFiles) {
    if (name == p.basename(kFontAssetRegular) ||
        name == p.basename(kFontAssetBold)) {
      continue;
    }
    try {
      files[name] = await copy('assets/fonts/$name');
    } catch (_) {}
  }
  return FontPaths(
    regular: await copy(kFontAssetRegular),
    bold: await copy(kFontAssetBold),
    files: files,
  );
}

/// Where to put the font files on Windows, best first.
///
/// FFmpeg's drawtext hands the font path to FreeType, which on Windows
/// opens it with `CreateFileA` (checked in the bundled libfreetype-6.dll:
/// it imports CreateFileA, not CreateFileW). That reads the path in the
/// computer's ANSI code page, not UTF-8, so a font under a user folder with
/// letters outside plain ASCII (C:\Users\Евгений\AppData\...) cannot be
/// opened and every export with a title fails. Such a [preferred] folder
/// is therefore tried last, after ASCII-only shared folders (ProgramData,
/// then the Public user folder).
List<String> fontDirCandidates(String preferred, Map<String, String> env) {
  bool ascii(String s) => s.codeUnits.every((c) => c < 0x80);
  if (ascii(preferred)) return [preferred];
  return [
    for (final v in [env['ProgramData'], env['PUBLIC']])
      if (v != null && v.isNotEmpty && ascii(v))
        p.windows.join(v, 'ClipForge', 'fonts'),
    preferred,
  ];
}
