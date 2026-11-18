#!/usr/bin/env bash
set -euo pipefail

echo "========================================"
echo "    Building Nexora VPN Linux CLI"
echo "========================================"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Checking Python environment..."
python3 --version

echo "[2/4] Validating Python syntax..."
python3 -m py_compile cli/nexora/*.py
echo "✓ Python syntax OK."

echo "[3/4] Ensuring executable permissions..."
chmod +x bin/nexora
chmod +x scripts/*.sh 2>/dev/null || true

echo "[4/4] Verifying CLI binary execution..."
./bin/nexora --version
./bin/nexora status --json >/dev/null

echo "========================================"
echo "✓ Build completed successfully!"
echo "To install Nexora CLI, run: ./scripts/install.sh"
echo "========================================"
