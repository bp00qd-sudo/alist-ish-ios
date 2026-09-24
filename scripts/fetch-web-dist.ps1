$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$distDir = Join-Path $repoRoot 'alist\public\dist'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('alist-web-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
try {
    $archive = Join-Path $tempDir 'dist.tar.gz'
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/alist-org/alist-web/releases/download/3.64.0/dist.tar.gz' `
        -OutFile $archive
    $expectedHash = 'B80550662DE42A2F8A72D35BCA8ED66EC9AD0C24A9A02CEEC6A01BF5038CF6F4'
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'AList web distribution checksum mismatch'
    }
    tar -xzf $archive -C $tempDir
    if (Test-Path $distDir) { Remove-Item -LiteralPath $distDir -Recurse -Force }
    Move-Item -LiteralPath (Join-Path $tempDir 'dist') -Destination $distDir
    Write-Output "Fetched Alist web distribution into $distDir"
} finally {
    if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
