import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/segment.dart';

/// A case from Unicode's break tests: the text and every boundary in UTF-16 offsets.
typedef BreakCase = ({String text, List<int> boundaries, String line});

List<BreakCase> readBreakTest(String file) {
  final cases = <BreakCase>[];
  for (final line in File(file).readAsLinesSync()) {
    final content = line.split('#').first.trim();
    if (content.isEmpty) continue;
    final text = StringBuffer();
    final boundaries = <int>[];
    var length = 0;
    for (final token in content.split(RegExp(r'\s+'))) {
      if (token == '÷') {
        boundaries.add(length);
      } else if (token != '×') {
        final char = String.fromCharCode(int.parse(token, radix: 16));
        text.write(char);
        length += char.length;
      }
    }
    cases.add((text: text.toString(), boundaries: boundaries, line: content));
  }
  return cases;
}

List<int> boundariesOf(List<Segment> segments, String text) => [
  for (final s in segments) s.index,
  if (text.isNotEmpty) text.length,
];

/// Lines of Unicode's tests where ICU, and so the desktop, splits differently. Each was checked
/// against Node's Intl.Segmenter, and the golden test below holds the segmenter to ICU.
const icuDifferences = <String>{};

void main() {
  for (final (name, split) in [
    ('WordBreakTest.txt', wordSegments),
    ('SentenceBreakTest.txt', sentenceSegments),
  ]) {
    test('follows Unicode $name', () {
      final failed = <String>[];
      final cases = readBreakTest('test/unicode/$name');
      for (final c in cases) {
        if (icuDifferences.contains(c.line)) continue;
        final got = boundariesOf(split(c.text), c.text);
        if (!listEquals(got, c.boundaries)) failed.add('${c.line}\n    got $got');
      }
      expect(failed, isEmpty, reason: '${failed.length} of ${cases.length} cases fail');
    });
  }

  group('matches Intl.Segmenter on the golden corpus', () {
    final golden = jsonDecode(File('test/golden/segments.json').readAsStringSync()) as List<Object?>;
    for (final entry in golden.cast<Map<String, Object?>>()) {
      final text = entry['text']! as String;
      final granularity = entry['granularity']! as String;
      test('$granularity: ${text.length > 50 ? '${text.substring(0, 50)}…' : text}', () {
        final got = (granularity == 'word' ? wordSegments : sentenceSegments)(text);
        final expected = (entry['segments']! as List<Object?>).cast<Map<String, Object?>>();
        expect(
          [for (final s in got) '${s.index}:${s.segment}${granularity == 'word' && s.isWordLike ? '*' : ''}'],
          [
            for (final s in expected)
              '${s['index']}:${s['segment']}${s['isWordLike'] == true ? '*' : ''}',
          ],
        );
      });
    }
  });
}
