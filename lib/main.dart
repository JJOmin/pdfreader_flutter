import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:path_provider/path_provider.dart';

import 'app_settings_store.dart';
import 'app_theme.dart';
import 'desktop_link.dart';
import 'dictation.dart';
import 'document_access.dart';
import 'favourites_store.dart';
import 'favourites_tab.dart';
import 'library.dart';
import 'library_list.dart';
import 'now_playing.dart';
import 'shared/home_lists.dart';
import 'shared/inbox.dart' show PendingOffer;
import 'shared/library_view.dart';
import 'notes_store.dart';
import 'places.dart';
import 'platform_secrets.dart';
import 'phone_voice.dart';
import 'player_screen.dart';
import 'playback.dart';
import 'reader_page.dart';
import 'store/cloud_accounts.dart';
import 'shared/sync.dart' show Manifest;
import 'shared/types.dart' show Lang;
import 'shared/sync_state.dart';
import 'store/cloud_catalog.dart';
import 'store/memo_file.dart';
import 'store/offer_file.dart';
import 'sync_controller.dart';
import 'settings_tab.dart';
import 'wifi_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The speech side reads page text through the engine before any viewer exists.
  await pdfrxFlutterInitialize();
  final playback = await initPlayback();
  final store = await DesktopStore.open();
  final places = await Places.open((device: store.device, name: await phoneName()));
  final library = await Library.open();
  final notesStore = await NotesStore.open();
  final support = (await getApplicationSupportDirectory()).path;
  final cloud = CloudAccounts(
    file: File('$support/cloud.json'),
    box: KeystoreSecretBox(),
    browser: SystemBrowser(),
  );
  final sync = SyncController(
    accounts: cloud,
    library: library,
    notes: notesStore,
    device: store.device,
    memoFile: MemoFile(File('$support/sync-memo.json')),
    catalogFile: CloudCatalog(File('$support/cloud-catalog.json')),
  );
  await sync.loadCatalog();
  // One store of paired computers: a pairing on the Sync screen is seen by the Wi-Fi sync at once.
  sync.desktopStore = store;
  sync.wifi = WifiSync(
    desktops: () => store.desktops,
    timers: const RealTimers(),
    discover: discoverDesktops,
    changes: changesFrom,
    sync: (desktop) => sync.exclusive(() async {
      final result = await syncFrom(
        desktop,
        library,
        store.device,
        (_) {},
        notes: notesStore,
        onlyHeld: true,
      );
      // Heard at another address than the one it was paired at: remember where it is now.
      if (store.desktops.every((d) => d.host != desktop.host || d.port != desktop.port)) {
        await store.remember(desktop);
      }
      return result;
    }),
    onSynced: (_, result) => sync.wifiSynced(result),
    inbox: inboxFrom,
    onOffers: sync.wifiOffers,
  );
  sync.offerFile = OfferFile(File('$support/offers.json'));
  await sync.offerFile.load();
  final favourites = await FavouritesStore.load(File('$support/favourites.json'));
  final appSettings = await AppSettingsStore.load(File('$support/app-settings.json'));
  // What the user changes is sent soon; what a sync brings in is not sent back.
  notesStore.onSaved = sync.ownChanged;
  places.onStateWritten = () => sync.ownChanged(place: true);
  runApp(
    PdfReaderApp(
      library: library,
      playback: playback,
      phoneVoice: PlatformPhoneVoice(),
      dictation: PlatformDictation(),
      places: places,
      notesStore: notesStore,
      cloud: cloud,
      sync: sync,
      favourites: favourites,
      appSettings: appSettings,
    ),
  );
}

class PdfReaderApp extends StatefulWidget {
  const PdfReaderApp({
    super.key,
    this.documents,
    this.library,
    this.playback,
    this.phoneVoice,
    this.dictation,
    this.places,
    this.notesStore,
    this.cloud,
    this.sync,
    this.favourites,
    this.appSettings,
  });

