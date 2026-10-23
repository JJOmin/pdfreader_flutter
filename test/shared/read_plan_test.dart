import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/sync.dart';
import 'package:pdfreader/shared/types.dart';
import 'package:pdfreader/shared/utterances.dart';

/// A block whose characters sit at raw offsets `start` onwards, one each.
Block block(String text, int start, {bool heading = false}) =>
    Block(text, List.generate(text.length, (i) => start + i), heading: heading);

/// An index sentence of `count` words, each 100 ms long.
Map<String, Object?> sentence(String text, int from, int count) => {
  'key': syncKey(text),
  'lang': 'en',
  'ms': count * 100 + 50,
  'from': from,
  'words': [
    for (var i = 0; i < count; i++) [i * 100, i * 100 + 100],
  ],
};

/// The index the desktop would write: its hash is of the phone's words unless `hash` says otherwise.
PageIndex index(List<Utterance> phone, List<Map<String, Object?>> sentences, {String? hash}) =>
    parsePageIndex({
      'wordCount': sentences.fold(0, (n, s) => n + (s['words']! as List).length),
      'wordsHash': hash ?? wordsHash(pageWords(phone)),
      'sentences': sentences,
    })!;

List<String> texts(PlannedSentence s) => [for (final w in s.words) w.text];

void main() {
  // "I. INTRODUCTION" at 0 to 15, a running header the reader leaves out at 15 to 20, then the body.
  final phone = buildUtterances(
    [block('I. INTRODUCTION', 0, heading: true), block('Tutorials help you.', 20)],
    1,
    Lang.en,
  );

  group('planPage, when the page’s words agree with the index', () {
    // The desktop joined the heading to the first sentence; the phone did not.
    final plan = planPage(
      phone,
      index(phone, [sentence('I. INTRODUCTION Tutorials', 0, 3), sentence('help you.', 3, 2)]),
    );

    test('reads the desktop’s sentences, made of the phone’s words by index', () {
      expect(plan.sentences.map(texts), [
        ['I', 'INTRODUCTION', 'Tutorials'],
        ['help', 'you'],
      ]);
      expect(plan.skipped, 0);
      expect(plan.sentences.first.key, syncKey('I. INTRODUCTION Tutorials'));
    });

    test('maps each sentence to raw ranges that leave out what lies between the phone’s sentences', () {
      // The header at 15 to 20 is not tinted: only the gaps inside one phone sentence are filled.
      // The full stop at 38 is, because the sentence ends where the phone's does.
      expect(plan.sentences[0].ranges, [(0, 15), (20, 29)]);
      expect(plan.sentences[1].ranges, [(30, 39)]);
    });

    test('takes the timings from the index, in seconds, and the role from the first word', () {
      expect(plan.sentences[1].timings.map((t) => (t.start, t.end)), [(0.0, 0.1), (0.1, 0.2)]);
      expect(plan.sentences[1].duration, 0.25);
      expect(plan.sentences[0].role, Role.heading);
      expect(plan.sentences[1].role, Role.main);
    });

    test('keeps a word broken across lines in one piece', () {
      // "Silben-" ends a line at 10; layout joins it to "trennung" and leaves the hyphen out.
      final raw = [for (var i = 0; i < 10; i++) i, for (var i = 12; i < 27; i++) i];
      final broken = buildUtterances([Block('Die Silbentrennung hilft.', raw, heading: false)], 1, Lang.de);
      final plan = planPage(broken, index(broken, [sentence('Die Silbentrennung hilft.', 0, 3)]));
      expect(plan.sentences.single.words[1].ranges, [(4, 10), (12, 20)]);
      expect(plan.sentences.single.ranges, broken.single.ranges);
    });
  });

  group('planPage, when the page’s words differ from the index', () {
    test('skips a phone sentence whose key is not in the index', () {
      final plan = planPage(phone, index(phone, [sentence('Tutorials help you.', 0, 3)], hash: 'f' * 64));
      expect(plan.sentences.map(texts), [
        ['Tutorials', 'help', 'you'],
      ]);
      expect(plan.skipped, 1);
    });

    test('uses a matched sentence’s own words, estimating timings when the counts differ', () {
      final sentences = [sentence('I. INTRODUCTION', 0, 2), sentence('Tutorials help you.', 2, 2)];
      final plan = planPage(phone, index(phone, sentences, hash: 'f' * 64));
      expect(plan.skipped, 0);
      expect(plan.sentences.map(texts), [
        ['I', 'INTRODUCTION'],
        ['Tutorials', 'help', 'you'],
      ]);
      expect(plan.sentences[0].ranges, phone[0].ranges);
      expect(plan.sentences[0].timings.map((t) => (t.start, t.end)), [(0.0, 0.1), (0.1, 0.2)]);
      // Three words in 250 ms of audio, spread by their length.
      expect(plan.sentences[1].timings, hasLength(3));
      expect(plan.sentences[1].timings.last.end, 0.25);
    });
  });

  test('planPage without an index skips every sentence', () {
    final plan = planPage(phone, null);
    expect(plan.sentences, isEmpty);
    expect(plan.skipped, 2);
  });

  test(
    'tints a sentence over the page break on both pages, and puts its words on theirs (desktop ADR 12)',
    () {
      final page1 = buildUtterances([block('This sentence runs over', 0)], 1, Lang.en);
      final page2 = buildUtterances([block('the page break. Next one.', 0)], 2, Lang.en);
      final joined = joinedPage(null, page1, page2);
      final plan = planPage(
        joined,
        index(joined, [sentence('This sentence runs over the page break.', 0, 7)]),
      );
      final s = plan.sentences.single;
      expect(texts(s), ['This', 'sentence', 'runs', 'over', 'the', 'page', 'break']);
      expect(s.page, 1);
      expect(s.ranges, [(0, 23)]);
      expect(s.next!.page, 2);
      expect(s.next!.ranges, [(0, 14)]);
      expect(s.words.last.page, 2);
    },
  );
}
