import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/marks.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/shared/pdfium_text.dart';

Annotation mark(String id, int start, int end, {String text = 'x', int page = 1}) => Annotation(
  id: id,
  page: page,
  start: start,
  end: end,
  text: text,
  quote: text,
  kind: MarkKind.highlight,
  color: HighlightColor.yellow,
  comment: '',
  created: '',
);

void main() {
  group('rawRangeFromBoxes', () {
    // Seven raw offsets from PDFium chars 0, 1, 2, 4, 5, 6 and 7: the CR LF at chars 3 and 8 is
    // dropped from the raw string. Each glyph has a box of its own, 10 wide, along one line.
    final charIndex = [0, 1, 2, 4, 5, 6, 7];
    CharBox box(int n) => (left: n * 10.0, bottom: 0, right: n * 10.0 + 8, top: 12);
    final rawBoxes = [for (var i = 0; i < 10; i++) box(i)];

    test('maps the boxes of a selection to the raw offsets of the chars they belong to', () {
      expect(rawRangeFromBoxes([box(1), box(2)], rawBoxes, charIndex), (1, 3));
      expect(rawRangeFromBoxes([for (var i = 0; i < 10; i++) box(i)], rawBoxes, charIndex), (0, 7));
    });

    test(
      'does not need the selection in the raw order or numbered the same, as with pdfrx reading order',
      () {
        // pdfrx lays the same glyphs out in its own text, so only the boxes tell which they are.
        expect(rawRangeFromBoxes([box(5), box(4)], rawBoxes, charIndex), (3, 5));
      },
    );

    test('tolerates the taller boxes pdfrx gives a glyph, and tells the same x on another line apart', () {
      // pdfrx sizes each box to its line; only the left and right edges stay those of the glyph.
      CharBox tall(CharBox b) => (left: b.left, bottom: b.bottom - 3, right: b.right, top: b.top + 2);
      expect(rawRangeFromBoxes([tall(box(1)), tall(box(2))], rawBoxes, charIndex), (1, 3));
      // A glyph at the same x on the line above is a different char.
      CharBox above(int n) => (left: n * 10.0, bottom: 100, right: n * 10.0 + 8, top: 112);
      final twoLines = [...rawBoxes, above(1)];
      expect(rawRangeFromBoxes([tall(above(1))], twoLines, [...charIndex, 10]), (7, 8));
      expect(rawRangeFromBoxes([tall(box(1))], twoLines, [...charIndex, 10]), (1, 2));
    });

    test('ignores boxes that are empty, and ones that are not on the page', () {
      const empty = (left: 5.0, bottom: 5.0, right: 5.0, top: 5.0);
      expect(rawRangeFromBoxes([empty, box(1), box(2)], rawBoxes, charIndex), (1, 3));
      expect(
        rawRangeFromBoxes([box(1), (left: 900.0, bottom: 0.0, right: 908.0, top: 12.0)], rawBoxes, charIndex),
        (1, 2),
      );
    });

    test('is null when nothing in the selection is raw text', () {
      expect(rawRangeFromBoxes(const [], rawBoxes, charIndex), isNull);
      expect(rawRangeFromBoxes([box(3)], rawBoxes, charIndex), isNull);
      expect(
        rawRangeFromBoxes([(left: 900.0, bottom: 0.0, right: 908.0, top: 12.0)], rawBoxes, charIndex),
        isNull,
      );
    });

    test('takes both units of a character outside the basic plane', () {
      // A surrogate pair is two raw offsets that share one char.
      expect(rawRangeFromBoxes([box(1)], rawBoxes, [0, 1, 1, 2]), (1, 3));
    });
  });

  group('newMark', () {
    // "A new language representa-" + "tion model": the raw string, and the readable text beside it.
    const raw = 'A new language representa-tion model';
    // The hyphen at raw offset 25 has no readable character.
    final blocks = [
      Block('A new language representation model', [
        for (var i = 0; i < raw.length; i++)
          if (i != 25) i,
      ], heading: false),
    ];

    test('keeps the raw slice, and the readable quote with the hyphenation undone', () {
      final m = newMark(
        page: 2,
        start: 15,
        end: raw.length,
        raw: raw,
        blocks: blocks,
        kind: MarkKind.underline,
        color: HighlightColor.green,
        id: 'id1',
        created: '2026-10-21T00:00:00.000Z',
      )!;
      expect(m.text, 'representa-tion model');
      expect(m.quote, 'representation model');
      expect(m.page, 2);
      expect((m.kind, m.color, m.comment, m.id), (MarkKind.underline, HighlightColor.green, '', 'id1'));
    });

    test('is null for a selection that holds no letters', () {
      for (final range in [(1, 2), (3, 3), (0, 0)]) {
        expect(
          newMark(
            page: 1,
            start: range.$1,
            end: range.$2,
            raw: raw,
            blocks: blocks,
            kind: MarkKind.highlight,
            color: HighlightColor.yellow,
            id: 'x',
            created: '',
          ),
          isNull,
          reason: '$range',
        );
      }
    });
  });

  group('anchorMarks', () {
    test('keeps what fits, moves what has shifted, and drops what is gone', () {
      final anchored = anchorMarks(
        [
          mark('keep', 0, 3, text: 'abc'),
          mark('move', 0, 3, text: 'xyz'),
          mark('gone', 0, 3, text: 'nope'),
          mark('other', 0, 3, text: 'abc', page: 2),
        ],
        {1: 'abc 12 xyz', 2: 'abc'},
      );
      expect(anchored.keys, containsAll(['keep', 'move', 'other']));
      expect(anchored.keys, isNot(contains('gone')));
      expect((anchored['move']!.start, anchored['move']!.end), (7, 10));
    });

    test('drops a mark on a page that has no text', () {
      expect(anchorMarks([mark('a', 0, 1)], const {}), isEmpty);
    });
  });

  group('markAt', () {
    test('finds the mark covering a raw offset, the shortest where several do', () {
      final marks = [mark('wide', 0, 20), mark('narrow', 5, 8)];
      expect(markAt(marks, 1, 6)?.id, 'narrow');
      expect(markAt(marks, 1, 1)?.id, 'wide');
      expect(markAt(marks, 1, 20), isNull);
      expect(markAt(marks, 2, 6), isNull);
    });
  });
}
