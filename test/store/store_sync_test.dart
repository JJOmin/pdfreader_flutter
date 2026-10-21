// The phone's half of the store (ADR 3 section 1) against a store the desktop's own engine wrote
// (test/golden/store-folder: the prepared sample, a place and notes, sealed with a fixed key).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/notes_store.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfreader/shared/sync_store.dart';
import 'package:pdfreader/store/store_sync.dart';

import '../memory_store.dart';

const fixture = 'test/golden/store-folder';
final docId = File('$fixture/doc.txt').readAsStringSync();
final key = parseSyncKey(File('$fixture/key.txt').readAsStringSync())!;
const phone = 'e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0';
const desktop = 'dddddddddddddddddddddddddddddddd';

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  late Directory dir;
  late MemoryStore store;
  late Library library;
  late NotesStore notes;
  late StoreSync sync;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('store-sync-');
    store = MemoryStore.fromFolder(fixture);
    library = Library(Directory('${dir.path}/library'));
    notes = NotesStore(Directory('${dir.path}/notes'));
    sync = StoreSync(store, key, library, notes, phone);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('documents', () {
    test('lists what the desktop sent, by the manifest it sealed', () async {
      final listed = await sync.documents();
      expect(listed.documents, hasLength(1));
      final m = listed.documents.single.manifest;
      expect((m.docId, m.name, m.pages, m.sentences), (docId, 'sample.pdf', 2, 17));
      expect(listed.unreadable, 0);
    });

    test('counts a document this key cannot open, instead of listing or failing', () async {
      final other = StoreSync(store, newSyncKey(), library, notes, phone);
      final listed = await other.documents();
      expect(listed.documents, isEmpty);
      expect(listed.unreadable, 1);
    });

    test('is empty for a store with nothing in it', () async {
      final listed = await StoreSync(MemoryStore(), key, library, notes, phone).documents();
      expect(listed.documents, isEmpty);
      expect(listed.unreadable, 0);
    });
  });

  group('download', () {
    test('writes the library as the Wi-Fi sync does, the manifest last, and checks the PDF', () async {
      final remote = (await sync.documents()).documents.single;
      final progress = <String>[];
      await sync.download(remote, (p) => progress.add('${p.done}/${p.total}'));
      final local = (await library.read(Directory('${library.root.path}/$docId')))!;
      expect(local.manifest.name, 'sample.pdf');
      expect(sha256.convert(await local.pdf.readAsBytes()).toString(), docId);
      for (var page = 1; page <= 2; page++) {
        final index = (await local.index(page))!;
        for (final s in index.sentences) {
          final audio = File(local.audioPath(s.key));
          expect(audio.existsSync(), isTrue, reason: s.key);
          // An Ogg Opus file, as the desktop's engine encoded it.
          expect(String.fromCharCodes(audio.readAsBytesSync().take(4)), 'OggS');
        }
      }
      expect(progress, isNotEmpty);
      expect(progress.last, startsWith('${remote.manifest.pages}/'));
    });

    test('reads sentences as the Wi-Fi sync does: the same files, so the same reader', () async {
      final remote = (await sync.documents()).documents.single;
      await sync.download(remote, (_) {});
      final audio = Directory('${library.root.path}/$docId/audio').listSync().whereType<File>();
      expect(audio, hasLength(17));
    });

    test('fetches nothing again when the document is current, and only the manifest to know', () async {
      final remote = (await sync.documents()).documents.single;
      await sync.download(remote, (_) {});
      store.gets.clear();
      final again = (await sync.documents()).documents.single;
      expect(await sync.download(again, (_) {}), isFalse);
      expect(store.gets.where((p) => p.contains('/audio/') || p.endsWith('.pdf')), isEmpty);
    });

    test('leaves no document behind when a file was changed in the store', () async {
      final remote = (await sync.documents()).documents.single;
      final pack = RemotePath.pack(docId, 2);
      store.files[pack] = Uint8List.fromList(store.files[pack]!)..[store.files[pack]!.length - 1] ^= 1;
      await expectLater(sync.download(remote, (_) {}), throwsA(isA<SealException>()));
      expect(await library.read(Directory('${library.root.path}/$docId')), isNull);
    });

    test('refuses a pack that lacks a sentence the page needs', () async {
      final remote = (await sync.documents()).documents.single;
      final path = RemotePath.pack(docId, 1);
      final pack = unpackAudio(await unseal(key, path, store.files[path]!))!;
      store.files[path] = await seal(key, path, packAudio(pack.take(pack.length - 1).toList()));
      await expectLater(sync.download(remote, (_) {}), throwsA(isA<StoreSyncException>()));
      expect(await library.read(Directory('${library.root.path}/$docId')), isNull);
    });

    test('refuses a PDF that is not the one the document is named for', () async {
      final remote = (await sync.documents()).documents.single;
      final path = RemotePath.pdf(docId);
      store.files[path] = await seal(key, path, text('%PDF-1.7 another file'));
      await expectLater(sync.download(remote, (_) {}), throwsA(isA<StoreSyncException>()));
    });
  });

  group('places', () {
    Future<void> downloaded() async => sync.download((await sync.documents()).documents.single, (_) {});

    test('brings the desktop’s place down, and nobody else’s lies', () async {
      await downloaded();
      expect(await sync.exchangeStates(docId), 0);
      final file = File('${library.root.path}/$docId/state/$desktop.json');
      final state = parseDeviceState(jsonDecode(file.readAsStringSync()))!;
      expect((state.name, state.page, state.offset), ('Leos_PC', 2, 0.25));
    });

    test('sends this phone’s own place up under its own name', () async {
      await downloaded();
      final own = File('${library.root.path}/$docId/state/$phone.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(
            DeviceState(
              device: phone,
              name: 'Galaxy',
              updated: 5,
              page: 1,
              offset: 0,
              sentence: null,
            ).toJson(),
          ),
        );
      await sync.exchangeStates(docId);
      expect(store.puts, contains(RemotePath.state(docId, phone)));
      final back = await unseal(
        key,
        RemotePath.state(docId, phone),
        store.files[RemotePath.state(docId, phone)]!,
      );
      expect(parseDeviceState(jsonDecode(utf8.decode(back)))!.name, 'Galaxy');
      own.deleteSync();
    });

    test('counts places it cannot read and does not write them', () async {
      await downloaded();
      // A valid state under another device's name: a state belongs to the device it carries.
      final liar = RemotePath.state(docId, 'c' * 32);
      final valid = DeviceState(device: desktop, name: 'x', updated: 1, page: 1, offset: 0, sentence: null);
      store.files[liar] = await seal(key, liar, text(jsonEncode(valid.toJson())));
      final wrongKey = RemotePath.state(docId, 'b' * 32);
      store.files[wrongKey] = await seal(newSyncKey(), wrongKey, text('{}'));
      expect(await sync.exchangeStates(docId), 2);
      expect(File('${library.root.path}/$docId/state/${'c' * 32}.json').existsSync(), isFalse);
    });
  });

  group('notes', () {
    Annotation mark(String id, {String comment = '', num? updated}) => Annotation(
      id: id,
      page: 1,
      start: 33,
      end: 39,
      text: 'Dieser',
      quote: 'Dieser',
      kind: MarkKind.highlight,
      color: HighlightColor.green,
      comment: comment,
      created: '2026-10-21T00:00:00.000Z',
      updated: updated,
    );

    test('reads the desktop’s marks, comments, general notes and removals, byte for byte its file', () async {
      expect(await sync.exchangeNotes(docId), (changed: true, unreadable: 0));
      final got = await notes.load(docId);
      expect(got.notes, 'General notes from the desktop, ä ö ü');
      expect((got.annotations.single.id, got.annotations.single.comment), ('a1', 'desktop comment'));
      expect(got.removed.single.id, 'gone');
    });

    test('merges this phone’s marks into the store’s, and sends the merge back', () async {
      await notes.save(
        docId,
        NotesFile(
          notes: '',
          annotations: [mark('p1', comment: 'phone', updated: 1792500000500)],
        ),
      );
      await sync.exchangeNotes(docId);
      final path = RemotePath.notes(docId);
      final remote = parseNotes(jsonDecode(utf8.decode(await unseal(key, path, store.files[path]!))))!;
      expect(remote.annotations.map((a) => a.id).toList()..sort(), ['a1', 'p1']);
      expect(encodeNotes(await notes.load(docId)), encodeNotes(remote));
    });

    test('keeps a deletion made on the phone, so the desktop loses the mark too', () async {
      await sync.exchangeNotes(docId);
      final have = await notes.load(docId);
      await notes.save(
        docId,
        NotesFile(
          notes: have.notes,
          annotations: const [],
          notesUpdated: have.notesUpdated,
          removed: [...have.removed, const Removal('a1', 1792500009000)],
        ),
      );
      await sync.exchangeNotes(docId);
      final path = RemotePath.notes(docId);
      final remote = parseNotes(jsonDecode(utf8.decode(await unseal(key, path, store.files[path]!))))!;
      expect(remote.annotations, isEmpty);
      expect(remote.removed.map((r) => r.id).toSet(), {'gone', 'a1'});
    });

    test(
      'a mark added after the first exchange only goes up: the phone’s notes do not change again',
      () async {
        // The store already holds several marks from other runs, as a used store does.
        final path = RemotePath.notes(docId);
        final remote = parseNotes(jsonDecode(utf8.decode(await unseal(key, path, store.files[path]!))))!;
        final more = NotesFile(
          notes: remote.notes,
          annotations: [
            ...remote.annotations,
            mark('r2', updated: 1792500000600),
            mark('r3', updated: 1792500000700),
          ],
          notesUpdated: remote.notesUpdated,
          removed: remote.removed,
        );
        store.files[path] = await seal(key, path, text(encodeNotes(more)));
        expect((await sync.exchangeNotes(docId)).changed, isTrue);
        final have = await notes.load(docId);
        await notes.save(
          docId,
          NotesFile(
            notes: have.notes,
            annotations: [...have.annotations, mark('p9', updated: 1792500009000)],
            notesUpdated: have.notesUpdated,
            // As the app does: a mark added later does not drop what was removed before.
            removed: have.removed,
          ),
        );
        final again = await sync.exchangeNotes(docId);
        expect(again.changed, isFalse);
        final back = parseNotes(jsonDecode(utf8.decode(await unseal(key, path, store.files[path]!))))!;
        expect(back.annotations.map((a) => a.id), contains('p9'));
      },
    );

    test('sends nothing when both sides already agree', () async {
      await sync.exchangeNotes(docId);
      store.puts.clear();
      expect(await sync.exchangeNotes(docId), (changed: false, unreadable: 0));
      expect(store.puts, isEmpty);
    });

    test('counts notes it cannot read, and leaves both sides alone', () async {
      await notes.save(docId, NotesFile(notes: '', annotations: [mark('p1', updated: 1)]));
      final path = RemotePath.notes(docId);
      final before = store.files[path] = await seal(newSyncKey(), path, text('{}'));
      expect(await sync.exchangeNotes(docId), (changed: false, unreadable: 1));
      expect(store.files[path], before);
      expect((await notes.load(docId)).annotations.single.id, 'p1');
    });

    test('writes nothing where there are no notes on either side', () async {
      store.files.remove(RemotePath.notes(docId));
      expect(await sync.exchangeNotes(docId), (changed: false, unreadable: 0));
      expect(store.puts, isEmpty);
    });
  });

  group('sync', () {
    test('updates what is on the phone, and does not download what is not', () async {
      // The document is in the store but not downloaded: sync leaves the choice to the user.
      final first = await sync.sync((_) {});
      expect((first.updated, first.notesChanged), (0, 0));
      expect(await library.read(Directory('${library.root.path}/$docId')), isNull);

      await sync.download((await sync.documents()).documents.single, (_) {});
      final second = await sync.sync((_) {});
      expect(second.notesChanged, 1);
      expect((await notes.load(docId)).annotations.single.id, 'a1');
      expect(File('${library.root.path}/$docId/state/$desktop.json').existsSync(), isTrue);
    });

    test('downloads a document again when the desktop prepared it again', () async {
      await sync.download((await sync.documents()).documents.single, (_) {});
      final path = RemotePath.manifest(docId);
      final manifest =
          jsonDecode(utf8.decode(await unseal(key, path, store.files[path]!))) as Map<String, Object?>;
      manifest['updated'] = (manifest['updated']! as num) + 1;
      store.files[path] = await seal(key, path, text(jsonEncode(manifest)));
      final summary = await sync.sync((_) {});
      expect(summary.updated, 1);
      expect(
        (await library.read(Directory('${library.root.path}/$docId')))!.manifest.updated,
        manifest['updated'],
      );
    });
  });
}
