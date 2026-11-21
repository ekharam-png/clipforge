// Where the Mac app is running from, and whether to say something about
// it (1.18). Pure Dart; nothing is ever moved by the app.
//
// A Mac runs an app that was opened straight from the unzipped download
// from a hidden, read-only copy ("App Translocation": a path with
// /AppTranslocation/ in it). From there the app cannot replace itself, so
// updates fail, and an older ClipForge may still sit in Applications and
// be the one that opens next time (that happened in the 1.17 test:
// 1.14.1 in Applications, 1.17.0 running from the download).

import 'dart:io';

import 'update/update_install.dart' show AppVersion;

/// What to tell the user about the place the Mac app runs from.
class InstallAdvice {
  const InstallAdvice({
    required this.translocated,
    required this.bundlePath,
    this.otherPath,
    this.otherVersion,
    this.otherIsOlder = false,
  });

  /// Running from macOS's hidden copy of a downloaded app.
  final bool translocated;

  /// This app's own `.app` folder.
  final String bundlePath;

  /// Another ClipForge in an Applications folder, if there is one.
  final String? otherPath;

  /// Its version ("1.14.1"), when it could be read.
  final String? otherVersion;

  /// True when [otherVersion] is older than this app.
  final bool otherIsOlder;

  /// The friendly line.
  String get message {
    final other = otherPath == null
        ? ''
        : otherIsOlder
            ? ' An older ClipForge'
                '${otherVersion == null ? '' : ' ($otherVersion)'} is in the '
                'Applications folder: replace it with this one.'
            : ' There is already a ClipForge'
                '${otherVersion == null ? '' : ' ($otherVersion)'} in the '
                'Applications folder.';
    return 'Move ClipForge to the Applications folder so it can update '
        'itself.$other';
  }
}

/// The `.app` folder [executable] is inside (`…/ClipForge.app`), or null.
String? macBundleOf(String executable) {
  final m = RegExp(r'^(.*?\.app)(/|$)').firstMatch(executable);
  return m?.group(1);
}

/// `CFBundleShortVersionString` in the text of an Info.plist; null when it
/// is not there (or the file is a binary plist).
String? plistVersion(String plist) {
  final m = RegExp(
          r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>')
      .firstMatch(plist);
  return m?.group(1)?.trim();
}

/// What to say on a Mac whose app runs from [executable] (the resolved
/// path of the program); null when it is where it should be: inside
/// `/Applications` or `~/Applications`.
///
/// [exists] and [readText] look at the disk (tests give their own);
/// [version] is this app's version.
InstallAdvice? macInstallAdvice({
  required String executable,
  required String? home,
  required String version,
  bool Function(String path)? exists,
  String? Function(String path)? readText,
}) {
  final bundle = macBundleOf(executable);
  if (bundle == null) return null; // Not an app bundle (a development run).
  final translocated = executable.contains('/AppTranslocation/');
  final places = [
    '/Applications',
    if (home != null && home.isNotEmpty) '$home/Applications',
  ];
  final inPlace =
      !translocated && places.any((dir) => bundle.startsWith('$dir/'));
  if (inPlace) return null;

  exists ??= (path) => Directory(path).existsSync();
  readText ??= (path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return null;
    }
  };
  final name = bundle.substring(bundle.lastIndexOf('/') + 1);
  String? otherPath, otherVersion;
  for (final dir in places) {
    final candidate = '$dir/$name';
    if (candidate == bundle) continue;
    bool there;
    try {
      there = exists(candidate);
    } catch (_) {
      there = false;
    }
    if (!there) continue;
    otherPath = candidate;
    final plist = readText('$candidate/Contents/Info.plist');
    otherVersion = plist == null ? null : plistVersion(plist);
    break;
  }
  var older = false;
  final theirs = AppVersion.parse(otherVersion), ours = AppVersion.parse(version);
  if (theirs != null && ours != null) older = theirs.isOlderThan(ours);
  return InstallAdvice(
    translocated: translocated,
    bundlePath: bundle,
    otherPath: otherPath,
    otherVersion: otherVersion,
    otherIsOlder: older,
  );
}
