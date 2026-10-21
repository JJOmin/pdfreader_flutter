// Port of the desktop's tests/unit/notes-merge.test.ts: the same cases, so both sides merge alike.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/shared/notes_merge.dart';

Annotation mark(String id, {String comment = '', num? updated}) => Annotation(
  id: id,
  page: 1,
  start: 0,
  end: 5,
  text: 'quick',
  quote: 'quick',
  kind: MarkKind.highlight,
  color: HighlightColor.yellow,
  comment: comment,
  created: '2026-10-13T00:00:00.000Z',
  updated: updated,
);

NotesFile file(
  List<Annotation> annotations, {
  String notes = '',
  num? notesUpdated,
  List<Removal> removed = const [],
}) => NotesFile(notes: notes, annotations: annotations, notesUpdated: notesUpdated, removed: removed);

List<String> ids(NotesFile f) => (f.annotations.map((a) => a.id).toList())..sort();
String comment(NotesFile f, String id) => f.annotations.firstWhere((a) => a.id == id).comment;
List<(String, num)> removals(NotesFile f) => [for (final r in f.removed) (r.id, r.updated)];

void main() {
  group('stampChanges', () {
    test('stamps a new mark, keeps an unchanged one, and re-stamps an edited one', () {
      final before = file([mark('a', updated: 100), mark('b', updated: 100)]);
      final after = file([mark('a'), mark('b', comment: 'edited'), mark('c')]);
      final stamped = stampChanges(before, after, 500);
      // "a" came back without its stamp, as the sidebar rebuilds marks: it is the same mark.
      expect({for (final a in stamped.annotations) a.id: a.updated}, {'a': 100, 'b': 500, 'c': 500});
    });

    test('records a mark that is gone as removed, and keeps what was removed before', () {
      final before = file(
        [mark('a', updated: 100), mark('b', updated: 100)],
        removed: [const Removal('old', 50)],
      );
      final stamped = stampChanges(before, file([mark('b', updated: 100)]), 500);
      expect(removals(stamped), [('old', 50), ('a', 500)]);
    });

    test('stamps the general notes only when their text changed', () {
      final before = file([], notes: 'one', notesUpdated: 100);
      expect(stampChanges(before, file([], notes: 'one'), 500).notesUpdated, 100);
      expect(stampChanges(before, file([], notes: 'two'), 500).notesUpdated, 500);
    });

    test('starts from nothing, and leaves the fields out where there is nothing to say', () {
      final stamped = stampChanges(null, file([mark('a')]), 500);
      expect(stamped.annotations.single.updated, 500);
      expect(stamped.removed, isEmpty);
      // A file with no marks and no notes stays as the desktop always wrote it.
      expect(encodeNotes(stampChanges(null, file([]), 500)), encodeNotes(file([])));
    });
  });

  group('mergeNotes', () {
    test('keeps marks that are new on either side', () {
      expect(ids(mergeNotes(file([mark('a', updated: 1)]), file([mark('b', updated: 2)]))), ['a', 'b']);
    });

    test('takes the later edit of a mark changed on both sides, whichever side it is', () {
      final phone = file([mark('a', comment: 'phone', updated: 200)]);
      final desk = file([mark('a', comment: 'desktop', updated: 100)]);
      expect(comment(mergeNotes(phone, desk), 'a'), 'phone');
      expect(comment(mergeNotes(desk, phone), 'a'), 'phone');
    });

    test('keeps a deleted mark deleted, even where the other side still has it', () {
      final gone = file([], removed: [const Removal('a', 300)]);
      final still = file([mark('a', comment: 'edited before', updated: 200)]);
      for (final merged in [mergeNotes(gone, still), mergeNotes(still, gone)]) {
        expect(ids(merged), isEmpty);
        expect(removals(merged), [('a', 300)]);
      }
    });

    test('lets an edit made after the deletion bring the mark back', () {
      final merged = mergeNotes(
        file([], removed: [const Removal('a', 300)]),
        file([mark('a', comment: 'back', updated: 400)]),
      );
      expect(merged.annotations.map((a) => a.comment), ['back']);
      expect(merged.removed, isEmpty);
    });

    test('treats a mark without a stamp, as the desktop wrote before, as the oldest', () {
      expect(
        comment(mergeNotes(file([mark('a')]), file([mark('a', comment: 'newer', updated: 1)])), 'a'),
        'newer',
      );
      expect(mergeNotes(file([mark('a')]), file([], removed: [const Removal('a', 1)])).annotations, isEmpty);
    });

    test('takes the later general notes', () {
      final a = file([], notes: 'phone', notesUpdated: 200);
      final b = file([], notes: 'desktop', notesUpdated: 100);
      expect(mergeNotes(a, b).notes, 'phone');
      expect(mergeNotes(b, a).notes, 'phone');
      expect(mergeNotes(a, b).notesUpdated, 200);
    });

    test(
      'gives the same marks whichever side is merged into which, and changes nothing merged with itself',
      () {
        final a = file(
          [mark('a', updated: 5), mark('b', comment: 'x', updated: 9)],
          removed: [const Removal('z', 4)],
          notes: 'n',
          notesUpdated: 3,
        );
        final b = file(
          [mark('b', comment: 'y', updated: 8), mark('c', updated: 1)],
          removed: [const Removal('a', 6)],
        );
        final ab = mergeNotes(a, b);
        expect(ids(ab), ids(mergeNotes(b, a)));
        expect(comment(ab, 'b'), 'x');
        expect(ids(ab), ['b', 'c']);
        expect(encodeNotes(mergeNotes(ab, ab)), encodeNotes(ab));
      },
    );

    test('keeps this side’s order and puts the other side’s new marks after', () {
      final merged = mergeNotes(
        file([mark('z', updated: 1), mark('a', updated: 1)]),
        file([mark('m', updated: 1)]),
      );
      expect(merged.annotations.map((a) => a.id), ['z', 'a', 'm']);
    });
  });

  group('the new fields in a notes file', () {
    test('are read and written back, and a file without them is read as it was', () {
      final full = file(
        [mark('a', updated: 100)],
        notes: 'n',
        notesUpdated: 90,
        removed: [const Removal('gone', 80)],
      );
      expect(encodeNotes(parseNotes(jsonDecode(encodeNotes(full)))!), encodeNotes(full));
      final old = parseNotes({
        'version': 1,
        'notes': '',
        'annotations': [mark('a').toJson()],
      })!;
      expect(old.annotations.single.updated, isNull);
      expect(old.toJson().containsKey('removed'), isFalse);
    });

    test('drop entries that are not valid, instead of refusing the file', () {
      final parsed = parseNotes({
        'version': 1,
        'notes': '',
        'notesUpdated': 'soon',
        'annotations': [
          {...mark('a').toJson(), 'updated': 'x'},
        ],
        'removed': [
          {'id': 'ok', 'updated': 1},
          {'id': 3, 'updated': 1},
          {'id': 'nan', 'updated': double.nan},
          null,
        ],
      })!;
      expect(removals(parsed), [('ok', 1)]);
      expect(parsed.annotations.single.updated, isNull);
      expect(parsed.notesUpdated, isNull);
    });

    test('match the desktop byte for byte, in a file the desktop wrote with them', () {
      final golden = File('test/golden/notes-merged.json').readAsStringSync();
      expect(encodeNotes(parseNotes(jsonDecode(golden))!), golden);
    });
  });
}
