// The speed reader (PLAN 18.2): in a long document it builds only what is on the screen, a jump to any
// page is at once, a paragraph that runs over a page break is one with the page number in the margin,
// and the voice is painted from a listenable of its own (PLAN 18.1).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_text.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/settings.dart';
import 'package:pdfreader/views/reading_view.dart';
import 'package:pdfreader/views/text_view.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

/// A PDF of `pages` pages, each with four paragraphs of three lines. Every fifth page ends in the middle
/// of a sentence, which the next page finishes.
Uint8List longPdf(int pages) {
  String page(int n) {
    final runsOn = n % 5 == 0 && n < pages;
    final continues = n % 5 == 1 && n > 1;
    final out = StringBuffer('BT /F1 12 Tf 72 700 Td ');
    for (var p = 1; p <= 4; p++) {
      final lines = [
        if (p == 1 && continues)
          'and finish here on the next page.'
        else
          'Page $n paragraph $p starts here and',
        'continues on this line with more words',
        if (p == 4 && runsOn) 'until the words that run on' else 'until it comes to its end.',
      ];
      for (final (i, line) in lines.indexed) {
        out.write('($line) Tj 0 ${i == 2 ? -30 : -14} Td ');
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

void main() {
  late DocumentText text;

  setUpAll(() async {
    await pdfrxInitialize();
    text = DocumentText(await PdfDocument.openData(longPdf(60)));
    // Read here, outside the widget tests' clock: the view then finds every page ready.
    for (var page = 1; page <= text.pageCount; page++) {
      await text.page(page);
    }
  });

  Future<ReadingController> pump(WidgetTester tester, {VoiceHighlights? voice}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ReadingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingView(
            text: text,
            settings: defaultSettings().reading,
            controller: controller,
            highlights: const [],
            voice: voice,
          ),
        ),
      ),
    );
    // The pages were read outside the test's clock, so the view gets them once real time passes.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    return controller;
  }

  int built() => find.byType(SelectableText, skipOffstage: false).evaluate().length;

  Finder paragraph(String part) => find.byWidgetPredicate(
    (w) => w is SelectableText && w.textSpan!.toPlainText().contains(part),
    description: 'the paragraph with “$part”',
  );

  testWidgets('builds only what is on the screen, in a document of 60 pages', (tester) async {
    final controller = await pump(tester);
    expect(paragraph('Page 1 paragraph 1 starts'), findsOneWidget);
    expect(built(), lessThan(40), reason: '240 paragraphs in all');
    expect(controller.scrollAnchor()!.page, 1);
  });

  testWidgets('a jump to a far page shows it at once, and the place is read back', (tester) async {
    final controller = await pump(tester);
    await controller.showPage(45, 0.5);
    await tester.pumpAndSettle();
    final at = controller.scrollAnchor()!;
    expect(at.page, 45);
    expect(at.offset, closeTo(0.5, 0.15));
    expect(paragraph('Page 45 paragraph 3'), findsOneWidget);
    expect(built(), lessThan(40));
    // And back to the start, which builds the text above the place it jumped to.
    await controller.showPage(1, 0);
    await tester.pumpAndSettle();
    expect(controller.scrollAnchor()!.page, 1);
  });

  testWidgets('a paragraph that runs over a page break is one, its page number in the margin', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = await pump(tester);
    await controller.showPage(5, 0.8);
    await tester.pumpAndSettle();
    expect(paragraph('until the words that run on and finish here on the next page.'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 6'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the voice is painted from its own listenable', (tester) async {
    final voice = ValueNotifier<List<Highlight>>(const []);
    addTearDown(voice.dispose);
    await pump(tester, voice: voice);
    final block = (await tester.runAsync(() => text.page(1)))!.blocks.first;
    final from = block.text.indexOf('paragraph');
    final ranges = rawRanges(block.raw, from, from + 'paragraph'.length);
    bool highlighted() => (tester.widget<SelectableText>(paragraph('Page 1 paragraph 1')).textSpan!.children!)
        .any((s) => (s as TextSpan).style?.backgroundColor != null && s.text == 'paragraph');
    expect(highlighted(), isFalse);
    voice.value = [Highlight(1, ranges, HighlightKind.word)];
    await tester.pump();
    expect(highlighted(), isTrue);
    voice.value = const [];
    await tester.pump();
    expect(highlighted(), isFalse);
  });
}
