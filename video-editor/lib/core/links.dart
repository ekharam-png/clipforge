// The outside addresses of ClipForge, in ONE place (1.16).
//
// - The built-in defaults below are a copy of tool/ci/links.json (a test
//   fails when the two differ, and when the site's address is written
//   anywhere else in lib/, tool/ or web/).
// - They can change without a new build: every release writes the same
//   addresses into latest.json ("links"), the app remembers the last ones
//   it saw (see lib/ui/links.dart) and uses them over the defaults.
// - What arrives from the internet is checked here: https only, a sane
//   length, and the feedback address must be on the site's own host (or on
//   one of [kFeedbackApiHosts]); anything else is ignored.
//
// Pure Dart: the app and clipforge-mcp both use it.

/// The name people see. A rename starts here; docs/RENAMING.md lists what
/// else it touches and what must stay as it is.
const String kAppName = 'ClipForge';

/// The website.
const String _site = 'https://clipforge-ek.vercel.app';

/// The project on GitHub: the releases (and latest.json) live there.
const String kRepositoryUrl = 'https://github.com/ekharam-png/clipforge';

/// Every published version.
const String kReleasesUrl = '$kRepositoryUrl/releases';

/// Where the newest release describes itself. Stays on GitHub and is NOT
/// one of the addresses latest.json can change (it would be changing its
/// own address).
const String kLatestJsonUrl = '$kReleasesUrl/latest/download/latest.json';

/// Hosts, besides the site's own, that feedback may be sent to (the same
/// list as "feedback_api_hosts" in tool/ci/links.json).
const List<String> kFeedbackApiHosts = [];

/// No address is longer than this.
const int kLinkMaxLength = 200;

/// The names of the addresses in latest.json's "links" (and links.json).
const List<String> kLinkNames = [
  'site',
  'download',
  'feedback_api',
  'feedback_page',
  'help',
  'privacy',
];

class AppLinks {
  const AppLinks({
    required this.site,
    required this.download,
    required this.feedbackApi,
    required this.feedbackPage,
    required this.help,
    required this.privacy,
  });

  /// What this build was made with.
  static const AppLinks builtIn = AppLinks(
    site: _site,
    download: '$_site/install',
    feedbackApi: '$_site/api/feedback',
    feedbackPage: '$_site/feedback',
    help: '$_site/help',
    privacy: '$_site/privacy',
  );

  /// The website's first page.
  final String site;

  /// The page people download ClipForge from (plan B for every update).
  final String download;

  /// Where "Send feedback" posts to.
  final String feedbackApi;

  /// The feedback form on the website (plan B for "Send feedback").
  final String feedbackPage;

  /// The help articles on the website.
  final String help;

  /// What the website and the app do with what they learn: nothing.
  final String privacy;

  /// The site's address without "https://", for showing it.
  String get siteLabel => site.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/+$'), '');

  Map<String, String> toJson() => {
        'site': site,
        'download': download,
        'feedback_api': feedbackApi,
        'feedback_page': feedbackPage,
        'help': help,
        'privacy': privacy,
      };

  /// These addresses with the valid ones of [json] (latest.json's "links",
  /// or what was remembered from it) in their place. A value that is not
  /// text, not https, too long or otherwise odd is ignored, one by one;
  /// a feedback address on a foreign host is ignored too.
  /// [allowHttp]: tests use a local server.
  AppLinks withOverrides(Object? json, {bool allowHttp = false}) {
    if (json is! Map) return this;
    String pick(String name, String now) =>
        checkedLink(json[name], allowHttp: allowHttp) ?? now;
    final newSite = pick('site', site);
    final api = checkedLink(json['feedback_api'], allowHttp: allowHttp);
    final siteHost = Uri.parse(newSite).host;
    final apiOk = api != null &&
        (Uri.parse(api).host == siteHost ||
            kFeedbackApiHosts.contains(Uri.parse(api).host));
    return AppLinks(
      site: newSite,
      download: pick('download', download),
      feedbackApi: apiOk ? api : feedbackApi,
      feedbackPage: pick('feedback_page', feedbackPage),
      help: pick('help', help),
      privacy: pick('privacy', privacy),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppLinks &&
      other.site == site &&
      other.download == download &&
      other.feedbackApi == feedbackApi &&
      other.feedbackPage == feedbackPage &&
      other.help == help &&
      other.privacy == privacy;

  @override
  int get hashCode =>
      Object.hash(site, download, feedbackApi, feedbackPage, help, privacy);

  @override
  String toString() => 'AppLinks(${toJson()})';
}

/// [value] when it is an address the app may open or post to, else null:
/// text, at most [kLinkMaxLength] characters, https (http only with
/// [allowHttp], for tests), a host, no user name or password in it, no
/// spaces or control characters.
String? checkedLink(Object? value, {bool allowHttp = false}) {
  if (value is! String) return null;
  if (value.isEmpty || value.length > kLinkMaxLength) return null;
  if (RegExp(r'[\s\u0000-\u001F\u007F"<>\\^`{|}]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) return null;
  if (uri.userInfo.isNotEmpty) return null;
  // A name with a dot, or (tests) this computer.
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (!uri.host.contains('.') && !(allowHttp && local)) return null;
  return value;
}

/// The text map of latest.json's "links" (only known names with text
/// values; nothing is checked yet), or null when there is none.
Map<String, String>? readLinksObject(Object? json) {
  if (json is! Map) return null;
  final out = <String, String>{
    for (final name in kLinkNames)
      if (json[name] is String) name: json[name] as String,
  };
  return out.isEmpty ? null : out;
}
