// Port of the desktop's src/shared/inbox.ts: a document a computer offers this phone ("Send to phone",
// desktop ADR 10 section 6). It comes over Wi-Fi (`GET /v1/inbox`) or in the computer's change journal.
class Offer {
  const Offer({required this.docId, required this.name, required this.bytes, required this.sent});

  final String docId;
  final String name;

  /// What it takes on the phone, so the question can say "paper.pdf (12 MB)".
  final int bytes;

  /// When it was sent: sending the same document again is a new offer.
  final int sent;

  /// One offer, the same wherever it came from: what "handled" remembers.
  String get key => '$docId@$sent';

  Map<String, Object?> toJson() => {'docId': docId, 'name': name, 'bytes': bytes, 'sent': sent};
}

final _docId = RegExp(r'^[0-9a-f]{64}$');
final _deviceId = RegExp(r'^[0-9a-f]{32}$');

bool _count(Object? value) => value is int && value >= 0;

List<Offer> parseOffers(Object? value) => [
  if (value is List)
    for (final entry in value)
      if (entry is Map<String, Object?>)
        if ((entry['docId'], entry['name'], entry['bytes'], entry['sent'])
            case (final String docId, final String name, final int bytes, final int sent)
            when _docId.hasMatch(docId) &&
                name.isNotEmpty &&
                name.length <= 512 &&
                _count(bytes) &&
                _count(sent))
          Offer(docId: docId, name: name, bytes: bytes, sent: sent),
];

/// Offers by the phone's device id, as a journal carries them.
Map<String, List<Offer>> parseInbox(Object? value) => {
  if (value is Map<String, Object?>)
    for (final MapEntry(:key, :value) in value.entries)
      if (_deviceId.hasMatch(key) && parseOffers(value).isNotEmpty) key: parseOffers(value),
};

/// An offer the phone still has to answer, with the computer it came from.
class PendingOffer {
  const PendingOffer(this.offer, this.from);

  final Offer offer;

  /// The computer's name, as it introduced itself: what "Always accept from this computer" remembers.
  final String from;
}

/// What the phone still has to answer: each document once (the newest offer of it), not one it
/// answered already, and not one that is on the phone.
List<PendingOffer> pendingOffers(
  Iterable<PendingOffer> offered, {
  required Set<String> handled,
  required Set<String> onPhone,
}) {
  final newest = <String, PendingOffer>{};
  for (final p in offered) {
    if (handled.contains(p.offer.key) || onPhone.contains(p.offer.docId)) continue;
    final known = newest[p.offer.docId];
    if (known == null || known.offer.sent < p.offer.sent) newest[p.offer.docId] = p;
  }
  return newest.values.toList()..sort((a, b) => a.offer.sent.compareTo(b.offer.sent));
}
