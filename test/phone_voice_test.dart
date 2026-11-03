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
    final spoken = await PlatformPhoneVoice().synthesize('Guten Tag.', Lang.de);
    expect(spoken.path, '/cache/tts/1.wav');
    expect(spoken.marks, isEmpty);
    expect(seen!.method, 'synthesize');
    expect(seen!.arguments, {'text': 'Guten Tag.', 'lang': 'de'});
  });

  // PLAN 18.3: where the engine says each word starts, in audio frames, becomes seconds.
  test('gets the engine’s word marks as places in the text and seconds into the audio', () async {
    answer(
      (call) async => {
        'path': '/cache/tts/2.wav',
        'rate': 22050,
        // Start, end and frame of each word.
        'marks': [0, 5, 0, 6, 9, 11025, 10, 13, 22050],
      },
    );
    final spoken = await PlatformPhoneVoice().synthesize('Guten Tag dir.', Lang.de);
    expect(spoken.path, '/cache/tts/2.wav');
    expect(spoken.marks, [(0, 0.0), (6, 0.5), (10, 1.0)]);
  });

  test('marks without the audio’s rate cannot be placed and are left out', () async {
    answer(
      (call) async => {
        'path': '/cache/tts/3.wav',
        'rate': 0,
        'marks': [0, 5, 0, 6, 8, 11025],
      },
    );
    expect((await PlatformPhoneVoice().synthesize('Hallo du.', Lang.de)).marks, isEmpty);
  });

  test('a failed synthesis throws, so the reader reports it', () async {
    answer((call) async => throw PlatformException(code: 'synthesis', message: 'engine stopped'));
    await expectLater(PlatformPhoneVoice().synthesize('Hi.', Lang.en), throwsA(isA<PlatformException>()));
  });
}
