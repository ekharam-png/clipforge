import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/build_info.dart';
import '../core/perf_log.dart';
import '../core/update/update_log.dart';
import '../core/links.dart';
import 'feedback/feedback_screen.dart';
import 'help/help_screen.dart';
import 'help/whats_new.dart';
import 'links.dart';
import 'theme.dart';
import 'update/update_controller.dart' show updatePlatformProvider;

// "Which build is this?": the About ClipForge box, the small version line
// on the project list and in Help, and "Copy version info" for bug
// reports. The version itself is lib/core/build_info.dart.

/// This app's build. Tests put another one here.
final buildInfoProvider = Provider<BuildInfo>((ref) => BuildInfo.current);

/// The performance log (core/perf_log.dart). Tests put their own here.
final perfLogProvider = Provider<PerfLog>((ref) => PerfLog.instance);

/// The system and device, for "Copy version info".
class DeviceDetails {
  const DeviceDetails({required this.system, this.device});

  /// e.g. "macOS Version 15.1 (Build 24B83), macos_arm64".
  final String system;

  /// e.g. "samsung SM-S911B" (Android only).
  final String? device;
}

/// Reads [DeviceDetails]. Tests put a fake here.
final deviceDetailsProvider =
    Provider<Future<DeviceDetails> Function()>((ref) => readDeviceDetails);

/// The real [DeviceDetails] of this device. Never throws.
Future<DeviceDetails> readDeviceDetails() async {
  final arch = RegExp(r'on "([^"]+)"').firstMatch(Platform.version)?.group(1);
  final os = switch (Platform.operatingSystem) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    'android' => 'Android',
    'ios' => 'iOS',
    final other => other,
  };
  var system = '$os ${Platform.operatingSystemVersion}'.trim();
  if (arch != null) system = '$system, $arch';
  String? device;
  if (Platform.isAndroid) {
    try {
      final info = await const MethodChannel('clipforge/device')
          .invokeMapMethod<String, Object?>('info')
          .timeout(const Duration(seconds: 3));
      if (info != null) {
        device = '${info['manufacturer']} ${info['model']}'.trim();
        system = 'Android ${info['release']} (API ${info['sdk']})'
            '${arch == null ? '' : ', $arch'}';
      }
    } catch (_) {}
  }
  return DeviceDetails(system: system, device: device);
}

/// Copies the version line, build details and device to the clipboard and
/// says so.
Future<void> copyVersionInfo(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final info = container.read(buildInfoProvider);
  final media = MediaQuery.maybeOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final details = await container.read(deviceDetailsProvider)();
  final screen = media == null
      ? null
      : '${media.size.width.round()}x${media.size.height.round()} '
          '(scale ${media.devicePixelRatio.toStringAsFixed(1)})';
  var text = versionReport(info,
      system: details.system, device: details.device, screen: screen);
  // Computers: where the app runs from and the last lines of the update
  // log (1.14.1), when an update has ever been tried here.
  try {
    final updates = container.read(updatePlatformProvider);
    if (updates.installDir != null) {
      text = '$text\nFolder: ${updates.installDir}';
    }
    final log = updateLogReport(await updates.stateDir());
    if (log != null) text = '$text\n\n$log';
  } catch (_) {}
  // The performance log (1.17): its last lines here, the whole of it in
  // perf-log.txt in ClipForge's data folder, written now.
  try {
    final perf = container.read(perfLogProvider);
    if (perf.last(1).isNotEmpty || perf.previousRun.isNotEmpty) {
      text = '$text\n\n${perf.shared()}';
      final written = await perf
          .write(header: info.describe())
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (written != null) {
        text = '$text\nThe whole log is in $kPerfLogFileName in '
            "ClipForge's data folder.";
      }
    }
  } catch (_) {}
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
        content: Text('Version info copied. Paste it into your message.')));
}

/// Opens [url] in the browser; says its address when that does not work.
Future<void> openOutsidePage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ProviderScope.containerOf(context)
        .read(updatePlatformProvider)
        .openUrl(url);
  } catch (_) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('The page could not be opened. Its address is: $url')));
  }
}

/// The About ClipForge box: version, build time (in this computer's time
/// zone and in UTC), commit, Copy version info and What's new.
Future<void> showAboutClipForge(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const AboutClipForgeDialog(),
  );
}

class AboutClipForgeDialog extends ConsumerWidget {
  const AboutClipForgeDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(buildInfoProvider);
    final links = ref.watch(linksProvider)..ready();
    final text = Theme.of(context).textTheme;
    const dim = TextStyle(color: AppColors.textDim);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 92, child: Text(label, style: dim)),
              Expanded(child: SelectableText(value)),
            ],
          ),
        );
    final time = info.buildTime;
    return AlertDialog(
      key: const ValueKey('about-dialog'),
      title: const Text('About $kAppName'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ClipForge ${info.version}', style: text.headlineSmall),
              const SizedBox(height: 4),
              const Text('A video editor for your phone and computer.',
                  style: dim),
              const SizedBox(height: 10),
              row('Build', info.buildNumber ?? 'unknown'),
              row(
                  'Built',
                  time == null
                      ? 'local build (made on a computer, not by GitHub)'
                      : '${formatBuildTime(time, utc: false)}\n'
                          '${formatBuildTime(time)}'),
              row('Commit', info.commit ?? 'unknown'),
              const SizedBox(height: 6),
              // The website (the address comes from lib/core/links.dart,
              // or from the newest release when the site has moved).
              ListenableBuilder(
                listenable: links,
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 92, child: Text('Website', style: dim)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          key: const ValueKey('about-website'),
                          onTap: () => openOutsidePage(context, links.current.site),
                          child: Text(links.current.siteLabel,
                              style: const TextStyle(
                                  color: AppColors.accent,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.accent)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                  'When you report a problem, tap Copy version info and '
                  'paste it into your message, so we know exactly which '
                  'build you used.',
                  style: text.bodySmall?.copyWith(color: AppColors.textDim)),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const ValueKey('about-send-feedback'),
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            openFeedback(navigator.context);
          },
          child: const Text('Send feedback'),
        ),
        TextButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            openHelp(navigator.context, articleId: kWhatsNewId);
          },
          child: const Text("What's new"),
        ),
        TextButton.icon(
          key: const ValueKey('copy-version-info'),
          onPressed: () => copyVersionInfo(context),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy version info'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The small muted line "ClipForge 1.4.0 (build 21) · 16 Nov 2026, 08:20
/// (UTC+1) · 877e482" (time in this computer's time zone). Tapping it
/// opens About ClipForge.
class VersionLine extends ConsumerWidget {
  const VersionLine({
    super.key,
    this.padding = const EdgeInsets.all(8),
    this.textAlign = TextAlign.center,
  });
  final EdgeInsets padding;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(buildInfoProvider);
    final line = info.describe(utc: false);
    return Semantics(
      button: true,
      label: 'About ClipForge. $line',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('version-line'),
        onTap: () => showAboutClipForge(context),
        child: Padding(
          padding: padding,
          child: Text(
            line,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ),
      ),
    );
  }
}

/// Whether About ClipForge is in a menu bar (macOS app menu, Windows and
/// Linux Help menu); phones offer it on the project list's "More" menu.
bool get aboutInMenuBar =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);
