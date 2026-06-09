<#
.SYNOPSIS
  Uninstaller for cc-limits-statusline on Windows (reverse of install-steps.ps1).

.DESCRIPTION
  Removes the statusLine wiring and the installed script:
    * drops the .statusLine key from ~/.claude/settings.json (backing it up first);
    * deletes ~/.claude/statusline.sh.

  Leaves the user config (~/.config/cc-limits-statusline.conf) and any
  settings.json.bak.* backups in place. Honours CLAUDE_CONFIG_DIR.

  Invoked by the .exe uninstaller (windows/cc-limits-statusline.iss) and runnable
  standalone:
    powershell -ExecutionPolicy Bypass -File windows\uninstall-steps.ps1

  Like install-steps.ps1, the side-effecting body (Invoke-Uninstall) runs only
  when executed directly; dot-sourcing just defines the functions for tests.
#>
#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- pure helpers (no side effects; safe to dot-source & unit-test) ---------

function Set-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# Drop the .statusLine key from a settings.json, preserving every other key.
# Backs the file up first. Returns $true if a key was removed, $false otherwise
# (file missing or no statusLine present). Unit-tested directly.
function Remove-StatusLineSetting([string]$SettingsPath) {
  if (-not (Test-Path -LiteralPath $SettingsPath)) { return $false }
  $json = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
  if (-not $json.PSObject.Properties['statusLine']) { return $false }
  Copy-Item -LiteralPath $SettingsPath -Destination "$SettingsPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force
  $json.PSObject.Properties.Remove('statusLine')
  Set-Utf8NoBom $SettingsPath ($json | ConvertTo-Json -Depth 20)
  return $true
}

# --- uninstaller step (side effects; runs only when executed directly) ------

function Invoke-Uninstall {
  $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
  $dest      = Join-Path $claudeDir 'statusline.sh'
  $settings  = Join-Path $claudeDir 'settings.json'

  if (Remove-StatusLineSetting $settings) {
    Write-Host "[ok] removed statusLine from $settings"
  } else {
    Write-Host "[--] no statusLine key in $settings — nothing to remove"
  }

  if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Force
    Write-Host "[ok] deleted $dest"
  }

  Write-Host ""
  Write-Host "Uninstalled. Your config (~/.config/cc-limits-statusline.conf) was left in place."
}

if ($MyInvocation.InvocationName -ne '.') {
  Invoke-Uninstall
}
