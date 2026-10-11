PublishAotCross
---

Forked from [MichalStrehovsky/PublishAotCross](https://github.com/MichalStrehovsky/PublishAotCross "")

This is a NuGet package with an MSBuild target to aid in crosscompilation with [PublishAot](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/). It helps resolving following error:

```sh
$ dotnet publish -r linux-x64
Microsoft.NETCore.Native.Publish.targets(59,5): error : Cross-OS native compilation is not supported.
```

This nuget package allows using [Zig](https://ziglang.org/) as the linker/sysroot to allow crosscompiling to linux-x64/linux-arm64/linux-musl-x64/linux-musl-arm64 from a Windows/Linux machine, and [xwin](https://github.com/Jake-Shadle/xwin "") to windows-x64/windows-arm64 from Linux machine.

The xwin implemetation is based on [Windows10CE's project](https://github.com/Windows10CE/PublishAotCrossXWin/tree/master "")

## Usage

### Typical Cross build

Only reference `Fallenwood.PublishAotCross`; no extra toolchain package references are needed. The nupkg has no fixed Zig/LLD/XWin dependencies. During NativeAOT publishing, a separate NuGet restore downloads only the toolchain needed for the current host and target:

| Build scenario | Toolchain packages downloaded |
|---|---|
| Cross-build to Linux/macOS, or `AotPreferCustom=true` on those targets | `Vezel.Zig.Toolsets.<host RID>` |
| Cross-build to `win-x64` | `LLD.Link.Toolsets.<host RID>` + `XWin.Store.x64` |
| Cross-build to `win-arm64` | `LLD.Link.Toolsets.<host RID>` + `XWin.Store.arm64` |
| Same-platform native build without `AotPreferCustom` | None |
| Zig build with `UseExternalZig=true` | None |

Toolchains use the NuGet cache and the consuming project's NuGet configuration (`RestoreSources`, `RestoreConfigFile`, and custom package cache paths are supported). The separate restore writes its assets under the consuming project's `obj/` directory, never into this package. Normal project restore and packing this package do not download toolchains. Even with `dotnet publish --no-restore`, the toolchain restore runs when needed; pre-populate the NuGet cache for offline publishing.

#### Zig

By default it relies on Zig provided by the unofficial [Vezel.Zig.Toolsets](https://github.com/vezel-dev/zig-toolsets) NuGet package. You can specify version of this package using the `ZigVersion` property. Instructions for using your own Zig binaries are near the end of this document.

If you don't want to use Zig from the Vezel.Zig.Toolsets NuGet package, you can specify `/p:UseExternalZig=true`. This will use whatever Zig is on your PATH. [Download](https://ziglang.org/download/) an archive with Zig for your host machine, extract it and place it on your PATH.

1. Optional: [download](https://releases.llvm.org/) LLVM. We only need llvm-objcopy executable so if you care about size, you can delete the rest. The executable needs to be on PATH - you could copy it next to the Zig executable. This step is optional and is required only to strip symbols (make the produced executables smaller). If you don't care about stripping symbols, you can skip it.

2. To your project that is already using Native AOT, add a reference to this NuGet package.

3. Publish for one of the newly available RIDs:
    * `dotnet publish -r linux-x64`
    * `dotnet publish -r linux-arm64`
    * `dotnet publish -r linux-musl-x64`
    * `dotnet publish -r linux-musl-arm64`
    * `dotnet publish -r linux-musl-arm` (Only works for net >= 9.0)

    If you skipped the second optional step to download llvm-objcopy, you must also pass `/p:StripSymbols=false` to the publish command, or you'll see an error instructing you to do that.

Even though Zig allows crosscompiling for Windows as well, it's not possible to crosscompile PublishAot like this due to ABI differences (MSVC vs. MingW ABI).

#### XWin

Publishing automatically restores the host-specific `LLD.Link.Toolsets` package and the target-specific `XWin.Store` package, which provide the linker and Windows SDK/CRT libraries. No system installation of xwin or lld is required on supported hosts. Source-target imports use the same on-demand restore as nupkg consumers.

1. Use a supported host: Linux x64/arm64 or macOS arm64.

2. To your project that is already using Native AOT, add a reference to this NuGet package.

3. Publish for one of the newly available RIDs:
    * `dotnet publish -r win-x64`
    * `dotnet publish -r win-arm64`

### Use Zig as c compiler on same host

This package auto detects if host and target platforms are different to determine if Zig is used or not. Even though on the same platform, Zig can also be used as the dropped in C Compiler with

```
dotnet publish -r linux-x64 /p:PublishAot=true /p:AotPreferCustom=true
```

## Testing source targets

`test/Hello.csproj` is the single source-target test project for every framework and static/non-static variant. It defaults to .NET 8 and non-static publishing. `test/publish_source.ps1` passes `TargetFramework`, `RuntimeIdentifier`, and `StaticExecutable` to it, using the same explicit restore/publish pattern as the nupkg consumer tests:

```powershell
./test/publish_source.ps1 -TargetFrameworks net9.0 -RuntimeIdentifiers win-x64 -NoStripSymbols
./test/publish_source.ps1 -TargetFrameworks net10.0 -RuntimeIdentifiers linux-musl-x64 -StaticExecutable -NoStripSymbols
```

The script explicitly restores each framework/RID before `publish --no-restore`, because CLI implicit restore can drop a `TargetFramework` override. It supports framework/RID arrays, `-UseExternalZig`, and `-NoStripSymbols`; ARM32 tests skip .NET 8. Published outputs are separated under `output-source/<normal-or-static>/<framework>/<RID>/`.

Static builds default to invariant globalization and use separate `bin/static/` and `obj/static/` paths, so they cannot reuse a non-static native binary. Override `InvariantGlobalization` explicitly if needed. Choose target RIDs supported by the host/toolchain. The Unix and Windows Zig wrappers translate the complete `-static-pie` argument to `-static` as a compatibility workaround, producing statically linked, non-PIE Linux executables. Unix wrappers preserve argument boundaries, including paths with spaces; `gcc` delegates to the same implementation as `clang`.

## Testing the local nupkg

Both `Hello.csproj` and `HelloNupkg.csproj` use SDK-style project files with implicit usings and nullable reference types enabled. `Hello.csproj` imports the source targets; `HelloNupkg.csproj` only references the nupkg and does not import source targets.

CI packs a unique package version into `artifacts/` before testing `HelloNupkg.csproj`. Both Linux and Windows runners publish it for .NET 8/9/10: Linux runners cover Linux GNU/MUSL and Windows x64/arm64 targets; Windows runners cover Linux GNU/MUSL targets. The Windows-built .NET 8 Linux x64 binary is also executed on Linux.

To run the same package-consumer tests locally (PowerShell 7+):

```powershell
./nuget_pack.ps1 -Version 42.42.42-dev
./test/publish_nupkg.ps1 -Version 42.42.42-dev -TargetFrameworks @('net8.0', 'net10.0') -RuntimeIdentifiers @('linux-arm64', 'linux-musl-x64', 'win-x64') -NoStripSymbols
```

Choose RIDs supported by your host. `test/nuget.config` restricts `Fallenwood.PublishAotCross` to the local source, and the script verifies that the restored package hash matches the nupkg just built. Outputs are separated under `output-nupkg/<framework>/<RID>/`. ARM32 tests skip .NET 8. Omit `-NoStripSymbols` when symbol-stripping tools are available. Packaging still requires the Windows `llvm-objcopy.exe` downloaded by `src/download-llvm-objcopy.ps1`, as in CI.

## Testing on-demand toolchain restore

Run `pwsh ./test/verify_on_demand.ps1` with PowerShell 7+ and .NET 8+ installed; no Python or Pester is needed. The checks verify the merged source project's framework/static parameters and Unix wrapper argument/exit-code handling, pack the actual nupkg, create consumers with no extra package references, and verify plain restore, host/target package selection, Windows/Zig and static Linux publishing, external Zig, and same-platform builds. Set `DOTNET` or pass `-Dotnet` to choose a specific dotnet executable. NuGet access or cached packages are required. The test package omits the optional Windows `llvm-objcopy.exe`; publishing tests use `StripSymbols=false`.

CI runs this script on Linux and Windows, and publishes the source project's static Linux variant for .NET 8/9/10 on both hosts. Static nupkg tests cover both Unix compiler wrappers and inspect the ELF headers to confirm no `PT_INTERP` or `PT_DYNAMIC` segment; on Linux x64 they also run the resulting executable. Temporary projects and command logs are removed after success and retained on failure; use `-KeepTemporaryFiles` to retain them after a successful run too.

## Tested Variants

|                    |(Host)Windows x64|Linux GNU x64|Linux GNU arm64|Linux MUSL x64|Linux MUSL arm64|
|--------------------|-----------------|-------------|---------------|--------------|----------------|
|(target)Windows x64 |N/A              |O            |N/A            |N/A           |N/A             |
|Linux GNU x64       |O                |O            |O              |N/A           |N/A             |
|Linux GNU arm64     |O                |O            |O              |N/A           |N/A             |
|Linux MUSL x64      |O                |O            |O              |N/A           |N/A             |
|Linux MUSL arm64    |O                |O            |O              |N/A           |N/A             |
|Linux MUSL arm      |N/A              |O            |N/A            |N/A           |N/A             |

Notes: `N/A` means it's might work but not tested.

