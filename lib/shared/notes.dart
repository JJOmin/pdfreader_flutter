// Port of the desktop's src/shared/notes.ts, with the notes types from its types.ts. The file is
// the same as the desktop's, so a notes file moves between the two unchanged.
import 'dart:convert';
import 'dart:math';

enum HighlightColor { yellow, green, blue, red }

enum MarkKind { highlight, underline, strike }

class Annotation {
  const Annotation({
    required this.id,
    required this.page,
    required this.start,
    required this.end,
    required this.text,
    required this.quote,
    required this.kind,
    required this.color,
    required this.comment,
    required this.created,
  });

  final String id;
  final int page;
  final int start;
  final int end;

  /// The marked slice of the page's raw string, kept so the mark can be found again if offsets shift.
  final String text;

  /// The same passage as readable text: lines joined, hyphenation undone. Shown to the user.
  final String quote;
  final MarkKind kind;
  final HighlightColor color;
  final String comment;
  final String created;

  Annotation copyWith({
    int? start,
    int? end,
    String? text,
    String? comment,
    MarkKind? kind,
    HighlightColor? color,
  }) => Annotation(
    id: id,
    page: page,
    start: start ?? this.start,
    end: end ?? this.end,
    text: text ?? this.text,
    quote: quote,
    kind: kind ?? this.kind,
    color: color ?? this.color,
    comment: comment ?? this.comment,
    created: created,
  );

  /// The keys in the order the desktop writes them.
  Map<String, Object?> toJson() => {
    'id': id,
    'page': page,
    'start': start,
    'end': end,
    'text': text,
    'quote': quote,
    'kind': kind.name,
    'color': color.name,
    'comment': comment,
    'created': created,
  };
}

class NotesFile {
  const NotesFile({required this.notes, required this.annotations});

  /// The general notes on the document.
  final String notes;
  final List<Annotation> annotations;

  Map<String, Object?> toJson() => {
    'version': 1,
    'notes': notes,
    'annotations': [for (final a in annotations) a.toJson()],
  };
}

NotesFile emptyNotes() => const NotesFile(notes: '', annotations: []);

/// What `JSON.stringify(notes, null, 2)` writes: two-space indent, keys in order, no final newline.
String encodeNotes(NotesFile file) => const JsonEncoder.withIndent('  ').convert(file.toJson());

bool _isInt(Object? v) => v is num && v.isFinite && v == v.roundToDouble();

/// Validates a parsed notes file and fills in fields that older files lack.
/// Returns null for anything that is not a notes file.
NotesFile? parseNotes(Object? value) {
  if (value is! Map<String, Object?> || value['version'] != 1) return null;
  final notes = value['notes'];
  final list = value['annotations'];
  if (notes is! String || list is! List) return null;
  final annotations = <Annotation>[];
  for (final entry in list) {
    if (entry is! Map<String, Object?>) return null;
    final kind = MarkKind.values.where((k) => k.name == (entry['kind'] ?? 'highlight')).firstOrNull;
    final color = HighlightColor.values.where((c) => c.name == entry['color']).firstOrNull;
    final Object? id = entry['id'], text = entry['text'], comment = entry['comment'];
    if (id is! String || text is! String || comment is! String || kind == null || color == null) return null;
    if (!_isInt(entry['page']) || !_isInt(entry['start']) || !_isInt(entry['end'])) return null;
    final quote = entry['quote'];
    final created = entry['created'];
    annotations.add(
      Annotation(
        id: id,
        page: (entry['page']! as num).toInt(),
        start: (entry['start']! as num).toInt(),
        end: (entry['end']! as num).toInt(),
        text: text,
        quote: quote is String ? quote : text,
        kind: kind,
        color: color,
        comment: comment,
        created: created is String ? created : '',
      ),
    );
  }
  return NotesFile(notes: notes, annotations: annotations);
}

final _space = RegExp(r'\s+', unicode: true);

/// A pattern for `text` that accepts any whitespace, or none, wherever the text has some, and
/// between any two characters: the two engines' raw strings differ in exactly that (PDF.js has no
/// character at a line end, PDFium has an inserted space).
RegExp _tolerant(String text) {
  final chars = text.replaceAll(_space, '').runes.map((r) => RegExp.escape(String.fromCharCode(r)));
  return RegExp(chars.join(r'\s*'), unicode: true);
}

/// Checks an annotation against the page's raw text and moves it if the text sits elsewhere.
/// Returns null when the text is gone, for example after the PDF was replaced.
Annotation? reanchor(Annotation annotation, String pageRaw) {
  if (annotation.start >= 0 &&
      annotation.end <= pageRaw.length &&
      annotation.start <= annotation.end &&
      pageRaw.substring(annotation.start, annotation.end) == annotation.text) {
    return annotation;
  }
  final exact = pageRaw.indexOf(annotation.text);
  if (exact >= 0) {
    return annotation.copyWith(start: exact, end: exact + annotation.text.length);
  }
  if (annotation.text.trim().isEmpty) return null;
  final match = _tolerant(annotation.text).firstMatch(pageRaw);
  if (match == null) return null;
  return annotation.copyWith(start: match.start, end: match.end, text: match.group(0));
}

List<Annotation> sortAnnotations(List<Annotation> annotations) =>
    [...annotations]..sort((a, b) => a.page != b.page ? a.page - b.page : a.start - b.start);

/// Renders notes and marks as a Markdown review document.
String toMarkdown(String title, NotesFile file) {
  final out = <String>['# Notes on $title', ''];
  if (file.notes.trim().isNotEmpty) out.addAll([file.notes.trim(), '']);
  var page = 0;
  for (final a in sortAnnotations(file.annotations)) {
    if (a.page != page) {
      page = a.page;
      out.addAll(['## Page $page', '']);
    }
    final quote = a.quote.replaceAll(_space, ' ').trim();
    out.addAll(['> ${a.kind == MarkKind.strike ? '~~$quote~~' : quote}', '']);
    if (a.comment.trim().isNotEmpty) out.addAll([a.comment.trim(), '']);
  }
  return out.join('\n');
}

/// A JavaScript `toISOString`: milliseconds and a Z. Dart's own would write microseconds.
String isoNow([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.${utc.millisecond.toString().padLeft(3, '0')}Z';
}

final _random = Random.secure();

/// A random version 4 UUID, as the desktop's `crypto.randomUUID` gives.
String newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
