import 'package:flutter/material.dart';

import '../shared/mark_styles.dart';
import '../shared/notes.dart';
import 'text_view.dart';

/// What a view asks for to show the menu above a selection. `selection` reads the selected raw
/// ranges, `done` clears the selection and closes the menu. Both views build the same menu, so
/// marking works the same in either.
typedef SelectionMenuBuilder = Widget Function(
  BuildContext context,
  Offset anchorA,
  Offset? anchorB,
  Future<List<PageSelection>> Function() selection,
  Future<void> Function() done,
);

typedef PageSelection = ({int page, (int, int) range});

const markKindIcons = {
  MarkKind.highlight: Icons.border_color,
  MarkKind.underline: Icons.format_underlined,
  MarkKind.strike: Icons.format_strikethrough,
};
const markKindNames = {
  MarkKind.highlight: 'Highlight',
  MarkKind.underline: 'Underline',
  MarkKind.strike: 'Strike through',
};

/// A mark's look as an icon: the kind's icon in the colour, on a tint of it for a highlight.
Widget markStyleIcon(MarkStyle style, {double size = 22}) {
  final icon = Icon(markKindIcons[style.kind], color: markLine[style.color], size: size);
  if (style.kind != MarkKind.highlight) return icon;
  return DecoratedBox(
    decoration: BoxDecoration(color: markFill[style.color], borderRadius: BorderRadius.circular(6)),
    child: Padding(padding: const EdgeInsets.all(2), child: icon),
  );
}

/// The menu over a selection (PLAN 18.7): Read from here, Comment in the primary comment colour, the two
/// favourite looks, which mark with one tap, and More for every kind and colour. There, the kind stays
/// selected for the next mark and one tap on a colour makes it. It is the platform's own selection
/// toolbar, which keeps itself on the screen and above or below the selection as there is room.
class MarkMenu extends StatefulWidget {
  const MarkMenu({
    super.key,
    required this.anchorA,
    required this.anchorB,
    required this.initialKind,
    required this.onKindChanged,
    required this.onMark,
    this.styles = const MarkStyles(),
    this.onReadFrom,
    this.onComment,
  });

  /// Where the selection starts and ends on the screen, as the views report them.
  final Offset anchorA;
  final Offset? anchorB;
  final MarkKind initialKind;

  /// The comment colour and the favourite looks.
  final MarkStyles styles;

  /// The kind was changed: kept for the next mark.
  final ValueChanged<MarkKind> onKindChanged;
  final void Function(MarkKind kind, HighlightColor color) onMark;

  /// "Read from here", as on the desktop; null where the document cannot be read aloud.
  final VoidCallback? onReadFrom;

  /// "Comment": opens the comment sheet, where the comment is typed or, if the phone can listen,
  /// spoken (ADR 6). Null where marks cannot be commented on.
  final VoidCallback? onComment;

  @override
  State<MarkMenu> createState() => _MarkMenuState();
}

class _MarkMenuState extends State<MarkMenu> {
  late MarkKind _kind = widget.initialKind;

  /// Every kind and colour shows instead of the favourites.
  bool _more = false;

  Widget _button({
    required Key key,
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
    bool selected = false,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    icon: icon,
    isSelected: selected,
    style: IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
    ),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    // The toolbar places itself in the room it is given, and the views' overlays give none.
    child: SizedBox.fromSize(size: MediaQuery.sizeOf(context), child: _toolbar()),
  );

  Widget _toolbar() => AdaptiveTextSelectionToolbar(
    // A new key for each row, so the toolbar measures the row it shows.
    key: ValueKey(_more),
    anchors: TextSelectionToolbarAnchors(primaryAnchor: widget.anchorA, secondaryAnchor: widget.anchorB),
    children: _more ? _everyLook() : _first(),
  );

  List<Widget> _first() => [
    if (widget.onReadFrom case final readFrom?)
      _button(
        key: const Key('read-from-here'),
        tooltip: 'Read from here',
        icon: const Icon(Icons.play_arrow),
        onPressed: readFrom,
      ),
    if (widget.onComment case final comment?)
      _button(
        key: const Key('comment-selection'),
        tooltip: 'Comment',
        icon: Icon(Icons.edit_note, color: markLine[widget.styles.comment]),
        onPressed: comment,
      ),
    for (final (i, look) in widget.styles.favourites.indexed)
      _button(
        key: Key('favourite-$i'),
        tooltip: '${markKindNames[look.kind]}, ${look.color.name}',
        icon: markStyleIcon(look),
        onPressed: () => widget.onMark(look.kind, look.color),
      ),
    _button(
      key: const Key('more-looks'),
      tooltip: 'Other kinds and colours',
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => setState(() => _more = true),
    ),
  ];

  List<Widget> _everyLook() => [
    for (final k in MarkKind.values)
      _button(
        key: Key('kind-${k.name}'),
        tooltip: markKindNames[k]!,
        icon: Icon(markKindIcons[k]),
        selected: _kind == k,
        onPressed: () {
          setState(() => _kind = k);
          widget.onKindChanged(k);
        },
      ),
    for (final c in HighlightColor.values)
      _button(
        key: Key('color-${c.name}'),
        tooltip: '${markKindNames[_kind]}, ${c.name}',
        icon: CircleAvatar(radius: 10, backgroundColor: markLine[c]),
        onPressed: () => widget.onMark(_kind, c),
      ),
  ];
}
