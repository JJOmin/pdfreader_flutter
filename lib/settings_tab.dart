import 'package:flutter/material.dart';

import 'app_settings_store.dart';
import 'cloud_section.dart';
import 'desktop_link.dart';
import 'desktops_section.dart';
import 'places.dart';
import 'shared/app_settings.dart';
import 'shared/settings.dart' show maxSpeed, minSpeed;
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
    ThemeChoice.dark: 'Dark',
  };

  void _open(BuildContext context, String title, Widget body) => Navigator.of(context).push(
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
          builder: (context, choice, _) => ListTile(
            key: const Key('settings-appearance'),
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            subtitle: Text(_themeNames[choice]!),
            onTap: () => _open(context, 'Appearance', _Appearance(appSettings)),
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

/// Light, dark, or whatever the system says.
class _Appearance extends StatelessWidget {
  const _Appearance(this.settings);

  final AppSettingsStore settings;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: settings,
    builder: (context, choice, _) => RadioGroup<ThemeChoice>(
      groupValue: choice,
      onChanged: (c) => settings.choose(c ?? ThemeChoice.system),
      child: Column(
        children: [
          for (final c in ThemeChoice.values)
            RadioListTile<ThemeChoice>(
              key: Key('theme-${c.name}'),
              value: c,
              title: Text(SettingsTab._themeNames[c]!),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'The reading view has its own light, sepia and dark choice, under Text settings in the reader’s menu.',
            ),
          ),
        ],
      ),
    ),
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
