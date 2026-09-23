param(
    [string]$Version = '42.42.42-dev'
)

$ErrorActionPreference = 'Stop'

# Quoted so Windows PowerShell 5 doesn't split the argument at the version's dots
dotnet pack "$PSScriptRoot/src/Fallenwood.PublishAotCross.nuproj" "-p:Version=$Version" -o "$PSScriptRoot/artifacts"
if ($LASTEXITCODE -ne 0) {
    $code = $LASTEXITCODE
    $Host.UI.WriteErrorLine("Pack failed with exit code $code")
    exit $code
}

Write-Host "Package created: artifacts/Fallenwood.PublishAotCross.$Version.nupkg"
