import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/endpoint.dart';

/// `ms` of a constant-amplitude signal at 16 kHz, alternating sign so it is not a DC offset.
Float32List tone(int ms, double amplitude) =>
    Float32List.fromList([for (var i = 0; i < 16 * ms; i++) i.isEven ? amplitude : -amplitude]);

const quiet = 0.002;
const loud = 0.15;

/// Feeds 100 ms chunks: `ms` of `amplitude`.
void feed(Endpointer e, int ms, double amplitude) {
  for (var t = 0; t < ms; t += 100) {
    e.accept(tone(100, amplitude));
  }
}

void main() {
  group('pcm16ToFloat', () {
    test('turns little-endian 16-bit samples into floats between -1 and 1', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0x00, 0x40]);
      final floats = pcm16ToFloat(bytes);
      expect(floats, hasLength(4));
      expect(floats[0], 0);
      expect(floats[1], closeTo(1, 1e-3));
      expect(floats[2], -1);
      expect(floats[3], closeTo(0.5, 1e-3));
    });

    test('ignores a half sample at the end', () {
      expect(pcm16ToFloat(Uint8List.fromList([1, 0, 2])), hasLength(1));
    });
  });

  group('Endpointer', () {
    test('stays open while someone is speaking', () {
      final e = Endpointer();
      feed(e, 500, quiet);
      feed(e, 3000, loud);
      expect(e.heardSpeech, isTrue);
      expect(e.finished, isFalse);
    });

    test('ends after a pause that follows speech', () {
      final e = Endpointer();
      feed(e, 300, quiet);
      feed(e, 2000, loud);
      feed(e, 1700, quiet);
      expect(e.finished, isFalse, reason: 'a breath between two words is not the end');
      feed(e, 200, quiet);
      expect(e.finished, isTrue);
      expect(e.reason, EndReason.pause);
    });

    test('a pause in the middle does not end it if speech comes back in time', () {
      final e = Endpointer();
      feed(e, 1000, loud);
      feed(e, 1500, quiet);
      feed(e, 1000, loud);
      feed(e, 1500, quiet);
      expect(e.finished, isFalse);
    });

    test('gives up when nothing is said', () {
      final e = Endpointer();
      feed(e, 5900, quiet);
      expect(e.finished, isFalse);
      feed(e, 200, quiet);
      expect(e.finished, isTrue);
      expect(e.reason, EndReason.nothingSaid);
      expect(e.heardSpeech, isFalse);
    });

    test('a click is not speech', () {
      final e = Endpointer();
      feed(e, 2000, quiet);
      e.accept(tone(50, loud));
      feed(e, 4500, quiet);
      expect(e.heardSpeech, isFalse);
      expect(e.reason, EndReason.nothingSaid);
    });

    test('stops at the longest length', () {
      final e = Endpointer(maxLength: const Duration(seconds: 10));
      feed(e, 9900, loud);
      expect(e.finished, isFalse);
      feed(e, 200, loud);
      expect(e.finished, isTrue);
      expect(e.reason, EndReason.tooLong);
    });

    test('speech over a steady hum is still heard, the hum alone is not', () {
      final hum = Endpointer();
      feed(hum, 8000, 0.02);
      expect(hum.heardSpeech, isFalse);

      final over = Endpointer();
      feed(over, 1000, 0.02);
      feed(over, 1000, 0.3);
      expect(over.heardSpeech, isTrue);
    });

    test('keeps what it was given, so the whole recording can be recognised', () {
      final e = Endpointer();
      feed(e, 300, loud);
      expect(e.samples, hasLength(16 * 300));
    });
  });
}
