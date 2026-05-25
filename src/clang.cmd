@echo off

setlocal EnableExtensions EnableDelayedExpansion

set "clangcmd="
for %%I in (%~n0.cmd) do set "clangcmd=%%~$PATH:I"

if not defined clangcmd (
  echo Error: unable to locate clang.cmd on the PATH.
  exit /B 1
)

for %%I in ("!clangcmd!") do set "clangps1=%%~dpIclang.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!clangps1!" %*
set "exitcode=%ERRORLEVEL%"
endlocal & exit /B %exitcode%
