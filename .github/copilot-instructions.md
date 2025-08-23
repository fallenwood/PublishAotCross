# GitHub Copilot Instructions for PublishAotCross

## Project Overview

This project is aimed to build .NET projects with Zig as C compiler to enable cross-platform NativeAOT support.

PublishAotCross is a NuGet package with MSBuild targets that helps resolve cross-OS native compilation errors when using PublishAOT. It enables cross-compilation using:
- [Zig](https://ziglang.org/) as the linker/sysroot for Linux targets (x64/arm64, GNU/MUSL)
- [xwin](https://github.com/Jake-Shadle/xwin) for Windows targets from Linux machines

## Development Workflow

### Build Commands
```bash
dotnet build test/Hello.csproj
dotnet build test/Hello9.csproj
```

### Testing Cross-Compilation
```bash
# Test with Zig (requires Zig installation)
dotnet publish -r linux-x64 -c Release test/Hello.csproj -p:StripSymbols=false

# Test with external Zig
dotnet publish -r linux-x64 /p:PublishAot=true /p:AotPreferCustom=true /p:UseExternalZig=true
```

### Required Before Each Commit
- Ensure code builds successfully with both test projects
- Run cross-compilation tests if making changes to core functionality  
- Follow the established code formatting and style conventions
- Verify MSBuild targets work correctly
- Test shell scripts (`src/gcc`, `src/clang`) if modified

## Repository Structure

- **`src/`** - Main source code
  - `Fallenwood.PublishAotCross.targets` - Main MSBuild targets file
  - `Crosscompile.targets` - Cross-compilation logic
  - `Fallenwood.PublishAotCross.nuproj` - NuGet package project
  - `gcc`, `clang`, `clang.cmd` - Wrapper scripts for Zig compiler
  - `objcopy` - LLVM objcopy wrapper
- **`test/`** - Test projects
  - `Hello.csproj` - .NET 8.0 test project
  - `Hello9.csproj` - .NET 9.0 test project
  - `Program.cs` - Simple Hello World test program

## Code Standards and Guidelines

### C# Best Practices
1. **Respect existing code format style** - Follow the patterns already established in the codebase
2. **Use latest C# and .NET features** - Leverage modern C# idioms and patterns when appropriate
3. **Maintain existing code structure** - Preserve the established project organization and architecture

### MSBuild and NuGet Guidelines
1. **Target compatibility** - Ensure compatibility with both .NET 8.0 and 9.0+
2. **Cross-platform support** - Maintain support for Windows, Linux, and cross-compilation scenarios
3. **Minimal dependencies** - Keep external dependencies to a minimum
4. **Clear property names** - Use descriptive MSBuild property names that follow existing conventions

### Shell Script Guidelines
1. **POSIX compliance** - Bash scripts should work across different Unix-like systems
2. **Windows compatibility** - Maintain corresponding `.cmd` files for Windows
3. **Error handling** - Include proper error checking and informative error messages
4. **Zig integration** - Ensure proper parameter translation for Zig compiler

## Key Integration Points

### MSBuild Integration
- The package integrates through `Fallenwood.PublishAotCross.targets`
- Automatically detects cross-compilation scenarios
- Provides custom compiler paths and settings

### Zig Compiler Wrapper
- Shell scripts (`gcc`, `clang`) wrap Zig compiler calls
- Handle parameter translation and workarounds for .NET-specific requirements
- Support both bundled Zig (via Vezel.Zig.Toolsets) and external Zig installations

### Supported Target Platforms
- Linux: x64, arm64 (both GNU and MUSL variants)
- Windows: x64, arm64 (via xwin on Linux hosts)
- Cross-compilation from Windows/Linux to various target platforms

## Common Development Scenarios

### Adding New Target Platform Support
1. Update `Crosscompile.targets` with new RID detection logic
2. Add appropriate compiler flag translations in wrapper scripts
3. Update documentation and test scenarios
4. Verify in CI pipeline

### Modifying Compiler Wrappers
1. Test both Unix (bash) and Windows (cmd) versions
2. Ensure parameter translation maintains compatibility
3. Test with various .NET project configurations
4. Validate cross-compilation still works

### Updating Dependencies
1. Test with different Zig versions when updating Vezel.Zig.Toolsets
2. Verify xwin compatibility for Windows cross-compilation
3. Ensure .NET SDK compatibility across supported versions