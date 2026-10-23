// Port of the desktop's src/shared/utterances.ts.
import 'language.dart';
import 'layout.dart';
import 'segment.dart';
import 'types.dart';

// Endings after which a full stop does not end the sentence, even before a capital letter.
final _noBreak = RegExp(
  r'(?:^|[\s(])(?:z\.\s?B|d\.\s?h|u\.\s?a|o\.\s?ä|bzw|vgl|ca|Abb|Tab|Kap|Abs|Nr|Dr|Prof|Fig|Eq|Sec|Ref|No|vs|cf|i\.e|e\.g|et al|\p{L})\.\s*$',
  unicode: true,
);
final _germanOrdinal = RegExp(r'(?:^|\s)\d{1,2}\.\s*$', unicode: true);
final _openingQuote = RegExp('^[„“"«»‚‘]', unicode: true);
final _closingQuote = RegExp(r'[“”"«»‘’][\s.,;:!?)\]\d]*$', unicode: true);
// A colon that introduces a quotation or a full clause, which may be in another language.
final _introducingColon = RegExp(r':\s+(?=[„“"«»‚‘\p{Lu}])', unicode: true);
// Numeric citations such as [3] or [12, 15-17] are noise when read aloud.
final _citation = RegExp(r'\[\d+(?:\s*[,;–-]\s*\d+)*\]', unicode: true);
final _letters = RegExp(r'\p{L}+', unicode: true);
final _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _space = RegExp(r'\s+', unicode: true);
final _spaceBeforePunctuation = RegExp(r' ([.,;:!?])', unicode: true);

List<(int, int)> _sentenceSpans(String text, Lang lang) {
  final spans = <(int, int)>[];
  for (final s in sentenceSegments(text)) {
    final before = spans.isEmpty ? '' : text.substring(spans.last.$1, spans.last.$2);
    if (spans.isNotEmpty &&
        (_noBreak.hasMatch(before) || (lang == Lang.de && _germanOrdinal.hasMatch(before)))) {
      spans.last = (spans.last.$1, s.index + s.segment.length);
    } else {
      spans.add((s.index, s.index + s.segment.length));
    }
  }
  // "Sie schreiben: The method is simple." becomes two utterances, each with its own voice.
  int words(int from, int to) => _letters.allMatches(text.substring(from, to)).length;
  return [
    for (final (start, end) in spans)
      ...() {
        final parts = <(int, int)>[];
        var from = start;
        for (final colon in _introducingColon.allMatches(text.substring(start, end))) {
          final at = start + colon.end;
          if (words(from, at) >= 1 && words(at, end) >= 3) {
            parts.add((from, at));
            from = at;
          }
        }
        return [...parts, (from, end)];
      }(),
  ];
}

/// Splits a page's blocks into the sentences and headings the reader speaks, in order.
List<Utterance> buildUtterances(List<Block> blocks, int page, Lang documentLang) {
  final utterances = <Utterance>[];
  for (final block in blocks) {
    final spans = block.heading ? [(0, block.text.length)] : _sentenceSpans(block.text, documentLang);
    var insideQuote = false;
    for (final (start, end) in spans) {
      final text = block.text.substring(start, end).trim();
      if (!_letterOrNumber.hasMatch(text)) continue;
      final lang = sentenceLang(text, documentLang);

      final opens = _openingQuote.hasMatch(text);
      final role = block.heading
          ? Role.heading
          : opens || insideQuote
          ? Role.quote
          : Role.main;
      if (opens || insideQuote) insideQuote = !_closingQuote.hasMatch(text);

      // Blanking keeps every offset stable, so words still map back to the page.
      final masked = block.text
          .substring(start, end)
          .replaceAllMapped(_citation, (m) => ' ' * m.group(0)!.length);
      final words = <Word>[
        for (final w in wordSegments(masked))
          if (w.isWordLike)
            Word(w.segment, rawRanges(block.raw, start + w.index, start + w.index + w.segment.length)),
      ];
      if (words.isEmpty) continue;
      utterances.add(
        Utterance(
          page: page,
          text: text,
          spoken: masked
              .replaceAll(_space, ' ')
              .replaceAllMapped(_spaceBeforePunctuation, (m) => m.group(1)!)
              .trim(),
          lang: lang,
          role: role,
          words: words,
          ranges: rawRanges(block.raw, start, end),
        ),
      );
    }
  }
  return utterances;
}

/// The heading of a reference list, numbered or not: where reading may stop (desktop backlog 5). Layout
/// does not always see it as a heading (IEEE's "REFERENCES" is set in body size), so a sentence that is
/// nothing but the heading counts too.
final _referenceHeading = RegExp(
  r'^(?:(?:\d+(?:\.\d+)*|[IVX]+)\.?\s+)?(?:references|bibliography|literature|works cited|literatur|literaturverzeichnis|quellen|quellenverzeichnis)$',
  caseSensitive: false,
  unicode: true,
);

bool isReferenceHeading(String text) => _referenceHeading.hasMatch(text.trim());

/// A sentence's end: what a sentence cut by a page break lacks.
final _sentenceEnd = RegExp(r'[.!?…:]["”’»)\]]*$', unicode: true);

/// Whether `first`, the next page's first sentence, goes on `last`, this page's last (desktop ADR 12).
bool continuesOver(Utterance? last, Utterance? first) =>
    last != null &&
    first != null &&
    last.role != Role.heading &&
    first.role != Role.heading &&
    !_sentenceEnd.hasMatch(last.text);

/// Port of the desktop's `joinedPage`: a page's sentences with page breaks undone (desktop ADR 12, the
/// owner's rule of 2026-10-22). A sentence that starts on this page belongs to it whole, so the next
/// page's first sentence is joined on when this page's last one has no end, and this page's first
/// sentence is left out when it was joined onto the page before. The words of the continuation keep
/// their own page, so every raw range stays on the page it is on.
/// // shortcut: a word hyphenated over the page break is read as two. Upgrade if it is heard often.
List<Utterance> joinedPage(List<Utterance>? previous, List<Utterance> own, List<Utterance>? next) {
  final list = continuesOver(previous?.lastOrNull, own.firstOrNull) ? own.sublist(1) : [...own];
  final last = list.lastOrNull;
  final first = next?.firstOrNull;
  if (last == null || first == null || !continuesOver(last, first)) return list;
  list[list.length - 1] = Utterance(
    page: last.page,
    text: '${last.text} ${first.text}',
    spoken: '${last.spoken} ${first.spoken}',
    lang: last.lang,
    role: last.role,
    words: [
      ...last.words,
      for (final w in first.words) Word(w.text, w.ranges, page: first.page),
    ],
    ranges: last.ranges,
    next: (page: first.page, ranges: first.ranges),
  );
  return list;
}
