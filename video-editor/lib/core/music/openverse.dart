// Free music search through Openverse (https://openverse.org, run by the
// WordPress project): a catalogue of openly licensed audio from Jamendo,
// Freesound, Wikimedia Commons, ccMixter and others. Pure Dart (dart:io
// HttpClient), so it is unit-tested with recorded answers.
//
// API: GET https://api.openverse.org/v1/audio/?q=<words>&license=<codes>
//   &page_size=<n>&page=<n>&mature=false
// Anonymous use needs no key (rate-limited; light use only). Answer:
//   {result_count, page_count, page_size, page,
//    results: [{id, title, creator, creator_url, url (the audio file),
//      foreign_landing_url, license (cc0|pdm|by|by-sa|by-nc|...),
//      license_version, license_url, provider, source, filetype, filesize,
//      duration (ms, may be null), attribution, mature, genres, tags, ...}]}
// NOTE: written against the documented format; this build container could
// not reach api.openverse.org, so the live service is unverified.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/project.dart';

/// Licences safe for personal videos shared on social media: no
/// "non-commercial" (a monetised post may count as commercial) and no
/// "no derivatives" (putting music under a video is an adaptation).
const List<String> kSafeMusicLicences = ['cc0', 'pdm', 'by', 'by-sa'];

/// Added by "Also show music with stricter licences".
const List<String> kRestrictedMusicLicences = [
  'by-nc',
  'by-nc-sa',
  'by-nd',
  'by-nc-nd',
];

const String kOpenverseAudioUrl = 'https://api.openverse.org/v1/audio/';

/// Results per page (anonymous use allows up to 20).
const int kMusicPageSize = 20;

/// One piece of music found.
class MusicResult {
  const MusicResult({
    required this.id,
    required this.title,
    required this.creator,
    required this.url,
    required this.licence,
    this.licenceVersion = '',
    this.licenceUrl = '',
    this.landingUrl = '',
    this.provider = '',
    this.fileType = '',
    this.fileSize = 0,
    this.durationMs = 0,
    this.attribution = '',
  });

  final String id;
  final String title;
  final String creator;

  /// The audio file (streamed for a preview, downloaded to use it).
  final String url;
  final String licence;
  final String licenceVersion;
  final String licenceUrl;
  final String landingUrl;
  final String provider;
  final String fileType;
  final int fileSize;

  /// 0 when unknown.
  final int durationMs;
  final String attribution;

  String get licenceName => musicLicenceName(licence, licenceVersion);

  bool get safe => kSafeMusicLicences.contains(licence);

  MusicCredit get credit => MusicCredit(
        title: title,
        creator: creator,
        licence: licence,
        licenceVersion: licenceVersion,
        licenceUrl: licenceUrl,
        sourceUrl: landingUrl,
        provider: provider,
        attribution: attribution,
      );

  /// File name for the download: `<title> - <creator>.<ext>`.
  String get fileName {
    String clean(String s) =>
        s.replaceAll(RegExp(r'[\x00-\x1f/\\:*?"<>|]'), '_').trim();
    var ext = fileType.toLowerCase().replaceAll('.', '');
    if (ext.isEmpty) {
      final path = Uri.tryParse(url)?.path ?? '';
      final dot = path.lastIndexOf('.');
      ext = dot >= 0 && path.length - dot <= 5
          ? path.substring(dot + 1).toLowerCase()
          : 'mp3';
    }
    final base = [clean(title), if (creator.trim().isNotEmpty) clean(creator)]
        .where((s) => s.isNotEmpty)
        .join(' - ');
    final short = base.length > 80 ? base.substring(0, 80) : base;
    return '${short.isEmpty ? id : short}.$ext';
  }

  static MusicResult? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final url = j['url'];
    if (id is! String || url is! String || url.isEmpty) return null;
    String str(String key) => j[key] is String ? j[key] as String : '';
    return MusicResult(
      id: id,
      title: str('title').trim().isEmpty ? 'Untitled' : str('title').trim(),
      creator: str('creator').trim(),
      url: url,
      licence: str('license').toLowerCase(),
      licenceVersion: str('license_version'),
      licenceUrl: str('license_url'),
      landingUrl: str('foreign_landing_url'),
      provider: str('source').isNotEmpty ? str('source') : str('provider'),
      fileType: str('filetype'),
      fileSize: (j['filesize'] as num?)?.toInt() ?? 0,
      durationMs: (j['duration'] as num?)?.toInt() ?? 0,
      attribution: str('attribution'),
    );
  }
}

class MusicSearchPage {
  const MusicSearchPage(
      {required this.results, this.total = 0, this.page = 1, this.pages = 1});
  final List<MusicResult> results;
  final int total;
  final int page;
  final int pages;
  bool get hasMore => page < pages;
}

/// Why a search did not work, in words for the user.
class MusicSearchException implements Exception {
  const MusicSearchException(this.message, {this.offline = false});
  final String message;
  final bool offline;
  @override
  String toString() => message;
}

/// Gets a URL's body as text (tests replace it with recorded answers).
typedef HttpGetText = Future<String> Function(Uri uri);

