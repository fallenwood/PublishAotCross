@echo off
setlocal

set VERSION=%~1
if "%VERSION%"=="" set VERSION=42.42.42-dev

dotnet pack src\Fallenwood.PublishAotCross.nuproj -p:Version=%VERSION% -o .\artifacts
if %ERRORLEVEL% neq 0 (
  echo Pack failed with exit code %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Package created: artifacts\Fallenwood.PublishAotCross.%VERSION%.nupkg
