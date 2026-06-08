#!/usr/bin/env bash
set -e

echo "==> Installing Solana CLI..."
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

echo "==> Building vulnerable vault (BPF)..."
cd vulnerable-vault
cargo build-sbf
cd ..

echo "==> Building proof-of-exploit (native)..."
cargo build -p proof-of-exploit --release

echo ""
echo "Setup complete. Run the demo:"
echo "  ./run_demo.sh              # exploit, interactive loop"
echo "  ./run_demo.sh both         # exploit + patched side-by-side"
echo "  ./run_demo.sh fix          # show patch blocking the attack"