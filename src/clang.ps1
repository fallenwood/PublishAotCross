if (-not (Get-Command -Name zig -CommandType Application -ErrorAction SilentlyContinue)) {
  Write-Host "Error: zig is not on the PATH. Install zig and make sure it's on PATH. Follow instructions at https://github.com/fallenwood/PublishAotCross."
  exit 1
}

$zigArgs = @()

foreach ($arg in $args) {
  $translatedArg = $arg.Replace("'-Wl,-rpath,`$ORIGIN'", '-Wl,-rpath,$ORIGIN')
  $translatedArg = $translatedArg.Replace('--discard-all', '--as-needed')
  $translatedArg = $translatedArg.Replace('-static-pie', '-static')

  if ($translatedArg -eq '-lz' `
      -or $translatedArg -eq '-Wl,-pie' `
      -or $translatedArg -eq '-pie' `
      -or $translatedArg -eq '-Wl,-e0x0' `
      -or $translatedArg -eq '-Wl,--defsym,__xmknod=mknod') {
    # remove the argument
    continue
  }

  $zigArgs += $translatedArg
}

$zigArgs = @('-Wl,-u,__Module') + $zigArgs

& zig cc @zigArgs
exit $LASTEXITCODE
