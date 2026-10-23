// The theme choice (PLAN 9.12), in `app-settings.json` in the app's own storage.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'shared/app_settings.dart';

class AppSettingsStore extends ValueNotifier<ThemeChoice> {
  AppSettingsStore._(this._file, super.value);

  /// Kept nowhere: for widget tests.
  AppSettingsStore.inMemory() : this._(null, ThemeChoice.system);

  final File? _file;

  static Future<AppSettingsStore> load(File file) async {
    try {
      return AppSettingsStore._(file, parseThemeChoice(jsonDecode(await file.readAsString())));
    } on FileSystemException {
      return AppSettingsStore._(file, ThemeChoice.system);
    } on FormatException {
      return AppSettingsStore._(file, ThemeChoice.system);
    }
  }

  Future<void> choose(ThemeChoice choice) async {
    value = choice;
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(jsonEncode(themeChoiceToJson(choice)), flush: true);
    await partial.rename(file.path);
  }
}
