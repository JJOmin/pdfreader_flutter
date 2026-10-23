// The full-screen player (PLAN 11): its buttons, the speed-reader preview and the quick comment.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/dictation.dart';
import 'package:pdfreader/now_playing.dart';
import 'package:pdfreader/player_screen.dart';
import 'package:pdfreader/reader.dart';
import 'package:pdfreader/shared/read_plan.dart';
import 'package:pdfreader/shared/types.dart';
import 'package:pdfreader/views/quick_comment.dart';
import 'package:pdfreader/views/speed_reader.dart';

PlannedSentence sentence({SpeechSource source = SpeechSource.desktop}) => PlannedSentence(
  page: 3,
  key: 'k',
  lang: Lang.en,
  role: Role.main,
  words: const [
    Word('The', [(0, 3)]),
    Word('quick', [(4, 9)]),
    Word('fox', [(10, 13)]),
  ],
  ranges: const [(0, 13)],
  timings: const [],
  duration: 0,
  source: source,
);

ReadingSession session({bool canDictate = true}) =>
    ReadingSession(name: 'Paper.pdf', data: Uint8List(0), placeKey: 'k', canDictate: canDictate);

Future<void> pumpPlayer(
  WidgetTester tester,
  ReadingSession session, {
  VoidCallback? onMinimize,
  VoidCallback? onOpenText,
}) => tester.pumpWidget(
  MaterialApp(
    home: PlayerScreen(session: session, onMinimize: onMinimize ?? () {}, onOpenText: onOpenText ?? () {}),
  ),
);

class FakeDictation implements Dictation {
  FakeDictation(this.heard, {this.partials = const []});

  final Dictated heard;
  final List<String> partials;
  bool cancelled = false;

  @override
  Future<bool> available() async => true;

  @override
  Future<Dictated> listen({void Function(String text)? onPartial}) async {
    listened++;
    for (final p in partials) {
      onPartial?.call(p);
    }
    return heard;
  }

  @override
  Future<void> stop() async => stopped = true;

  bool stopped = false;
  int listened = 0;

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  group('PlayerScreen', () {
    testWidgets('plays, skips and minimises', (tester) async {
      final s = session();
      var toggled = 0, skipped = 0, minimised = 0, text = 0;
      s
        ..toggle = (() => toggled++)
        ..skip = ((direction) => skipped += direction);
      await pumpPlayer(tester, s, onMinimize: () => minimised++, onOpenText: () => text++);
      await tester.tap(find.byKey(const Key('player-play')));
      await tester.tap(find.byKey(const Key('player-next')));
      await tester.tap(find.byKey(const Key('player-next')));
      await tester.tap(find.byKey(const Key('player-previous')));
      await tester.tap(find.byKey(const Key('player-minimize')));
      await tester.tap(find.byKey(const Key('player-open-text')));
      expect((toggled, skipped, minimised, text), (1, 1, 1, 1));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      s.update(ReaderState.playing);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('keeps the controls compact at the bottom and gives the text the rest', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = session()..update(ReaderState.playing, sentence: sentence());
      await pumpPlayer(tester, s);
      final panel = tester.getRect(find.byKey(const Key('player-panel')));
      expect(panel.height, lessThan(2000 * 0.25), reason: 'only as tall as the controls need');
      expect(panel.bottom, 2000, reason: 'on the bottom edge');
      expect(tester.getCenter(find.byKey(const Key('player-play'))).dx, closeTo(500, 1));
      final text = tester.getRect(find.byKey(const Key('speed-reader')));
      expect(text.bottom, lessThanOrEqualTo(panel.top));
      expect(tester.getTopLeft(find.byKey(const Key('player-minimize'))).dy, lessThan(100));
      expect(tester.getTopLeft(find.byKey(const Key('player-minimize'))).dx, lessThan(100));
    });

    testWidgets('asks to press play before anything is read, and shows the sentence once it is', (
      tester,
    ) async {
      final s = session();
      await pumpPlayer(tester, s);
      expect(find.text('Press play to start reading'), findsOneWidget);
      s.update(ReaderState.playing, sentence: sentence(), word: 1);
      await tester.pump();
      expect(find.text('Press play to start reading'), findsNothing);
      expect(find.byKey(const Key('speed-reader')), findsOneWidget);
    });

    testWidgets('says in words where the audio comes from, not with an icon', (tester) async {
      final s = session();
      await pumpPlayer(tester, s);
      expect(tester.widget<Text>(find.byKey(const Key('player-source'))).data, '');
      s.update(ReaderState.playing, sentence: sentence());
      await tester.pump();
      expect(find.text('Page 3 · computer audio'), findsOneWidget);
      s.update(ReaderState.playing, sentence: sentence(source: SpeechSource.phone));
      await tester.pump();
      expect(find.text('Page 3 · phone voice'), findsOneWidget);
      expect(find.byIcon(Icons.smartphone), findsNothing);
      expect(find.byIcon(Icons.computer), findsNothing);
    });

    testWidgets('changes the speed by a tenth and stops at the limits', (tester) async {
      final s = session()..speed = 1.0;
      final set = <double>[];
      s.setSpeed = set.add;
      await pumpPlayer(tester, s);
      expect(find.text('1.00×'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed-up')));
      await tester.tap(find.byKey(const Key('speed-down')));
      expect(set, [1.1, 0.9]);
      s.updateSpeed(2.0);
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed-up')));
      expect(set.last, 2.0);
    });

    testWidgets('comments only on a sentence being read, and speaking only where the phone can listen', (
      tester,
    ) async {
      final s = session();
      final asked = <bool>[];
      s.comment = ({required speak}) async => asked.add(speak);
      await pumpPlayer(tester, s);
      expect(tester.widget<FilledButton>(find.byKey(const Key('player-comment'))).onPressed, isNull);
      s.update(ReaderState.paused, sentence: sentence());
      await tester.pump();
      await tester.tap(find.byKey(const Key('player-comment')));
      await tester.tap(find.byKey(const Key('player-dictate')));
      expect(asked, [false, true]);

      final silent = session(canDictate: false)..comment = (({required speak}) async {});
      await pumpPlayer(tester, silent);
      expect(find.byKey(const Key('player-comment')), findsOneWidget);
      expect(find.byKey(const Key('player-dictate')), findsNothing);
    });

    testWidgets('PlayerLayer slides in and out and builds nothing while down', (tester) async {
      final s = session();
      Widget layer(bool open) => MaterialApp(
        home: Stack(
          children: [PlayerLayer(open: open, session: s, onMinimize: () {}, onOpenText: () {})],
        ),
      );
      await tester.pumpWidget(layer(false));
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.pumpWidget(layer(true));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.pumpWidget(layer(false));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
    });
  });

  group('SpeedReaderWindow', () {
    List<InlineSpan> words(WidgetTester tester) =>
        ((tester.widget<RichText>(find.byKey(const Key('speed-reader'))).text) as TextSpan).children!;

    testWidgets('highlights only the spoken word', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 300, child: SpeedReaderWindow(words: ['The', 'quick', 'fox'], current: 1)),
          ),
        ),
      );
      final highlighted = [
        for (final span in words(tester))
          if (span is TextSpan && span.style?.backgroundColor != null) span.text,
      ];
      expect(highlighted, ['quick']);
    });

