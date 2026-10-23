// The page words and their hash, computed from PDFium's text on the PC, must equal those the
// desktop computed from PDF.js (desktop step S2 writes the golden files). On a page where they
// agree the phone reads the desktop's sentences, so this is what the whole design rests on.
// The PDFs live in the desktop repository; the test is skipped where it is not checked out.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_text.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'desktop_repo.dart';

final files = {
  'sample': sampleFixture,
  'centric': '$desktopRepo/docs/sample_pdfs/centric_2026_1_10_30003.pdf',
};

void main() {
  setUpAll(pdfrxInitialize);

  for (final MapEntry(key: name, value: path) in files.entries) {
    test('page words of $name equal the desktop golden file', () async {
      final golden =
          jsonDecode(File('test/golden/page-words-$name.json').readAsStringSync()) as Map<String, Object?>;
      final document = await PdfDocument.openFile(path);
      final text = DocumentText(document);
      final pages = golden['pages']! as List<Object?>;
      expect(text.pageCount, pages.length);
      for (final entry in pages.cast<Map<String, Object?>>()) {
        final words = pageWords(await text.utterances(entry['page']! as int));
        expect(words, entry['words'], reason: 'page ${entry['page']}');
        expect(wordsHash(words), entry['wordsHash'], reason: 'page ${entry['page']}');
      }
      await document.dispose();
    }, skip: skipWithout(path));
  }
}
