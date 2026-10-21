import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../document_text.dart';
import '../shared/highlight_runs.dart';
import '../shared/layout.dart';
import '../shared/settings.dart';
import '../shared/types.dart';
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
  });

  final DocumentText text;
  final ReadingSettings settings;
  final ReadingController controller;
  final List<Highlight> highlights;

  /// The user scrolled: the view stops following the voice for a while.
  final VoidCallback? onTouched;

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
    for (final (start, end) in ranges) {
      for (final span in blockSpans(blocks, start, end)) {
        final key = _blockKeys[page - 1][span.block];
        final paragraph = key.currentContext?.findRenderObject();
        final top = _top(key);
        if (paragraph is! RenderParagraph || top == null) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: span.from, extentOffset: span.to),
        );
        if (boxes.isEmpty) continue;
        final y = top + boxes.first.top;
        final view = _scroll.position.viewportDimension;
        final from = _scroll.offset;
        // Comfortably inside: leave the view still, as the desktop does.
        final height = boxes.first.bottom - boxes.first.top;
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

  /// A paragraph's text, cut where highlights start and end.
  TextSpan _paragraph(int page, int index, Block block, TextStyle style) {
    final layered = <HighlightRun>[];
    for (final highlight in widget.highlights) {
      if (highlight.page != page) continue;
      for (final (start, end) in highlight.ranges) {
        for (final span in blockSpans(_pages[page - 1], start, end)) {
          if (span.block == index) layered.add((from: span.from, to: span.to, layer: highlight.kind.index));
        }
      }
    }
    return TextSpan(
      style: style,
      children: [
        for (final run in highlightRuns(block.text.length, layered))
          TextSpan(
            text: block.text.substring(run.from, run.to),
            style: run.layer == null
                ? null
                : TextStyle(backgroundColor: HighlightKind.values[run.layer!].color),
          ),
      ],
    );
  }

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
    return ColoredBox(
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
                          child: RichText(
                            key: _blockKeys[page - 1][i],
                            textScaler: scaler,
                            text: _paragraph(
                              page,
                              i,
                              _pages[page - 1][i],
                              _pages[page - 1][i].heading ? heading : base,
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
    );
  }
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
