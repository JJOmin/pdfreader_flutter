// The phone's own voice behind its platform channel: what a missing or failing engine means.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/phone_voice.dart';
import 'package:pdfreader/shared/types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdfreader/tts');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('lists the languages the engine speaks offline', () async {
    answer((call) async => ['de', 'en', 'fr']);
    expect(await PlatformPhoneVoice().languages(), {Lang.de, Lang.en});
  });

  test('no engine, or a platform without one, means no voice', () async {
    answer((call) async => throw PlatformException(code: 'no-engine'));
    expect(await PlatformPhoneVoice().languages(), isEmpty);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await PlatformPhoneVoice().languages(), isEmpty, reason: 'iOS has no channel yet');
  });

  test('asks for one sentence in its language and gets the file back', () async {
    MethodCall? seen;
    answer((call) async {
      seen = call;
      return '/cache/tts/1.wav';
    });
    expect(await PlatformPhoneVoice().synthesize('Guten Tag.', Lang.de), '/cache/tts/1.wav');
    expect(seen!.method, 'synthesize');
    expect(seen!.arguments, {'text': 'Guten Tag.', 'lang': 'de'});
  });

  test('a failed synthesis throws, so the reader reports it', () async {
    answer((call) async => throw PlatformException(code: 'synthesis', message: 'engine stopped'));
    await expectLater(PlatformPhoneVoice().synthesize('Hi.', Lang.en), throwsA(isA<PlatformException>()));
  });
}
