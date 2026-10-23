import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../document_text.dart';
import '../shared/highlight_runs.dart';
import '../shared/layout.dart';
import '../shared/notes.dart';
import '../shared/settings.dart';
import '../shared/types.dart';
import 'mark_badge.dart';
import 'mark_menu.dart';
import 'text_view.dart';

/// The fonts the phone can show. Verdana, Comic Sans MS, Arial and Georgia are Microsoft fonts
/// that cannot be bundled (Phase 0 report, question 6), so the desktop's names map to the phone's
/// own sans and serif. A settings file therefore means the same on both.
const readingFontChoices = [
  ('OpenDyslexic', 'OpenDyslexic'),
  ('Lexend', 'Lexend'),
  ('Verdana', 'Phone sans'),
  ('Georgia', 'Phone serif'),
];

String? _fontFamily(String font) => switch (font) {
  'OpenDyslexic' || 'Lexend' => font,
  'Georgia' => 'serif',
  _ => null,
};

/// Background and text colour of each theme.
const readingThemeColors = {
  'light': (Color(0xFFFFFFFF), Color(0xFF1F1F1F)),
  'sepia': (Color(0xFFF4ECD8), Color(0xFF5B4636)),
  'dark': (Color(0xFF1E1E1E), Color(0xFFE2E2E2)),
};

/// The reading view as a `TextView`: a paragraph's characters are its block's readable text, so a
/// raw range becomes a stretch of a paragraph through `blockSpans`, as on the desktop.
class ReadingController implements TextView {
  _ReadingViewState? _state;

  @override
  bool get isReady => _state?._scroll.hasClients ?? false;

  @override
  int? get currentPage => scrollAnchor()?.page;

  /// Where raw ranges of a page are on the screen, for tests that press on a word.
  Offset? globalCenterOf(int page, List<RawRange> ranges) => _state?._globalCenterOf(page, ranges);

  @override
  ({int page, double offset})? scrollAnchor() => _state?._anchor();

  @override
  Future<void> showPage(int page, double offset) async => _state?._showPage(page, offset);

  @override
  Future<void> reveal(int page, List<RawRange> ranges) async => _state?._reveal(page, ranges);
}

class ReadingView extends StatefulWidget {
  const ReadingView({
    super.key,
    required this.text,
    required this.settings,
    required this.controller,
    required this.highlights,
    this.onTouched,
    this.buildSelectionMenu,
    this.onMarkTapped,
    this.onTapped,
  });

  final DocumentText text;
  final ReadingSettings settings;
  final ReadingController controller;
  final List<Highlight> highlights;

  /// The user scrolled: the view stops following the voice for a while.
  final VoidCallback? onTouched;

  /// The menu shown over selected text, or null where nothing can be marked.
  final SelectionMenuBuilder? buildSelectionMenu;
  final MarkTapped? onMarkTapped;

  /// A tap that is not on a mark: the reader shows or hides its top bar.
  final VoidCallback? onTapped;

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<ReadingView> {
  final _scroll = ScrollController();
  final _content = GlobalKey();

  /// Each page's blocks, in order, as they are loaded.
  final _pages = <List<Block>>[];
  final _pageKeys = <GlobalKey>[];
  final _blockKeys = <List<GlobalKey>>[];

  /// A place asked for before its page was built: shown as soon as it is.
  ({int page, double offset})? _wanted;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ReadingView old) {
    super.didUpdateWidget(old);
    widget.controller._state = this;
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _scroll.dispose();
    super.dispose();
  }

