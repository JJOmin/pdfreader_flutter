import 'dart:convert';
import 'dart:io';

/// What the phone remembers of "Send to phone": the offers it answered (by `Offer.key`), so that a
/// computer still offering one is not asked about again, and the computers it always accepts from.
class OfferFile {
  OfferFile(this.file);

  final File file;
  var handled = <String>{};
  var alwaysFrom = <String>{};

  Future<void> load() async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?>) return;
      handled = {
        for (final k in value['handled'] is List ? value['handled']! as List : const [])
          if (k is String) k,
      };
      alwaysFrom = {
        for (final k in value['alwaysFrom'] is List ? value['alwaysFrom']! as List : const [])
          if (k is String) k,
      };
    } on FileSystemException {
      return;
    } on FormatException {
      return;
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'handled': handled.toList(), 'alwaysFrom': alwaysFrom.toList()}));
  }
}
