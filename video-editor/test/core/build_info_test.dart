// The version line every build shows (lib/core/build_info.dart): parsing of
// the compile-time defines and the text people quote in bug reports.

import 'dart:io';

import 'package:clipforge/core/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a CI build (all defines given)', () {
    final info = BuildInfo.fromValues(
      version: '1.4.0',
      buildNumber: '21',
      buildTime: '2026-11-16T07:20:31Z',
      commit: '877e482c0ffee',
      channel: 'ci',
    );

    test('reads every value', () {
      expect(info.version, '1.4.0');
      expect(info.buildNumber, '21');
      expect(info.buildTime, DateTime.utc(2026, 11, 16, 7, 20, 31));
      expect(info.buildTime!.isUtc, isTrue);
      expect(info.commit, '877e482', reason: 'shortened to 7');
      expect(info.isCi, isTrue);
    });

    test('the display string', () {
      expect(info.versionLabel, '1.4.0 (build 21)');
      expect(info.describe(),
          'ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482');
      expect(info.describe(name: 'clipforge-mcp'),
          startsWith('clipforge-mcp 1.4.0 (build 21) · '));
    });

    test('on screen the time is in this computer\'s time zone', () {
      final local = info.buildTime!.toLocal();
      final shown = info.describe(utc: false);
      expect(shown, startsWith('ClipForge 1.4.0 (build 21) · '));
      expect(shown, endsWith(' · 877e482'));
      expect(shown, contains('${local.day} Nov 2026, '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')} '
          '(${utcOffsetLabel(local.timeZoneOffset)})'));
    });

    test('as JSON for the Claude control server', () {
      expect(info.toJson(), {
        'version': '1.4.0',
        'buildNumber': '21',
        'buildTime': '2026-11-16T07:20:31.000Z',
        'commit': '877e482',
        'channel': 'ci',
        'display':
            'ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482',
      });
    });
  });

  group('a local build (no defines)', () {
    test('says "local build" instead of a time', () {
      final info = BuildInfo.fromValues(version: '1.4.0', buildNumber: '1');
      expect(info.buildTime, isNull);
      expect(info.commit, isNull);
      expect(info.channel, 'local');
      expect(info.describe(), 'ClipForge 1.4.0 (build 1) · local build');
      expect(info.describe(utc: false), info.describe());
    });

    test('nothing at all: "dev", no build number', () {
      final info = BuildInfo.fromValues();
      expect(info.version, BuildInfo.kUnknownVersion);
      expect(info.buildNumber, isNull);
      expect(info.describe(), 'ClipForge dev · local build');
    });

    test('a time given to a local build is marked local', () {
      final info = BuildInfo.fromValues(
          version: '1.4.0', buildTime: '2026-11-16T07:20:00Z');
      expect(info.timeLabel(), 'local build, 16 Nov 2026, 07:20 UTC');
    });

    test('this test run compiles in pubspec.yaml\'s version', () {
      final m = RegExp(r'^version:\s*([^\s+]+)\+(\d+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!;
      expect(BuildInfo.current.version, m[1]);
      expect(BuildInfo.current.buildNumber, m[2]);
      expect(BuildInfo.current.channel, 'local');
    });
  });

  group('bad values are left out, not guessed', () {
    test('build number, commit, channel', () {
      final info = BuildInfo.fromValues(
          version: ' 1.4.0 ',
          buildNumber: 'abc',
          commit: 'not-a-sha!',
          channel: 'nightly');
      expect(info.version, '1.4.0');
      expect(info.buildNumber, isNull);
      expect(info.commit, isNull);
      expect(info.channel, 'local');
      expect(BuildInfo.fromValues(commit: 'ABC1234').commit, 'abc1234');
      expect(BuildInfo.fromValues(channel: 'CI').channel, 'ci');
    });

    test('times', () {
      expect(parseBuildTime(null), isNull);
      expect(parseBuildTime(''), isNull);
      expect(parseBuildTime('yesterday'), isNull);
      // Without a zone: UTC.
      expect(parseBuildTime('2026-11-16T07:20:00'),
          DateTime.utc(2026, 11, 16, 7, 20));
      expect(parseBuildTime('2026-11-16T09:20:00+02:00'),
          DateTime.utc(2026, 11, 16, 7, 20));
    });
  });

  test('time formatting', () {
    final t = DateTime.utc(2026, 1, 5, 3, 4);
    expect(formatBuildTime(t), '5 Jan 2026, 03:04 UTC');
    expect(utcOffsetLabel(Duration.zero), 'UTC');
    expect(utcOffsetLabel(const Duration(hours: 2)), 'UTC+2');
    expect(utcOffsetLabel(const Duration(hours: -5)), 'UTC-5');
    expect(utcOffsetLabel(const Duration(hours: 5, minutes: 30)), 'UTC+5:30');
    expect(utcOffsetLabel(const Duration(hours: -3, minutes: -30)), 'UTC-3:30');
  });

  test('the copied report', () {
    final info = BuildInfo.fromValues(
        version: '1.4.0',
        buildNumber: '21',
        buildTime: '2026-11-16T07:20:00Z',
        commit: '877e482',
        channel: 'ci');
    expect(
        versionReport(info,
            system: 'Android 14 (API 34), android_arm64',
            device: 'samsung SM-S911B',
            screen: '390x844 (scale 3.0)'),
        'ClipForge 1.4.0 (build 21) · 16 Nov 2026, 07:20 UTC · 877e482\n'
        'Version: 1.4.0\n'
        'Build: 21 (ci)\n'
        'Built: 2026-11-16T07:20:00.000Z\n'
        'Commit: 877e482\n'
        'System: Android 14 (API 34), android_arm64\n'
        'Device: samsung SM-S911B\n'
        'Screen: 390x844 (scale 3.0)');
    final local = versionReport(BuildInfo.fromValues(version: '1.4.0'),
        system: 'macOS 15');
    expect(local, contains('Built: local build, no time recorded'));
    expect(local, contains('Build: unknown (local)'));
    expect(local, isNot(contains('Device:')));
  });
}
