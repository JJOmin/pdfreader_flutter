// The reading session tells of a new word on a listenable of its own, so the bars and the player are
// not built again for every word (PLAN 18.1).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/now_playing.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/types.dart';

void main() {
  test('a new word reaches the word listenable alone; a new sentence or state tells every listener', () {
    final session = ReadingSession(name: 'Paper.pdf', data: Uint8List(0), placeKey: 'k');
    var told = 0;
    session.addListener(() => told++);
    final words = <int>[];
    session.spokenWord.addListener(() => words.add(session.spokenWord.value));
    const sentence = PlannedSentence(
      page: 1,
      key: 'k',
      lang: Lang.en,
      role: Role.main,
      words: [
        Word('One', [(0, 3)]),
        Word('two', [(4, 7)]),
        Word('three', [(8, 13)]),
      ],
      ranges: [(0, 13)],
      timings: [],
      duration: 0,
    );
    session.update(ReaderState.playing, sentence: sentence, word: 0);
    session.update(ReaderState.playing, sentence: sentence, word: 1);
    session.update(ReaderState.playing, sentence: sentence, word: 2);
    expect(told, 1);
    expect(words, [0, 1, 2]);
    expect(session.word, 2);
    session.update(ReaderState.paused, sentence: sentence, word: 2);
    expect(told, 2);
  });
}
