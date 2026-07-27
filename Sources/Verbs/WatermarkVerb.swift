// Verbs/WatermarkVerb.swift - `pdfutil watermark`: stamp a text or image mark.

import Foundation

private let watermarkUsage = """
Usage: pdfutil watermark (--text STR | --image FILE) [options] <in.pdf>

Stamp a watermark onto the pages. The default burn-in mode redraws the document
with the mark drawn over (or --under) the content, honoring position, rotation,
and opacity. Because it redraws, annotations, links, outline, and form fields
are NOT carried over - use --annotation for a structure-preserving text mark.

--annotation adds an axis-aligned freeText annotation instead (text only,
interactive, structure-preserving). The annotation is drawn by PDFKit over the
page, so --rotate-mark, --under, and --image cannot apply in that mode and are
refused rather than ignored.

Options:
      --text STR          Text to stamp
      --image FILE        Image to stamp (burn-in only)
      --position POS      center, top-left, top-right, bottom-left, bottom-right
                          (default: center)
      --rotate-mark DEG   Rotate the mark (default: 45; burn-in only)
      --opacity N         Opacity 0-100 (default: 25)
      --point-size N      Text mark font size (default: 1/10 of the page
                          diagonal); text marks only
      --under             Draw beneath the page content (burn-in only)
      --annotation        Add a freeText annotation instead of burning in
  -p, --pages RANGE       Only mark these pages (default: all)
  -o, --output FILE       Output file (default: edit in place)
      --password PW       Password for an encrypted PDF
      --force             Overwrite an existing output file
  -h, --help              Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runWatermark(_ args: [String]) throws {
    var common = CommonOptions()
    var spec = WatermarkSpec()
    var rotateGiven = false      // rotateMark defaults to 45, so track the flag itself
    var scanner = ArgScanner(verb: "watermark", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(watermarkUsage); return
        case "--text": spec.text = try scanner.value(a)
        case "--image": spec.imagePath = try scanner.value(a)
        case "--position":
            let raw = try scanner.value(a)
            guard let p = WatermarkPosition(rawValue: raw) else {
                throw PDFUtilError.usage("--position must be center, top-left, top-right, bottom-left, or bottom-right")
            }
            spec.position = p
        case "--rotate-mark":
            let raw = try scanner.value(a)
            guard let d = Double(raw), d.isFinite else {
                throw PDFUtilError.usage("--rotate-mark requires a number of degrees")
            }
            spec.rotateMark = d
            rotateGiven = true
        case "--opacity":
            let raw = try scanner.value(a)
            guard let pct = Double(raw), pct.isFinite, pct >= 0, pct <= 100 else {
                throw PDFUtilError.usage("--opacity must be a number from 0 to 100")
            }
            spec.opacity = pct / 100
        case "--point-size":
            spec.pointSize = try positiveDouble(try scanner.value(a), option: "--point-size")
        case "--under": spec.under = true
        case "--annotation": spec.annotation = true
        case "-p", "--pages": common.pages = try scanner.value(a)
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
    switch (spec.text, spec.imagePath) {
    case (nil, nil): throw PDFUtilError.usage("one of --text or --image is required")
    case (.some, .some): throw PDFUtilError.usage("--text and --image are mutually exclusive")
    default: break
    }
    if spec.annotation && spec.imagePath != nil {
        throw PDFUtilError.usage("--annotation supports only --text (not --image)")
    }
    // drawImageMark scales the image to the page and never reads pointSize, so
    // an image mark took this and dropped it: --point-size 5 and 500 produced
    // byte-identical output. Only drawTextMark and watermarkAnnotation use it.
    if spec.imagePath != nil && spec.pointSize != nil {
        throw PDFUtilError.usage("--point-size sets a text mark's font size: an image mark is scaled to the page instead")
    }
    // watermarkAnnotation reads text, position, opacity and point size; it never
    // looks at rotateMark or under, so both were accepted and dropped (an
    // --annotation --under run produced byte-identical output to one without).
    if spec.annotation {
        var inapplicable: [String] = []
        if rotateGiven { inapplicable.append("--rotate-mark") }
        if spec.under { inapplicable.append("--under") }
        if !inapplicable.isEmpty {
            throw PDFUtilError.usage("--annotation cannot be combined with \(inapplicable.joined(separator: ", ")): a freeText annotation is axis-aligned and always sits above the page content")
        }
    }
    let path = scanner.positionals[0]
    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount)

    if spec.annotation {
        try watermarkAnnotation(doc: doc, output: common.output, force: common.force,
                                pages: pages, spec: spec, inPlaceOf: path)
    } else {
        try watermarkBurnIn(path: path, output: common.output, force: common.force,
                            password: common.password, pages: pages, spec: spec)
    }
}
