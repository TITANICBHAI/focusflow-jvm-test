#!/usr/bin/env bash
# FocusFlow Linux installer
# Usage: curl -fsSL https://raw.githubusercontent.com/TITANICBHAI/FocusFlow-jvm-Test/main/install.sh | bash
set -euo pipefail

REPO="TITANICBHAI/FocusFlow-jvm-Test"
INSTALL_DIR="$HOME/.local/share/focusflow"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

# ── Helpers ────────────────────────────────────────────────────────────────────
info()  { echo -e "\033[1;34m[focusflow]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[focusflow]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[focusflow]\033[0m $*"; }
die()   { echo -e "\033[1;31m[focusflow]\033[0m $*" >&2; exit 1; }

need() { command -v "$1" &>/dev/null || die "Required tool not found: $1. Please install it first."; }
need curl
need grep

# ── Detect distro ──────────────────────────────────────────────────────────────
PKG_TYPE=""
if command -v dpkg &>/dev/null; then
  PKG_TYPE="deb"
elif command -v rpm &>/dev/null; then
  PKG_TYPE="rpm"
else
  PKG_TYPE="appimage"
fi

info "Detected package type: $PKG_TYPE"

# ── Fetch latest release ───────────────────────────────────────────────────────
info "Fetching latest release from GitHub..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
[ -z "$VERSION" ] && die "Could not determine latest release version."
info "Latest release: $VERSION"

# ── Find the right asset ───────────────────────────────────────────────────────
case "$PKG_TYPE" in
  deb)
    ASSET_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.deb"' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    ;;
  rpm)
    ASSET_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.rpm"' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    ;;
  appimage)
    ASSET_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.AppImage"' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    ;;
esac

[ -z "$ASSET_URL" ] && die "No $PKG_TYPE asset found in release $VERSION. Try again after the release assets are uploaded."

FILENAME=$(basename "$ASSET_URL")
TMPFILE="/tmp/$FILENAME"

# ── Download ───────────────────────────────────────────────────────────────────
info "Downloading $FILENAME..."
curl -fsSL --progress-bar -o "$TMPFILE" "$ASSET_URL"

# ── Install ────────────────────────────────────────────────────────────────────
case "$PKG_TYPE" in
  deb)
    info "Installing .deb package (requires sudo)..."
    sudo dpkg -i "$TMPFILE" || sudo apt-get install -f -y
    ok "FocusFlow $VERSION installed. Run: focusflow"
    ;;
  rpm)
    info "Installing .rpm package (requires sudo)..."
    if command -v dnf &>/dev/null; then
      sudo dnf install -y "$TMPFILE"
    else
      sudo rpm -U --force "$TMPFILE"
    fi
    ok "FocusFlow $VERSION installed. Run: focusflow"
    ;;
  appimage)
    info "Installing AppImage to $INSTALL_DIR ..."
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR"
    cp "$TMPFILE" "$INSTALL_DIR/FocusFlow.AppImage"
    chmod +x "$INSTALL_DIR/FocusFlow.AppImage"

    # Launcher shim
    cat > "$BIN_DIR/focusflow" <<SHIM
#!/usr/bin/env bash
exec "$INSTALL_DIR/FocusFlow.AppImage" "\$@"
SHIM
    chmod +x "$BIN_DIR/focusflow"

    # .desktop file
    cat > "$DESKTOP_DIR/focusflow.desktop" <<DESKTOP
[Desktop Entry]
Name=FocusFlow
Comment=Focus & productivity app with real app blocking
Exec=$INSTALL_DIR/FocusFlow.AppImage
Icon=$INSTALL_DIR/focusflow.png
Type=Application
Categories=Utility;
StartupNotify=true
DESKTOP
    chmod +x "$DESKTOP_DIR/focusflow.desktop"

    # Try to extract icon from AppImage for the desktop entry
    if "$INSTALL_DIR/FocusFlow.AppImage" --appimage-extract usr/share/pixmaps/focusflow.png &>/dev/null; then
      cp squashfs-root/usr/share/pixmaps/focusflow.png "$INSTALL_DIR/focusflow.png" 2>/dev/null || true
      rm -rf squashfs-root
    fi

    # Add ~/.local/bin to PATH hint
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
      warn "$BIN_DIR is not in your PATH."
      warn "Add this to your ~/.bashrc or ~/.zshrc:"
      warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi

    ok "FocusFlow $VERSION installed."
    ok "Launch from your app menu, or run: focusflow"
    ;;
esac

# ── Optional deps reminder ─────────────────────────────────────────────────────
if [ "$PKG_TYPE" = "appimage" ]; then
  echo ""
  info "Optional tools for full feature coverage:"
  command -v xdotool  &>/dev/null || warn "  xdotool missing  → install: sudo apt install xdotool   (window focus detection on X11)"
  command -v wmctrl   &>/dev/null || warn "  wmctrl missing   → install: sudo apt install wmctrl    (Wayland fallback)"
  command -v notify-send &>/dev/null || warn "  notify-send missing → install: sudo apt install libnotify-bin (desktop notifications)"
fi

rm -f "$TMPFILE"
ok "Done."
