// Port of the desktop's tests/unit/notes.test.ts, plus the encoder's golden test and the
// whitespace-tolerant fallback of reanchor, which the desktop does not have.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/notes.dart';

Annotation annotation({
  String id = 'a1',
  int page = 2,
  int start = 4,
  int end = 9,
  String text = 'quick',
  String quote = 'quick',
  MarkKind kind = MarkKind.highlight,
  HighlightColor color = HighlightColor.yellow,
  String comment = '',
  String? via,
}) => Annotation(
  id: id,
  page: page,
  start: start,
  end: end,
  text: text,
  quote: quote,
  kind: kind,
  color: color,
  comment: comment,
  created: '2026-10-13T00:00:00.000Z',
  via: via,
);

void main() {
  group('parseNotes', () {
    test('accepts a valid file and rejects malformed ones', () {
      final file = NotesFile(
        notes: 'n',
        annotations: [annotation(kind: MarkKind.underline)],
      );
      expect(parseNotes(jsonDecode(encodeNotes(file)))?.toJson(), file.toJson());
      expect(parseNotes(null), isNull);
      expect(parseNotes({'version': 2, 'notes': '', 'annotations': <Object?>[]}), isNull);
      expect(
        parseNotes({
          'version': 1,
          'notes': '',
          'annotations': [
            {'id': 1},
          ],
        }),
        isNull,
      );
      for (final bad in [
        {'color': 'pink'},
        {'kind': 'circle'},
      ]) {
        expect(
          parseNotes({
            'version': 1,
            'notes': '',
            'annotations': [
              {...annotation().toJson(), ...bad},
            ],
          }),
          isNull,
        );
      }
    });

    test('reads files written before marks had a kind and a readable quote', () {
      final old = {
        'id': 'a1',
        'page': 2,
        'start': 4,
        'end': 9,
        'text': 'qu-ick',
        'color': 'green',
        'comment': 'c',
      };
      final parsed = parseNotes({
        'version': 1,
        'notes': '',
        'annotations': [old],
      })!.annotations.first;
      expect(parsed.kind, MarkKind.highlight);
      expect(parsed.quote, 'qu-ick');
    });
  });

  group('reanchor', () {
    test('keeps, moves or drops an annotation depending on the page text', () {
      expect(reanchor(annotation(), 'The quick fox')?.toJson(), annotation().toJson());
      final moved = reanchor(annotation(), 'A very quick fox')!;
      expect((moved.start, moved.end), (7, 12));
      expect(reanchor(annotation(), 'Nothing here'), isNull);
    });

    test('finds text again where the page has other whitespace, as between PDF.js and PDFium', () {
      // The desktop's raw string has no space at a line end; PDFium's has one inserted.
      final mark = annotation(text: 'wastrained', start: 0, end: 10);
      final moved = reanchor(mark, 'it was trained twice')!;
      expect((moved.start, moved.end), (3, 14));
      expect(moved.text, 'was trained');
      // And the other way round.
      final spaced = annotation(text: 'was trained', start: 0, end: 11);
      final back = reanchor(spaced, 'it wastrained twice')!;
      expect(back.text, 'wastrained');
      expect(reanchor(spaced, 'it was not trained'), isNull);
    });

    test('prefers an exact match, wherever it is', () {
      final mark = annotation(text: 'a b', start: 0, end: 3);
      expect(reanchor(mark, 'ab a b')!.start, 3);
    });
  });

  group('toMarkdown', () {
    test('groups marks by page in reading order and shows the readable quote', () {
      final markdown = toMarkdown(
        'paper.pdf',
        NotesFile(
          notes: 'Overall solid.',
          annotations: [
            annotation(id: 'b', page: 3, text: 'la-terclaim', quote: 'later  claim', comment: 'Check this.'),
            annotation(id: 'c', page: 3, start: 50, quote: 'wrong', kind: MarkKind.strike),
            annotation(id: 'a', page: 1, quote: 'first claim'),
          ],
        ),
      );
      expect(
        markdown,
        [
          '# Notes on paper.pdf',
          '',
          'Overall solid.',
          '',
          '## Page 1',
          '',
          '> first claim',
          '',
          '## Page 3',
          '',
          '> later claim',
          '',
          'Check this.',
          '',
          '> ~~wrong~~',
          '',
        ].join('\n'),
      );
    });
  });

  group('how a comment was made (via)', () {
    NotesFile read(Map<String, Object?> over) => parseNotes({
      'version': 1,
      'notes': '',
      'annotations': [
        {...annotation().toJson(), ...over},
      ],
    })!;

    test('is read, and written between created and updated, where the desktop writes it', () {
      final mark = read({'via': 'speech', 'updated': 5, 'comment': 'spoken'}).annotations.single;
      expect(mark.via, 'speech');
      expect(mark.toJson().keys.toList().sublist(9), ['created', 'via', 'updated']);
    });

    test('is left out of a mark that has none, so that a file written before reads and writes as it did', () {
      expect(read({}).annotations.single.toJson().containsKey('via'), isFalse);
    });

    test('ignores a value this version does not know instead of refusing the file', () {
      expect(read({'via': 'telepathy'}).annotations.single.via, isNull);
      expect(read({'via': 3}).annotations.single.via, isNull);
    });

    test('stays with a mark when its comment is edited or its place is found again', () {
      final spoken = annotation(comment: 'spoken', via: 'speech');
      expect(spoken.copyWith(comment: 'edited').via, 'speech');
      expect(spoken.copyWith(start: 10, end: 15).via, 'speech');
      expect(spoken.unstamped.via, 'speech');
    });

    test('is the desktop’s file, byte for byte', () {
      final golden = File('test/golden/notes-via.json').readAsStringSync();
      expect(encodeNotes(parseNotes(jsonDecode(golden))!), golden);
    });
  });

  group('markBadge', () {
    test('shows nothing for a mark without a comment, however it was made', () {
      expect(markBadge(annotation()), isNull);
      expect(markBadge(annotation(comment: '  \n ')), isNull);
      expect(markBadge(annotation(via: 'speech')), isNull);
    });

    test('shows a note for a written comment and a microphone for a spoken one', () {
      expect(markBadge(annotation(comment: 'typed')), NoteBadge.note);
      expect(markBadge(annotation(comment: 'spoken', via: 'speech')), NoteBadge.speech);
    });
  });

  group('encodeNotes', () {
    test('writes byte for byte what the desktop writes: JSON.stringify(notes, null, 2)', () {
      for (final name in ['notes', 'notes-empty']) {
        final golden = File('test/golden/$name.json').readAsStringSync();
        final parsed = parseNotes(jsonDecode(golden))!;
        expect(encodeNotes(parsed), golden, reason: name);
      }
    });
  });

  test('isoNow writes a JavaScript toISOString, with milliseconds and a Z', () {
    expect(isoNow(DateTime.utc(2026, 10, 13, 8, 30, 0, 123, 456)), '2026-10-13T08:30:00.123Z');
    expect(isoNow(DateTime.utc(2026, 10, 13)), '2026-10-13T00:00:00.000Z');
  });

  test('newId is a version 4 UUID, different each time', () {
    final id = newId();
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(newId(), isNot(id));
  });
}
