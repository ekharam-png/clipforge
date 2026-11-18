import 'package:material_ui/material_ui.dart';

/// Colours used outside the Material colour scheme.
abstract final class AppColors {
  static const background = Color(0xFF0E0F12);
  static const panel = Color(0xFF17191E);
  static const panelHigh = Color(0xFF22252C);
  static const outline = Color(0xFF30343D);
  static const accent = Color(0xFF7C9BFF);
  static const textDim = Color(0xFF9AA0AC);
  static const clip = Color(0xFF34507A);
  static const photo = Color(0xFF5B4A82);
  static const audio = Color(0xFF2F7D62);
  static const overlay = Color(0xFF2B6F80);
  static const title = Color(0xFFA8672C);
  static const caption = Color(0xFF8E3F76);
  static const missing = Color(0xFF7A2E2E);
  static const playhead = Color(0xFFFFFFFF);
  static const danger = Color(0xFFFF6B6B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    surface: AppColors.background,
    surfaceContainer: AppColors.panel,
    surfaceContainerHigh: AppColors.panelHigh,
    surfaceContainerHighest: AppColors.panelHigh,
    outlineVariant: AppColors.outline,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.panel),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    sliderTheme: const SliderThemeData(trackHeight: 4),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
