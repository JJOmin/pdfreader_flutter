import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'catalog.dart';

/// Where the speech models live (ADR 1, section 2): the app's own folder, which adb and, on iOS,
/// the Files app can write to. Null when the platform has no such folder.
Future<Directory?> modelsFolder() async {
  final base = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getApplicationDocumentsDirectory();
  return base == null ? null : Directory('${base.path}/models');
}

/// The model's folder if it is installed.
String? installedDir(Directory models, SpeechModel model) {
  final dir = Directory('${models.path}/${model.dir}');
  return dir.existsSync() ? dir.path : null;
}
