#!/bin/bash
# Compila l'helper sideport-icon, che legge le icone delle app dal dispositivo.
#
# Uso: Scripts/build-icon-helper.sh PERCORSO_ESEGUIBILE
#
# Si collega alla libimobiledevice di Homebrew; bundle-tools.sh poi ne copia
# le dipendenze nel bundle come per gli altri tool.
set -euo pipefail

OUTPUT="${1:?Percorso di destinazione richiesto}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/Helpers/sideport-icon"

# Xcode esegue le fasi di script con un PATH ridotto: cargo va cercato
# esplicitamente fra le installazioni note. Lo stesso vale per pkg-config, che
# pero' se lo cerca da solo build.rs.
CARGO=""
for candidate in "$HOME/.cargo/bin/cargo" /opt/homebrew/bin/cargo /usr/local/bin/cargo "$(command -v cargo 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { CARGO="$candidate"; break; }
done
if [ -z "$CARGO" ]; then
    echo "cargo non trovato: installa Rust da https://rustup.rs oppure con 'brew install rust'." >&2
    exit 1
fi

# Il crate non ha dipendenze esterne, quindi --locked compila anche offline.
"$CARGO" build --release --locked --manifest-path "$CRATE/Cargo.toml"

mkdir -p "$(dirname "$OUTPUT")"
cp "$CRATE/target/release/sideport-icon" "$OUTPUT"
chmod u+w "$OUTPUT"
