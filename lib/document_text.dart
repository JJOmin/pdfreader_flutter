// A document's text as the reader sees it: PDFium's chars to raw strings, blocks and sentences.
// Shared by the app, tool/dump.dart and the golden test, so all three read the same sentences.
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'shared/language.dart';
import 'shared/layout.dart';
import 'shared/pdfium_text.dart';
import 'shared/types.dart';
import 'shared/utterances.dart';

/// The pages the document's language is guessed from, as on the desktop.
const _languagePages = 5;

class LoadedPage {
  const LoadedPage(this.text, this.blocks, this.charRects);

  final PageText text;
  final List<Block> blocks;

  /// PDFium's glyph boxes, by char index: `text.charIndex` maps raw offsets to them.
  final List<PdfRect> charRects;
}

/// Loads each page's text once, on first use.
class DocumentText {
  DocumentText(this.document);

  final PdfDocument document;
  final _pages = <int, Future<LoadedPage>>{};
  final _utterances = <int, Future<List<Utterance>>>{};
  Future<Lang>? _lang;

  int get pageCount => document.pages.length;

  Future<LoadedPage> page(int number) => _pages[number] ??= () async {
    final page = document.pages[number - 1];
    final raw = await page.loadText();
    final rects = raw?.charRects ?? const <PdfRect>[];
    final text = pageTextFromPdfium(raw?.fullText ?? '', [
      for (final r in rects) (left: r.left, bottom: r.bottom, right: r.right, top: r.top),
    ]);
    return LoadedPage(text, layoutPage(text.items, page.height), rects);
  }();

  Future<Lang> get lang => _lang ??= () async {
    final blocks = [for (var n = 1; n <= pageCount && n <= _languagePages; n++) ...(await page(n)).blocks];
    return guessLang(blocks.map((b) => b.text).join(' ')).lang;
  }();

  Future<List<Utterance>> utterances(int number) => _utterances[number] ??= () async {
    final blocks = (await page(number)).blocks;
    return buildUtterances(blocks, number, await lang);
  }();
}
