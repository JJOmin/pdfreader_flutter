// Port of the desktop's src/shared/settings.ts, with the settings types from types.ts.
// Inputs are whatever jsonDecode gives, so every reader checks types itself.
import 'dart:math' as math;

import 'types.dart';

const minSpeed = 0.6;
const maxSpeed = 2.0;

// shortcut: the desktop's font list, kept so a settings file reads the same on both. Verdana,
// Comic Sans MS, Arial and Georgia cannot be bundled on the phone; PLAN step 3.4 decides.
const readingFonts = ['OpenDyslexic', 'Lexend', 'Verdana', 'Comic Sans MS', 'Arial', 'Georgia'];
const readingThemes = ['light', 'sepia', 'dark'];

/// Allowed range of each numeric reading setting: minimum, maximum, slider step.
const readingLimits = {
  'size': (14.0, 40.0, 1.0),
  'lineHeight': (1.2, 2.6, 0.1),
  // Below zero, because some fonts, OpenDyslexic above all, are set very wide already.
  'letterSpacing': (-0.08, 0.2, 0.01),
};

/// The zoom of the PDF pages: smallest and largest scale, 1 being 100 %.
const zoomLimits = (0.3, 5.0);

/// Documents whose place is remembered; the one not opened for longest is forgotten first.
const progressLimit = 300;

/// How the reading view sets its text.
class ReadingSettings {
  const ReadingSettings({
    required this.font,
    required this.size,
    required this.lineHeight,
    required this.letterSpacing,
    required this.theme,
  });

  final String font;

  /// Font size in logical pixels.
  final double size;

  /// Line height as a multiple of the font size.
  final double lineHeight;

  /// Extra space between letters, in em.
  final double letterSpacing;
  final String theme;

  Map<String, Object?> toJson() => {
    'font': font,
    'size': size,
    'lineHeight': lineHeight,
    'letterSpacing': letterSpacing,
    'theme': theme,
  };
}

class Settings {
  const Settings({
    required this.speed,
    required this.voices,
    required this.reading,
    required this.focusMode,
    required this.polish,
  });

  /// Multiplier applied on top of every voice.
  final double speed;
  final Map<Lang, Map<Role, VoiceRef?>> voices;
  final ReadingSettings reading;

  /// While reading aloud, keep the spoken sentence in the middle of the view.
  final bool focusMode;

  /// Fade each sentence in and out and cut rumble below the voice, when it is played.
  final bool polish;

  Map<String, Object?> toJson() => {
    'speed': speed,
    'voices': {
      for (final lang in Lang.values)
        lang.name: {for (final role in Role.values) role.name: voices[lang]![role]?.toJson()},
    },
    'reading': reading.toJson(),
    'focusMode': focusMode,
    'polish': polish,
  };
}

// The desktop's defaults. Where a voice is not installed on the phone, resolveVoice picks the
// language's main voice or any voice for the language instead.
Settings defaultSettings() => const Settings(
  speed: 1,
  voices: {
    Lang.en: {
      Role.main: VoiceRef('kokoro', 16),
      Role.quote: VoiceRef('kokoro', 2),
      Role.heading: VoiceRef('supertonic', 9),
    },
    Lang.de: {
      Role.main: VoiceRef('supertonic', 9),
      Role.quote: VoiceRef('supertonic', 7),
      Role.heading: VoiceRef('supertonic', 1),
    },
  },
  reading: ReadingSettings(font: 'Verdana', size: 20, lineHeight: 1.7, letterSpacing: 0.03, theme: 'sepia'),
  focusMode: false,
  polish: false,
);

Map<String, Object?> _object(Object? value) => value is Map<String, Object?> ? value : const {};

bool _isInteger(Object? v) => v is num && v.isFinite && v == v.roundToDouble();

VoiceRef? _voice(Object? v) {
  final map = _object(v);
  final model = map['model'];
  final sid = map['sid'];
  return model is String && _isInteger(sid) ? VoiceRef(model, (sid! as num).toInt()) : null;
}

double _clamp(Object? value, double min, double max, double fallback) =>
    value is num && value.isFinite ? math.min(max, math.max(min, value.toDouble())) : fallback;

/// Builds valid settings from anything read from disk.
Settings normalizeSettings(Object? value) {
  final defaults = defaultSettings();
  final input = _object(value);
  final inputVoices = _object(input['voices']);
  final voices = <Lang, Map<Role, VoiceRef?>>{};
  for (final lang in Lang.values) {
    final forLang = _object(inputVoices[lang.name]);
    voices[lang] = {
      for (final role in Role.values)
        role: switch (forLang[role.name]) {
          final v when _voice(v) != null => _voice(v),
          null when forLang.containsKey(role.name) && role != Role.main => null,
          _ => defaults.voices[lang]![role],
        },
    };
  }
  final reading = _object(input['reading']);
  final d = defaults.reading;
  double limited(String key, double fallback) {
    final (min, max, _) = readingLimits[key]!;
    return _clamp(reading[key], min, max, fallback);
  }

  return Settings(
    speed: _clamp(input['speed'], minSpeed, maxSpeed, defaults.speed),
    voices: voices,
    reading: ReadingSettings(
      font: readingFonts.contains(reading['font']) ? reading['font']! as String : d.font,
      size: limited('size', d.size),
      lineHeight: limited('lineHeight', d.lineHeight),
      letterSpacing: limited('letterSpacing', d.letterSpacing),
      theme: readingThemes.contains(reading['theme']) ? reading['theme']! as String : d.theme,
    ),
    focusMode: input['focusMode'] is bool ? input['focusMode']! as bool : defaults.focusMode,
    polish: input['polish'] is bool ? input['polish']! as bool : defaults.polish,
  );
}

