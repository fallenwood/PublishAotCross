#requires -Version 7.0
<#
Integration checks for the actual nupkg; no Pester or Python dependency.
Requires .NET 8+ and NuGet access or cached packages. DOTNET selects the SDK.
The temporary test package omits the optional Windows llvm-objcopy executable.
#>
param(
    [string]$Dotnet = $(if ($env:DOTNET) { $env:DOTNET } else { 'dotnet' }),
    [switch]$KeepTemporaryFiles
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path ([System.IO.Path]::GetTempPath()) "publishaotcross-test-$([Guid]::NewGuid().ToString('N'))"
$feed = Join-Path $work 'feed'
$version = "42.42.44-ondemand-test.$([Guid]::NewGuid().ToString('N'))"
$script:Passed = 0
$script:Skipped = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:CommandNumber = 0
$completed = $false

function Invoke-CommandLine {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [hashtable]$Environment = @{},
        [int]$ExpectedExitCode = 0
    )

    $script:CommandNumber++
    $log = Join-Path $work "command-$($script:CommandNumber).log"
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($key in $Environment.Keys) {
        $startInfo.Environment[$key] = $Environment[$key]
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        Set-Content $log -Value ("$Executable $($Arguments -join ' ')`n$stdout`n$stderr") -Encoding utf8
        if ($process.ExitCode -ne $ExpectedExitCode) {
            throw "$Executable exited with code $($process.ExitCode), expected $ExpectedExitCode. Log: $log`n$stdout`n$stderr"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Invoke-Dotnet {
    param([string[]]$Arguments)
    return (Invoke-CommandLine -Executable $Dotnet -Arguments $Arguments).Trim()
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw "${Message}: expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-SetEqual {
    param([string[]]$Actual, [string[]]$Expected, [string]$Message)
    Assert-Equal (@($Actual | Sort-Object -Unique) -join ',') (@($Expected | Sort-Object -Unique) -join ',') $Message
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body, [switch]$Skip)
    if ($Skip) {
        $script:Skipped++
        Write-Host "SKIP: $Name (requires a supported non-Windows host)"
        return
    }
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS: $Name"
    } catch {
        $script:Failures.Add("${Name}: $_")
        Write-Host "FAIL: ${Name}: $_" -ForegroundColor Red
    }
}

function Assert-StaticLinuxExecutable {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    Assert-True ($bytes.Length -ge 64) 'ELF header missing'
    Assert-Equal $bytes[0] 127 'ELF magic'
    Assert-Equal ([System.Text.Encoding]::ASCII.GetString($bytes, 1, 3)) 'ELF' 'ELF magic'
    Assert-Equal $bytes[4] 2 'ELF64 class'
    Assert-Equal $bytes[5] 1 'Little-endian ELF encoding'
    Assert-Equal ([System.BitConverter]::ToUInt16($bytes, 16)) 2 'Static workaround produces a non-PIE executable'
    $offset = [System.BitConverter]::ToUInt64($bytes, 32)
    $entrySize = [System.BitConverter]::ToUInt16($bytes, 54)
    $count = [System.BitConverter]::ToUInt16($bytes, 56)
    Assert-True ($count -gt 0 -and $entrySize -ge 56) 'ELF program headers missing'
    Assert-True ($offset + $entrySize * $count -le $bytes.Length) 'ELF program headers out of bounds'
    for ($index = 0; $index -lt $count; $index++) {
        $type = [System.BitConverter]::ToUInt32($bytes, [int]($offset + $entrySize * $index))
        Assert-True ($type -ne 2 -and $type -ne 3) 'Static binary must have no PT_DYNAMIC or PT_INTERP segment'
    }
}

function New-Consumer {
    param([string]$Name)
    $directory = Join-Path $work $Name
    $null = New-Item $directory -ItemType Directory
    $project = Join-Path $directory 'Consumer.csproj'
    Set-Content $project -Encoding utf8 -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <StripSymbols>false</StripSymbols>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Fallenwood.PublishAotCross" Version="$version" />
  </ItemGroup>
</Project>
"@
    Set-Content (Join-Path $directory 'Program.cs') -Value 'System.Console.WriteLine("On demand");' -Encoding utf8
    $escapedFeed = [System.Security.SecurityElement]::Escape($feed)
    Set-Content (Join-Path $directory 'NuGet.Config') -Encoding utf8 -Value @"
<configuration>
  <packageSources>
    <clear />
    <add key="test" value="$escapedFeed" />
    <add key="nuget" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="test"><package pattern="Fallenwood.PublishAotCross" /></packageSource>
    <packageSource key="nuget"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
"@
    return $project
}

function Get-ToolchainDownloads {
    param([string]$Project)
    $obj = Join-Path (Split-Path $Project -Parent) 'obj'
    if (Test-Path $obj) {
        foreach ($assets in Get-ChildItem $obj -Recurse -Filter project.assets.json) {
            if ($assets.FullName -match '[\\/]aot-toolchain[\\/]') {
                $graph = Get-Content $assets.FullName -Raw | ConvertFrom-Json -AsHashtable
                foreach ($framework in $graph.project.frameworks.Values) {
                    foreach ($dependency in $framework.downloadDependencies) {
                        $dependency.name
                    }
                }
            }
        }
    }
}

try {
    $null = New-Item $feed -ItemType Directory -Force
    $omit = Join-Path $work 'pack.targets'
    Set-Content $omit -Encoding utf8 -Value @'
<Project>
  <Target Name="OmitOptionalObjcopy" BeforeTargets="_GetPackageFiles">
    <ItemGroup><None Remove="llvm-objcopy.exe" /></ItemGroup>
  </Target>
</Project>
'@
    $null = Invoke-Dotnet @('pack', (Join-Path $repoRoot 'src/Fallenwood.PublishAotCross.nuproj'), "-p:Version=$version", "-p:CustomAfterMicrosoftCommonTargets=$omit", '-o', $feed)
    $package = Join-Path $feed "Fallenwood.PublishAotCross.$version.nupkg"
    $sourceProject = Join-Path $PSScriptRoot 'Hello.csproj'
    $properties = (Invoke-Dotnet @('msbuild', $sourceProject, '-getProperty:HostRuntimeIdentifier,ZigVersion,LLDVersion,LLDRevision,XWinVersion,XWinRevision') | ConvertFrom-Json -AsHashtable).Properties
    $hostRid = $properties.HostRuntimeIdentifier

    Invoke-Test 'Unix Zig wrappers preserve argument boundaries and exit codes' -Skip:$IsWindows {
        $fakeBin = Join-Path $work 'fake zig'
        $null = New-Item $fakeBin -ItemType Directory
        $fakeZig = Join-Path $fakeBin 'zig'
        Set-Content $fakeZig -Encoding utf8 -Value @'
#!/bin/sh
printf '%s\0' "$@"
exit "${FAKE_ZIG_EXIT_CODE:-0}"
'@
        $null = Invoke-CommandLine -Executable 'chmod' -Arguments @('+x', $fakeZig)
        $environment = @{ PATH = "$fakeBin$([System.IO.Path]::PathSeparator)$env:PATH" }
        $inputArguments = @(
            'folder with spaces/测 试.o', '-o', 'output directory/app',
            '-static-pie', '-Wl,-z,relro', '-Wl,-z,now', '--target=x86_64-linux-musl',
            '-lz', '-pie', '-Wl,-pie', '-Wl,-e0x0', '-Wl,--defsym,__xmknod=mknod',
            '-Wl,--discard-all', '--discard-all', "'-Wl,-rpath,`$ORIGIN'",
            'file -pie .o', 'file -static-pie.o', 'file --discard-all.o', 'literal [x]*?.o', '', '-pie'
        )
        $expectedArguments = @(
            'cc', '-Wl,-u,__Module', 'folder with spaces/测 试.o', '-o', 'output directory/app',
            '-static', '-Wl,-z,relro', '-Wl,-z,now', '--target=x86_64-linux-musl',
            '-Wl,--as-needed', '--as-needed', '-Wl,-rpath,$ORIGIN',
            'file -pie .o', 'file -static-pie.o', 'file --discard-all.o', 'literal [x]*?.o', ''
        )
        $expectedOutput = ($expectedArguments -join [char]0) + [char]0
        foreach ($wrapper in @('clang', 'gcc')) {
            $wrapperPath = Join-Path $repoRoot "src/$wrapper"
            $environment.FAKE_ZIG_EXIT_CODE = '0'
            $actual = Invoke-CommandLine -Executable 'bash' -Arguments (@($wrapperPath) + $inputArguments) -Environment $environment
            Assert-Equal $actual $expectedOutput "Exact Zig argv for $wrapper"
            $environment.FAKE_ZIG_EXIT_CODE = '33'
            $null = Invoke-CommandLine -Executable 'bash' -Arguments @($wrapperPath, '-static-pie') -Environment $environment -ExpectedExitCode 33
        }
    }

    Invoke-Test 'Merged Hello project supports framework/static parameters' {
        $projects = @(Get-ChildItem $PSScriptRoot -Filter 'Hello*.csproj')
        Assert-SetEqual $projects.BaseName @('Hello', 'HelloNupkg') 'Only the two parameterized projects should remain'
        foreach ($project in $projects) {
            [xml]$xml = Get-Content $project.FullName -Raw
            Assert-Equal $xml.Project.Sdk 'Microsoft.NET.Sdk' 'SDK-style project'
            foreach ($name in @('ImplicitUsings', 'Nullable')) {
                Assert-Equal $xml.SelectSingleNode("//${name}").InnerText 'enable' $name
            }
            Assert-Equal $xml.SelectSingleNode('//PublishAot').InnerText 'true' 'NativeAOT enabled'
            if ($project.BaseName -eq 'HelloNupkg') {
                Assert-Equal $xml.SelectNodes('//Import').Count 0 'Nupkg consumer must not import source targets'
                $references = $xml.SelectNodes('//PackageReference')
                Assert-Equal $references.Count 1 'Single nupkg reference'
                Assert-Equal $references[0].Include 'Fallenwood.PublishAotCross' 'Nupkg reference'
            } else {
                Assert-Equal $xml.SelectNodes('//Import').Count 1 'Single source import'
                Assert-Equal $xml.Project.Import.Project '../src/Fallenwood.PublishAotCross.targets' 'Source targets'
                Assert-Equal $xml.SelectNodes('//PackageReference').Count 0 'Source test has no nupkg reference'
            }
        }
        foreach ($framework in @('net8.0', 'net9.0', 'net10.0')) {
            foreach ($static in @('false', 'true')) {
                $values = (Invoke-Dotnet @('msbuild', $sourceProject, "-p:TargetFramework=$framework", "-p:StaticExecutable=$static", '-getProperty:TargetFramework,StaticExecutable,InvariantGlobalization,OutputPath,IntermediateOutputPath') | ConvertFrom-Json -AsHashtable).Properties
                Assert-Equal $values.TargetFramework $framework 'Framework parameter'
                Assert-Equal $values.StaticExecutable $static 'Static executable parameter'
                if ($static -eq 'true') {
                    Assert-Equal $values.InvariantGlobalization 'true' 'Static globalization default'
                    Assert-True ($values.OutputPath -match '[\\/]static[\\/]') 'Static binary output must be isolated'
                    Assert-True ($values.IntermediateOutputPath -match '[\\/]static[\\/]') 'Static intermediate output must be isolated'
                }
            }
        }
    }

    Invoke-Test 'Nupkg has no fixed toolchain dependencies' {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package)
        try {
            $entry = @($archive.Entries | Where-Object FullName -Like '*.nuspec')[0]
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                [xml]$spec = $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
            }
            Assert-Equal $spec.SelectNodes("//*[local-name()='dependency']").Count 0 'Fixed dependency count'
            Assert-True ($null -ne $archive.GetEntry('build/Toolchain.proj')) 'Toolchain project missing from nupkg'
            Assert-True ($null -ne $archive.GetEntry('build/RestoreToolchain.targets')) 'Restore targets missing from nupkg'
        } finally {
            $archive.Dispose()
        }
    }

    Invoke-Test 'Plain restore does not restore toolchains' {
        $project = New-Consumer 'plain'
        $null = Invoke-Dotnet @('restore', $project, '-p:RuntimeIdentifier=win-x64')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @() 'Unexpected toolchain restore'
        $graph = Get-Content (Join-Path (Split-Path $project -Parent) 'obj/project.assets.json') -Raw | ConvertFrom-Json -AsHashtable
        $tools = @($graph.libraries.Keys | Where-Object { $_ -match '^(vezel\.zig\.|lld\.link\.|xwin\.store\.)' })
        Assert-Equal $tools.Count 0 'Unexpected transitive toolchain dependencies'
    }

    Invoke-Test 'Toolchain packages follow host and target selection' {
        $cases = @(
            @{ HostRid = 'linux-x64'; Kind = 'zig'; Arch = 'arm64'; Packages = @('Vezel.Zig.Toolsets.linux-x64') },
            @{ HostRid = 'win-arm64'; Kind = 'zig'; Arch = 'x64'; Packages = @('Vezel.Zig.Toolsets.win-arm64') },
            @{ HostRid = 'linux-x64'; Kind = 'xwin'; Arch = 'x64'; Packages = @('LLD.Link.Toolsets.linux-x64', 'XWin.Store.x64') },
            @{ HostRid = 'linux-arm64'; Kind = 'xwin'; Arch = 'arm64'; Packages = @('LLD.Link.Toolsets.linux-arm64', 'XWin.Store.arm64') },
            @{ HostRid = 'osx-arm64'; Kind = 'xwin'; Arch = 'x64'; Packages = @('LLD.Link.Toolsets.osx-arm64', 'XWin.Store.x64') }
        )
        foreach ($case in $cases) {
            $arguments = @('msbuild', (Join-Path $repoRoot 'src/Toolchain.proj'), '-getItem:PackageDownload', "-p:AotToolchainHost=$($case.HostRid)", "-p:AotToolchainKind=$($case.Kind)", "-p:AotToolchainArch=$($case.Arch)")
            foreach ($name in @('ZigVersion', 'LLDVersion', 'LLDRevision', 'XWinVersion', 'XWinRevision')) {
                $arguments += "-p:${name}=$($properties[$name])"
            }
            $items = (Invoke-Dotnet $arguments | ConvertFrom-Json -AsHashtable).Items.PackageDownload
            Assert-SetEqual @($items.Identity) $case.Packages "Packages for $($case.HostRid) / $($case.Kind) / $($case.Arch)"
        }
    }

    Invoke-Test 'Windows nupkg publish restores only host LLD and target store' -Skip:($hostRid -notin @('linux-x64', 'linux-arm64', 'osx-arm64')) {
        $project = New-Consumer 'windows'
        $null = Invoke-Dotnet @('restore', $project, '-p:RuntimeIdentifier=win-x64')
        $null = Invoke-Dotnet @('publish', $project, '-r', 'win-x64', '-c', 'Release', '--no-restore')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @("LLD.Link.Toolsets.$hostRid", 'XWin.Store.x64') 'Windows toolchain packages'
        Assert-True (Test-Path (Join-Path (Split-Path $project -Parent) 'bin/Release/net8.0/win-x64/publish/Consumer.exe')) 'Windows executable missing'
    }

    Invoke-Test 'Zig nupkg publish restores only host Zig' {
        $project = New-Consumer 'zig'
        $null = Invoke-Dotnet @('publish', $project, '-r', 'linux-musl-x64', '-c', 'Release', '-p:AotPreferCustom=true')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @("Vezel.Zig.Toolsets.$hostRid") 'Zig toolchain packages'
        Assert-True (Test-Path (Join-Path (Split-Path $project -Parent) 'bin/Release/net8.0/linux-musl-x64/publish/Consumer')) 'Linux executable missing'
    }

    Invoke-Test 'Static nupkg publish produces a statically linked Linux executable' {
        $project = New-Consumer 'static'
        $null = Invoke-Dotnet @('publish', $project, '-r', 'linux-musl-x64', '-c', 'Release', '-p:StaticExecutable=true', '-p:InvariantGlobalization=true', '-p:AotPreferCustom=true')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @("Vezel.Zig.Toolsets.$hostRid") 'Static toolchain packages'
        $binary = Join-Path (Split-Path $project -Parent) 'bin/Release/net8.0/linux-musl-x64/publish/Consumer'
        Assert-StaticLinuxExecutable $binary
        if ($hostRid -eq 'linux-x64') {
            $output = Invoke-CommandLine -Executable $binary -Arguments @()
            Assert-Equal $output.Trim() 'On demand' 'Static executable output'
        }
    }

    Invoke-Test 'Unix gcc fallback also publishes a static nupkg executable' -Skip:$IsWindows {
        $project = New-Consumer 'static-gcc'
        $null = Invoke-Dotnet @('publish', $project, '-r', 'linux-musl-x64', '-c', 'Release', '-p:StaticExecutable=true', '-p:InvariantGlobalization=true', '-p:AotPreferCustom=true', '-p:CppCompilerAndLinker=gcc')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @("Vezel.Zig.Toolsets.$hostRid") 'Fallback static toolchain packages'
        $binary = Join-Path (Split-Path $project -Parent) 'bin/Release/net8.0/linux-musl-x64/publish/Consumer'
        Assert-StaticLinuxExecutable $binary
        if ($hostRid -eq 'linux-x64') {
            $output = Invoke-CommandLine -Executable $binary -Arguments @()
            Assert-Equal $output.Trim() 'On demand' 'Fallback static executable output'
        }
    }

    Invoke-Test 'External Zig does not restore toolchains' {
        $project = New-Consumer 'external'
        $null = Invoke-Dotnet @('msbuild', $project, '-target:SelectAotToolchain,RestoreAotToolchain', '-restore', '-p:RuntimeIdentifier=linux-musl-x64', '-p:UseExternalZig=true', '-p:AotPreferCustom=true')
        Assert-SetEqual @(Get-ToolchainDownloads $project) @() 'External Zig toolchain packages'
    }

    Invoke-Test 'Native platform does not restore toolchains' {
        $project = New-Consumer 'native'
        $null = Invoke-Dotnet @('msbuild', $project, '-target:SelectAotToolchain,RestoreAotToolchain', '-restore', "-p:RuntimeIdentifier=$hostRid")
        Assert-SetEqual @(Get-ToolchainDownloads $project) @() 'Native toolchain packages'
    }

    Write-Host "Results: $($script:Passed) passed, $($script:Skipped) skipped, $($script:Failures.Count) failed."
    if ($script:Failures.Count -gt 0) {
        throw ($script:Failures -join "`n")
    }
    $completed = $true
} finally {
    if ($completed -and -not $KeepTemporaryFiles) {
        Remove-Item $work -Recurse -Force
    } else {
        Write-Host "Temporary projects and dotnet logs retained at: $work"
    }
}
