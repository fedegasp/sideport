#!/bin/bash
# Compila IMC e assembla dist/IMC.app.
#
# Uso:
#   Scripts/build-app.sh              compila e incorpora i tool nel bundle
#   Scripts/build-app.sh --no-tools   usa i tool installati sul sistema (PATH/Homebrew)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/dist/IMC.app"
EMBED_TOOLS=1
[ "${1:-}" = "--no-tools" ] && EMBED_TOOLS=0

echo "==> Stringhe localizzate"
"$ROOT/Scripts/compile-strings.sh"

echo "==> Compilazione release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/IMC"
[ -f "$BINARY" ] || { echo "Binario non trovato: $BINARY" >&2; exit 1; }

echo "==> Assemblaggio del bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/IMC"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Risorse localizzate"
# Le stringhe dell'interfaccia stanno nel bundle di risorse del modulo, che
# SwiftPM lascia accanto all'eseguibile; quelle dell'Info.plist (copyright e
# nome del tipo di documento) vanno nelle .lproj del bundle dell'app.
cp -R "$BIN_DIR/IMC_IMC.bundle" "$APP/Contents/Resources/"
xcrun xcstringstool compile "$ROOT/Resources/InfoPlist.xcstrings" \
    --output-directory "$APP/Contents/Resources"

echo "==> Icona"
"$ROOT/Scripts/make-icon.sh"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [ "$EMBED_TOOLS" = "1" ]; then
    echo "==> Incorporamento di libimobiledevice"
    "$ROOT/Scripts/bundle-tools.sh" "$APP"
else
    # Senza tool incorporati l'helper resta collegato alla libimobiledevice di sistema.
    echo "==> Helper delle icone"
    "$ROOT/Scripts/build-icon-helper.sh" "$APP/Contents/Resources/tools/imc-icon" || \
        echo "Helper delle icone non compilato: le app installate mostreranno un segnaposto." >&2
fi

echo "==> Firma ad-hoc"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "Firma ad-hoc non riuscita: l'app funziona comunque in locale." >&2

echo
echo "Fatto: $APP"
echo "Avvia con: open \"$APP\""
