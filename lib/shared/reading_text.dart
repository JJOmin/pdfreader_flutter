// The speed reader's text (PLAN 18.2): the pages' blocks as paragraphs, read without a break where a
// page ends in the middle of a sentence. A paragraph over a page break is joined by the rule the voice
// uses for a sentence there (desktop ADR 12), so the text and the voice agree. Every place in a
// paragraph still leads back to a block of a page, and so to raw ranges (ADR 1).
import 'dart:math' as math;

import 'layout.dart';
import 'types.dart';
import 'utterances.dart' show endsSentence;

/// One block of a paragraph: its page, its index among the page's blocks, and where its text starts in
/// the paragraph's.
typedef ParagraphPart = ({int page, int block, int at});

/// Where a page begins inside a paragraph.
typedef PageStart = ({int page, int at});

/// A place in the speed reader: a paragraph and a UTF-16 offset in its text.
typedef ReadingPlace = ({int paragraph, int at});

class ReadingParagraph {
  ReadingParagraph(this.parts, this.text, {required this.heading, required this.pageStarts});

  final List<ParagraphPart> parts;

  /// The blocks' texts, joined by single spaces.
  final String text;
  final bool heading;

  /// The pages whose first block is in this paragraph.
  final List<PageStart> pageStarts;

  int get page => parts.first.page;
}

class ReadingText {
  /// `pages` are the blocks of pages 1, 2, and so on, as many as are loaded.
  ReadingText(this.pages) {
    final current = <ParagraphPart>[];
    final starts = <PageStart>[];
    final text = StringBuffer();
    var heading = false;
    void close() {
      if (current.isEmpty) return;
      paragraphs.add(
        ReadingParagraph(List.of(current), text.toString(), heading: heading, pageStarts: List.of(starts)),
      );
      current.clear();
      starts.clear();
      text.clear();
    }

    for (var page = 1; page <= pages.length; page++) {
      final blocks = pages[page - 1];
      _found.add(List.filled(blocks.length, (paragraph: 0, at: 0)));
      for (var b = 0; b < blocks.length; b++) {
        final block = blocks[b];
        final last = current.isEmpty ? null : current.last;
        final joins =
            b == 0 &&
            last != null &&
            last.page == page - 1 &&
            !heading &&
            !block.heading &&
            !endsSentence(pages[last.page - 1][last.block].text);
        if (!joins) {
          close();
          heading = block.heading;
        } else {
          text.write(' ');
        }
        final at = text.length;
        current.add((page: page, block: b, at: at));
        if (b == 0) starts.add((page: page, at: at));
        _found[page - 1][b] = (paragraph: paragraphs.length, at: at);
        text.write(block.text);
      }
    }
    close();
  }

  final List<List<Block>> pages;
  final paragraphs = <ReadingParagraph>[];

  /// For each page and block, its paragraph and where it starts there.
  final _found = <List<ReadingPlace>>[];

  int _length(int page) => pages[page - 1].fold(0, (sum, b) => sum + b.text.length);

  /// Where a page's raw range `[start, end)` shows up, one stretch per paragraph it reaches.
  List<({int paragraph, int from, int to})> spans(int page, int start, int end) {
    if (page < 1 || page > pages.length) return const [];
    final found = _found[page - 1];
    return [
      for (final span in blockSpans(pages[page - 1], start, end))
        (
          paragraph: found[span.block].paragraph,
          from: found[span.block].at + span.from,
          to: found[span.block].at + span.to,
        ),
    ];
  }

  /// The raw range on each page that a stretch `[from, to)` of a paragraph covers. The space that
  /// joins two parts belongs to no page.
  List<({int page, RawRange range})> rawSelection(int paragraph, int from, int to) {
    final out = <({int page, RawRange range})>[];
    for (final part in paragraphs[paragraph].parts) {
      final block = pages[part.page - 1][part.block];
      final a = math.max(from, part.at) - part.at;
      final b = math.min(to, part.at + block.text.length) - part.at;
      if (a >= b) continue;
      final ranges = rawRanges(block.raw, a, b);
      if (ranges.isEmpty) continue;
      final range = (ranges.first.$1, ranges.last.$2);
      if (out.isNotEmpty && out.last.page == part.page) {
        out.last = (page: part.page, range: (out.last.range.$1, range.$2));
      } else {
        out.add((page: part.page, range: range));
      }
    }
    return out;
  }

  /// The place `offset` (0 to 1) of the way through a page's text. A page with no text is shown where
  /// the next page with text starts; null when that page is not loaded yet.
  ReadingPlace? placeOfPage(int page, double offset) {
    for (var p = math.max(1, page); p <= pages.length; p++) {
      final blocks = pages[p - 1];
      if (blocks.isEmpty) continue;
      if (p != page) return _found[p - 1][0];
      final length = _length(p);
      var at = math.min((offset.clamp(0.0, 1.0) * length).floor(), math.max(0, length - 1));
      for (var b = 0; b < blocks.length; b++) {
        if (at < blocks[b].text.length || b == blocks.length - 1) {
          final found = _found[p - 1][b];
          return (paragraph: found.paragraph, at: found.at + math.min(at, blocks[b].text.length));
        }
        at -= blocks[b].text.length;
      }
    }
    return null;
  }

  /// The page a place in a paragraph is on, and how far through that page's text it lies (0 to 1).
  ({int page, double offset}) pageOfPlace(int paragraph, int at) {
    final parts = paragraphs[paragraph].parts;
    var part = parts.first;
    for (final p in parts) {
      if (p.at <= at) part = p;
    }
    final blocks = pages[part.page - 1];
    var before = 0;
    for (var b = 0; b < part.block; b++) {
      before += blocks[b].text.length;
    }
    final inBlock = (at - part.at).clamp(0, blocks[part.block].text.length);
    final length = _length(part.page);
    return (page: part.page, offset: length == 0 ? 0 : (before + inBlock) / length);
  }
}
