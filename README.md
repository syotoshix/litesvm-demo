# Proof of Exploit — Solana Hackathon Demo

Automated vulnerability verification for Solana smart contracts.

Given a machine-readable security report (`security-report.json`), the tool:
1. Spins up an isolated Solana environment
2. Deploys the vulnerable program
3. Reproduces the exact exploit from the report
4. Measures before/after state as on-chain evidence
5. Writes a signed `evidence-report.json` with the verdict

---

## TL;DR — Quickest way to run

### Option A — GitHub Codespaces (no install, works now, ~3 min)

1. Push this folder to a GitHub repo
2. Click **Code → Codespaces → Create codespace**
3. The `devcontainer.json` auto-installs Rust + Solana CLI and builds everything
4. Then run:
   ```bash
   ./run_demo.sh              # exploit (loops — press Enter to repeat)
   ./run_demo.sh both         # shows exploit then patched side-by-side
   ./run_demo.sh fix          # shows the patch blocking the attack
   ```

### Option B — Windows (after restart)

> **Note:** Smart App Control has been disabled via registry (state=0).
> A **restart is required** for that change to take effect.
> After restart, the steps below will work.

```powershell
# 1. Install Solana CLI if not done (one-time)
.\setup.ps1

# 2. Run the demo
.\run_demo.ps1                   # exploit, interactive loop
.\run_demo.ps1 -Mode both        # exploit + fix side-by-side
.\run_demo.ps1 -Mode fix         # show patch working
.\run_demo.ps1 -Once             # single run, exit 0/1 for CI
```

### Option C — Any Linux / Mac (standard Solana toolchain)

```bash
# Install deps (once)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$HOME/.cargo/bin:$PATH"

# Build and run
./run_demo.sh              # exploit loop
./run_demo.sh both         # full comparison
```

---

## Vulnerability: Missing Signer Authorization Check (CWE-862)

**Program:** `vulnerable-vault` — a SOL vault with admin-only withdrawals.

**Bug in `process_admin_withdraw`:** The instruction checks that the provided
admin account's *public key* matches the stored admin, but never checks that
the admin *signed* the transaction. Since the admin's pubkey is on-chain and
publicly visible, any attacker can drain the vault without the admin's private key.

```rust
// ✓ present — identity check
if state.admin != *admin_account.key { ... }

// ❌ MISSING — authorization check
// if !admin_account.is_signer {
//     return Err(ProgramError::MissingRequiredSignature);
// }
```

**Fix:** Compile with `--features patched` to enable the signer check.

---

## Project Structure

```
litesvm demo/
├── Cargo.toml                    # Workspace
├── security-report.json          # Input: machine-readable vulnerability report
├── run_demo.ps1                  # Windows demo runner
├── run_demo.sh                   # Linux/Mac/Codespaces demo runner
├── setup.ps1                     # Windows one-time setup
├── .devcontainer/                # GitHub Codespaces config
│   ├── devcontainer.json
│   └── setup.sh
├── vulnerable-vault/
│   ├── Cargo.toml                # [features] default=[] patched=[]
│   └── src/lib.rs                # Solana program — bug on line ~131
└── proof-of-exploit/
    ├── Cargo.toml
    └── src/main.rs               # Verifier — reads report, runs exploit, emits evidence
```

---

## How the Verifier Works

```
security-report.json
        │
        ▼
proof-of-exploit binary
        │
        ├─ parse report
        ├─ create fresh mock accounts (VaultState pre-initialized)
        ├─ call process_instruction() directly (native Rust, no BPF needed)
        │       admin_account.is_signer = false  ← the exploit
        ├─ compare vault/attacker balances before vs after
        └─ emit evidence-report.json + exit 0 (exploitable) / 1 (not)
```

**Native mode** (default) calls the program's Rust function directly — no BPF
compilation, no validator, works on any platform.

**LiteSVM mode** (future, requires `cargo build-sbf` on Linux/Mac) loads the
compiled `.so` into an isolated in-process Solana validator via `add_program_from_file`.

---

## Repeating / Undoing the Demo

Every invocation creates **fresh accounts** (no persistent state). The "undo"
is automatic — just run again. In interactive mode, press **Enter** to reset
all accounts and repeat the exploit from scratch.

```
./run_demo.sh              ← loops forever, Enter = reset + repeat
Ctrl+C                     ← exit
```

Evidence files are numbered (`evidence-report-01.json`, `02`, …) so each run
is independently recorded.