/// Picks the voice for a sentence from those installed: the role's voice, else the
/// language's main voice, else any voice that speaks the language, else any voice at all.
VoiceRef? resolveVoice(Settings settings, List<VoiceOption> available, Lang lang, Role role) {
  bool has(VoiceRef? v) =>
      v != null && available.any((o) => o.model == v.model && o.sid == v.sid && o.langs.contains(lang));
  for (final candidate in [settings.voices[lang]![role], settings.voices[lang]![Role.main]]) {
    if (has(candidate)) return candidate;
  }
  for (final o in available) {
    if (o.langs.contains(lang)) return VoiceRef(o.model, o.sid);
  }
  return available.isEmpty ? null : VoiceRef(available.first.model, available.first.sid);
}

/// Where the user was in a document, so that it opens there again.
class Progress {
  const Progress({
    required this.view,
    required this.zoom,
    required this.page,
    required this.offset,
    required this.sentence,
  });

  /// 'pdf' or 'reading'.
  final String view;

  /// The pages' zoom, 1 being 100 %, or null for fit to width.
  final double? zoom;

  /// The page at the top of the view, and how far down it the top edge lies, from 0 to 1.
  final int page;
  final double offset;

  /// The sentence the voice read last: its page and its place among that page's sentences.
  final ({int page, int index})? sentence;

  Map<String, Object?> toJson() => {
    'view': view,
    'zoom': zoom,
    'page': page,
    'offset': offset,
    'sentence': sentence == null ? null : {'page': sentence!.page, 'index': sentence!.index},
  };
}

int? _integer(Object? value, int min) =>
    _isInteger(value) && (value! as num) >= min ? (value as num).toInt() : null;

/// Builds a valid place in a document from anything read from disk.
Progress? normalizeProgress(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final page = _integer(value['page'], 1);
  if (page == null) return null;
  final sentence = _object(value['sentence']);
  final sentencePage = _integer(sentence['page'], 1);
  final sentenceIndex = _integer(sentence['index'], 0);
  final zoom = value['zoom'];
  final offset = value['offset'];
  return Progress(
    view: value['view'] == 'reading' ? 'reading' : 'pdf',
    zoom: zoom is num && zoom.isFinite
        ? math.min(zoomLimits.$2, math.max(zoomLimits.$1, zoom.toDouble()))
        : null,
    page: page,
    offset: offset is num && offset.isFinite ? math.min(0.999, math.max(0, offset.toDouble())) : 0,
    sentence: sentencePage != null && sentenceIndex != null
        ? (page: sentencePage, index: sentenceIndex)
        : null,
  );
}

/// Everything remembered about documents, keyed by the document's URI.
class ProgressStore {
  ProgressStore(this.documents);

  Map<String, ({Progress progress, num updated})> documents;

  Map<String, Object?> toJson() => {
    'version': 1,
    'documents': {
      for (final MapEntry(:key, :value) in documents.entries)
        key: {...value.progress.toJson(), 'updated': value.updated},
    },
  };
}

/// Reads the progress file, which may hold anything: entries that are not valid are dropped.
ProgressStore parseProgressStore(Object? value) {
  final store = ProgressStore({});
  final documents = _object(value)['documents'];
  if (documents is! Map<String, Object?>) return store;
  documents.forEach((key, entry) {
    final progress = normalizeProgress(entry);
    final updated = _object(entry)['updated'];
    if (progress != null && updated is num && updated.isFinite) {
      store.documents[key] = (progress: progress, updated: updated);
    }
  });
  return store;
}

/// Records a document's place, and forgets the documents untouched for longest above the limit.
void rememberProgress(ProgressStore store, String key, Progress progress, num now) {
  store.documents[key] = (progress: progress, updated: now);
  if (store.documents.length <= progressLimit) return;
  final keys = store.documents.keys.toList();
  // Ties keep their stored order, like the desktop's stable sort.
  final order = List.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final byTime = store.documents[keys[b]]!.updated.compareTo(store.documents[keys[a]]!.updated);
      return byTime != 0 ? byTime : a - b;
    });
  final newest = {for (final i in order.take(progressLimit)) keys[i]};
  store.documents.removeWhere((key, _) => !newest.contains(key));
}
