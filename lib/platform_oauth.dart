import 'dart:async';

import 'package:flutter/services.dart';

/// Where a sign-in returns to the app (ADR 3 section 4): the addresses of the app's own scheme that
/// the browser sent the user back with, such as `io.github.jjomin.pdfreader:/oauth?code=…`.
abstract interface class OAuthRedirects {
  Stream<Uri> get uris;
}

/// Android: MainActivity.kt receives the address through an intent filter and sends it on here.
class AndroidOAuthRedirects implements OAuthRedirects {
  AndroidOAuthRedirects() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'redirect') _uris.add(Uri.parse(call.arguments as String));
    });
  }

  static const _channel = MethodChannel('pdfreader/oauth');
  final _uris = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uris => _uris.stream;
}

/// The address Dropbox sends the user back to. The owner registers it in the Dropbox app's settings.
const oauthRedirect = 'io.github.jjomin.pdfreader:/oauth';
