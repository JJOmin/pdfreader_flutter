# 6. The full-screen player and spoken comments

Date: 2026-10-23

Status: **Accepted** by the owner's request of 2026-10-23. Section 5 was first built on Android's
own recogniser, which did not work on the owner's phone; on 2026-10-23 the owner asked for speech
recognition on the phone itself, and section 5 now describes that.

## Decision

1. **Two players.** The small bar is the one from the menu (play, title at 13 sp, heart, next) and
   now also sits in the reader, where the old bar with previous, next and speed was. The icon that
   said where the audio comes from is gone from both: it looked like a button. A tap on either bar
   opens the full-screen player.
2. **The full-screen player** (`lib/player_screen.dart`) slides over the whole app, the navigation
   bar too. Top left, a minimise button returns to where it was opened from, the menu or the reader
   (Back does the same); top right, "Show the text" minimises into the reader. The controls sit on
   one rounded panel on the bottom edge, as tall as they need and no more (about a quarter of the
   screen, so the text gets the rest): previous, play and next (56, 72 and 56 dp), Comment and
   Speak (44 dp) side by side; speed is a pair of − and + buttons (a tenth each). The source of the audio is a line
   of words ("Page 2 · computer audio", "· phone voice").
3. **The preview** (`lib/views/speed_reader.dart`) replaces cover art: the sentence in 30 sp type,
   the spoken word highlighted, words already spoken dimmed, the window scrolling so the spoken word
   stays at its middle, and the sentences before and after faded. It paints from the same words and
   word index the voice follows (`ReadingSession.sentence`, `word`).
4. **Comments without touching the text.** *Comment* pauses the voice, asks for a comment on the
   sentence being read and marks that sentence (a yellow highlight over its raw range) with it, then
   reads on if it was reading. *Speak* does the same but starts listening. The same sheet has a
   microphone for a selection's mark menu. What is heard goes into the text field as a **draft**, to
   be corrected before Save; nothing is saved by itself. The format of notes is unchanged.
5. **Speech recognition runs on the phone with sherpa-onnx** (already approved in ADR 1), with the
   multilingual NeMo CTC model of the speech spike (English and German, 127 MB), which finds the
   language itself. Nothing leaves the phone. Android's own recogniser was tried first
   (`createOnDeviceSpeechRecognizer`): on the owner's Samsung S20 FE it reports itself available but
   cannot be bound (`Bind to system recognition service failed with error 10`; the only
   `RecognitionService` installed is Google TTS's), and its "prefer offline" mode may use the network.
   - `Dictation.kt` only records the microphone (`AudioRecord`, 16 kHz mono, 100 ms pieces) and asks
     for `RECORD_AUDIO` the first time the user speaks.
   - `lib/shared/endpoint.dart` ends the recording after a 1.8 s pause that follows speech, after 6 s
     with nothing said, or after 60 s. A plain level detector with a capped background estimate, so
     speaking from the first moment is not taken for a hum.
   - `lib/speech/transcriber.dart` runs the model in an isolate that is started when the user begins
     to speak and let go 90 s after the last use. The audio gets 0.4 s of silence before and after:
     without it the first word of an English test sentence came out as "Thishi".
   - While the user speaks, the words so far are worked out every 1.5 s; the whole recording is
     worked out once more at the end. The text goes into the comment field as a draft.
   - The model must be on the phone, in the app's `models` folder (`tool/push_models`; only
     `model.int8.onnx` and `tokens.txt` of the recogniser are read). Without it the sheet says so and
     typing works. `// shortcut: pushed with adb; an in-app import comes with ADR 1's import button.`

6. **A spoken comment is told apart in the notes file** (PLAN M12): the mark gets `"via": "speech"`,
   and a mark with a comment shows a note icon above its first line, or a microphone icon if the
   comment was spoken, in both apps. The field is optional, sits between `created` and `updated`,
   travels through the merge like the rest of the mark, and is ignored if it holds anything else.
   The desktop reads and writes it (its `docs/SPEC.md`, "Comment badges").

7. **The selection menu's Comment button** replaces its microphone: it always opens the comment sheet,
   which has the keyboard and, where the phone can listen, the microphone (PLAN 13.1).
8. **The voice can be chosen in the player** where both exist (PLAN 13.2): computer audio, the
   default, or the phone's own voice for every sentence. See ADR 5, which says the computer's audio
   is preferred; this is the user overriding that, per app run.

## Consequences

- Playback can be run without looking: large targets, one screen, no menus.
- The reader loses the previous button and the speed control from its bar; they are in the player.
- A comment on a sentence over a page break marks the part on the sentence's own page.
- The model takes 127 MB on the phone, and about 1.2 s to load; decoding 4.5 s of speech takes about
  0.12 s on the S20 FE.

## Measured (2026-10-23, S20 FE)

`integration_test/dictation_test.dart`: the phone's own German and English voice, fed to the
recogniser, came back as the sentence said (German with commas, English exact after the padding).
The real microphone opened, a quiet room gave "nothing heard" after 6 s, and the phone's voice played
aloud into its own microphone was written out with the words appearing while it spoke. In that last
run the first two words ("Hier ist") were missing, which is probably the speaker and microphone, not
the model; no person has spoken to it yet.
