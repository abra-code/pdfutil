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
      --page-size S   Scale each IMAGE to fit a fixed page instead, centered and
                      keeping its aspect ratio. S is letter, legal, tabloid, a3,
                      a4, a5, or WxH in points. The page is oriented to the
                      image, so landscape photos get landscape pages. PDF inputs
                      keep their own page sizes - only images are refitted, so a
                      mixed run produces a document of mixed page sizes.
                      Excludes --dpi: both decide how big a page is.
      --force         Overwrite an existing output file
  -h, --help          Show this help

Without --page-size a page is as large as its image claims to be, and cameras
record 72 DPI, so a 4284 px photo becomes a 4284 pt (59 inch) page. That is
faithful but rarely useful, and it also defeats 'reduce -r', which measures
resolution against the page. --page-size letter is usually what you want.

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runFromPages(_ args: [String]) throws {
    var output: String?
    var force = false
    var dpi: Double?
    var pageSize: CGSize?
    var scanner = ArgScanner(verb: "frompages", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(fromPagesUsage); return
        case "-o", "--output": output = try scanner.value(a)
        case "--dpi": dpi = try positiveDouble(try scanner.value(a), option: a)
        case "--page-size": pageSize = try parsePageSize(try scanner.value(a))
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
    // Refused rather than silently ranked: both options answer "how big is this
    // page", and picking one for the user would mean quietly discarding the
    // other. Same rule the rest of the verbs follow.
    if dpi != nil && pageSize != nil {
        throw PDFUtilError.usage("--page-size cannot be combined with --dpi: both decide the page size")
    }

    try combineToPDF(inputs: scanner.positionals, output: output, dpiOverride: dpi,
                     pageSize: pageSize, force: force)
}
