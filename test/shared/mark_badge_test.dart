import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/mark_badge.dart';
import 'package:pdfreader/shared/pdfium_text.dart';

CharBox line(double height) => (left: 72, bottom: 700, right: 200, top: 700 + height);

void main() {
  group('badgeBox', () {
    test('sits above the first line of the mark, at its left edge', () {
      final box = badgeBox(line(10));
      expect(box.left, 72);
      expect(box.bottom, greaterThan(710), reason: 'above the top of the line');
      expect(box.top, greaterThan(box.bottom));
      expect(box.right - box.left, closeTo(box.top - box.bottom, 1e-9), reason: 'square');
    });

    test('is about as big as the text, and no smaller than a thumbnail nor a headline', () {
      expect(badgeBox(line(10)).right - 72, closeTo(11, 1e-9));
      expect(badgeBox(line(2)).right - 72, 7, reason: 'a tiny line still gets a visible icon');
      expect(badgeBox(line(60)).right - 72, 14, reason: 'a huge line does not get a huge icon');
    });

    test('does not overlap the line it belongs to', () {
      for (final h in [4.0, 10.0, 24.0, 80.0]) {
        expect(badgeBox(line(h)).bottom, greaterThanOrEqualTo(700 + h));
      }
    });
  });
}
