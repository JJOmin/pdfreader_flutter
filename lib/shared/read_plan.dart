// What the phone plays on a page: the desktop's prepared sentences placed on the phone's own text
// (desktop ADR 7 section 3, ADR 2 section 1). Raw ranges stay the phone's; the page's word
// sequence is the only thing the two sides share.
import 'align.dart';
import 'sync.dart';
import 'types.dart';

/// A sentence with prepared audio, placed on the phone's page.
class PlannedSentence {
  const PlannedSentence({
    required this.page,
    required this.key,
    required this.lang,
    required this.role,
    required this.words,
    required this.ranges,
    required this.timings,
    required this.duration,
  });

  final int page;

  /// Names the audio file.
  final String key;
  final Lang lang;
  final Role role;

  /// The phone's own words, with their raw ranges.
  final List<Word> words;
  final List<RawRange> ranges;

  /// One per word, in seconds of the audio.
  final List<WordTiming> timings;
  final double duration;
}

class PagePlan {
  const PagePlan(this.sentences, this.skipped);

  final List<PlannedSentence> sentences;

  /// The phone's sentences that have no audio and are not read.
  final int skipped;
}

List<WordTiming> _seconds(List<(int, int)> words) => [
  for (final (start, end) in words) WordTiming(start / 1000, end / 1000),
];

/// Joins the words' ranges into the sentence's, filling a gap between two words only where one
/// phone sentence covers it. So a running header between two of the phone's blocks stays untinted.
/// Where the sentence starts or ends with a phone sentence, it takes in that sentence's opening
/// quote or closing full stop too.
List<RawRange> _sentenceRanges(List<Word> words, List<Utterance> phone) {
  final covered = [for (final u in phone) ...u.ranges];
  final out = <RawRange>[];
  for (final range in words.expand((w) => w.ranges)) {
    if (out.isNotEmpty) {
      final (start, end) = out.last;
      final gap = (end, range.$1);
      if (gap.$1 <= gap.$2 && covered.any((c) => c.$1 <= gap.$1 && gap.$2 <= c.$2)) {
        out.last = (start, range.$2);
        continue;
      }
    }
    out.add(range);
  }
  for (final u in phone) {
    final (first, last) = (u.ranges.first, u.ranges.last);
    if (identical(u.words.first, words.first) && first.$1 <= out.first.$1 && out.first.$1 <= first.$2) {
      out.first = (first.$1, out.first.$2);
    }
    if (identical(u.words.last, words.last) && last.$1 <= out.last.$2 && out.last.$2 <= last.$2) {
      out.last = (out.last.$1, last.$2);
    }
  }
  return out;
}

/// Places a page's prepared sentences on the phone's sentences of the same page. `index` is null
/// when the page has none.
PagePlan planPage(List<Utterance> phone, PageIndex? index) {
  if (index == null) return PagePlan(const [], phone.length);
  final words = pageWords(phone);
  if (words.length == index.wordCount && wordsHash(words) == index.wordsHash) {
    final flat = [for (final u in phone) ...u.words];
    final roles = [
      for (final u in phone)
        for (final _ in u.words) u.role,
    ];
    return PagePlan([
      for (final s in index.sentences)
        PlannedSentence(
          page: phone.first.page,
          key: s.key,
          lang: s.lang,
          role: roles[s.from],
          words: flat.sublist(s.from, s.from + s.words.length),
          ranges: _sentenceRanges(flat.sublist(s.from, s.from + s.words.length), phone),
          timings: _seconds(s.words),
          duration: s.ms / 1000,
        ),
    ], 0);
  }

  // The engines found different words, which the spike never saw: match whole sentences by text.
  final byKey = <String, LibrarySentence>{};
  for (final s in index.sentences) {
    byKey.putIfAbsent(s.key, () => s);
  }
  final sentences = <PlannedSentence>[];
  for (final u in phone) {
    final s = byKey[syncKey(u.text)];
    if (s == null) continue;
    final duration = s.ms / 1000;
    sentences.add(
      PlannedSentence(
        page: u.page,
        key: s.key,
        lang: s.lang,
        role: u.role,
        words: u.words,
        ranges: u.ranges,
        timings: s.words.length == u.words.length
            ? _seconds(s.words)
            : estimateTimings([for (final w in u.words) w.text], duration),
        duration: duration,
      ),
    );
  }
  return PagePlan(sentences, phone.length - sentences.length);
}
