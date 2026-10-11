// Windows SDK filenames and COFF /DEFAULTLIB directives can differ in casing.
// Use an LLD VFS overlay instead of modifying the shared NuGet package cache.
var overlay = new System.Text.StringBuilder();
overlay.AppendLine("version: 0");
overlay.AppendLine("case-sensitive: false");
overlay.AppendLine("roots:");

foreach (var libraryDirectory in LibraryDirectories) {
  var directory = Path.GetFullPath(libraryDirectory);
  if (!Directory.Exists(directory)) {
    this.Log.LogError("XWin library directory does not exist: {0}", directory);
    return false;
  }

  overlay.AppendLine("  - type: directory");
  overlay.AppendLine("    name: '" + directory.Replace("'", "''") + "'");
  overlay.AppendLine("    contents:");
  foreach (var file in Directory.GetFiles(directory)) {
    overlay.AppendLine("      - type: file");
    overlay.AppendLine("        name: '" + Path.GetFileName(file).Replace("'", "''") + "'");
    overlay.AppendLine("        external-contents: '" + file.Replace("'", "''") + "'");
  }
}

var overlayPath = Path.GetFullPath(OverlayPath);
Directory.CreateDirectory(Path.GetDirectoryName(overlayPath));
File.WriteAllText(overlayPath, overlay.ToString(), new System.Text.UTF8Encoding(false));
