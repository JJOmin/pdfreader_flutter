// The full-screen player's preview (PLAN 11): the sentence being read in large type with the spoken
// word highlighted, kept at the middle of the window as the voice moves on, with the sentences
// either side faded. It paints from the same words the voice follows, so it cannot disagree with it.
import 'package:flutter/material.dart';

import '../shared/player_preview.dart';

class SpeedReaderWindow extends StatelessWidget {
  const SpeedReaderWindow({
    super.key,
    required this.words,
    required this.current,
    this.previous,
    this.next,
    this.fontSize = 30,
  });

  final List<String> words;

  /// The spoken word's index; -1 before the first.
  final int current;

  /// The sentences before and after, shown small and faded.
  final String? previous;
  final String? next;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final faded = TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.45), height: 1.3);
    return Column(
      children: [
        if (previous != null) Text(previous!, maxLines: 2, overflow: TextOverflow.ellipsis, style: faded),
        Expanded(
          child: _Window(words: words, current: current, fontSize: fontSize),
        ),
        if (next != null) Text(next!, maxLines: 2, overflow: TextOverflow.ellipsis, style: faded),
      ],
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({required this.words, required this.current, required this.fontSize});

  final List<String> words;
  final int current;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // One weight for every word: the highlight changes colour, never width, so nothing reflows.
    final base = TextStyle(fontSize: fontSize, height: 1.4, fontWeight: FontWeight.w600);
    final spans = wordSpans(words);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: words.join(' '), style: base),
          textDirection: Directionality.of(context),
          textAlign: TextAlign.center,
        )..layout(maxWidth: box.maxWidth);
        var shift = 0.0;
        if (painter.height <= box.maxHeight) {
          shift = -(box.maxHeight - painter.height) / 2;
        } else if (current >= 0 && current < spans.length) {
          final boxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: spans[current].$1, extentOffset: spans[current].$2),
          );
          if (boxes.isNotEmpty) {
            final middle = (boxes.first.top + boxes.first.bottom) / 2;
            shift = (middle - box.maxHeight / 2).clamp(0.0, painter.height - box.maxHeight);
          }
        }
        painter.dispose();
        return ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: shift),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, child) => Transform.translate(offset: Offset(0, -value), child: child),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: RichText(
                key: const Key('speed-reader'),
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: base.copyWith(color: colors.onSurface.withValues(alpha: 0.55)),
                  children: [
                    for (var i = 0; i < words.length; i++) ...[
                      TextSpan(
                        text: words[i],
                        style: i == current
                            ? TextStyle(
                                color: colors.onPrimaryContainer,
                                backgroundColor: colors.primaryContainer,
                              )
                            : i > current
                            ? TextStyle(color: colors.onSurface)
                            : null,
                      ),
                      if (i < words.length - 1) const TextSpan(text: ' '),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
