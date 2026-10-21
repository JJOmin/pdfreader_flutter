// The playback queue with a fake library and fake players: order, lookahead, cancellation.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/types.dart';

PlannedSentence sentence(int page, String key) => PlannedSentence(
  page: page,
  key: key,
  lang: Lang.en,
  role: Role.main,
  words: const [
    Word('one', [(0, 3)]),
    Word('two', [(4, 7)]),
  ],
  ranges: const [(0, 7)],
  timings: const [WordTiming(0, 0.4), WordTiming(0.4, 1)],
  duration: 1,
);

class FakePlayer implements PreparedAudio {
  FakePlayer(this.key);

  final String key;
  final ended = Completer<void>();
  void Function(Duration)? onPosition;
  double? speed;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<void> play(double speed, void Function(Duration position) onPosition) {
    if (disposed) throw StateError('$key was disposed');
    this.speed = speed;
    this.onPosition = onPosition;
    return ended.future;
  }

  void finish() => ended.complete();

  @override
  Future<void> stop() async {
    stopped = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
}

class FakeAudio implements SentenceAudio {
  final prepared = <FakePlayer>[];

  List<String> get keys => [for (final p in prepared) p.key];

  /// The player of the sentence that is playing now.
  FakePlayer get current => prepared.lastWhere((p) => p.onPosition != null && !p.ended.isCompleted);

  @override
  Future<PreparedAudio> prepare(PlannedSentence sentence) async {
    final player = FakePlayer(sentence.key);
    prepared.add(player);
    return player;
  }
}

class FakeHost implements ReaderHost {
  FakeHost(this.pages);

  /// Page 2 is empty: a page whose sentences all lack audio.
  final List<List<PlannedSentence>> pages;
  final changes = <(ReaderState, String?, int)>[];
  final errors = <Object>[];

  @override
  int get pageCount => pages.length;

  @override
  Future<List<PlannedSentence>> sentences(int page) async => pages[page - 1];

  @override
  void onChange(ReaderState state, PlannedSentence? sentence, int word) =>
      changes.add((state, sentence?.key, word));

  @override
  void onError(Object error) => errors.add(error);

  /// The sentences started, in order.
  List<String> get started => [
    for (final (_, key, word) in changes)
      if (key != null && word == -1) key,
  ];
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeHost host;
  late FakeAudio audio;
  late Reader reader;

  setUp(() {
    host = FakeHost([
      [sentence(1, 'a'), sentence(1, 'b')],
      [],
      [sentence(3, 'c'), sentence(3, 'd')],
    ]);
    audio = FakeAudio();
    reader = Reader(host, audio, gap: Duration.zero, headingGap: Duration.zero);
  });

  test('reads every sentence in order, across a page without audio, then stops', () async {
    reader.toggle((page: 1, index: 0));
    for (var i = 0; i < 4; i++) {
      await settle();
      audio.current.finish();
    }
    await settle();
    expect(host.started, ['a', 'b', 'c', 'd']);
    expect(reader.state, ReaderState.idle);
    expect(host.changes.last, (ReaderState.idle, null, -1));
    expect(host.errors, isEmpty);
  });

  test('loads the two sentences ahead, and no more', () async {
    reader.toggle((page: 1, index: 0));
    await settle();
    expect(audio.keys, ['a', 'b', 'c']);
    audio.current.finish();
    await settle();
    expect(audio.keys, ['a', 'b', 'c', 'd']);
    // A loaded sentence is not loaded twice.
    expect(audio.current.key, 'b');
  });

  test('reports each word as the position passes its start', () async {
    reader.toggle((page: 1, index: 0));
    await settle();
    audio.current.onPosition!(const Duration(milliseconds: 100));
    audio.current.onPosition!(const Duration(milliseconds: 500));
    audio.current.onPosition!(const Duration(milliseconds: 600));
    expect(host.changes.where((c) => c.$2 == 'a').map((c) => c.$3), [-1, 0, 1]);
  });

  test('a seek stops the sentence playing and reads on from the new place', () async {
    reader.toggle((page: 1, index: 0));
    await settle();
    final first = audio.current;
    reader.startAt((page: 3, index: 1));
    await settle();
    expect(first.stopped, isTrue);
    expect(audio.current.key, 'd');
    // The stopped loop does not go on to "b".
    expect(host.started, ['a', 'd']);
  });

  test('a seek back to the playing sentence loads it afresh', () async {
    reader.toggle((page: 1, index: 0));
    await settle();
    final first = audio.current;
    reader.startAt((page: 1, index: 0));
    await settle();
    expect(audio.current, isNot(same(first)));
    expect(audio.current.key, 'a');
    expect(host.errors, isEmpty);
  });

  test('previous and next cross pages, past the page without audio', () async {
    reader.toggle((page: 3, index: 0));
    await settle();
    await reader.skip(-1);
    await settle();
    expect(audio.current.key, 'b');
    await reader.skip(1);
    await settle();
    expect(audio.current.key, 'c');
  });

  test('plays at the reader’s speed and changes it while playing', () async {
    reader.speed = 1.5;
    reader.toggle((page: 1, index: 0));
    await settle();
    expect(audio.current.speed, 1.5);
    reader.speed = 0.8;
    expect(audio.current.speed, 0.8);
  });

  test('pause and resume keep the sentence; stop goes idle', () async {
    reader.toggle((page: 1, index: 0));
    await settle();
    reader.toggle((page: 1, index: 0));
    expect(reader.state, ReaderState.paused);
    reader.toggle((page: 1, index: 0));
    expect(reader.state, ReaderState.playing);
    reader.stop();
    await settle();
    expect(reader.state, ReaderState.idle);
    expect(host.started, ['a']);
  });
}
