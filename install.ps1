param(
  [string]$Ref = $env:ADTENTION_REF,
  [string]$Version = $(if ($env:ADTENTION_VERSION) { $env:ADTENTION_VERSION } else { "latest" })
)

$ErrorActionPreference = "Stop"

$ScriptPath = $MyInvocation.MyCommand.Path
$SourceRoot = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { (Get-Location).Path }
$InstallRoot = if ($env:ADTENTION_INSTALL_ROOT) { $env:ADTENTION_INSTALL_ROOT } else { Join-Path $HOME ".codex/adtention-codex" }

function Get-ADtentionDefaultCache {
  if ($env:ADTENTION_CACHE) { return $env:ADTENTION_CACHE }
  $claudeCache = Join-Path $HOME ".claude/adtention"
  if (Test-Path $claudeCache) { return $claudeCache }
  return (Join-Path $HOME ".adtention")
}

$Cache = Get-ADtentionDefaultCache

function Get-SafeRef([string]$Value) {
  if (!$Value) { return "" }
  $out = New-Object System.Text.StringBuilder
  foreach ($char in $Value.ToLowerInvariant().ToCharArray()) {
    if ((($char -ge 'a') -and ($char -le 'z')) -or (($char -ge '0') -and ($char -le '9'))) {
      [void]$out.Append($char)
      if ($out.Length -ge 32) { break }
    }
  }
  return $out.ToString()
}

if (!(Test-Path (Join-Path $SourceRoot "plugins/adtention-codex/.codex-plugin/plugin.json"))) {
  if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path $InstallRoot) { Remove-Item -Recurse -Force $InstallRoot }
    git clone --depth 1 https://github.com/adtention-ai/codex.git $InstallRoot | Out-Null
    $SourceRoot = $InstallRoot
  } else {
    throw "Could not find repo files and git is unavailable. Clone https://github.com/adtention-ai/codex.git and run .\\install.ps1."
  }
}

if ((Resolve-Path $SourceRoot).Path -ne (Resolve-Path (New-Item -ItemType Directory -Force -Path $InstallRoot)).Path) {
  if (Test-Path $InstallRoot) { Remove-Item -Recurse -Force $InstallRoot }
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  Get-ChildItem -Force $SourceRoot | Where-Object { $_.Name -ne ".git" } | Copy-Item -Destination $InstallRoot -Recurse -Force
}

$RepoRoot = $InstallRoot
$PluginRoot = Join-Path $RepoRoot "plugins/adtention-codex"
$ClientBin = Join-Path $PluginRoot "bin/adtention-codex.exe"
$PlatformBin = Join-Path $PluginRoot "bin/adtention-codex-windows-amd64.exe"
New-Item -ItemType Directory -Force -Path $Cache | Out-Null

$LegacyCache = Join-Path $HOME ".codex/adtention"
if ((Test-Path $LegacyCache) -and ((Resolve-Path $LegacyCache).Path -ne (Resolve-Path $Cache).Path)) {
  foreach ($file in @("identity.json", "balance", "balance_display", "current_ad.txt", "current_click.txt", "title.txt", "prompt_line.txt", "terminal.txt", "category.txt", "source.txt", "ref")) {
    $from = Join-Path $LegacyCache $file
    $to = Join-Path $Cache $file
    if ((Test-Path $from) -and !(Test-Path $to)) {
      Copy-Item $from $to -Force
    }
  }
}

if ($env:ADTENTION_SKIP_DAEMON_CLEANUP -ne "1") {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "adtention-codex.*title-daemon" } |
    ForEach-Object {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

$SafeRef = Get-SafeRef $Ref
if ($SafeRef) {
  [System.IO.File]::WriteAllText((Join-Path $Cache "ref"), $SafeRef, [System.Text.Encoding]::ASCII)
}

function Test-Client {
  if (!(Test-Path $ClientBin)) { return $false }
  try {
    & $ClientBin setup *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Install-ReleaseBinary {
  if ($env:ADTENTION_SKIP_BINARY_DOWNLOAD -eq "1") { return $false }
  if ($env:PROCESSOR_ARCHITECTURE -and $env:PROCESSOR_ARCHITECTURE -notmatch "AMD64|x86_64") {
    return $false
  }
  $asset = "adtention-codex-windows-amd64.exe"
  if ($Version -eq "latest") {
    $url = "https://github.com/adtention-ai/codex/releases/latest/download/$asset"
  } else {
    $url = "https://github.com/adtention-ai/codex/releases/download/$Version/$asset"
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ClientBin) | Out-Null
  try {
    Invoke-WebRequest -Uri $url -OutFile $ClientBin -UseBasicParsing
    Write-Host "[adtention] Installed prebuilt client $asset"
    return $true
  } catch {
    if (Test-Path $ClientBin) { Remove-Item -Force $ClientBin }
    return $false
  }
}

if (!(Test-Client)) {
  if ((Test-Path $PlatformBin) -and ($PlatformBin -ne $ClientBin)) {
    Copy-Item $PlatformBin $ClientBin -Force
  }
}

if (!(Test-Client)) {
  Install-ReleaseBinary | Out-Null
}

if (!(Test-Client)) {
  if (Get-Command cargo -ErrorAction SilentlyContinue) {
    cargo build --release --manifest-path (Join-Path $PluginRoot "client/Cargo.toml") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $PluginRoot "bin") | Out-Null
    Copy-Item (Join-Path $PluginRoot "client/target/release/adtention-codex.exe") $ClientBin -Force
  } else {
    throw "Windows binary is not present, release download failed, and Cargo is unavailable."
  }
}

function Find-Codex {
  $candidates = @()
  if ($env:CODEX_BIN) { $candidates += $env:CODEX_BIN }
  if ($env:LOCALAPPDATA) {
    $candidates += (Join-Path $env:LOCALAPPDATA "Programs/Codex/codex.exe")
  }
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }

  foreach ($candidate in $candidates) {
    if (!$candidate -or !(Test-Path $candidate)) { continue }
    try {
      & $candidate --version *> $null
      if ($LASTEXITCODE -eq 0) { return $candidate }
    } catch {}
  }

  throw "Codex CLI not found. Install Codex or set CODEX_BIN, then rerun this installer."
}

if ($env:ADTENTION_SKIP_CODEX_INSTALL -ne "1") {
  $Codex = Find-Codex
  & $Codex plugin marketplace add $RepoRoot | Out-Null
  & $Codex plugin add "adtention-codex@adtention-local" | Out-Null
}

$ShellInstaller = Join-Path $PluginRoot "scripts/install-shell-integration.ps1"
& $ShellInstaller -PluginRoot $PluginRoot -Cache $Cache | Out-Null

Write-Host "[adtention] Installed ADtention for Codex."
