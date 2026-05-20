#!/bin/bash
# Usage: ./build.sh [docker|podman]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
PACKAGES_DIR="$SCRIPT_DIR/packages"
IMAGE_NAME="weather-apko"
IMAGE_TAG="latest"

# Auto-detect container engine or use argument
if [ -n "${1:-}" ]; then
    ENGINE="$1"
elif command -v podman &> /dev/null; then
    ENGINE="podman"
elif command -v docker &> /dev/null; then
    ENGINE="docker"
else
    echo "Error: Neither docker nor podman found. Install one of them first."
    exit 1
fi
echo "Using container engine: $ENGINE"

echo "=== Step 1/4: Building .NET 10 AOT app ==="
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

$ENGINE run --rm \
    -v "$ROOT_DIR/src/WeatherApi:/source" \
    -v "$OUTPUT_DIR:/output" \
    -w /source \
    mcr.microsoft.com/dotnet/sdk:10.0-noble-aot \
    dotnet publish -c Release -o /output \
        --self-contained \
        -r linux-x64 \
        -p:PublishAot=true \
        -p:InvariantGlobalization=true

echo "=== Step 2/4: Generating melange signing key ==="
if [ ! -f "$SCRIPT_DIR/melange.rsa" ]; then
    $ENGINE run --rm \
        -v "$SCRIPT_DIR:/work" \
        -w /work \
        cgr.dev/chainguard/melange \
        keygen
fi

echo "=== Step 3/4: Building APK package with melange ==="
rm -rf "$PACKAGES_DIR"

$ENGINE run --rm --privileged \
    -v "$SCRIPT_DIR:/work" \
    -v "$OUTPUT_DIR:/home/build/output" \
    -w /work \
    cgr.dev/chainguard/melange \
    build melange.yaml \
        --arch x86_64 \
        --signing-key melange.rsa \
        --out-dir /work/packages

echo "=== Step 4/4: Building OCI image with apko ==="
$ENGINE run --rm \
    -v "$SCRIPT_DIR:/work" \
    -w /work \
    cgr.dev/chainguard/apko \
    build apko.yaml \
        "$IMAGE_NAME:$IMAGE_TAG" \
        /work/output.tar \
        --arch x86_64

echo "=== Loading image ==="
$ENGINE load -i "$SCRIPT_DIR/output.tar"

echo ""
echo "=== Done! ==="
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
echo "Run:   docker run -p 8082:8080 $IMAGE_NAME:$IMAGE_TAG"
