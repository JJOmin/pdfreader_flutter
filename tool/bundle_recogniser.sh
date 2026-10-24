#!/bin/sh
# Puts the speech recogniser into assets/recogniser, from where the build takes it into the app
# (ADR 7). Run before `flutter build`; the release and CI workflows do.
#   sh tool/bundle_recogniser.sh [<desktop models folder>]
# Taken from the desktop's models folder when it has the model (no download), else downloaded from
# sherpa-onnx's release, the address the desktop's models.json names. Either way the two files must
# match the checksums below, so a build never carries a model nobody checked.
set -eu
cd "$(dirname "$0")/.."
name=sherpa-onnx-nemo-fast-conformer-ctc-en-de-es-fr-14288-int8
url=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$name.tar.bz2
out=assets/recogniser
sums="85451f03e004d607f86f4d6291ca55a8ca984d7e32dedc828cebe7fe61447511  model.int8.onnx
29effa220ddd8fcae96d2d6c78c2e24de4cd9dfaa4ceb86d54dc3d22259c1f93  tokens.txt"

checked() { (cd "$1" && echo "$sums" | shasum -a 256 -c --status 2>/dev/null); }

if checked "$out"; then
  echo "The recogniser is already in $out."
  exit 0
fi

# The desktop checkout is ../pdfreader on Windows and ../pdfReaderWindows on the Mac.
for from in "${1:-}" ../pdfreader/models ../pdfReaderWindows/models; do
  if [ -n "$from" ] && [ -d "$from/$name" ] && checked "$from/$name"; then
    cp "$from/$name/model.int8.onnx" "$from/$name/tokens.txt" "$out/"
    echo "Copied the recogniser from $from."
    exit 0
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading the recogniser (about 120 MB)."
curl --fail --location --retry 4 --silent --show-error "$url" -o "$tmp/model.tar.bz2"
# All of it: the archive names its files ./<name>/..., which GNU tar does not match to <name>/...
tar -xjf "$tmp/model.tar.bz2" -C "$tmp"
if ! checked "$tmp/$name"; then
  echo "The downloaded recogniser does not match its checksums: not used." >&2
  exit 1
fi
cp "$tmp/$name/model.int8.onnx" "$tmp/$name/tokens.txt" "$out/"
echo "Downloaded the recogniser into $out."
