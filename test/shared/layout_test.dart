// Port of the desktop's tests/unit/layout.test.ts and the blockSpans part of search.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/layout.dart';
import 'package:pdfreader/shared/types.dart';

const pageHeight = 800.0;

/// One PDF line as a single text run.
RawItem line(String str, double y, {double height = 10, String font = 'body', bool rotated = false}) =>
    RawItem(str: str, x: 72, y: y, height: height, font: font, hasEOL: true, rotated: rotated);

String rawOf(List<RawItem> items) => items.map((i) => i.str).join();

void main() {
  group('layoutPage', () {
    test('joins the lines of a paragraph with spaces', () {
      final [block] = layoutPage([line('First line', 700), line('second line.', 688)], pageHeight);
      expect(block.text, 'First line second line.');
      expect(block.heading, false);
    });

    test('undoes hyphenation at a line break', () {
      final [block] = layoutPage([line('Die Ent-', 700), line('wicklung läuft.', 688)], pageHeight);
      expect(block.text, 'Die Entwicklung läuft.');
    });

    test('keeps the hyphen of a compound and of an omitted word part', () {
      final compound = layoutPage([line('Benchmark-', 700), line('Datensätze.', 688)], pageHeight);
      expect(compound[0].text, 'Benchmark-Datensätze.');
      final omitted = layoutPage([line('Vor-', 700), line('und Nachteile.', 688)], pageHeight);
      expect(omitted[0].text, 'Vor- und Nachteile.');
      final chain = layoutPage([line('state-of-the-', 700), line('art results.', 688)], pageHeight);
      expect(chain[0].text, 'state-of-the-art results.');
    });

    test('maps every character back to its place in the page', () {
      final items = [line('Die Ent-', 700), line('wicklung.', 688)];
      final [block] = layoutPage(items, pageHeight);
      final pageRaw = rawOf(items);
      final word = block.text.indexOf('Entwicklung');
      final ranges = rawRanges(block.raw, word, word + 'Entwicklung'.length);
      // The removed hyphen splits the word into its two visible halves.
      expect([for (final (a, b) in ranges) pageRaw.substring(a, b)], ['Ent', 'wicklung']);
    });

    test('expands ligatures without losing the mapping', () {
      final [block] = layoutPage([line('efﬁcient', 700)], pageHeight);
      expect(block.text, 'efficient');
      expect(rawRanges(block.raw, 0, block.text.length), [(0, 8)]);
    });

    test('marks larger and numbered lines as headings', () {
      final blocks = layoutPage([
        line('A Study of Reading', 740, height: 16),
        line('This is the body text of the paper. It is long enough to set the size.', 700),
        line('2.1 Related Work', 660, font: 'bold'),
        line('More body text that follows the heading and ends properly.', 640),
      ], pageHeight);
      expect(blocks.map((b) => b.heading), [true, false, true, false]);
    });

    test('drops page numbers, running headers and rotated stamps', () {
      final blocks = layoutPage([
        line('Journal of Examples', 780),
        line('arXiv:1234.5678', 400, rotated: true),
        line('Body text that stays in the result.', 600),
        line('7', 30),
      ], pageHeight);
      expect(blocks.map((b) => b.text), ['Body text that stays in the result.']);
    });

    test('leaves out small figure labels, but keeps captions, small-caps section headings and footnote sentences (backlog 1)', () {
      final blocks = layoutPage([
        line('This is the body text of the paper. It is long enough to set the size.', 712),
        line('A second line of body text, so that the page has more body than small print.', 700),
        line('And a third one, as a real page has far more body text than labels in it.', 688),
        line('E[CLS] E1 E[SEP]', 600, height: 8),
        line('Input Embeddings', 580, height: 8),
        line('Figure 1: Overview of the model', 540, height: 8),
        line('V. A STUDY ON THE IMPORTANCE OF QUALITY', 500, height: 8),
        line('CRITERIA FOR TUTORIALS', 490, height: 8),
        line('1 This footnote is a sentence of its own.', 120, height: 8),
      ], pageHeight);
      expect(blocks.map((b) => b.text), [
        'This is the body text of the paper. It is long enough to set the size. A second line of body text, so that the page has more body than small print. And a third one, as a real page has far more body text than labels in it.',
        'Figure 1: Overview of the model',
        'V. A STUDY ON THE IMPORTANCE OF QUALITY CRITERIA FOR TUTORIALS',
        '1 This footnote is a sentence of its own.',
      ]);
    });

    test('leaves out table rows of numbers and displayed formulas, but not sentences with numbers (backlog 1, 2)', () {
      final blocks = layoutPage([
        line('This is the body text of the paper. It is long enough to set the size.', 700),
        line('I1 2.13 (1.20) I10 0.43 (2.00) I2 1.47 (1.59)', 650),
        line('E = mc² (1)', 600),
        line('f(x) = Σ a_i x^i', 560),
        line('In 2023, 45 % of 1,200 users agreed.', 520),
        line('We set α = 0.5 for all runs.', 500),
        line('RQ1:', 480),
        line('II.', 440),
      ], pageHeight);
      expect(blocks.map((b) => b.text), [
        'This is the body text of the paper. It is long enough to set the size.',
        'In 2023, 45 % of 1,200 users agreed.',
        'We set α = 0.5 for all runs.',
        'RQ1:',
        'II.',
      ]);
    });

    test('starts a new block when the text jumps to the next column', () {
      final blocks = layoutPage([
        line('End of column one.', 100),
        line('Top of column two.', 700),
      ], pageHeight);
      expect(blocks, hasLength(2));
    });
  });

  group('blockSpans', () {
    // Raw string: "A new language representa-" + "tion model was" + "trained (twice)."
    final items = [
      line('A new language representa-', 700),
      line('tion model was', 688),
      line('trained (twice).', 676),
    ];
    final pageRaw = rawOf(items);
    final blocks = layoutPage(items, 800);

    test('maps a raw range back to readable text', () {
      final start = pageRaw.indexOf('representa');
      final end = pageRaw.indexOf('was') + 3;
      expect(readableText(blocks, start, end), 'representation model was');
      expect(blockSpans(blocks, start, end), [(block: 0, from: 15, to: 39)]);
      expect(blockSpans(blocks, 9999, 10000), isEmpty);
    });
  });
}
