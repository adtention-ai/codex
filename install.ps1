$ErrorActionPreference = "Stop"

$ScriptPath = $MyInvocation.MyCommand.Path
$SourceRoot = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { (Get-Location).Path }
$InstallRoot = if ($env:ADTENTION_INSTALL_ROOT) { $env:ADTENTION_INSTALL_ROOT } else { Join-Path $HOME ".codex/adtention-codex" }
$Cache = if ($env:ADTENTION_CACHE) { $env:ADTENTION_CACHE } else { Join-Path $HOME ".codex/adtention" }

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
New-Item -ItemType Directory -Force -Path $Cache | Out-Null
if (!(Test-Path $ClientBin)) {
  if (Get-Command cargo -ErrorAction SilentlyContinue) {
    cargo build --release --manifest-path (Join-Path $PluginRoot "client/Cargo.toml") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $PluginRoot "bin") | Out-Null
    Copy-Item (Join-Path $PluginRoot "client/target/release/adtention-codex.exe") $ClientBin -Force
  } else {
    throw "Windows binary is not present and Cargo is unavailable."
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

$TaskName = "ADtention Codex Viewability"
if (Test-Path $ClientBin) {
  $PowerShell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
  if (!$PowerShell) { $PowerShell = "powershell.exe" }
  $ClientLiteral = "'" + $ClientBin.Replace("'", "''") + "'"
  $CacheLiteral = "'" + $Cache.Replace("'", "''") + "'"
  $HelperCommand = "`$env:ADTENTION_CACHE = $CacheLiteral; & $ClientLiteral viewability-daemon Codex"
  $EncodedHelperCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($HelperCommand))
  $Action = New-ScheduledTaskAction -Execute $PowerShell -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $EncodedHelperCommand"
  $Trigger = New-ScheduledTaskTrigger -AtLogOn
  $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
  if ($env:ADTENTION_NO_START_SERVICE -ne "1") {
    Start-ScheduledTask -TaskName $TaskName
  }
}

Write-Host "[adtention] Installed ADtention for Codex."
