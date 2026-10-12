#requires -Version 7.0
param(
    [string[]]$TargetFrameworks = @('net8.0', 'net9.0', 'net10.0'),
    [Parameter(Mandatory = $true)]
    [string[]]$RuntimeIdentifiers,
    [switch]$StaticExecutable,
    [switch]$UseExternalZig,
    [switch]$NoStripSymbols
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$project = Join-Path $PSScriptRoot 'Hello.csproj'
$config = Join-Path $PSScriptRoot 'nuget.config'
$variant = 'normal'
if ($StaticExecutable) {
    $variant = 'static'
}

foreach ($framework in $TargetFrameworks) {
    foreach ($rid in $RuntimeIdentifiers) {
        if ($framework -eq 'net8.0' -and $rid -eq 'linux-musl-arm') {
            Write-Host "Skipping $framework / ${rid}: NativeAOT ARM32 requires .NET 9+."
            continue
        }
        $properties = @(
            "-p:TargetFramework=$framework",
            "-p:RuntimeIdentifier=$rid",
            '-p:Configuration=Release',
            '-p:SelfContained=true',
            "-p:StaticExecutable=$($StaticExecutable.IsPresent.ToString().ToLowerInvariant())",
            "-p:UseExternalZig=$($UseExternalZig.IsPresent.ToString().ToLowerInvariant())",
            "-p:StripSymbols=$((-not $NoStripSymbols).ToString().ToLowerInvariant())"
        )
        $output = Join-Path $repoRoot "output-source/$variant/$framework/$rid"
        Write-Host "Testing source targets -> $framework / $rid / $variant"

        # Match publish's configuration and self-contained mode, including on SDK 8.
        # CLI implicit restore can drop TargetFramework; restore it explicitly instead.
        dotnet restore $project --configfile $config @properties
        if ($LASTEXITCODE -ne 0) {
            throw "Source restore failed for $framework / $rid / $variant (exit $LASTEXITCODE)."
        }
        dotnet publish $project -c Release --no-restore @properties "-p:RestoreConfigFile=$config" -o $output
        if ($LASTEXITCODE -ne 0) {
            throw "Source publish failed for $framework / $rid / $variant (exit $LASTEXITCODE)."
        }
    }
}
