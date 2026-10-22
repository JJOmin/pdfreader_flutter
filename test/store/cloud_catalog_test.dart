import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfreader/store/cloud_catalog.dart';

Manifest doc(String id, String name, {num updated = 1}) =>
    Manifest(docId: id * 64, name: name, pages: 1, sentences: 2, bytes: 10, updated: updated);

void main() {
  late Directory dir;
  late CloudCatalog catalog;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog-');
    catalog = CloudCatalog(File('${dir.path}/sub/cloud-catalog.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps what a full walk found, and forgets what it did not find', () async {
    await catalog.update([doc('a', 'A'), doc('b', 'B')], complete: true);
    expect((await catalog.load()).map((m) => m.name), ['A', 'B']);
    await catalog.update([doc('a', 'A')], complete: true);
    expect((await catalog.load()).map((m) => m.name), ['A']);
  });

  test('adds and replaces what a sync that read the journals learned, and forgets nothing', () async {
    await catalog.update([doc('a', 'A'), doc('b', 'B')], complete: true);
    final merged = await catalog.update([doc('b', 'B', updated: 2), doc('c', 'C')], complete: false);
    expect(merged.map((m) => m.name), ['A', 'B', 'C']);
    expect((await catalog.load()).firstWhere((m) => m.name == 'B').updated, 2);
  });

  test('reads a missing or damaged file as an empty list, and clears', () async {
    expect(await catalog.load(), isEmpty);
    catalog.file.createSync(recursive: true);
    catalog.file.writeAsStringSync('{ not json');
    expect(await catalog.load(), isEmpty);
    await catalog.update([doc('a', 'A')], complete: true);
    await catalog.clear();
    expect(await catalog.load(), isEmpty);
  });
}
