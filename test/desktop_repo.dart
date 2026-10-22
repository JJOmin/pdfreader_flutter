import 'dart:io';

/// The desktop's checkout beside this one: `../pdfreader` on the Windows PC, `../pdfReaderWindows`
/// on the Mac. Tests read its fixtures and golden files from there.
final String desktopRepo = [
  '../pdfreader',
  '../pdfReaderWindows',
].firstWhere((path) => Directory(path).existsSync(), orElse: () => '../pdfreader');
