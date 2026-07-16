#!/bin/sh
# Build pdfutil as a universal (x86_64 + arm64) command-line binary.
#
# System frameworks auto-link from the `import` statements in the sources, so no
# -framework flags are needed. Deployment target is macOS 14.0 for both slices.
#
# Usage:
#   ./build.sh        # produces ./pdfutil (universal, ad-hoc signed)

set -e

cd "$(dirname "$0")"

min_macos="14.0"
sources="Sources/main.swift Sources/CLI.swift Sources/PageRange.swift Sources/Output.swift Sources/Core/*.swift Sources/Verbs/*.swift"

build_slice() {
    arch="$1"
    echo "Building $arch slice..."
    # shellcheck disable=SC2086  # $sources must glob-expand into separate args.
    xcrun -sdk macosx swiftc -O \
        -target "${arch}-apple-macos${min_macos}" \
        $sources \
        -o "pdfutil-$arch"
}

build_slice x86_64
build_slice arm64

echo "Creating universal binary..."
lipo -create -output pdfutil pdfutil-x86_64 pdfutil-arm64
rm -f pdfutil-x86_64 pdfutil-arm64
lipo -info pdfutil

codesign -s - pdfutil

echo "Done."
