import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

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

  /// Asks everything that is open whether the app may close now (an open
  /// project saves first; a running export says no). The app does NOT
  /// close by this.
  Future<bool> mayQuit();
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
  Future<bool> mayQuit() async =>
      await ServicesBinding.instance.handleRequestAppExit() ==
      AppExitResponse.exit;

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

/// [startSwap], or what stands in for it in tests.
typedef SwapStarter = Future<void> Function({
  required String os,
  required String scriptText,
  required String workDir,
  required String installDir,
  required String newDir,
  required String resultFile,
  required String version,
  String exeName,
});

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
    SwapStarter? swap,
  })  : _now = now ?? DateTime.now,
        _swap = swap ?? startSwap;

  /// Starts the swap script (tests record the call instead).
  final SwapStarter _swap;

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

  /// With [lastResult] "updated": a sentence about a folder that is still
  /// named after an older version ([folderNameNote]); else null.
  String? folderNote;

  /// An unpacked update that is waiting for the swap ("Try again" after a
  /// failed or unfinished swap uses it; no new download).
  PendingUpdate? pending;

  /// The app is closing to finish an update that was waiting.
  bool finishingAtStart = false;

  bool autoCheck = true;
  UpdateDownload? _download;
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
      if (await _afterEarlierUpdate()) return;
    } catch (_) {}
    if (!build.isCi || !autoCheck) return;
    DateTime? last;
    try {
      last = DateTime.tryParse(await prefs.text(kUpdateLastCheckText) ?? '');
    } catch (_) {}
    if (!autoCheckDue(switchedOff: false, lastCheck: last, now: _now())) return;
    await check(manual: false);
  }

  /// Looks at what an earlier update left behind (the swap script's
  /// result, the record of an update that is waiting, folders next to the
  /// app) and acts on it; see [decideUpdateAtStart]. True when the app is
  /// now closing to finish an update.
  Future<bool> _afterEarlierUpdate() async {
    final state = await platform.stateDir();
    final os = platform.os;
    final dir = platform.installDir;
    final result = takeUpdateResult(state);
    final waiting = PendingUpdate.read(state);
    final same = waiting != null && dir != null && p.equals(waiting.installDir, dir);
    final staged = waiting != null &&
        Directory(waiting.newDir).existsSync() &&
        hasUpdateMarker(waiting.newDir, os);
    final action = decideUpdateAtStart(
        result: result,
        pending: waiting,
        currentBuild: _currentBuild,
        sameInstall: same,
        stagedReady: staged);
    switch (action) {
      case UpdateStartAction.tidy:
        PendingUpdate.clear(state);
        if (dir != null) cleanUpdateLeftovers(dir, os);
        return false;
      case UpdateStartAction.reportUpdated:
        lastResult = result ??
            UpdateResult('updated', '', waiting?.version ?? build.version);
        PendingUpdate.clear(state);
        if (dir != null) {
          cleanUpdateLeftovers(dir, os);
          folderNote = folderNameNote(dir, build.version, os);
        }
        pruneUpdateFiles(await platform.downloadDir());
        notifyListeners();
        return false;
      case UpdateStartAction.reportFailed:
        lastResult = result;
        // After a "broken" swap the app runs from the .update-old folder:
        // everything is left as it is. Otherwise the unpacked update is
        // kept for "Try again" and the rest is tidied.
        if (result!.status == 'broken') {
          PendingUpdate.clear(state);
        } else if (same && staged) {
          pending = waiting;
          cleanUpdateLeftovers(dir, os, keep: {waiting.newDir});
        } else {
          PendingUpdate.clear(state);
          if (dir != null) cleanUpdateLeftovers(dir, os);
        }
        notifyListeners();
        return false;
      case UpdateStartAction.reportUnfinished:
        pending = waiting;
        lastResult = UpdateResult(
            'failed',
            'ClipForge closed to finish the update, but the step that swaps '
                'the old version for the new one did not run (it may have '
                'been blocked by the system or by security software)',
            waiting!.version);
        cleanUpdateLeftovers(dir!, os, keep: {waiting.newDir});
        notifyListeners();
        return false;
      case UpdateStartAction.applyNow:
        // "Later" was chosen (or the app was closed another way) after the
        // download was checked and unpacked: finish it now, at the start,
        // while no project is open and nothing is running.
        pending = waiting;
        finishingAtStart = true;
        notifyListeners();
        final problem = await finishPending();
        if (problem == null) return true;
        finishingAtStart = false;
        lastResult = UpdateResult('failed', problem, waiting!.version);
        notifyListeners();
        return false;
    }
  }

  /// Forgets [lastResult] (its message was shown).
  void clearLastResult() {
    lastResult = null;
    folderNote = null;
  }

  /// Forgets an update that is waiting and removes its folder ("Not now"
  /// after a failed swap, or the download page was chosen instead).
  Future<void> dropPending() async {
    final waiting = pending;
    pending = null;
    try {
      PendingUpdate.clear(await platform.stateDir());
      final dir = platform.installDir;
      if (waiting != null && dir != null) cleanUpdateLeftovers(dir, platform.os);
    } catch (_) {}
  }

  /// Starts the swap for [pending] and closes the app. Returns null when
  /// the app is closing, else why it could not be done (in plain words).
  /// Never while something that is open says no (unsaved changes that
  /// cannot be saved, a running export).
  Future<String?> finishPending() async {
    final waiting = pending, dir = platform.installDir;
    if (waiting == null || dir == null) return 'There is no update waiting.';
    if (!Directory(waiting.newDir).existsSync() ||
        !hasUpdateMarker(waiting.newDir, platform.os)) {
      await dropPending();
      return 'The downloaded update is no longer there. Use Update again.';
    }
    try {
      if (!await platform.mayQuit()) {
        return 'ClipForge is still busy (an export is running, or a project '
            'could not be saved). The update will be finished the next time '
            'ClipForge starts.';
      }
      final state = await platform.stateDir();
      waiting.started(_now()).write(state);
      await _swap(
        os: platform.os,
        scriptText: await platform.swapScript(),
        workDir: state,
        installDir: dir,
        newDir: waiting.newDir,
        resultFile: p.join(state, kUpdateResultFile),
        version: waiting.version,
        exeName: p.basename(Platform.resolvedExecutable),
      );
      await platform.quit();
      return null;
    } catch (e) {
      return 'The update could not be started ($e). ClipForge is unchanged; '
          'you can use the download page instead.';
    }
  }

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
      if (os == 'windows' || inPlaceProblem == null) {
        final newDir = os == 'windows'
            ? await stageWindowsUpdate(file, installDir!)
            : await stageMacUpdate(file, installDir!);
        // Remembered on disk: "Later" (or closing the app another way)
        // does not lose it; the next start finishes the update.
        pending = PendingUpdate(
            version: info.version,
            build: info.build,
            installDir: installDir,
            newDir: newDir);
        try {
          pending!.write(await platform.stateDir());
        } catch (_) {}
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
    if (pending == null) return;
    final problem = await finishPending();
    if (problem == null) return;
    if (pending != null && problem.startsWith('ClipForge is still busy')) {
      // Still ready: said in the window, finished at the next start.
      _set(UpdateStage.readyToRestart, note: problem);
    } else {
      _set(UpdateStage.failed, note: problem);
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
