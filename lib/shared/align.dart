// Port of the desktop's src/shared/align.ts.
import 'dart:math' as math;

import 'types.dart';

const _gapCost = 0.6;
const _minSimilarity = 0.5;

final _notWordChar = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final _wordStart = RegExp(r'^[\s▁]+', unicode: true);

String _normalize(String word) => word.toLowerCase().replaceAll(_notWordChar, '');

double _similarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var row = List.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final next = [i];
    for (var j = 1; j <= b.length; j++) {
      next.add(math.min(math.min(row[j] + 1, next[j - 1] + 1), row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)));
    }
    row = next;
  }
  return 1 - row[b.length] / math.max(a.length, b.length);
}

/// Turns known start times into full timings. Unknown starts are interpolated by word length, or by
/// `weights` where given.
List<WordTiming> _fill(List<String> words, List<double?> starts, double duration, [List<int>? weights]) {
  final weight = weights ?? [for (final w in words) w.length + 2];
  final out = <double>[];
  var from = 0.0;
  for (var i = 0; i < words.length;) {
    final known = starts[i];
    if (known != null) {
      from = math.max(from, known);
      out.add(from);
      i++;
      continue;
    }
    // A run of unknown words shares the time up to the next known word.
    var j = i;
    while (j < words.length && starts[j] == null) {
      j++;
    }
    final to = math.max(from, j < words.length ? starts[j]! : duration);
    // The known word before the run keeps its own share of that time.
    final before = i > 0 ? weight[i - 1] : 0;
    final total = weight.sublist(i, j).fold(before, (a, b) => a + b);
    var acc = before;
    for (var k = i; k < j; k++) {
      out.add(from + (to - from) * acc / total);
      acc += weight[k];
    }
    from = to;
    i = j;
  }
  return [
    for (var k = 0; k < out.length; k++)
      WordTiming(out[k], k + 1 < out.length ? out[k + 1] : math.max(out[k], duration)),
  ];
}

/// Spreads `duration` over the words by length. Used when nothing was measured.
List<WordTiming> estimateTimings(List<String> words, double duration) =>
    _fill(words, List.filled(words.length, null), duration);

// Phone only (PLAN 18.3): the phone's voice speaks `spoken`, the sentence's text, and its words are
// found in it in order.

final _digit = RegExp(r'\p{N}', unicode: true);
final _stop = RegExp(r'[.!?;:…]');
final _comma = RegExp(r'[,–—()\[\]"“”„«»]');

/// Where each word starts in `spoken`, or -1 where it is not found.
List<int> _locate(List<String> words, String spoken) {
  final out = <int>[];
  var from = 0;
  for (final w in words) {
    final at = spoken.indexOf(w, from);
    out.add(at);
    if (at >= 0) from = at + w.length;
  }
  return out;
}

/// How long each word and the pause after it take, in the units of `_fill`: a digit is said as a
/// syllable or more, and punctuation is a pause.
List<int> _spokenWeights(List<String> words, String spoken, List<int> at) => [
  for (var i = 0; i < words.length; i++)
    () {
      final word = words[i];
      var weight = word.length + 2 + 2 * _digit.allMatches(word).length;
      if (at[i] >= 0) {
        final end = at[i] + word.length;
        final next = i + 1 < words.length && at[i + 1] >= end ? at[i + 1] : spoken.length;
        final after = spoken.substring(end, math.max(end, next));
        weight += _stop.hasMatch(after) ? 7 : (_comma.hasMatch(after) ? 4 : 0);
      }
      return weight;
    }(),
];

/// Spreads `duration` over the words of `spoken` by how long each is to say: longer for numbers, with
/// a pause after a comma and a longer one after a full stop. Used when the engine gives no marks.
List<WordTiming> estimateSpokenTimings(List<String> words, String spoken, double duration) => _fill(
  words,
  List.filled(words.length, null),
  duration,
  _spokenWeights(words, spoken, _locate(words, spoken)),
);

