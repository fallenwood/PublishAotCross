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

It relies on xwin and lld in system path to work.

1. Install XWin and lld and make sure the executables are in path

2. To your project that is already using Native AOT, add a reference to this NuGet package.

3. Publish for one of the newly available RIDs:
    * `dotnet publish -r win-x64`
    * `dotnet publish -r win-arm64`

### Use Zig as c compiler on same host

This package auto detects if host and target platforms are different to determine if Zig is used or not. Even though on the same platform, Zig can also be used as the dropped in C Compiler with

```
dotnet publish -r linux-x64 /p:PublishAot=true /p:AotPreferCustom=true
```

## Tested Variants

|                    |(Host)Windows x64|Linux GNU x64|Linux GNU arm64|Linux MUSL x64|Linux MUSL arm64| macOS x64 | macOS arm64 |
|--------------------|-----------------|-------------|---------------|--------------|----------------|-----------|-------------|
|(target)Windows x64 |N/A              |O            |N/A            |N/A           |N/A             |N/A        |N/A          |
|Linux GNU x64       |O                |O            |O              |N/A           |N/A             |O          |N/A          |
|Linux GNU arm64     |O                |O            |O              |N/A           |N/A             |O          |N/A          |
|Linux MUSL x64      |O                |O            |O              |N/A           |N/A             |O          |N/A          |
|Linux MUSL arm64    |O                |O            |O              |N/A           |N/A             |O          |N/A          |
|Linux MUSL arm      |N/A              |O            |N/A            |N/A           |N/A             |O          |N/A          |
|macOS x64           |X                |X            |X              |X             |X               |N/A        |X            |
|macOS arm64         |X                |X            |X              |X             |X               |X          |N/A          |

Notes: `N/A` means it's might work but not tested.

