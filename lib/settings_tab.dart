import 'package:flutter/material.dart';

import 'app_settings_store.dart';
import 'cloud_section.dart';
import 'desktop_link.dart';
import 'desktops_section.dart';
import 'places.dart';
import 'shared/app_settings.dart';
import 'shared/fonts.dart';
import 'shared/settings.dart' show maxSpeed, minSpeed;
import 'views/reading_view.dart' show ReadingSettingsSheet;
import 'sync_controller.dart';

/// The Settings tab (PLAN 9.12): a list, each entry opening a page of its own: how the app looks,
/// reading aloud, and the two ways this phone connects to others (7.5), the cloud and the computers.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, this.sync, this.desktops, this.places, required this.appSettings});

  /// Null in widget tests, where there is no sync.
  final SyncController? sync;
  final DesktopStore? desktops;
  final Places? places;
  final AppSettingsStore appSettings;

  static const _themeNames = {
    ThemeChoice.system: 'Same as the system',
    ThemeChoice.light: 'Light',
    ThemeChoice.sepia: 'Sepia',
    ThemeChoice.dark: 'Dark',
    ThemeChoice.custom: 'Custom',
  };

  static final _fontNames = {for (final (key, label) in fontChoices) key: label};

  static void _open(BuildContext context, String title, Widget body) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [body]),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        ValueListenableBuilder(
          valueListenable: appSettings,
          builder: (context, look, _) => ListTile(
            key: const Key('settings-appearance'),
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            subtitle: Text('${_themeNames[look.theme]}, ${_fontNames[look.font]}'),
            onTap: () => _open(context, 'Appearance', _Appearance(appSettings, places)),
          ),
        ),
        ListTile(
          key: const Key('settings-reading'),
          leading: const Icon(Icons.record_voice_over_outlined),
          title: const Text('Reading aloud'),
          subtitle: const Text('Speed, the reference list'),
          onTap: () => _open(context, 'Reading aloud', _Reading(places)),
        ),
        if (sync != null) ...[
          const Divider(),
          ListTile(
            key: const Key('settings-cloud'),
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Nextcloud'),
            subtitle: const Text('Your own cloud, with the sync key'),
            onTap: () => _open(context, 'Nextcloud', CloudSection(sync: sync!)),
          ),
          if (desktops != null)
            ListTile(
              key: const Key('settings-computers'),
              leading: const Icon(Icons.computer_outlined),
              title: const Text('Computers'),
              subtitle: const Text('Pair over Wi-Fi: scan the code, or type it'),
              onTap: () => _open(
                context,
                'Computers',
                DesktopsSection(store: desktops!, library: sync!.library, notes: sync!.notes),
              ),
            ),
        ],
      ],
    ),
  );
}

/// The look of the whole app: the colours, the font and its size, and the reading view's type.
class _Appearance extends StatelessWidget {
  const _Appearance(this.settings, this.places);

  final AppSettingsStore settings;
  final Places? places;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: settings,
    builder: (context, look, _) {
      final title = Theme.of(context).textTheme.titleMedium;
      final (min, max, step) = fontScaleLimits;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Colours', style: title),
          RadioGroup<ThemeChoice>(
            groupValue: look.theme,
            onChanged: (c) => settings.change(look.copyWith(theme: c ?? ThemeChoice.system)),
            child: Column(
              children: [
                for (final c in ThemeChoice.values)
                  RadioListTile<ThemeChoice>(
                    key: Key('theme-${c.name}'),
                    contentPadding: EdgeInsets.zero,
                    value: c,
                    title: Text(SettingsTab._themeNames[c]!),
                  ),
              ],
            ),
          ),
          if (look.theme == ThemeChoice.custom) _CustomColours(look: look, settings: settings),
          const Divider(height: 32),
          Text('Font', style: title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (font, label) in fontChoices)
                ChoiceChip(
                  key: Key('font-$font'),
                  label: Text(label, style: TextStyle(fontFamily: fontFamilyOf(font))),
                  selected: look.font == font,
                  onSelected: (_) => settings.change(look.copyWith(font: font)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Text size: ${(look.fontScale * 100).round()} %', style: title),
          Slider(
            key: const Key('font-scale'),
            value: look.fontScale,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: '${(look.fontScale * 100).round()} %',
            onChanged: (v) => settings.change(look.copyWith(fontScale: v)),
          ),
          const Divider(height: 32),
          ListTile(
            key: const Key('settings-speed-reader'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined),
            title: const Text('Speed reader'),
            subtitle: const Text('Font, size and spacing of the reading view'),
            trailing: const Icon(Icons.chevron_right),
            enabled: places != null,
            onTap: () => SettingsTab._open(context, 'Speed reader', _SpeedReader(places!)),
          ),
        ],
      );
    },
  );
}

