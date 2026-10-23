import 'package:flutter/services.dart';

/// A document the user opened, with the content URI it came from.
class OpenedDocument {
  const OpenedDocument({required this.uri, required this.name, required this.data});

  /// Names the document across sessions; never a file path (ADR 1).
  final String uri;
  final String name;
  final Uint8List data;
}

/// The platform side of opening and saving documents: MainActivity.kt on Android.
class DocumentAccess {
  static const _channel = MethodChannel('pdfreader/documents');

  /// Shows the system picker for PDFs. Null when the user cancels.
  Future<OpenedDocument?> pickPdf() async {
    final result = await _channel.invokeMapMethod<String, Object?>('pickPdf');
    if (result == null) return null;
    return OpenedDocument(
      uri: result['uri']! as String,
      name: result['name']! as String,
      data: result['data']! as Uint8List,
    );
  }

  /// The system's "save as" with `name` proposed. True once written, false when the user cancels.
  Future<bool> saveAs(String name, String mime, Uint8List data) async =>
      await _channel.invokeMethod<bool>('saveAs', {'name': name, 'mime': mime, 'data': data}) ?? false;
}
