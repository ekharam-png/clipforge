// Windows paths in the export command: a user folder with a space and
// Cyrillic letters (C:\Users\Евгений Иванов\...), the temp folder under it
// (title text files), the fonts under AppData, and media file names with
// commas, brackets and an apostrophe.
//
// Input and output files are separate arguments (no escaping needed); the
// paths INSIDE the filter graph (drawtext fontfile / textfile) must survive
// the graph parser. The integration part runs the exact graph through the
// system ffmpeg on Linux: "C:" is then just a folder in the working
// directory, so `C:/Users/...` is a relative path that exists (inputs and
// the output get `file:` in front, because Linux ffmpeg would read "C:" as
// a protocol; Windows ffmpeg treats a drive letter as a file path).

import 'dart:convert';
import 'dart:io';

import 'package:clipforge/core/model/project.dart';
import 'package:clipforge/media/ffmpeg_command.dart';
import 'package:clipforge/media/media_api.dart';
import 'package:clipforge/media/media_fonts.dart' show fontDirCandidates;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _user = r'C:\Users\Евгений Иванов';
const _work = '$_user\\AppData\\Local\\Temp\\clipforge_export_ab12';
const _fonts = '$_user\\AppData\\Roaming\\com.example\\clipforge\\clipforge_fonts';
const _video = '$_user\\Videos\\Мой клип (1).mp4';
const _music = "$_user\\Music\\song, it's [live].mp3";
const _out = '$_user\\Videos\\ClipForge\\Видео 1.mp4';

final _t0 = DateTime.utc(2026);

Project _project() => Project(
      id: 'p',
      name: 'p',
      createdAt: _t0,
      updatedAt: _t0,
      duckMusic: true,
      clips: const [
        Clip(
          id: 'c1', type: ClipType.video, path: _video,
          sourceDurationMs: 4000, inMs: 0, outMs: 4000,
          width: 320, height: 240, denoise: true, voiceFocus: 0.85,
        ),
      ],
      audio: const [
        AudioClip(
          id: 'm', path: _music, sourceDurationMs: 10000,
          startMs: 0, inMs: 0, outMs: 10000,
          fadeInMs: 1000, fadeOutMs: 1500, volume: 0.8,
        ),
      ],
      titles: const [
        TitleOverlay(
            id: 't', text: "Привет: it's 100% [ok], yes", startMs: 0,
            endMs: 4000, fontSize: 0.12),
      ],
    );

FfmpegCommand _build() => buildExportCommand(
      project: _project(),
      outputPath: _out,
      fonts: const FontPaths(
          regular: '$_fonts\\DejaVuSans.ttf',
          bold: '$_fonts\\DejaVuSans-Bold.ttf'),
      workDir: _work,
      options: const ExportOptions(quality: ExportQuality.small),
    );

void main() {
  test('paths inside the graph: forward slashes, drive colon and space '
      'escaped, letters kept', () {
    expect(escapeFilterPath(r'C:\Users\Евгений Иванов\a, b [1].txt'),
        r'C\\:/Users/Евгений\ Иванов/a\,\ b\ \[1\].txt');
    final cmd = _build();
    final text = cmd.textFiles.keys.first;
    expect(text, startsWith(_work));
    expect(cmd.filterGraph,
        contains(r'fontfile=C\\:/Users/Евгений\ Иванов/AppData/Roaming/'
            r'com.example/clipforge/clipforge_fonts/DejaVuSans-Bold.ttf'
            r':textfile=C\\:/Users/Евгений\ Иванов/AppData/Local/Temp/'
            r'clipforge_export_ab12/title_0_0.txt:'));
    // Media paths are plain arguments.
    expect(cmd.args, containsAllInOrder(['-i', _video]));
    expect(cmd.args, containsAllInOrder(['-i', _music]));
    expect(cmd.args.last, _out);
  });

  test('fonts go to an ASCII folder on Windows when the user folder is not '
      '(FreeType opens them with CreateFileA)', () {
    const env = {
      'ProgramData': r'C:\ProgramData',
      'PUBLIC': r'C:\Users\Public',
    };
    expect(fontDirCandidates(r'C:\Users\you\AppData\Roaming\x\clipforge_fonts', env),
        [r'C:\Users\you\AppData\Roaming\x\clipforge_fonts']);
    expect(fontDirCandidates(_fonts, env), [
      r'C:\ProgramData\ClipForge\fonts',
      r'C:\Users\Public\ClipForge\fonts',
      _fonts,
    ]);
    expect(fontDirCandidates(_fonts, const {}), [_fonts]);
  });

  final ok = Process.runSync('which', ['ffmpeg']).exitCode == 0;
  test('the exact command runs with such paths (system ffmpeg)', () async {
    if (!ok) {
      markTestSkipped('ffmpeg not installed');
      return;
    }
    final root = await Directory.systemTemp.createTemp('cf_winpaths_');
    addTearDown(() => root.delete(recursive: true));
    String local(String windowsPath) =>
        p.join(root.path, windowsPath.replaceAll(r'\', '/'));
    Future<void> ff(List<String> args) async {
      final r = await Process.run('ffmpeg',
          ['-hide_banner', '-loglevel', 'error', '-y', ...args],
          stderrEncoding: utf8);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    for (final f in [_video, _music, _out, '$_fonts\\x', '$_work\\x']) {
      await Directory(p.dirname(local(f))).create(recursive: true);
    }
    await ff([
      '-f', 'lavfi', '-i', 'testsrc=d=4:s=320x240:r=30',
      '-f', 'lavfi', '-i', 'sine=f=220:d=4', '-ac', '2',
      '-c:v', 'libx264', '-c:a', 'aac', '-shortest', local(_video),
    ]);
    await ff(['-f', 'lavfi', '-i', 'sine=f=660:d=10', '-ac', '2',
      '-c:a', 'aac', '-f', 'mp4', local(_music)]);
    for (final n in ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf']) {
      await File('assets/fonts/$n').copy(local('$_fonts\\$n'));
    }
    final cmd = _build();
    for (final e in cmd.textFiles.entries) {
      await File(local(e.key)).writeAsString(e.value);
    }
    final args = [
      for (var i = 0; i < cmd.args.length; i++)
        (i > 0 && cmd.args[i - 1] == '-i') || i == cmd.args.length - 1
            ? 'file:${cmd.args[i].replaceAll(r'\', '/')}'
            : cmd.args[i],
    ];
    final r = await Process.run('ffmpeg', ['-hide_banner', ...args],
        workingDirectory: root.path, stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final out = File(local(_out));
    expect(out.lengthSync(), greaterThan(0));

    // The music fades in: quiet in its first 0.25 s, full a second later.
    double rms(int fromMs, int toMs) {
      final s = Process.runSync('ffmpeg', [
        '-hide_banner', '-nostats', '-ss', '${fromMs / 1000}',
        '-t', '${(toMs - fromMs) / 1000}', '-i', out.path,
        '-af', 'bandpass=f=660:w=60,volumedetect', '-f', 'null', '-',
      ]).stderr as String;
      return double.parse(
          RegExp(r'mean_volume: (-?[\d.]+) dB').firstMatch(s)!.group(1)!);
    }

    expect(rms(1500, 2000) - rms(0, 250), greaterThan(12));
  });
}
