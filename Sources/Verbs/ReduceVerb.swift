// Verbs/ReduceVerb.swift - `pdfutil reduce`: recompress/downsample images to
// shrink a PDF (redraw path).

import Foundation

private let reduceUsage = """
Usage: pdfutil reduce [options] <in.pdf>

Shrink a PDF by recompressing (and optionally downsampling) its raster images
through the macOS Quartz image filter. Text and vectors are preserved; only
images are re-encoded, so it handles ICC/JPEG images that qpdf cannot optimize.

Redraw path: the document is re-recorded through a new PDF context, so
annotations, links, outline, and form fields are not carried over. Use qpdf for
structure-preserving optimization of non-scanned PDFs.

Options:
  -q, --quality N     JPEG quality 1-100 (default 85)
  -r, --dpi N         Downsample images above this resolution, in DPI
                      (default 150; 0 disables resolution downsampling)
  -m, --max-edge N    Cap the longest image edge to N pixels (default 0 = no cap)
      --gray          Convert to grayscale via the system "Gray Tone" filter
      --filter FILE   Apply an explicit .qfilter (excludes -q/-r/-m/--gray)
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runReduce(_ args: [String]) throws {
    var common = CommonOptions()
    var options = ReduceOptions()
    var sawImageFlag = false     // any of -q/-r/-m/--gray, which --filter excludes
    var scanner = ArgScanner(verb: "reduce", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(reduceUsage); return
        case "-q", "--quality": options.quality = try scanner.intValue(a); sawImageFlag = true
        case "-r", "--dpi": options.dpi = try scanner.intValue(a); sawImageFlag = true
        case "-m", "--max-edge": options.maxEdge = try scanner.intValue(a); sawImageFlag = true
        case "--gray": options.gray = true; sawImageFlag = true
        case "--filter": options.filterPath = try scanner.value(a)
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
    if options.filterPath != nil && sawImageFlag {
        throw PDFUtilError.usage("--filter cannot be combined with -q/-r/-m/--gray")
    }
    // Clamp to the same sane ranges as pdfreduce.
    options.quality = min(100, max(1, options.quality))
    options.dpi = max(0, options.dpi)
    options.maxEdge = max(0, options.maxEdge)

    try reduceDocument(path: scanner.positionals[0], output: common.output,
                       force: common.force, password: common.password, options: options)
}
