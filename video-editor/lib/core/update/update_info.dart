// "Is there a newer ClipForge?" - the one small file the app reads from
// the internet (latest.json, published with every release) and the rules
// around it: newer / same / older build, "skip this version", at most one
// automatic check a day. Pure Dart (dart:io for the request).
//
// latest.json (written by the release job of the build workflow):
//
//   {"version":"1.12.0","build":142,"date":"2026-11-18T10:00:00Z",
//    "notes_url":"https://.../releases/tag/v1.12.0",
//    "platforms":{
//      "windows":  {"url":"https://.../ClipForge-windows.zip","size":123,"sha256":"..."},
//      "macos":    {...}, "android": {...}},
//    "links":{"site":"https://...","download":"https://.../install",
//      "feedback_api":"https://.../api/feedback","feedback_page":"...",
//      "help":"...","privacy":"..."}}
//
// "links" (1.16, optional) are the outside addresses of the moment, from
// tool/ci/links.json; lib/core/links.dart checks them before they are used.
//
// (Until 1.14 there was also a 32-bit Android file. It is no longer built: a
// 32-bit phone finds no file for itself and is offered the download page.)
//
// Files made before 1.12 have no "platforms": the app then only offers the
// download page.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../links.dart';


/// At most one automatic check in this time.
const Duration kAutoCheckEvery = Duration(hours: 24);

/// One downloadable file of a release.
class UpdateAsset {
  const UpdateAsset({required this.url, required this.size, required this.sha256});
  final String url;

  /// Bytes; the download must have exactly this length.
  final int size;

  /// Lower-case hex; the download must hash to this.
  final String sha256;

  /// The last part of the address, e.g. "ClipForge-windows.zip".
  String get fileName {
    final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? 'ClipForge-update' : segments.last;
  }

  static UpdateAsset? fromJson(Object? json, {bool allowHttp = false}) {
    if (json is! Map) return null;
    final url = json['url'], size = json['size'], hash = json['sha256'];
    if (url is! String || size is! num || hash is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    // Downloads only over an encrypted connection (tests use a local server).
    if (uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) return null;
    final sum = hash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sum) || size <= 0) return null;
    return UpdateAsset(url: url, size: size.toInt(), sha256: sum);
  }
}

/// What latest.json says.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    this.date,
    this.notesUrl,
    this.platforms = const {},
    this.links,
  });

  /// e.g. "1.12.0".
  final String version;

  /// The build number; a higher one is newer.
  final int build;
  final DateTime? date;

  /// The release notes page ("What's new").
  final String? notesUrl;

  /// "windows", "macos", "android" -> the file for it.
  final Map<String, UpdateAsset> platforms;

  /// The outside addresses of the moment ("site", "download", ... as
  /// text, not checked yet: [AppLinks.withOverrides] does that); null in
  /// files made before 1.16.
  final Map<String, String>? links;

  /// Parses the text of latest.json; a [FormatException] when it is not
  /// what a release writes.
  static UpdateInfo parse(String text, {bool allowHttp = false}) {
    // Windows tools like to put a byte order mark first.
    final clean = text.startsWith('﻿') ? text.substring(1) : text;
    final Object? json;
    try {
      json = jsonDecode(clean);
    } on FormatException {
      throw const FormatException('latest.json is not JSON');
    }
    if (json is! Map) throw const FormatException('latest.json is not an object');
    final version = json['version'], build = json['build'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('latest.json has no version');
    }
    final number = build is num ? build.toInt() : int.tryParse('$build');
    if (number == null || number <= 0) {
      throw const FormatException('latest.json has no build number');
    }
    final notes = json['notes_url'];
    final notesUri = notes is String ? Uri.tryParse(notes) : null;
    final platforms = <String, UpdateAsset>{};
    final raw = json['platforms'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final asset = UpdateAsset.fromJson(e.value, allowHttp: allowHttp);
        if (asset != null) platforms['${e.key}'] = asset;
      }
    }
    return UpdateInfo(
      version: version.trim(),
      build: number,
      date: json['date'] is String ? DateTime.tryParse(json['date'] as String) : null,
      notesUrl: notesUri != null &&
              (notesUri.scheme == 'https' || (allowHttp && notesUri.scheme == 'http'))
          ? notes as String
          : null,
      platforms: platforms,
      links: readLinksObject(json['links']),
    );
  }

  /// True when this release is newer than the running [currentBuild]
  /// (null = unknown build, e.g. run from source: never "newer").
  bool isNewerThan(int? currentBuild) => currentBuild != null && build > currentBuild;
}

