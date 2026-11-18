// docs/FEATURES.md (the feature log) must mention every version that
// CHANGELOG.md has, so it is updated with each release.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every CHANGELOG version is in docs/FEATURES.md', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final features = File('docs/FEATURES.md').readAsStringSync();
    final versions = [
      for (final m in RegExp(r'^## (\d+\.\d+\.\d+)', multiLine: true)
          .allMatches(changelog))
        m.group(1)!,
    ];
    expect(versions, isNotEmpty);
    final missing = [
      for (final v in versions)
        if (!features.contains(v)) v,
    ];
    expect(missing, isEmpty,
        reason: 'Add these versions and their features to docs/FEATURES.md');
    expect(features, contains('## Planned'));
  });
}
