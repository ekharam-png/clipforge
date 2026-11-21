// Options, the default projects folder per operating system, ffmpeg and
// font lookup.

import 'dart:io';

import 'package:clipforge/mcp/environment.dart';
import 'package:clipforge/mcp/mcp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// A fake `runForOutput`: answers by executable name, null = cannot run.
OutputRunner runner(Map<String, String?> outputs, [List<String>? log]) =>
    (exe, args) async {
      log?.add(exe);
      return outputs[exe];
    };

void main() {
  group('ServerOptions', () {
    test('defaults to nothing set', () {
      final o = ServerOptions.parse(const [], const {});
      expect([o.projectsDir, o.ffmpeg, o.ffprobe, o.fontsDir], everyElement(isNull));
      expect(o.help, isFalse);
      expect(o.version, isFalse);
    });

    test('reads "--name value" and "--name=value"', () {
      final o = ServerOptions.parse(
          const ['--projects-dir', '/p q', '--ffmpeg=/bin/ffmpeg', '--ffprobe', '/bin/ffprobe', '--fonts-dir=/f'],
          const {});
      expect(o.projectsDir, '/p q');
      expect(o.ffmpeg, '/bin/ffmpeg');
      expect(o.ffprobe, '/bin/ffprobe');
      expect(o.fontsDir, '/f');
    });

    test('environment variables are the fallback; the command line wins', () {
      const env = {
        kEnvProjectsDir: '/env/projects',
        kEnvFfmpeg: '/env/ffmpeg',
        kEnvFfprobe: '/env/ffprobe',
        kEnvFontsDir: '  ',
      };
      final o = ServerOptions.parse(const ['--ffmpeg', '/cli/ffmpeg'], env);
      expect(o.projectsDir, '/env/projects');
      expect(o.ffmpeg, '/cli/ffmpeg');
      expect(o.ffprobe, '/env/ffprobe');
      expect(o.fontsDir, isNull, reason: 'a blank variable counts as not set');
    });

    test('--help and --version', () {
      expect(ServerOptions.parse(const ['--help'], const {}).help, isTrue);
      expect(ServerOptions.parse(const ['-h'], const {}).help, isTrue);
      expect(ServerOptions.parse(const ['--version'], const {}).version, isTrue);
    });

    test('mistakes are reported', () {
      FormatException bad(List<String> args) {
        try {
          ServerOptions.parse(args, const {});
        } on FormatException catch (e) {
          return e;
        }
        fail('no error for $args');
      }

      expect(bad(const ['--project-dir', 'x']).message, contains('Unknown option: --project-dir'));
      expect(bad(const ['--ffmpeg']).message, contains('needs a value'));
      expect(bad(const ['--ffmpeg=']).message, contains('needs a value'));
      expect(bad(const ['stray']).message, contains('Unexpected argument'));
    });
  });

  group('Windows helpers', () {
    test('expandWindowsVariables ignores case and keeps unknown names', () {
      const env = {'UserProfile': r'C:\Users\Ann', 'OneDrive': r'D:\OD'};
      expect(expandWindowsVariables(r'%USERPROFILE%\Documents', env), r'C:\Users\Ann\Documents');
      expect(expandWindowsVariables(r'%onedrive%\Docs', env), r'D:\OD\Docs');
      expect(expandWindowsVariables(r'%NOPE%\x', env), r'%NOPE%\x');
    });

    test('parseRegDocuments reads the Personal value', () {
      const env = {'USERPROFILE': r'C:\Users\Ann'};
      const key = r'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders';
      expect(parseRegDocuments('\r\n$key\r\n    Personal    REG_EXPAND_SZ    %USERPROFILE%\\Documents\r\n\r\n', env),
          r'C:\Users\Ann\Documents');
      expect(parseRegDocuments('$key\n    Personal    REG_SZ    D:\\One Drive\\My Documents\n', env),
          r'D:\One Drive\My Documents');
      expect(parseRegDocuments('$key\n    Personal    REG_EXPAND_SZ    %MISSING%\\Documents\n', env), isNull);
      expect(parseRegDocuments('ERROR: The system was unable to find the specified registry key or value.', env),
          isNull);
    });
  });

  group('resolveProjectsDir', () {
    test('an explicit folder is used as it is', () async {
      final log = <String>[];
      final r = await resolveProjectsDir(
          explicit: '/data/my projects/', operatingSystem: 'linux', environment: const {}, run: runner({}, log));
      expect(r.path, '/data/my projects');
      expect(r.source, contains('--projects-dir'));
      expect(log, isEmpty, reason: 'nothing is looked up');
    });

    test('Windows: the Shell answer wins (Documents moved into OneDrive)', () async {
      final r = await resolveProjectsDir(
        operatingSystem: 'windows',
        environment: const {'USERPROFILE': r'C:\Users\Ann', 'OneDrive': r'C:\Users\Ann\OneDrive'},
        run: runner({'powershell': 'C:\\Users\\Ann\\OneDrive\\Documents\r\n', 'reg': null}),
        dirExists: (_) => true,
      );
      expect(r.path, r'C:\Users\Ann\OneDrive\Documents\ClipForge\projects');
      expect(r.source, contains('Shell'));
      expect(r.alsoChecked, [r'C:\Users\Ann\Documents\ClipForge\projects']);
    });

    test('Windows: a non-ASCII Documents path survives', () async {
      final r = await resolveProjectsDir(
        operatingSystem: 'windows',
        environment: const {'USERPROFILE': r'C:\Users\Женя'},
        run: runner({'powershell': 'C:\\Users\\Женя\\OneDrive\\Документы\r\n'}),
        dirExists: (_) => false,
      );
      expect(r.path, r'C:\Users\Женя\OneDrive\Документы\ClipForge\projects');
    });

    test('Windows: without PowerShell the registry is used, if that folder exists', () async {
      const reg = '    Personal    REG_EXPAND_SZ    %USERPROFILE%\\OneDrive\\Documents\r\n';
      const env = {'USERPROFILE': r'C:\Users\Ann'};
      final yes = await resolveProjectsDir(
          operatingSystem: 'windows',
          environment: env,
          run: runner({'powershell': null, 'reg': reg}),
          dirExists: (_) => true);
      expect(yes.path, r'C:\Users\Ann\OneDrive\Documents\ClipForge\projects');
      expect(yes.source, contains('registry'));
      // A garbled (non-existing) registry value is not believed.
      final no = await resolveProjectsDir(
          operatingSystem: 'windows',
          environment: env,
          run: runner({'powershell': null, 'reg': reg}),
          dirExists: (_) => false);
      expect(no.path, r'C:\Users\Ann\Documents\ClipForge\projects');
      expect(no.source, contains('USERPROFILE'));
    });

    test('Windows: falls back to the candidate that really holds the projects', () async {
      const elsewhere = r'C:\Users\Ann\OneDrive\Documents\ClipForge\projects';
      final r = await resolveProjectsDir(
        operatingSystem: 'windows',
        environment: const {'USERPROFILE': r'C:\Users\Ann', 'OneDrive': r'C:\Users\Ann\OneDrive'},
        run: runner({'powershell': 'C:\\Users\\Ann\\Documents\r\n'}),
        dirExists: (path) => path == elsewhere,
      );
      expect(r.path, elsewhere);
      expect(r.source, contains('does not exist'));
      expect(r.alsoChecked, [r'C:\Users\Ann\Documents\ClipForge\projects']);
    });

    test('macOS: ~/Documents, no programs are run', () async {
      final log = <String>[];
      final r = await resolveProjectsDir(
          operatingSystem: 'macos',
          environment: const {'HOME': '/Users/ann'},
          run: runner({}, log),
          dirExists: (_) => false);
      expect(r.path, '/Users/ann/Documents/ClipForge/projects');
      expect(log, isEmpty);
    });

    test('Linux: xdg-user-dir first, then ~/Documents', () async {
      const env = {'HOME': '/home/ann'};
      final xdg = await resolveProjectsDir(
          operatingSystem: 'linux',
          environment: env,
          run: runner({'xdg-user-dir': '/home/ann/Dokumente\n'}),
          dirExists: (_) => true);
      expect(xdg.path, '/home/ann/Dokumente/ClipForge/projects');
      final plain = await resolveProjectsDir(
          operatingSystem: 'linux', environment: env, run: runner({}), dirExists: (_) => true);
      expect(plain.path, '/home/ann/Documents/ClipForge/projects');
    });

    test('no home folder at all is an error that names the option', () async {
      await expectLater(
          resolveProjectsDir(operatingSystem: 'macos', environment: const {}, run: runner({})),
          throwsA(isA<FileSystemException>().having((e) => e.message, 'message', contains('--projects-dir'))));
    });

    test('on this machine the default ends in ClipForge/projects', () async {
      final r = await resolveProjectsDir();
      expect(p.isAbsolute(r.path), isTrue);
      expect(p.split(r.path).reversed.take(2), ['projects', 'ClipForge']);
    });
  });

  group('ffmpeg lookup', () {
    test('install hints name the command for each system', () {
      expect(ffmpegInstallHint('windows'), contains('winget install ffmpeg'));
      expect(ffmpegInstallHint('macos'), contains('brew install ffmpeg'));
      expect(ffmpegInstallHint('linux'), contains('apt install ffmpeg'));
    });

    test('usual folders cover Homebrew and winget', () {
      expect(usualToolDirs('macos', const {'HOME': '/Users/ann'}), containsAll(['/opt/homebrew/bin', '/usr/local/bin']));
      expect(usualToolDirs('windows', const {'LOCALAPPDATA': r'C:\Users\Ann\AppData\Local'}),
          contains(r'C:\Users\Ann\AppData\Local\Microsoft\WinGet\Links'));
    });

    test('a configured path that does not work is reported, with the install hint', () async {
      final tools = MediaTools(ffmpegOption: '/no/such/ffmpeg', ffprobeOption: '/no/such/ffprobe');
      expect(await tools.ffmpeg(), isNull);
      expect(await tools.ffprobe(), isNull);
      await expectLater(
          tools.requireEngine(),
          throwsA(isA<ToolError>().having(
              (e) => e.message,
              'message',
              allOf(contains('ffmpeg and ffprobe'), contains('/no/such/ffmpeg'), contains(ffmpegNeededMessage()),
                  contains('--ffmpeg <path>')))));
    });

    test('nothing on the PATH and nothing configured: not found', () async {
      final empty = Directory.systemTemp.createTempSync('clipforge_mcp_nopath_');
      addTearDown(() => empty.deleteSync(recursive: true));
      // "windows" so that none of this machine's usual folders is searched.
      final tools = MediaTools(environment: {'PATH': empty.path}, operatingSystem: 'windows', executableDir: empty.path);
      expect(await tools.ffmpeg(), isNull);
      await expectLater(tools.requireEngine(),
          throwsA(isA<ToolError>().having((e) => e.message, 'message', contains('winget install ffmpeg'))));
    });

    test('finds ffmpeg through the PATH and reports path and version', () async {
      final tools = MediaTools();
      final mpeg = await tools.ffmpeg();
      final probe = await tools.ffprobe();
      expect(mpeg, isNotNull);
      expect(p.isAbsolute(mpeg!.path), isTrue);
      expect(mpeg.version, matches(RegExp(r'\d')));
      expect(p.dirname(probe!.path), p.dirname(mpeg.path));
      final engine = await tools.requireEngine();
      expect(engine.ffmpegPath, mpeg.path);
      expect(await tools.requireEngine(), same(engine));
    }, skip: skipWithoutFfmpeg);

    test('a program that appears later is found without a restart', () async {
      final dir = Directory.systemTemp.createTempSync('clipforge_mcp_late_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final tools = MediaTools(environment: {'PATH': dir.path}, operatingSystem: 'windows', executableDir: dir.path);
      expect(await tools.ffmpeg(), isNull);
      // "Install" it: on Windows the server looks for ffmpeg.exe.
      final real = (await MediaTools().ffmpeg())!.path;
      Link(p.join(dir.path, 'ffmpeg.exe')).createSync(real);
      expect((await tools.ffmpeg())?.path, p.join(dir.path, 'ffmpeg.exe'));
    }, skip: Platform.isWindows ? 'needs symbolic links' : skipWithoutFfmpeg);
  });

  group('locateFonts', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('clipforge_mcp_fonts_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void put(String dir, {bool bold = true}) {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, kFontRegular)).writeAsStringSync('r');
      if (bold) File(p.join(dir, kFontBold)).writeAsStringSync('b');
    }

    FontLookup look({String? explicit}) => locateFonts(
        explicitDir: explicit,
        executableDir: p.join(tmp.path, 'exe'),
        scriptDir: p.join(tmp.path, 'repo', 'bin'),
        workingDir: p.join(tmp.path, 'cwd'));

    test('nothing anywhere: null, with the folders that were checked', () {
      final r = look();
      expect(r.fonts, isNull);
      expect(r.checked, contains(p.join(tmp.path, 'exe', 'fonts')));
      expect(r.checked.toSet().length, r.checked.length);
    });

    test('fonts/ next to the executable (macOS download, Linux)', () {
      put(p.join(tmp.path, 'exe', 'fonts'));
      final r = look();
      expect(r.fonts!.regular, p.join(tmp.path, 'exe', 'fonts', kFontRegular));
      expect(r.fonts!.bold, p.join(tmp.path, 'exe', 'fonts', kFontBold));
    });

    test('the Flutter bundle next to clipforge.exe (Windows download)', () {
      final dir = p.join(tmp.path, 'exe', 'data', 'flutter_assets', 'assets', 'fonts');
      put(dir);
      expect(p.dirname(look().fonts!.regular), dir);
    });

    test('ClipForge.app beside the executable (macOS)', () {
      final dir = p.join(tmp.path, 'exe', 'ClipForge.app', 'Contents', 'Frameworks', 'App.framework', 'Resources',
          'flutter_assets', 'assets', 'fonts');
      put(dir);
      expect(p.dirname(look().fonts!.regular), dir);
    });

    test('the repository when run from source', () {
      final dir = p.join(tmp.path, 'repo', 'assets', 'fonts');
      put(dir);
      expect(p.dirname(look().fonts!.regular), dir);
    });

    test('both files are needed', () {
      put(p.join(tmp.path, 'exe', 'fonts'), bold: false);
      expect(look().fonts, isNull);
    });

    test('an explicit folder is the only one looked at', () {
      put(p.join(tmp.path, 'exe', 'fonts'));
      final other = p.join(tmp.path, 'other');
      expect(look(explicit: other).fonts, isNull);
      expect(look(explicit: other).checked, [other]);
      put(other);
      expect(p.dirname(look(explicit: other).fonts!.bold), other);
    });

    test('this checkout: found from the working directory', () {
      final r = locateFonts(executableDir: tmp.path, scriptDir: tmp.path);
      expect(r.fonts, isNotNull);
      expect(File(r.fonts!.regular).lengthSync(), greaterThan(100000));
    });
  });
}
