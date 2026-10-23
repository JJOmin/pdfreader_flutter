// Spoken comments end to end without a microphone or a model: the platform's chunks come in through
// the channel, a fake transcriber stands for the speech model.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/dictation.dart';
import 'package:pdfreader/speech/transcriber.dart';

class FakeTranscriber implements Transcriber {
  FakeTranscriber({this.missing, this.fails = false});

  final String? missing;
  final bool fails;
  final transcribed = <int>[];
  var warmed = 0;

  @override
  Future<String?> problem() async => missing;

  @override
  Future<void> warmUp() async => warmed++;

  @override
  Future<String> transcribe(Float32List samples) async {
    transcribed.add(samples.length);
    if (fails) throw StateError('no model');
    return 'words ${transcribed.length}';
  }
}

/// 100 ms of 16 kHz 16-bit samples at `amplitude`, as the microphone sends them.
Uint8List pcm(double amplitude) {
  final data = ByteData(3200);
  for (var i = 0; i < 1600; i++) {
    data.setInt16(i * 2, ((i.isEven ? 1 : -1) * amplitude * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdfreader/dictation');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  Object? startFails;

  setUp(() {
    calls = [];
    startFails = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start' && startFails != null) throw startFails!;
      return call.method == 'available' ? true : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> send(double amplitude, int chunks) async {
    for (var i = 0; i < chunks; i++) {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('chunk', pcm(amplitude))),
        (_) {},
      );
    }
  }

  test('listens until the speaker pauses, then writes out the whole recording once', () async {
    final transcriber = FakeTranscriber();
    final dictation = PlatformDictation(transcriber: transcriber, partialEvery: const Duration(hours: 1));
    final heard = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('start'));
    expect(transcriber.warmed, 1, reason: 'the model starts loading while the speaker begins');
    await send(0.002, 3);
    await send(0.2, 20);
    await send(0.002, 25);
    final result = await heard;
    expect(result.text, 'words 1');
    expect(result.error, isNull);
    expect(transcriber.transcribed, [
      65600,
    ], reason: '4.1 s: 0.3 s quiet, 2 s speech, 1.8 s pause; the rest is ignored');
    expect(calls, contains('stop'));
  });

  test('a stop writes out what was said so far', () async {
    final transcriber = FakeTranscriber();
    final dictation = PlatformDictation(transcriber: transcriber, partialEvery: const Duration(hours: 1));
    final heard = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    await send(0.2, 10);
    await dictation.stop();
    expect((await heard).text, 'words 1');
  });

  test('a cancel throws it away', () async {
    final transcriber = FakeTranscriber();
    final dictation = PlatformDictation(transcriber: transcriber, partialEvery: const Duration(hours: 1));
    final heard = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    await send(0.2, 10);
    await dictation.cancel();
    final result = await heard;
    expect(result.text, isNull);
    expect(result.error, isNull);
    expect(transcriber.transcribed, isEmpty);
  });

  test('says nothing was heard when only quiet came in', () async {
    final transcriber = FakeTranscriber();
    final dictation = PlatformDictation(transcriber: transcriber, partialEvery: const Duration(hours: 1));
    final heard = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    await send(0.002, 61);
    final result = await heard;
    expect(result.text, isNull);
    expect(result.error, isNull);
    expect(transcriber.transcribed, isEmpty, reason: 'no point in decoding silence');
  });

  test('shows the words so far while the speaker goes on', () async {
    final transcriber = FakeTranscriber();
    final dictation = PlatformDictation(
      transcriber: transcriber,
      partialEvery: const Duration(milliseconds: 20),
    );
    final partials = <String>[];
    final heard = dictation.listen(onPartial: partials.add);
    await Future<void>.delayed(Duration.zero);
    await send(0.2, 5);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(partials, isNotEmpty);
    await dictation.stop();
    await heard;
  });

  test('tells the user when the model is not on the phone, and never opens the microphone', () async {
    final dictation = PlatformDictation(
      transcriber: FakeTranscriber(missing: 'The speech model is not on this phone.'),
    );
    final result = await dictation.listen();
    expect(result.error, 'The speech model is not on this phone.');
    expect(calls, isNot(contains('start')));
  });

  test('tells the user when the microphone is refused', () async {
    startFails = PlatformException(code: 'permission', message: 'The microphone is not allowed');
    final dictation = PlatformDictation(transcriber: FakeTranscriber());
    final result = await dictation.listen();
    expect(result.error, 'The microphone is not allowed');
    // It can be tried again.
    startFails = null;
    final again = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    await dictation.cancel();
    expect((await again).error, isNull);
  });

  test('a failing model is reported, not swallowed', () async {
    final dictation = PlatformDictation(
      transcriber: FakeTranscriber(fails: true),
      partialEvery: const Duration(hours: 1),
    );
    final heard = dictation.listen();
    await Future<void>.delayed(Duration.zero);
    await send(0.2, 10);
    await dictation.stop();
    expect((await heard).error, contains('The speech model failed'));
  });

  test('is available where the platform side answers', () async {
    expect(await PlatformDictation(transcriber: FakeTranscriber()).available(), isTrue);
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await PlatformDictation(transcriber: FakeTranscriber()).available(),
      isFalse,
      reason: 'iOS, for now',
    );
  });
}
