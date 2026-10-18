$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Push-Location (Join-Path $PSScriptRoot '..')
try {
    $flutter = if ($env:FLUTTER) { $env:FLUTTER } else { 'flutter' }
    if (-not (Get-Command $flutter -ErrorAction SilentlyContinue)) {
        throw "flutter not found; set FLUTTER to the Flutter executable"
    }

    if ($env:VERSION) {
        $version = $env:VERSION.TrimStart('v')
    } else {
        $versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)' |
            Select-Object -First 1
        if (-not $versionLine) {
            throw 'cannot determine version from pubspec.yaml'
        }
        $version = $versionLine.Matches[0].Groups[1].Value
    }
    if (-not $version) {
        throw 'version must not be empty'
    }

    Write-Host "==> version $version"
    Write-Host '==> flutter config --enable-windows-desktop'
    & $flutter config --enable-windows-desktop | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'flutter config failed' }

    Write-Host '==> flutter pub get'
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    Write-Host '==> flutter build windows --release'
    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

    $bundle = 'build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $bundle 'faria2.exe'))) {
        throw "Windows bundle not found at $bundle"
    }

    $stage = 'dist\stage\faria2'
    if (Test-Path 'dist\stage') { Remove-Item -Recurse -Force 'dist\stage' }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item -Path (Join-Path $bundle '*') -Destination $stage -Recurse -Force
    Copy-Item -Path 'LICENSE', 'README.md' -Destination $stage -Force

    $archive = "dist\faria2-$version-windows-x64.zip"
    if (Test-Path $archive) { Remove-Item -Force $archive }
    Compress-Archive -Path $stage -DestinationPath $archive -Force

    Remove-Item -Recurse -Force 'dist\stage'
    Write-Host "created $archive"
    Get-Item $archive | Format-List Name, Length
} finally {
    Pop-Location
}
