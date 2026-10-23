import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/player_preview.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/types.dart';

void main() {
  group('wordSpans', () {
    test('gives each word its offsets in the words joined by single spaces', () {
      expect(wordSpans(['Hello', 'there', 'you']), [(0, 5), (6, 11), (12, 15)]);
    });

    test('counts characters, not bytes', () {
      expect(wordSpans(['Größe', 'ist', 'wichtig']), [(0, 5), (6, 9), (10, 17)]);
    });

    test('has no spans for no words', () {
      expect(wordSpans(const []), isEmpty);
    });
  });

  group('steppedSpeed', () {
    test('moves by a tenth', () {
      expect(steppedSpeed(1.0, 1), 1.1);
      expect(steppedSpeed(1.0, -1), 0.9);
    });

    test('lands on a multiple of 0.05 even after a slider left it in between', () {
      expect(steppedSpeed(1.23, 1), 1.35);
      expect(steppedSpeed(1.23, -1), 1.15);
    });

    test('stays within the allowed speeds', () {
      expect(steppedSpeed(2.0, 1), 2.0);
      expect(steppedSpeed(0.6, -1), 0.6);
    });
  });

  test('sentenceText joins the words with spaces', () {
    const sentence = PlannedSentence(
      page: 1,
      key: 'k',
      lang: Lang.en,
      role: Role.main,
      words: [
        Word('One', [(0, 3)]),
        Word('two', [(4, 7)]),
      ],
      ranges: [(0, 7)],
      timings: [],
      duration: 0,
    );
    expect(sentenceText(sentence), 'One two');
  });
}
