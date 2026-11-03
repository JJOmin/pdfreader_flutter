// Runs integration_test/screens_test.dart and keeps its screenshots in build/screens/:
//   flutter drive --driver=test_driver/screens.dart --target=integration_test/screens_test.dart
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/screens/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