/// Why a check or download did not work; [message] is for the user.
class UpdateException implements Exception {
  UpdateException(this.message, {this.kind = 'failed', this.detail});
  final String message;

  /// "offline", "failed", "check" (size or fingerprint wrong), "stopped".
  final String kind;
  final String? detail;
  @override
  String toString() => detail == null ? message : '$message [$detail]';
}

/// Reads latest.json from [url]. Throws an [UpdateException] (offline,
/// server error, not the expected file).
Future<UpdateInfo> fetchUpdateInfo(
  Uri url, {
  HttpClient Function()? client,
  Duration timeout = const Duration(seconds: 15),
  bool allowHttp = false,
}) async {
  final http = (client ?? HttpClient.new)();
  http.userAgent = 'ClipForge (update check)';
  http.connectionTimeout = timeout;
  try {
    final request = await http.getUrl(url).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(timeout, onTimeout: () {});
      throw UpdateException(
          'The update information could not be read (the server answered '
          '${response.statusCode}). Try again later.',
          detail: 'HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      // The real file is a few hundred bytes.
      if (bytes.length > 256 * 1024) {
        throw UpdateException('The update information is not what ClipForge expected.',
            detail: 'latest.json larger than 256 KB');
      }
    }
    try {
      return UpdateInfo.parse(utf8.decode(bytes, allowMalformed: true),
          allowHttp: allowHttp);
    } on FormatException catch (e) {
      throw UpdateException('The update information is not what ClipForge expected.',
          detail: e.message);
    }
  } on UpdateException {
    rethrow;
  } on TimeoutException {
    throw UpdateException(
        'ClipForge could not reach the update server. Check the internet '
        'connection and try again.',
        kind: 'offline');
  } on IOException catch (e) {
    throw UpdateException(
        'ClipForge could not reach the update server. Check the internet '
        'connection and try again.',
        kind: 'offline',
        detail: '$e');
  } finally {
    http.close(force: true);
  }
}

/// Whether the automatic check may run now: not switched off, and the last
/// one (automatic or by hand) is at least [kAutoCheckEvery] ago. A last
/// check "in the future" (clock changed) counts as never.
bool autoCheckDue({
  required bool switchedOff,
  required DateTime? lastCheck,
  required DateTime now,
  Duration every = kAutoCheckEvery,
}) {
  if (switchedOff) return false;
  if (lastCheck == null || lastCheck.isAfter(now)) return true;
  return now.difference(lastCheck) >= every;
}

/// Whether the "Version X is available" banner shows for [info]: a newer
/// build that the user did not choose to skip. A check by hand
/// ([manual]) shows a skipped version again.
bool offerUpdate(UpdateInfo info,
        {required int? currentBuild, int? skippedBuild, bool manual = false}) =>
    info.isNewerThan(currentBuild) && (manual || skippedBuild != info.build);

/// The key in [UpdateInfo.platforms] for this device, or null where the
/// app cannot install an update itself (Linux, and an Android phone that
/// is [only32Bit], for which no file is built since 1.15: download page
/// only).
String? updatePlatformKey(String operatingSystem, {bool only32Bit = false}) =>
    switch (operatingSystem) {
      'windows' => 'windows',
      'macos' => 'macos',
      'android' => only32Bit ? null : 'android',
      _ => null,
    };
