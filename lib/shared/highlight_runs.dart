// The reading view paints highlights as styled stretches of a paragraph's text. Where several
// cover the same characters, the one on the higher layer shows, as the word mark over the
// sentence's tint on the desktop.

typedef HighlightRun = ({int from, int to, int? layer});

/// Splits text of `length` characters into runs, each with the highest layer covering it, or null.
List<HighlightRun> highlightRuns(int length, List<HighlightRun> highlights) {
  final cuts = <int>{0, length};
  final clipped = [
    for (final h in highlights)
      if (h.from.clamp(0, length) case final from when from < h.to.clamp(0, length))
        (from: from, to: h.to.clamp(0, length), layer: h.layer),
  ];
  for (final h in clipped) {
    cuts
      ..add(h.from)
      ..add(h.to);
  }
  final points = cuts.toList()..sort();
  final runs = <HighlightRun>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final (from, to) = (points[i], points[i + 1]);
    int? layer;
    for (final h in clipped) {
      if (h.from <= from && to <= h.to && (layer == null || (h.layer ?? -1) > layer)) layer = h.layer;
    }
    // Neighbours with the same look are one run.
    if (runs.isNotEmpty && runs.last.layer == layer) {
      runs.last = (from: runs.last.from, to: to, layer: layer);
    } else {
      runs.add((from: from, to: to, layer: layer));
    }
  }
  return runs;
}
