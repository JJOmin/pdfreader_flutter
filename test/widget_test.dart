import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_access.dart';
import 'package:pdfreader/main.dart';

class _CancelledPicker extends DocumentAccess {
  int calls = 0;

  @override
  Future<OpenedDocument?> pickPdf() async {
    calls++;
    return null;
  }
}

void main() {
  testWidgets('starts with an open button and stays empty when the picker is cancelled', (tester) async {
    final picker = _CancelledPicker();
    await tester.pumpWidget(PdfReaderApp(documents: picker));
    await tester.tap(find.widgetWithText(FilledButton, 'Open a PDF'));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('PDF Reader'), findsOneWidget);
  });
}
