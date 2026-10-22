import 'dart:async';

import 'package:flutter/material.dart';

import 'store/cancellation.dart';
import 'store/cloud_accounts.dart';
import 'sync_controller.dart';

/// The user's own Nextcloud (ADR 3) on the Sync screen: sign in, the sync key, and a full sync. The
/// documents it holds are listed on the home screen, with the rest.
class CloudSection extends StatefulWidget {
  const CloudSection({super.key, required this.sync});

  /// Owns the engine and the syncs; this section signs in, sets the key and asks for a sync.
  final SyncController sync;

  CloudAccounts get accounts => sync.accounts;

  @override
  State<CloudSection> createState() => _CloudSectionState();
}

class _CloudSectionState extends State<CloudSection> {
  CloudStatus? _status;
  final _server = TextEditingController();
  final _key = TextEditingController();
  Cancellation? _signingIn;
  String? _message;
  bool _error = false;
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _signingIn?.cancel();
    _server.dispose();
    _key.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = message;
        _error = error;
      });
    }
  }

  Future<void> _refresh() async {
    final status = await widget.accounts.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// Runs something that talks to the network, with one message for how it ended.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
      _progress = null;
    });
    try {
      await action();
    } on CancelledException {
      _say('Cancelled.');
    } catch (error) {
      _say('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn(Future<CloudStatus> Function(Cancellation) connect, String waiting) async {
    final cancel = _signingIn = Cancellation();
    await _run(() async {
      _say(waiting);
      final status = await connect(cancel);
      await widget.sync.forget();
      if (mounted) setState(() => _status = status);
      _say('Signed in as ${status.account}');
      if (status.hasKey) await _walk();
    });
    _signingIn = null;
  }

  Future<void> _saveKey() async {
    await _run(() async {
      final status = await widget.accounts.setKey(_key.text);
      _key.clear();
      await widget.sync.forget();
      if (mounted) setState(() => _status = status);
      _say('The key is saved on this phone.');
      if (status.backend != CloudBackend.none) await _walk();
    });
  }

  /// Walks the whole store, which also fills the home screen's list of what is in the cloud.
  Future<void> _walk() async {
    // The button walks the whole store; the automatic sync asks the journals instead.
    final summary = await widget.sync.sync(
      full: true,
      progress: (p) {
        if (mounted) setState(() => _progress = p.total == 0 ? null : p.done / p.total);
      },
    );
    if (summary == null) return _say('Sign in and set the sync key first.', error: true);
    final parts = [
      if (summary.updated > 0) '${summary.updated} documents updated',
      if (summary.notesChanged > 0) 'marks changed in ${summary.notesChanged}',
      if (summary.unreadable > 0) '${summary.unreadable} files need the same sync key as the desktop',
    ];
    _say(parts.isEmpty ? 'Everything is up to date.' : parts.join('; '), error: summary.unreadable > 0);
  }

  Future<void> _syncNow() => _run(_walk);

  Future<void> _signOut() async {
    final status = await widget.accounts.disconnect();
    await widget.sync.forget();
    if (!mounted) return;
    setState(() {
      _status = status;
    });
    _say('Signed out. The files in the cloud are kept.');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    final connected = status != null && status.backend != CloudBackend.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) LinearProgressIndicator(value: _progress),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _message!,
              key: const Key('cloud-status'),
              style: TextStyle(color: _error ? theme.colorScheme.error : null),
            ),
          ),
        if (status == null) const Center(child: CircularProgressIndicator()),
        if (status != null && !connected) ...[
          Text('Sign in to the cloud that holds your documents', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            key: const Key('cloud-server'),
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Nextcloud address',
              hintText: 'https://cloud.example.com',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('sign-in-nextcloud'),
              onPressed: _busy
                  ? null
                  : () => _signIn(
                      (c) => widget.accounts.connectNextcloud(_server.text, c),
                      'Approve this app in your browser…',
                    ),
              child: const Text('Sign in to Nextcloud'),
            ),
          ),
          if (_busy && _signingIn != null)
            TextButton(
              key: const Key('cancel-sign-in'),
              onPressed: () => _signingIn?.cancel(),
              child: const Text('Cancel sign-in'),
            ),
        ],
        if (connected) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_done),
            title: Text('Signed in as ${status.account}'),
            trailing: TextButton(
              key: const Key('sign-out'),
              onPressed: _busy ? null : _signOut,
              child: const Text('Sign out'),
            ),
          ),
        ],
        if (status != null) ...[
          const Divider(),
          Text('Sync key', style: theme.textTheme.titleSmall),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              status.hasKey ? 'A key is saved. Enter another to replace it.' : 'The key that scrambles the files. Copy it from the desktop’s Phone dialog, under Sync key. Without it nothing in the cloud can be read.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextField(
            key: const Key('cloud-key'),
            controller: _key,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: 'xxxxxxxx-xxxxxxxx-…'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('save-key'),
              onPressed: _busy ? null : _saveKey,
              child: const Text('Use this key'),
            ),
          ),
        ],
        if (connected && status.hasKey) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.sync.lastError ?? 'Syncs by itself while the app is open.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              FilledButton.tonal(
                key: const Key('sync-now'),
                onPressed: _busy ? null : _syncNow,
                child: const Text('Refresh everything'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
