// The menu over selected text: its Comment button opens the comment sheet, with or without a
// microphone on the phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/views/mark_menu.dart';

Widget menu({VoidCallback? onComment}) => MaterialApp(
  home: Scaffold(
    body: MarkMenu(
      anchorA: const Offset(100, 200),
      anchorB: null,
      initialKind: MarkKind.highlight,
      onKindChanged: (_) {},
      onMark: (_, _) {},
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
}