  /// Replaced in widget tests, which have no platform side.
  final DocumentAccess? documents;
  final Library? library;
  final ReadingHandler? playback;

  /// The phone's own voice, for what the desktop did not prepare (ADR 5); null in widget tests.
  final PhoneVoice? phoneVoice;

  /// The offline speech recogniser for spoken comments (ADR 6); null in widget tests.
  final Dictation? dictation;
  final Places? places;
  final NotesStore? notesStore;
  final CloudAccounts? cloud;
  final SyncController? sync;
  final FavouritesStore? favourites;
  final AppSettingsStore? appSettings;

  @override
  State<PdfReaderApp> createState() => _PdfReaderAppState();
}

class _PdfReaderAppState extends State<PdfReaderApp> {
  late final AppSettingsStore _appSettings = widget.appSettings ?? AppSettingsStore.inMemory();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _appSettings,
    builder: (context, look, _) {
      // The colours, the font and the text size of the whole app (PLAN M15).
      final themes = appThemes(look);
      return MaterialApp(
        title: 'PDF Reader',
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: themes.mode,
        builder: (context, child) => scaleText(context, look, child),
        home: HomePage(
          documents: widget.documents ?? DocumentAccess(),
          library: widget.library,
          playback: widget.playback,
          phoneVoice: widget.phoneVoice,
          dictation: widget.dictation,
          places: widget.places,
          notesStore: widget.notesStore,
          cloud: widget.cloud,
          sync: widget.sync,
          favourites: widget.favourites,
          appSettings: _appSettings,
        ),
      );
    },
  );
}

