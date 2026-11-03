import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../document_text.dart';
import '../shared/fonts.dart';
import '../shared/highlight_runs.dart';
import '../shared/layout.dart';
import '../shared/notes.dart';
import '../shared/number_steps.dart';
import '../shared/reading_text.dart';
import '../shared/settings.dart';
import '../shared/types.dart';
import 'fast_scroll.dart';
import 'mark_badge.dart';
import 'mark_menu.dart';
import 'text_view.dart';

/// The speed reader as a `TextView` (PLAN 18.2). Its paragraphs are the pages' blocks, joined where a
/// page ends in the middle of a sentence, so a raw range becomes a stretch of a paragraph through
/// `ReadingText`, as on the desktop through `blockSpans`.
class ReadingController implements TextView {
  _ReadingViewState? _state;

  @override
  bool get isReady => _state?._ready ?? false;

  /// Waiting for a page to load before it can show the place asked for.
  bool get settling => _state?._wanted != null;

  @override
  int? get currentPage => scrollAnchor()?.page;

  /// Where raw ranges of a page are on the screen, for tests that press on a word.
  Offset? globalCenterOf(int page, List<RawRange> ranges) => _state?._globalCenterOf(page, ranges);

  @override
  ({int page, double offset})? scrollAnchor() => _state?._anchorNow();

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
    this.voice,
    this.onTouched,
    this.onMoved,
    this.buildSelectionMenu,
    this.onMarkTapped,
    this.onTapped,
  });

  final DocumentText text;
  final ReadingSettings settings;
  final ReadingController controller;

  /// The marks and the search matches.
  final List<Highlight> highlights;

  /// The spoken sentence and word: only the paragraphs they touch are built again (PLAN 18.1).
  final VoiceHighlights? voice;

  /// The user scrolled: the view stops following the voice for a while.
  final VoidCallback? onTouched;

  /// The view came to rest somewhere else, for remembering the place.
  final VoidCallback? onMoved;

  /// The menu shown over selected text, or null where nothing can be marked.
  final SelectionMenuBuilder? buildSelectionMenu;
  final MarkTapped? onMarkTapped;

  /// A tap that is not on a mark: the reader shows or hides its top bar.
  final VoidCallback? onTapped;

  @override
  State<ReadingView> createState() => _ReadingViewState();
}

/// A highlight's stretch of one paragraph.
typedef _Span = ({int from, int to, Highlight highlight});

/// The room left of the text, where the page numbers are.
const _gutter = 30.0;

class _ReadingViewState extends State<ReadingView> {
  final _scroll = ScrollController();

  /// Each page's blocks, as they are loaded, and the paragraphs made of them.
  final _pages = <List<Block>>[];
  ReadingText _text = ReadingText(const []);

  /// The list is built from this paragraph down, and from the one before it up, so a jump to any
  /// place builds only what is shown there. `_generation` names the lists anew for each jump.
  int _anchor = 0;
  int _generation = 0;

  /// The paragraphs that are built now, by their index.
  final _built = <int, _ParagraphState>{};

  /// A place asked for before its page was loaded: shown as soon as it is.
  ({int page, double offset})? _wanted;

  /// The marks and search matches, and the voice, as stretches of each paragraph.
  Map<int, List<_Span>> _marks = const {};
  final _voice = ValueNotifier<Map<int, List<_Span>>>(const {});

  /// The text styles of this build, for the paragraphs.
  late TextStyle _base;
  late TextStyle _heading;
  late TextScaler _scaler;

