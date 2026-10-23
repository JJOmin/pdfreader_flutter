// The play bar in the reader takes the colours of the reader's top bar, so the two belong together.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/now_playing.dart';

Widget bar({({Color bar, Color onBar})? colors}) => MaterialApp(
  home: Scaffold(
    body: NowPlayingBar(
      session: ReadingSession(name: 'Paper.pdf', data: Uint8List(0), placeKey: 'k'),
      onOpen: () {},
      colors: colors,
    ),
  ),
);

Color? surface(WidgetTester tester) => tester
    .widget<Material>(find.descendant(of: find.byType(NowPlayingBar), matching: find.byType(Material)).first)
    .color;

void main() {
  testWidgets('takes the colours it is given: the bar, its title and its buttons', (tester) async {
    const sepia = (bar: Color(0xFFE0D5BD), onBar: Color(0xFF5B4636));
    await tester.pumpWidget(bar(colors: sepia));
    expect(surface(tester), sepia.bar);
    expect(tester.widget<Text>(find.text('Paper.pdf')).style?.color, sepia.onBar);
    final context = tester.element(find.byKey(const Key('mini-play')));
    expect(Theme.of(context).colorScheme.onSurfaceVariant, sepia.onBar);
  });

  testWidgets('keeps the app surface colours where it is given none', (tester) async {
    await tester.pumpWidget(bar());
    final context = tester.element(find.byType(NowPlayingBar));
    expect(surface(tester), Theme.of(context).colorScheme.surfaceContainerHigh);
  });
}
