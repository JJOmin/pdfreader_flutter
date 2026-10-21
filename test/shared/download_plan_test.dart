import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/download_plan.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfreader/shared/types.dart';

Manifest manifest({num updated = 1000, String docId = 'a'}) =>
    Manifest(docId: docId * 64, name: 'x.pdf', pages: 2, sentences: 3, bytes: 10, updated: updated);

LibrarySentence sentence(String key) =>
    LibrarySentence(key: key * 40, lang: Lang.en, ms: 100, from: 0, words: const [(0, 100)]);

PageIndex index(List<String> keys) =>
    PageIndex(wordCount: 0, wordsHash: 'f' * 64, sentences: keys.map(sentence).toList());

void main() {
  group('isCurrent', () {
    test('is true only for the same document with the same update time', () {
      expect(isCurrent(manifest(), manifest()), isTrue);
      expect(isCurrent(manifest(), null), isFalse);
      expect(isCurrent(manifest(updated: 2000), manifest()), isFalse);
      expect(isCurrent(manifest(), manifest(docId: 'b')), isFalse);
    });
  });

  group('audioToFetch and audioToRemove', () {
    final pages = [
      index(['a', 'b']),
      index(['b', 'c']),
    ];

    test('fetches each sentence the phone lacks, once, in page order', () {
      expect(audioToFetch(pages, {'b' * 40}), ['a' * 40, 'c' * 40]);
      expect(audioToFetch(pages, {'a' * 40, 'b' * 40, 'c' * 40}), isEmpty);
    });

    test('removes audio no page refers to any more, as after preparing with other voices', () {
      expect(audioToRemove(pages, {'a' * 40, 'd' * 40}), ['d' * 40]);
    });
  });
}
