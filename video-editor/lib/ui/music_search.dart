import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/build_info.dart';
import '../core/music/openverse.dart';

/// "Add music" > "Find free music": searching and downloading openly
/// licensed music (Openverse, core/music/openverse.dart). Behind a provider
/// so tests use recorded answers.
abstract class MusicSearch {
  const MusicSearch();

  /// False where the search is not offered (tests that do not set one).
  bool get available;

  Future<MusicSearchPage> search(String query,
      {bool includeRestricted = false, int page = 1});

  /// Saves [result] in the app media folder (`<mediaDir>/music/<id>/`) and
  /// returns its path; a file downloaded before is reused.
  Future<String> download(MusicResult result, String mediaDir,
      {void Function(double fraction)? onProgress});
}

class NoMusicSearch extends MusicSearch {
  const NoMusicSearch();
  @override
  bool get available => false;
  @override
  Future<MusicSearchPage> search(String query,
          {bool includeRestricted = false, int page = 1}) async =>
      const MusicSearchPage(results: []);
  @override
  Future<String> download(MusicResult result, String mediaDir,
          {void Function(double fraction)? onProgress}) =>
      throw const MusicSearchException('Music search is not available.');
}

/// Folder for a downloaded piece of music.
String musicDownloadPath(MusicResult r, String mediaDir) => p.join(
    mediaDir, 'music', r.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'), r.fileName);

class OpenverseMusicSearch extends MusicSearch {
  OpenverseMusicSearch({OpenverseClient? client})
      : _client = client ?? OpenverseClient(userAgent: _agent);

  static String get _agent =>
      'ClipForge/${BuildInfo.current.version} (personal video editor)';

  final OpenverseClient _client;

  @override
  bool get available => true;

  @override
  Future<MusicSearchPage> search(String query,
          {bool includeRestricted = false, int page = 1}) =>
      _client.search(query, includeRestricted: includeRestricted, page: page);

  @override
  Future<String> download(MusicResult result, String mediaDir,
      {void Function(double fraction)? onProgress}) async {
    final path = musicDownloadPath(result, mediaDir);
    final f = File(path);
    if (await f.exists() && await f.length() > 0) {
      try {
        await f.setLastModified(DateTime.now());
      } catch (_) {}
      onProgress?.call(1);
      return path;
    }
    await downloadMusicFile(result.url, path,
        expectedBytes: result.fileSize,
        onProgress: onProgress,
        userAgent: _agent);
    return path;
  }
}

final musicSearchProvider =
    Provider<MusicSearch>((ref) => OpenverseMusicSearch());
