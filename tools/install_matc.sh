#!/usr/bin/env bash
# Installs matc from the Filament release in tools/filament_version into
# .tools/filament-<version>/, and prints the path of the matc binary.
#
# The release must match the Filament the pinned thermion_dart links,
# or the runtime cannot parse the compiled .filamat blobs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/tools/filament_version")"
DIR="$ROOT/.tools/filament-$VERSION"
MATC="$DIR/bin/matc"

if [ ! -x "$MATC" ]; then
    case "$(uname -s)" in
        Linux) SUFFIX=linux.tgz ;;
        Darwin) SUFFIX=mac.tgz ;;
        *) echo "install_matc: unsupported platform $(uname -s)" >&2; exit 1 ;;
    esac
    URL="https://github.com/google/filament/releases/download/v$VERSION/filament-v$VERSION-$SUFFIX"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    curl -fsSL -o "$TMP/filament.tgz" "$URL"
    tar -xzf "$TMP/filament.tgz" -C "$TMP"
    mkdir -p "$DIR/bin"
    cp "$(find "$TMP" -type f -name matc -path '*/bin/*' | head -1)" "$MATC"
    chmod +x "$MATC"
fi

echo "$MATC"
