// swift-tools-version:5.9
//
// pdfutil is a standalone command-line tool, not a library. This manifest exists
// so that `swift build` owns the compiler configuration - in particular the
// release preset, which is easy to get subtly wrong by hand (a plain `swiftc -O`
// over a file list silently falls back to per-file batch mode, with no
// cross-file inlining or generic specialization).
//
// Nothing depends on this package. The four downstream apps - Cadabra.app,
// PDFUtil.app, QuickPDF.app, Interpreter.app - run ./build.sh and copy the
// resulting binary into their bundles. Keep it dependency-free so that stays true.
//
// There are no linkSettings here and none are needed: the system frameworks
// pdfutil uses (PDFKit, Vision, CoreGraphics, ...) auto-link from the `import`
// statements in the sources against the macOS SDK.

import PackageDescription

let package = Package(
    name: "pdfutil",
    platforms: [
        // Matches the deployment target build.sh used to pass as -target
        // <arch>-apple-macos14.0.
        .macOS(.v14)
    ],
    targets: [
        // path: "Sources" keeps the existing flat layout (main.swift and friends
        // at the top, Core/ Verbs/ MCP/ beneath) instead of forcing the sources
        // down into Sources/pdfutil/. Files are discovered, so adding a new
        // subdirectory no longer means editing a glob list in build.sh.
        .executableTarget(name: "pdfutil", path: "Sources")
    ]
)
