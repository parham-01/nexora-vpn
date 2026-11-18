#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_SOURCE="$ROOT_DIR/bin/nexora"
CLI_SOURCE="$ROOT_DIR/cli"

echo "========================================"
echo "    Installing Nexora VPN Linux CLI"
echo "========================================"

# Determine install prefix
if [ "$(id -u)" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
    LIB_DIR="/usr/local/lib/nexora"
    SYSTEMD_DIR="/etc/systemd/system"
    COMPLETION_DIR="/etc/bash_completion.d"
    IS_SYSTEM=true
else
    INSTALL_DIR="$HOME/.local/bin"
    LIB_DIR="$HOME/.local/lib/nexora"
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
    IS_SYSTEM=false
fi

echo "Installing to: $INSTALL_DIR (System: $IS_SYSTEM)"

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR"
mkdir -p "$SYSTEMD_DIR"
mkdir -p "$COMPLETION_DIR"

# Copy CLI package to lib directory
rm -rf "$LIB_DIR/nexora"
cp -r "$CLI_SOURCE/nexora" "$LIB_DIR/"

# Create executable wrapper
WRAPPER="$INSTALL_DIR/nexora"
cat << EOF > "$WRAPPER"
#!/usr/bin/env python3
import sys
from pathlib import Path

lib_dir = Path("$LIB_DIR")
if str(lib_dir) not in sys.path:
    sys.path.insert(0, str(lib_dir))

from nexora.cli import main

if __name__ == "__main__":
    main()
EOF

chmod +x "$WRAPPER"

# Install systemd service
if [ "$IS_SYSTEM" = true ]; then
    sed "s|/usr/local/bin/nexora|$WRAPPER|g" "$ROOT_DIR/systemd/nexora.service" > "$SYSTEMD_DIR/nexora.service"
else
    sed "s|/usr/local/bin/nexora|$WRAPPER|g; s|%h/.local/bin/nexora|$WRAPPER|g" "$ROOT_DIR/systemd/nexora.service" > "$SYSTEMD_DIR/nexora.service"
fi

# Install bash completion
cat << 'EOF' > "$COMPLETION_DIR/nexora"
_nexora_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="help version login logout account servers connect disconnect reconnect status ip ping logs config firefox"
    firefox_commands="login logout status servers connect disconnect"
    config_commands="show reset"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "${commands} --help --version --json" -- ${cur}) )
        return 0
    fi

    case "${prev}" in
        firefox)
            COMPREPLY=( $(compgen -W "${firefox_commands}" -- ${cur}) )
            return 0
            ;;
        config)
            COMPREPLY=( $(compgen -W "${config_commands}" -- ${cur}) )
            return 0
            ;;
        connect)
            COMPREPLY=( $(compgen -W "--server --json" -- ${cur}) )
            return 0
            ;;
        servers)
            COMPREPLY=( $(compgen -W "--country --json" -- ${cur}) )
            return 0
            ;;
        --country)
            COMPREPLY=( $(compgen -W "germany france netherlands finland usa uk turkey" -- ${cur}) )
            return 0
            ;;
    esac
}
complete -F _nexora_completion nexora
EOF

echo "✓ Executable installed: $WRAPPER"
echo "✓ Python package copied to: $LIB_DIR/nexora"
echo "✓ Systemd service installed: $SYSTEMD_DIR/nexora.service"
echo "✓ Shell completion installed: $COMPLETION_DIR/nexora"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠ Note: $INSTALL_DIR is not in your PATH."
    echo "  Add it to your ~/.bashrc or ~/.zshrc: export PATH=\"\$PATH:$INSTALL_DIR\""
fi

# Verify
"$WRAPPER" version

echo "========================================"
echo "✓ Nexora CLI has been successfully installed!"
echo "  Try running: nexora status"
echo "========================================"
