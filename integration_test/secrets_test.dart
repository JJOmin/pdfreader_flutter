// ADR 3 section 5 on the phone: the Keystore box keeps a secret that only this app can open.
//   flutter test integration_test/secrets_test.dart --no-uninstall
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/platform_secrets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Keystore box round trips and hides a secret', (tester) async {
    final box = KeystoreSecretBox();
    const secret = '{"password":"app-password ä ö ü 😀","key":"abc"}';
    final sealed = await box.encrypt(secret);
    expect(sealed, isNot(contains('app-password')));
    expect(await box.decrypt(sealed), secret);
    // Fresh each time: a random IV.
    expect(await box.encrypt(secret), isNot(sealed));
    // A changed value is refused, not read as something else.
    final changed = '${sealed.substring(0, sealed.length - 4)}AAAA';
    await expectLater(box.decrypt(changed), throwsA(isA<PlatformException>()));
    await expectLater(box.decrypt('not base64 !!'), throwsA(isA<PlatformException>()));
  });

  testWidgets('the browser channel refuses an address that is not a web page', (tester) async {
    await expectLater(
      SystemBrowser().open(Uri.parse('file:///etc/hosts')),
      throwsA(isA<PlatformException>()),
    );
  });
}
