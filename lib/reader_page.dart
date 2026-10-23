import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'annotated_pdf.dart';
import 'dictation.dart';
import 'document_access.dart';
import 'document_text.dart';
import 'favourites_store.dart';
import 'library.dart';
import 'notes_store.dart';
import 'now_playing.dart';
import 'places.dart';
import 'phone_voice.dart';
import 'playback.dart';
import 'reader.dart';
import 'shared/layout.dart' show readableText;
import 'shared/mark_export.dart';
import 'shared/marks.dart';
import 'shared/notes.dart';
import 'shared/notes_merge.dart';
import 'shared/pdfium_text.dart' show rangeBoxes;
import 'shared/player_preview.dart';
import 'shared/read_plan.dart';
import 'shared/search.dart';
import 'shared/settings.dart';
import 'shared/sync.dart';
import 'shared/types.dart';
import 'views/mark_menu.dart';
import 'views/notes_sheet.dart';
import 'views/pdf_pages_view.dart';
import 'views/quick_comment.dart';
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

/// The play bar hidden behind its notch for more page, kept across documents while the app runs.
bool _barHidden = false;

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
    this.phoneVoice,
    this.phoneLangs = const {},
    this.playback,
    this.places,
    this.notesStore,
    this.documents,
    this.session,
    this.dictation,
    this.favourites,
    this.onOpenPlayer,
    this.onCollapse,
    this.startInReading = false,
  });

  final String name;
  final Uint8List data;

  /// Names the document in the saved places: its URI, or its id when it came from the library.
  final String placeKey;

  /// Null in widget tests: nothing is remembered.
  final Places? places;

  /// Null in widget tests: nothing is marked.
  final NotesStore? notesStore;

  /// The system's "save as", for the Markdown export and "Save PDF"; null in widget tests.
  final DocumentAccess? documents;

  /// Null when the desktop has not prepared this PDF: it is then read by the phone's own voice, if
  /// it has one, else it only shows.
  final LibraryDocument? prepared;

  /// The phone's own voice and the languages it speaks (ADR 5); null and empty in widget tests.
  final PhoneVoice? phoneVoice;
  final Set<Lang> phoneLangs;
  final ReadingHandler? playback;

  /// The app's reading session, which the Now Playing bar controls while the reader is hidden.
  final ReadingSession? session;

  /// The offline speech recogniser for spoken comments (ADR 6); null where there is none.
  final Dictation? dictation;

  /// For the heart on the bar; null in widget tests.
  final FavouritesStore? favourites;

  /// A tap on the bar opens the full-screen player (PLAN 11).
  final VoidCallback? onOpenPlayer;

  /// Back hides the reader and the voice goes on (PLAN 9.4); null where the reader is a route of its own.
  final VoidCallback? onCollapse;

  /// Opens in the reading view whatever the saved place says: for a PDF another app handed over.
  final bool startInReading;

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage> implements ReaderHost {
  PdfDocument? _document;
  PdfDocumentRef? _documentRef;
  DocumentText? _text;
  Reader? _reader;
  final _plans = <int, Future<PagePlan>>{};

  /// Each page's plan once it is made, for counting what the voice passed over.
  final _planned = <int, PagePlan>{};

  /// The app's session, or one of the reader's own where it runs alone (tests).
  late final ReadingSession _session =
      widget.session ??
      ReadingSession(
        name: widget.name,
        data: widget.data,
        placeKey: widget.placeKey,
        prepared: widget.prepared,
        phoneLangs: widget.phoneLangs,
        canDictate: widget.dictation != null,
      );

  final _pdf = PdfPagesController();
  final _readingView = ReadingController();

  /// True while the reading view is shown instead of the pages.
  late bool reading = widget.startInReading || _saved?.view == 'reading';

  /// Whether there is anything to play; without audio the player is not shown at all.
  bool get _hasAudio =>
      widget.phoneLangs.isNotEmpty ||
      (widget.prepared != null && widget.prepared!.manifest.voiced.isNotEmpty);
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
    if (prepared == null && widget.phoneLangs.isEmpty) return;
    if (prepared != null) unawaited(_findOffer(prepared));
    final reader = Reader(this, LibraryAudio(document: prepared, voice: widget.phoneVoice))
      ..speed = _speed
      ..stopAtReferences = widget.places?.stopAtReferences ?? false;
    setState(() => _reader = reader);
    _session
      ..toggle = _toggle
      ..skip = ((direction) => unawaited(reader.skip(direction)))
      ..setSpeed = _changeSpeed
      ..comment = _commentOnSentence
      ..speed = _speed;
    _session.update(state);
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
    // Stamped here, by comparing with what was before, as the desktop does on save (ADR 7 section 1).
    final stamped = stampChanges(_notes, notes, DateTime.now().millisecondsSinceEpoch);
    setState(() => _notes = stamped);
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
  Future<void> _addMarks(
    List<PageSelection> selection,
    MarkKind kind,
    HighlightColor color, {
    String comment = '',
  }) async {
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
      if (mark != null) made.add(comment.isEmpty ? mark : mark.copyWith(comment: comment));
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
    onSpeak: !_session.canDictate
        ? null
        : () async {
            final selected = await selection();
            await done();
            await _commentOnSelection(selected, speak: true);
          },
    onReadFrom: _reader == null || !_hasAudio
        ? null
        : () async {
            final selected = await selection();
            await done();
            if (selected.isNotEmpty) await _readFrom(selected.first.page, selected.first.range.$1);
          },
  );

  /// Reads from the sentence the selection starts in, or the next page's first (as the desktop does).
  Future<void> _readFrom(int page, int offset) async {
    final sentences = (await _plan(page)).sentences;
    final index = readFromIndex([for (final s in sentences) s.ranges], offset);
    _lastTouch = DateTime(0);
    _reader?.startAt(index < 0 ? (page: page + 1, index: 0) : (page: page, index: index));
  }

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

  /// The document says once how many of its sentences have no audio (ADR 2 section 1), and how many
  /// of a fully prepared document the phone's own voice reads (ADR 5).
  Future<void> _countSkipped() async {
    var skipped = 0, byPhone = 0;
    for (var page = 1; page <= pageCount; page++) {
      final plan = await _plan(page);
      skipped += plan.skipped;
      byPhone += plan.sentences.where((s) => s.source == SpeechSource.phone).length;
    }
    // Pages the computer has not voiced yet are not counted: the phone's voice reads them.
    final m = widget.prepared?.manifest;
    if (m != null && m.voiced.length < m.pages) return;
    if (skipped > 0) {
      _toast('$skipped sentences have no audio and are skipped');
    } else if (byPhone > 0 && m != null) {
      _toast(
        byPhone == 1
            ? 'One sentence is read by this phone’s voice'
            : '$byPhone sentences are read by this phone’s voice',
      );
    }
  }

  Future<PagePlan> _plan(int page) => _plans[page] ??= () async {
    final utterances = await _text!.utterances(page);
    final index = await widget.prepared?.index(page);
    return _planned[page] = planPage(utterances, index, phoneLangs: widget.phoneLangs);
  }();

  /// A short note above the reader's buttons, only while the reader shows: hidden behind the tabs,
  /// it would cover the Now Playing bar.
  void _toast(String message) {
    if (!mounted || !TickerMode.valuesOf(context).enabled) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          margin: EdgeInsets.fromLTRB(16, 0, 16, _barHidden ? 32 : 112),
        ),
      );
  }

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
    _session.update(state, sentence: this.sentence, word: this.word);
    if (changedSentence) {
      unawaited(_showNeighbours());
      _resume = null;
      final at = _reader?.cursor;
      if (at != null) {
        final from = _lastSentence;
        final skipped = from == null ? 0 : skippedBetween(from, at, (page) => _planned[page]);
        if (skipped > 0) {
          _toast(
            skipped == 1 ? 'Skipped a sentence without audio' : 'Skipped $skipped sentences without audio',
          );
        }
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
    final current = word >= 0 && word < sentence.words.length ? sentence.words[word] : null;
    final ranges = current?.ranges ?? sentence.ranges;
    // A word of the sentence's continuation is on the next page (desktop ADR 12).
    final page = current?.page ?? sentence.page;
    // After the frame, so the reading view has laid out the new highlight's paragraph.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_view.reveal(page, ranges)));
  }

  /// What both views paint: the spoken sentence and word, and the search matches.
  List<Highlight> get _highlights {
    final sentence = this.sentence;
    return [
      // The marks first, so the voice and search lie over them.
      for (final a in _notes.annotations)
        if (_markAt[a.id] case final at?) Highlight.mark(a.page, [at], a.kind, a.color, a.id),
      if (sentence != null) Highlight(sentence.page, sentence.ranges, HighlightKind.sentence),
      // A sentence over a page break is tinted on both pages (desktop ADR 12).
      if (sentence?.next case final next?) Highlight(next.page, next.ranges, HighlightKind.sentence),
      for (var i = 0; i < _matches.length; i++)
        Highlight(
          _matches[i].page,
          _matches[i].ranges,
          i == _match ? HighlightKind.searchCurrent : HighlightKind.search,
        ),
      if (sentence != null && word >= 0 && word < sentence.words.length)
        Highlight(
          sentence.words[word].page ?? sentence.page,
          sentence.words[word].ranges,
          HighlightKind.word,
        ),
    ];
  }

  /// The page the view shows, for the integration test.
  int? get currentPage => _view.currentPage;

  /// The session the bar and the full-screen player control, for the integration test.
  @visibleForTesting
  ReadingSession get session => _session;

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

  /// Changes a mark's comment as the card does, for tests.
  @visibleForTesting
  void setCommentFor(String id, String comment) => _actions.onComment(id, comment);

  /// Deletes a mark as the card does, for tests.
  @visibleForTesting
  void deleteMarkFor(String id) => _actions.onDelete(id);

  /// Makes a mark as the menu does, for tests that need many.
  @visibleForTesting
  Future<void> addMarkFor(int page, RawRange range, MarkKind kind, HighlightColor color) =>
      _addMarks([(page: page, range: range)], kind, color);

  void _toggle() => _reader?.toggle(_resume ?? (page: _view.currentPage ?? 1, index: 0));

  void _changeSpeed(double value) {
    setState(() {
      _speed = value;
      _reader?.speed = value;
      widget.places?.speed = value;
    });
    _session.updateSpeed(value);
  }

  /// Shows the sentences either side of the one being read in the full-screen player.
  Future<void> _showNeighbours() async {
    final at = _reader?.cursor;
    if (at == null) return;
    final previous = await _neighbour(at, -1);
    final next = await _neighbour(at, 1);
    if (mounted && !_closing && _reader?.cursor == at) _session.updateNeighbours(previous, next);
  }

  /// The text of the sentence `direction` away, across pages that have none.
  Future<String?> _neighbour(Cursor at, int direction) async {
    var page = at.page;
    var index = at.index + direction;
    while (page >= 1 && page <= pageCount) {
      final sentences = (await _plan(page)).sentences;
      if (index >= 0 && index < sentences.length) return sentenceText(sentences[index]);
      page += direction;
      if (page < 1 || page > pageCount) return null;
      final count = (await _plan(page)).sentences.length;
      index = direction > 0 ? 0 : count - 1;
    }
    return null;
  }

  /// Pauses the voice for a comment and goes on afterwards, if it was reading.
  Future<T> _whilePaused<T>(Future<T> Function() ask) async {
    final wasPlaying = state == ReaderState.playing;
    if (wasPlaying) _toggle();
    try {
      return await ask();
    } finally {
      if (wasPlaying && mounted && state == ReaderState.paused) _toggle();
    }
  }

  Future<String?> _askComment(String quote, {required bool speak}) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => QuickCommentSheet(
      quote: quote,
      dictation: _session.canDictate ? widget.dictation : null,
      listenAtOnce: speak && _session.canDictate,
    ),
  );

  /// The player's Comment and Speak buttons: pause, ask for a comment on the sentence being read, and
  /// mark the sentence with it, without touching the text (PLAN 11).
  Future<void> _commentOnSentence({required bool speak}) async {
    final spoken = sentence;
    if (spoken == null || spoken.ranges.isEmpty) return;
    final range = (spoken.ranges.first.$1, spoken.ranges.last.$2);
    final comment = await _whilePaused(() => _askComment(sentenceText(spoken), speak: speak));
    if (comment == null || comment.isEmpty || !mounted) return;
    await _addMarks(
      [(page: spoken.page, range: range)],
      MarkKind.highlight,
      HighlightColor.yellow,
      comment: comment,
    );
  }

  /// A comment spoken for the text the user selected (the mark menu's microphone).
  Future<void> _commentOnSelection(List<PageSelection> selected, {required bool speak}) async {
    final text = _text;
    if (text == null || selected.isEmpty) return;
    final first = selected.first;
    final page = await text.page(first.page);
    final quote = readableText(page.blocks, first.range.$1, first.range.$2);
    final comment = await _whilePaused(() => _askComment(quote, speak: speak));
    if (comment == null || comment.isEmpty || !mounted) return;
    await _addMarks(selected, _lastKind, HighlightColor.yellow, comment: comment);
  }

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
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (context, setSheet) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReadingSettingsSheet(
              settings: _readingSettings,
              onChanged: (settings) {
                setState(() => _readingSettings = settings);
                widget.places?.reading = settings;
              },
            ),
            SwitchListTile(
              key: const Key('stop-at-references'),
              title: const Text('Stop reading at the reference list'),
              subtitle: const Text('“References”, “Literatur”'),
              value: widget.places?.stopAtReferences ?? false,
              onChanged: widget.places == null
                  ? null
                  : (on) => setSheet(() {
                      widget.places!.stopAtReferences = on;
                      _reader?.stopAtReferences = on;
                    }),
            ),
          ],
        ),
      ),
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

  /// Only a problem is shown above the bar; where the audio comes from is the player's business.
  String? get _status => _error;

  PreferredSizeWidget _appBar() {
    final (:bar, :onBar) = _barColors;
    if (_searching) {
      return AppBar(
        backgroundColor: bar,
        foregroundColor: onBar,
        scrolledUnderElevation: 0,
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
      backgroundColor: bar,
      foregroundColor: onBar,
      scrolledUnderElevation: 0,
      leading: widget.onCollapse == null ? null : BackButton(onPressed: widget.onCollapse),
      title: Text(widget.name, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          key: const Key('notes'),
          icon: const Icon(Icons.sticky_note_2_outlined),
          tooltip: 'Notes and marks',
          onPressed: _text == null ? null : _openNotes,
        ),
        IconButton(
          key: const Key('toggle-reading'),
          icon: Icon(reading ? Icons.picture_as_pdf : Icons.article),
          tooltip: reading ? 'Show the pages' : 'Reading view',
          onPressed: _text == null ? null : _switchView,
        ),
        PopupMenuButton<String>(
          key: const Key('reader-menu'),
          enabled: _text != null,
          onSelected: (choice) => switch (choice) {
            'search' => setState(() => _searching = true),
            'text' => unawaited(_openReadingSettings()),
            'markdown' => unawaited(_exportMarkdown()),
            _ => unawaited(_savePdf()),
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'search',
              child: ListTile(leading: Icon(Icons.search), title: Text('Search')),
            ),
            if (reading)
              const PopupMenuItem(
                value: 'text',
                child: ListTile(leading: Icon(Icons.format_size), title: Text('Text settings')),
              ),
            if (widget.documents != null) ...[
              const PopupMenuItem(
                value: 'markdown',
                child: ListTile(leading: Icon(Icons.notes), title: Text('Export notes as Markdown')),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: ListTile(leading: Icon(Icons.save_alt), title: Text('Save PDF with marks')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The bars take their colour from what lies behind them, a step towards its text, so they belong
  /// to the page without vanishing in it.
  ({Color bar, Color onBar}) get _barColors {
    if (!reading) {
      final backdrop = pagesBackdrop(Theme.of(context).brightness);
      return Theme.of(context).brightness == Brightness.dark
          ? (bar: Color.lerp(backdrop, Colors.white, 0.18)!, onBar: const Color(0xFFE2E2E2))
          : (bar: Color.lerp(backdrop, Colors.white, 0.6)!, onBar: const Color(0xFF1F1F1F));
    }
    final (background, foreground) =
        readingThemeColors[_readingSettings.theme] ?? readingThemeColors['sepia']!;
    return (bar: Color.lerp(background, foreground, 0.14)!, onBar: foreground);
  }

  /// The top bar, hidden by a tap on the page as in a photo gallery; search keeps it.
  bool _topHidden = false;

  void _toggleTop() {
    if (!_searching) setState(() => _topHidden = !_topHidden);
  }

  /// The file's name without `.pdf`, for the names the exports propose.
  String get _baseName => widget.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');

  void _tell(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The marks and comments as Markdown, as the desktop exports them (PLAN 4.2).
  Future<void> _exportMarkdown() async {
    try {
      final markdown = toMarkdown(widget.name, _notes);
      final saved = await widget.documents!.saveAs(
        '$_baseName.notes.md',
        'text/markdown',
        Uint8List.fromList(utf8.encode(markdown)),
      );
      if (saved) _tell('Notes exported.');
    } catch (error) {
      _tell('Could not export: $error');
    }
  }

  /// A copy of the PDF with every mark and its comment as an annotation, and the notes as a sticky
  /// note on page one (PLAN 4.4). The PDF itself is never changed.
  Future<void> _savePdf() async {
    final text = _text;
    if (text == null) return;
    try {
      final marks = <ExportMark>[];
      var unplaced = 0;
      for (final a in _notes.annotations) {
        final at = _markAt[a.id];
        if (at == null) {
          unplaced++;
          continue;
        }
        final page = await text.page(a.page);
        final boxes = rangeBoxes(
          [at],
          page.text.charIndex,
          [for (final r in page.charRects) (left: r.left, bottom: r.bottom, right: r.right, top: r.top)],
        );
        marks.add(ExportMark(page: a.page, kind: a.kind, color: a.color, comment: a.comment, boxes: boxes));
      }
      final pdf = await annotatedPdf(widget.data, marks, _notes.notes);
      final saved = await widget.documents!.saveAs('$_baseName.annotated.pdf', 'application/pdf', pdf);
      if (saved) {
        _tell(
          unplaced == 0
              ? 'PDF saved with ${marks.length} marks.'
              : 'PDF saved; $unplaced marks could not be placed.',
        );
      }
    } catch (error) {
      _tell('Could not save the PDF: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final documentRef = _documentRef;
    final text = _text;
    final highlights = _highlights;
    final topHidden = _topHidden && !_searching;
    return Scaffold(
      backgroundColor: reading
          ? (readingThemeColors[_readingSettings.theme] ?? readingThemeColors['sepia']!).$1
          : pagesBackdrop(Theme.of(context).brightness),
      appBar: topHidden ? null : _appBar(),
      body: SafeArea(
        top: topHidden,
        bottom: false,
        child: Column(
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
              child: Stack(
                children: [
                  Positioned.fill(
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
                                  onTapped: _toggleTop,
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
                                  onTapped: _toggleTop,
                                ),
                            ],
                          ),
                  ),
                  // Over the page, which runs on behind the bar (PLAN 9.8). The same bar as in the menu
                  // (PLAN 11); a tap on it opens the full-screen player.
                  if (_hasAudio)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: _barNotch(
                                Theme.of(context).colorScheme.surfaceContainerHigh,
                                Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (status != null && !_barHidden) _statusLine(status),
                            if (!_barHidden)
                              NowPlayingBar(
                                session: _session,
                                favourites: widget.favourites,
                                playKey: const Key('play'),
                                barKey: const Key('reader-bar'),
                                onOpen: widget.onOpenPlayer ?? () {},
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A problem with the audio, above the bar.
  Widget _statusLine(String status) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(status, key: const Key('status'), style: Theme.of(context).textTheme.bodySmall),
      ),
    ),
  );

  /// A small tab above the play bar's right end that hides the bar and brings it back.
  Widget _barNotch(Color bar, Color onBar) => Material(
    color: bar,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    child: InkWell(
      key: const Key('toggle-bar'),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      onTap: () => setState(() => _barHidden = !_barHidden),
      child: Tooltip(
        message: _barHidden ? 'Show the play bar' : 'Hide the play bar',
        child: SizedBox(
          width: 44,
          height: 24,
          child: Icon(
            _barHidden ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 22,
            color: onBar,
          ),
        ),
      ),
    ),
  );
}
