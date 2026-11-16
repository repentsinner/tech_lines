#!/usr/bin/env bash
# Compiles materials/*.mat into assets/materials/*.filamat for every
# backend the package ships on: Metal for macOS, OpenGL and Vulkan for
# Linux and Windows. Then builds each style in example/styles/ into
# example/assets/styles/ with tools/compile_style.sh, reading its
# parameters from the .params file beside it when there is one.
#
# With an argument, writes both trees under that directory instead of the
# repository, as tools/check_materials.sh does.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATC="${MATC:-$("$ROOT/tools/install_matc.sh")}"
OUT="${1:-$ROOT}"

mkdir -p "$OUT/assets/materials"
for mat in "$ROOT"/materials/*.mat; do
    name="$(basename "${mat%.mat}")"
    "$MATC" -a opengl -a metal -a vulkan \
        -o "$OUT/assets/materials/$name.filamat" "$mat"
done

for style in "$ROOT"/example/styles/*.fs; do
    name="$(basename "${style%.fs}")"
    params="${style%.fs}.params"
    args=()
    [ -f "$params" ] && args=(--params "$params")
    # ${args[@]+...} keeps an empty array from tripping set -u in bash 3.2.
    MATC="$MATC" "$ROOT/tools/compile_style.sh" ${args[@]+"${args[@]}"} \
        "$name" "$style" "$OUT/example/assets/styles"
done
