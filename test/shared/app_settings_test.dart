import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/app_settings.dart';

void main() {
  test('reads the saved choice, and follows the system for anything else', () {
    for (final choice in ThemeChoice.values) {
      expect(parseAppearance({'theme': choice.name}).theme, choice);
    }
    for (final bad in [
      null,
      'dark',
      3,
      <String, Object?>{},
      {'theme': 'purple'},
      {'theme': 4},
    ]) {
      expect(parseAppearance(bad).theme, ThemeChoice.system, reason: '$bad');
    }
  });

  test('reads a file from before sepia and fonts: only the theme is in it', () {
    final old = parseAppearance({'version': 1, 'theme': 'dark'});
    expect(old, const Appearance(theme: ThemeChoice.dark));
  });

  test('writes what it reads, every field', () {
    const look = Appearance(
      theme: ThemeChoice.custom,
      font: 'Lexend',
      fontScale: 1.25,
      background: 0xFF0F1B2D,
      text: 0xFFFFD400,
      accent: 0xFFC2185B,
    );
    expect(parseAppearance(look.toJson()), look);
  });

  test('keeps the text size within what the app offers', () {
    expect(parseAppearance({'fontScale': 9}).fontScale, 1.6);
    expect(parseAppearance({'fontScale': 0.1}).fontScale, 0.8);
    expect(parseAppearance({'fontScale': 'big'}).fontScale, 1);
    expect(parseAppearance({'fontScale': double.nan}).fontScale, 1);
  });

  test('ignores a font it does not have and a colour that is not one', () {
    final look = parseAppearance({
      'font': 'Comic Sans MS',
      'custom': {'background': 'red', 'text': -1, 'accent': 0x1FFFFFFFF},
    });
    expect(look.font, 'Verdana');
    expect(look.background, const Appearance().background);
    expect(look.text, const Appearance().text);
    expect(look.accent, const Appearance().accent);
  });

  test('a colour is always opaque', () {
    expect(
      parseAppearance({
        'custom': {'background': 0x00112233},
      }).background,
      0xFF112233,
    );
  });

  test('contrast: black on white is 21, a colour with itself 1', () {
    expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21, 0.01));
    expect(contrastRatio(0xFFF4ECD8, 0xFFF4ECD8), 1);
    expect(contrastRatio(0xFF5B4636, 0xFFF4ECD8), greaterThan(minContrast));
  });

  test('every offered text colour is readable on at least one offered background, and vice versa', () {
    for (final text in customTexts) {
      expect(customBackgrounds.any((b) => contrastRatio(text, b) >= minContrast), isTrue);
    }
    for (final b in customBackgrounds) {
      expect(customTexts.any((t) => contrastRatio(t, b) >= minContrast), isTrue);
    }
  });

  test('a new background keeps the text if it can still be read on it', () {
    const look = Appearance(theme: ThemeChoice.custom, background: 0xFFFFFFFF, text: 0xFF1F1F1F);
    final next = look.withBackground(0xFFF4ECD8);
    expect(next.background, 0xFFF4ECD8);
    expect(next.text, 0xFF1F1F1F);
  });

  test('a new background that the text cannot be read on brings the best offered text with it', () {
    const look = Appearance(theme: ThemeChoice.custom, background: 0xFFFFFFFF, text: 0xFF1F1F1F);
    final next = look.withBackground(0xFF000000);
    expect(next.background, 0xFF000000);
    expect(contrastRatio(next.text, next.background), greaterThanOrEqualTo(minContrast));
    for (final background in customBackgrounds) {
      final chosen = look.withBackground(background);
      expect(
        contrastRatio(chosen.text, chosen.background),
        greaterThanOrEqualTo(minContrast),
        reason: '$background',
      );
    }
  });

  test('every colour on offer has a name for a screen reader', () {
    for (final colour in [...customBackgrounds, ...customTexts, ...customAccents]) {
      expect(colourNames, contains(colour), reason: colour.toRadixString(16));
    }
    expect(colourName(0xFF123456), 'ff123456');
  });
}
