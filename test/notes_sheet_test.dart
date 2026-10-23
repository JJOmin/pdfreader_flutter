// A mark's card only shows until the pencil opens it: then the comment, the kind, the colour and
// Delete can be changed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/views/notes_sheet.dart';

const mark = Annotation(
  id: 'm1',
  page: 2,
  start: 0,
  end: 5,
  text: 'quick',
  quote: 'quick',
  kind: MarkKind.highlight,
  color: HighlightColor.yellow,
  comment: 'Said so.',
  created: '2026-10-23T09:00:00.000Z',
);

class Log {
  final comments = <String>[];
  final styles = <(MarkKind, HighlightColor)>[];
  final deleted = <String>[];

  NotesActions get actions => NotesActions(
    onNotes: (_) {},
    onComment: (_, text) => comments.add(text),
    onStyle: (_, kind, color) => styles.add((kind, color)),
    onDelete: deleted.add,
    onJump: (_) {},
  );
}

Widget card(Log log) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: MarkCard(mark: mark, found: true, actions: log.actions),
    ),
  ),
);

TextField field(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('comment-m1')));

void main() {
  testWidgets('closed, it shows the comment and offers nothing to change', (tester) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    expect(find.text('Said so.'), findsOneWidget);
    expect(field(tester).readOnly, isTrue);
    expect(find.byKey(const Key('color-blue-m1')), findsNothing);
    expect(find.byKey(const Key('kind-underline-m1')), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.byKey(const Key('edit-m1')), findsOneWidget);
  });

  testWidgets('does not take typing while it is closed', (tester) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    await tester.tap(find.byKey(const Key('comment-m1')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('comment-m1')), 'Overwritten');
    expect(log.comments, isEmpty);
  });

  testWidgets('the pencil opens it: the comment changes, and the kind, the colour and Delete show', (
    tester,
  ) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    await tester.tap(find.byKey(const Key('edit-m1')));
    await tester.pump();
    expect(field(tester).readOnly, isFalse);
    await tester.enterText(find.byKey(const Key('comment-m1')), 'Said otherwise.');
    expect(log.comments, ['Said otherwise.']);

    await tester.tap(find.byKey(const Key('color-blue-m1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('kind-underline-m1')));
    await tester.pump();
    expect(log.styles, [
      (MarkKind.highlight, HighlightColor.blue),
      (MarkKind.underline, HighlightColor.blue),
    ]);
    expect(find.textContaining('Underline'), findsOneWidget, reason: 'the card shows the new kind');

    await tester.tap(find.text('Delete'));
    expect(log.deleted, ['m1']);
  });

  testWidgets('the check mark closes it again', (tester) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    await tester.tap(find.byKey(const Key('edit-m1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-m1')));
    await tester.pump();
    expect(field(tester).readOnly, isTrue);
    expect(find.byKey(const Key('color-blue-m1')), findsNothing);
  });
}
