// What "Save PDF" writes for a mark (PLAN 4.3, 4.4), the same as the desktop's src/main/annotate.ts:
// the quad points of each line it covers, and the desktop's colours. Pure, so it is tested without
// PDFium; lib/annotated_pdf.dart writes it into the PDF.
import 'notes.dart';
import 'pdfium_text.dart' show CharBox;

/// Fill colours for highlights, and stronger tones of the same hues for lines, as on the desktop.
const markFill = {
  HighlightColor.yellow: (1.0, 0.87, 0.2),
  HighlightColor.green: (0.55, 0.88, 0.57),
  HighlightColor.blue: (0.55, 0.78, 1.0),
  HighlightColor.red: (1.0, 0.6, 0.6),
};
const markLine = {
  HighlightColor.yellow: (0.83, 0.66, 0.0),
  HighlightColor.green: (0.18, 0.62, 0.23),
  HighlightColor.blue: (0.12, 0.5, 0.88),
  HighlightColor.red: (0.88, 0.19, 0.19),
};

/// The colour of a mark of this kind, as 0 to 255 for PDFium.
(int, int, int) markColor(MarkKind kind, HighlightColor color) {
  final (r, g, b) = (kind == MarkKind.highlight ? markFill : markLine)[color]!;
  int byte(double v) => (v * 255).round();
  return (byte(r), byte(g), byte(b));
}

/// One line of a mark in the PDF's order of quad points: top left, top right, bottom left, bottom
/// right, in page coordinates with the origin at the bottom left.
typedef Quad = (double, double, double, double, double, double, double, double);

Quad quadOf(CharBox b) => (b.left, b.top, b.right, b.top, b.left, b.bottom, b.right, b.bottom);

/// The rectangle around all the lines of a mark: the annotation's /Rect.
CharBox boundsOf(List<CharBox> boxes) => (
  left: boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b),
  bottom: boxes.map((b) => b.bottom).reduce((a, b) => a < b ? a : b),
  right: boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b),
  top: boxes.map((b) => b.top).reduce((a, b) => a > b ? a : b),
);

/// A mark ready to be written: its page, kind, colour, comment, and the boxes of its lines.
class ExportMark {
  const ExportMark({
    required this.page,
    required this.kind,
    required this.color,
    required this.comment,
    required this.boxes,
  });

  final int page;
  final MarkKind kind;
  final HighlightColor color;
  final String comment;
  final List<CharBox> boxes;
}
