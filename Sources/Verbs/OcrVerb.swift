// Verbs/OcrVerb.swift - `pdfutil ocr`: recognize text in a PDF (Vision), either
// printed to stdout/-o or embedded as a searchable layer.

import Foundation

private let ocrUsage = """
Usage: pdfutil ocr [options] <in.pdf>

Recognize text with the Vision framework. OCR always rasterizes each page first,
so it works on scanned/image-only PDFs (use 'pdfutil text' to read an existing
text layer). Recognized text is printed in reading order, pages separated by a
form-feed page break.

With --searchable, the document is instead saved with an embedded text layer
produced by PDFKit's own OCR (a structure-preserving save). That path OCRs the
whole document and picks its own recognition parameters, so -p/--pages, --lang,
--fast, and --dpi cannot be honored and are refused rather than ignored.

Options:
  -p, --pages RANGE   Only these pages (default: all)
      --lang TAG      Recognition language (BCP-47, e.g. en-US); repeatable.
                      Omitted: Vision auto-detects.
      --fast          Use the fast recognition level instead of accurate
      --dpi N         Rasterization resolution (default 300, clamped 72-600)
      --searchable    Embed a searchable text layer and save (requires -o)
  -o, --output FILE   Output text file, or the output PDF with --searchable
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runOcr(_ args: [String]) throws {
    var common = CommonOptions()
    var languages: [String] = []
    var fast = false
    var dpi: Double = 300
    var dpiGiven = false
    var searchable = false
    var scanner = ArgScanner(verb: "ocr", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(ocrUsage); return
        case "-p", "--pages": common.pages = try scanner.value(a)
        case "--lang": languages.append(try scanner.value(a))
        case "--fast": fast = true
        case "--dpi":
            dpi = try positiveDouble(try scanner.value(a), option: "--dpi")
            dpiGiven = true
        case "--searchable": searchable = true
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
    let path = scanner.positionals[0]

    // Validated from parsed state alone, BEFORE openPDF, so a bad command line
    // reports a usage error (exit 1) rather than whatever the file turns out to
    // be (exit 2 for missing or password-protected). Every other guard added in
    // this pass runs before any I/O; this one has to be hoisted explicitly
    // because the searchable branch needs the opened document afterwards.
    var searchableOutput: String?
    if searchable {
        guard let output = common.output else {
            throw PDFUtilError.usage("--searchable requires -o/--output")
        }
        // PDFKit's OCR-embed is a whole-document write option with no per-page
        // or per-parameter control, so none of these can be honored. Refuse
        // rather than drop: silently ignoring -p wrote a fully OCR'd document
        // while the caller believed one page had been touched, and an
        // out-of-range -p was accepted without a word because the validation
        // lives on the other branch. Unknown options are already a usage error
        // (ArgScanner.addPositional); an option that cannot apply should be too.
        var inapplicable: [String] = []
        if common.pages != nil { inapplicable.append("-p/--pages") }
        if !languages.isEmpty { inapplicable.append("--lang") }
        if fast { inapplicable.append("--fast") }
        if dpiGiven { inapplicable.append("--dpi") }
        if !inapplicable.isEmpty {
            throw PDFUtilError.usage("--searchable cannot be combined with \(inapplicable.joined(separator: ", ")): PDFKit's OCR-embed covers the whole document and chooses its own recognition parameters")
        }
        searchableOutput = output
    }

    let doc = try openPDF(path: path, password: common.password)

    if let output = searchableOutput {
        try ocrSearchable(doc: doc, output: output, force: common.force, inPlaceOf: path)
        return
    }

    // Clamp to a sane rasterization range (matches the plan's 72-600 bound).
    dpi = min(600, max(72, dpi))
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount) ?? Array(0..<doc.pageCount)
    let text = try ocrText(doc: doc, pages: pages, dpi: dpi, languages: languages, fast: fast)
    try writeTextOutput(text, to: common.output, force: common.force)
}
