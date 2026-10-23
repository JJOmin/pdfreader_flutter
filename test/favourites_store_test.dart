import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/favourites_store.dart';
import 'package:pdfreader/shared/favourites.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('favourites-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('starts empty, and keeps a change for the next start', () async {
    final file = File('${dir.path}/favourites.json');
    final store = await FavouritesStore.load(file);
    expect(store.value.liked, isEmpty);
    var told = 0;
    store.addListener(() => told++);
    await store.change(
      (f) => f.toggleLike('a').putFolder(const Folder(id: 'f', name: 'Verträge', color: 1, docs: ['a'])),
    );
    expect(told, 1);
    final again = await FavouritesStore.load(file);
    expect(again.value.isLiked('a'), isTrue);
    expect(again.value.folders.single.name, 'Verträge');
  });
}
