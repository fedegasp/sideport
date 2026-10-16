#!/bin/bash
# Compila l'helper imc-icon, che legge le icone delle app dal dispositivo.
#
# Uso: Scripts/build-icon-helper.sh PERCORSO_ESEGUIBILE
#
# Si collega alla libimobiledevice di Homebrew; bundle-tools.sh poi ne copia
# le dipendenze nel bundle come per gli altri tool.
set -euo pipefail

OUTPUT="${1:?Percorso di destinazione richiesto}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Helpers/imc-icon/main.c"

# Xcode esegue le fasi di script con un PATH ridotto: pkg-config va cercato
# esplicitamente fra le installazioni Homebrew note.
PKG_CONFIG=""
for candidate in /opt/homebrew/bin/pkg-config /usr/local/bin/pkg-config "$(command -v pkg-config 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { PKG_CONFIG="$candidate"; break; }
done
if [ -z "$PKG_CONFIG" ]; then
    echo "pkg-config non trovato: installalo con 'brew install pkg-config'." >&2
    exit 1
fi

if ! FLAGS="$("$PKG_CONFIG" --cflags --libs libimobiledevice-1.0)"; then
    echo "libimobiledevice non trovata: installala con 'brew install libimobiledevice'." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
# shellcheck disable=SC2086
xcrun clang -O2 -Wall -Wextra \
    "$SOURCE" $FLAGS -o "$OUTPUT"
