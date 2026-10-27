#!/bin/bash
# Compila il catalogo di stringhe nei .strings/.stringsdict che finiscono nel
# bundle del modulo.
#
# Xcode compila i .xcstrings da solo, `swift build` no: copia il catalogo cosi'
# com'e', e Foundation non lo sa leggere. I file generati sono versionati, quindi
# dopo ogni modifica a Localizable.xcstrings va rilanciato questo script.
set -euo pipefail

cd "$(dirname "$0")/.."
RESOURCES="$PWD/Sources/Sideport/Resources"

rm -rf "$RESOURCES"/*.lproj
xcrun xcstringstool compile "$RESOURCES/Localizable.xcstrings" --output-directory "$RESOURCES"

echo "Lingue compilate:" "$(cd "$RESOURCES" && echo *.lproj)"