  /// Builds the text page by page, so the first page shows while the rest is read.
  Future<void> _load() async {
    for (var page = 1; page <= widget.text.pageCount; page++) {
      final blocks = (await widget.text.page(page)).blocks;
      if (!mounted) return;
      setState(() {
        _pages.add(blocks);
        _pageKeys.add(GlobalKey());
        _blockKeys.add([for (final _ in blocks) GlobalKey()]);
      });
      if (_wanted?.page == page) {
        final wanted = _wanted!;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showPage(wanted.page, wanted.offset));
      }
    }
  }

  /// The text's render object inside a paragraph's selectable text: it knows where each character is.
  RenderEditable? _editable(GlobalKey key) {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    final root = key.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  RenderBox? _box(GlobalKey key) => key.currentContext?.findRenderObject() as RenderBox?;

  /// Where a widget's top is in the scrolled content.
  double? _top(GlobalKey key) {
    final box = _box(key);
    final content = _box(_content);
    if (box == null || content == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: content).dy;
  }

  ({int page, double offset})? _anchor() {
    if (!_scroll.hasClients) return null;
    final top = _scroll.offset;
    ({int page, double offset})? anchor;
    for (var i = 0; i < _pageKeys.length; i++) {
      final y = _top(_pageKeys[i]);
      final height = _box(_pageKeys[i])?.size.height;
      if (y == null || height == null || y > top + 1) break;
      anchor = (page: i + 1, offset: ((top - y) / height).clamp(0.0, 0.999));
    }
    return anchor ?? (page: 1, offset: 0);
  }

  void _showPage(int page, double offset) {
    final key = page >= 1 && page <= _pageKeys.length ? _pageKeys[page - 1] : null;
    final y = key == null ? null : _top(key);
    if (y == null || !_scroll.hasClients) {
      _wanted = (page: page, offset: offset);
      return;
    }
    _wanted = null;
    final height = _box(key!)!.size.height;
    _scroll.jumpTo((y + offset * height).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _reveal(int page, List<RawRange> ranges) {
    if (page > _pages.length || !_scroll.hasClients) return _showPage(page, 0);
    final blocks = _pages[page - 1];
    final content = _box(_content);
    for (final (start, end) in ranges) {
      for (final span in blockSpans(blocks, start, end)) {
        final editable = _editable(_blockKeys[page - 1][span.block]);
        if (editable == null || content == null) continue;
        final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: span.from, extentOffset: span.to),
        );
        if (boxes.isEmpty) continue;
        final y = editable.localToGlobal(Offset(0, boxes.first.top), ancestor: content).dy;
        final view = _scroll.position.viewportDimension;
        final from = _scroll.offset;
        final height = boxes.first.bottom - boxes.first.top;
        // Comfortably inside: leave the view still, as the desktop does.
        if (y >= from + view * 0.1 && y + height <= from + view * 0.75) return;
        unawaited(
          _scroll.animateTo(
            (y - view * 0.3).clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
        return;
      }
    }
  }

  Offset? _globalCenterOf(int page, List<RawRange> ranges) {
    if (page > _pages.length) return null;
    for (final (start, end) in ranges) {
      for (final span in blockSpans(_pages[page - 1], start, end)) {
        final editable = _editable(_blockKeys[page - 1][span.block]);
        if (editable == null) continue;
        final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: span.from, extentOffset: span.to),
        );
        if (boxes.isNotEmpty) return editable.localToGlobal(boxes.first.toRect().center);
      }
    }
    return null;
  }

  /// A paragraph's text, cut where highlights start and end. Each highlight that covers a stretch
  /// adds its look: fills blend, in list order, and underline and strike-through combine.
  TextSpan _paragraph(int page, int index, Block block, TextStyle style) {
    // A highlight's ranges share its number, so that `ids` name highlights, not ranges.
    final byHighlight = <int, Highlight>{};
    final numbered = <HighlightSpan>[];
    var n = 0;
    for (final highlight in widget.highlights) {
      if (highlight.page != page) continue;
      for (final (start, end) in highlight.ranges) {
        for (final span in blockSpans(_pages[page - 1], start, end)) {
          if (span.block != index) continue;
          numbered.add((from: span.from, to: span.to, id: n));
        }
      }
      byHighlight[n++] = highlight;
    }
    return TextSpan(
      style: style,
      children: [
        for (final run in highlightRuns(block.text.length, numbered))
          TextSpan(
            text: block.text.substring(run.from, run.to),
            style: run.ids.isEmpty ? null : _runStyle([for (final id in run.ids) byHighlight[id]!]),
          ),
      ],
    );
  }

  /// The comment icons of a paragraph: one per mark whose first stretch starts in it.
  List<_Badge> _badges(int page, int index) {
    final out = <_Badge>[];
    for (final highlight in widget.highlights) {
      if (highlight.badge == null || highlight.page != page || highlight.ranges.isEmpty) continue;
      final first = blockSpans(
        _pages[page - 1],
        highlight.ranges.first.$1,
        highlight.ranges.first.$2,
      ).firstOrNull;
      if (first != null && first.block == index) {
        out.add((from: first.from, to: first.to, badge: highlight.badge!, color: highlight.color!));
      }
    }
    return out;
  }

  TextStyle _runStyle(List<Highlight> layers) {
    var fill = const Color(0x00000000);
    final decorations = <TextDecoration>[];
    Color? lineColor;
    for (final layer in layers) {
      final kind = layer.kind;
      if (kind != null) {
        fill = Color.alphaBlend(kind.color, fill);
        continue;
      }
      final color = layer.color!;
      switch (layer.mark!) {
        case MarkKind.highlight:
          fill = Color.alphaBlend(markFill[color]!, fill);
        case MarkKind.underline:
          decorations.add(TextDecoration.underline);
          lineColor = markLine[color];
        case MarkKind.strike:
          decorations.add(TextDecoration.lineThrough);
          lineColor = markLine[color];
      }
    }
    return TextStyle(
      backgroundColor: fill.a == 0 ? null : fill,
      decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
      decorationColor: lineColor,
      decorationThickness: 2,
    );
  }

  /// The raw range a selection in one paragraph covers, from its readable-text offsets.
  Future<List<PageSelection>> _selected(int page, int index, TextSelection selection) async {
    final block = _pages[page - 1][index];
    final ranges = rawRanges(block.raw, selection.start, selection.end);
    if (ranges.isEmpty) return const [];
    return [(page: page, range: (ranges.first.$1, ranges.last.$2))];
  }

  Widget _menu(int page, int index, BuildContext context, EditableTextState state) {
    final build = widget.buildSelectionMenu;
    final selection = state.textEditingValue.selection;
    if (build == null || selection.isCollapsed) return const SizedBox.shrink();
    final anchors = state.contextMenuAnchors;
    return build(
      context,
      anchors.primaryAnchor,
      anchors.secondaryAnchor,
      () => _selected(page, index, selection),
      () async {
        state.userUpdateTextEditingValue(
          state.textEditingValue.copyWith(selection: TextSelection.collapsed(offset: selection.end)),
          SelectionChangedCause.toolbar,
        );
        state.hideToolbar();
      },
    );
  }

  /// A tap on a paragraph: on a mark, its comment opens.
  void _tapParagraph(int page, int index) {
    final tapped = widget.onMarkTapped;
    final at = _lastPointer;
    final editable = _editable(_blockKeys[page - 1][index]);
    if (tapped == null || at == null || editable == null) {
      widget.onTapped?.call();
      return;
    }
    final offset = editable.getPositionForPoint(at).offset;
    final blocks = _pages[page - 1];
    String? found;
    for (final highlight in widget.highlights) {
      if (highlight.markId == null || highlight.page != page) continue;
      for (final (start, end) in highlight.ranges) {
        for (final span in blockSpans(blocks, start, end)) {
          if (span.block == index && offset >= span.from && offset < span.to) found = highlight.markId;
        }
      }
    }
    if (found != null) {
      tapped(found);
    } else {
      widget.onTapped?.call();
    }
  }

  /// Where the last pointer went down, for finding what a tap landed on.
  Offset? _lastPointer;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final (background, foreground) = readingThemeColors[settings.theme] ?? readingThemeColors['sepia']!;
    final base = TextStyle(
      fontFamily: _fontFamily(settings.font),
      fontSize: settings.size,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing * settings.size,
      color: foreground,
    );
    final heading = base.copyWith(fontSize: settings.size * 1.25, fontWeight: FontWeight.bold);
    final scaler = MediaQuery.textScalerOf(context);
    return GestureDetector(
      // Between the paragraphs; a tap on one is handled by its text.
      onTap: widget.onTapped,
      child: ColoredBox(
        color: background,
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            if (n.dragDetails != null) widget.onTouched?.call();
            return false;
          },
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Column(
                key: _content,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var page = 1; page <= _pages.length; page++)
                    Column(
                      key: _pageKeys[page - 1],
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Page $page',
                            style: TextStyle(color: foreground.withValues(alpha: 0.5), fontSize: 12),
                          ),
                        ),
                        for (var i = 0; i < _pages[page - 1].length; i++)
                          Padding(
                            padding: EdgeInsets.only(bottom: settings.size * 0.8),
                            child: Listener(
                              onPointerDown: (e) => _lastPointer = e.position,
                              child: Builder(
                                builder: (context) {
                                  final span = _paragraph(
                                    page,
                                    i,
                                    _pages[page - 1][i],
                                    _pages[page - 1][i].heading ? heading : base,
                                  );
                                  final badges = _badges(page, i);
                                  return CustomPaint(
                                    foregroundPainter: badges.isEmpty
                                        ? null
                                        : _BadgePainter(span, scaler, Directionality.of(context), badges),
                                    child: SelectableText.rich(
                                      span,
                                      key: _blockKeys[page - 1][i],
                                      textScaler: scaler,
                                      onTap: () => _tapParagraph(page, i),
                                      contextMenuBuilder: (context, state) => _menu(page, i, context, state),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A comment icon to paint in a paragraph: where the mark's first stretch starts and ends in the
/// paragraph's text, and what to show.
typedef _Badge = ({int from, int to, NoteBadge badge, HighlightColor color});

/// Paints the comment icons over a paragraph. It lays the same text out at the same width as the
/// selectable text does, to find the first line of each mark, so it needs nothing from that widget.
class _BadgePainter extends CustomPainter {
  _BadgePainter(this.span, this.scaler, this.direction, this.badges);

  final TextSpan span;
  final TextScaler scaler;
  final TextDirection direction;
  final List<_Badge> badges;

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(text: span, textDirection: direction, textScaler: scaler)
      ..layout(maxWidth: size.width);
    for (final b in badges) {
      final boxes = text.getBoxesForSelection(TextSelection(baseOffset: b.from, extentOffset: b.to));
      if (boxes.isEmpty) continue;
      final line = boxes.first.toRect();
      // About the size of the text, so it follows the reader's font size; above the line.
      final side = (line.height * 0.55).clamp(11.0, 20.0);
      paintMarkBadge(canvas, Rect.fromLTWH(line.left, line.top - side * 0.85, side, side), b.badge, b.color);
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_BadgePainter old) => true;
}

/// The reading view's text settings, changed in a sheet below the view.
class ReadingSettingsSheet extends StatefulWidget {
  const ReadingSettingsSheet({super.key, required this.settings, required this.onChanged});

  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  State<ReadingSettingsSheet> createState() => _ReadingSettingsSheetState();
}

class _ReadingSettingsSheetState extends State<ReadingSettingsSheet> {
  late ReadingSettings _settings = widget.settings;

  void _set(Map<String, Object?> change) {
    final next = normalizeSettings({
      'reading': {..._settings.toJson(), ...change},
    }).reading;
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  Widget _slider(String label, String key, double value, String shown) {
    final (min, max, step) = readingLimits[key]!;
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: (v) => _set({key: v}),
          ),
        ),
        SizedBox(width: 48, child: Text(shown, textAlign: TextAlign.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (font, label) in readingFontChoices)
                ChoiceChip(
                  label: Text(label, style: TextStyle(fontFamily: _fontFamily(font))),
                  selected:
                      _settings.font == font || (_fontFamily(_settings.font) == null && font == 'Verdana'),
                  onSelected: (_) => _set({'font': font}),
                ),
            ],
          ),
          _slider('Size', 'size', _settings.size, '${_settings.size.round()}'),
          _slider(
            'Line spacing',
            'lineHeight',
            _settings.lineHeight,
            _settings.lineHeight.toStringAsFixed(1),
          ),
          _slider(
            'Letter spacing',
            'letterSpacing',
            _settings.letterSpacing,
            _settings.letterSpacing.toStringAsFixed(2),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'sepia', label: Text('Sepia')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {_settings.theme},
            onSelectionChanged: (s) => _set({'theme': s.first}),
          ),
        ],
      ),
    ),
  );
}
