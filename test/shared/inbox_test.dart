// Port of the desktop's tests/unit/inbox.test.ts, the parts the phone reads.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/shared/inbox.dart';
import 'package:pdfreader/shared/sync_store.dart';

void main() {
  final phone = 'e' * 32;
  Map<String, Object?> offer(String id, {int sent = 1}) => {
    'docId': id * 64,
    'name': '$id.pdf',
    'bytes': 1000,
    'sent': sent,
  };

  test('reads only what is valid', () {
    final read = parseOffers([
      offer('a'),
      {...offer('b'), 'bytes': -1},
      {'docId': 'x'},
      null,
    ]);
    expect(read.map((o) => o.name), ['a.pdf']);
    expect(read.single.key, '${'a' * 64}@1');
    expect(parseOffers('nope'), isEmpty);
    expect(
      parseInbox({
        phone: [offer('a')],
        'short': [offer('b')],
        'c' * 32: <Object?>[],
      }).keys,
      [phone],
    );
  });

  test('a journal carries them, and leaves them out of its bytes when there are none', () {
    final journal = parseJournal({
      'device': 'd' * 32,
      'name': 'Mac',
      'updated': 1,
      'docs': <String, Object?>{},
      'offers': {
        phone: [offer('a')],
      },
    })!;
    expect(journal.offers[phone]!.single.name, 'a.pdf');
    expect(
      jsonEncode(parseJournal(jsonDecode(jsonEncode(journal.toJson())))!.toJson()),
      jsonEncode(journal.toJson()),
    );
    expect(
      jsonEncode(Journal(device: 'd' * 32, name: '', updated: 1, docs: const {}).toJson()),
      isNot(contains('offers')),
    );
  });

  group('pendingOffers', () {
    Offer o(String id, int sent) => Offer(docId: id * 64, name: '$id.pdf', bytes: 1, sent: sent);

    test('asks once per document, about the newest offer, oldest question first', () {
      final pending = pendingOffers(
        [PendingOffer(o('a', 1), 'Mac'), PendingOffer(o('b', 2), 'PC'), PendingOffer(o('a', 3), 'Mac')],
        handled: {},
        onPhone: {},
      );
      expect([for (final p in pending) '${p.offer.name} ${p.offer.sent}'], ['b.pdf 2', 'a.pdf 3']);
    });

    test(
      'leaves out what was answered and what is on the phone, but asks again for a document sent again',
      () {
        final pending = pendingOffers(
          [PendingOffer(o('a', 1), 'Mac'), PendingOffer(o('b', 2), 'Mac'), PendingOffer(o('c', 5), 'Mac')],
          handled: {o('a', 1).key, o('c', 4).key},
          onPhone: {'b' * 64},
        );
        expect([for (final p in pending) p.offer.name], ['c.pdf']);
      },
    );
  });
}
