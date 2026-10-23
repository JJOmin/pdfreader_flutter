// The liked documents and folders (PLAN 9.3), in `favourites.json` in the app's own storage.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'shared/favourites.dart';

class FavouritesStore extends ValueNotifier<Favourites> {
  FavouritesStore._(this._file, super.value);

  /// Kept nowhere: for widget tests.
  FavouritesStore.inMemory() : this._(null, const Favourites());

  final File? _file;

  static Future<FavouritesStore> load(File file) async {
    try {
      return FavouritesStore._(file, parseFavourites(jsonDecode(await file.readAsString())));
    } on FileSystemException {
      return FavouritesStore._(file, const Favourites());
    } on FormatException {
      return FavouritesStore._(file, const Favourites());
    }
  }

  /// Shows the change at once and writes it beside the file, renamed over it.
  Future<void> change(Favourites Function(Favourites) edit) async {
    value = edit(value);
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(jsonEncode(value.toJson()), flush: true);
    await partial.rename(file.path);
  }
}
