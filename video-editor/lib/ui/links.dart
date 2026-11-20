import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/build_info.dart';
import '../core/links.dart';
import 'about.dart' show buildInfoProvider;
import 'app_prefs.dart';

// The outside addresses the app uses right now (1.16): the built-in ones
// (lib/core/links.dart), or the last ones a latest.json carried. They are
// remembered in settings.json together with the version that saw them; a
// newer version of the app starts from its own built-in addresses again
// (they are at least as new) until its first update check.

/// [AppPrefs.text]: `{"v":"1.16.0","links":{...}}` as JSON text.
const String kLinksSeenText = 'linksSeen';

class LinksController extends ChangeNotifier {
  LinksController({required this.prefs, required this.build, this.allowHttp = false});

  final AppPrefs prefs;
  final BuildInfo build;

  /// Tests use a local server.
  final bool allowHttp;

  /// The addresses in use.
  AppLinks current = AppLinks.builtIn;
  Future<void>? _loading;

  /// [current], once what was remembered has been read (read once per run).
  Future<AppLinks> ready() async {
    await (_loading ??= _load());
    return current;
  }

  Future<void> _load() async {
    try {
      final text = await prefs.text(kLinksSeenText);
      if (text != null) {
        final json = jsonDecode(text);
        if (json is Map && json['v'] == build.version) {
          current = AppLinks.builtIn
              .withOverrides(json['links'], allowHttp: allowHttp);
        }
      }
    } catch (_) {
      // Unreadable: the built-in addresses.
    }
  }

  /// What a latest.json just said (null: it has no "links", nothing
  /// changes). Only what passes the checks is used; what is remembered is
  /// checked again when it is read.
  Future<void> remember(Map<String, String>? links) async {
    if (links == null) return;
    await ready();
    final next = AppLinks.builtIn.withOverrides(links, allowHttp: allowHttp);
    try {
      await prefs.setText(
          kLinksSeenText, jsonEncode({'v': build.version, 'links': links}));
    } catch (_) {}
    if (next != current) {
      current = next;
      notifyListeners();
    }
  }
}

final linksProvider = Provider<LinksController>((ref) {
  final c = LinksController(
      prefs: ref.watch(appPrefsProvider), build: ref.watch(buildInfoProvider));
  ref.onDispose(c.dispose);
  return c;
});
