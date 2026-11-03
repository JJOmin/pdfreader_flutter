// PDFs made in the tests, so they need nothing pushed to the phone: English prose in a 10 point font,
// seven paragraphs of five lines a page, about 3,000 characters.
import 'dart:convert';
import 'dart:typed_data';

const _sentences = [
  'The study measures how readers move through long scientific texts on a small screen.',
  'Each participant read the same chapter twice, once on paper and once on the phone.',
  'We recorded where they paused, which passages they marked, and what they wrote beside them.',
  'Most readers returned to a passage they had marked at least once before the end.',
  'Comments were short, often a single word, and almost always written in the margin.',
  'The results suggest that marking and commenting help readers keep their place.',
];

/// `pages` pages; with `runOn`, every fifth page ends in the middle of a sentence that the next
/// page finishes.
Uint8List longPdf(int pages, {bool runOn = false}) {
  String page(int n) {
    final out = StringBuffer('BT /F1 10 Tf 60 730 Td ');
    for (var p = 0; p < 7; p++) {
      for (var line = 0; line < 5; line++) {
        final runsOver = runOn && n % 5 == 0 && n < pages && p == 6 && line == 4;
        final finishes = runOn && n % 5 == 1 && n > 1 && p == 0 && line == 0;
        final text = runsOver
            ? 'and this sentence runs over the page'
            : finishes
            ? 'break, where the next page finishes it.'
            : _sentences[(n + p + line) % _sentences.length];
        out.write('($text) Tj 0 ${line == 4 ? -24 : -12} Td ');
      }
    }
    out.write('ET');
    return out.toString();
  }

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[for (var n = 0; n < pages; n++) '${4 + 2 * n} 0 R'].join(' ')}] /Count $pages >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    for (var n = 1; n <= pages; n++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${5 + 2 * (n - 1)} 0 R '
          '/Resources << /Font << /F1 3 0 R >> >> >>',
      '<< /Length ${page(n).length} >>\nstream\n${page(n)}\nendstream',
    ],
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(utf8.encode(out.toString()));
}
