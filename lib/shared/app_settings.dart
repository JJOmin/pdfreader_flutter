// The app's own settings, apart from the reading settings that the desktop shares (PLAN 9.12).

/// Whether the app is light, dark, or follows the system's setting.
enum ThemeChoice { system, light, dark }

/// A missing or unreadable file, or an unknown name, follows the system.
ThemeChoice parseThemeChoice(Object? json) {
  final name = json is Map ? json['theme'] : null;
  return ThemeChoice.values.where((c) => c.name == name).firstOrNull ?? ThemeChoice.system;
}

Map<String, Object?> themeChoiceToJson(ThemeChoice choice) => {'version': 1, 'theme': choice.name};
