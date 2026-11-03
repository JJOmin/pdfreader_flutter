// The primary comment colour and the two favourite looks of the selection menu (PLAN 18.7).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/app_settings.dart';
import 'package:pdfreader/shared/mark_styles.dart';
import 'package:pdfreader/shared/notes.dart';

void main() {
  test('a comment is a yellow highlight, and there are two favourites, until the user chooses', () {
    const styles = MarkStyles();
    expect(styles.comment, HighlightColor.yellow);
    expect(styles.commentStyle, (kind: MarkKind.highlight, color: HighlightColor.yellow));
    expect(styles.favourites, hasLength(2));
  });

  test('is written and read back', () {
    final styles = const MarkStyles().copyWith(comment: HighlightColor.blue).withFavourite(1, (
      kind: MarkKind.underline,
      color: HighlightColor.red,
    ));
    expect(parseMarkStyles(styles.toJson()), styles);
    expect(styles.favourites[1], (kind: MarkKind.underline, color: HighlightColor.red));
  });

  test('a missing or unknown value falls back field by field, and there are always two favourites', () {
    expect(parseMarkStyles(null), const MarkStyles());
    expect(parseMarkStyles({'comment': 'purple'}).comment, HighlightColor.yellow);
    final one = parseMarkStyles({
      'comment': 'green',
      'favourites': [
        {'kind': 'strike', 'color': 'blue'},
      ],
    });
    expect(one.comment, HighlightColor.green);
    expect(one.favourites, [
      (kind: MarkKind.strike, color: HighlightColor.blue),
      const MarkStyles().favourites[1],
    ]);
    final odd = parseMarkStyles({
      'favourites': [
        {'kind': 'glow', 'color': 'blue'},
        'nonsense',
        {'kind': 'underline', 'color': 'red'},
      ],
    });
    expect(odd.favourites, [
      (kind: MarkKind.highlight, color: HighlightColor.blue),
      const MarkStyles().favourites[1],
    ]);
  });

  test('the app settings carry them, and a file from before reads with the defaults', () {
    final look = const Appearance().copyWith(marks: const MarkStyles(comment: HighlightColor.red));
    expect(parseAppearance(look.toJson()).marks.comment, HighlightColor.red);
    expect(parseAppearance({'version': 1, 'theme': 'dark'}).marks, const MarkStyles());
  });
}
