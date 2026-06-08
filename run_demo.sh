#!/usr/bin/env bash
# Demo runner for Linux/Mac/Codespaces
# Usage: ./run_demo.sh [exploit|fix|both]
set -e

MODE="${1:-exploit}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$HOME/.cargo/bin:$PATH"

build_native() {
    echo "==> Building proof-of-exploit (native)..."
    cargo build -p proof-of-exploit --release
}

build_sbf() {
    echo "==> Building vulnerable-vault (BPF)..."
    (cd "$ROOT/vulnerable-vault" && cargo build-sbf)
}

case "$MODE" in
  exploit)
    build_native
    echo ""
    echo "=========================================="
    echo "  RUNNING — VULNERABLE (exploit should SUCCEED)"
    echo "=========================================="
    "$ROOT/target/release/proof-of-exploit" "${@:2}"
    ;;
  fix)
    echo "==> Building PATCHED binary..."
    cargo build -p proof-of-exploit --release --features patched
    echo ""
    echo "=========================================="
    echo "  RUNNING — PATCHED (exploit should FAIL)"
    echo "=========================================="
    "$ROOT/target/release/proof-of-exploit" "${@:2}"
    # Restore default
    cargo build -p proof-of-exploit --release >/dev/null 2>&1
    ;;
  both)
    build_native
    echo ""
    echo "========================================== ROUND 1 — VULNERABLE"
    "$ROOT/target/release/proof-of-exploit" --once
    R1=$?
    echo ""
    read -p "Press ENTER for Round 2 (patched)..."
    echo "==> Building PATCHED binary..."
    cargo build -p proof-of-exploit --release --features patched >/dev/null 2>&1
    echo ""
    echo "========================================== ROUND 2 — PATCHED"
    "$ROOT/target/release/proof-of-exploit" --once
    R2=$?
    cargo build -p proof-of-exploit --release >/dev/null 2>&1
    echo ""
    echo "SUMMARY"
    echo "  Vulnerable : $([ $R1 -eq 0 ] && echo 'EXPLOITABLE (exit 0)' || echo 'not exploitable')"
    echo "  Patched    : $([ $R2 -eq 1 ] && echo 'REJECTED — patch effective (exit 1)' || echo 'unexpectedly succeeded')"
    ;;
  *)
    echo "Usage: $0 [exploit|fix|both]"
    exit 1
    ;;
esac
