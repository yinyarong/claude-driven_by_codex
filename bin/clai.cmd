@echo off
setlocal
REM Management CLI for the WSL-side runtime: clai list | doctor | config | models | probe | map

set "ENVFILE=%USERPROFILE%\.claude-codex\route.env.cmd"
if not exist "%ENVFILE%" (
  echo [clai] missing %ENVFILE%
  echo [clai] run install\install.ps1 from this repository first
  exit /b 1
)
call "%ENVFILE%"

powershell -NoProfile -WindowStyle Hidden -Command "if (-not (Get-NetTCPConnection -LocalPort %CDR_RELAY_PORT% -State Listen -ErrorAction SilentlyContinue)) { Start-Process -FilePath 'node.exe' -ArgumentList '%CDR_RELAY_JS%' -WindowStyle Hidden; for ($i=0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 250; if (Get-NetTCPConnection -LocalPort %CDR_RELAY_PORT% -State Listen -ErrorAction SilentlyContinue) { break } } }"

wsl.exe -d %CDR_WSL_DISTRO% -- /home/%CDR_WSL_USER%/.local/bin/clai-run %*
exit /b %errorlevel%
