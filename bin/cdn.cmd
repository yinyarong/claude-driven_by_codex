@echo off
setlocal
REM Route 1: native Windows Claude Code driven by a Codex (ChatGPT) subscription
REM through CLIProxyAPI. Configuration lives outside this repository.

set "ENVFILE=%USERPROFILE%\.claude-codex\route.env.cmd"
if not exist "%ENVFILE%" (
  echo [cdn] missing %ENVFILE%
  echo [cdn] run install\install.ps1 from this repository first
  exit /b 1
)
call "%ENVFILE%"

REM Make sure CLIProxyAPI is listening; start it minimized if not.
curl.exe -s --noproxy "*" --max-time 2 "%CDR_CPA_BASE_URL%/healthz" 2>nul | findstr /c:"\"status\":\"ok\"" >nul 2>&1
if errorlevel 1 (
  echo [cdn] starting CLIProxyAPI on %CDR_CPA_BASE_URL% ...
  for %%i in ("%CDR_CPA_CFG%") do set "CDR_CPA_DIR=%%~dpi"
  powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%CDR_CPA_EXE%' -ArgumentList '--config','%CDR_CPA_CFG%' -RedirectStandardOutput '%CDR_CPA_DIR%server.out.log' -RedirectStandardError '%CDR_CPA_DIR%server.err.log' -WindowStyle Hidden"
  for /l %%i in (1,1,20) do (
    ping -n 2 127.0.0.1 >nul
    curl.exe -s --noproxy "*" --max-time 2 "%CDR_CPA_BASE_URL%/healthz" 2>nul | findstr /c:"\"status\":\"ok\"" >nul 2>&1
    if not errorlevel 1 goto ready
  )
  echo [cdn] CLIProxyAPI did not start. Run it manually to see the error:
  echo   "%CDR_CPA_EXE%" --config "%CDR_CPA_CFG%"
  exit /b 1
)

:ready
set "ANTHROPIC_BASE_URL=%CDR_CPA_BASE_URL%"
set "ANTHROPIC_AUTH_TOKEN=%CDR_CLIENT_KEY%"
set "ANTHROPIC_API_KEY="
set "ANTHROPIC_MODEL=%CDR_MODEL%"
set "ANTHROPIC_DEFAULT_OPUS_MODEL=%CDR_MODEL%"
set "ANTHROPIC_DEFAULT_FABLE_MODEL=%CDR_MODEL%"
set "ANTHROPIC_DEFAULT_SONNET_MODEL=%CDR_MODEL%"
set "ANTHROPIC_DEFAULT_HAIKU_MODEL=%CDR_FAST_MODEL%"
set "CLAUDE_CODE_SUBAGENT_MODEL=%CDR_FAST_MODEL%"
set "CLAUDE_CODE_MAX_CONTEXT_TOKENS=%CDR_CONTEXT%"
set "CLAUDE_CODE_AUTO_COMPACT_WINDOW=%CDR_COMPACT%"
set "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1"
set "CLAUDE_CONFIG_DIR=%CDR_CLAUDE_HOME%"
set "NO_PROXY=127.0.0.1,localhost"
set "no_proxy=127.0.0.1,localhost"

REM --setting-sources user prevents a .claude\settings.json in the working
REM directory from overriding the gateway environment below.
claude --setting-sources user %*
exit /b %errorlevel%
