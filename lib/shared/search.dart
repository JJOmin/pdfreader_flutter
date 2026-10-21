// Port of the desktop's src/shared/search.ts.
import 'layout.dart';
import 'types.dart';

final _space = RegExp(r'\s+', unicode: true);

/// Finds a phrase in a page's readable text, ignoring case. Searching the readable text rather
/// than the raw string lets a phrase match across a line break or a hyphenated word. Each match
/// is returned as the raw ranges it covers on the page.
List<List<RawRange>> findInBlocks(List<Block> blocks, String query) {
  final words = query.trim().split(_space).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final pattern = RegExp(words.map(RegExp.escape).join(r'\s+'), caseSensitive: false, unicode: true);
  return [
    for (final block in blocks)
      for (final match in pattern.allMatches(block.text))
        if (rawRanges(block.raw, match.start, match.end) case final ranges when ranges.isNotEmpty) ranges,
  ];
}
