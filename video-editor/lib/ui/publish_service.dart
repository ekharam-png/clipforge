// What "publishing" needs from the system (1.14): a folder for a kit, the
// phone's gallery album, the share sheet, "Show in folder" and opening a
// site's upload page in the user's own browser. ClipForge never uploads
// anything and never logs in anywhere. Behind a provider so that tests
// replace it.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final publishServiceProvider =
    Provider<PublishService>((ref) => PlatformPublishService());

abstract class PublishService {
  /// True on phones: finished files are handed to the share sheet.
  bool get canShare;

  /// Computers: lets the user pick the folder a kit goes into (once per
  /// kit). Null when cancelled.
  Future<String?> chooseFolder();

  /// Phones: a folder in the app's own storage for the kit of the project
  /// called [name] (videos are then copied into the gallery).
  Future<String> appKitFolder(String name);

  /// Phones: puts the video at [path] into the gallery album [album] (made
  /// when it does not exist). Returns where it went in words, or null when
  /// the user did not allow it. The file itself stays (it is shared from
  /// there).
  Future<String?> saveToAlbum(String path, String album);

  /// Computers: opens the file manager with [path] selected.
  Future<void> showInFolder(String path);

  /// Opens [url] (https only) in the user's own browser.
  Future<void> openUrl(String url);

  /// Phones: the system share sheet with [paths]; [text] goes along where
  /// the receiving app takes it (many ignore it). False when dismissed.
  Future<bool> share(List<String> paths, {String? text, String? subject});
}

class PlatformPublishService implements PublishService {
  static const _channel = MethodChannel('clipforge/update');

  @override
  bool get canShare => Platform.isAndroid || Platform.isIOS;

  @override
  Future<String?> chooseFolder() async {
    if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
    return FilePicker.getDirectoryPath(
        dialogTitle: 'Choose the folder for the files');
  }

  @override
  Future<String> appKitFolder(String name) async {
    Directory? base;
    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'exports', name));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// NOTE: phone-only path (the `gal` plugin has no desktop side).
  @override
  Future<String?> saveToAlbum(String path, String album) async {
    if (!canShare) throw UnsupportedError('The gallery is only on phones');
    if (!await Gal.requestAccess(toAlbum: true)) return null;
    await Gal.putVideo(path, album: album);
    return 'your gallery, album "$album"';
  }

  @override
  Future<void> showInFolder(String path) async {
    if (Platform.isWindows) {
      await Process.start('explorer', ['/select,', path],
          mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      final dir = FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
      await Process.start('xdg-open', [dir], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<void> openUrl(String url) async {
    // Only ever a site's own page from the destinations table.
    if (!url.startsWith('https://')) return;
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } else if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  }

  /// NOTE: phone-only path. share_plus copies the files to its own cache
  /// and grants the receiving app access through a FileProvider.
  @override
  Future<bool> share(List<String> paths,
      {String? text, String? subject}) async {
    final result = await SharePlus.instance.share(ShareParams(
      files: [for (final path in paths) XFile(path)],
      text: text == null || text.trim().isEmpty ? null : text,
      subject: subject,
    ));
    return result.status != ShareResultStatus.dismissed;
  }
}
