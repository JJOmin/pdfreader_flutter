import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'document_text.dart';
import 'library.dart';
import 'notes_store.dart';
import 'places.dart';
import 'playback.dart';
import 'reader.dart';
import 'shared/marks.dart';
import 'shared/notes.dart';
import 'shared/read_plan.dart';
import 'shared/search.dart';
import 'shared/settings.dart';
import 'shared/sync.dart';
import 'shared/types.dart';
import 'views/mark_menu.dart';
import 'views/notes_sheet.dart';
import 'views/pdf_pages_view.dart';
import 'views/reading_view.dart';
import 'views/text_view.dart';

/// After the user scrolls or zooms, the view leaves the voice alone this long, as on the desktop.
const _followPause = Duration(seconds: 3);

/// A run of scrolling is saved once it has paused this long, as on the desktop.
const _placeDelay = Duration(milliseconds: 400);

/// Typing is searched once it pauses this long, as on the desktop.
const _searchDelay = Duration(milliseconds: 200);

/// The kind of mark made last, kept for the next one and across documents while the app runs.
MarkKind _lastKind = MarkKind.highlight;

/// Marks are written once they have not changed for this long.
const _notesDelay = Duration(milliseconds: 500);

/// One document: the pages or the reading view, reading aloud when the desktop prepared it, and search.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.name,
    required this.data,
    required this.placeKey,
    this.prepared,
    this.playback,
    this.places,
    this.notesStore,
  });

  final String name;
  final Uint8List data;

  /// Names the document in the saved places: its URI, or its id when it came from the library.
  final String placeKey;

  /// Null in widget tests: nothing is remembered.
  final Places? places;

  /// Null in widget tests: nothing is marked.
  final NotesStore? notesStore;

  /// Null when the desktop has not prepared this PDF: it shows, but cannot be read aloud.
  final LibraryDocument? prepared;
  final ReadingHandler? playback;

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage> implements ReaderHost {
  PdfDocument? _document;
  PdfDocumentRef? _documentRef;
  DocumentText? _text;
  Reader? _reader;
  final _plans = <int, Future<PagePlan>>{};
  int? _skipped;

  final _pdf = PdfPagesController();
  final _readingView = ReadingController();

  /// True while the reading view is shown instead of the pages.
  late bool reading = _saved?.view == 'reading';
  TextView get _view => reading ? _readingView : _pdf;

  /// The sentence being read and its word.
  PlannedSentence? sentence;
  int word = -1;
  ReaderState state = ReaderState.idle;
  DateTime _lastTouch = DateTime(0);
  String? _error;

  /// Set when the page closes: stopping the reader then reports back, but nothing may be rebuilt.
  bool _closing = false;

  late double _speed = widget.places?.speed ?? 1;
  late ReadingSettings _readingSettings = widget.places?.reading ?? defaultSettings().reading;

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

  /// The document's id: the hash of its bytes, which the library and the notes files share.
  late final String _docId = widget.prepared?.manifest.docId ?? sha256.convert(widget.data).toString();

  /// The marks and general notes as written, and where each mark lies on this device's raw
  /// strings. A mark made on the desktop is placed by its text, since the two engines' offsets differ.
  NotesFile _notes = emptyNotes();
  Map<String, (int, int)> _markAt = const {};
  Timer? _notesTimer;
  bool _notesDirty = false;

  /// The search box, while it is open, and what it found: page and raw ranges, in reading order.
  final _searchBox = TextEditingController();
  bool _searching = false;
  Timer? _searchTimer;
  List<({int page, List<RawRange> ranges})> _matches = const [];
  int _match = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final document = await PdfDocument.openData(widget.data, sourceName: widget.placeKey);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() {
        _document = document;
        // Both views and the speech share one document: the app opens it and closes it.
        _documentRef = PdfDocumentRefDirect(document, autoDispose: false);
        _text = DocumentText(document);
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open ${widget.name}: $error');
      return;
    }
    final saved = _saved;
    final sentence = saved?.sentence;
    if (sentence != null) _resume = _lastSentence = (page: sentence.page, index: sentence.index);
    unawaited(_loadNotes());
    final prepared = widget.prepared;
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

  Future<void> _loadNotes() async {
    final loaded = await widget.notesStore?.load(_docId);
    if (loaded == null || !mounted) return;
    setState(() => _notes = loaded);
    await _place(loaded.annotations);
  }

  /// Places marks on this device's raw strings, by their text where the offsets no longer fit.
  Future<void> _place(List<Annotation> marks) async {
    final text = _text;
    if (text == null || marks.isEmpty) return;
    final raw = <int, String>{};
    for (final page in {for (final m in marks) m.page}) {
      if (page >= 1 && page <= text.pageCount) raw[page] = (await text.page(page)).text.raw;
    }
    if (!mounted) return;
    final anchored = anchorMarks(marks, raw);
    setState(() => _markAt = {..._markAt, for (final a in anchored.values) a.id: (a.start, a.end)});
  }

  void _notesChanged(NotesFile notes) {
    setState(() => _notes = notes);
    _notesDirty = true;
    _notesTimer?.cancel();
    _notesTimer = Timer(_notesDelay, () => unawaited(_flushNotes()));
  }

  Future<void> _flushNotes() async {
    _notesTimer?.cancel();
    if (!_notesDirty) return;
    _notesDirty = false;
    await widget.notesStore?.save(_docId, _notes);
  }

  /// Makes a mark for each page the selection reaches.
  Future<void> _addMarks(List<PageSelection> selection, MarkKind kind, HighlightColor color) async {
    final text = _text;
    if (text == null) return;
    final made = <Annotation>[];
    for (final (:page, :range) in selection) {
      final loaded = await text.page(page);
      final mark = newMark(
        page: page,
        start: range.$1,
        end: range.$2,
        raw: loaded.text.raw,
        blocks: loaded.blocks,
        kind: kind,
        color: color,
        id: newId(),
        created: isoNow(),
      );
      if (mark != null) made.add(mark);
    }
    if (made.isEmpty || !mounted) return;
    setState(() => _markAt = {..._markAt, for (final m in made) m.id: (m.start, m.end)});
    _notesChanged(NotesFile(notes: _notes.notes, annotations: [..._notes.annotations, ...made]));
  }

  Widget _selectionMenu(
    BuildContext context,
    Offset anchorA,
    Offset? anchorB,
    Future<List<PageSelection>> Function() selection,
    Future<void> Function() done,
  ) => MarkMenu(
    anchorA: anchorA,
    anchorB: anchorB,
    initialKind: _lastKind,
    onKindChanged: (kind) => _lastKind = kind,
    onMark: (kind, color) async {
      final selected = await selection();
      await done();
      await _addMarks(selected, kind, color);
    },
  );

  late final _actions = NotesActions(
    onNotes: (text) => _notesChanged(NotesFile(notes: text, annotations: _notes.annotations)),
    onComment: (id, comment) => _notesChanged(
      NotesFile(
        notes: _notes.notes,
        annotations: [for (final a in _notes.annotations) a.id == id ? a.copyWith(comment: comment) : a],
      ),
    ),
    onDelete: (id) {
      setState(() => _markAt = {..._markAt}..remove(id));
      _notesChanged(
        NotesFile(notes: _notes.notes, annotations: _notes.annotations.where((a) => a.id != id).toList()),
      );
    },
    onJump: (mark) {
      Navigator.of(context).pop();
      final at = _markAt[mark.id];
      if (at == null) return;
      _lastTouch = DateTime.now();
      unawaited(_view.reveal(mark.page, [at]));
    },
  );

  Future<void> _openNotes() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => NotesSheet(
      notes: _notes.notes,
      marks: _notes.annotations,
      found: _markAt.keys.toSet(),
      actions: _actions,
    ),
  );

  /// A tap on a mark opens its comment.
  Future<void> _openMark(String id) async {
    final mark = _notes.annotations.where((a) => a.id == id).firstOrNull;
    if (mark == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: MarkCard(
          mark: mark,
          found: true,
          actions: _actions,
          onDeleted: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// The pages are laid out: show the saved place, then start remembering where the user goes.
  void _pagesReady() {
    // A move during the viewer's first layout is undone by it, so the offset follows a moment later.
    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _placed = true;
      _pdf.viewer.addListener(_moved);
      final saved = _saved;
      if (saved != null && !reading) unawaited(_pdf.showPage(saved.page, saved.offset, zoom: saved.zoom));
    });
  }

  void _moved() {
    _placeTimer?.cancel();
    _placeTimer = Timer(_placeDelay, _savePlace);
  }

  void _touched() {
    _lastTouch = DateTime.now();
    _moved();
  }

  /// Remembers where the user is, and for a prepared document writes this phone's state (step 5.6).
  Future<void> _savePlace() async {
    final places = widget.places;
    if (places == null || !_placed || _closing || !_view.isReady) return;
    final anchor = _view.scrollAnchor();
    if (anchor == null) return;
    final last = _lastSentence;
    String? key;
    if (last != null && widget.prepared != null) {
      final sentences = (await _plan(last.page)).sentences;
      if (last.index < sentences.length) key = sentences[last.index].key;
    }
    places.remember(
      widget.placeKey,
      Progress(
        view: reading ? 'reading' : 'pdf',
        zoom: _pdf.isReady ? (_pdf.zoom * 1000).round() / 1000 : _saved?.zoom,
        page: anchor.page,
        offset: anchor.offset,
        sentence: last,
      ),
      prepared: widget.prepared,
      sentenceKey: key,
    );
  }

  /// Switches between the pages and the reading view, at the same page and with the voice going on.
  void _switchView() {
    final page = sentence?.page ?? _view.currentPage ?? 1;
    setState(() => reading = !reading);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _view.showPage(page, 0);
      _revealSpoken(force: true);
      if (reading) _placed = true;
      unawaited(_savePlace());
    });
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
    await _view.showPage(offer.page, offer.offset);
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
    widget.playback?.show(state, widget.name, this.sentence?.page ?? _view.currentPage ?? 1);
    if (changedSentence) {
      _resume = null;
      final at = _reader?.cursor;
      if (at != null) {
        _lastSentence = at;
        unawaited(_savePlace());
      }
    }
    _revealSpoken();
  }

  @override
  void onError(Object error) {
    if (mounted && !_closing) setState(() => _error = '$error');
  }

  /// Keeps the spoken word in view, unless the user has just moved the view somewhere else.
  void _revealSpoken({bool force = false}) {
    final sentence = this.sentence;
    if (sentence == null || (!force && DateTime.now().difference(_lastTouch) < _followPause)) return;
    final ranges = word >= 0 && word < sentence.words.length ? sentence.words[word].ranges : sentence.ranges;
    // After the frame, so the reading view has laid out the new highlight's paragraph.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_view.reveal(sentence.page, ranges)));
  }

  /// What both views paint: the spoken sentence and word, and the search matches.
  List<Highlight> get _highlights {
    final sentence = this.sentence;
    return [
      // The marks first, so the voice and search lie over them.
      for (final a in _notes.annotations)
        if (_markAt[a.id] case final at?) Highlight.mark(a.page, [at], a.kind, a.color, a.id),
      if (sentence != null) Highlight(sentence.page, sentence.ranges, HighlightKind.sentence),
      for (var i = 0; i < _matches.length; i++)
        Highlight(
          _matches[i].page,
          _matches[i].ranges,
          i == _match ? HighlightKind.searchCurrent : HighlightKind.search,
        ),
      if (sentence != null && word >= 0 && word < sentence.words.length)
        Highlight(sentence.page, sentence.words[word].ranges, HighlightKind.word),
    ];
  }

  /// The page the view shows, for the integration test.
  int? get currentPage => _view.currentPage;

  /// The marks as written, for the integration test.
  List<Annotation> get marks => _notes.annotations;

  /// The general notes as written, for the integration test.
  String get generalNotes => _notes.notes;

  /// The document's sentences of a page, for tests that need words to press on.
  @visibleForTesting
  Future<List<Utterance>> utterancesOf(int page) => _text!.utterances(page);

  /// Where raw ranges are on the screen in the view that shows, for tests that press on a word.
  @visibleForTesting
  Offset? globalCenterOf(int page, List<RawRange> ranges) =>
      reading ? _readingView.globalCenterOf(page, ranges) : _pdf.globalCenterOf(page, ranges);

  /// Makes a mark as the menu does, for tests that need many.
  @visibleForTesting
  Future<void> addMarkFor(int page, RawRange range, MarkKind kind, HighlightColor color) =>
      _addMarks([(page: page, range: range)], kind, color);

  void _toggle() => _reader?.toggle(_resume ?? (page: _view.currentPage ?? 1, index: 0));

  void _searchChanged(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDelay, () => unawaited(_search(query)));
  }

  /// Finds the phrase on every page, in order, and shows the first match from the current page on.
  Future<void> _search(String query) async {
    final text = _text;
    if (text == null) return;
    final matches = <({int page, List<RawRange> ranges})>[];
    for (var page = 1; page <= text.pageCount; page++) {
      for (final ranges in findInBlocks((await text.page(page)).blocks, query)) {
        matches.add((page: page, ranges: ranges));
      }
    }
    if (!mounted || _searchBox.text != query) return;
    final here = _view.currentPage ?? 1;
    final first = matches.indexWhere((m) => m.page >= here);
    setState(() {
      _matches = matches;
      _match = first < 0 ? 0 : first;
    });
    _showMatch();
  }

  void _step(int direction) {
    if (_matches.isEmpty) return;
    setState(() => _match = (_match + direction) % _matches.length);
    _showMatch();
  }

  void _showMatch() {
    if (_matches.isEmpty) return;
    final match = _matches[_match];
    _lastTouch = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_view.reveal(match.page, match.ranges)));
  }

  void _closeSearch() {
    _searchTimer?.cancel();
    _searchBox.clear();
    setState(() {
      _searching = false;
      _matches = const [];
    });
  }

  Future<void> _openReadingSettings() => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ReadingSettingsSheet(
      settings: _readingSettings,
      onChanged: (settings) {
        setState(() => _readingSettings = settings);
        widget.places?.reading = settings;
      },
    ),
  );

  @override
  void dispose() {
    _placeTimer?.cancel();
    _searchTimer?.cancel();
    unawaited(_flushNotes());
    _pdf.viewer.removeListener(_moved);
    if (_placed) unawaited(_savePlace().then((_) => widget.places?.flush()));
    _closing = true;
    final playback = widget.playback;
    if (playback != null) {
      playback.onPlay = playback.onPause = playback.onStop = null;
      playback.onSkip = null;
      playback.show(ReaderState.idle, widget.name, 1);
    }
    unawaited(_reader?.dispose());
    _searchBox.dispose();
    unawaited(_document?.dispose());
    super.dispose();
  }

  String? get _status {
    if (_error != null) return _error;
    if (widget.prepared == null) return 'Not prepared on the desktop';
    final skipped = _skipped ?? 0;
    if (skipped > 0) return '$skipped sentences have no audio and are skipped';
    return null;
  }

  PreferredSizeWidget _appBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Close search', onPressed: _closeSearch),
        title: TextField(
          key: const Key('search'),
          controller: _searchBox,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search', border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onChanged: _searchChanged,
          onSubmitted: (_) => _step(1),
        ),
        actions: [
          Center(
            child: Text(
              _searchBox.text.trim().isEmpty
                  ? ''
                  : _matches.isEmpty
                  ? 'No results'
                  : '${_match + 1} / ${_matches.length}',
              key: const Key('search-count'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: 'Previous match',
            onPressed: () => _step(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Next match',
            onPressed: () => _step(1),
          ),
        ],
      );
    }
    return AppBar(
      title: Text(widget.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: _text == null ? null : () => setState(() => _searching = true),
        ),
        IconButton(
          key: const Key('notes'),
          icon: const Icon(Icons.sticky_note_2_outlined),
          tooltip: 'Notes and marks',
          onPressed: _text == null ? null : _openNotes,
        ),
        if (reading)
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'Text settings',
            onPressed: _openReadingSettings,
          ),
        IconButton(
          key: const Key('toggle-reading'),
          icon: Icon(reading ? Icons.picture_as_pdf : Icons.article),
          tooltip: reading ? 'Show the pages' : 'Reading view',
          onPressed: _text == null ? null : _switchView,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reader = _reader;
    final status = _status;
    final documentRef = _documentRef;
    final text = _text;
    final highlights = _highlights;
    return Scaffold(
      appBar: _appBar(),
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
            child: documentRef == null || text == null
                ? const Center(child: CircularProgressIndicator())
                // The pages stay built behind the reading view, so switching back keeps their place.
                : Stack(
                    children: [
                      Offstage(
                        offstage: reading,
                        child: PdfPagesView(
                          document: documentRef,
                          text: text,
                          controller: _pdf,
                          highlights: reading ? const [] : highlights,
                          initialPage: _saved?.page ?? 1,
                          onReady: _pagesReady,
                          onTouched: _touched,
                          buildSelectionMenu: widget.notesStore == null ? null : _selectionMenu,
                          onMarkTapped: _openMark,
                        ),
                      ),
                      if (reading)
                        ReadingView(
                          text: text,
                          settings: _readingSettings,
                          controller: _readingView,
                          highlights: highlights,
                          onTouched: _touched,
                          buildSelectionMenu: widget.notesStore == null ? null : _selectionMenu,
                          onMarkTapped: _openMark,
                        ),
                    ],
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
