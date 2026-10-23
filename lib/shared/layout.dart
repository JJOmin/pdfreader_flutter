// Port of the desktop's src/shared/layout.ts.
import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'types.dart';

/// A paragraph or heading in reading order, with each character traced back to the page.
class Block {
  Block(this.text, this.raw, {required this.heading});

  final String text;

  /// Raw offset of each UTF-16 unit of `text`, or -1 for characters layout inserted.
  final List<int> raw;
  final bool heading;
}

class _Line {
  _Line(this.text, this.raw, this.y, this.size, this.font);

  final String text;
  final List<int> raw;
  final double y;
  final double size;
  final String font;
}

const _headerZone = 0.935;
const _footerZone = 0.065;
final _numberedHeading = RegExp(r'^(\d+(\.\d+)*\.?|[IVX]+\.)\s+\p{Lu}', unicode: true);
final _hyphenatedEnd = RegExp(r'(\S+)-$', unicode: true);
final _firstWord = RegExp(r'^\S+', unicode: true);
final _lowerStart = RegExp(r'^\p{Ll}', unicode: true);
final _upperStart = RegExp(r'^\p{Lu}', unicode: true);
final _omittedPart = RegExp(r'^(und|oder|bzw\.?|and|or)$', unicode: true);
final _endsInHyphenOrSpace = RegExp(r'[-\s]$', unicode: true);
final _terminated = RegExp(r'[.!?:,;]$', unicode: true);

/// The key with the largest summed weight; the first one seen wins a tie.
T? _dominant<T>(Iterable<(T, int)> entries) {
  final weights = <T, int>{};
  for (final (key, weight) in entries) {
    weights[key] = (weights[key] ?? 0) + weight;
  }
  T? best;
  var bestWeight = -1;
  weights.forEach((key, weight) {
    if (weight > bestWeight) (best, bestWeight) = (key, weight);
  });
  return best;
}

List<_Line> _toLines(List<RawItem> items) {
  final lines = <_Line>[];
  var parts = <(RawItem, int)>[];
  void flush() {
    final visible = parts.where((p) => p.$1.str.trim() != '').toList();
    if (visible.isNotEmpty) {
      final text = StringBuffer();
      final raw = <int>[];
      for (final (item, offset) in parts) {
        var at = offset;
        for (final cp in item.str.runes) {
          final ch = String.fromCharCode(cp);
          // Normalising per character keeps the map exact when a ligature expands.
          final normalized = unorm.nfkc(ch);
          text.write(normalized);
          for (var i = 0; i < normalized.length; i++) {
            raw.add(at);
          }
          at += ch.length;
        }
      }
      lines.add(
        _Line(
          text.toString(),
          raw,
          visible.first.$1.y,
          _dominant(visible.map((p) => ((p.$1.height * 2).round() / 2, p.$1.str.length)))!,
          _dominant(visible.map((p) => (p.$1.font, p.$1.str.length)))!,
        ),
      );
    }
    parts = [];
  }

  var offset = 0;
  for (final item in items) {
    // Rotated runs are margin stamps such as the arXiv identifier, never body text.
    if (!item.rotated) {
      final last = parts.isEmpty ? null : parts.last.$1;
      if (last != null && item.str.trim() != '' && (item.y - last.y).abs() > 2 * last.height) flush();
      parts.add((item, offset));
    }
    offset += item.str.length;
    if (item.hasEOL) flush();
  }
  flush();
  return lines;
}

/// Joins a line onto its block: undoes line-break hyphenation, otherwise adds a space.
void _appendLine(StringBuffer block, List<int> raw, _Line line) {
  final text = line.text.trimLeft();
  final lineRaw = line.raw.sublist(line.text.length - text.length);
  final current = block.toString();
  final lastWord = _hyphenatedEnd.firstMatch(current)?.group(1);
  final nextWord = _firstWord.firstMatch(text)?.group(0) ?? '';
  if (lastWord != null && _lowerStart.hasMatch(nextWord)) {
    if (_omittedPart.hasMatch(nextWord)) {
      // "Vor- und Nachteile": the hyphen stands for an omitted word part.
      block.write(' ');
      raw.add(-1);
    } else if (!lastWord.contains('-')) {
      // shortcut: "state-of-the-" + "art" keeps its hyphen, a plain "Ent-" + "wicklung"
      // loses it. Wrong for a compound broken at its only hyphen before a lower-case
      // part; upgrade to a dictionary lookup if that shows up in real papers.
      block
        ..clear()
        ..write(current.substring(0, current.length - 1));
      raw.removeLast();
    }
  } else if (current.isNotEmpty && !_endsInHyphenOrSpace.hasMatch(current)) {
    block.write(' ');
    raw.add(-1);
  }
  block.write(text);
  raw.addAll(lineRaw);
}

/// A figure's or table's caption, which is read although it is set small (desktop backlog 1).
final _caption = RegExp(
  r'^(fig(ure|\.)?|table|tab\.|abb(ildung|\.)|tabelle)\s*[\dIVX]',
  caseSensitive: false,
  unicode: true,
);

/// Text this much smaller than the body, without a sentence's end, is a label inside a figure.
const _figureSize = 0.88;

