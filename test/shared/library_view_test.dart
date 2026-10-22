import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/library_view.dart';
import 'package:pdfreader/shared/sync.dart';

Manifest doc(String id, String name, {num updated = 1, int bytes = 1000}) =>
    Manifest(docId: id * 64, name: name, pages: 2, sentences: 10, bytes: bytes, updated: updated);

void main() {
  final a = doc('a', 'Alpha.pdf');
  final b = doc('b', 'beta.pdf');
  final c = doc('c', 'Gamma.pdf');

  Map<String, DocState> states(List<LibraryEntry> entries) => {
    for (final e in entries) e.manifest.name: e.state,
  };

  test('says on this phone for a document that is here and current', () {
    expect(states(libraryEntries(local: [a], cloud: [a])), {'Alpha.pdf': DocState.onPhone});
  });

  test('says update available when the cloud has a newer preparation', () {
    final entries = libraryEntries(local: [a], cloud: [doc('a', 'Alpha.pdf', updated: 2)]);
    expect(entries.single.state, DocState.updateAvailable);
    expect(entries.single.manifest.updated, 2);
    expect(entries.single.local!.updated, 1);
  });

  test('says in the cloud for a document that is not here', () {
    final entries = libraryEntries(local: [], cloud: [a]);
    expect(entries.single.state, DocState.inCloud);
    expect(entries.single.onThisPhone, isFalse);
  });

  test('keeps a document that came another way and the cloud does not know as on this phone', () {
    expect(libraryEntries(local: [a], cloud: []).single.state, DocState.onPhone);
  });

  test('says downloading with the progress, for a new document and for an update', () {
    final fresh = libraryEntries(local: [], cloud: [a], downloading: {a.docId: 0.4});
    expect((fresh.single.state, fresh.single.progress), (DocState.downloading, 0.4));
    final update = libraryEntries(
      local: [a],
      cloud: [doc('a', 'Alpha.pdf', updated: 2)],
      downloading: {a.docId: null},
    );
    expect(
      (update.single.state, update.single.progress, update.single.onThisPhone),
      (DocState.downloading, null, true),
    );
  });

  test('lists each document once, by name without regard to case', () {
    final entries = libraryEntries(local: [c, a], cloud: [b, a]);
    expect([for (final e in entries) e.manifest.name], ['Alpha.pdf', 'beta.pdf', 'Gamma.pdf']);
  });

  test('filters to what is on the phone, or only in the cloud', () {
    final entries = libraryEntries(local: [a], cloud: [a, b]);
    expect(
      [for (final e in filterEntries(entries, LibraryFilter.all)) e.manifest.name],
      ['Alpha.pdf', 'beta.pdf'],
    );
    expect([for (final e in filterEntries(entries, LibraryFilter.onPhone)) e.manifest.name], ['Alpha.pdf']);
    expect([for (final e in filterEntries(entries, LibraryFilter.cloudOnly)) e.manifest.name], ['beta.pdf']);
  });

  test('adds up what is on the phone and not what is only in the cloud', () {
    final entries = libraryEntries(local: [doc('a', 'A', bytes: 3000)], cloud: [doc('b', 'B', bytes: 9000)]);
    expect(spaceUsed(entries), 3000);
  });

  test('writes sizes the way a person reads them', () {
    expect(formatBytes(0), '0 KB');
    expect(formatBytes(1500), '2 KB');
    expect(formatBytes(340 * 1024 * 1024), '340 MB');
    expect(formatBytes((1.2 * 1024 * 1024 * 1024).round()), '1.2 GB');
  });
}
