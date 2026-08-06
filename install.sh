#!/bin/bash
# Build fujimm and put it on your PATH.
set -euo pipefail

cd "$(dirname "$0")"

echo "Building fujimm (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/fujimm"
[ -x "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

# Prefer a directory we can write to without sudo.
if [ -w /usr/local/bin ] 2>/dev/null; then
    DEST=/usr/local/bin
elif [ -d "$HOME/.local/bin" ]; then
    DEST="$HOME/.local/bin"
else
    DEST=/usr/local/bin
fi

if [ -w "$DEST" ] 2>/dev/null || mkdir -p "$DEST" 2>/dev/null && [ -w "$DEST" ]; then
    install -m 755 "$BIN" "$DEST/fujimm"
else
    echo "Installing to $DEST needs administrator rights."
    sudo install -d -m 755 "$DEST"
    sudo install -m 755 "$BIN" "$DEST/fujimm"
fi

echo "Installed: $DEST/fujimm"

case ":$PATH:" in
    *":$DEST:"*) ;;
    *)
        echo
        echo "$DEST is not on your PATH. Add it with:"
        echo "  echo 'export PATH=\"$DEST:\$PATH\"' >> ~/.zshrc && exec zsh"
        ;;
esac

echo
echo "Try it:  fujimm --dry-run"
