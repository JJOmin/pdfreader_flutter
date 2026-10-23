// Port of the desktop's src/shared/types.ts, limited to what the phone uses so far.

enum Lang { en, de }

enum Role { main, quote, heading }

/// One text run, reduced to what layout needs. PDF units, y grows upwards.
class RawItem {
  const RawItem({
    required this.str,
    required this.x,
    required this.y,
    required this.height,
    required this.font,
    required this.hasEOL,
    required this.rotated,
  });

  final String str;
  final double x;
  final double y;
  final double height;
  final String font;
  final bool hasEOL;
  final bool rotated;
}

/// Half-open span of offsets into a page's raw string, which is every item's `str` concatenated
/// in order. Raw offsets are the one coordinate system shared by speech, highlights and notes.
typedef RawRange = (int, int);

class Word {
  const Word(this.text, this.ranges, {this.page});

  final String text;
  final List<RawRange> ranges;

  /// Set for a word of a sentence's continuation on the next page (desktop ADR 12); else the
  /// utterance's page.
  final int? page;
}

/// The part of a sentence that runs over the page break, on the next page (desktop ADR 12).
typedef PagePart = ({int page, List<RawRange> ranges});

/// One unit handed to the speech engine: a sentence or a heading.
class Utterance {
  const Utterance({
    required this.page,
    required this.text,
    required this.spoken,
    required this.lang,
    required this.role,
    required this.words,
    required this.ranges,
    this.next,
  });

  final int page;

  /// Text as shown in the PDF.
  final String text;

  /// Text sent to the engine: citations blanked out, whitespace collapsed.
  final String spoken;
  final Lang lang;
  final Role role;
  final List<Word> words;
  final List<RawRange> ranges;
  final PagePart? next;
}

class WordTiming {
  const WordTiming(this.start, this.end);

  final double start;
  final double end;

  @override
  String toString() => 'WordTiming($start, $end)';
}

class VoiceRef {
  const VoiceRef(this.model, this.sid);

  final String model;
  final int sid;

  Map<String, Object> toJson() => {'model': model, 'sid': sid};

  @override
  bool operator ==(Object other) => other is VoiceRef && other.model == model && other.sid == sid;

  @override
  int get hashCode => Object.hash(model, sid);

  @override
  String toString() => 'VoiceRef($model, $sid)';
}

class VoiceOption extends VoiceRef {
  const VoiceOption(super.model, super.sid, {required this.label, required this.langs});

  final String label;
  final List<Lang> langs;
}
