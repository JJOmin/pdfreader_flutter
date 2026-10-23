// "Save PDF" on the phone (PLAN 4.3, 4.4): the marks written into a copy of the PDF as standard
// annotations, which any PDF reader shows, and the general notes as a sticky note on page one, as the
// desktop's src/main/annotate.ts does. PDFium writes them: pdfrx already ships it, and lends it out
// while its own worker waits (`useNativeDocumentHandle`), since PDFium must not be used from two
// threads at once. PDF readers draw these annotations themselves when they carry no appearance.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'shared/mark_export.dart';
import 'shared/notes.dart';

const _subtype = {
  MarkKind.highlight: pdfium.FPDF_ANNOT_HIGHLIGHT,
  MarkKind.underline: pdfium.FPDF_ANNOT_UNDERLINE,
  MarkKind.strike: pdfium.FPDF_ANNOT_STRIKEOUT,
};

/// A copy of `data` with the marks and the notes in it. The original is never changed.
Future<Uint8List> annotatedPdf(Uint8List data, List<ExportMark> marks, String notes) async {
  final document = await PdfDocument.openData(data);
  try {
    await document.useNativeDocumentHandle((handle) {
      final lib = pdfium.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
      final doc = pdfium.FPDF_DOCUMENT.fromAddress(handle);
      using((arena) {
        Pointer<pdfium.FPDF_WCHAR> wide(String text) {
          final out = arena<Uint16>(text.length + 1);
          for (var i = 0; i < text.length; i++) {
            out[i] = text.codeUnitAt(i);
          }
          out[text.length] = 0;
          return out.cast();
        }

        final contents = 'Contents'.toNativeUtf8(allocator: arena).cast<Char>();
        void annotate(int pageNumber, void Function(pdfium.FPDF_PAGE page) write) {
          final page = lib.FPDF_LoadPage(doc, pageNumber - 1);
          if (page == nullptr) return;
          try {
            write(page);
          } finally {
            lib.FPDF_ClosePage(page);
          }
        }

        for (final mark in marks) {
          if (mark.boxes.isEmpty) continue;
          annotate(mark.page, (page) {
            final annot = lib.FPDFPage_CreateAnnot(page, _subtype[mark.kind]!);
            if (annot == nullptr) return;
            final (r, g, b) = markColor(mark.kind, mark.color);
            lib.FPDFAnnot_SetColor(annot, pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, r, g, b, 255);
            final quad = arena<pdfium.FS_QUADPOINTSF>();
            for (final box in mark.boxes) {
              final (x1, y1, x2, y2, x3, y3, x4, y4) = quadOf(box);
              quad.ref
                ..x1 = x1
                ..y1 = y1
                ..x2 = x2
                ..y2 = y2
                ..x3 = x3
                ..y3 = y3
                ..x4 = x4
                ..y4 = y4;
              lib.FPDFAnnot_AppendAttachmentPoints(annot, quad);
            }
            final bounds = boundsOf(mark.boxes);
            final rect = arena<pdfium.FS_RECTF>();
            rect.ref
              ..left = bounds.left
              ..top = bounds.top
              ..right = bounds.right
              ..bottom = bounds.bottom;
            lib.FPDFAnnot_SetRect(annot, rect);
            lib.FPDFAnnot_SetFlags(annot, pdfium.FPDF_ANNOT_FLAG_PRINT);
            if (mark.comment.isNotEmpty) lib.FPDFAnnot_SetStringValue(annot, contents, wide(mark.comment));
            lib.FPDFPage_CloseAnnot(annot);
          });
        }

        // The general notes: a sticky note in the top left corner of page one.
        if (notes.trim().isNotEmpty) {
          annotate(1, (page) {
            final annot = lib.FPDFPage_CreateAnnot(page, pdfium.FPDF_ANNOT_TEXT);
            if (annot == nullptr) return;
            final height = lib.FPDF_GetPageHeightF(page);
            final rect = arena<pdfium.FS_RECTF>();
            rect.ref
              ..left = 18
              ..top = height - 18
              ..right = 42
              ..bottom = height - 42;
            lib.FPDFAnnot_SetRect(annot, rect);
            lib.FPDFAnnot_SetColor(
              annot,
              pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
              255,
              222,
              51,
              255,
            );
            lib.FPDFAnnot_SetStringValue(annot, contents, wide(notes));
            lib.FPDFPage_CloseAnnot(annot);
          });
        }
      });
    });
    return await document.encodePdf();
  } finally {
    await document.dispose();
  }
}