/// The search request for [query] ([includeRestricted]: also NC / ND).
Uri openverseSearchUri(String query,
        {bool includeRestricted = false, int page = 1}) =>
    Uri.parse(kOpenverseAudioUrl).replace(queryParameters: {
      'q': query.trim(),
      'license': [
        ...kSafeMusicLicences,
        if (includeRestricted) ...kRestrictedMusicLicences,
      ].join(','),
      'page_size': '$kMusicPageSize',
      'page': '$page',
      'mature': 'false',
    });

/// Parses an Openverse audio search answer. Results with a licence that
/// was not asked for are dropped (the server is not trusted to filter),
/// and so are results without a file.
MusicSearchPage parseOpenverseAudio(String body,
    {bool includeRestricted = false}) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw const MusicSearchException(
        'The music search sent an answer ClipForge does not understand.');
  }
  if (json is! Map<String, dynamic>) {
    throw const MusicSearchException(
        'The music search sent an answer ClipForge does not understand.');
  }
  final allowed = {
    ...kSafeMusicLicences,
    if (includeRestricted) ...kRestrictedMusicLicences,
  };
  final results = <MusicResult>[];
  for (final item in (json['results'] as List? ?? const [])) {
    if (item is! Map<String, dynamic>) continue;
    if (item['mature'] == true) continue;
    final r = MusicResult.fromJson(item);
    if (r == null || !allowed.contains(r.licence)) continue;
    results.add(r);
  }
  return MusicSearchPage(
    results: results,
    total: (json['result_count'] as num?)?.toInt() ?? results.length,
    page: (json['page'] as num?)?.toInt() ?? 1,
    pages: (json['page_count'] as num?)?.toInt() ?? 1,
  );
}

/// Searches Openverse. [get] defaults to a dart:io request with a
/// ClipForge user agent and a 15 s timeout.
class OpenverseClient {
  OpenverseClient(
      {HttpGetText? get, this.userAgent = 'ClipForge (personal video editor)'})
      : getText = get;

  /// Replaces the network request (tests).
  final HttpGetText? getText;
  final String userAgent;

  Future<MusicSearchPage> search(String query,
      {bool includeRestricted = false, int page = 1}) async {
    if (query.trim().isEmpty) return const MusicSearchPage(results: []);
    final uri = openverseSearchUri(query,
        includeRestricted: includeRestricted, page: page);
    final body = await (getText ?? _httpGet)(uri);
    return parseOpenverseAudio(body, includeRestricted: includeRestricted);
  }

  Future<String> _httpGet(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent;
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429) {
        throw const MusicSearchException(
            'The free music search is busy (too many searches). Try again '
            'in a few minutes.');
      }
      if (res.statusCode != 200) {
        throw MusicSearchException(
            'The music search did not answer (error ${res.statusCode}). '
            'Try again later.');
      }
      return body;
    } on SocketException {
      throw offlineError;
    } on HandshakeException {
      throw offlineError;
    } on HttpException {
      throw offlineError;
    } on TimeoutException {
      throw offlineError;
    } finally {
      client.close(force: true);
    }
  }
}

const MusicSearchException offlineError = MusicSearchException(
    'No connection to the internet (or the music search cannot be '
    'reached). Check the connection and try again; your own music files '
    'still work.',
    offline: true);

/// Downloads [url] to [path] (via `<path>.part`), reporting 0..1 (by the
/// size the server gives, else [expectedBytes]). Throws
/// [MusicSearchException] on any failure; a half file is removed.
Future<void> downloadMusicFile(String url, String path,
    {int expectedBytes = 0,
    void Function(double fraction)? onProgress,
    String userAgent = 'ClipForge (personal video editor)'}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = userAgent;
  final part = File('$path.part');
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw MusicSearchException(
          'The music file could not be downloaded (error ${res.statusCode}).');
    }
    final total = res.contentLength > 0 ? res.contentLength : expectedBytes;
    await part.parent.create(recursive: true);
    final sink = part.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
      }
    } finally {
      await sink.close();
    }
    if (got == 0) {
      throw const MusicSearchException('The music file was empty.');
    }
    await part.rename(path);
    onProgress?.call(1);
  } on MusicSearchException {
    rethrow;
  } on SocketException {
    throw offlineError;
  } on TimeoutException {
    throw offlineError;
  } on HttpException {
    throw offlineError;
  } on HandshakeException {
    throw offlineError;
  } finally {
    client.close(force: true);
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }
}

/// The credits of every downloaded piece of music in [project], once each,
/// in order of first use.
List<MusicCredit> projectCredits(Project project) {
  final out = <MusicCredit>[];
  for (final a in project.audio) {
    final c = a.credit;
    if (c != null && !out.contains(c)) out.add(c);
  }
  return out;
}

/// The "Credits" text to copy into a post: one line per piece of music.
String creditsText(Project project) =>
    [for (final c in projectCredits(project)) c.fullLine].join('\n');

/// The short credits for a caption at the end of the video.
String creditsCaption(Project project) =>
    [for (final c in projectCredits(project)) c.shortLine].join('\n');
