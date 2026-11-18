import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A file on the phone found by [GallerySearch.findByName].
class GalleryItem {
  const GalleryItem({
    required this.uri,
    required this.name,
    this.sizeBytes = 0,
    this.modified,
    this.folder,
  });

  /// Where the system keeps it (content:// address).
  final String uri;
  final String name;
  final int sizeBytes;
  final DateTime? modified;

  /// Folder as the phone shows it ("DCIM/Camera/"), when known.
  final String? folder;
}

/// Why a gallery search found nothing usable.
class GallerySearchDenied implements Exception {
  const GallerySearchDenied();
  @override
  String toString() => 'No access to the photos and videos on this phone';
}

/// "Find file…" > "Search the gallery": looks for a missing file by its
/// name among the phone's photos, videos and music (Android MediaStore,
/// channel `clipforge/gallery` in MainActivity). Asks for the "photos and
/// videos" / "music" permission the first time. Elsewhere [supported] is
/// false and the normal file picker is used.
abstract class GallerySearch {
  const GallerySearch();

  bool get supported;

  /// Files called [name] (any upper/lower case), newest first, at most 20.
  /// Throws [GallerySearchDenied] when the user refused access.
  Future<List<GalleryItem>> findByName(String name);

  /// Copies [item] to a temporary file and returns its path (the caller
  /// keeps it in the app media folder).
  Future<String> fetch(GalleryItem item);
}

class NoGallerySearch extends GallerySearch {
  const NoGallerySearch();
  @override
  bool get supported => false;
  @override
  Future<List<GalleryItem>> findByName(String name) async => const [];
  @override
  Future<String> fetch(GalleryItem item) =>
      throw UnsupportedError('No gallery here');
}

class AndroidGallerySearch extends GallerySearch {
  const AndroidGallerySearch();
  static const _channel = MethodChannel('clipforge/gallery');

  @override
  bool get supported => true;

  @override
  Future<List<GalleryItem>> findByName(String name) async {
    try {
      final list = await _channel
          .invokeListMethod<Map<Object?, Object?>>('find', {'name': name});
      return [
        for (final m in list ?? const <Map<Object?, Object?>>[])
          GalleryItem(
            uri: m['uri'] as String,
            name: m['name'] as String? ?? name,
            sizeBytes: (m['size'] as num?)?.toInt() ?? 0,
            modified: m['modified'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (m['modified'] as num).toInt())
                : null,
            folder: m['folder'] as String?,
          ),
      ];
    } on PlatformException catch (e) {
      if (e.code == 'permission') throw const GallerySearchDenied();
      rethrow;
    }
  }

  @override
  Future<String> fetch(GalleryItem item) async {
    final dir = Directory(p.join(
        (await getTemporaryDirectory()).path,
        'gallery',
        DateTime.now().microsecondsSinceEpoch.toString()));
    await dir.create(recursive: true);
    final path = p.join(dir.path, p.basename(item.name));
    await _channel.invokeMethod<int>('copy', {'uri': item.uri, 'path': path});
    return path;
  }
}

final gallerySearchProvider = Provider<GallerySearch>((ref) =>
    Platform.isAndroid ? const AndroidGallerySearch() : const NoGallerySearch());
