// Verbs/RotateVerb.swift - `pdfutil rotate`: lossless page rotation
// (structure-preserving).

import Foundation

private let rotateUsage = """
Usage: pdfutil rotate [options] <degrees> <in.pdf>

Rotate pages by 90, 180, 270, or -90 degrees, added to their current rotation.
Lossless (only the page's rotation entry changes); annotations, links, outline,
and form fields are preserved.

Options:
  -p, --pages RANGE   Only rotate these pages (default: all)
  -o, --output FILE   Output file (default: edit in place)
      --password PW   Password for an encrypted PDF
      --force         Overwrite an existing output file
  -h, --help          Show this help

Exit status: 0 success, 1 usage/argument error, 2 processing error.
"""

func runRotate(_ args: [String]) throws {
    var common = CommonOptions()
    var scanner = ArgScanner(verb: "rotate", args)

    while let a = scanner.nextToken() {
        switch a {
        case "-h", "--help": printUsage(rotateUsage); return
        case "-p", "--pages": common.pages = try scanner.value(a)
        case "-o", "--output": common.output = try scanner.value(a)
        case "--password": common.password = try scanner.value(a)
        case "--force": common.force = true
        case "--": scanner.endOptions()
        default:
            // A negative angle like -90 is a value, not an option.
            if Int(a) != nil { scanner.addRawPositional(a) } else { try scanner.addPositional(a) }
        }
    }

    guard scanner.positionals.count == 2, let degrees = Int(scanner.positionals[0]) else {
        throw PDFUtilError.usage("expected <degrees> <in.pdf>")
    }
    guard [90, 180, 270, -90].contains(degrees) else {
        throw PDFUtilError.usage("degrees must be one of 90, 180, 270, -90")
    }
    let path = scanner.positionals[1]

    let doc = try openPDF(path: path, password: common.password)
    let pages = try resolvePages(common.pages, pageCount: doc.pageCount) ?? Array(0..<doc.pageCount)
    try rotatePages(doc: doc, pages: pages, degrees: degrees)
    try savePDF(doc, to: common.output, force: common.force, inPlaceOf: path,
                password: common.password)
}
