#!/bin/bash
# Copia i binari di libimobiledevice e le loro dipendenze dentro IMC.app,
# riscrivendo gli install name in modo che l'app funzioni anche su un Mac
# senza Homebrew.
#
# Uso: Scripts/bundle-tools.sh dist/IMC.app
set -euo pipefail

APP="${1:?Percorso di IMC.app richiesto}"
TOOLS_DIR="$APP/Contents/Resources/tools"
FW_DIR="$APP/Contents/Frameworks"
TOOLS=(idevice_id ideviceinfo idevicepair ideviceinstaller idevicename idevicediagnostics ipatool)

mkdir -p "$TOOLS_DIR" "$FW_DIR"

# Considera "da incorporare" solo le librerie non di sistema.
is_bundlable() {
    case "$1" in
        /opt/homebrew/*|/usr/local/*) return 0 ;;
        *) return 1 ;;
    esac
}

deps_of() {
    otool -L "$1" | tail -n +2 | awk '{print $1}'
}

# Xcode esegue le fasi di script con un PATH ridotto, quindi Homebrew va cercato
# esplicitamente invece di affidarsi a `command -v`.
find_tool() {
    local name="$1" dir
    for dir in /opt/homebrew/bin /usr/local/bin; do
        [ -x "$dir/$name" ] && { echo "$dir/$name"; return 0; }
    done
    command -v "$name" 2>/dev/null || true
}

copied_libs=()

already_copied() {
    local needle="$1"
    for lib in ${copied_libs+"${copied_libs[@]}"}; do
        [ "$lib" = "$needle" ] && return 0
    done
    return 1
}

# Copia ricorsivamente le dipendenze di un binario in Contents/Frameworks.
collect_deps() {
    local binary="$1"
    local dep base
    while IFS= read -r dep; do
        is_bundlable "$dep" || continue
        base="$(basename "$dep")"
        if ! already_copied "$base"; then
            copied_libs+=("$base")
            cp -L "$dep" "$FW_DIR/$base"
            chmod u+w "$FW_DIR/$base"
            install_name_tool -id "@loader_path/$base" "$FW_DIR/$base" 2>/dev/null || true
            collect_deps "$FW_DIR/$base"
        fi
    done < <(deps_of "$binary")
}

# 1. Copia i tool e raccoglie le dipendenze.
missing=()
for tool in "${TOOLS[@]}"; do
    src="$(find_tool "$tool")"
    if [ -z "$src" ]; then
        missing+=("$tool")
        continue
    fi
    cp -L "$src" "$TOOLS_DIR/$tool"
    chmod u+w "$TOOLS_DIR/$tool"
    collect_deps "$TOOLS_DIR/$tool"
done

# L'helper delle icone non esiste in Homebrew: si compila direttamente nel bundle.
if "$(dirname "$0")/build-icon-helper.sh" "$TOOLS_DIR/imc-icon"; then
    collect_deps "$TOOLS_DIR/imc-icon"
else
    echo "Attenzione: helper delle icone non compilato, le app installate mostreranno un segnaposto." >&2
fi

if [ ${#missing[@]} -gt 0 ]; then
    echo "Attenzione: tool non trovati nel PATH e non incorporati: ${missing[*]}" >&2
    echo "Installali con: brew install libimobiledevice ideviceinstaller" >&2
fi

# 2. Riscrive i riferimenti nei tool (Resources/tools -> ../../Frameworks).
for tool in "$TOOLS_DIR"/*; do
    [ -f "$tool" ] || continue
    while IFS= read -r dep; do
        is_bundlable "$dep" || continue
        install_name_tool -change "$dep" "@loader_path/../../Frameworks/$(basename "$dep")" "$tool"
    done < <(deps_of "$tool")
done

# 3. Riscrive i riferimenti fra le librerie stesse (stessa cartella).
for lib in "$FW_DIR"/*.dylib; do
    [ -f "$lib" ] || continue
    while IFS= read -r dep; do
        is_bundlable "$dep" || continue
        install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$lib"
    done < <(deps_of "$lib")
done

# 4. Su Apple silicon ogni binario modificato va rifirmato, anche ad-hoc.
for binary in "$TOOLS_DIR"/* "$FW_DIR"/*; do
    [ -f "$binary" ] || continue
    codesign --force --sign - --timestamp=none "$binary" >/dev/null 2>&1 || true
done

echo "Incorporati $(ls "$TOOLS_DIR" | wc -l | tr -d ' ') tool e $(ls "$FW_DIR" | wc -l | tr -d ' ') librerie."
