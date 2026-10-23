import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/scan_page.dart';
import 'package:pdfreader/shared/pairing.dart';

void main() {
  final secret = '0123456789abcdef' * 2;
  final good = 'pdfreader://pair?v=1&name=Mac&addr=10.0.0.5:47613&code=ABCD-EFGH-JKMN&secret=$secret';

  late void Function(String) read;
  PairingUrl? result;

  Future<void> open(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context).push<PairingUrl>(
                MaterialPageRoute(
                  builder: (_) => ScanPage(
                    scanner: (context, onText) {
                      read = onText;
                      return const SizedBox();
                    },
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('hands back what a pairing code holds, once', (tester) async {
    await open(tester);
    read(good);
    read(good);
    await tester.pumpAndSettle();
    expect(result!.name, 'Mac');
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('says so when the code is not one of ours, and goes on looking', (tester) async {
    await open(tester);
    read('https://example.com');
    await tester.pump();
    expect(find.text('That is not a pairing code from Easy Reader.'), findsOneWidget);
    read(good);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
  });
}
