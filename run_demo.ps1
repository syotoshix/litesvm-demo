<#
.SYNOPSIS
    Proof of Exploit demo runner.

.PARAMETER Mode
    exploit  — run exploit against the VULNERABLE program (default)
    fix      — run exploit against the PATCHED program (shows rejection)
    both     — run exploit, pause, then run patched side-by-side

.PARAMETER Once
    Single run then exit (exit 0 = exploitable, exit 1 = not exploitable)

.PARAMETER Build
    Force a rebuild before running

.EXAMPLE
    .\run_demo.ps1                   # exploit, interactive loop (press Enter to repeat)
    .\run_demo.ps1 -Mode both        # show exploit + fix back-to-back
    .\run_demo.ps1 -Mode fix         # show the patch blocking the attack
    .\run_demo.ps1 -Once             # single run, CI-friendly
    .\run_demo.ps1 -Build            # force rebuild then run
#>
param(
    [ValidateSet("exploit","fix","both")]
    [string]$Mode = "exploit",
    [switch]$Once,
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Write-Banner($text, $color = "Cyan") {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor $color
    Write-Host "  $text" -ForegroundColor $color
    Write-Host ("=" * 70) -ForegroundColor $color
    Write-Host ""
}

# ── Dependency check ──────────────────────────────────────────────────────────
Write-Banner "Proof of Exploit — checking dependencies"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: cargo not found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  cargo  : $(cargo --version)" -ForegroundColor Green

# ── Build ─────────────────────────────────────────────────────────────────────
$needBuild = $Build
if (-not $needBuild) {
    # Check if the binary exists and is newer than the source
    $binary = Join-Path $root "target\release\proof-of-exploit.exe"
    if (-not (Test-Path $binary)) { $needBuild = $true }
}

if ($needBuild) {
    Write-Banner "Building proof-of-exploit"
    Push-Location $root
    cargo build -p proof-of-exploit --release
    Pop-Location
    Write-Host "  Binary ready." -ForegroundColor Green
}

$binary = Join-Path $root "target\release\proof-of-exploit.exe"
$onceFlag = if ($Once) { @("--once") } else { @() }

switch ($Mode) {
    "exploit" {
        Write-Banner "RUNNING — exploit (VULNERABLE build)" "Red"
        & $binary @onceFlag
        $exit = $LASTEXITCODE
        if ($Once) {
            Write-Host ""
            if ($exit -eq 0) { Write-Host "  EXIT 0 — exploit confirmed." -ForegroundColor Red }
            else              { Write-Host "  EXIT 1 — exploit failed (unexpected)." -ForegroundColor Yellow }
        }
        exit $exit
    }

    "fix" {
        Write-Banner "Building PATCHED build (--features patched)" "Green"
        Push-Location $root
        cargo build -p proof-of-exploit --release --features patched
        $patchedBin = Join-Path $root "target\release\proof-of-exploit.exe"
        Pop-Location

        Write-Banner "RUNNING — exploit against PATCHED program" "Green"
        & $patchedBin @onceFlag
        $exit = $LASTEXITCODE
        if ($Once) {
            Write-Host ""
            if ($exit -eq 1) { Write-Host "  EXIT 1 — exploit rejected, patch is effective." -ForegroundColor Green }
            else              { Write-Host "  EXIT 0 — patch did NOT block the exploit!" -ForegroundColor Red }
        }
        # Rebuild default (vulnerable) so next run_demo works normally
        Push-Location $root
        cargo build -p proof-of-exploit --release | Out-Null
        Pop-Location
        exit $exit
    }

    "both" {
        Write-Banner "ROUND 1 — VULNERABLE (exploit should SUCCEED)" "Red"
        & $binary --once
        $r1 = $LASTEXITCODE

        Write-Host ""
        Write-Host "  Press ENTER to continue to Round 2 (patched)..."
        Read-Host

        Write-Banner "Building patched binary..." "Green"
        Push-Location $root
        cargo build -p proof-of-exploit --release --features patched | Out-Null
        Pop-Location

        Write-Banner "ROUND 2 — PATCHED (exploit should FAIL)" "Green"
        & $binary --once
        $r2 = $LASTEXITCODE

        # Restore default build
        Push-Location $root
        cargo build -p proof-of-exploit --release | Out-Null
        Pop-Location

        Write-Host ""
        Write-Host ("=" * 70) -ForegroundColor Cyan
        Write-Host "  SUMMARY" -ForegroundColor Cyan
        Write-Host ("=" * 70) -ForegroundColor Cyan
        Write-Host ""
        $s1 = if ($r1 -eq 0) { "EXPLOITABLE (exit 0)" } else { "NOT exploitable (exit 1)" }
        $s2 = if ($r2 -eq 1) { "REJECTED — patch effective (exit 1)" } else { "unexpectedly succeeded (exit 0)" }
        Write-Host "  Vulnerable  : $s1" -ForegroundColor $(if ($r1 -eq 0){"Red"}else{"Gray"})
        Write-Host "  Patched     : $s2" -ForegroundColor $(if ($r2 -eq 1){"Green"}else{"Red"})
        Write-Host ""
        exit $(if ($r1 -eq 0 -and $r2 -eq 1) { 0 } else { 1 })
    }
}
