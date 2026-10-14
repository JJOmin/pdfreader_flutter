// Port of the desktop's tests/unit/utterances.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/language.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/types.dart';
import 'package:pdfreader/shared/utterances.dart';

/// A block whose text is also the page's raw string.
Block block(String text, {bool heading = false}) =>
    Block(text, List.generate(text.length, (i) => i), heading: heading);

void main() {
  group('guessLang', () {
    test('recognises German and English sentences', () {
      expect(guessLang('Die Methode ist nicht neu und wird oft verwendet.'), (
        lang: Lang.de,
        confident: true,
      ));
      expect(guessLang('The method is not new and has been used for years.'), (
        lang: Lang.en,
        confident: true,
      ));
    });

    test('falls back to the document language without evidence', () {
      expect(sentenceLang('Transformer Encoder Layer', Lang.de), Lang.de);
      expect(sentenceLang('Transformer Encoder Layer', Lang.en), Lang.en);
    });
  });

  group('buildUtterances', () {
    test('splits a paragraph into sentences with their words', () {
      final [first, second] = buildUtterances([block('We test it. It works well.')], 3, Lang.en);
      expect(first.text, 'We test it.');
      expect(first.page, 3);
      expect(first.words.map((w) => w.text), ['We', 'test', 'it']);
      expect(second.words[0].ranges, [(12, 14)]);
    });

    test('does not split at abbreviations, initials or German ordinals', () {
      final en = buildUtterances(
        [block('As shown by Smith et al. Results in Fig. 2 hold, cf. J. Doe.')],
        1,
        Lang.en,
      );
      expect(en, hasLength(1));
      final de = buildUtterances([block('Das gilt z. B. für den 3. Mai. Danach nicht.')], 1, Lang.de);
      expect(de.map((u) => u.text), ['Das gilt z. B. für den 3. Mai.', 'Danach nicht.']);
    });

    test('gives an English sentence in a German text to the English voice', () {
      final utterances = buildUtterances(
        [block('Das Modell ist sehr groß. The authors did not release the code for this. Das ist schade.')],
        1,
        Lang.de,
      );
      expect(utterances.map((u) => u.lang), [Lang.de, Lang.en, Lang.de]);
    });

    test('splits at a colon that introduces a quote or a clause in the other language', () {
      final utterances = buildUtterances(
        [
          block(
            'Die Autoren schreiben: The proposed method is simple and it does not need data. '
            'Ein Satz lautet: „Der Mensch spielt gern.“',
          ),
        ],
        1,
        Lang.de,
      );
      expect(utterances.map((u) => (u.lang, u.role, u.text)), [
        (Lang.de, Role.main, 'Die Autoren schreiben:'),
        (Lang.en, Role.main, 'The proposed method is simple and it does not need data.'),
        (Lang.de, Role.main, 'Ein Satz lautet:'),
        (Lang.de, Role.quote, '„Der Mensch spielt gern.“'),
      ]);
    });

    test('assigns the heading and quote roles', () {
      final utterances = buildUtterances(
        [
          block('2 Methode', heading: true),
          block('Er schrieb: Es geht. „Das ist der erste Satz. Und der zweite.“ Danach folgt Text.'),
        ],
        1,
        Lang.de,
      );
      expect(utterances.map((u) => u.role), [Role.heading, Role.main, Role.quote, Role.quote, Role.main]);
    });

    test('skips numeric citations in speech but keeps the visible text', () {
      final [u] = buildUtterances([block('This was shown before [3, 14] and later [7].')], 1, Lang.en);
      expect(u.spoken, 'This was shown before and later.');
      expect(u.text, contains('[3, 14]'));
      expect(u.words.map((w) => w.text), ['This', 'was', 'shown', 'before', 'and', 'later']);
    });
  });
}
