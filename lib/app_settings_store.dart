// How the app looks (PLAN 9.12, M15), in `app-settings.json` in the app's own storage.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'shared/app_settings.dart';

class AppSettingsStore extends ValueNotifier<Appearance> {
  AppSettingsStore._(this._file, super.value);

  /// Kept nowhere: for widget tests.
  AppSettingsStore.inMemory([Appearance look = const Appearance()]) : this._(null, look);

  final File? _file;

  static Future<AppSettingsStore> load(File file) async {
    try {
      return AppSettingsStore._(file, parseAppearance(jsonDecode(await file.readAsString())));
    } on FileSystemException {
      return AppSettingsStore._(file, const Appearance());
    } on FormatException {
      return AppSettingsStore._(file, const Appearance());
    }
  }

  /// Shows the new look at once and writes it.
  Future<void> change(Appearance look) async {
    value = look;
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(jsonEncode(look.toJson()), flush: true);
    await partial.rename(file.path);
  }
}
