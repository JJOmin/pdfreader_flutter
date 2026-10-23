// The grip on the right edge that scrolls a long text by dragging.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/views/fast_scroll.dart';

Widget view(ScrollController controller, {double content = 5000}) => MaterialApp(
  home: Scaffold(
    body: FastScrollThumb(
      controller: controller,
      label: () => 'p${controller.offset.round()}',
      child: SingleChildScrollView(
        controller: controller,
        child: SizedBox(height: content, width: 300),
      ),
    ),
  ),
);

void main() {
  testWidgets('dragging the grip to the bottom of the screen scrolls to the end of the text', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller));
    await tester.pump();
    expect(find.byKey(const Key('fast-scroll')), findsOneWidget);
    // One drag of the whole height of the screen goes through the whole text.
    await tester.drag(find.byKey(const Key('fast-scroll')), const Offset(0, 800));
    await tester.pump();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('a short drag scrolls in proportion, and the grip follows a flick of the text itself', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller));
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(const Key('fast-scroll'))).dy;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pump();
    final middle = tester.getTopLeft(find.byKey(const Key('fast-scroll'))).dy;
    expect(middle, greaterThan(before + 100));
    expect(middle, lessThan(600));
  });

  testWidgets('a text that fits the screen has no grip', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller, content: 100));
    await tester.pump();
    expect(find.byKey(const Key('fast-scroll')), findsNothing);
  });
}
