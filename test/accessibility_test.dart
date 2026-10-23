// Accessibility (PLAN M16): what a screen reader and a thumb need from the screens that the app
// builds itself. Flutter's own guidelines check the size of every tap target, that each has a label,
// and the contrast of the text, in each of the app's colour themes.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/app_settings_store.dart';
import 'package:pdfreader/app_theme.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/favourites_store.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart';
import 'package:pdfreader/now_playing.dart';
import 'package:pdfreader/places.dart';
import 'package:pdfreader/shared/app_settings.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfreader/views/fast_scroll.dart';
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

NotesActions get actions => NotesActions(
  onNotes: (_) {},
  onComment: (_, _) {},
  onStyle: (_, _, _) {},
  onDelete: (_) {},
  onJump: (_) {},
);

/// Each theme the app can wear, so that every guideline is checked in all of them.
const looks = {
  'light': Appearance(theme: ThemeChoice.light),
  'dark': Appearance(theme: ThemeChoice.dark),
  'sepia': Appearance(theme: ThemeChoice.sepia),
  'custom': Appearance(
    theme: ThemeChoice.custom,
    background: 0xFF0F1B2D,
    text: 0xFFFFD400,
    accent: 0xFFC2185B,
  ),
};

Future<void> guidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<void> openAppearance(WidgetTester tester, Appearance look) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('a11y-');
  addTearDown(() => dir.deleteSync(recursive: true));
  await tester.pumpWidget(
    PdfReaderApp(
      documents: DocumentAccess(),
      library: Library(Directory('${dir.path}/library')),
      favourites: FavouritesStore.inMemory(),
      appSettings: AppSettingsStore.inMemory(look),
      places: Places.inMemory(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: name, value: look) in looks.entries) {
    group('in the $name theme', () {
      testWidgets('Home, Favourites and Settings meet the guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await openAppearance(tester, look);
        await guidelines(tester);
        await tester.tap(find.text('Favourites'));
        await tester.pumpAndSettle();
        await guidelines(tester);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await guidelines(tester);
        handle.dispose();
      });

      testWidgets('Appearance and Speed reader meet the guidelines, every choice labelled', (tester) async {
        final handle = tester.ensureSemantics();
        await openAppearance(tester, look);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-appearance')));
        await tester.pumpAndSettle();
        await guidelines(tester);
        // The custom colours have rows of swatches that are only a colour.
        await tester.tap(find.byKey(const Key('theme-custom')));
        await tester.pumpAndSettle();
        await guidelines(tester);
        await tester.tap(find.byKey(const Key('settings-speed-reader')));
        await tester.pumpAndSettle();
        await guidelines(tester);
        handle.dispose();
      });

      testWidgets('a mark’s card meets them, closed and open', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorSchemeSeed: Colors.indigo),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarkCard(mark: mark, found: true, actions: actions),
              ),
            ),
          ),
        );
        await guidelines(tester);
        await tester.tap(find.byKey(const Key('edit-m1')));
        await tester.pumpAndSettle();
        await guidelines(tester);
        handle.dispose();
      });
    });
  }

  testWidgets('the grip for fast scrolling is a named control that can be moved without dragging', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastScrollThumb(
            controller: controller,
            label: () => '3',
            child: SingleChildScrollView(
              controller: controller,
              child: const SizedBox(height: 5000, width: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await guidelines(tester);
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Scroll')));
    expect(node.label, contains('Scroll'));
    expect(node.value, 'page 3');
    // A screen reader user moves it with the volume keys or a swipe: increase and decrease.
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
    final before = controller.offset;
    tester.semantics.increase(find.semantics.byLabel(RegExp('Scroll')));
    await tester.pump();
    expect(controller.offset, greaterThan(before));
    tester.semantics.decrease(find.semantics.byLabel(RegExp('Scroll')));
    await tester.pump();
    expect(controller.offset, closeTo(before, 0.01));
    handle.dispose();
  });

  for (final MapEntry(key: name, value: look) in looks.entries) {
    testWidgets('the play bar meets the guidelines in the $name theme, and says what a tap does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final themes = appThemes(look);
      await tester.pumpWidget(
        MaterialApp(
          theme: themes.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: NowPlayingBar(
                session: ReadingSession(name: 'Paper.pdf', data: Uint8List(0), placeKey: 'k'),
                onOpen: () {},
                colors: (
                  bar: themes.light.colorScheme.surfaceContainerHigh,
                  onBar: themes.light.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
      await guidelines(tester);
      expect(find.bySemanticsLabel(RegExp('Open the player')), findsOneWidget);
      handle.dispose();
    });
  }
}
