// The Material themes for the look the user chose (PLAN M15): one `ThemeData` for light and one for
// dark, and which of them the app uses.
import 'package:flutter/material.dart';

import 'shared/app_settings.dart';
import 'shared/fonts.dart';

const _sepia = (background: 0xFFF4ECD8, text: 0xFF5B4636, accent: 0xFF8B5E3C);

/// The themes and the mode to run them in.
typedef AppThemes = ({ThemeData light, ThemeData dark, ThemeMode mode});

AppThemes appThemes(Appearance look) {
  final family = fontFamilyOf(look.font);
  ThemeData stock(Brightness b) =>
      ThemeData(colorSchemeSeed: Colors.indigo, brightness: b, fontFamily: family);
  ThemeData painted(({int background, int text, int accent}) c) =>
      _painted(Color(c.background), Color(c.text), Color(c.accent), family);
  switch (look.theme) {
    case ThemeChoice.system:
      return (light: stock(Brightness.light), dark: stock(Brightness.dark), mode: ThemeMode.system);
    case ThemeChoice.light:
      return (light: stock(Brightness.light), dark: stock(Brightness.light), mode: ThemeMode.light);
    case ThemeChoice.dark:
      return (light: stock(Brightness.dark), dark: stock(Brightness.dark), mode: ThemeMode.dark);
    case ThemeChoice.sepia:
      final theme = painted(_sepia);
      return (light: theme, dark: theme, mode: ThemeMode.light);
    case ThemeChoice.custom:
      final theme = painted((background: look.background, text: look.text, accent: look.accent));
      return (light: theme, dark: theme, mode: ThemeMode.light);
  }
}

/// A theme from a background, a text colour and an accent: the surfaces step from the background
/// towards the text, as the reader's bars always did, so cards and bars show against the page.
ThemeData _painted(Color background, Color text, Color accent, String? family) {
  Color step(double t) => Color.lerp(background, text, t)!;
  // Secondary text is the text colour faded towards the background, as far as it can go and still be
  // read (4.5 to 1, WCAG AA) on the darkest surface a card or a bar has.
  final darkest = step(0.14);
  var fade = 0.25;
  while (fade > 0 && _contrast(Color.lerp(text, background, fade)!, darkest) < 4.5) {
    fade -= 0.05;
  }
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: ThemeData.estimateBrightnessForColor(background),
      ).copyWith(
        surface: background,
        onSurface: text,
        onSurfaceVariant: Color.lerp(text, background, fade < 0 ? 0 : fade),
        surfaceContainerLowest: background,
        surfaceContainerLow: step(0.03),
        surfaceContainer: step(0.06),
        surfaceContainerHigh: step(0.10),
        surfaceContainerHighest: step(0.14),
        outline: Color.lerp(text, background, 0.5),
        outlineVariant: Color.lerp(text, background, 0.75),
        inverseSurface: text,
        onInverseSurface: background,
      );
  return ThemeData(colorScheme: scheme, fontFamily: family);
}

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// The text size the system gives, times the user's choice, so that the system's own setting still
/// counts.
Widget scaleText(BuildContext context, Appearance look, Widget? child) {
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(textScaler: TextScaler.linear(media.textScaler.scale(1) * look.fontScale)),
    child: child!,
  );
}