/// The marks a speech engine reported, as places in the text and seconds into the audio. Android
/// documents a mark as (start, end, frame); Samsung's engine gives (frame, start, end). Which one it
/// is shows in the numbers: text offsets never pass the text's length, and frames do not go back.
List<(int, double)> marksFromRanges(
  List<(int, int, int)> ranges, {
  required int textLength,
  required int rate,
}) {
  if (rate <= 0 || ranges.isEmpty) return const [];
  bool fits(List<(int, int, int)> marks) {
    var frame = 0;
    for (final (start, end, at) in marks) {
      if (start < 0 || start > end || end > textLength || at < frame) return false;
      frame = at;
    }
    return true;
  }

  final documented = [for (final (start, end, frame) in ranges) (start, end, frame)];
  final rotated = [for (final (frame, start, end) in ranges) (start, end, frame)];
  final read = fits(documented) ? documented : (fits(rotated) ? rotated : null);
  return [for (final (start, _, frame) in read ?? const <(int, int, int)>[]) (start, frame / rate)];
}

/// Word timings from the marks a speech engine reports while it speaks `spoken`: each mark is where a
/// stretch starts in the text (a UTF-16 offset) and when in the audio, in seconds. A word takes the
/// first mark that starts in it or in the space before it; words no mark reached are spread between
/// their neighbours as in `estimateSpokenTimings`.
List<WordTiming> timingsFromMarks(
  List<String> words,
  String spoken,
  List<(int, double)> marks,
  double duration,
) {
  final at = _locate(words, spoken);
  final starts = List<double?>.filled(words.length, null);
  for (final (offset, seconds) in marks) {
    for (var i = 0; i < words.length; i++) {
      if (at[i] < 0) continue;
      if (offset < at[i] + words[i].length) {
        starts[i] ??= seconds;
        break;
      }
    }
  }
  return _fill(words, starts, duration, _spokenWeights(words, spoken, at));
}

/// Finds when each expected word is spoken, given what a speech recogniser heard in the
/// synthesised audio. Recogniser tokens are word pieces; a leading space or "▁" starts a word.
List<WordTiming> alignWords(
  List<String> words,
  List<String> tokens,
  List<double> timestamps,
  double duration,
) {
  final heardText = <StringBuffer>[];
  final heardStart = <double>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final piece = token.replaceFirst(_wordStart, '');
    if (piece != token || heardText.isEmpty) {
      heardText.add(StringBuffer());
      heardStart.add(i < timestamps.length ? timestamps[i] : 0);
    }
    heardText.last.write(piece);
  }
  final expected = words.map(_normalize).toList();
  final actual = heardText.map((h) => _normalize(h.toString())).toList();

  // Edit-distance alignment of the two word sequences. Besides the usual match and skip,
  // a move may pair one word with two: recognisers split and join compounds freely.
  final n = expected.length;
  final m = actual.length;
  final cost = List.generate(n + 1, (_) => List.filled(m + 1, 0.0));
  final move = List.generate(n + 1, (_) => List<(int, int, double)?>.filled(m + 1, null));
  for (var i = 0; i <= n; i++) {
    for (var j = 0; j <= m; j++) {
      if (i == 0 && j == 0) continue;
      final moves = <(int, int, double)>[
        if (i > 0) (1, 0, _gapCost),
        if (j > 0) (0, 1, _gapCost),
        if (i > 0 && j > 0) (1, 1, 1 - _similarity(expected[i - 1], actual[j - 1])),
        if (i > 0 && j > 1) (1, 2, 1 - _similarity(expected[i - 1], actual[j - 2] + actual[j - 1])),
        if (i > 1 && j > 0) (2, 1, 1 - _similarity(expected[i - 2] + expected[i - 1], actual[j - 1])),
      ];
      // The first cheapest move wins a tie, as in the desktop's reduce.
      for (final mv in moves) {
        final c = cost[i - mv.$1][j - mv.$2] + mv.$3;
        if (move[i][j] == null || c < cost[i][j]) {
          cost[i][j] = c;
          move[i][j] = mv;
        }
      }
    }
  }
  final starts = List<double?>.filled(words.length, null);
  for (var i = n, j = m; i > 0 || j > 0;) {
    final (di, dj, c) = move[i][j]!;
    i -= di;
    j -= dj;
    // Only the first word of a pairing gets the measured start; a second one is interpolated.
    if (di > 0 && dj > 0 && 1 - c >= _minSimilarity) starts[i] = heardStart[j];
  }
  return _fill(words, starts, duration);
}