/// Below this share of letters among the visible characters a block is a table row or a formula.
const _symbolic = 0.5;
final _mathOperator = RegExp(r'[=<>≤≥≈≠∑Σ∏∫∂√∞∈∉±×÷^]', unicode: true);

/// A word of three letters or more. A formula has at most two, such as "max" and "log".
final _proseWord = RegExp(r'\p{L}{3,}', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _space = RegExp(r'\s', unicode: true);

/// Text that is not read (desktop backlog 1 and 2): a label inside a figure (smaller than the body, no
/// sentence end, short), a table row (mostly digits and symbols), or a displayed formula (a math operator
/// and hardly a word of prose). Fonts are not asked: PDF.js and PDFium name them differently, and both
/// apps must leave out the same text.
bool _notProse(String text, double size, double bodySize, bool unterminated) {
  final visible = text.replaceAll(_space, '');
  // Letters by code point and the length in UTF-16 units, as the desktop's JavaScript counts them.
  final letters = _letter.allMatches(visible).length;
  final symbolic = visible.length >= 3 && letters / visible.length < _symbolic;
  final label = unterminated && text.length <= 80 && size <= bodySize * _figureSize;
  final formula =
      text.length <= 150 && _mathOperator.hasMatch(text) && _proseWord.allMatches(text).length <= 2;
  return symbolic || label || formula;
}

/// Turns one page's text runs into paragraphs and headings, dropping running headers and footers, and
/// figure labels, table rows and displayed formulas.
List<Block> layoutPage(List<RawItem> items, double pageHeight) {
  final lines = _toLines(items);
  final bodySize = _dominant(lines.map((l) => (l.size, l.text.length))) ?? 0;
  final bodyFont = _dominant(lines.map((l) => (l.font, l.text.length)));

  final groups = <List<_Line>>[];
  for (final line in lines) {
    final prev = groups.isEmpty ? null : groups.last.last;
    final gap = prev != null ? prev.y - line.y : 0.0;
    final size = prev != null ? math.max(prev.size, line.size) : 0.0;
    final sameBlock =
        prev != null &&
        (prev.size - line.size).abs() <= 0.7 &&
        gap > 0 &&
        gap <= 1.9 * size &&
        !(prev.font != line.font && gap > 1.35 * size);
    if (sameBlock) {
      groups.last.add(line);
    } else {
      groups.add([line]);
    }
  }

  final blocks = <Block>[];
  for (final group in groups) {
    final buffer = StringBuffer();
    final raw = <int>[];
    for (final line in group) {
      _appendLine(buffer, raw, line);
    }
    final text = buffer.toString().trimRight();
    raw.length = text.length;

    final first = group.first;
    final inMargin = first.y > pageHeight * _headerZone || group.last.y < pageHeight * _footerZone;
    if (text.isEmpty || (inMargin && text.length < 150)) continue;

    final short = text.length <= 200 && group.length <= 3;
    final unterminated = !_terminated.hasMatch(text);
    final larger = first.size >= bodySize * 1.12;
    final numbered = group.length == 1 && text.length <= 100 && _numberedHeading.hasMatch(text);
    final titleLike =
        group.length == 1 && first.font != bodyFont && text.length <= 60 && _upperStart.hasMatch(text);
    final heading = short && unterminated && (larger || numbered || titleLike);
    // A numbered section heading in small capitals is smaller than the body, but no figure label.
    // `heading` is not asked: it depends on font names, which PDF.js sees differently.
    final kept = larger || _caption.hasMatch(text) || _numberedHeading.hasMatch(text);
    if (!kept && _notProse(text, first.size, bodySize, unterminated)) continue;
    blocks.add(Block(text, raw, heading: heading));
  }
  return blocks;
}

/// Collapses the raw offsets behind `text[start..end)` into contiguous page ranges.
List<RawRange> rawRanges(List<int> raw, int start, int end) {
  final ranges = <RawRange>[];
  for (var i = start; i < end; i++) {
    final at = raw[i];
    if (at < 0) continue;
    // A ligature maps several characters to one offset, which extends nothing.
    if (ranges.isNotEmpty && (at == ranges.last.$2 || at == ranges.last.$2 - 1)) {
      ranges.last = (ranges.last.$1, at + 1);
    } else {
      ranges.add((at, at + 1));
    }
  }
  return ranges;
}

/// A stretch of one block's readable text.
typedef BlockSpan = ({int block, int from, int to});

/// The inverse of `rawRanges`: where the page's raw range `[start, end)` shows up in the blocks' text.
List<BlockSpan> blockSpans(List<Block> blocks, int start, int end) {
  bool inside(int at) => at >= start && at < end;
  return [
    for (var index = 0; index < blocks.length; index++)
      if (blocks[index].raw.indexWhere(inside) case final from when from >= 0)
        (block: index, from: from, to: blocks[index].raw.lastIndexWhere(inside) + 1),
  ];
}

/// The readable text behind a raw range: lines joined and hyphenation undone.
String readableText(List<Block> blocks, int start, int end) => blockSpans(
  blocks,
  start,
  end,
).map((span) => blocks[span.block].text.substring(span.from, span.to)).join(' ');
