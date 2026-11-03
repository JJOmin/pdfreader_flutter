// The search in the notes sheet, over the comments only (PLAN 18.8).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/comment_search.dart';
import 'package:pdfreader/shared/notes.dart';

Annotation mark(String id, String comment, {String quote = 'quoted text'}) => Annotation(
  id: id,
  page: 1,
  start: 0,
  end: 1,
  text: quote,
  quote: quote,
  kind: MarkKind.highlight,
  color: HighlightColor.yellow,
  comment: comment,
  created: '2026-11-02T10:00:00Z',
);

void main() {
  final marks = [
    mark('a', 'The contract ends in March'),
    mark('b', '', quote: 'contract'),
    mark('c', 'Ask Anna about the Vertrag'),
  ];

  List<String> ids(String query) => [for (final m in searchComments(marks, query)) m.id];

  test('an empty search shows every mark', () {
    expect(ids(''), ['a', 'b', 'c']);
    expect(ids('   '), ['a', 'b', 'c']);
  });

  test('finds the comments that hold every word, in any order and any case', () {
    expect(ids('contract'), ['a']);
    expect(ids('MARCH contract'), ['a']);
    expect(ids('march anna'), isEmpty);
    expect(ids('vertr'), ['c']);
  });

  test('looks at the comment, not at the marked text', () {
    expect(ids('quoted'), isEmpty);
  });
}