  bool get _ready => _scroll.hasClients && _text.paragraphs.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    widget.voice?.addListener(_voiceChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ReadingView old) {
    super.didUpdateWidget(old);
    widget.controller._state = this;
    if (old.voice != widget.voice) {
      old.voice?.removeListener(_voiceChanged);
      widget.voice?.addListener(_voiceChanged);
      _voiceChanged();
    }
    if (!identical(old.highlights, widget.highlights)) _marks = _spansOf(widget.highlights);
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    widget.voice?.removeListener(_voiceChanged);
    _voice.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reads the pages in order, so the first page shows while the rest is read. The paragraphs are
  /// made again in batches, not for every page, which a long document would feel.
  Future<void> _load() async {
    var shown = DateTime.now();
    final count = widget.text.pageCount;
    for (var page = 1; page <= count; page++) {
      final blocks = (await widget.text.page(page)).blocks;
      if (!mounted) return;
      _pages.add(blocks);
      final now = DateTime.now();
      if (page <= 2 || page == count || _wanted?.page == page || now.difference(shown).inMilliseconds > 300) {
        shown = now;
        _textChanged();
      }
    }
  }

  void _textChanged() {
    setState(() {
      _text = ReadingText(List.of(_pages));
      _marks = _spansOf(widget.highlights);
    });
    _voiceChanged();
    final wanted = _wanted;
    if (wanted != null && wanted.page <= _pages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wanted == wanted) _showPage(wanted.page, wanted.offset);
      });
    }
  }

  void _voiceChanged() => _voice.value = _spansOf(widget.voice?.value ?? const []);

  Map<int, List<_Span>> _spansOf(List<Highlight> highlights) {
    final out = <int, List<_Span>>{};
    for (final h in highlights) {
      for (final (start, end) in h.ranges) {
        for (final s in _text.spans(h.page, start, end)) {
          (out[s.paragraph] ??= []).add((from: s.from, to: s.to, highlight: h));
        }
      }
    }
    return out;
  }

  /// The viewport's box, which the positions of the paragraphs are measured from.
  RenderBox? get _viewport => context.findRenderObject() as RenderBox?;

  /// The page at the top edge of the view and how far down its text that edge lies.
  ({int page, double offset})? _anchorNow() {
    final viewport = _viewport;
    if (!_ready || viewport == null || !viewport.hasSize) return null;
    _ParagraphState? below;
    var belowY = double.infinity;
    for (final state in _built.values) {
      final box = state._textBox;
      if (box == null) continue;
      final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (y <= 0 && y + box.size.height > 0) {
        final at = state._offsetAt(Offset(1, -y + 1));
        return _text.pageOfPlace(state.widget.index, at);
      }
      if (y > 0 && y < belowY) (below, belowY) = (state, y);
    }
    if (below == null) return null;
    return _text.pageOfPlace(below.widget.index, 0);
  }

  void _showPage(int page, double offset) {
    final place = _text.placeOfPage(page, offset);
    if (place == null) {
      _wanted = (page: page, offset: offset);
      return;
    }
    _wanted = null;
    _showPlace(place, 0);
  }

  /// Scrolls so that the line of `place` is `share` of the view's height from the top. A paragraph
  /// that is not built is reached by building the lists afresh from it.
  void _showPlace(ReadingPlace place, double share, {bool animate = false, bool again = true}) {
    final viewport = _viewport;
    final line = _built[place.paragraph]?._lineOf(place.at, viewport);
    if (line != null && _scroll.hasClients && viewport != null) {
      final position = _scroll.position;
      final target = (_scroll.offset + line.top - share * viewport.size.height).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (animate) {
        unawaited(
          _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        );
      } else {
        _scroll.jumpTo(target);
      }
      return;
    }
    if (!again || !mounted) return;
    setState(() {
      _anchor = place.paragraph;
      _generation++;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showPlace(place, share, again: false);
    });
  }

  /// The first range's first stretch, the line it is on, and the paragraph's state if it is built.
  ({int paragraph, int from, int to})? _firstSpan(int page, List<RawRange> ranges) {
    for (final (start, end) in ranges) {
      final spans = _text.spans(page, start, end);
      if (spans.isNotEmpty) return spans.first;
    }
    return null;
  }

  void _reveal(int page, List<RawRange> ranges) {
    final span = _firstSpan(page, ranges);
    if (span == null) {
      if (page > _pages.length) _showPage(page, 0);
      return;
    }
    final viewport = _viewport;
    final line = _built[span.paragraph]?._lineOf(span.from, viewport);
    if (line != null && viewport != null) {
      final view = viewport.size.height;
      // Comfortably inside: leave the view still, as the desktop does.
      if (line.top >= view * 0.1 && line.bottom <= view * 0.75) return;
    }
    _showPlace((paragraph: span.paragraph, at: span.from), 0.3, animate: true);
  }

  Offset? _globalCenterOf(int page, List<RawRange> ranges) {
    final span = _firstSpan(page, ranges);
    if (span == null) return null;
    return _built[span.paragraph]?._globalCenter(span.from, span.to);
  }

  /// The menu over a selection in one paragraph, which may reach over a page break.
  Widget _menu(int index, BuildContext context, EditableTextState state) {
    final build = widget.buildSelectionMenu;
    final selection = state.textEditingValue.selection;
    if (build == null || selection.isCollapsed) return const SizedBox.shrink();
    final anchors = state.contextMenuAnchors;
    return build(
      context,
      anchors.primaryAnchor,
      anchors.secondaryAnchor,
      () async => _text.rawSelection(index, selection.start, selection.end),
      () async {
        state.userUpdateTextEditingValue(
          state.textEditingValue.copyWith(selection: TextSelection.collapsed(offset: selection.end)),
          SelectionChangedCause.toolbar,
        );
        state.hideToolbar();
      },
    );
  }

  int get _pageCount => math.max(1, widget.text.pageCount);

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    // The page and the text take the app's colours (PLAN M15); only the type is the reading view's own.
    final scheme = Theme.of(context).colorScheme;
    _base = TextStyle(
      fontFamily: fontFamilyOf(settings.font),
      fontSize: settings.size,
      height: settings.lineHeight,
      letterSpacing: settings.letterSpacing * settings.size,
      color: scheme.onSurface,
    );
    _heading = _base.copyWith(fontSize: settings.size * 1.25, fontWeight: FontWeight.bold);
    // The system's text size counts, the app's own text size does not: the reading view has its own.
    _scaler = MediaQueryData.fromView(View.of(context)).textScaler;
    final count = _text.paragraphs.length;
    final center = ValueKey('reading-$_generation');
    Widget item(int index) => _Paragraph(key: ValueKey(index), index: index, view: this);
    return GestureDetector(
      // Between the paragraphs; a tap on one is handled by its text.
      onTap: widget.onTapped,
      child: ColoredBox(
        color: scheme.surface,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) widget.onTouched?.call();
            if (n is ScrollEndNotification) widget.onMoved?.call();
            return false;
          },
          child: FastScrollThumb(
            listenable: _scroll,
            fraction: () {
              final at = _anchorNow();
              return at == null || widget.text.pageCount < 2
                  ? null
                  : ((at.page - 1 + at.offset) / _pageCount).clamp(0.0, 1.0);
            },
            label: () => '${_anchorNow()?.page ?? 1}',
            onJump: (fraction) {
              widget.onTouched?.call();
              final x = fraction * _pageCount;
              final page = (x.floor() + 1).clamp(1, _pageCount);
              _showPage(page, (x - (page - 1)).clamp(0.0, 0.999));
              widget.onMoved?.call();
            },
            // A page a step: that is what a swipe of a screen reader means in a document.
            onStep: (direction) {
              final page = _anchorNow()?.page ?? 1;
              _showPage((page + direction).clamp(1, _pageCount), 0);
              widget.onMoved?.call();
            },
            child: CustomScrollView(
              controller: _scroll,
              center: center,
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 0, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => item(_anchor - 1 - i),
                      childCount: _anchor,
                    ),
                  ),
                ),
                SliverPadding(
                  key: center,
                  padding: const EdgeInsets.fromLTRB(_gutter, 0, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => item(_anchor + i),
                      childCount: math.max(0, count - _anchor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One paragraph of the speed reader. It is built again when the reader's highlights change, and on
/// its own when the voice comes to it or leaves it.
class _Paragraph extends StatefulWidget {
  const _Paragraph({super.key, required this.index, required this.view});

  final int index;
  final _ReadingViewState view;

  @override
  State<_Paragraph> createState() => _ParagraphState();
}

class _ParagraphState extends State<_Paragraph> {
  final _textKey = GlobalKey();
  List<_Span> _voice = const [];

  /// Where the last pointer went down, for finding what a tap landed on.
  Offset? _pointer;

  _ReadingViewState get _view => widget.view;

  @override
  void initState() {
    super.initState();
    _view._built[widget.index] = this;
    _voice = _view._voice.value[widget.index] ?? const [];
    _view._voice.addListener(_voiceChanged);
  }

  @override
  void didUpdateWidget(_Paragraph old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (_view._built[old.index] == this) _view._built.remove(old.index);
      _view._built[widget.index] = this;
    }
    _voice = _view._voice.value[widget.index] ?? const [];
  }

  // A paragraph taken out of the tree, as the lists are built afresh after a jump, is no longer asked
  // where it is.
  @override
  void deactivate() {
    if (_view._built[widget.index] == this) _view._built.remove(widget.index);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _view._built[widget.index] = this;
  }

  @override
  void dispose() {
    if (_view._built[widget.index] == this) _view._built.remove(widget.index);
    _view._voice.removeListener(_voiceChanged);
    super.dispose();
  }

  void _voiceChanged() {
    final next = _view._voice.value[widget.index] ?? const <_Span>[];
    if (_same(next, _voice)) return;
    setState(() => _voice = next);
  }

  static bool _same(List<_Span> a, List<_Span> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].from != b[i].from || a[i].to != b[i].to || a[i].highlight.kind != b[i].highlight.kind) {
        return false;
      }
    }
    return true;
  }

  /// The text's render object inside the selectable text: it knows where each character is.
  RenderEditable? get _editable {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    final root = _textKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  RenderBox? get _textBox {
    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.attached && box.hasSize ? box : null;
  }

  /// The character at a point given in this paragraph's text box.
  int _offsetAt(Offset local) {
    final editable = _editable;
    final box = _textBox;
    if (editable == null || box == null) return 0;
    return editable.getPositionForPoint(box.localToGlobal(local)).offset;
  }

  /// The line of a character, from the top of the viewport.
  ({double top, double bottom})? _lineOf(int at, RenderBox? viewport) {
    final editable = _editable;
    if (editable == null || viewport == null || !editable.attached) return null;
    final length = _view._text.paragraphs[widget.index].text.length;
    final from = math.max(0, math.min(at, length - 1));
    final boxes = editable.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: from + 1));
    final top = editable.localToGlobal(Offset(0, boxes.isEmpty ? 0 : boxes.first.top), ancestor: viewport).dy;
    final height = boxes.isEmpty ? 0.0 : boxes.first.bottom - boxes.first.top;
    return (top: top, bottom: top + height);
  }

  Offset? _globalCenter(int from, int to) {
    final editable = _editable;
    if (editable == null) return null;
    final boxes = editable.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to));
    return boxes.isEmpty ? null : editable.localToGlobal(boxes.first.toRect().center);
  }

  /// The paragraph's text, cut where highlights start and end. Each highlight that covers a stretch
  /// adds its look, in the order of `paintLayer`: fills blend, underline and strike-through combine.
  TextSpan _span(ReadingParagraph paragraph, TextStyle style, List<_Span> spans) {
    final layered = [...spans]..sort((a, b) => paintLayer(a.highlight).compareTo(paintLayer(b.highlight)));
    final ids = <Highlight, int>{};
    final numbered = <HighlightSpan>[
      for (final s in layered) (from: s.from, to: s.to, id: ids.putIfAbsent(s.highlight, () => ids.length)),
    ];
    final byId = {for (final MapEntry(:key, :value) in ids.entries) value: key};
    return TextSpan(
      style: style,
      children: [
        for (final run in highlightRuns(paragraph.text.length, numbered))
          TextSpan(
            text: paragraph.text.substring(run.from, run.to),
            style: run.ids.isEmpty ? null : _runStyle([for (final id in run.ids) byId[id]!]),
          ),
      ],
    );
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

  /// A tap on the paragraph: on a mark, its comment opens.
  void _tap() {
    final tapped = _view.widget.onMarkTapped;
    final at = _pointer;
    final editable = _editable;
    if (tapped == null || at == null || editable == null) {
      _view.widget.onTapped?.call();
      return;
    }
    final offset = editable.getPositionForPoint(at).offset;
    String? found;
    for (final s in _view._marks[widget.index] ?? const <_Span>[]) {
      if (s.highlight.markId != null && offset >= s.from && offset < s.to) found = s.highlight.markId;
    }
    if (found != null) {
      tapped(found);
    } else {
      _view.widget.onTapped?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final paragraph = view._text.paragraphs[widget.index];
    final marks = view._marks[widget.index] ?? const <_Span>[];
    final span = _span(paragraph, paragraph.heading ? view._heading : view._base, [...marks, ..._voice]);
    // A mark's comment icon goes on the paragraph that holds the mark's first stretch.
    final badges = <_Badge>[
      for (final s in marks)
        if (s.highlight.badge case final badge? when _isFirst(s))
          (from: s.from, to: s.to, badge: badge, color: s.highlight.color!),
    ];
    final scheme = Theme.of(context).colorScheme;
    Widget text = SelectableText.rich(
      span,
      key: _textKey,
      textScaler: view._scaler,
      onTap: _tap,
      contextMenuBuilder: (context, state) => view._menu(widget.index, context, state),
    );
    if (paragraph.heading) text = Semantics(header: true, child: text);
    if (badges.isNotEmpty || paragraph.pageStarts.isNotEmpty) {
      text = CustomPaint(
        foregroundPainter: _MarginPainter(
          span,
          view._scaler,
          Directionality.of(context),
          badges,
          paragraph.pageStarts,
          TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
        ),
        child: text,
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: widget.index == 0 ? 16 : 0, bottom: view.widget.settings.size * 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A heading for a screen reader, which jumps from page to page by headings; the number itself
          // is painted in the margin, so the text runs on without a gap between pages.
          for (final start in paragraph.pageStarts)
            Semantics(header: true, label: 'Page ${start.page}', child: const SizedBox(height: 1)),
          Listener(onPointerDown: (e) => _pointer = e.position, child: text),
        ],
      ),
    );
  }

  /// Whether a mark's stretch is the first one of its mark, where its icon belongs.
  bool _isFirst(_Span s) {
    final first = s.highlight.ranges.firstOrNull;
    if (first == null) return false;
    final spans = _view._text.spans(s.highlight.page, first.$1, first.$2);
    return spans.isNotEmpty && spans.first.paragraph == widget.index && spans.first.from == s.from;
  }
}

