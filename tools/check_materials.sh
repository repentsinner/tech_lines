#!/usr/bin/env bash
# Fails when a committed .filamat no longer matches its source. matc is
# deterministic, so recompiling and comparing bytes is a sound check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/tools/compile_materials.sh" "$TMP"

stale=()
for blob in "$TMP"/*.filamat; do
    name="$(basename "$blob")"
    cmp -s "$blob" "$ROOT/assets/materials/$name" || stale+=("$name")
done

if [ ${#stale[@]} -gt 0 ]; then
    echo "Stale materials: ${stale[*]}" >&2
    echo "Run ./tools/compile_materials.sh and commit assets/materials." >&2
    exit 1
fi
echo "Materials match their sources."
