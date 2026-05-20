<#
.SYNOPSIS
    Builds the WeatherApi as an OCI image using melange + apko.
.PARAMETER Engine
    Container engine to use: 'docker' or 'podman'. Default: auto-detect.
#>
param(
    [ValidateSet('docker', 'podman')]
    [string]$Engine
)

$ErrorActionPreference = 'Continue'

$ScriptDir = $PSScriptRoot
$RootDir = Split-Path $ScriptDir -Parent
$OutputDir = Join-Path $ScriptDir 'output'
$PackagesDir = Join-Path $ScriptDir 'packages'
$ImageName = 'weather-apko'
$ImageTag = 'latest'

# Auto-detect container engine
if (-not $Engine) {
    if (Get-Command podman -ErrorAction SilentlyContinue) {
        $Engine = 'podman'
    } elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        $Engine = 'docker'
    } else {
        Write-Error "Neither docker nor podman found. Install one of them first."
        exit 1
    }
}
Write-Host "Using container engine: $Engine" -ForegroundColor Cyan

# === Step 1/4: Build .NET 10 AOT app ===
Write-Host "`n=== Step 1/4: Building .NET 10 AOT app ===" -ForegroundColor Green
if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Convert Windows paths to Docker-compatible paths
$SourceMount = "$RootDir/src/WeatherApi" -replace '\\', '/'
$OutputMount = $OutputDir -replace '\\', '/'

& $Engine run --rm `
    -v "${SourceMount}:/source" `
    -v "${OutputMount}:/output" `
    -w /source `
    mcr.microsoft.com/dotnet/sdk:10.0-noble-aot `
    dotnet publish -c Release -o /output `
        --self-contained `
        -r linux-x64 `
        -p:PublishAot=true `
        -p:InvariantGlobalization=true

if ($LASTEXITCODE -ne 0) { Write-Error "dotnet publish failed"; exit 1 }

# === Step 2/4: Generate melange signing key ===
Write-Host "`n=== Step 2/4: Generating melange signing key ===" -ForegroundColor Green
$KeyPath = Join-Path $ScriptDir 'melange.rsa'
$WorkMount = $ScriptDir -replace '\\', '/'

if (-not (Test-Path $KeyPath)) {
    & $Engine run --rm `
        -v "${WorkMount}:/work" `
        -w /work `
        cgr.dev/chainguard/melange `
        keygen

    if ($LASTEXITCODE -ne 0) { Write-Error "melange keygen failed"; exit 1 }
}

# === Step 3/4: Build APK package with melange ===
Write-Host "`n=== Step 3/4: Building APK package with melange ===" -ForegroundColor Green
if (Test-Path $PackagesDir) { Remove-Item $PackagesDir -Recurse -Force }

& $Engine run --rm --privileged `
    -v "${WorkMount}:/work" `
    -v "${OutputMount}:/home/build/output" `
    -w /work `
    cgr.dev/chainguard/melange `
    build melange.yaml `
        --arch x86_64 `
        --signing-key melange.rsa `
        --out-dir /work/packages

if ($LASTEXITCODE -ne 0) { Write-Error "melange build failed"; exit 1 }

# === Step 4/4: Build OCI image with apko ===
Write-Host "`n=== Step 4/4: Building OCI image with apko ===" -ForegroundColor Green
& $Engine run --rm `
    -v "${WorkMount}:/work" `
    -w /work `
    cgr.dev/chainguard/apko `
    build apko.yaml `
        "${ImageName}:${ImageTag}" `
        /work/output.tar `
        --arch x86_64

if ($LASTEXITCODE -ne 0) { Write-Error "apko build failed"; exit 1 }

# === Load image ===
Write-Host "`n=== Loading image ===" -ForegroundColor Green
$TarPath = Join-Path $ScriptDir 'output.tar'
& $Engine load -i $TarPath

if ($LASTEXITCODE -ne 0) { Write-Error "Image load failed"; exit 1 }

Write-Host "`n=== Done! ===" -ForegroundColor Green
Write-Host "Image: ${ImageName}:${ImageTag}"
Write-Host "Run:   $Engine run -p 8082:8080 ${ImageName}:${ImageTag}"
