// The grip on the right edge that scrolls a long text by dragging.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/views/fast_scroll.dart';

/// A plain scroll view behind the grip: the fraction is the offset, a jump goes there.
Widget view(ScrollController controller, {double content = 5000}) {
  double max() => controller.hasClients && controller.position.hasContentDimensions
      ? controller.position.maxScrollExtent
      : 0;
  return MaterialApp(
    home: Scaffold(
      body: FastScrollThumb(
        listenable: controller,
        fraction: () => max() > 0 ? controller.offset / max() : null,
        onJump: (f) => controller.jumpTo(f * max()),
        label: () => 'p${controller.offset.round()}',
        child: SingleChildScrollView(
          controller: controller,
          child: SizedBox(height: content, width: 300),
        ),
      ),
    ),
  );
}

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

  testWidgets('a screen reader steps it', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final handle = tester.ensureSemantics();
    final steps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FastScrollThumb(
          listenable: controller,
          fraction: () => 0.5,
          onJump: (_) {},
          onStep: steps.add,
          label: () => '3',
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Scroll'))).value, 'page 3');
    tester.semantics.increase(find.semantics.byLabel(RegExp('Scroll')));
    tester.semantics.decrease(find.semantics.byLabel(RegExp('Scroll')));
    expect(steps, [1, -1]);
    handle.dispose();
  });
}
