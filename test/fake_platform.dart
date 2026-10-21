// Stand-ins for the platform channels of lib/platform_secrets.dart, so that the sync code is
// tested without a phone.
import 'dart:async';

import 'package:pdfreader/platform_oauth.dart';
import 'package:pdfreader/platform_secrets.dart';

/// Records the addresses opened, and lets a test act as the user at the sign-in page.
class FakeBrowser implements Browser {
  FakeBrowser({this.onOpen});

  final void Function(Uri url)? onOpen;
  final opened = <Uri>[];

  @override
  Future<void> open(Uri url) async {
    opened.add(url);
    onOpen?.call(url);
  }
}

/// Keeps secrets in memory, scrambled enough that a test cannot read one by accident.
class FakeSecretBox implements SecretBox {
  @override
  Future<String> encrypt(String text) async => 'sealed:${text.split('').reversed.join()}';

  @override
  Future<String> decrypt(String sealed) async {
    if (!sealed.startsWith('sealed:')) throw StateError('not sealed');
    return sealed.substring(7).split('').reversed.join();
  }
}

/// The app's own scheme, as the sign-in returns to it: a test pushes what the browser would send.
class FakeRedirects implements OAuthRedirects {
  final _uris = StreamController<Uri>.broadcast();

  void add(Uri uri) => Future<void>.microtask(() => _uris.add(uri));

  @override
  Stream<Uri> get uris => _uris.stream;
}
