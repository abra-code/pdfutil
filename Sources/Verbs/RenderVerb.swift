// Verbs/RenderVerb.swift - `pdfutil render`: rasterize pages to image files.

import Foundation

private let renderUsage = """
Usage: pdfutil render [options] <in.pdf>

Rasterize pages to PNG/JPEG/TIFF/HEIC. With a single selected page and -o, the
output is that literal file; otherwise pages are written as <prefix>-NNN.<ext>
(1-based over the selection; default prefix is the input minus .pdf).

Options:
  -p, --pages RANGE    Only these pages (default: all)
      --dpi N          Output resolution in DPI (default 150)
      --scale F        Scale factor instead of --dpi (72 * F DPI)
      --format FMT     png, jpeg, tiff, or heic (default png)
      --quality N      Lossy quality 1-100 for jpeg/heic (default 85)
      --transparent    Keep the background transparent (png/tiff/heic only)
  -o, --output PATH    Output file (single page) or filename prefix
      --password PW    Password for an encrypted PDF
      --force          Overwrite existing output files
  -h, --help           Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runRender(_ args: [String]) throws {
    var common = CommonOptions()
    var dpi: Double?
    var scale: Double?
    var format = ImageFormat.png
    var quality = 85
    var transparent = false
    var scanner = ArgScanner(verb: "render", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(renderUsage); return
        case "-p", "--pages": common.pages = try scanner.value(a)
        case "--dpi": dpi = try positiveDouble(try scanner.value(a), option: a)
        case "--scale": scale = try positiveDouble(try scanner.value(a), option: a)
        case "--format": format = try parseImageFormat(try scanner.value(a))
        case "--quality": quality = try scanner.intValue(a)
        case "--transparent": transparent = true
        case "-o", "--output": common.output = try scanner.value(a)
        case "--password": common.password = try scanner.value(a)
        case "--force": common.force = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard scanner.positionals.count == 1 else {
        throw PDFUtilError.usage("expected exactly one input PDF")
    }
    guard dpi == nil || scale == nil else {
        throw PDFUtilError.usage("--dpi and --scale are mutually exclusive")
    }
    if transparent && !format.supportsTransparency {
        throw PDFUtilError.usage("--transparent is not supported for \(format.rawValue)")
    }
    let effectiveDPI = dpi ?? scale.map { $0 * 72.0 } ?? 150.0
    let clampedQuality = Double(min(100, max(1, quality))) / 100.0
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount) ?? Array(0..<doc.pageCount)
    guard !pages.isEmpty else { throw PDFUtilError.usage("no pages selected") }

    // Single page with -o writes that literal file; otherwise use prefix naming.
    if pages.count == 1, let output = common.output {
        if FileManager.default.fileExists(atPath: output) && !common.force {
            throw PDFUtilError.processing("output exists: \(output) (use --force to overwrite)")
        }
        try autoreleasepool {
            guard let page = doc.page(at: pages[0]) else {
                throw PDFUtilError.processing("cannot read page \(pages[0] + 1)")
            }
            let image = try renderPageToImage(page, dpi: effectiveDPI, transparent: transparent)
            try writeCGImage(image, to: URL(fileURLWithPath: output),
                             format: format, quality: clampedQuality, dpi: effectiveDPI)
        }
        return
    }

    // When -o is reused as a multi-page prefix, drop a trailing image extension so
    // we do not produce doubled names like out.png-001.png.
    let prefix = common.output.map(stripImageExtension) ?? stripPDFExtension(path)
    let outPaths = (0..<pages.count).map {
        String(format: "%@-%03d.%@", prefix, $0 + 1, format.fileExtension)
    }
    if !common.force {
        for outPath in outPaths where FileManager.default.fileExists(atPath: outPath) {
            throw PDFUtilError.processing("output exists: \(outPath) (use --force to overwrite)")
        }
    }
    for (i, idx) in pages.enumerated() {
        try autoreleasepool {
            guard let page = doc.page(at: idx) else {
                throw PDFUtilError.processing("cannot read page \(idx + 1)")
            }
            let image = try renderPageToImage(page, dpi: effectiveDPI, transparent: transparent)
            try writeCGImage(image, to: URL(fileURLWithPath: outPaths[i]),
                             format: format, quality: clampedQuality, dpi: effectiveDPI)
        }
    }
    writeErr("render: wrote \(outPaths.count) file(s)\n")
}
