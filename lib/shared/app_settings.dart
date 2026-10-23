// How the whole app looks (PLAN 9.12, M15): the colours, the font and its size. The reading view's
// own font, size and spacing stay in the reading settings that the desktop shares (settings.dart).
import 'dart:math' as math;

import 'fonts.dart';

/// The colours of the whole app. Light and dark are the stock Material look; sepia and custom set the
/// background, the text and the accent. The system's choice picks light or dark.
enum ThemeChoice { system, light, sepia, dark, custom }

/// Allowed range of the app's text size, as a multiple of what the system gives: smallest, largest,
/// step.
const fontScaleLimits = (0.8, 1.6, 0.05);

// Colours as 0xAARRGGBB. The custom theme picks from these, so every pair can be told apart.
const customBackgrounds = [
  0xFFFFFFFF,
  0xFFF4ECD8,
  0xFFE8EEF5,
  0xFFE6F0E6,
  0xFF2B2B2B,
  0xFF1E1E1E,
  0xFF0F1B2D,
  0xFF000000,
];
const customTexts = [
  0xFF1F1F1F,
  0xFF5B4636,
  0xFF1B2A41,
  0xFF1E4620,
  0xFFE2E2E2,
  0xFFF4ECD8,
  0xFFFFFFFF,
  0xFFFFD400,
];
const customAccents = [
  0xFF3F51B5,
  0xFF1F7FE0,
  0xFF00897B,
  0xFF2E9E3A,
  0xFFF57C00,
  0xFFE03131,
  0xFFC2185B,
  0xFF7B1FA2,
];

/// The app's look, as the user chose it.
class Appearance {
  const Appearance({
    this.theme = ThemeChoice.system,
    this.font = 'Verdana',
    this.fontScale = 1,
    this.background = 0xFFFFFFFF,
    this.text = 0xFF1F1F1F,
    this.accent = 0xFF3F51B5,
  });

  final ThemeChoice theme;

  /// A key of [fontChoices].
  final String font;

  /// A multiple of the text size the system gives.
  final double fontScale;

  /// The colours of the custom theme: used only when [theme] is [ThemeChoice.custom].
  final int background;
  final int text;
  final int accent;

  Appearance copyWith({
    ThemeChoice? theme,
    String? font,
    double? fontScale,
    int? background,
    int? text,
    int? accent,
  }) => Appearance(
    theme: theme ?? this.theme,
    font: font ?? this.font,
    fontScale: fontScale ?? this.fontScale,
    background: background ?? this.background,
    text: text ?? this.text,
    accent: accent ?? this.accent,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'theme': theme.name,
    'font': font,
    'fontScale': fontScale,
    'custom': {'background': background, 'text': text, 'accent': accent},
  };

  /// The look with another custom background. If the text could no longer be read on it, the text
  /// becomes the offered colour that reads best, so that no choice leaves the app unreadable.
  Appearance withBackground(int next) {
    if (contrastRatio(text, next) >= minContrast) return copyWith(background: next);
    final best = customTexts.reduce((a, b) => contrastRatio(a, next) >= contrastRatio(b, next) ? a : b);
    return copyWith(background: next, text: best);
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.theme == theme &&
      other.font == font &&
      other.fontScale == fontScale &&
      other.background == background &&
      other.text == text &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(theme, font, fontScale, background, text, accent);
}

/// Builds the look from anything read from disk: a missing or unreadable file, an unknown name or a
/// value that is out of range falls back to the default, field by field.
Appearance parseAppearance(Object? json) {
  const defaults = Appearance();
  final map = json is Map<Object?, Object?> ? json : const <Object?, Object?>{};
  final custom = map['custom'] is Map<Object?, Object?>
      ? map['custom']! as Map<Object?, Object?>
      : const <Object?, Object?>{};
  int colour(String key, int fallback) {
    final value = custom[key];
    return value is int && value >= 0 && value <= 0xFFFFFFFF ? (value | 0xFF000000) : fallback;
  }

  final scale = map['fontScale'];
  final (min, max, _) = fontScaleLimits;
  return Appearance(
    theme: ThemeChoice.values.where((c) => c.name == map['theme']).firstOrNull ?? defaults.theme,
    font: fontChoices.any((f) => f.$1 == map['font']) ? map['font']! as String : defaults.font,
    fontScale: scale is num && scale.isFinite
        ? math.min(max, math.max(min, scale.toDouble()))
        : defaults.fontScale,
    background: colour('background', defaults.background),
    text: colour('text', defaults.text),
    accent: colour('accent', defaults.accent),
  );
}

/// How well two colours can be told apart, 1 (the same) to 21 (black on white), by the WCAG formula
/// on 0xAARRGGBB values. The custom theme refuses text that is too close to its background.
double contrastRatio(int a, int b) {
  double luminance(int argb) {
    double channel(int v) {
      final s = v / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((argb >> 16) & 0xFF) +
        0.7152 * channel((argb >> 8) & 0xFF) +
        0.0722 * channel(argb & 0xFF);
  }

  final (la, lb) = (luminance(a), luminance(b));
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Text on its background has to be at least this clear to be offered.
const minContrast = 3.0;
