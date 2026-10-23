// The fonts the phone offers, for the reading view and for the whole app. The names are the
// desktop's, so a settings file reads the same on both; two are bundled, two are the phone's own.

/// The key kept in the settings and what the user sees.
const fontChoices = [
  ('OpenDyslexic', 'OpenDyslexic'),
  ('Lexend', 'Lexend'),
  ('Verdana', 'Phone sans'),
  ('Georgia', 'Phone serif'),
];

/// The font family to set, or null for the phone's own sans-serif.
String? fontFamilyOf(String font) => switch (font) {
  'OpenDyslexic' || 'Lexend' => font,
  'Georgia' => 'serif',
  _ => null,
};
