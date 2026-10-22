import 'dart:convert';
import 'dart:io';

import '../shared/sync.dart';

/// The manifests of the documents the cloud holds, as the last syncs learned them, so that the library
/// can list what is only in the cloud without asking for it. A full walk replaces the list; a sync
/// that read the journals adds or replaces the documents they named.
class CloudCatalog {
  CloudCatalog(this.file);

  final File file;

  Future<List<Manifest>> load() async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! List) return const [];
      return [for (final entry in value) ?parseManifest(entry)];
    } on FileSystemException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  /// [complete] says [manifests] is all of the cloud, so what is not in it is gone.
  Future<List<Manifest>> update(List<Manifest> manifests, {required bool complete}) async {
    final merged = {
      if (!complete)
        for (final m in await load()) m.docId: m,
      for (final m in manifests) m.docId: m,
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final m in merged.values) m.toJson()]));
    return merged.values.toList();
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
