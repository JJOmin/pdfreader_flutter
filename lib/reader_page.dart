import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'document_text.dart';
import 'library.dart';
import 'places.dart';
import 'playback.dart';
import 'reader.dart';
import 'shared/pdfium_text.dart';
import 'shared/read_plan.dart';
import 'shared/settings.dart';
import 'shared/sync.dart';
import 'shared/types.dart';

/// After the user scrolls or zooms, the view leaves the voice alone this long, as on the desktop.
const _followPause = Duration(seconds: 3);

/// A run of scrolling is saved once it has paused this long, as on the desktop.
const _placeDelay = Duration(milliseconds: 400);

/// One document: the pages, and reading aloud when the desktop prepared it.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.name,
    required this.data,
    required this.placeKey,
    this.prepared,
    this.playback,
    this.places,
  });

  final String name;
  final Uint8List data;

  /// Names the document in the saved places: its URI, or its id when it came from the library.
  final String placeKey;

  /// Null in widget tests: nothing is remembered.
  final Places? places;

  /// Null when the desktop has not prepared this PDF: it shows, but cannot be read aloud.
  final LibraryDocument? prepared;
  final ReadingHandler? playback;

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage> implements ReaderHost {
  final _controller = PdfViewerController();
  DocumentText? _text;
  Reader? _reader;
  final _plans = <int, Future<PagePlan>>{};
  int? _skipped;

  /// The sentence being read and its word, and the page's text they are painted from.
  PlannedSentence? sentence;
  int word = -1;
  ReaderState state = ReaderState.idle;
  LoadedPage? _spokenPage;
  DateTime _lastTouch = DateTime(0);
  String? _error;

  /// Set when the page closes: stopping the reader then reports back, but nothing may be rebuilt.
  bool _closing = false;

  late double _speed = widget.places?.speed ?? 1;
  PdfDocument? _document;

  /// Where Play continues the first time it is pressed: the sentence the voice left off at.
  Cursor? _resume;

  /// The sentence the voice read last, kept with the place.
  Cursor? _lastSentence;

  /// The place saved when the document was last open here.
  late final _saved = widget.places?.progress(widget.placeKey)?.progress;

  /// False until the saved place is shown, so the top of the document is not saved over it.
  bool _placed = false;
  Timer? _placeTimer;

  /// Another device's newer place in this document, offered until the user answers.
  DeviceState? _offer;

  void _ready(PdfDocument document, PdfViewerController controller) {
    final text = DocumentText(document);
    final prepared = widget.prepared;
    _document = document;
    setState(() => _text = text);
    final saved = _saved;
    final sentence = saved?.sentence;
    if (sentence != null) _resume = _lastSentence = (page: sentence.page, index: sentence.index);
    // The viewer opens on the saved page itself; the offset and zoom follow once it has settled,
    // because a move during its first layout is undone by it.
    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      // Saving waits for the view to rest, so it records where this move ends.
      _placed = true;
      _controller.addListener(_moved);
      if (saved != null) unawaited(_show(saved.page, saved.offset, saved.zoom));
    });
    if (prepared == null) return;
    unawaited(_findOffer(prepared));
    final reader = Reader(this, LibraryAudio(prepared))..speed = _speed;
    setState(() => _reader = reader);
    final playback = widget.playback;
    if (playback != null) {
      playback.onPlay = playback.onPause = _toggle;
      playback.onSkip = (direction) => reader.skip(direction);
      playback.onStop = reader.stop;
    }
    unawaited(_countSkipped());
  }

  /// Scrolls to a place at the given zoom, or the current one.
  Future<void> _show(int page, double offset, double? zoom) async {
    final document = _document;
    if (document == null || page < 1 || page > document.pages.length || !_controller.isReady) return;
    final rect = _pageRect(page);
    final scale = zoom ?? _controller.currentZoom;
    final top = rect.top + offset * rect.height;
    final view = _controller.viewSize;
    final matrix = _controller.calcMatrixFor(
      Offset(_controller.centerPosition.dx, top + view.height / (2 * scale)),
      zoom: scale,
    );
    await _controller.goTo(_controller.calcMatrixForClampedToNearestBoundary(matrix, viewSize: view));
  }

  /// A page's rectangle in the document's layout.
  Rect _pageRect(int page) {
    final pdfPage = _document!.pages[page - 1];
    return _controller.calcRectForRectInsidePage(
      pageNumber: page,
      rect: PdfRect(0, pdfPage.height, pdfPage.width, 0),
    );
  }

  void _moved() {
    _placeTimer?.cancel();
    _placeTimer = Timer(_placeDelay, _savePlace);
  }

  /// Remembers where the user is, and for a prepared document writes this phone's state (step 5.6).
  Future<void> _savePlace() async {
    final places = widget.places;
    if (places == null || !_placed || !_controller.isReady || _closing) return;
    final page = _controller.pageNumber ?? 1;
    final rect = _pageRect(page);
    final offset = ((_controller.visibleRect.top - rect.top) / rect.height).clamp(0.0, 0.999);
    final last = _lastSentence;
    String? key;
    if (last != null && widget.prepared != null) {
      final sentences = (await _plan(last.page)).sentences;
      if (last.index < sentences.length) key = sentences[last.index].key;
    }
    places.remember(
      widget.placeKey,
      Progress(
        view: 'pdf',
        zoom: (_controller.currentZoom * 1000).round() / 1000,
        page: page,
        offset: offset,
        sentence: last,
      ),
      prepared: widget.prepared,
      sentenceKey: key,
    );
  }

  /// Offers another device's place if it is newer than this phone's (ADR 7 section 8).
  Future<void> _findOffer(LibraryDocument prepared) async {
    final identity = widget.places?.identity;
    if (identity == null) return;
    final offer = placeOffer(
      await libraryStates(prepared),
      identity.device,
      widget.places!.progress(widget.placeKey)?.updated,
    );
    if (offer != null && mounted) setState(() => _offer = offer);
  }

  Future<void> _continueThere(DeviceState offer) async {
    setState(() => _offer = null);
    _reader?.stop();
    final sentence = offer.sentence;
    if (sentence != null && widget.prepared != null) {
      // Found by its key first, by its index second.
      final sentences = (await _plan(sentence.page)).sentences;
      final byKey = sentences.indexWhere((s) => s.key == sentence.key);
      _resume = _lastSentence = (page: sentence.page, index: byKey >= 0 ? byKey : sentence.index);
    } else {
      _resume = (page: offer.page, index: 0);
    }
    await _show(offer.page, offer.offset, null);
    await _savePlace();
  }

  /// The document says how many of its sentences have no audio (ADR 2 section 1).
  Future<void> _countSkipped() async {
    var skipped = 0;
    for (var page = 1; page <= pageCount; page++) {
      skipped += (await _plan(page)).skipped;
    }
    if (mounted) setState(() => _skipped = skipped);
  }

  Future<PagePlan> _plan(int page) => _plans[page] ??= () async {
    final utterances = await _text!.utterances(page);
    return planPage(utterances, await widget.prepared!.index(page));
  }();

  @override
  int get pageCount => _text?.pageCount ?? 0;

  @override
  Future<List<PlannedSentence>> sentences(int page) async => (await _plan(page)).sentences;

  @override
  void onChange(ReaderState state, PlannedSentence? sentence, int word) {
    if (!mounted || _closing) return;
    final changedSentence = sentence != null && sentence != this.sentence;
    setState(() {
      this.state = state;
      _error = null;
      if (sentence != null) {
        this.sentence = sentence;
        this.word = word;
      } else if (state == ReaderState.idle) {
        this.sentence = null;
        this.word = -1;
      }
    });
    widget.playback?.show(state, widget.name, this.sentence?.page ?? _controller.pageNumber ?? 1);
    if (changedSentence) {
      _resume = null;
      final at = _reader?.cursor;
      if (at != null) {
        _lastSentence = at;
        unawaited(_savePlace());
      }
      _spokenPage = null;
      unawaited(
        _text!.page(sentence.page).then((page) {
          if (!mounted || this.sentence != sentence) return;
          _spokenPage = page;
          _repaint();
        }),
      );
    }
    _repaint();
  }

  @override
  void onError(Object error) {
    if (mounted && !_closing) setState(() => _error = '$error');
  }

  void _repaint() {
    if (_controller.isReady) _controller.invalidate();
    _follow();
  }

  /// The page the view shows, for the integration test.
  int? get currentPage => _controller.pageNumber;

  void _toggle() => _reader?.toggle(_resume ?? (page: _controller.pageNumber ?? 1, index: 0));

  /// The boxes of raw ranges on the spoken page, in PDF units.
  List<CharBox> _boxes(List<RawRange> ranges) {
    final page = _spokenPage;
    if (page == null) return const [];
    final rects = [
      for (final r in page.charRects) (left: r.left, bottom: r.bottom, right: r.right, top: r.top),
    ];
    return rangeBoxes(ranges, page.text.charIndex, rects);
  }

  /// Keeps the spoken word in view, unless the user has just moved the view somewhere else.
  void _follow() {
    final sentence = this.sentence;
    if (sentence == null || !_controller.isReady || DateTime.now().difference(_lastTouch) < _followPause) {
      return;
    }
    final word = this.word;
    final boxes = _boxes(
      word >= 0 && word < sentence.words.length ? sentence.words[word].ranges : sentence.ranges,
    );
    if (boxes.isEmpty) {
      if (_spokenPage == null && _controller.pageNumber != sentence.page) {
        unawaited(_controller.goToPage(pageNumber: sentence.page));
      }
      return;
    }
    final b = boxes.first;
    final rect = _controller.calcRectForRectInsidePage(
      pageNumber: sentence.page,
      rect: PdfRect(b.left, b.top, b.right, b.bottom),
    );
    final visible = _controller.visibleRect;
    // Comfortably inside: leave the view still, as the desktop does.
    final comfort = Rect.fromLTRB(
      visible.left,
      visible.top + visible.height * 0.1,
      visible.right,
      visible.bottom - visible.height * 0.25,
    );
    if (!comfort.contains(rect.topLeft) || !comfort.contains(rect.bottomRight)) {
      // Scrolls at the user's zoom: the word goes to 30 % from the top, sideways only if it is off
      // screen. ensureVisible would zoom in on the word.
      final x = visible.left <= rect.left && rect.right <= visible.right ? visible.center.dx : rect.center.dx;
      final matrix = _controller.calcMatrixFor(Offset(x, rect.center.dy + visible.height * 0.2));
      unawaited(
        _controller.goTo(
          _controller.calcMatrixForClampedToNearestBoundary(matrix, viewSize: _controller.viewSize),
        ),
      );
    }
  }

  void _paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final sentence = this.sentence;
    if (sentence == null || page.pageNumber != sentence.page) return;
    Rect place(CharBox b) =>
        PdfRect(b.left, b.top, b.right, b.bottom).toRectInDocument(page: page, pageRect: pageRect);
    final tint = Paint()..color = const Color(0x40FFD54F);
    for (final b in _boxes(sentence.ranges)) {
      canvas.drawRect(place(b), tint);
    }
    if (word >= 0 && word < sentence.words.length) {
      final mark = Paint()..color = const Color(0x66FF8F00);
      for (final b in _boxes(sentence.words[word].ranges)) {
        canvas.drawRRect(RRect.fromRectAndRadius(place(b).inflate(1), const Radius.circular(2)), mark);
      }
    }
  }

  @override
  void dispose() {
    _placeTimer?.cancel();
    _controller.removeListener(_moved);
    if (_placed) unawaited(_savePlace().then((_) => widget.places?.flush()));
    _closing = true;
    final playback = widget.playback;
    if (playback != null) {
      playback.onPlay = playback.onPause = playback.onStop = null;
      playback.onSkip = null;
      playback.show(ReaderState.idle, widget.name, 1);
    }
    unawaited(_reader?.dispose());
    super.dispose();
  }

  String? get _status {
    if (_error != null) return _error;
    if (widget.prepared == null) return 'Not prepared on the desktop';
    final skipped = _skipped ?? 0;
    if (skipped > 0) return '$skipped sentences have no audio and are skipped';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final reader = _reader;
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          if (_offer case final offer?)
            MaterialBanner(
              key: const Key('place-offer'),
              content: Text('Continue where you stopped on ${offer.name}, page ${offer.page}?'),
              actions: [
                TextButton(onPressed: () => setState(() => _offer = null), child: const Text('Stay here')),
                TextButton(
                  key: const Key('place-continue'),
                  onPressed: () => _continueThere(offer),
                  child: const Text('Continue there'),
                ),
              ],
            ),
          Expanded(
            child: PdfViewer.data(
              widget.data,
              sourceName: widget.prepared?.manifest.docId ?? widget.name,
              controller: _controller,
              initialPageNumber: _saved?.page ?? 1,
              params: PdfViewerParams(
                onViewerReady: _ready,
                onInteractionStart: (_) => _lastTouch = DateTime.now(),
                pagePaintCallbacks: [_paint],
              ),
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(status, key: const Key('status'), style: Theme.of(context).textTheme.bodySmall),
            ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous sentence',
                  onPressed: reader == null ? null : () => reader.skip(-1),
                ),
                IconButton.filled(
                  key: const Key('play'),
                  icon: Icon(state == ReaderState.playing ? Icons.pause : Icons.play_arrow),
                  tooltip: state == ReaderState.playing ? 'Pause' : 'Read aloud',
                  onPressed: reader == null ? null : _toggle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next sentence',
                  onPressed: reader == null ? null : () => reader.skip(1),
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  tooltip: 'Stop reading',
                  onPressed: reader == null || state == ReaderState.idle ? null : reader.stop,
                ),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: ((maxSpeed - minSpeed) / 0.05).round(),
                    label: '${_speed.toStringAsFixed(2)}×',
                    onChanged: reader == null
                        ? null
                        : (value) => setState(() {
                            _speed = value;
                            reader.speed = value;
                            widget.places?.speed = value;
                          }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('${_speed.toStringAsFixed(2)}×'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
