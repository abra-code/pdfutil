// Verbs/CropVerb.swift - `pdfutil crop`: set a page box (structure-preserving).

import Foundation

private let cropUsage = """
Usage: pdfutil crop (--rect X,Y,W,H | --margins L,B,R,T) [options] <in.pdf>

Set a page box to an absolute rectangle (--rect, in points with the origin at
the bottom-left of the media box) or by insetting the current box (--margins:
left, bottom, right, top, in points). Lossless: content is untouched, only the
box changes; annotations, links, outline, and form fields are preserved.

Options:
      --box NAME      Box to set: media, crop, art, bleed, trim (default crop)
      --rect X,Y,W,H  Absolute rectangle in points
      --margins L,B,R,T  Inset the current box by these margins
  -p, --pages RANGE   Only these pages (default: all)
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runCrop(_ args: [String]) throws {
    var common = CommonOptions()
    var boxName = "crop"
    var rectSpec: String?
    var marginsSpec: String?
    var scanner = ArgScanner(verb: "crop", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(cropUsage); return
        case "--box": boxName = try scanner.value(a)
        case "--rect": rectSpec = try scanner.value(a)
        case "--margins": marginsSpec = try scanner.value(a)
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
    guard (rectSpec == nil) != (marginsSpec == nil) else {
        throw PDFUtilError.usage("exactly one of --rect or --margins is required")
    }
    let box = try parseBox(boxName)
    let spec: CropSpec = try rectSpec.map { .rect(try parseFour($0, option: "--rect")) }
        ?? .margins(try parseFour(marginsSpec!, option: "--margins"))
    let path = scanner.positionals[0]

    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount) ?? Array(0..<doc.pageCount)
    try cropPages(doc: doc, pages: pages, box: box, spec: spec)
    try savePDF(doc, to: common.output, force: common.force, inPlaceOf: path)
}
