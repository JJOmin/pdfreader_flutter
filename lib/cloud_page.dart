import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'library.dart';
import 'notes_store.dart';
import 'shared/download_plan.dart';
import 'store/cancellation.dart';
import 'desktop_link.dart' show phoneName;
import 'shared/sync_memo.dart';
import 'store/cloud_accounts.dart';
import 'store/memo_file.dart';
import 'store/store_sync.dart';

/// The user's own Nextcloud (ADR 3): sign in, the sync key, the documents the desktop
/// put there, and a sync of the ones on the phone.
class CloudPage extends StatefulWidget {
  const CloudPage({
    super.key,
    required this.accounts,
    required this.library,
    required this.notes,
    required this.device,
    this.memoFile,
  });

  /// What a sync remembers for the next one; without it the page remembers only while it is open.
  final MemoFile? memoFile;

  final CloudAccounts accounts;
  final Library library;
  final NotesStore notes;

  /// This phone's id, which names its place in the store.
  final String device;

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  CloudStatus? _status;
  final _server = TextEditingController();
  final _key = TextEditingController();
  Cancellation? _signingIn;
  String? _message;
  bool _error = false;
  bool _busy = false;
  double? _progress;
  CloudListing? _listing;

  /// What the phone holds of each document in the cloud, or null where it holds nothing.
  final _local = <String, LibraryDocument?>{};
  StoreSync? _sync;

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

  SyncMemo? _memo;

  Future<StoreSync> _engine() async {
    final memo = _memo ??= await widget.memoFile?.load() ?? SyncMemo();
    return _sync ??= StoreSync(
      await widget.accounts.store(),
      await widget.accounts.key(),
      widget.library,
      widget.notes,
      widget.device,
      memo: memo,
      name: await phoneName(),
    );
  }

  /// A new account or key: the memo describes another store, so the next sync walks everything.
  Future<void> _forget() async {
    _sync = null;
    _memo = null;
    await widget.memoFile?.clear();
  }

  Future<void> _refresh() async {
    final status = await widget.accounts.status();
    if (!mounted) return;
    setState(() => _status = status);
    if (status.backend != CloudBackend.none && status.hasKey) await _list();
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

  Future<void> _list() async {
    try {
      final listing = await (await _engine()).documents();
      for (final doc in listing.documents) {
        _local[doc.manifest.docId] = await widget.library.read(
          Directory('${widget.library.root.path}/${doc.manifest.docId}'),
        );
      }
      if (mounted) setState(() => _listing = listing);
    } catch (error) {
      _say('$error', error: true);
    }
  }

  Future<void> _signIn(Future<CloudStatus> Function(Cancellation) connect, String waiting) async {
    final cancel = _signingIn = Cancellation();
    await _run(() async {
      _say(waiting);
      final status = await connect(cancel);
      await _forget();
      if (mounted) setState(() => _status = status);
      _say('Signed in as ${status.account}');
      if (status.hasKey) await _list();
    });
    _signingIn = null;
  }

  Future<void> _saveKey() async {
    await _run(() async {
      final status = await widget.accounts.setKey(_key.text);
      _key.clear();
      await _forget();
      if (mounted) setState(() => _status = status);
      _say('The key is saved on this phone.');
      if (status.backend != CloudBackend.none) await _list();
    });
  }

  Future<void> _download(CloudDocument doc) async {
    await _run(() async {
      final engine = await _engine();
      await engine.download(doc, (p) {
        if (mounted) setState(() => _progress = p.total == 0 ? null : p.done / p.total);
      });
      _say('${doc.manifest.name} is on the phone.');
      await _list();
    });
  }

  Future<void> _syncNow() async {
    await _run(() async {
      // The button walks the whole store; the automatic sync of step 7.3 asks the journals instead.
      final summary = await (await _engine()).sync((p) {
        if (mounted) setState(() => _progress = p.total == 0 ? null : p.done / p.total);
      }, full: true);
      await widget.memoFile?.save(_memo!);
      final parts = [
        if (summary.updated > 0) '${summary.updated} documents updated',
        if (summary.notesChanged > 0) 'marks changed in ${summary.notesChanged}',
        if (summary.unreadable > 0) '${summary.unreadable} files need the same sync key as the desktop',
      ];
      _say(parts.isEmpty ? 'Everything is up to date.' : parts.join('; '), error: summary.unreadable > 0);
      await _list();
    });
  }

  Future<void> _signOut() async {
    final status = await widget.accounts.disconnect();
    await _forget();
    if (!mounted) return;
    setState(() {
      _status = status;
      _listing = null;
    });
    _say('Signed out. The files in the cloud are kept.');
  }

  String _size(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    final connected = status != null && status.backend != CloudBackend.none;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                Expanded(child: Text('In your cloud', style: theme.textTheme.titleSmall)),
                FilledButton.tonal(
                  key: const Key('sync-now'),
                  onPressed: _busy ? null : _syncNow,
                  child: const Text('Sync now'),
                ),
              ],
            ),
            if (_listing != null && _listing!.documents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing here yet. On the desktop, open Phone, sign in under Sync between devices, and press Sync now.',
                ),
              ),
            for (final doc in _listing?.documents ?? const <CloudDocument>[])
              ListTile(
                key: Key('doc-${doc.manifest.name}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.record_voice_over),
                title: Text(doc.manifest.name),
                subtitle: Text('${doc.manifest.pages} pages, ${_size(doc.manifest.bytes)}'),
                trailing: isCurrent(doc.manifest, _local[doc.manifest.docId]?.manifest)
                    ? const Chip(label: Text('On this phone'))
                    : FilledButton(
                        key: Key('download-${doc.manifest.name}'),
                        onPressed: _busy ? null : () => _download(doc),
                        child: Text(_local[doc.manifest.docId] == null ? 'Download' : 'Update'),
                      ),
              ),
            if ((_listing?.unreadable ?? 0) > 0)
              Text(
                '${_listing!.unreadable} documents cannot be opened with this key.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ],
      ),
    );
  }
}
