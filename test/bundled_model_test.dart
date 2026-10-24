import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/speech/catalog.dart';
import 'package:pdfreader/speech/model_files.dart';

void main() {
  late Directory models;
  final recogniser = catalog.firstWhere((m) => m.id == 'aligner');
  final assets = {
    'assets/recogniser/model.int8.onnx': Uint8List.fromList([1, 2, 3]),
    'assets/recogniser/tokens.txt': Uint8List.fromList('a 0\n'.codeUnits),
  };
  late List<String> loaded;

  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = assets[key];
    // What rootBundle does for an asset the app was built without.
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(bytes);
  }

  setUp(() {
    models = Directory.systemTemp.createTempSync('bundled_model_test');
    loaded = [];
  });
  tearDown(() => models.deleteSync(recursive: true));

  test('copies the model that comes with the app into the models folder', () async {
    final dir = await unpackBundled(models, recogniser, load);
    expect(dir, '${models.path}/${recogniser.dir}');
    expect(File('$dir/model.int8.onnx').readAsBytesSync(), [1, 2, 3]);
    expect(File('$dir/tokens.txt').readAsStringSync(), 'a 0\n');
  });

  test('copies it only once', () async {
    await unpackBundled(models, recogniser, load);
    loaded.clear();
    expect(await unpackBundled(models, recogniser, load), isNotNull);
    expect(loaded, isEmpty);
  });

  test('finds nothing in an app built without the model', () async {
    assets.remove('assets/recogniser/model.int8.onnx');
    addTearDown(() => assets['assets/recogniser/model.int8.onnx'] = Uint8List.fromList([1, 2, 3]));
    expect(await unpackBundled(models, recogniser, load), isNull);
    expect(Directory('${models.path}/${recogniser.dir}').existsSync(), isFalse);
  });

  test('copies again after a copy that was cut off', () async {
    final dir = Directory('${models.path}/${recogniser.dir}')..createSync();
    File('${dir.path}/model.int8.onnx').writeAsBytesSync([1]);
    expect(await unpackBundled(models, recogniser, load), dir.path);
    expect(File('${dir.path}/model.int8.onnx').readAsBytesSync(), [1, 2, 3]);
  });
}
