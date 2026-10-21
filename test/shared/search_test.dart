// Port of the desktop's tests/unit/search.test.ts, the findInBlocks part (blockSpans is in
// layout_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/search.dart';
import 'package:pdfreader/shared/types.dart';

RawItem line(String str, double y) =>
    RawItem(str: str, x: 72, y: y, height: 10, font: 'body', hasEOL: true, rotated: false);

void main() {
  // Raw string: "A new language representa-" + "tion model was" + "trained (twice)."
  final items = [
    line('A new language representa-', 700),
    line('tion model was', 688),
    line('trained (twice).', 676),
  ];
  final pageRaw = items.map((i) => i.str).join();
  final blocks = layoutPage(items, 800);
  List<List<String>> matched(String query) => [
    for (final ranges in findInBlocks(blocks, query)) [for (final (a, b) in ranges) pageRaw.substring(a, b)],
  ];

  group('findInBlocks', () {
    test('ignores case and finds every occurrence', () {
      expect(matched('MODEL'), [
        ['model'],
      ]);
      expect(findInBlocks(blocks, 'a'), hasLength(6));
      expect(matched('missing'), isEmpty);
      expect(matched('   '), isEmpty);
    });

    test('matches across a hyphenated line break and a plain one', () {
      expect(matched('representation'), [
        ['representa', 'tion'],
      ]);
      // The raw string has no character at a plain line break, so the two words are one raw range.
      expect(matched('was trained'), [
        ['wastrained'],
      ]);
    });

    test('treats punctuation in the query literally', () {
      expect(matched('(twice).'), [
        ['(twice).'],
      ]);
      expect(matched('.*'), isEmpty);
    });
  });
}
