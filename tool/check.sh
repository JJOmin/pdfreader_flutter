#!/bin/sh
# The Mac's tool/check.ps1: analyze, format check, unit tests, through FVM. Stops at the first
# failing stage.
set -e
cd "$(dirname "$0")/.."

# On the Mac, `flutter test` does not load the PDFium that pdfium_dart's build hook downloaded:
# the hook leaves macOS to pdfium_flutter's XCFramework, which only an app links. Point the tests
# that open real PDFs at the downloaded library instead (pdfrxInitialize reads PDFIUM_PATH).
if [ -z "$PDFIUM_PATH" ]; then
  PDFIUM_PATH=$(find .dart_tool/hooks_runner build/native_assets -name libpdfium.dylib 2>/dev/null | head -n 1)
  [ -n "$PDFIUM_PATH" ] && export PDFIUM_PATH="$PWD/$PDFIUM_PATH"
fi

echo "== analyze"; fvm flutter analyze --fatal-infos || { echo "check failed at: analyze"; exit 1; }
echo "== format"; fvm dart format --output=none --set-exit-if-changed . || { echo "check failed at: format"; exit 1; }
echo "== test"; fvm flutter test || { echo "check failed at: test"; exit 1; }
echo "check passed"
