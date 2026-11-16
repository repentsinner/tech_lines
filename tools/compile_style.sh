#!/usr/bin/env bash
# Builds a consumer style (SPEC.md §spec:consumer-styles) into a body and an
# edge material from this package's line materials.
#
# Usage: tools/compile_style.sh [--params FILE] NAME STYLE OUT_DIR
#
#   NAME     the style's name, lower snake case
#   STYLE    a GLSL file that defines styleLine
#   FILE     the style's own parameters as matc parameter entries, such as
#            { type : float, name : fadeRadius, precision : high }
#   OUT_DIR  receives NAME_body.filamat and NAME_edge.filamat
#
# Each material is named "tech_lines <release> style:NAME pass:<pass>", which
# ScreenLineRenderer.loadStyle checks. Set MATC to use a matc other than the
# one tools/install_matc.sh installs; it must come from the Filament release
# in tools/filament_version.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "usage: $0 [--params FILE] NAME STYLE OUT_DIR" >&2
    exit 2
}

params=""
if [ "${1:-}" = "--params" ]; then
    [ $# -ge 2 ] || usage
    params="$2"
    shift 2
fi
[ $# -eq 3 ] || usage
name="$1"
style="$2"
out="$3"

if ! [[ "$name" =~ ^[a-z0-9_]+$ ]]; then
    echo "compile_style: style name \"$name\" must be lower snake case" \
        "(a-z, 0-9 and _)" >&2
    exit 2
fi

# Names of the parameters a material file declares.
declared_names() {
    sed -n '/parameters *: *\[/,/\]/p' "$1" |
        grep -o 'name *: *[A-Za-z_][A-Za-z0-9_]*' |
        sed 's/name *: *//'
}

# The style's entries on one line, comments dropped and a comma between each.
entries=""
if [ -n "$params" ]; then
    entries="$(sed 's://.*$::' "$params" | tr '\n' ' ' |
        sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/} *,* *{/}, {/g' \
            -e 's/^ *//' -e 's/[ ,]*$//')"
    clashes=()
    while read -r own; do
        [ -n "$own" ] || continue
        if declared_names "$ROOT/materials/screen_line_body.mat" |
            grep -qx "$own"; then
            clashes+=("$own")
        fi
    done < <(grep -o 'name *: *[A-Za-z_][A-Za-z0-9_]*' <<<"$entries" |
        sed 's/name *: *//')
    if [ ${#clashes[@]} -gt 0 ]; then
        echo "compile_style: ${clashes[*]} reuse parameter names the" \
            "package sets itself; rename them in $params" >&2
        exit 1
    fi
fi

release="$(sed -n 's/^version: *//p' "$ROOT/pubspec.yaml")"
MATC="${MATC:-$("$ROOT/tools/install_matc.sh")}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# matc resolves #include beside the material, so the stage sources and the
# style sit together in the build directory.
cp "$ROOT/materials/screen_line_vertex.vs" \
    "$ROOT/materials/screen_line_fragment.fs" "$TMP/"
cp "$style" "$TMP/screen_line_style.fs"

for pass in body edge; do
    src="$ROOT/materials/screen_line_$pass.mat"
    mat="$TMP/${name}_$pass.mat"
    stamp="tech_lines $release style:$name pass:$pass"
    awk -v stamp="$stamp" -v entries="$entries" '
        !named && /^ *name *: *ScreenLine[A-Za-z]*, *$/ {
            sub(/name *: *ScreenLine[A-Za-z]*/, "name : \"" stamp "\"")
            named = 1
        }
        { print }
        !listed && /parameters *: *\[/ {
            if (entries != "") print "        " entries ","
            listed = 1
        }
        END { if (!named || !listed) exit 1 }
    ' "$src" >"$mat" || {
        echo "compile_style: $src lacks its name or parameters line" >&2
        exit 1
    }
    "$MATC" -a opengl -a metal -a vulkan -o "$TMP/${name}_$pass.filamat" "$mat"
done

mkdir -p "$out"
mv "$TMP/${name}_body.filamat" "$TMP/${name}_edge.filamat" "$out/"
