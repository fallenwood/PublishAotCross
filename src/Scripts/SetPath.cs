Console.Error.WriteLine("Running custom toolchain environment setup for cross building...");

if (!UseExternalZig) {
  Environment.SetEnvironmentVariable("PATH", ZigPath + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
}

var buildenv = "";
var isHostWindows = false;
var isTargetingWindows = RuntimeIdentifier.StartsWith("win");
var isDebug = Environment.GetEnvironmentVariable("DOTNET_FALLENWOOD_PUBLISHAOTCROSS") == bool.TrueString;

if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) {
  var osDescription = RuntimeInformation.OSDescription;
  buildenv += "linux";
  if (osDescription.Contains("GNU")) {
    // noop
  } else if (osDescription.Contains("MUSL")) {
    buildenv += "-musl";
  } else {
    // TODO: android/loongarch/bionic/osx/ios
  }
} else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
  buildenv += "win";
  isHostWindows = true;
}

if (RuntimeInformation.OSArchitecture == Architecture.X64) {
  buildenv += "-x64";
} else if (RuntimeInformation.OSArchitecture == Architecture.Arm64) {
  buildenv += "-arm64";
} else if (RuntimeInformation.OSArchitecture == Architecture.Arm) {
  buildenv += "-arm";
}

if (isTargetingWindows) {
  if (!isHostWindows && (buildenv != RuntimeIdentifier || AotPreferCustom)) {
    // Cross-compile from *nix to Windows
    Environment.SetEnvironmentVariable("CustomAotToolChain", "xwin");
    CustomAotToolChain = "xwin";

    return Success;
  }
} else {
  if (buildenv != RuntimeIdentifier || AotPreferCustom) {
    Environment.SetEnvironmentVariable("PATH", MSBuildThisFileDirectory + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));

    if (!isHostWindows) {
      var cmd = new Process();
      cmd.StartInfo.FileName = "chmod";
      cmd.StartInfo.Arguments = "-R +x " + MSBuildThisFileDirectory;
      cmd.StartInfo.CreateNoWindow = true;
      cmd.StartInfo.UseShellExecute = false;
      cmd.Start();
      cmd.WaitForExit();
    }

    if (isDebug) {
      Console.Error.WriteLine($"Adding {MSBuildThisFileDirectory} to PATH for cross building {RuntimeIdentifier} on {buildenv}");
    }

    Environment.SetEnvironmentVariable("CustomAotToolChain", "zig");
    CustomAotToolChain = "zig";

    return Success;
  }
}

if (isDebug) {
  Console.Error.WriteLine($"Native building for {buildenv}, skip setting custom toolchain environment...");
}
