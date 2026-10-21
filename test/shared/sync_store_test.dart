// Port of the desktop's tests/unit/sync-store.test.ts, with golden files written by the desktop's own
// seal and packAudio (test/golden/store.json), so that the two programs agree on every byte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync_store.dart';

final keyA = 'a' * 40;
final keyB = 'b' * 40;
Uint8List bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  final golden = jsonDecode(File('test/golden/store.json').readAsStringSync()) as Map<String, Object?>;
  Uint8List b64(String key) => base64Decode(golden[key]! as String);

  group('assertPath', () {
    test('accepts the names the library uses', () {
      for (final path in [RemotePath.manifest('c' * 64), RemotePath.pack('c' * 64, 12)]) {
        expect(() => assertPath(path), returnsNormally);
      }
    });

    test('refuses anything else', () {
      for (final path in ['../x', 'a/../b', '/abs', 'a//b', 'a b', r'a\b', '', '.', 'a/..', 'ä']) {
        expect(() => assertPath(path), throwsArgumentError, reason: path);
      }
    });
  });

  group('packAudio', () {
    test('returns the files it was given, in order', () {
      final files = [
        PackedFile(keyA, bytes([1, 2, 3])),
        PackedFile(keyB, bytes([])),
        PackedFile(keyA, bytes([9])),
      ];
      final back = unpackAudio(packAudio(files))!;
      // As text: a record holding a list would compare by identity.
      expect([for (final f in back) '${f.key} ${f.bytes}'], [for (final f in files) '${f.key} ${f.bytes}']);
    });

    test('packs no files', () => expect(unpackAudio(packAudio([])), isEmpty));

    test('reads a pack that is a view into a larger buffer', () {
      final pack = packAudio([
        PackedFile(keyA, bytes([5, 6])),
      ]);
      final padded = Uint8List(pack.length + 3)..setRange(2, 2 + pack.length, pack);
      expect(unpackAudio(Uint8List.sublistView(padded, 2, 2 + pack.length))!.single.bytes, [5, 6]);
    });

    test('refuses a pack that is cut short, has extra bytes or a bad header', () {
      final pack = packAudio([
        PackedFile(keyA, bytes([1, 2, 3])),
      ]);
      expect(unpackAudio(Uint8List.sublistView(pack, 0, pack.length - 1)), isNull);
      expect(unpackAudio(bytes([...pack, 0])), isNull);
      expect(unpackAudio(bytes([0, 0, 0, 9, 1])), isNull);
      expect(unpackAudio(bytes([1])), isNull);
      expect(
        unpackAudio(
          packAudio([
            PackedFile('not-a-key', bytes([1])),
          ]),
        ),
        isNull,
      );
    });

    test('is the pack the desktop wrote, byte for byte, and reads it', () {
      final files = [
        for (final f in golden['packFiles']! as List)
          PackedFile((f as Map)['key']! as String, base64Decode(f['base64']! as String)),
      ];
      expect(packAudio(files), b64('packBase64'));
      final back = unpackAudio(b64('packBase64'))!;
      expect(
        [for (final f in back) (f.key, f.bytes.length)],
        [for (final f in files) (f.key, f.bytes.length)],
      );
      expect(back[2].bytes, files[2].bytes);
    });
  });

  group('seal and unseal', () {
    final key = newSyncKey();
    final data = Uint8List.fromList(utf8.encode('Sentence one. Sentence two.'));

    test('returns what was sealed, and hides it', () async {
      final sealed = await seal(key, 'a/b.json', data);
      expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('Sentence')));
      expect(await unseal(key, 'a/b.json', sealed), data);
    });

    test('seals the same data differently each time', () async {
      expect(await seal(key, 'a', data), isNot(await seal(key, 'a', data)));
    });

    test('seals nothing', () async {
      expect(await unseal(key, 'a', await seal(key, 'a', Uint8List(0))), isEmpty);
    });

    test('refuses a wrong key, another path, a changed file and a file that is not sealed', () async {
      final sealed = await seal(key, 'a/b.json', data);
      await expectLater(unseal(newSyncKey(), 'a/b.json', sealed), throwsA(isA<SealException>()));
      await expectLater(unseal(key, 'a/c.json', sealed), throwsA(isA<SealException>()));
      final changed = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
      await expectLater(
        unseal(key, 'a/b.json', changed),
        throwsA(isA<SealException>().having((e) => e.message, 'message', contains('sync key is wrong'))),
      );
      await expectLater(
        unseal(key, 'a/b.json', data),
        throwsA(isA<SealException>().having((e) => e.message, 'message', contains('not a file of this app'))),
      );
    });

    test('opens a file the desktop sealed', () async {
      final key = parseSyncKey(golden['key']! as String)!;
      expect(await unseal(key, golden['path']! as String, b64('sealedBase64')), b64('plainBase64'));
      // And not under the name of another file.
      await expectLater(unseal(key, 'abc/pages/4.json', b64('sealedBase64')), throwsA(isA<SealException>()));
    });

    test('writes the very bytes the desktop writes, given the same IV', () async {
      final key = parseSyncKey(golden['key']! as String)!;
      final iv = Uint8List.fromList([
        for (var i = 0; i < 12; i++)
          int.parse((golden['iv']! as String).substring(i * 2, i * 2 + 2), radix: 16),
      ]);
      expect(await seal(key, golden['path']! as String, b64('plainBase64'), iv: iv), b64('fixedBase64'));
    });
  });

  group('sync key text', () {
    test('goes round trip, in groups of eight digits', () {
      final key = newSyncKey();
      final text = formatSyncKey(key);
      expect(text, matches(RegExp(r'^([0-9a-f]{8}-){7}[0-9a-f]{8}$')));
      expect(parseSyncKey(text), key);
    });

    test('reads a key pasted with spaces, capitals or no dashes', () {
      final key = newSyncKey();
      expect(parseSyncKey(' ${formatSyncKey(key).replaceAll('-', '').toUpperCase()}\n'), key);
    });

    test('refuses text that is not a key', () {
      for (final text in ['', 'abc', 'g' * 64, 'a' * 65]) {
        expect(parseSyncKey(text), isNull, reason: text);
      }
    });

    test('makes keys of 32 random bytes', () {
      expect(newSyncKey(), hasLength(32));
      expect(newSyncKey(), isNot(newSyncKey()));
    });
  });

  group('parseServerUrl', () {
    test('assumes https when no scheme is typed', () {
      expect(parseServerUrl('cloud.example.com')?.toString(), 'https://cloud.example.com/');
      expect(
        parseServerUrl(' https://cloud.example.com/nextcloud ')?.toString(),
        'https://cloud.example.com/nextcloud',
      );
    });

    test('accepts plain http only on the local network', () {
      for (final ok in [
        'http://192.168.1.5',
        'http://10.0.0.2:8080',
        'http://truenas.local',
        'http://localhost:8080',
      ]) {
        expect(parseServerUrl(ok), isNotNull, reason: ok);
      }
      for (final bad in ['http://cloud.example.com', 'http://8.8.8.8', 'http://192.168.1.5.evil.com']) {
        expect(parseServerUrl(bad), isNull, reason: bad);
      }
    });

    test('refuses addresses with a password, a query or another scheme', () {
      for (final bad in [
        '',
        '  ',
        'https://user:pw@cloud.example.com',
        'https://x.com/?a=1',
        'ftp://x.com',
        'file:///c',
      ]) {
        expect(parseServerUrl(bad), isNull, reason: bad);
      }
    });
  });
}
