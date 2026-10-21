// Marks on the phone: selections become raw ranges, raw ranges become marks, and marks written on
// either device are placed on this device's raw string. Raw ranges stay the one coordinate system.
import 'layout.dart';
import 'notes.dart';
import 'pdfium_text.dart';
import 'types.dart';

/// The raw range a selection covers, found by its glyph boxes. pdfrx selects in its own reading-order
/// text, whose characters are numbered differently from PDFium's char stream that the raw string
/// is made from (ADR 1); the glyphs and their boxes are the same in both. `rawBoxes` has the box of
/// every PDFium char, and `charIndex` the char each raw offset came from.
RawRange? rawRangeFromBoxes(List<CharBox> selected, List<CharBox> rawBoxes, List<int> charIndex) {
  // pdfrx sizes a box to its line, PDFium's is tight around the ink, so only the left and right
  // edges agree. Candidates share them; the one on the same line, by its middle, is the glyph.
  String key(CharBox b) => '${b.left.toStringAsFixed(2)},${b.right.toStringAsFixed(2)}';
  bool empty(CharBox b) => b.right <= b.left || b.top <= b.bottom;
  final byEdges = <String, List<int>>{};
  for (var i = 0; i < rawBoxes.length; i++) {
    if (!empty(rawBoxes[i])) byEdges.putIfAbsent(key(rawBoxes[i]), () => []).add(i);
  }
  int? first;
  int? last;
  for (final box in selected) {
    if (empty(box)) continue;
    final middle = (box.top + box.bottom) / 2;
    int? best;
    var distance = double.infinity;
    for (final i in byEdges[key(box)] ?? const <int>[]) {
      final r = rawBoxes[i];
      // On the line: the glyph's middle lies within the line's box.
      final glyph = (r.top + r.bottom) / 2;
      if (glyph < box.bottom || glyph > box.top) continue;
      final d = (glyph - middle).abs();
      if (d < distance) {
        best = i;
        distance = d;
      }
    }
    if (best == null) continue;
    first = first == null || best < first ? best : first;
    last = last == null || best > last ? best : last;
  }
  if (first == null || last == null) return null;
  final from = charIndex.indexWhere((c) => c >= first!);
  final to = charIndex.lastIndexWhere((c) => c <= last!) + 1;
  return from < 0 || to <= from ? null : (from, to);
}

final _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A new mark over raw `[start, end)` of a page, or null when that holds nothing to mark.
Annotation? newMark({
  required int page,
  required int start,
  required int end,
  required String raw,
  required List<Block> blocks,
  required MarkKind kind,
  required HighlightColor color,
  required String id,
  required String created,
}) {
  if (start < 0 || end > raw.length || start >= end) return null;
  final text = raw.substring(start, end);
  if (!_letterOrNumber.hasMatch(text)) return null;
  return Annotation(
    id: id,
    page: page,
    start: start,
    end: end,
    text: text,
    quote: readableText(blocks, start, end),
    kind: kind,
    color: color,
    comment: '',
    created: created,
  );
}

/// Each mark placed on this device's raw string, by id. A mark whose text is gone from its page
/// is left out. `pageRaw` holds the raw string of every page that has been read.
Map<String, Annotation> anchorMarks(List<Annotation> marks, Map<int, String> pageRaw) {
  final anchored = <String, Annotation>{};
  for (final mark in marks) {
    final raw = pageRaw[mark.page];
    if (raw == null) continue;
    final placed = reanchor(mark, raw);
    if (placed != null) anchored[mark.id] = placed;
  }
  return anchored;
}

/// The mark covering a raw offset of a page, the shortest where several do.
Annotation? markAt(Iterable<Annotation> marks, int page, int offset) {
  Annotation? best;
  for (final mark in marks) {
    if (mark.page != page || offset < mark.start || offset >= mark.end) continue;
    if (best == null || mark.end - mark.start < best.end - best.start) best = mark;
  }
  return best;
}
