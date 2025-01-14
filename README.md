PublishAotCross
---

Forked from [MichalStrehovsky/PublishAotCross](https://github.com/MichalStrehovsky/PublishAotCross "")

This is a NuGet package with an MSBuild target to aid in crosscompilation with [PublishAot](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/). It helps resolving following error:

```sh
$ dotnet publish -r linux-x64
Microsoft.NETCore.Native.Publish.targets(59,5): error : Cross-OS native compilation is not supported.
```

This nuget package allows using [Zig](https://ziglang.org/) as the linker/sysroot to allow crosscompiling to linux-x64/linux-arm64/linux-musl-x64/linux-musl-arm64 from a Windows/Linux machine.

## Usage

### Typical Cross build

1. [Download](https://ziglang.org/download/) an archive with Zig for your host machine, extract it and place it on your PATH. I'm using zig 0.13.0 stable.

2. Optional: [download](https://releases.llvm.org/) LLVM. We only need llvm-objcopy executable so if you care about size, you can delete the rest. The executable needs to be on PATH - you could copy it next to the Zig executable. This step is optional and is required only to strip symbols (make the produced executables smaller). If you don't care about stripping symbols, you can skip it.

3. To your project that is already using Native AOT, add a reference to this NuGet package.

4. Publish for one of the newly available RIDs:
    * `dotnet publish -r linux-x64`
    * `dotnet publish -r linux-arm64`
    * `dotnet publish -r linux-musl-x64`
    * `dotnet publish -r linux-musl-arm64`
    * `dotnet publish -r linux-musl-arm` (Only works for net >= 9.0)

    If you skipped the second optional step to download llvm-objcopy, you must also pass `/p:StripSymbols=false` to the publish command, or you'll see an error instructing you to do that.

Even though Zig allows crosscompiling for Windows as well, it's not possible to crosscompile PublishAot like this due to ABI differences (MSVC vs. MingW ABI).

### Use Zig as c compiler on same host

This package auto detects if host and target platforms are different to determine if Zig is used or not. Even though on the same platform, Zig can also be used as the dropped in C Compiler with

```
dotnet publish -r linux-x64 /p:PublishAot=true /p:AotPreferZig=true
```

## Tested Variants

|                    |(Host)Windows x64|Linux GNU x64|Linux GNU arm64|Linux MUSL x64|Linux MUSL arm64|
|--------------------|-----------------|-------------|---------------|--------------|----------------|
|(target)Windows x64 |X                |X            |X              |X             |X               |
|Linux GNU x64       |O                |O            |O              |N/A           |N/A             |
|Linux GNU arm64     |O                |O            |O              |N/A           |N/A             |
|Linux MUSL x64      |O                |O            |O              |N/A           |N/A             |
|Linux MUSL arm64    |O                |O            |O              |N/A           |N/A             |
|Linux MUSL arm      |N/A              |O            |N/A            |N/A           |N/A             |

Notes: `N/A` means it's might work but not tested.

