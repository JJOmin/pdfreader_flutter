// Sentence and word boundaries after Unicode's UAX #29, which is what the desktop's
// Intl.Segmenter does through ICU. Dart has no segmenter of its own (ADR 1, section 3).
// Offsets are UTF-16 code units, like JavaScript's, so ported offset arithmetic stays the same.
import 'unicode_tables.dart';

class Segment {
  const Segment(this.segment, this.index, {this.isWordLike = false});

  final String segment;
  final int index;

  /// For words: the segment holds a letter or a number, like Intl.Segmenter's `isWordLike`.
  final bool isWordLike;

  @override
  String toString() => '$index:$segment${isWordLike ? '*' : ''}';
}

// Same order as tool/gen_unicode.dart's value lists, which the tables index into.
enum _W {
  other,
  cr,
  lf,
  newline,
  extend,
  zwj,
  ri,
  format,
  katakana,
  hebrewLetter,
  aLetter,
  singleQuote,
  doubleQuote,
  midNumLet,
  midLetter,
  midNum,
  numeric,
  extendNumLet,
  wSegSpace,
}

enum _S {
  other,
  cr,
  lf,
  extend,
  sep,
  format,
  sp,
  lower,
  upper,
  oLetter,
  numeric,
  aTerm,
  sContinue,
  sTerm,
  close,
}

int _lookup(List<int> table, int cp) {
  var lo = 0;
  var hi = table.length ~/ 3 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cp < table[mid * 3]) {
      hi = mid - 1;
    } else if (cp > table[mid * 3 + 1]) {
      lo = mid + 1;
    } else {
      return table[mid * 3 + 2];
    }
  }
  return 0;
}

/// The text as code points with their UTF-16 start offsets; `starts` has one extra entry, the end.
({List<int> cps, List<int> starts}) _codePoints(String text) {
  final cps = <int>[];
  final starts = <int>[];
  var at = 0;
  for (final cp in text.runes) {
    cps.add(cp);
    starts.add(at);
    at += cp > 0xFFFF ? 2 : 1;
  }
  starts.add(at);
  return (cps: cps, starts: starts);
}

List<Segment> _cut(String text, List<int> starts, List<int> breaks, [bool Function(int, int)? wordLike]) => [
  for (var i = 0; i + 1 < breaks.length; i++)
    Segment(
      text.substring(starts[breaks[i]], starts[breaks[i + 1]]),
      starts[breaks[i]],
      isWordLike: wordLike?.call(breaks[i], breaks[i + 1]) ?? false,
    ),
];

final _letter = RegExp(r'\p{L}', unicode: true);

/// Splits text into words and the pieces between them (spaces, punctuation), like
/// `Intl.Segmenter(lang, {granularity: 'word'})`.
List<Segment> wordSegments(String text) {
  final (:cps, :starts) = _codePoints(text);
  final n = cps.length;
  final p = [for (final cp in cps) _W.values[_lookup(wordBreakRanges, cp)]];
  bool pict(int i) => _lookup(extendedPictographicRanges, cps[i]) != 0;
  bool ignored(int i) => p[i] == _W.extend || p[i] == _W.format || p[i] == _W.zwj;
  bool ahLetter(_W w) => w == _W.aLetter || w == _W.hebrewLetter;
  bool midNumLetQ(_W w) => w == _W.midNumLet || w == _W.singleQuote;

  // WB4: Extend, Format and ZWJ belong to the character before them, unless that is a line end.
  int before(int i) {
    var j = i;
    while (j > 0 && ignored(j)) {
      j--;
    }
    if (j < i && (p[j] == _W.cr || p[j] == _W.lf || p[j] == _W.newline)) return j + 1;
    return j;
  }

  int after(int i) {
    var j = i;
    while (j < n && ignored(j)) {
      j++;
    }
    return j;
  }

  _W at(int i) => i >= 0 && i < n ? p[i] : _W.other;

  bool breakAt(int i) {
    final prev = p[i - 1];
    final cur = p[i];
    if (prev == _W.cr && cur == _W.lf) return false; // WB3
    if (prev == _W.cr || prev == _W.lf || prev == _W.newline) return true; // WB3a
    if (cur == _W.cr || cur == _W.lf || cur == _W.newline) return true; // WB3b
    if (prev == _W.zwj && pict(i)) return false; // WB3c
    if (prev == _W.wSegSpace && cur == _W.wSegSpace) return false; // WB3d
    if (ignored(i)) return false; // WB4

    final b = before(i - 1);
    final l = p[b];
    final ll = b > 0 ? at(before(b - 1)) : _W.other;
    final rr = at(after(i + 1));
    if (ahLetter(l) && ahLetter(cur)) return false; // WB5
    if (ahLetter(l) && (cur == _W.midLetter || midNumLetQ(cur)) && ahLetter(rr)) return false; // WB6
    if (ahLetter(ll) && (l == _W.midLetter || midNumLetQ(l)) && ahLetter(cur)) return false; // WB7
    if (l == _W.hebrewLetter && cur == _W.singleQuote) return false; // WB7a
    if (l == _W.hebrewLetter && cur == _W.doubleQuote && rr == _W.hebrewLetter) return false; // WB7b
    if (ll == _W.hebrewLetter && l == _W.doubleQuote && cur == _W.hebrewLetter) return false; // WB7c
    if (l == _W.numeric && cur == _W.numeric) return false; // WB8
    if (ahLetter(l) && cur == _W.numeric) return false; // WB9
    if (l == _W.numeric && ahLetter(cur)) return false; // WB10
    if (ll == _W.numeric && (l == _W.midNum || midNumLetQ(l)) && cur == _W.numeric) return false; // WB11
    if (l == _W.numeric && (cur == _W.midNum || midNumLetQ(cur)) && rr == _W.numeric) return false; // WB12
    if (l == _W.katakana && cur == _W.katakana) return false; // WB13
    if ((ahLetter(l) || l == _W.numeric || l == _W.katakana || l == _W.extendNumLet) &&
        cur == _W.extendNumLet) {
      return false; // WB13a
    }
    if (l == _W.extendNumLet && (ahLetter(cur) || cur == _W.numeric || cur == _W.katakana)) {
      return false; // WB13b
    }
    if (l == _W.ri && cur == _W.ri) {
      // WB15, WB16: regional indicators pair up from the left.
      var count = 0;
      for (var j = b; j >= 0 && (p[j] == _W.ri || ignored(j)); j--) {
        if (p[j] == _W.ri) count++;
      }
      return count.isEven;
    }
    return true; // WB999
  }

  final breaks = [
    0,
    for (var i = 1; i < n; i++)
      if (breakAt(i)) i,
    if (n > 0) n,
  ];
  bool wordLike(int from, int to) {
    for (var i = from; i < to; i++) {
      final w = p[i];
      if (ahLetter(w) || w == _W.numeric || w == _W.katakana) return true;
      if (_letter.hasMatch(String.fromCharCode(cps[i]))) return true;
    }
    return false;
  }

  return _cut(text, starts, n == 0 ? const [] : breaks, wordLike);
}

