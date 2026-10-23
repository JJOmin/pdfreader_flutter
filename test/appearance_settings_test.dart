// Settings, Appearance (PLAN M15): the colours, the font and its size for the whole app, and the
// Speed reader page with the reading view's own type.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/app_settings_store.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/favourites_store.dart';
import 'package:pdfreader/library.dart';
import 'package:pdfreader/main.dart';
import 'package:pdfreader/places.dart';
import 'package:pdfreader/shared/app_settings.dart';

Future<(AppSettingsStore, Places)> openAppearance(WidgetTester tester) async {
  // Tall, so that the whole page is on screen at once.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('appearance-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final settings = AppSettingsStore.inMemory();
  final places = Places.inMemory();
  await tester.pumpWidget(
    PdfReaderApp(
      documents: DocumentAccess(),
      library: Library(Directory('${dir.path}/library')),
      favourites: FavouritesStore.inMemory(),
      appSettings: settings,
      places: places,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings-appearance')));
  await tester.pumpAndSettle();
  return (settings, places);
}

ThemeData appTheme(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).last));

void main() {
  testWidgets('sepia colours the whole app, and the other choices take it back', (tester) async {
    final (settings, _) = await openAppearance(tester);
    await tester.tap(find.byKey(const Key('theme-sepia')));
    await tester.pumpAndSettle();
    expect(settings.value.theme, ThemeChoice.sepia);
    expect(appTheme(tester).colorScheme.surface, const Color(0xFFF4ECD8));
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, isNull);
    expect(appTheme(tester).scaffoldBackgroundColor, const Color(0xFFF4ECD8));

    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();
    expect(appTheme(tester).colorScheme.surface, isNot(const Color(0xFFF4ECD8)));
  });

  testWidgets('custom shows the colour rows; the chosen colours paint the app', (tester) async {
    final (settings, _) = await openAppearance(tester);
    expect(find.byKey(const Key('custom-background-ff0f1b2d')), findsNothing);
    await tester.tap(find.byKey(const Key('theme-custom')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('custom-background-ff0f1b2d')));
    await tester.tap(find.byKey(const Key('custom-background-ff0f1b2d')));
    await tester.pumpAndSettle();
    expect(settings.value.background, 0xFF0F1B2D);
    expect(
      contrastRatio(settings.value.text, settings.value.background),
      greaterThanOrEqualTo(minContrast),
      reason: 'the dark text was swapped for one that reads on the dark background',
    );
    expect(appTheme(tester).colorScheme.surface, const Color(0xFF0F1B2D));
    expect(appTheme(tester).brightness, Brightness.dark);

    // The text colour that the background would hide cannot be chosen.
    final dim = find.byKey(const Key('custom-text-ff1f1f1f'));
    await tester.ensureVisible(dim);
    await tester.tap(dim, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(settings.value.text, isNot(0xFF1F1F1F));

    await tester.ensureVisible(find.byKey(const Key('custom-accent-fff57c00')));
    await tester.tap(find.byKey(const Key('custom-accent-fff57c00')));
    await tester.pumpAndSettle();
    expect(settings.value.accent, 0xFFF57C00);
  });

  testWidgets('the font is the whole app’s: a choice changes the theme’s font', (tester) async {
    final (settings, _) = await openAppearance(tester);
    await tester.ensureVisible(find.byKey(const Key('font-Lexend')));
    await tester.tap(find.byKey(const Key('font-Lexend')));
    await tester.pumpAndSettle();
    expect(settings.value.font, 'Lexend');
    expect(appTheme(tester).textTheme.bodyMedium?.fontFamily, 'Lexend');
  });

  testWidgets('the text size slider scales the text of the whole app', (tester) async {
    final (settings, _) = await openAppearance(tester);
    final before = tester.getSize(find.text('Appearance').first).height;
    final slider = find.byKey(const Key('font-scale'));
    await tester.ensureVisible(slider);
    // To the right end of the slider: the largest text.
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(settings.value.fontScale, 1.6);
    expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).last)).scale(10), closeTo(16, 0.01));
    expect(tester.getSize(find.text('Appearance').first).height, greaterThan(before));
  });

  testWidgets('Speed reader is a page under Appearance: font, size and spacing, and no colours', (
    tester,
  ) async {
    final (_, places) = await openAppearance(tester);
    await tester.ensureVisible(find.byKey(const Key('settings-speed-reader')));
    await tester.tap(find.byKey(const Key('settings-speed-reader')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Line spacing'), findsOneWidget);
    expect(find.text('Letter spacing'), findsOneWidget);
    expect(find.text('Lexend'), findsOneWidget);
    // Its colours are the app's now.
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Sepia'), findsNothing);
    expect(find.byKey(const Key('speed-reader-preview')), findsOneWidget);

    await tester.tap(find.text('Lexend'));
    await tester.pumpAndSettle();
    expect(places.reading.font, 'Lexend');
    final preview = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('speed-reader-preview')), matching: find.byType(Text)),
    );
    expect(preview.style?.fontFamily, 'Lexend');
  });
}
