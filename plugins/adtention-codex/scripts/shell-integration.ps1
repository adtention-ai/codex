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
