<#
  Unit tests for the Windows installer logic. Zero-dependency: just PowerShell
  (no Pester), mirroring tests/run.sh. Dot-sources install-steps.ps1 /
  uninstall-steps.ps1 (whose side-effecting bodies are guarded, so dot-sourcing
  only defines functions) and asserts on the pure helpers using temp files.

  These cover the logic that is verifiable WITHOUT Windows: the statusLine
  command string, the settings.json merge (preserve other keys, overwrite an
  existing statusLine, BOM-free output, backup), and the uninstall removal.
  They do NOT cover winget installs or bash.exe discovery — that needs real
  Windows (see the .iss build in CI and the manual smoke test).

  Run:  pwsh -NoProfile -File windows/tests/run.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
. (Join-Path $here '..\install-steps.ps1')
. (Join-Path $here '..\uninstall-steps.ps1')

$script:pass = 0
$script:fail = 0
function Assert([bool]$Cond, [string]$Name) {
  if ($Cond) { Write-Host "  [pass] $Name"; $script:pass++ }
  else       { Write-Host "  [FAIL] $Name"; $script:fail++ }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ccsl-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  Write-Host "== Get-StatusLineCommand =="
  $cmd = Get-StatusLineCommand 'C:\Program Files\Git\bin\bash.exe' 'C:\Users\me\.claude\statusline.sh'
  Assert ($cmd -eq '"C:/Program Files/Git/bin/bash.exe" "C:/Users/me/.claude/statusline.sh"') `
    "forward-slashes both paths and quotes them"

  Write-Host "== Set-StatusLineSetting: fresh file =="
  $s1 = Join-Path $tmp 's1.json'
  Set-StatusLineSetting $s1 $cmd | Out-Null
  $o1 = Get-Content -LiteralPath $s1 -Raw | ConvertFrom-Json
  Assert ($o1.statusLine.type -eq 'command')  "type = command"
  Assert ($o1.statusLine.command -eq $cmd)    "command stored verbatim"

  $bytes = [System.IO.File]::ReadAllBytes($s1)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  Assert (-not $hasBom) "settings.json written without a UTF-8 BOM"

  Write-Host "== Set-StatusLineSetting: preserve other keys, overwrite existing =="
  $s2 = Join-Path $tmp 's2.json'
  Set-Utf8NoBom $s2 '{"model":"opus","statusLine":{"type":"command","command":"old"}}'
  $backup = Set-StatusLineSetting $s2 $cmd
  $o2 = Get-Content -LiteralPath $s2 -Raw | ConvertFrom-Json
  Assert ($o2.model -eq 'opus')             "unrelated key 'model' preserved"
  Assert ($o2.statusLine.command -eq $cmd)  "existing statusLine overwritten"
  Assert (Test-Path -LiteralPath $backup)   "backup file created"

  Write-Host "== Remove-StatusLineSetting =="
  $r1 = Remove-StatusLineSetting $s2
  $o3 = Get-Content -LiteralPath $s2 -Raw | ConvertFrom-Json
  Assert ($r1 -eq $true)                                "returns true when statusLine present"
  Assert (-not $o3.PSObject.Properties['statusLine'])   "statusLine key removed"
  Assert ($o3.model -eq 'opus')                         "unrelated key still preserved"

  $r2 = Remove-StatusLineSetting $s2
  Assert ($r2 -eq $false) "returns false when statusLine already absent"

  $r3 = Remove-StatusLineSetting (Join-Path $tmp 'does-not-exist.json')
  Assert ($r3 -eq $false) "returns false on a missing file"
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Result: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
