import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/shared/notes.dart';

final docId = 'a' * 64;

void main() {
  late Directory dir;
  late NotesStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('notes-store-');
    store = NotesStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('is empty for a document nobody has marked', () async {
    final file = await store.load(docId);
    expect(file.notes, '');
    expect(file.annotations, isEmpty);
  });

  test('writes the desktop’s format and reads it back', () async {
    final file = NotesFile(
      notes: 'General',
      annotations: [
        Annotation(
          id: 'a1',
          page: 1,
          start: 0,
          end: 3,
          text: 'abc',
          quote: 'abc',
          kind: MarkKind.strike,
          color: HighlightColor.red,
          comment: 'c',
          created: '2026-10-21T00:00:00.000Z',
        ),
      ],
    );
    await store.save(docId, file);
    expect(File('${dir.path}/$docId.json').readAsStringSync(), encodeNotes(file));
    expect((await store.load(docId)).annotations.single.comment, 'c');
  });

  test('treats a damaged file as empty instead of failing, and keeps it for a look', () async {
    File('${dir.path}/$docId.json').writeAsStringSync('{ not json');
    expect((await store.load(docId)).annotations, isEmpty);
    expect(File('${dir.path}/$docId.json').readAsStringSync(), '{ not json');
  });

  test('refuses an id that is not a document hash, so no path comes from outside', () async {
    expect(() => store.load('../../x'), throwsArgumentError);
    expect(() => store.save('x', emptyNotes()), throwsArgumentError);
  });

  test('leaves no half-written file behind', () async {
    await store.save(docId, emptyNotes());
    expect(dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last), ['$docId.json']);
  });
}
