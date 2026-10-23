import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/app_settings.dart';

void main() {
  test('reads the saved choice, and follows the system for anything else', () {
    expect(parseThemeChoice({'theme': 'dark'}), ThemeChoice.dark);
    expect(parseThemeChoice({'theme': 'light'}), ThemeChoice.light);
    expect(parseThemeChoice({'theme': 'system'}), ThemeChoice.system);
    for (final bad in [
      null,
      'dark',
      3,
      <String, Object?>{},
      {'theme': 'sepia'},
      {'theme': 4},
    ]) {
      expect(parseThemeChoice(bad), ThemeChoice.system, reason: '$bad');
    }
  });

  test('writes what it reads', () {
    for (final choice in ThemeChoice.values) {
      expect(parseThemeChoice(themeChoiceToJson(choice)), choice);
    }
  });
}
