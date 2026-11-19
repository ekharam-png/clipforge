// Updates (1.12): what the app does with latest.json - the quiet banner,
// "Later" / "Skip this version", the once-a-day automatic check and its
// switch, a manual check when offline, and what "Update" does on each
// system (Android: system installer; Linux: download page; Windows:
// unpack next to the app, or the download page when the folder cannot be
// written). The widgets are in update_ui_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:clipforge/core/build_info.dart';
import 'package:clipforge/core/update/update_download.dart';
import 'package:clipforge/core/update/update_info.dart';
import 'package:clipforge/core/update/update_install.dart';
import 'package:clipforge/ui/app_prefs.dart';
import 'package:clipforge/ui/update/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart' show FakeUpdatePlatform;

const ci139 = BuildInfo(version: '1.11.0', buildNumber: '139', channel: 'ci');

UpdateInfo release(int build, {String version = '1.12.0', Map<String, UpdateAsset> files = const {}}) =>
    UpdateInfo(
        version: version,
        build: build,
        notesUrl: 'https://example.org/releases/tag/v$version',
        platforms: files);

const apk = UpdateAsset(
    url: 'https://example.org/dl/ClipForge-android.apk', size: 3, sha256: 'abc');
const zip = UpdateAsset(
    url: 'https://example.org/dl/ClipForge-windows.zip', size: 3, sha256: 'abc');

