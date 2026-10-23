// What the phone plays on a page: the desktop's prepared sentences placed on the phone's own text
// (desktop ADR 7 section 3, ADR 2 section 1). Raw ranges stay the phone's; the page's word
// sequence is the only thing the two sides share.
import 'align.dart';
import 'sync.dart';
import 'types.dart';

/// Where a sentence's audio comes from. The desktop's is always preferred (ADR 5).
enum SpeechSource { desktop, phone }

/// A sentence to read, placed on the phone's page: with the desktop's prepared audio, or to be
/// spoken by the phone's own voice.
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
    this.next,
    this.source = SpeechSource.desktop,
    this.spoken = '',
  });

  final int page;

  /// Names the audio file.
  final String key;
  final Lang lang;
  final Role role;

  /// The phone's own words, with their raw ranges.
  final List<Word> words;
  final List<RawRange> ranges;

  /// The part on the next page, for a sentence over the page break (desktop ADR 12).
  final PagePart? next;

  /// One per word, in seconds of the audio. Empty for the phone's voice: its audio is measured
  /// once it exists, and the player reports the timings then.
  final List<WordTiming> timings;
  final double duration;

  final SpeechSource source;

  /// What the phone's voice is given to say; empty for the desktop's audio.
  final String spoken;
}

class PagePlan {
  const PagePlan(this.sentences, this.skipped, [this.skippedBefore = const []]);

  final List<PlannedSentence> sentences;

  /// The phone's sentences that have no audio and are not read.
  final int skipped;

  /// How many of them come right before each planned sentence; missing entries are 0. The rest
  /// are at the end of the page.
  final List<int> skippedBefore;

  int _before(int index) => index < skippedBefore.length ? skippedBefore[index] : 0;

  int get _atEnd => skipped - skippedBefore.fold(0, (a, b) => a + b);
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

/// A prepared sentence on the phone's words. The words of a continuation on the next page (desktop
/// ADR 12) are tinted there, as their own part.
PlannedSentence _planned(List<Utterance> phone, List<Word> words, LibrarySentence s, Role role) {
  final here = [
    for (final w in words)
      if (w.page == null) w,
  ];
  final over = [
    for (final w in words)
      if (w.page != null) w,
  ];
  final next = [for (final u in phone) ?u.next].firstOrNull;
  return PlannedSentence(
    page: phone.first.page,
    key: s.key,
    lang: s.lang,
    role: role,
    words: words,
    ranges: here.isEmpty ? const [] : _sentenceRanges(here, phone),
    next: over.isEmpty || next == null ? null : (page: next.page, ranges: _joined(over, next.ranges)),
    timings: _seconds(s.words),
    duration: s.ms / 1000,
  );
}

/// The words' ranges, a gap filled where the continuation's own sentence covers it.
List<RawRange> _joined(List<Word> words, List<RawRange> covered) {
  final out = <RawRange>[];
  for (final range in words.expand((w) => w.ranges)) {
    if (out.isNotEmpty) {
      final (start, end) = out.last;
      if (end <= range.$1 && covered.any((c) => c.$1 <= end && range.$1 <= c.$2)) {
        out.last = (start, range.$2);
        continue;
      }
    }
    out.add(range);
  }
  return out;
}

/// A sentence for the phone's own voice, in the phone's words and ranges.
PlannedSentence _phoneSentence(Utterance u) => PlannedSentence(
  page: u.page,
  key: syncKey(u.text),
  lang: u.lang,
  role: u.role,
  words: u.words,
  ranges: u.ranges,
  next: u.next,
  timings: const [],
  duration: 0,
  source: SpeechSource.phone,
  spoken: u.spoken,
);

/// Places a page's prepared sentences on the phone's sentences of the same page. `index` is null
/// when the page has none. A sentence the desktop did not prepare goes to the phone's own voice if
/// that speaks its language (`phoneLangs`), else it is skipped.
PagePlan planPage(List<Utterance> phone, PageIndex? index, {Set<Lang> phoneLangs = const {}}) {
  if (index != null) {
    final words = pageWords(phone);
    if (words.length == index.wordCount && wordsHash(words) == index.wordsHash) {
      final flat = [for (final u in phone) ...u.words];
      final roles = [
        for (final u in phone)
          for (final _ in u.words) u.role,
      ];
      return PagePlan([
        for (final s in index.sentences)
          _planned(phone, flat.sublist(s.from, s.from + s.words.length), s, roles[s.from]),
      ], 0);
    }
  }

  // No index, or the engines found different words, which the spike never saw: match whole
  // sentences by text.
  final byKey = <String, LibrarySentence>{};
  for (final s in index?.sentences ?? const <LibrarySentence>[]) {
    byKey.putIfAbsent(s.key, () => s);
  }
  final sentences = <PlannedSentence>[];
  final skippedBefore = <int>[];
  var missed = 0;
  for (final u in phone) {
    final s = byKey[syncKey(u.text)];
    if (s == null) {
      if (phoneLangs.contains(u.lang) && u.spoken.trim().isNotEmpty) {
        skippedBefore.add(missed);
        missed = 0;
        sentences.add(_phoneSentence(u));
      } else {
        missed++;
      }
      continue;
    }
    skippedBefore.add(missed);
    missed = 0;
    final duration = s.ms / 1000;
    sentences.add(
      PlannedSentence(
        page: u.page,
        key: s.key,
        lang: s.lang,
        role: u.role,
        words: u.words,
        ranges: u.ranges,
        next: u.next,
        timings: s.words.length == u.words.length
            ? _seconds(s.words)
            : estimateTimings([for (final w in u.words) w.text], duration),
        duration: duration,
      ),
    );
  }
  return PagePlan(sentences, phone.length - sentences.length, skippedBefore);
}

/// Where "Read from here" starts on a page, as the desktop's `readFrom`: the first sentence with a
/// range ending after `offset`, or -1 when the offset is past the last one (the next page then).
int readFromIndex(List<List<RawRange>> sentences, int offset) =>
    sentences.indexWhere((ranges) => ranges.any((r) => r.$2 > offset));

/// How many sentences without audio the voice passed over going on from [from] to [to]: 0 unless
/// [to] is the very next sentence read, or a page on the way is not planned yet.
int skippedBetween(
  ({int page, int index}) from,
  ({int page, int index}) to,
  PagePlan? Function(int page) plan,
) {
  final start = plan(from.page);
  final end = plan(to.page);
  if (start == null || end == null) return 0;
  if (to.page == from.page) return to.index == from.index + 1 ? end._before(to.index) : 0;
  if (to.page < from.page || to.index != 0 || from.index != start.sentences.length - 1) return 0;
  var count = start._atEnd + end._before(0);
  for (var page = from.page + 1; page < to.page; page++) {
    final between = plan(page);
    if (between == null || between.sentences.isNotEmpty) return 0;
    count += between.skipped;
  }
  return count;
}
