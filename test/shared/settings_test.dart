// Port of the desktop's tests/unit/settings.test.ts. Settings compare through toJson, which is
// the shape the desktop writes to disk.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/settings.dart';
import 'package:pdfreader/shared/types.dart';

VoiceOption voice(String model, int sid, List<Lang> langs) =>
    VoiceOption(model, sid, label: '$model $sid', langs: langs);

void main() {
  final defaults = defaultSettings().toJson();

  group('normalizeSettings', () {
    test('returns defaults for garbage and clamps the speed', () {
      expect(normalizeSettings('nonsense').toJson(), defaults);
      expect(normalizeSettings({'speed': 99}).speed, 2);
      expect(normalizeSettings({'speed': double.nan}).speed, 1);
    });

    test('keeps valid voices, lets a role fall back to main, and ignores invalid entries', () {
      final settings = normalizeSettings({
        'voices': {
          'en': {
            'main': {'model': 'pocket', 'sid': 1},
            'quote': null,
            'heading': {'model': 7},
          },
        },
      });
      expect(settings.voices[Lang.en]![Role.main], const VoiceRef('pocket', 1));
      expect(settings.voices[Lang.en]![Role.quote], isNull);
      expect(settings.voices[Lang.en]![Role.heading], defaultSettings().voices[Lang.en]![Role.heading]);
      expect(
        settings.toJson()['voices']! as Map<String, Object?>,
        containsPair('de', (defaults['voices']! as Map)['de']),
      );
    });

    test('keeps valid reading settings, clamps numbers and ignores unknown fonts and themes', () {
      final reading = normalizeSettings({
        'reading': {
          'font': 'OpenDyslexic',
          'size': 500,
          'lineHeight': 2,
          'letterSpacing': -1,
          'theme': 'neon',
        },
      }).reading;
      expect(reading.toJson(), {
        'font': 'OpenDyslexic',
        'size': 40,
        'lineHeight': 2,
        'letterSpacing': -0.08,
        'theme': defaultSettings().reading.theme,
      });
      expect(
        normalizeSettings({
          'reading': {'font': 'Wingdings'},
        }).reading.toJson(),
        defaults['reading'],
      );
      expect(normalizeSettings({'reading': null}).reading.toJson(), defaults['reading']);
    });
  });

  group('stopAtReferences', () {
    test('is off unless switched on', () {
      expect(defaultSettings().stopAtReferences, false);
      expect(normalizeSettings({'stopAtReferences': true}).stopAtReferences, true);
      expect(normalizeSettings({'stopAtReferences': 'yes'}).stopAtReferences, false);
    });
  });

  group('polish', () {
    test('is off by default and keeps only a real boolean', () {
      expect(defaultSettings().polish, false);
      expect(normalizeSettings({'polish': true}).polish, true);
      expect(normalizeSettings({'polish': 'yes'}).polish, false);
      expect(normalizeSettings(<String, Object?>{}).polish, false);
    });
  });

  group('focus mode', () {
    test('is off by default and keeps only a real boolean', () {
      expect(defaultSettings().focusMode, false);
      expect(normalizeSettings({'focusMode': true}).focusMode, true);
      expect(normalizeSettings({'focusMode': 'yes'}).focusMode, false);
      expect(normalizeSettings(<String, Object?>{}).focusMode, false);
    });
  });

  group('resolveVoice', () {
    final settings = normalizeSettings({
      'voices': {
        'en': {
          'main': {'model': 'kokoro', 'sid': 3},
          'quote': {'model': 'kokoro', 'sid': 26},
        },
        'de': {
          'main': {'model': 'piper-thorsten', 'sid': 0},
          'quote': {'model': 'supertonic', 'sid': 5},
        },
      },
    });

    test('uses the voice configured for the role', () {
      final available = [
        voice('kokoro', 3, [Lang.en]),
        voice('kokoro', 26, [Lang.en]),
      ];
      expect(resolveVoice(settings, available, Lang.en, Role.quote), const VoiceRef('kokoro', 26));
    });

    test('falls back to the main voice, then to any voice for the language', () {
      final onlyMain = [
        voice('piper-thorsten', 0, [Lang.de]),
      ];
      expect(resolveVoice(settings, onlyMain, Lang.de, Role.quote), const VoiceRef('piper-thorsten', 0));
      final other = [
        voice('kokoro', 3, [Lang.en]),
        voice('supertonic', 9, [Lang.en, Lang.de]),
      ];
      expect(resolveVoice(settings, other, Lang.de, Role.main), const VoiceRef('supertonic', 9));
    });

    test('does not use a voice for a language it cannot speak', () {
      // Kokoro only speaks English, so a German quote must not get the English quote voice.
      final available = [
        voice('kokoro', 26, [Lang.en]),
        voice('piper-thorsten', 0, [Lang.de]),
      ];
      final german = normalizeSettings({
        'voices': {
          'de': {
            'quote': {'model': 'kokoro', 'sid': 26},
          },
        },
      });
      expect(resolveVoice(german, available, Lang.de, Role.quote)?.model, 'piper-thorsten');
    });

    test('prefers a wrong-language voice over silence and returns nothing without voices', () {
      expect(
        resolveVoice(
          settings,
          [
            voice('kokoro', 3, [Lang.en]),
          ],
          Lang.de,
          Role.main,
        )?.model,
        'kokoro',
      );
      expect(resolveVoice(settings, [], Lang.de, Role.main), isNull);
    });
  });

  group('progress', () {
    final place = <String, Object?>{
      'view': 'reading',
      'zoom': 1.5,
      'page': 3,
      'offset': 0.25,
      'sentence': {'page': 3, 'index': 7},
    };

    test('keeps a valid place as it is', () {
      expect(normalizeProgress(place)?.toJson(), place);
    });

    test('repairs what can be repaired and refuses what cannot', () {
      expect(normalizeProgress(null), isNull);
      expect(normalizeProgress('x'), isNull);
      expect(normalizeProgress({...place, 'page': 0}), isNull);
      expect(normalizeProgress({...place, 'page': 2.5}), isNull);
      final repaired = normalizeProgress({...place, 'view': 'x', 'zoom': 99, 'offset': 7})!;
      expect((repaired.view, repaired.zoom, repaired.offset), ('pdf', 5, 0.999));
      final reset = normalizeProgress({...place, 'zoom': 'big', 'offset': double.nan})!;
      expect((reset.zoom, reset.offset), (null, 0));
      expect(
        normalizeProgress({
          ...place,
          'sentence': {'page': 1},
        })?.sentence,
        isNull,
      );
      expect(
        normalizeProgress({
          ...place,
          'sentence': {'page': 1, 'index': -1},
        })?.sentence,
        isNull,
      );
    });

    test('reads a store, dropping entries without a valid place or a time', () {
      final store = parseProgressStore({
        'version': 1,
        'documents': {
          'a.pdf': {...place, 'updated': 5},
          'b.pdf': {...place, 'page': 'one', 'updated': 6},
          'c.pdf': {...place},
          'd.pdf': 'text',
        },
      });
      expect(store.documents.keys, ['a.pdf']);
      expect(parseProgressStore('nonsense').documents, isEmpty);
      expect(
        parseProgressStore({
          'documents': [1, 2],
        }).documents,
        isEmpty,
      );
    });

    test('keeps at most 300 documents and forgets the least recently touched first', () {
      final store = parseProgressStore(null);
      final progress = normalizeProgress(place)!;
      for (var i = 0; i < progressLimit; i++) {
        rememberProgress(store, 'doc$i', progress, 1000 + i);
      }
      expect(store.documents, hasLength(progressLimit));
      // Touching the oldest makes it the newest, so the next one to go is doc1.
      rememberProgress(store, 'doc0', normalizeProgress({...place, 'page': 9})!, 5000);
      rememberProgress(store, 'new', progress, 5001);
      final keys = store.documents.keys;
      expect(keys, hasLength(progressLimit));
      expect(keys, isNot(contains('doc1')));
      expect(keys, contains('doc0'));
      expect((store.documents['doc0']!.progress.page, store.documents['doc0']!.updated), (9, 5000));
    });
  });
}
