import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'desktop_link.dart';
import 'desktops_page.dart';
import 'document_access.dart';
import 'library.dart';
import 'places.dart';
import 'playback.dart';
import 'reader_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The speech side reads page text through the engine before any viewer exists.
  await pdfrxFlutterInitialize();
  final playback = await initPlayback();
  final store = await DesktopStore.open();
  final places = await Places.open((device: store.device, name: await phoneName()));
  runApp(PdfReaderApp(library: await Library.open(), playback: playback, places: places));
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key, this.documents, this.library, this.playback, this.places});

  /// Replaced in widget tests, which have no platform side.
  final DocumentAccess? documents;
  final Library? library;
  final ReadingHandler? playback;
  final Places? places;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PDF Reader',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: HomePage(
      documents: documents ?? DocumentAccess(),
      library: library,
      playback: playback,
      places: places,
    ),
  );
}

/// The documents the desktop prepared, and the picker for any other PDF.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.documents, this.library, this.playback, this.places});

  final DocumentAccess documents;
  final Library? library;
  final ReadingHandler? playback;
  final Places? places;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<LibraryDocument>> _prepared = widget.library?.documents() ?? Future.value(const []);

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
        builder: (_) => DesktopsPage(store: store, library: library),
      ),
    );
    _reload();
  }

  Future<void> _remove(LibraryDocument document) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${document.manifest.name} from this phone?'),
        content: const Text('The desktop keeps it, and the next sync fetches it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    await widget.library?.remove(document);
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
      ],
    ),
    body: FutureBuilder(
      future: _prepared,
      builder: (context, snapshot) {
        final prepared = snapshot.data ?? const <LibraryDocument>[];
        return ListView(
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
            if (prepared.isEmpty && snapshot.connectionState == ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Documents prepared on your PC appear here. On the PC, open Phone and switch on '
                  'phone sync; here, connect to it and type the code it shows.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (prepared.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Prepared on the desktop', style: Theme.of(context).textTheme.titleSmall),
              for (final document in prepared)
                ListTile(
                  leading: const Icon(Icons.record_voice_over),
                  title: Text(document.manifest.name),
                  subtitle: Text(
                    '${document.manifest.pages} pages, ${document.manifest.sentences} sentences',
                  ),
                  onTap: () => _openPrepared(document),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove from this phone',
                    onPressed: () => _remove(document),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}
