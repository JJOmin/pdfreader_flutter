import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/home_lists.dart';

void main() {
  test('continue reading lists the documents read last, newest first', () {
    expect(continueReading({'a': 10, 'b': 30, 'c': 20}), ['b', 'c', 'a']);
    expect(continueReading({'a': 10, 'b': 30, 'c': 20}, limit: 2), ['b', 'c']);
    expect(continueReading(const {}), isEmpty);
  });

  test('new on this phone leaves out what was opened, newest download first', () {
    expect(newOnPhone({'a': 1, 'b': 3, 'c': 2}, {'b'}), ['c', 'a']);
    expect(newOnPhone({'a': 1, 'b': 3, 'c': 2}, const {}, limit: 1), ['b']);
  });

  test('a place key names the library document it belongs to', () {
    expect(docIdOfPlace('library:abc'), 'abc');
    expect(docIdOfPlace('content://x/y.pdf'), isNull);
  });
}
