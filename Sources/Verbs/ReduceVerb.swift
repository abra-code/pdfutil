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
                      (replaces recompression, so it excludes -q/-r/-m)
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
    // Tracked separately: --filter excludes all four, but --gray excludes only
    // the three recompression knobs (it replaces them rather than tuning them).
    var recompressFlags: [String] = []   // -q/-r/-m, in the order given
    var scanner = ArgScanner(verb: "reduce", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(reduceUsage); return
        case "-q", "--quality": options.quality = try scanner.intValue(a); recompressFlags.append("-q/--quality")
        case "-r", "--dpi": options.dpi = try scanner.intValue(a); recompressFlags.append("-r/--dpi")
        case "-m", "--max-edge": options.maxEdge = try scanner.intValue(a); recompressFlags.append("-m/--max-edge")
        case "--gray": options.gray = true
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
    if options.filterPath != nil && (!recompressFlags.isEmpty || options.gray) {
        throw PDFUtilError.usage("--filter cannot be combined with -q/-r/-m/--gray")
    }
    // buildReduceFilter returns the Gray Tone filter before it ever reads
    // quality/dpi/maxEdge, so these were being accepted and dropped: -q 1 and
    // -q 100 produced byte-identical output. The MCP twin (pdf_reduce) already
    // refuses this exact combination; the CLI verb simply never got the guard.
    if options.gray && !recompressFlags.isEmpty {
        throw PDFUtilError.usage("--gray cannot be combined with \(recompressFlags.joined(separator: ", ")): the grayscale filter replaces recompression rather than tuning it")
    }
    // Clamp to the same sane ranges as pdfreduce.
    options.quality = min(100, max(1, options.quality))
    options.dpi = max(0, options.dpi)
    options.maxEdge = max(0, options.maxEdge)

    try reduceDocument(path: scanner.positionals[0], output: common.output,
                       force: common.force, password: common.password, options: options)
}
