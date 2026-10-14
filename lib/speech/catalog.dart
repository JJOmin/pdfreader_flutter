import '../shared/types.dart';

/// A speech model from the desktop's models.json, limited to the ones the phone runs (ADR 1).
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.label,
    required this.engine,
    required this.dir,
    required this.langs,
    required this.speakers,
  });

  final String id;
  final String label;

  /// 'kokoro', 'vits' or 'aligner'.
  final String engine;

  /// Folder under the models folder, the same name as on the desktop.
  final String dir;
  final List<Lang> langs;

  /// Speaker names by `sid`, in ascending `sid` order like the desktop's voice list.
  final Map<int, String> speakers;
}

// shortcut: a copy of three entries of ../pdfreader/models.json; read that file as an asset if
// the phone ever offers more models than these.
const catalog = [
  SpeechModel(
    id: 'kokoro',
    label: 'Kokoro',
    engine: 'kokoro',
    dir: 'kokoro-multi-lang-v1_0',
    langs: [Lang.en],
    speakers: {
      2: 'Bella (US, female)',
      3: 'Heart (US, female)',
      6: 'Nicole (US, female)',
      14: 'Fenrir (US, male)',
      16: 'Michael (US, male)',
      21: 'Emma (UK, female)',
      24: 'Daniel (UK, male)',
      26: 'George (UK, male)',
    },
  ),
  SpeechModel(
    id: 'piper-thorsten',
    label: 'Piper Thorsten',
    engine: 'vits',
    dir: 'vits-piper-de_DE-thorsten-high',
    langs: [Lang.de],
    speakers: {0: 'Thorsten (male)'},
  ),
  SpeechModel(
    id: 'aligner',
    label: 'Word aligner (speech recogniser)',
    engine: 'aligner',
    dir: 'sherpa-onnx-nemo-fast-conformer-ctc-en-de-es-fr-14288-int8',
    langs: [Lang.en, Lang.de],
    speakers: {},
  ),
];
