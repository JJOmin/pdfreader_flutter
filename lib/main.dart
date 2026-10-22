import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:path_provider/path_provider.dart';

import 'cloud_page.dart';
import 'desktop_link.dart';
import 'desktops_page.dart';
import 'document_access.dart';
import 'library.dart';
import 'library_list.dart';
import 'shared/library_view.dart';
import 'notes_store.dart';
import 'places.dart';
import 'platform_secrets.dart';
import 'playback.dart';
import 'reader_page.dart';
import 'store/cloud_accounts.dart';
import 'shared/sync.dart' show Manifest;
import 'shared/sync_state.dart';
import 'store/cloud_catalog.dart';
import 'store/memo_file.dart';
import 'sync_controller.dart';

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
  // What the user changes is sent soon; what a sync brings in is not sent back.
  notesStore.onSaved = sync.ownChanged;
  places.onStateWritten = () => sync.ownChanged(place: true);
  runApp(
    PdfReaderApp(
      library: library,
      playback: playback,
      places: places,
      notesStore: notesStore,
      cloud: cloud,
      sync: sync,
    ),
  );
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({
    super.key,
    this.documents,
    this.library,
    this.playback,
    this.places,
    this.notesStore,
    this.cloud,
    this.sync,
  });

  /// Replaced in widget tests, which have no platform side.
  final DocumentAccess? documents;
  final Library? library;
  final ReadingHandler? playback;
  final Places? places;
  final NotesStore? notesStore;
  final CloudAccounts? cloud;
  final SyncController? sync;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PDF Reader',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: HomePage(
      documents: documents ?? DocumentAccess(),
      library: library,
      playback: playback,
      places: places,
      notesStore: notesStore,
      cloud: cloud,
      sync: sync,
    ),
  );
}

/// The documents the desktop prepared, and the picker for any other PDF.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.documents,
    this.library,
    this.playback,
    this.places,
    this.notesStore,
    this.cloud,
    this.sync,
  });

  final DocumentAccess documents;
  final Library? library;
  final ReadingHandler? playback;
  final Places? places;
  final NotesStore? notesStore;
  final CloudAccounts? cloud;
  final SyncController? sync;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late Future<List<LibraryDocument>> _prepared = widget.library?.documents() ?? Future.value(const []);

  var _syncsSeen = 0;

  /// What the list listens to where there is no sync (widget tests).
  static final _never = ChangeNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sync?.addListener(_onSync);
    widget.sync?.resume();
  }

  @override
  void dispose() {
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

  /// A sync that brought something shows it in the list without a tap.
  void _onSync() {
    final sync = widget.sync!;
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

  void _show(String name, Uint8List data, String placeKey, LibraryDocument? prepared) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            name: name,
            data: data,
            placeKey: placeKey,
            prepared: prepared,
            playback: widget.playback,
            places: widget.places,
            notesStore: widget.notesStore,
          ),
        ),
      );

  Future<void> _open() async {
    try {
      final document = await widget.documents.pickPdf();
      if (document == null) return;
      // A PDF the desktop prepared is found by its bytes, wherever it was opened from.
      final prepared = await widget.library?.find(document.data);
      if (mounted) _show(document.name, document.data, document.uri, prepared);
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

  Future<void> _desktops() async {
    final library = widget.library;
    if (library == null) return;
    final store = await DesktopStore.open();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopsPage(store: store, library: library, notes: widget.notesStore),
      ),
    );
    _reload();
  }

  Future<void> _cloud() async {
    final sync = widget.sync;
    if (sync == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CloudPage(sync: sync)));
    _reload();
  }

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('PDF Reader'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Look for prepared documents again',
          onPressed: _reload,
        ),
        IconButton(icon: const Icon(Icons.computer), tooltip: 'Desktops', onPressed: _desktops),
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
                SyncState.off => 'Cloud: not set up',
                SyncState.pending => 'Cloud: waiting to sync',
                SyncState.syncing => 'Cloud: syncing',
                SyncState.done => 'Cloud: up to date',
              },
              onPressed: _cloud,
            ),
          ),
      ],
    ),
    body: FutureBuilder(
      future: _prepared,
      builder: (context, snapshot) {
        final prepared = snapshot.data ?? const <LibraryDocument>[];
        return RefreshIndicator(
          onRefresh: _pull,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open a PDF'),
                  onPressed: _open,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  key: const Key('connect'),
                  icon: const Icon(Icons.computer),
                  label: const Text('Connect to a desktop'),
                  onPressed: widget.library == null ? null : _desktops,
                ),
              ),
              ListenableBuilder(
                listenable: widget.sync ?? _never,
                builder: (context, _) {
                  final sync = widget.sync;
                  final entries = libraryEntries(
                    local: [for (final d in prepared) d.manifest],
                    cloud: sync?.cloud ?? const [],
                    downloading: sync?.downloading ?? const {},
                  );
                  if (entries.isEmpty) {
                    return snapshot.connectionState == ConnectionState.done
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Documents prepared on your computer appear here once it syncs with your '
                              'Nextcloud, or when you connect to it over Wi-Fi.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: LibraryList(
                      entries: entries,
                      onOpen: (e) =>
                          _openPrepared(prepared.firstWhere((d) => d.manifest.docId == e.manifest.docId)),
                      onDownload: (e) => _download(e.manifest),
                      onRemove: (e) =>
                          _remove(prepared.firstWhere((d) => d.manifest.docId == e.manifest.docId)),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
