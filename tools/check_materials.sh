#!/usr/bin/env bash
# Fails when a committed .filamat, a package material or an example style,
# no longer matches its source. matc is deterministic, so recompiling and
# comparing bytes is a sound check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/tools/compile_materials.sh" "$TMP"

stale=()
for blob in "$TMP"/assets/materials/*.filamat \
    "$TMP"/example/assets/styles/*.filamat; do
    path="${blob#"$TMP"/}"
    cmp -s "$blob" "$ROOT/$path" || stale+=("$path")
done

if [ ${#stale[@]} -gt 0 ]; then
    echo "Stale materials: ${stale[*]}" >&2
    echo "Run ./tools/compile_materials.sh and commit the blobs." >&2
    exit 1
fi
echo "Materials match their sources."
