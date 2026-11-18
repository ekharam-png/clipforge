import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/build_info.dart';
import '../../core/update/update_download.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_install.dart';
import '../about.dart';
import '../app_prefs.dart';

// Updates from inside the app (1.12). The rules are in lib/core/update;
// this file is what the app does with them on each system:
//   Windows  download the zip, check it, unpack next to the app, swap the
//            folders with a small script after the app closed, restart.
//            A folder that cannot be written -> the download page.
//   macOS    the same with ClipForge.app; when the app's place cannot be
//            changed (opened straight from Downloads, no permission) the
//            unpacked new app is shown in Finder instead.
//   Android  download the APK, check it, hand it to the system installer.
//   Linux    (development builds) the download page only.
// "Open the download page" is always there as plan B.

/// What the app needs from the system for updates. Tests use a fake.
abstract class UpdatePlatform {
  /// "windows", "macos", "android", "linux", ...
  String get os;

  /// The key of this device's file in latest.json, null = cannot install
  /// by itself.
  Future<String?> platformKey();

  /// Opens a web page in the browser.
  Future<void> openUrl(String url);

  /// Where update files are downloaded to.
  Future<String> downloadDir();

  /// Where the swap script leaves its result (and is written to).
  Future<String> stateDir();

  /// The installed app (see [installDirOf]); null when unknown.
  String? get installDir;

  /// The swap script for this system.
  Future<String> swapScript();

  /// Android: hands the APK to the system installer.
  Future<void> installApk(String path);

  /// macOS: shows [path] in Finder.
  Future<void> reveal(String path);

  /// Closes the app (the swap script is waiting for that).
  Future<void> quit();
}

class RealUpdatePlatform implements UpdatePlatform {
  static const _channel = MethodChannel('clipforge/update');

  @override
  String get os => Platform.operatingSystem;

  @override
  Future<String?> platformKey() async {
    if (!Platform.isAndroid) return updatePlatformKey(os);
    var is64 = true;
    try {
      is64 = await _channel.invokeMethod<bool>('is64Bit') ?? true;
    } catch (_) {}
    return updatePlatformKey(os, android32: !is64);
  }

  @override
  Future<void> openUrl(String url) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } else if (Platform.isWindows) {
      // rundll32 takes the address as it is (cmd's "start" would trip
      // over & in it).
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  }

  @override
  Future<String> downloadDir() async => p.join(
      (Platform.isAndroid
              ? await getTemporaryDirectory()
              : await getApplicationSupportDirectory())
          .path,
      'updates');

  @override
  Future<String> stateDir() async =>
      p.join((await getApplicationSupportDirectory()).path, 'update-state');

  @override
  String? get installDir => installDirOf(Platform.resolvedExecutable, os);

  @override
  Future<String> swapScript() => rootBundle.loadString(Platform.isWindows
      ? 'assets/update/clipforge-update.ps1'
      : 'assets/update/clipforge-update.sh');

  @override
  Future<void> installApk(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});

  @override
  Future<void> reveal(String path) async {
    await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
  }

  @override
  Future<void> quit() async {
    await ServicesBinding.instance.exitApplication(AppExitType.required);
    // Should the window still be there, end the program anyway: the swap
    // script is waiting for it.
    await Future<void>.delayed(const Duration(seconds: 2));
    exit(0);
  }
}

final updatePlatformProvider =
    Provider<UpdatePlatform>((ref) => RealUpdatePlatform());

/// Reads latest.json. Tests put a fake (or a local server) here.
typedef UpdateFetcher = Future<UpdateInfo> Function();

final updateFetcherProvider = Provider<UpdateFetcher>(
    (ref) => () => fetchUpdateInfo(Uri.parse(kLatestJsonUrl)));

/// Starts a download. Tests replace it.
typedef UpdateDownloader = UpdateDownload Function(
    UpdateAsset asset, String dir, int build);

final updateDownloaderProvider = Provider<UpdateDownloader>((ref) =>
    (asset, dir, build) => downloadUpdate(asset, dir, build: build));

enum UpdateStage {
  /// Nothing going on.
  idle,
  checking,
  downloading,

  /// Size and fingerprint are being checked.
  verifying,
  unpacking,

  /// Windows / macOS: everything is ready; the app must restart.
  readyToRestart,

  /// Android: the system installer has the file.
  handedToSystem,

  /// macOS plan B: the new app is shown in Finder.
  shownInFinder,
  failed,
}

