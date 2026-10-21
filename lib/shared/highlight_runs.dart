// The reading view paints highlights as styled stretches of a paragraph's text. Where several cover
// the same characters, all of them apply, and the view layers them: the word mark over the
// sentence's tint, a strike-through under both.

/// A highlight's stretch of one paragraph, and which highlight it is (its place in the caller's list).
typedef HighlightSpan = ({int from, int to, int id});

/// A stretch of text and the highlights covering all of it, by id, ascending.
typedef HighlightRun = ({int from, int to, List<int> ids});

/// Splits text of `length` characters into runs of equal look.
List<HighlightRun> highlightRuns(int length, List<HighlightSpan> highlights) {
  final clipped = [
    for (final h in highlights)
      if (h.from.clamp(0, length) case final from when from < h.to.clamp(0, length))
        (from: from, to: h.to.clamp(0, length), id: h.id),
  ];
  final points = <int>{0, length};
  for (final h in clipped) {
    points
      ..add(h.from)
      ..add(h.to);
  }
  final cuts = points.toList()..sort();
  final runs = <HighlightRun>[];
  for (var i = 0; i + 1 < cuts.length; i++) {
    final (from, to) = (cuts[i], cuts[i + 1]);
    final ids = [
      for (final h in clipped)
        if (h.from <= from && to <= h.to) h.id,
    ]..sort();
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && _same(last.ids, ids)) {
      runs.last = (from: last.from, to: to, ids: ids);
    } else {
      runs.add((from: from, to: to, ids: ids));
    }
  }
  return runs;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
