// Port of the desktop's tests/unit/pairing.test.ts, the parts the phone uses.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/pairing.dart';

final fingerprint = '9c1e4d7a03bb5f2e${'ab' * 24}';

void main() {
  group('pairingCode', () {
    test('is the first 60 bits of the fingerprint in Crockford base32, in groups of four', () {
      final code = pairingCode(fingerprint);
      expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$')));
      var value = BigInt.zero;
      for (final c in code.replaceAll('-', '').split('')) {
        value = value * BigInt.from(32) + BigInt.from('0123456789ABCDEFGHJKMNPQRSTVWXYZ'.indexOf(c));
      }
      expect(value.toRadixString(16), '9c1e4d7a03bb5f2');
    });

    test('is the same with upper-case hex', () {
      expect(pairingCode(fingerprint.toUpperCase()), pairingCode(fingerprint));
    });

    test('equals the desktop for a fixed fingerprint', () {
      // Computed with the desktop's pairingCode, so both sides show and check the same code.
      expect(pairingCode('0' * 64), '0000-0000-0000');
      expect(pairingCode('f' * 64), 'ZZZZ-ZZZZ-ZZZZ');
      expect(pairingCode(fingerprint), 'KGF4-TYG3-QDFJ');
    });
  });

  group('normalizeCode and codeMatches', () {
    final code = pairingCode(fingerprint);

    test(
      'accepts the code as typed: any case, without dashes, with the letters Crockford reads as digits',
      () {
        expect(normalizeCode(code.toLowerCase()), code.replaceAll('-', ''));
        expect(normalizeCode(' ${code.replaceAll('-', '')} '), code.replaceAll('-', ''));
        expect(normalizeCode('oil0-1111-1111'), '011011111111');
      },
    );

    test('rejects a code that is too short, too long or has a letter Crockford leaves out', () {
      expect(normalizeCode('ABCD-EFGH-JKM'), isNull);
      expect(normalizeCode('ABCD-EFGH-JKMNP'), isNull);
      expect(normalizeCode('ABCD-EFGH-JKMU'), isNull);
    });

    test('matches only the certificate the code was made from', () {
      expect(codeMatches(fingerprint, code), isTrue);
      expect(codeMatches('0${fingerprint.substring(1)}', code), isFalse);
      expect(codeMatches(fingerprint, 'nonsense'), isFalse);
    });
  });

  group('announcement', () {
    test('reads the desktop’s, and refuses anything that is not ours', () {
      List<int> bytes(Object value) => utf8.encode(jsonEncode(value));
      expect(parseAnnouncement(bytes({'app': 'pdfreader', 'protocol': 1, 'name': 'Desk', 'port': 47613})), (
        name: 'Desk',
        port: 47613,
      ));
      expect(parseAnnouncement(bytes({'app': 'other', 'protocol': 1})), isNull);
      expect(parseAnnouncement(utf8.encode('not json')), isNull);
      expect(
        parseAnnouncement(bytes({'app': 'pdfreader', 'protocol': 1, 'name': 'x', 'port': 70000})),
        isNull,
      );
    });
  });

  group('parsePairingUrl', () {
    final secret = '0123456789abcdef' * 2;
    // The very string the desktop's tests/unit/pairing.test.ts makes.
    final golden =
        'pdfreader://pair?v=1&name=Leos%20MacBook&addr=192.168.1.20:47613,10.0.0.5:47613&code=ABCD-EFGH-JKMN&secret=$secret';

    test('reads what the desktop wrote', () {
      final url = parsePairingUrl(golden)!;
      expect((url.name, url.code, url.secret), ('Leos MacBook', 'ABCD-EFGH-JKMN', secret));
      expect(url.addresses, [(host: '192.168.1.20', port: 47613), (host: '10.0.0.5', port: 47613)]);
    });

    test('reads a name with letters outside ASCII and punctuation', () {
      final odd =
          'pdfreader://pair?v=1&name=${Uri.encodeComponent('Léo & “Mac”, 15%')}&addr=10.0.0.5:47613&code=ABCD-EFGH-JKMN&secret=$secret';
      expect(parsePairingUrl(odd)!.name, 'Léo & “Mac”, 15%');
    });

    test('refuses anything that is not ours', () {
      for (final bad in [
        '',
        'https://pair?v=1',
        golden.replaceFirst('v=1', 'v=2'),
        golden.replaceFirst('pdfreader://pair', 'pdfreader://other'),
        golden.replaceFirst('192.168.1.20:47613,10.0.0.5:47613', 'evil.example.com:47613'),
        golden.replaceFirst('47613,10', '99999,10'),
        golden.replaceFirst('ABCD-EFGH-JKMN', 'ABCD'),
        golden.replaceFirst(secret, 'short'),
        golden.replaceFirst(RegExp('&addr=[^&]*'), ''),
      ]) {
        expect(parsePairingUrl(bad), isNull, reason: bad);
      }
    });
  });
}
