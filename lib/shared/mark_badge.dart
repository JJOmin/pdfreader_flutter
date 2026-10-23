// Where the icon above a commented mark goes on a PDF page (PLAN 12): a small square over the first
// line of the mark, at its left edge. The same for painting and for tapping it.
import 'pdfium_text.dart';

/// The icon's box, in PDF units like the glyph box of the mark's first line it belongs to.
CharBox badgeBox(CharBox line) {
  final size = ((line.top - line.bottom) * 1.1).clamp(7.0, 14.0);
  return (
    left: line.left,
    right: line.left + size,
    bottom: line.top + size * 0.08,
    top: line.top + size * 1.08,
  );
}
