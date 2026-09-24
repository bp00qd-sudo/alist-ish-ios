$ErrorActionPreference = 'Stop'
if (-not $IsMacOS) {
    Write-Error 'The iOS archive must be built on macOS with Xcode.'
    exit 2
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $PSScriptRoot 'build-ios.sh')
