param(
    [string] $Version = "v1.19.1",
    [string] $GoToolchain = "go1.26.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourceDir = Join-Path $env:TEMP "glacier-mediamtx-$Version"
$outputDir = Join-Path $repoRoot "android/app/src/main/jniLibs/arm64-v8a"
$outputFile = Join-Path $outputDir "libmediamtx.so"

if (Test-Path -LiteralPath $sourceDir) {
    Remove-Item -LiteralPath $sourceDir -Recurse -Force
}

git clone --depth 1 --branch $Version https://github.com/bluenviron/mediamtx $sourceDir

Push-Location $sourceDir
try {
    $androidPatch = Join-Path $repoRoot "scripts/patches/mediamtx-android-netlink-fallback.patch"
    git apply --whitespace=nowarn $androidPatch

    go generate ./...

    $env:GOTOOLCHAIN = $GoToolchain
    $env:GOOS = "android"
    $env:GOARCH = "arm64"
    $env:CGO_ENABLED = "0"

    go build `
        -trimpath `
        -ldflags="-s -w -checklinkname=0" `
        -o "mediamtx-android-arm64" `
        ./

    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    Copy-Item -LiteralPath "mediamtx-android-arm64" -Destination $outputFile -Force

    Write-Host "Wrote $outputFile"
} finally {
    Pop-Location
}
