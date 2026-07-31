#!/bin/sh
# Build pdfutil as a universal (x86_64 + arm64) command-line binary.
#
# Usage:
#   ./build.sh                   # produces build/pdfutil (universal, ad-hoc signed)
#   ./build.sh arm64|x86_64      # produces a single-architecture build/pdfutil
#
# Always an optimized release build. The compiler flags are SwiftPM's business
# now - see Package.swift for why. This script only picks the architectures,
# strips, and signs.
#
# The contract downstream consumers rely on is build/pdfutil: a universal,
# ad-hoc signed binary at a fixed path. Cadabra.app, PDFUtil.app, QuickPDF.app
# and Interpreter.app all run this script and copy that file into their bundles.
# Keep that path and that CLI stable.

set -e

cd "$(dirname "$0")"

want="${1:-universal}"
case "$want" in
    universal)    arch_flags="--arch x86_64 --arch arm64" ;;
    arm64|x86_64) arch_flags="--arch $want" ;;
    *) echo "usage: ./build.sh [arm64|x86_64]" >&2; exit 1 ;;
esac

# SwiftPM's scratch directory. It defaults to a hidden .build; put it in the
# visible build/ instead, alongside the binary we hand to consumers. SwiftPM only
# creates subdirectories in here (apple/, artifacts/, checkouts/, ...), so the
# build/pdfutil we write below does not collide with anything it owns.
scratch="build"

# `swift build` runs lipo itself when given more than one --arch, so there is no
# separate universal-binary step. Repeating the flags for --show-bin-path is not
# a rebuild: it re-resolves the manifest and prints the path, which differs by
# architecture selection (build/apple/Products/Release with --arch, build/release
# without), so it must not be hardcoded.
# shellcheck disable=SC2086  # $arch_flags must word-split into separate args.
swift build -c release --scratch-path "$scratch" $arch_flags
# shellcheck disable=SC2086
bin_path="$(swift build -c release --scratch-path "$scratch" $arch_flags --show-bin-path)"

# Assemble under a temporary name and rename into place only once the binary is
# finished. build/pdfutil is what four app bundles copy from, and a cp that dies
# partway - full disk, killed build - would leave a truncated binary there that
# still looks like a build product. A rename within one filesystem is atomic, so
# build/pdfutil is only ever the previous good binary or the new one.
rm -f build/pdfutil.new
cp "$bin_path/pdfutil" build/pdfutil.new

# Drop the local symbol table - roughly a quarter of the binary in mangled Swift
# names for local functions. Must run before codesign, since stripping a signed
# binary invalidates the signature (SwiftPM ad-hoc signs its own output, so there
# is always a signature here to invalidate). -x rather than bare strip: bare
# strip means -u -r, which also drops globals that are not marked
# referenced-dynamically, for no meaningful extra saving.
strip -x build/pdfutil.new

codesign -s - build/pdfutil.new

mv build/pdfutil.new build/pdfutil

# Keep the debug symbols that the release build produces, next to the binary
# rather than buried in SwiftPM's scratch tree. This is what makes the strip
# above non-lossy: crash reports from the stripped binary can still be
# symbolicated against this bundle, which the plain swiftc build never allowed
# since it passed no -g and produced no dSYM at all.
if [ -d "$bin_path/pdfutil.dSYM" ]; then
    rm -rf build/pdfutil.dSYM.new
    cp -R "$bin_path/pdfutil.dSYM" build/pdfutil.dSYM.new
    rm -rf build/pdfutil.dSYM
    mv build/pdfutil.dSYM.new build/pdfutil.dSYM
fi

lipo -info build/pdfutil

echo "Done."
