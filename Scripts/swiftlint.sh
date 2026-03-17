#!/bin/bash

# SwiftLint runner script for CI/CD and local builds
# This script ensures SwiftLint runs consistently across all environments
# without requiring a global installation.

set -e

SWIFTLINT_VERSION="0.54.0"
CACHE_DIR="${HOME}/.swiftlint-cache"
SWIFTLINT_PATH="${CACHE_DIR}/swiftlint-${SWIFTLINT_VERSION}/swiftlint"

# Function to download SwiftLint if not cached
download_swiftlint() {
    echo "Downloading SwiftLint ${SWIFTLINT_VERSION}..."
    mkdir -p "${CACHE_DIR}/swiftlint-${SWIFTLINT_VERSION}"

    # Determine architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        ZIP_NAME="swiftlint_macos.zip"
    else
        ZIP_NAME="swiftlint_macos.zip"
    fi

    DOWNLOAD_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

    curl -sL "$DOWNLOAD_URL" -o "${CACHE_DIR}/swiftlint.zip"
    unzip -o -q "${CACHE_DIR}/swiftlint.zip" -d "${CACHE_DIR}/swiftlint-${SWIFTLINT_VERSION}"
    rm "${CACHE_DIR}/swiftlint.zip"
    chmod +x "${SWIFTLINT_PATH}"
    echo "SwiftLint ${SWIFTLINT_VERSION} installed to cache."
}

# Find SwiftLint: prefer local cache, then check PATH
if [ -x "${SWIFTLINT_PATH}" ]; then
    SWIFTLINT="${SWIFTLINT_PATH}"
elif command -v swiftlint &> /dev/null; then
    SWIFTLINT="swiftlint"
    echo "Using system SwiftLint: $(swiftlint version)"
else
    download_swiftlint
    SWIFTLINT="${SWIFTLINT_PATH}"
fi

echo "Running SwiftLint ${SWIFTLINT_VERSION}..."

# Run SwiftLint from the project root
cd "$(dirname "$0")/.."

# Use --strict to fail on warnings in CI, or remove for local dev
if [ "$CI" = "true" ]; then
    "${SWIFTLINT}" lint --strict
else
    "${SWIFTLINT}" lint
fi