    testWidgets('has no highlight before the first word', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 300, child: SpeedReaderWindow(words: ['The', 'fox'], current: -1)),
          ),
        ),
      );
      expect([
        for (final s in words(tester))
          if (s is TextSpan && s.style?.backgroundColor != null) s,
      ], isEmpty);
    });

    testWidgets('scrolls a long sentence so the spoken word stays in the window', (tester) async {
      final long = [for (var i = 0; i < 80; i++) 'word$i'];
      Widget window(int current) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: SpeedReaderWindow(words: long, current: current),
          ),
        ),
      );
      await tester.pumpWidget(window(0));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.byKey(const Key('speed-reader'))).dy;
      await tester.pumpWidget(window(70));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('speed-reader'))).dy, lessThan(top - 500));
    });

    testWidgets('shows the sentences either side, faded', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: SpeedReaderWindow(words: ['Now'], current: 0, previous: 'Before it.', next: 'After it.'),
            ),
          ),
        ),
      );
      expect(find.text('Before it.'), findsOneWidget);
      expect(find.text('After it.'), findsOneWidget);
    });
  });

  group('QuickCommentSheet', () {
    Future<String?> open(WidgetTester tester, {Dictation? dictation, bool speak = false}) async {
      String? result;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      QuickCommentSheet(quote: 'The quick fox.', dictation: dictation, listenAtOnce: speak),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      addTearDown(() => expect(done || result == null, isTrue));
      return result;
    }

    testWidgets('saves what was typed', (tester) async {
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => saved = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const QuickCommentSheet(quote: 'q'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dictate')), findsNothing, reason: 'no recogniser on this phone');
      await tester.enterText(find.byKey(const Key('quick-comment')), '  A thought  ');
      await tester.tap(find.byKey(const Key('save-comment')));
      await tester.pumpAndSettle();
      expect(saved, 'A thought');
    });

    testWidgets('puts what was heard into the field as a draft', (tester) async {
      final dictation = FakeDictation(const Dictated(text: 'spoken thought'), partials: ['spoken']);
      await open(tester, dictation: dictation);
      await tester.tap(find.byKey(const Key('dictate')));
      await tester.pumpAndSettle();
      expect(dictation.listened, 1);
      expect(
        tester.widget<TextField>(find.byKey(const Key('quick-comment'))).controller!.text,
        'spoken thought',
      );
    });

    testWidgets('listens at once when asked, and appends to what was typed', (tester) async {
      final dictation = FakeDictation(const Dictated(text: 'and more'));
      await open(tester, dictation: dictation, speak: true);
      expect(dictation.listened, 1);
      await tester.enterText(find.byKey(const Key('quick-comment')), 'First');
      await tester.tap(find.byKey(const Key('dictate')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('quick-comment'))).controller!.text,
        'First and more',
      );
    });

    testWidgets('says so when nothing was heard or listening failed', (tester) async {
      await open(tester, dictation: FakeDictation(const Dictated()), speak: true);
      expect(find.text('Nothing heard'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dictate')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing heard'), findsOneWidget);
    });

    testWidgets('fits a narrow phone with the microphone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await open(tester, dictation: FakeDictation(const Dictated(text: 'x')));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('save-comment')), findsOneWidget);
      expect(find.byKey(const Key('dictate')), findsOneWidget);
    });

    testWidgets('shows a failure from the recogniser', (tester) async {
      await open(
        tester,
        dictation: FakeDictation(const Dictated(error: 'This language is not installed')),
        speak: true,
      );
      expect(find.text('This language is not installed'), findsOneWidget);
    });
  });
}