/// The three colours of the custom theme, each from a row of swatches. A text colour that could not
/// be read on the background is dimmed and cannot be chosen; a new background brings a readable text.
class _CustomColours extends StatelessWidget {
  const _CustomColours({required this.look, required this.settings});

  final Appearance look;
  final AppSettingsStore settings;

  Widget _row(
    String label,
    String id,
    List<int> colours,
    int selected,
    void Function(int) choose, {
    bool Function(int)? allowed,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final colour in colours)
              Builder(
                builder: (context) {
                  final ok = allowed?.call(colour) ?? true;
                  return Opacity(
                    opacity: ok ? 1 : 0.25,
                    child: InkResponse(
                      key: Key('custom-$id-${colour.toRadixString(16)}'),
                      onTap: ok ? () => choose(colour) : null,
                      child: Semantics(
                        label: '$label ${colour.toRadixString(16)}',
                        selected: colour == selected,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(colour),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: colour == selected ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row(
        'Background',
        'background',
        customBackgrounds,
        look.background,
        (c) => settings.change(look.withBackground(c)),
      ),
      _row(
        'Text',
        'text',
        customTexts,
        look.text,
        (c) => settings.change(look.copyWith(text: c)),
        allowed: (c) => contrastRatio(c, look.background) >= minContrast,
      ),
      _row('Accent', 'accent', customAccents, look.accent, (c) => settings.change(look.copyWith(accent: c))),
    ],
  );
}

/// The reading view's font, size and spacing, kept in the reading settings the desktop shares. Its
/// colours are the app's, chosen under Appearance.
class _SpeedReader extends StatelessWidget {
  const _SpeedReader(this.places);

  final Places places;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: places,
    builder: (context, _) {
      final s = places.reading;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The colours of the reading view are the app’s, chosen under Appearance.'),
          const SizedBox(height: 12),
          Container(
            key: const Key('speed-reader-preview'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Dieser Text zeigt, wie das Lesen aussieht. This text shows how reading looks.',
              style: TextStyle(
                fontFamily: fontFamilyOf(s.font),
                fontSize: s.size,
                height: s.lineHeight,
                letterSpacing: s.letterSpacing * s.size,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          ReadingSettingsSheet(settings: s, onChanged: (next) => places.reading = next),
        ],
      );
    },
  );
}

/// The reading speed the next document starts with, and the reference list.
class _Reading extends StatefulWidget {
  const _Reading(this.places);

  final Places? places;

  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading> {
  @override
  Widget build(BuildContext context) {
    final places = widget.places;
    final speed = places?.speed ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Speed: ${speed.toStringAsFixed(2)}×', style: Theme.of(context).textTheme.titleMedium),
        Slider(
          key: const Key('settings-speed'),
          value: speed,
          min: minSpeed,
          max: maxSpeed,
          divisions: ((maxSpeed - minSpeed) / 0.05).round(),
          label: '${speed.toStringAsFixed(2)}×',
          onChanged: places == null ? null : (value) => setState(() => places.speed = value),
        ),
        const Text('Applies from the next document you open; the open one keeps its speed.'),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('settings-stop-at-references'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Stop reading at the reference list'),
          subtitle: const Text('“References”, “Literatur”'),
          value: places?.stopAtReferences ?? false,
          onChanged: places == null ? null : (on) => setState(() => places.stopAtReferences = on),
        ),
      ],
    );
  }
}
