#!/usr/bin/env bash
set -euo pipefail

PURGE=false
for arg in "$@"; do
    if [ "$arg" == "--purge" ]; then
        PURGE=true
    fi
done

echo "========================================"
echo "    Uninstalling Nexora VPN Linux CLI"
echo "========================================"

# Attempt disconnecting if running
if command -v nexora >/dev/null 2>&1; then
    echo "Stopping any active Nexora VPN connections..."
    nexora disconnect 2>/dev/null || true
fi

# Stop and disable systemd service if active
if [ "$(id -u)" -eq 0 ]; then
    systemctl stop nexora 2>/dev/null || true
    systemctl disable nexora 2>/dev/null || true
    rm -f /etc/systemd/system/nexora.service
    rm -f /usr/local/bin/nexora
    rm -rf /usr/local/lib/nexora
    rm -f /etc/bash_completion.d/nexora
else
    systemctl --user stop nexora 2>/dev/null || true
    systemctl --user disable nexora 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/nexora.service"
    rm -f "$HOME/.local/bin/nexora"
    rm -rf "$HOME/.local/lib/nexora"
    rm -f "$HOME/.local/share/bash-completion/completions/nexora"
fi

if [ "$PURGE" = true ]; then
    echo "Purging configuration and data files..."
    rm -rf "$HOME/.config/nexora"
    rm -rf "$HOME/.local/share/nexora"
    rm -rf "$HOME/.local/state/nexora"
fi

echo "========================================"
echo "✓ Nexora CLI has been successfully uninstalled."
if [ "$PURGE" = false ]; then
    echo "  (Note: configuration files were kept in ~/.config/nexora; use --purge to remove them)"
fi
echo "========================================"
