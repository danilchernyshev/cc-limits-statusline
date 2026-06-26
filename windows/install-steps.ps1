<#
.SYNOPSIS
  Windows installer for cc-limits-statusline (the PowerShell port of install.sh).

.DESCRIPTION
  Mirrors install.sh's contract on Windows:
    * auto-installs the runtime dependencies (jq, and Git for Windows for `bash`)
      via winget when they are missing;
    * copies statusline.sh into ~/.claude/;
    * wires it into ~/.claude/settings.json (backing the file up first);
    * seeds ~/.config/cc-limits-statusline.conf if absent (never overwrites).

  The statusline is a bash script — Claude Code runs it as `bash …statusline.sh`,
  so bash + jq are required at RUNTIME no matter what; this installer just
  provides and wires them. Because Git for Windows does not put bash on PATH by
  default, the absolute path to bash.exe is written into settings.json.

  This script is the single source of truth used by BOTH the .exe installer
  (windows/cc-limits-statusline.iss invokes it) and a standalone run. Run it
  directly with:
    powershell -ExecutionPolicy Bypass -File windows\install-steps.ps1

  Honours CLAUDE_CONFIG_DIR and CC_STATUSLINE_RC, exactly like install.sh.

  TESTABILITY: like the BASH_SOURCE guard in statusline.sh, this script runs its
  installer (Invoke-Install) only when executed directly. When *dot-sourced*
  (`. .\install-steps.ps1`, as windows/tests/run.ps1 does) it just defines the
  functions — no winget, no file changes — so the pure helpers can be unit-tested.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:RepoRaw = 'https://raw.githubusercontent.com/danilchernyshev/cc-limits-statusline/main'

# --- pure helpers (no side effects; safe to dot-source & unit-test) ---------

# Write text as UTF-8 *without* a BOM (a BOM can trip strict JSON readers).
function Set-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# Build the statusLine command string: forward-slash both paths so MSYS bash
# reads them, and quote both so spaces in "Program Files" survive. e.g.
#   "C:/Program Files/Git/bin/bash.exe" "C:/Users/you/.claude/statusline.sh"
function Get-StatusLineCommand([string]$BashExe, [string]$ScriptPath) {
  '"{0}" "{1}"' -f $BashExe.Replace('\', '/'), $ScriptPath.Replace('\', '/')
}

# Set (or overwrite) the .statusLine key in a settings.json, preserving every
# other key. Creates the file as {} if missing; backs it up first. Returns the
# backup path. This is the heart of the wiring and is unit-tested directly.
function Set-StatusLineSetting([string]$SettingsPath, [string]$Command) {
  if (-not (Test-Path -LiteralPath $SettingsPath)) { Set-Utf8NoBom $SettingsPath '{}' }
  $backup = "$SettingsPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
  Copy-Item -LiteralPath $SettingsPath -Destination $backup -Force

  $json = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
  $statusLine = [PSCustomObject]@{ type = 'command'; command = $Command }
  if ($json.PSObject.Properties['statusLine']) {
    $json.statusLine = $statusLine
  } else {
    $json | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLine
  }
  Set-Utf8NoBom $SettingsPath ($json | ConvertTo-Json -Depth 20)
  return $backup
}

function Test-Have([string]$Cmd) {
  [bool](Get-Command $Cmd -ErrorAction SilentlyContinue)
}

# Locate bash.exe: prefer one on PATH, else the standard Git for Windows spots.
function Find-Bash {
  $onPath = Get-Command bash -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  $candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
  return $null
}

# --- installer steps (side effects; run only when executed, not dot-sourced) -

# Re-read PATH from the registry so freshly winget-installed tools resolve in
# this same session (installers update the registry, not our live process env).
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Install-Dependency([string]$Id, [string]$Friendly) {
  Write-Host ">> Installing $Friendly via winget ($Id)…"
  & winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements
  Update-SessionPath
}

# Copy a bundled asset, or download it from the repo when running standalone.
function Get-Asset([string]$Name, [string]$Target) {
  $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $Name } else { $null }
  if ($local -and (Test-Path -LiteralPath $local)) {
    Copy-Item -LiteralPath $local -Destination $Target -Force
  } else {
    Invoke-WebRequest -Uri "$script:RepoRaw/$Name" -OutFile $Target -UseBasicParsing
  }
}

function Invoke-Install {
  $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
  $dest      = Join-Path $claudeDir 'statusline.sh'
  $settings  = Join-Path $claudeDir 'settings.json'
  $rc        = if ($env:CC_STATUSLINE_RC) { $env:CC_STATUSLINE_RC } else { Join-Path $env:USERPROFILE '.config\cc-limits-statusline.conf' }

  # 0) dependencies (jq + bash)
  $hasWinget = Test-Have 'winget'
  if (-not $hasWinget) {
    Write-Warning "winget not found. Install 'App Installer' from the Microsoft Store, or install jq + Git for Windows manually:"
    Write-Warning "  jq:  https://jqlang.github.io/jq/   Git: https://git-scm.com/download/win"
  }

  if (-not (Test-Have 'jq')) {
    if ($hasWinget) { Install-Dependency 'jqlang.jq' 'jq' }
    else            { Write-Warning "jq is missing and cannot be auto-installed without winget." }
  }

  if (-not (Find-Bash)) {
    if ($hasWinget) { Install-Dependency 'Git.Git' 'Git for Windows (provides bash)' }
    else            { Write-Warning "bash is missing and cannot be auto-installed without winget." }
  }

  $bash = Find-Bash
  if (-not $bash) {
    throw "Could not locate bash.exe after setup. Install Git for Windows (https://git-scm.com/download/win) and re-run."
  }

  # 1) place the script
  New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
  Get-Asset 'statusline.sh' $dest
  Write-Host "[ok] installed statusline -> $dest"

  # 2) wire it into settings.json
  $command = Get-StatusLineCommand $bash $dest
  Set-StatusLineSetting $settings $command | Out-Null
  Write-Host "[ok] updated $settings (backup saved alongside it)"

  # 3) seed the user config (never overwrite an existing one)
  if (-not (Test-Path -LiteralPath $rc)) {
    New-Item -ItemType Directory -Path (Split-Path $rc -Parent) -Force | Out-Null
    Get-Asset 'config.example.conf' $rc
    Write-Host "[ok] wrote default config -> $rc (edit to tune thresholds / hide fields)"
  } else {
    Write-Host "[--] kept existing config -> $rc"
  }

  if (-not (Test-Have 'jq')) {
    Write-Warning "jq still not on PATH in this session — it should resolve once Claude Code restarts. If the line shows 'jq not found', open a new terminal or reboot."
  }

  Write-Host ""
  Write-Host "Done. Start or reload Claude Code to see the new statusline."
}

# --- run only when executed directly; dot-sourcing just defines functions ----
if ($MyInvocation.InvocationName -ne '.') {
  Invoke-Install
}
