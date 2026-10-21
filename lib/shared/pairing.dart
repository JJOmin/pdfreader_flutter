// Port of the desktop's src/shared/pairing.ts, the parts the phone needs: the pairing code it
// checks the desktop's certificate against, and the UDP announcement it listens for.
import 'dart:convert';

const protocolVersion = 1;
const _app = 'pdfreader';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 60 bits: an attacker needs about 10^18 key generations to match them (desktop ADR 7 section 6).
const _codeHexDigits = 15;
const _codeLength = 12;

/// The desktop's phone server, and where its announcements go (desktop step S5).
const desktopPort = 47613;
const announceGroup = '239.255.47.13';

/// The code the desktop shows: the fingerprint's first 60 bits in Crockford base32, as XXXX-XXXX-XXXX.
String pairingCode(String fingerprintHex) {
  var value = BigInt.parse(fingerprintHex.substring(0, _codeHexDigits), radix: 16);
  final code = StringBuffer();
  final digits = <String>[];
  for (var i = 0; i < _codeLength; i++) {
    digits.insert(0, _crockford[(value & BigInt.from(31)).toInt()]);
    value >>= 5;
  }
  for (var i = 0; i < _codeLength; i += 4) {
    if (i > 0) code.write('-');
    code.writeAll(digits.sublist(i, i + 4));
  }
  return code.toString();
}

final _separators = RegExp(r'[\s-]');

/// A typed code without dashes, or null. Crockford reads O as 0 and I and L as 1, so typos pass.
String? normalizeCode(String typed) {
  final code = typed
      .toUpperCase()
      .replaceAll(_separators, '')
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
  if (code.length != _codeLength || code.split('').any((c) => !_crockford.contains(c))) return null;
  return code;
}

/// Whether a certificate with this fingerprint is the one the typed code was made from.
bool codeMatches(String fingerprintHex, String typed) {
  final code = normalizeCode(typed);
  return code != null && pairingCode(fingerprintHex.toLowerCase()).replaceAll('-', '') == code;
}

/// A desktop as its announcement names it.
typedef Announcement = ({String name, int port});

Announcement? parseAnnouncement(List<int> bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, Object?>) return null;
    final name = value['name'];
    final port = value['port'];
    if (value['app'] != _app || value['protocol'] != protocolVersion || name is! String) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    return (name: name, port: port);
  } on FormatException {
    return null;
  }
}
