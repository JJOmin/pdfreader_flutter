// Creates the sherpa-onnx engines, as the desktop's src/main/tts.ts does. The calls block, so the
// app makes them in the speech isolate, never on the UI thread.
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'catalog.dart';

/// Threads per engine. The phone's big cores; the desktop uses half its cores, at most eight.
const speechThreads = 4;

sherpa.OfflineTts createTts(SpeechModel model, String dir, {int threads = speechThreads}) {
  String at(String file) => '$dir/$file';
  final config = switch (model.engine) {
    'kokoro' => sherpa.OfflineTtsModelConfig(
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: at('model.onnx'),
        voices: at('voices.bin'),
        tokens: at('tokens.txt'),
        dataDir: at('espeak-ng-data'),
        lexicon: at('lexicon-us-en.txt'),
        lang: 'en-us',
      ),
      numThreads: threads,
      debug: false,
    ),
    'vits' => sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: at('${model.dir.replaceFirst('vits-piper-', '')}.onnx'),
        tokens: at('tokens.txt'),
        dataDir: at('espeak-ng-data'),
      ),
      numThreads: threads,
      debug: false,
    ),
    _ => throw ArgumentError('No speech engine for model "${model.id}"'),
  };
  return sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: config));
}

/// The recogniser that finds when each word is spoken in the synthesised audio.
sherpa.OfflineRecognizer createAligner(String dir) => sherpa.OfflineRecognizer(
  sherpa.OfflineRecognizerConfig(
    feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
    model: sherpa.OfflineModelConfig(
      nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: '$dir/model.int8.onnx'),
      tokens: '$dir/tokens.txt',
      numThreads: speechThreads,
      debug: false,
    ),
  ),
);
