// Turns PDFium's char stream into the text runs layout reads (ADR 1, "How the raw string is made
// on the phone"). PDFium gives one code point and one glyph box per char index, in content-stream
// order, with spaces and CR LF pairs of its own inserted.
import 'types.dart';

/// A glyph box in PDF units, y growing upwards. PDFium gives inserted characters an empty box.
typedef CharBox = ({double left, double bottom, double right, double top});

class PageText {
  PageText(this.items, this.charIndex);

  final List<RawItem> items;

  /// For every UTF-16 unit of the raw string, the PDFium char index it came from.
  final List<int> charIndex;

  String get raw => items.map((i) => i.str).join();
}

// PDFium's boxes are tight around the ink, so a glyph's height is not the font size. A run's size
// is its x-height letters' height over a typical share of the font size. Only ratios between
// lines matter to layout, and its absolute thresholds are in font sizes, so an estimate close
// to the font size is enough.
const _xHeightShare = 0.5;
const _capHeightShare = 0.7;
const _xHeightLetters = 'acemnorsuvwxz';
final _capOrDigit = RegExp('[A-IK-PR-Z0-9]');
const _offBaseline = 'gjpqy,;()[]{}';

/// PDFium's mark for a hyphen at a line end, which it joins to the next line without a CR LF.
const _lineEndHyphen = '\u0002';

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

double _height(CharBox b) => b.top - b.bottom;

class _Run {
  final str = StringBuffer();
  final index = <int>[];
  final inked = <(String, CharBox)>[];
  CharBox? first;
  bool eol = false;

  bool get isEmpty => index.isEmpty;

  Iterable<double> heightsOf(bool Function(String) kind) => [
    for (final (ch, box) in inked)
      if (kind(ch)) _height(box),
  ];

  /// `capToX` converts a capital's height into the x-height of the same font, measured on the page.
  RawItem toItem(double capToX) {
    final boxes = inked.map((c) => c.$2).toList();
    final onBaseline = [
      for (final (ch, box) in inked)
        if (!_offBaseline.contains(ch)) box.bottom,
    ];
    final xHeights = heightsOf(_xHeightLetters.contains).toList();
    final capHeights = heightsOf(_capOrDigit.hasMatch).toList();
    final double xHeight;
    if (xHeights.isNotEmpty) {
      xHeight = _median(xHeights);
    } else if (capHeights.isNotEmpty) {
      xHeight = _median(capHeights) * capToX;
    } else if (boxes.isNotEmpty) {
      xHeight = boxes.map(_height).reduce((a, b) => a > b ? a : b) * capToX;
    } else {
      xHeight = 0;
    }
    // Text running up or down the page, such as an arXiv stamp, advances in y instead of x.
    var rotated = false;
    if (boxes.length >= 2) {
      final dx = (boxes.last.left - boxes.first.left).abs();
      final dy = (boxes.last.bottom - boxes.first.bottom).abs();
      rotated = dy > dx;
    }
    return RawItem(
      str: str.toString(),
      x: boxes.isNotEmpty ? boxes.first.left : first!.left,
      y: onBaseline.isNotEmpty
          ? _median(onBaseline)
          : boxes.isNotEmpty
          ? _median([for (final b in boxes) b.bottom])
          : first!.bottom,
      height: xHeight / _xHeightShare,
      font: '',
      hasEOL: eol,
      rotated: rotated,
    );
  }
}

/// Builds the page's text runs, one per line, and the map from raw offsets to PDFium chars.
/// The CR LF that PDFium inserts at a line end is dropped; the run before it gets `hasEOL`,
/// which is how PDF.js reports a line end on the desktop, with no character there either.
PageText pageTextFromPdfium(String fullText, List<CharBox> boxes) {
  final runs = <_Run>[];
  var run = _Run();
  void end({required bool eol}) {
    if (!run.isEmpty) {
      runs.add(run..eol = eol);
    } else if (eol && runs.isNotEmpty) {
      runs.last.eol = true;
    }
    run = _Run();
  }

  // A new line that PDFium did not mark: the text jumps back left onto another baseline.
  bool startsLine(CharBox box) {
    for (final (ch, prev) in run.inked.reversed) {
      if (_offBaseline.contains(ch) || _height(prev) <= 0) continue;
      return box.left < prev.left - (prev.right - prev.left) &&
          (box.bottom - prev.bottom).abs() > 0.5 * _height(prev);
    }
    return false;
  }

  var i = 0;
  for (final cp in fullText.runes) {
    final ch = String.fromCharCode(cp);
    final box = i < boxes.length ? boxes[i] : null;
    final empty = box == null || (box.right <= box.left && box.top <= box.bottom);
    if ((ch == '\r' || ch == '\n') && empty) {
      if (ch == '\r' || !run.isEmpty) end(eol: true);
    } else if (ch == _lineEndHyphen && box != null) {
      // The hyphen goes back in, so that layout undoes the hyphenation exactly as on the desktop.
      run.first ??= box;
      run.str.write('-');
      run.index.add(i);
      end(eol: true);
    } else if (box != null) {
      final inked = !empty && ch.trim().isNotEmpty;
      if (inked && startsLine(box)) end(eol: true);
      run.first ??= box;
      run.str.write(ch);
      for (var u = 0; u < ch.length; u++) {
        run.index.add(i);
      }
      if (inked) run.inked.add((ch, box));
    }
    i++;
  }
  end(eol: false);

  // Capitals and digits stand taller next to the x-height in some faces than in others, so the
  // page itself says how the two compare: within each line, where both share a font and size.
  final ratios = [
    for (final r in runs)
      if ((r.heightsOf(_xHeightLetters.contains).toList(), r.heightsOf(_capOrDigit.hasMatch).toList())
          case (final x, final cap) when x.isNotEmpty && cap.isNotEmpty)
        _median(x) / _median(cap),
  ];
  final capToX = ratios.isNotEmpty ? _median(ratios) : _xHeightShare / _capHeightShare;
  return PageText([for (final r in runs) r.toItem(capToX)], [for (final r in runs) ...r.index]);
}
