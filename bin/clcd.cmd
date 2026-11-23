@echo off
setlocal
REM Route 2: the claude-driven-ai-providers clcd bridge running inside WSL,
REM still driven by the same Codex (ChatGPT) subscription.

set "ENVFILE=%USERPROFILE%\.claude-codex\route.env.cmd"
if not exist "%ENVFILE%" (
  echo [clcd] missing %ENVFILE%
  echo [clcd] run install\install.ps1 from this repository first
  exit /b 1
)
call "%ENVFILE%"

REM WSL cannot reach the Windows loopback, so a TCP relay exposes Clash to the
REM Linux side. Start it when it is not already listening.
powershell -NoProfile -WindowStyle Hidden -Command "if (-not (Get-NetTCPConnection -LocalPort %CDR_RELAY_PORT% -State Listen -ErrorAction SilentlyContinue)) { Start-Process -FilePath 'node.exe' -ArgumentList '%CDR_RELAY_JS%' -WindowStyle Hidden; for ($i=0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 250; if (Get-NetTCPConnection -LocalPort %CDR_RELAY_PORT% -State Listen -ErrorAction SilentlyContinue) { break } } }"

wsl.exe -d %CDR_WSL_DISTRO% -- /home/%CDR_WSL_USER%/.local/bin/clcd-run %*
exit /b %errorlevel%