/// A comment icon to paint in a paragraph: where the mark's first stretch starts and ends in the
/// paragraph's text, and what to show.
typedef _Badge = ({int from, int to, NoteBadge badge, HighlightColor color});

/// Paints the comment icons over a paragraph and the page numbers in the margin beside the line each
/// page starts on. It lays the same text out at the same width as the selectable text does, so it
/// needs nothing from that widget.
class _MarginPainter extends CustomPainter {
  _MarginPainter(this.span, this.scaler, this.direction, this.badges, this.pages, this.pageStyle);

  final TextSpan span;
  final TextScaler scaler;
  final TextDirection direction;
  final List<_Badge> badges;
  final List<PageStart> pages;
  final TextStyle pageStyle;

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
    for (final start in pages) {
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: start.at, extentOffset: start.at + 1),
      );
      final line = boxes.isEmpty ? Rect.fromLTWH(0, 0, 0, text.preferredLineHeight) : boxes.first.toRect();
      final number = TextPainter(
        text: TextSpan(text: '${start.page}', style: pageStyle),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      number.paint(canvas, Offset(-number.width - 8, line.top + (line.height - number.height) / 2));
      number.dispose();
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_MarginPainter old) => true;
}

/// The reading view's text settings: each a number with − and + (PLAN 18.6), in a sheet below the
/// view and on the Speed reader page in Settings.
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
              for (final (font, label) in fontChoices)
                ChoiceChip(
                  label: Text(label, style: TextStyle(fontFamily: fontFamilyOf(font))),
                  selected:
                      _settings.font == font || (fontFamilyOf(_settings.font) == null && font == 'Verdana'),
                  onSelected: (_) => _set({'font': font}),
                ),
            ],
          ),
          const SizedBox(height: 8),
          NumberSetting(
            label: 'Size',
            settingKey: 'size',
            value: _settings.size,
            limits: readingLimits['size']!,
            onChanged: (v) => _set({'size': v}),
          ),
          NumberSetting(
            label: 'Line spacing',
            settingKey: 'lineHeight',
            value: _settings.lineHeight,
            limits: readingLimits['lineHeight']!,
            onChanged: (v) => _set({'lineHeight': v}),
          ),
          NumberSetting(
            label: 'Letter spacing',
            settingKey: 'letterSpacing',
            value: _settings.letterSpacing,
            limits: readingLimits['letterSpacing']!,
            onChanged: (v) => _set({'letterSpacing': v}),
          ),
        ],
      ),
    ),
  );
}

