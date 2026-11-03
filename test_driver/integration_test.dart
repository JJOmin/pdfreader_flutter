// Runs an integration test with `flutter drive`, which can build in profile mode for frame times:
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/perf_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
