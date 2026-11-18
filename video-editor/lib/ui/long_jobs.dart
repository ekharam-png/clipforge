import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

/// What a long export needs from the device: how much room the target disk
/// has, and keeping the app running (and the device awake) until it ends.
///
/// [instance] is the platform's; tests get [LongJobSupport.none] (the
/// FLUTTER_TEST environment variable) and may put a fake there.
abstract class LongJobSupport {
  const LongJobSupport();

  static LongJobSupport instance =
      Platform.environment.containsKey('FLUTTER_TEST')
          ? const _NoSupport()
          : _PlatformSupport();

  /// Does nothing and knows nothing.
  static const LongJobSupport none = _NoSupport();

  /// Free bytes on the disk that holds [directory] (or the nearest folder
  /// above it that exists); null when that cannot be told.
  Future<int?> freeBytes(String directory);

  /// An export started: keep the device awake and, on Android, the app
  /// running in the background (a foreground service with a notification
  /// that says [text]).
  Future<void> exportStarted({required String title, required String text});

  /// The export ended (any way).
  Future<void> exportEnded();
}

class _NoSupport extends LongJobSupport {
  const _NoSupport();

  @override
  Future<int?> freeBytes(String directory) async => null;

  @override
  Future<void> exportStarted(
      {required String title, required String text}) async {}

  @override
  Future<void> exportEnded() async {}
}

class _PlatformSupport extends LongJobSupport {
  static const _channel = MethodChannel('clipforge/long_jobs');

  @override
  Future<int?> freeBytes(String directory) async {
    try {
      final dir = _existing(directory);
      if (dir == null) return null;
      return await _freeBytes(dir).timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }

  static String? _existing(String directory) {
    var d = directory;
    for (var i = 0; i < 40; i++) {
      if (Directory(d).existsSync()) return d;
      final up = p.dirname(d);
      if (up == d) return null;
      d = up;
    }
    return null;
  }

  Future<int?> _freeBytes(String dir) async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<int>('freeBytes', {'path': dir});
    }
    if (Platform.isWindows) {
      final quoted = dir.replaceAll("'", "''");
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "[System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot('$quoted'))"
            '.AvailableFreeSpace',
      ], stdoutEncoding: utf8);
      return r.exitCode == 0 ? int.tryParse('${r.stdout}'.trim()) : null;
    }
    // Linux, macOS: POSIX df, 1024-byte blocks; the 4th field of the
    // second line is what is available.
    final r = await Process.run('df', ['-Pk', dir], stdoutEncoding: utf8);
    if (r.exitCode != 0) return null;
    return parseDfAvailableBytes('${r.stdout}');
  }

  @override
  Future<void> exportStarted(
      {required String title, required String text}) async {
    await _quietly(WakelockPlus.enable);
    if (Platform.isAndroid) {
      await _quietly(() =>
          _channel.invokeMethod<bool>('startExport', {'title': title, 'text': text}));
    }
  }

  @override
  Future<void> exportEnded() async {
    if (Platform.isAndroid) {
      await _quietly(() => _channel.invokeMethod<bool>('stopExport'));
    }
    await _quietly(WakelockPlus.disable);
  }

  static Future<void> _quietly(Future<Object?> Function() call) async {
    try {
      await call().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Keeping awake is a help, not a condition for exporting.
    }
  }
}

/// The available bytes in the output of `df -Pk <dir>`; null when it
/// cannot be read.
int? parseDfAvailableBytes(String output) {
  final lines = const LineSplitter()
      .convert(output)
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  // A long device name can push the numbers onto the next line; the
  // numbers are the last fields either way: blocks used available
  // capacity mount.
  final fields = lines.sublist(1).join(' ').trim().split(RegExp(r'\s+'));
  final percent = fields.indexWhere((f) => RegExp(r'^\d+%$').hasMatch(f));
  if (percent < 1) return null;
  final kb = int.tryParse(fields[percent - 1]);
  return kb == null ? null : kb * 1024;
}