/// One number: − and + move it a step, and it can be typed; what is typed counts when the field is left
/// or the keyboard's done is pressed, kept inside the setting's limits.
class NumberSetting extends StatefulWidget {
  const NumberSetting({
    super.key,
    required this.label,
    required this.settingKey,
    required this.value,
    required this.limits,
    required this.onChanged,
  });

  final String label;

  /// Names the controls for tests: `<key>-down`, `<key>-field`, `<key>-up`.
  final String settingKey;
  final double value;
  final NumberLimits limits;
  final ValueChanged<double> onChanged;

  @override
  State<NumberSetting> createState() => _NumberSettingState();
}

class _NumberSettingState extends State<NumberSetting> {
  late final _field = TextEditingController(text: shownNumber(widget.value, widget.limits));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberSetting old) {
    super.didUpdateWidget(old);
    final shown = shownNumber(widget.value, widget.limits);
    if (!_focus.hasFocus && _field.text != shown) _field.text = shown;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final value = parsedNumber(_field.text, widget.limits);
    final shown = shownNumber(value ?? widget.value, widget.limits);
    if (_field.text != shown) _field.text = shown;
    if (value != null && value != widget.value) widget.onChanged(value);
  }

  void _step(int direction) {
    final value = stepped(parsedNumber(_field.text, widget.limits) ?? widget.value, widget.limits, direction);
    _field.text = shownNumber(value, widget.limits);
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final (min, max, _) = widget.limits;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(widget.label)),
          IconButton.outlined(
            key: Key('${widget.settingKey}-down'),
            icon: const Icon(Icons.remove),
            tooltip: '${widget.label}: less',
            onPressed: widget.value <= min ? null : () => _step(-1),
          ),
          SizedBox(
            width: 72,
            // The field and its name are one thing to a screen reader.
            child: MergeSemantics(
              child: Semantics(
                label: widget.label,
                child: TextField(
                  key: Key('${widget.settingKey}-field'),
                  controller: _field,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ),
          ),
          IconButton.outlined(
            key: Key('${widget.settingKey}-up'),
            icon: const Icon(Icons.add),
            tooltip: '${widget.label}: more',
            onPressed: widget.value >= max ? null : () => _step(1),
          ),
        ],
      ),
    );
  }
}
