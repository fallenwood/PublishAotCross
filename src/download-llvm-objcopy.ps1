$version="21.1.0"
$downloadUrl="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/LLVM-$version-win64.exe"

$llvmArchivePath="$env:TEMP\\LLVM-$version-win64.exe"
$llvmExtractedPath="$env:TEMP\\LLVM-$version"

if (Test-Path $llvmArchivePath) {
    Write-Host "binary already downloaded"
} else {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $llvmArchivePath
}

7z e $llvmArchivePath "bin/llvm-objcopy.exe" -o"$PSScriptRoot" -r
