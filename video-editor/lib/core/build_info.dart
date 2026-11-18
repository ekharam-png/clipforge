// Which build of ClipForge this is: version, build number, when and from
// which commit it was built. Pure Dart: the app and the Claude control
// server (bin/clipforge_mcp.dart) both report it, so they always agree.
//
// Where the values come from (compile-time defines):
// - FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER: set by `flutter build` and
//   `flutter run`/`flutter test` from pubspec.yaml `version:` or from
//   `--build-name` / `--build-number` (CI passes the GitHub Actions run
//   number). bin/build_mcp.dart passes the same two to `dart compile exe`.
// - CLIPFORGE_BUILD_TIME (UTC, ISO 8601), CLIPFORGE_COMMIT (short SHA),
//   CLIPFORGE_CHANNEL ("ci" or "local"): passed by CI with
//   `--dart-define-from-file` (and to bin/build_mcp.dart the same way).
//   A build on someone's own computer normally has none of them and says
//   "local build" instead of a time.

/// The version, build number and build details of this program.
class BuildInfo {
  const BuildInfo({
    required this.version,
    this.buildNumber,
    this.buildTime,
    this.commit,
    this.channel = 'local',
  });

  /// Reads the raw define values; anything missing or malformed is left
  /// out rather than guessed.
  factory BuildInfo.fromValues({
    String? version,
    String? buildNumber,
    String? buildTime,
    String? commit,
    String? channel,
  }) {
    final v = (version ?? '').trim();
    final n = (buildNumber ?? '').trim();
    final c = (commit ?? '').trim().toLowerCase();
    return BuildInfo(
      version: v.isEmpty ? kUnknownVersion : v,
      buildNumber: RegExp(r'^\d+$').hasMatch(n) ? n : null,
      buildTime: parseBuildTime(buildTime),
      commit: RegExp(r'^[0-9a-f]{4,40}$').hasMatch(c)
          ? c.substring(0, c.length < 7 ? c.length : 7)
          : null,
      channel: (channel ?? '').trim().toLowerCase() == 'ci' ? 'ci' : 'local',
    );
  }

  /// This program's own build (from the compile-time defines).
  static final BuildInfo current = BuildInfo.fromValues(
    version: const String.fromEnvironment('FLUTTER_BUILD_NAME'),
    buildNumber: const String.fromEnvironment('FLUTTER_BUILD_NUMBER'),
    buildTime: const String.fromEnvironment('CLIPFORGE_BUILD_TIME'),
    commit: const String.fromEnvironment('CLIPFORGE_COMMIT'),
    channel: const String.fromEnvironment('CLIPFORGE_CHANNEL'),
  );

  /// Shown when the program was compiled without a version (only
  /// `dart run` of the Claude control server from source).
  static const String kUnknownVersion = 'dev';

  /// Semantic version, e.g. "1.4.0".
  final String version;

  /// e.g. "21" (the GitHub Actions run number for CI builds); null when
  /// unknown.
  final String? buildNumber;

  /// When the build started, in UTC; null for a local build.
  final DateTime? buildTime;

  /// Short commit SHA, e.g. "877e482".
  final String? commit;

  /// "ci" (built by GitHub Actions) or "local".
  final String channel;

  bool get isCi => channel == 'ci';

  /// "1.4.0 (build 21)".
  String get versionLabel =>
      buildNumber == null ? version : '$version (build $buildNumber)';

  /// When it was built: "16 Nov 2026, 07:20 UTC" ([utc]) or in this
  /// computer's time zone, "16 Nov 2026, 08:20 (UTC+1)". "local build"
  /// for a build without a time.
  String timeLabel({bool utc = true}) {
    final t = buildTime;
    if (t == null) return 'local build';
    final text = formatBuildTime(t, utc: utc);
    return isCi ? text : 'local build, $text';
  }

  /// The one line to quote: "ClipForge 1.4.0 (build 21) · 16 Nov 2026,
  /// 07:20 UTC · 877e482". [utc] false shows the time in this computer's
  /// time zone (for the screen; copied text uses UTC).
  String describe({String name = 'ClipForge', bool utc = true}) => [
        '$name $versionLabel',
        timeLabel(utc: utc),
        ?commit,
      ].join(' · ');

  /// For the Claude control server's get_status.
  Map<String, Object?> toJson() => {
        'version': version,
        'buildNumber': buildNumber,
        'buildTime': buildTime?.toIso8601String(),
        'commit': commit,
        'channel': channel,
        'display': describe(),
      };
}

/// Parses an ISO 8601 time; one without a zone is taken as UTC. Null when
/// [text] is empty or not a time.
DateTime? parseBuildTime(String? text) {
  final s = (text ?? '').trim();
  if (s.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d\d(:?\d\d)?)$').hasMatch(s);
  final t = DateTime.tryParse(hasZone ? s : '${s}Z');
  return t?.toUtc();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "16 Nov 2026, 07:20 UTC", or with [utc] false the same moment in this
/// computer's time zone: "16 Nov 2026, 09:20 (UTC+2)".
String formatBuildTime(DateTime time, {bool utc = true}) {
  final t = utc ? time.toUtc() : time.toLocal();
  final text = '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '${_two(t.hour)}:${_two(t.minute)}';
  if (utc) return '$text UTC';
  return '$text (${utcOffsetLabel(t.timeZoneOffset)})';
}

/// "UTC", "UTC+2", "UTC-5", "UTC+5:30".
String utcOffsetLabel(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return 'UTC$sign$h${m == 0 ? '' : ':${_two(m)}'}';
}

/// The text "Copy version info" puts on the clipboard, for bug reports:
/// the version line (time in UTC), the raw build details, and the device.
String versionReport(
  BuildInfo info, {
  required String system,
  String? device,
  String? screen,
}) {
  final out = StringBuffer()
    ..writeln(info.describe())
    ..writeln('Version: ${info.version}')
    ..writeln('Build: ${info.buildNumber ?? 'unknown'} (${info.channel})')
    ..writeln('Built: ${info.buildTime?.toIso8601String() ?? 'local build, no time recorded'}')
    ..writeln('Commit: ${info.commit ?? 'unknown'}')
    ..writeln('System: $system');
  if (device != null && device.isNotEmpty) out.writeln('Device: $device');
  if (screen != null && screen.isNotEmpty) out.writeln('Screen: $screen');
  return out.toString().trimRight();
}
