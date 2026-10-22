import 'package:flutter/material.dart';

import 'cloud_section.dart';
import 'desktop_link.dart';
import 'desktops_section.dart';
import 'sync_controller.dart';

/// The one place for everything that connects this phone to others (PLAN 7.5): the Nextcloud account
/// and key, and the computers it is paired with over Wi-Fi. The documents themselves are on the home
/// screen.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key, required this.sync, required this.desktops});

  final SyncController sync;
  final DesktopStore desktops;

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nextcloud', style: title),
          const SizedBox(height: 8),
          CloudSection(sync: sync),
          const Divider(height: 32),
          Text('Computers', style: title),
          const SizedBox(height: 8),
          DesktopsSection(store: desktops, library: sync.library, notes: sync.notes),
        ],
      ),
    );
  }
}
