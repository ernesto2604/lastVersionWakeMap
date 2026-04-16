import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Centralized typography tokens for WakeMap.
///
/// SF Pro families are defined here so the whole app can switch in one place
/// once the corresponding font assets are declared in pubspec.yaml.
class AppTypography {
  const AppTypography._();

  static const String sfProTextFamily = 'SF Pro Text';
  static const String sfProDisplayFamily = 'SF Pro Display';

  /// Set to true only after SF Pro assets are present and declared in pubspec.
  static const bool useBundledSfPro = true;

  static String? get textFamily => useBundledSfPro ? sfProTextFamily : null;
  static String? get displayFamily => useBundledSfPro ? sfProDisplayFamily : null;

  static TextTheme textTheme(ColorScheme colorScheme) {
    return TextTheme(
      displayLarge: _style(
        family: displayFamily,
        size: 40,
        weight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.8,
      ),
      displayMedium: _style(
        family: displayFamily,
        size: 34,
        weight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.6,
      ),
      headlineLarge: _style(
        family: displayFamily,
        size: 30,
        weight: FontWeight.w600,
        height: 1.16,
        letterSpacing: -0.45,
      ),
      headlineMedium: _style(
        family: displayFamily,
        size: 26,
        weight: FontWeight.w600,
        height: 1.18,
        letterSpacing: -0.35,
      ),
      titleLarge: _style(
        family: textFamily,
        size: 22,
        weight: FontWeight.w600,
        height: 1.24,
        letterSpacing: -0.2,
      ),
      titleMedium: _style(
        family: textFamily,
        size: 18,
        weight: FontWeight.w600,
        height: 1.28,
        letterSpacing: -0.1,
      ),
      bodyLarge: _style(
        family: textFamily,
        size: 17,
        weight: FontWeight.w400,
        height: 1.35,
      ),
      bodyMedium: _style(
        family: textFamily,
        size: 15,
        weight: FontWeight.w400,
        height: 1.36,
      ),
      bodySmall: _style(
        family: textFamily,
        size: 13,
        weight: FontWeight.w400,
        height: 1.34,
      ),
      labelLarge: _style(
        family: textFamily,
        size: 15,
        weight: FontWeight.w600,
        height: 1.2,
      ),
      labelMedium: _style(
        family: textFamily,
        size: 13,
        weight: FontWeight.w500,
        height: 1.2,
      ),
      labelSmall: _style(
        family: textFamily,
        size: 11,
        weight: FontWeight.w500,
        height: 1.2,
      ),
    ).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
  }

  static CupertinoTextThemeData cupertinoTextTheme({
    required Color primaryColor,
    required Color onSurface,
  }) {
    return CupertinoTextThemeData(
      textStyle: _style(
        family: textFamily,
        size: 15,
        weight: FontWeight.w400,
        height: 1.35,
        color: onSurface,
      ),
      actionTextStyle: _style(
        family: textFamily,
        size: 15,
        weight: FontWeight.w600,
        height: 1.2,
        color: primaryColor,
      ),
      navTitleTextStyle: _style(
        family: textFamily,
        size: 17,
        weight: FontWeight.w600,
        height: 1.2,
        color: onSurface,
      ),
      navLargeTitleTextStyle: _style(
        family: displayFamily,
        size: 34,
        weight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.6,
        color: onSurface,
      ),
      navActionTextStyle: _style(
        family: textFamily,
        size: 17,
        weight: FontWeight.w500,
        height: 1.2,
        color: primaryColor,
      ),
      tabLabelTextStyle: _style(
        family: textFamily,
        size: 11,
        weight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }

  static TextStyle _style({
    required String? family,
    required double size,
    required FontWeight weight,
    required double height,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}
