// "Save PDF" (PLAN 4.4): marks written into a copy of the desktop's sample PDF through PDFium, then
// read back with PDFium. The PDF lives in the desktop repository; skipped where it is not checked out.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfreader/annotated_pdf.dart';
import 'package:pdfreader/shared/mark_export.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'desktop_repo.dart';

final sample = '$desktopRepo/tests/fixtures/sample.pdf';

/// Each page's annotations, by PDFium subtype.
Future<List<List<int>>> annotationsOf(List<int> bytes) async {
  final document = await PdfDocument.openData(Uint8List.fromList(bytes));
  try {
    return await document.useNativeDocumentHandle((handle) {
      final lib = pdfium.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final doc = pdfium.FPDF_DOCUMENT.fromAddress(handle);
      return [
        for (var i = 0; i < lib.FPDF_GetPageCount(doc); i++)
          () {
            final page = lib.FPDF_LoadPage(doc, i);
            final count = lib.FPDFPage_GetAnnotCount(page);
            final subtypes = <int>[];
            for (var a = 0; a < count; a++) {
              final annot = lib.FPDFPage_GetAnnot(page, a);
              subtypes.add(lib.FPDFAnnot_GetSubtype(annot));
              lib.FPDFPage_CloseAnnot(annot);
            }
            lib.FPDF_ClosePage(page);
            return subtypes;
          }(),
      ];
    });
  } finally {
    await document.dispose();
  }
}

void main() {
  setUpAll(pdfrxInitialize);

  test('writes each mark as its kind of annotation, and the notes as a sticky note on page one', () async {
    final original = File(sample).readAsBytesSync();
    const box = (left: 72.0, bottom: 700.0, right: 300.0, top: 712.0);
    final saved = await annotatedPdf(original, [
      const ExportMark(
        page: 1,
        kind: MarkKind.highlight,
        color: HighlightColor.yellow,
        comment: 'wichtig ä',
        boxes: [box],
      ),
      const ExportMark(
        page: 2,
        kind: MarkKind.underline,
        color: HighlightColor.red,
        comment: '',
        boxes: [box],
      ),
      const ExportMark(
        page: 2,
        kind: MarkKind.strike,
        color: HighlightColor.blue,
        comment: '',
        boxes: [box, box],
      ),
    ], 'General notes');
    // For a look with another reader: ANNOTATED_OUT=/path/out.pdf.
    if (Platform.environment['ANNOTATED_OUT'] case final out?) File(out).writeAsBytesSync(saved);
    expect(await annotationsOf(saved), [
      [pdfium.FPDF_ANNOT_HIGHLIGHT, pdfium.FPDF_ANNOT_TEXT],
      [pdfium.FPDF_ANNOT_UNDERLINE, pdfium.FPDF_ANNOT_STRIKEOUT],
    ]);
    // A copy: the original is left as it was.
    expect(await annotationsOf(original), [<int>[], <int>[]]);
  }, skip: File(sample).existsSync() ? false : 'needs $sample');

  test('leaves out the sticky note when there are no general notes', () async {
    final saved = await annotatedPdf(File(sample).readAsBytesSync(), const [], '  ');
    expect(await annotationsOf(saved), [<int>[], <int>[]]);
  }, skip: File(sample).existsSync() ? false : 'needs $sample');
}