/// The state of "is there an update, and what is happening with it".
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.prefs,
    required this.platform,
    required this.build,
    required this.fetch,
    required this.download,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppPrefs prefs;
  final UpdatePlatform platform;
  final BuildInfo build;
  final UpdateFetcher fetch;
  final UpdateDownloader download;
  final DateTime Function() _now;

  /// The newer version on offer (the banner shows while this is set).
  UpdateInfo? available;

  /// "Later" was pressed: no banner for the rest of this run.
  bool _hidden = false;
  bool get showBanner => available != null && !_hidden;

  UpdateStage stage = UpdateStage.idle;
  double progress = 0;

  /// What went wrong, or what to do next, in plain words.
  String? message;

  /// The result of an update that ran before this start (shown once).
  UpdateResult? lastResult;

  bool autoCheck = true;
  UpdateDownload? _download;
  String? _stagedNewDir;
  bool _started = false;

  int? get _currentBuild => int.tryParse(build.buildNumber ?? '');

  void _set(UpdateStage s, {String? note, double? fraction}) {
    stage = s;
    message = note;
    if (fraction != null) progress = fraction;
    notifyListeners();
  }

  /// Once per run, when the project list is up: tidy up after an earlier
  /// update, then the automatic check (at most once a day, not when
  /// switched off, never for builds made on someone's own computer).
  Future<void> onAppStart() async {
    if (_started) return;
    _started = true;
    try {
      autoCheck = !await prefs.flag(kUpdateCheckOffFlag);
    } catch (_) {}
    try {
      lastResult = takeUpdateResult(await platform.stateDir());
      final dir = platform.installDir;
      // After a "broken" swap the app runs from the .update-old folder:
      // leave everything as it is then.
      if (dir != null && lastResult?.status != 'broken') cleanUpdateLeftovers(dir);
      if (lastResult != null) {
        if (lastResult!.updated) {
          pruneUpdateFiles(await platform.downloadDir());
        }
        notifyListeners();
      }
    } catch (_) {}
    if (!build.isCi || !autoCheck) return;
    DateTime? last;
    try {
      last = DateTime.tryParse(await prefs.text(kUpdateLastCheckText) ?? '');
    } catch (_) {}
    if (!autoCheckDue(switchedOff: false, lastCheck: last, now: _now())) return;
    await check(manual: false);
  }

  /// Forgets [lastResult] (its message was shown).
  void clearLastResult() => lastResult = null;

  Future<void> setAutoCheck(bool on) async {
    autoCheck = on;
    notifyListeners();
    try {
      if (on) {
        await prefs.clearFlag(kUpdateCheckOffFlag);
      } else {
        await prefs.setFlag(kUpdateCheckOffFlag);
      }
    } catch (_) {}
  }

  /// Reads latest.json. Automatic ([manual] false): errors stay silent and
  /// a skipped version stays hidden. Returns what to tell the user after a
  /// check by hand (null when the banner says it all).
  Future<String?> check({required bool manual}) async {
    if (stage == UpdateStage.checking) return null;
    final busy = stage != UpdateStage.idle && stage != UpdateStage.failed;
    if (busy) return 'An update is already being prepared.';
    _set(UpdateStage.checking);
    try {
      final info = await fetch();
      try {
        await prefs.setText(kUpdateLastCheckText, _now().toUtc().toIso8601String());
      } catch (_) {}
      int? skipped;
      try {
        skipped = int.tryParse(await prefs.text(kUpdateSkipBuildText) ?? '');
      } catch (_) {}
      final offer = offerUpdate(info,
          currentBuild: _currentBuild, skippedBuild: skipped, manual: manual);
      available = offer ? info : null;
      if (offer) _hidden = false;
      _set(UpdateStage.idle);
      if (!manual || offer) return null;
      if (_currentBuild == null) {
        return 'The newest version is ${info.version} (build ${info.build}). '
            'This copy has no build number, so ClipForge cannot tell whether '
            'it is older.';
      }
      return 'You have the newest version '
          '(${build.versionLabel}).';
    } on UpdateException catch (e) {
      _set(UpdateStage.idle);
      return manual ? e.message : null;
    } catch (e) {
      _set(UpdateStage.idle);
      return manual ? 'Updates could not be checked. ($e)' : null;
    }
  }

  /// "Later": hides the banner until the app is started again.
  void later() {
    _hidden = true;
    notifyListeners();
  }

  /// "Skip this version": no banner for this version again (a check by
  /// hand still shows it).
  Future<void> skip() async {
    final info = available;
    if (info == null) return;
    available = null;
    notifyListeners();
    try {
      await prefs.setText(kUpdateSkipBuildText, '${info.build}');
    } catch (_) {}
  }

  Future<String?> openDownloadPage() => _open(kDownloadPageUrl);

  /// "What's new": the release notes of the version on offer.
  Future<String?> openNotes() =>
      _open(available?.notesUrl ?? kDownloadPageUrl);

  Future<String?> _open(String url) async {
    try {
      await platform.openUrl(url);
      return null;
    } catch (_) {
      return 'The page could not be opened. Its address is: $url';
    }
  }

  /// True when "Update" can do more than open the download page here.
  Future<bool> canInstallHere() async {
    final info = available;
    if (info == null) return false;
    final key = await platform.platformKey();
    return key != null && info.platforms[key] != null;
  }

  /// "Update": download, check, prepare. Ends in [UpdateStage.readyToRestart]
  /// (computers), [UpdateStage.handedToSystem] (Android),
  /// [UpdateStage.shownInFinder] (macOS plan B) or [UpdateStage.failed]
  /// with a [message].
  Future<void> startUpdate() async {
    final info = available;
    if (info == null ||
        stage == UpdateStage.downloading ||
        stage == UpdateStage.verifying ||
        stage == UpdateStage.unpacking) {
      return;
    }
    final key = await platform.platformKey();
    final asset = key == null ? null : info.platforms[key];
    if (asset == null) {
      final problem = await openDownloadPage();
      _set(UpdateStage.failed,
          note: problem ??
              'ClipForge cannot update itself on this system. The download '
                  'page was opened: get the new version there.');
      return;
    }
    final os = platform.os;
    final installDir = platform.installDir;
    final inPlaceProblem =
        os == 'android' ? null : replaceInPlaceProblem(installDir, os);
    if (os == 'windows' && inPlaceProblem != null) {
      final problem = await openDownloadPage();
      _set(UpdateStage.failed,
          note: problem ??
              'ClipForge cannot update itself where it is installed '
                  '($inPlaceProblem). The download page was opened: get the '
                  'new version there and unpack it over the old one.');
      return;
    }
    try {
      _set(UpdateStage.downloading, fraction: 0);
      final dir = await platform.downloadDir();
      pruneUpdateFiles(dir, keepBuild: info.build);
      final d = _download = download(asset, dir, info.build);
      final sub = d.progress.listen((p) {
        progress = p.fraction;
        stage = p.checking ? UpdateStage.verifying : UpdateStage.downloading;
        notifyListeners();
      });
      final String file;
      try {
        file = await d.done;
      } finally {
        unawaited(sub.cancel());
        _download = null;
      }
      if (os == 'android') {
        await platform.installApk(file);
        _set(UpdateStage.handedToSystem);
        return;
      }
      _set(UpdateStage.unpacking);
      if (os == 'windows') {
        _stagedNewDir = await stageWindowsUpdate(file, installDir!);
        _set(UpdateStage.readyToRestart);
      } else if (inPlaceProblem == null) {
        _stagedNewDir = await stageMacUpdate(file, installDir!);
        _set(UpdateStage.readyToRestart);
      } else {
        // macOS plan B: the new app, unpacked, shown in Finder.
        final home = Platform.environment['HOME'] ?? '';
        final target = p.join(home, 'Downloads', 'ClipForge ${info.version}');
        final app = await unpackMacUpdate(file, target);
        await platform.reveal(app);
        _set(UpdateStage.shownInFinder,
            note: 'The new ClipForge is in your Downloads folder (Finder '
                'shows it). Close ClipForge, drag the new one into '
                'Applications, choose Replace, then open it.');
      }
    } on UpdateException catch (e) {
      _set(e.kind == 'stopped' ? UpdateStage.idle : UpdateStage.failed,
          note: e.kind == 'stopped' ? null : e.message);
    } catch (e) {
      _set(UpdateStage.failed,
          note: 'The update could not be prepared ($e). Nothing was '
              'changed; you can use the download page instead.');
    }
  }

  /// Stops a running download (what was fetched stays for next time).
  Future<void> cancelDownload() async {
    await _download?.cancel();
  }

  /// Back to the banner after a failure or "not now".
  void reset({bool notify = true}) {
    if (stage == UpdateStage.downloading ||
        stage == UpdateStage.verifying ||
        stage == UpdateStage.unpacking ||
        stage == UpdateStage.checking ||
        stage == UpdateStage.readyToRestart) {
      return;
    }
    stage = UpdateStage.idle;
    message = null;
    if (notify) notifyListeners();
  }

  /// Windows / macOS, after [UpdateStage.readyToRestart]: starts the swap
  /// script and closes the app. The script puts the new version in place
  /// and starts it.
  Future<void> restartToUpdate() async {
    final info = available, newDir = _stagedNewDir, dir = platform.installDir;
    if (info == null || newDir == null || dir == null) return;
    try {
      final state = await platform.stateDir();
      await startSwap(
        os: platform.os,
        scriptText: await platform.swapScript(),
        workDir: state,
        installDir: dir,
        newDir: newDir,
        resultFile: p.join(state, kUpdateResultFile),
        version: info.version,
        exeName: p.basename(Platform.resolvedExecutable),
      );
      await platform.quit();
    } catch (e) {
      _set(UpdateStage.failed,
          note: 'The update could not be started ($e). ClipForge is '
              'unchanged; you can use the download page instead.');
    }
  }
}

final updateControllerProvider = Provider<UpdateController>((ref) {
  final c = UpdateController(
    prefs: ref.watch(appPrefsProvider),
    platform: ref.watch(updatePlatformProvider),
    build: ref.watch(buildInfoProvider),
    fetch: ref.watch(updateFetcherProvider),
    download: ref.watch(updateDownloaderProvider),
  );
  ref.onDispose(c.dispose);
  return c;
});
