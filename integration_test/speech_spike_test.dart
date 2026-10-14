// PLAN step 1.8: can the phone run the desktop's speech models fast enough? Prints load time,
// time per second of audio, memory, and what the recogniser hears in each sentence.
//   flutter test integration_test/speech_spike_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfreader/speech/catalog.dart';
import 'package:pdfreader/speech/engines.dart';
import 'package:pdfreader/speech/model_files.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

int rssMb() {
  final line = File('/proc/self/status').readAsLinesSync().firstWhere((l) => l.startsWith('VmRSS:'));
  return int.parse(RegExp(r'\d+').firstMatch(line)!.group(0)!) ~/ 1024;
}

T timed<T>(String label, T Function() action) {
  final watch = Stopwatch()..start();
  final result = action();
  // ignore: avoid_print
  print('$label: ${watch.elapsedMilliseconds} ms, RSS ${rssMb()} MB');
  return result;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro speed by thread count', (tester) async {
    sherpa.initBindings();
    final models = (await modelsFolder())!;
    final kokoro = catalog.firstWhere((m) => m.id == 'kokoro');
    const text =
        'Wissenschaftliche Texte sind lang, so this sentence is long as well: it has commas, '
        'numbers such as 2024 and 3.5 percent, and it keeps going for a while before it ends.';
    for (final threads in [2, 3, 4, 6, 8]) {
      final tts = createTts(kokoro, installedDir(models, kokoro)!, threads: threads);
      final rates = <String>[];
      for (var run = 0; run < 3; run++) {
        final watch = Stopwatch()..start();
        final audio = tts.generate(text: text, sid: 16);
        rates.add(
          (watch.elapsedMilliseconds / 1000 / (audio.samples.length / audio.sampleRate)).toStringAsFixed(2),
        );
      }
      tts.free();
      // ignore: avoid_print
      print('kokoro threads $threads: ${rates.join(', ')} s per s of audio');
    }
  });

  testWidgets('speech models load, speak and are understood', (tester) async {
    sherpa.initBindings();
    final models = (await modelsFolder())!;
    SpeechModel model(String id) => catalog.firstWhere((m) => m.id == id);
    String dir(String id) => installedDir(models, model(id)) ?? (throw StateError('$id not installed'));
    // ignore: avoid_print
    print('start, RSS ${rssMb()} MB, threads $speechThreads');

    final aligner = timed('load aligner', () => createAligner(dir('aligner')));
    final sentences = {
      'piper-thorsten': (0, 'Die Verarbeitung erfolgt vollständig lokal auf dem eigenen Rechner.'),
      'kokoro': (16, 'The proposed method is simple and it does not need any training data at all.'),
    };
    for (final MapEntry(key: id, value: (sid, text)) in sentences.entries) {
      final tts = timed('load $id', () => createTts(model(id), dir(id)));
      for (final run in ['first', 'second']) {
        final watch = Stopwatch()..start();
        final audio = tts.generate(text: text, sid: sid);
        final seconds = audio.samples.length / audio.sampleRate;
        final synth = watch.elapsedMilliseconds / 1000;
        // ignore: avoid_print
        print(
          '$id $run: ${seconds.toStringAsFixed(2)} s audio in ${synth.toStringAsFixed(2)} s, '
          '${(synth / seconds).toStringAsFixed(2)} s per s of audio, RSS ${rssMb()} MB',
        );
        expect(seconds, greaterThan(1));
        if (run == 'second') {
          final heard = timed('recognise $id', () {
            final stream = aligner.createStream()
              ..acceptWaveform(samples: audio.samples, sampleRate: audio.sampleRate);
            aligner.decode(stream);
            final result = aligner.getResult(stream);
            stream.free();
            return result;
          });
          // ignore: avoid_print
          print('heard: "${heard.text}" (${heard.tokens.length} tokens, ${heard.timestamps.length} times)');
          expect(heard.tokens, isNotEmpty);
          expect(heard.timestamps, hasLength(heard.tokens.length));
          sherpa.writeWave(
            filename: '${models.parent.path}/spike-$id.wav',
            samples: audio.samples,
            sampleRate: audio.sampleRate,
          );
        }
      }
    }
  });
}
