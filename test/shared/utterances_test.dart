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

  group('isReferenceHeading', () {
    test('knows the reference list by its heading, numbered or not, in English and German', () {
      for (final text in [
        'References',
        'REFERENCES',
        '7 References',
        'VII. References',
        'Bibliography',
        'Literatur',
        '6.1 Literaturverzeichnis',
        'Works Cited',
        'Quellenverzeichnis',
        'Literature',
      ]) {
        expect(isReferenceHeading(text), isTrue, reason: text);
      }
    });

    test('is a sentence that is nothing but the heading, but not one that only mentions references', () {
      expect(isReferenceHeading('REFERENCES'), isTrue);
      expect(isReferenceHeading('See the references.'), isFalse);
      for (final text in ['References to prior work', 'Related Work', 'Literature review']) {
        expect(isReferenceHeading(text), isFalse, reason: text);
      }
    });
  });

  group('joinedPage (desktop ADR 12)', () {
    Utterance u(int page, String text, [Role role = Role.main]) => Utterance(
      page: page,
      text: text,
      spoken: text,
      lang: Lang.en,
      role: role,
      words: [
        for (final (i, w) in text.split(' ').indexed)
          Word(w.replaceAll(RegExp('[.,]'), ''), [(i * 10, i * 10 + w.length)]),
      ],
      ranges: [(0, text.length)],
    );
    final page1 = [u(1, 'First sentence.'), u(1, 'This sentence runs over')];
    final page2 = [u(2, 'the page break.'), u(2, 'Then another one.')];

    test('joins the next page’s start onto a sentence that has no end, its words on their own page', () {
      final joined = joinedPage(null, page1, page2);
      expect(joined.map((s) => s.text), ['First sentence.', 'This sentence runs over the page break.']);
      final last = joined[1];
      expect(last.page, 1);
      expect(last.next!.page, 2);
      expect(last.next!.ranges, [(0, 15)]);
      expect(last.words.map((w) => w.page), [null, null, null, null, 2, 2, 2]);
      expect(last.words.last.text, 'break');
      expect(last.words.last.ranges, [(20, 26)]);
    });

    test('leaves the joined start out of the next page', () {
      expect(joinedPage(page1, page2, null).map((s) => s.text), ['Then another one.']);
    });

    test('joins nothing after a sentence end, a colon, or a heading on either side', () {
      for (final ending in ['Ends here.', 'Asked?', 'As follows:', '“Quoted.”']) {
        expect(joinedPage(null, [u(1, ending)], page2), hasLength(1), reason: ending);
      }
      expect(joinedPage(null, [u(1, '2 Methods', Role.heading)], page2), hasLength(1));
      final beforeHeading = joinedPage(null, page1, [u(2, 'Results', Role.heading)]);
      expect(beforeHeading, hasLength(2));
      expect(beforeHeading[1].next, isNull);
    });

    test('is the page as it is on the last page, and for an empty one', () {
      expect(joinedPage(null, page1, null).map((s) => s.text), page1.map((s) => s.text));
      expect(joinedPage(null, [], page2), isEmpty);
    });
  });
}
