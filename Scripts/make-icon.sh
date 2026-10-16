#!/bin/bash
# Genera Resources/AppIcon.icns da Scripts/make-icon.swift.
# Rigenera solo se l'icns manca o e' piu' vecchio dello script sorgente.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SOURCE="$ROOT/Scripts/make-icon.swift"
OUTPUT="$ROOT/Resources/AppIcon.icns"

if [ -f "$OUTPUT" ] && [ "$OUTPUT" -nt "$SOURCE" ] && [ "${1:-}" != "--force" ]; then
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift "$SOURCE" "$WORK/icon_1024.png"
for size in 16 32 64 128 256 512; do
    sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "Icona generata: $OUTPUT"
