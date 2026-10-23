# 5. The phone's own voice

Date: 2026-10-23

Status: **Accepted** by the owner on 2026-10-23 ("if the audio is missing, the native TTS can just
be used … always prefer the prerendered version"). It replaces section 1 of
[ADR 2](0002-audio-from-the-desktop.md), which turned the phone's voice off. The rest of ADR 2
stands.

## Context

The desktop's audio is better than anything the phone can make, but it is not always there: a PDF
the desktop never prepared, pages it has not voiced yet (desktop ADR 11), and sentences on a page
whose words differ from the index. Until now each of these was skipped or not readable at all.

## Decision

1. **The desktop's audio is always preferred.** The phone's voice speaks a sentence only when the
   desktop has no audio for it. `planPage` decides, sentence by sentence:
   - a page whose words agree with the index: the desktop's sentences, all of them;
   - a page whose words differ: a sentence whose sync key is in the index uses the desktop's audio,
     any other sentence is spoken by the phone;
   - a page with no index (an unprepared document, or a page not voiced yet): every sentence is
     spoken by the phone.
   A sentence in a language the phone cannot speak offline is skipped, as before.
2. **The system's text-to-speech, to a file, not live.** A small `pdfreader/tts` platform channel
   (`PhoneVoice.kt`) renders one sentence with `TextToSpeech.synthesizeToFile`, and the file plays
   through the same `just_audio` player as the desktop's audio. So the two-sentence lookahead, the
   speed control (`setSpeed`, pitch kept), the word mark, the media notification and the screen-off
   case need no second code path. Requests run one at a time, with the voice set before each. No
   package is added.
3. **Offline voices only.** The app's rule is no internet at runtime. A voice is used only if
   `isNetworkConnectionRequired` is false and its data is installed. If a language has none, the
   phone does not speak it. Samsung's engine names locales with three-letter codes (`eng_USA`), so
   the language is matched in both forms.
4. **Word timings are estimated.** The engine tells nothing about its words, so the player measures
   the file's length and `estimateTimings` spreads it over the words by length, as the desktop's
   spike did before it had a recogniser. The mark can drift by a word on a long sentence.
   `// shortcut: estimated word timings, align with the recogniser if the drift is heard as wrong.`
5. **The source is shown.** Superseded by ADR 6: the bars carry no icon and the reader no status
   box; the full-screen player's line says "computer audio" or "phone voice" for the sentence being
   read, and a fully prepared document tells once how many sentences the phone reads.
6. **iOS later.** `PhoneVoice` is a Dart interface; the Swift side would use
   `AVSpeechSynthesizer.write`. Until it exists the channel is missing and the phone reports no
   voice, so iOS builds and behaves as before.

## Consequences

- Every PDF can be read aloud on an Android phone that has an offline voice, prepared or not.
- A page is planned once when first needed. Audio the desktop delivers after that is used the next
  time the document is opened.
- The phone's voice is usually lower in quality and its sentence breaks are the phone's own.
- Each phone sentence costs a synthesis (about 300 ms on the S20 FE with Samsung's engine), which
  the lookahead of two hides. The audio is a temporary file in the app's cache, deleted when the
  sentence has been played; leftovers are removed when the engine starts.
- The manifest needs `<queries>` for the `TTS_SERVICE` action, or Android 11 and later hide the
  engine from the app.

## Measured (2026-10-23, S20 FE, Samsung TTS, Android 13)

Both German and English found offline. A short sentence took 287 ms (German) and 340 ms (English)
to render. `integration_test/phone_voice_test.dart` reads an unprepared one-page PDF: both
sentences were spoken by the phone, the word mark advanced, and Pause worked.

## Not verified

- A document mixing the desktop's audio and the phone's voice, heard by the owner.
- Google's speech engine; only Samsung's was on the phone.
