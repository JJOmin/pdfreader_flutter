// Port of the desktop's src/shared/language.ts.
import 'types.dart';

// Function words only. Words common to both languages (in, an, was, war, also, so) are left out.
final _words = <Lang, Set<String>>{
  Lang.de:
      '''der die das und ist nicht ein eine einer eines einem einen zu mit von für auf den dem des
     sich auch als wie bei oder aber wird werden wurde wurden sind dass durch nach über unter
     zwischen diese dieser dieses diesem ich wir sie es im zum zur vom kann können nur noch
     mehr sehr wenn weil hat haben sein ihre ihr um aus bis ohne gegen beim keine kein
     jedoch sowie damit dabei daher dies man'''
          .split(RegExp(r'\s+'))
          .toSet(),
  Lang.en:
      '''the and of to is that for with as on are be this by it were which or from at have has
     not but can we our their these those its into than been would should could there what
     when where who will more most such may between using used use if then they you your
     his her all any each both does did do'''
          .split(RegExp(r'\s+'))
          .toSet(),
};

final _letters = RegExp(r'\p{L}+', unicode: true);
final _umlaut = RegExp('[äöüß]', unicode: true);

/// A language guess; `confident` when the evidence is strong enough to override the document's.
typedef LangGuess = ({Lang lang, bool confident});

/// Guesses German or English from function words. Built for sentences, not single words.
LangGuess guessLang(String text) {
  var de = 0;
  var en = 0;
  for (final match in _letters.allMatches(text.toLowerCase())) {
    final word = match.group(0)!;
    if (_words[Lang.de]!.contains(word) || _umlaut.hasMatch(word)) {
      de++;
    } else if (_words[Lang.en]!.contains(word)) {
      en++;
    }
  }
  final lang = de > en ? Lang.de : Lang.en;
  final (score, other) = lang == Lang.de ? (de, en) : (en, de);
  return (lang: lang, confident: score >= 2 && score >= 2 * other);
}

/// Language of a sentence, falling back to the document's language when the sentence is ambiguous.
Lang sentenceLang(String text, Lang documentLang) {
  final guess = guessLang(text);
  return guess.confident ? guess.lang : documentLang;
}