void main() {
  late MemoryAppPrefs prefs;
  late FakeUpdatePlatform platform;
  late Directory tmp;
  UpdateInfo? latest;
  var fetches = 0;
  var now = DateTime.utc(2026, 11, 18, 12);
  String? downloaded;
  Object? downloadError;
  final swaps = <({String installDir, String newDir, String version})>[];
  Object? swapError;

  UpdateController controller({BuildInfo build = ci139}) => UpdateController(
        prefs: prefs,
        platform: platform,
        build: build,
        fetch: () async {
          fetches++;
          final info = latest;
          if (info == null) {
            throw UpdateException('ClipForge could not reach the update server.',
                kind: 'offline');
          }
          return info;
        },
        download: (asset, dir, build) => UpdateDownload.of(
            asset,
            downloadError != null
                ? Future<String>.error(downloadError!)
                : Future.value(downloaded ?? p.join(dir, 'b$build-${asset.fileName}')),
            steps: const [UpdateProgress(1, 3), UpdateProgress(3, 3, checking: true)]),
        now: () => now,
        swap: ({
          required String os,
          required String scriptText,
          required String workDir,
          required String installDir,
          required String newDir,
          required String resultFile,
          required String version,
          String exeName = 'clipforge.exe',
        }) async {
          if (swapError != null) throw swapError!;
          swaps.add((installDir: installDir, newDir: newDir, version: version));
        },
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipforge_updctl_test');
    prefs = MemoryAppPrefs(answered: true);
    platform = FakeUpdatePlatform()..dir = tmp.path;
    latest = release(142);
    fetches = 0;
    now = DateTime.utc(2026, 11, 18, 12);
    downloaded = null;
    downloadError = null;
    swaps.clear();
    swapError = null;
  });
  tearDown(() => tmp.delete(recursive: true));

  group('the automatic check', () {
    test('a newer build shows the banner; the same or an older one does not', () async {
      var c = controller();
      await c.onAppStart();
      expect(fetches, 1);
      expect(c.showBanner, isTrue);
      expect(c.available!.version, '1.12.0');

      prefs = MemoryAppPrefs(answered: true);
      latest = release(139);
      c = controller();
      await c.onAppStart();
      expect(c.showBanner, isFalse, reason: 'same build');

      prefs = MemoryAppPrefs(answered: true);
      latest = release(120, version: '1.9.0');
      c = controller();
      await c.onAppStart();
      expect(c.showBanner, isFalse, reason: 'older release: never a downgrade');
    });

    test('at most once a day', () async {
      await controller().onAppStart();
      expect(fetches, 1);
      now = now.add(const Duration(hours: 5));
      await controller().onAppStart(); // the app is started again
      expect(fetches, 1, reason: 'not again within a day');
      now = now.add(const Duration(hours: 20));
      final c = controller();
      await c.onAppStart();
      expect(fetches, 2, reason: 'the next day');
      expect(c.showBanner, isTrue);
      // Once per run of the app, however often the project list shows.
      await c.onAppStart();
      expect(fetches, 2);
    });

    test('can be switched off, and on again', () async {
      final c = controller();
      await c.setAutoCheck(false);
      expect(await prefs.flag(kUpdateCheckOffFlag), isTrue);
      final next = controller();
      await next.onAppStart();
      expect(next.autoCheck, isFalse);
      expect(fetches, 0);
      // A check by hand still works.
      expect(await next.check(manual: true), isNull);
      expect(next.showBanner, isTrue);
      await next.setAutoCheck(true);
      expect(await prefs.flag(kUpdateCheckOffFlag), isFalse);
    });

    test('offline or a broken answer: silent', () async {
      latest = null;
      final c = controller();
      await c.onAppStart();
      expect(c.showBanner, isFalse);
      expect(c.message, isNull);
      expect(c.stage, UpdateStage.idle);
      expect(await prefs.text(kUpdateLastCheckText), isNull,
          reason: 'a failed check does not count: tried again next start');
    });

    test('builds made on someone\'s own computer never check by themselves', () async {
      final c = controller(build: const BuildInfo(version: '1.12.0', buildNumber: '1'));
      await c.onAppStart();
      expect(fetches, 0);
    });
  });

  group('Later and Skip this version', () {
    test('Later hides the banner for this run only', () async {
      final c = controller();
      await c.onAppStart();
      c.later();
      expect(c.showBanner, isFalse);
      now = now.add(const Duration(days: 2));
      final next = controller();
      await next.onAppStart();
      expect(next.showBanner, isTrue, reason: 'offered again the next time');
    });

    test('Skip: not offered again, until a newer version or a check by hand', () async {
      final c = controller();
      await c.onAppStart();
      await c.skip();
      expect(c.showBanner, isFalse);
      expect(await prefs.text(kUpdateSkipBuildText), '142');

      now = now.add(const Duration(days: 2));
      var next = controller();
      await next.onAppStart();
      expect(next.showBanner, isFalse, reason: 'the skipped version stays hidden');
      expect(await next.check(manual: true), isNull);
      expect(next.showBanner, isTrue, reason: 'asked by hand: shown');

      latest = release(150, version: '1.13.0');
      now = now.add(const Duration(days: 2));
      next = controller();
      await next.onAppStart();
      expect(next.available!.version, '1.13.0');
    });
  });

  group('Check for updates (by hand)', () {
    test('says so plainly when offline, up to date, or the build is unknown', () async {
      latest = null;
      final c = controller();
      expect(await c.check(manual: true), contains('could not reach the update server'));
      latest = release(139);
      expect(await c.check(manual: true), 'You have the newest version (1.11.0 (build 139)).');
      final dev = controller(build: const BuildInfo(version: 'dev'));
      expect(await dev.check(manual: true), contains('cannot tell'));
    });

    test('"What\'s new" opens the release notes, plan B the download page', () async {
      final c = controller();
      await c.check(manual: true);
      await c.openNotes();
      await c.openDownloadPage();
      expect(platform.opened,
          ['https://example.org/releases/tag/v1.12.0', kDownloadPageUrl]);
    });
  });

  group('Update', () {
    test('Linux (development builds): the download page', () async {
      final c = controller();
      await c.check(manual: true);
      expect(await c.canInstallHere(), isFalse);
      await c.startUpdate();
      expect(platform.opened, [kDownloadPageUrl]);
      expect(c.stage, UpdateStage.failed);
      expect(c.message, contains('download page was opened'));
    });

    test('a release from before 1.12 has no files: the download page', () async {
      platform
        ..os = 'android'
        ..key = 'android';
      latest = release(142); // no "platforms"
      final c = controller();
      await c.check(manual: true);
      expect(await c.canInstallHere(), isFalse);
      await c.startUpdate();
      expect(platform.opened, [kDownloadPageUrl]);
      expect(platform.installed, isEmpty);
    });

    test('Android: the checked APK goes to the system installer', () async {
      platform
        ..os = 'android'
        ..key = 'android';
      latest = release(142, files: {'android': apk});
      final c = controller();
      await c.check(manual: true);
      expect(await c.canInstallHere(), isTrue);
      final stages = <UpdateStage>[];
      c.addListener(() => stages.add(c.stage));
      await c.startUpdate();
      expect(platform.installed.single, endsWith('b142-ClipForge-android.apk'));
      expect(c.stage, UpdateStage.handedToSystem);
      expect(stages, containsAllInOrder([UpdateStage.downloading, UpdateStage.verifying]));
      expect(platform.opened, isEmpty);
    });

    test('a download that fails its check: a message, nothing is installed', () async {
      platform
        ..os = 'android'
        ..key = 'android';
      latest = release(142, files: {'android': apk});
      downloadError = UpdateException(
          'The update was downloaded, but it is not the file ClipForge expected, '
          'so it was deleted and nothing was installed.',
          kind: 'check');
      final c = controller();
      await c.check(manual: true);
      await c.startUpdate();
      expect(platform.installed, isEmpty);
      expect(c.stage, UpdateStage.failed);
      expect(c.message, contains('nothing was installed'));
      // "Try again" works once the download is right.
      downloadError = null;
      await c.startUpdate();
      expect(platform.installed, hasLength(1));
    });

    test('Windows, folder cannot be written: the download page, nothing downloaded', () async {
      platform
        ..os = 'windows'
        ..key = 'windows'
        ..installDir = p.join(tmp.path, 'Program Files', 'missing');
      latest = release(142, files: {'windows': zip});
      var downloads = 0;
      final c = UpdateController(
          prefs: prefs,
          platform: platform,
          build: ci139,
          fetch: () async => latest!,
          download: (a, d, b) {
            downloads++;
            return UpdateDownload.of(a, Future.value('x'));
          });
      await c.check(manual: true);
      await c.startUpdate();
      expect(downloads, 0);
      expect(platform.opened, [kDownloadPageUrl]);
      expect(c.message, contains('cannot update itself where it is installed'));
    });

    test('Windows: unpacked next to the app, ready to restart; the app is untouched until then',
        () async {
      final install = Directory(p.join(tmp.path, 'Apps', 'ClipForge'))..createSync(recursive: true);
      File(p.join(install.path, 'clipforge.exe')).writeAsStringSync('old');
      final zipPath = p.join(tmp.path, 'new.zip');
      final encoder = ZipFileEncoder()..create(zipPath);
      encoder.addArchiveFile(ArchiveFile.bytes('ClipForge/clipforge.exe', utf8.encode('new')));
      await encoder.close();
      downloaded = zipPath;
      platform
        ..os = 'windows'
        ..key = 'windows'
        ..installDir = install.path;
      latest = release(142, files: {'windows': zip});
      final c = controller();
      await c.check(manual: true);
      await c.startUpdate();
      expect(c.stage, UpdateStage.readyToRestart, reason: '${c.message}');
      expect(File(p.join('${install.path}$kUpdateNewSuffix', 'clipforge.exe')).readAsStringSync(),
          'new');
      expect(File(p.join(install.path, 'clipforge.exe')).readAsStringSync(), 'old');
      expect(hasUpdateMarker('${install.path}$kUpdateNewSuffix', 'windows'), isTrue);
      // It is remembered on disk.
      final waiting = PendingUpdate.read(await platform.stateDir())!;
      expect([waiting.version, waiting.build], ['1.12.0', 142]);
      expect(waiting.swapStartedAt, isNull);
    });

    /// A Windows install with version 142 downloaded, checked and unpacked.
    Future<({Directory install, UpdateController c})> staged() async {
      final install = Directory(p.join(tmp.path, 'Apps', 'ClipForge-1.11.0'))
        ..createSync(recursive: true);
      File(p.join(install.path, 'clipforge.exe')).writeAsStringSync('old');
      final zipPath = p.join(tmp.path, 'new.zip');
      final encoder = ZipFileEncoder()..create(zipPath);
      encoder.addArchiveFile(ArchiveFile.bytes('ClipForge/clipforge.exe', utf8.encode('new')));
      await encoder.close();
      downloaded = zipPath;
      platform
        ..os = 'windows'
        ..key = 'windows'
        ..installDir = install.path;
      latest = release(142, files: {'windows': zip});
      final c = controller();
      await c.check(manual: true);
      await c.startUpdate();
      expect(c.stage, UpdateStage.readyToRestart, reason: '${c.message}');
      return (install: install, c: c);
    }

    test('"Restart ClipForge to finish": asks what is open, starts the swap, '
        'closes; not while something is busy', () async {
      final s = await staged();
      platform.allowQuit = false;
      await s.c.restartToUpdate();
      expect(swaps, isEmpty, reason: 'an export is running');
      expect(platform.quits, 0);
      expect(s.c.stage, UpdateStage.readyToRestart);
      expect(s.c.message, contains('will be finished the next time ClipForge starts'));
      platform.allowQuit = true;
      await s.c.restartToUpdate();
      expect(swaps.single.newDir, '${s.install.path}$kUpdateNewSuffix');
      expect(swaps.single.version, '1.12.0');
      expect(platform.quits, 1);
      expect(PendingUpdate.read(await platform.stateDir())!.swapStartedAt, isNotNull);
    });

    test('"Later": the next start finishes the update by itself, once',
        () async {
      final s = await staged();
      final newDir = '${s.install.path}$kUpdateNewSuffix';
      // The app is closed without restarting. The next start:
      final next = controller();
      await next.onAppStart();
      expect(swaps.single.newDir, newDir);
      expect(platform.quits, 1);
      expect(next.finishingAtStart, isTrue);
      expect(Directory(newDir).existsSync(), isTrue, reason: 'the script needs it');
      expect(fetches, 1, reason: 'no update check while it closes');
      // The script never ran (blocked): the start after that does NOT try
      // again by itself; it says so and offers Try again.
      final third = controller();
      await third.onAppStart();
      expect(swaps.length, 1);
      expect(third.lastResult!.updated, isFalse);
      expect(third.lastResult!.message, contains('did not run'));
      expect(third.pending, isNotNull);
      expect(Directory(newDir).existsSync(), isTrue, reason: 'kept for Try again');
      expect(await third.finishPending(), isNull);
      expect(swaps.length, 2);
      // "Not now" instead: the download is removed.
      final fourth = controller();
      await fourth.onAppStart();
      await fourth.dropPending();
      expect(Directory(newDir).existsSync(), isFalse);
      expect(PendingUpdate.read(await platform.stateDir()), isNull);
    });

    test('the swap could not be started at the start: a message, the app '
        'stays open', () async {
      await staged();
      swapError = const ProcessException('powershell.exe', [], 'not found');
      final next = controller();
      await next.onAppStart();
      expect(platform.quits, 0);
      expect(next.finishingAtStart, isFalse);
      expect(next.lastResult!.message, contains('could not be started'));
    });

    test('after the swap: "Updated", leftovers with the marker go, others '
        'stay, and a folder named after an old version is mentioned', () async {
      final s = await staged();
      await s.c.restartToUpdate();
      final state = await platform.stateDir();
      // What the script leaves when it worked but could not delete the
      // old folder: the new app in place, .update-old with its marker.
      final old = Directory('${s.install.path}$kUpdateOldSuffix')..createSync();
      writeUpdateMarker(old.path, 'windows');
      Directory('${s.install.path}$kUpdateNewSuffix').deleteSync(recursive: true);
      final foreign = Directory(p.join(tmp.path, 'Apps', 'Other.update-old'))..createSync();
      File(p.join(state, kUpdateResultFile))
          .writeAsStringSync('{"status":"updated","message":"","version":"1.12.0"}');
      final c = controller(
          build: const BuildInfo(version: '1.12.0', buildNumber: '142', channel: 'ci'));
      await c.onAppStart();
      expect(c.lastResult!.updated, isTrue);
      expect(old.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue);
      expect(PendingUpdate.read(state), isNull);
      expect(c.folderNote, contains('"ClipForge-1.11.0"'));
      expect(c.folderNote, contains('the app inside is 1.12.0'));
      expect(s.install.existsSync(), isTrue, reason: 'never renamed by the app');
    });

    test('a failed swap keeps the download for Try again; folders nobody '
        'marked are never deleted', () async {
      final s = await staged();
      await s.c.restartToUpdate();
      final state = await platform.stateDir();
      File(p.join(state, kUpdateResultFile)).writeAsStringSync(
          '{"status":"failed","message":"A file of ClipForge is still in use","version":"1.12.0"}');
      final c = controller();
      await c.onAppStart();
      expect(c.lastResult!.message, contains('still in use'));
      expect(c.pending, isNotNull);
      expect(Directory('${s.install.path}$kUpdateNewSuffix').existsSync(), isTrue);
      expect(swaps.length, 1);
      // A start with nothing waiting: a marked leftover goes, an unmarked
      // folder of that name stays.
      PendingUpdate.clear(state);
      final mine = Directory('${s.install.path}$kUpdateOldSuffix')..createSync();
      File(p.join(mine.path, 'notes.txt')).writeAsStringSync('mine');
      final plain = controller();
      await plain.onAppStart();
      expect(Directory('${s.install.path}$kUpdateNewSuffix').existsSync(), isFalse);
      expect(File(p.join(mine.path, 'notes.txt')).existsSync(), isTrue);
    });

    test('after a restart the result of the swap is reported once', () async {
      final state = Directory(await platform.stateDir())..createSync(recursive: true);
      File(p.join(state.path, kUpdateResultFile))
          .writeAsStringSync('{"status":"updated","message":"","version":"1.12.0"}');
      final c = controller(build: const BuildInfo(version: '1.12.0', buildNumber: '142', channel: 'ci'));
      latest = release(142);
      await c.onAppStart();
      expect(c.lastResult!.updated, isTrue);
      expect(c.lastResult!.version, '1.12.0');
      expect(File(p.join(state.path, kUpdateResultFile)).existsSync(), isFalse);
      expect(c.showBanner, isFalse);

      File(p.join(state.path, kUpdateResultFile)).writeAsStringSync(
          '{"status":"failed","message":"A file of ClipForge is still in use","version":"1.13.0"}');
      final failed = controller();
      await failed.onAppStart();
      expect(failed.lastResult!.updated, isFalse);
      expect(failed.lastResult!.message, contains('still in use'));
    });
  });
}
