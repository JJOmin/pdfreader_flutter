import 'dart:async';

import 'package:flutter/material.dart';

import 'desktop_link.dart';
import 'library.dart';
import 'shared/pairing.dart';

/// Desktops on the network and the ones this phone paired with (PLAN steps 5.3 and 5.4).
class DesktopsPage extends StatefulWidget {
  const DesktopsPage({super.key, required this.store, required this.library});

  final DesktopStore store;
  final Library library;

  @override
  State<DesktopsPage> createState() => _DesktopsPageState();
}

class _DesktopsPageState extends State<DesktopsPage> {
  final _found = <String, FoundDesktop>{};
  StreamSubscription<FoundDesktop>? _listening;
  String? _status;
  bool _syncing = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _listening = discoverDesktops().listen((desktop) {
      if (_found[desktop.host] != desktop) setState(() => _found[desktop.host] = desktop);
    }, onError: (Object error) => setState(() => _status = 'Cannot listen for desktops: $error'));
  }

  @override
  void dispose() {
    unawaited(_listening?.cancel());
    super.dispose();
  }

  /// The desktop where it was last heard: a home router may have given it a new address.
  PairedDesktop _current(PairedDesktop desktop) {
    for (final found in _found.values) {
      if (found.name == desktop.name) return desktop.at(found.host, found.port);
    }
    return desktop;
  }

  Future<void> _pair(String host, int port, String name) async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _CodeDialog(name: name),
    );
    if (code == null || !mounted) return;
    setState(() => _status = 'Accept on $name to pair');
    try {
      final desktop = await pair(widget.store, host, port, code);
      if (mounted) setState(() => _status = 'Paired with ${desktop.name}');
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    }
  }

  Future<void> _typeAddress() async {
    final typed = await showDialog<String>(context: context, builder: (_) => const _AddressDialog());
    if (typed == null) return;
    final parts = typed.trim().split(':');
    final port = parts.length > 1 ? int.tryParse(parts[1]) : desktopPort;
    if (parts.first.isEmpty || port == null) {
      setState(() => _status = 'Type an address such as 192.168.1.20:$desktopPort');
      return;
    }
    await _pair(parts.first, port, parts.first);
  }

  Future<void> _sync(PairedDesktop paired) async {
    final desktop = _current(paired);
    setState(() {
      _syncing = true;
      _progress = null;
      _status = 'Asking ${desktop.name}';
    });
    try {
      final result = await syncFrom(desktop, widget.library, (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.total == 0 ? null : p.done / p.total;
          _status = 'Fetching ${p.document}: ${p.done} of ${p.total}';
        });
      });
      if (desktop.host != paired.host || desktop.port != paired.port) await widget.store.remember(desktop);
      if (!mounted) return;
      setState(
        () => _status = result.files == 0
            ? 'Everything from ${desktop.name} is here already'
            : '${result.documents} documents from ${desktop.name}, '
                  '${result.files} files, ${(result.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
      );
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _forget(PairedDesktop desktop) async {
    await widget.store.forget(desktop);
    setState(() => _status = 'Forgot ${desktop.name}');
  }

  @override
  Widget build(BuildContext context) {
    final paired = widget.store.desktops;
    final pairedNames = {for (final d in paired) d.name};
    final unpaired = _found.values.where((f) => !pairedNames.contains(f.name)).toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Desktops')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_syncing) LinearProgressIndicator(value: _progress),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_status!, key: const Key('desktop-status')),
            ),
          if (paired.isNotEmpty) Text('Paired', style: theme.textTheme.titleSmall),
          for (final desktop in paired)
            ListTile(
              leading: const Icon(Icons.computer),
              title: Text(desktop.name),
              subtitle: Text('${_current(desktop).host}:${_current(desktop).port}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('sync-${desktop.name}'),
                    icon: const Icon(Icons.sync),
                    tooltip: 'Fetch what ${desktop.name} prepared',
                    onPressed: _syncing ? null : () => _sync(desktop),
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Forget ${desktop.name}',
                    onPressed: _syncing ? null : () => _forget(desktop),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('On this network', style: theme.textTheme.titleSmall),
          if (unpaired.isEmpty)
            const ListTile(
              leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('Looking for desktops with phone sync switched on'),
            ),
          for (final found in unpaired)
            ListTile(
              key: Key('found-${found.name}'),
              leading: const Icon(Icons.computer_outlined),
              title: Text(found.name),
              subtitle: Text('${found.host}:${found.port}'),
              onTap: () => _pair(found.host, found.port, found.name),
            ),
          TextButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Type an address'),
            onPressed: _typeAddress,
          ),
        ],
      ),
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.name});

  final String name;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Pair with ${widget.name}'),
    content: TextField(
      key: const Key('code'),
      controller: _code,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Code from the desktop’s Phone dialog',
        hintText: 'XXXX-XXXX-XXXX',
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('pair'),
        onPressed: normalizeCode(_code.text) == null ? null : () => Navigator.pop(context, _code.text),
        child: const Text('Pair'),
      ),
    ],
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Desktop address'),
    content: TextField(
      controller: _address,
      autofocus: true,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(hintText: '192.168.1.20:$desktopPort'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _address.text), child: const Text('Next')),
    ],
  );
}
