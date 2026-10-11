var buildenv = HostRuntimeIdentifier;
var isHostWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
var isTargetingWindows = RuntimeIdentifier.StartsWith("win-");
var isDebug = Environment.GetEnvironmentVariable("DOTNET_FALLENWOOD_PUBLISHAOTCROSS") == bool.TrueString;

CustomAotToolChain = "";
if (isTargetingWindows) {
  if (!isHostWindows || AotPreferCustom) {
    CustomAotToolChain = "xwin";
  }
} else if (buildenv != RuntimeIdentifier || AotPreferCustom) {
  CustomAotToolChain = "zig";
}

// Selection runs before the toolchain restore; configure PATH only after it completes.
if (!ConfigureEnvironment) {
  return Success;
}

if (CustomAotToolChain == "zig") {
  if (!UseExternalZig) {
    var zigExecutable = "zig";
    if (isHostWindows) {
      zigExecutable = "zig.exe";
    }
    if (!File.Exists(Path.Combine(ZigPath, zigExecutable))) {
      this.Log.LogError("Zig executable is missing after toolchain restore: {0}", ZigPath);
      return false;
    }
    Environment.SetEnvironmentVariable("PATH", ZigPath + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
  }

  Environment.SetEnvironmentVariable("PATH", MSBuildThisFileDirectory + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
  if (!isHostWindows) {
    // NuGet may extract the packaged shell wrappers without executable permissions.
    foreach (var wrapper in new[] { "clang", "gcc", "objcopy" }) {
      using (var cmd = new Process()) {
        cmd.StartInfo.FileName = "chmod";
        cmd.StartInfo.Arguments = "+x \"" + Path.Combine(MSBuildThisFileDirectory, wrapper) + "\"";
        cmd.StartInfo.CreateNoWindow = true;
        cmd.StartInfo.UseShellExecute = false;
        cmd.Start();
        cmd.WaitForExit();
        if (cmd.ExitCode != 0) {
          this.Log.LogError("Failed to make toolchain wrapper executable: {0}", wrapper);
          return false;
        }
      }
    }
  }
}

if (CustomAotToolChain != "") {
  Console.Error.WriteLine("Running custom toolchain environment setup for cross building...");
}

if (isDebug) {
  Console.Error.WriteLine($"Toolchain '{CustomAotToolChain}' for {RuntimeIdentifier} on {buildenv}; ZigPath='{ZigPath}'");
}
