param(
    [string]$Version = '42.42.42-dev',
    [string[]]$TargetFrameworks = @('net8.0', 'net9.0', 'net10.0'),
    [Parameter(Mandatory = $true)]
    [string[]]$RuntimeIdentifiers,
    [switch]$NoStripSymbols
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$packagePath = Join-Path $repoRoot "artifacts/Fallenwood.PublishAotCross.$Version.nupkg"
if (-not (Test-Path $packagePath)) {
    throw "Local nupkg not found: $packagePath. Run nuget_pack.ps1 -Version $Version first."
}

$project = Join-Path $PSScriptRoot 'HelloNupkg.csproj'
$config = Join-Path $PSScriptRoot 'nuget.config'
$stripSymbols = (-not $NoStripSymbols).ToString().ToLowerInvariant()

foreach ($framework in $TargetFrameworks) {
    foreach ($rid in $RuntimeIdentifiers) {
        if ($framework -eq 'net8.0' -and $rid -eq 'linux-musl-arm') {
            Write-Host "Skipping $framework / ${rid}: NativeAOT ARM32 requires .NET 9+."
            continue
        }

        $properties = @(
            "-p:TargetFramework=$framework",
            "-p:PublishAotCrossPackageVersion=$Version",
            "-p:RuntimeIdentifier=$rid",
            "-p:StripSymbols=$stripSymbols"
        )
        $output = Join-Path $repoRoot "output-nupkg/$framework/$rid"
        Write-Host "Testing local nupkg $Version -> $framework / $rid"

        # The source mapping restricts Fallenwood.PublishAotCross to artifacts/.
        dotnet restore $project --configfile $config @properties
        if ($LASTEXITCODE -ne 0) {
            throw "Local nupkg restore failed for $framework / $rid (exit $LASTEXITCODE)."
        }

        # Fail if an old cached package was used instead of the nupkg just built.
        $assets = Get-Content (Join-Path $PSScriptRoot 'obj/project.assets.json') -Raw | ConvertFrom-Json -AsHashtable
        $library = $assets.libraries["Fallenwood.PublishAotCross/$Version"]
        if ($null -eq $library) {
            throw "Expected Fallenwood.PublishAotCross/$Version in restored assets."
        }
        $localHash = (Get-FileHash $packagePath -Algorithm SHA512).Hash
        $matchedPackage = $false
        foreach ($folder in $assets.packageFolders.Keys) {
            $cachedPackage = Join-Path $folder "$($library.path)/fallenwood.publishaotcross.$($Version.ToLowerInvariant()).nupkg"
            if (Test-Path $cachedPackage) {
                if ((Get-FileHash $cachedPackage -Algorithm SHA512).Hash -ne $localHash) {
                    throw "Cached package does not match local nupkg: $cachedPackage"
                }
                $matchedPackage = $true
                break
            }
        }
        if (-not $matchedPackage) {
            throw 'Restored nupkg was not found in the NuGet package folders.'
        }

        dotnet publish $project -c Release --no-restore @properties "-p:RestoreConfigFile=$config" -o $output
        if ($LASTEXITCODE -ne 0) {
            throw "Local nupkg publish failed for $framework / $rid (exit $LASTEXITCODE)."
        }
    }
}
