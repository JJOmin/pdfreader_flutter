import 'package:flutter/material.dart';

import 'cloud_section.dart';
import 'desktop_link.dart';
import 'desktops_section.dart';
import 'places.dart';
import 'sync_controller.dart';

/// The Settings tab (PLAN 9.2): everything that connects this phone to others (7.5), the Nextcloud
/// account and key and the computers paired over Wi-Fi, then the reading options.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, this.sync, this.desktops, this.places});

  /// Null in widget tests, where there is no sync.
  final SyncController? sync;
  final DesktopStore? desktops;
  final Places? places;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    final sync = widget.sync;
    final desktops = widget.desktops;
    final places = widget.places;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (sync != null) ...[
            Text('Nextcloud', style: title),
            const SizedBox(height: 8),
            CloudSection(sync: sync),
            const Divider(height: 32),
          ],
          if (sync != null && desktops != null) ...[
            Text('Computers', style: title),
            const SizedBox(height: 8),
            DesktopsSection(store: desktops, library: sync.library, notes: sync.notes),
            const Divider(height: 32),
          ],
          Text('Reading', style: title),
          SwitchListTile(
            key: const Key('settings-stop-at-references'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop reading at the reference list'),
            subtitle: const Text('“References”, “Literatur”'),
            value: places?.stopAtReferences ?? false,
            onChanged: places == null ? null : (on) => setState(() => places.stopAtReferences = on),
          ),
        ],
      ),
    );
  }
}
