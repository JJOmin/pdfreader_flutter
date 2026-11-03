// PDFs opened from Files or another app, kept so that Home can open them again (PLAN 18.10).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/home_lists.dart';
import 'package:pdfreader/shared/kept_documents.dart';

String id(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  test('the document opened last comes first, and a document is kept once', () {
    var list = keepOpened(const [], id(1), 'a.pdf', 100).kept;
    list = keepOpened(list, id(2), 'b.pdf', 200).kept;
    list = keepOpened(list, id(1), 'a (renamed).pdf', 300).kept;
    expect([for (final d in list) d.name], ['a (renamed).pdf', 'b.pdf']);
    expect(list.first.opened, 300);
  });

  test('only the ones read last are kept, and the others are named for deleting', () {
    var list = const <KeptDocument>[];
    final dropped = <String>[];
    for (var n = 1; n <= 12; n++) {
      final result = keepOpened(list, id(n), '$n.pdf', n, limit: 10);
      list = result.kept;
      dropped.addAll(result.dropped);
    }
    expect(list, hasLength(10));
    expect(list.first.id, id(12));
    expect(dropped, [id(1), id(2)]);
  });

  test('is written and read back; an entry that is not ours is left out', () {
    final list = keepOpened(const [], id(7), 'seven.pdf', 7).kept;
    final back = parseKept(keptToJson(list));
    expect([for (final d in back) (d.id, d.name, d.opened)], [(id(7), 'seven.pdf', 7)]);
    expect(
      parseKept([
        {'id': '../../settings', 'name': 'x.pdf', 'opened': 1},
        {'id': id(3), 'name': 3, 'opened': 1},
        {'id': id(4), 'name': 'four.pdf', 'opened': 4},
        'nonsense',
      ]).map((d) => d.id),
      [id(4)],
    );
    expect(parseKept(null), isEmpty);
  });

  test('a kept document is remembered by its hash', () {
    expect(placeOfKept(id(5)), 'doc:${id(5)}');
    expect(keptIdOfPlace('doc:${id(5)}'), id(5));
    expect(keptIdOfPlace('library:${id(5)}'), isNull);
    expect(docIdOfPlace('doc:${id(5)}'), isNull);
  });
}
