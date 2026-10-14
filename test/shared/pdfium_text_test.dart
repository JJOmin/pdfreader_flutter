import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/pdfium_text.dart';

/// Builds a PDFium-like char stream: every char gets a glyph box on `baseline`, sized like a
/// sans-serif font of `size` points. Spaces, CR and LF get the empty box PDFium gives the
/// characters it inserts.
class Stream {
  Stream({this.capShare = 0.72, this.xShare = 0.52});

  /// Height of capitals and of x-height letters as a share of the font size.
  final double capShare;
  final double xShare;
  final text = StringBuffer();
  final boxes = <CharBox>[];
  double x = 72;

  void line(String s, double baseline, {double size = 10}) {
    for (final cp in s.runes) {
      final ch = String.fromCharCode(cp);
      if (ch == ' ' || ch == '\r' || ch == '\n') {
        boxes.add((left: x, bottom: baseline, right: x, top: baseline));
      } else {
        final descends = 'gjpqy'.contains(ch);
        final tall = RegExp(r'[A-Z0-9bdfhklﬁ]').hasMatch(ch);
        final bottom = descends ? baseline - 0.2 * size : baseline;
        final top = baseline + (tall ? capShare : xShare) * size;
        boxes.add((left: x, bottom: bottom, right: x + 0.5 * size, top: top));
      }
      text.write(ch);
      x += 0.5 * size;
    }
  }

  /// Ends the line the way PDFium does: an inserted CR LF.
  void eol(double baseline) {
    line('\r\n', baseline);
    x = 72;
  }

  PageText build() => pageTextFromPdfium(text.toString(), boxes);
}

void main() {
  group('pageTextFromPdfium', () {
    test('drops the inserted line ends and marks the run before them', () {
      final s = Stream()
        ..line('Hello world', 700)
        ..eol(700)
        ..line('Next line.', 688);
      final page = s.build();
      expect(page.items.map((i) => (i.str, i.hasEOL)), [('Hello world', true), ('Next line.', false)]);
      expect(page.raw, 'Hello worldNext line.');
      // "N" is raw offset 11 and PDFium char 13: the CR and LF sit between.
      expect(page.charIndex[11], 13);
      expect(page.charIndex, hasLength(page.raw.length));
    });

    test('keeps the spaces PDFium inserts between words', () {
      final page = (Stream()..line('two words', 700)).build();
      expect(page.raw, 'two words');
      expect(page.charIndex, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('sets the baseline from the glyphs that sit on it, not the descenders', () {
      final page = (Stream()..line('gyp quiz', 700)).build();
      expect(page.items.single.y, 700);
    });

    test('estimates the same size for a line with and without capitals', () {
      final page =
          (Stream()
                ..line('ALL CAPS 2024', 700)
                ..eol(700)
                ..line('lower case words', 688))
              .build();
      final [caps, lower] = page.items;
      expect((caps.height - lower.height).abs(), lessThanOrEqualTo(0.7));
      expect(lower.height, closeTo(10, 0.5));
    });

    test('sizes a line of digits like the letters around it, whatever the font', () {
      // Times-like proportions: capitals and digits are relatively taller than in a sans face.
      final page =
          (Stream(capShare: 0.66, xShare: 0.45)
                ..line('The group sizes were', 700)
                ..eol(700)
                ..line('2+, 3+).', 688)
                ..eol(688)
                ..line('and the rest of it.', 676))
              .build();
      final [letters, digits, _] = page.items;
      expect((digits.height - letters.height).abs(), lessThan(0.2));
      expect(layoutPage(page.items, 800), hasLength(1));
    });

    test('turns the hyphen PDFium marks at a line end into a line break', () {
      // PDFium writes a line-end hyphen as U+0002 with the hyphen's box, and no CR LF after it.
      final s = Stream()..line('not well', 700);
      s.text.write('\u0002');
      s.boxes.add((left: s.x, bottom: 702, right: s.x + 3, top: 703));
      s.x = 72;
      s.line('designed, customers', 688);
      final page = s.build();
      expect(page.items.map((i) => (i.str, i.hasEOL)), [('not well-', true), ('designed, customers', false)]);
      expect(page.charIndex[8], 8);
      expect(layoutPage(page.items, 800).single.text, 'not welldesigned, customers');
    });

    test('starts a new line where the baseline drops without a line end', () {
      final s = Stream()..line('first line of text', 700);
      s.x = 72;
      s.line('second line of text', 688);
      final page = s.build();
      expect(page.items.map((i) => (i.str, i.y)), [
        ('first line of text', 700),
        ('second line of text', 688),
      ]);
      expect(page.items.first.hasEOL, true);
    });

    test('keeps a superscript on its line', () {
      final s = Stream()..line('mass m', 700);
      s.line('2', 703, size: 6);
      s.line(' is used', 700);
      expect(s.build().items.single.str, 'mass m2 is used');
    });

    test('keeps a ligature as one character and lets layout expand it', () {
      final page = (Stream()..line('efﬁcient', 700)).build();
      expect(page.raw, 'efﬁcient');
      final [block] = layoutPage(page.items, 800);
      expect(block.text, 'efficient');
    });

    test('maps both halves of a character outside the BMP to one PDFium char', () {
      final page = (Stream()..line('a 𝑥 b', 700)).build();
      expect(page.raw, 'a 𝑥 b');
      expect(page.charIndex, [0, 1, 2, 2, 3, 4]);
    });

    test('marks text running up the margin as rotated', () {
      final s = Stream()..line('Body text that stays.', 400);
      s.eol(400);
      for (final (i, ch) in 'arXiv:1234'.split('').indexed) {
        final y = 300.0 + 6 * i;
        s.text.write(ch);
        s.boxes.add((left: 20, bottom: y, right: 27, top: y + 5));
      }
      final page = s.build();
      expect(page.items.map((i) => i.rotated), [false, true]);
      expect(layoutPage(page.items, 800).map((b) => b.text), ['Body text that stays.']);
    });

    test('finds a heading by its size', () {
      final page =
          (Stream()
                ..line('Introduction', 720, size: 16)
                ..eol(720)
                ..line('This is the body text of the page, long enough to set the size.', 690)
                ..eol(690)
                ..line('It goes on for another line of ordinary text here.', 678))
              .build();
      expect(layoutPage(page.items, 800).map((b) => b.heading), [true, false]);
    });
  });
}
