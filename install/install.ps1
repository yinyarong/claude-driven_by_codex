#Requires -Version 5.1
<#
.SYNOPSIS
  Install the Windows side of claude-driven_by_codex.

.DESCRIPTION
  Prepares CLIProxyAPI, writes a private configuration, installs the cdn/clcd/clai
  launchers, and installs the WSL proxy relay. Does not log in to ChatGPT; the
  script prints the command to run afterwards.

.PARAMETER Proxy
  HTTP proxy used only for downloading CLIProxyAPI from GitHub, e.g.
  http://127.0.0.1:7897

.PARAMETER BypassPermissions
  Write a profile settings.json with defaultMode=bypassPermissions.
#>
[CmdletBinding()]
param(
  [string]$CpaHome    = (Join-Path $env:USERPROFILE 'Tools\CLIProxyAPI'),
  [string]$CpaVersion = '8.1.1',
  [int]   $CpaPort    = 8317,
  [int]   $ClashPort  = 7897,
  [int]   $RelayPort  = 17897,
  [string]$Model      = 'gpt-6-luna',
  [string]$FastModel  = 'gpt-6-luna',
  [int]   $Context    = 200000,
  [string]$WslDistro  = 'Ubuntu',
  [string]$WslUser    = '',
  [string]$Proxy      = '',
  [switch]$SkipDownload,
  [switch]$BypassPermissions
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$binDir = Join-Path $env:USERPROFILE '.local\bin'
$profileDir = Join-Path $env:USERPROFILE '.claude-codex'
$envFile = Join-Path $profileDir 'route.env.cmd'

function Info($m) { Write-Host "[install] $m" }
function Die($m) { Write-Host "[install] ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- prerequisites ----------
foreach ($t in 'node.exe', 'claude', 'curl.exe') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t not found on PATH" }
}

if (-not $WslUser) {
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    $wp = Start-Process -FilePath 'wsl.exe' -ArgumentList '-d', $WslDistro, '--', 'whoami' `
      -RedirectStandardOutput $tmp -WindowStyle Hidden -PassThru
    if ($wp.WaitForExit(15000) -and (Test-Path $tmp)) {
      $WslUser = (Get-Content $tmp -Raw).Trim()
    }
  } catch { }
  finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}
if (-not $WslUser -or $WslUser -notmatch '^[A-Za-z0-9._-]+$') {
  Info 'WARNING: could not detect a WSL user; pass -WslUser <name> for the clcd route'
  $WslUser = 'USER'
}

# ---------- CLIProxyAPI ----------
$appDir = Join-Path $CpaHome "app-$CpaVersion"
$exe = Join-Path $appDir 'cli-proxy-api.exe'
New-Item -ItemType Directory -Force $CpaHome | Out-Null

if (-not (Test-Path $exe)) {
  if ($SkipDownload) { Die "cli-proxy-api.exe is missing at $exe and -SkipDownload was set" }
  $asset = "CLIProxyAPI_${CpaVersion}_windows_amd64.zip"
  $base = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v$CpaVersion"
  $zip = Join-Path $CpaHome $asset
  $sum = Join-Path $CpaHome 'checksums.txt'
  $curlArgs = @('-L', '--fail', '--silent', '--show-error', '--max-time', '300')
  if ($Proxy) { $curlArgs += @('--proxy', $Proxy) }
  Info "downloading $asset"
  & curl.exe @curlArgs -o $zip "$base/$asset"
  if ($LASTEXITCODE -ne 0) { Die 'download failed; pass -Proxy http://127.0.0.1:7897 or use -SkipDownload' }
  & curl.exe @curlArgs -o $sum "$base/checksums.txt"
  if ($LASTEXITCODE -ne 0) { Die 'checksums.txt download failed' }
  $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  $line = Select-String -Path $sum -Pattern ([regex]::Escape($asset)) | Select-Object -First 1
  if (-not $line -or $line.Line -notmatch '^([0-9a-f]{64})') { Die 'could not parse checksum' }
  if ($Matches[1] -ne $actual) { Die "checksum mismatch for $asset" }
  Info 'checksum OK'
  New-Item -ItemType Directory -Force $appDir | Out-Null
  Expand-Archive -Path $zip -DestinationPath $appDir -Force
}
if (-not (Test-Path $exe)) { Die "cli-proxy-api.exe still missing at $exe" }

# ---------- private configuration ----------
$cfg = Join-Path $CpaHome 'config.yaml'
$authDir = Join-Path $env:USERPROFILE '.cli-proxy-api'
New-Item -ItemType Directory -Force $authDir | Out-Null

$clientKey = ''
if (Test-Path $cfg) {
  $hit = Select-String -Path $cfg -Pattern 'sk-local-[A-Za-z0-9]+' | Select-Object -First 1
  if ($hit) { $clientKey = $hit.Matches[0].Value }
  Info "keeping existing $cfg"
}
if (-not $clientKey) {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $clientKey = 'sk-local-' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
if (-not (Test-Path $cfg)) {
  $tpl = Get-Content (Join-Path $repo 'config\cliproxyapi.yaml.template') -Raw
  $tpl = $tpl.Replace('__CPA_PORT__', "$CpaPort")
  $tpl = $tpl.Replace('__CLASH_PORT__', "$ClashPort")
  $tpl = $tpl.Replace('__AUTH_DIR__', ($authDir -replace '\\', '/'))
  $tpl = $tpl.Replace('__CLIENT_KEY__', $clientKey)
  Set-Content -Path $cfg -Value $tpl -Encoding utf8
  Info "wrote $cfg"
}

# ---------- relay ----------
$relay = Join-Path $CpaHome 'proxy-relay.js'
Copy-Item (Join-Path $repo 'relay\proxy-relay.js') $relay -Force
Info "installed relay at $relay"

# ---------- launchers ----------
New-Item -ItemType Directory -Force $binDir | Out-Null
New-Item -ItemType Directory -Force $profileDir | Out-Null
foreach ($f in 'cdn.cmd', 'clcd.cmd', 'clai.cmd') {
  Copy-Item (Join-Path $repo "bin\$f") (Join-Path $binDir $f) -Force
}
Info "installed launchers into $binDir"

# ---------- route environment ----------
$route = @(
  'REM Generated by install.ps1. Contains a local client key; keep it private.'
  ('set "CDR_CPA_EXE={0}"' -f $exe)
  ('set "CDR_CPA_CFG={0}"' -f $cfg)
  ('set "CDR_CPA_BASE_URL=http://127.0.0.1:{0}"' -f $CpaPort)
  ('set "CDR_CLIENT_KEY={0}"' -f $clientKey)
  ('set "CDR_MODEL={0}"' -f $Model)
  ('set "CDR_FAST_MODEL={0}"' -f $FastModel)
  ('set "CDR_CONTEXT={0}"' -f $Context)
  ('set "CDR_COMPACT={0}"' -f [math]::Floor($Context * 0.8))
  'set "CDR_CLAUDE_HOME=%USERPROFILE%\.claude-codex"'
  ('set "CDR_RELAY_JS={0}"' -f $relay)
  ('set "CDR_RELAY_PORT={0}"' -f $RelayPort)
  ('set "CDR_WSL_DISTRO={0}"' -f $WslDistro)
  ('set "CDR_WSL_USER={0}"' -f $WslUser)
) -join "`r`n"
Set-Content -Path $envFile -Value $route -Encoding ascii
Info "wrote $envFile"

# ---------- Claude profile ----------
if ($BypassPermissions) {
  $settingsPath = Join-Path $profileDir 'settings.json'
  if (-not (Test-Path $settingsPath)) {
    @{ permissions = @{ defaultMode = 'bypassPermissions' }; skipDangerousModePermissionPrompt = $true } |
      ConvertTo-Json -Depth 4 | Set-Content -Path $settingsPath -Encoding utf8
    Info "wrote $settingsPath (bypassPermissions)"
  }
}

# ---------- relay ----------
if (-not (Get-NetTCPConnection -LocalPort $RelayPort -State Listen -ErrorAction SilentlyContinue)) {
  Info 'starting WSL proxy relay'
  Start-Process -FilePath 'node.exe' -ArgumentList $relay -WindowStyle Hidden
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 250
    if (Get-NetTCPConnection -LocalPort $RelayPort -State Listen -ErrorAction SilentlyContinue) { break }
  }
}

# ---------- next steps ----------
function ToWslPath([string]$p) {
  $drive = $p.Substring(0, 1).ToLower()
  $rest = $p.Substring(2) -replace '\\', '/'
  return "/mnt/$drive$rest"
}
$repoWsl = ToWslPath $repo
$authWsl = (ToWslPath $authDir) + '/codex-*.json'

Write-Host ''
Info 'Windows side installed.'
Write-Host ''
Write-Host 'Next: log in to ChatGPT/Codex (one time, opens a browser):'
Write-Host ('  "{0}" --config "{1}" --codex-login --login-proxy http://127.0.0.1:{2}' -f $exe, $cfg, $ClashPort)
Write-Host ''
Write-Host 'Then install the WSL side (reuses the credential just created):'
Write-Host ('  wsl -d {0} -- bash "{1}/install/install-wsl.sh" --relay-port {2} --auth-json "{3}"' -f $WslDistro, $repoWsl, $RelayPort, $authWsl)
Write-Host ''
Write-Host 'Usage: cdn   (native Windows Claude Code)'
Write-Host '       clcd  (upstream bridge inside WSL)'
Write-Host '       clai  (manage the WSL runtime)'
