// The themes the app builds for the look the user chose.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/app_theme.dart';
import 'package:pdfreader/shared/app_settings.dart';

void main() {
  test('the system choice gives a light and a dark theme and lets the system pick', () {
    final themes = appThemes(const Appearance());
    expect(themes.mode, ThemeMode.system);
    expect(themes.light.brightness, Brightness.light);
    expect(themes.dark.brightness, Brightness.dark);
  });

  test('light and dark are fixed, whatever the system says', () {
    final light = appThemes(const Appearance(theme: ThemeChoice.light));
    expect(light.mode, ThemeMode.light);
    expect(light.light.brightness, Brightness.light);
    final dark = appThemes(const Appearance(theme: ThemeChoice.dark));
    expect(dark.mode, ThemeMode.dark);
    expect(dark.light.brightness, Brightness.dark);
    expect(dark.dark.brightness, Brightness.dark);
  });

  test('sepia paints the whole app on the sepia page, with its brown text', () {
    final theme = appThemes(const Appearance(theme: ThemeChoice.sepia)).light;
    expect(theme.colorScheme.surface, const Color(0xFFF4ECD8));
    expect(theme.colorScheme.onSurface, const Color(0xFF5B4636));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4ECD8));
    expect(theme.brightness, Brightness.light);
  });

  test('custom colours are the ones chosen, and the brightness follows the background', () {
    const look = Appearance(
      theme: ThemeChoice.custom,
      background: 0xFF0F1B2D,
      text: 0xFFFFD400,
      accent: 0xFFC2185B,
    );
    final theme = appThemes(look).light;
    expect(theme.colorScheme.surface, const Color(0xFF0F1B2D));
    expect(theme.colorScheme.onSurface, const Color(0xFFFFD400));
    expect(theme.brightness, Brightness.dark, reason: 'a dark background gets the dark widget defaults');
    expect(theme.colorScheme.surfaceContainerHigh, isNot(const Color(0xFF0F1B2D)));
  });

  test('the surfaces step from the background towards the text, lightest step first', () {
    final s = appThemes(const Appearance(theme: ThemeChoice.sepia)).light.colorScheme;
    final steps = [
      s.surfaceContainerLowest,
      s.surfaceContainerLow,
      s.surfaceContainer,
      s.surfaceContainerHigh,
      s.surfaceContainerHighest,
    ];
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i].computeLuminance(), lessThan(steps[i - 1].computeLuminance()));
    }
  });

  test('the chosen font is set on every theme', () {
    for (final choice in ThemeChoice.values) {
      final themes = appThemes(Appearance(theme: choice, font: 'Lexend'));
      expect(themes.light.textTheme.bodyMedium?.fontFamily, 'Lexend', reason: choice.name);
      expect(themes.dark.textTheme.bodyMedium?.fontFamily, 'Lexend', reason: choice.name);
    }
    expect(appThemes(const Appearance(font: 'Georgia')).light.textTheme.bodyMedium?.fontFamily, 'serif');
    expect(
      appThemes(const Appearance()).light.textTheme.bodyMedium?.fontFamily,
      isNot(anyOf('Lexend', 'serif')),
    );
  });

  testWidgets('the text size multiplies the system size', (tester) async {
    double? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: Builder(
          builder: (context) => scaleText(
            context,
            const Appearance(fontScale: 1.5),
            Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context).scale(10);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(seen, closeTo(18, 0.001));
  });

  double ratio(Color a, Color b) {
    final (la, lb) = (a.computeLuminance(), b.computeLuminance());
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  test('every colour pair the custom theme offers is readable, on every surface the app draws', () {
    for (final background in customBackgrounds) {
      for (final text in customTexts) {
        if (contrastRatio(text, background) < minContrast) continue;
        final scheme = appThemes(Appearance(theme: ThemeChoice.custom, background: background, text: text))
            .light
            .colorScheme;
        for (final surface in [
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ]) {
          for (final ink in [scheme.onSurface, scheme.onSurfaceVariant]) {
            expect(
              ratio(ink, surface),
              greaterThanOrEqualTo(4.5),
              reason: '${background.toRadixString(16)} / ${text.toRadixString(16)}',
            );
          }
        }
      }
    }
  });

  test('sepia is readable in the same way', () {
    final scheme = appThemes(const Appearance(theme: ThemeChoice.sepia)).light.colorScheme;
    for (final surface in [scheme.surface, scheme.surfaceContainerHighest]) {
      expect(ratio(scheme.onSurface, surface), greaterThanOrEqualTo(4.5));
      expect(ratio(scheme.onSurfaceVariant, surface), greaterThanOrEqualTo(4.5));
    }
  });
}