/// Splits text into sentences, like `Intl.Segmenter(lang, {granularity: 'sentence'})`.
List<Segment> sentenceSegments(String text) {
  final (:cps, :starts) = _codePoints(text);
  final n = cps.length;
  final p = [for (final cp in cps) _S.values[_lookup(sentenceBreakRanges, cp)]];
  bool ignored(int i) => p[i] == _S.extend || p[i] == _S.format;
  bool paraSep(_S s) => s == _S.sep || s == _S.cr || s == _S.lf;
  bool saTerm(_S s) => s == _S.sTerm || s == _S.aTerm;

  // SB5: Extend and Format belong to the character before them, unless that ends a paragraph.
  int before(int i) {
    var j = i;
    while (j > 0 && ignored(j)) {
      j--;
    }
    if (j < i && paraSep(p[j])) return j + 1;
    return j;
  }

  bool breakAt(int i) {
    final prev = p[i - 1];
    final cur = p[i];
    if (prev == _S.cr && cur == _S.lf) return false; // SB3
    if (paraSep(prev)) return true; // SB4
    if (ignored(i)) return false; // SB5

    final b = before(i - 1);
    final l = p[b];
    if (l == _S.aTerm && cur == _S.numeric) return false; // SB6
    if (l == _S.aTerm && cur == _S.upper && b > 0) {
      final ll = p[before(b - 1)];
      if (ll == _S.upper || ll == _S.lower) return false; // SB7
    }

    // Look back for SATerm Close* Sp*.
    var j = b;
    var spaces = false;
    while (j >= 0 && p[j] == _S.sp) {
      spaces = true;
      j = j > 0 ? before(j - 1) : -1;
    }
    while (j >= 0 && p[j] == _S.close) {
      j = j > 0 ? before(j - 1) : -1;
    }
    if (j < 0 || !saTerm(p[j])) return false; // SB998
    if (p[j] == _S.aTerm) {
      // SB8: no break if a lower-case letter follows before any letter, separator or terminator.
      for (var k = i; k < n; k++) {
        final s = p[k];
        if (s == _S.lower) return false;
        if (s == _S.oLetter || s == _S.upper || paraSep(s) || saTerm(s)) break;
      }
    }
    if (cur == _S.sContinue || saTerm(cur)) return false; // SB8a
    if (!spaces && (cur == _S.close || cur == _S.sp || paraSep(cur))) return false; // SB9
    if (cur == _S.sp || paraSep(cur)) return false; // SB10
    return true; // SB11
  }

  final breaks = [
    0,
    for (var i = 1; i < n; i++)
      if (breakAt(i)) i,
    if (n > 0) n,
  ];
  return _cut(text, starts, n == 0 ? const [] : breaks);
}
