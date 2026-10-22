import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/store/offer_file.dart';

void main() {
  test('remembers the answered offers and the computers always accepted from, across runs', () async {
    final dir = Directory.systemTemp.createTempSync('offers-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/offers.json');
    final offers = OfferFile(file)
      ..handled.add('x@1')
      ..alwaysFrom.add('Mac');
    await offers.save();
    final again = OfferFile(file);
    await again.load();
    expect(again.handled, {'x@1'});
    expect(again.alwaysFrom, {'Mac'});
    file.writeAsStringSync('{ not json');
    final damaged = OfferFile(file);
    await damaged.load();
    expect(damaged.handled, isEmpty);
  });
}
