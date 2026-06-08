<#
.SYNOPSIS
    One-time setup: installs Rust, Solana CLI, and builds both .so variants.
    Run this once before using run_demo.ps1.
#>

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }

# ── 1. Rust ───────────────────────────────────────────────────────────────────
Step "Checking Rust / cargo"
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Ok "cargo already installed: $(cargo --version)"
} else {
    Step "Installing Rust via rustup"
    $rustup = "$env:TEMP\rustup-init.exe"
    Write-Host "    Downloading rustup-init.exe..." -ForegroundColor Gray
    curl.exe -sS -L "https://win.rustup.rs/x86_64" -o $rustup
    Write-Host "    Running installer (this takes ~2 minutes)..." -ForegroundColor Gray
    & $rustup -y --default-toolchain stable --no-modify-path
    # Add cargo to PATH for this session
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    Ok "Rust installed: $(cargo --version)"
}

# ── 2. Solana CLI / cargo-build-sbf ──────────────────────────────────────────
Step "Checking cargo-build-sbf (Solana BPF compiler)"
if (Get-Command cargo-build-sbf -ErrorAction SilentlyContinue) {
    Ok "cargo-build-sbf already installed"
} else {
    Step "Installing Solana CLI"
    Write-Host "    Downloading Solana installer..." -ForegroundColor Gray

    # Solana releases a Windows .exe installer
    $solanaInstaller = "$env:TEMP\solana-install.exe"
    $releaseUrl = "https://release.anza.xyz/stable/solana-install-init-x86_64-pc-windows-msvc.exe"
    curl.exe -sS -L $releaseUrl -o $solanaInstaller

    Write-Host "    Running Solana installer..." -ForegroundColor Gray
    & $solanaInstaller v2.1.0
    # Add to PATH for this session
    $env:PATH = "$env:USERPROFILE\.local\share\solana\install\active_release\bin;$env:PATH"

    if (Get-Command cargo-build-sbf -ErrorAction SilentlyContinue) {
        Ok "Solana CLI installed: $(solana --version)"
    } else {
        Warn "Solana CLI installed but not in PATH for this session."
        Warn "Restart your terminal and run setup.ps1 again, or manually add:"
        Warn "  `$env:PATH = '`$env:USERPROFILE\.local\share\solana\install\active_release\bin;`$env:PATH'"
        exit 1
    }
}

# ── 3. Build vulnerable program (.so files) ───────────────────────────────────
Step "Building vulnerable-vault (default — with bug)"
Push-Location (Join-Path $root "vulnerable-vault")
cargo build-sbf
$deployDir = Join-Path (Get-Location) "target\deploy"
$vulnerableSo = Join-Path $deployDir "vulnerable_vault.so"
Ok "Built: $vulnerableSo"

Step "Building patched-vault (--features patched — fix applied)"
cargo build-sbf --features patched
$patchedSo = Join-Path $deployDir "vulnerable_vault_patched.so"
Copy-Item $vulnerableSo $patchedSo -Force
# Rebuild vulnerable so both coexist
cargo build-sbf
Ok "Built: $patchedSo"
Pop-Location

# ── 4. Build verifier binary ──────────────────────────────────────────────────
Step "Building proof-of-exploit verifier"
Push-Location $root
cargo build -p proof-of-exploit --release
Ok "Built: $(Join-Path $root 'target\release\proof-of-exploit.exe')"
Pop-Location

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  SETUP COMPLETE — you can now run:" -ForegroundColor Green
Write-Host ""
Write-Host "    .\run_demo.ps1                # exploit (loops)" -ForegroundColor White
Write-Host "    .\run_demo.ps1 -Mode both     # exploit + fix" -ForegroundColor White
Write-Host "    .\run_demo.ps1 -Mode fix      # show patch working" -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
