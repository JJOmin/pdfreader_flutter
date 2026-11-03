// The looks the selection menu offers first (PLAN 18.7): the primary comment colour, which a comment's
// mark takes unless another look is chosen for it, and two favourite looks for marking with one tap.
// Kept on this phone only, in the app's settings.
import 'notes.dart';

/// A mark's look: its kind and its colour.
typedef MarkStyle = ({MarkKind kind, HighlightColor color});

const _defaultFavourites = <MarkStyle>[
  (kind: MarkKind.highlight, color: HighlightColor.yellow),
  (kind: MarkKind.highlight, color: HighlightColor.green),
];

class MarkStyles {
  const MarkStyles({this.comment = HighlightColor.yellow, this.favourites = _defaultFavourites});

  final HighlightColor comment;

  /// Always two.
  final List<MarkStyle> favourites;

  /// A comment's mark is a highlight in the primary comment colour.
  MarkStyle get commentStyle => (kind: MarkKind.highlight, color: comment);

  MarkStyles copyWith({HighlightColor? comment, List<MarkStyle>? favourites}) =>
      MarkStyles(comment: comment ?? this.comment, favourites: favourites ?? this.favourites);

  MarkStyles withFavourite(int index, MarkStyle style) =>
      copyWith(favourites: [for (var i = 0; i < favourites.length; i++) i == index ? style : favourites[i]]);

  Map<String, Object?> toJson() => {
    'comment': comment.name,
    'favourites': [
      for (final f in favourites) {'kind': f.kind.name, 'color': f.color.name},
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is MarkStyles &&
      other.comment == comment &&
      other.favourites.length == favourites.length &&
      [for (var i = 0; i < favourites.length; i++) other.favourites[i] == favourites[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(comment, Object.hashAll(favourites));
}

T _named<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;

/// Reads the styles from anything read from disk; what is missing or unknown falls back to the default,
/// field by field, and there are always two favourites.
MarkStyles parseMarkStyles(Object? json) {
  final map = json is Map<Object?, Object?> ? json : const <Object?, Object?>{};
  final list = map['favourites'] is List<Object?> ? map['favourites']! as List<Object?> : const <Object?>[];
  MarkStyle favourite(int i) => switch (i < list.length ? list[i] : null) {
    final Map<Object?, Object?> item => (
      kind: _named(MarkKind.values, item['kind'], _defaultFavourites[i].kind),
      color: _named(HighlightColor.values, item['color'], _defaultFavourites[i].color),
    ),
    _ => _defaultFavourites[i],
  };
  return MarkStyles(
    comment: _named(HighlightColor.values, map['comment'], HighlightColor.yellow),
    favourites: [for (var i = 0; i < _defaultFavourites.length; i++) favourite(i)],
  );
}
