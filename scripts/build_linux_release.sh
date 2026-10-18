#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLUTTER="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  echo "error: flutter not found; set FLUTTER to the Flutter executable" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64 | amd64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "error: unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

VERSION="${VERSION:-$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml | head -n 1)}"
VERSION="${VERSION#v}"
if [ -z "$VERSION" ]; then
  echo "error: cannot determine version from pubspec.yaml" >&2
  exit 1
fi

echo "==> version $VERSION"
echo "==> flutter config --enable-linux-desktop"
"$FLUTTER" config --enable-linux-desktop >/dev/null

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> flutter build linux --release ($ARCH)"
"$FLUTTER" build linux --release

BUNDLE="build/linux/$ARCH/release/bundle"
if [ ! -x "$BUNDLE/faria2" ]; then
  echo "error: Linux bundle not found at $BUNDLE" >&2
  exit 1
fi

STAGE="dist/stage/faria2"
ARCHIVE="dist/faria2-$VERSION-linux-$ARCH.tar.gz"
rm -rf "dist/stage"
mkdir -p "$STAGE"
cp -a "$BUNDLE/." "$STAGE/"
cp LICENSE README.md "$STAGE/"
chmod +x "$STAGE/faria2"

rm -f "$ARCHIVE"
tar -C dist/stage -czf "$ARCHIVE" faria2
rm -rf "dist/stage"

echo "created $ARCHIVE"
du -h "$ARCHIVE"
