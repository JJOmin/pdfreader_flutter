// A mark's card: its comment is typed into directly (PLAN 18.8), while the kind, the colour and Delete
// wait behind the pencil. The notes sheet searches the comments.
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
  testWidgets('shows the comment, and offers the kind, the colour and Delete only behind the pencil', (
    tester,
  ) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    expect(find.text('Said so.'), findsOneWidget);
    expect(find.byKey(const Key('color-blue-m1')), findsNothing);
    expect(find.byKey(const Key('kind-underline-m1')), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.byKey(const Key('edit-m1')), findsOneWidget);
  });

  testWidgets('the comment is typed into directly, without the pencil', (tester) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    expect(field(tester).readOnly, isFalse);
    await tester.enterText(find.byKey(const Key('comment-m1')), 'Said otherwise.');
    expect(log.comments, ['Said otherwise.']);
  });

  testWidgets('the pencil opens the kind, the colour and Delete', (tester) async {
    final log = Log();
    await tester.pumpWidget(card(log));
    await tester.tap(find.byKey(const Key('edit-m1')));
    await tester.pump();
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
    expect(find.byKey(const Key('color-blue-m1')), findsNothing);
  });

  testWidgets('the notes sheet finds marks by their comment', (tester) async {
    final log = Log();
    const other = Annotation(
      id: 'm2',
      page: 3,
      start: 0,
      end: 5,
      text: 'brown',
      quote: 'brown',
      kind: MarkKind.highlight,
      color: HighlightColor.green,
      comment: 'Ask about the contract',
      created: '2026-10-23T09:00:00.000Z',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesSheet(
            notes: '',
            marks: const [mark, other],
            found: const {'m1', 'm2'},
            actions: log.actions,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('mark-m1')), findsOneWidget);
    expect(find.byKey(const Key('mark-m2')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-search')), 'contract');
    await tester.pump();
    expect(find.byKey(const Key('mark-m1')), findsNothing);
    expect(find.byKey(const Key('mark-m2')), findsOneWidget);
    expect(find.text('1 of 2 marks'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-search')), 'quick');
    await tester.pump();
    expect(find.byKey(const Key('mark-m2')), findsNothing);
    expect(
      find.text('No comment has these words.'),
      findsOneWidget,
      reason: 'the marked text is not searched',
    );
  });
}
