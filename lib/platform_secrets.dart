// The two small platform channels of ADR 3: the Android Keystore for secrets, and the browser for
// the sign-in pages. Both are interfaces first, so that the sync code is tested without a phone.
import 'package:flutter/services.dart';

/// Keeps secrets safe at rest: what is encrypted here can only be decrypted on this phone, by this app.
abstract interface class SecretBox {
  /// Text in, an opaque string out, which is safe to write to the app's storage.
  Future<String> encrypt(String text);
  Future<String> decrypt(String sealed);
}

/// The Android Keystore: MainActivity.kt, channel `pdfreader/secrets`.
class KeystoreSecretBox implements SecretBox {
  static const _channel = MethodChannel('pdfreader/secrets');

  @override
  Future<String> encrypt(String text) async => (await _channel.invokeMethod<String>('encrypt', text))!;

  @override
  Future<String> decrypt(String sealed) async => (await _channel.invokeMethod<String>('decrypt', sealed))!;
}

/// Opens a web address in the user's own browser.
abstract interface class Browser {
  Future<void> open(Uri url);
}

/// MainActivity.kt, channel `pdfreader/browser`.
class SystemBrowser implements Browser {
  static const _channel = MethodChannel('pdfreader/browser');

  @override
  Future<void> open(Uri url) => _channel.invokeMethod<void>('open', url.toString());
}
