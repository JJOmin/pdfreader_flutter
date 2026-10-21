import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../document_text.dart';
import '../shared/marks.dart';
import '../shared/notes.dart';
import '../shared/pdfium_text.dart';
import '../shared/types.dart';
import 'mark_menu.dart';
import 'text_view.dart';

/// The PDF pages as a `TextView`: raw ranges are painted on PDFium's glyph boxes (ADR 1).
class PdfPagesController implements TextView {
  final viewer = PdfViewerController();
  _PdfPagesViewState? _state;

  @override
  bool get isReady => viewer.isReady && _state != null;

  @override
  int? get currentPage => viewer.isReady ? viewer.pageNumber : null;

  double get zoom => viewer.currentZoom;

  /// A page's rectangle in the document's layout.
  Rect _pageRect(int page) {
    final pdfPage = viewer.document.pages[page - 1];
    return viewer.calcRectForRectInsidePage(
      pageNumber: page,
      rect: PdfRect(0, pdfPage.height, pdfPage.width, 0),
    );
  }

  /// Where raw ranges of a page are on the screen, for tests that press on a word.
  Offset? globalCenterOf(int page, List<RawRange> ranges) {
    final state = _state;
    final boxes = state?._boxes(page, ranges);
    if (state == null || boxes == null || boxes.isEmpty || !viewer.isReady) return null;
    final b = boxes.first;
    final doc = viewer.calcRectForRectInsidePage(
      pageNumber: page,
      rect: PdfRect(b.left, b.top, b.right, b.bottom),
    );
    final local = MatrixUtils.transformPoint(viewer.value, doc.center);
    return (state.context.findRenderObject()! as RenderBox).localToGlobal(local);
  }

  @override
  ({int page, double offset})? scrollAnchor() {
    final page = currentPage;
    if (page == null) return null;
    final rect = _pageRect(page);
    return (page: page, offset: ((viewer.visibleRect.top - rect.top) / rect.height).clamp(0.0, 0.999));
  }

  @override
  Future<void> showPage(int page, double offset, {double? zoom}) async {
    if (!isReady || page < 1 || page > viewer.pageCount) return;
    final rect = _pageRect(page);
    final scale = zoom ?? viewer.currentZoom;
    final view = viewer.viewSize;
    final matrix = viewer.calcMatrixFor(
      Offset(viewer.centerPosition.dx, rect.top + offset * rect.height + view.height / (2 * scale)),
      zoom: scale,
    );
    await viewer.goTo(viewer.calcMatrixForClampedToNearestBoundary(matrix, viewSize: view));
  }

  @override
  Future<void> reveal(int page, List<RawRange> ranges) async {
    final state = _state;
    if (!isReady || state == null) return;
    final boxes = state._boxes(page, ranges);
    if (boxes == null) {
      // Its text is not loaded yet: go to the page, and the word follows once it is.
      if (viewer.pageNumber != page) unawaited(viewer.goToPage(pageNumber: page));
      return;
    }
    if (boxes.isEmpty) return;
    final b = boxes.first;
    final rect = viewer.calcRectForRectInsidePage(
      pageNumber: page,
      rect: PdfRect(b.left, b.top, b.right, b.bottom),
    );
    final visible = viewer.visibleRect;
    // Comfortably inside: leave the view still, as the desktop does.
    final comfort = Rect.fromLTRB(
      visible.left,
      visible.top + visible.height * 0.1,
      visible.right,
      visible.bottom - visible.height * 0.25,
    );
    if (comfort.contains(rect.topLeft) && comfort.contains(rect.bottomRight)) return;
    // At the user's zoom: the text goes to 30 % from the top, sideways only if it is off screen.
    // ensureVisible would zoom in on it.
    final x = visible.left <= rect.left && rect.right <= visible.right ? visible.center.dx : rect.center.dx;
    final matrix = viewer.calcMatrixFor(Offset(x, rect.center.dy + visible.height * 0.2));
    await viewer.goTo(viewer.calcMatrixForClampedToNearestBoundary(matrix, viewSize: viewer.viewSize));
  }
}

class PdfPagesView extends StatefulWidget {
  const PdfPagesView({
    super.key,
    required this.document,
    required this.text,
    required this.controller,
    required this.highlights,
    required this.initialPage,
    this.onReady,
    this.onTouched,
    this.buildSelectionMenu,
    this.onMarkTapped,
  });

  final PdfDocumentRef document;
  final DocumentText text;
  final PdfPagesController controller;
  final List<Highlight> highlights;
  final int initialPage;
  final VoidCallback? onReady;

  /// The user scrolled or zoomed: the view stops following the voice for a while.
  final VoidCallback? onTouched;

  /// The menu shown over selected text, or null where nothing can be marked.
  final SelectionMenuBuilder? buildSelectionMenu;
  final MarkTapped? onMarkTapped;

  @override
  State<PdfPagesView> createState() => _PdfPagesViewState();
}

