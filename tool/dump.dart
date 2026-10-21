// Prints what the reader would speak for a PDF, one utterance per line, in the same format as the
// desktop's `npm run dump`, so the two can be compared with a diff:
//   dart run tool/dump.dart paper.pdf       every page
//   dart run tool/dump.dart paper.pdf 3     page 3 only
//   dart run tool/dump.dart paper.pdf 3 --runs   also the text runs: baseline, size, text
// Runs on the PC through pdfrx_engine, the same PDFium code the app uses.
import 'dart:io';

import 'package:pdfreader/document_text.dart';
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
  final text = DocumentText(doc);
  if (runs) {
    for (var n = 1; n <= text.pageCount; n++) {
      if (onlyPage != null && onlyPage != n) continue;
      stdout.writeln('## Runs on page $n');
      for (final i in (await text.page(n)).text.items) {
        final flags = '${i.hasEOL ? 'EOL' : '   '}${i.rotated ? ' ROT' : ''}';
        stdout.writeln(
          'y ${i.y.toStringAsFixed(1).padLeft(6)}  size ${i.height.toStringAsFixed(1).padLeft(5)}  '
          'x ${i.x.toStringAsFixed(0).padLeft(4)}  $flags  ${i.str}',
        );
      }
    }
  }
  stdout.writeln('# $file: ${text.pageCount} pages, document language ${(await text.lang).name}');
  for (var n = 1; n <= text.pageCount; n++) {
    if (onlyPage != null && onlyPage != n) continue;
    stdout.writeln('\n## Page $n');
    for (final u in await text.utterances(n)) {
      stdout.writeln('[${u.role.name.padRight(7)} ${u.lang.name}] ${u.spoken}');
    }
  }
  await doc.dispose();
}
