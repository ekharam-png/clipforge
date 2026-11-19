import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/connect.dart';
import '../../core/storage/project_lock.dart' as lock;

// The computer as "Connect to Claude" needs it (see
// lib/core/claude/connect.dart for the rules), and the Test button's
// helper run. Tests replace both through the providers.

class RealConnectHost implements ConnectHost {
  @override
  String get os => Platform.operatingSystem;

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  bool dirExists(String path) => Directory(path).existsSync();

  @override
  List<String> listDirs(String path) {
    try {
      return [
        for (final e in Directory(path).listSync(followLinks: false))
          if (e is Directory) e.uri.pathSegments.where((s) => s.isNotEmpty).last,
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  String? readText(String path) {
    try {
      var text = utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      return text;
    } catch (_) {
      return null;
    }
  }

  @override
  void writeText(String path, String text) {
    // Whole or not at all: a temporary file, then a rename.
    final tmp = File('$path.clipforge-tmp');
    tmp.writeAsStringSync(text, flush: true);
    tmp.renameSync(path);
  }

  @override
  void deleteFile(String path) => File(path).deleteSync();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<RunResult> run(String exe, List<String> args,
      {String? workingDirectory,
      Duration timeout = const Duration(seconds: 30)}) async {
    // .cmd / .bat (npm's "claude.cmd") need the shell on Windows.
    final lower = exe.toLowerCase();
    final shell =
        Platform.isWindows && (lower.endsWith('.cmd') || lower.endsWith('.bat'));
    final r = await Process.run(exe, args,
            workingDirectory: workingDirectory,
            runInShell: shell,
            stdoutEncoding: utf8,
            stderrEncoding: utf8)
        .timeout(timeout);
    return RunResult(r.exitCode, '${r.stdout}', '${r.stderr}');
  }

  @override
  Future<bool> processAlive(int pid) => lock.processAlive(pid);
}

final connectHostProvider = Provider<ConnectHost>((ref) => RealConnectHost());

/// The names of the files in a folder (for the helper's "in use" files).
List<String> listFileNames(String dir) {
  try {
    return [
      for (final e in Directory(dir).listSync(followLinks: false))
        if (e is File) e.uri.pathSegments.last,
    ];
  } catch (_) {
    return const [];
  }
}

final helperFilesProvider =
    Provider<List<String> Function(String dir)>((ref) => listFileNames);

/// Starts the helper at a path by itself, does the handshake and the
/// quick self-test, and says PASS or FAIL. Independent of Claude.
typedef HelperTester = Future<HelperTestResult> Function(String launcher);

Future<HelperTestResult> runHelperTest(String launcher,
    {Duration timeout = const Duration(seconds: 120)}) async {
  if (!File(launcher).existsSync()) {
    return HelperTestResult(false, 'FAIL: the helper is not there.', launcher);
  }
  final Process proc;
  try {
    proc = await Process.start(launcher, const []);
  } catch (e) {
    return HelperTestResult(false, 'FAIL: the helper could not be started.', '$e');
  }
  final out = StringBuffer(), err = StringBuffer();
  final answered = Completer<void>();
  final outSub = proc.stdout.transform(utf8.decoder).listen((chunk) {
    out.write(chunk);
    // The self-test's answer (id 2) is the last thing wanted.
    if (!answered.isCompleted && RegExp(r'"id"\s*:\s*2\b').hasMatch(out.toString())) {
      answered.complete();
    }
  });
  final errSub = proc.stderr.transform(utf8.decoder).listen(err.write);
  int? code;
  try {
    for (final m in helperTestMessages()) {
      proc.stdin.writeln(m);
    }
    await proc.stdin.flush();
    await Future.any([answered.future, proc.exitCode]).timeout(timeout);
    await proc.stdin.close();
    code = await proc.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    proc.kill();
    await outSub.cancel();
    await errSub.cancel();
    return HelperTestResult(
        false,
        'FAIL: the helper did not finish the test in '
            '${timeout.inSeconds} seconds.',
        err.toString().trim());
  } catch (e) {
    proc.kill();
  }
  await outSub.cancel();
  await errSub.cancel();
  return readHelperTest(out.toString(), stderr: err.toString(), exitCode: code);
}

final helperTesterProvider = Provider<HelperTester>((ref) => runHelperTest);
