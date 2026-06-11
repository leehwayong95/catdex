#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
APP_TARGET_DIR="$HOME/Applications"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

zshrc_has_local_bin() {
    [[ -f "$ZSHRC" ]] && awk '
        index($0, ".local/bin") && $0 !~ /^[[:space:]]*#/ { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$ZSHRC"
}

ensure_zsh_path() {
    if zshrc_has_local_bin; then
        return
    fi

    mkdir -p "$(dirname "$ZSHRC")"
    cat >> "$ZSHRC" <<'ZSHRC'

# Catdex local executables
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
ZSHRC
}

cd "$ROOT_DIR"
swift build -c release --product catdex
APP_PATH="$($ROOT_DIR/scripts/build-app.sh)"

mkdir -p "$BIN_DIR" "$APP_TARGET_DIR"
TMP_CATDEX="$BIN_DIR/.catdex.tmp.$$"
cp "$ROOT_DIR/.build/release/catdex" "$TMP_CATDEX"
chmod 755 "$TMP_CATDEX"
mv -f "$TMP_CATDEX" "$BIN_DIR/catdex"
rm -rf "$APP_TARGET_DIR/CatdexMenu.app"
cp -R "$APP_PATH" "$APP_TARGET_DIR/CatdexMenu.app"
ensure_zsh_path

cat <<MSG
Installed:
  $BIN_DIR/catdex
  $APP_TARGET_DIR/CatdexMenu.app

PATH configured in:
  $ZSHRC
MSG

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    cat <<MSG

To use catdex in this already-open terminal, run:
  source "$ZSHRC"

New zsh terminals can run:
  catdex
MSG
else
    cat <<MSG

You can run:
  catdex
MSG
fi
