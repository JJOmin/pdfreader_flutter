import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync icon in the home screen's app bar (PLAN 7.5); it opens the Sync screen, where the
/// Desktops and Cloud screens used to be reached from two icons.
final syncButton = find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip?.startsWith('Sync:') ?? false),
  description: 'the sync icon',
);
