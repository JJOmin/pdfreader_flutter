// Prints what the reader would speak for a PDF, one utterance per line, in the same format as the
// desktop's `npm run dump`, so the two can be compared with a diff:
//   dart run tool/dump.dart paper.pdf       every page
//   dart run tool/dump.dart paper.pdf 3     page 3 only
//   dart run tool/dump.dart paper.pdf 3 --runs   also the text runs: baseline, size, text
// Runs on the PC through pdfrx_engine, the same PDFium code the app uses.
import 'dart:io';

import 'package:pdfreader/shared/language.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/pdfium_text.dart';
import 'package:pdfreader/shared/utterances.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> arguments) async {
  final runs = arguments.contains('--runs');
  final args = arguments.where((a) => a != '--runs').toList();
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/dump.dart <file.pdf> [page] [--runs]');
    exit(1);
  }
  final file = args[0];
  final onlyPage = args.length > 1 ? int.parse(args[1]) : null;
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(file);
  final pages = <List<Block>>[];
  for (final page in doc.pages) {
    final text = await page.loadText();
    final pageText = pageTextFromPdfium(text?.fullText ?? '', [
      for (final r in text?.charRects ?? const <PdfRect>[])
        (left: r.left, bottom: r.bottom, right: r.right, top: r.top),
    ]);
    if (runs && (onlyPage == null || onlyPage == page.pageNumber)) {
      stdout.writeln('## Runs on page ${page.pageNumber}');
      for (final i in pageText.items) {
        final flags = '${i.hasEOL ? 'EOL' : '   '}${i.rotated ? ' ROT' : ''}';
        stdout.writeln(
          'y ${i.y.toStringAsFixed(1).padLeft(6)}  size ${i.height.toStringAsFixed(1).padLeft(5)}  '
          'x ${i.x.toStringAsFixed(0).padLeft(4)}  $flags  ${i.str}',
        );
      }
    }
    pages.add(layoutPage(pageText.items, page.height));
  }
  final lang = guessLang(pages.take(5).expand((p) => p).map((b) => b.text).join(' ')).lang;
  stdout.writeln('# $file: ${doc.pages.length} pages, document language ${lang.name}');
  for (var i = 0; i < pages.length; i++) {
    if (onlyPage != null && onlyPage != i + 1) continue;
    stdout.writeln('\n## Page ${i + 1}');
    for (final u in buildUtterances(pages[i], i + 1, lang)) {
      stdout.writeln('[${u.role.name.padRight(7)} ${u.lang.name}] ${u.spoken}');
    }
  }
  await doc.dispose();
}
