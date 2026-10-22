// Port of the desktop's tests/unit/phone-library.test.ts, the parts the phone reads. The desktop
// alone builds indexes, so its libraryTimings, parsePreparedPage and buildPageIndex are not here.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfreader/shared/types.dart';

Utterance utterance(List<String> words) => Utterance(
  page: 1,
  text: words.join(' '),
  spoken: words.join(' '),
  lang: Lang.en,
  role: Role.main,
  words: [for (final w in words) Word(w, const [])],
  ranges: const [],
);

final key = 'a' * 40;
final hash = 'b' * 64;
final device = 'c' * 32;

void main() {
  group('pageWords', () {
    test('is every word of every sentence, in order', () {
      expect(
        pageWords([
          utterance(['I.', 'INTRODUCTION']),
          utterance(['Tutorials', 'help']),
        ]),
        ['I.', 'INTRODUCTION', 'Tutorials', 'help'],
      );
    });

    test('does not depend on where the sentences break', () {
      // PDF.js and PDFium can break a heading off differently; the words must not change.
      final joined = pageWords([
        utterance(['INTRODUCTION', 'Tutorials', 'help']),
      ]);
      final split = pageWords([
        utterance(['INTRODUCTION']),
        utterance(['Tutorials', 'help']),
      ]);
      expect(split, joined);
    });

    test('applies NFKC, so a ligature and its letters are one word', () {
      expect(
        pageWords([
          utterance(['ﬁnd', 'Ａ']),
        ]),
        ['find', 'A'],
      );
    });
  });

  group('sentenceStarts', () {
    test('gives the index of each sentence’s first word among the page’s words', () {
      expect(
        sentenceStarts([
          utterance(['a', 'b']),
          utterance(['c']),
          utterance(['d', 'e', 'f']),
        ]),
        [0, 2, 3],
      );
      expect(sentenceStarts([]), <int>[]);
    });
  });

  group('syncText', () {
    test('folds whitespace, including line breaks, and trims', () {
      expect(syncText('  Tutorials break\ndown \t complex topics. '), 'Tutorials break down complex topics.');
    });

    test('applies NFKC', () {
      expect(syncText('Eine ﬂache Ａrt'), 'Eine flache Art');
    });
  });

  group('syncKey and wordsHash', () {
    // Values from Node's crypto on the desktop, so both sides name the same files.
    test('are SHA-256 in hex, the key its first 40 digits', () {
      expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(syncKey(' abc\n'), 'ba7816bf8f01cfea414140de5dae2223b00361a3');
      expect(wordsHash(['a', 'bc']), sha256Hex('a bc'));
    });
  });

  Map<String, Object?> sentence([Map<String, Object?> over = const {}]) => {
    'key': key,
    'lang': 'en',
    'ms': 1000,
    'from': 0,
    'words': [
      [0, 400],
      [400, 1000],
    ],
    ...over,
  };

  group('parsePageIndex', () {
    Map<String, Object?> index([Map<String, Object?> over = const {}]) => {
      'wordCount': 5,
      'wordsHash': hash,
      'sentences': [
        sentence(),
        sentence({
          'from': 2,
          'words': [
            [0, 100],
            [100, 200],
            [250, 300],
          ],
        }),
      ],
      ...over,
    };

    test('accepts a valid index as it is', () {
      expect(parsePageIndex(index())?.toJson(), index());
      expect(
        parsePageIndex(index({'wordCount': 0, 'sentences': <Object?>[]}))?.toJson(),
        index({'wordCount': 0, 'sentences': <Object?>[]}),
      );
    });

    test('rejects an index whose sentences do not tile the words in order', () {
      // The phone maps sentences to its own words by index, so a gap or overlap would misplace them.
      expect(parsePageIndex(index({'wordCount': 6})), isNull);
      expect(parsePageIndex(index({'wordCount': 4})), isNull);
      expect(
        parsePageIndex(
          index({
            'sentences': [
              sentence(),
              sentence({'from': 1}),
            ],
          }),
        ),
        isNull,
      );
      expect(
        parsePageIndex(
          index({
            'sentences': [
              sentence({'from': 1}),
            ],
            'wordCount': 3,
          }),
        ),
        isNull,
      );
    });

    test('rejects bad fields', () {
      expect(parsePageIndex(null), isNull);
      expect(parsePageIndex(index({'wordsHash': 'B' * 64})), isNull);
      expect(parsePageIndex(index({'sentences': 'x'})), isNull);
      final bad = <Map<String, Object?>>[
        {'key': '../../etc'},
        {'key': key.substring(1)},
        {'lang': 'fr'},
        {'ms': -1},
        {'ms': double.nan},
        {'words': <Object?>[]},
        {
          'words': [
            [400, 0],
            [400, 1000],
          ],
        },
        {
          'words': [
            [0, 400],
            [300, 1000],
          ],
        },
        {
          'words': [
            [0, 400],
            [400, 1001],
          ],
        },
        {
          'words': [
            [0],
            [400, 1000],
          ],
        },
      ];
      for (final over in bad) {
        expect(
          parsePageIndex({
            'wordCount': 2,
            'wordsHash': hash,
            'sentences': [sentence(over)],
          }),
          isNull,
          reason: '$over',
        );
      }
    });
  });

  group('parseManifest', () {
    Map<String, Object?> manifest([Map<String, Object?> over = const {}]) => {
      'version': 2,
      'docId': hash,
      'name': 'paper.pdf',
      'pages': 7,
      'sentences': 355,
      'bytes': 1200000,
      'updated': 1792500000000,
      'voiced': [3, 1, 2],
      'voices': 'a1b2c3d4e5f60718',
      ...over,
    };

    test('accepts a valid manifest, its voiced pages in order', () {
      expect(parseManifest(manifest())?.toJson(), {
        ...manifest(),
        'voiced': [1, 2, 3],
      });
      // A PDF that has no audio yet.
      expect(parseManifest(manifest({'voiced': <int>[], 'voices': '', 'sentences': 0}))!.voiced, isEmpty);
    });

    test('reads version 1 as every page voiced, by voices unknown', () {
      final old = manifest({'version': 1})
        ..remove('voiced')
        ..remove('voices');
      final read = parseManifest(old)!;
      expect(read.voiced, [1, 2, 3, 4, 5, 6, 7]);
      expect(read.voices, '');
    });

    test('rejects other versions and bad fields', () {
      expect(parseManifest(manifest({'version': 3})), isNull);
      expect(parseManifest(manifest({'docId': 'x'})), isNull);
      expect(parseManifest(manifest({'name': ''})), isNull);
      expect(parseManifest(manifest({'name': 'x' * 256})), isNull);
      expect(parseManifest(manifest({'pages': 0})), isNull);
      expect(parseManifest(manifest({'sentences': 1.5})), isNull);
      expect(parseManifest(manifest({'bytes': -1})), isNull);
      expect(parseManifest(manifest({'updated': 'today'})), isNull);
      expect(
        parseManifest(
          manifest({
            'voiced': [8],
          }),
        ),
        isNull,
      );
      expect(
        parseManifest(
          manifest({
            'voiced': [1, 1],
          }),
        ),
        isNull,
      );
      expect(parseManifest(manifest({'voiced': 'all'})), isNull);
      expect(parseManifest(manifest({'voices': 'NOT HEX'})), isNull);
    });
  });

  group('parseDeviceState', () {
    Map<String, Object?> state([Map<String, Object?> over = const {}]) => {
      'device': device,
      'name': 'Galaxy S20 FE',
      'updated': 1792500000000,
      'page': 34,
      'offset': 0.2,
      'sentence': {'page': 34, 'index': 5, 'key': key},
      ...over,
    };

    test('accepts a valid state, with or without a sentence', () {
      expect(parseDeviceState(state())?.toJson(), state());
      expect(parseDeviceState(state({'sentence': null}))?.toJson(), state({'sentence': null}));
    });

    test('clamps the offset as progress does', () {
      expect(parseDeviceState(state({'offset': 3}))?.offset, 0.999);
      expect(parseDeviceState(state({'offset': -1}))?.offset, 0);
    });

    test('drops a sentence that is not valid but keeps the place', () {
      expect(
        parseDeviceState(
          state({
            'sentence': {'page': 34, 'index': -1, 'key': key},
          }),
        )?.sentence,
        isNull,
      );
      expect(
        parseDeviceState(
          state({
            'sentence': {'page': 34, 'index': 5, 'key': 'x'},
          }),
        )?.sentence,
        isNull,
      );
    });

    test('rejects a state without a device, name, time or page', () {
      expect(parseDeviceState(null), isNull);
      expect(parseDeviceState(state({'device': '../x'})), isNull);
      expect(parseDeviceState(state({'name': ''})), isNull);
      expect(parseDeviceState(state({'name': 'x' * 65})), isNull);
      expect(parseDeviceState(state({'updated': double.infinity})), isNull);
      expect(parseDeviceState(state({'page': 0})), isNull);
    });
  });

  group('newestState', () {
    DeviceState at(num updated, [String? id]) =>
        DeviceState(device: id ?? device, name: 'x', updated: updated, page: 1, offset: 0, sentence: null);

    test('picks the most recently updated state', () {
      expect(newestState([at(1), at(3, 'd' * 32), at(2)])?.updated, 3);
      expect(newestState([]), isNull);
    });
  });

  group('placeOffer', () {
    DeviceState phone(num updated) => DeviceState(
      device: 'd' * 32,
      name: 'Galaxy S20 FE',
      updated: updated,
      page: 2,
      offset: 0,
      sentence: null,
    );
    final own = DeviceState(device: device, name: 'Desk', updated: 0, page: 1, offset: 0, sentence: null);
    DeviceState ownAt(num updated) =>
        DeviceState(device: own.device, name: own.name, updated: updated, page: 1, offset: 0, sentence: null);

    test('offers another device’s place when it is newer than this device’s', () {
      expect(placeOffer([phone(2000)], device, 1000)?.name, 'Galaxy S20 FE');
      expect(placeOffer([phone(2000)], device, null)?.page, 2);
    });

    test('offers nothing when this device read last, or nobody else did', () {
      expect(placeOffer([phone(1000)], device, 2000), isNull);
      expect(placeOffer([ownAt(3000), phone(2000)], device, 1000), isNull);
      expect(placeOffer([], device, 1000), isNull);
    });
  });
}
