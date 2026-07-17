// Verbs/FromPagesVerb.swift - `pdfutil frompages`: build a PDF from images and/or
// PDFs (img2pdf plus mixed inputs).

import Foundation

private let fromPagesUsage = """
Usage: pdfutil frompages -o out.pdf [options] <input...>

Assemble images (PNG/JPEG/TIFF/HEIC/GIF - anything ImageIO reads) and/or PDFs,
in order, into one PDF. Each image becomes one page sized from its pixels and
DPI (multi-frame images contribute one page per frame). PDF inputs are redrawn,
so their annotations, links, outline, and form fields are lost - use 'merge' to
combine PDFs while preserving structure.

Options:
  -o, --output FILE   Output file (required)
      --dpi N         Assume this DPI for all images (overrides recorded DPI)
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runFromPages(_ args: [String]) throws {
    var output: String?
    var force = false
    var dpi: Double?
    var scanner = ArgScanner(verb: "frompages", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(fromPagesUsage); return
        case "-o", "--output": output = try scanner.value(a)
        case "--dpi": dpi = try positiveDouble(try scanner.value(a), option: a)
        case "--force": force = true
        case "--": scanner.endOptions()
        default: try scanner.addPositional(a)
        }
    }

    guard let output = output else {
        throw PDFUtilError.usage("frompages requires -o/--output")
    }
    guard !scanner.positionals.isEmpty else {
        throw PDFUtilError.usage("expected at least one input file")
    }

    try combineToPDF(inputs: scanner.positionals, output: output, dpiOverride: dpi, force: force)
}
