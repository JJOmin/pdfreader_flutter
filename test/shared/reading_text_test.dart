// The speed reader's paragraphs (PLAN 18.2): each page's blocks in order, a paragraph that runs over a
// page break joined into one by the rule the voice uses for a sentence there (desktop ADR 12), and the
// ways between a page's raw ranges and places in the paragraphs.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/reading_text.dart';

/// A block whose characters sit at raw offsets `from`, `from + 1`, and so on.
Block block(String text, {bool heading = false, int from = 0}) =>
    Block(text, [for (var i = 0; i < text.length; i++) from + i], heading: heading);

void main() {
  test('each block is a paragraph, page after page', () {
    final reading = ReadingText([
      [block('Title', heading: true), block('First paragraph.', from: 5)],
      [block('Second page.')],
    ]);
    expect(reading.paragraphs.map((p) => p.text), ['Title', 'First paragraph.', 'Second page.']);
    expect(reading.paragraphs.map((p) => p.heading), [true, false, false]);
    expect(reading.paragraphs[2].parts, [(page: 2, block: 0, at: 0)]);
  });

  test('a paragraph whose page ends in the middle of a sentence goes on with the next page', () {
    final reading = ReadingText([
      [block('Intro.'), block('The sentence runs over', from: 6)],
      [block('the page break and ends here.'), block('Next one.', from: 29)],
    ]);
    expect(reading.paragraphs.map((p) => p.text), [
      'Intro.',
      'The sentence runs over the page break and ends here.',
      'Next one.',
    ]);
    expect(reading.paragraphs[1].parts, [(page: 1, block: 1, at: 0), (page: 2, block: 0, at: 23)]);
  });

  test('a finished sentence, a heading on either side or an empty page keeps the break', () {
    List<String> texts(List<List<Block>> pages) => [for (final p in ReadingText(pages).paragraphs) p.text];
    expect(
      texts([
        [block('Ends with a full stop.')],
        [block('new paragraph')],
      ]),
      ['Ends with a full stop.', 'new paragraph'],
    );
    expect(
      texts([
        [block('He said: “stop.”')],
        [block('and so on')],
      ]),
      ['He said: “stop.”', 'and so on'],
    );
    expect(
      texts([
        [block('Chapter', heading: true)],
        [block('text')],
      ]),
      ['Chapter', 'text'],
    );
    expect(
      texts([
        [block('runs on')],
        [block('Heading', heading: true)],
      ]),
      ['runs on', 'Heading'],
    );
    expect(
      texts([
        [block('runs on')],
        [],
        [block('more.')],
      ]),
      ['runs on', 'more.'],
    );
  });

  test('a paragraph can run over several pages', () {
    final reading = ReadingText([
      [block('one')],
      [block('two')],
      [block('three.')],
    ]);
    expect(reading.paragraphs.single.text, 'one two three.');
    expect(reading.paragraphs.single.parts.map((p) => p.at), [0, 4, 8]);
  });

  test('each page starts where its first block is, also inside a joined paragraph', () {
    final reading = ReadingText([
      [block('Intro.'), block('The sentence runs over', from: 6)],
      [block('the page break.')],
      [],
      [block('Last.')],
    ]);
    expect(reading.paragraphs[0].pageStarts, [(page: 1, at: 0)]);
    expect(reading.paragraphs[1].pageStarts, [(page: 2, at: 23)]);
    expect(reading.paragraphs[2].pageStarts, [(page: 4, at: 0)]);
  });

  test('a raw range of a page becomes stretches of the paragraphs it reaches', () {
    final reading = ReadingText([
      [block('Intro.'), block('The sentence runs over', from: 6)],
      [block('the page break.')],
    ]);
    // "runs over" on page 1, raw 19 to 28.
    expect(reading.spans(1, 19, 28), [(paragraph: 1, from: 13, to: 22)]);
    // "the page" on page 2, in the second part of the joined paragraph.
    expect(reading.spans(2, 0, 8), [(paragraph: 1, from: 23, to: 31)]);
    // From "Intro" into the next block on the same page: two paragraphs.
    expect(reading.spans(1, 0, 9), [(paragraph: 0, from: 0, to: 6), (paragraph: 1, from: 0, to: 3)]);
    expect(reading.spans(3, 0, 5), isEmpty);
  });

  test('a stretch of a paragraph becomes a raw range on each page it covers', () {
    final reading = ReadingText([
      [block('Intro.'), block('The sentence runs over', from: 6)],
      [block('the page break.', from: 100)],
    ]);
    expect(reading.rawSelection(1, 13, 31), [(page: 1, range: (19, 28)), (page: 2, range: (100, 108))]);
    // The space that joins the two parts belongs to neither page.
    expect(reading.rawSelection(1, 22, 23), isEmpty);
  });

  test('a place on a page and a place in the paragraphs are found from each other', () {
    final reading = ReadingText([
      [block('Intro.'), block('The sentence runs over', from: 6)],
      [block('the page break.'), block('Next one.', from: 15)],
    ]);
    // Page 2 has 24 characters; halfway (12) is in "the page break." at 12, which is 23 + 12 in paragraph 1.
    expect(reading.placeOfPage(2, 0.5), (paragraph: 1, at: 35));
    expect(reading.pageOfPlace(1, 35), (page: 2, offset: 0.5));
    // The start of a page, and a place in a paragraph that starts on a page.
    expect(reading.placeOfPage(1, 0), (paragraph: 0, at: 0));
    expect(reading.pageOfPlace(2, 0), (page: 2, offset: 15 / 24));
    // A page with no text is shown where the next page with text starts.
    final gap = ReadingText([
      [block('One.')],
      [],
      [block('Three.')],
    ]);
    expect(gap.placeOfPage(2, 0.3), (paragraph: 1, at: 0));
    // A page not loaded yet has no place.
    expect(gap.placeOfPage(9, 0), isNull);
  });
}
