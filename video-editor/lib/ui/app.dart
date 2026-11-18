import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'about.dart';
import 'app_menu.dart';
import 'help/help_screen.dart';
import 'help/tour.dart';
import 'home/home_screen.dart';
import 'theme.dart';

/// The app's navigator, for the menu bar (which sits above it).
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'app navigator');

class ClipForgeApp extends ConsumerWidget {
  const ClipForgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(tourControllerProvider);
    return MaterialApp(
      title: 'ClipForge',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: appNavigatorKey,
      home: const HomeScreen(),
      // The app's menu bar: macOS in the system's bar; Windows and Linux
      // along the top of the window (File, Edit, Playback, Help).
      // Everywhere: the guided tour draws over every screen.
      builder: (context, child) => AppMenuBar(
        help: HelpMenuActions(
          openHelp: () {
            final navigator = appNavigatorKey.currentState;
            if (navigator != null) openHelp(navigator.context);
          },
          showTour: tour.requestStart,
          showAbout: () {
            final navigator = appNavigatorKey.currentState;
            if (navigator != null) showAboutClipForge(navigator.context);
          },
          copyVersionInfo: () {
            final navigator = appNavigatorKey.currentState;
            if (navigator != null) copyVersionInfo(navigator.context);
          },
        ),
        child: TourOverlayHost(child: child!),
      ),
    );
  }
}
