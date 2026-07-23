#!/bin/sh
# Build pdfutil as a universal (x86_64 + arm64) command-line binary.
#
# System frameworks auto-link from the `import` statements in the sources, so no
# -framework flags are needed. Deployment target is macOS 14.0 for both slices.
#
# Usage:
#   ./build.sh                   # produces build/pdfutil (universal, ad-hoc signed)
#   ./build.sh arm64|x86_64      # produces a single-architecture build/pdfutil
#
# Always an optimized release build (-O).

set -e

cd "$(dirname "$0")"

want="${1:-universal}"
case "$want" in
    universal|arm64|x86_64) ;;
    *) echo "usage: ./build.sh [arm64|x86_64]" >&2; exit 1 ;;
esac

min_macos="14.0"
sources="Sources/main.swift Sources/CLI.swift Sources/PageRange.swift Sources/Output.swift Sources/Core/*.swift Sources/Verbs/*.swift Sources/MCP/*.swift"

mkdir -p build

build_slice() {
    arch="$1"
    echo "Building $arch slice..."
    # shellcheck disable=SC2086  # $sources must glob-expand into separate args.
    xcrun -sdk macosx swiftc -O \
        -target "${arch}-apple-macos${min_macos}" \
        $sources \
        -o "build/pdfutil-$arch"
}

if [ "$want" = "universal" ]; then
    build_slice x86_64
    build_slice arm64
    echo "Creating universal binary..."
    lipo -create -output build/pdfutil build/pdfutil-x86_64 build/pdfutil-arm64
    rm -f build/pdfutil-x86_64 build/pdfutil-arm64
else
    build_slice "$want"
    mv "build/pdfutil-$want" build/pdfutil
fi
lipo -info build/pdfutil

codesign -s - build/pdfutil

echo "Done."
