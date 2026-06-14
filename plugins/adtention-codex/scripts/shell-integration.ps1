function Get-ADtentionCodexCache {
  if ($env:ADTENTION_CACHE) { return $env:ADTENTION_CACHE }
  $claudeCache = Join-Path $HOME ".claude/adtention"
  if (Test-Path $claudeCache) { return $claudeCache }
  return (Join-Path $HOME ".adtention")
}

function Test-ADtentionCodexDisplay {
  return (($env:ADTENTION_DISPLAY -eq "1") -or
    ($env:ADTENTION_CODEX_ACTIVE -eq "1") -or
    ($env:ADTENTION_CODEX_DISPLAY -eq "1") -or
    ($env:CODEX_SHELL -eq "1") -or
    ($env:__CFBundleIdentifier -eq "com.openai.codex"))
}

function Invoke-ADtentionCodexPrompt {
  if (!(Test-ADtentionCodexDisplay)) { return }

  $cache = Get-ADtentionCodexCache
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

function global:adtention-codex-on {
  $env:ADTENTION_DISPLAY = "1"
  Invoke-ADtentionCodexPrompt
}

function global:adtention-codex-off {
  Remove-Item Env:\ADTENTION_DISPLAY -ErrorAction SilentlyContinue
  Remove-Item Env:\ADTENTION_CODEX_ACTIVE -ErrorAction SilentlyContinue
  Remove-Item Env:\ADTENTION_CODEX_DISPLAY -ErrorAction SilentlyContinue
}

if (-not $Global:ADtentionCodexRealCodex) {
  $codexCommand = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
  if ($codexCommand) {
    $Global:ADtentionCodexRealCodex = $codexCommand.Source
  }
}

if (($env:ADTENTION_WRAP_CODEX_CLI -ne "0") -and $Global:ADtentionCodexRealCodex) {
  function global:codex {
    $hadDisplay = Test-Path Env:\ADTENTION_DISPLAY
    $oldDisplay = $env:ADTENTION_DISPLAY
    $hadActive = Test-Path Env:\ADTENTION_CODEX_ACTIVE
    $oldActive = $env:ADTENTION_CODEX_ACTIVE

    $env:ADTENTION_DISPLAY = "1"
    $env:ADTENTION_CODEX_ACTIVE = "1"
    & $Global:ADtentionCodexRealCodex @args
    $status = $LASTEXITCODE

    if ($hadDisplay) { $env:ADTENTION_DISPLAY = $oldDisplay } else { Remove-Item Env:\ADTENTION_DISPLAY -ErrorAction SilentlyContinue }
    if ($hadActive) { $env:ADTENTION_CODEX_ACTIVE = $oldActive } else { Remove-Item Env:\ADTENTION_CODEX_ACTIVE -ErrorAction SilentlyContinue }
    if ($null -ne $status) { $global:LASTEXITCODE = $status }
  }
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
