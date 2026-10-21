// Port of the desktop's src/renderer/src/view.ts (PLAN step 3.2). Both ways of showing a document,
// the PDF pages and the reading view, place raw ranges on the screen, so speech, search and later
// marks are written once against raw ranges and work in either.
import 'dart:ui';

import '../shared/types.dart';

/// What a highlight is for. Later kinds are drawn over earlier ones.
enum HighlightKind {
  sentence(Color(0x40FFD54F)),
  search(Color(0x4064B5F6)),
  searchCurrent(Color(0x9964B5F6)),
  word(Color(0x66FF8F00));

  const HighlightKind(this.color);

  final Color color;
}

/// Raw ranges of one page, painted the same way by every view.
class Highlight {
  const Highlight(this.page, this.ranges, this.kind);

  final int page;
  final List<RawRange> ranges;
  final HighlightKind kind;
}

/// One way of showing the document's text.
abstract interface class TextView {
  bool get isReady;

  /// The page the user is looking at.
  int? get currentPage;

  /// The page at the top edge of the view and how far down it that edge lies, from 0 to 1.
  ({int page, double offset})? scrollAnchor();

  /// Scrolls to `offset` (0 to 1) of the way down a page.
  Future<void> showPage(int page, double offset);

  /// Scrolls so that raw ranges of a page are comfortably in view; leaves the view still if they are.
  Future<void> reveal(int page, List<RawRange> ranges);
}
