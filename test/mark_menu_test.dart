// The menu over selected text: its Comment button opens the comment sheet, with or without a
// microphone on the phone; the two favourite looks mark with one tap, and More has every kind and
// colour (PLAN 18.7).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/mark_styles.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/views/mark_menu.dart';
import 'package:pdfreader/views/text_view.dart';

Widget menu({
  VoidCallback? onComment,
  void Function(MarkKind, HighlightColor)? onMark,
  MarkStyles styles = const MarkStyles(),
}) => MaterialApp(
  home: Scaffold(
    body: MarkMenu(
      anchorA: const Offset(100, 200),
      anchorB: null,
      styles: styles,
      initialKind: MarkKind.highlight,
      onKindChanged: (_) {},
      onMark: onMark ?? (_, _) {},
      onComment: onComment,
    ),
  ),
);

void main() {
  testWidgets('has a Comment button that asks for a comment, where there is no microphone too', (
    tester,
  ) async {
    var asked = 0;
    await tester.pumpWidget(menu(onComment: () => asked++));
    expect(find.byKey(const Key('comment-selection')), findsOneWidget);
    expect(
      find.byKey(const Key('speak-comment')),
      findsNothing,
      reason: 'the microphone is in the sheet now',
    );
    expect(find.byTooltip('Comment'), findsOneWidget);
    await tester.tap(find.byKey(const Key('comment-selection')));
    expect(asked, 1);
  });

  testWidgets('has no Comment button where marks cannot carry one', (tester) async {
    await tester.pumpWidget(menu());
    expect(find.byKey(const Key('comment-selection')), findsNothing);
  });

  testWidgets('the Comment button has the primary comment colour', (tester) async {
    await tester.pumpWidget(
      menu(
        onComment: () {},
        styles: const MarkStyles(comment: HighlightColor.blue),
      ),
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: find.byKey(const Key('comment-selection')), matching: find.byType(Icon)),
    );
    expect(icon.color, markLine[HighlightColor.blue]);
  });

  testWidgets('a favourite marks with one tap', (tester) async {
    final marked = <(MarkKind, HighlightColor)>[];
    final styles = const MarkStyles().withFavourite(1, (kind: MarkKind.underline, color: HighlightColor.red));
    await tester.pumpWidget(menu(styles: styles, onMark: (k, c) => marked.add((k, c))));
    expect(find.byKey(const Key('color-red')), findsNothing, reason: 'the colours wait behind More');
    await tester.tap(find.byKey(const Key('favourite-1')));
    expect(marked, [(MarkKind.underline, HighlightColor.red)]);
  });

  testWidgets('More shows every kind and colour; the kind chosen there marks', (tester) async {
    final marked = <(MarkKind, HighlightColor)>[];
    await tester.pumpWidget(menu(onMark: (k, c) => marked.add((k, c))));
    await tester.tap(find.byKey(const Key('more-looks')));
    await tester.pump();
    expect(find.byKey(const Key('favourite-0')), findsNothing);
    await tester.tap(find.byKey(const Key('kind-strike')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-green')));
    expect(marked, [(MarkKind.strike, HighlightColor.green)]);
  });
}
