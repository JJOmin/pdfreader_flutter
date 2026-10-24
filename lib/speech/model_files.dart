import 'dart:io';
import 'dart:typed_data';

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

/// Where the recogniser that comes with the app is (ADR 7), filled before a build by
/// tool/bundle_recogniser.sh. Only the files the phone reads.
const bundledAssets = 'assets/recogniser';
const bundledFiles = ['model.int8.onnx', 'tokens.txt'];

/// Copies a model that comes with the app out of its assets into [models] and returns its folder:
/// sherpa-onnx reads a model from a file, and an asset is not one. The copy is made once; a marker
/// written last tells a whole copy from one that was cut off. Null when the app was built without it.
Future<String?> unpackBundled(
  Directory models,
  SpeechModel model,
  Future<ByteData> Function(String key) load,
) async {
  final dir = Directory('${models.path}/${model.dir}');
  final done = File('${dir.path}/.unpacked');
  if (done.existsSync()) return dir.path;
  for (final (i, name) in bundledFiles.indexed) {
    final ByteData data;
    try {
      data = await load('$bundledAssets/$name');
    } catch (_) {
      // The first file missing is a build without the model; one missing later is a broken build.
      if (i == 0) return null;
      rethrow;
    }
    dir.createSync(recursive: true);
    final part = File('${dir.path}/$name.part');
    await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    part.renameSync('${dir.path}/$name');
  }
  done.writeAsStringSync('');
  return dir.path;
}
