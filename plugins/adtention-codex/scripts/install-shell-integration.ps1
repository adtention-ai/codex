param(
  [string]$PluginRoot = $(Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Cache = $(if ($env:ADTENTION_CACHE) { $env:ADTENTION_CACHE } else { Join-Path $HOME ".codex/adtention" })
)

$start = "# >>> ADtention Codex >>>"
$end = "# <<< ADtention Codex <<<"
$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $profilePath
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (!(Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath | Out-Null }

$existing = Get-Content -Raw -Path $profilePath
$pattern = "(?s)\r?\n?# >>> ADtention Codex >>>.*?# <<< ADtention Codex <<<\r?\n?"
$clean = [regex]::Replace($existing, $pattern, "`n")

$block = @"
$start
`$env:ADTENTION_PLUGIN_ROOT = '$PluginRoot'
`$env:ADTENTION_CACHE = '$Cache'
. "`$env:ADTENTION_PLUGIN_ROOT/scripts/shell-integration.ps1"
$end
"@

Set-Content -Path $profilePath -Value ($clean.TrimEnd() + "`n`n" + $block + "`n")
Write-Host "Installed ADtention shell integration in $profilePath"
