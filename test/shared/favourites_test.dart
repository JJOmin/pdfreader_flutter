import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/favourites.dart';

typedef Doc = ({String docId, String name});

void main() {
  const vertraege = Folder(id: 'f1', name: 'Verträge', color: 0xFF3F51B5, notes: 'Arbeit', docs: ['a']);
  const papers = Folder(id: 'f2', name: 'Papers', color: 0xFF4CAF50, docs: ['b', 'a']);
  final favourites = Favourites(liked: {'c'}, folders: const [vertraege, papers]);
  const docs = <Doc>[
    (docId: 'a', name: 'Arbeitsvertrag.pdf'),
    (docId: 'b', name: 'attention.pdf'),
    (docId: 'c', name: 'Mietvertrag.pdf'),
    (docId: 'd', name: 'other.pdf'),
  ];

  List<String> ids(List<Doc> found) => [for (final d in found) d.docId];
  List<Doc> search({String query = '', String? folder, bool likedOnly = false}) => searchDocuments(
    docs,
    (d) => d.docId,
    (d) => d.name,
    favourites,
    query: query,
    folder: folder,
    likedOnly: likedOnly,
  );

  test('round-trips through JSON', () {
    final again = parseFavourites(favourites.toJson());
    expect(again.liked, {'c'});
    expect(
      [for (final f in again.folders) (f.id, f.name, f.color, f.notes, f.docs.join(','))],
      [('f1', 'Verträge', 0xFF3F51B5, 'Arbeit', 'a'), ('f2', 'Papers', 0xFF4CAF50, '', 'b,a')],
    );
  });

  test('reads a missing or broken file as empty', () {
    for (final json in [
      null,
      'x',
      {
        'liked': 3,
        'folders': [
          1,
          {'id': 'f'},
        ],
      },
    ]) {
      final f = parseFavourites(json);
      expect(f.liked, isEmpty);
      expect(f.folders, isEmpty);
    }
  });

  test('a like is toggled', () {
    expect(favourites.toggleLike('a').isLiked('a'), isTrue);
    expect(favourites.toggleLike('c').isLiked('c'), isFalse);
  });

  test('a folder is added, changed and removed', () {
    const more = Folder(id: 'f3', name: 'More', color: 0);
    expect([for (final f in favourites.putFolder(more).folders) f.id], ['f1', 'f2', 'f3']);
    final renamed = favourites.putFolder(vertraege.copyWith(name: 'Contracts'));
    expect([for (final f in renamed.folders) f.name], ['Contracts', 'Papers']);
    expect([for (final f in favourites.removeFolder('f1').folders) f.id], ['f2']);
  });

  test('a document is put in the folders chosen and taken out of the others', () {
    expect([for (final f in favourites.foldersOf('a')) f.id], ['f1', 'f2']);
    final moved = favourites.setFolders('a', {'f2'});
    expect([for (final f in moved.foldersOf('a')) f.id], ['f2']);
    expect(favourites.setFolders('d', {'f1'}).folders.first.docs, ['a', 'd']);
  });

  test('without a search, the liked documents and those in a folder are shown', () {
    expect(ids(search()), ['a', 'b', 'c']);
    expect(ids(search(likedOnly: true)), ['c']);
    expect(ids(search(folder: 'f2')), ['a', 'b']);
  });

  test('a search finds every document by its title or its folders, ignoring case', () {
    expect(ids(search(query: 'VERTRAG')), ['a', 'c']);
    expect(ids(search(query: 'verträge')), ['a']);
    expect(ids(search(query: 'other')), ['d']);
    expect(ids(search(query: 'pdf', folder: 'f1')), ['a']);
  });
}
