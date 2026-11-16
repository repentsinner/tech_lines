#!/usr/bin/env bash
# Compiles materials/*.mat into assets/materials/*.filamat for every
# backend the package ships on: Metal for macOS, OpenGL and Vulkan for
# Linux and Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATC="${MATC:-$("$ROOT/tools/install_matc.sh")}"
OUT="${1:-$ROOT/assets/materials}"

mkdir -p "$OUT"
for mat in "$ROOT"/materials/*.mat; do
    name="$(basename "${mat%.mat}")"
    "$MATC" -a opengl -a metal -a vulkan -o "$OUT/$name.filamat" "$mat"
done
