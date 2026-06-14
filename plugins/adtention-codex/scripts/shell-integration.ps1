function Invoke-ADtentionCodexPrompt {
  $cache = if ($env:ADTENTION_CACHE) { $env:ADTENTION_CACHE } else { Join-Path $HOME ".codex/adtention" }
  $terminal = Join-Path $cache "terminal.txt"
  $title = ""
  $line = ""

  if (Test-Path $terminal) {
    $rows = Get-Content -Path $terminal -TotalCount 2 -ErrorAction SilentlyContinue
    if ($rows.Count -ge 1) { $title = [string]$rows[0] }
    if ($rows.Count -ge 2) { $line = [string]$rows[1] }
  }

  if ($title) {
    try { $host.UI.RawUI.WindowTitle = $title } catch {}
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $cache "last_render_seen") | Out-Null
  }

  if ($line -and $env:ADTENTION_PROMPT_LINE -ne "0") {
    Write-Host $line
  }
}

function Get-ADtentionCodexClient {
  $root = $env:ADTENTION_PLUGIN_ROOT
  $candidates = @(
    $env:ADTENTION_CODEX_BIN,
    $(if ($root) { Join-Path $root "bin/adtention-codex.exe" }),
    $(if ($root) { Join-Path $root "bin/adtention-codex" }),
    $(if ($root) { Join-Path $root "client/target/release/adtention-codex.exe" }),
    $(if ($root) { Join-Path $root "client/target/release/adtention-codex" }),
    $(if ($root) { Join-Path $root "client/target/debug/adtention-codex.exe" }),
    $(if ($root) { Join-Path $root "client/target/debug/adtention-codex" })
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  return $null
}

function Invoke-ADtentionCodexOpen {
  $client = Get-ADtentionCodexClient
  if (!$client) {
    Write-Error "adtention: client binary not found."
    return
  }
  & $client open @args
}

function global:adtention-open {
  Invoke-ADtentionCodexOpen @args
}

if (-not $Global:ADtentionCodexOriginalPrompt) {
  $Global:ADtentionCodexOriginalPrompt = if (Test-Path Function:\prompt) {
    (Get-Command prompt).ScriptBlock
  } else {
    { "PS $($executionContext.SessionState.Path.CurrentLocation)> " }
  }
}

function global:prompt {
  Invoke-ADtentionCodexPrompt
  & $Global:ADtentionCodexOriginalPrompt
}
