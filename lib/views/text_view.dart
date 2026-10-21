// Port of the desktop's src/renderer/src/view.ts (PLAN step 3.2). Both ways of showing a document,
// the PDF pages and the reading view, place raw ranges on the screen, so speech, search and marks
// are written once against raw ranges and work in either.
import 'dart:ui';

import '../shared/notes.dart';
import '../shared/types.dart';

/// What a highlight is for, and its colour, as on the desktop.
enum HighlightKind {
  sentence(Color(0x292F6FED)),
  search(Color(0x59FF9632)),
  searchCurrent(Color(0xBFFF7800)),
  word(Color(0x802F6FED));

  const HighlightKind(this.color);

  final Color color;
}

/// The fill of a highlight mark, and the stronger tone of its underline and strike-through, so that
/// a thin line stays visible. The desktop's values.
const markFill = {
  HighlightColor.yellow: Color(0x66FFD400),
  HighlightColor.green: Color(0x665FCF65),
  HighlightColor.blue: Color(0x665AB0FF),
  HighlightColor.red: Color(0x66FF6B6B),
};
const markLine = {
  HighlightColor.yellow: Color(0xFFD4A900),
  HighlightColor.green: Color(0xFF2E9E3A),
  HighlightColor.blue: Color(0xFF1F7FE0),
  HighlightColor.red: Color(0xFFE03131),
};

/// Raw ranges of one page, painted the same way by every view: the voice or search, or a mark.
/// A view paints the highlights in list order, so later ones lie over earlier ones.
class Highlight {
  const Highlight(this.page, this.ranges, HighlightKind this.kind) : mark = null, color = null, markId = null;

  const Highlight.mark(
    this.page,
    this.ranges,
    MarkKind this.mark,
    HighlightColor this.color,
    String this.markId,
  ) : kind = null;

  final int page;
  final List<RawRange> ranges;
  final HighlightKind? kind;
  final MarkKind? mark;
  final HighlightColor? color;

  /// The mark's id, so that a tap on it can be told from a tap on other text.
  final String? markId;
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

/// Called when the user taps a mark, with its id.
typedef MarkTapped = void Function(String id);