/// The app's frame (PLAN 9.2 to 9.4): the tabs Home, Favourites and Settings, the Now Playing bar
/// above them, and the open document's reader, which stays alive while it is hidden.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.documents,
    this.library,
    this.playback,
    this.phoneVoice,
    this.dictation,
    this.places,
    this.notesStore,
    this.cloud,
    this.sync,
    this.favourites,
    this.appSettings,
  });

  final DocumentAccess documents;
  final Library? library;
  final ReadingHandler? playback;
  final PhoneVoice? phoneVoice;
  final Dictation? dictation;
  final Places? places;
  final NotesStore? notesStore;
  final CloudAccounts? cloud;
  final SyncController? sync;
  final FavouritesStore? favourites;
  final AppSettingsStore? appSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late Future<List<LibraryDocument>> _prepared = widget.library?.documents() ?? Future.value(const []);

  var _syncsSeen = 0;

  /// 0 Home, 1 Favourites, 2 Settings.
  var _tab = 0;

  /// The open document, and whether its reader is shown or only the bar.
  ReadingSession? _session;
  var _expanded = false;

  late final FavouritesStore _favourites = widget.favourites ?? FavouritesStore.inMemory();

  /// The languages the phone's own voice speaks, asked once; a document opens after the answer.
  late final Future<Set<Lang>> _phoneLangs = widget.phoneVoice?.languages() ?? Future.value(const {});

  /// Whether spoken comments work on this phone, asked once like the voice.
  late final Future<bool> _canDictate = widget.dictation?.available() ?? Future.value(false);

  /// The full-screen player is up, over the menu or the reader (PLAN 11).
  var _playerOpen = false;

  /// What the list listens to where there is no sync (widget tests).
  static final _never = ChangeNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sync?.addListener(_onSync);
    widget.sync?.resume();
    // A PDF another app opened this one with: now if it started us, later if we were running.
    widget.documents.onIncoming = () => unawaited(_openIncoming());
    unawaited(_openIncoming());
  }

  @override
  void dispose() {
    widget.documents.onIncoming = null;
    widget.sync?.removeListener(_onSync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The app in front syncs now and every 30 seconds; in the background it does not.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sync?.resume();
    } else if (state == AppLifecycleState.paused) {
      unawaited(widget.sync?.pause());
    }
  }

  /// Offers already asked about in this run: one that is not answered stays in the list.
  final _asked = <String>{};
  var _asking = false;

  /// "Leos-MacBook sends paper.pdf (12 MB): Accept, Decline", with "Always accept from this computer".
  Future<void> _ask(PendingOffer p) async {
    final sync = widget.sync;
    if (sync == null || _asking) return;
    _asking = true;
    _asked.add(p.offer.key);
    var always = false;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${p.from} sends ${p.offer.name} (${formatBytes(p.offer.bytes)})'),
          content: CheckboxListTile(
            key: const Key('always-accept'),
            contentPadding: EdgeInsets.zero,
            value: always,
            onChanged: (value) => setState(() => always = value ?? false),
            title: const Text('Always accept from this computer'),
          ),
          actions: [
            TextButton(
              key: const Key('decline-offer'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              key: const Key('accept-offer'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
    _asking = false;
    try {
      // Closed without an answer: it stays offered in the list.
      if (accept == true) await sync.accept(p, always: always);
      if (accept == false) await sync.decline(p);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
    if (mounted) _reload();
  }

  /// A sync that brought something shows it in the list without a tap, and a new offer asks.
  void _onSync() {
    final sync = widget.sync!;
    final fresh = sync.offers.where(
      (p) => !_asked.contains(p.offer.key) && !sync.offerFile.alwaysFrom.contains(p.from),
    );
    if (fresh.isNotEmpty && mounted && !_expanded && (ModalRoute.of(context)?.isCurrent ?? false)) {
      unawaited(_ask(fresh.first));
    }
    if (sync.syncs == _syncsSeen) return;
    _syncsSeen = sync.syncs;
    final summary = sync.lastSummary;
    if (mounted && (summary == null || summary.updated > 0)) _reload();
  }

  Future<void> _pull() async {
    try {
      await widget.sync?.sync(full: true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
    if (mounted) _reload();
  }

  /// Opens the reader; another document ends the session before, as only one voice reads.
  Future<void> _show(
    String name,
    Uint8List data,
    String placeKey,
    LibraryDocument? prepared, {
    bool reading = false,
  }) async {
    final phoneLangs = await _phoneLangs;
    final canDictate = await _canDictate;
    if (!mounted) return;
    setState(() {
      if (_session?.placeKey != placeKey) {
        _session = ReadingSession(
          name: name,
          data: data,
          placeKey: placeKey,
          prepared: prepared,
          phoneLangs: phoneLangs,
          canDictate: canDictate,
          startInReading: reading,
        );
      }
      _expanded = true;
    });
  }

  /// Back hides the reader, and a document with audio goes on in the Now Playing bar; one without has
  /// nothing to play, so closing it ends it.
  void _collapse() {
    if (_session?.hasAudio ?? false) {
      setState(() => _expanded = false);
    } else {
      _endSession();
    }
  }

  void _endSession() => setState(() {
    _session = null;
    _expanded = false;
    _playerOpen = false;
  });

  /// Shows a PDF that came from outside: the picker, or "Open with" in another app.
  Future<void> _openOpened(OpenedDocument document, {bool reading = false}) async {
    // A PDF the desktop prepared is found by its bytes, wherever it was opened from.
    final prepared = await widget.library?.find(document.data);
    if (mounted) await _show(document.name, document.data, document.uri, prepared, reading: reading);
  }

  Future<void> _openIncoming() async {
    try {
      final document = await widget.documents.takeIncoming();
      // Handed over by another app: straight into the reading view.
      if (document != null) await _openOpened(document, reading: true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: ${e.message}')));
    }
  }

  Future<void> _open() async {
    try {
      final document = await widget.documents.pickPdf();
      if (document != null) await _openOpened(document);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: ${e.message}')));
    }
  }

  Future<void> _openPrepared(LibraryDocument document) async => _show(
    document.manifest.name,
    await document.pdf.readAsBytes(),
    'library:${document.manifest.docId}',
    document,
  );

  void _reload() {
    final prepared = widget.library?.documents() ?? Future.value(const <LibraryDocument>[]);
    setState(() {
      _prepared = prepared;
    });
  }

  /// Everything that connects the phone to others is on the Settings tab.
  void _syncScreen() => setState(() => _tab = 2);

  /// A tap on a document that is not here, or on Download: always, whatever the network.
  Future<void> _download(Manifest manifest) async {
    try {
      await widget.sync?.download(manifest);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
    if (mounted) _reload();
  }

  Future<void> _remove(LibraryDocument document) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${document.manifest.name} from this phone?'),
        content: const Text('It stays in your cloud, and you can download it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    await widget.sync?.removeFromPhone(document);
    if (widget.sync == null) await widget.library?.remove(document);
    _reload();
  }

  LibraryDocument? _held(List<LibraryDocument> prepared, LibraryEntry e) =>
      prepared.where((d) => d.manifest.docId == e.manifest.docId).firstOrNull;

  /// Home: the documents read last and those new on the phone, then every document (PLAN 9.2).
  Widget _home(List<LibraryDocument> prepared, List<LibraryEntry> entries, bool loaded) {
    final byId = {for (final d in prepared) d.manifest.docId: d};
    final lastRead = widget.places?.lastRead ?? const <String, num>{};
    final recent = [for (final id in continueReading(lastRead)) ?byId[id]];
    final fresh = [
      for (final id in newOnPhone({
        for (final d in prepared) d.manifest.docId: d.arrived.millisecondsSinceEpoch,
      }, lastRead.keys.toSet()))
        byId[id]!,
    ];
    Widget section(String title, List<LibraryDocument> docs, String Function(LibraryDocument) subtitle) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            for (final d in docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(d.manifest.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle(d)),
                onTap: () => _openPrepared(d),
              ),
          ],
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Look for prepared documents again',
            onPressed: _reload,
          ),
          if (widget.sync case final sync?)
            ListenableBuilder(
              listenable: sync,
              builder: (context, _) => IconButton(
                key: Key('sync-${sync.state.name}'),
                icon: Icon(switch (sync.state) {
                  SyncState.off => Icons.cloud_off_outlined,
                  SyncState.pending => Icons.cloud_upload_outlined,
                  SyncState.syncing => Icons.sync,
                  SyncState.done => Icons.cloud_done_outlined,
                }),
                tooltip: switch (sync.state) {
                  SyncState.off => 'Sync: not set up',
                  SyncState.pending => 'Sync: waiting',
                  SyncState.syncing => 'Sync: syncing',
                  SyncState.done => 'Sync: up to date',
                },
                onPressed: _syncScreen,
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pull,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Room under the last document for the button over the list's corner.
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (recent.isNotEmpty)
              section('Continue reading', recent, (d) {
                final page = widget.places?.progress('library:${d.manifest.docId}')?.progress.page;
                return page == null ? '' : 'Page $page of ${d.manifest.pages}';
              }),
            if (fresh.isNotEmpty) section('New on this phone', fresh, (d) => formatBytes(d.manifest.bytes)),
            if (entries.isEmpty)
              loaded
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Documents prepared on your computer appear here once it syncs with your '
                        'Nextcloud, or once you pair with it over Wi-Fi. Both are set up in Settings.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox.shrink()
            else ...[
              const SizedBox(height: 16),
              Text('All documents', style: Theme.of(context).textTheme.titleSmall),
              _list(prepared, entries),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(List<LibraryDocument> prepared, List<LibraryEntry> entries) => ValueListenableBuilder(
    valueListenable: _favourites,
    builder: (context, favourites, _) => LibraryList(
      entries: entries,
      onOpen: (e) => _openPrepared(_held(prepared, e)!),
      onDownload: (e) => _download(e.manifest),
      onOffer: (e) => _ask(e.offer!),
      onRemove: (e) => _remove(_held(prepared, e)!),
      isLiked: (e) => favourites.isLiked(e.manifest.docId),
      onLike: (e) => _favourites.change((f) => f.toggleLike(e.manifest.docId)),
      onFolders: (e) => chooseFolders(context, _favourites, e.manifest.docId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return PopScope(
      // Back minimises the player first, then hides the reader; the voice goes on and the bar stays.
      canPop: !_expanded && !_playerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_playerOpen) {
          setState(() => _playerOpen = false);
        } else {
          _collapse();
        }
      },
      child: Stack(
        children: [
          FutureBuilder(
            future: _prepared,
            builder: (context, snapshot) {
              final prepared = snapshot.data ?? const <LibraryDocument>[];
              return ListenableBuilder(
                listenable: widget.sync ?? _never,
                builder: (context, _) {
                  final sync = widget.sync;
                  final entries = libraryEntries(
                    local: [for (final d in prepared) d.manifest],
                    cloud: sync?.cloud ?? const [],
                    downloading: sync?.downloading ?? const {},
                    offers: sync?.offers ?? const [],
                  );
                  return Scaffold(
                    body: IndexedStack(
                      index: _tab,
                      children: [
                        _home(prepared, entries, snapshot.connectionState == ConnectionState.done),
                        FavouritesTab(
                          favourites: _favourites,
                          entries: entries,
                          onOpen: (e) => _openPrepared(_held(prepared, e)!),
                          onDownload: (e) => _download(e.manifest),
                          onOffer: (e) => _ask(e.offer!),
                          onRemove: (e) => _remove(_held(prepared, e)!),
                        ),
                        // Built only while shown: it listens for computers on the network.
                        if (_tab == 2)
                          SettingsTab(
                            sync: sync,
                            desktops: sync?.desktopStore,
                            places: widget.places,
                            appSettings: widget.appSettings ?? AppSettingsStore.inMemory(),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                    floatingActionButton: switch (_tab) {
                      0 => FloatingActionButton(
                        key: const Key('open-pdf'),
                        tooltip: 'Open a PDF',
                        onPressed: _open,
                        child: const Icon(Icons.file_open_outlined),
                      ),
                      1 => FloatingActionButton(
                        key: const Key('new-folder'),
                        tooltip: 'New folder',
                        onPressed: () => editFolder(context, _favourites),
                        child: const Icon(Icons.add),
                      ),
                      _ => null,
                    },
                    bottomNavigationBar: NavigationBarTheme(
                      data: const NavigationBarThemeData(height: 56),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (session != null && session.hasAudio)
                            NowPlayingBar(
                              session: session,
                              favourites: _favourites,
                              onOpen: () => setState(() => _playerOpen = true),
                              onClose: _endSession,
                            ),
                          NavigationBar(
                            selectedIndex: _tab,
                            onDestinationSelected: (tab) => setState(() => _tab = tab),
                            destinations: const [
                              NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
                              NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Favourites'),
                              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // The reader stays alive under the tabs while the bar shows, so the voice goes on.
          if (session != null)
            Offstage(
              offstage: !_expanded,
              child: TickerMode(
                enabled: _expanded,
                child: ReaderPage(
                  key: ObjectKey(session),
                  name: session.name,
                  data: session.data,
                  placeKey: session.placeKey,
                  prepared: session.prepared,
                  phoneVoice: widget.phoneVoice,
                  phoneLangs: session.phoneLangs,
                  dictation: widget.dictation,
                  favourites: _favourites,
                  onOpenPlayer: () => setState(() => _playerOpen = true),
                  playback: widget.playback,
                  places: widget.places,
                  notesStore: widget.notesStore,
                  documents: widget.documents,
                  session: session,
                  onCollapse: _collapse,
                  startInReading: session.startInReading,
                ),
              ),
            ),
          // Over everything, the navigation bar too (PLAN 11).
          if (session != null)
            Positioned.fill(
              child: PlayerLayer(
                open: _playerOpen,
                session: session,
                onMinimize: () => setState(() => _playerOpen = false),
                onOpenText: () => setState(() {
                  _playerOpen = false;
                  _expanded = true;
                }),
              ),
            ),
        ],
      ),
    );
  }
}