class _PdfPagesViewState extends State<PdfPagesView> {
  /// Pages whose text is loaded, for painting on their glyph boxes.
  final _loaded = <int, LoadedPage>{};
  final _loading = <int>{};

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(PdfPagesView old) {
    super.didUpdateWidget(old);
    widget.controller._state = this;
    if (!identical(old.highlights, widget.highlights) && widget.controller.viewer.isReady) {
      widget.controller.viewer.invalidate();
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  /// The boxes to paint for raw ranges of a page, or null while its text is being loaded.
  List<CharBox>? _boxes(int page, List<RawRange> ranges) {
    final loaded = _loaded[page];
    if (loaded == null) {
      if (_loading.add(page)) {
        unawaited(
          widget.text.page(page).then((text) {
            _loaded[page] = text;
            if (mounted && widget.controller.viewer.isReady) widget.controller.viewer.invalidate();
          }),
        );
      }
      return null;
    }
    final rects = [
      for (final r in loaded.charRects) (left: r.left, bottom: r.bottom, right: r.right, top: r.top),
    ];
    return rangeBoxes(ranges, loaded.text.charIndex, rects);
  }

  void _paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    Rect place(CharBox b) =>
        PdfRect(b.left, b.top, b.right, b.bottom).toRectInDocument(page: page, pageRect: pageRect);
    for (final highlight in widget.highlights) {
      if (highlight.page != page.pageNumber) continue;
      final kind = highlight.kind;
      for (final b in _boxes(page.pageNumber, highlight.ranges) ?? const <CharBox>[]) {
        final rect = place(b);
        if (kind != null) {
          final paint = Paint()..color = kind.color;
          if (kind == HighlightKind.word) {
            canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)), paint);
          } else {
            canvas.drawRect(rect, paint);
          }
          continue;
        }
        final color = highlight.color!;
        switch (highlight.mark!) {
          case MarkKind.highlight:
            canvas.drawRect(rect, Paint()..color = markFill[color]!);
          case MarkKind.underline:
            // On the baseline: PDFium's boxes are tight around the ink, so the bottom is below it.
            final y = rect.bottom - rect.height * 0.12;
            canvas.drawLine(
              Offset(rect.left, y),
              Offset(rect.right, y),
              Paint()
                ..color = markLine[color]!
                ..strokeWidth = (rect.height * 0.08).clamp(1.0, 3.0),
            );
          case MarkKind.strike:
            canvas.drawLine(
              Offset(rect.left, rect.center.dy),
              Offset(rect.right, rect.center.dy),
              Paint()
                ..color = markLine[color]!
                ..strokeWidth = (rect.height * 0.08).clamp(1.0, 3.0),
            );
        }
      }
    }
  }

  /// The mark under a tap, the last painted where several lie there.
  String? _markAt(PdfPageHitTestResult hit) {
    String? found;
    for (final highlight in widget.highlights) {
      if (highlight.markId == null || highlight.page != hit.page.pageNumber) continue;
      for (final b in _boxes(highlight.page, highlight.ranges) ?? const <CharBox>[]) {
        if (hit.offset.x >= b.left &&
            hit.offset.x <= b.right &&
            hit.offset.y >= b.bottom &&
            hit.offset.y <= b.top) {
          found = highlight.markId;
        }
      }
    }
    return found;
  }

  bool _tapped(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.tap || widget.onMarkTapped == null) return false;
    final hit = controller.getPdfPageHitTestResult(
      details.documentPosition,
      useDocumentLayoutCoordinates: true,
    );
    final id = hit == null ? null : _markAt(hit);
    if (id == null) return false;
    widget.onMarkTapped!(id);
    return true;
  }

  /// The raw ranges the selected text covers, one per page it reaches. pdfrx numbers the characters
  /// of its own reading-order text, so the selection is placed by its glyph boxes (ADR 1).
  Future<List<PageSelection>> _selected(PdfTextSelectionDelegate selection) async {
    CharBox box(PdfRect r) => (left: r.left, bottom: r.bottom, right: r.right, top: r.top);
    final out = <PageSelection>[];
    for (final range in await selection.getSelectedTextRanges()) {
      final loaded = await widget.text.page(range.pageNumber);
      final raw = rawRangeFromBoxes(
        [for (final r in range.pageText.charRects.sublist(range.start, range.end)) box(r)],
        [for (final r in loaded.charRects) box(r)],
        loaded.text.charIndex,
      );
      if (raw != null) out.add((page: range.pageNumber, range: raw));
    }
    return out;
  }

  Widget? _menu(BuildContext context, PdfViewerContextMenuBuilderParams params) {
    final build = widget.buildSelectionMenu;
    if (build == null ||
        params.contextMenuFor != PdfViewerPart.selectedText ||
        !params.textSelectionDelegate.hasSelectedText) {
      return null;
    }
    return build(
      context,
      params.anchorA,
      params.anchorB,
      () => _selected(params.textSelectionDelegate),
      params.textSelectionDelegate.clearTextSelection,
    );
  }

  @override
  Widget build(BuildContext context) => PdfViewer(
    widget.document,
    controller: widget.controller.viewer,
    initialPageNumber: widget.initialPage,
    params: PdfViewerParams(
      onViewerReady: (_, _) => widget.onReady?.call(),
      onInteractionStart: (_) => widget.onTouched?.call(),
      pagePaintCallbacks: [_paint],
      onGeneralTap: _tapped,
      buildContextMenu: _menu,
    ),
  );
}
