import 'dart:io';

/// The desktop's checkout beside this one: `../pdfreader` on the Windows PC, `../pdfReaderWindows`
/// on the Mac. A few tests read its files and golden files from there; where it does not exist, as
/// on the CI, they are skipped (`skipWithout`). `DESKTOP_REPO` names another place, or a place that
/// is not there, to try that.
final String desktopRepo =
    Platform.environment['DESKTOP_REPO'] ??
    [
      '../pdfreader',
      '../pdfReaderWindows',
    ].firstWhere((path) => Directory(path).existsSync(), orElse: () => '../pdfreader');

/// The desktop's synthetic sample PDF, copied here so that the tests that need it run anywhere. The
/// desktop's `npm run fixtures` makes it, and the golden files need exactly these bytes: when it is
/// made again there, copy it here (`fixtures_test.dart` says so when the two differ).
const sampleFixture = 'test/fixtures/sample.pdf';

/// A reason to skip a test that needs a file of the desktop's checkout, or false when it is there.
Object skipWithout(String path) =>
    File(path).existsSync() ? false : 'needs $path: the desktop checkout is not beside this one';
