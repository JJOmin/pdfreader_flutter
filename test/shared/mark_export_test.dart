import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/mark_export.dart';
import 'package:pdfreader/shared/notes.dart';

void main() {
  test('gives the desktop’s colours: the fill for a highlight, the stronger tone for a line', () {
    expect(markColor(MarkKind.highlight, HighlightColor.yellow), (255, 222, 51));
    expect(markColor(MarkKind.underline, HighlightColor.red), (224, 48, 48));
    expect(markColor(MarkKind.strike, HighlightColor.blue), (31, 128, 224));
  });

  test('puts a line’s quad points in the PDF’s order, and the rectangle around all lines', () {
    const line1 = (left: 72.0, bottom: 700.0, right: 300.0, top: 712.0);
    const line2 = (left: 72.0, bottom: 686.0, right: 150.0, top: 698.0);
    expect(quadOf(line1), (72.0, 712.0, 300.0, 712.0, 72.0, 700.0, 300.0, 700.0));
    expect(boundsOf([line1, line2]), (left: 72.0, bottom: 686.0, right: 300.0, top: 712.0));
  });
}
