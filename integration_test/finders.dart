import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync icon in the home screen's app bar (PLAN 7.5); it opens the Sync screen, where the
/// Desktops and Cloud screens used to be reached from two icons.
final syncButton = find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip?.startsWith('Sync:') ?? false),
  description: 'the sync icon',
);

/// The fixture in the home screen's lists; it can be in several (PLAN 9.2), the first is enough.
final sampleTile = find.text('sample.pdf').first;

/// The Home tab in the navigation bar, where a test returns after the Settings tab.
final homeTab = find.text('Home');

/// Closes the document, as reopening it is meant to: Back only hides the reader (PLAN 9.4), and
/// swiping the Now Playing bar away ends the session.
Future<void> closeDocument(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump(const Duration(seconds: 1));
  await tester.drag(find.byKey(const Key('now-playing')), const Offset(-600, 0));
  await tester.pump(const Duration(seconds: 2));
}
