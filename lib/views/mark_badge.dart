// The icon above a marked section that has a comment (PLAN 12): a note for typed text, a microphone
// for a comment that was spoken. Both views paint it the same way, in the mark's colour.
import 'package:flutter/material.dart';

import '../shared/notes.dart';
import 'text_view.dart';

/// Paints the badge into `rect`: a white disc with a ring and the pictogram in the mark's line
/// colour, which reads on a page, on a dark reading view and over the mark's own fill.
void paintMarkBadge(Canvas canvas, Rect rect, NoteBadge badge, HighlightColor color) {
  final tone = markLine[color]!;
  final centre = rect.center;
  final radius = rect.shortestSide / 2;
  canvas.drawCircle(centre, radius, Paint()..color = const Color(0xF5FFFFFF));
  canvas.drawCircle(
    centre,
    radius - rect.shortestSide * 0.03,
    Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.shortestSide * 0.07,
  );
  final icon = badge == NoteBadge.speech ? Icons.mic : Icons.sticky_note_2;
  final glyph = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: rect.shortestSide * 0.66,
        color: tone,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  glyph.dispose();
}
