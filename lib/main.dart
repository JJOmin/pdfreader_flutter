import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'document_access.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The speech side reads page text through the engine before any viewer exists.
  pdfrxFlutterInitialize();
  runApp(const PdfReaderApp());
}

class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key, this.documents});

  /// Replaced in widget tests, which have no platform side.
  final DocumentAccess? documents;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PDF Reader',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: ReaderPage(documents: documents ?? DocumentAccess()),
  );
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.documents});

  final DocumentAccess documents;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  OpenedDocument? _document;

  Future<void> _open() async {
    try {
      final document = await widget.documents.pickPdf();
      if (document != null) setState(() => _document = document);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        title: Text(document?.name ?? 'PDF Reader', overflow: TextOverflow.ellipsis),
        actions: [IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Open a PDF', onPressed: _open)],
      ),
      body: document == null
          ? Center(
              child: FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Open a PDF'),
                onPressed: _open,
              ),
            )
          : PdfViewer.data(document.data, sourceName: document.uri, key: ValueKey(document.uri)),
    );
  }
}
