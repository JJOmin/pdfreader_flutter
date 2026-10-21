// Turns a WOFF 1.0 font into the TrueType/OpenType file it was made from, so the phone can bundle
// the same OFL fonts the desktop takes from @fontsource (PLAN step 3.4). WOFF is the font's tables
// compressed one by one with zlib; this undoes that and writes the sfnt table directory again.
//   dart run tool/woff_to_ttf.dart <in.woff> <out.ttf>
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/woff_to_ttf.dart <in.woff> <out.ttf>');
    exit(1);
  }
  File(args[1]).writeAsBytesSync(woffToSfnt(File(args[0]).readAsBytesSync()));
}

Uint8List woffToSfnt(Uint8List woff) {
  final input = ByteData.sublistView(woff);
  if (input.getUint32(0) != 0x774F4646) throw const FormatException('Not a WOFF 1.0 file'); // "wOFF"
  final flavor = input.getUint32(4);
  final count = input.getUint16(12);
  final tables = <({int tag, int checksum, Uint8List data})>[];
  for (var i = 0; i < count; i++) {
    final at = 44 + i * 20;
    final offset = input.getUint32(at + 4);
    final compressed = input.getUint32(at + 8);
    final original = input.getUint32(at + 12);
    final bytes = woff.sublist(offset, offset + compressed);
    final data = compressed < original ? Uint8List.fromList(zlib.decode(bytes)) : bytes;
    if (data.length != original) throw FormatException('Table $i has ${data.length} bytes, not $original');
    tables.add((tag: input.getUint32(at), checksum: input.getUint32(at + 16), data: data));
  }

  // The table directory's search fields, as the OpenType spec defines them.
  var power = 1;
  var selector = 0;
  while (power * 2 <= count) {
    power *= 2;
    selector++;
  }
  int padded(int n) => (n + 3) & ~3;
  final headerSize = 12 + 16 * count;
  final out = ByteData(headerSize + tables.fold<int>(0, (n, t) => n + padded(t.data.length)));
  out
    ..setUint32(0, flavor)
    ..setUint16(4, count)
    ..setUint16(6, power * 16)
    ..setUint16(8, selector)
    ..setUint16(10, count * 16 - power * 16);
  var offset = headerSize;
  final bytes = out.buffer.asUint8List();
  for (var i = 0; i < count; i++) {
    final table = tables[i];
    out
      ..setUint32(12 + i * 16, table.tag)
      ..setUint32(16 + i * 16, table.checksum)
      ..setUint32(20 + i * 16, offset)
      ..setUint32(24 + i * 16, table.data.length);
    bytes.setRange(offset, offset + table.data.length, table.data);
    offset += padded(table.data.length);
  }
  return bytes;
}
